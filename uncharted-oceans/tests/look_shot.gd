extends Node
## Before/after shots of SkySystem.cinematic_look in the capital start, with GPU frame times.
## Run tests/look_shot.tscn (writes to ../renders/lighting_look).
var out_dir := ""
var hours := [9.5, 17.5]

func _ready() -> void:
	out_dir = ProjectSettings.globalize_path("res://").path_join("../renders/lighting_look")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_go.call_deferred()

func _gpu_ms(frames: int) -> float:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var t := 0.0
	for i in frames:
		await RenderingServer.frame_post_draw
		t += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	return t / frames

func _go() -> void:
	var world: Node = (load("res://scenes/world_capital_start.tscn") as PackedScene).instantiate()
	add_child(world)
	for i in 120: await get_tree().physics_frame
	for n in world.find_children("*", "", true, false):
		var sc = n.get_script()
		if sc != null and str(sc.resource_path).ends_with("world_weather.gd"):
			n.set_process(false)
			n.set_physics_process(false)
	var hud := world.get_node_or_null("HUD")
	if hud: hud.visible = false
	var sky = world.get_node("SkySystem")
	sky.set("hours_per_second", 0.0)
	sky.set("overcast", 0.0)
	sky.set("storm", 0.0)
	sky.set("coverage", 0.3)
	if sky.get("_dbg"): sky.get("_dbg").visible = false
	for c in sky.get_children():
		if c is CanvasLayer: c.visible = false
	var player: Node3D = world.get_node("Player")
	player.set_physics_process(false)
	player.set_process(false)
	var head: Vector3 = (world.get_node("Player/Head") as Node3D).global_position
	var cam := Camera3D.new()
	cam.far = 20000.0
	cam.fov = 70.0
	world.add_child(cam)
	cam.current = true
	var views := []
	for yaw in [0, 90, 180, 270]:
		var d := Vector3(sin(deg_to_rad(yaw)), -0.05, cos(deg_to_rad(yaw)))
		views.append(["deck%d" % yaw, head, head + d * 30.0])
	views.append(["high", head + Vector3(-40, 25, 40), head])
	var report := []
	sky.set("volumetric_quality", 2)
	for h in hours:
		sky.set("time_hours", h)
		for look in [false, true]:
			sky.set("cinematic_look", look)
			for v in views:
				cam.look_at_from_position(v[1], v[2])
				for i in 30: await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				img.save_png("%s/h%d_%s_%s.png" % [out_dir, int(h), v[0], "new" if look else "old"])
			var ms: float = await _gpu_ms(60)
			report.append("hour %.1f look %s: gpu %.2f ms" % [h, "new" if look else "old", ms])
			print("LOOKSHOT ", report[-1])
	# cost of each part: everything on, then one part off at a time (from the high view, morning)
	sky.set("time_hours", 9.5)
	sky.set("volumetric_quality", 2)
	sky.set("cinematic_look", true)
	cam.look_at_from_position(views[4][1], views[4][2])
	for i in 30: await get_tree().process_frame
	var env: Environment = (world.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun: DirectionalLight3D = world.get_node("Sun")
	var base: float = await _gpu_ms(90)
	report.append("all on: %.2f ms" % base)
	for part in ["ssao_enabled", "ssil_enabled", "volumetric_fog_enabled", "glow_enabled", "soft_shadow"]:
		if part == "soft_shadow": sun.light_angular_distance = 0.0
		else: env.set(part, false)
		for i in 20: await get_tree().process_frame
		var ms: float = await _gpu_ms(90)
		report.append("without %s: %.2f ms (saves %.2f)" % [part, ms, base - ms])
		print("LOOKSHOT ", report[-1])
		if part == "soft_shadow": sun.light_angular_distance = 0.5
		else: env.set(part, true)
	var f := FileAccess.open(out_dir.path_join("timings.txt"), FileAccess.WRITE)
	f.store_string("\n".join(report))
	f.close()
	print("LOOKSHOT DONE")
	get_tree().quit()
