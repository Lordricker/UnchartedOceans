class_name ShipRigging
extends Node
## Climbing the rigging to the lookout barrels (the crow's nests on the main mast and on the foremast). Created by
## ship_motion.gd (rigging_enabled).
##
## The brig carries its own climbing zones and waypoints as markers (so nothing has to be placed by hand in the scene).
## Every marker has an extra `mast` ("main" or "fore"):
##   Ladder_Shroud_A / _B   the ratlines on either side: a box along the net (extras ladder_size = across, up the net, depth)
##   Ladder_Mast            the rungs up the mast from the top to the barrel's hatch
##   Climb_MastBase, Climb_ShroudTop_A / _B, Climb_NestExit, Climb_Barrel   where you are put when you pass between them
## Each Ladder_* marker becomes a ShipLadder (ship_ladder.gd) under the marker: climb it like the hull ladders
## (W up, S down, A/D sideways, Space jump off), only it draws you in to the net or the rungs as you go.
##
## The way up: climb a shroud to its top and you are drawn over onto the mast ladder; climb that to near the top
## and you are drawn up through the hatch into the barrel. In the barrel you stand and look about (the mouse), hands
## down, and cannot walk. Press any movement key (W A S D or Space) and you are put back on the mast ladder to
## climb down; at the bottom of it you are put back on the net you came up by.

@export var transfer_seconds := 0.7
## How close to the top of a ladder box you must climb before you are drawn on to the next stage (m).
@export var top_margin := 0.25
## ... and how close to the bottom of the mast ladder before you are put back on the net.
@export var base_margin := 0.2
## Seconds after any move before another can start, so you aren't bounced straight back.
@export var cooldown := 0.9
## Where you stand in the barrel is the Climb_Barrel marker moved this far toward the bow (m), so you are in the barrel and not at its edge.
@export var nest_forward_m := 0.3
## The shroud and mast climbing boxes are made from the brig's markers, which were sized too deep: the box stuck out
## well past the ropes. Their depth (in/out of the ship) is held to this many metres, centred on the marker, and the
## extra reach to grab one from outside it to this many.
@export var max_ladder_depth := 0.45
@export var max_grab_slack := 0.3
## Move the boxes this far toward the ship (m), if their middle sits out past the ropes (0 = where the marker is).
@export var ladder_inset := 0.0

var _ship: Node3D
var _player: Node
var _masts := {}                  # "main" / "fore" -> {"ladders": {id: ShipLadder}, "points": {id: Node3D}, "net": "shroud_a"}
var _owner := {}                  # ShipLadder -> mast name
var _busy := false
var _hull_ladders := 0
var _cool := 0.0
var _in_nest := false
var _armed := false               # in the barrel: true once all movement keys have been let go
var _nest_local := Vector3.ZERO
var _prev_basis := Basis.IDENTITY

func _ready() -> void:
	_ship = get_parent() as Node3D
	call_deferred("_setup")

func _mast(name: String) -> Dictionary:
	if not _masts.has(name):
		_masts[name] = {"ladders": {}, "points": {}, "net": "shroud_a"}
	return _masts[name]

