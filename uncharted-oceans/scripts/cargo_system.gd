class_name CargoSystem
extends Node
## Carrying cargo boxes and stowing them in the hold. Created by player.gd (a child of the player).
##
## A box is a good's block shape (goods.json, scaled to 25 cm hold cells), drawn as a stack of its container
## (barrels, sacks, crates, bales: cargo_visuals.gd). You carry it low in front of you, gripped between both hands,
## in the orientation you picked it up in. It has no collision, so it never snags on anything.
##   hold Space   snap the box to the hold grid: a ghost shows green where it fits, red where it doesn't
##   left click   place it (while the ghost is green)
##   right click  drop it on the ground in front of you (not locked to anything: pick it up again whenever)
##   E            flip it end over end (towards you)
##   R            turn it 90 degrees flat
##   Q            put the box away (it vanishes)
## With empty hands, click a stowed or dropped box to pick it up, or click the cargo crate on the pier
## (cargo_generator.gd) for a random new one.
##
## Orientation is kept in the HAND frame (x right, y up, z back, as you see it) so E and R always do what you see.
## When you snap to the grid the hand frame is mapped to the ship by the way you are facing (nearest ship axis).
##
## The lattice: the flood grid's 25 cm squares (ship_flooding.gd) stacked up from the main hold floor, in the
## ship's own frame, so boxes ride the ship. A cell is free if it is inside an open hold space and holds no other
## box. A box needs at least one cell resting on the floor (or furniture within 7 cm) or on another box; the rest
## may overhang.

const Outline := preload("res://scripts/interact_outline.gd")
## Physics layer 10: stowed and dropped boxes (the player collides with it, nothing else scans it).
const CARGO_LAYER_BIT := 1 << 9
const QuestsScript := preload("res://scripts/courier_quests.gd")

const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const CATEGORY_COLOR := {
	"food": Color(0.78, 0.66, 0.42),
	"spices": Color(0.72, 0.32, 0.16),
	"plantation": Color(0.5, 0.62, 0.28),
	"drink": Color(0.5, 0.22, 0.2),
	"textiles": Color(0.4, 0.5, 0.72),
	"metals": Color(0.56, 0.58, 0.62),
	"naval_stores": Color(0.32, 0.26, 0.19),
	"luxury": Color(0.78, 0.64, 0.2),
	"dyes": Color(0.52, 0.27, 0.62),
	"military": Color(0.27, 0.32, 0.27),
	"courier": Color(0.2, 0.46, 0.5),
}

## How far you can reach to click a crate or a box (m).
@export var reach := 3.2
## How many cells the ghost may slide to find a spot where the box fits.
@export var snap_search := 3
## How far a cell's bottom may sit off a floor or a table top and still count as resting on it (m).
@export var floor_tolerance := 0.07
## How far around a hammock (or its posts) stays clear of cargo (m); they swing a little.
@export var hammock_margin := 0.1
## Where the test crate goes, in the berth's frame (+X away from the pier, -Z the way the ship points).
@export var quay_spot := Vector3(-1.5, 0.0, 2.0)
@export_group("Carry pose")
## The box in your hands is shrunk to fit this (m) at most, and sits this far ahead of the camera.
@export var carry_max_size := 0.42
@export var carry_distance := 0.8
## How far ahead of you a dropped box lands (m).
@export var drop_distance := 0.9

class Placed:
	var uid := 0
	var good: GoodDef
	var shape: Array[Vector3i] = []    # ship-frame orientation, minimum corner at (0, 0, 0)
	var anchor := Vector3i.ZERO        # lattice cell of the minimum corner
	var cells: Array[Vector3i] = []    # lattice cells it fills
	var node: MeshInstance3D

class Loose:
	var good: GoodDef
	var hand_cells: Array[Vector3i] = []
	var node: MeshInstance3D

var data: CargoData
var player: CharacterBody3D
var cam: Camera3D
var flood: ShipFlooding
var rig: Node3D

var carried: GoodDef
var carried_qty := 0                   # boxes of `carried` in your arms: you hold the whole stack, one is placed at a time
var hand_cells: Array[Vector3i] = []   # orientation as you hold it (x right, y up, z back)
var cur_cells: Array[Vector3i] = []    # the same mapped to the ship by the way you face
var carried_mesh: ArrayMesh            # plain cell mesh of cur_cells (the ghost and the lattice)
var snapping := false
var ghost_ok := false
var ghost_anchor := Vector3i.ZERO

## Boxes the hold starts with ({good id: how many}), stowed wherever they fit once the hold grid is ready (see stow_auto).
## Set from the player's start_cargo (player.gd), so a world scene can say what the ship starts with.
var starting_cargo := {}
var placed := {}      # uid -> Placed
var occ := {}         # Vector3i lattice cell -> uid
var loose: Array[Loose] = []

