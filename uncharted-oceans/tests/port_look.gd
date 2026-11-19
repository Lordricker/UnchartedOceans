extends SceneTree
## Camera looks at port models (needs a window):
## godot --path uncharted-oceans --resolution 1280x720 --script res://tests/port_look.gd -- ports=PortSmall_BS09,PortSmall_FF24 out=C:/dir
func _init() -> void:
	_run()
func _run() -> void:
	var ports := PackedStringArray(["PortSmall_BS09"])
	var outdir := "."
	for a in OS.get_cmdline_user_args():
		if a.begins_with("ports="): ports = a.substr(6).split(",")
		if a.begins_with("out="): outdir = a.substr(4)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.74, 0.88)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.85, 0.95)
	e.ambient_light_energy = 0.7
	we.environment = e
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -40, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	sea.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.08, 0.3, 0.42)
	sea.material_override = sm
	root.add_child(sea)
	var cam := Camera3D.new()
	cam.far = 3000.0
	root.add_child(cam)
	cam.current = true
	for p in ports:
		var ps := load("res://assets/port/%s.glb" % p) as PackedScene
		if ps == null:
			print("LOOK missing ", p)
			continue
		var inst := ps.instantiate()
		root.add_child(inst)
		for i in 15: await process_frame
		var shots := {
			"sea": [Vector3(0, 22, 110), Vector3(0, 6, -20)],
			"left": [Vector3(-90, 26, 40), Vector3(0, 5, 15)],
			"right": [Vector3(90, 26, 40), Vector3(0, 5, 15)],
			"quay": [Vector3(0, 4.5, 2), Vector3(0, 4, -40)],
			"pier": [Vector3(14, 5, 2), Vector3(-12, 4, -22)],
			"light": [Vector3(-40, 8, 20), Vector3(-40, 12, -30)],
		}
		for k in shots:
			cam.look_at_from_position(shots[k][0], shots[k][1])
			for i in 4: await process_frame
			var img := root.get_texture().get_image()
			var path := "%s/%s_%s.png" % [outdir, p, k]
			img.save_png(path)
			print("LOOK saved ", path)
		inst.queue_free()
		await process_frame
	quit()
