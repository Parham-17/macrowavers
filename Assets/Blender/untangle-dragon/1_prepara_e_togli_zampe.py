# Passo 4 della guida. Prepara il "Chinese dragon" importato e toglie le 4 zampe:
# 1. unisce gli occhi al corpo; 2. toglie il modificatore Armature (il corpo torna dritto);
# 3. cancella le zampe (riconosciute dalle ossa originali) e chiude i 4 buchi rimasti.
# Uso: Run Script (non serve selezionare niente). Da lanciare una volta sola, subito dopo l'import.
import bpy, bmesh, math
from mathutils import Vector, geometry


def avvisa(testo):
    """Su Mac i print non si vedono: mostra il risultato anche in un riquadro sopra il mouse."""
    print(testo)
    if not bpy.app.background:
        bpy.context.window_manager.popup_menu(lambda menu, _: menu.layout.label(text=testo), title="Drago", icon="INFO")


def armatura_originale():
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE" and "drgon_025" in o.data.bones), None)
    if arm is None:
        raise RuntimeError("Armatura del modello non trovata: ricomincia da un file nuovo e reimporta il glTF.")
    return arm


def corpo_del_drago():
    """La mesh più grande con i gruppi di vertici delle ossa originali."""
    mesh = [o for o in bpy.data.objects if o.type == "MESH" and "drgon_025" in o.vertex_groups]
    if not mesh:
        raise RuntimeError("Corpo del drago non trovato: ricomincia da un file nuovo e reimporta il glTF.")
    return max(mesh, key=lambda o: len(o.data.vertices))


def vertici_delle_ossa(obj, arm, radici):
    """Vertici il cui peso maggiore è su una delle ossa indicate (o loro figlie)."""
    nomi = set()
    for radice in radici:
        osso = arm.data.bones[radice]
        nomi |= {osso.name} | {figlio.name for figlio in osso.children_recursive}
    gruppi = {obj.vertex_groups[n].index for n in nomi if n in obj.vertex_groups}
    return {v.index for v in obj.data.vertices
            if v.groups and max(v.groups, key=lambda g: g.weight).group in gruppi}


def parti_staccate(bm):
    """La mesh è fatta di tante parti separate (corpo, corna, baffi...): insiemi di indici di vertice."""
    viste, parti = set(), []
    for inizio in bm.verts:
        if inizio.index in viste:
            continue
        pila, parte = [inizio], set()
        while pila:
            v = pila.pop()
            if v.index not in parte:
                parte.add(v.index)
                pila.extend(e.other_vert(v) for e in v.link_edges)
        viste |= parte
        parti.append(parte)
    return parti


def scelta_pulita(bm, scelti):
    """Il corpo principale si taglia vertice per vertice; le parti piccole (artigli, corna) vanno intere
    dalla parte dove sta la maggioranza dei loro vertici, così non restano pezzi a metà."""
    parti = parti_staccate(bm)
    corpo = max(parti, key=len)
    risultato = scelti & corpo
    for parte in parti:
        if parte is not corpo and len(parte & scelti) * 2 > len(parte):
            risultato |= parte
    return risultato


def chiave(co):
    return tuple(round(c, 4) for c in co)


def bordo_del_taglio(bm, scelti):
    """Posizioni dei vertici sui due lati del taglio (servono a ritrovare i buchi dopo)."""
    bordo = set()
    for i in scelti:
        for e in bm.verts[i].link_edges:
            altro = e.other_vert(bm.verts[i])
            if altro.index not in scelti:
                bordo |= {chiave(altro.co), chiave(bm.verts[i].co)}
    return bordo


