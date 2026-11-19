"""
Build and export the Ottoman-style small ports for Godot (companion of build_small_ports.py).

Run (background Blender, with PortRegionA_Ottoman.blend saved):
    Blender -b PortRegionA_Ottoman.blend --python tools/port_small/build_small_ports_ott.py

Set pieces:  Ottoman file, collection PortO_Small  (harbour-master houses V1-4, storehouses V1-4, wide stone quay, mole, lighthouse)
             PortRegionA.blend, collection PortA_Small  (wooden pier + berth, six canvas-top stalls, lamp post, props)
The Ottoman pieces use the Ottoman file's own export-ready materials (UVs already scaled). The Region A pieces are relinked to
the converted materials of PortRegionA_merge.blend and their UVs scaled, exactly like build_small_ports.py.
Output: assets/port/PortSmall_<ID>.glb  (+ .import files that point at port_import.gd)
"""
import bpy, bmesh, math, os, re, random
from mathutils import Vector, Matrix

REPO = r"C:\Users\Victus\Documents\GitHub\UnchartedOceans"
SRC_A = os.path.join(REPO, "PortRegionA.blend")
MERGE_A = os.path.join(REPO, "PortRegionA_merge.blend")
MERGE_O = os.path.join(REPO, "PortRegionA_Ottoman_merge.blend")
OUT = os.path.join(REPO, "uncharted-oceans", "assets", "port")
VEG_DIR = os.path.join(REPO, "uncharted-oceans", "assets", "vegetation")
DECK_Y = 1.85
KINDS = ["grocer", "fishmonger", "chandler", "cloth", "drink", "toolshop"]
PALETTE = {'grocer': 'M_PortA_AwningOchre', 'fishmonger': 'M_PortA_AwningTeal', 'chandler': 'M_PortA_AwningSlate',
           'cloth': 'M_PortA_AwningRed', 'drink': 'M_PortA_AwningPurple', 'toolshop': 'M_PortA_AwningGreen'}
# id, layout, buildings (HM = harbour-master house, AM = ambar/storehouse; variant), stall shuffle seed, land seed
PORTS = [
    ("CS14", "LR", [("HM", 1), ("AM", 2)], 21, 31),
    ("CS15", "LL", [("HM", 2), ("AM", 3)], 22, 32),
    ("CS16", "RR", [("AM", 4), ("HM", 3)], 23, 33),
    ("CS17", "LR", [("HM", 4), ("AM", 1)], 24, 34),
    ("CS18", "RL", [("AM", 1), ("HM", 3)], 25, 35),
]
def base(n): return re.sub(r"\.\d{3}$", "", n)

ott_orig = {m.name: m for m in bpy.data.materials}
before = set(bpy.data.materials)
with bpy.data.libraries.load(SRC_A, link=False) as (df, dt):
    dt.collections = ["PortA_Small"]
libA = bpy.data.collections["PortA_Small"]
appendedA = set(bpy.data.materials) - before
a_scale = {}
for m in appendedA:
    if m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == 'MAPPING': a_scale[base(m.name)] = float(n.inputs['Scale'].default_value[0])
with bpy.data.libraries.load(MERGE_A, link=False) as (df, dt):
    dt.materials = list(df.materials)
mergeA = set(bpy.data.materials) - before - appendedA
convA = {base(m.name): m for m in mergeA}
with bpy.data.libraries.load(MERGE_O, link=False) as (df, dt):
    dt.materials = list(df.materials)
mergeO = set(bpy.data.materials) - before - appendedA - mergeA
convO = {base(m.name): m for m in mergeO}     # the Ottoman capital's export-ready materials (pre-tinted OT_*_diff textures)
is_img = {k: any(n.type == 'TEX_IMAGE' for n in m.node_tree.nodes) for k, m in convA.items() if m.use_nodes}

libO = bpy.data.collections["PortO_Small"]
lib = {o.name: o for o in libA.all_objects}
lib.update({o.name: o for o in libO.all_objects})
keep = set(lib.values())
for o in list(bpy.data.objects):
    if o not in keep: bpy.data.objects.remove(o)

