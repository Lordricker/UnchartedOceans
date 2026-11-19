class_name ShipMap
extends Node
## The chart on the cabin table. Created by ship_motion.gd (map_enabled).
##
## Look at the chart (a white frame shows round it) and click: the camera comes down over the table until the
## chart fills the screen. The chart is the whole world drawn out (chart_canvas.gd): land, a km grid and scale bar,
## every port, your destination, the route, and a marker for the ship with a ring that grows the longer you are
## away from the last port. Esc, right click or another click puts the camera back.
## Needs the world scene (WorldStreamer, group "world_streamer"); without it the chart is just a prop.

const Outline := preload("res://scripts/interact_outline.gd")

@export var reach := 2.4
## Size of the picture on the table, in pixels (the table chart is 0.7 m wide).
@export var map_px := Vector2i(2048, 1365)
@export var follow_rate := 6.0
@export var grid_km := 50.0
@export var ring_base_km := 2.0
@export var ring_per_km := 0.02
## A brass compass standing on a corner of the chart, so the heading can be read at the table (radius in metres).
@export var table_compass := true
@export var table_compass_r := 0.055
## The barometer standing on the opposite corner (ship_barometer.gd), radius in metres.
@export var table_barometer := true
@export var table_barometer_r := 0.075

var _chart_mi: MeshInstance3D
var _quad: MeshInstance3D
var _quad_mat: StandardMaterial3D
var _frame: Node3D
var _vp: SubViewport
var _canvas: Node2D
var _streamer: Node
var _built := false
var _open := false
var _cam: Camera3D
var _head: Node3D
var _player: Node
var _cam_rest := Transform3D.IDENTITY
var _cam_moved := false
var _hands_were_visible := true
var _hint: Label
var _quad_w := 0.7
var _quad_d := 0.466
var _tc_card: Node3D
## A brass magnifying glass that follows the mouse while the chart fills the screen. It is a second, crisp draw of the
## chart (a small SubViewport) shown through a round lens, so the zoomed-in text and lines stay sharp.
@export var lens_radius_px := 170
@export var lens_zoom := 3.0
var _layer: CanvasLayer
var _lens: Control
var _lens_vp: SubViewport
var _lens_canvas: Node2D
var _lens_t := 0.0
var _lock_dist := 1.0
var _lock_scale := Vector3.ONE
var _view_locked := false      # once the camera has arrived over the chart it is held rigidly to it (no lag behind the ship's motion)
var _quad_turn := 0.0            # the picture is turned this much (radians, about the mesh's up) so its top faces the bow

func _ready() -> void:
	var ship := get_parent()
	for n in ship.find_children("*", "MeshInstance3D", true, false):
		if n.has_meta("interaction") and String(n.get_meta("interaction")) == "chart":
			_chart_mi = n
			break
	if _chart_mi == null:
		push_warning("ShipMap: no chart (a mesh with interaction = chart) in the ship; map left alone")
		set_process(false)
		set_process_input(false)
		return
	process_priority = 1000      # run after the ship and the player have moved this frame (keeps the lens steady)
	var layer := CanvasLayer.new()
	layer.layer = 6
	_layer = layer
	add_child(layer)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_END
	_hint.offset_top = 28.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", 24)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override("outline_size", 6)
	if ResourceLoader.exists("res://assets/fonts/Ferrum-ExtraCondensed.otf"):
		_hint.add_theme_font_override("font", load("res://assets/fonts/Ferrum-ExtraCondensed.otf") as Font)
	_hint.text = "Esc: look up from the chart"
	_hint.visible = false
	layer.add_child(_hint)

func _world() -> Node:
	if _streamer == null or not is_instance_valid(_streamer):
		_streamer = get_tree().get_first_node_in_group("world_streamer")
	return _streamer

func _camera() -> Camera3D:
	if _cam == null or not is_instance_valid(_cam):
		_player = get_tree().get_first_node_in_group("player")
		if _player:
			_head = _player.get_node_or_null("Head") as Node3D
			_cam = _player.get_node_or_null("Head/Camera3D") as Camera3D
			if _cam:
				_cam_rest = _cam.transform
	return _cam

