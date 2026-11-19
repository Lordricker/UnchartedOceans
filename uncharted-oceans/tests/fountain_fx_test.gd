extends Node3D
## Run scenes/fountain_test.tscn (F6): the capital's piazza fountain with its water running, camera orbiting it.

func _ready() -> void:
	var port := (load("res://assets/port/PortCapital.glb") as PackedScene).instantiate()
	add_child(port)
	FountainFX.attach(port)
	var f := port.find_child("Cap_Fountain", true, false)
	print("fountain found: ", f != null, "  fx: ", f != null and f.get_node_or_null("FountainFX") != null)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.7, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.name = "Cam"
	add_child(cam)
	cam.current = true
	set_meta("fountain", f)
	get_tree().create_timer(12.0).timeout.connect(func(): print("fountain test done"); get_tree().quit())

func _process(_d: float) -> void:
	var f = get_meta("fountain", null)
	if f == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var c: Vector3 = f.global_position + Vector3(0, 2.4, 0)
	var cam: Camera3D = get_node("Cam")
	cam.global_position = c + Vector3(sin(t * 0.4) * 6.0, 2.0, cos(t * 0.4) * 6.0)
	cam.look_at(c, Vector3.UP)
