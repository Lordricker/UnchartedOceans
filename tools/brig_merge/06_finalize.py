
import bpy, os
O = bpy.data.objects
for n in ("Hull", "MainDeck", "DeckFittings"):
    O[n]["vis_end"] = 0.0          # no hull LOD yet (see README): the full-detail meshes stay visible at any distance
for m in list(bpy.data.meshes):
    if m.users == 0: bpy.data.meshes.remove(m)
bpy.ops.wm.save_as_mainfile(filepath=os.environ["MERGE_OUT"]); print("OK finalize")
