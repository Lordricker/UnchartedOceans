extends Node
## Takes screenshots of the world scene from a few places. Run under a display:
## xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 --path <project> res://tests/shot_runner.tscn

var out_dir := "/tmp/shots"

func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene: Node = (load("res://scenes/world_test.tscn") as PackedScene).instantiate()
	add_child(scene)
	for i in 40:
		await get_tree().physics_frame
	var st: WorldStreamer = scene.get_node("WorldStreamer")
	var ship: Node3D = scene.get_node("ShipRig")
	var player: Node3D = scene.get_node("Player")
	var c: WorldChart = st.chart
	var views: Array = []
	views.append({"name": "1_start", "cx": null})
	# a high peak, seen from the sea
	var peak := Vector2.ZERO
	var best := 0.0
	var x := 5000.0
	while x < c.width_m - 5000.0:
		var z := 5000.0
		while z < c.height_m - 5000.0:
			var h := c.height01(x, z)
			if h > best and c.is_land(x, z):
				best = h
				peak = Vector2(x, z)
			z += 3000.0
		x += 3000.0
	print("peak ", peak, " h ", best)
	for dist in [14000.0, 30000.0]:
		for a in range(0, 360, 20):
			var d := WorldChart.direction(float(a))
			var sx: float = peak.x + d.x * dist
			var sz: float = peak.y + d.y * dist
			if c.sea_depth_m(sx, sz) >= 30.0 and c.sea_depth_m(peak.x + d.x * dist * 0.5, peak.y + d.y * dist * 0.5) >= 0.0:
				views.append({"name": "peak_%d" % int(dist / 1000.0), "cx": sx, "cz": sz, "hdg": WorldChart.heading_to(sx, sz, peak.x, peak.y)})
				break
	for v in views:
		if v["cx"] != null:
			st.place_ship(v["cx"], v["cz"], v["hdg"])
		for i in 30:
			await get_tree().physics_frame
		player.rotation.y = ship.rotation.y
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, v["name"]])
		print("saved ", v["name"], "  ", st.ship_cx(), " ", st.ship_cz(), " ports ", st.port_ids())
	get_tree().quit()
