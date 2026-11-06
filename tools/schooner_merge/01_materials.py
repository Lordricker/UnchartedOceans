"""01_materials.py  -  SchoonerShip.blend -> export-clean materials (same method as tools/brig_merge/00_materials.py).
Every PH_* (Poly Haven) material -> M_Schooner_*: the pre-tinted diffuse JPG already in textures/polyhaven/export (EX_*; the brig's own, same tints),
roughness + normal maps kept, plain Principled. Procedural ropes / tar / parchment -> flat colours. The sail material is multiplied by the
Color Attribute 'PinWeights' so the glTF exporter (Blender 4.1) writes COLOR_0. Never modifies the source: saves MERGE_OUT."""
import bpy, os, numpy as np
PROJ = os.environ["SCHOONER_PROJECT"]; OUT = os.environ["MERGE_OUT"]
ex_dir = os.path.join(PROJ, "textures", "polyhaven", "export"); os.makedirs(ex_dir, exist_ok=True)
M = bpy.data.materials
def s2l(c): return np.where(c <= 0.04045, c/12.92, ((c+0.055)/1.055)**2.4)
def l2s(c): return np.where(c <= 0.0031308, c*12.92, 1.055*np.power(np.clip(c, 1e-8, None), 1/2.4)-0.055)
def node(m, label): return next((n for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.label == label), None)
made = {}
for ph in sorted(m.name for m in M if m.name.startswith("PH_") and m.users > 0):
    m = M[ph]; d, r, nr = node(m, "Diffuse"), node(m, "Roughness"), node(m, "Normal")
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    exn = "EX_" + ph[3:]; path = os.path.join(ex_dir, exn + "_diff.jpg")
    if os.path.exists(path):                                   # already tinted for the brig: reuse the very same file
        im = bpy.data.images.load(path, check_existing=True); im.colorspace_settings.name = "sRGB"; print("reuse", exn)
    elif d is None or d.image is None:                          # no diffuse image (a flat-colour material): keep its base colour
        flatc = bsdf.inputs["Base Color"].default_value[:3]
        cm = M.new("M_Schooner_" + ph[3:]) if ("M_Schooner_" + ph[3:]) not in M else M["M_Schooner_" + ph[3:]]
        cm.use_nodes = True; bb = cm.node_tree.nodes["Principled BSDF"]; bb.inputs["Base Color"].default_value = (*flatc, 1.0)
        bb.inputs["Roughness"].default_value = bsdf.inputs["Roughness"].default_value; made[ph] = cm.name; print("flat", ph); continue
    else:
        tn = m.node_tree.nodes.get("Tint"); tint = np.array(tn.inputs[7].default_value[:3] if tn else (1, 1, 1), dtype=np.float32)
        src = d.image; w, h = src.size; px = np.empty(w*h*4, dtype=np.float32); src.pixels.foreach_get(px); px = px.reshape(h, w, 4)
        px[..., :3] = l2s(np.clip(s2l(px[..., :3]) * tint, 0, 1)); px[..., 3] = 1.0
        im = bpy.data.images.new(exn, w, h, alpha=False); im.pixels.foreach_set(px.ravel()); im.update()
        im.filepath_raw = path; im.file_format = 'JPEG'; im.save(); im.colorspace_settings.name = "sRGB"; print("baked", exn)
    cn = "M_Schooner_" + ph[3:]
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
       "BR_RopeHemp": flat("M_Rope_Hemp", (0.26, 0.18, 0.09), 0.95), "BR_RopeTar": flat("M_Rope_Tar", (0.02, 0.01, 0.01), 0.95),
       "BR_Tar_Flat": flat("M_Schooner_Tar", (0.025, 0.02, 0.015), 0.75), "BR_Parchment": flat("M_Schooner_Parchment", (0.49, 0.37, 0.20), 0.95)}
for o in bpy.data.objects:
    if o.type != 'MESH': continue
    for s in o.material_slots:
        if s.material and s.material.name in rep: s.material = rep[s.material.name]
# sails: Base Color = image x Color Attribute 'PinWeights' (so the exporter writes COLOR_0)
nt = M["M_Schooner_Sail"].node_tree; b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'); img = b.inputs["Base Color"].links[0].from_node
mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'; mix.inputs[0].default_value = 1.0; mix.label = "x PinWeights (exported as COLOR_0)"
vc = nt.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "PinWeights"
nt.links.new(img.outputs["Color"], mix.inputs[6]); nt.links.new(vc.outputs["Color"], mix.inputs[7]); nt.links.new(mix.outputs[2], b.inputs["Base Color"])
bpy.data.orphans_purge(do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT); print("OK materials ->", OUT)
