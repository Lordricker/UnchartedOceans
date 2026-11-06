extends SceneTree
## Renders frames (needs a window): godot --path uncharted-oceans --resolution 1280x720 --script res://tests/cutter_render.gd -- view=scene|sea out=C:/dir
func _shot(path: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("RENDER saved ", path, " ", img.get_size())
func _init() -> void:
	var view := "scene"
	var outdir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("view="): view = a.substr(5)
		if a.begins_with("out="): outdir = a.substr(4)
	if view == "scene":
		var sc := (load("res://scenes/ships/cutter.tscn") as PackedScene).instantiate()
		root.add_child(sc)
		var we := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.25, 0.26, 0.29)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.85, 0.85, 0.9)
		e.ambient_light_energy = 0.8
		we.environment = e
		root.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, -35, 0)
		root.add_child(sun)
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.current = true
		cam.look_at_from_position(Vector3(10, 6.5, 9), Vector3(0, 2.0, 0))
		for i in 20: await process_frame
		await _shot(outdir + "/scene_a.png")
		cam.look_at_from_position(Vector3(-9, 4.0, -8), Vector3(0, 2.0, 0))
		await _shot(outdir + "/scene_b.png")
		quit()
		return
	var world := (load("res://scenes/world_cutter_test.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 240: await physics_frame
	var rig := world.get_node("ShipRig") as Node3D
	var ocean := world.get_node("Ocean")
	for n in world.find_children("*", "", true, false):
		var sc = n.get_script()
		if sc != null and (str(sc.resource_path).ends_with("sea_wind.gd") or str(sc.resource_path).ends_with("world_weather.gd")):
			n.set_process(false)
			n.set_physics_process(false)
	var hb := get_first_node_in_group("ship_harbor")
	if hb != null and bool(hb.get("moored")): hb.call("cast_off")
	ocean.set("sea_state", 3)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.far = 3000.0
	for i in 900: await process_frame
	print("RENDER sea_state=", ocean.get("sea_state"))
	for shot in 6:
		var side := 1.0 if shot % 2 == 0 else -1.0
		var right := rig.global_transform.basis.x
		var p := rig.global_position + right * 11.0 * side
		var h: float = ocean.call("get_height", p.x, p.z)
		cam.look_at_from_position(Vector3(p.x, h + 0.7, p.z), rig.global_position + Vector3(0, 1.8, 0))
		print("RENDER shot ", shot, " ship above the plane under her: ", snappedf(rig.position.y - (rig.call("water_pose") as Vector3).x, 0.01), " roll=", snappedf(rad_to_deg(float(rig.get("_roll"))), 0.1), " pitch=", snappedf(rad_to_deg(float(rig.get("_pitch"))), 0.1))
		await _shot(outdir + "/sea_%d.png" % shot)
		for i in 150: await process_frame
	quit()
