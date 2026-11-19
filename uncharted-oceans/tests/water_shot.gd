extends Node
## Water seam / quilt check (Claude, 2026-11-19): the main menu sea, moderate, fixed time, frozen, UI hidden, a low camera
## looking down at the water like a player on deck. Writes Medium and High shots and shader variants to
## res://tests/water_shots/, then quits.
var mat: ShaderMaterial
var base_code: String

func _ready() -> void:
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/water_shots"))
	await _wait(2.0)
	for c in menu.get_children():
		if c is CanvasLayer:
			c.visible = false
	var oc: Ocean = menu.get("_ocean")
	var cam: Camera3D = menu.get("_cam")
	oc.sea_state = Ocean.SeaState.MODERATE
	await _wait(1.5)
	menu.set_process(false)
	cam.h_offset = 0.0
	cam.global_position = Vector3(-30, 2.6, 30)
	cam.look_at(Vector3(-30 + 14, -1.5, 30 - 14))
	mat = oc.material_override
	base_code = mat.shader.code
	oc.time = 1500.0
	Engine.time_scale = 1.0
	await _frames(2)
	Engine.time_scale = 0.0
	var cur: Shader = mat.shader
	var old_sh := Shader.new()
	old_sh.code = FileAccess.get_file_as_string("res://shaders/ocean.gdshader.pre-inthash-2026-11-19")
	for q in [GameSettings.MEDIUM, GameSettings.HIGH]:
		GameSettings.set_quality(q)
		var qn := "medium" if q == GameSettings.MEDIUM else "high"
		mat.shader = cur
		await _shot("h_%s_after" % qn)
		mat.shader = old_sh
		await _shot("h_%s_before" % qn)
		mat.shader = cur
	GameSettings.set_quality(GameSettings.MEDIUM)
	await _debug("h_rip_after", "vec3(rip.x * 0.5 + 0.5)")
	print("WATER_SHOTS_DONE")
	get_tree().quit()

func _variant(n: String, find: String, repl: String) -> void:
	if base_code.find(find) < 0:
		print("WATER_SHOT: pattern not found for ", n)
		return
	var sh := Shader.new()
	sh.code = base_code.replace(find, repl)
	var old: Shader = mat.shader
	mat.shader = sh
	await _shot(n)
	mat.shader = old

func _texlod(n: String) -> void:
	var code := base_code.replace("texture(foam_noise, ", "tex_l0(")
	code = code.replace("void vertex() {", "vec4 tex_l0(vec2 uv) { return textureLod(foam_noise, uv, 0.0); }\n\nvoid vertex() {")
	var sh := Shader.new()
	sh.code = code
	var old: Shader = mat.shader
	mat.shader = sh
	await _shot(n)
	mat.shader = old

func _debug(n: String, expr: String) -> void:
	# replace the final colour with a debug value (unlit)
	var code := base_code
	var k := code.rfind("}")
	code = code.substr(0, k) + "\tALBEDO = vec3(0.0); SPECULAR = 0.0; ROUGHNESS = 1.0; ALPHA = 1.0; EMISSION = " + expr + ";\n}\n"
	var sh := Shader.new()
	sh.code = code
	var old: Shader = mat.shader
	mat.shader = sh
	await _shot(n)
	mat.shader = old

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(n: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/water_shots/%s.png" % n)
