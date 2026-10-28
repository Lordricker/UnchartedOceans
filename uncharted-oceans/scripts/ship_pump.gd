class_name ShipPump
extends Node
## The bilge pump's brake handle. Created by ship_motion.gd (pump_enabled).
##
## Look at the handle (it is outlined in white), hold the left button and take hold of it: the pumps go on,
## and both hands work the handle up and down, hand over hand, for as long as you hold on. Let go and
## the pumps stop and the handle settles. (The water they move is ShipFlooding's pump_rate.)
## The brig's Pump_Brake swings about its own X axis (extras: brake_pivot_axis x; crew_per_pump 2, for the
## sailors who will work these later).

const Outline := preload("res://scripts/interact_outline.gd")

@export var brake_name := "Pump_Brake"
## How far you can reach the handle (m).
@export var reach := 2.2
## Strokes per second and how far the handle swings each way (degrees).
@export var stroke_hz := 0.85
@export var swing_deg := 22.0
## Where the hands take hold, in the handle's own frame. Left at zero they're worked out from the handle's size.
@export var grip_right := Vector3.ZERO
@export var grip_left := Vector3.ZERO

var held := false

var _ship: Node
var _brake: MeshInstance3D
var _basis0 := Basis.IDENTITY
var _cam: Camera3D
var _player: Node
var _hands: Node
var _flood: Node
var _phase := 0.0
var _amp := 0.0
var _outlined := false
var _turned_on := false

func _ready() -> void:
	_ship = get_parent()
	_brake = _ship.find_child(brake_name, true, false) as MeshInstance3D
	if _brake == null:
		push_warning("ShipPump: no %s in the ship; pump left alone" % brake_name)
		set_process(false)
		set_process_input(false)
		return
	_basis0 = _brake.transform.basis
	var bb := _brake.get_aabb()
	var gx := minf(0.12, bb.size.x * 0.3)
	var gy := bb.end.y - 0.04
	var gz := bb.end.z - 0.08
	if grip_right == Vector3.ZERO:
		grip_right = Vector3(gx, gy, gz)
	if grip_left == Vector3.ZERO:
		grip_left = Vector3(-gx, gy, gz)

func _camera() -> Camera3D:
	if _cam == null or not is_instance_valid(_cam):
		_player = get_tree().get_first_node_in_group("player")
		if _player:
			_cam = _player.get_node_or_null("Head/Camera3D") as Camera3D
			_hands = _player.get("hands")
	return _cam

## True while you're looking at the handle from within reach with the mouse captured.
func _aimed() -> bool:
	var cam := _camera()
	if cam == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if bool(_player.get("input_locked")) or bool(_player.get_meta("grab_busy", false)):
		return false
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var inv := _brake.global_transform.affine_inverse()
	var hit = _brake.get_aabb().grow(0.08).intersects_ray(inv * o, (inv.basis * d).normalized())
	return hit != null and o.distance_to(_brake.global_transform * (hit as Vector3)) <= reach

func _input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if e.pressed and not held and _aimed():
		_grab()
		get_viewport().set_input_as_handled()        # no hole punching, no recapture
	elif not e.pressed and held:
		_release()
		get_viewport().set_input_as_handled()

func _grab() -> void:
	held = true
	_player.set_meta("grab_busy", true)
	_flood = get_tree().get_first_node_in_group("ship_flooding")
	if _flood != null and not bool(_flood.get("pumps_on")):
		_flood.set("pumps_on", true)
		_turned_on = true

func _release() -> void:
	held = false
	if _player:
		_player.set_meta("grab_busy", false)
	if _turned_on and _flood != null and is_instance_valid(_flood):
		_flood.set("pumps_on", false)
	_turned_on = false
	if _hands != null and is_instance_valid(_hands):
		_hands.set("hold_active", false)
		_hands.set("hold_active_l", false)
		_hands.set("closed_override", [-1.0, -1.0])

func _process(delta: float) -> void:
	var cam := _camera()
	if cam == null:
		return
	if held and (Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or cam.global_position.distance_to(_brake.global_position) > reach + 1.2):
		_release()                         # Esc, or you walked away
	# the handle works while you hold it, and settles when you let go
	_amp = move_toward(_amp, 1.0 if held else 0.0, delta * (3.0 if held else 2.0))
	if _amp > 0.0:
		_phase += TAU * stroke_hz * delta
		var a := deg_to_rad(swing_deg) * _amp * sin(_phase)
		_brake.transform.basis = _basis0 * Basis(Vector3.RIGHT, a)
	elif _brake.transform.basis != _basis0:
		_brake.transform.basis = _basis0
		_phase = 0.0
	if held and _hands != null and is_instance_valid(_hands):
		var xf := _brake.global_transform
		_hands.set("hold_active", true)
		_hands.set("hold_point", xf * grip_right)
		_hands.set("hold_active_l", true)
		_hands.set("hold_point_l", xf * grip_left)
		_hands.set("closed_override", [1.0, 1.0])
	var want := held or _aimed()
	if want != _outlined:
		_outlined = want
		Outline.set_on(_brake, want)
