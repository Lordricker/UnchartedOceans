extends SceneTree
## Plays the real world scene starting moored in each port, then flies a camera around it (needs a window):
## godot --path uncharted-oceans --resolution 1280x720 --script res://tests/port_visit.gd -- ports=BC01,DC03 out=C:/dir hold=3
func _init() -> void:
	_run()
func _run() -> void:
	var ids := PackedStringArray(["BS09"])
	var outdir := "."
	var hold := 2.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("ports="): ids = a.substr(6).split(",")
		if a.begins_with("out="): outdir = a.substr(4)
		if a.begins_with("hold="): hold = float(a.substr(5))
	for id in ids:
		var world := (load("res://scenes/world_capital_start.tscn") as PackedScene).instantiate()
		var st := world.get_node("WorldStreamer")
		st.set("home_port_id", id)
		st.set("start_moored", true)
		root.add_child(world)
		for i in 240: await physics_frame
		var port: Node3D = st.get("_ports").get(id)
		if port == null:
			print("VISIT no port node ", id)
			world.queue_free()
			continue
		var cam := Camera3D.new()
		cam.far = 6000.0
		world.add_child(cam)
		cam.current = true
		var t := port.global_transform
		var shots := {
			"sea": [Vector3(0, 30, 130), Vector3(0, 6, -20)],
			"left": [Vector3(-110, 35, 50), Vector3(0, 6, 10)],
			"quay": [Vector3(0, 5, 4), Vector3(0, 5, -40)],
			"harbour": [Vector3(30, 14, 70), Vector3(-5, 4, 0)],
		}
		if id.substr(1, 1) == "C":
			shots = {
				"wide": [Vector3(0, 70, 480), Vector3(0, 8, 0)],
				"west": [Vector3(-260, 45, 300), Vector3(-160, 8, 0)],
				"east": [Vector3(260, 45, 300), Vector3(160, 8, 0)],
				"berth": [Vector3(-30, 14, 90), Vector3(-30, 6, 0)],
			}
		for k in shots:
			cam.global_position = t * (shots[k][0] as Vector3)
			cam.look_at(t * (shots[k][1] as Vector3))
			await create_timer(hold).timeout
			var img := root.get_texture().get_image()
			img.save_png("%s/visit_%s_%s.png" % [outdir, id, k])
			print("VISIT saved ", id, " ", k)
		world.queue_free()
		await process_frame
	quit()