## Builds the picture, the quad on the table and the white frame once the world (and its chart) exists.
func _build() -> void:
	var st := _world()
	if st == null or st.get("chart") == null:
		return
	var chart: WorldChart = st.get("chart")
	_vp = SubViewport.new()
	_vp.size = map_px
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	_canvas = load("res://scripts/chart_canvas.gd").new() as Node2D
	_canvas.size_px = Vector2(map_px)
	_canvas.grid_km = grid_km
	_canvas.ring_base_km = ring_base_km
	_canvas.ring_per_km = ring_per_km
	_vp.add_child(_canvas)
	_canvas.call("setup", st, chart)
	_canvas.active = false
	# a quad on the table top, the chart's own width and the picture's proportions
	var bb := _chart_mi.get_aabb()
	# The picture's top is turned to face the bow (whole quarter turns): pick the turn that does it, from how the
	# chart mesh sits in the ship.
	var ship := get_parent() as Node3D
	var rel := ship.global_transform.basis.orthonormalized().inverse() * _chart_mi.global_transform.basis.orthonormalized()
	var turn := 0
	var best := -INF
	for k in 4:
		var top_ship: Vector3 = rel * Basis(Vector3.UP, k * PI * 0.5) * Vector3(0.0, 0.0, -1.0)
		if -top_ship.z > best:
			best = -top_ship.z
			turn = k
	var ratio := float(map_px.y) / float(map_px.x)          # picture depth / width
	if turn % 2 == 0:
		_quad_w = bb.size.x
		_quad_d = _quad_w * ratio
		_quad_d = minf(_quad_d, bb.size.z) if bb.size.z > 0.01 else _quad_d
		_quad_w = _quad_d / ratio
	else:
		# turned a quarter: the picture's width now runs along the mesh's Z and its depth along its X
		_quad_w = minf(bb.size.z, bb.size.x / ratio) if bb.size.z > 0.01 else bb.size.x / ratio
		_quad_d = _quad_w * ratio
	_quad_turn = float(turn) * PI * 0.5
	var pm := PlaneMesh.new()
	pm.size = Vector2(_quad_w, _quad_d)
	_quad = MeshInstance3D.new()
	_quad.mesh = pm
	_quad_mat = StandardMaterial3D.new()
	_quad_mat.albedo_texture = _vp.get_texture()
	_quad_mat.roughness = 0.9
	_quad_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_quad.material_override = _quad_mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.position = bb.get_center() + Vector3(0.0, bb.size.y * 0.5 + 0.0012, 0.0)
	_quad.rotation.y = _quad_turn
	_chart_mi.add_child(_quad)
	# the white frame (4 thin strips) shown while the chart can be clicked
	_frame = Node3D.new()
	_frame.position = _quad.position + Vector3(0.0, 0.0006, 0.0)
	_frame.rotation.y = _quad_turn
	_frame.visible = false
	_chart_mi.add_child(_frame)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1, 1, 1)
	var t := 0.006
	for s in [Vector4(0, -1, _quad_w + t, t), Vector4(0, 1, _quad_w + t, t), Vector4(-1, 0, t, _quad_d + t), Vector4(1, 0, t, _quad_d + t)]:
		var bm := BoxMesh.new()
		bm.size = Vector3(s.z, 0.002, s.w)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = fm
		mi.position = Vector3(s.x * (_quad_w * 0.5 + t * 0.5), 0.0, s.y * (_quad_d * 0.5 + t * 0.5))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_frame.add_child(mi)
	_build_table_compass()
	_build_barometer()
	_build_lens(st, chart)
	_built = true

