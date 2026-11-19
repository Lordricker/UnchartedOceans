"""02_build_export.py  -  materials-ready cutter -> merged game meshes, game-named parts, markers, collision, sails; exports Cutter.glb.
Follows tools/brig_merge (node names + glTF extras that brig_import.gd and the game scripts read). Read first, then create (Blender 4.1
crashes if objects are evaluated after the scene changed). The source is never modified."""
import bpy, bmesh, os, json, math
import numpy as np
from mathutils import Vector, Matrix
PROJ = os.environ["CUTTER_PROJECT"]; OUT = os.environ["MERGE_OUT"]; GLB = os.environ["GLB_OUT"]
O = bpy.data.objects
LOG = open(os.path.join(PROJ, "tools", "cutter_merge", "stage2_log.txt"), "w", encoding="utf-8")
def L(m): LOG.write(str(m) + "\n"); LOG.flush(); os.fsync(LOG.fileno())

# ------------------------------------------------------------------ helpers
class Acc:
    def __init__(self): self.verts = []; self.faces = []; self.uvs = []; self.mi = []; self.sm = []; self.mats = []
def add_obj(acc, obj):
    ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()); me = bpy.data.meshes.new_from_object(ev); mw = np.array(obj.matrix_world)
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
    if a is None: a = next((x for x in me.attributes if x.domain == 'CORNER' and x.data_type == 'FLOAT2'), None)
    uv = None
    if a is not None:
        uv = np.empty(len(a.data)*2, dtype=np.float32); a.data.foreach_get("vector", uv); uv = uv.reshape(-1, 2)
    mats = [s.material for s in obj.material_slots]
    base = len(acc.verts); acc.verts.extend(map(tuple, wco.tolist())); n = 0
    for i in range(npoly):
        s, t = int(ls[i]), int(lt[i]); vs = lv[s:s+t]
        acc.faces.append(tuple(int(base + v) for v in vs))
        acc.uvs.append(uv[s:s+t].tolist() if uv is not None else None)
        m = mats[mi[i]] if mi[i] < len(mats) else None
        if m not in acc.mats: acc.mats.append(m)
        acc.mi.append(acc.mats.index(m)); acc.sm.append(bool(sm[i])); n += 1
    bpy.data.meshes.remove(me); return n
def make_mesh(acc, name, with_mats=True):
    me = bpy.data.meshes.new(name); me.from_pydata([tuple(v) for v in acc.verts], [], acc.faces)
    if with_mats:
        for m in acc.mats: me.materials.append(m)
        me.polygons.foreach_set("material_index", np.array(acc.mi, dtype=np.int32))
    me.polygons.foreach_set("use_smooth", np.array(acc.sm, dtype=np.bool_))
    uvl = me.uv_layers.new(name="UVMap"); flat = []
    for p, u in zip(me.polygons, acc.uvs): flat.extend(([c for uv in u for c in uv]) if u else [0.0] * (2 * p.loop_total))
    uvl.data.foreach_set("uv", np.array(flat, dtype=np.float32))
    bm = bmesh.new(); bm.from_mesh(me); dead = [x for x in bm.verts if not x.link_faces]
    if dead: bmesh.ops.delete(bm, geom=dead, context='VERTS')
    bm.to_mesh(me); bm.free(); me.update(); return me
def wbox(o):
    ws = [o.matrix_world @ Vector(c) for c in o.bound_box]
    return Vector((min(w.x for w in ws), min(w.y for w in ws), min(w.z for w in ws))), Vector((max(w.x for w in ws), max(w.y for w in ws), max(w.z for w in ws)))

