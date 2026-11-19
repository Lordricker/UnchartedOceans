class_name ShipWheel
extends Node
## Click-and-drag steering for the brig's wheel. Created by ship_motion.gd (wheel_enabled).
##
## Look at the wheel and hold the left mouse button: your right hand grabs the wheel at that
## spot. While you hold, the camera stays put and moving the mouse turns the wheel: move it the
## way the rim moves where you grabbed (grab the top and slide left or right, grab the side and
## slide up or down). Let go to release.
## Turning the wheel clockwise, seen from behind it, turns the ship to starboard.
##
## The wheel (node "Wheel" in Brig.glb) spins about its own axle and the rudder ("Rudder")
## swings with it. The ship only answers the rudder while it is underway (F in game);
## see ship_motion.gd (max_turn_rate_deg, turn_lag).

## How far from your eyes you can grab it (metres).
@export var reach := 1.8
## Mouse drag to wheel rotation (degrees of wheel per pixel).
@export var degrees_per_pixel := 0.7
## Wheel lock to lock: the wheel stops this far either side of centre (1080 = 3 turns; it was 540). The rudder follows
## the wheel in proportion, so the same turn of the wheel now gives half the rudder: half the sensitivity.
@export var max_turn_deg := 1080.0
## Rudder angle when the wheel is at its stop.
@export var rudder_max_deg := 30.0
## Grab area on the wheel face, in metres from the hub.
@export var grip_inner := 0.3
@export var grip_outer := 1.05
@export var wheel_name := "Wheel"
@export var rudder_name := "Rudder"
## Tiller mode (ShipClasses "helm": {"type": "tiller", ...}): the handle is the node called wheel_name ("Tiller"), a child of
## the rudder, so it swings with it. Drag the mouse sideways to push the handle; the ship turns the other way, as with a real
## tiller (handle to starboard = bow to port). turn, rudder and max_turn_deg work as for the wheel, so ShipHelm needs no change.
@export var grip_radius := 0.14
## +1 / -1: which way the rudder node turns for a positive (starboard) turn in tiller mode. -1 puts the blade's trailing edge on the
## side the ship turns to (so the handle, forward of the rudder head, goes the other way, as on a real boat).
@export var tiller_rudder_sign := -1.0

## Wheel angle in radians (+ = clockwise seen from behind = turn to starboard).
var turn := 0.0
var held := false
## Set by ShipHelm while the camera is away looking at the compass or the stern rail: the wheel then
## judges how far you've wandered from where you stand, not from where the camera is.
var view_lock := false

var _ship: Node
var _wheel: Node3D
var _tiller_mode := false
var _tiller_tip := Vector3(0.0, 0.0, 1.7)   # the handle's far end, in the tiller's own frame
var _rudder: Node3D
var _wheel_basis0 := Basis.IDENTITY
var _rudder_basis0 := Basis.IDENTITY
var _grip_local := Vector3.ZERO     # grip point in the wheel's own frame
var _drag_dir := Vector2.RIGHT      # screen direction of mouse movement that turns the wheel clockwise
var _cam: Camera3D
var _hands: Node
var _label: Label
var _outlined := false

const Outline := preload("res://scripts/interact_outline.gd")

