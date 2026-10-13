# Passo 5 della guida. Stacca la testa e mette in ordine la scena:
# 1. testa (corna, baffi, criniera, occhi) in un oggetto "DragonHead", il resto diventa "DragonBody";
# 2. chiude il collo da entrambe le parti;
# 3. cancella armatura e oggetti vuoti dell'import, toglie i vecchi gruppi di vertici;
# 4. porta il drago a misura di gioco (scala 0.0005: circa 2,3 m) e applica la scala.
# Uso: Run Script (non serve selezionare niente), dopo lo script 1.
import bpy, bmesh


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


def chiudi_buchi(bm, bordo):
    """Chiude ogni buco lungo il taglio con una faccia orientata come le vicine, poi la divide in triangoli."""
    rimasti = {e for e in bm.edges if e.is_boundary and all(chiave(v.co) in bordo for v in e.verts)}
    nuove = []
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
            nuove.append(faccia)
    bmesh.ops.triangulate(bm, faces=nuove)
    return len(nuove)


OSSO_TESTA = "drgon_025"
SCALA = 0.0005

if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
arm = armatura_originale()
corpo = corpo_del_drago()
if any(m.type == "ARMATURE" for m in corpo.modifiers):
    raise RuntimeError("Lancia prima lo script 1_prepara_e_togli_zampe.py.")

# 1. Seleziona la testa e separala (come Edit Mode → P → Selection).
bm = bmesh.new()
bm.from_mesh(corpo.data)
bm.verts.ensure_lookup_table()
testa = scelta_pulita(bm, vertici_delle_ossa(corpo, arm, [OSSO_TESTA]))
bordo = bordo_del_taglio(bm, testa)
for elemento in (*bm.faces, *bm.edges):
    elemento.select = False
for v in bm.verts:
    v.select = v.index in testa
bm.select_flush(True)
bm.to_mesh(corpo.data)
bm.free()

bpy.ops.object.select_all(action="DESELECT")
corpo.select_set(True)
bpy.context.view_layer.objects.active = corpo
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.separate(type="SELECTED")
bpy.ops.object.mode_set(mode="OBJECT")
nuova = next(o for o in bpy.context.selected_objects if o is not corpo)
nuova.name = nuova.data.name = "DragonHead"
corpo.name = corpo.data.name = "DragonBody"

# 2. Collo chiuso su entrambi i pezzi.
chiusi = []
for obj in (corpo, nuova):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    chiusi.append(chiudi_buchi(bm, bordo))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()

# 3. Pulizia: restano solo DragonBody e DragonHead, senza genitori né vecchi gruppi di vertici.
for obj in (corpo, nuova):
    mondo = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = mondo
    obj.vertex_groups.clear()
for obj in list(bpy.data.objects):
    if obj not in (corpo, nuova):
        bpy.data.objects.remove(obj, do_unlink=True)

# 4. Misura di gioco, scala applicata.
bpy.ops.object.select_all(action="DESELECT")
for obj in (corpo, nuova):
    obj.scale = [s * SCALA for s in obj.scale]
    obj.select_set(True)
bpy.context.view_layer.objects.active = corpo
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.select_all(action="DESELECT")
avvisa(f"Fatto: testa staccata, collo chiuso (corpo {chiusi[0]}, testa {chiusi[1]}; attesi 1 e 1), scena pulita, scala applicata.")