# ------------------------------------------------------------------ what goes where
GROUPS = {
 "Hull": ["Hull"],
 "MainDeck": ["Deck", "CockpitSole", "CockpitCoaming", "HoldFloor", "CabinFloor", "Companionway_Steps"],
 "DeckFittings": ["Capstan", "BoardingSteps", "Channels", "Deadeyes", "Chainplates", "Blocks", "RopeFittings", "SheetCleats", "Cleats", "MainsheetHorse", "PinRail", "BelayPins",
                  "Anchor", "BowspritBitts", "HoldLadder", "Mooring_Rope", "BinnacleBody", "BinnacleBrass", "RudderGudgeons"],
 "Rig_Spars": ["Mast", "Topmast", "Bowsprit", "MastTop", "MastHoops"],
 "Rig_Ropes": ["Rigging", "Ratlines", "BoardingRopes"],          # RunningRigging (halyards, jib sheets) and Mainsheet are modelled for the Blender view only: the game draws them live (ship_classes.gd rig haul / rope_lines) so they follow the sails
 "Interiors": ["Cabin", "Skylight", "Bulkheads", "Bunk_Port", "ChartTable", "CabinBookshelf_Frame"],
 "HullTrim": ["CapRail", "Wales", "StemKeel"],                     # the sloop hull's rail cap, wales and stem / keel: their own mesh so the Hull convex collider is not widened by them
 "Glass": ["CabinWindows", "SkylightGlass"],
}
ROLE = {"Hull": "static", "MainDeck": "static", "DeckFittings": "static", "Rig_Spars": "static", "Rig_Ropes": "static", "Interiors": "static", "Glass": "glass", "HullTrim": "static"}
# kept as their own nodes (old name, new name, props). Sails and spars are siblings under the root, like the brig's spanker parts.
KEEP = [
 ("Rudder", "Rudder", {"game_role": "rudder", "vis_begin": 0.0, "vis_end": 60.0}),
 ("Tiller", "Tiller", {"game_role": "tiller", "vis_begin": 0.0, "vis_end": 60.0}),
 ("Swivel_Post", "Gun_0", {"game_role": "gun"}),
 ("Swivel_Gun", "Gun_0_Barrel", {"game_role": "gun_barrel"}),
 ("MainSail", "Sail_Spanker", {"game_role": "sail", "reefable": False, "sail_kind": "spanker"}),
 ("Boom", "Spanker_Boom", {"game_role": "spanker_spar", "vis_begin": 0.0, "vis_end": 250.0}),
 ("HorseBlock", "Sheet_Block", {"game_role": "sheet_block", "vis_begin": 0.0, "vis_end": 120.0}),                     # the mainsheet block on the horse; ShipSails slides it along the bar
 ("Jib", "Sail_Jib", {"game_role": "sail", "reefable": False, "sail_kind": "headsail"}),
 ("BinnacleGlass", "BinnacleGlass", {"interaction": "compass"}),
 ("CabinBed", "CabinBed", {"interaction": "bed"}), ("CabinBedding", "CabinBedding", {"interaction": "bed"}), ("Chart", "TableChart", {"interaction": "chart"}),                      # ShipHelm builds its compass card under this node
 ("PumpHandle", "Pump_Brake", {}), ("Pump", "Pump_Body", {}), ("LogLineCoil", "LogLine_Coil", {"interaction": "log_line", "vis_begin": 0.0, "vis_end": 35.0}),
]
BOOKS = [n for n in O.keys() if n.startswith("Book_")]
OBSTACLE_BOXES = ["Bunk_Port", "CabinBed", "ChartTable", "CabinBookshelf_Frame", "Pump", "PinRail", "Anchor", "BinnacleBody"]

# ================================================================== READ (everything that needs evaluation)
accs = {g: Acc() for g in GROUPS}
for g, names in GROUPS.items():
    for n in names:
        if n in O: add_obj(accs[g], O[n])
        else: L("MISSING " + n)
walls, floors = Acc(), Acc()
for n in ("Hull", "Cabin", "Bulkheads", "CockpitCoaming", "Skylight"): add_obj(walls, O[n])
for n in ("Deck", "CockpitSole", "HoldFloor", "CabinFloor", "Companionway_Steps"): add_obj(floors, O[n])
boxes = {n: wbox(O[n]) for n in OBSTACLE_BOXES if n in O}
mast_box = wbox(O["Mast"])
worlds = {n: O[n].matrix_world.copy() for n in [k[0] for k in KEEP] + BOOKS + ["CabinBookshelf"] if n in O}
dg = bpy.context.evaluated_depsgraph_get(); sc = bpy.context.scene
wl = []
for i in range(23):
    y = -5.5 + 0.5 * i; hx = 0.0; org = Vector((4.0, y, 0.0))
    for _ in range(5):
        ok, loc, nrm, idx, ob, mw = sc.ray_cast(dg, org, Vector((-1, 0, 0)), distance=8.0)
        if not ok: break
        if ob.name == "Hull": hx = abs(loc.x); break
        org = loc + Vector((-0.01, 0, 0))
    wl.append(round(hx, 3))
