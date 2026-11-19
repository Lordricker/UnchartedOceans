class_name ShipHarbor
extends Node3D
## Where the ship meets the land (made by ship_motion.gd at startup, like the wheel and sails).
##
##  - Running aground: the keel is sampled against the island's sea floor. Touching it kills the ship's
##    speed (friction, plus the part of the motion that points into the shallows) and eases her back out
##    to deeper water. Waves count, so a trough can ground you where a crest would not.
##  - The pier: the hull is a rectangle that cannot pass through the pier. Hitting it slows the ship and
##    reports the impact speed.
##  - Mooring (E): a glowing rectangle (DockBerth, dock_berth.gd) shows on the water as you near a berth,
##    sized for the ship's class (ShipClasses). With the whole hull inside it, slow enough and lined up
##    (the rectangle turns green) E puts the lines ashore: the ship eases into the berth over snap_time
##    seconds, is held against the fenders, and the gangway comes out to the pier.
##    E again casts off (not while someone is standing on the gangway).
##  - B (testing): jump the ship to the cove's mouth, heading for the pier.
## Shows the water under the keel and the berth state at the top of the screen when the island is near.

@export var key_moor := KEY_E
@export var key_teleport := KEY_B
## Seconds the ship takes to ease into the berth once the lines go on (the speed and heading limits live in
## ShipClasses, the size of the light in ShipClasses and the berth).
@export var snap_time := 2.5
## Ship-local z of the gangway: midway between the two forward port cannons (Gun_0 / Gun_1, Blender y -2.2 and -0.4;
## ship-local z = Blender y, bow is -z).
@export var gangway_z := -1.3
## Width of the ramp (m); the gap between the two cannon carriages is a little over 1 m.
@export var gangway_width := 0.9
## The "E  Dock" / "E  Cast off" hotkey line at the bottom of the screen.
var _hint: Label

## (ship-local x, z, keel depth below the waterline). The brig's keel is about 2.3 m down amidships.
const FOOT: Array[Vector3] = [
	Vector3(0, -10.0, 0.9), Vector3(0, -7.0, 1.7), Vector3(0, -3.5, 2.2), Vector3(0, 0, 2.3),
	Vector3(0, 3.5, 2.3), Vector3(0, 7.0, 2.0), Vector3(0, 9.5, 1.4),
	Vector3(-2.2, -5.0, 1.2), Vector3(2.2, -5.0, 1.2), Vector3(-2.6, 0.0, 1.5), Vector3(2.6, 0.0, 1.5),
	Vector3(-2.2, 5.0, 1.2), Vector3(2.2, 5.0, 1.2),
	Vector3(-3.3, -2.0, 0.4), Vector3(3.3, -2.0, 0.4), Vector3(-3.3, 3.0, 0.4), Vector3(3.3, 3.0, 0.4),
]
## Mooring cleats on the port rail (ship-local) and the bollard each line goes to (index into
## Island.bollards_world(): 0 = northernmost).
const LINES := [
	[Vector3(-3.05, 2.5, -7.0), 0],    # bow line
	[Vector3(-3.05, 2.5, -3.2), 2],    # forward spring, leads aft
	[Vector3(-3.05, 2.5, 3.4), 1],     # after spring, leads forward
	[Vector3(-3.05, 2.5, 6.8), 3],     # stern line
]

## The brig's gangway (ship-local x across to port, y up): quay, over the rail, down to the deck. Other classes bring
## their own in ShipClasses.DATA ("gangway", "gangway_z", "gangway_width", "gangway_min_y").
## Click a mooring bollard (one a line is made fast to) while moored to cast off.
const Outline := preload("res://scripts/interact_outline.gd")
const BOLLARD_REACH := 7.0       ## how far you can reach a bollard (m)
const BOLLARD_RADIUS := 0.55     ## radius of the click cylinder round a bollard (m)

const GANGWAY := [Vector2(-4.8, 1.9), Vector2(-3.35, 2.82), Vector2(-2.35, 2.82), Vector2(-1.2, 1.86)]

var ship: Node3D
var island: Island
var berth: DockBerth            ## the nearest berth (kept while moored)
var moored := false
var settle := 0.0               ## seconds the ship has been at rest against the pier
var aground := false
var clearance := 99.0           ## water under the keel at the shallowest sampled point (m)
var message := ""

