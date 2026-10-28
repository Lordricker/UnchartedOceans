extends SceneTree
## Headless checks for WorldChart.
## godot --headless --path <project> --script res://tests/world_chart_test.gd   (import the project once first)

var fails := 0

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s  %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1

func _init() -> void:
	var c := WorldChart.load_default()
	check("chart loads", c != null)
	if c == null:
		quit(1)
		return
	check("25 ports, 4 capitals", c.ports.size() == 25 and c.ports.filter(func(p): return p["tier"] == "capital").size() == 4, "(%d ports)" % c.ports.size())

	var land := 0
	var n := 0
	for yy in range(0, c.px_h, 8):
		for xx in range(0, c.px_w, 8):
			n += 1
			if c.is_land((xx + 0.5) * c.mpp, (yy + 0.5) * c.mpp):
				land += 1
	var lf := float(land) / float(n)
	check("land fraction near 37%", lf > 0.32 and lf < 0.42, "(%.1f%%)" % (lf * 100.0))

	var bad := ""
	for p in c.ports:
		var sd := c.shore_distance_m(p["x"], p["z"])
		if c.is_land(p["x"], p["z"]) or sd > 3.0 * c.mpp:
			bad += " %s(%.0f m)" % [p["id"], sd]
	check("every port is on the water at the coast", bad == "", bad)

	# open sea: find a cell far from any coast, march 20 km
	var open := Vector2.ZERO
	for yy in range(100, c.px_h - 100, 16):
		for xx in range(100, c.px_w - 100, 16):
			var x := (xx + 0.5) * c.mpp
			var z := (yy + 0.5) * c.mpp
			if c.shore_distance_m(x, z) > 40000.0:
				open = Vector2(x, z)
	check("found open ocean", open != Vector2.ZERO)
	var r := c.march(open.x, open.y, 45.0, 20000.0, {"stop_at_ports": false})
	check("open-sea march goes the full 20 km", r["stop"] == "none" and absf(r["dist_m"] - 20000.0) < 1.0, str(r))

	# march into land: from a capital, some heading runs a good way over water and then stops short of a coast
	var cap: Dictionary = c.ports.filter(func(p): return p["tier"] == "capital")[0]
	var found := false
	for pc in c.ports.filter(func(p): return p["tier"] == "capital"):
		for hd in range(0, 360, 15):
			var rr := c.march(pc["x"], pc["z"], float(hd), 300000.0, {"stop_at_ports": false})
			if rr["stop"] == "land" and rr["dist_m"] > 2000.0:
				found = true
				check("march stops before land (%s, heading %d)" % [pc["id"], hd], not c.is_land(rr["x"], rr["z"]) and c.shore_distance_m(rr["x"], rr["z"]) > 0.0, "(%.0f km)" % (rr["dist_m"] / 1000.0))
				break
		if found:
			break
	check("some heading from a capital hits land", found)

	# port ring: from any capital find a clear 9 km line out, then sail back toward it
	var ok_ring := false
	for pc in c.ports.filter(func(p): return p["tier"] == "capital"):
		for hd in range(0, 360, 10):
			var out := c.march(pc["x"], pc["z"], float(hd), 9000.0, {"stop_at_ports": false})
			if out["stop"] == "none":
				var back := c.march(out["x"], out["z"], fposmod(float(hd) + 180.0, 360.0), 15000.0)
				var d := WorldChart.distance_m(back["x"], back["z"], pc["x"], pc["z"])
				ok_ring = back["stop"] == "port_ring" and back["port"] == pc["id"] and absf(d - WorldChart.PORT_SPAWN_M) < 250.0
				check("sailing back stops at the port's 6 km ring", ok_ring, "(%s: %s, %.0f m from the port)" % [pc["id"], back["stop"], d])
				break
		if ok_ring:
			break
	check("found a clear approach to test the ring", ok_ring)

	# leaving a port is allowed (start inside the ring)
	var leave := c.march(cap["x"], cap["z"], 0.0, 1000.0, {"stop_at_ports": true})
	check("can leave a port (no instant ring stop)", leave["stop"] != "port_ring")

	var s := c.sleep_travel(open.x, open.y, 90.0, 8.0, 3.5, {"stop_at_ports": false, "land_margin_m": 0.0})
	check("8 h at 3.5 m/s is about 100.8 km when clear", s["stop"] != "none" or absf(s["dist_m"] - 100800.0) < 1.0, str(s["stop"]))
	check("horizon: eye 3 m about 6.2 km", absf(WorldChart.horizon_m(3.0) - 6183.0) < 10.0)
	check("horizon: 22 m light from 3 m about 23 km", absf(WorldChart.horizon_m(3.0, 22.0) - 22930.0) < 100.0, "(%.0f)" % WorldChart.horizon_m(3.0, 22.0))
	check("heading north is -Z", absf(WorldChart.direction(0.0).y + 1.0) < 1e-5 and absf(WorldChart.direction(90.0).x - 1.0) < 1e-5)
	check("heading_to east = 90", absf(WorldChart.heading_to(0, 0, 100, 0) - 90.0) < 1e-4)
	var d_deep := c.sea_depth_m(open.x, open.y)
	check("deep water is deep", d_deep > 1500.0, "(%.0f m)" % d_deep)
	# --- turning sleeps (the wheel bends the path into an arc: opts curve_per_m, radians per metre, + = clockwise)
	var q := WorldChart.arc_pos(0.0, 0.0, 0.0, PI * 0.5 * 1000.0, 1.0 / 1000.0)
	check("quarter circle to starboard from north ends east and north of the start (r = 1 km)", absf(q.x - 1000.0) < 1e-6 and absf(q.y + 1000.0) < 1e-6, str(q))
	check("the same quarter circle turns the heading 90 degrees", absf(WorldChart.arc_heading(0.0, PI * 0.5 * 1000.0, 1.0 / 1000.0) - 90.0) < 1e-6)
	var q2 := WorldChart.arc_pos(5.0, 7.0, 123.0, 4000.0, 0.0)
	var dq := WorldChart.direction(123.0) * 4000.0
	check("no curve is the old straight line", absf(q2.x - (5.0 + dq.x)) < 1e-6 and absf(q2.y - (7.0 + dq.y)) < 1e-6)
	var st0 := c.sleep_travel(open.x, open.y, 90.0, 1.0, 3.5, {"stop_at_ports": false, "land_margin_m": 0.0})
	check("a straight sleep wakes on the heading she lay down on", absf(float(st0["heading"]) - 90.0) < 1e-6, str(st0["heading"]))
	var sa := c.sleep_travel(open.x, open.y, 90.0, 1.0, 3.5, {"stop_at_ports": false, "land_margin_m": 0.0, "curve_per_m": 1.0 / 50000.0})
	var turned := rad_to_deg(3.5 * 3600.0 / 50000.0)
	check("a one hour arc to starboard turns her by dist / radius", sa["stop"] != "none" or absf(float(sa["heading"]) - (90.0 + turned)) < 1e-6, "%.3f deg (%.3f expected)" % [float(sa["heading"]) - 90.0, turned])
	var ep := WorldChart.arc_pos(open.x, open.y, 90.0, float(sa["dist_m"]), 1.0 / 50000.0)
	check("the arc ends where arc_pos says", absf(float(sa["x"]) - ep.x) < 1e-6 and absf(float(sa["z"]) - ep.y) < 1e-6)
	check("an arc to starboard bends south of an eastward line (z grows)", sa["stop"] != "none" or float(sa["z"]) > open.y + 100.0, "dz %.0f m" % (float(sa["z"]) - open.y))
	var sp_port := c.sleep_travel(open.x, open.y, 90.0, 1.0, 3.5, {"stop_at_ports": false, "land_margin_m": 0.0, "curve_per_m": -1.0 / 50000.0})
	check("an arc to port bends north (z shrinks)", sp_port["stop"] != "none" or float(sp_port["z"]) < open.y - 100.0)
	var loop := c.sleep_travel(open.x, open.y, 0.0, 8.0, 3.5, {"stop_at_ports": false, "land_margin_m": 0.0, "curve_per_m": deg_to_rad(4.0) / 3.5})
	check("hard over for 8 hours circles in place (about 50 m radius)", Vector2(float(loop["x"]) - open.x, float(loop["z"]) - open.y).length() < 120.0, "%.0f m from the start" % Vector2(float(loop["x"]) - open.x, float(loop["z"]) - open.y).length())
	print("FAILS: %d" % fails)
	quit(fails)
