extends SceneTree
## Headless checks for WorldStreamer + Ocean world mode, using the real brig and player.
## godot --headless --path <project> --script res://tests/world_streamer_test.gd

var fails := 0

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("   " + extra if extra != "" else ""))
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func find_spot(c: WorldChart, around: Dictionary, lo: float, hi: float, step: float = 150.0) -> Vector2:
	# nearest grid point to `around` whose depth is in [lo, hi] and whose neighbours 10 m away are water too
	var best := Vector2.ZERO
	var bd := INF
	var x := step
	while x < c.width_m - step:
		var z := step
		while z < c.height_m - step:
			var d := c.sea_depth_m(x, z)
			if d >= lo and d <= hi:
				var dist := WorldChart.distance_m(x, z, around["x"], around["z"])
				if dist < bd and c.sea_depth_m(x + 10, z) >= lo * 0.9 and c.sea_depth_m(x - 10, z) >= lo * 0.9 and c.sea_depth_m(x, z + 10) >= lo * 0.9 and c.sea_depth_m(x, z - 10) >= lo * 0.9:
					bd = dist
					best = Vector2(x, z)
			z += step
		x += step
	return best

func c_depth_ok(c: WorldChart, p: Dictionary, dv: Vector2, dists: Array) -> bool:
	for d in dists:
		if c.sea_depth_m(float(p["x"]) + dv.x * d, float(p["z"]) + dv.y * d) < 6.0:
			return false
	return true

func _initialize() -> void:
	_run()