var _msg_time := 0.0
var _label: Label
var _rope_mesh: ImmediateMesh
var _rope_node: MeshInstance3D
var _gang: Node3D
var _gang_body: AnimatableBody3D
var _gang_shapes: Array[CollisionShape3D] = []
var _gang_out := false
var _gang_z := -1.3             ## this ship class's gangway lane, width and the height above which someone counts as on it
var _gang_w := 0.9
var _gang_min_y := 1.6
var _foot_cache: Array[Vector3] = []
var _lines_cache: Array = []
var _hit_cool := 0.0
var _last_slope := 0.1
var _snap_t := 1.0
var _snap_from := Vector3.ZERO
var _snap_h0 := 0.0
var _snap_dh := 0.0

func _ready() -> void:
	add_to_group("ship_harbor")
	ship = get_parent() as Node3D
	_make_label()
	_make_ropes()
	_make_gangway()

func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed and _bollard_aimed():
		get_viewport().set_input_as_handled()
		if settle > 0.8:
			cast_off()
		else:
			_say("Wait for the lines to come taut")

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == key_moor:
			toggle_moor()
		elif e.physical_keycode == key_teleport:
			teleport_to_approach()

# ------------------------------------------------------------------ helpers

func _model() -> SailModel:
	var s = ship.get("sails")
	return s.model if s != null else null

func _basis_vectors() -> Array:
	var yaw := deg_to_rad(float(ship.get("heading_deg")))
	return [Vector2(-sin(yaw), -cos(yaw)), Vector2(cos(yaw), -sin(yaw))]   # fwd, right (world xz)

func _velocity() -> Vector2:
	var m := _model()
	if m == null:
		return Vector2.ZERO
	var b := _basis_vectors()
	return b[0] * m.v_f + b[1] * m.v_s

func _set_velocity(v: Vector2) -> void:
	var m := _model()
	if m == null:
		return
	var b := _basis_vectors()
	m.v_f = v.dot(b[0])
	m.v_s = v.dot(b[1])

func _say(text: String, seconds := 3.0) -> void:
	message = text
	_msg_time = seconds

## Keel footprint and mooring cleats for this ship's class (the brig's constants above unless the class has its own).
func _foot() -> Array[Vector3]:
	if _foot_cache.is_empty():
		var f = ShipClasses.data(_ship_class()).get("foot")
		if f == null:
			_foot_cache = FOOT
		else:
			for v in f:
				_foot_cache.append(v)
	return _foot_cache

func _lines() -> Array:
	if _lines_cache.is_empty():
		var l = ShipClasses.data(_ship_class()).get("lines")
		_lines_cache = LINES if l == null else l
	return _lines_cache

func _ship_class() -> int:
	var c = ship.get("ship_class")
	return int(c) if c != null else ShipClasses.Size.MEDIUM

## The nearest berth. Once moored the ship keeps hers.
func _find_berth() -> void:
	if moored and berth != null and is_instance_valid(berth):
		return
	var best: DockBerth = null
	var best_d := 1.0e9
	for n in get_tree().get_nodes_in_group("dock_berths"):
		var b := n as DockBerth
		if b == null:
			continue
		var d := b.global_position.distance_to(ship.global_position)
		if d < best_d:
			best_d = d
			best = b
	berth = best

func _find_island() -> void:
	if island == null or not is_instance_valid(island):
		island = get_tree().get_first_node_in_group("islands") as Island

# ------------------------------------------------------------------ per tick

func _physics_process(delta: float) -> void:
	_find_island()
	if ship == null:
		return
	_hit_cool = maxf(_hit_cool - delta, 0.0)
	_msg_time = maxf(_msg_time - delta, 0.0)
	_find_berth()
	if moored and (berth == null or not is_instance_valid(berth)):
		moored = false          # her port was left behind
	if moored:
		_hold(delta)
		clearance = _keel_clearance()
	elif island != null:
		_ground(delta)
		_pier_collide(delta)
	else:
		_port_collide(delta)
	for n in get_tree().get_nodes_in_group("dock_berths"):
		var b := n as DockBerth
		if b == null:
			continue
		if b == berth:
			b.set_light(ship.global_position, _ship_class(), can_moor(), moored)
		else:
			b.hide_light()
	_update_gangway()
	_update_ropes()
	_update_label()
	_update_bollard_name()

