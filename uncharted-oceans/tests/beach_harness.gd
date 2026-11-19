extends SceneTree
## Renders beaches for checking the shore water. Args after --: out=DIR q=0|1 sea=0..3 sites=N hour=H
var out_dir := "/tmp/shots"
var q := 1
var sea := 1
var nsites := 2
var hour := 11.0
var tag := ""
var _g
func g_y(p: Vector2) -> float:
	return _g.terrain_y(p.x, p.y)

func _shot(path: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2: continue
		match kv[0]:
			"out": out_dir = kv[1]
			"q": q = int(kv[1])
			"sea": sea = int(kv[1])
			"sites": nsites = int(kv[1])
			"hour": hour = float(kv[1])
			"tag": tag = kv[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var src := load("res://scenes/world_capital_start.tscn") as PackedScene
	var st := src.get_state()
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	# environment, sun, sky and sea as the game scene has them
	var full := (load("res://scenes/world_capital_start.tscn") as PackedScene)
	var env_node := WorldEnvironment.new()
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	world.add_child(sun)
	var sk := Node.new()
	sk.name = "SkySystem"
	# pull Env and SeaMat from the scene file
	var tmp := full.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	var we := tmp.get_node("WorldEnvironment") as WorldEnvironment
	env_node.environment = we.environment
	world.add_child(env_node)
	sun.transform = (tmp.get_node("Sun") as Node3D).transform
	sun.light_color = Color(1, 0.93, 0.82)
	sun.shadow_enabled = true
	var sea_mat := (tmp.get_node("Ocean") as MeshInstance3D).material_override
	tmp.free()
	sk.set_script(load("res://scripts/sky_system.gd"))
	sk.set("debug_overlay", false)
	world.add_child(sk)
	var ocean := MeshInstance3D.new()
	ocean.name = "Ocean"
	ocean.material_override = sea_mat
	ocean.set_script(load("res://scripts/ocean.gd"))
	ocean.set("curvature_radius_m", 6370000.0)
	ocean.set("radius", 24000.0)
	world.add_child(ocean)
	var cam := Camera3D.new()
	cam.far = 30000.0
	cam.fov = 70.0
	world.add_child(cam)
	cam.current = true
	var chart := WorldChart.load_default()
	var ground = load("res://scripts/world_ground.gd").new(chart)
	_g = ground
	ocean.set("ground", ground)
	var terr := WorldTerrain.new()
	terr.curvature_radius_m = 6370000.0
	terr.ocean = ocean
	world.add_child(terr)
	for i in 10: await process_frame
	sk.set("time_hours", hour)
	sk.set("overcast", 0.0)
	sk.set("storm", 0.0)
	sk.set("coverage", 0.2)
	ocean.set("sea_state", sea)
	ocean.set("water_quality", q)
	var sites := _find_sites(chart, ground)
	print("SITES ", sites.size())
	var si := 0
	for s in sites:
		if si >= nsites: break
		var ox := roundf(float(s.x) / 5000.0) * 5000.0
		var oz := roundf(float(s.z) / 5000.0) * 5000.0
		ocean.call("set_world", chart, ox, oz)
		terr.set_world(chart, ox, oz)
		var dir: Vector2 = s.dir   # toward land
		var wl: Vector2 = s.wl     # waterline point (chart)
		# views: from a deck 120 m out, 4 m up; low close 35 m out; aerial
		var side := Vector2(-dir.y, dir.x)
		# (name, camera chart xz, camera height, look-at chart xz)
		var views := [
			["deck", wl - dir * 130.0, 4.5, wl + dir * 20.0 + side * 70.0],
			["beach", wl + dir * 7.0, 1.7 + maxf(g_y(wl + dir * 7.0), 0.0), wl - dir * 35.0 + side * 60.0],
			["aerial", wl - dir * 60.0 - side * 40.0, 40.0, wl + side * 40.0],
		]
		for v in views:
			var p: Vector2 = v[1]
			var t: Vector2 = v[3]
			cam.global_position = Vector3(p.x - ox, float(v[2]), p.y - oz)
			cam.look_at(Vector3(t.x - ox, 0.0, t.y - oz))
			for i in 30: await process_frame
			await _shot("%s/%s%d_%s.png" % [out_dir, tag, si, v[0]])
		si += 1
	print("DONE")
	quit()

## Sandy coast points away from ports: the waterline point (chart xz) and the direction toward land.
func _find_sites(c: WorldChart, g) -> Array:
	var out := []
	for band in 3:
		var z := c.height_m * (0.15 + 0.28 * band)
		var found := false
		while z < c.height_m * (0.4 + 0.28 * band) and not found:
			var x := 30000.0
			while x < c.width_m - 30000.0 and not found:
				x += 2300.0
				var sd := c.shore_distance_m(x, z)
				if c.is_land(x, z) or sd > 1500.0 or sd < 300.0: continue
				if not c.ports_within(x, z, 8000.0).is_empty(): continue
				# march toward the nearest land along 16 directions; waterline = where terrain_y crosses 0
				var best := INF
				var bdir := Vector2.ZERO
				for k in 16:
					var d := Vector2.from_angle(TAU * k / 16.0)
					var t := 0.0
					while t < 2000.0 and g.terrain_y(x + d.x * t, z + d.y * t) < 0.0:
						t += 4.0
					if t < best:
						best = t
						bdir = d
				if best >= 2000.0: continue
				var wl := Vector2(x, z) + bdir * best
				if g.coast_kind(wl).x < 0.8: continue
				out.append({"x": wl.x, "z": wl.y, "wl": wl, "dir": bdir})
				found = true
			z += 1700.0
	return out
