"""00_materials.py  -  Master.blend -> export-clean materials (no tint nodes, no procedurals).
Input: MerchantBrigShipMaster.blend (opened by run_all).  Output: MERGE_OUT .blend.
 * every PH_* (Poly Haven) material -> M_Brig_* : pre-tinted diffuse JPG (textures/polyhaven/export), roughness + normal maps, plain Principled
 * ropes -> flat colours, tar/parchment/burlap -> flat, table top -> dark wood (+UVs), book covers -> Color Attribute node
 * flags -> generated textures (red field + cream ring / plain red); sails + flags get Base Color = image x Color Attribute 'PinWeights'
   (the glTF exporter in Blender 4.1 only writes COLOR_0 when the material multiplies by a vertex colour)"""
import bpy, os, numpy as np
from mathutils import Vector
PROJ = os.environ["BRIG_PROJECT"]; OUT = os.environ["MERGE_OUT"]
out_dir = os.path.join(PROJ, "textures", "polyhaven", "export"); os.makedirs(out_dir, exist_ok=True)
M = bpy.data.materials
def s2l(c): return np.where(c <= 0.04045, c/12.92, ((c+0.055)/1.055)**2.4)
def l2s(c): return np.where(c <= 0.0031308, c*12.92, 1.055*np.power(np.clip(c, 1e-8, None), 1/2.4)-0.055)
def node(m, label): return next((n for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.label == label), None)
made = {}
for ph in sorted(m.name for m in M if m.name.startswith("PH_") and m.users > 0):
    m = M[ph]; d, r, nr = node(m, "Diffuse"), node(m, "Roughness"), node(m, "Normal")
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    tn = m.node_tree.nodes.get("Tint"); tint = np.array(tn.inputs[7].default_value[:3] if tn else (1, 1, 1), dtype=np.float32)
    src = d.image; w, h = src.size; px = np.empty(w*h*4, dtype=np.float32); src.pixels.foreach_get(px); px = px.reshape(h, w, 4)
    px[..., :3] = l2s(np.clip(s2l(px[..., :3]) * tint, 0, 1)); px[..., 3] = 1.0
    exn = "EX_" + ph.replace("PH_", "")
    if exn in bpy.data.images: bpy.data.images.remove(bpy.data.images[exn])
    im = bpy.data.images.new(exn, w, h, alpha=False); im.pixels.foreach_set(px.ravel()); im.update()
    im.filepath_raw = os.path.join(out_dir, exn + "_diff.jpg"); im.file_format = 'JPEG'; im.save()
    im.colorspace_settings.name = "sRGB"; im.filepath = "//textures/polyhaven/export/" + exn + "_diff.jpg"
    cn = "M_Brig_" + ph.replace("PH_", "")
    if cn in M: M.remove(M[cn])
    cm = M.new(cn); cm.use_nodes = True; nt = cm.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); b = nt.nodes.new("ShaderNodeBsdfPrincipled"); nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
    ti = nt.nodes.new("ShaderNodeTexImage"); ti.image = im; ti.label = "Diffuse"; nt.links.new(ti.outputs["Color"], b.inputs["Base Color"])
    if bsdf.inputs["Roughness"].is_linked and r:
        tr = nt.nodes.new("ShaderNodeTexImage"); tr.image = r.image; tr.label = "Roughness"; nt.links.new(tr.outputs["Color"], b.inputs["Roughness"])
    else: b.inputs["Roughness"].default_value = bsdf.inputs["Roughness"].default_value
    for k in ("Specular IOR Level", "Specular"):
        if k in b.inputs: b.inputs[k].default_value = bsdf.inputs[k].default_value; break
    b.inputs["Metallic"].default_value = bsdf.inputs["Metallic"].default_value
    if nr:
        tn2 = nt.nodes.new("ShaderNodeTexImage"); tn2.image = nr.image; tn2.label = "Normal"; nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tn2.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    made[ph] = cn
def flat(name, rgb, rough=0.9):
    if name in M: M.remove(M[name])
    m = M.new(name); m.use_nodes = True; b = m.node_tree.nodes["Principled BSDF"]; b.inputs["Base Color"].default_value = (*rgb, 1); b.inputs["Roughness"].default_value = rough; return m
rep = {**{k: M[v] for k, v in made.items()},
       "BR_RopeHemp": flat("M_Rope_Hemp", (0.26, 0.18, 0.09), 0.95), "BR_RopeTar": flat("M_Rope_Tar", (0.02, 0.01, 0.01), 0.95), "BR_Boltrope": flat("M_Rope_Boltrope", (0.38, 0.34, 0.26), 0.95),
       "BR_Tar": flat("M_Brig_Tar", (0.025, 0.02, 0.015), 0.75), "BR_Parchment": flat("M_Brig_Parchment", (0.49, 0.37, 0.20), 0.95), "BR_Burlap": flat("M_Brig_Burlap", (0.45, 0.36, 0.22), 0.95),
       "BR_TableTopWood": M[made["PH_DarkWood"]]}
