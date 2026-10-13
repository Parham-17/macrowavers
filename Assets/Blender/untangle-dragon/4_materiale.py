# Passo 11 della guida: materiale del corpo rosso pieno, illuminato dalla stanza, senza luce propria.
# La texture "emissiva" di questo modello non è il colore del drago (è chiara e verdastra):
# esportata così farebbe brillare il drago di bianco. Restano normal map (squame) e vernice lucida.
# Uso: con qualsiasi oggetto selezionato, Run Script.
import bpy

def avvisa(testo):
    """Su Mac i print non si vedono: mostra il risultato anche in un riquadro sopra il mouse."""
    print(testo)
    if not bpy.app.background:
        bpy.context.window_manager.popup_menu(lambda menu, _: menu.layout.label(text=testo), title="Drago", icon='INFO')


ROSSO = (0.45, 0.02, 0.03, 1.0)  # valori lineari; si può cambiare dopo in Material Properties → Base Color

mat = bpy.data.materials["MI_b09_00_drg_hair"]
bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
for presa in ("Emission Color", "Base Color"):
    for link in list(bsdf.inputs[presa].links):
        mat.node_tree.links.remove(link)
bsdf.inputs["Emission Strength"].default_value = 0.0
bsdf.inputs["Base Color"].default_value = ROSSO
avvisa("Materiale del corpo aggiornato.")
