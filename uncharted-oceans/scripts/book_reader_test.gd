extends Node3D
## Test bench for the book: a book on a table. Run this scene (F6).
##   Space = open / close the book     Right / D / wheel down / click right = next page
##   Left / A / wheel up / click left = previous page     1 / 2 = different chapter file if you add more
## Put the fonts in res://assets/fonts (Ferrum for titles; set body_font_hint below for the body).

@export var chapter := "res://data/book/log_line.md"
@export var body_font_hint := "imfellenglish-regular"

var _book: BookReader

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.07, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.72, 0.62)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, -25.0, 0.0)
	sun.light_energy = 0.9
	add_child(sun)
	var table := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	table.mesh = pm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.16, 0.10, 0.06)
	tm.roughness = 0.9
	table.material_override = tm
	add_child(table)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.40, 0.24)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.0, -0.01), Vector3.UP)
	cam.fov = 48.0
	_book = BookReader.new()
	_book.body_font_hint = body_font_hint
	add_child(_book)
	await _book.open_file(chapter)
	print("BookReader: ready, press Space to open")

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_SPACE:
		if _book.is_open():
			_book.close()
		else:
			_book.open()
