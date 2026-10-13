# Passo 9 della guida: rinomina la catena di ossa spine_00 (collo) ... spine_63 (punta della coda).
# Uso: Run Script (non serve selezionare niente), con la nuova armatura già suddivisa in 64 ossa.
import bpy

def avvisa(testo):
    """Su Mac i print non si vedono: mostra il risultato anche in un riquadro sopra il mouse."""
    print(testo)
    if not bpy.app.background:
        bpy.context.window_manager.popup_menu(lambda menu, _: menu.layout.label(text=testo), title="Drago", icon='INFO')


armature = [o for o in bpy.data.objects if o.type == 'ARMATURE']
if len(armature) != 1:
    raise RuntimeError(f"Mi aspetto una sola armatura nella scena, ne trovo {len(armature)}.")
arm = armature[0]
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
ossa = arm.data.edit_bones
catena = [next(b for b in ossa if b.parent is None)]
while catena[-1].children:
    catena.append(catena[-1].children[0])
for indice, osso in enumerate(catena):
    osso.name = f"spine_{indice:02d}"
bpy.ops.object.mode_set(mode='OBJECT')
avvisa(f"Rinominate {len(catena)} ossa: spine_00 ... spine_{len(catena) - 1:02d} (attese 64).")
