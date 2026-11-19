"""
Build and export the Asian-style small ports of region B (BS09-BS13) and the neutral free port FF24 (a European/Asian mix).

Run (background Blender, with PortRegionD.blend saved):
    Blender -b PortRegionD.blend --python tools/port_small/build_small_ports_asi.py

Set pieces:  PortRegionD.blend, collection PortD_Small  (harbour-master houses V1-4, storehouses V1-4, wide coral-stone quay, mole,
             lighthouse, walkable coffee-house tavern kit)
             PortRegionA.blend, collection PortA_Small  (wooden pier + berth, six canvas-top stalls, lamp post, props)
The African pieces use PortRegionD.blend's own materials (shared Poly Haven textures, UVs already in metres/tile). The Region A pieces
are relinked to the converted materials of PortRegionA_merge.blend and their UVs scaled, exactly like the other small-port scripts.
Output: assets/port/PortSmall_<ID>.glb  (+ .import files that point at port_import.gd). Nothing is saved back to the .blend.
"""
import bpy, bmesh, math, os, re, random
from mathutils import Vector, Matrix

REPO = r"C:\Users\Victus\Documents\GitHub\UnchartedOceans"
SRC_A = os.path.join(REPO, "PortRegionA.blend")
MERGE_A = os.path.join(REPO, "PortRegionA_merge.blend")
OUT = os.path.join(REPO, "uncharted-oceans", "assets", "port")
VEG_DIR = os.path.join(REPO, "uncharted-oceans", "assets", "vegetation")
DECK_Y = 1.85
KINDS = ["grocer", "fishmonger", "chandler", "cloth", "drink", "toolshop"]
PALETTE = {'grocer': 'M_PortA_AwningOchre', 'fishmonger': 'M_PortA_AwningTeal', 'chandler': 'M_PortA_AwningSlate',
           'cloth': 'M_PortA_AwningRed', 'drink': 'M_PortA_AwningPurple', 'toolshop': 'M_PortA_AwningGreen'}
# id, layout, buildings (HM = harbour-master house, AM = ambar/storehouse; variant), stall shuffle seed, land seed
PORTS = [   # id, layout, buildings ((WH,1-3)=Asian warehouse, (HM,1-4)/(NL,1-4)=Region A), tavern ('ASI'|'EU'), stall seed, land seed, style
    ("BS09", "LR", [("WH", 1), ("WH", 2)], 'ASI', 61, 71, 'asian'),
    ("BS10", "RL", [("WH", 2), ("WH", 3)], 'ASI', 62, 72, 'asian'),
    ("BS11", "LR", [("WH", 3), ("WH", 1)], 'ASI', 63, 73, 'asian'),
    ("BS12", "RL", [("WH", 3), ("WH", 1)], 'ASI', 64, 74, 'asian'),
    ("BS13", "RL", [("WH", 2), ("WH", 1)], 'ASI', 65, 75, 'asian'),
    ("FF24", "LR", [("HM", 2), ("WH", 2)], 'EU', 81, 85, 'free'),
]
def base(n): return re.sub(r"\.\d{3}$", "", n)

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
is_img = {k: any(n.type == 'TEX_IMAGE' for n in m.node_tree.nodes) for k, m in convA.items() if m.use_nodes}


# ---- Asian set pieces from the capital in this file (PortCapital_Asian), regrouped into canonical frame: front = -y, corner at origin ----
cap = bpy.data.objects["PortCapital_Asian"]
def grp(pred):
    return [o for o in bpy.data.objects if o.name.startswith("Cap_") and o.type in ('MESH', 'EMPTY') and pred(o.name)]
GROUPS = {
    "WH1": (lambda n: n.startswith("Cap_Warehouse_E1"), None),
    "WH2": (lambda n: n.startswith("Cap_Warehouse_W1"), None),
    "WH3": (lambda n: n.startswith("Cap_Warehouse_W2"), None),
    "TV": (lambda n: n.startswith(("Cap_Bldg_Tavern", "Cap_Int_Tavern", "Cap_Tavern")), (-1.0, 0.0)),
    "LH": (lambda n: n.startswith("Cap_Bldg_MouthTower_E"), None),
}
def bbox(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs if o.type == 'MESH' for c in o.bound_box]
    return [min(p[i] for p in pts) for i in range(3)], [max(p[i] for p in pts) for i in range(3)]
