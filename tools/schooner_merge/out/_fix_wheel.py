
import bpy, bmesh, math
from mathutils import Vector, Matrix
w = bpy.data.objects['Wheel']
k = 0.88 / 1.27                       # same size as before (0.88 m across, like the brig's)
R, rt = 0.42 * k, 0.032 * k           # rim radius, rim tube radius
bm = bmesh.new(); uvl = bm.loops.layers.uv.verify()
# rim: a proper torus (radial frame, no twisting) in the XZ plane, axle along Y
N, S = 32, 6
rings = []
for i in range(N):
    th = 2 * math.pi * i / N; n = Vector((math.cos(th), 0, math.sin(th)))
    rings.append([bm.verts.new(n * R + (n * math.cos(2 * math.pi * j / S) + Vector((0, 1, 0)) * math.sin(2 * math.pi * j / S)) * rt) for j in range(S)])
for i in range(N):
    i2 = (i + 1) % N
    for j in range(S):
        j2 = (j + 1) % S
        f = bm.faces.new((rings[i][j], rings[i2][j], rings[i2][j2], rings[i][j2])); f.material_index = 0
        for lp, (ii, jj) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
            lp[uvl].uv = (ii * 2 * math.pi * R / N, jj / S * 2 * math.pi * rt)
def cyl(p0, p1, r0, r1, seg, mi):
    p0 = Vector(p0); p1 = Vector(p1); d = p1 - p0
    vs = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r0, radius2=r1, depth=d.length)['verts']
    bmesh.ops.transform(bm, matrix=Matrix.Translation((p0 + p1) / 2) @ Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4(), verts=vs)
    for f in set(f for v in vs for f in v.link_faces): f.material_index = mi
for q in range(8):
    a = 2 * math.pi * q / 8; d = Vector((math.cos(a), 0, math.sin(a)))
    cyl(d * 0.06 * k, d * R, 0.02 * k, 0.016 * k, 6, 0)                  # spoke
    cyl(d * R, d * 0.60 * k, 0.024 * k, 0.02 * k, 6, 0)                  # handle
    vs = bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=0.03 * k)['verts']
    bmesh.ops.transform(bm, matrix=Matrix.Translation(d * 0.61 * k), verts=vs)
    for f in set(f for v in vs for f in v.link_faces): f.material_index = 0
cyl((0, -0.09 * k, 0), (0, 0.09 * k, 0), 0.075 * k, 0.075 * k, 10, 1)    # hub
cyl((0, -0.12 * k, 0), (0, 0.12 * k, 0), 0.03 * k, 0.03 * k, 8, 1)       # axle
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
# uv for everything that has none yet (spokes, handles, hub): by world direction
for f in bm.faces:
    if all(abs(l[uvl].uv[0]) < 1e-9 and abs(l[uvl].uv[1]) < 1e-9 for l in f.loops):
        n = f.normal; ax = max(range(3), key=lambda a: abs(n[a]))
        for l in f.loops:
            c = l.vert.co; l[uvl].uv = (c.y, c.x) if ax == 2 else ((c.y, c.z) if ax == 0 else (c.x, c.z))
me = bpy.data.meshes.new('Wheel'); bm.to_mesh(me); bm.free()
for m in w.data.materials: me.materials.append(m)
for p in me.polygons: p.use_smooth = False
old = w.data; w.data = me; bpy.data.meshes.remove(old)
bpy.ops.wm.save_mainfile()
print("wheel rebuilt", len(me.vertices))