## Water under the keel at the shallowest sampled point.
func _keel_clearance() -> float:
	if island == null:
		return 99.0          # no test island: the world's own shoals are WorldStreamer's business
	var b := _basis_vectors()
	var base := Vector2(ship.global_position.x, ship.global_position.z)
	var y := ship.global_position.y
	var clear := 99.0
	for f: Vector3 in _foot():
		var w: Vector2 = base + (b[1] as Vector2) * f.x - (b[0] as Vector2) * f.y
		clear = minf(clear, (y - f.z) - island.height_at(w.x, w.y))
	return clear

## Keel against the sea floor.
func _ground(delta: float) -> void:
	var b := _basis_vectors()
	var fwd: Vector2 = b[0]
	var right: Vector2 = b[1]
	var base := Vector2(ship.global_position.x, ship.global_position.z)
	var y := ship.global_position.y
	var worst := 0.0
	var push := Vector2.ZERO
	var clear := 99.0
	for f: Vector3 in _foot():
		var w := base + right * f.x - fwd * f.y
		var g := island.height_at(w.x, w.y)
		var keel_y := y - f.z
		clear = minf(clear, keel_y - g)
		var pen := g - keel_y
		if pen > 0.0:
			var n := island.normal_at(w.x, w.y)
			var nh := Vector2(n.x, n.z)
			_last_slope = maxf(nh.length() / maxf(n.y, 0.1), 0.05)
			if nh.length() < 0.01:
				nh = (base - Vector2(island.global_position.x, island.global_position.z))
			push += nh.normalized() * pen
			worst = maxf(worst, pen)
	clearance = clear
	if worst <= 0.0:
		if aground:
			aground = false
		return
	var dir := push.normalized() if push.length() > 0.001 else -fwd
	var v := _velocity()
	var vn := v.dot(dir)
	if vn < 0.0:
		if -vn > 0.8 and not aground:
			_say("Aground! (%.1f knots)" % (-vn / 0.5144))
		v -= dir * vn * 1.1
	aground = true
	v *= exp(-delta * (0.7 + 2.5 * clampf(worst, 0.0, 1.0)))
	_set_velocity(v)
	var m := _model()
	if m == null and bool(ship.get("underway")):
		ship.set("underway", false)
	# ease back out toward deeper water: the slope converts depth to distance
	var move := dir * minf(worst / _last_slope, 2.5) * (1.0 - exp(-delta * 4.0))
	ship.global_position += Vector3(move.x, 0.0, move.y)

## The hull (a rectangle) against the pier (a rectangle); separating-axis test.
func _pier_collide(delta: float) -> void:
	if not island.harbor:
		return
	var rect := island.pier_rect_world().grow(island.fender_gap)
	var pc := rect.get_center()
	var ph := rect.size * 0.5
	var b := _basis_vectors()
	var a1: Vector2 = b[0]
	var a2: Vector2 = b[1]
	var c := Vector2(ship.global_position.x, ship.global_position.z)
	var dims := ShipClasses.data(_ship_class())
	var hl: float = float(dims.length) * 0.5
	var hb: float = float(dims.beam) * 0.5
	var best := 1.0e9
	var best_n := Vector2.ZERO
	for u in [Vector2(1, 0), Vector2(0, 1), a1, a2]:
		var rs: float = hl * absf(u.dot(a1)) + hb * absf(u.dot(a2))
		var rp: float = ph.x * absf(u.x) + ph.y * absf(u.y)
		var d := (c - pc).dot(u)
		var overlap: float = rs + rp - absf(d)
		if overlap <= 0.0:
			return
		if overlap < best:
			best = overlap
			best_n = u * (1.0 if d >= 0.0 else -1.0)
	ship.global_position += Vector3(best_n.x, 0.0, best_n.y) * best
	var v := _velocity()
	var vn := v.dot(best_n)
	if vn < 0.0:
		if -vn > 0.5 and _hit_cool <= 0.0:
			_say("Bumped the pier (%.1f m/s)" % -vn)
			_hit_cool = 1.0
		v -= best_n * vn * 1.2
	v -= (v - best_n * v.dot(best_n)) * (1.0 - exp(-0.8 * delta))
	_set_velocity(v)

