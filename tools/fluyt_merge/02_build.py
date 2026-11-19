"""02_build.py  -  materials-ready fluyt -> merged game meshes, game-named parts, markers, collision, sails.
Follows tools/schooner_merge/02_build.py (node names + glTF extras that brig_import.gd and the game scripts read). Read first, then create
(Blender 4.1 crashes if objects are evaluated after the scene changed). The source is never modified (runs on c1_materials.blend).
Frame: Blender bow is -Y, +Z up, +X = PORT (the ship frame in Godot is x -> -x, y -> z, z -> y). Side words in names follow the x sign."""
import bpy, bmesh, os, json, math, re
import numpy as np
from mathutils import Vector, Matrix
PROJ = os.environ["FLUYT_PROJECT"]; OUT = os.environ["MERGE_OUT"]; GLB = os.environ["GLB_OUT"]
O = bpy.data.objects
LOG = open(os.path.join(PROJ, "tools", "fluyt_merge", "stage2_log.txt"), "w", encoding="utf-8")
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
def make_mesh(acc, name, with_mats=True, origin=None):
    off = Vector(origin) if origin is not None else Vector((0, 0, 0))
    me = bpy.data.meshes.new(name); me.from_pydata([(v[0]-off.x, v[1]-off.y, v[2]-off.z) for v in acc.verts], [], acc.faces)
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
def world_verts(o):
    me = o.data; n = len(me.vertices); co = np.empty(n*3, dtype=np.float32); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    return (np.c_[co, np.ones(n, dtype=np.float32)] @ np.array(o.matrix_world).T)[:, :3]
def side_of(x): return "Port" if x > 0 else "Stbd"             # bow is -Y, so Blender +X is the ship's port side
def side_fix(name, x):
    lab = "Port" if "Port" in name else ("Stbd" if "Stbd" in name else None)
    return name if lab is None else name.replace(lab, side_of(x))

# ------------------------------------------------------------------ what goes where
SPARS = ["Foremast", "Mainmast", "Mizzenmast", "ForeTopmast", "MainTopmast", "Bowsprit", "BowspritBand", "ForeTop", "MainTop", "MastBands", "MastCheeks", "Flags", "Gammoning"]
ROPES = ["Rigging", "Ratlines", "Backstays", "Bobstays", "FuttockShrouds", "Lanyards", "Deadeyes", "Coils", "AnchorCables"]
GLASS = ["BinnacleLampGlass", "CabinLampGlass", "CabinLanternGlass", "CabinWindows", "SternLanternGlass"]
HULL = ["Hull", "HullPlanking", "StemKeel", "Deadwood", "Wales", "Channels", "Chainplates", "TransomGilt", "BowScroll", "CapRail", "TopRails", "Waterway",
        "BulwarkStanchions", "CabinWindowFrames", "SternLanternPosts", "SternLanterns", "Catheads", "CatheadSheaves", "RudderGudgeons", "QuarterRailing", "QuarterBalusters", "Anchors"]
DECK = ["Deck", "Forecastle_Deck", "Quarterdeck", "CabinFloor", "HoldFloor", "LowerDeckFloor", "LowerSteps", "QuarterStairs", "DeckSeams"]
INTERIOR = ["CabinBeams", "CabinBooksFiller", "CabinBookshelf_Fillers", "CabinChest", "CabinDoorFrame", "CabinDoorFrames", "CabinLamps", "CabinLantern", "CabinLining",
            "CabinPartition_Port", "CabinPartition_Stbd", "ChartTable", "HallBulkhead", "HallWall_Port", "HallWall_Stbd", "HoldKeelson", "HoldRibs", "LowerDeckBalusters",
            "LowerDeckFront", "LowerDeckRail", "RoomAftWall", "RoomBeams", "RoomLining", "DeckBeams", "Quarterdeck_Bulkhead", "Forecastle_Bulkhead"]
