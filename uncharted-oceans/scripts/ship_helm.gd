class_name ShipHelm
extends Node
## What you can do while your hand is on the brig's wheel. Created by ship_motion.gd (wheel_enabled).
##
## Hold the wheel (ship_wheel.gd: hold left click on it) and a list of keys shows on the right:
##   Q  wheel amidships: the helm eases back to centre.
##   Z  hold course: a steady hand keeps the heading you have now (the wheel turns by itself, at a
##      helmsman's pace). Z again, Q, or turning the wheel yourself lets it go. The ship keeps the
##      course after you let go of the wheel, so you can walk off to work the ropes (hold_survives_letting_go).
##   V  look at the compass (the camera moves over it; V again to look back).
##   X  look aft over the stern rail at the log line (ship_log_line.gd shows it only from here).
## Letting go of the wheel puts the camera back.
##
## Sail work is never done from here: sails and braces are hauled by hand at their ropes
## (ship_sails.gd). Crew orders from the wheel come later with the sailors.
##
## Camera views use the brig's own marker pairs (CamPos_Compass / CamTarget_Compass and
## CamPos_LogLine / CamTarget_LogLine, game_role camera_marker; any name with "compass", or
## "log", "rail", "stern", "knot" is accepted). Without them it falls back to a spot over the
## compass and one at the stern rail, found from the wheel and the hull's size.
##
## The compass: the card turns to keep north as the ship turns, under the binnacle's glass.
## If the brig has its own card (a node called Compass_Card) that one is turned. Otherwise a plain
## card is built under BinnacleGlass (build_compass); with no binnacle either, a small stand-in
## binnacle is built in front of the wheel.

@export var key_amidships := KEY_Q
@export var key_hold_course := KEY_Z
@export var key_compass := KEY_V
@export var key_stern := KEY_X

## How fast the hand turns the wheel on its own (degrees of wheel per second).
@export var wheel_rate_deg := 240.0
## Course holding: rudder (-1..1) per degree off course, per degree/second of turn, and per degree-second of error.
@export var kp := 0.067
@export var kd := 0.30
@export var ki := 0.004
## Keep the course after you let go of the wheel.
@export var hold_survives_letting_go := true

## How fast the camera moves to a view and back (higher = snappier).
@export var follow_rate := 6.0

## Build a card when the brig has none of its own.
@export var build_compass := true
## For the brig's own Compass_Card: degrees the printed N sits to port of the bow when the card is at rest.
@export var card_north_deg := 0.0
## Stand-in compass, only when the brig has no binnacle glass: from the wheel hub, in the ship's frame
## (bow is -Z), and the height of its pedestal.
@export var compass_offset := Vector3(0.0, -0.35, -0.9)
@export var compass_pedestal := 0.8
## Stern view fallback: how far inboard of the stern the camera sits.
@export var stern_view_back := 1.1

## Holding a course now.
var hold := false
var hold_heading := 0.0         # heading_deg being held (0 = north, grows to port)
## 0 = normal view, 1 = compass, 2 = stern rail (log line).
var view := 0
## Set by ShipInteract while you've clicked the compass without holding the wheel: keeps the compass view.
var peek := false

var _ship: Node3D
var _wheel: Node
var _cam: Camera3D
var _head: Node3D
var _cam_rest := Transform3D.IDENTITY
var _cam_moved := false
var _amid := false
var _integ := 0.0
var _expected := 0.0
var _label: Label
var _markers := {}              # view -> [position marker, target marker]
var _card: Node3D
var _card_base_y := 0.0
var _hub := Vector3.ZERO        # wheel hub, ship frame
var _stern_local = null         # Transform3D once worked out

func _ready() -> void:
	_ship = get_parent() as Node3D
	_wheel = _ship.get_node_or_null("ShipWheel")
	if _wheel == null or _wheel.get("_wheel") == null:
		push_warning("ShipHelm: no working ShipWheel; helm commands are off")
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	_hub = _ship.to_local((_wheel.get("_wheel") as Node3D).global_position)
	_find_markers()
	_setup_compass()
	_make_label()

# ---------------------------------------------------------------- keys

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if not _held():
		return
	var k: int = e.physical_keycode
	if k == key_amidships:
		hold = false
		_amid = true
		_expected = float(_wheel.get("turn"))
	elif k == key_hold_course:
		if hold:
			_release_course()
		else:
			hold = true
			_amid = false
			hold_heading = float(_ship.get("heading_deg"))
			_integ = 0.0
			_expected = float(_wheel.get("turn"))
	elif k == key_compass:
		view = 0 if view == 1 else 1

func _held() -> bool:
	return _wheel != null and bool(_wheel.get("held"))

func _release_course() -> void:
	hold = false
	_integ = 0.0

# ---------------------------------------------------------------- steering