## The same card as the binnacle's: it keeps north as the ship turns and the red line is fixed to the bow, so it reads
## the heading the bow is on. It stands on the chart's far-right corner and rides with the ship.
func _build_table_compass() -> void:
	var ship := get_parent() as Node3D
	if not table_compass or ship == null:
		return
	var r := table_compass_r
	var k := r / 0.118
	var inset := r + 0.02
	var root := Node3D.new()
	root.name = "TableCompass"
	ship.add_child(root)
	root.global_position = _quad.to_global(Vector3(_quad_w * 0.5 - inset, 0.004, _quad_d * 0.5 - inset))
	var brass := _tc_mat(Color(0.72, 0.55, 0.22), 0.35, 0.8)
	var cream := _tc_mat(Color(0.93, 0.9, 0.8), 0.9, 0.0)
	var ink := _tc_mat(Color(0.08, 0.07, 0.06), 0.9, 0.0)
	var red := _tc_mat(Color(0.75, 0.08, 0.06), 0.8, 0.0)
	var bowl := CylinderMesh.new()
	bowl.top_radius = r * 1.12
	bowl.bottom_radius = r * 1.08
	bowl.height = 0.016
	bowl.radial_segments = 24
	bowl.rings = 1
	_tc_part(root, bowl, brass, Vector3(0.0, -0.008, 0.0))
	_tc_card = Node3D.new()
	_tc_card.name = "Card"
	root.add_child(_tc_card)
	var disc := CylinderMesh.new()
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = 0.004
	disc.radial_segments = 28
	disc.rings = 1
	_tc_part(_tc_card, disc, cream, Vector3(0.0, 0.002, 0.0))
	var tick := BoxMesh.new()
	tick.size = Vector3(0.004, 0.002, 0.014) * k
	for i in 16:
		var b := deg_to_rad(22.5 * i)
		var mi := _tc_part(_tc_card, tick, ink, Vector3(sin(b), 0.0, -cos(b)) * r * 0.89 + Vector3(0.0, 0.0045, 0.0))
		mi.rotation.y = -b
	var names := ["N", "E", "S", "W"]
	for i in 4:
		var b := deg_to_rad(90.0 * i)
		var lab := Label3D.new()
		lab.text = names[i]
		lab.font_size = 96
		lab.pixel_size = 0.0009 * k
		lab.modulate = Color(0.75, 0.08, 0.06) if i == 0 else Color(0.08, 0.07, 0.06)
		lab.outline_size = 0
		lab.basis = Basis(Vector3.UP, -b) * Basis(Vector3.RIGHT, deg_to_rad(-90.0))
		lab.position = Vector3(sin(b), 0.0, -cos(b)) * r * 0.61 + Vector3(0.0, 0.0052, 0.0)
		_tc_card.add_child(lab)
	var lub := BoxMesh.new()
	lub.size = Vector3(0.006, 0.006, 0.03) * k
	_tc_part(root, lub, red, Vector3(0.0, 0.006, -(r * 1.0 - 0.012 * k)))

## The barometer stands on the chart's near-left corner (the compass is on the far right), dial top toward the bow.
func _build_barometer() -> void:
	var ship := get_parent() as Node3D
	if not table_barometer or ship == null:
		return
	var baro := (load("res://scripts/ship_barometer.gd") as GDScript).new() as Node3D
	baro.name = "Barometer"
	ship.add_child(baro)
	var inset := table_barometer_r + 0.02
	baro.global_position = _quad.to_global(Vector3(-_quad_w * 0.5 + inset, 0.004, _quad_d * 0.5 - inset))
	baro.call("build", table_barometer_r)

const LENS_SHADER := """
shader_type canvas_item;
void fragment() {
	vec2 q = UV - vec2(0.5);
	float d = length(q) * 2.0;
	vec4 c = texture(TEXTURE, UV);
	vec3 col = mix(vec3(0.09, 0.11, 0.13), c.rgb, c.a);
	col += vec3(0.07) * smoothstep(0.55, 0.0, length(q - vec2(-0.18, -0.24)));
	COLOR = vec4(col, 1.0 - smoothstep(0.87, 0.88, d));
}
"""

## The round lens (a brass ring, no handle) that rides on the mouse while the chart is open.
func _build_lens(st: Node, chart: WorldChart) -> void:
	var r := lens_radius_px
	_lens_vp = SubViewport.new()
	_lens_vp.size = Vector2i(r * 2, r * 2)
	_lens_vp.disable_3d = true
	_lens_vp.transparent_bg = true
	_lens_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_lens_vp)
	_lens_canvas = load("res://scripts/chart_canvas.gd").new() as Node2D
	_lens_canvas.size_px = Vector2(map_px)
	_lens_canvas.grid_km = grid_km
	_lens_canvas.ring_base_km = ring_base_km
	_lens_canvas.ring_per_km = ring_per_km
	_lens_vp.add_child(_lens_canvas)
	_lens_canvas.call("setup", st, chart)
	_lens_canvas.active = false         # redrawn on a short timer instead (moving/scaling it needs no redraw)
	_lens = Control.new()
	_lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lens.visible = false
	_layer.add_child(_lens)
	var tr := TextureRect.new()
	tr.texture = _lens_vp.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = Vector2(-r, -r)
	tr.size = Vector2(r * 2, r * 2)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = LENS_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	tr.material = sm
	_lens.add_child(tr)
	_lens.add_child(_build_ring())