# ------------------------------------------------------------------ port stone

## Inside this distance (m) of a berth the hull is tested against the port's stone (the quay, moles, breakwaters and
## lighthouse all lie within it). Farther out nothing is tested.
const PORT_COLLIDE_RANGE_M := 450.0
const HULL_BOX_HEIGHT := 3.0           ## the hull box reaches 1.5 m above and below her waterline

var _hull_box: BoxShape3D
var _hull_box_class := -1
var _skip: Array[RID] = []             ## her own bodies (deck, hull skin, ladders, gangway) and the player: never hit
var _skip_t := 0.0
var _push_sign := 1.0                  ## which way round the engine reports a contact pair (found out once, see below)

## The hull (a box the size of her class) against the port's colliders (physics layer 4: port_import.gd puts the quay,
## moles, breakwaters and lighthouse there). Whatever it overlaps pushes her back out sideways, and the speed that
## points into it is lost. Used when there is no test island (that has its own pier code, _pier_collide).
func _port_collide(delta: float) -> void:
	if berth == null or not is_instance_valid(berth):
		return
	if ship.global_position.distance_to(berth.global_position) > PORT_COLLIDE_RANGE_M:
		return
	var cls := _ship_class()
	if _hull_box == null or _hull_box_class != cls:
		var dims := ShipClasses.data(cls)
		_hull_box = BoxShape3D.new()
		_hull_box.size = Vector3(float(dims.beam), HULL_BOX_HEIGHT, float(dims.length))
		_hull_box_class = cls
	_skip_t -= delta
	if _skip_t <= 0.0:
		_skip_t = 2.0
		_refresh_skip()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _hull_box
	q.collision_mask = Island.LAYER_BIT
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = _skip
	var basis := Basis(Vector3.UP, deg_to_rad(float(ship.get("heading_deg"))))
	var space := ship.get_world_3d().direct_space_state
	var pos := ship.global_position
	var moved := Vector2.ZERO
	for i in 4:
		q.transform = Transform3D(basis, pos + Vector3(moved.x, 0.0, moved.y))
		var push := _deepest_push(space, q)
		if push.length() < 0.004:
			break
		var step := push * _push_sign
		if step.length() > 1.5:
			step = step.normalized() * 1.5
		# if that step makes the overlap worse, the engine lists the pair the other way round: flip once and go on
		q.transform = Transform3D(basis, pos + Vector3(moved.x + step.x, 0.0, moved.y + step.y))
		if _deepest_push(space, q).length() > push.length() + 0.003:
			_push_sign = -_push_sign
			step = -step
		moved += step
	if moved.length() < 0.001:
		return
	ship.global_position += Vector3(moved.x, 0.0, moved.y)
	var n := moved.normalized()
	var v := _velocity()
	var vn := v.dot(n)
	if vn < 0.0:
		if -vn > 0.5 and _hit_cool <= 0.0:
			_say("Bumped the quay (%.1f m/s)" % -vn)
			_hit_cool = 1.0
		v -= n * vn * 1.2
	v -= (v - n * v.dot(n)) * (1.0 - exp(-0.8 * delta))
	_set_velocity(v)

## The deepest overlap of the query shape with the world, as a sideways push (world xz) that would clear it.
## collide_shape lists pairs of points: the first on the query shape, the second on what it overlaps; the way out is
## from the first to the second.
func _deepest_push(space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D) -> Vector2:
	var pts := space.collide_shape(q, 24)
	var best := Vector2.ZERO
	var k := 0
	while k + 1 < pts.size():
		var d: Vector3 = pts[k + 1] - pts[k]
		var h := Vector2(d.x, d.z)
		if h.length_squared() > best.length_squared():
			best = h
		k += 2
	return best

func _refresh_skip() -> void:
	_skip.clear()
	for c in ship.find_children("*", "CollisionObject3D", true, false):
		_skip.append((c as CollisionObject3D).get_rid())
	for p in get_tree().get_nodes_in_group("player"):
		if p is CollisionObject3D:
			_skip.append((p as CollisionObject3D).get_rid())