func _setup() -> void:
	var ladder_script := load("res://scripts/ship_ladder.gd")
	for n in get_tree().get_nodes_in_group("role_ladder"):
		if not (n is Node3D) or not _ship.is_ancestor_of(n):
			continue
		var ex = n.get_meta("extras") if n.has_meta("extras") else {}
		if not (ex is Dictionary) or not ex.has("ladder_size"):
			continue
		var sz: Array = ex["ladder_size"]
		var lad: Area3D = ladder_script.new()
		lad.name = "Rungs"
		lad.set("snap_depth", true)
		lad.set("center_on_grab", false)       # the nets are wide: you can still shift along them
		lad.set("grab_slack", minf(float(ex.get("grab_slack", 0.7)), max_grab_slack))
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(sz[0]), float(sz[1]), minf(float(sz[2]), max_ladder_depth))
		cs.shape = box
		cs.position = Vector3(0.0, 0.0, -ladder_inset)
		lad.add_child(cs)
		n.add_child(lad)
		var mast := String(ex.get("mast", "main"))
		_mast(mast)["ladders"][String(ex.get("ladder_id", n.name))] = lad
		_owner[lad] = mast
	# Zones placed in the ship's scene (ship_ladder.gd with a rigging_id): the nets / mast ladder, no markers needed
	for n in get_tree().get_nodes_in_group("ship_ladders"):
		var sl := n as ShipLadder
		if sl == null or String(sl.rigging_id) == "" or not _ship.is_ancestor_of(sl):
			continue
		_mast(String(sl.rigging_mast))["ladders"][String(sl.rigging_id)] = sl
		_owner[sl] = String(sl.rigging_mast)
	# Boarding ladders on the hull, for climbing back aboard from the water: one-rung-wide boxes, +Y up, +Z away from the ship
	# (markers of role hull_ladder, extras ladder_size = along the ship, up, in/out). They need no mast, nets or points.
	for n in get_tree().get_nodes_in_group("role_hull_ladder"):
		if not (n is Node3D) or not _ship.is_ancestor_of(n):
			continue
		var hx = n.get_meta("extras") if n.has_meta("extras") else {}
		if not (hx is Dictionary) or not hx.has("ladder_size"):
			continue
		var hs: Array = hx["ladder_size"]
		var hl: Area3D = ladder_script.new()
		hl.name = "Rungs"
		var hcs := CollisionShape3D.new()
		var hbox := BoxShape3D.new()
		hbox.size = Vector3(float(hs[0]), float(hs[1]), float(hs[2]))
		hcs.shape = hbox
		hl.add_child(hcs)
		n.add_child(hl)
		_hull_ladders += 1
	for n in get_tree().get_nodes_in_group("role_climb_point"):
		if not (n is Node3D) or not _ship.is_ancestor_of(n):
			continue
		var ex2 = n.get_meta("extras") if n.has_meta("extras") else {}
		if ex2 is Dictionary and ex2.has("point_id"):
			_mast(String(ex2.get("mast", "main")))["points"][String(ex2["point_id"])] = n
	for m in _masts.keys():
		var d: Dictionary = _masts[m]
		print("ShipRigging: %s mast: ladders %s, points %s" % [m, d["ladders"].keys(), d["points"].keys()])
	if _hull_ladders > 0:
		print("ShipRigging: %d hull boarding ladders" % _hull_ladders)
	if _masts.is_empty():
		push_warning("ShipRigging: the brig has no climbing markers (Ladder_*, Climb_*); rigging left alone")
		set_physics_process(false)

func _pl() -> Node:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	return _player

func _body_centre(pl: Node3D) -> Vector3:
	return pl.global_position + Vector3.UP * float(pl.get("player_height")) * 0.5

func _physics_process(delta: float) -> void:
	var pl := _pl() as Node3D
	if pl == null:
		return
	_cool = maxf(_cool - delta, 0.0)
	if _in_nest:
		_stand_in_nest(pl)
		return
	if _busy or _cool > 0.0:
		return
	var lad = pl.get("ladder")
	if lad == null or not _owner.has(lad):
		return
	var mast: String = _owner[lad]
	var m: Dictionary = _masts[mast]
	var lp: Vector3 = lad.call("local_point", _body_centre(pl))
	var half: Vector3 = lad.call("half_size")
	if lad == m["ladders"].get("shroud_a") or lad == m["ladders"].get("shroud_b"):
		if lp.y >= half.y - top_margin and m["points"].has("mast_base"):
			m["net"] = "shroud_a" if lad == m["ladders"].get("shroud_a") else "shroud_b"
			_move_to(mast, "mast_base", Callable())
		elif lp.y >= half.y - top_margin and m["points"].has("barrel") and not m["ladders"].has("mast"):
			m["net"] = "shroud_a" if lad == m["ladders"].get("shroud_a") else "shroud_b"
			_move_to(mast, "barrel", _arrived_in_nest.bind(mast))
	elif lad == m["ladders"].get("mast"):
		if lp.y >= half.y - top_margin and m["points"].has("barrel"):
			_move_to(mast, "barrel", _arrived_in_nest.bind(mast))
		elif lp.y <= -half.y + base_margin + 0.5:
			_move_to(mast, "shroud_top_" + String(m["net"]).right(1), Callable())