func _run() -> void:
	var scene: Node = (load("res://scenes/world_test.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await frames(90)
	var st: WorldStreamer = scene.get_node("WorldStreamer")
	var ship: Node3D = scene.get_node("ShipRig")
	var player: CharacterBody3D = scene.get_node("Player")
	var ocean: Ocean = scene.get_node("Ocean")
	check("chart loaded", st.chart != null and st.chart.ports.size() == 25)
	check("ship starts near the origin", Vector2(ship.global_position.x, ship.global_position.z).length() < 6000.0, str(ship.global_position))
	var home := st.chart.get_port("AC00")
	var d_home := WorldChart.distance_m(st.ship_cx(), st.ship_cz(), home["x"], home["z"])
	check("start is %.0f m from the home port" % st.start_distance_m, absf(d_home - st.start_distance_m) < 5.0, "%.1f" % d_home)
	check("home port spawned", st.port_ids().has("AC00"), str(st.port_ids()))
	var pn: Node3D = st.get_node_or_null("Port_AC00")
	check("beacon is at its chart position", pn != null and absf(pn.global_position.x + st.origin_x - home["x"]) < 0.01 and absf(pn.global_position.z + st.origin_z - home["z"]) < 0.01)
	check("ship starts afloat", st.chart.sea_depth_m(st.ship_cx(), st.ship_cz()) >= 4.0, "%.1f m of water" % st.ship_depth_m())
	check("not aground at the start", not st.aground)
	var all_ok := true
	for pp in st.chart.ports:
		if st.chart.sea_depth_m(pp["x"], pp["z"]) < WorldStreamer.KEEL_CLEARANCE_M:
			all_ok = false
			print("      port in the shallows/land: ", pp["id"])
	check("every port sits in water deeper than the keel", all_ok)
	check("player on the deck", player.is_on_floor(), "y %.2f floor %s" % [player.global_position.y, player.is_on_floor()])

	# --- wave continuity across a rebase: a fixed chart point must keep its height
	var px: float = st.ship_cx() + 300.0
	var pz: float = st.ship_cz() - 200.0
	ocean.set_process(false)
	var h0 := ocean.get_height(px - st.origin_x, pz - st.origin_z)
	var s0 := ocean.wave_scale(px - st.origin_x, pz - st.origin_z)
	var ox0 := st.origin_x
	var cx0 := st.ship_cx()
	var cz0 := st.ship_cz()
	st.relocate(cx0 + 36000.0, cz0)
	var h1 := ocean.get_height(px - st.origin_x, pz - st.origin_z)
	check("origin moved", absf(st.origin_x - ox0) > 30000.0, "%.0f -> %.0f" % [ox0, st.origin_x])
	check("wave height is the same after a rebase", absf(h0 - h1) < 0.002, "%.5f vs %.5f" % [h0, h1])
	st.relocate(cx0, cz0)
	var h2 := ocean.get_height(px - st.origin_x, pz - st.origin_z)
	check("and after coming back", absf(h0 - h2) < 0.002, "%.5f vs %.5f" % [h0, h2])
	ocean.set_process(true)
	var sh := st.chart.wave_scale(px, pz)
	check("ocean uses the chart's wave scale", absf(s0 - sh) < 1e-6 and sh > 0.2, "%.3f" % s0)

	# --- sleep
	var open := find_spot(st.chart, home, 100.0, 5000.0, 2000.0)
	check("found open sea for the sleep test", open != Vector2.ZERO, str(open))
	st.place_ship(open.x, open.y, 90.0)   # east
	await frames(10)
	var before := Vector2(st.ship_cx(), st.ship_cz())
	var expect := st.chart.sleep_travel(before.x, before.y, st.ship_chart_heading(), 4.0, st.sleep_speed_mps)
	var r := st.sleep(4.0)
	await frames(10)
	check("sleep result matches the chart", absf(float(r["x"]) - float(expect["x"])) < 0.01 and absf(float(r["z"]) - float(expect["z"])) < 0.01, "%s %.1f km" % [r["stop"], float(r["dist_m"]) / 1000.0])
	check("ship is at the slept position", absf(st.ship_cx() - float(r["x"])) < 0.5 and absf(st.ship_cz() - float(r["z"])) < 0.5, "%.2f / %.2f" % [st.ship_cx() - float(r["x"]), st.ship_cz() - float(r["z"])])
	check("ship stays near the Godot origin", Vector2(ship.global_position.x, ship.global_position.z).length() <= st.rebase_step_m * 0.75 + 1.0, str(ship.global_position))
	var dp := player.global_position - ship.global_position
	await frames(30)
	check("player still on the ship", (player.global_position - ship.global_position).length() < 8.0 and player.is_on_floor(), "%s floor %s" % [dp, player.is_on_floor()])

	# --- ports spawn and despawn on the rings
	var p2 := st.chart.get_port("AC00")
	var ang := 0.0
	for a2 in range(0, 360, 10):
		var dv := WorldChart.direction(float(a2))
		if c_depth_ok(st.chart, p2, dv, [5800.0, 7500.0, 8500.0]):
			ang = float(a2)
			break
	var dd := WorldChart.direction(ang)
	st.place_ship(p2["x"] + dd.x * 5800.0, p2["z"] + dd.y * 5800.0, 0.0)
	st._update_ports()
	check("port spawns inside 6 km", st.port_ids().has("AC00"))
	st.place_ship(p2["x"] + dd.x * 7500.0, p2["z"] + dd.y * 7500.0, 0.0)
	st._update_ports()
	check("port stays between 6 and 8 km", st.port_ids().has("AC00"))
	st.place_ship(p2["x"] + dd.x * 8500.0, p2["z"] + dd.y * 8500.0, 0.0)
	st._update_ports()
	await frames(2)
	check("port despawns outside 8 km", not st.port_ids().has("AC00"))

	# --- grounding
	var c: WorldChart = st.chart
	var shoal := find_spot(c, p2, 2.0, 2.95, 60.0)
	check("found a shoal to test on", shoal != Vector2.ZERO, str(shoal))
	if shoal != Vector2.ZERO:
		st.place_ship(shoal.x, shoal.y, 0.0)
		st._ground_check()
		check("aground on the shoal", st.aground, "%.2f m" % st.ship_depth_m())
	var deep := find_spot(c, p2, 80.0, 400.0, 1500.0)
	st.place_ship(deep.x, deep.y, 0.0)
	st._ground_check()
	check("afloat in deep water", not st.aground, "%.0f m" % st.ship_depth_m())
	check("waves are full size out there", ocean.wave_scale(0.0, 0.0) > 0.99, "%.2f" % ocean.wave_scale(0.0, 0.0))

	# --- the kinematic velocity spike when the ship is moved
	await frames(120)
	check("player settled on deck", player.is_on_floor())
	for pause in [true, false]:
		st.pause_player_on_move = pause
		await frames(30)
		var here_x := st.ship_cx()
		var here_z := st.ship_cz()
		st.relocate(here_x + 12000.0, here_z)   # the ship is only moved on the chart here, the spot may be land
		var worst := 0.0
		var max_drift := 0.0
		var rel0 := player.global_position - ship.global_position
		for i in 12:
			await physics_frame
			worst = maxf(worst, player.get_platform_velocity().length())
			max_drift = maxf(max_drift, ((player.global_position - ship.global_position) - rel0).length())
		print("INFO  pause_player_on_move=%s  worst platform velocity after a move %.1f m/s, player drift %.2f m" % [pause, worst, max_drift])
		check("player stays on the ship after a move (pause=%s)" % pause, (player.global_position - ship.global_position).length() < 8.0)
		if pause:
			check("no velocity spike with the pause", worst < 5.0, "%.1f m/s" % worst)
	print("RESULT: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
