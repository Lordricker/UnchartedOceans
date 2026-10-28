
import bpy, bmesh, os, json, math
import numpy as np
from mathutils import Vector, Matrix
BASE = os.environ["BRIG_PROJECT"]; WORK = os.path.join(BASE, "tools", "brig_merge")
G = json.load(open(os.path.join(WORK, "game_groups.json"))); A = json.load(open(os.path.join(WORK, "game_assign.json")))
META = json.load(open(os.path.join(WORK, "old_meta.json")))
def depsgraph(): return bpy.context.evaluated_depsgraph_get()
def islands_of(me):
    parent = list(range(len(me.vertices)))
    def find(a):
        while parent[a] != a: parent[a] = parent[parent[a]]; a = parent[a]
        return a
    ls = np.empty(len(me.polygons), dtype=np.int32); me.polygons.foreach_get("loop_start", ls)
    lt = np.empty(len(me.polygons), dtype=np.int32); me.polygons.foreach_get("loop_total", lt)
    lv = np.empty(len(me.loops), dtype=np.int32); me.loops.foreach_get("vertex_index", lv)
    for s, t in zip(ls, lt):
        vs = lv[s:s+t]
        for a in vs[1:]: parent[find(int(a))] = find(int(vs[0]))
    order = {}
    for v in range(len(me.vertices)):
        r = find(v)
        if r not in order: order[r] = len(order)
    return find, order
class Acc:
    def __init__(self): self.verts=[]; self.faces=[]; self.uvs=[]; self.mi=[]; self.sm=[]; self.mats=[]
def add_obj(acc, obj, face_filter=None, island_ok=None):
    """Bake modifiers via new_from_object and read everything with bulk foreach_get (no per-element RNA access)."""
    ev = obj.evaluated_get(depsgraph()); me = bpy.data.meshes.new_from_object(ev); mw = np.array(obj.matrix_world)
    nv, npoly, nl = len(me.vertices), len(me.polygons), len(me.loops)
    if npoly == 0: bpy.data.meshes.remove(me); return 0
    co = np.empty(nv*3, dtype=np.float32); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    wco = (np.c_[co, np.ones(nv, dtype=np.float32)] @ mw.T)[:, :3]
    ls = np.empty(npoly, dtype=np.int32); me.polygons.foreach_get("loop_start", ls)
    lt = np.empty(npoly, dtype=np.int32); me.polygons.foreach_get("loop_total", lt)
    mi = np.empty(npoly, dtype=np.int32); me.polygons.foreach_get("material_index", mi)
    sm = np.empty(npoly, dtype=np.bool_); me.polygons.foreach_get("use_smooth", sm)
    lv = np.empty(nl, dtype=np.int32); me.loops.foreach_get("vertex_index", lv)
    a = me.attributes.get("UVMap")
    if a is None:
        ua = next((x for x in me.attributes if x.domain == 'CORNER' and x.data_type == 'FLOAT2'), None); a = ua
    uv = None
    if a is not None:
        uv = np.empty(len(a.data)*2, dtype=np.float32); a.data.foreach_get("vector", uv); uv = uv.reshape(-1, 2)
    mats = [s.material for s in obj.material_slots]   # ORIGINAL materials: the evaluated copy's slots point at temporary CoW IDs that vanish on save
    find = order = None
    if island_ok: find, order = islands_of(me)
    base = len(acc.verts); acc.verts.extend(map(tuple, wco.tolist())); n = 0
    cen = None
    for i in range(npoly):
        s, t = int(ls[i]), int(lt[i]); vs = lv[s:s+t]
        if island_ok and not island_ok(order[find(int(vs[0]))]): continue
        if face_filter is not None:
            c = wco[vs].mean(axis=0)
            if not face_filter(c): continue
        acc.faces.append(tuple(int(base + v) for v in vs))
        acc.uvs.append(uv[s:s+t].tolist() if uv is not None else None)
        m = mats[mi[i]] if mi[i] < len(mats) else None
        if m not in acc.mats: acc.mats.append(m)
        acc.mi.append(acc.mats.index(m)); acc.sm.append(bool(sm[i])); n += 1
    bpy.data.meshes.remove(me); return n
def make_mesh(acc, name, origin=(0,0,0), rot_z=0.0):
    inv = np.array(Matrix.Rotation(-rot_z, 3, 'Z')); o = np.array(origin, dtype=np.float64)
    v = (np.array(acc.verts, dtype=np.float64) - o) @ inv.T
    me = bpy.data.meshes.new(name); me.from_pydata(v.tolist(), [], acc.faces)
    for m in acc.mats: me.materials.append(m)
    mi = np.array(acc.mi, dtype=np.int32); me.polygons.foreach_set("material_index", mi)
    me.polygons.foreach_set("use_smooth", np.array(acc.sm, dtype=np.bool_))
    uvl = me.uv_layers.new(name="UVMap")
    flat = []
    for p, u in zip(me.polygons, acc.uvs):
        flat.extend(([c for uv in u for c in uv]) if u else [0.0] * (2 * p.loop_total))
    uvl.data.foreach_set("uv", np.array(flat, dtype=np.float32))
    bm = bmesh.new(); bm.from_mesh(me)
    dead = [x for x in bm.verts if not x.link_faces]
    if dead: bmesh.ops.delete(bm, geom=dead, context='VERTS')
    bm.to_mesh(me); bm.free(); me.update(); return me
def coll(name, parent=None):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    par = parent or bpy.context.scene.collection
    if c.name not in [x.name for x in par.children]: par.children.link(c)
    return c
def make_obj(name, me, loc=(0,0,0), rot_z=0.0, parent=None, props=None, col=None):
    ob = bpy.data.objects.new(name, me); ob.location = loc; ob.rotation_euler = (0, 0, rot_z)
    (col or coll("Brig_Export")).objects.link(ob)
    if parent: ob.parent = parent
    for k, v in (props or {}).items(): ob[k] = v
    return ob
def tris(me): return sum(len(p.vertices) - 2 for p in me.polygons)