var _held: MeshInstance3D
var _ghost: MeshInstance3D
var _ghost_ok_mat: StandardMaterial3D
var _ghost_bad_mat: StandardMaterial3D
var _free_cache := {}
var _fp_cache := {}
var _blocked := {}          # lattice cells taken by hammocks
var _blocked_t := 0.0
var _reported := false
var _offsets: Array[Vector3i] = []
var _ghost_key: Array = []
var _orient_id := 0
var _version := 0
var _next_uid := 1
var _aim_gen: Node3D
var _aim_loose: Loose
var _aim_box: Placed
var _aim_node: Node3D
var _box_dist := 0.0
var _label: Label
var _msg := ""
var _msg_t := 0.0
var _gen_done := false
var _start_done := false
var _start_wait := 0.0
var _gen_timer := 0.0
var _gen_tries := 0


func _ready() -> void:
	add_to_group("cargo_system")
	data = CargoData.get_shared()
	player = get_parent() as CharacterBody3D
	if player != null:
		cam = player.get_node_or_null("Head/Camera3D") as Camera3D
	_held = MeshInstance3D.new()
	_held.name = "HeldBox"
	_held.visible = false
	_held.material_override = CargoVisuals.material()
	_held.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if cam != null:
		cam.add_child(_held)     # rides the camera, so it stays between your hands however you move
	else:
		add_child(_held)
	_ghost_ok_mat = _make_ghost_mat(Color(0.2, 1.0, 0.35, 0.5))
	_ghost_bad_mat = _make_ghost_mat(Color(1.0, 0.2, 0.2, 0.5))
	_make_offsets()
	_make_hud()


## player.gd asks: while you carry a box, Space snaps it instead of jumping.
func blocks_jump() -> bool:
	return carried != null


## Total weight of everything stowed (kg).
func stowed_weight_kg() -> float:
	var w := 0.0
	for uid in placed:
		w += (placed[uid] as Placed).good.weight_kg
	return w


# ------------------------------------------------------------------ setup

func _make_ghost_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _make_offsets() -> void:
	var n := snap_search
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			for dy in range(-2, 5):
				_offsets.append(Vector3i(dx, dy, dz))
	_offsets.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return _offset_cost(a) < _offset_cost(b))


func _offset_cost(o: Vector3i) -> float:
	return float(o.x * o.x + o.z * o.z) + 0.6 * float(o.y * o.y) + (2.0 if o.y < 0 else 0.0)


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.offset_bottom = -230.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	if ResourceLoader.exists("res://assets/fonts/Ferrum-ExtraCondensed.otf"):
		var font := load("res://assets/fonts/Ferrum-ExtraCondensed.otf") as Font
		if font != null:
			_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", 26)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	layer.add_child(_label)


func _find_refs() -> void:
	if flood == null or not is_instance_valid(flood):
		flood = get_tree().get_first_node_in_group("ship_flooding") as ShipFlooding
		rig = flood.get_parent() as Node3D if flood != null else null
		_free_cache.clear()
		_fp_cache.clear()
	if flood != null and _ghost == null and flood.cargo_ready():
		_ghost = MeshInstance3D.new()
		_ghost.name = "CargoGhost"
		_ghost.visible = false
		_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(_ghost)


## When the hold grid is ready (and rarely after that): print a one-line summary of the free cargo cells. Throttled so
## hammock changes don't spam the Output panel.
const REPORT_MIN_INTERVAL_MS := 60000
var _last_report_ms := -REPORT_MIN_INTERVAL_MS
var _last_reported_free := -1


func _report_capacity() -> void:
	var now := Time.get_ticks_msec()
	if _last_reported_free >= 0 and now - _last_report_ms < REPORT_MIN_INTERVAL_MS:
		return
	var nx := int(ceil(flood.grid_half_width * 2.0 / flood.cell))
	var nz := int(ceil((flood.grid_z_max - flood.grid_z_min) / flood.cell))
	var ny := int(ceil((flood.grid_top - flood.cargo_floor_y()) / flood.cell)) + 1
	var free := 0
	for x in nx:
		for z in nz:
			for y in ny:
				if _cell_free(Vector3i(x, y, z)):
					free += 1
	if free == _last_reported_free:
		return
	_last_reported_free = free
	_last_report_ms = now
	var vol := float(free) * pow(flood.cell, 3.0)
	print("Cargo hold: %d free cells (%.0f m3)" % [free, vol])


func _grid_ready() -> bool:
	return flood != null and is_instance_valid(flood) and flood.cargo_ready() and _ghost != null


# ------------------------------------------------------------------ lattice

func _cell() -> float:
	return flood.cell


func _lat_origin() -> Vector3:
	return Vector3(-flood.grid_half_width, flood.cargo_floor_y(), flood.grid_z_min)


