# usage: blender -b <Region>.blend --python export_capital.py -- <RootName> <out.glb>
import bpy, sys, json
root_name, out = sys.argv[-2], sys.argv[-1]
root = bpy.data.objects[root_name]
print("root loc", tuple(root.location), "rot", tuple(root.rotation_euler))
sel = [root] + list(root.children_recursive)
bad = [o.name for o in sel if o.type not in ('MESH','EMPTY')]
print("objects", len(sel), "non mesh/empty:", bad[:10])
# materials without image/flat? report object-space texcoord usage
issues = set()
for o in sel:
    if o.type != 'MESH': continue
    for s in o.material_slots:
        m = s.material
        if not m or not m.use_nodes: continue
        for n in m.node_tree.nodes:
            if n.type == 'TEX_COORD' and any(l.from_socket.name in ('Object','Generated') for out_ in n.outputs for l in out_.links):
                issues.add(m.name)
print("objspace materials:", sorted(issues)[:20], len(issues))
bpy.ops.object.select_all(action='DESELECT')
for o in sel: o.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_extras=True,
    export_yup=True, export_apply=False, export_lights=False, export_materials='EXPORT', export_cameras=False)
print("EXPORTED", out)
