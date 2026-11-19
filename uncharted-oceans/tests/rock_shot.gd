extends SceneTree
## Finds the coast stretches with the most rocks (RockField) and photographs them, High water.
##   godot --path uncharted-oceans --resolution 1280x720 --script res://tests/rock_shot.gd -- out=C:/dir [hour=11]
var out_dir := "."
var hour := 11.0

func _shot(path: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out_dir = a.substr(4)
		if a.begins_with("hour="): hour = float(a.substr(5))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var world := (load("res://scenes/world_capital_start.tscn") as PackedScene).instantiate()
	root.add_child(world)
	_run.call_deferred(world)

func _run(world: Node) -> void:
	for i in 90: await physics_frame
	var st: WorldStreamer = world.get_node("WorldStreamer")
	var rf = st.get("_rocks")
	var ocean: Ocean = world.get_node("Ocean")
	for n in world.find_children("*", "", true, false):
		var sc = n.get_script()
		if sc != null and str(sc.resource_path).ends_with("world_weather.gd"):
			n.set_process(false)
			n.set_physics_process(false)
	var sky = world.get_node_or_null("SkySystem")
	if sky:
		sky.set("time_hours", hour)
		sky.set("overcast", 0.0)
		sky.set("storm", 0.0)
		sky.set("coverage", 0.25)
	ocean.set("sea_state", 2)
	ocean.water_quality = 1
	var cam := Camera3D.new()
	cam.far = 20000.0
	cam.fov = 70.0
	world.add_child(cam)
	cam.current = true
	var c: WorldChart = st.chart
	if rf == null:
		print("NO ROCKFIELD")
		quit()
		return
	# rocks counted in a 3 x 3 block of scatter cells around coastal sample points
	var cands: Array = []
	var cell := 160.0
	var z := 8000.0
	while z < c.height_m - 8000.0:
		var x := 8000.0
		while x < c.width_m - 8000.0:
			x += 2400.0
			if c.is_land(x, z) or c.shore_distance_m(x, z) > 900.0:
				continue
			var ci := int(floor(x / cell))
			var cj := int(floor(z / cell))
			var n := 0
			var sum := Vector2.ZERO
			for di in range(-1, 2):
				for dj in range(-1, 2):
					for rk in rf.call("_cell", 0, ci + di, cj + dj):
						n += 1
						sum += Vector2(rk["x"], rk["z"])
			if n >= 5:
				cands.append({"n": n, "p": sum / float(n)})
		z += 2400.0
	cands.sort_custom(func(a, b): return a["n"] > b["n"])
	print("CANDS ", cands.size(), " best ", cands[0]["n"] if cands.size() > 0 else 0)
	var used: Array = []
	var si := 0
	for cd in cands:
		var p: Vector2 = cd["p"]
		var near := false
		for u in used:
			if p.distance_to(u) < 20000.0:
				near = true
		if near:
			continue
		used.append(p)
		# land direction from the cluster
		var best_d := INF
		var best_dir := Vector2.UP
		for k in 16:
			var dir := Vector2.from_angle(TAU * float(k) / 16.0)
			var d := 0.0
			while d < 2000.0 and not c.is_land(p.x + dir.x * d, p.y + dir.y * d):
				d += 10.0
			if d < best_d:
				best_d = d
				best_dir = dir
		var hb := get_first_node_in_group("ship_harbor")
		if hb != null and bool(hb.get("moored")):
			hb.call("cast_off")
		st.place_ship(p.x, p.y, rad_to_deg(atan2(best_dir.x, -best_dir.y)))
		var ship_n := world.get_node("ShipRig")
		ship_n.set_physics_process(false)
		for i in 90: await physics_frame
		# where do the drawn rocks actually stand, relative to the ship?
		var drawn := 0
		var nearest := INF
		for kid in rf.get_children():
			if kid is MultiMeshInstance3D:
				var mm: MultiMesh = kid.multimesh
				drawn += mm.instance_count
				for j in mm.instance_count:
					var o: Vector3 = mm.get_instance_transform(j).origin
					nearest = minf(nearest, Vector2(o.x - (p.x - st.origin_x), o.z - (p.y - st.origin_z)).length())
		print("DBG last_c ", rf.get("_last_c"), " ship_c ", Vector2(st.ship_cx(), st.ship_cz()), " cam ", cam.global_position, " kit_ok ", [rf.get("_kit")[0]["ok"], rf.get("_kit")[5]["ok"]])
		var cells_n := 0
		for di in range(-1, 2):
			for dj in range(-1, 2):
				cells_n += (rf.call("_cell", 0, int(floor(p.x / 160.0)) + di, int(floor(p.y / 160.0)) + dj) as Array).size()
		print("DBG rocks_in_cells ", cells_n)
		rf.call("_rebuild", Vector2(st.ship_cx(), st.ship_cz()), Vector2(st.origin_x, st.origin_z), cam.global_position, 1.0)
		var d2 := 0
		for kid in rf.get_children():
			if kid is MultiMeshInstance3D:
				d2 += kid.multimesh.instance_count
		print("DBG drawn_after_manual_rebuild ", d2)
		print("SITE ", si, " cluster ", p, " n ", cd["n"], " land_d ", best_d, " dir ", best_dir, " drawn ", drawn, " nearest_rock_m ", nearest, " shore_d ", c.shore_distance_m(p.x, p.y))
		var ox := st.origin_x
		var oz := st.origin_z
		var cx := p.x - best_dir.x * 90.0 - ox          # stand seaward of the cluster, looking in at it and the shore
		var cz := p.y - best_dir.y * 90.0 - oz
		cam.global_position = Vector3(cx, 4.5, cz)
		cam.look_at(Vector3(p.x + best_dir.x * 60.0 - ox, 1.0, p.y + best_dir.y * 60.0 - oz))
		for i in 40: await process_frame
		await _shot("%s/rocks%d_low.png" % [out_dir, si])
		cam.global_position = Vector3(p.x - best_dir.x * 30.0 - ox, 2.2, p.y - best_dir.y * 30.0 - oz)
		cam.look_at(Vector3(p.x + best_dir.x * 25.0 - ox, 0.3, p.y + best_dir.y * 25.0 - oz))
		await _shot("%s/rocks%d_close.png" % [out_dir, si])
		cam.global_position = Vector3(cx - best_dir.x * 60.0, 26.0, cz - best_dir.y * 60.0)
		cam.look_at(Vector3(p.x - ox, 0.0, p.y - oz))
		await _shot("%s/rocks%d_aerial.png" % [out_dir, si])
		si += 1
		if si >= 2:
			break
	print("DONE")
	quit()
