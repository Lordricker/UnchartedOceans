extends Node
## Saving, loading and bug reports. Autoload "SaveSystem" (the pause menu's Report / Save / Load buttons call it).
##
## History: everything Godot prints (print, push_warning, push_error, script errors with their call stacks) is kept in
## a ring buffer through a Logger, along with the keys and mouse buttons you press and a one-line snapshot of the
## ship, the player and the world every SAMPLE_EVERY seconds. That buffer is the "what happened" part of a report.
##
## Save (capture / apply): the scene, the ship (model, chart position, heading, speed, rudder, sails, anchor, mooring
## berth), the player (spot on the ship or in the world, look direction), the clock and the storms, the wind override,
## the destination, gold, markets, port boxes, courier jobs and every box in the hold (exactly where it was stowed).
## Not saved yet: other ships you own or bought, boxes dropped loose on the ground, flooding water, cannon state.
## Loading reloads the scene and then puts all of that back. The last save is user://saves/last_save.txt.
##
## Bug report: a folder with screenshot.png (the frame you were looking at when you pressed Esc), save.txt (the
## state, loadable), and report.md (your prompt, a readable summary of the state, the history and the tail of the
## Godot log). Run from the editor it goes to <repo>/bug_reports/<time>/ so Claude can read it straight from the
## repo; in an exported build it goes to user://bug_reports/. The prompt and the folder are copied to the clipboard:
## paste that into the chat with Claude.

const SAVE_DIR := "user://saves"
const LAST_SAVE := "user://saves/last_save.txt"
const SAVE_VERSION := 1
const SAMPLE_EVERY := 5.0
const MAX_LINES := 500
const LOG_TAIL_LINES := 150

signal saved(path: String)
signal loaded

var last_report_dir := ""
var _logger: HistoryLogger
var _sample_t := 2.0
var _loading := false
var _toast: Label
var _toast_t := 0.0


## Keeps the last MAX_LINES lines Godot logs. Godot can log from any thread, so the buffer is locked.
class HistoryLogger extends Logger:
	var mutex := Mutex.new()
	var lines: PackedStringArray = PackedStringArray()
	var max_lines := 500

	func add(t: String) -> void:
		var stamp := Time.get_time_string_from_system()
		mutex.lock()
		for part in t.strip_edges(false, true).split("\n"):
			lines.append("%s  %s" % [stamp, part])
		while lines.size() > max_lines:
			lines.remove_at(0)
		mutex.unlock()

	func copy() -> PackedStringArray:
		mutex.lock()
		var out := lines.duplicate()
		mutex.unlock()
		return out

	func _log_message(message: String, error: bool) -> void:
		add(("[stderr] " if error else "") + message)

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var kinds := ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"]
		var kind: String = kinds[clampi(error_type, 0, kinds.size() - 1)]
		var what := rationale if rationale != "" else code
		var t := "%s: %s   (%s:%d in %s)" % [kind, what, file, line, function]
		for bt in script_backtraces:
			if bt != null and bt.get_frame_count() > 0:
				t += "\n" + bt.format(4, 4)
		add(t)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_logger = HistoryLogger.new()
	_logger.max_lines = MAX_LINES
	OS.add_logger(_logger)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var cl := CanvasLayer.new()
	cl.layer = 70
	add_child(cl)
	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 40.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.visible = false
	cl.add_child(_toast)
	note("game started, scene %s" % _scene_path())


func _exit_tree() -> void:
	if _logger != null:
		OS.remove_logger(_logger)


## Add a line to the history (other scripts can call SaveSystem.note("...") for anything worth knowing in a report).
func note(t: String) -> void:
	if _logger != null:
		_logger.add("[game] " + t)


func has_save() -> bool:
	return FileAccess.file_exists(LAST_SAVE)


func toast(t: String, secs := 4.0) -> void:
	_toast.text = t
	_toast.visible = true
	_toast_t = secs


# ------------------------------------------------------------------ history

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.visible = false
	if get_tree().paused:
		return
	_sample_t -= delta / maxf(Engine.time_scale, 0.001)
	if _sample_t <= 0.0:
		_sample_t = SAMPLE_EVERY
		if _logger != null:
			_logger.add("[state] " + status_line())