# ------------------------------------------------------------------ mooring

## How the ship sits against the berth (see DockBerth.evaluate): lat / along offsets (m), heading error (deg),
## speed (m/s), and whether she is inside the light, slow enough and lined up (ok).
func berth_state() -> Dictionary:
	if berth == null:
		return {"lat": 0.0, "along": 0.0, "heading": 0.0, "speed": _velocity().length(),
			"out_lat": 0.0, "out_fwd": 0.0, "inside": false, "speed_ok": false, "heading_ok": false,
			"max_speed": 0.0, "max_heading": 0.0, "ok": false}
	return berth.evaluate(ship.global_position, float(ship.get("heading_deg")), _velocity().length(), _ship_class())

func can_moor() -> bool:
	if berth == null:
		return false
	if ShipClasses.berth_class(_ship_class()) > berth.max_ship_class:
		return false
	return bool(berth_state().ok)

func toggle_moor() -> void:
	_find_island()
	_find_berth()
	if berth == null:
		return
	if moored:
		if _wheel_held():      # casting off is done from the wheel, like the hint
			cast_off()
	elif can_moor():
		moored = true
		settle = 0.0
		ship.set("underway", false)
		_snap_t = 0.0
		_snap_from = ship.global_position
		_snap_h0 = float(ship.get("heading_deg"))
		_snap_dh = fposmod(berth.berth_heading - _snap_h0 + 180.0, 360.0) - 180.0
		_say("Lines ashore")
	elif ShipClasses.berth_class(_ship_class()) > berth.max_ship_class:
		_say("This berth is too small for her")
	else:
		var s := berth_state()
		if not s.speed_ok:
			_say("Too fast to moor (%.1f m/s, under %.1f)" % [s.speed, s.max_speed])
		elif not s.inside:
			_say("Not inside the berth light")
		else:
			_say("Line her up with the berth")

func cast_off() -> void:
	if not moored:
		return
	if _player_on_gangway():
		_say("Get off the gangway first")
		return
	moored = false
	settle = 0.0
	_snap_t = 1.0
	var m := _model()
	if m:
		m.v_s = 0.6        # drift off the pier (starboard is away from it)
		m.v_f = 0.0
	_say("Cast off")

## Ease the ship into the berth (position and heading, smooth in and out), then hold her there with no way on.
func _hold(delta: float) -> void:
	ship.set("underway", false)
	var slot := berth.slot_position(_ship_class())
	_snap_t = minf(_snap_t + delta / maxf(snap_time, 0.1), 1.0)
	var t := _snap_t
	var e := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)        # smootherstep
	var y := ship.global_position.y
	ship.global_position = Vector3(lerpf(_snap_from.x, slot.x, e), y, lerpf(_snap_from.z, slot.z, e))
	ship.set("heading_deg", fposmod(_snap_h0 + _snap_dh * e, 360.0))
	var m := _model()
	if m:
		m.v_f = 0.0
		m.v_s = 0.0
		m.yaw_rate = 0.0
	if _snap_t >= 1.0:
		settle += delta
	else:
		settle = 0.0

## Start the run already lying in a berth: lines ashore, gangway out, no way on. The caller (world_streamer.gd,
## start_moored) has already put the ship on the berth's slot, bow along its heading.
func start_moored_at(b: DockBerth) -> void:
	berth = b
	moored = true
	settle = 1.0
	_snap_t = 1.0
	_snap_from = ship.global_position
	_snap_h0 = float(ship.get("heading_deg"))
	_snap_dh = 0.0
	ship.set("underway", false)
	var m := _model()
	if m:
		m.v_f = 0.0
		m.v_s = 0.0
		m.yaw_rate = 0.0

## Forget any mooring: the ship has just been put somewhere else, free of her lines.
func release_mooring() -> void:
	moored = false
	settle = 0.0
	_snap_t = 1.0

# ------------------------------------------------------------------ test teleport