func _cell_center(c: Vector3i) -> Vector3:
	return _lat_origin() + (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * _cell()


func _local_to_lat(p: Vector3) -> Vector3:
	return (p - _lat_origin()) / _cell()


## The highest floor and lowest ceiling under a cell's whole footprint (the centre and four points near its corners),
## or Vector2(INF, INF) if any of them is solid or outside the hold. Checking the footprint, not just the centre, keeps
## boxes out of stair ramps and curved hull walls.
func _footprint(c: Vector3i) -> Vector2:
	if _fp_cache.has(c):
		return _fp_cache[c]
	var p := _cell_center(c)
	var d := _cell() * 0.4
	var fl := -INF
	var ce := INF
	var res := Vector2(INF, INF)
	var solid := false
	for o in [Vector2(0.0, 0.0), Vector2(d, d), Vector2(-d, d), Vector2(d, -d), Vector2(-d, -d)]:
		var r := flood.cargo_range_at(Vector3(p.x + o.x, p.y, p.z + o.y))
		if not is_finite(r.x):
			solid = true
			break
		fl = maxf(fl, r.x)
		ce = minf(ce, r.y)
	if not solid:
		res = Vector2(fl, ce)
	_fp_cache[c] = res
	return res


func _cell_free(c: Vector3i) -> bool:
	if occ.has(c) or _blocked.has(c):
		return false
	if _free_cache.has(c):
		return _free_cache[c]
	var fc := _footprint(c)
	var p := _cell_center(c)
	var half := _cell() * 0.5
	var ok := is_finite(fc.x) and (p.y - half) >= fc.x - floor_tolerance and (p.y + half) <= fc.y + 0.03
	_free_cache[c] = ok
	return ok


## Resting on the floor (or furniture, or a stair) or on another box.
func _cell_grounded(c: Vector3i) -> bool:
	if occ.has(c + Vector3i(0, -1, 0)):
		return true
	return _floor_grounded(c)


func _floor_grounded(c: Vector3i) -> bool:
	var fc := _footprint(c)
	return is_finite(fc.x) and absf((_cell_center(c).y - _cell() * 0.5) - fc.x) <= floor_tolerance


## True if a stowed box really rests on something: the floor (or a stair, furniture) or a DIFFERENT box under any cell.
func _supported(p: Placed) -> bool:
	for c in p.cells:
		var below := c + Vector3i(0, -1, 0)
		if occ.has(below):
			if int(occ[below]) != p.uid:
				return true
		elif _floor_grounded(c):
			return true
	return false


## Boxes with nothing under them fall until they rest on something, for when you take away what they sat on.
func _settle() -> void:
	var moved := true
	var guard := 0
	while moved and guard < 60:
		moved = false
		guard += 1
		for uid in placed:
			var p: Placed = placed[uid]
			if _supported(p):
				continue
			for c in p.cells:
				occ.erase(c)
			var ok := true
			var nc: Array[Vector3i] = []
			for c in p.cells:
				var t := c + Vector3i(0, -1, 0)
				nc.append(t)
				if not _cell_free(t):
					ok = false
					break
			if ok:
				p.cells = nc
				p.anchor += Vector3i(0, -1, 0)
				if is_instance_valid(p.node):
					p.node.position = _lat_origin() + Vector3(p.anchor) * _cell()
				moved = true
			for c in p.cells:
				occ[c] = p.uid


## Hammocks (and the posts of their sets) block the cells they occupy, for as many sets as are showing: more crew
## means more hammocks slung, which means less hold. Re-checked twice a second.
func _refresh_blocked(delta: float) -> void:
	_blocked_t -= delta
	if _blocked_t > 0.0 or not _grid_ready():
		return
	_blocked_t = 0.5
	var nb := {}
	var inv := rig.global_transform.affine_inverse()
	var sets := get_tree().get_nodes_in_group("hammock_sets")
	if sets.is_empty():
		sets = get_tree().get_nodes_in_group("hammocks")
	for s in sets:
		var n3 := s as Node3D
		if n3 == null or not n3.is_visible_in_tree():
			continue
		var meshes: Array = n3.find_children("*", "MeshInstance3D", true, false)
		if n3 is MeshInstance3D:
			meshes.append(n3)
		for m in meshes:
			var mi := m as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var bb: AABB = (inv * mi.global_transform) * mi.get_aabb()
			bb = bb.grow(hammock_margin)
			if bb.size.x > 8.0 or bb.size.y > 6.0 or bb.size.z > 8.0:
				continue     # a mesh that big is the whole ship, not a hammock
			var lo := _local_to_lat(bb.position)
			var hi := _local_to_lat(bb.end)
			for x in range(floori(lo.x), floori(hi.x) + 1):
				for y in range(floori(lo.y), floori(hi.y) + 1):
					for z in range(floori(lo.z), floori(hi.z) + 1):
						nb[Vector3i(x, y, z)] = true
	var same := nb.size() == _blocked.size()
	if same:
		for k in nb:
			if not _blocked.has(k):
				same = false
				break
	if not same:
		_blocked = nb
		_free_cache.clear()
		_version += 1
	if not same or not _reported:
		_reported = true
		_report_capacity()     # on load, and again whenever hammocks are added or removed


func _can_place(cells: Array[Vector3i], anchor: Vector3i) -> bool:
	var supported := false
	for c in cells:
		var w := anchor + c
		if not _cell_free(w):
			return false
		if not supported and _cell_grounded(w):
			supported = true
	return supported


# ------------------------------------------------------------------ shapes

static func normalized(cells: Array[Vector3i]) -> Array[Vector3i]:
	var mn := Vector3i(1 << 30, 1 << 30, 1 << 30)
	for c in cells:
		mn = Vector3i(mini(mn.x, c.x), mini(mn.y, c.y), mini(mn.z, c.z))
	var out: Array[Vector3i] = []
	for c in cells:
		out.append(c - mn)
	return out


## Quarter turn about the X axis (end over end when you face along -Z).
static func rot_x(cells: Array[Vector3i]) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for c in cells:
		out.append(Vector3i(c.x, -c.z, c.y))
	return normalized(out)


static func size_of(cells: Array[Vector3i]) -> Vector3i:
	var mx := Vector3i.ZERO
	for c in cells:
		mx = Vector3i(maxi(mx.x, c.x), maxi(mx.y, c.y), maxi(mx.z, c.z))
	return mx + Vector3i.ONE


## Mesh of the exposed faces only, plain cells (used for the ghost silhouette).
static func build_mesh(cells: Array[Vector3i], cell: float) -> ArrayMesh:
	var filled := {}
	for c in cells:
		filled[c] = true
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for c in cells:
		var centre := (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * cell
		for d in DIRS:
			if filled.has(c + d):
				continue
			var n := Vector3(d)
			var u := Vector3(0.0, 1.0, 0.0) if d.y == 0 else Vector3(1.0, 0.0, 0.0)
			var v := n.cross(u)
			var fc := centre + n * cell * 0.5
			var a := fc - u * cell * 0.5 - v * cell * 0.5
			var b := fc + u * cell * 0.5 - v * cell * 0.5
			var cc := fc + u * cell * 0.5 + v * cell * 0.5
			var dd := fc - u * cell * 0.5 + v * cell * 0.5
			var base := verts.size()
			verts.append_array([a, b, cc, dd])
			for i in 4:
				norms.append(n)
			# Godot front faces are clockwise seen from outside
			if (b - a).cross(cc - a).dot(n) > 0.0:
				idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
			else:
				idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	if verts.size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _color_for(g: GoodDef) -> Color:
	var c: Color = CATEGORY_COLOR.get(g.category, Color(0.6, 0.5, 0.4))
	var h := absi(hash(g.id)) % 9 - 4
	return c.lightened(0.04 * h) if h > 0 else c.darkened(-0.04 * h)


func _visual(g: GoodDef, cells: Array[Vector3i]) -> ArrayMesh:
	return CargoVisuals.build(cells, g.container, _color_for(g), data.cell_m, data.scale)


# ------------------------------------------------------------------ hand frame <-> ship frame

## The way you face, snapped to a ship axis: [right, back] as integer vectors in the ship's frame.
func _axes() -> Array:
	var f := _forward_local()
	var fwd := Vector3i(0, 0, -1 if f.z < 0.0 else 1) if absf(f.z) >= absf(f.x) else Vector3i(-1 if f.x < 0.0 else 1, 0, 0)
	var right := Vector3i(-fwd.z, 0, fwd.x)     # forward x up
	return [right, -fwd]


func _to_ship(cells: Array[Vector3i]) -> Array[Vector3i]:
	var ax := _axes()
	var right: Vector3i = ax[0]
	var back: Vector3i = ax[1]
	var out: Array[Vector3i] = []
	for c in cells:
		out.append(right * c.x + Vector3i(0, c.y, 0) + back * c.z)
	return normalized(out)


func _to_hand(cells: Array[Vector3i]) -> Array[Vector3i]:
	var ax := _axes()
	var right: Vector3i = ax[0]
	var back: Vector3i = ax[1]
	var out: Array[Vector3i] = []
	for c in cells:
		out.append(Vector3i(c.x * right.x + c.z * right.z, c.y, c.x * back.x + c.z * back.z))
	return normalized(out)


func _forward_local() -> Vector3:
	var f := -cam.global_transform.basis.z
	if rig != null and is_instance_valid(rig):
		f = rig.global_transform.basis.inverse() * f
	return f


# ------------------------------------------------------------------ carrying

func _carry(g: GoodDef, shape: Array[Vector3i] = [], qty: int = 1) -> void:
	carried = g
	carried_qty = maxi(qty, 1)
	hand_cells = shape.duplicate() if not shape.is_empty() else normalized(g.cells)
	_hand_changed()
	_held.visible = true


## The hand-frame shape changed: rebuild what's in your hands and refresh the ship-frame copy.
func _hand_changed() -> void:
	_held.mesh = _visual(carried, hand_cells)
	cur_cells = []
	_refresh_ship()


## Re-map the hand shape to the ship (the way you face may have changed).
func _refresh_ship() -> void:
	var nc := _to_ship(hand_cells)
	if nc == cur_cells and carried_mesh != null:
		return
	cur_cells = nc
	_orient_id += 1
	carried_mesh = build_mesh(cur_cells, data.cell_m)
	if _ghost != null:
		_ghost.mesh = carried_mesh


func _flip() -> void:
	hand_cells = rot_x(hand_cells)
	_hand_changed()


func _turn() -> void:
	hand_cells = GoodDef.rotated_yaw(hand_cells, 1)
	_hand_changed()


## Q: send the box back to the port box pool (never lose something you paid for).
func _stow_away() -> void:
	var stock := preload("res://scripts/trade_state.gd").box_stock("")
	var n := carried_qty
	for i in n:
		stock.append(carried.id)
	_let_go()
	if _ghost != null:
		_ghost.visible = false
	_say("%d sent back to the port box" % n if n > 1 else "Box sent back to the port box")


func _say(t: String) -> void:
	_msg = t
	_msg_t = 2.0


## The box rides low in front of you between the gloves, covering no more than the bottom quarter of the view.
func _update_held() -> void:
	var sz := Vector3(size_of(hand_cells)) * data.cell_m
	var s := minf(1.0, carry_max_size / maxf(sz.x, maxf(sz.y, sz.z)))
	var ssz := sz * s
	var quarter := tan(deg_to_rad(cam.fov * 0.5)) * 0.5     # view height below the middle that the bottom quarter spans, per metre
	var cz := -carry_distance
	var near := absf(cz) - ssz.z * 0.5
	var top := -quarter * near - 0.01
	var centre := Vector3(0.0, top - ssz.y * 0.5, cz)
	_held.scale = Vector3.ONE * s
	_held.position = centre - ssz * 0.5
	_held.rotation = Vector3.ZERO
	var hands := player.get("hands") as PlayerHands
	if hands != null:
		hands.carry_active = true
		hands.carry_centre = centre
		hands.carry_half = ssz.x * 0.5


func _release_hands() -> void:
	var hands := player.get("hands") as PlayerHands
	if hands != null:
		hands.carry_active = false


# ------------------------------------------------------------------ aiming

func _world_hit_dist(o: Vector3, d: Vector3, max_d: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(o, o + d * max_d, 1, [player.get_rid()])
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return max_d
	return o.distance_to(hit["position"] as Vector3)


## Ship-local point the box is aimed at: a deck or wall hit (nudged off the surface), the front of a stowed
## box (they have no collision, so the lattice is marched), or two metres ahead in the air.
func _aim_local() -> Vector3:
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var max_d := reach + 1.0
	var q := PhysicsRayQueryParameters3D.create(o, o + d * max_d, 1, [player.get_rid()])
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	var end_d := max_d
	var has_hit := false
	if not hit.is_empty() and rig != null and rig.is_ancestor_of(hit["collider"] as Node):
		end_d = o.distance_to(hit["position"] as Vector3)
		has_hit = true
	var inv := rig.global_transform.affine_inverse()
	var t := 0.1
	while t < end_d:
		var lc := _local_to_lat(inv * (o + d * t))
		if occ.has(Vector3i(floori(lc.x), floori(lc.y), floori(lc.z))):
			return inv * (o + d * maxf(t - 0.08, 0.05))
		t += 0.06
	if has_hit:
		return inv * ((hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.12)
	return inv * (o + d * minf(end_d, 2.2))


func _update_ghost() -> void:
	_ghost.visible = snapping
	if not snapping:
		return
	var lc := _local_to_lat(_aim_local())
	var sz := size_of(cur_cells)
	var base := Vector3i(roundi(lc.x - sz.x * 0.5), floori(lc.y + 0.15), roundi(lc.z - sz.z * 0.5))
	var key: Array = [base, _orient_id, _version]
	if key != _ghost_key:
		_ghost_key = key
		_solve(base)
	if _ghost.mesh != carried_mesh:
		_ghost.mesh = carried_mesh
	_ghost.position = _lat_origin() + Vector3(ghost_anchor) * _cell()
	_ghost.material_override = _ghost_ok_mat if ghost_ok else _ghost_bad_mat


## Where the box goes: right where you aim if it fits, else the nearest spot within snap_search cells that does.
func _solve(base: Vector3i) -> void:
	ghost_ok = false
	ghost_anchor = base
	if _can_place(cur_cells, base):
		ghost_ok = true
		return
	for off in _offsets:
		var a := base + off
		if _can_place(cur_cells, a):
			ghost_anchor = a
			ghost_ok = true
			return


## Distance along the ray to a node's meshes (box test), or -1.
func _ray_node(root: Node3D, o: Vector3, d: Vector3, max_d: float) -> float:
	var best := -1.0
	var list: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		list.append(root)
	for m in list:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var inv := mi.global_transform.affine_inverse()
		var hit = mi.get_aabb().grow(0.03).intersects_ray(inv * o, (inv.basis * d).normalized())
		if hit != null:
			var dist := o.distance_to(mi.global_transform * (hit as Vector3))
			if dist <= max_d and (best < 0.0 or dist < best):
				best = dist
	return best


func _box_along_ray(o: Vector3, d: Vector3, max_d: float) -> Placed:
	if not _grid_ready():
		return null
	var limit := minf(max_d, _world_hit_dist(o, d, max_d))
	var inv := rig.global_transform.affine_inverse()
	var t := 0.1
	while t < limit:
		var lc := _local_to_lat(inv * (o + d * t))
		var c := Vector3i(floori(lc.x), floori(lc.y), floori(lc.z))
		if occ.has(c):
			_box_dist = t
			return placed.get(occ[c]) as Placed
		t += 0.05
	return null


func _update_aim(captured: bool) -> void:
	var gen: Node3D = null
	var lo: Loose = null
	var box: Placed = null
	if captured and cam != null:
		var o := cam.global_position
		var d := -cam.global_transform.basis.z
		var best := reach
		for g in get_tree().get_nodes_in_group("cargo_generators"):
			var dist := _ray_node(g as Node3D, o, d, best)
			if dist >= 0.0 and dist <= best:
				best = dist
				gen = g as Node3D
		for l in loose:
			if not is_instance_valid(l.node):
				continue
			var dist := _ray_node(l.node, o, d, best)
			if dist >= 0.0 and dist <= best:
				best = dist
				lo = l
				gen = null
		if carried == null:
			box = _box_along_ray(o, d, best)
		if box != null:
			gen = null
			lo = null
		if carried != null:
			lo = null       # with a box in your hands only the port box can be aimed at (to put it back)
	_set_aim(gen, lo, box)


func _set_aim(gen: Node3D, lo: Loose, box: Placed) -> void:
	_aim_gen = gen
	_aim_loose = lo
	_aim_box = box
	var target: Node3D = gen
	if lo != null:
		target = lo.node
	elif box != null:
		target = box.node
	if target != _aim_node:
		if _aim_node != null and is_instance_valid(_aim_node):
			Outline.set_on(_aim_node, false)
		_aim_node = target
		if target != null:
			Outline.set_on(target, true)


# ------------------------------------------------------------------ actions

func _place() -> void:
	var p := Placed.new()
	p.uid = _next_uid
	_next_uid += 1
	p.good = carried
	p.shape = cur_cells.duplicate()
	p.anchor = ghost_anchor
	for c in cur_cells:
		var w := ghost_anchor + c
		p.cells.append(w)
		occ[w] = p.uid
	var mi := MeshInstance3D.new()
	mi.name = "Cargo_%s_%d" % [carried.id, p.uid]
	mi.mesh = _visual(carried, p.shape)
	mi.material_override = CargoVisuals.material()
	mi.position = _lat_origin() + Vector3(ghost_anchor) * _cell()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(mi)
	_add_collision(mi, p.shape)
	p.node = mi
	placed[p.uid] = p
	_version += 1
	_push_load()
	var how := "nothing!"
	for c in p.cells:
		var below := c + Vector3i(0, -1, 0)
		if occ.has(below) and int(occ[below]) != p.uid:
			how = "on a box at cell %s" % str(c)
			break
		if _floor_grounded(c):
			how = "on floor at cell %s (footprint floor y %.2f, hold floor %.2f)" % [str(c), _footprint(c).x, flood.cargo_floor_y()]
			break
	print("cargo placed %s at %s, resting %s" % [carried.id, str(ghost_anchor), how])
	_used_one()


## Makes a stowed or dropped box solid for the player: one box shape per hold cell, on its own physics layer
## (CARGO_LAYER_BIT, which player.gd adds to its mask) so the flood grid's scans and the aiming rays never see it.
func _add_collision(mi: MeshInstance3D, cells: Array[Vector3i]) -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = CARGO_LAYER_BIT
	body.collision_mask = 0
	var cm := data.cell_m
	for c in cells:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3.ONE * cm
		cs.shape = bs
		cs.position = (Vector3(c) + Vector3.ONE * 0.5) * cm
		body.add_child(cs)
	mi.add_child(body)


func _let_go() -> void:
	carried = null
	carried_qty = 0
	_held.visible = false
	_release_hands()


## One box of the stack in your arms is gone (placed or set down). The rest stay in your hands, the way you hold
## them, until the last one goes.
func _used_one() -> void:
	carried_qty -= 1
	if carried_qty <= 0:
		_let_go()
	else:
		_say("%d left in your arms" % carried_qty)
	if _ghost != null:
		_ghost.visible = false


## Right click: set the box down on the ground a little ahead of you, the way you hold it. It's an ordinary
## loose box (no grid, no lock) that you can pick up again.
func _drop() -> void:
	var fwd := -cam.global_transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.05:
		flat = -player.global_transform.basis.z
	flat = flat.normalized()
	var o := cam.global_position + flat * drop_distance
	var q := PhysicsRayQueryParameters3D.create(o, o + Vector3.DOWN * 4.0, 1 | Island.LAYER_BIT, [player.get_rid()])
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	var parent: Node3D = null
	if not hit.is_empty():
		parent = hit["collider"] as Node3D
	if parent == null:
		_say("Nowhere to put it down")
		return
	var sz := Vector3(size_of(hand_cells)) * data.cell_m
	var basis := Basis.looking_at(flat, Vector3.UP)
	var centre := (hit["position"] as Vector3) + Vector3.UP * (sz.y * 0.5 + 0.005)
	var l := Loose.new()
	l.good = carried
	l.hand_cells = hand_cells.duplicate()
	var mi := MeshInstance3D.new()
	mi.name = "Loose_%s" % carried.id
	mi.mesh = _visual(carried, hand_cells)
	mi.material_override = CargoVisuals.material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = Transform3D(basis, centre - basis * (sz * 0.5))
	_add_collision(mi, hand_cells)
	l.node = mi
	loose.append(l)
	_used_one()


func _pick_up(p: Placed) -> void:
	for c in p.cells:
		occ.erase(c)
	placed.erase(p.uid)
	if is_instance_valid(p.node):
		Outline.set_on(p.node, false)
		p.node.queue_free()
	_version += 1
	_settle()
	_push_load()
	_aim_box = null
	_aim_node = null
	_carry(p.good, _to_hand(p.shape))


func _pick_up_loose(l: Loose) -> void:
	loose.erase(l)
	if is_instance_valid(l.node):
		Outline.set_on(l.node, false)
		l.node.queue_free()
	_aim_loose = null
	_aim_node = null
	_carry(l.good, l.hand_cells)


## Once the hold grid is ready (and the hammocks have been counted), stow the starting load, once.
func _try_start_cargo(delta: float) -> void:
	if _start_done or starting_cargo.is_empty():
		return
	if _reported and _grid_ready():
		_start_done = true
		for id in starting_cargo:
			var want := int(starting_cargo[id])
			var got := stow_auto(str(id), want)
			print("cargo: starting load %s: %d of %d boxes stowed" % [str(id), got, want])
		return
	_start_wait += delta
	if _start_wait > 30.0:
		_start_done = true
		push_warning("CargoSystem: the hold grid never became ready, so the starting cargo was not stowed")


## Put up to n boxes of a good straight into the hold, wherever they fit, without anyone carrying them: lowest level
## first, working out from the middle of the hold, each resting on the floor or on another box. Returns how many fit.
func stow_auto(good_id: String, n: int) -> int:
	if not _grid_ready():
		return 0
	var g := data.get_good(good_id)
	if g == null:
		push_warning("CargoSystem: no such good '%s'" % good_id)
		return 0
	var shape := normalized(g.cells)
	var sz := size_of(shape)
	var nx := int(ceil(flood.grid_half_width * 2.0 / flood.cell))
	var nz := int(ceil((flood.grid_z_max - flood.grid_z_min) / flood.cell))
	var ny := int(ceil((flood.grid_top - flood.cargo_floor_y()) / flood.cell)) + 1
	var zc := float(nz - sz.z) * 0.5
	var spots: Array[Vector3i] = []
	for y in ny:
		for z in range(0, maxi(nz - sz.z, 0) + 1):
			for x in range(0, maxi(nx - sz.x, 0) + 1):
				spots.append(Vector3i(x, y, z))
	spots.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		var da := absf(float(a.z) - zc)
		var db := absf(float(b.z) - zc)
		if not is_equal_approx(da, db):
			return da < db
		return a.x < b.x)
	var done := 0
	for i in n:
		var spot := Vector3i(-1, -1, -1)
		for a in spots:
			if _can_place(shape, a):
				spot = a
				break
		if spot.x < 0:
			break
		_stow_box(g, shape, spot)
		done += 1
	if done > 0:
		_version += 1
		_push_load()
	return done


## One box into the hold at a lattice spot (the same as _place, for a box nobody carried).
func _stow_box(g: GoodDef, shape: Array[Vector3i], anchor: Vector3i) -> void:
	var p := Placed.new()
	p.uid = _next_uid
	_next_uid += 1
	p.good = g
	p.shape = shape.duplicate()
	p.anchor = anchor
	for c in shape:
		var w := anchor + c
		p.cells.append(w)
		occ[w] = p.uid
	var mi := MeshInstance3D.new()
	mi.name = "Cargo_%s_%d" % [g.id, p.uid]
	mi.mesh = _visual(g, p.shape)
	mi.material_override = CargoVisuals.material()
	mi.position = _lat_origin() + Vector3(anchor) * _cell()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(mi)
	_add_collision(mi, p.shape)
	p.node = mi
	placed[p.uid] = p


## How many boxes of each good are stowed in the hold: {good id: count}.
func hold_counts() -> Dictionary:
	var out := {}
	for uid in placed:
		var id: String = (placed[uid] as Placed).good.id
		out[id] = int(out.get(id, 0)) + 1
	return out


## Take n boxes of a good out of the hold (a sale: the dockhands unload them). The highest ones go first so nothing is
## left hanging, and whatever sat on them settles. Returns how many were taken.
func remove_from_hold(good_id: String, n: int) -> int:
	var list: Array = []
	for uid in placed:
		if (placed[uid] as Placed).good.id == good_id:
			list.append(placed[uid])
	list.sort_custom(func(a: Placed, b: Placed) -> bool: return a.anchor.y > b.anchor.y)
	var k := mini(n, list.size())
	for i in k:
		var p: Placed = list[i]
		for c in p.cells:
			occ.erase(c)
		placed.erase(p.uid)
		if is_instance_valid(p.node):
			Outline.set_on(p.node, false)
			p.node.queue_free()
	if k > 0:
		_aim_box = null
		_aim_node = null
		_version += 1
		_settle()
		_push_load()
	return k


## Tell the ship how much cargo is stowed and where, so she rides lower, trims and (overloaded) swamps (ship_flooding.gd).
func _push_load() -> void:
	if flood == null or not is_instance_valid(flood):
		return
	var kg := 0.0
	var mx := 0.0
	var mz := 0.0
	for uid in placed:
		var p: Placed = placed[uid]
		var c := Vector3.ZERO
		for w in p.cells:
			c += _cell_center(w)
		c /= float(maxi(p.cells.size(), 1))
		kg += p.good.weight_kg
		mx += p.good.weight_kg * c.x
		mz += p.good.weight_kg * c.z
	flood.set_cargo(kg, mx / kg if kg > 0.0 else 0.0, mz / kg if kg > 0.0 else 0.0)


## Put the box in your hands back into the port box (it joins the shared pool).
func _put_in_port_box(gen: Node3D) -> void:
	var n := carried_qty
	var said := ""
	if QuestsScript.is_parcel(carried.id):
		# a courier parcel put into a port box of the port it is addressed to is delivered (courier_quests.gd)
		var res: Dictionary = QuestsScript.deliver(carried.id, String((gen as CargoGenerator).stock_key).get_slice("/", 0))
		said = String(res["msg"])
		if bool(res["ok"]):
			_say(said)
			_let_go()
			if _ghost != null:
				_ghost.visible = false
			return
	for i in n:
		(gen as CargoGenerator).put_good(carried)
	_say(said if said != "" else ("Put %d back in the port box" % n if n > 1 else "Put back in the port box"))
	_let_go()
	if _ghost != null:
		_ghost.visible = false


func _take_from_crate(gen: Node3D) -> void:
	if carried != null:
		_say("Hands full")
		return
	var g := (gen as CargoGenerator).take_good(data)
	if g == null:
		_say("The port box is empty")
	else:
		# the whole stack of that good comes out into your arms
		var stock := preload("res://scripts/trade_state.gd").box_stock((gen as CargoGenerator).stock_key)
		var n := 1
		while stock.has(g.id):
			stock.erase(g.id)
			n += 1
		_carry(g, [], n)


func _input(e: InputEvent) -> void:
	if player == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or bool(player.get("input_locked")):
		return
	if e is InputEventKey and e.pressed and not e.echo and carried != null:
		var handled := true
		match e.physical_keycode:
			KEY_E:
				_flip()
			KEY_R:
				_turn()
			KEY_Q:
				_stow_away()
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		if carried != null:
			_drop()
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if carried != null:
			if snapping and ghost_ok:
				_place()
				get_viewport().set_input_as_handled()
			elif _aim_gen != null and not snapping:
				_put_in_port_box(_aim_gen)
				get_viewport().set_input_as_handled()
		elif _aim_gen != null:
			_take_from_crate(_aim_gen)
			get_viewport().set_input_as_handled()
		elif _aim_loose != null:
			_pick_up_loose(_aim_loose)
			get_viewport().set_input_as_handled()
		elif _aim_box != null:
			_pick_up(_aim_box)
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if player == null or cam == null:
		return
	_msg_t = maxf(_msg_t - delta, 0.0)
	_find_refs()
	_refresh_blocked(delta)
	_try_start_cargo(delta)
	_try_spawn_crate(delta)
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not bool(player.get("input_locked"))
	snapping = carried != null and captured and Input.is_physical_key_pressed(KEY_SPACE) and _grid_ready()
	if carried != null:
		_update_aim(captured)
		_update_held()
		if _grid_ready():
			_refresh_ship()
			_update_ghost()
	else:
		_release_hands()
		_update_aim(captured)
	_update_label()


func _update_label() -> void:
	var t := ""
	if carried != null:
		t = "%s  (%s, %d kg)%s\n" % [carried.display_name, carried.container, roundi(carried.weight_kg), ("   qty %d" % carried_qty) if carried_qty > 1 else ""]
		if snapping:
			t += ("Click to place one" if carried_qty > 1 else "Click to place") if ghost_ok else "Won't fit here: no room, or nothing to rest on"
			t += "\nE flip   R turn   Right click drop   Q send back"
		elif _aim_gen != null:
			t += (QuestsScript.prompt_for(carried.id, String((_aim_gen as CargoGenerator).stock_key).get_slice("/", 0)) if QuestsScript.is_parcel(carried.id) else "Click: put it back in the port box") + "\nE flip   R turn   Right click drop   Q send back"
		else:
			t += "Hold SPACE to snap it to the hold grid\nE flip   R turn   Right click drop   Q send back"
	elif _aim_gen != null:
		t = (_aim_gen as CargoGenerator).prompt()
	elif _aim_loose != null:
		t = "Click: pick up %s (%d kg)" % [_aim_loose.good.display_name, roundi(_aim_loose.good.weight_kg)]
	elif _aim_box != null:
		t = "Click: pick up %s (%d kg)" % [_aim_box.good.display_name, roundi(_aim_box.good.weight_kg)]
	if _msg_t > 0.0:
		t = (t + "\n" if t != "" else "") + _msg
	_label.text = t
	_label.visible = t != ""


# ------------------------------------------------------------------ the test crate on the pier

## Waits for the home port's berth, then stands the crate on the quay beside where the gangway comes ashore.

func _try_spawn_crate(_delta: float) -> void:
	if get_tree().get_first_node_in_group("market_director") != null:
		return
	var md := preload("res://scripts/market_director.gd").new()
	md.name = "MarketDirector"
	player.add_child(md)
