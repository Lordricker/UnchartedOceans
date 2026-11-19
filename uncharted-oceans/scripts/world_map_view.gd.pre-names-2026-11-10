extends Node2D
## World chart viewer. Open scenes/world_map.tscn and press F6.
## Wheel = zoom, left-drag = pan, left-click twice = measure (distance and sailing time),
## S = sleep from the ship marker toward the cursor, [ ] = sleep hours, R = back to the home port,
## Esc = clear. The sleep uses WorldChart.sleep_travel (constant speed for now).

@export var ship_speed_mps := 3.5
@export var sleep_hours := 8.0
@export var home_port_id := "AC00"

const REGION_COLORS := {
	"A": Color(0.35, 0.62, 1.0),
	"B": Color(1.0, 0.80, 0.25),
	"C": Color(1.0, 0.42, 0.32),
	"D": Color(0.45, 1.0, 0.55),
	"F": Color(0.90, 0.50, 1.0),
}

var chart: WorldChart
var cam: Camera2D
var hud: Label
var ship_x := 0.0
var ship_z := 0.0
var ship_heading := 0.0
var trail: Array = []        # Vector2 chart pixels
var meas: Array = []         # Vector2 chart pixels, up to 2
var last_result := ""
var _press := Vector2.ZERO
var _dragging := false
var _moved := false


func _ready() -> void:
	chart = WorldChart.load_default()
	if chart == null:
		push_error("world_map_view: chart failed to load")
		return
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.show_behind_parent = true
	sprite.texture = load(WorldChart.HEIGHT_PATH) as Texture2D
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/world_chart.gdshader") as Shader
	mat.set_shader_parameter("land_tex", load(WorldChart.LAND_PATH))
	mat.set_shader_parameter("shore_tex", load(WorldChart.SHORE_PATH))
	mat.set_shader_parameter("shelf_px", 12000.0 / chart.mpp)
	sprite.material = mat
	add_child(sprite)

	cam = Camera2D.new()
	add_child(cam)
	cam.position = Vector2(chart.px_w, chart.px_h) * 0.5
	var vp := get_viewport_rect().size
	var z := minf(vp.x / chart.px_w, vp.y / chart.px_h)
	cam.zoom = Vector2(z, z)
	cam.make_current()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(10, 8)
	hud.add_theme_color_override("font_color", Color(1, 1, 1))
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(hud)
	_ship_home()


func _ship_home() -> void:
	var p := chart.get_port(home_port_id)
	if p.is_empty() and chart.ports.size() > 0:
		p = chart.ports[0]
	ship_x = p.get("x", chart.width_m * 0.5)
	ship_z = p.get("z", chart.height_m * 0.5)
	ship_heading = 0.0
	trail = [Vector2(ship_x, ship_z) / chart.mpp]
	last_result = "At %s." % p.get("id", "?")


func _to_px(x: float, z: float) -> Vector2:
	return Vector2(x, z) / chart.mpp


func _cursor_world() -> Vector2:
	var m := get_global_mouse_position()
	return m * chart.mpp


func _zoom_at(mouse: Vector2, factor: float) -> void:
	var c := get_viewport_rect().size * 0.5
	var z0 := cam.zoom.x
	var z1 := clampf(z0 * factor, 0.3, 40.0)
	var world := cam.position + (mouse - c) / z0
	cam.zoom = Vector2(z1, z1)
	cam.position = world - (mouse - c) / z1


func _unhandled_input(event: InputEvent) -> void:
	if chart == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.18)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.18)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = mb.position
				_dragging = true
				_moved = false
			else:
				_dragging = false
				if not _moved:
					_click()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_press) > 4.0:
			_moved = true
		if _moved:
			cam.position -= mm.relative / cam.zoom.x
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_S:
				_sleep()
			KEY_R:
				_ship_home()
			KEY_ESCAPE:
				meas.clear()
			KEY_BRACKETLEFT:
				sleep_hours = maxf(1.0, sleep_hours - 1.0)
			KEY_BRACKETRIGHT:
				sleep_hours = minf(16.0, sleep_hours + 1.0)


func _click() -> void:
	if meas.size() >= 2:
		meas.clear()
	meas.append(get_global_mouse_position())