func _ready() -> void:
	_ship = get_parent()
	var hd: Dictionary = ShipClasses.data(_ship_class()).get("helm", {})
	if String(hd.get("type", "wheel")) == "tiller":
		_tiller_mode = true
		wheel_name = String(hd.get("node", "Tiller"))
		max_turn_deg = float(hd.get("max_turn_deg", 32.0))
		degrees_per_pixel = float(hd.get("degrees_per_pixel", 0.1))
		rudder_max_deg = float(hd.get("rudder_max_deg", 32.0))
	_wheel = _ship.find_child(wheel_name, true, false) as Node3D
	_rudder = _ship.find_child(rudder_name, true, false) as Node3D
	if _wheel == null:
		push_warning("ShipWheel: no node named '%s' under the ship" % wheel_name)
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		return
	if _tiller_mode and _wheel is MeshInstance3D:
		var bb := (_wheel as MeshInstance3D).get_aabb()
		_tiller_tip = Vector3(0.0, 0.0, bb.end.z if absf(bb.end.z) >= absf(bb.position.z) else bb.position.z)
	_wheel_basis0 = _wheel.transform.basis
	if _rudder:
		_rudder_basis0 = _rudder.transform.basis
	var layer := CanvasLayer.new()
	layer.layer = 5
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.offset_bottom = -140.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 5)
	_label.add_theme_font_size_override("font_size", 20)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	layer.add_child(_label)
	add_child(layer)

func _camera() -> Camera3D:
	if _cam == null or not is_instance_valid(_cam):
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			_cam = pl.get_node_or_null("Head/Camera3D") as Camera3D
			_hands = pl.get("hands")
	return _cam

## Where your crosshair meets the tiller, or null if you aren't looking at it (or it's too far): the closest point of the view
## ray to the tiller's centre line, on its handle half.
func _aim_tiller() -> Variant:
	var cam := _camera()
	if cam == null:
		return null
	var a := _wheel.global_transform * Vector3.ZERO
	var u := _wheel.global_transform * _tiller_tip - a
	var o := cam.global_position
	var d := -cam.global_basis.z
	var r := o - a
	var bb := d.dot(u)
	var cc := u.dot(u)
	var den := cc - bb * bb
	if cc < 1e-6 or absf(den) < 1e-6:
		return null
	var s := clampf((u.dot(r) - d.dot(r) * bb) / den, 0.3, 1.0)     # the first 30 % is the rudder head, not a handle
	var p := a + u * s
	var t := maxf((p - o).dot(d), 0.0)
	if p.distance_to(o + d * t) > grip_radius or p.distance_to(o) > reach:
		return null
	return p

## Where your crosshair meets the wheel face, or null if you aren't looking at it (or it's too far).
func _aim_point() -> Variant:
	if _tiller_mode:
		return _aim_tiller()
	var cam := _camera()
	if cam == null:
		return null
	var c := _wheel.global_position
	var a := _wheel.global_basis.z.normalized()
	var o := cam.global_position
	var d := -cam.global_basis.z
	var den := d.dot(a)
	if absf(den) < 0.05:
		return null                       # edge-on
	var t := (c - o).dot(a) / den
	if t < 0.0 or t > reach:
		return null
	var p := o + d * t
	var r := (p - c).length()
	if r < grip_inner or r > grip_outer:
		return null
	return p

func _grip_world() -> Vector3:
	return _wheel.global_transform * _grip_local

func _input(e: InputEvent) -> void:
	if _wheel == null:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and not held and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _busy():
			var p = _aim_point()
			if p != null:
				_grab(p)
				get_viewport().set_input_as_handled()    # no hole punching, no recapture
		elif not e.pressed and held:
			_release()
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion and held:
		_drag(e.relative)
		get_viewport().set_input_as_handled()            # the camera stays put while you steer

func _busy() -> bool:
	var pl := get_tree().get_first_node_in_group("player")
	return pl != null and pl.get_meta("grab_busy", false)

func _set_busy(b: bool) -> void:
	var pl := get_tree().get_first_node_in_group("player")
	if pl:
		pl.set_meta("grab_busy", b)

func _grab(p: Vector3) -> void:
	_set_busy(true)
	_grip_local = _wheel.global_transform.affine_inverse() * p
	held = true
	# Which way on screen the rim moves where you grabbed it (kept for the whole hold, since
	# the view doesn't move, so one straight mouse stroke can turn the wheel a long way).
	var c := _wheel.global_position
	var a := _wheel.global_basis.z.normalized()
	var tangent := a.cross(p - c).normalized()          # the way the grip moves for + turn
	var tl := _camera().global_basis.inverse() * tangent  # camera space: x right, y up
	var t2 := Vector2(tl.x, tl.y)
	_drag_dir = t2.normalized() * clampf(t2.length(), 0.35, 1.0) if t2.length_squared() > 1e-6 else Vector2.RIGHT

