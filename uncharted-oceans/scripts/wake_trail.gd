class_name WakeTrail
extends Node
## The ship's wake as water that stays behind her (the High water setting, Ocean.water_quality).
##
## Every SPACING metres she travels this records where her bow and her stern were, when, and how fast she was going. The ocean
## shader turns each bow record into a ring of water spreading out from where the bow was (the rings overlap into the V of
## arms about 20 degrees off her track) and each stern record into a patch of churned, darker, foamy water that fades. Because
## the records stay where they were made, the wake bends when she turns and carries on after she stops.
## Nothing is simulated here: the shader works the shapes out from the records, so this node only keeps a list.
## Child of the ship (ship_motion.gd adds it). On the Standard setting it does nothing.

const N := 64                  # records kept (the shader's arrays are this long): 64 x 1.5 m = a trail up to about 96 m
const SPACING := 1.5           # metres of travel between records
const MIN_SPEED := 0.3         # no records while she is (nearly) stopped
const JUMP := 40.0             # she moved this far in one frame: a world rebase or a sleep jump, so start the trail again

var _ship: Node3D
var _ocean: Ocean
var _bow := PackedVector4Array()
var _stern := PackedVector4Array()
var _head := 0
var _last := Vector2(1.0e9, 1.0e9)
var _was_on := false

func _ready() -> void:
	_ship = get_parent() as Node3D
	if _ship:
		_ocean = _ship.get_node_or_null(_ship.get("ocean_path")) as Ocean
	_clear()

## Empty the list: a record born at -1000 s is older than anything the shader draws.
func _clear() -> void:
	_bow.resize(N)
	_stern.resize(N)
	for i in N:
		_bow[i] = Vector4(0.0, 0.0, -1000.0, 0.0)
		_stern[i] = Vector4(0.0, 0.0, -1000.0, 0.0)
	_head = 0

func _process(_delta: float) -> void:
	if _ship == null or _ocean == null:
		return
	var mat := _ocean.get_ocean_material()
	if mat == null:
		return
	var on := _ocean.water_quality >= 1
	if on != _was_on:
		_was_on = on
		_clear()
		_last = Vector2(1.0e9, 1.0e9)
		mat.set_shader_parameter("wake_trail_on", 1.0 if on else 0.0)
		mat.set_shader_parameter("wake_bow", _bow)
		mat.set_shader_parameter("wake_stern", _stern)
	if not on:
		return
	var pos := Vector2(_ship.global_position.x, _ship.global_position.z)
	if pos.distance_to(_last) > JUMP:
		_clear()
		_last = pos
	var v := absf(float(_ship.get("speed")))
	if v > MIN_SPEED and pos.distance_to(_last) >= SPACING:
		var yaw := deg_to_rad(float(_ship.get("heading_deg")))
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		# hull_bow / hull_stern are metres along the bow direction from the rig's origin (stern is negative)
		var bow_p := pos + fwd * float(_ship.get("_hull_bow"))
		var stern_p := pos + fwd * float(_ship.get("_hull_stern"))
		var t := _ocean.time
		_bow[_head] = Vector4(bow_p.x, bow_p.y, t, v)
		_stern[_head] = Vector4(stern_p.x, stern_p.y, t, v)
		_head = (_head + 1) % N
		_last = pos
	mat.set_shader_parameter("wake_bow", _bow)
	mat.set_shader_parameter("wake_stern", _stern)
