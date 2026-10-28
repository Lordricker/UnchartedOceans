
import bpy, bmesh, os
from mathutils import Vector
WORK = os.path.join(os.environ["BRIG_PROJECT"], "tools", "brig_merge"); BASE = os.environ["BRIG_PROJECT"]
exec(open(os.path.join(WORK, "merge_lib.py")).read(), globals())
LOG = open(os.path.join(WORK, "stage7_log.txt"), "a", encoding="utf-8")
def L(m): LOG.write(m + "\n"); LOG.flush(); os.fsync(LOG.fileno())
O = bpy.data.objects; exp = bpy.data.collections["Brig_Export"]; root = O["Brig"]
# boxes for the new things (world-space bounding boxes of the source objects), read BEFORE the scene changes
def wbox(o):
    ws = [o.matrix_world @ Vector(c) for c in o.bound_box]; return Vector((min(w.x for w in ws), min(w.y for w in ws), min(w.z for w in ws))), Vector((max(w.x for w in ws), max(w.y for w in ws), max(w.z for w in ws)))
want = ["Bunk_Port", "Bunk_Stbd", "GalleyBarrel", "Pump_Body"] + [n for n in O.keys() if n in ("CabinBookshelf_Frame", "Bookshelf_Frame", "BookshelfFrame", "Shelf_Frame") ]
boxes = {}
for n in want:
    if n in O: boxes[n] = wbox(O[n]); L(f"BOX {n}: {tuple(round(x,2) for x in boxes[n][0])} .. {tuple(round(x,2) for x in boxes[n][1])}")
    else: L(f"MISSING {n}")
sh = [n for n in O.keys() if "shelf" in n.lower() and not n.startswith(("Book_", "Src_")) and n not in boxes]
L(f"other shelf-like objects: {sh}")
# append the six old collision meshes
with bpy.data.libraries.load(os.path.join(WORK, "source", "MerchantBrigShipGame_source.blend"), link=False) as (df, dt): dt.objects = [n for n in df.objects if n.startswith("Col_")]
col_objs = [o for o in dt.objects if o is not None]
for o in col_objs:
    exp.objects.link(o); o.parent = root; o.matrix_parent_inverse = o.matrix_parent_inverse.Identity(4)
    if "cycles" in o.keys(): del o["cycles"]
    L(f"APPENDED {o.name}: {len(o.data.vertices)} verts")
ob = next(o for o in col_objs if o.name.startswith("Col_Obstacles"))
bm = bmesh.new(); bm.from_mesh(ob.data)
# drop the old centre-line pump boxes (the pump is now a starboard brake pump)
dead = [v for v in bm.verts if abs(v.co.x) < 0.7 and 2.9 < v.co.y < 4.3 and v.co.z < 3.2]
bmesh.ops.delete(bm, geom=dead, context='VERTS'); L(f"removed {len(dead)} verts of the old centre pump boxes")
for n, (lo, hi) in boxes.items():
    c = (lo + hi) / 2; s = hi - lo
    r = bmesh.ops.create_cube(bm, size=1.0)
    for v in r["verts"]: v.co = (v.co.x * s.x + c.x, v.co.y * s.y + c.y, v.co.z * s.z + c.z)
    L(f"ADDED box {n}: centre {tuple(round(x,2) for x in c)} size {tuple(round(x,2) for x in s)}")
bm.to_mesh(ob.data); bm.free(); ob.data.update()
# ---- gentle ramps (walkable collision) at the two places the player used to catch: the cabin door and the foot of the
# poop stairs. The old collision (from the frozen source) only has short steep ramps there and is narrower than the doorway.
# Each ramp starts flush with the main deck (z = 1.688 + 0.131 * (y - 3.85)) and rises to the floor beyond; the old surfaces
# lie under or at the end of them, so the player simply walks up the higher, gentler surface.
def deck_z(y): return 1.688 + 0.131 * (y - 3.85)
ramps = [("cabin door", -1.96, -0.94, 4.4, 5.25, 2.16), ("poop stair foot", 1.86, 2.80, 4.15, 5.33, 2.285)]
rbm = bmesh.new()
for nm, xa, xb, y0, y1, z1 in ramps:
    zb = 1.4; z0 = deck_z(y0)
    pv = {}
    for xi, x in (("a", xa), ("b", xb)):
        pv[xi] = [rbm.verts.new((x, y0, zb)), rbm.verts.new((x, y0, z0)), rbm.verts.new((x, y1, z1)), rbm.verts.new((x, y1, zb))]
    a, b = pv["a"], pv["b"]
    rbm.faces.new((a[0], a[1], a[2], a[3])); rbm.faces.new((b[3], b[2], b[1], b[0]))        # the two sides
    rbm.faces.new((a[1], b[1], b[2], a[2]))                                                  # the slope
    rbm.faces.new((a[0], b[0], b[1], a[1])); rbm.faces.new((a[2], b[2], b[3], a[3]))        # front and back
    rbm.faces.new((a[3], b[3], b[0], a[0]))                                                  # underside
    L(f"RAMP {nm}: x {xa}..{xb}  y {y0}..{y1}  z {z0:.3f} -> {z1}")
bmesh.ops.recalc_face_normals(rbm, faces=rbm.faces[:])
rme = bpy.data.meshes.new("Col_Ramps-colonly"); rbm.to_mesh(rme); rbm.free()
rob = bpy.data.objects.new("Col_Ramps-colonly", rme); exp.objects.link(rob)
rob.parent = root; rob.matrix_parent_inverse = rob.matrix_parent_inverse.Identity(4)
for o in list(bpy.data.objects):
    if o.name.startswith("Brig") and o.name != "Brig" and o.type == 'EMPTY': bpy.data.objects.remove(o)
bpy.data.orphans_purge(do_recursive=True); bpy.ops.wm.save_as_mainfile(filepath=os.environ["MERGE_OUT"]); L("SAVED"); L(f"Col_Obstacles now {len(ob.data.vertices)} verts")
