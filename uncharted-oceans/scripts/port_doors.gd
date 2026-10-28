class_name PortDoors
extends Node
## Opens the port's doors as the player walks up to them, and closes them again when the player leaves.
##
## Add one of these anywhere under the instanced port scene (or put the port in `port_root`).
## It looks for glTF nodes whose Blender custom properties (glTF "extras") say:
##   game_role = "door"       a door leaf; the node's origin is the hinge
##   open_angle_deg           how far it swings about its own up axis, from the closed pose (the sign is the direction)
##   open_dist_m              optional: opens when the player is closer than this to the hinge (default 3.5)
##   open_speed_dps           optional: swing speed in degrees per second (default 160)
## Leaves that have an "interaction" key (for example the vault gate) are left alone: they open from the interaction.

@export var port_root: Node
@export var player_group: StringName = &"player"
@export var default_open_dist := 3.5
@export var default_speed_dps := 160.0

var _doors: Array[Dictionary] = []
var _player: Node3D

func _ready() -> void:
	var r: Node = port_root if port_root != null else get_parent()
	_collect(r)

func _collect(n: Node) -> void:
	if n is Node3D and n.has_meta("extras"):
		var ex = n.get_meta("extras")
		if ex is Dictionary and str(ex.get("game_role", "")) == "door" and ex.has("open_angle_deg") and not ex.has("interaction"):
			var d := n as Node3D
			_doors.append({
				"node": d,
				"closed": d.rotation.y,
				"angle": deg_to_rad(float(ex["open_angle_deg"])),
				"dist": float(ex.get("open_dist_m", default_open_dist)),
				"speed": deg_to_rad(float(ex.get("open_speed_dps", default_speed_dps))),
				"t": 0.0,
			})
	for c in n.get_children():
		_collect(c)

func _physics_process(delta: float) -> void:
	if _doors.is_empty():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(player_group) as Node3D
		if _player == null:
			return
	var p := _player.global_position
	for d in _doors:
		var node: Node3D = d["node"]
		if not is_instance_valid(node):
			continue
		var want := 1.0 if node.global_position.distance_to(p) < float(d["dist"]) else 0.0
		var angle := float(d["angle"])
		var rate := float(d["speed"]) / maxf(absf(angle), 0.01)       # fraction of the swing per second
		d["t"] = move_toward(float(d["t"]), want, rate * delta)
		node.rotation.y = float(d["closed"]) + angle * smoothstep(0.0, 1.0, float(d["t"]))