## Put the ship (and the player, if aboard) at the mouth of the cove heading for the pier.
func teleport_to_approach() -> void:
	_find_island()
	_find_berth()
	if berth == null and (island == null or not island.harbor):
		return
	if berth != null and ship.global_position.distance_to(berth.global_position) > 400.0:
		return          # out at sea: a stray key must not throw the ship across the chart
	var from := ship.global_position
	var to: Vector3
	var head := 0.0
	if berth != null:
		var slot := berth.slot_position(_ship_class())
		var f2 := berth.forward2()
		var r2 := berth.right2()
		to = Vector3(slot.x - f2.x * 75.0 + r2.x * 1.5, from.y, slot.z - f2.y * 75.0 + r2.y * 1.5)
		head = berth.berth_heading
	else:
		var bw := island.berth_world()
		to = Vector3(bw.x + 1.5, from.y, bw.z + 75.0)
	moored = false
	ship.global_position = to
	ship.set("heading_deg", head)
	ship.set("underway", false)
	var m := _model()
	if m:
		m.v_f = 0.0
		m.v_s = 0.0
		m.yaw_rate = 0.0
	ship.set("_xf_prev", ship.global_transform)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl and pl.global_position.distance_to(from) < 40.0:
		pl.global_position += to - from
		if "velocity" in pl:
			pl.velocity = Vector3.ZERO
	_say("Approach: sail %s into the cove, pier on the port side" % ShipClasses.compass(head))

# ------------------------------------------------------------------ gangway

func _make_gangway() -> void:
	var cd := ShipClasses.data(_ship_class())
	var pts: Array = cd.get("gangway", GANGWAY)
	_gang_z = float(cd.get("gangway_z", gangway_z))
	_gang_w = float(cd.get("gangway_width", gangway_width))
	_gang_min_y = float(cd.get("gangway_min_y", 1.6))
	_gang = Node3D.new()
	_gang.name = "Gangway"
	_gang.visible = false
	add_child(_gang)
	_gang_body = AnimatableBody3D.new()
	_gang_body.name = "GangwayBody"
	_gang_body.sync_to_physics = false
	_gang_body.collision_layer = Island.LAYER_BIT
	_gang_body.collision_mask = 0
	_gang.add_child(_gang_body)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.38, 0.24)
	wood.roughness = 0.9
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var bpt: Vector2 = pts[i + 1]
		var d := bpt - a
		var ang := atan2(d.y, d.x)
		var mid := (a + bpt) * 0.5
		var nrm := Vector2(-sin(ang), cos(ang))
		var basis := Basis(Vector3.BACK, ang)
		var width := _gang_w
		var xf := Transform3D(basis, Vector3(mid.x - nrm.x * 0.05, mid.y - nrm.y * 0.05, _gang_z))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(d.length(), 0.1, width)
		mi.mesh = bm
		mi.material_override = wood
		mi.transform = xf
		_gang.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs
		cs.transform = xf
		cs.disabled = true
		_gang_body.add_child(cs)
		_gang_shapes.append(cs)
		for sz in [-1.0, 1.0]:
			var side := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(d.length(), 0.2, 0.05)
			side.mesh = sm
			side.material_override = wood
			side.transform = Transform3D(basis, Vector3(mid.x + nrm.x * 0.1, mid.y + nrm.y * 0.1, _gang_z + sz * (width * 0.5 - 0.02)))
			_gang.add_child(side)
		# cleats across the ramp so there is something to grip
		var steps := int(d.length() / 0.4)
		for s in steps:
			var t := (float(s) + 0.5) / steps
			var cp := a.lerp(bpt, t)
			var cleat := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(0.04, 0.03, width - 0.1)
			cleat.mesh = cm
			cleat.material_override = wood
			cleat.transform = Transform3D(basis, Vector3(cp.x + nrm.x * 0.03, cp.y + nrm.y * 0.03, _gang_z))
			_gang.add_child(cleat)

func _update_gangway() -> void:
	var want := moored and settle > 0.8
	if want == _gang_out:
		return
	_gang_out = want
	_gang.visible = want
	for cs in _gang_shapes:
		cs.disabled = not want

func _player_on_gangway() -> bool:
	if not _gang_out:
		return false
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return false
	var l := ship.global_transform.affine_inverse() * pl.global_position
	return l.x < -1.0 and absf(l.z - _gang_z) < _gang_w * 0.5 + 0.5 and l.y > _gang_min_y

# ------------------------------------------------------------------ ropes