def chiudi_buchi(bm, bordo, mondo=None):
    """Chiude ogni buco lungo il taglio con una faccia orientata come le vicine, poi la divide in triangoli.
    Con `mondo` (matrice dell'oggetto) la toppa non è piatta ma segue la curva del corpo (vedi `toppa_curva`)."""
    rimasti = {e for e in bm.edges if e.is_boundary and all(chiave(v.co) in bordo for v in e.verts)}
    piatte, chiusi = [], 0
    while rimasti:
        anello, pila = set(), [rimasti.pop()]
        while pila:
            spigolo = pila.pop()
            anello.add(spigolo)
            for v in spigolo.verts:
                for vicino in v.link_edges:
                    if vicino in rimasti:
                        rimasti.discard(vicino)
                        pila.append(vicino)
        for faccia in bmesh.ops.contextual_create(bm, geom=list(anello))["faces"]:
            if not faccia.edges[0].is_contiguous:
                bmesh.ops.reverse_faces(bm, faces=[faccia])
            chiusi += 1
            if mondo is None:
                piatte.append(faccia)
            else:
                toppa_curva(bm, faccia, mondo)
    bmesh.ops.triangulate(bm, faces=piatte)
    return chiusi


def toppa_curva(bm, faccia, mondo, passate=20):
    """Copre il buco con una toppa che segue la rotondità del corpo invece di una faccia piatta.
    Il corpo è un tubo dritto attorno all'asse della spina (x = 0, z = ASSE_SPINA, lungo Y): il bordo del buco
    si "srotola" sul cilindro (angolo, y), si riempie di punti e si triangola in 2D, poi si riavvolge. La distanza
    dall'asse dei punti nuovi è sfumata da quella del bordo, così la toppa raccorda la pelle intorno."""
    inversa = mondo.inverted()
    bordo = list(faccia.verts)
    mondo_bordo = [mondo @ v.co for v in bordo]
    angoli = [math.atan2(p.x, p.z - ASSE_SPINA) for p in mondo_bordo]
    medio = math.atan2(sum(math.sin(a) for a in angoli), sum(math.cos(a) for a in angoli))
    raggi = [math.hypot(p.x, p.z - ASSE_SPINA) for p in mondo_bordo]
    raggio_medio = sum(raggi) / len(raggi)
    # Coordinate 2D sul cilindro srotolato, centrate sul buco (niente salto a ±180°).
    piano = [Vector((math.remainder(a - medio, 2 * math.pi) * raggio_medio, p.y))
             for a, p in zip(angoli, mondo_bordo)]
    passo = sum((piano[i] - piano[i - 1]).length for i in range(len(piano))) / len(piano)
    bmesh.ops.delete(bm, geom=[faccia], context="FACES_ONLY")

    # Punti interni su una griglia, lontani dal bordo almeno mezzo passo.
    xs, ys = [p.x for p in piano], [p.y for p in piano]
    interni = []
    x = min(xs) + passo
    while x < max(xs):
        y = min(ys) + passo
        while y < max(ys):
            q = Vector((x, y))
            if dentro(q, piano) and min(distanza_segmento(q, piano[i - 1], piano[i]) for i in range(len(piano))) > passo / 2:
                interni.append(q)
            y += passo
        x += passo
    punti = piano + interni
    uscita = geometry.delaunay_2d_cdt(punti, [], [list(range(len(piano)))], 1, 1e-6)
    coordinate, triangoli, origini = uscita[0], uscita[2], uscita[3]

    # Vertici 3D: quelli del bordo restano, gli altri si creano sul cilindro.
    verso, nuovi, raggio_di = {}, [], dict(zip(bordo, raggi))
    for i, origine in enumerate(origini):
        if origine and origine[0] < len(bordo):
            verso[i] = bordo[origine[0]]
        else:
            q = coordinate[i]
            angolo = medio + q.x / raggio_medio
            pesi = [1 / max((q - b).length, 1e-6) ** 2 for b in piano]
            r = sum(w * rb for w, rb in zip(pesi, raggi)) / sum(pesi)
            v = bm.verts.new(inversa @ Vector((r * math.sin(angolo), q.y, ASSE_SPINA + r * math.cos(angolo))))
            raggio_di[v] = r
            verso[i] = v
            nuovi.append((v, q))
    facce = []
    for t in triangoli:
        try:
            facce.append(bm.faces.new([verso[i] for i in t]))
        except ValueError:
            pass
    # Raggio sfumato: media dei vicini (il bordo resta fermo), poi riposiziona sul cilindro.
    for _ in range(passate):
        for v, _ in nuovi:
            vicini = [e.other_vert(v) for e in v.link_edges]
            raggio_di[v] = sum(raggio_di.get(n, raggio_di[v]) for n in vicini) / len(vicini)
    for v, q in nuovi:
        angolo = medio + q.x / raggio_medio
        r = raggio_di[v]
        v.co = inversa @ Vector((r * math.sin(angolo), q.y, ASSE_SPINA + r * math.cos(angolo)))
    # Stesso verso delle facce vicine: un lato del bordo deve essere percorso al contrario dalla toppa.
    if facce:
        spigolo = next((e for e in bordo[0].link_edges if bordo[1] in e.verts), None)
        if spigolo and len(spigolo.link_faces) == 2 and not spigolo.is_contiguous:
            bmesh.ops.reverse_faces(bm, faces=facce)
    # UV sfumati da quelli del bordo: la normal map delle squame continua sulla toppa.
    uv = bm.loops.layers.uv.active
    if uv:
        uv_bordo = [next((l[uv].uv.copy() for l in v.link_loops if l.face not in facce), None) for v in bordo]
        noti = [(q, u) for q, u in zip(piano, uv_bordo) if u is not None]
        posizione = {v: q for v, q in nuovi} | dict(zip(bordo, piano))
        for f in facce:
            for l in f.loops:
                q = posizione[l.vert]
                pesi = [1 / max((q - b).length, 1e-6) ** 2 for b, _ in noti]
                l[uv].uv = sum((u * w for (_, u), w in zip(noti, pesi)), Vector((0, 0))) / sum(pesi)
    for f in facce:
        f.smooth = True
    return facce