INTERIOR += [n for n in O.keys() if n.startswith(("Bunk", "RoomTable_"))]
GROUPS = {"Hull": HULL, "MainDeck": DECK, "Interiors": INTERIOR, "Rig_Spars": SPARS, "Rig_Ropes": ROPES, "Glass": GLASS, "DeckFittings": []}
ROLE = {"Hull": "static", "MainDeck": "static", "DeckFittings": "static", "Rig_Spars": "static", "Rig_Ropes": "static", "Interiors": "static", "Glass": "glass"}
VIS = {"Interiors": (0.0, 35.0), "Rig_Ropes": (0.0, 150.0)}
# separate game nodes (old name -> final name, props)
KEEP = [
 ("Rudder", "Rudder", {"game_role": "rudder", "vis_begin": 0.0, "vis_end": 60.0}),
 ("Wheel", "Wheel", {"game_role": "wheel", "vis_begin": 0.0, "vis_end": 60.0}),
 ("BinnacleGlass", "BinnacleGlass", {"interaction": "compass"}),
 ("CabinBed", "CabinBed", {"interaction": "bed"}), ("CabinBedding", "CabinBedding", {"interaction": "bed"}), ("Chart", "TableChart", {"interaction": "chart"}),
 ("Pump_Brake", "Pump_Brake", {}), ("Pump_Body", "Pump_Body", {}),
 ("LogLine_Coil", "LogLine_Coil", {"interaction": "log_line", "vis_begin": 0.0, "vis_end": 35.0}),
]
TREES = ["HammockSet_Port", "HammockSet_Stbd", "HammockSet_Stbd.001"]
SET_NEW = {"HammockSet_Port": "HammockSet_0", "HammockSet_Stbd": "HammockSet_1", "HammockSet_Stbd.001": "HammockSet_2"}
BOOKS = [n for n in O.keys() if n.startswith("Book_")]
# yards: (old name, mast, level, mast mesh used to find the axis (None = keep the origin as it is))
YARDS = [("Yard_Fore_0", "fore", "course", "Foremast"), ("Yard_Fore_1", "fore", "topsail", "ForeTopmast"),
         ("Yard_Main_0", "main", "course", "Mainmast"), ("Yard_Main_1", "main", "topsail", "MainTopmast"),
         ("Yard_Mizzen", "mizzen", "lateen", None), ("Yard_Sprit", "sprit", "spritsail", None)]
SAILS = {"Sail_Fore_0": ("Yard_Fore_0", "square", True), "Sail_Fore_1": ("Yard_Fore_1", "square", True),
         "Sail_Main_0": ("Yard_Main_0", "square", True), "Sail_Main_1": ("Yard_Main_1", "square", True),
         "Sail_Mizzen": ("Yard_Mizzen", "lateen", False), "Sail_Sprit": ("Yard_Sprit", "square", False)}
EXCLUDE = {"Sea_Preview", "Sandglass"}                           # the game builds its own sand glass; the sea preview is a viewport aid
BOX_OBJECTS = ["Capstan", "Windlass", "Pump_Body", "Binnacle", "WheelStand", "ChartTable", "CabinChest", "CabinBookshelf_Frame", "CabinBookshelf_Frame_R"] + \
              [n for n in O.keys() if n.startswith(("Bunk_", "RoomTable_")) and "Bedding" not in n]
FLOORS = ["Deck", "Forecastle_Deck", "Quarterdeck", "CabinFloor", "HoldFloor", "LowerDeckFloor", "LowerSteps", "QuarterStairs"]
WALLS = ["Hull", "Quarterdeck_Bulkhead", "Forecastle_Bulkhead", "CabinPartition_Port", "CabinPartition_Stbd", "HallBulkhead", "HallWall_Port", "HallWall_Stbd",
         "RoomAftWall", "LowerDeckFront", "HatchCoaming", "QuarterRailing", "LowerDeckRail"]

