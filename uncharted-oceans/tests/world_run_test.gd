extends SceneTree
## Headless checks for the run: start in the capital's berth, route, waypoint, sleep to arrival.
## godot --headless --path <project> --script res://tests/world_run_test.gd

var fails := 0

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("   " + extra if extra != "" else ""))
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func key(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = true
	return e

func _initialize() -> void:
	_run()

func _run() -> void:
	var scene: Node = (load("res://scenes/world_test.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await frames(120)
	var st: WorldStreamer = scene.get_node("WorldStreamer")
	var ship: Node3D = scene.get_node("ShipRig")
	var player: CharacterBody3D = scene.get_node("Player")
	var c: WorldChart = st.chart
	var home := c.get_port("AC00")
	var dest := c.get_port("CC02")

	# --- the start in the port
	var port: Node3D = st.get_node_or_null("Port_AC00")
	check("home port scene is loaded", port != null and port.find_children("*", "", true, false).size() > 500, "%d nodes" % (port.find_children("*", "", true, false).size() if port else 0))
	var berth: Node3D = st._find_berth(port, "Berth_01") if port else null
	check("start berth found", berth != null)
	if berth:
		var d := ship.global_position - berth.global_position
		check("ship is at the berth", Vector2(d.x, d.z).length() < 0.5, "%.2f m off" % Vector2(d.x, d.z).length())
		var bow := st._berth_bow_world(port, berth)
		var fwd := Vector3(-sin(deg_to_rad(float(ship.get("heading_deg")))), 0, -cos(deg_to_rad(float(ship.get("heading_deg")))))
		check("ship points along the berth's bow", fwd.dot(bow.normalized()) > 0.99, "dot %.3f" % fwd.dot(bow.normalized()))
		print("INFO  berth local ", berth.position, " port yaw %.0f deg, mouth chart heading %.0f" % [rad_to_deg(port.rotation.y), st._mouth_angle("AC00")])
	check("ship afloat at y~0", absf(ship.global_position.y) < 2.5, "%.2f" % ship.global_position.y)
	check("not aground in the port", not st.aground)
	check("player on the deck", player.is_on_floor(), "floor %s" % player.is_on_floor())
	check("port is turned to deep water", c.sea_depth_m(float(home["x"]) + WorldChart.direction(st._mouth_angle("AC00")).x * 3000.0, float(home["z"]) + WorldChart.direction(st._mouth_angle("AC00")).y * 3000.0) >= 3.0)
	check("terrain hole has been cut for the port", port.has_meta("terrain_hole_m"))
	check("harbour mouth faces the sea (local +Z)", (port.basis * Vector3(0, 0, 1)).dot(Vector3(WorldChart.direction(st._mouth_angle("AC00")).x, 0, WorldChart.direction(st._mouth_angle("AC00")).y)) > 0.99)

	# --- the route and the marker
	check("destination set", st.destination == "CC02")
	check("route found", not st.route_blind and st.route.size() >= 1, "%d legs, %.0f km" % [st.route.size(), st.route_length_m() / 1000.0])
	var last: Vector2 = st.route[st.route.size() - 1]
	check("route ends at the destination port", absf(last.x - float(dest["x"])) < 1.0 and absf(last.y - float(dest["z"])) < 1.0)
	var s := ""
	var prev := Vector2(st.ship_cx(), st.ship_cz())
	for w in st.route:
		s += " %03d/%.0fkm" % [int(WorldChart.heading_to(prev.x, prev.y, w.x, w.y)), prev.distance_to(w) / 1000.0]
		prev = w
	print("INFO  route:", s)
	check("marker is the first waypoint", st.waypoint() == st.route[0], "wp %d of %d" % [st.route_i + 1, st.route.size()])
	var b := st.waypoint_bearing()
	check("bearing to the marker is sane", b >= 0.0 and b < 360.0, "%.0f" % b)

	# --- the sleep prompt takes typed hours
	st.open_prompt()
	check("prompt opens with a preview", st.prompt_open and st.prompt_preview != "", st.prompt_preview)
	st._prompt_key(key(KEY_9)); st._prompt_key(key(KEY_9)); st._prompt_key(key(KEY_9))
	check("typed 999", st.prompt_text == "999")
	st._prompt_key(key(KEY_BACKSPACE))
	check("backspace works", st.prompt_text == "99")
	st._prompt_key(key(KEY_ESCAPE))
	check("escape closes it", not st.prompt_open)

	# --- run the whole route: steer at the marker, sleep a huge number, repeat
	var wake := []
	var zero_streak := 0
	for iter in 40:
		if st.arrived_flag:
			break
		var wp := st.waypoint()
		var bear := st.waypoint_bearing()
		ship.set("heading_deg", fposmod(-bear, 360.0))
		ship.rotation.y = deg_to_rad(float(ship.get("heading_deg")))
		st._check_line()
		if st.line_blocked_m >= 0.0 and iter == 0:
			# the harbour exit is by hand: sail out to the first waypoint, then carry on from there
			var nxt: Vector2 = st.route[mini(1, st.route.size() - 1)]
			st.place_ship(wp.x, wp.y, WorldChart.heading_to(wp.x, wp.y, nxt.x, nxt.y))
			wake.append("by hand to waypoint 1")
			await frames(10)
			st._advance_route()
			continue
		var here := Vector2(st.ship_cx(), st.ship_cz())
		print("INFO  iter %d: at (%.0f, %.0f) marker wp %d/%d (%.0f, %.0f) %.1f km bearing %.1f, blocked %.1f, clear %s, ship heading %.1f" % [iter, here.x, here.y, st.route_i + 1, st.route.size(), wp.x, wp.y, here.distance_to(wp) / 1000.0, bear, st.line_blocked_m, WorldRoute.line_clear(c, here, wp, 1500.0), st.ship_chart_heading()])
		var r := st.sleep(999.0)
		await frames(6)
		wake.append("%s %.0fkm" % [r["stop"], float(r["dist_m"]) / 1000.0])
		zero_streak = zero_streak + 1 if float(r["dist_m"]) < 1.0 else 0
		if zero_streak >= 3:
			break
	print("INFO  wakes: ", wake)
	check("arrived near the destination", st.arrived_flag, "dist %.1f km" % (WorldChart.distance_m(st.ship_cx(), st.ship_cz(), dest["x"], dest["z"]) / 1000.0))
	var waited := 0
	while not st.port_ids().has("CC02") and waited < 600:
		await frames(5)
		waited += 5
	check("destination port is spawned", st.port_ids().has("CC02"), "after %d frames" % waited)
	var ott: Node3D = st.get_node_or_null("Port_CC02")
	if ott:
		var ob: Node3D = st._find_berth(ott, "Berth_01")
		check("Ottoman port has its berths", ob != null)
	check("ship is still on the Godot grid", Vector2(ship.global_position.x, ship.global_position.z).length() <= 5000.0)
	check("player stays with the ship", (player.global_position - ship.global_position).length() < 8.0, str(player.global_position - ship.global_position))

	# --- a bad heading: a huge sleep ends at land or the edge, then the route is re-plotted
	st.place_ship(float(dest["x"]) - 40000.0, float(dest["z"]) + 30000.0, 270.0)
	var rr := st.sleep(999.0)
	print("INFO  bad heading woke: %s after %.0f km" % [rr["stop"], float(rr["dist_m"]) / 1000.0])
	check("a bad heading stops somewhere safe", rr["stop"] in ["land", "edge", "port_ring", "waypoint"], str(rr["stop"]))
	check("and the route is re-plotted from there", st.route.size() >= 1 and st.route_i == 0 or st.arrived_flag)
	print("RESULT: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