## The lens's brass frame: a real torus lit and reflecting a sky, drawn once into a small 3D viewport and laid over the
## glass (it never changes, so it costs nothing per frame).
func _build_ring() -> TextureRect:
	var r := float(lens_radius_px)
	var vp := SubViewport.new()
	vp.size = Vector2i(lens_radius_px * 2, lens_radius_px * 2)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var cam := Camera3D.new()
	cam.environment = env
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = r * 2.0
	cam.near = 1.0
	cam.far = 1000.0
	cam.position = Vector3(0.0, 0.0, 400.0)
	vp.add_child(cam)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var tm := TorusMesh.new()
	tm.outer_radius = r - 2.0
	tm.inner_radius = r - 26.0
	tm.rings = 72
	tm.ring_segments = 24
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.86, 0.63, 0.26)
	brass.metallic = 1.0
	brass.roughness = 0.27
	var ring := MeshInstance3D.new()
	ring.mesh = tm
	ring.material_override = brass
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)     # the torus's axis points at the camera
	ring.scale = Vector3(1.0, 0.7, 1.0)
	vp.add_child(ring)
	var tr := TextureRect.new()
	tr.texture = vp.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = Vector2(-r, -r)
	tr.size = Vector2(r * 2.0, r * 2.0)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _open_lens() -> void:
	if _lens == null:
		return
	# the mouse is free (but kept in the window and hidden) so the lens can follow it
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	_view_locked = false
	_lens_t = 0.0
	_lens_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_lens_canvas.queue_redraw()

func _close_lens() -> void:
	if _lens == null:
		return
	_lens.visible = false
	_lens_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_view_locked = false

## Chart-picture pixels under a screen point (the chart quad seen through the camera), or INF if the ray misses.
func _canvas_at(m: Vector2) -> Vector2:
	# Worked out in the camera's own space, from the distance and scale fixed when the camera locked on, so no world
	# position goes into it (world positions are rounded to ~2 mm far from the origin, which this lens magnifies).
	var d := _cam.project_local_ray_normal(m)
	if d.z > -0.0001:
		return Vector2.INF
	var hit := d * (_lock_dist / -d.z)           # the camera looks straight down at the chart, top of the picture up
	var cx := hit.x / _lock_scale.x
	var cz := -hit.y / _lock_scale.z
	return Vector2(cx / _quad_w + 0.5, cz / _quad_d + 0.5) * Vector2(map_px)

## Puts the lens on the mouse and aims its inner picture: the chart, drawn lens_zoom times bigger, centred on the
## chart point under the mouse. Only shown once the camera has settled over the chart and the mouse is over it.
func _update_lens(delta: float) -> void:
	if _lens == null:
		return
	if not _open or _camera() == null:
		_lens.visible = false
		return
	var settled := _view_locked
	var m := get_viewport().get_mouse_position()
	var c0 := _canvas_at(m)
	var c1 := _canvas_at(m + Vector2(1.0, 0.0))
	if not settled or not c0.is_finite() or not c1.is_finite():
		_lens.visible = false
		return
	var s := (c1 - c0).length()          # chart-picture pixels per screen pixel
	if s < 0.0001 or c0.x < 0.0 or c0.y < 0.0 or c0.x > map_px.x or c0.y > map_px.y:
		_lens.visible = false
		return
	var k := lens_zoom / s
	_lens_canvas.scale = Vector2(k, k)
	if absf(float(_lens_canvas.dot_scale) - k) > 0.01:
		_lens_canvas.dot_scale = k          # the ship's dot stays the size it is on the chart, not magnified
		_lens_canvas.queue_redraw()
	_lens_canvas.position = Vector2(lens_radius_px, lens_radius_px) - c0 * k
	_lens.position = m
	_lens.visible = true
	_lens_t += delta
	if _lens_t > 0.25:
		_lens_t = 0.0
		_lens_canvas.queue_redraw()

