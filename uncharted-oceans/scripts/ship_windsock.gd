class_name ShipWindsock
extends Node3D
## The wind vane on the poop deck, by the wheel: an old-style swallow-tailed pennant on a wooden
## staff, the kind a helmsman glanced at to see where the wind was. (The class keeps its first name,
## "windsock", so nothing else had to change.) Created by ship_motion.gd (windsock_enabled).
##
## It shows the APPARENT wind, the air as the ship feels it (true wind plus the ship's own motion),
## the same wind the flags show and the sails work in. It streams downwind. In a light breeze it
## hangs limp, as the wind builds it lifts, and from about full_speed m/s it flies level, with a
## ripple running down it that grows with the wind. It swings round to a change of wind rather than
## snapping.
##
## Where it stands: put an Empty (or any Node3D) called "Windsock" in the brig and it stands on that
## spot. Without one it stands beside the wheel (wheel_offset, ship frame, bow is -Z) and finds the
## deck under itself by itself.

@export var enabled := true
@export var mount_node_name := "Windsock"
## From the wheel hub to the foot of the staff (x to starboard, z aft).
@export var wheel_offset := Vector3(1.2, 0.0, 0.5)
## Used until the deck under the staff is found: how far below the wheel hub the foot sits.
@export var hub_to_deck := 1.0
## Height of the flag's hoist above the deck.
@export var pole_height := 1.6
@export var flag_length := 1.3
## Height of the pennant at the staff and at the tail.
@export var hoist_height := 0.24
@export var tail_height := 0.07
@export_range(3, 10) var segments := 6
## Apparent wind (m/s) at which it flies level (about 12 knots).
@export var full_speed := 6.0
## How quickly it swings round to a new wind direction.
@export var swivel_rate := 3.0
@export var cloth_color := Color(0.72, 0.10, 0.08)
@export var hoist_color := Color(0.94, 0.93, 0.88)

var _ship: Node3D
var _pivot: Node3D
var _segs: Array[Node3D] = []
var _psi := 0.0                  # which way it points, same convention as the flags
var _ext := 0.0                  # 0 hanging limp .. 1 flying level
var _t := 0.0
var _probe_frames := 0

func _ready() -> void:
	_ship = get_parent() as Node3D
	if not enabled or _ship == null:
		set_process(false)
		set_physics_process(false)
		return
	var wd: Dictionary = ShipClasses.data(_ship_class()).get("windsock", {})
	pole_height = float(wd.get("pole_height", pole_height))
	flag_length = float(wd.get("flag_length", flag_length))
	hoist_height = float(wd.get("hoist_height", hoist_height))
	tail_height = float(wd.get("tail_height", tail_height))
	position = _mount_point()
	_build()

func _mount_point() -> Vector3:
	var mk := _ship.find_child(mount_node_name, true, false) as Node3D
	if mk and mk != self:
		_probe_frames = 99                 # placed by hand, leave the height alone
		return _ship.to_local(mk.global_position)
	var wheel := _ship.find_child("Wheel", true, false) as Node3D
	if wheel == null:
		push_warning("ShipWindsock: no Wheel and no '%s' marker; standing it aft of the middle" % mount_node_name)
		return Vector3(0.0, 1.8, 5.0)
	var hub := _ship.to_local(wheel.global_position)
	return Vector3(hub.x + wheel_offset.x, hub.y - hub_to_deck, hub.z + wheel_offset.z)

