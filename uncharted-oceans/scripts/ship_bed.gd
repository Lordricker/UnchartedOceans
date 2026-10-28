class_name ShipBed
extends Node
## The captain's bed. Created by ship_motion.gd (bed_enabled).
##
## Look at the bed (it is outlined in white) and click: the sleep window opens, the same one T opens
## (WorldStreamer.open_prompt): type the hours, Enter to sleep, Esc to get up. You stand still while it is open.
## The bed is the CabinBed and CabinBedding nodes in Brig.glb (extras interaction = "bed").
##
## Sleeping (Enter in the sleep window): the camera lies back onto the bed looking up at the ceiling, the screen
## fades to black, the sleep itself happens while it is black (the ship is carried along, ports spawn in) and the
## result pops up on the black screen. Then the screen fades back in on the bed, the message lingers a moment and
## fades out, and you get up. Every sleep plays this, T included. The streamer leaves the sleep to this node
## because we listen to its sleep_requested signal; with no bed in the ship a sleep just happens.

const Outline := preload("res://scripts/interact_outline.gd")

enum Phase { IDLE, LIE, FADE_OUT, BLACK, FADE_IN, WAKE }

## How far you can click the bed (m, along your line of sight).
@export var reach := 2.4

@export_group("Sleep sequence (seconds)")
## The camera lies back onto the bed.
@export var lie_down_time := 0.65
@export var fade_out_time := 0.6
## Minimum time on the black screen (the message is read here). It also waits for a port that is still loading.
@export var black_hold := 1.3
@export var loading_wait_max := 6.0
@export var message_pop_time := 0.2
@export var fade_in_time := 0.9
## After the screen is fully clear, the message stays this long, then fades out.
@export var message_linger := 0.6
@export var message_fade_time := 0.5
## After the screen is fully clear, you get up (camera back to eye height) after this delay.
@export var get_up_delay := 0.3
@export var get_up_time := 0.7

@export_group("Lying in bed")
## Eye height above the top of the bed (m).
@export var eye_above_bed := 0.22
## How far toward the pillow end the eyes are, as a fraction of the bed's length from its middle.
@export var toward_head := 0.22
## 0 = straight up at the ceiling; more tilts the view toward the foot of the bed.
@export var look_tilt_deg := 15.0
## Which end of the bed is the pillow: 0 = work it out from the shape, 1 / -1 = force one end if the ceiling
## looks upside down.
@export_range(-1, 1, 1) var head_end := 0

var _parts: Array[MeshInstance3D] = []
var _ship: Node
var _ship3d: Node3D
var _cam: Camera3D
var _head: Node3D
var _cam_rest := Transform3D.IDENTITY
var _player: Node
var _streamer: Node
var _connected_to: Node
var _outlined := false
var _locked := false

var _phase := Phase.IDLE
var _t := 0.0
var _blend := 0.0        # 0 = standing, 1 = lying in the bed
var _fade := 0.0         # 0 = clear, 1 = black
var _msg_a := 0.0
var _hours := 0.0
var _lock_before := false
var _hands_were_visible := true
var _layer: CanvasLayer
var _black: ColorRect
var _msg: Label
var _bed_ready := false
var _bed_box := AABB()           # the bed in the ship's frame
var _head_dir := Vector3.ZERO    # ship frame, horizontal: from the foot to the pillow end

func _ready() -> void:
	_ship = get_parent()
	_ship3d = _ship as Node3D
	process_priority = 100       # after the helm and the chart, which also move the camera
	_build_overlay()
	call_deferred("_collect")

func _collect() -> void:
	for n in _ship.find_children("*", "MeshInstance3D", true, false):
		if n.has_meta("interaction") and String(n.get_meta("interaction")) == "bed":
			_parts.append(n)
	if _parts.is_empty():
		push_warning("ShipBed: no bed (a mesh with interaction = bed) in the ship; bed left alone")
		set_process(false)
		set_process_input(false)

func _camera() -> Camera3D:
	if _cam == null or not is_instance_valid(_cam):
		_player = get_tree().get_first_node_in_group("player")
		if _player:
			_head = _player.get_node_or_null("Head") as Node3D
			_cam = _player.get_node_or_null("Head/Camera3D") as Camera3D
			if _cam:
				_cam_rest = _cam.transform
	return _cam

func _world() -> Node:
	if _streamer == null or not is_instance_valid(_streamer):
		_streamer = get_tree().get_first_node_in_group("world_streamer")
	return _streamer

