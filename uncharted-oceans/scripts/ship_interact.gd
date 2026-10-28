class_name ShipInteract
extends Node
## Outlines things on the ship in white while you're looking at them close enough to click.
## Created by ship_motion.gd (interact_enabled). The wheel, the ropes and the bookshelf outline themselves
## (ship_wheel.gd, ship_rope.gd, ship_bookshelf.gd); this covers the rest:
##   * the compass is not clickable or outlined: V at the wheel looks at it, or you walk up to it.
##   * anything else you register with _add() gets the same treatment and emits `clicked(node)` (nothing else
##     is registered now: the pump handle has its own script, ship_pump.gd, and the cannons aren't clickable yet)

signal clicked(node: Node3D)

const Outline := preload("res://scripts/interact_outline.gd")

@export var reach := 2.6
@export var gun_group := "guns"
@export var pump_prefix := "Pump"
@export var compass_name := "Compass"

class Target:
	var root: Node3D
	var meshes: Array[MeshInstance3D] = []
	var kind := ""
	var needs_wheel := false

var _targets: Array[Target] = []
var _cam: Camera3D
var _player: Node
var _current: Target
var _ship: Node
var _peeking := false

func _ready() -> void:
	_ship = get_parent()
	# the brig's own nodes exist by the time this runs, but ShipHelm may not: look things up lazily
	call_deferred("_collect")

func _collect() -> void:
	# nothing is registered: the compass is not clickable or outlined (V at the wheel looks at it, or walk up to it)
	pass

func _add(root: Node3D, kind: String, needs_wheel: bool) -> void:
	var t := Target.new()
	t.root = root
	t.kind = kind
	t.needs_wheel = needs_wheel
	for m in root.find_children("*", "MeshInstance3D", true, false):
		t.meshes.append(m)
	if root is MeshInstance3D:
		t.meshes.append(root)
	_targets.append(t)

func _camera() -> Camera3D:
	if _cam == null or not is_instance_valid(_cam):
		_player = get_tree().get_first_node_in_group("player")
		if _player:
			_cam = _player.get_node_or_null("Head/Camera3D") as Camera3D
	return _cam

func _at_wheel() -> bool:
	var w := _ship.get_node_or_null("ShipWheel")
	return w != null and bool(w.get("held"))

func _process(_delta: float) -> void:
	var cam := _camera()
	var best: Target = null
	if cam != null and not _peeking and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not bool(_player.get("input_locked")):
		var o := cam.global_position
		var d := -cam.global_transform.basis.z
		var at_wheel := _at_wheel()
		var best_d := reach
		for t in _targets:
			if t.kind == "compass" and at_wheel:
				continue                      # at the wheel the compass is V, not a click (the button is busy holding the wheel)
			if not is_instance_valid(t.root):
				continue
			for m in t.meshes:
				var inv := m.global_transform.affine_inverse()
				var hit = m.get_aabb().grow(0.03).intersects_ray(inv * o, (inv.basis * d).normalized())
				if hit != null:
					var dist := o.distance_to(m.global_transform * (hit as Vector3))
					if dist < best_d:
						best_d = dist
						best = t
	if best != _current:
		if _current != null and is_instance_valid(_current.root):
			Outline.set_on(_current.root, false)
		_current = best
		if _current != null:
			Outline.set_on(_current.root, true)

func _input(e: InputEvent) -> void:
	if _peeking:
		# any click or Esc puts the camera back
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE):
			_end_peek()
			get_viewport().set_input_as_handled()
		return
	if _current == null or not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if _current.kind == "compass":
		_start_peek()
	else:
		clicked.emit(_current.root)
	get_viewport().set_input_as_handled()

## Click the compass (not at the wheel): the camera moves over it, you stand still; click or Esc to look up again.
func _start_peek() -> void:
	var helm := _ship.get_node_or_null("ShipHelm")
	if helm == null:
		return
	_peeking = true
	_player.set("input_locked", true)
	helm.set("peek", true)
	helm.set("view", 1)

func _end_peek() -> void:
	_peeking = false
	_player.set("input_locked", false)
	var helm := _ship.get_node_or_null("ShipHelm")
	if helm != null:
		helm.set("peek", false)
		helm.set("view", 0)
