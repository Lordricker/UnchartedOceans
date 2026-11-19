class_name WorldRoute
extends RefCounted
## Plans a sea route between two chart points: a breadth-first search over a coarse grid of open water
## (at least `clearance_m` from any coast), pulled straight into a few legs. Returns the waypoints after
## the start; the last one is the goal. If the straight line is already clear, that is the whole route.
## The streamer shows the next waypoint as the marker; sleep wakes up near each one.
## The world wraps (2026-11-18): the grid wraps too, so a route may run off one edge and in at the other. The waypoints
## then follow on from each other without a jump, so some lie outside the chart (x < 0 or past width_m); WorldChart's
## distance_m and heading_to read them the short way round.

const STEP_M := 1500.0
## Near the start and the goal the route is the gulf or harbour mouth: legs there are sailed by sight,
## so tiny legs are merged even if the merged line clips the coast.
const HARBOUR_ZONE_M := 14000.0

## Waypoints from (ax, az) to (bx, bz) as Vector2 chart positions. Empty = no sea route found.
## start_in_harbour: the start is a port or harbour mouth, so its first legs are sailed by sight (merged).
static func plan(chart: WorldChart, ax: float, az: float, bx: float, bz: float,
		clearance_m: float = 1500.0, min_leg_m: float = 6000.0, line_margin_m: float = 1500.0, start_in_harbour: bool = false) -> Array:
	var goal := WorldChart.near(Vector2(bx, bz), Vector2(ax, az))      # the copy of the goal the short way round
	if line_clear(chart, Vector2(ax, az), goal, line_margin_m):
		return [goal]
	var nx := int(chart.width_m / STEP_M)
	var nz := int(chart.height_m / STEP_M)
	var sx := posmod(int(round(ax / STEP_M)), nx)
	var sz := posmod(int(round(az / STEP_M)), nz)
	var gx := posmod(int(round(bx / STEP_M)), nx)
	var gz := posmod(int(round(bz / STEP_M)), nz)
	# open-water mask on the grid (ports sit in gulfs, so cells near the start and goal are always allowed)
	var open := PackedByteArray()
	open.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var px := float(ix) * STEP_M
			var pz := float(iz) * STEP_M
			var near_end := (_wd(ix, sx, nx) <= 6 and _wd(iz, sz, nz) <= 6) or (_wd(ix, gx, nx) <= 6 and _wd(iz, gz, nz) <= 6)
			if near_end:
				open[iz * nx + ix] = 1 if not chart.is_land(px, pz) else 0
			else:
				open[iz * nx + ix] = 1 if chart.shore_distance_m(px, pz) >= clearance_m else 0
	var prev := PackedInt32Array()
	prev.resize(nx * nz)
	prev.fill(-2)
	var queue := PackedInt32Array()
	queue.append(sz * nx + sx)
	prev[sz * nx + sx] = -1
	var head := 0
	var found := -1
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
	while head < queue.size():
		var cur := queue[head]
		head += 1
		var cx := cur % nx
		var cz := cur / nx
		if _wd(cx, gx, nx) <= 3 and _wd(cz, gz, nz) <= 3:
			found = cur
			break
		for d in dirs:
			var mx: int = posmod(cx + d.x, nx)       # the grid wraps with the world
			var mz: int = posmod(cz + d.y, nz)
			var mi := mz * nx + mx
			if prev[mi] != -2 or open[mi] == 0:
				continue
			prev[mi] = cur
			queue.append(mi)
	if found < 0:
		return []
	var path: Array = []
	var k := found
	while k != -1:
		path.push_front(Vector2(float(k % nx) * STEP_M, float(k / nx) * STEP_M))
		k = prev[k]
	# lay the cells end to end, each the copy nearest the one before, so the path has no jump at the seam
	var ref := Vector2(ax, az)
	for n0 in path.size():
		path[n0] = WorldChart.near(path[n0], ref)
		ref = path[n0]
	goal = WorldChart.near(goal, ref)
	# pull the path straight: from each kept point, jump to the furthest cell still in clear line
	var pts: Array = [Vector2(ax, az)]
	var i := 0
	while i < path.size() - 1:
		var j := path.size() - 1
		while j > i + 1:
			if line_clear(chart, pts[pts.size() - 1], path[j], line_margin_m):
				break
			j -= 1
		pts.append(path[j])
		i = j
	pts.append(goal)
	pts.remove_at(0)
	# drop waypoints that would make tiny legs (the winding gulf mouths), but only where the leg that
	# skips them is still a clear line; keep the goal
	var out: Array = []
	var last := Vector2(ax, az)
	for n in pts.size():
		var p: Vector2 = pts[n]
		if n == pts.size() - 1 or last.distance_to(p) >= min_leg_m:
			out.append(p)
			last = p
		elif (start_in_harbour and last.distance_to(Vector2(ax, az)) < HARBOUR_ZONE_M) or p.distance_to(goal) < HARBOUR_ZONE_M \
				or line_clear(chart, last, pts[n + 1], line_margin_m):
			continue
		else:
			out.append(p)
			last = p
	return out


## True if the straight line a -> b stays over open water (the coast margin is 0 by default).
static func line_clear(chart: WorldChart, a: Vector2, b: Vector2, margin_m: float) -> bool:
	var d := WorldChart.distance_m(a.x, a.y, b.x, b.y)
	if d < 1.0:
		return true
	var hd := WorldChart.heading_to(a.x, a.y, b.x, b.y)
	var r := chart.march(a.x, a.y, hd, d, {"stop_at_ports": false, "land_margin_m": margin_m, "step_m": 300.0})
	return float(r["dist_m"]) >= d - 1.0


## Cells apart along a grid axis of n cells that wraps.
static func _wd(a: int, b: int, n: int) -> int:
	var d := absi(a - b) % n
	return mini(d, n - d)