## Listen for Enter in the sleep window, once the world scene's streamer exists.
func _connect_world() -> void:
	var st := _world()
	if st == null or st == _connected_to:
		return
	_connected_to = st
	if not st.is_connected("sleep_requested", _on_sleep_requested):
		st.connect("sleep_requested", _on_sleep_requested)

func _aimed() -> bool:
	var cam := _camera()
	if cam == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if bool(_player.get("input_locked")) or bool(_player.get_meta("grab_busy", false)):
		return false
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	for m in _parts:
		var inv := m.global_transform.affine_inverse()
		var hit = m.get_aabb().grow(0.03).intersects_ray(inv * o, (inv.basis * d).normalized())
		if hit != null and o.distance_to(m.global_transform * (hit as Vector3)) <= reach:
			return true
	return false

func _input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if _locked or _phase != Phase.IDLE or _world() == null or not _aimed():
		return
	_world().call("open_prompt")
	_player.set("input_locked", true)
	_locked = true
	get_viewport().set_input_as_handled()        # no hole punching, no recapture

func _process(delta: float) -> void:
	_connect_world()
	if _phase != Phase.IDLE:
		_run(delta)
		return
	# stand still while the sleep window is open, then get up
	if _locked and (_world() == null or not bool(_world().get("prompt_open"))):
		_locked = false
		if _player:
			_player.set("input_locked", false)
	# outlined while you can click it, but only if there is a world to sleep in
	var want := not _locked and _world() != null and _aimed()
	if want != _outlined:
		_outlined = want
		for m in _parts:
			Outline.set_on(m, want)

# ---------------------------------------------------------------- the sleep sequence

## Enter was pressed in the sleep window.
func _on_sleep_requested(hours: float) -> void:
	var st := _world()
	if st == null or _phase != Phase.IDLE:
		return
	if _camera() == null or _head == null or _ship3d == null or not _measure_bed():
		st.call("sleep", hours)         # nothing to lie down on: just sleep
		return
	_hours = hours
	# the lock is ours when the bed's click opened the window; when T did, someone else may hold it
	_lock_before = bool(_player.get("input_locked")) and not _locked
	_locked = true
	_player.set("input_locked", true)
	st.set("sleep_busy", true)
	# a camera view from the wheel would fight with ours
	var helm := _ship.get_node_or_null("ShipHelm")
	if helm:
		helm.set("view", 0)
		helm.set("peek", false)
	var h = _player.get("hands")
	if h is Node3D:
		_hands_were_visible = h.visible
		h.visible = false
	_blend = 0.0
	_fade = 0.0
	_msg_a = 0.0
	_msg.text = ""
	_begin(Phase.LIE)

func _begin(p: Phase) -> void:
	_phase = p
	_t = 0.0
	if p == Phase.BLACK:
		_do_sleep()

## Runs while the screen is fully black.
func _do_sleep() -> void:
	var st := _world()
	if st == null:
		return
	st.call("sleep", _hours)
	_msg.text = String(st.get("message"))
	st.set("message_t", 0.0)             # it is shown here instead of on the HUD

func _port_loading() -> bool:
	var st := _world()
	if st == null:
		return false
	var l = st.get("_loading")
	return l is Dictionary and not (l as Dictionary).is_empty()

func _run(delta: float) -> void:
	_t += delta
	match _phase:
		Phase.LIE:
			_blend = clampf(_t / lie_down_time, 0.0, 1.0)
			if _t >= lie_down_time:
				_begin(Phase.FADE_OUT)
		Phase.FADE_OUT:
			_fade = clampf(_t / fade_out_time, 0.0, 1.0)
			if _t >= fade_out_time:
				_fade = 1.0
				_begin(Phase.BLACK)
		Phase.BLACK:
			_msg_a = clampf(_t / message_pop_time, 0.0, 1.0)
			if _t >= black_hold and (not _port_loading() or _t >= black_hold + loading_wait_max):
				_begin(Phase.FADE_IN)
		Phase.FADE_IN:
			_fade = 1.0 - clampf(_t / fade_in_time, 0.0, 1.0)
			if _t >= fade_in_time:
				_fade = 0.0
				_begin(Phase.WAKE)
		Phase.WAKE:
			# fully clear now: the message lingers and fades, and you get up
			_msg_a = 1.0 - clampf((_t - message_linger) / message_fade_time, 0.0, 1.0)
			_blend = 1.0 - clampf((_t - get_up_delay) / get_up_time, 0.0, 1.0)
			if _t >= maxf(message_linger + message_fade_time, get_up_delay + get_up_time):
				_finish()
				return
	_apply()