def auto_front(objs, mn, mx):
    # the side with the most "detail" geometry (doors, signs, banners): offset of the Details/Windows centroid from the shell centre
    det = [o for o in objs if o.type == 'MESH' and o.name.endswith(("_Details", "_Windows"))]
    if not det: return (0.0, -1.0)
    sx = sy = n = 0.0
    for o in det:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co; sx += w.x; sy += w.y; n += 1
    cx, cy = (mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2
    dx, dy = sx / n - cx, sy / n - cy
    return (math.copysign(1, dx), 0.0) if abs(dx) > abs(dy) else (0.0, math.copysign(1, dy))
kit = {}
for key, (pred, front) in GROUPS.items():
    objs = grp(pred)
    meshes = [o for o in objs if o.type == 'MESH' and 'convcolonly' not in o.name]
    mn, mx = bbox(meshes)
    f = front or auto_front(objs, mn, mx)
    # rotation taking f to (0,-1)
    ang = math.atan2(-1.0, 0.0) - math.atan2(f[1], f[0])
    R = Matrix.Rotation(ang, 4, 'Z')
    pts = [R @ Vector((x, y, 0)) for x in (mn[0], mx[0]) for y in (mn[1], mx[1])]
    cx0, cy0 = min(p.x for p in pts), min(p.y for p in pts)
    W = max(p.x for p in pts) - cx0; L = max(p.y for p in pts) - cy0
    T = Matrix.Translation((-cx0, -cy0, -DECK_Y)) @ R
    g = bpy.data.objects.new("KIT_" + key, None); bpy.context.scene.collection.objects.link(g)
    for o in objs:
        mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
        o.parent = g; o.matrix_parent_inverse = T
    g['footprint_m'] = (W, L)
    kit[key] = g
    print(f"kit {key}: front {f}, footprint {W:.1f} x {L:.1f}, {len(objs)} objs")
# the lighthouse lamp: an empty with light props at the top of the tower
lhg = kit["LH"]; lhW, lhL = lhg['footprint_m']

libs = {o.name: o for o in libA.all_objects}
keep = set(libs.values()) | set(bpy.data.objects[n] for n in [] )
for k in kit.values(): keep |= {k} | set(k.children_recursive)
for o in list(bpy.data.objects):
    if o not in keep: bpy.data.objects.remove(o)
for k in kit.values(): keep |= set(k.children_recursive)

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
print("Region A pieces converted")

lib = libs
STONE = bpy.data.materials["M_Asi_Stone"]
def land_material(name, rgb):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]; b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1); b.inputs["Roughness"].default_value = 0.95
    return m
landmats = {'asian': (land_material("AS_Earth", (0.40, 0.44, 0.27)), land_material("AS_HillEarth", (0.31, 0.37, 0.22))),
            'free': (land_material("FF_Earth", (0.52, 0.48, 0.32)), land_material("FF_HillEarth", (0.40, 0.40, 0.27)))}
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
    dx = max(0.0, abs(x) - 30.0); dy = max(0.0, y - 46.0); dist = math.hypot(dx, dy)
    if dist <= 0.0 and y >= 0: return -0.12
    w = min(dist / 20.0, 1.0); w = w * w * (3 - 2 * w)
    d = max(0.0, max(abs(x) - 36.0, y - 50.0)); t = min(d / 230.0, 1.0); t = t * t * (3 - 2 * t)
    n = (noise(x / 45.0, y / 45.0, seed) - 0.5) * 2.0
    return w * (18.0 * t + n * (0.4 + 3.0 * t)) + (1 - w) * (-0.05)

def build_land(seed, root, style):
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
    for m in landmats[style]: me.materials.append(m)
    o = bpy.data.objects.new("SP_Land", me); col.objects.link(o); made.append(o); o.parent = root; o['game_role'] = 'static'
    return o

def vegetation(root, seed, style):
    rnd = random.Random(seed)
    def have(n): return os.path.exists(os.path.join(VEG_DIR, n + ".glb"))
    if style == 'free':
        trees = [t for t in ("Tree_Palm_A", "Tree_Palm_B", "Tree_Oak", "Tree_Linden", "Tree_Pine", "Tree_Mango_A") if have(t)]
        shrubs = [t for t in ("Shrub_Round", "Shrub_Flowering", "Shrub_Bougainvillea", "Plant_Banana") if have(t)]
        ground = [t for t in ("Grass_Tuft", "Fern_Clump") if have(t)]
    else:
        trees = [t for t in ("Tree_Pine", "Tree_Pine", "Tree_Palm_A", "Tree_Palm_B", "Tree_Pine", "Tree_Palm_A") if have(t)]
        shrubs = [t for t in ("Shrub_Juniper", "Shrub_Flowering", "Shrub_Round") if have(t)]
        ground = [t for t in ("Grass_Tuft", "Fern_Clump") if have(t)]
    def place(name, x, y, k):
        e = empty(f"Veg_{name}.{k:02d}", root, (x, y, land_h(x, y, seed)), {'vegetation': name, 'scene': f'res://assets/vegetation/{name}.glb', 'vis_begin': 0.0, 'vis_end': 160.0})
        e.rotation_euler = (0, 0, rnd.uniform(0, 6.283))
    def free(x, y): return not (abs(x) < 34 and y < 56) and not (-48 < x < -32 and y < 12)
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