func _make_ropes() -> void:
	_rope_mesh = ImmediateMesh.new()
	_rope_node = MeshInstance3D.new()
	_rope_node.name = "MooringLines"
	_rope_node.mesh = _rope_mesh
	_rope_node.top_level = true
	_rope_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope_node.extra_cull_margin = 40.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.58, 0.38)
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rope_node.material_override = mat
	add_child(_rope_node)

func _update_ropes() -> void:
	_rope_mesh.clear_surfaces()
	_rope_node.visible = moored
	if not moored or berth == null:
		return
	var bol := berth.bollards_world()
	_rope_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for ln in _lines():
		var a: Vector3 = ship.global_transform * (ln[0] as Vector3)
		var b: Vector3 = bol[ln[1]]
		var slack := clampf(1.0 - settle / 0.8, 0.0, 1.0)
		_tube(a, b, 0.05 + 0.9 * slack)
	_rope_mesh.surface_end()

func _tube(a: Vector3, b: Vector3, sag: float) -> void:
	const N := 10
	const R := 0.035
	var pts: Array[Vector3] = []
	for i in N + 1:
		var t := float(i) / N
		pts.append(a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
	var prev_ring: Array[Vector3] = []
	var prev_n: Array[Vector3] = []
	for i in N + 1:
		var dir := (pts[mini(i + 1, N)] - pts[maxi(i - 1, 0)]).normalized()
		var u := dir.cross(Vector3.UP)
		if u.length() < 0.01:
			u = dir.cross(Vector3.RIGHT)
		u = u.normalized()
		var v := dir.cross(u).normalized()
		var ring: Array[Vector3] = []
		var rn: Array[Vector3] = []
		for s in 4:
			var ang := TAU * float(s) / 4.0 + PI * 0.25
			var nn := u * cos(ang) + v * sin(ang)
			ring.append(pts[i] + nn * R)
			rn.append(nn)
		if i > 0:
			for s in 4:
				var s2 := (s + 1) % 4
				_rope_mesh.surface_set_normal(prev_n[s]); _rope_mesh.surface_add_vertex(prev_ring[s])
				_rope_mesh.surface_set_normal(rn[s]); _rope_mesh.surface_add_vertex(ring[s])
				_rope_mesh.surface_set_normal(prev_n[s2]); _rope_mesh.surface_add_vertex(prev_ring[s2])
				_rope_mesh.surface_set_normal(prev_n[s2]); _rope_mesh.surface_add_vertex(prev_ring[s2])
				_rope_mesh.surface_set_normal(rn[s]); _rope_mesh.surface_add_vertex(ring[s])
				_rope_mesh.surface_set_normal(rn[s2]); _rope_mesh.surface_add_vertex(ring[s2])
		prev_ring = ring
		prev_n = rn

# ------------------------------------------------------------------ prompt

func _make_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.offset_top = 36.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1, 0.97, 0.9))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	# the hotkey line, bottom of the screen (above the helm's), same font as the other hotkeys
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_bottom = -90.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override("outline_size", 6)
	var font := load("res://assets/fonts/Ferrum-ExtraCondensed.otf") as Font
	if font != null:
		_hint.add_theme_font_override("font", font)
	_hint.add_theme_font_size_override("font_size", 26)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	layer.add_child(_hint)

## True while a hand is on the wheel (a ship with no wheel never blocks the key).
func _wheel_held() -> bool:
	var w := ship.get_node_or_null("ShipWheel")
	return w == null or w.get("held") == null or bool(w.get("held"))

## "E  Dock" while the berth light is green, "E  Cast off" once moored (and the gangway is clear), the latter only
## while holding the wheel.
func _hint_text() -> String:
	if moored:
		return "E   Cast off" if settle > 0.8 and _wheel_held() else ""
	if berth != null and can_moor():
		return "E   Dock"
	return ""

