# blender -b PortRegionC.blend --python prep_african.py -- <out.glb>   (African capital -> PortCapital_African.glb)
import bpy, sys, re, mathutils
out = sys.argv[-1]
root = bpy.data.objects["PortCapital"]
# 1. leftover European object-space materials -> converted (UV/image) ones
REMAP = {"M_Cap_Cobble":"M_Afr_Sand.001","M_Cap_Stone.001":"M_Cap_Stone.005","M_Cap_Stone.002":"M_Cap_Stone.005",
 "M_Cap_Stone.003":"M_Cap_Stone.005","M_Cap_WoodDark.001":"M_Cap_WoodDark.002","M_Cap_WoodPale.001":"M_Cap_WoodPale.002",
 "M_PortA_Brick.001":"M_Afr_Plaster.001","M_PortA_Pantile.001":"M_PortA_Pantile.002","M_PortA_Plaster":"M_Afr_Plaster.001"}
kids = list(root.children_recursive)
import bmesh
for o in kids:
    if o.type != 'MESH': continue
    hit = False
    for s in o.material_slots:
        if s.material and s.material.name in REMAP:
            s.material = bpy.data.materials[REMAP[s.material.name]]; hit = True
    if hit and not o.data.uv_layers:
        bm = bmesh.new(); bm.from_mesh(o.data); uv = bm.loops.layers.uv.new("UVMap")
        for f in bm.faces:
            n = f.normal; ax = max(range(3), key=lambda i: abs(n[i]))
            for l in f.loops:
                p = l.vert.co; a, b = [(1,2),(0,2),(0,1)][ax]
                l[uv].uv = (p[a], p[b])
        bm.to_mesh(o.data); bm.free()
# 2. trees -> vegetation empties
mapping = {"Baobab": ["Tree_Baobab_A","Tree_Baobab_B"], "Mango": ["Tree_Mango_A"], "Palm": ["Tree_Palm_A","Tree_Palm_B","Tree_Palm_C"]}
idx = {}
coll = bpy.data.collections["PortCapital"]
for o in list(bpy.data.collections["Trees_Africa"].objects):
    m = re.match(r"Cap_Tree_(Baobab|Mango|Palm)", o.name)
    if not m or o.type != 'MESH': continue
    k = m.group(1); i = idx.get(k, 0); idx[k] = i + 1
    name = mapping[k][i % len(mapping[k])]
    e = bpy.data.objects.new(o.name + "_VEG", None)
    e.empty_display_type = 'PLAIN_AXES'; e.empty_display_size = 0.6
    coll.objects.link(e)
    mw = o.matrix_world.copy()
    e.parent = o.parent; e.matrix_world = mw
    e["vegetation"] = name; e["scene"] = f"res://assets/vegetation/{name}.glb"
    e["vis_begin"] = 0.0; e["vis_end"] = 260.0 if k == "Baobab" else 160.0
    bpy.data.objects.remove(o, do_unlink=True)
# 3. root to the origin, children keep their world positions (the capital is already laid out around world x=0)
saved = [(c, c.matrix_world.copy()) for c in root.children]
root.location = (0, 0, 0)
bpy.context.view_layer.update()
for c, mw in saved:
    c.matrix_world = mw
root.name = "PortCapital_African"
bpy.context.view_layer.update()
sel = [root] + list(root.children_recursive)
bpy.ops.object.select_all(action='DESELECT')
for o in sel:
    if o.type in ('MESH','EMPTY'): o.select_set(True)
bpy.context.view_layer.objects.active = root
print("EXPORT objects", len(sel))
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_extras=True, export_yup=True,
    export_apply=False, export_lights=False, export_materials='EXPORT', export_cameras=False)
print("EXPORTED", out)