func _physics_process(delta: float) -> void:
	if hold and not _held() and not hold_survives_letting_go:
		_release_course()
	if not (hold or _amid):
		return
	var turn := float(_wheel.get("turn"))
	if absf(turn - _expected) > deg_to_rad(1.0):
		# you turned the wheel yourself: the helmsman lets go
		_release_course()
		_amid = false
		return
	var limit := deg_to_rad(float(_wheel.get("max_turn_deg")))
	var target := 0.0
	if hold:
		var heading := float(_ship.get("heading_deg"))
		var err := wrapf(hold_heading - heading, -180.0, 180.0)      # + = target is to port
		var rate := float(_ship.get("yaw_rate_deg"))                # + = turning to port
		_integ = clampf(_integ + err * delta, -60.0, 60.0)
		var to_port := kp * err - kd * rate + ki * _integ
		target = clampf(-to_port, -1.0, 1.0) * limit               # rudder + = starboard
	var step := deg_to_rad(wheel_rate_deg) * delta
	turn = move_toward(turn, target, step)
	_wheel.set("turn", turn)
	_expected = turn
	if _amid and is_equal_approx(turn, 0.0):
		_amid = false

# ---------------------------------------------------------------- camera and prompt

func _camera() -> Camera3D:
	if _cam == null or not is_instance_valid(_cam):
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			_head = pl.get_node_or_null("Head") as Node3D
			_cam = pl.get_node_or_null("Head/Camera3D") as Camera3D
			if _cam:
				_cam_rest = _cam.transform
	return _cam

func _process(delta: float) -> void:
	var held := _held()
	if not held and not peek:
		view = 0
	_wheel.set("view_lock", view != 0)
	_move_camera(delta)
	if _card:
		_card.rotation.y = _card_base_y - deg_to_rad(float(_ship.get("heading_deg")) + card_north_deg)
	_update_label(held)

func _move_camera(delta: float) -> void:
	var cam := _camera()
	if cam == null or _head == null:
		return
	if view == 0 and not _cam_moved:
		return
	var rest := _head.global_transform * _cam_rest
	var want := rest
	if view != 0:
		want = _view_xf(view)
	_cam_moved = true
	var a := 1.0 - exp(-delta * follow_rate)
	var next := cam.global_transform.interpolate_with(want, a)
	cam.global_transform = next
	if view == 0:
		var ang := next.basis.get_rotation_quaternion().angle_to(rest.basis.get_rotation_quaternion())
		if next.origin.distance_to(rest.origin) < 0.004 and ang < 0.01:
			cam.transform = _cam_rest
			_cam_moved = false

func _view_xf(v: int) -> Transform3D:
	if _markers.has(v):
		var pair: Array = _markers[v]
		var p := pair[0] as Node3D
		var t := pair[1] as Node3D
		if is_instance_valid(p) and is_instance_valid(t):
			var d := t.global_position - p.global_position
			if d.length() > 0.001:
				return _look(p.global_position, d.normalized())
	var local := _compass_view_local() if v == 1 else _stern_view_local()
	return _ship.global_transform * local

func _look(pos: Vector3, dir: Vector3) -> Transform3D:
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.BACK
	return Transform3D(Basis.looking_at(dir, up), pos)

func _compass_view_local() -> Transform3D:
	var c := _hub + compass_offset
	if _card:
		c = _ship.to_local(_card.global_position)
	var p := c + Vector3(0.0, 0.9, 0.35)
	var d := (c - p).normalized()
	var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.BACK
	return Transform3D(Basis.looking_at(d, up), p)

## A node's bounding box in the ship's frame (box of its eight corners).
func _ship_aabb(mi: MeshInstance3D) -> AABB:
	var to_ship := _ship.global_transform.affine_inverse() * mi.global_transform
	var bb := mi.mesh.get_aabb()
	var out := AABB()
	for i in 8:
		var q := to_ship * (bb.position + bb.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1))
		if i == 0:
			out = AABB(q, Vector3.ZERO)
		else:
			out = out.expand(q)
	return out

## Over the stern rail, looking aft and down at the water. Found from the hull's size, once.
func _stern_view_local() -> Transform3D:
	if _stern_local != null:
		return _stern_local
	var aft_z := _hub.z + 3.0
	var top_y := _hub.y
	var mi := _ship.find_child(String(_ship.get("hull_mesh_name")), true, false) as MeshInstance3D
	if mi and mi.mesh:
		var box := _ship_aabb(mi)
		aft_z = box.end.z
		top_y = box.end.y
	var p := Vector3(0.0, top_y + 0.25, aft_z - stern_view_back)
	var t := Vector3(0.0, top_y - 0.6, aft_z + 1.5)
	var d := (t - p).normalized()
	var xf := Transform3D(Basis.looking_at(d, Vector3.UP), p)
	_stern_local = xf
	return xf

func _make_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	_label = Label.new()
	# along the bottom of the screen, in the title face, like the other prompts
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.offset_bottom = -40.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	if ResourceLoader.exists("res://assets/fonts/Ferrum-ExtraCondensed.otf"):
		_label.add_theme_font_override("font", load("res://assets/fonts/Ferrum-ExtraCondensed.otf") as Font)
		_label.add_theme_font_size_override("font_size", 26)
	else:
		_label.add_theme_font_size_override("font_size", 20)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	layer.add_child(_label)
	add_child(layer)

