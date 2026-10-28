
import bpy, os, sys, json, time, math
WORK = os.path.join(os.environ["BRIG_PROJECT"], "tools", "brig_merge")
exec(open(os.path.join(WORK, "merge_lib.py")).read(), globals())
LOG = open(os.path.join(WORK, "stage2_log.txt"), "a", encoding="utf-8")
def L(m): LOG.write(m + "\n"); LOG.flush(); os.fsync(LOG.fileno())
OUT = os.environ["MERGE_OUT"]; GAME = os.path.join(WORK, "source", "MerchantBrigShipGame_source.blend")
O = bpy.data.objects; XF = META["xf"]; PR = META["props"]
L(f"=== stage2 start {time.strftime('%H:%M:%S')} file={bpy.data.filepath}")
def objs(names): return [O[n] for n in names if n in O and O[n].type == 'MESH']
# ------------------------------------------------ phase A: read/bake sources (scene untouched) ------------------------------------------------
A_ = {}
def read(key, items, **kw):
    acc = Acc()
    for o, flt in items:
        L(f"READ {key}: {o.name}"); add_obj(acc, o, **({} if flt is None else flt))
    A_[key] = acc; L(f"READ {key}: verts={len(acc.verts)} faces={len(acc.faces)}")
read("Rudder", [(o, None) for o in objs(G["Rudder"])])
read("Wheel",  [(o, None) for o in objs(G["Wheel"])])
read("Door_Cabin", [(O["CabinDoorLeaf"], None)])
read("Door_Room_Port", [(O["RoomDoorLeaves"], {"face_filter": lambda c: c[0] < 0})])
read("Door_Room_Stbd", [(O["RoomDoorLeaves"], {"face_filter": lambda c: c[0] > 0})])
for i in range(6):
    read(f"Gun_{i}", [(O[f"GunCarriage{i}"], None), (O[f"GunTrucks{i}"], None), (O[f"Breeching{i}"], None)])
    read(f"Gun_{i}_Barrel", [(O[f"GunBarrel{i}"], None)])
by_yard = {}
for key, parts in A.items():
    if not key.startswith("Yard_"): continue
    per = {}
    for p in parts:
        _, src, idx = p.split("__"); per.setdefault(src, set()).add(int(idx))
    by_yard[key] = per
    read(key, [(O[src], {"island_ok": (lambda i, s=s: i in s)}) for src, s in per.items() if src in O])
read("ProvisionsSlate", [(O["ProvisionsSlate"], None)])
# spanker spars: boom (low) and gaff (high) with their jaws, blocks and the lines strung between them (islands from game_spanker.json)
SP = json.load(open(os.path.join(WORK, "game_spanker.json")))
for part in ("Boom", "Gaff"):
    read(f"Spanker_{part}", [(O[src], {"island_ok": (lambda i, s=set(d[part.lower()]): i in s)}) for src, d in SP.items() if d.get(part.lower())])
# ------------------------------------------------ phase B: create ------------------------------------------------
exp = coll("Brig_Export"); root = O["Brig"]
def put(name, key, origin, rot_z, parent, props):
    me = make_mesh(A_[key], name, origin=origin, rot_z=rot_z); ob = make_obj(name, me, loc=tuple(origin), rot_z=rot_z, parent=parent, props=props)
    L(f"MADE {name}: verts={len(me.vertices)} tris={tris(me)} at {tuple(round(v,2) for v in origin)} mats={[m.name if m else None for m in me.materials]}"); return ob
put("Rudder", "Rudder", XF["Rudder"][0], 0.0, root, {"game_role": "rudder", "vis_begin": 0.0, "vis_end": 60.0})
put("Wheel", "Wheel", XF["Wheel"][0], 0.0, root, {"game_role": "wheel", "vis_begin": 0.0, "vis_end": 60.0})
for n in ("Door_Cabin", "Door_Room_Port", "Door_Room_Stbd"): put(n, n, XF[n][0], 0.0, root, {"game_role": "door", "vis_begin": 0.0, "vis_end": 35.0})
for i in range(6):
    rz = math.radians(180.0) if i < 3 else 0.0; g = put(f"Gun_{i}", f"Gun_{i}", XF[f"Gun_{i}"][0], rz, root, {"game_role": "gun", "gun_index": i, "side": "port" if i < 3 else "starboard"})
    bw = XF[f"Gun_{i}_Barrel"][0]; b = put(f"Gun_{i}_Barrel", f"Gun_{i}_Barrel", bw, rz, g, {"game_role": "gun_barrel"}); b.location = (0, 0, bw[2] - XF[f"Gun_{i}"][0][2]); b.rotation_euler = (0, 0, 0)
lvl = {"0": "course", "1": "topsail", "2": "topgallant"}; yards = {}
for key in by_yard:
    mast = "fore" if "Fore" in key else "main"
    yards[key] = put(key, key, XF[key][0], 0.0, root, {"game_role": "yard", "mast": mast, "yard_level": lvl[key[-1]]})
