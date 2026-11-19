
import bpy, bmesh, math
from mathutils import Vector, Matrix
col = bpy.data.collections['Schooner']
CX, CY, ZD = 1.45, -0.6, 1.15
bm = bmesh.new()
def cyl(z0, z1, r0, r1, mi, seg=12):
    vs = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r0, radius2=r1, depth=z1 - z0)['verts']
    bmesh.ops.transform(bm, matrix=Matrix.Translation((CX, CY, (z0 + z1) / 2)), verts=vs)
    for f in set(f for v in vs for f in v.link_faces): f.material_index = mi
cyl(ZD, ZD + 0.12, 0.27, 0.26, 0)            # foot
cyl(ZD + 0.12, ZD + 0.16, 0.24, 0.24, 1)     # iron pawl ring
cyl(ZD + 0.16, ZD + 0.50, 0.20, 0.17, 0)     # barrel, flared at the foot
cyl(ZD + 0.50, ZD + 1.00, 0.17, 0.21, 0)     # barrel, flared to the head
cyl(ZD + 1.00, ZD + 1.03, 0.235, 0.235, 1)   # iron hoop under the head
cyl(ZD + 1.03, ZD + 1.15, 0.27, 0.27, 0)     # head
cyl(ZD + 1.15, ZD + 1.17, 0.12, 0.12, 1)     # iron cap
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
uvl = bm.loops.layers.uv.verify()
for f in bm.faces:
    n = f.normal; ax = max(range(3), key=lambda a: abs(n[a]))
    for l in f.loops:
        c = l.vert.co; l[uvl].uv = (c.z, c.x) if ax != 0 else (c.z, c.y)
        if ax == 2: l[uvl].uv = (c.y, c.x)
me = bpy.data.meshes.new('Capstan'); bm.to_mesh(me); bm.free()
me.materials.append(bpy.data.materials['PH_Walnut']); me.materials.append(bpy.data.materials['PH_Iron'])
for p in me.polygons: p.use_smooth = False
o = bpy.data.objects.get('Capstan')
if o: bpy.data.objects.remove(o, do_unlink=True)
o = bpy.data.objects.new('Capstan', me); col.objects.link(o)
bpy.ops.wm.save_mainfile()
print("capstan added")