func _bearing_text(heading_deg: float) -> String:
	return "%03d° (%s)" % [roundi(fposmod(-heading_deg, 360.0)) % 360, ShipClasses.compass(heading_deg)]

func _update_label(held: bool) -> void:
	var text := ""
	var heading := float(_ship.get("heading_deg"))
	if held:
		# only the keys: the heading is on the compass, the course you hold is where the bow is pointing
		var parts := PackedStringArray()
		parts.append("[%s] amidships" % OS.get_keycode_string(key_amidships))
		parts.append("[%s] %s" % [OS.get_keycode_string(key_hold_course), "let go of the course" if hold else "hold course"])
		parts.append("[%s] %s" % [OS.get_keycode_string(key_compass), "look ahead" if view == 1 else "compass"])
		text += "     ".join(parts)
	_label.text = text
	_label.visible = text != ""

# ---------------------------------------------------------------- markers and the compass

func _find_markers() -> void:
	var pos := {}
	var tgt := {}
	for n in get_tree().get_nodes_in_group("camera_markers"):
		if not (n is Node3D) or not _ship.is_ancestor_of(n):
			continue
		var nm := String(n.name).to_lower()
		var v := 0
		if nm.contains("compass"):
			v = 1
		elif nm.contains("log") or nm.contains("rail") or nm.contains("stern") or nm.contains("knot"):
			v = 2
		if v == 0:
			continue
		if nm.contains("campos"):
			pos[v] = n
		elif nm.contains("camtarget"):
			tgt[v] = n
	for v in [1, 2]:
		if pos.has(v) and tgt.has(v):
			_markers[v] = [pos[v], tgt[v]]

func _setup_compass() -> void:
	var own := _ship.find_child("Compass_Card", true, false) as Node3D
	if own:
		_card = own
		_card_base_y = own.rotation.y
		return
	if build_compass:
		_build_compass()

func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

## A card that keeps north, with N E S W and tick marks, and a red lubber line fixed to the ship at the
## bow so it reads the heading the bow is on. Goes under the binnacle's glass if there is one (sized
## to it), otherwise it builds a small binnacle of its own in front of the wheel.
func _build_compass() -> void:
	var r := 0.118
	var at := _hub + compass_offset
	var stand_in := true
	var glass := _ship.find_child("BinnacleGlass", true, false) as MeshInstance3D
	if glass and glass.mesh:
		var box := _ship_aabb(glass)
		at = Vector3(box.get_center().x, box.position.y + 0.012, box.get_center().z)
		r = minf(box.size.x, box.size.z) * 0.5 * 0.92
		stand_in = false
	var k := r / 0.118
	var root := Node3D.new()
	root.name = "CompassCard"
	root.position = at
	_ship.add_child(root)
	var cream := _mat(Color(0.93, 0.9, 0.8), 0.9, 0.0)
	var ink := _mat(Color(0.08, 0.07, 0.06), 0.9, 0.0)
	var red := _mat(Color(0.75, 0.08, 0.06), 0.8, 0.0)
	if stand_in:
		var brass := _mat(Color(0.72, 0.55, 0.22), 0.35, 0.8)
		var wood := _mat(Color(0.20, 0.12, 0.07), 0.8, 0.0)
		var ped := CylinderMesh.new()
		ped.top_radius = 0.11
		ped.bottom_radius = 0.15
		ped.height = compass_pedestal
		ped.radial_segments = 14
		ped.rings = 1
		_part(root, ped, wood, Vector3(0.0, -0.075 - compass_pedestal * 0.5, 0.0))
		var bowl := CylinderMesh.new()
		bowl.top_radius = 0.135
		bowl.bottom_radius = 0.125
		bowl.height = 0.07
		bowl.radial_segments = 20
		bowl.rings = 1
		_part(root, bowl, brass, Vector3(0.0, -0.04, 0.0))
	_card = Node3D.new()
	_card.name = "Card"
	root.add_child(_card)
	var disc := CylinderMesh.new()
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = 0.004
	disc.radial_segments = 28
	disc.rings = 1
	_part(_card, disc, cream, Vector3(0.0, 0.0, 0.0))
	var tick := BoxMesh.new()
	tick.size = Vector3(0.004, 0.002, 0.014) * k
	for i in 16:
		var b := deg_to_rad(22.5 * i)
		var mi := _part(_card, tick, ink, Vector3(sin(b), 0.0035, -cos(b)) * r * 0.89)
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
		lab.position = Vector3(sin(b), 0.0, -cos(b)) * r * 0.61 + Vector3(0.0, 0.004, 0.0)
		_card.add_child(lab)
	var lub := BoxMesh.new()
	lub.size = Vector3(0.006, 0.006, 0.03) * k
	_part(root, lub, red, Vector3(0.0, 0.004, -(r - 0.012 * k)))
