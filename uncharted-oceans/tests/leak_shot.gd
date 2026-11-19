extends Node
## Light leak check: the capital tavern hearth seen from the ship, indoor-light shadows off vs on.
## Writes ../renders/light_leak/.
func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	var out := ProjectSettings.globalize_path("res://").path_join("../renders/light_leak")
	DirAccess.make_dir_recursive_absolute(out)
	var world: Node = (load("res://scenes/world_capital_start.tscn") as PackedScene).instantiate()
	add_child(world)
	for i in 150: await get_tree().physics_frame
	for n in world.find_children("*", "", true, false):
		var sc = n.get_script()
		if sc != null and str(sc.resource_path).ends_with("world_weather.gd"):
			n.set_process(false)
	var hud := world.get_node_or_null("HUD")
	if hud: hud.visible = false
	var sky = world.get_node("SkySystem")
	sky.set("hours_per_second", 0.0)
	sky.set("time_hours", 17.8)
	sky.set("volumetric_quality", 2)
	for c in sky.get_children():
		if c is CanvasLayer: c.visible = false
	var hearth: Node3D = null
	for n in world.find_children("*HearthLight*", "", true, false):
		hearth = n
		break
	var lights := []
	for l in world.find_children("Light", "OmniLight3D", true, false):
		if (l as OmniLight3D).shadow_enabled: lights.append(l)
	print("LEAK shadowed lights ", lights.size(), " hearth ", hearth.global_position if hearth else null)
	var head: Vector3 = (world.get_node("Player/Head") as Node3D).global_position
	var cam := Camera3D.new()
	cam.fov = 75.0
	world.add_child(cam)
	cam.current = true
	var hp := hearth.global_position
	var views := [["ship", head, Vector3(hp.x, head.y + 2.0, hp.z)],
		["street", hp + (head - hp).normalized() * 9.0 + Vector3(0, 1.0, 0), hp],
	]
	var k := 0
	for n in world.find_children("*Tavern_HangLamp*", "", true, false):
		var lp: Vector3 = (n as Node3D).global_position - Vector3(0, 1.2, 0)
		views.append(["inside%d" % k, lp, Vector3(hp.x, lp.y - 0.5, hp.z)])
		views.append(["inside%d_away" % k, lp, lp + (lp - hp)])
		k += 1
		if k >= 2: break
	for on in [false, true]:
		for l in lights: (l as OmniLight3D).shadow_enabled = on
		for v in views:
			cam.look_at_from_position(v[1], v[2])
			for i in 30: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, v[0], "fixed" if on else "leak"])
	# GPU cost from the street, shadows off vs on
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	cam.look_at_from_position(views[1][1], views[1][2])
	var res := []
	for on in [false, true, false, true]:
		for l in lights: (l as OmniLight3D).shadow_enabled = on
		for i in 30: await get_tree().process_frame
		var t := 0.0
		for i in 90:
			await RenderingServer.frame_post_draw
			t += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		res.append("shadows %s: %.2f ms" % [on, t / 90.0])
	var f := FileAccess.open(out.path_join("timings.txt"), FileAccess.WRITE)
	f.store_string("lights shadowed: %d\n" % lights.size() + "\n".join(res))
	f.close()
	print("LEAK DONE")
	get_tree().quit()
