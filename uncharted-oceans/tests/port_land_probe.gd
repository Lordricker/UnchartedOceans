extends Node
var _log: FileAccess
func _p(t: String) -> void:
	print(t)
	if _log:
		_log.store_line(t)
		_log.flush()
## Port land join probe (2026-11-19): seats of the small ports, then AS06 moored with screenshots round it.
## Run tests/port_land_probe.tscn (F6 or the Godot MCP). Shots go to <repo>/renders/port_land/.
const IDS := ["BC01", "AS08", "BS09", "BS10", "BS11", "BS12", "BS13", "CS14", "CS15", "CS16", "CS17", "CS18", "DS19", "DS20", "DS21", "DS22", "DS23", "FF24"]
const SHOTS := true
const ONLY_CHART := false
const NO_PAD := false
const ORBIT_FRAMES := 0
const PROFILE := false
const HOLD_END_S := 0.0
const ORBIT_R := 420.0
const ORBIT_H := 110.0

func _ready() -> void:
	_run()

func _run() -> void:
	var outdir := ProjectSettings.globalize_path("res://").path_join("../renders/port_land")
	DirAccess.make_dir_recursive_absolute(outdir)
	_log = FileAccess.open(outdir.path_join("log.txt"), FileAccess.WRITE)
	var c := WorldChart.load_default()
	_p("SEATCACHE " + str(WorldChart._seat_cache.size()))
	var a6 := c.get_port("AS06")
	for a in range(0, 360, 30):
		var d := WorldChart.direction(float(a))
		var row := ""
		for f in [500.0, 1000.0, 1500.0, 2000.0, 3000.0, 4000.0]:
			row += " %.2f" % c.land_value(a6["x"] + d.x * f, a6["z"] + d.y * f)
		_p("RAY %d:%s" % [a, row])
	_p("FIND " + str(c._find_seat(a6["x"], a6["z"])))
	_p("AS06 " + str(a6))
	_p("AS06 land at json pos %.2f" % c.land_value(a6.get("json_x", a6["x"]), a6.get("json_z", a6["z"])))
	for p in c.ports:
		if p.has("mouth"):
			_p(str("SEAT %s moved %.0f m, mouth %.0f deg" % [p["id"], WorldChart.distance_m(p["json_x"], p["json_z"], p["x"], p["z"]), p["mouth"]]))
		elif String(p["tier"]) != "capital":
			_p(str("SEAT %s NOT SEATED" % p["id"]))
	var world: Node = null
	var st: Node = null
	for id in ([] if ONLY_CHART else IDS):
		if world == null:
			world = (load("res://scenes/world_capital_start.tscn") as PackedScene).instantiate()
			st = world.get_node("WorldStreamer")
			st.set("home_port_id", id)
			st.set("start_moored", true)
			add_child(world)
		else:
			# one world for every port (a second world crashes on the freed ship): move to the next port
			st.set("home_port_id", id)
			st.call("go_home")
		for i in (900 if id.substr(1, 1) == "C" else 360):
			await get_tree().physics_frame
		var port: Node3D = st.get("_ports").get(id)
		if port == null:
			_p(str("PROBE no port node ", id))
			continue
		var g = st.get("ground")
		_p("PROBE port node pos %s rot %.1f deg, origin %.0f %.0f" % [port.position, rad_to_deg(port.rotation.y), float(st.get("origin_x")), float(st.get("origin_z"))])
		var t := port.global_transform
		var ox := float(st.get("origin_x"))
		var oz := float(st.get("origin_z"))
		_p(str("PROBE ", id, " pad live: ", st.get("_pad_id"), " aground: ", st.get("aground")))
		for q in [Vector3(0, 0, 30), Vector3(0, 0, 200), Vector3(0, 0, 500), Vector3(0, 0, -100), Vector3(0, 0, -300), Vector3(-350, 0, -100), Vector3(350, 0, -100), Vector3(0, 0, -450)]:
			var w: Vector3 = t * q
			_p(str("PROBE local %s ground %.1f (no pad %.1f)" % [q, g.terrain_y(ox + w.x, oz + w.z), g._ground_y0(ox + w.x, oz + w.z)]))
		if NO_PAD:
			st.get("_pads").clear()
			st.call("_pick_pad")
		if PROFILE:
			for line in [[Vector2(0, -300), Vector2(0, -4000)], [Vector2(-3000, -900), Vector2(3000, -900)], [Vector2(-3000, -1800), Vector2(3000, -1800)]]:
				var a: Vector2 = line[0]
				var b: Vector2 = line[1]
				var steps := int(a.distance_to(b) / 10.0)
				var prev := NAN
				var maxslope := 0.0
				for k in steps + 1:
					var l := a.lerp(b, float(k) / float(steps))
					var w: Vector3 = t * Vector3(l.x, 0, l.y)
					var cx := ox + w.x
					var cz := oz + w.z
					var y: float = g.terrain_y(cx, cz)
					if not is_nan(prev):
						var sl := absf(y - prev) / 10.0
						maxslope = maxf(maxslope, sl)
						if sl > 1.5:
							_p("JUMP line %s at %s: %.1f -> %.1f (shore_d %.0f, land %.3f, h16raw %.4f)" % [a, l, prev, y, g.shore_d(cx, cz), c.land_value(cx, cz), g._h16_at(cx, cz)])
					prev = y
				_p("LINE %s->%s max slope %.2f" % [a, b, maxslope])
		var cam := Camera3D.new()
		cam.far = 20000.0
		world.add_child(cam)
		cam.current = true
		var shots := {
			"aerial": [Vector3(0, 380, 750), Vector3(0, 0, -150)],
		}
		for k in (shots if SHOTS else {}):
			cam.global_position = t * (shots[k][0] as Vector3)
			cam.look_at(t * (shots[k][1] as Vector3))
			await get_tree().create_timer(2.0).timeout
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/%s_%s%s.png" % [outdir, id, k, "_nopad" if NO_PAD else ""])
			_p(str("PROBE saved ", id, " ", k))
		if ORBIT_FRAMES > 0:
			var od := outdir.path_join("orbit")
			DirAccess.make_dir_recursive_absolute(od)
			var centre: Vector3 = t * Vector3(0, 8, -90)
			for f in ORBIT_FRAMES:
				var ang := TAU * float(f) / float(ORBIT_FRAMES) + PI * 0.5
				var off := Vector3(cos(ang), 0.0, sin(ang)) * ORBIT_R
				cam.global_position = centre + off + Vector3(0, ORBIT_H + 25.0 * sin(ang * 2.0), 0)
				cam.look_at(centre)
				for _k in 3:
					await get_tree().process_frame
				var im := get_viewport().get_texture().get_image()
				im.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
				im.save_jpg("%s/f_%04d.jpg" % [od, f], 0.92)
			_p("PROBE orbit done")
	_p(str("PROBE done"))
	await get_tree().create_timer(HOLD_END_S).timeout
	get_tree().quit()