# ================================================================== READ (everything that needs evaluation)
worlds_all = {o.name: o.matrix_world.copy() for o in O}
used = set(EXCLUDE) | {k[0] for k in KEEP} | set(BOOKS) | {"CabinBookshelf_Frame", "CabinBookshelf_Frame_R", "BinnacleCard"}
used |= {y[0] for y in YARDS} | set(SAILS)
for r in TREES: used.add(r); used |= {c.name for c in O[r].children_recursive}
used |= {o.name for o in O if o.name.startswith(("Rope_", "Seams_Sail", "Boltrope_Sail", "ClewIrons_Sail"))}
assigned = set(); accs = {g: Acc() for g in GROUPS}
for g, names in GROUPS.items():
    for n in names:
        if n in O and n not in used and n not in assigned: add_obj(accs[g], O[n]); assigned.add(n)
for o in O:                                            # everything else that is a mesh: deck fittings (log it)
    if o.type == 'MESH' and o.name not in used and o.name not in assigned:
        add_obj(accs["DeckFittings"], o); assigned.add(o.name); L("DeckFittings (default): " + o.name)
walls, floors = Acc(), Acc()
for n in WALLS:
    if n in O: add_obj(walls, O[n])
for n in FLOORS:
    if n in O: add_obj(floors, O[n])
boxes = {n: wbox(O[n]) for n in BOX_OBJECTS if n in O}
def tree_box(name):
    pts = [c.matrix_world @ Vector(q) for c in O[name].children_recursive if c.type == "MESH" and "Frame" in c.name for q in c.bound_box]
    return Vector((min(q.x for q in pts), min(q.y for q in pts), min(q.z for q in pts))), Vector((max(q.x for q in pts), max(q.y for q in pts), max(q.z for q in pts)))
for _i, _t in enumerate(TREES): boxes["Hammock_%d" % _i] = tree_box(_t)
# masts: a box from the hold to the quarterdeck round each, at the mast foot's footprint
def mast_box(name, z0=-1.2, z1=4.6):
    w = world_verts(O[name]); w = w[w[:, 2] < w[:, 2].min() + 3.5]
    L("mast box %s: x %.2f..%.2f y %.2f..%.2f (%d verts)" % (name, w[:, 0].min(), w[:, 0].max(), w[:, 1].min(), w[:, 1].max(), len(w)))
    return Vector((w[:, 0].min(), w[:, 1].min(), z0)), Vector((w[:, 0].max(), w[:, 1].max(), z1))
mast_boxes = [mast_box(n) for n in ("Foremast", "Mainmast", "Mizzenmast")]
rail_boxes = []
# ---- yards: origin on the mast axis (so a braced yard turns about the mast)
yard_origin = {}
for yn, mast, lvl, mm in YARDS:
    yo = worlds_all[yn].translation.copy()
    if mm:
        w = world_verts(O[mm]); sel = w[np.abs(w[:, 2] - yo.z) < 0.35]
        if len(sel): yo = Vector((0.0, float((sel[:, 1].min() + sel[:, 1].max()) / 2), yo.z))
    yard_origin[yn] = yo; L("yard %s origin %s (was %s)" % (yn, tuple(round(v, 3) for v in yo), tuple(round(v, 3) for v in worlds_all[yn].translation)))
accY = {}
for yn, *_ in YARDS: a = Acc(); add_obj(a, O[yn]); accY[yn] = a
# ---- sails (cloth + seams + boltrope + clew irons in one mesh, so they billow together)
accS = {}; sailw = {}
for sn, (yn, mode, reef) in SAILS.items():
    a = Acc(); add_obj(a, O[sn])
    for pre in ("Seams_", "Boltrope_", "ClewIrons_"):
        if pre + sn in O: add_obj(a, O[pre + sn])
    accS[sn] = a
    L("sail %s: %d verts %d faces, mats %s" % (sn, len(a.verts), len(a.faces), [m.name if m else None for m in a.mats]))