for me in {o.data for o in libA.all_objects if o.type == 'MESH'}:
    names = [base(m.name) if m else None for m in me.materials]
    if me.uv_layers and any(n and is_img.get(n) and a_scale.get(n) for n in names):
        uv = me.uv_layers.active.data
        for p in me.polygons:
            n = names[p.material_index] if p.material_index < len(names) else None
            s = a_scale.get(n) if n and is_img.get(n) else None
            if s:
                for li in p.loop_indices:
                    u = uv[li].uv; uv[li].uv = (u[0] * s, u[1] * s)
    for i, n in enumerate(names):
        if n is not None and n in convA: me.materials[i] = convA[n]
for me in {o.data for o in libO.all_objects if o.type == 'MESH'}:
    for i, m in enumerate(me.materials):
        if m is not None and base(m.name) in convO: me.materials[i] = convO[base(m.name)]
print("Region A pieces converted;", len(convA), "converted materials available")

col = bpy.data.collections.new("ExportTmp"); bpy.context.scene.collection.children.link(col)
made = []; extra_meshes = []
def clone(o, name, parent=None):
    n = o.copy(); n.name = name; col.objects.link(n); made.append(n)
    if parent is not None: n.parent = parent; n.matrix_parent_inverse = Matrix.Identity(4)
    return n
def clone_tree(src, rename, parent, loc, rotz=0.0):
    objs = [src] + list(src.children_recursive); mp = {}
    for o in objs: mp[o] = clone(o, rename(o.name))
    for o in objs:
        n = mp[o]
        if o is src:
            n.parent = parent; n.matrix_parent_inverse = Matrix.Identity(4); n.location = loc; n.rotation_euler = (0, 0, rotz)
        else:
            n.parent = mp[o.parent]; n.matrix_parent_inverse = o.matrix_parent_inverse.copy()
    return mp[src]
def empty(name, parent, loc, props=None):
    e = bpy.data.objects.new(name, None); col.objects.link(e); made.append(e); e.parent = parent; e.location = loc
    for k, v in (props or {}).items(): e[k] = v
    return e
def noise(x, y, seed):
    def h(ix, iy): return random.Random((ix * 73856093) ^ (iy * 19349663) ^ (seed * 83492791)).random()
    ix, iy = math.floor(x), math.floor(y); fx, fy = x - ix, y - iy
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b, c, d = h(ix, iy), h(ix + 1, iy), h(ix, iy + 1), h(ix + 1, iy + 1)
    top = a + (b - a) * sx; bot = c + (d - c) * sx
    return top + (bot - top) * sy
def coast(x): return 0.0 if abs(x) <= 34 else 0.0006 * (abs(x) - 34) ** 2
def land_h(x, y, seed):
    dx = max(0.0, abs(x) - 30.0); dy = max(0.0, y - 36.0); dist = math.hypot(dx, dy)
    if dist <= 0.0 and y >= 0: return -0.12
    w = min(dist / 20.0, 1.0); w = w * w * (3 - 2 * w)
    d = max(0.0, max(abs(x) - 36.0, y - 40.0)); t = min(d / 230.0, 1.0); t = t * t * (3 - 2 * t)
    n = (noise(x / 45.0, y / 45.0, seed) - 0.5) * 2.0
    return w * (18.0 * t + n * (0.4 + 3.0 * t)) + (1 - w) * (-0.05)

