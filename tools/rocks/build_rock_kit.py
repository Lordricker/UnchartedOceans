"""Builds the coastal rock kit for Uncharted Oceans from Poly Haven (CC0) scans.

Run in a separate background Blender so no open .blend is touched:
    blender -b --factory-startup --python build_rock_kit.py -- <out_dir> <tmp_dir>

For each rock: download the 1K glTF, join to one mesh, decimate (collapse) to a game triangle count, put the origin at the
bottom centre of the rock (so the game can sink it to the waterline), and export a GLB with the 1K textures embedded.
Writes <out_dir>/rock_kit.json (tris, size in metres, source id) and prints a log.
"""
import bpy, sys, os, json, time, urllib.request
from mathutils import Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, TMP = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
os.makedirs(TMP, exist_ok=True)

# (Poly Haven id, game name, target triangles)
KIT = [
    ("namaqualand_boulder_06", "Rock_Boulder_S", 1500),
    ("coast_rocks_05", "Rock_Reef_S", 3000),
    ("namaqualand_boulder_04", "Rock_Boulder_M", 2500),
    ("namaqualand_boulder_03", "Rock_Boulder_L", 3000),
    ("sand_rocks_small_01", "Rock_Shingle_M", 3500),
    ("coast_rocks_03", "Rock_Shelf_XL", 8000),
    ("coastal_cliff_04", "Rock_Headland_XL", 10000),
]
UA = {"User-Agent": "Mozilla/5.0 (UnchartedOceans rock kit)"}


def fetch(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180) as r, open(dest, "wb") as f:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            f.write(b)


def download(pid):
    files = json.load(urllib.request.urlopen(urllib.request.Request(f"https://api.polyhaven.com/files/{pid}", headers=UA), timeout=60))
    g = files["gltf"]["1k"]["gltf"]
    d = os.path.join(TMP, pid)
    main = os.path.join(d, os.path.basename(g["url"]))
    fetch(g["url"], main)
    for rel, inc in g.get("include", {}).items():
        fetch(inc["url"], os.path.join(d, rel))
    return main


def tri_count(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


results = []
for pid, name, target in KIT:
    t0 = time.time()
    try:
        path = download(pid)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=path)
        meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        bpy.ops.object.select_all(action="DESELECT")
        for o in bpy.context.scene.objects:
            o.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
        bpy.ops.object.select_all(action="DESELECT")
        for o in meshes:
            o.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        if len(meshes) > 1:
            bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
        for o in list(bpy.context.scene.objects):
            if o is not obj:
                bpy.data.objects.remove(o, do_unlink=True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        before = tri_count(obj.data)
        mod = obj.modifiers.new("Dec", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = min(1.0, target / max(before, 1))
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="Dec")
        me = obj.data
        xs = [v.co.x for v in me.vertices]
        ys = [v.co.y for v in me.vertices]
        zs = [v.co.z for v in me.vertices]
        cx, cy, mz = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)
        me.transform(Matrix.Translation((-cx, -cy, -mz)))
        obj.location = (0, 0, 0)
        obj.name = name
        me.name = name
        for p in me.polygons:
            p.use_smooth = True
        size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        out = os.path.join(OUT, name + ".glb")
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_image_format="JPEG", export_yup=True)
        results.append({"name": name, "source": pid, "tris_before": before, "tris": tri_count(me), "size_m": [round(s, 2) for s in size], "bytes": os.path.getsize(out)})
        print("OK", name, results[-1], round(time.time() - t0, 1), "s", flush=True)
    except Exception as e:
        import traceback
        traceback.print_exc()
        print("FAIL", pid, e, flush=True)

with open(os.path.join(OUT, "rock_kit.json"), "w") as f:
    json.dump(results, f, indent=2)
print("DONE", len(results), "of", len(KIT), flush=True)