# ---- waterline half-beam (for the ship's physics)
dg = bpy.context.evaluated_depsgraph_get(); sc = bpy.context.scene; wl = []
for i in range(52):
    y = -13.0 + 0.5 * i; hx = 0.0; org = Vector((5.0, y, 0.0))
    for _ in range(5):
        ok, loc, nrm, idx, ob, mw = sc.ray_cast(dg, org, Vector((-1, 0, 0)), distance=10.0)
        if not ok: break
        if ob.name == "Hull": hx = abs(loc.x); break
        org = loc + Vector((-0.01, 0, 0))
    wl.append(round(hx, 3))
L("waterline half beam: %s" % wl)
stations = []
for c in bpy.data.collections["Fluyt_Stations"].objects:
    cp = {k: (list(c[k]) if hasattr(c[k], '__len__') and not isinstance(c[k], str) else c[k]) for k in c.keys() if not k.startswith('_')}
    stations.append((c.name, c.matrix_world.translation.copy(), c.empty_display_type, c.empty_display_size, c.scale.copy(), c.rotation_euler.copy(), cp))
cacc = Acc(); add_obj(cacc, O["BinnacleCard"]); card_origin = Vector((0.0, 5.775, 4.895))      # the game spins the node called Compass_Card
rope_info = {}
for o in O:
    if o.name.startswith("Rope_") and o.type == 'MESH':
        end = "RopeEnd_" + o.name[len("Rope_"):]
        if end in O: rope_info[o.name] = (end, (worlds_all[end].translation - worlds_all[o.name].translation).length)
for o in O:
    if o.animation_data: o.animation_data_clear()
L("READ done: %s" % {g: len(a.faces) for g, a in accs.items()})

# ================================================================== CREATE
exp = bpy.data.collections.new("Fluyt_Export"); bpy.context.scene.collection.children.link(exp)
FINAL = []
def newobj(name, data):
    ob = bpy.data.objects.new(name + "__new", data); FINAL.append((ob, name)); return ob
def rename(ob, final): ob.name = "~" + final; FINAL.append((ob, final))
ident = Matrix.Identity(4)
root = newobj("Fluyt", None); exp.objects.link(root)
for _k, _v in ({"game_role": "ship_root", "ship_class": "fluyt", "ship_tier": "large", "length_on_deck_m": 22.0, "guns": 0, "crew_min": 8, "crew_max": 13,
                "bow_axis_blender": "-Y", "bow_axis_godot": "+Z (rotate 180 deg about Y for -Z forward)", "waterline_z": 0.0, "main_deck_z_midships": 2.0,
                "poop_deck_z": 4.0, "lower_deck_z": -0.27, "hold_floor_z": -1.78, "source_file": "FluytShip.blend",
                "waterline_half_beam": wl, "waterline_y_min": -13.0, "waterline_y_step": 0.5}).items(): root[_k] = _v
def link(ob):
    for c in list(ob.users_collection): c.objects.unlink(ob)
    exp.objects.link(ob)
def put(ob, parent=None):
    link(ob); ob.parent = parent or root; ob.matrix_parent_inverse = ident
def setprops(ob, props):
    for k, v in (props or {}).items(): ob[k] = v
for g, acc in accs.items():
    me = make_mesh(acc, g); ob = newobj(g, me); put(ob); setprops(ob, {"game_role": ROLE[g]})
    if g in VIS: setprops(ob, {"vis_begin": VIS[g][0], "vis_end": VIS[g][1]})
    L("GROUP %s: %d faces, %d materials" % (g, len(me.polygons), len(me.materials)))
# ---- pump
pump_root = newobj("Pump", None); put(pump_root); setprops(pump_root, {"type": "pump", "brake_pivot_axis": "x", "crew_per_pump": 2, "interaction": "pump"})
for old, new, props in KEEP:
    ob = O.get(old)
    if ob is None: L("MISSING keep " + old); continue
    link(ob); ob.parent = pump_root if old in ("Pump_Brake", "Pump_Body") else root
    ob.matrix_parent_inverse = ident; ob.matrix_basis = worlds_all[old]; rename(ob, new); setprops(ob, props)