bpy.data.meshes.remove(bpy.data.meshes.new("x"))
# the spanker spars hang off the mainmast axis (Blender y 1.6): Godot (ship_sails.gd _scan_spanker_parts) finds them by name and swings them with the sail
for part in ("Boom", "Gaff"):
    put(f"Spanker_{part}", f"Spanker_{part}", (0.0, 1.6, 0.0), 0.0, root, {"game_role": "spanker_spar", "vis_begin": 0.0, "vis_end": 250.0})
# BinnacleGlass is replaced by the Compass / Compass_Card / Compass_Glass objects (kept as-is, see KEEP in 03_organize.py)
put("ProvisionsSlate", "ProvisionsSlate", (0, 0, 0), 0.0, root, {"interaction": "provisions", "vis_begin": 0.0, "vis_end": 35.0})
# ---- shipped sails + flags (they carry PinWeights vertex colors and Furled/Reefed shape keys) ----
want = [n for n in ("Sail_Fore_0","Sail_Fore_1","Sail_Fore_2","Sail_Main_0","Sail_Main_1","Sail_Main_2","Sail_Jib","Sail_ForeStaysail","Sail_Spanker","Flag_Ensign","Flag_Pennant")]
before = set(bpy.data.materials.keys())
with bpy.data.libraries.load(GAME, link=False) as (df, dt): dt.objects = want
app = {o.name: o for o in dt.objects if o is not None}
L(f"APPENDED {sorted(app)}")
M = bpy.data.materials
sail_m, boltrope_m, flag_m, pen_m = M["M_Brig_Sail"], M["M_Rope_Boltrope"], M["M_Brig_Flag"], M["M_Brig_Pennant"]
kinds = {"Sail_Fore_0": "square", "Sail_Fore_1": "square", "Sail_Fore_2": "square", "Sail_Main_0": "square", "Sail_Main_1": "square", "Sail_Main_2": "square", "Sail_Jib": "headsail", "Sail_ForeStaysail": "headsail", "Sail_Spanker": "spanker"}
reef = {"Sail_Fore_0": True, "Sail_Fore_1": True, "Sail_Main_0": True, "Sail_Main_1": True}
TILE = 0.5
for n, o in app.items():
    me = o.data; world0 = Vector(XF[n][0]); props = {k: v for k, v in PR[n].items()}
    parent_name = XF[n][2]
    # materials: slot0 cloth, slot1 boltrope (sails); flags single material
    for i, s in enumerate(o.material_slots):       # slot 0 = cloth, slot 1 = boltrope/reef (flags have one slot)
        if n.startswith("Flag"): s.material = flag_m if n == "Flag_Ensign" else pen_m
        else: s.material = sail_m if i == 0 else boltrope_m
    # UVs from the basis vertex positions
    uv = me.uv_layers[0]; lv = np.empty(len(me.loops), dtype=np.int32); me.loops.foreach_get("vertex_index", lv)
    co = np.empty(len(me.vertices) * 3, dtype=np.float32); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3) + np.array(world0, dtype=np.float32)
    P = co[lv]
    if n.startswith("Flag"):
        lo, hi = co.min(axis=0), co.max(axis=0); u = (P[:, 1] - lo[1]) / max(hi[1] - lo[1], 1e-6); v = (P[:, 2] - lo[2]) / max(hi[2] - lo[2], 1e-6)
    else:
        sq = kinds[n] == "square"; u = (P[:, 0] if sq else P[:, 1]) / TILE; v = P[:, 2] / TILE
    uv.data.foreach_set("uv", np.c_[u, v].astype(np.float32).ravel())
    # parent: sails ride on their yard (same origin), the rest on the root
    if parent_name in yards: o.parent = yards[parent_name]
    else: o.parent = root
    o.matrix_parent_inverse = Matrix.Identity(4)
    o.location = (0, 0, 0) if parent_name in yards else tuple(world0)
    for k, v in props.items(): o[k] = v
    exp.objects.link(o)
    L(f"PLACED {n}: parent={o.parent.name} world={tuple(round(x,2) for x in o.matrix_world.translation)} (old {tuple(round(x,2) for x in world0)}) shape_keys={[k.name for k in me.shape_keys.key_blocks] if me.shape_keys else None} colors={[a.name for a in me.color_attributes]}")
for nm in set(M.keys()) - before:
    if nm.startswith(("M_Brig_Sails","M_Brig_Extra","M_Brig_Hull","M_Brig_Fittings","M_Brig_Interior","M_Brig_Rig")) or nm.endswith(".001"):
        L(f"unused appended material: {nm} (users {M[nm].users})")
if OUT:
    bpy.ops.wm.save_as_mainfile(filepath=OUT); L("SAVED " + OUT)
L("=== stage2 finished")