func _apply() -> void:
	var a := smoothstep(0.0, 1.0, _fade)
	_black.color = Color(0.0, 0.0, 0.0, a)
	_black.visible = a > 0.001
	_msg.modulate.a = _msg_a
	_msg.visible = _msg_a > 0.001
	var cam := _camera()
	if cam == null or _head == null:
		return
	var rest := _head.global_transform * _cam_rest
	var k := smoothstep(0.0, 1.0, _blend)
	cam.global_transform = rest if k <= 0.0 else rest.interpolate_with(_bed_pose(), k)

func _finish() -> void:
	_fade = 0.0
	_msg_a = 0.0
	_blend = 0.0
	_apply()
	var cam := _camera()
	if cam:
		cam.transform = _cam_rest
	if _player:
		var h = _player.get("hands")
		if h is Node3D:
			h.visible = _hands_were_visible
		_player.set("input_locked", _lock_before)
	var st := _world()
	if st:
		st.set("sleep_busy", false)
	_locked = false
	_phase = Phase.IDLE

# ---------------------------------------------------------------- where the camera lies

## The bed's box in the ship's frame, which way the pillow is. False if there is no bed to measure.
func _measure_bed() -> bool:
	if _bed_ready:
		return true
	if _parts.is_empty() or _ship3d == null:
		return false
	var to_ship := _ship3d.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for m in _parts:
		var xf := to_ship * m.global_transform
		var bb := m.get_aabb()
		for i in 8:
			var q := xf * (bb.position + bb.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1))
			if first:
				box = AABB(q, Vector3.ZERO)
				first = false
			else:
				box = box.expand(q)
	if box.size.length() < 0.05:
		return false
	_bed_box = box
	var axis := Vector3.RIGHT if box.size.x > box.size.z else Vector3.BACK
	var sgn := head_end
	if sgn == 0:
		sgn = _pillow_sign(to_ship, axis, box)
	_head_dir = axis * float(sgn)
	_bed_ready = true
	return true

## +1 or -1: which end of the bed along axis stands highest (pillow, headboard).
func _pillow_sign(to_ship: Transform3D, axis: Vector3, box: AABB) -> int:
	var mid := box.get_center().dot(axis)
	var hi_plus := -INF
	var hi_minus := -INF
	for m in _parts:
		if m.mesh == null:
			continue
		var xf := to_ship * m.global_transform
		var faces := m.mesh.get_faces()
		for i in faces.size():
			var q := xf * faces[i]
			if q.dot(axis) >= mid:
				hi_plus = maxf(hi_plus, q.y)
			else:
				hi_minus = maxf(hi_minus, q.y)
	if absf(hi_plus - hi_minus) < 0.03:
		return 1
	return 1 if hi_plus > hi_minus else -1

## Lying on the bed looking up, in world space (follows the ship's roll and any origin shift).
func _bed_pose() -> Transform3D:
	var c := _bed_box.get_center()
	var bed_len := _bed_box.size.x if absf(_head_dir.x) > 0.5 else _bed_box.size.z
	var pos := Vector3(c.x, _bed_box.end.y + eye_above_bed, c.z) + _head_dir * (bed_len * toward_head)
	var tilt := deg_to_rad(look_tilt_deg)
	var fwd := (Vector3.UP * cos(tilt) - _head_dir * sin(tilt)).normalized()
	return _ship3d.global_transform * Transform3D(Basis.looking_at(fwd, _head_dir), pos)

# ---------------------------------------------------------------- the black screen and its message

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100                   # over the HUD, the sleep window and the chart hint
	add_child(_layer)
	_black = ColorRect.new()
	_black.color = Color(0.0, 0.0, 0.0, 0.0)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.visible = false
	_layer.add_child(_black)
	_msg = Label.new()
	_msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_msg.offset_left = 140.0
	_msg.offset_right = -140.0
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.add_theme_color_override("font_color", Color(0.96, 0.92, 0.80))
	_msg.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_msg.add_theme_constant_override("outline_size", 6)
	_msg.add_theme_font_size_override("font_size", 34)
	if ResourceLoader.exists("res://assets/fonts/IMFellEnglish-Regular.ttf"):
		_msg.add_theme_font_override("font", load("res://assets/fonts/IMFellEnglish-Regular.ttf") as Font)
	_msg.visible = false
	_layer.add_child(_msg)
