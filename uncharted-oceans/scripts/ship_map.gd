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
	var layer := CanvasLayer.new()
	layer.layer = 6
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
	# redraw every frame while you're looking at it (the ship moves), once when you step back
	_canvas.active = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _close() -> void:
	_open = false
	_player.set("input_locked", false)
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
	if _open or _cam_moved:
		var rest := _head.global_transform * _cam_rest
		var want := _view() if _open else rest
		_cam_moved = true
		var a := 1.0 - exp(-delta * follow_rate)
		var next := cam.global_transform.interpolate_with(want, a)
		cam.global_transform = next
		if not _open:
			var ang := next.basis.get_rotation_quaternion().angle_to(rest.basis.get_rotation_quaternion())
			if next.origin.distance_to(rest.origin) < 0.004 and ang < 0.01:
				cam.transform = _cam_rest
				_cam_moved = false