# ---- hammock sets: renamed by set (all three stand on the centre line), pivots and slots described for the game
for k, rn in enumerate(TREES):
    r = O[rn]; kids = list(r.children_recursive); new = SET_NEW[rn]
    link(r); r.parent = root; r.matrix_parent_inverse = ident; r.matrix_basis = worlds_all[rn]
    for ob in [r] + kids:
        if ob is not r: link(ob)
        nm = re.sub(r"\.\d{3}$", "", ob.name).replace(rn.replace(".001", ""), new)
        rename(ob, nm)
        if ob is r: setprops(ob, {"game_role": "hammock_set"})
        elif ob.type == 'EMPTY' and "_Hammock_" in nm: setprops(ob, {"game_role": "hammock", "hammock_index": "ABC".index(nm[-1]), "swing_axis": "local_y"})
# ---- the shelves (frame nodes stay separate so the shelf can be aimed at and outlined) and the books
shelf = O["CabinBookshelf"]; link(shelf); shelf.parent = root; shelf.matrix_parent_inverse = ident; shelf.matrix_basis = worlds_all["CabinBookshelf"]; setprops(shelf, {"interaction": "bookshelf"})
for fn in ("CabinBookshelf_Frame", "CabinBookshelf_Frame_R"):
    f = O[fn]; link(f); f.parent = shelf; f.matrix_parent_inverse = worlds_all["CabinBookshelf"].inverted(); f.matrix_basis = ident
    f.matrix_parent_inverse = worlds_all["CabinBookshelf"].inverted(); f.matrix_basis = worlds_all[fn]
for n in BOOKS:
    b = O[n]; link(b)
    setprops(b, {"interaction": "logbook" if n == "Book_Logbook" else "book", "book_id": "logbook" if n == "Book_Logbook" else n[len("Book_"):].lower()})
# ---- yards
NEWY = {}
for yn, mast, lvl, mm in YARDS:
    me = make_mesh(accY[yn], yn, origin=yard_origin[yn]); y = newobj(yn, me); y.location = yard_origin[yn]; put(y)
    setprops(y, {"game_role": "yard", "mast": mast, "yard_level": lvl}); NEWY[yn] = y
cm_ = make_mesh(cacc, "Compass_Card", origin=card_origin); cc_ = newobj("Compass_Card", cm_); cc_.location = card_origin; put(cc_)
# ---- sails: PinWeights (r billow, g height head=0..foot=1, b across), Furled / Reefed shape keys, origin on the yard
def attach(ob, wco, origin, mode, reef):
    me = ob.data; nv = len(wco); loc = wco - np.array(origin)
    x0, x1 = wco[:, 0].min(), wco[:, 0].max(); zmin, zmax = wco[:, 2].min(), wco[:, 2].max()
    if mode == "square":
        g = np.clip((zmax - wco[:, 2]) / max(zmax - zmin, 1e-6), 0, 1); b = np.clip((wco[:, 0] - x0) / max(x1 - x0, 1e-6), 0, 1)
        r = np.sin(np.pi * b) ** 0.7 * np.clip(g * 3.0, 0, 1) * (1.0 - 0.35 * g * g)
        def squash(f): q = wco.copy(); q[:, 2] = zmax - (zmax - wco[:, 2]) * f; return q
    else:
        ymin = wco[:, 1].min(); tack = wco[np.argmin(wco[:, 1])]; head = wco[np.argmax(wco[:, 2])]; ax = head - tack; ln2 = float(ax @ ax)
        t = np.clip(((wco - tack) @ ax) / ln2, 0.0, 1.0); q_on = tack + t[:, None] * ax
        d = np.linalg.norm(wco - q_on, axis=1); g = 1.0 - t; b = d / max(d.max(), 1e-6)
        r = np.clip((wco[:, 0] - x0) / max(x1 - x0, 1e-6), 0, 1)
        def squash(f): return q_on + (wco - q_on) * f
    ca = me.color_attributes.new("PinWeights", 'FLOAT_COLOR', 'POINT')
    for i in range(nv): ca.data[i].color = (float(r[i]), float(g[i]), float(b[i]), 1.0)
    me.color_attributes.active_color = ca; me.color_attributes.render_color_index = list(me.color_attributes).index(ca)
    ob.shape_key_add(name="Basis", from_mix=False)
    for name, f in (("Furled", 0.05), ("Reefed", 0.6)):
        if name == "Reefed" and not reef: continue
        sk = ob.shape_key_add(name=name, from_mix=False); q = squash(f) - np.array(origin)
        for i, p in enumerate(q): sk.data[i].co = (float(p[0]), float(p[1]), float(p[2]))
