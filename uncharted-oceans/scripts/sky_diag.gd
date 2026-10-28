extends Node3D
## Sky diagnostic. Run the scene (F6) and wait: it tries each sky setup in turn, reads back the screen colours,
## writes them to the log (lines starting DIAG) and then closes itself. Nothing to click.

const SkySystemScript := preload("res://scripts/sky_system.gd")
const BRIG := "res://assets/ships/brig/Brig.glb"

func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	print("DIAG start  driver=", RenderingServer.get_current_rendering_driver_name(), "  adapter=", RenderingServer.get_video_adapter_name(), "  version=", Engine.get_version_info().get("string", "?"))

	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	add_child(we)
	var sun := DirectionalLight3D.new()
	add_child(sun)

	var brig: Node3D = null
	if ResourceLoader.exists(BRIG):
		brig = (load(BRIG) as PackedScene).instantiate()
		brig.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		add_child(brig)
		print("DIAG brig loaded; children: ", _list_nodes(brig))
	else:
		print("DIAG brig not found")

	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40000.0, 40000.0)
	sea.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("0b2a3a")
	m.roughness = 0.14
	sea.material_override = m
	add_child(sea)

	var cam := Camera3D.new()
	cam.far = 60000.0
	cam.position = Vector3(-1.3, 3.5, -3.2)
	add_child(cam)
	cam.make_current()

	var sky: SkySystem = SkySystemScript.new()
	sky.debug_overlay = false
	sky.world_environment = we
	sky.sun = sun
	sky.time_hours = 12.0
	add_child(sky)

	for i in 30:
		await get_tree().process_frame

	var AUTO := Sky.PROCESS_MODE_AUTOMATIC
	var QUAL := Sky.PROCESS_MODE_QUALITY
	var INCR := Sky.PROCESS_MODE_INCREMENTAL
	var configs := [
		{"n": "builtin sky | AUTOMATIC 256 | no ship", "shader": false, "mode": AUTO, "rad": Sky.RADIANCE_SIZE_256, "brig": false},
		{"n": "builtin sky | AUTOMATIC 256 | ship", "shader": false, "mode": AUTO, "rad": Sky.RADIANCE_SIZE_256, "brig": true},
		{"n": "builtin sky | INCREMENTAL 64 | ship", "shader": false, "mode": INCR, "rad": Sky.RADIANCE_SIZE_64, "brig": true},
		{"n": "builtin sky | QUALITY 64 | ship", "shader": false, "mode": QUAL, "rad": Sky.RADIANCE_SIZE_64, "brig": true},
		{"n": "custom shader | INCREMENTAL 64 | ship", "shader": true, "mode": INCR, "rad": Sky.RADIANCE_SIZE_64, "brig": true},
		{"n": "custom shader | QUALITY 64 | ship", "shader": true, "mode": QUAL, "rad": Sky.RADIANCE_SIZE_64, "brig": true},
		{"n": "custom shader | AUTOMATIC 256 | ship", "shader": true, "mode": AUTO, "rad": Sky.RADIANCE_SIZE_256, "brig": true},
		{"n": "custom shader | INCREMENTAL 64 | no ship", "shader": true, "mode": INCR, "rad": Sky.RADIANCE_SIZE_64, "brig": false},
	]

	for c in configs:
		if brig:
			brig.visible = c["brig"]
		sky.use_shader_sky = c["shader"]
		var s: Sky = we.environment.sky
		s.process_mode = c["mode"]
		s.radiance_size = c["rad"]
		var sd: Vector3 = sky.sun_direction()
		cam.rotation_degrees = Vector3(14.0, rad_to_deg(atan2(-sd.x, -sd.z)) + 90.0, 0.0)
		var t0 := Time.get_ticks_msec()
		for i in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var ms := Time.get_ticks_msec() - t0
		var img := get_viewport().get_texture().get_image()
		var w := img.get_width()
		var h := img.get_height()
		print("DIAG ", c["n"], "   sky ", _px(img, w / 2, h / 6), "  sea ", _px(img, w / 2, int(h * 0.92)), "  (", ms, " ms for 40 frames)")

	print("DIAG done")
	get_tree().quit()

func _px(img: Image, x: int, y: int) -> String:
	var c := img.get_pixel(x, y)
	return "(%.2f %.2f %.2f)" % [c.r, c.g, c.b]

func _list_nodes(n: Node) -> String:
	var out: Array[String] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		var cls := cur.get_class()
		if cls in ["Camera3D", "WorldEnvironment", "DirectionalLight3D", "OmniLight3D", "SpotLight3D", "ReflectionProbe", "VoxelGI", "FogVolume", "CanvasLayer"]:
			out.append("%s:%s" % [cls, cur.name])
		for ch in cur.get_children():
			stack.append(ch)
	return str(out) if not out.is_empty() else "no cameras/lights/environments"