def box(name, x0, x1, y0, y1, z0, z1, root):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x = x0 if v.co.x < 0 else x1; v.co.y = y0 if v.co.y < 0 else y1; v.co.z = z0 if v.co.z < 0 else z1
    uv = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        n = f.normal; ax = max(range(3), key=lambda i: abs(n[i])); a, b = [(1, 2), (0, 2), (0, 1)][ax]
        for l in f.loops: l[uv].uv = (l.vert.co[a] / 2.0, l.vert.co[b] / 2.0)
    me = bpy.data.meshes.new(name + "_mesh"); bm.to_mesh(me); bm.free(); me.materials.append(STONE)
    for p in me.polygons: p.use_smooth = False
    o = bpy.data.objects.new(name, me); col.objects.link(o); made.append(o); o.parent = root; o['game_role'] = 'static'
    extra_meshes.append(me)
    return o

def kit_src(kind, variant):
    if kind == "WH": return kit["WH%d" % variant]
    return lib["PortA_Harbourmaster" + ("" if variant == 1 else "_V%d" % variant)] if kind == "HM" else lib["PortA_NetLoft" + ("" if variant == 1 else "_V%d" % variant)]

def build_port(pid, layout, bldgs, tav, sseed, lseed, style):
    made.clear(); extra_meshes.clear()
    root = empty(f"PortSmall_{pid}", None, (0, 0, DECK_Y), {'game_role': 'port', 'port_id': pid, 'region': 'F' if style == 'free' else 'B', 'style': 'small_free' if style == 'free' else 'small_asian'})
    box("SP_Quay", -34, 34, -3, 52, -7, 0, root)
    box("SP_Mole", -47, -33, -36, -2, -7, 0, root)
    def pier_name(n):
        if n == "PortA_Berth_01": return "Berth_01"
        if n == "PortA_Pier_Deck": return "SP_Pier_Deck"
        return n.replace("PortA_Pier", "Pier")
    clone_tree(lib["PortA_Pier"], pier_name, root, (0, 0, 0))
    lh = clone_tree(kit["LH"], lambda n: n, root, (-40 - lhW / 2, -29 - lhL / 2, 0))
    lh_empty = empty("Lighthouse", root, (-40, -29, 0), {'game_role': 'landmark', 'region': 'B', 'height_m': 20.6})
    empty("Lighthouse_Light", lh_empty, (0, 0, 19.0), {'game_role': 'light', 'light_color': (1.0, 0.82, 0.45), 'light_range_m': 35.0, 'light_energy': 3.0, 'flash_period_s': 0.0, 'night_only': True})
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
    def place_bldg(src, rn, side):
        W, L = [float(v) for v in src['footprint_m']]
        if side == "L":
            clone_tree(src, rn, root, (-12.0, ycur["L"], 0), math.radians(90)); ycur["L"] += W + 3.5
        else:
            clone_tree(src, rn, root, (12.0, ycur["R"] + W, 0), math.radians(-90)); ycur["R"] += W + 3.5
    for idx, ((bk, bv), side) in enumerate(zip(bldgs, layout)):
        src = kit_src(bk, bv); pre = src.name
        if bk == "WH":
            wp = {1: "Cap_Warehouse_E1", 2: "Cap_Warehouse_W1", 3: "Cap_Warehouse_W2"}[bv]
            rn = lambda n, wp=wp, idx=idx: n.replace(wp, f"Cap_Warehouse_P{idx+1}_{wp[-2:]}", 1) if n.startswith(wp) else n
        else:
            rn = lambda n, pre=pre, idx=idx: ("SP_" if n.endswith("_Shell") else "") + n.replace(pre, f"Bldg_{bk}{idx+1}", 1)
        place_bldg(src, rn, side)
    if tav == 'ASI':
        tv = kit["TV"]; rn_tv = lambda n: n
    else:
        tv = lib["PortA_Tavern_Kit"]
        rn_tv = lambda n: ("SP_" + n.replace("PortA_Tavern_Kit", "Bldg_TV", 1)) if lib[n].get('walk') else n.replace("PortA_Tavern_Kit", "Bldg_TV", 1)
    side = "L" if ycur["L"] <= ycur["R"] else "R"
    place_bldg(tv, rn_tv, side)
    if max(ycur.values()) > 51: print("WARNING: buildings run past the quay in", pid, ycur)
    build_land(lseed, root, style); vegetation(root, lseed, style)
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

ONLY = [x for x in os.environ.get('PORT_ONLY', '').split(',') if x]
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