if wl[-1] == 0.0: wl[-1] = wl[-2]                 # the transom plane itself gives no hit
L("waterline half beam: %s" % wl)
stations = []
for c in bpy.data.collections["Cutter_Stations"].objects:
    cp = {k: (list(c[k]) if hasattr(c[k], '__len__') and not isinstance(c[k], str) else c[k]) for k in c.keys() if not k.startswith('_')}
    stations.append((c.name, c.matrix_world.translation.copy(), c.empty_display_type, c.empty_display_size, c.scale.copy(), c.rotation_euler.copy(), cp))
L("READ done: %s" % {g: len(a.faces) for g, a in accs.items()})

# ================================================================== CREATE
exp = bpy.data.collections.new("Cutter_Export"); bpy.context.scene.collection.children.link(exp)
FINAL = []                                                       # (object, final name): renamed after the sources are removed
def newobj(name, data):
    ob = bpy.data.objects.new(name + "__new", data); FINAL.append((ob, name)); return ob
ident = Matrix.Identity(4)
root = newobj("Cutter", None); exp.objects.link(root)
for _k, _v in ({"game_role": "ship_root", "ship_class": "cutter", "ship_tier": "small", "length_on_deck_m": 11.0, "guns": 1, "crew_min": 1, "crew_max": 2,
             "bow_axis_blender": "-Y", "bow_axis_godot": "+Z (rotate 180 deg about Y for -Z forward)", "waterline_z": 0.0, "main_deck_z_midships": 0.85,
             "lower_deck_z": -0.5, "hold_floor_z": -0.95, "source_file": "StarterCutterShip.blend",
             "waterline_half_beam": wl, "waterline_y_min": -5.5, "waterline_y_step": 0.5}).items(): root[_k] = _v
def link(ob):
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    exp.objects.link(ob)
def put(ob, parent=None):
    link(ob); ob.parent = parent or root; ob.matrix_parent_inverse = ident
def setprops(ob, props):
    for k, v in (props or {}).items(): ob[k] = v

# ---- merged static groups
for g, acc in accs.items():
    me = make_mesh(acc, g); ob = newobj(g, me); put(ob); setprops(ob, {"game_role": ROLE[g]})
    L("GROUP %s: %d faces, %d materials" % (g, len(me.polygons), len(me.materials)))

# ---- kept parts (names the game scripts look for)
pump_root = newobj("Pump", None); put(pump_root)
setprops(pump_root, {"type": "pump", "brake_pivot_axis": "x", "crew_per_pump": 1, "interaction": "pump"})
CHILD_OF = {"Tiller": "Rudder", "Swivel_Gun": "Swivel_Post"}      # these keep their parent (and its pivot)
for old, new, props in KEEP:
    ob = O.get(old)
    if ob is None: L("MISSING keep " + old); continue
    w = worlds[old]
    if old in CHILD_OF:
        link(ob)
    else:
        link(ob); ob.parent = pump_root if old in ("PumpHandle", "Pump") else root
        ob.matrix_parent_inverse = ident; ob.matrix_basis = w
    ob.name = new; setprops(ob, props)
# ---- books and the shelf marker
shelf = O["CabinBookshelf"]; shelf_w = worlds["CabinBookshelf"]
link(shelf); shelf.parent = root; shelf.matrix_parent_inverse = ident; shelf.matrix_basis = shelf_w; setprops(shelf, {"interaction": "bookshelf"})
for n in BOOKS:
    b = O[n]; link(b)
    setprops(b, {"interaction": "logbook" if n == "Book_Logbook" else "book", "book_id": "logbook" if n == "Book_Logbook" else n[len("Book_"):].lower()})

# ---- sails: PinWeights (r billow, g height head=0..foot=1, b across), Furled / Reefed shape keys, origins where the game expects them
def sail_data(ob):
    mw = np.array(ob.matrix_basis); me = ob.data; nv = len(me.vertices)
    co = np.empty(nv*3, dtype=np.float32); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    return mw, (np.c_[co, np.ones(nv, dtype=np.float32)] @ mw.T)[:, :3]