rep["BR_Tar_Flat"] = rep["BR_Tar"]
for o in bpy.data.objects:
    if o.type != 'MESH': continue
    for s in o.material_slots:
        if s.material and s.material.name in rep: s.material = rep[s.material.name]
tt = bpy.data.objects["TableTop"]; me = tt.data                       # TableTop had no UVs (procedural material)
if not me.uv_layers:
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        n = Vector(poly.normal); pts = [tt.matrix_world @ me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        g = max(((pts[(i+1) % len(pts)] - pts[i]) for i in range(len(pts))), key=lambda e: e.length); t1 = g - n*g.dot(n)
        if t1.length < 1e-5: t1 = Vector((0, 1, 0)) - n*n.y
        t1.normalize(); t2 = n.cross(t1)
        for li, p in zip(poly.loop_indices, pts): uvl.data[li].uv = (p.dot(t1)/2.0, p.dot(t2)/2.0)
bk = M.get("BK_Cover")
if bk:
    nt = bk.node_tree; b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    for n in [n for n in nt.nodes if n.type == 'ATTRIBUTE']: nt.nodes.remove(n)
    vc = nt.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "Col"; nt.links.new(vc.outputs["Color"], b.inputs["Base Color"])
# ---- flags: generated textures (the procedural ones cannot be exported; this Blender has no Cycles bake) ----
RED, CREAM = np.array((0.22, 0.05, 0.04)), np.array((0.62, 0.56, 0.43))
def save_png(name, arr):
    h, w = arr.shape[:2]; px = np.ones((h, w, 4), dtype=np.float32); px[..., :3] = arr
    if name in bpy.data.images: bpy.data.images.remove(bpy.data.images[name])
    im = bpy.data.images.new(name, w, h, alpha=False); im.pixels.foreach_set(px.ravel()); im.update()
    im.filepath_raw = os.path.join(out_dir, name + "_diff.png"); im.file_format = 'PNG'; im.save()
    im.colorspace_settings.name = "sRGB"; im.filepath = "//textures/polyhaven/export/" + name + "_diff.png"; return im
fl = bpy.data.objects["Flag"].data; uv = fl.uv_layers["UVMap"].data; us = np.array([uv[li].uv[0] for p in fl.polygons for li in p.loop_indices])
ys = np.array([(bpy.data.objects["Flag"].matrix_world @ fl.vertices[fl.loops[li].vertex_index].co).y for p in fl.polygons for li in p.loop_indices])
u_is_length = abs(np.corrcoef(us, ys)[0, 1]) > 0.5
W, H = (512, 366) if u_is_length else (366, 512)                      # flag proportions 1.6 x 1.14 so the ring stays round
yy, xx = np.mgrid[0:H, 0:W]; r = np.hypot(xx - W/2, yy - H/2) / min(W, H); ring = ((r > 0.165) & (r < 0.22)).astype(np.float32)[..., None]
rng = np.random.default_rng(7); cloth = 0.93 + 0.07*rng.random((H, W, 1))
ens = save_png("EX_Flag", l2s(np.clip((RED*(1-ring) + CREAM*ring) * cloth, 0, 1)))
pen = save_png("EX_Pennant", l2s(np.clip(np.ones((64, 256, 3)) * RED * (0.93 + 0.07*rng.random((64, 256, 1))), 0, 1)))
for name, im in (("Flag", ens), ("Pennant", pen)):
    if "M_Brig_" + name in M: M.remove(M["M_Brig_" + name])
    m = M.new("M_Brig_" + name); m.use_nodes = True; nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    ti = nt.nodes.new("ShaderNodeTexImage"); ti.image = im; nt.links.new(ti.outputs["Color"], b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.9
    for s in bpy.data.objects[name].material_slots: s.material = m
for n in ("BR_FlagEnsign", "BR_FlagPennant"): M[n].use_fake_user = False
# ---- sails + flags: Base Color = image x Color Attribute 'PinWeights' so the exporter writes COLOR_0 ----
for name in ("M_Brig_Sail", "M_Brig_Flag", "M_Brig_Pennant"):
    nt = M[name].node_tree; b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'); img = b.inputs["Base Color"].links[0].from_node
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'; mix.inputs[0].default_value = 1.0; mix.label = "x PinWeights (exported as COLOR_0)"
    vc = nt.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "PinWeights"
    nt.links.new(img.outputs["Color"], mix.inputs[6]); nt.links.new(vc.outputs["Color"], mix.inputs[7]); nt.links.new(mix.outputs[2], b.inputs["Base Color"])
bpy.data.orphans_purge(do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT); print("OK materials ->", OUT)