def build_land(seed, root):
    xs = [-336 + 14 * i for i in range(49)]; ys = [14 * j for j in range(20)]; nx, ny = len(xs) - 1, len(ys) - 1
    kept = {(i, j): math.hypot((xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2 + 70.0) <= 332.0 for i in range(nx) for j in range(ny)}
    bm = bmesh.new(); V = {}
    def vert(i, j):
        if (i, j) not in V:
            x = xs[i]; y = max(ys[j], coast(x)); V[(i, j)] = bm.verts.new((x, y, land_h(x, y, seed)))
        return V[(i, j)]
    for (i, j), k in kept.items():
        if not k: continue
        vs = [vert(i, j), vert(i + 1, j), vert(i + 1, j + 1), vert(i, j + 1)]
        f = bm.faces.new(vs); f.material_index = 1 if sum(v.co.z for v in vs) / 4 > 6.0 else 0
    for (i, j), k in kept.items():
        if not k: continue
        for (di, dj, edge, out) in ((0, -1, ((i, j), (i + 1, j)), (0, -1)), (0, 1, ((i + 1, j + 1), (i, j + 1)), (0, 1)),
                                    (-1, 0, ((i, j + 1), (i, j)), (-1, 0)), (1, 0, ((i + 1, j), (i + 1, j + 1)), (1, 0))):
            if kept.get((i + di, j + dj), False): continue
            a, b = vert(*edge[0]), vert(*edge[1])
            f = bm.faces.new([bm.verts.new(a.co), bm.verts.new(b.co), bm.verts.new((b.co.x, b.co.y, -6.0)), bm.verts.new((a.co.x, a.co.y, -6.0))]); f.normal_update()
            if Vector((out[0], out[1], 0)).dot(f.normal) < 0: f.normal_flip()
            f.material_index = 0
    me = bpy.data.meshes.new("SP_Land_mesh"); bm.to_mesh(me); bm.free()
    for m in ("OT_Earth", "OT_HillEarth"): me.materials.append(convO[m])
    o = bpy.data.objects.new("SP_Land", me); col.objects.link(o); made.append(o); o.parent = root; o['game_role'] = 'static'
    return o

def vegetation(root, seed):
    rnd = random.Random(seed)
    def have(n): return os.path.exists(os.path.join(VEG_DIR, n + ".glb"))
    trees = [t for t in ("Tree_Poplar", "Tree_Oak", "Tree_Linden") if have(t)]
    shrubs = [t for t in ("Shrub_Round", "Shrub_Juniper", "Hedge_4m") if have(t)]
    ground = [t for t in ("Grass_Tuft", "Fern_Clump") if have(t)]
    def place(name, x, y, k):
        e = empty(f"Veg_{name}.{k:02d}", root, (x, y, land_h(x, y, seed)), {'vegetation': name, 'vis_begin': 0.0, 'vis_end': 160.0})
        e.rotation_euler = (0, 0, rnd.uniform(0, 6.283))
    def free(x, y): return not (abs(x) < 34 and y < 44) and not (-48 < x < -32 and y < 12)
    k = 0
    for _ in range(400):
        if k >= 20: break
        x, y = rnd.uniform(-220, 220), rnd.uniform(40, 200)
        if free(x, y) and trees: place(rnd.choice(trees), x, y, k); k += 1
    for _ in range(400):
        if k >= 46: break
        x, y = rnd.uniform(-90, 90), rnd.uniform(2, 70)
        if abs(x) > 33 and shrubs and free(x, y): place(rnd.choice(shrubs), x, y, k); k += 1
    for _ in range(400):
        if k >= 80: break
        x, y = rnd.uniform(-120, 120), rnd.uniform(4, 120)
        if ground and free(x, y) and abs(x) > 31: place(rnd.choice(ground), x, y, k); k += 1

def building_src(kind, variant):
    return lib[("PortO_Harbourmaster_V%d" if kind == "HM" else "PortO_Ambar_V%d") % variant]

def build_port(pid, layout, bldgs, sseed, lseed):
    made.clear(); extra_meshes.clear()
    root = empty(f"PortSmall_{pid}", None, (0, 0, DECK_Y), {'game_role': 'port', 'port_id': pid, 'region': 'C', 'style': 'small_ottoman'})
    q = clone(lib["PortO_SmallQuay_Mesh"], "SP_Quay", root); q.location = (0, 0, 0)
    def pier_name(n):
        if n == "PortA_Berth_01": return "Berth_01"
        if n == "PortA_Pier_Deck": return "SP_Pier_Deck"
        return n.replace("PortA_Pier", "Pier")
    clone_tree(lib["PortA_Pier"], pier_name, root, (0, 0, 0))
    mole = clone(lib["PortO_Mole_Mesh"], "SP_Mole", root); mole.location = (-40, 0, 0)
    clone_tree(lib["PortO_Lighthouse"], lambda n: {"PortO_Lighthouse": "Lighthouse", "PortO_Lighthouse_Mesh": "SP_Lighthouse", "PortO_Lighthouse_Light": "Lighthouse_Light"}[n], root, (-40, -29, 0))
    for i, (x, y) in enumerate(((-4.5, 3.0), (4.5, 3.0), (-4.5, 22.0), (4.5, 22.0))):
        lp = clone(lib["PortA_Pier_LampPost.1"], f"Quay_LampPost.{i+1}", root); lp.location = (x, y, 0); lp.rotation_euler = (0, 0, 0)
    order = KINDS[:]; random.Random(sseed).shuffle(order)
    slots = [("L1", -7.0, 7.0), ("L2", -7.0, 11.8), ("L3", -7.0, 16.6), ("R1", 7.0, 7.0), ("R2", 7.0, 11.8), ("R3", 7.0, 16.6)]
    for (slot, x, y), kind in zip(slots, order):
        src = lib[f"PortA_Stall_{kind}"]; pre = src.name
        sroot = clone_tree(src, lambda n, pre=pre, slot=slot, kind=kind: n.replace(pre, f"Stall_{slot}_{kind}", 1), root, (x, y, 0), math.radians(90 if x < 0 else -90))
        for o in sroot.children_recursive:
            if o.name.endswith("_Frame") and o.type == 'MESH':
                me = o.data.copy(); extra_meshes.append(me)
                for i, m in enumerate(me.materials):
                    if m and base(m.name).startswith("M_PortA_Awning"): me.materials[i] = convA[PALETTE[kind]]
                o.data = me
    ycur = {"L": 6.5, "R": 6.5}
    for idx, ((bk, bv), side) in enumerate(zip(bldgs, layout)):
        src = building_src(bk, bv); W, L = [float(v) for v in src['footprint_m']]; pre = src.name; slotn = f"{bk}_{idx+1}"
        def rn(n, pre=pre, slotn=slotn):
            nn = n.replace(pre, f"Bldg_{slotn}", 1)
            return "SP_" + nn if nn.endswith("_Shell") else nn
        if side == "L":
            clone_tree(src, rn, root, (-12.0, ycur["L"], 0), math.radians(90)); ycur["L"] += W + 3.5
        else:
            clone_tree(src, rn, root, (12.0, ycur["R"] + W, 0), math.radians(-90)); ycur["R"] += W + 3.5
    # the tavern, copied from the capital, goes on the less crowded side and faces the middle too
    tv = lib["PortO_Tavern_Kit"]; W, L = [float(v) for v in tv['footprint_m']]
    def rn_tv(n):
        nn = n.replace("PortO_Tavern_Kit", "Bldg_TV", 1)
        return "SP_" + nn if lib[n].get('walk') else nn
    if ycur["L"] <= ycur["R"]:
        clone_tree(tv, rn_tv, root, (-12.0, ycur["L"], 0), math.radians(90)); ycur["L"] += W + 3.5
    else:
        clone_tree(tv, rn_tv, root, (12.0, ycur["R"] + W, 0), math.radians(-90)); ycur["R"] += W + 3.5
    if max(ycur.values()) > 40: print("WARNING: buildings run past the quay in", pid, ycur)
    build_land(lseed, root); vegetation(root, lseed)
    path = os.path.join(OUT, f"PortSmall_{pid}.glb")
    bpy.ops.object.select_all(action='DESELECT')
    for o in made: o.select_set(True)
    bpy.context.view_layer.objects.active = root
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_extras=True, export_yup=True, export_cameras=False,
              export_lights=False, export_animations=False, export_apply=False, export_materials='EXPORT', export_image_format='AUTO')
    bpy.ops.export_scene.gltf(**{k: v for k, v in kw.items() if k in props})
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in made if o.type == 'MESH' and 'convcolonly' not in o.name)
    print(f"EXPORTED {pid}: {os.path.getsize(path)/1e6:.1f} MB, objects {len(made)}, tris {tris}")
    for o in made:
        d = o.data if o.type == 'MESH' else None
        bpy.data.objects.remove(o)
        if d is not None and d.users == 0 and d.name.startswith("SP_Land"): bpy.data.meshes.remove(d)
    for me in extra_meshes:
        if me.users == 0: bpy.data.meshes.remove(me)

ONLY = [x for x in os.environ.get('PORT_ONLY', '').split(',') if x]   # e.g. PORT_ONLY=AS08 rebuilds just that port
for cfg in PORTS:
    if ONLY and cfg[0] not in ONLY: continue
    build_port(*cfg)

IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="res://assets/port/%s.glb"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
mesh_library/use_node_names_as_mesh_names=false
array_mesh/deduplicate_surfaces=true
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path="res://assets/port/port_import.gd"
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={}
gltf/naming_version=2
gltf/embedded_image_handling=1
gltf/texture_map_mode=1
"""
for pid, *_ in PORTS:
    p = os.path.join(OUT, f"PortSmall_{pid}.glb.import")
    if not os.path.exists(p): open(p, "w", encoding="utf8", newline="\n").write(IMPORT % f"PortSmall_{pid}")
print("DONE")