func _input(e: InputEvent) -> void:
	if _logger == null or get_tree().paused:      # not the typing in the report box
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var k := e as InputEventKey
		_logger.add("[key] " + OS.get_keycode_string(k.get_physical_keycode_with_modifiers()))
	elif e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_logger.add("[mouse] %s click" % ["", "left", "right", "middle"][mb.button_index])


## One line: where the ship is and what she is doing, where the player is, the clock, the wind, the frame rate.
func status_line() -> String:
	var parts: PackedStringArray = []
	parts.append("fps %d" % Engine.get_frames_per_second())
	var st := _streamer()
	var rig := _rig()
	if st != null and rig != null and st.get("chart") != null:
		parts.append("ship %s at chart (%.0f, %.0f) hdg %.0f spd %.2f m/s rudder %.2f" % [_model_name(rig),
			float(st.call("ship_cx")), float(st.call("ship_cz")), float(st.call("ship_chart_heading")),
			float(rig.get("speed")), float(rig.get("rudder"))])
		var hb := _harbor()
		if hb != null and bool(hb.get("moored")):
			parts.append("moored")
		if bool(st.get("aground")):
			parts.append("AGROUND")
	var pl := _player()
	if pl != null and rig != null:
		var lp := _ship_frame(rig).affine_inverse() * pl.global_position
		parts.append("player %s (%.1f, %.1f, %.1f)" % ["on ship" if lp.length() < 60.0 else "ashore/far", lp.x, lp.y, lp.z])
		if bool(pl.get("swimming")):
			parts.append("SWIMMING")
	var wx := _weather()
	if wx != null:
		parts.append("%s %s" % [String(wx.call("date_text")), _clock(float(wx.call("hour_of_day")))])
	var w := get_tree().get_first_node_in_group("wind")
	if w != null and w.has_method("speed"):
		parts.append("wind %.1f m/s from %.0f" % [float(w.call("speed")), float(w.call("from_bearing_deg"))])
	var st_ff := get_tree().get_first_node_in_group("world_streamer")
	if st_ff != null and st_ff.has_method("time_speed") and float(st_ff.call("time_speed")) != 1.0:
		parts.append("time x%.0f" % float(st_ff.call("time_speed")))
	return ", ".join(parts)


# ------------------------------------------------------------------ save / load

func save_game() -> String:
	if GameSession.tutorial:
		toast("Saving is off in the tutorial.")
		return ""
	var d := capture()
	var err := _write_text(LAST_SAVE, var_to_str(d))
	if err != OK:
		push_error("SaveSystem: could not write %s (%s)" % [LAST_SAVE, error_string(err)])
		return ""
	note("saved the game to %s" % ProjectSettings.globalize_path(LAST_SAVE))
	saved.emit(LAST_SAVE)
	return LAST_SAVE


func load_last() -> void:
	if GameSession.tutorial:
		toast("Loading is off in the tutorial.")
		return
	load_file(LAST_SAVE)