func _turn_table_compass() -> void:
	if _tc_card == null:
		return
	var ship := get_parent()
	_tc_card.rotation.y = -deg_to_rad(float(ship.get("heading_deg")))

func _tc_mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _tc_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## True while the chart is open and you are looking at it.
func is_open() -> bool:
	return _open


func _aimed() -> bool:
	var cam := _camera()
	if cam == null or not _built or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if bool(_player.get("input_locked")) or bool(_player.get_meta("grab_busy", false)):
		return false
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var inv := _quad.global_transform.affine_inverse()
	var box := AABB(Vector3(-_quad_w * 0.5, -0.02, -_quad_d * 0.5), Vector3(_quad_w, 0.04, _quad_d)).grow(0.03)
	var hit = box.intersects_ray(inv * o, (inv.basis * d).normalized())
	return hit != null and o.distance_to(_quad.global_transform * (hit as Vector3)) <= reach

## Where the camera goes to see the whole chart: straight above it, the top of the picture at the top of the screen.
func _view() -> Transform3D:
	var xf := _quad.global_transform
	var up_axis := xf.basis.y.normalized()
	var fov := deg_to_rad(_cam.fov)
	var dist := (_quad_d * xf.basis.get_scale().z * 0.5) / tan(fov * 0.5) * 1.04
	var pos := xf.origin + up_axis * dist
	var top := -xf.basis.z.normalized()           # the top of the picture is local -Z
	return Transform3D(Basis.looking_at(-up_axis, top), pos)

func _input(e: InputEvent) -> void:
	if _camera() == null:
		return
	if not _built:
		return
	if _open:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE):
			_close()
			get_viewport().set_input_as_handled()
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _aimed():
		_enter()
		get_viewport().set_input_as_handled()

func _enter() -> void:
	_open = true
	_player.set("input_locked", true)
	var h = _player.get("hands")
	if h is Node3D:
		_hands_were_visible = h.visible
		h.visible = false
	_quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# the chart is drawn over everything on the table (the book, candle, ink, quill... stand on it and would hide it)
	_quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_quad_mat.no_depth_test = true
	_quad_mat.render_priority = 100
	_hint.visible = true
	_open_lens()
	# redraw every frame while you're looking at it (the ship moves), once when you step back
	_canvas.active = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _close() -> void:
	_open = false
	_player.set("input_locked", false)
	_close_lens()
	var h = _player.get("hands")
	if h is Node3D:
		h.visible = _hands_were_visible
	_quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_quad_mat.no_depth_test = false
	_quad_mat.render_priority = 0
	_hint.visible = false
	_canvas.active = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

func _process(delta: float) -> void:
	if not _built:
		_build()
		return
	var cam := _camera()
	if cam == null or _head == null:
		return
	_turn_table_compass()
	var aimed := not _open and _aimed()
	_frame.visible = aimed
	if aimed:
		Outline.show_name(self, "Chart")
	else:
		Outline.hide_name(self)
	if _open or _cam_moved:
		var rest := _head.global_transform * _cam_rest
		var want := _view() if _open else rest
		_cam_moved = true
		var a := 1.0 - exp(-delta * follow_rate)
		var next := cam.global_transform.interpolate_with(want, a)
		if _open:
			if not _view_locked and next.origin.distance_to(want.origin) < 0.01 \
					and next.basis.get_rotation_quaternion().angle_to(want.basis.get_rotation_quaternion()) < 0.015:
				_view_locked = true
				var sc := _quad.global_transform.basis.get_scale()
				_lock_scale = sc
				_lock_dist = (_quad_d * sc.z * 0.5) / tan(deg_to_rad(cam.fov) * 0.5) * 1.04
			if _view_locked:
				next = want
		cam.global_transform = next
		if not _open:
			var ang := next.basis.get_rotation_quaternion().angle_to(rest.basis.get_rotation_quaternion())
			if next.origin.distance_to(rest.origin) < 0.004 and ang < 0.01:
				cam.transform = _cam_rest
				_cam_moved = false
	_update_lens(delta)