func _release() -> void:
	held = false
	_set_busy(false)
	if _hands:
		_hands.set("hold_active", false)

func _drag(rel: Vector2) -> void:
	if _tiller_mode:
		# the handle follows the mouse: right pushes it to starboard, which turns the bow to port (turn is + to starboard)
		turn = clampf(turn - rel.x * deg_to_rad(degrees_per_pixel), -deg_to_rad(max_turn_deg), deg_to_rad(max_turn_deg))
		return
	var amount := Vector2(rel.x, -rel.y).dot(_drag_dir)
	var limit := deg_to_rad(max_turn_deg)
	turn = clampf(turn + amount * deg_to_rad(degrees_per_pixel), -limit, limit)

func _physics_process(_delta: float) -> void:
	var cam := _camera()
	if held and (cam == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			or _eye_pos(cam).distance_to(_grip_world()) > reach + 0.8):
		_release()                        # Esc, or you walked / got carried away
	var limit := deg_to_rad(max_turn_deg)
	if "rudder" in _ship:
		_ship.rudder = turn / limit

func _process(_delta: float) -> void:
	if not _tiller_mode:                   # the tiller is a child of the rudder and swings with it
		_wheel.transform.basis = _wheel_basis0 * Basis(Vector3(0, 0, 1), turn)
	var rud := turn / deg_to_rad(max_turn_deg) * deg_to_rad(rudder_max_deg)
	if _rudder:
		_rudder.transform.basis = _rudder_basis0 * Basis(Vector3.UP, -rud * (tiller_rudder_sign if _tiller_mode else 1.0))
	if _camera() and _hands:
		# the gloves stay on the wheel unless the camera has moved off so far they couldn't reach it
		_hands.set("hold_active", held and (not view_lock or _camera().global_position.distance_to(_grip_world()) < reach + 0.4))
		if held:
			_hands.set("hold_point", _grip_world())
	var text := ""
	if held:
		var deg := absf(rad_to_deg(rud))
		text = "Rudder %d° to %s" % [roundi(deg), "starboard" if rud > 0.0 else "port"] if deg >= 0.5 else "Rudder amidships"
		if absf(float(_ship.get("speed"))) < 0.3 and not _ship.get("underway"):
			text += "   (no way on: the rudder needs the ship moving)"
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _aim_point() != null:
		text = "Hold left click and move the mouse to steer"
	if not Engine.get_meta("debug_ui", false):
		text = ""                          # the outline and the wheel itself are the prompt; H shows the readout for testing
	_label.text = text
	_label.visible = text != ""
	# the wheel is outlined in white while you can take hold of it (or are holding it)
	var want_outline := held or (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _aim_point() != null)
	if want_outline != _outlined:
		_outlined = want_outline
		Outline.set_on(_wheel, want_outline)
	# its name along the bottom while you look at it (not while you're steering: the helm hints are there)
	if want_outline and not held:
		Outline.show_name(self, "Ship's wheel")
	else:
		Outline.hide_name(self)


func _eye_pos(cam: Camera3D) -> Vector3:
	## Where you are for the "walked away from the wheel" check: the camera, or your head when the
	## camera has been moved off to look at something else (ShipHelm).
	if view_lock:
		var pl := get_tree().get_first_node_in_group("player")
		var head := pl.get_node_or_null("Head") as Node3D if pl else null
		if head:
			return head.global_position
	return cam.global_position

## The ship's size class (ShipClasses.Size), for the class's own helm.
func _ship_class() -> int:
	var c = _ship.get("ship_class")
	return int(c) if c != null else ShipClasses.Size.MEDIUM
