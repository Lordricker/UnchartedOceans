extends SceneTree
## Renders the cutter in the test world with the sails set: godot --path uncharted-oceans --resolution 1280x720 --script res://tests/cutter_rig_shot.gd -- out=C:/dir
func _shot(path: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(path)
	print("RENDER saved ", path)
func _init() -> void:
	var outdir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): outdir = a.substr(4)
	var world := (load("res://scenes/world_cutter_test.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 240: await physics_frame
	var rig := world.get_node("ShipRig") as Node3D
	for n in world.find_children("*", "", true, false):
		var sc = n.get_script()
		if sc != null and str(sc.resource_path).ends_with("ship_sails.gd"):
			print("RENDER sails node ", n.name, " recs=", n.get("recs").size())
			for ln in n.get("sheet_lines"):
				var pts: PackedVector3Array = n.call("line_points", ln.spec)
				print("RENDER line ", ln.name, " ", pts)
			for r in n.get("recs"):
				n.call("set_progress", r.id, 0.0)
				print("RENDER sail ", r.id)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.far = 3000.0
	cam.fov = 75.0
	for i in 200: await process_frame
	var shots := [
		["head_side", Vector3(6.5, 5.5, 0.2), Vector3(0.0, 5.6, 0.2)],
		["sheet_side", Vector3(4.2, 2.4, 4.3), Vector3(0.0, 1.9, 4.2)],
		["sheet_top", Vector3(0.3, 4.6, 6.2), Vector3(0.0, 1.8, 4.2)],
		["stern", Vector3(0.5, 2.1, 2.2), Vector3(0.0, 1.3, 5.2)],
		["stern_side", Vector3(-3.0, 2.6, 7.5), Vector3(0.0, 1.6, 4.0)],
		["rig", Vector3(7.0, 4.5, 4.5), Vector3(0.0, 3.3, 0.5)],
		["masthead", Vector3(3.0, 5.5, -4.0), Vector3(0.0, 6.0, -1.4)],
	]
	for s in shots:
		var from: Vector3 = rig.to_global(s[1])
		cam.look_at_from_position(from, rig.to_global(s[2]))
		await _shot(outdir + "/" + str(s[0]) + ".png")
	quit()