def dentro(q, poligono):
    """Punto dentro un poligono 2D (regola pari/dispari)."""
    risultato = False
    for i in range(len(poligono)):
        a, b = poligono[i - 1], poligono[i]
        if (a.y > q.y) != (b.y > q.y) and q.x < a.x + (q.y - a.y) * (b.x - a.x) / (b.y - a.y):
            risultato = not risultato
    return risultato


def distanza_segmento(q, a, b):
    ab = b - a
    t = 0 if ab.length_squared == 0 else max(0, min(1, (q - a).dot(ab) / ab.length_squared))
    return (q - (a + ab * t)).length


OSSA_ZAMPE = ["drgon_0154", "drgon_0175", "drgon_0234", "drgon_0253"]  # radici delle 4 zampe
ASSE_SPINA = 346  # altezza (unità del modello originale) dell'asse del corpo, dritto lungo Y

if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
arm = armatura_originale()
corpo = corpo_del_drago()

# 1. Occhi (e ogni altra mesh legata alla stessa armatura) dentro il corpo.
altre = [o for o in bpy.data.objects if o.type == "MESH" and o is not corpo
         and any(m.type == "ARMATURE" and m.object is arm for m in o.modifiers)]
if altre:
    bpy.ops.object.select_all(action="DESELECT")
    for o in altre + [corpo]:
        o.select_set(True)
    bpy.context.view_layer.objects.active = corpo
    bpy.ops.object.join()

# 2. Niente più animazione importata: il corpo resta nella posa di riposo, dritta.
for modificatore in [m for m in corpo.modifiers if m.type == "ARMATURE"]:
    corpo.modifiers.remove(modificatore)

# 3. Zampe.
bm = bmesh.new()
bm.from_mesh(corpo.data)
bm.verts.ensure_lookup_table()
via = scelta_pulita(bm, vertici_delle_ossa(corpo, arm, OSSA_ZAMPE))
if not via:
    raise RuntimeError("Zampe già tolte? Non trovo vertici delle zampe.")
bordo = bordo_del_taglio(bm, via)
bmesh.ops.delete(bm, geom=[bm.verts[i] for i in via], context="VERTS")
chiusi = chiudi_buchi(bm, bordo, corpo.matrix_world)
bm.to_mesh(corpo.data)
bm.free()
corpo.data.update()
avvisa(f"Fatto: occhi uniti, zampe tolte ({len(via)} vertici), buchi chiusi: {chiusi} (attesi 4).")
