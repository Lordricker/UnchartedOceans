extends Node
## Checks the wrapped world and fast time (x1-x8, only while holding the wheel) (2026-11-18). Runs the main scene (world_capital_start) under it, writes
## res://tests/wrap_fasttime_report.txt (and prints it), then quits.

var out := PackedStringArray()
var fails := 0
var world: Node
var streamer: WorldStreamer
var ship: Node3D
var player: Node3D


func _ready() -> void:
	_run.call_deferred()


func _log(s: String) -> void:
	out.append(s)
	print(s)


func check(name: String, ok: bool, detail: String = "") -> void:
	_log("%s  %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _run() -> void:
	await _wait(0.5)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_chart_checks()
	await _wait(3.0)
	world = get_parent().get_node("World")
	streamer = world.get_node("WorldStreamer") as WorldStreamer
	ship = world.get_node("ShipRig") as Node3D
	player = world.get_node("Player") as Node3D
	await _fast_time_checks()
	await _seam_checks()
	_finish()


# ------------------------------------------------------------------ the chart on its own

func _chart_checks() -> void:
	var c := WorldChart.load_default()
	var w := c.width_m
	var h := c.height_m
	check("wrap size set", is_equal_approx(WorldChart.wrap_w, w) and is_equal_approx(WorldChart.wrap_h, h))
	check("distance across the east-west seam", absf(WorldChart.distance_m(w - 1000.0, 5000.0, 1000.0, 5000.0) - 2000.0) < 0.01)
	check("distance across the north-south seam", absf(WorldChart.distance_m(5000.0, h - 500.0, 5000.0, 500.0) - 1000.0) < 0.01)
	check("heading across the seam is east", absf(WorldChart.heading_to(w - 1000.0, 5000.0, 1000.0, 5000.0) - 90.0) < 0.01)
	check("heading across the seam is south", absf(WorldChart.heading_to(5000.0, h - 500.0, 5000.0, 500.0) - 180.0) < 0.01)
	var same := true
	for i in 200:
		var x := randf() * w
		var z := randf() * h
		if absf(c.shore_distance_m(x, z) - c.shore_distance_m(x + w, z - h)) > 0.01 or c.is_land(x, z) != c.is_land(x - w, z + h):
			same = false
	check("lookups repeat every lap", same)
	# no step in the shore distance at the seams
	var worst := 0.0
	for i in 64:
		var z := (float(i) + 0.5) / 64.0 * h
		worst = maxf(worst, absf(c.shore_distance_m(w - 50.0, z) - c.shore_distance_m(w + 50.0, z)))
		var x := (float(i) + 0.5) / 64.0 * w
		worst = maxf(worst, absf(c.shore_distance_m(x, h - 50.0) - c.shore_distance_m(x, h + 50.0)))
	check("shore distance has no step at the seams", worst < 2.0 * c.mpp, "(worst %.0f m)" % worst)
	var r := c.march(w - 4000.0, h * 0.5, 90.0, 30000.0, {"stop_at_ports": false})
	_log("  march east over the seam from x=%.0f: stop=%s dist=%.0f x=%.0f" % [w - 4000.0, r["stop"], r["dist_m"], r["x"]])
	check("no edge stop any more", String(r["stop"]) != "edge")
	check("near() gives the copy by the ship", WorldChart.near(Vector2(1000.0, 1000.0), Vector2(w - 500.0, h - 500.0)).is_equal_approx(Vector2(w + 1000.0, h + 1000.0)))
	# a route between two open-sea points either side of the seam goes the short way
	var a := _open_sea(c, w - 9000.0, h * 0.5)
	var b := _open_sea(c, 9000.0, h * 0.5)
	var route := WorldRoute.plan(c, a.x, a.y, b.x, b.y)
	var length := 0.0
	var p := a
	for q: Vector2 in route:
		length += WorldChart.distance_m(p.x, p.y, q.x, q.y)
		p = q
	_log("  route over the seam %s -> %s: %d legs, %.0f km (%s)" % [str(a.round()), str(b.round()), route.size(), length / 1000.0, str(route)])
	check("route over the seam is short", route.size() > 0 and length < 40000.0, "(%.0f km)" % (length / 1000.0))


func _open_sea(c: WorldChart, x: float, z: float) -> Vector2:
	for k in 400:
		var zz := fposmod(z + float(k) * 997.0, c.height_m)
		if c.shore_distance_m(x, zz) > 20000.0:
			return Vector2(x, zz)
	return Vector2(x, z)


# ------------------------------------------------------------------ fast time in the game

func _fast_time_checks() -> void:
	var wx := get_tree().get_first_node_in_group("weather")
	_log("start: held=%s ship chart (%.0f, %.0f) origin (%.0f, %.0f)" % [str(streamer.ship_held()), streamer.ship_cx(), streamer.ship_cz(), streamer.origin_x, streamer.origin_z])
	streamer.set_fast_forward(3)
	check("keys do nothing without the wheel", streamer.fast_forward_i == 0 and is_equal_approx(Engine.time_scale, 1.0))
	# cast off and take her out to open sea under the test engine
	var hb := ship.get_node_or_null("ShipHarbor")
	if hb and bool(hb.get("moored")):
		hb.call("release_mooring")
	var sails = ship.get("sails")
	if sails:
		sails.set_physics_process(false)
	ship.set("underway", true)
	var sea := _open_sea(streamer.chart, 300000.0, 100000.0)
	streamer.place_ship(sea.x, sea.y, 90.0)
	await _wait(1.5)
	await _take_wheel()
	var h1 := float(wx.game_hours)
	var x1 := streamer.ship_cx()
	var t0 := Time.get_ticks_msec()
	streamer.set_fast_forward(3)
	check("x8 while holding the wheel", streamer.fast_forward_i == 3 and is_equal_approx(Engine.time_scale, 8.0))
	var off0 := ship.to_local(player.global_position)
	await get_tree().create_timer(3.0, true, false, true).timeout       # 3 real seconds
	var real_s := float(Time.get_ticks_msec() - t0) / 1000.0
	var moved := WorldChart.distance_m(x1, 0.0, streamer.ship_cx(), 0.0)
	var dh := float(wx.game_hours) - h1
	var off1 := ship.to_local(player.global_position)
	_log("  %.1f real s at x8: moved %.0f m, clock %.3f h, player on deck moved %.2f m, fps %d" % [real_s, moved, dh, (off1 - off0).length(), Engine.get_frames_per_second()])
	check("x8: she covers about 8x the ground", moved > real_s * 2.6 * 6.0, "(%.0f m)" % moved)
	check("x8: the clock runs about 8x", dh > real_s * 6.0 / 3600.0 and dh < real_s * 10.0 / 3600.0, "(%.4f h)" % dh)
	check("x8: player still on the deck by the wheel", (off1 - off0).length() < 1.5, "(%.2f m)" % (off1 - off0).length())
	check("x8: still holding the wheel", streamer.wheel_held())
	_let_go()
	await _wait(0.3)
	check("let go: back to x1", streamer.fast_forward_i == 0 and is_equal_approx(Engine.time_scale, 1.0))


# ------------------------------------------------------------------ over the seam in the game

func _seam_checks() -> void:
	var c := streamer.chart
	var w := c.width_m
	var sea := _open_sea(c, w - 150.0, 150000.0)
	streamer.place_ship(sea.x, sea.y, 90.0)
	await _wait(1.5)
	var lap0 := streamer.get("_lap") as Vector2
	_log("seam start: ship chart (%.0f, %.0f) origin %.0f" % [streamer.ship_cx(), streamer.ship_cz(), streamer.origin_x])
	await _wait(8.0)       # about 20 m at the test engine's 2.6 m/s... move her over by hand if she is slow
	if streamer.ship_cx() < w:
		ship.global_position.x += w - streamer.ship_cx() + 200.0
	await _wait(0.5)
	_log("  over the seam: ship chart x %.0f" % streamer.ship_cx())
	streamer.relocate(streamer.ship_cx(), streamer.ship_cz())      # the rebase that happens every 20 km
	await _wait(1.0)
	var lap1 := streamer.get("_lap") as Vector2
	_log("  after the rebase: ship chart (%.0f, %.0f) origin %.0f lap %s -> %s" % [streamer.ship_cx(), streamer.ship_cz(), streamer.origin_x, str(lap0), str(lap1)])
	check("came in at the west edge", streamer.ship_cx() >= 0.0 and streamer.ship_cx() < 5000.0)
	check("the origin is back on the chart's copy", streamer.origin_x >= 0.0 and streamer.origin_x <= w)
	check("the waves were told the lap", is_equal_approx(lap1.x - lap0.x, w), "(%.0f)" % (lap1.x - lap0.x))
	check("the sea under her is still sea", not c.is_land(streamer.ship_cx(), streamer.ship_cz()))


## Stand the player just aft of the wheel and take hold of it (as a click on the rim would).
func _take_wheel() -> void:
	var wheel := ship.get_node_or_null("ShipWheel")
	if wheel == null or wheel.get("_wheel") == null:
		_log("  no ShipWheel on this ship")
		return
	var hub: Vector3 = (wheel.get("_wheel") as Node3D).global_position
	if "velocity" in player:
		player.set("velocity", Vector3.ZERO)
	player.global_position = hub + ship.global_basis.z.normalized() * 0.8 + Vector3.DOWN * 1.1
	await _wait(0.4)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	wheel.set("held", true)
	await _wait(0.1)
	_log("  took the wheel: held=%s" % str(streamer.wheel_held()))


func _let_go() -> void:
	var wheel := ship.get_node_or_null("ShipWheel")
	if wheel and wheel.has_method("_release"):
		wheel.call("_release")


func _finish() -> void:
	_log("%s: %d failed" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	var f := FileAccess.open("res://tests/wrap_fasttime_report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out) + "\n")
		f.close()
	await _wait(0.5)
	get_tree().quit(0 if fails == 0 else 1)