## Load a save file (a bug report's save.txt works too).
func load_file(path: String) -> void:
	if _loading:
		return
	if not FileAccess.file_exists(path):
		toast("No save to load.")
		return
	var d = str_to_var(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		toast("That save could not be read.")
		push_error("SaveSystem: %s is not a save" % path)
		return
	_loading = true
	note("loading %s" % path)
	var tree := get_tree()
	tree.paused = false
	Engine.time_scale = 1.0
	var old := tree.current_scene
	var scene := String(d.get("scene", ""))
	if scene != "" and ResourceLoader.exists(scene):
		tree.change_scene_to_file(scene)
	else:
		tree.reload_current_scene()
	while tree.current_scene == null or tree.current_scene == old or not tree.current_scene.is_node_ready():
		await tree.process_frame
	# the starting cargo must not be stowed on top of the saved hold
	var pl := _player()
	if pl != null and pl.get("cargo") != null:
		pl.get("cargo").set("starting_cargo", {})
		pl.get("cargo").set("_start_done", true)
	for i in 3:
		await tree.physics_frame
	await _apply(d)
	_loading = false
	toast("Loaded the save from %s" % String(d.get("time", "?")))
	loaded.emit()


func capture() -> Dictionary:
	var tree := get_tree()
	var d := {"version": SAVE_VERSION, "time": Time.get_datetime_string_from_system(false, true), "scene": _scene_path()}
	var st := _streamer()
	var rig := _rig()
	if st != null and rig != null:
		var ship := {
			"model": _model_of(rig),
			"cx": float(st.call("ship_cx")), "cz": float(st.call("ship_cz")),
			"heading": float(st.call("ship_chart_heading")),
			"speed": float(rig.get("speed")), "side_speed": float(rig.get("side_speed")),
			"rudder": float(rig.get("rudder")),
		}
		var sl = rig.get("sails")
		if sl != null and sl.get("model") != null:
			var fr: Array = []
			for s in sl.model.sails:
				fr.append(float(s.set_frac))
			ship["sails"] = fr
			ship["braces"] = (sl.braces as Array).duplicate()
		var an := _anchor()
		if an != null:
			ship["anchor"] = {"state": int(an.get("state")), "t": float(an.get("_t"))}
		var hb := _harbor()
		if hb != null and bool(hb.get("moored")) and hb.get("berth") != null:
			var b := hb.get("berth") as Node3D
			ship["moored"] = {"name": String(b.name), "cx": st.call("chart_x", b.global_position.x),
				"cz": st.call("chart_z", b.global_position.z)}
		d["ship"] = ship
		d["world"] = {"destination": String(st.get("destination")), "fast_forward": int(st.get("fast_forward_i"))}
	var pl := _player()
	if pl != null:
		var p := {"yaw": pl.global_rotation.y, "pitch": 0.0, "cx": 0.0, "cz": 0.0, "y": pl.global_position.y}
		var head := pl.get_node_or_null("Head") as Node3D
		if head != null:
			p["pitch"] = head.rotation.x
		if st != null:
			p["cx"] = float(st.call("chart_x", pl.global_position.x))
			p["cz"] = float(st.call("chart_z", pl.global_position.z))
		if rig != null:
			var f := _ship_frame(rig)
			var lp := f.affine_inverse() * pl.global_position
			p["on_ship"] = lp.length() < 60.0
			p["local"] = lp
			p["yaw_rel"] = wrapf(pl.global_rotation.y - f.basis.get_euler().y, -PI, PI)
		d["player"] = p
		var cg = pl.get("cargo")
		if cg != null:
			var boxes: Array = []
			for uid in cg.placed:
				var pc = cg.placed[uid]
				boxes.append({"good": String(pc.good.id), "shape": pc.shape.duplicate(), "anchor": pc.anchor})
			var c := {"hold": boxes}
			if cg.carried != null:
				c["carried"] = {"good": String(cg.carried.id), "qty": int(cg.carried_qty), "hand": cg.hand_cells.duplicate()}
			d["cargo"] = c
	var wx := _weather()
	if wx != null:
		var tracks: Array = []
		for t in wx.get("tracks"):
			tracks.append({"kind": t.kind, "cx": t.cx, "cz": t.cz, "heading": t.heading, "speed": t.speed,
				"curve": t.curve, "age": t.age, "life": t.life, "peak": t.peak, "wind_boost": t.wind_boost,
				"radius": t.cell.radius_m, "depth": t.cell.depth_m, "height": t.cell.height_m, "rain": t.cell.rain,
				"seed": t.cell.shape_seed, "intensity": t.cell.intensity})
		d["weather"] = {"game_hours": float(wx.get("game_hours")), "rng": (wx.get("_rng") as RandomNumberGenerator).state,
			"tracks": tracks}
	var w := tree.get_first_node_in_group("wind")
	if w != null:
		d["wind"] = {"manual": bool(w.get("_manual")), "speed": float(w.get("_manual_speed")),
			"heading": float(w.get("_manual_heading"))}
	var markets := {}
	for id in TradeState.markets:
		markets[id] = (TradeState.markets[id] as TradeMarket).to_dict()
	d["trade"] = {"gold": TradeState.gold, "markets": markets, "stock": TradeState._stock.duplicate(true),
		"pool": TradeState._pool.duplicate(true), "cost_basis": TradeState.cost_basis.duplicate(true),
		"last_day": TradeState._last_day}
	d["courier"] = {"offers": CourierQuests.offers.duplicate(true), "active": CourierQuests.active.duplicate(true),
		"done": CourierQuests.done.duplicate(true), "total_earned": CourierQuests.total_earned,
		"thanks": CourierQuests.thanks.duplicate(true), "jobs_made": CourierQuests._jobs_made.duplicate(true),
		"serial": CourierQuests._serial}
	return d


func _apply(d: Dictionary) -> void:
	var tree := get_tree()
	_apply_statics(d)
	var st := _streamer()
	var rig := _rig()
	var ship: Dictionary = d.get("ship", {})
	# the ship model
	if rig != null and ship.has("model") and int(ship["model"]) != _model_of(rig):
		rig = await _swap_rig(rig, int(ship["model"]))
	# the clock and the storms
	var wx := _weather()
	if wx != null and d.has("weather"):
		_apply_weather(wx, d["weather"])
	# the ship's place
	if st != null and rig != null and not ship.is_empty():
		var hb := _harbor()
		if hb != null:
			hb.call("release_mooring")
		st.call("place_ship", float(ship["cx"]), float(ship["cz"]), float(ship["heading"]))
		if ship.has("moored"):
			var m: Dictionary = ship["moored"]
			var berth := await _find_berth(st, float(m["cx"]), float(m["cz"]), 15.0)
			if berth != null and hb != null:
				var slot := berth.slot_position(_model_of(rig))
				st.call("place_ship", float(st.get("origin_x")) + slot.x, float(st.get("origin_z")) + slot.z, -berth.berth_heading)
				rig.global_position.y = 0.0
				hb.call("start_moored_at", berth)
			else:
				push_warning("SaveSystem: the berth the ship was moored at did not turn up; she is loaded unmoored")
		else:
			var sm = hb.call("_model") if hb != null else null
			if sm != null:
				sm.v_f = float(ship.get("speed", 0.0))
				sm.v_s = float(ship.get("side_speed", 0.0))
			rig.set("speed", float(ship.get("speed", 0.0)))
			rig.set("side_speed", float(ship.get("side_speed", 0.0)))
		rig.set("rudder", float(ship.get("rudder", 0.0)))
		var sl = rig.get("sails")
		if sl != null and sl.get("model") != null and ship.has("sails"):
			var fr: Array = ship["sails"]
			for i in mini(fr.size(), sl.model.sails.size()):
				sl.model.sails[i].set_frac = float(fr[i])
			if ship.has("braces"):
				var br: Array = ship["braces"]
				for i in mini(br.size(), sl.braces.size()):
					sl.braces[i] = float(br[i])
		var an := _anchor()
		if an != null and ship.has("anchor"):
			an.set("state", int(ship["anchor"]["state"]))
			an.set("_t", float(ship["anchor"]["t"]))
	# the player
	var pl := _player()
	var p: Dictionary = d.get("player", {})
	if pl != null and not p.is_empty():
		if rig != null and bool(p.get("on_ship", false)):
			var f := _ship_frame(rig)
			pl.global_position = f * (p["local"] as Vector3) + Vector3(0, 0.05, 0)
			pl.global_rotation.y = f.basis.get_euler().y + float(p.get("yaw_rel", 0.0))
		elif st != null:
			pl.global_position = Vector3(float(p["cx"]) - float(st.get("origin_x")), float(p["y"]) + 0.05,
				float(p["cz"]) - float(st.get("origin_z")))
			pl.global_rotation.y = float(p.get("yaw", 0.0))
		var head := pl.get_node_or_null("Head") as Node3D
		if head != null:
			head.rotation.x = float(p.get("pitch", 0.0))
		if pl is CharacterBody3D:
			(pl as CharacterBody3D).velocity = Vector3.ZERO
	# wind and the run
	var w := tree.get_first_node_in_group("wind")
	if w != null and d.has("wind"):
		w.set("_manual", bool(d["wind"]["manual"]))
		w.set("_manual_speed", float(d["wind"]["speed"]))
		w.set("_manual_heading", float(d["wind"]["heading"]))
	if st != null and d.has("world"):
		var dest := String(d["world"].get("destination", ""))
		if dest != "" and dest != String(st.get("destination")):
			st.call("set_destination", dest)
		st.call("set_fast_forward", 0)      # a game always loads at normal time (fast time locks you to the helm)
	# the hold
	if pl != null and d.has("cargo"):
		await _apply_cargo(pl.get("cargo"), d["cargo"])
	note("loaded: " + status_line())


func _apply_statics(d: Dictionary) -> void:
	if d.has("trade"):
		var t: Dictionary = d["trade"]
		TradeState.gold = int(t.get("gold", TradeState.gold))
		var data := CargoData.get_shared()
		TradeState.markets.clear()
		var mk: Dictionary = t.get("markets", {})
		for id in mk:
			TradeState.markets[id] = TradeMarket.from_dict(mk[id], data)
		TradeState._stock = t.get("stock", {})
		TradeState._pool.clear()
		TradeState._pool.append_array(t.get("pool", []))
		TradeState.cost_basis = t.get("cost_basis", {})
		TradeState._last_day = int(t.get("last_day", -1))
	if d.has("courier"):
		var c: Dictionary = d["courier"]
		CourierQuests.offers = c.get("offers", {})
		CourierQuests.active = c.get("active", [])
		CourierQuests.done = c.get("done", [])
		CourierQuests.total_earned = int(c.get("total_earned", 0))
		CourierQuests.thanks = c.get("thanks", {})
		CourierQuests._jobs_made = c.get("jobs_made", {})
		CourierQuests._serial = int(c.get("serial", 0))
		for q in CourierQuests.active:
			CourierQuests._register_good(q)


func _apply_weather(wx: Node, w: Dictionary) -> void:
	wx.set("game_hours", float(w.get("game_hours", 0.0)))
	if w.has("rng"):
		(wx.get("_rng") as RandomNumberGenerator).state = int(w["rng"])
	var sky = wx.get("_sky")
	var live: Array = wx.get("tracks")        # the weather's own array (edited in place)
	for t in live:
		if sky != null:
			sky.storms.erase(t.cell)
	live.clear()
	for s in w.get("tracks", []):
		var t := WorldWeather.Track.new()
		t.kind = String(s["kind"])
		t.cx = float(s["cx"])
		t.cz = float(s["cz"])
		t.heading = float(s["heading"])
		t.speed = float(s["speed"])
		t.curve = float(s["curve"])
		t.age = float(s["age"])
		t.life = float(s["life"])
		t.peak = float(s["peak"])
		t.wind_boost = float(s["wind_boost"])
		var c := StormCell.new()
		c.radius_m = float(s["radius"])
		c.depth_m = float(s["depth"])
		c.height_m = float(s["height"])
		c.rain = float(s["rain"])
		c.shape_seed = float(s["seed"])
		c.intensity = float(s["intensity"])
		c.velocity = Vector2.ZERO
		t.cell = c
		live.append(t)
		if sky != null:
			sky.storms.append(c)
	if wx.has_method("_sync_sky"):
		wx.call("_sync_sky")
	wx.emit_signal("time_jumped")


func _apply_cargo(cg, c: Dictionary) -> void:
	if cg == null:
		return
	var tree := get_tree()
	cg.set("flood", null)          # find the hold of the ship we have now
	var waited := 0.0
	while waited < 30.0:
		cg.call("_find_refs")
		if cg.flood != null and cg.call("_grid_ready"):
			break
		await tree.process_frame
		waited += get_process_delta_time()
	if cg.flood == null or not cg.call("_grid_ready"):
		push_warning("SaveSystem: the hold never became ready, so the saved cargo was not put back")
		return
	for uid in cg.placed.keys():
		var pc = cg.placed[uid]
		if is_instance_valid(pc.node):
			pc.node.queue_free()
	cg.placed.clear()
	cg.occ.clear()
	var data := CargoData.get_shared()
	var missing := 0
	for b in c.get("hold", []):
		var g := data.get_good(String(b["good"]))
		if g == null:
			missing += 1
			continue
		var shape: Array[Vector3i] = []
		for v in b["shape"]:
			shape.append(v as Vector3i)
		cg.call("_stow_box", g, shape, b["anchor"] as Vector3i)
	cg.set("_version", int(cg.get("_version")) + 1)
	cg.call("_push_load")
	if missing > 0:
		push_warning("SaveSystem: %d saved boxes were of goods that no longer exist" % missing)
	if c.has("carried"):
		var g2 := data.get_good(String(c["carried"]["good"]))
		if g2 != null:
			var hand: Array[Vector3i] = []
			for v in c["carried"]["hand"]:
				hand.append(v as Vector3i)
			cg.call("_carry", g2, hand, int(c["carried"]["qty"]))


## Put a fresh rig of another ship model where the current one is (what ShipFleet does when you change ships, minus
## the berths and proxies).
func _swap_rig(old: Node3D, model: int) -> Node3D:
	var fleet := get_tree().get_first_node_in_group("ship_fleet")
	if fleet == null or not ShipFleet.MODELS.has(model):
		push_warning("SaveSystem: cannot load ship model %d here; keeping the scene's ship" % model)
		return old
	var parent := old.get_parent()
	var nr: Node3D = fleet.call("_build_rig", old, model)
	var nm := old.name
	old.remove_from_group("ships")
	var oh := old.get_node_or_null("ShipHarbor")
	if oh != null:
		oh.remove_from_group("ship_harbor")
	for n in old.find_children("*", "", true, false):
		for g in ["ship_flooding", "ship_anchor", "ship_harbor"]:
			if n.is_in_group(g):
				n.remove_from_group(g)
	old.name = "%s_unloaded" % nm
	old.visible = false
	old.process_mode = Node.PROCESS_MODE_DISABLED
	nr.name = nm
	nr.set("heading_deg", old.get("heading_deg"))
	parent.add_child(nr)
	nr.global_position = Vector3(old.global_position.x, 0.0, old.global_position.z)
	var st := _streamer()
	if st != null:
		st.set("_ship", nr)
	await get_tree().process_frame
	await get_tree().process_frame
	var oc = nr.get("_ocean")
	if oc != null:
		var ws := (oc as Node).get_node_or_null("WaveSpray")
		if ws != null:
			ws.set("motion", nr)
	old.queue_free()
	await get_tree().process_frame
	fleet.emit_signal("active_ship_changed", nr)
	return nr


## The DockBerth nearest a chart position, waiting (up to 20 s) for its port to stream in.
func _find_berth(st: Node, cx: float, cz: float, max_m: float) -> DockBerth:
	var waited := 0.0
	while waited < 20.0:
		var best: DockBerth = null
		var bd := max_m
		for n in get_tree().get_nodes_in_group("dock_berths"):
			var b := n as DockBerth
			if b == null or not b.is_inside_tree():
				continue
			var d := Vector2(float(st.call("chart_x", b.global_position.x)) - cx,
				float(st.call("chart_z", b.global_position.z)) - cz).length()
			if d < bd:
				bd = d
				best = b
		if best != null:
			return best
		await get_tree().process_frame
		waited += get_process_delta_time()
	return null


# ------------------------------------------------------------------ bug report

## Write a bug report folder. Returns its absolute path ("" if it failed). The prompt and path go to the clipboard.
func write_report(prompt: String, shot: Image) -> String:
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var root := _report_root()
	var dir := root.path_join(stamp)
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		push_error("SaveSystem: could not make %s (%s)" % [dir, error_string(err)])
		return ""
	var d := capture()
	var save_text := var_to_str(d)
	_write_text(dir.path_join("save.txt"), save_text)
	_write_text(LAST_SAVE, save_text)
	if shot != null and not shot.is_empty():
		shot.save_png(dir.path_join("screenshot.png"))
	_write_text(dir.path_join("report.md"), _report_md(prompt, d, stamp, shot != null))
	last_report_dir = dir
	var rel := "bug_reports/%s" % stamp if OS.has_feature("editor") else dir
	DisplayServer.clipboard_set("Uncharted Oceans bug report: %s\n\n%s" % [rel, prompt.strip_edges()])
	note("bug report written to %s" % dir)
	return dir


func _report_root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join("..").simplify_path().path_join("bug_reports")
	return ProjectSettings.globalize_path("user://bug_reports")


func _report_md(prompt: String, d: Dictionary, stamp: String, has_shot: bool) -> String:
	var L: PackedStringArray = []
	L.append("# Bug report %s" % stamp)
	L.append("")
	L.append("## Prompt")
	L.append("")
	L.append(prompt.strip_edges() if prompt.strip_edges() != "" else "(no prompt)")
	L.append("")
	L.append("## Files")
	L.append("")
	if has_shot:
		L.append("- screenshot.png: what was on screen when Esc was pressed")
	L.append("- save.txt: the game state (Load last save in the Esc menu loads it while it is the newest save)")
	L.append("")
	L.append("## Situation")
	L.append("")
	L.append("- %s" % status_line())
	L.append("- scene: %s" % String(d.get("scene", "")))
	L.append("- Godot %s, %s, %s" % [Engine.get_version_info()["string"], OS.get_name(), RenderingServer.get_video_adapter_name()])
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		L.append("- graphics quality: %s" % ["Low", "Medium", "High"][clampi(int(gs.call("current_quality")), 0, 2)])
	if d.has("trade"):
		L.append("- gold: %d" % int(d["trade"]["gold"]))
	if d.has("cargo"):
		var counts := {}
		for b in d["cargo"]["hold"]:
			counts[b["good"]] = int(counts.get(b["good"], 0)) + 1
		L.append("- hold: %s" % (str(counts) if not counts.is_empty() else "empty"))
		if d["cargo"].has("carried"):
			L.append("- carrying: %s x%d" % [d["cargo"]["carried"]["good"], int(d["cargo"]["carried"]["qty"])])
	if d.has("courier"):
		L.append("- courier jobs open: %d" % (d["courier"]["active"] as Array).size())
	if d.has("weather"):
		L.append("- storms on the chart: %d" % (d["weather"]["tracks"] as Array).size())
	L.append("")
	L.append("## History (oldest first: Godot output, errors, keys pressed, a state line every %d s)" % int(SAMPLE_EVERY))
	L.append("")
	L.append("```")
	L.append_array(_logger.copy() if _logger != null else PackedStringArray())
	L.append("```")
	var tail := _log_tail()
	if tail != "":
		L.append("")
		L.append("## Godot log (last %d lines of user://logs/godot.log)" % LOG_TAIL_LINES)
		L.append("")
		L.append("```")
		L.append(tail)
		L.append("```")
	return "\n".join(L) + "\n"


func _log_tail() -> String:
	var path := "user://logs/godot.log"
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines := f.get_as_text().split("\n")
	var from := maxi(lines.size() - LOG_TAIL_LINES, 0)
	return "\n".join(lines.slice(from))


# ------------------------------------------------------------------ helpers

func _write_text(path: String, text: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK


func _scene_path() -> String:
	var cs: Node = get_tree().current_scene if get_tree() != null else null
	return cs.scene_file_path if cs != null else ""


func _streamer() -> Node:
	return get_tree().get_first_node_in_group("world_streamer")


func _rig() -> Node3D:
	return get_tree().get_first_node_in_group("ships") as Node3D


func _harbor() -> Node:
	return get_tree().get_first_node_in_group("ship_harbor")


func _anchor() -> Node:
	return get_tree().get_first_node_in_group("ship_anchor")


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _weather() -> Node:
	return get_tree().get_first_node_in_group("weather")


func _model_of(rig: Node3D) -> int:
	var c = rig.get("ship_class")
	return int(c) if c != null else 1


func _model_name(rig: Node3D) -> String:
	var m := _model_of(rig)
	return String(ShipFleet.MODELS[m]["name"]) if ShipFleet.MODELS.has(m) else "model %d" % m


## The ship's frame on the water: her position and heading only (no roll or pitch), so a spot saved on her deck comes
## back on the deck whatever the waves are doing.
func _ship_frame(rig: Node3D) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(rig.get("heading_deg")))), rig.global_position)


func _clock(h: float) -> String:
	return "%02d:%02d" % [int(h), int(fposmod(h, 1.0) * 60.0)]
