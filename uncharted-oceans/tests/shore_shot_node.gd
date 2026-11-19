extends Node
## Looks at the world's coasts and saves screenshots, Standard water against High (the High setting's caustics, swash and
## rolling surf, and the coastal rocks). Needs a window:
##   godot --path uncharted-oceans --resolution 1280x720 --script res://tests/shore_shot.gd -- out=C:/dir [sea=2] [hour=11]
var out_dir := "C:/Users/Victus/Documents/GitHub/UnchartedOceans/renders/shore_shots_v2"
var sea := 2
var hour := 11.0

func _shot(path: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out_dir = a.substr(4)
		if a.begins_with("sea="): sea = int(a.substr(4))
		if a.begins_with("hour="): hour = float(a.substr(5))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var world := (load("res://scenes/world_capital_start.tscn") as PackedScene).instantiate()
	add_child(world)
	_run.call_deferred(world)

func _run(world: Node) -> void:
	for i in 90: await get_tree().physics_frame
	var st: WorldStreamer = world.get_node("WorldStreamer")
	var ocean: Ocean = world.get_node("Ocean")
	# freeze the weather's clock and set the sun, so every shot is lit the same
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
	ocean.set("sea_state", sea)
	var cam := Camera3D.new()
	cam.far = 20000.0
	cam.fov = 70.0
	world.add_child(cam)
	cam.current = true
	var c: WorldChart = st.chart
	# beach coasts (coast_kind() of world_ground.gdshaderinc, ported) away from ports, scanned from three starting latitudes
	var sites: Array = []
	for band in 3:
		var found := false
		var z := c.height_m * (0.1 + 0.3 * band)
		while z < c.height_m * (0.4 + 0.3 * band) and not found:
			var x := 20000.0
			while x < c.width_m - 20000.0 and not found:
				x += 1700.0
				if c.is_land(x, z) or c.shore_distance_m(x, z) > 500.0 or c.shore_distance_m(x, z) < 150.0:
					continue
				if not c.ports_within(x, z, 6000.0).is_empty():
					continue
				var best_d := INF
				var best_dir := Vector2.ZERO
				for k in 16:
					var dir := Vector2.from_angle(TAU * float(k) / 16.0)
					var d := 0.0
					while d < 1500.0 and not c.is_land(x + dir.x * d, z + dir.y * d):
						d += 5.0
					if d < best_d:
						best_d = d
						best_dir = dir
				if best_d < 900.0 and _beach(Vector2(x + best_dir.x * best_d, z + best_dir.y * best_d), c) > 0.8:
					sites.append({"x": x, "z": z, "dir": best_dir, "d": best_d})
					found = true
			z += 1500.0
	print("SITES ", sites.size())
	var si := 0
	for s in sites:
		st.relocate(s["x"], s["z"])
		for i in 60: await get_tree().physics_frame
		var ox := st.origin_x
		var oz := st.origin_z
		var dir: Vector2 = s["dir"]
		var d_land: float = s["d"]
		var views := [["aerial", maxf(d_land - 70.0, 0.0), 24.0, -3.0], ["low", maxf(d_land - 150.0, 0.0), 3.0, -1.0]]
		for v in views:
			var off: float = v[1]
			var px: float = s["x"] + dir.x * off - ox
			var pz: float = s["z"] + dir.y * off - oz
			var look := Vector3(px + dir.x * 40.0, float(v[3]), pz + dir.y * 40.0)
			cam.global_position = Vector3(px, float(v[2]), pz)
			cam.look_at(look)
			for q in [0, 1]:
				ocean.water_quality = q
				for i in 20: await get_tree().process_frame
				await _shot("%s/site%d_%s_%s.png" % [out_dir, si, v[0], "high" if q == 1 else "std"])
		si += 1
	print("DONE")
	get_tree().quit()


# ---- coast_kind() from world_ground.gdshaderinc, to pick sandy stretches (x = beach weight) ----
func _fr(v: float) -> float:
	return v - floor(v)

func _hash12(p: Vector2) -> float:
	var x := _fr(p.x * 0.1031)
	var y := _fr(p.y * 0.1031)
	var z := _fr(p.x * 0.1031)
	var d := x * (y + 33.33) + y * (z + 33.33) + z * (x + 33.33)
	x += d
	y += d
	z += d
	return _fr((x + y) * z)

func _vnoise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	return lerpf(lerpf(_hash12(i), _hash12(i + Vector2(1, 0)), u.x), lerpf(_hash12(i + Vector2(0, 1)), _hash12(i + Vector2(1, 1)), u.x), u.y)

func _fbm(p: Vector2) -> float:
	var a := 0.5
	var s := 0.0
	for i in 4:
		s += a * _vnoise(p)
		p = p * 2.03 + Vector2(17.3, 17.3)
		a *= 0.5
	return s

func _beach(cp: Vector2, c: WorldChart) -> float:
	var lat := clampf(cp.y / c.height_m, 0.0, 1.0)
	var a := _fbm(cp / 2600.0 + Vector2(41.3, 7.9)) + (lat - 0.5) * 0.12
	var b := _fbm(cp / 1700.0 + Vector2(-13.7, 88.1))
	var rock := 1.0 - smoothstep(0.38, 0.46, a)
	return (1.0 - rock) * smoothstep(0.42, 0.5, b)
