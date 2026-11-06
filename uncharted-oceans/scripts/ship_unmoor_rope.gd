class_name ShipUnmoorRope
extends Node3D
## A rope hung over the port rail of the poop deck that you click to cast off. Created by ship_motion.gd
## (unmoor_rope_enabled). It is only there while the ship is moored with her lines hauled in and the gangway out
## (ShipHarbor.moored, settle); it gets the white outline when you look at it close enough to click, like the other
## clickable things on the ship. Clicking it does what E at the wheel does: ShipHarbor.cast_off() (which still
## refuses, with a message, while someone is standing on the gangway).
##
## Where it hangs: put an Empty called "UnmoorRope" in the brig on the spot (the top of the rail) and the rope hangs
## there. Without one it hangs at rail_position (ship frame: bow is -Z, port is -X), and the height is then found
## from the poop deck under it (rail_height above the deck).

const Outline := preload("res://scripts/interact_outline.gd")

@export var enabled := true
@export var mount_node_name := "UnmoorRope"
## The top of the poop deck's port rail, aft of the wheel (the poop deck is 3.875 m up and its rail 0.875 m above that).
@export var rail_position := Vector3(-2.75, 4.75, 6.1)
## Rail height above the poop deck, used to set the height once the deck under the rope is found.
@export var rail_height := 0.875
## Which way is out over the side: -1 = port (-X), +1 = starboard.
@export var outboard := -1.0
@export var rope_radius := 0.032
## The turns round the rail: radius from the rail's centre line (rail half-thickness plus the rope), how far the centre
## line sits below the origin, how many turns (use a half-turn count: x.5 ends the rope on the outboard side),
## and how far along the rail the turns run.
@export var wrap_radius := 0.085
@export var wrap_drop := 0.05
@export var wrap_turns := 3.5
@export var wrap_length := 0.5
@export var rope_color := Color(0.60, 0.48, 0.28)
## How far you can click it (m).
@export var reach := 3.0

var _ship: Node3D
var _harbor: Node
var _cam: Camera3D
var _player: Node
var _meshes: Array[MeshInstance3D] = []
var _placed := false              # a marker put it there: leave the height alone
var _probe_frames := 0
var _lit := false


func _ready() -> void:
	_ship = get_parent() as Node3D
	if not enabled or _ship == null:
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		return
	position = _mount_point()
	_build()
	visible = false


func _mount_point() -> Vector3:
	var mk := _ship.find_child(mount_node_name, true, false) as Node3D
	if mk != null and mk != self:
		_placed = true
		return _ship.to_local(mk.global_position)
	return rail_position


# ---------------------------------------------------------------- the rope

func _spline(pts: Array[Vector3]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in pts.size() - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		var n := maxi(4, int(p1.distance_to(p2) / 0.03))
		for s in n:
			var t := float(s) / n
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(pts[pts.size() - 1])
	return out


## A thin tube along the points (they lie in the XY plane, so the ring frame is easy).
func _tube(pts: Array[Vector3], z: float, mat: Material) -> void:
	var path := _spline(pts)
	var sides := 6
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in path.size():
		var t := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var n := Vector3(0.0, 0.0, 1.0)
		var b := t.cross(n).normalized()
		for s in sides + 1:
			var a := TAU * float(s) / sides
			var dir := n * cos(a) + b * sin(a)
			verts.append(path[i] + Vector3(0.0, 0.0, z) + dir * rope_radius)
			norms.append(dir)
	var ring := sides + 1
	for i in path.size() - 1:
		for s in sides:
			var a := i * ring + s
			var bb := a + ring
			idx.append_array(PackedInt32Array([a, bb, a + 1, a + 1, bb, bb + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_meshes.append(mi)


## A knot (a small ball of rope) at the end of a line.
func _knot(at: Vector3, mat: Material) -> void:
	var sm := SphereMesh.new()
	sm.radius = rope_radius * 1.7
	sm.height = rope_radius * 3.4
	sm.radial_segments = 8
	sm.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_meshes.append(mi)


## One rope wound round the rail (the rail runs along Z): it hangs down on the deck side, climbs round the rail in a
## few loose turns and the other end hangs down outboard, each end with a knot. Origin is the top of the rail.
func _build() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = rope_color
	mat.roughness = 0.95
	var s := -outboard                    # +1 when inboard is +X
	var cy := -wrap_drop                  # the rail's centre line, a little below the origin
	var steps := int(wrap_turns * 12.0)
	var z0 := -wrap_length * 0.5
	var pts: Array[Vector3] = [
		Vector3(s * (wrap_radius + 0.10), cy - 0.60, z0), Vector3(s * (wrap_radius + 0.04), cy - 0.25, z0)]
	for k in steps + 1:
		var a := TAU * float(k) / 12.0
		pts.append(Vector3(s * wrap_radius * cos(a), cy + wrap_radius * sin(a), z0 + wrap_length * float(k) / steps))
	var z1 := z0 + wrap_length
	# after whole and half turns the rope is on the outboard side (a = wrap_turns * TAU); drop it from there
	pts.append(Vector3(-s * (wrap_radius + 0.03), cy - 0.30, z1))
	pts.append(Vector3(-s * (wrap_radius + 0.09), cy - 0.66, z1))
	_tube(pts, 0.0, mat)
	_knot(pts[0], mat)
	_knot(pts[pts.size() - 1], mat)


# ---------------------------------------------------------------- aiming and clicking

func _get_harbor() -> Node:
	if _harbor == null or not is_instance_valid(_harbor):
		_harbor = _ship.get_node_or_null("ShipHarbor")
	return _harbor


func _camera() -> Camera3D:
	if _cam == null or not is_instance_valid(_cam):
		_player = get_tree().get_first_node_in_group("player")
		if _player:
			_cam = _player.get_node_or_null("Head/Camera3D") as Camera3D
	return _cam


## True while you are looking at the rope close enough to click it.
func _aimed() -> bool:
	var cam := _camera()
	if cam == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if bool(_player.get("input_locked")) or bool(_player.get_meta("grab_busy", false)):
		return false
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var best := INF
	for m in _meshes:
		var inv := m.global_transform.affine_inverse()
		var hit = m.get_aabb().grow(0.12).intersects_ray(inv * o, (inv.basis * d).normalized())
		if hit != null:
			best = minf(best, o.distance_to(m.global_transform * (hit as Vector3)))
	return best <= reach


func _input(e: InputEvent) -> void:
	if not visible:
		return
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if not _aimed():
		return
	var h := _get_harbor()
	if h != null and h.has_method("cast_off"):
		h.call("cast_off")
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var h := _get_harbor()
	var lines_in := h != null and bool(h.get("moored")) and float(h.get("settle")) > 0.8
	visible = lines_in
	var aimed := lines_in and _aimed()
	if aimed != _lit:
		_lit = aimed
		Outline.set_on(self, aimed)


## Once, a few frames in (the deck collision is up by then): when no marker placed the rope, find the poop deck under
## it and hang it rail_height above that.
func _physics_process(_delta: float) -> void:
	if _probe_frames >= 3:
		return
	_probe_frames += 1
	if _probe_frames < 3 or _placed:
		return
	var from := _ship.global_transform * Vector3(position.x - outboard * 0.5, position.y + 0.5, position.z)
	var to := from - _ship.global_transform.basis.y * 2.5
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var pl := get_tree().get_first_node_in_group("player")
	if pl is CollisionObject3D:
		q.exclude = [(pl as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var y := _ship.to_local(hit["position"]).y + rail_height
	if absf(y - position.y) < 0.8:
		position.y = y
