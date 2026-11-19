extends SceneTree
## Headless checks for the wrapped world (2026-11-18): distances, headings, lookups, seams, routes.
## godot --headless --path <project> --script res://tests/wrap_chart_test.gd

var fails := 0


func _log(s: String) -> void:
	print(s)


func check(name: String, ok: bool, detail: String = "") -> void:
	_log("%s  %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


func _init() -> void:
	_chart_checks()
	_log("%s: %d failed" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(0 if fails == 0 else 1)


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