def attach_weights_and_shapes(ob, mode):
    mw, wco = sail_data(ob); me = ob.data
    inv = np.linalg.inv(mw)
    x0, x1 = wco[:, 0].min(), wco[:, 0].max(); r = (wco[:, 0] - x0) / max(x1 - x0, 1e-6)
    if mode == "main":
        zmin, zmax = wco[:, 2].min(), wco[:, 2].max(); ymin, ymax = wco[:, 1].min(), wco[:, 1].max()
        g = 1.0 - (wco[:, 2] - zmin) / max(zmax - zmin, 1e-6); b = (wco[:, 1] - ymin) / max(ymax - ymin, 1e-6)
        def squash(f):
            q = wco.copy(); q[:, 2] = zmin + (wco[:, 2] - zmin) * f; return q
    else:
        tack = wco[np.argmin(wco[:, 1])]; head = wco[np.argmax(wco[:, 2])]; ax = head - tack; ln2 = float(ax @ ax)
        t = np.clip(((wco - tack) @ ax) / ln2, 0.0, 1.0); q_on = tack + t[:, None] * ax
        d = np.linalg.norm(wco - q_on, axis=1); g = 1.0 - t; b = d / max(d.max(), 1e-6)
        def squash(f): return q_on + (wco - q_on) * f
    ca = me.color_attributes.new("PinWeights", 'FLOAT_COLOR', 'POINT')
    for i in range(len(me.vertices)): ca.data[i].color = (float(r[i]), float(g[i]), float(b[i]), 1.0)
    me.color_attributes.active_color = ca; me.color_attributes.render_color_index = list(me.color_attributes).index(ca)
    ob.shape_key_add(name="Basis", from_mix=False)
    for name, f in (("Furled", 0.05), ("Reefed", 0.6)):
        sk = ob.shape_key_add(name=name, from_mix=False); q = squash(f); lq = (np.c_[q, np.ones(len(q))] @ inv.T)[:, :3]
        for i, p in enumerate(lq): sk.data[i].co = (float(p[0]), float(p[1]), float(p[2]))
def set_origin(ob, p):
    p = Vector(p); ob.data.transform(Matrix.Translation(-(p - ob.matrix_basis.translation)))   # world verts stay put
    mb = ob.matrix_basis.copy(); mb.translation = p; ob.matrix_basis = mb
for nm, mode in (("Sail_Spanker", "main"), ("Sail_Jib", "head")):
    ob = O[nm]
    if mode == "head":                                           # headsails swing about their stay: the node origin is the tack
        _, wco = sail_data(ob); set_origin(ob, wco[np.argmin(wco[:, 1])])
    attach_weights_and_shapes(ob, mode)
L("sails done")

# ---- markers (game_role props as the brig's)
def side_fix(name, x):
    lab = "Port" if "Port" in name else ("Stbd" if "Stbd" in name else None)
    if lab is None: return name
    actual = "Port" if x > 0 else "Stbd"        # Blender +X is the ship's port side (bow is -Y)
    return name if lab == actual else name.replace(lab, "@").replace("Port" if lab == "Stbd" else "Stbd", lab).replace("@", actual)
RENAME = {"Station_Sheet_Main": "Station_Sheet_Spanker", "Station_Halyard_Main": "Station_Halyard_Spanker", "Station_Pump": "Station_Pump_01"}
def props_for(n, x):
    if n.startswith("SinkCheck_"): return {"type": "sink_check", "trigger_seconds": 5.0, "rule": "water over the rail for about 5 s = ship lost, reset to last save", "game_role": "sink_check"}
    if n == "CamPos_Compass": return {"type": "camera", "pair": "CamTarget_Compass", "game_role": "camera_marker"}
    if n == "CamTarget_Compass": return {"type": "camera_target", "game_role": "camera_marker"}
    if n == "Station_Tiller": return {"type": "helm", "item": "Tiller", "game_role": "station"}
    if n == "Station_Sheet_Spanker": return {"type": "sheet", "sail": "Spanker", "game_role": "station"}
    if n == "Station_Halyard_Spanker": return {"type": "halyard", "sail": "Spanker", "game_role": "station"}
    if n.startswith("Station_Halyard_Jib"): return {"type": "halyard", "sail": "Jib", "game_role": "station"}
    if n.startswith("Station_Sheet_Jib"): return {"type": "sheet", "sail": "Jib", "side": "port" if n.endswith("Port") else "stbd", "game_role": "station"}
    if n.startswith("Station_Sheet_Staysail"): return {"type": "sheet", "sail": "ForeStaysail", "side": "port" if n.endswith("Port") else "stbd", "game_role": "station"}
    if n == "Station_Gun": return {"type": "gun", "gun": "Gun_0", "side": "port" if x > 0 else "stbd", "game_role": "station"}
    if n == "Station_Pump_01": return {"type": "pump", "pump": "Pump", "game_role": "station"}
    if n == "Station_LogLine": return {"type": "log_line", "note": "knotted log line goes over the stern rail", "game_role": "station"}
    if n == "Station_Mooring": return {"type": "mooring", "game_role": "station"}
    if n == "Station_Bed": return {"type": "bed", "game_role": "station"}
    if n == "LogLine": return {"type": "log_line", "note": "coil of rope on the deck; LogLine_P0..P4 are the path the line takes over the stern rail", "interaction": "log_line"}
    if n == "HoldBounds": return {"game_role": "hold_bounds"}
    if n == "Climb_Hold_Bottom": return {"game_role": "climb_point", "point_id": "hold_bottom", "mast": "none"}
    if n == "Climb_Hold_Top": return {"game_role": "climb_point", "point_id": "hold_top", "mast": "none"}
    return {}