func status_text() -> String:
	if island == null and berth == null:
		return ""
	var cls := _ship_class()
	var bw := berth.slot_position(cls) if berth != null else island.berth_world()
	var dist := Vector2(ship.global_position.x - bw.x, ship.global_position.z - bw.z).length()
	var lines := PackedStringArray()
	if island != null and (dist < 140.0 or aground):
		lines.append("under keel %.1f m   shore %d m" % [
			clearance, roundi(island.shore_distance(ship.global_position.x, ship.global_position.z))])
	if berth != null:
		if moored:
			lines.append("MOORED - E to cast off" if settle > 0.8 else "Hauling in the lines...")
		elif dist < 90.0:
			if ShipClasses.berth_class(cls) > berth.max_ship_class:
				lines.append("Berth too small for this ship")
			elif can_moor():
				lines.append("E: put the lines ashore")
			else:
				var s := berth_state()
				var hints := PackedStringArray()
				if not s.speed_ok:
					hints.append("slow down (%.1f m/s)" % s.speed)
				if not s.heading_ok:
					hints.append("head %s" % ShipClasses.compass(berth.berth_heading))
				if s.out_lat > 0.0:
					hints.append("%s the pier" % ("closer to" if s.lat > 0.0 else "away from"))
				if s.out_fwd > 0.0:
					hints.append("%d m %s" % [maxi(roundi(absf(s.along)), 1), "forward" if s.along > 0.0 else "aft"])
				lines.append("Berth: " + ", ".join(hints) if hints.size() > 0 else "Berth: ease into the light")
	if _msg_time > 0.0:
		lines.append(message)
	return "\n".join(lines)

func _update_label() -> void:
	# only the short event messages ("Lines ashore", "Aground!") show on their own; the status lines are for H
	if Engine.get_meta("debug_ui", false):
		_label.text = status_text()
	else:
		_label.text = message if _msg_time > 0.0 else ""
	var h := _hint_text()
	_hint.text = h
	_hint.visible = h != ""


# ------------------------------------------------------------------ clicking a bollard to cast off

var _cam: Camera3D
var _player: Node
var _bollard_named := false

func _camera() -> Camera3D:
	if _cam == null or not is_instance_valid(_cam):
		_player = get_tree().get_first_node_in_group("player")
		if _player:
			_cam = _player.get_node_or_null("Head/Camera3D") as Camera3D
	return _cam

## Distance along the view ray to a vertical cylinder round `c` (radius r, from y0 to y1 above/below c), or INF.
func _bollard_hit(c: Vector3, o: Vector3, d: Vector3, r: float, y0: float, y1: float) -> float:
	var lo := o - c
	var best := INF
	var a := d.x * d.x + d.z * d.z
	if a > 0.00000001:
		var b := 2.0 * (lo.x * d.x + lo.z * d.z)
		var cc := lo.x * lo.x + lo.z * lo.z - r * r
		var disc := b * b - 4.0 * a * cc
		if disc >= 0.0:
			var sq := sqrt(disc)
			for k in 2:
				var t := (-b - sq) / (2.0 * a) if k == 0 else (-b + sq) / (2.0 * a)
				if t >= 0.0:
					var y := lo.y + d.y * t
					if y >= y0 and y <= y1:
						best = minf(best, t)
	if absf(d.y) > 0.000001:
		for k in 2:
			var t2 := ((y0 if k == 0 else y1) - lo.y) / d.y
			if t2 >= 0.0:
				var px := lo.x + d.x * t2
				var pz := lo.z + d.z * t2
				if px * px + pz * pz <= r * r:
					best = minf(best, t2)
	return best if best <= BOLLARD_REACH else INF

## True while moored and the crosshair is on a bollard the lines are made fast to.
func _bollard_aimed() -> bool:
	if not moored or berth == null or not is_instance_valid(berth):
		return false
	var cam := _camera()
	if cam == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if _player != null and (bool(_player.get("input_locked")) or bool(_player.get_meta("grab_busy", false))):
		return false
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var seen: Array[Vector3] = []
	for ln in _lines():
		var p: Vector3 = berth.bollards_world()[ln[1]]
		if p in seen:
			continue
		seen.append(p)
		# bollard tops: the post stands below the point, with some margin above it
		if _bollard_hit(p, o, d, BOLLARD_RADIUS, -0.9, 0.35) < INF:
			return true
	return false

func _update_bollard_name() -> void:
	var on := _bollard_aimed()
	if on:
		Outline.show_name(self, "Bollard - cast off")
		_bollard_named = true
	elif _bollard_named:
		Outline.hide_name(self)
		_bollard_named = false
