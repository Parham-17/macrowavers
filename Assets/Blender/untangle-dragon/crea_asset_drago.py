# Genera DragonBody.usdz e DragonHead.usdz dal glTF "Chinese dragon" di Sketchfab, senza aprire Blender:
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
#       -P Assets/Blender/untangle-dragon/crea_asset_drago.py -- <percorso/scene.gltf> <cartella di uscita>
#
# Esegue in ordine gli script 1–4 di questa cartella più i passaggi "a mano" della guida
# (assottigliare il corpo, nuovo scheletro spine_00…spine_63, testa con nostrils/mouth, export).
import bpy, os, sys

argomenti = sys.argv[sys.argv.index("--") + 1:]
GLTF, USCITA = argomenti[0], argomenti[1]
CARTELLA = os.path.dirname(os.path.abspath(__file__))

ASSE_Z = 0.173               # altezza della spina dopo la scala di gioco
COLLO_Y, CODA_Y = -1.225, 0.93
SPESSORE = 0.5               # sezione del corpo: raggio ~3 cm a misura di gioco
SCALA_TESTA = 0.6
OSSA_SPINA = 64              # più ossa = curve più morbide (il corpo simulato ha 48 nodi)
NARICI = (0, -0.135, 0.001)  # rispetto all'origine della testa (muso verso -Y in Blender)
BOCCA = (0, -0.125, -0.023)


def esegui(nome):
    exec(open(os.path.join(CARTELLA, nome)).read(), {"__name__": "__main__"})


def seleziona(oggetti, attivo=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in oggetti:
        o.select_set(True)
    bpy.context.view_layer.objects.active = attivo or oggetti[0]


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLTF, merge_vertices=True)
bpy.ops.object.select_all(action="DESELECT")
esegui("1_prepara_e_togli_zampe.py")
esegui("2_stacca_testa_e_pulisci.py")
corpo, testa = bpy.data.objects["DragonBody"], bpy.data.objects["DragonHead"]

# Corpo più sottile attorno alla spina (larghezza e altezza, non la lunghezza).
for v in corpo.data.vertices:
    v.co.x *= SPESSORE
    v.co.z = ASSE_Z + (v.co.z - ASSE_Z) * SPESSORE

# Scheletro: un osso dal collo alla coda, diviso in OSSA_SPINA.
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.armature_add(location=(0, 0, 0))
armatura = bpy.context.object
bpy.ops.object.mode_set(mode="EDIT")
osso = armatura.data.edit_bones[0]
osso.head, osso.tail, osso.roll = (0, COLLO_Y, ASSE_Z), (0, CODA_Y, ASSE_Z), 0
bpy.ops.armature.select_all(action="SELECT")
bpy.ops.armature.subdivide(number_cuts=OSSA_SPINA - 1)
esegui("3_rinomina_spina.py")
seleziona([corpo, armatura], attivo=armatura)
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
# Pesi sfumati su più ossa vicine: la pelle si piega in curva invece che a gomito su ogni giunto.
seleziona([corpo])
bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.5, repeat=6, expand=0.2)
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(lock_active=False)
bpy.ops.object.mode_set(mode="OBJECT")

# Testa: origine nel punto di attacco al collo, poi all'origine del file.
bpy.context.scene.cursor.location = (0, COLLO_Y, ASSE_Z)
seleziona([testa])
bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
testa.scale = (SCALA_TESTA,) * 3
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
testa.location = (0, 0, 0)
for nome, posizione in (("nostrils", NARICI), ("mouth", BOCCA)):
    vuoto = bpy.data.objects.new(nome, None)
    bpy.context.scene.collection.objects.link(vuoto)
    vuoto.location = posizione
    vuoto.parent = testa

esegui("4_materiale.py")

os.makedirs(USCITA, exist_ok=True)
for nome, oggetti in (("DragonBody", [corpo, armatura]), ("DragonHead", [testa, *testa.children])):
    seleziona(oggetti)
    bpy.ops.wm.usd_export(filepath=os.path.join(USCITA, f"{nome}.usdz"), selected_objects_only=True,
                          export_animation=False, export_armatures=True, convert_orientation=True,
                          export_global_forward_selection="NEGATIVE_Z", export_global_up_selection="Y")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(USCITA, "drago.blend"))
print(f"Asset del drago generati in {USCITA}")
