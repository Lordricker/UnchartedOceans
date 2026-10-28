
import bpy, bmesh, os, time
WORK = os.path.join(os.environ["BRIG_PROJECT"], "tools", "brig_merge")
exec(open(os.path.join(WORK, "merge_lib.py")).read(), globals())
LOG = open(os.path.join(WORK, "stage5_log.txt"), "a", encoding="utf-8")
def L(m): LOG.write(m + "\n"); LOG.flush(); os.fsync(LOG.fileno())
OUT = os.environ["MERGE_OUT"]; O = bpy.data.objects; M = bpy.data.materials
def s2l(c): return np.where(c <= 0.04045, c/12.92, ((c+0.055)/1.055)**2.4)
def l2s(c): return np.where(c <= 0.0031308, c*12.92, 1.055*np.power(np.clip(c,1e-8,None), 1/2.4)-0.055)
def mat_color(m):
    """representative linear colour: mean of the diffuse image for image materials, else the Principled base colour"""
    if m is None: return np.array([0.3, 0.3, 0.3])
    nt = m.node_tree
    for n in nt.nodes:
        if n.type == 'TEX_IMAGE' and n.label == "Diffuse" and n.image and n.image.size[0] > 0:
            px = np.empty(n.image.size[0]*n.image.size[1]*4, dtype=np.float32); n.image.pixels.foreach_get(px)
            return s2l(px.reshape(-1, 4)[::97, :3]).mean(axis=0)   # sparse sample is plenty for a mean colour
    b = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    return np.array(b.inputs["Base Color"].default_value[:3]) if b else np.array([0.3, 0.3, 0.3])
def kmeans(cols, w, k):
    cols = np.array(cols); w = np.array(w, dtype=float); k = min(k, len(cols))
    lum = cols @ np.array([0.3, 0.6, 0.1]); cen = cols[np.argsort(lum)[np.linspace(0, len(cols)-1, k).astype(int)]].copy()
    for _ in range(25):
        lab = np.argmin(((cols[:, None, :] - cen[None]) ** 2).sum(-1), axis=1)
        for j in range(k):
            sel = lab == j
            if sel.any(): cen[j] = (cols[sel] * w[sel, None]).sum(0) / max(w[sel].sum(), 1e-9)
    return lab, cen

def prune(acc, thr):
    if thr <= 0: return acc
    V = np.array(acc.verts, dtype=np.float64); n = len(V); parent = np.arange(n)
    def find(a):
        while parent[a] != a: parent[a] = parent[parent[a]]; a = parent[a]
        return a
    for f in acc.faces:
        r0 = find(f[0])
        for v in f[1:]:
            r = find(v)
            if r != r0: parent[r] = r0
    roots = np.array([find(i) for i in range(n)])
    lo = np.full((n, 3), 1e9); hi = np.full((n, 3), -1e9)
    np.minimum.at(lo, roots, V); np.maximum.at(hi, roots, V)
    diag = np.linalg.norm(hi - lo, axis=1)
    out = Acc(); out.verts = acc.verts; out.mats = acc.mats
    for f, uv, mi, sm in zip(acc.faces, acc.uvs, acc.mi, acc.sm):
        if diag[roots[f[0]]] >= thr: out.faces.append(f); out.uvs.append(uv); out.mi.append(mi); out.sm.append(sm)
    return out

def tri_of(me): return sum(len(p.vertices) - 2 for p in me.polygons)


L(f"=== stage5c start {time.strftime('%H:%M:%S')}")
SRC = {"Rig": ["Rig_Spars"]}
accs = {}
for key, names in SRC.items():
    acc = Acc()
    for n in names: add_obj(acc, O[n])
    accs[key] = acc; L(f"READ {key}: {len(acc.faces)} faces, {len(acc.mats)} materials")
SPEC = [("Rig_LOD1", "Rig", 6800, 60.0, 250.0), ("Rig_LOD2", "Rig", 3400, 250.0, 0.0)]
tmp_col = coll("__tmp"); lodmats = {}
for key, acc in accs.items():
    cols = [mat_color(m) for m in acc.mats]; cnt = np.bincount(np.array(acc.mi), minlength=len(acc.mats))
    lab, cen = kmeans(cols, cnt, 6 if key == "Hull" else 3); used = sorted(set(lab.tolist())); remap = {c: i for i, c in enumerate(used)}; mats = []
    for c in used:
        nm = f"M_LOD_{key}_{remap[c]}"
        if nm in M: M.remove(M[nm])
        mm = M.new(nm); mm.use_nodes = True; b = mm.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*l2s(np.clip(cen[c], 0, 1)).tolist(), 1.0); b.inputs["Roughness"].default_value = 0.85; mats.append(mm)
    lodmats[key] = (mats, [remap[l] for l in lab.tolist()])
jobs = []
for name, key, target, vb, ve in SPEC:
    me = make_mesh(accs[key], f"__src_{name}"); ratio = min(1.0, target / tri_of(me))
    tmp = bpy.data.objects.new(f"__dec_{name}", me); tmp_col.objects.link(tmp)
    md = tmp.modifiers.new("dec", 'DECIMATE'); md.decimate_type = 'COLLAPSE'; md.ratio = ratio; md.use_collapse_triangulate = True
    jobs.append((name, key, tmp, vb, ve)); L(f"PREP {name}: {tri_of(me)} tris -> ratio {ratio:.3f}")
dg = bpy.context.evaluated_depsgraph_get(); baked = {}
for name, key, tmp, vb, ve in jobs: baked[name] = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg)); L(f"EVAL {name}: {tri_of(baked[name])} tris")
root = O["Brig"]
for name, key, tmp, vb, ve in jobs:
    me = baked[name]; mats, mp = lodmats[key]; mi = np.empty(len(me.polygons), dtype=np.int32); me.polygons.foreach_get("material_index", mi)
    mi = np.array([mp[i] if i < len(mp) else 0 for i in mi], dtype=np.int32); me.materials.clear()
    for m in mats: me.materials.append(m)
    me.polygons.foreach_set("material_index", mi); me.name = name; me.validate(); me.update()
    make_obj(name, me, parent=root, props={"vis_begin": vb, "vis_end": ve, "game_role": "lod"}); L(f"MADE {name}: {tri_of(me)} tris")
for name, key, tmp, vb, ve in jobs: bpy.data.objects.remove(tmp)
bpy.data.collections.remove(tmp_col)
for m in list(bpy.data.meshes):
    if m.name.startswith("__"): bpy.data.meshes.remove(m)
bpy.data.orphans_purge(do_recursive=True); bpy.ops.wm.save_as_mainfile(filepath=OUT); L("SAVED " + OUT)