func _mat(c: Color, rough: float, metal: float, two_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## One flat piece of cloth hung from a hinge at its start, running down -Z.
func _cloth(parent: Node3D, mat: Material, length: float, h_start: float, h_end: float) -> void:
	var mesh := ArrayMesh.new()
	var v := PackedVector3Array([
		Vector3(0, h_start * 0.5, 0), Vector3(0, -h_start * 0.5, 0),
		Vector3(0, -h_end * 0.5, -length), Vector3(0, h_end * 0.5, -length)])
	var n := PackedVector3Array([Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _build() -> void:
	var wood := _mat(Color(0.20, 0.12, 0.07), 0.8, 0.0)
	var brass := _mat(Color(0.72, 0.55, 0.22), 0.35, 0.8)
	var iron := _mat(Color(0.10, 0.10, 0.11), 0.6, 0.6)
	var red := _mat(cloth_color, 0.95, 0.0, true)
	var white := _mat(hoist_color, 0.95, 0.0, true)
	# the staff, a little taller than the hoist, with a brass ball on top
	var staff_top := pole_height + hoist_height * 0.5 + 0.05
	var pm := CylinderMesh.new()
	pm.top_radius = 0.016
	pm.bottom_radius = 0.026
	pm.height = staff_top
	pm.radial_segments = 8
	pm.rings = 1
	var pole := MeshInstance3D.new()
	pole.mesh = pm
	pole.material_override = wood
	pole.position = Vector3(0.0, staff_top * 0.5, 0.0)
	add_child(pole)
	var ball := SphereMesh.new()
	ball.radius = 0.03
	ball.height = 0.06
	ball.radial_segments = 10
	ball.rings = 5
	var bi := MeshInstance3D.new()
	bi.mesh = ball
	bi.material_override = brass
	bi.position = Vector3(0.0, staff_top + 0.02, 0.0)
	add_child(bi)
	# the swivel: turns about the staff and carries the pennant
	_pivot = Node3D.new()
	_pivot.name = "Swivel"
	_pivot.position = Vector3(0.0, pole_height, 0.0)
	add_child(_pivot)
	# two thin iron bands hold the hoist edge to the staff
	var band := CylinderMesh.new()
	band.top_radius = 0.022
	band.bottom_radius = 0.022
	band.height = 0.012
	band.radial_segments = 8
	band.rings = 1
	for dy in [hoist_height * 0.38, -hoist_height * 0.38]:
		var bm := MeshInstance3D.new()
		bm.mesh = band
		bm.material_override = iron
		bm.position = Vector3(0.0, dy, 0.0)
		_pivot.add_child(bm)
	# the pennant: a chain of cloth pieces tapering to a swallow tail, each hinged to the one before.
	# The first (hoist) piece is white, the rest red.
	var seg_len := flag_length / float(segments)
	var parent: Node3D = _pivot
	var tail_h := 0.0
	for i in segments:
		var hinge := Node3D.new()
		hinge.name = "Seg%d" % i
		hinge.position = Vector3(0.0, 0.0, -seg_len) if i > 0 else Vector3(0.0, 0.0, -0.03)
		parent.add_child(hinge)
		var h0 := lerpf(hoist_height, tail_height, float(i) / segments)
		var h1 := lerpf(hoist_height, tail_height, float(i + 1) / segments)
		tail_h = h1
		_cloth(hinge, white if i == 0 else red, seg_len, h0, h1)
		_segs.append(hinge)
		parent = hinge
	# the swallow tail: two points splayed from the last hinge's end
	var fork := Node3D.new()
	fork.name = "Fork"
	fork.position = Vector3(0.0, 0.0, -seg_len)
	parent.add_child(fork)
	for s in [-1.0, 1.0]:
		var pt := Node3D.new()
		pt.rotation.y = deg_to_rad(9.0) * s
		fork.add_child(pt)
		var half := Node3D.new()
		half.position = Vector3(0.0, 0.0, 0.0)
		pt.add_child(half)
		var m := ArrayMesh.new()
		var cy := -tail_h * 0.5 if s < 0.0 else tail_h * 0.5
		var tl := seg_len * 0.9
		var v := PackedVector3Array([
			Vector3(0, tail_h * 0.5, 0), Vector3(0, -tail_h * 0.5, 0), Vector3(0, cy * 0.2, -tl)])
		var n := PackedVector3Array([Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = red
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		half.add_child(mi)

func _physics_process(_delta: float) -> void:
	# once, a few frames in: find the deck under the staff (the deck collision is up by then)
	if _probe_frames >= 3:
		return
	_probe_frames += 1
	if _probe_frames < 3:
		return
	var from := _ship.global_transform * (position + Vector3(0.0, 1.2, 0.0))
	var to := from - _ship.global_transform.basis.y * 3.5
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var pl := get_tree().get_first_node_in_group("player")
	if pl is CollisionObject3D:
		q.exclude = [(pl as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var y := _ship.to_local(hit["position"]).y
	if absf(y - position.y) < 1.8:
		position.y = y

func _process(delta: float) -> void:
	_t += delta
	var a := Vector2.ZERO
	var sails = _ship.get("sails")
	if sails != null and sails.get("model") != null:
		a = sails.model.apparent                       # (forward, right) air velocity past the ship
	var spd := a.length()
	if spd >= 0.2:
		var d := Vector2(a.y, -a.x)                      # where the air is going: x starboard, z aft
		_psi = lerp_angle(_psi, atan2(-d.x, -d.y), 1.0 - exp(-delta * swivel_rate))
	_pivot.rotation.y = _psi
	_ext = lerpf(_ext, clampf(spd / maxf(full_speed, 0.1), 0.0, 1.0), 1.0 - exp(-delta * 2.5))
	var lift := pow(_ext, 0.5)
	var droop := lerpf(84.0, 1.0, lift)                  # total bend down, degrees
	var ripple := 2.0 + 14.0 * _ext                      # side to side, degrees at the tail
	var n := _segs.size()
	for i in n:
		var k := float(i + 1) / n                        # the tail moves most
		var pitch := -(droop / float(n)) + sin(_t * 5.5 - i * 0.8) * (0.6 + 1.6 * _ext)
		var yaw := sin(_t * 8.0 - i * 1.0) * ripple * k * 0.55
		_segs[i].rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)

## The ship's size class (ShipClasses.Size), for the class's own vane size.
func _ship_class() -> int:
	var c = _ship.get("ship_class")
	return int(c) if c != null else ShipClasses.Size.MEDIUM