NEWS = {}
for sn, (yn, mode, reef) in SAILS.items():
    a = accS[sn]; org = yard_origin[yn]
    # the cloth's own vertex count may shrink when loose vertices are dropped: build, then read the vertices back in world space
    me = make_mesh(a, sn, origin=org); s = newobj(sn, me); put(s, NEWY[yn]); s.matrix_basis = Matrix.Identity(4)
    wco = np.array([(v.co.x + org.x, v.co.y + org.y, v.co.z + org.z) for v in me.vertices])
    attach(s, wco, org, mode, reef)
    setprops(s, {"game_role": "sail", "reefable": reef, "sail_kind": mode if mode == "square" else "lateen"}); NEWS[sn] = s
# ---- running rigging parts that move with the yards and sails: the rope (origin at its fixed end) and the end marker on the part it ties to
for rn, (en, ln) in rope_info.items():
    ro = O[rn]; eo = O[en]
    for ob, role in ((ro, "rope_rig"), (eo, "rope_end")):
        p = ob.parent
        newp = NEWY.get(p.name) or NEWS.get(p.name) if p else None
        if newp is None: L("rope part %s: parent %s not exported, put on the root" % (ob.name, p.name if p else None)); newp = root; pw = ident
        else: pw = Matrix.Translation(yard_origin[p.name if p.name in NEWY else SAILS[p.name][0]])
        link(ob); ob.parent = newp; ob.matrix_parent_inverse = ident; ob.matrix_basis = pw.inverted() @ worlds_all[ob.name]
        setprops(ob, {"game_role": role, "end": en, "rope_len": round(ln, 4)} if role == "rope_rig" else {"game_role": role})
# ---- markers
SAILID = {"Fore_Course": "Sail_Fore_0", "Fore_Topsail": "Sail_Fore_1", "Main_Course": "Sail_Main_0", "Main_Topsail": "Sail_Main_1", "Mizzen": "Sail_Mizzen", "Sprit": "Sail_Sprit"}
def props_for(n, x):
    if n.startswith("SinkCheck_"): return {"type": "sink_check", "trigger_seconds": 5.0, "rule": "water over the rail for about 5 s = ship lost, reset to last save", "game_role": "sink_check"}
    if n in ("CamPos_Compass", "CamPos_LogLine"): return {"type": "camera", "pair": n.replace("CamPos", "CamTarget"), "game_role": "camera_marker"}
    if n in ("CamTarget_Compass", "CamTarget_LogLine"): return {"type": "camera_target", "game_role": "camera_marker"}
    if n == "Station_Wheel": return {"type": "helm", "item": "Wheel", "game_role": "station"}
    if n.startswith("Station_Brace_"):
        mast = n.split("_")[2]; return {"type": "brace", "yards": "Yard_" + mast, "side": "port" if x > 0 else "stbd", "game_role": "station"}
    if n.startswith("Station_Halyard_"):
        k = n[len("Station_Halyard_"):]; d = {"type": "halyard", "sail": SAILID.get(k, k), "game_role": "station"}
        if k.startswith("Fore"): d["mast"] = "fore"
        elif k.startswith("Main"): d["mast"] = "main"
        elif k.startswith("Mizzen"): d["mast"] = "mizzen"
        return d
    if n == "Station_Sheet_Mizzen": return {"type": "sheet", "sail": "Sail_Mizzen", "game_role": "station"}
    if n.startswith("Station_Capstan_"): return {"type": "anchor", "item": "Capstan", "game_role": "station"}
    if n == "Station_Windlass": return {"type": "anchor", "item": "Windlass", "game_role": "station"}
    if n.startswith("Station_Pump_"): return {"type": "pump", "pump": "Pump", "game_role": "station"}
    if n == "Station_LogLine": return {"type": "log_line", "note": "knotted log line goes over the stern rail", "game_role": "station"}
    if n == "Station_Mooring": return {"type": "mooring", "game_role": "station"}
    if n in ("Station_Bed",) or n.startswith("Station_Cabin_Bed_"): return {"type": "bed", "game_role": "station"}
    if n == "LogLine": return {"type": "log_line", "note": "coil of rope on the quarterdeck; LogLine_P0..P4 are the path the line takes over the stern rail", "interaction": "log_line"}
    if n == "HoldBounds": return {"game_role": "hold_bounds"}
    return {}
