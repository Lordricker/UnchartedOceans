extends Node
## Diagnostic 2: loads the real sky_test scene, flips through its presets and logs what the screen shows (DIAG2 lines).

func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	var scene: Node = (load("res://scenes/sky_test.tscn") as PackedScene).instantiate()
	add_child(scene)
	for i in 40:
		await get_tree().process_frame
	var sky = scene.get_node("SkySystem")
	var cam: Camera3D = scene.get_node("Camera3D")
	print("DIAG2 camera current=", cam.current, "  viewport camera=", get_viewport().get_camera_3d().get_path(), "  pos=", cam.global_position, "  rot=", cam.rotation_degrees)
	var env: Environment = scene.get_node("WorldEnvironment").environment
	print("DIAG2 env bg=", env.background_mode, " sky=", env.sky != null, " ambient_src=", env.ambient_light_source, " fog=", env.fog_enabled, " density=", env.fog_density, " tonemap=", env.tonemap_mode)
	var sun: DirectionalLight3D = scene.get_node("Sun")
	print("DIAG2 sun energy=", sun.light_energy, " visible=", sun.visible, " time=", sky.time_hours)

	for p in scene.PRESETS:
		scene._apply_preset(p)
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var w := img.get_width()
		var h := img.get_height()
		var s := ""
		for ys in [0.1, 0.3, 0.45, 0.6, 0.85]:
			var c := img.get_pixel(int(w * 0.55), int(h * ys))
			s += " (%.2f %.2f %.2f)" % [c.r, c.g, c.b]
		print("DIAG2 ", p["name"], " yaw=", scene._yaw, " pitch=", scene._pitch, " | pixels top->bottom:", s)
	print("DIAG2 done")
	get_tree().quit()