func _sleep() -> void:
	var c := _cursor_world()
	ship_heading = WorldChart.heading_to(ship_x, ship_z, c.x, c.y)
	var r := chart.sleep_travel(ship_x, ship_z, ship_heading, sleep_hours, ship_speed_mps)
	ship_x = r["x"]
	ship_z = r["z"]
	trail.append(Vector2(ship_x, ship_z) / chart.mpp)
	var why := {"none": "full rest", "land": "land ahead", "edge": "world edge", "port_ring": "reached %s" % r["port"]}
	last_result = "Slept %.1f h, %.0f km on heading %.0f. Woke: %s." % [r["hours_slept"], float(r["dist_m"]) / 1000.0, ship_heading, why[r["stop"]]]


func _process(_dt: float) -> void:
	if chart == null:
		return
	queue_redraw()
	var c := _cursor_world()
	var land := chart.is_land(c.x, c.y)
	var s := "cursor %.0f, %.0f km  %s" % [c.x / 1000.0, c.y / 1000.0, "LAND" if land else "sea %.0f m deep, %.1f km off the coast" % [chart.sea_depth_m(c.x, c.y), chart.shore_distance_m(c.x, c.y) / 1000.0]]
	var np := chart.nearest_port(c.x, c.y)
	if not np.is_empty():
		s += "\nnearest port %s (%s, %s): %.0f km" % [np["id"], np["region"], np["tier"], float(np["dist_m"]) / 1000.0]
	if meas.size() == 2:
		var d: float = (meas[1] - meas[0]).length() * chart.mpp
		var h: float = d / ship_speed_mps / 3600.0
		s += "\nmeasure %.0f km = %.1f h at %.1f m/s (%.1f sleeps of %.0f h)" % [d / 1000.0, h, ship_speed_mps, h / sleep_hours, sleep_hours]
	elif meas.size() == 1:
		s += "\nmeasure: click a second point"
	s += "\nship at %.0f, %.0f km   sleep %.0f h   %s" % [ship_x / 1000.0, ship_z / 1000.0, sleep_hours, last_result]
	s += "\nwheel zoom, drag pan, click measure, S sleep toward cursor, [ ] hours, R home, Esc clear"
	hud.text = s


func _draw() -> void:
	if chart == null:
		return
	var z := cam.zoom.x
	var fs := int(clampf(14.0 / z, 8.0, 80.0))
	var font := ThemeDB.fallback_font
	for p in chart.ports:
		var pos := _to_px(p["x"], p["z"])
		var col: Color = REGION_COLORS.get(p["region"], Color.WHITE)
		var big: bool = p["tier"] == "capital"
		var r := (7.0 if big else 4.0) / z
		draw_circle(pos, r, Color(0, 0, 0, 0.65))
		draw_arc(pos, r, 0.0, TAU, 20, col, 2.5 / z)
		if z > 0.9 or big:
			draw_string(font, pos + Vector2(r + 2.0 / z, 4.0 / z), p["id"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
		if z > 3.0:
			draw_arc(pos, WorldChart.PORT_SPAWN_M / chart.mpp, 0.0, TAU, 48, Color(col, 0.55), 1.2 / z)
	if trail.size() > 1:
		draw_polyline(PackedVector2Array(trail), Color(1, 1, 1, 0.8), 1.6 / z)
	var sp := _to_px(ship_x, ship_z)
	var dir := Vector2.from_angle(deg_to_rad(ship_heading - 90.0))
	var side := dir.orthogonal()
	var sz := 9.0 / z
	draw_colored_polygon(PackedVector2Array([sp + dir * sz, sp - dir * sz * 0.7 + side * sz * 0.6, sp - dir * sz * 0.7 - side * sz * 0.6]), Color(1.0, 0.95, 0.4))
	var cur := get_global_mouse_position()
	draw_dashed_line(sp, cur, Color(1, 1, 1, 0.35), 1.2 / z, 6.0 / z)
	if meas.size() >= 1:
		draw_circle(meas[0], 3.0 / z, Color(1, 0.3, 0.3))
	if meas.size() == 2:
		draw_circle(meas[1], 3.0 / z, Color(1, 0.3, 0.3))
		draw_line(meas[0], meas[1], Color(1, 0.3, 0.3), 1.6 / z)