made_markers = []
def add_marker(name, loc, kind='PLAIN_AXES', size=0.25, scale=(1, 1, 1), rot=None, srcprops=None, extra=None):
    e = newobj(name, None); e.empty_display_type = kind; e.empty_display_size = size; e.location = loc; e.scale = scale
    if rot is not None: e.rotation_euler = rot
    e.parent = root; exp.objects.link(e); setprops(e, srcprops or {}); setprops(e, props_for(name, loc[0])); setprops(e, extra or {})
    if "side" in e.keys(): e["side"] = "port" if loc[0] > 0 else "stbd"
    made_markers.append(name); return e
LIGHTS = {"Light_Cabin": ("LT_Lamp_Cabin_0", 1.2, 5.5, True), "Light_Hall_0": ("LT_Lamp_Hall_0", 0.9, 3.8, False), "Light_Hall_1": ("LT_Lamp_Hall_1", 0.9, 3.8, False),
          "Light_SternLantern_Port": ("LT_Lamp_Stern_0", 0.7, 6.0, False), "Light_SternLantern_Stbd": ("LT_Lamp_Stern_1", 0.7, 6.0, False)}
for name, loc, kind, size, scale, rot, cprops in stations:
    if name in ("Compass", "Station_Sandglass", "CabinBookshelf") or name.startswith(("Climb_", "Ladder_", "RopeEnd_", "HammockSlot_")): continue
    if name.startswith("Light_"):
        if name.startswith("Light_Cabin_"): ln = "LT_Lamp_Room_%s_%s" % (side_of(loc.x), name[-1]); en, rg, sh = 0.8, 3.5, False
        elif name in LIGHTS: ln, en, rg, sh = LIGHTS[name]
        else: L("light not mapped: " + name); continue
        lt = bpy.data.lights.new(ln, 'POINT'); lt.energy = 40.0
        lo = newobj(ln, lt); lo.location = loc; lo.parent = root; exp.objects.link(lo)
        setprops(lo, {"godot_energy": en, "godot_range": rg, "godot_shadow": sh, "blender_watts": 40.0, "game_role": "light"}); made_markers.append(ln); continue
    nn = side_fix(name, loc.x) if name.startswith(("Station_", "SinkCheck_")) else name
    add_marker(nn, loc, kind, size, tuple(scale), rot, cprops)
for k, rn in enumerate(TREES):
    p = worlds_all[rn].translation
    add_marker("HammockSlot_%02d" % k, (p.x, p.y, p.z), 'ARROWS', 0.3, extra={"slot_index": k, "side": "centre", "hammocks": 3, "module": "HammockSet", "occupied_by": SET_NEW[rn], "game_role": "hammock_slot"})
# ---- collision
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
for lo_, hi_ in mast_boxes: add_box(lo_, hi_)
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
L("markers: %s" % sorted(made_markers))
bpy.ops.wm.save_as_mainfile(filepath=OUT); L("saved " + OUT); print("OK build", OUT)