## Put the player at a marker over a moment, with walking switched off while it happens (the ship carries the
## ship-local point along, so a heaving ship doesn't shake you off).
func _move_to(mast: String, point_id: String, then: Callable) -> void:
	var pl := _pl() as Node3D
	var points: Dictionary = _masts[mast]["points"]
	if pl == null or not points.has(point_id):
		return
	_busy = true
	print("ShipRigging: moving you to %s (%s mast)" % [point_id, mast])
	var marker: Node3D = points[point_id]
	var end_local := _ship.to_local(marker.global_position)
	if point_id == "barrel":
		end_local += Vector3(0.0, 0.0, -nest_forward_m)      # the bow is -Z: stand a little further into the barrel
	var start_local := _ship.to_local(pl.global_position)
	pl.set_physics_process(false)
	pl.set("velocity", Vector3.ZERO)
	var tw := create_tween()
	tw.tween_method(func(f: float): pl.global_position = _ship.to_global(start_local.lerp(end_local, f)), 0.0, 1.0, transfer_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if is_instance_valid(pl):
		pl.set("velocity", Vector3.ZERO)
		pl.set_physics_process(true)
	_cool = cooldown
	_busy = false
	if then.is_valid():
		then.call()

func _arrived_in_nest(mast: String) -> void:
	var pl := _pl() as Node3D
	if pl == null:
		return
	pl.set_physics_process(false)             # stand still: the nest is not walked about in
	pl.set("velocity", Vector3.ZERO)
	pl.set("ladder", null)
	_nest_local = _ship.to_local(pl.global_position)
	_prev_basis = _ship.global_transform.basis
	_in_nest = true
	_armed = false
	_hands_down(pl)
	print("ShipRigging: in the %s barrel at ship-local %s" % [mast, _nest_local])
	_exit_mast = mast

var _exit_mast := "main"

## The gloves hang at rest: the player script, which normally feeds them, is not running up here.
func _hands_down(pl: Node) -> void:
	var h = pl.get("hands")
	if h == null:
		return
	h.set("on_floor", true)
	h.set("ground_speed", 0.0)
	h.set("sprinting", false)
	h.set("vertical_speed", 0.0)
	h.set("climbing", false)
	h.set("climb_rate", 0.0)
	h.set("swimming", false)
	h.set("swim_effort", 0.0)
	h.set("hold_active", false)
	h.set("hold_active_l", false)

## In the barrel: ride with the ship, hands down, and let go of the stand when a movement key is pressed.
func _stand_in_nest(pl: Node3D) -> void:
	pl.global_position = _ship.to_global(_nest_local)
	var now := _ship.global_transform.basis
	var delta_rot := now * _prev_basis.inverse()
	pl.global_transform.basis = (delta_rot * pl.global_transform.basis).orthonormalized()
	_prev_basis = now
	_hands_down(pl)
	var moving := false
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE]:
		if Input.is_physical_key_pressed(k):
			moving = true
	if not moving:
		_armed = true                            # the key that brought you here has been let go
	elif _armed and not _busy:
		_in_nest = false
		var exit_pts: Dictionary = _masts[_exit_mast]["points"]
		var exit_id := "nest_exit" if exit_pts.has("nest_exit") else "shroud_top_" + String(_masts[_exit_mast]["net"]).right(1)
		_move_to(_exit_mast, exit_id, Callable())