made_markers = []
def add_marker(name, loc, kind='PLAIN_AXES', size=0.25, scale=(1, 1, 1), rot=None, srcprops=None):
    e = newobj(name, None); e.empty_display_type = kind; e.empty_display_size = size; e.location = loc; e.scale = scale
    if rot is not None: e.rotation_euler = rot
    e.parent = root; exp.objects.link(e); setprops(e, srcprops or {}); setprops(e, props_for(name, loc[0])); made_markers.append(name); return e
for name, loc, kind, size, scale, rot, cprops in stations:
    if name == "CabinBookshelf": continue                         # the shelf node above
    if name.startswith(("Ladder_", "Climb_")): continue            # climbing zones and points live in scenes/ships/cutter.tscn (editable Area3Ds), not in the glb
    nn = side_fix(RENAME.get(name, name), loc.x); add_marker(nn, loc, kind, size, tuple(scale), rot, cprops)
for i, p in enumerate([(0.6, 4.2, 0.43), (1.0, 5.25, 1.60), (1.0, 5.7, 1.45), (1.0, 5.9, 1.05), (1.0, 6.0, 0.65)]): add_marker("LogLine_P%d" % i, p)
lt = bpy.data.lights.new("LT_Lamp_Cabin_0", 'POINT'); lt.energy = 40.0
lo = newobj("LT_Lamp_Cabin_0", lt); lo.location = (0.0, 0.3, 1.15); lo.parent = root; exp.objects.link(lo)
setprops(lo, {"godot_energy": 1.2, "godot_range": 5.0, "godot_shadow": True, "blender_watts": 40.0, "game_role": "light"})
L("markers: %s" % sorted(made_markers))

# ---- collision (Godot turns "-colonly" / "-convcolonly" into StaticBody3D shapes; brig_import.gd moves them onto the moving ship bodies)
def col_obj(name, me):
    ob = newobj(name, me); ob.parent = root; exp.objects.link(ob); ob["game_role"] = "collision"; return ob
col_obj("Col_Floors-colonly", make_mesh(floors, "Col_Floors", with_mats=False))
col_obj("Col_Walls-colonly", make_mesh(walls, "Col_Walls", with_mats=False))
bm = bmesh.new(); vs = [bm.verts.new(v) for v in accs["Hull"].verts]
bmesh.ops.convex_hull(bm, input=vs); bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
me = bpy.data.meshes.new("Col_HullShape"); bm.to_mesh(me); bm.free(); col_obj("Col_HullShape-convcolonly", me)
bm = bmesh.new()
def add_box(lo_, hi_):
    c = (lo_ + hi_) / 2; s = hi_ - lo_
    r = bmesh.ops.create_cube(bm, size=1.0)
    for v in r["verts"]: v.co = (v.co.x * s.x + c.x, v.co.y * s.y + c.y, v.co.z * s.z + c.z)
for n, (lo_, hi_) in boxes.items(): add_box(lo_, hi_)
add_box(Vector((-0.17, -1.86, -1.2)), Vector((0.17, -1.38, 3.0)))             # the mast (it rakes aft a little), as far up as anyone reaches
me = bpy.data.meshes.new("Col_Obstacles"); bm.to_mesh(me); bm.free(); col_obj("Col_Obstacles-colonly", me)

# ---- drop everything that is not part of the export
keep_set = set(exp.objects)
for o in list(O):
    if o not in keep_set: bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c is not exp: bpy.data.collections.remove(c)
bpy.data.orphans_purge(do_recursive=True)
for ob, nm in FINAL: ob.name = nm
bad = [(ob.name, nm) for ob, nm in FINAL if ob.name != nm]
L("name collisions after rename: %s" % bad)
bpy.ops.wm.save_as_mainfile(filepath=OUT); L("saved " + OUT); print("OK build", OUT)
