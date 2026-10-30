class_name ShipFlooding
extends Node3D
## Flooding prototype. Put this node under the ShipRig (next to the Brig).
##
## In game (mouse captured), only while the debug screen is open (H):
##   Left click   punch a hole in the hull where you're looking (within reach)
##   Right click  plug the hole you're looking at
##   P            pumps on/off
##   Backspace    drain everything and remove all holes
##   G            show the hold grid (a green tile on the floor of every space water can reach)
##
## How it works
## - The hold is a grid of 25 cm squares in the ship's own frame, found at startup by probing
##   the ship's deck collision (ShipBody, layer 1). Each square can hold several stacked
##   "spaces": every open gap that sits on something solid becomes one (the floor under a
##   staircase and the steps above it, under a table and on top of it). Spaces outside the
##   hull walls are dropped.
## - Water is a depth per space, moved between neighbouring spaces whose heights overlap with
##   a "virtual pipe" shallow-water model. The driving force is the difference in surface
##   height measured along real gravity, so when the ship rolls the water runs to the low
##   side and sloshes back.
## - Drawn as one box per wet space (one draw call). The shader drops the box faces that are
##   inside the water body, makes it see-through by how much water is behind each pixel (like
##   the sea), and draws faint 25 cm cube seams.
## - Holes: inflow = discharge coefficient x area x sqrt(2 g head) (Torricelli), where head =
##   sea height outside (Ocean.get_height) minus the higher of the hole and the water inside.
##   A hole above the sea drains the hold back out. Holes near the waterline only take water
##   when a wave covers them. Spray squares are visual only (the volume goes straight in).
## - The water's volume and centre go to ship_motion.gd (load_offset), so the ship sinks,
##   heels toward the side the water collects on, and trims.

const G := 9.81
const NO_FACE := 1000.0

@export var ocean_path: NodePath = ^"../../Ocean"
@export var ship_path: NodePath = ^"../Brig"
@export var reach := 6.0                  ## how far away you can punch or plug (m)

@export_group("Hold grid")
@export var cell := 0.25                  ## square size (m); also the size of the drawn cubes
@export var grid_bottom := -0.9           ## ship-local height where the scan starts (below the lower deck floor)
@export var grid_top := 1.6               ## ship-local height where it stops (just under the main deck)
@export var grid_half_width := 3.3
@export var grid_z_min := -10.0           ## bow end (ship-local, bow is -Z)
@export var grid_z_max := 9.6
## Only keep spaces with a wall on both sides (drops cells between the hull wall and the
## waterline outline). Turned off automatically if it leaves almost nothing.
@export var require_side_walls := true

@export_group("Flooding")
## Multiplier on the real inflow so tests don't take ten minutes. 1 = real.
@export var flood_speed := 4.0
@export var hole_radius := 0.12           ## m
@export var discharge_coef := 0.6
@export var pump_rate := 0.6              ## m³/s removed with the pumps on
@export var sim_rate := 30.0              ## water updates per second
@export var flow_damping := 0.985         ## lower = water settles faster, less sloshing
@export var min_flow_depth := 0.004       ## thinner films than this stop spreading (m)
@export var draw_every := 2               ## redraw the water every Nth update (it's snapped anyway)

@export_group("Ship response")
@export var waterplane_area := 65.0       ## m²: sinkage = water volume / this
@export var displacement := 180.0         ## m³ of hull underwater when dry
@export var gm_transverse := 1.0          ## m: smaller = heels more from water off to one side
@export var gm_longitudinal := 20.0
@export var max_sink := 3.0
## Overloading: when cargo + hold water make the ship sit this much lower (m), the sea starts coming over the rails
## and floods the lowest part of the hold, and the more it floods the lower she sits. 1.4 m is about 93 tonnes.
@export var cargo_swamp_sink := 1.4
@export var swamp_rate := 0.6             ## m³/s of sea coming aboard per metre past that

@export_group("Look")
@export var deep_color := Color(0.018, 0.07, 0.085)
@export var shallow_color := Color(0.06, 0.26, 0.26)
@export var absorption := 1.1             ## per metre: higher = murkier
@export var spray_color := Color(0.95, 0.97, 0.98)
@export var spray_per_m3 := 160.0         ## spray squares per m³ of inflow
@export var spray_max_rate := 260.0       ## per hole, per second
@export var max_spray := 900

# --- read by the HUD ---
var water_volume := 0.0                   ## m³ in the hold
var pumps_on := false
var last_sim_ms := 0.0
var build_ms := 0.0
var status := ""
var status_time := 0.0
var cargo_kg := 0.0                       ## stowed cargo (set by CargoSystem through set_cargo)
var cargo_cx := 0.0                       ## its centre, ship-local
var cargo_cz := 0.0
var swamping := false                     ## overloaded: the sea is coming over the rails
var _sink_depth := 0.0                    ## m the ship sits lower from cargo + hold water
var _low: Array[int] = []                 ## the lowest spaces of the hold, where swamping water collects

class Hole:
	var pos: Vector3          # ship-local
	var normal: Vector3       # ship-local, pointing into the hold
	var col: int              # the space the water goes into
	var flow := 0.0           # m³/s, negative = draining out
	var speed := 0.0          # jet speed (m/s)
	var submerged := false    # water inside is above the hole
	var acc := 0.0
	var marker: MeshInstance3D

var _rig: Node3D
var _motion: Node
var _ocean: Ocean
var _built := false
var _acc := 0.0
var _draw_tick := 0
var _was_captured := false

# grid: squares (ix, iz) -> list of stacked spaces
var _nx := 0
var _nz := 0
var _sq_start := PackedInt32Array() # per square: first space index (spaces of a square are contiguous)
var _sq_count := PackedInt32Array() # per square: number of spaces
# per space
var _cx := PackedFloat32Array()     # centre x (ship-local)
var _cz := PackedFloat32Array()
var _b := PackedFloat32Array()      # floor height
var _cap := PackedFloat32Array()    # max depth (floor to whatever is overhead)
var _d := PackedFloat32Array()      # water depth
var _h := PackedFloat32Array()      # surface height along gravity, per step
var _shown := PackedFloat32Array()  # drawn water height
# neighbour links (CSR): space i links to _adj[_adj_start[i] .. _adj_start[i + 1] - 1]
var _adj_start := PackedInt32Array()
var _adj := PackedInt32Array()      # neighbouring space
var _adj_dir := PackedByteArray()   # 0 +x, 1 -x, 2 +z, 3 -z
var _adj_rev := PackedInt32Array()  # index of the link back from the neighbour
var _f := PackedFloat32Array()      # outflow along each link (m³/s), kept between steps

var _holes: Array[Hole] = []

# spray squares (ship-local)
var _pc := 0
var _pp := PackedVector3Array()
var _pv := PackedVector3Array()
var _pa := PackedVector3Array()     # spin axis
var _pl := PackedFloat32Array()     # life left
var _ps := PackedFloat32Array()     # size
var _pt := PackedFloat32Array()     # age

var _water_mm: MultiMesh
var _spray_mm: MultiMesh
var _water_buf := PackedFloat32Array()
var _spray_buf := PackedFloat32Array()
var _marker_mat: StandardMaterial3D
var _water_mat: ShaderMaterial
var _debug: MeshInstance3D
var _hb := {}                       # waterline outline (Brig extras), cached

func _ready() -> void:
	_rig = get_parent() as Node3D
	_motion = _rig
	_ocean = get_node_or_null(ocean_path) as Ocean
	if _ocean == null:
		push_warning("ship_flooding: no Ocean at %s; holes won't take water" % ocean_path)
	add_to_group("ship_flooding")
	_hb = _waterline()
	_make_visuals()

func _process(_delta: float) -> void:
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if status_time > 0.0:
		status_time -= _delta
		if status_time <= 0.0:
			status = ""

func _unhandled_input(e: InputEvent) -> void:
	# punching holes, plugging them, the P pump switch and the grid view are test aids: only with the debug screen open (H)
	if not Engine.get_meta("debug_ui", false):
		return
	if e is InputEventMouseButton and e.pressed:
		if not _was_captured:
			return              # this click is the one that recaptures the mouse
		if e.button_index == MOUSE_BUTTON_LEFT:
			_aim(true)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_aim(false)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_P:
			pumps_on = not pumps_on
			_say("pumps on" if pumps_on else "pumps off")
		elif e.physical_keycode == KEY_BACKSPACE:
			reset()
			_say("hold drained, holes removed")
		elif e.physical_keycode == KEY_G:
			show_grid(not (_debug and _debug.visible))

func _physics_process(delta: float) -> void:
	if not _built:
		_built = true
		_build_grid()
		return
	_acc += delta
	var step := 1.0 / sim_rate
	var t0 := Time.get_ticks_usec()
	var stepped := false
	var guard := 0
	while _acc >= step and guard < 4:
		_acc -= step
		guard += 1
		_sim_step(step)
		stepped = true
	if stepped:
		_update_load()
		_draw_tick += 1
		if _draw_tick >= draw_every:
			_draw_tick = 0
			_draw_water()
		last_sim_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_update_spray(delta)

# ---------------------------------------------------------------- public

func reset() -> void:
	_d.fill(0.0)
	_f.fill(0.0)
	for h in _holes:
		if h.marker:
			h.marker.queue_free()
	_holes.clear()
	_pc = 0
	water_volume = 0.0
	_update_load()
	_draw_water()
	_draw_spray()

func hole_count() -> int:
	return _holes.size()

## Number of water spaces in the hold grid.
func column_count() -> int:
	return _d.size()

## World height of the water surface relevant to a world point: the flood water inside
## the hull (below the main deck), the sea everywhere else. -INF if there's no water there
## (for example a dry part of the hold). Used by the player for wading and swimming.
func water_surface_at(p: Vector3) -> float:
	var xf := _rig.global_transform
	var lp := xf.affine_inverse() * p
	if _inside_hull(lp):
		if not _built:
			return -INF
		var si := _space_at(lp)
		if si >= 0 and _d[si] > 0.01:
			return (xf * Vector3(_cx[si], _b[si] + _d[si], _cz[si])).y
		return -INF
	return _ocean.get_height(p.x, p.z) if _ocean else -INF

## True if world point p is inside the hull's outline (where hold water, not the sea, applies).
func is_inside_hull(p: Vector3) -> bool:
	return _inside_hull(_rig.global_transform.affine_inverse() * p)

func _inside_hull(lp: Vector3) -> bool:
	if lp.y < grid_bottom or lp.y > grid_top + 0.1:
		return false
	if _hb.is_empty():
		return absf(lp.x) < grid_half_width and lp.z > grid_z_min and lp.z < grid_z_max
	return absf(lp.x) < _half_beam(_hb, lp.z)

## Show or hide the hold grid: a green tile on the floor of every space water can reach
## (squares with stacked spaces show a tile at each level).
func show_grid(on: bool) -> void:
	if _debug == null:
		_debug = _make_debug_mesh()
		_rig.add_child(_debug)
	_debug.visible = on
	_say("grid view on: %d spaces" % _d.size() if on else "grid view off")

## Punch a hole where the line from -> to (world space) first hits the ship.
func punch_from_ray(from: Vector3, to: Vector3, exclude: Array[RID] = []) -> bool:
	var hit := _world_ray(from, to, 3, exclude)
	if hit.is_empty() or not _is_ship(hit["collider"]):
		_say("no hull there")
		return false
	var inv := _rig.global_transform.affine_inverse()
	var lp: Vector3 = inv * (hit["position"] as Vector3)
	var ln: Vector3 = (_rig.global_transform.basis.inverse() * (hit["normal"] as Vector3)).normalized()
	return punch_hole_local(lp, ln)

## Punch a hole at a ship-local point on the hull (normal = surface normal, either side).
func punch_hole_local(lp: Vector3, ln: Vector3) -> bool:
	var ci := _nearest_space(lp, 1.2)
	if ci < 0:
		_say("too far from the hold")
		return false
	for h in _holes:
		if h.pos.distance_to(lp) < 0.35:
			_say("already holed there")
			return false
	var target := Vector3(_cx[ci], clampf(lp.y, _b[ci], _b[ci] + _cap[ci]), _cz[ci])
	var inward := ln if ln.dot(target - lp) >= 0.0 else -ln
	var h := Hole.new()
	h.pos = lp
	h.normal = inward
	h.col = ci
	h.marker = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(hole_radius * 2.4, hole_radius * 2.4, 0.06)
	h.marker.mesh = bm
	h.marker.material_override = _marker_mat
	h.marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var up := Vector3.UP if absf(inward.y) < 0.9 else Vector3.RIGHT
	h.marker.transform = Transform3D(Basis.looking_at(inward, up), lp)
	_rig.add_child(h.marker)
	_holes.append(h)
	_say("hole punched (%d)" % _holes.size())
	return true

## Plug the hole nearest to where the line from -> to hits the ship.
func plug_from_ray(from: Vector3, to: Vector3, exclude: Array[RID] = []) -> bool:
	var hit := _world_ray(from, to, 3, exclude)
	if hit.is_empty():
		return false
	var lp: Vector3 = _rig.global_transform.affine_inverse() * (hit["position"] as Vector3)
	var best := -1
	var best_d := 0.7
	for i in _holes.size():
		var dd := _holes[i].pos.distance_to(lp)
		if dd < best_d:
			best_d = dd
			best = i
	if best < 0:
		_say("no hole there")
		return false
	if _holes[best].marker:
		_holes[best].marker.queue_free()
	_holes.remove_at(best)
	_say("hole plugged")
	return true

# ---------------------------------------------------------------- input helpers

func _aim(punch: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not _built:
		return
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * reach
	var ex: Array[RID] = []
	var n: Node = cam
	while n:
		if n is CollisionObject3D:
			ex.append((n as CollisionObject3D).get_rid())
		n = n.get_parent()
	if punch:
		punch_from_ray(from, to, ex)
	else:
		plug_from_ray(from, to, ex)

func _say(s: String) -> void:
	status = s
	status_time = 2.5

func _is_ship(o: Object) -> bool:
	return o is Node and _rig.is_ancestor_of(o as Node)

func _world_ray(from: Vector3, to: Vector3, mask: int, exclude: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return get_world_3d().direct_space_state.intersect_ray(q)

# ---------------------------------------------------------------- grid

func _build_grid() -> void:
	var t0 := Time.get_ticks_usec()
	_scan(require_side_walls, 1.0)
	if _cx.size() < 50 and require_side_walls:
		push_warning("ship_flooding: only %d hold spaces found with side walls; scanning again without the wall check (inside 85%% of the waterline beam)" % _cx.size())
		_scan(false, 0.85)
	_link()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	var stacked := 0
	for c in _sq_count:
		if c > 1:
			stacked += 1
	print("ship_flooding: hold grid %d spaces (%d squares with stacked spaces), %d links, built in %.0f ms" % [
		_cx.size(), stacked, _adj.size(), build_ms])

func _scan(walls: bool, beam_scale: float) -> void:
	var space := get_world_3d().direct_space_state
	var xf := _physics_xf()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * cell * 0.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1
	var hb := _waterline()
	_nx = int(ceil(grid_half_width * 2.0 / cell))
	_nz = int(ceil((grid_z_max - grid_z_min) / cell))
	var ny := int(ceil((grid_top - grid_bottom) / cell))
	_sq_start.resize(_nx * _nz)
	_sq_start.fill(0)
	_sq_count.resize(_nx * _nz)
	_sq_count.fill(0)
	var blocked := PackedByteArray()
	blocked.resize(ny)
	var cx := []
	var cz := []
	var cb := []
	var ccap := []
	var side := grid_half_width + 0.5
	for iz in _nz:
		var z := grid_z_min + (iz + 0.5) * cell
		var bound := grid_half_width
		if not hb.is_empty():
			bound = _half_beam(hb, z) * beam_scale
		for ix in _nx:
			var x := -grid_half_width + (ix + 0.5) * cell
			var sq := ix + iz * _nx
			_sq_start[sq] = cx.size()
			if absf(x) > bound - cell * 0.25:
				continue
			for iy in ny:
				var y := grid_bottom + (iy + 0.5) * cell
				q.transform = xf * Transform3D(Basis(), Vector3(x, y, z))
				blocked[iy] = 1 if _hits_ship(space.intersect_shape(q, 6)) else 0
			# every open run of cells that sits on something solid is a space, bottom to top
			var iy := 1
			while iy < ny:
				if blocked[iy] == 1 or blocked[iy - 1] == 0:
					iy += 1
					continue
				var start := iy
				var end := start
				while end + 1 < ny and blocked[end + 1] == 0:
					end += 1
				iy = end + 1
				var cy := grid_bottom + (start + 0.5) * cell
				var b := grid_bottom + start * cell
				var down := _local_ray(space, xf, Vector3(x, cy, z), Vector3(x, cy - cell * 1.5, z))
				if not down.is_empty():
					b = (xf.affine_inverse() * (down["position"] as Vector3)).y
				var top := grid_bottom + (end + 1) * cell
				# must have a wall on both sides (drops cells between the hull wall and the bound).
				# Checked at a few heights: the brig's wall collision doesn't reach the floor everywhere.
				if walls and not _walled(space, xf, x, z, b, top, side):
					continue
				cx.append(x)
				cz.append(z)
				cb.append(b)
				ccap.append(maxf(top - b, 0.05))
				_sq_count[sq] += 1
	var n := cx.size()
	_cx = PackedFloat32Array(cx)
	_cz = PackedFloat32Array(cz)
	_b = PackedFloat32Array(cb)
	_cap = PackedFloat32Array(ccap)
	_d.resize(n)
	_d.fill(0.0)
	_h.resize(n)
	_shown.resize(n)
	_shown.fill(0.0)
	_water_mm.instance_count = maxi(n, 1)
	_water_mm.visible_instance_count = 0
	_water_buf.resize(maxi(n, 1) * 16)
	_water_buf.fill(0.0)
	for k in maxi(n, 1):
		_water_buf[k * 16] = cell
		_water_buf[k * 16 + 10] = cell

## True if rays toward both sides hit the ship at one of a few heights in this space.
func _walled(space: PhysicsDirectSpaceState3D, xf: Transform3D, x: float, z: float, b: float, top: float, side: float) -> bool:
	for dy in [0.15, 0.45, 0.85, 1.3]:
		var ys: float = b + dy
		if ys > top - 0.05:
			break
		if _local_ray(space, xf, Vector3(x, ys, z), Vector3(side, ys, z)).is_empty():
			continue
		if _local_ray(space, xf, Vector3(x, ys, z), Vector3(-side, ys, z)).is_empty():
			continue
		return true
	return false

## Where physics currently has the ship. The ship's collision bodies can trail the visual
## ship by a physics step while it moves, so probing with the rig's own transform would
## shift the whole grid (the floor came out ~10 cm high in calm water, more in a swell).
func _physics_xf() -> Transform3D:
	var body := _find_body(_rig)
	if body == null:
		return _rig.global_transform
	var server_xf: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var rel := _rig.global_transform.affine_inverse() * body.global_transform   # body in rig space
	return server_xf * rel.affine_inverse()

func _find_body(n: Node) -> CollisionObject3D:
	for c in n.get_children():
		if c is CollisionObject3D and ((c as CollisionObject3D).collision_layer & 1) != 0:
			return c as CollisionObject3D
		var r := _find_body(c)
		if r:
			return r
	return null

## Link each space to the spaces in the four neighbouring squares whose open heights overlap.
func _link() -> void:
	var n := _cx.size()
	var starts := PackedInt32Array()
	starts.resize(n + 1)
	var adj := PackedInt32Array()
	var dirs := PackedByteArray()
	var offs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for iz in _nz:
		for ix in _nx:
			var sq := ix + iz * _nx
			for s in _sq_count[sq]:
				var i := _sq_start[sq] + s
				starts[i] = adj.size()
				for dir in 4:
					var o: Vector2i = offs[dir]
					var jx: int = ix + o.x
					var jz: int = iz + o.y
					if jx < 0 or jz < 0 or jx >= _nx or jz >= _nz:
						continue
					var sq2 := jx + jz * _nx
					for t in _sq_count[sq2]:
						var j := _sq_start[sq2] + t
						if _b[j] < _b[i] + _cap[i] and _b[i] < _b[j] + _cap[j]:
							adj.append(j)
							dirs.append(dir)
	starts[n] = adj.size()
	_adj_start = starts
	_adj = adj
	_adj_dir = dirs
	_adj_rev.resize(adj.size())
	for i in n:
		for k in range(starts[i], starts[i + 1]):
			var j := adj[k]
			for r in range(starts[j], starts[j + 1]):
				if adj[r] == i:
					_adj_rev[k] = r
					break
	_f.resize(adj.size())
	_f.fill(0.0)

func _hits_ship(results: Array) -> bool:
	for r in results:
		if _is_ship(r["collider"]):
			return true
	return false

func _local_ray(space: PhysicsDirectSpaceState3D, xf: Transform3D, a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(xf * a, xf * b, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or not _is_ship(hit["collider"]):
		return {}
	return hit

func _waterline() -> Dictionary:
	var ship := get_node_or_null(ship_path)
	return _find_waterline(ship) if ship else {}

func _find_waterline(n: Node) -> Dictionary:
	if n.has_meta("extras"):
		var e = n.get_meta("extras")
		if e is Dictionary and e.has("waterline_half_beam"):
			return e
	for c in n.get_children():
		var r := _find_waterline(c)
		if not r.is_empty():
			return r
	return {}

## Half-beam at the waterline at ship-local z (ship-local z = Blender y).
func _half_beam(ex: Dictionary, z: float) -> float:
	var hb := PackedFloat32Array(ex["waterline_half_beam"])
	var f := (z - float(ex["waterline_y_min"])) / float(ex["waterline_y_step"])
	if f < 0.0 or f > hb.size() - 1:
		return 0.0
	var i := int(floor(f))
	var j := mini(i + 1, hb.size() - 1)
	return lerpf(hb[i], hb[j], f - i)

## The space at a ship-local point, or -1 if it's solid or outside the hold.
func _space_at(p: Vector3) -> int:
	var ix := int(floor((p.x + grid_half_width) / cell))
	var iz := int(floor((p.z - grid_z_min) / cell))
	if ix < 0 or iz < 0 or ix >= _nx or iz >= _nz:
		return -1
	var sq := ix + iz * _nx
	var s0 := _sq_start[sq]
	for s in _sq_count[sq]:
		var i := s0 + s
		if p.y >= _b[i] - 0.05 and p.y <= _b[i] + _cap[i]:
			return i
	return -1

func _nearest_space(lp: Vector3, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist * max_dist
	for i in _cx.size():
		var y := clampf(lp.y, _b[i], _b[i] + _cap[i])
		var dd := Vector3(_cx[i] - lp.x, y - lp.y, _cz[i] - lp.z).length_squared()
		if dd < best_d:
			best_d = dd
			best = i
	return best

# ---------------------------------------------------------------- simulation

func _sim_step(dt: float) -> void:
	var n := _d.size()
	if n == 0:
		return
	var area := cell * cell
	_inflow(dt, area)
	_swamp(dt, area)
	if pumps_on:
		_pump(dt, area)
	if water_volume <= 0.0 and _holes.is_empty():
		return
	# read-only locals (packed arrays are copy-on-write, so only alias ones we don't write)
	var cx := _cx
	var cz := _cz
	var bb := _b
	var cap := _cap
	var adj := _adj
	var st := _adj_start
	var rev := _adj_rev
	var up := (_rig.global_transform.basis.inverse() * Vector3.UP).normalized()
	var ux := up.x
	var uy := up.y
	var uz := up.z
	for i in n:
		_h[i] = ux * cx[i] + uy * (bb[i] + _d[i]) + uz * cz[i]
	var kk := dt * G * cell
	var damp := flow_damping
	var max_scale := area / dt
	# outflows from each wet space along each of its links
	for i in n:
		var s := st[i]
		var e := st[i + 1]
		var di := _d[i]
		if di <= min_flow_depth:
			for k in range(s, e):
				_f[k] = 0.0
			continue
		var hi := _h[i]
		var total := 0.0
		for k in range(s, e):
			var j := adj[k]
			var fl := 0.0
			if _d[j] < cap[j]:
				fl = maxf(0.0, _f[k] * damp + kk * (hi - _h[j]))
			_f[k] = fl
			total += fl
		var maxout := di * max_scale
		if total > maxout:
			var sc := maxout / total
			for k in range(s, e):
				_f[k] *= sc
	# depth change = what flows in from the neighbours - what flows out
	var to_depth := dt / area
	var vol := 0.0
	for i in n:
		var net := 0.0
		for k in range(st[i], st[i + 1]):
			net += _f[rev[k]] - _f[k]
		var di := _d[i]
		if net != 0.0:
			di = clampf(di + net * to_depth, 0.0, cap[i])
			_d[i] = di
		vol += di
	water_volume = vol * area

func _inflow(dt: float, area: float) -> void:
	var xf := _rig.global_transform
	var a := PI * hole_radius * hole_radius
	for h in _holes:
		var wp: Vector3 = xf * h.pos
		var sea := _ocean.get_height(wp.x, wp.z) if _ocean else -1000.0
		var ci := h.col
		var inside_y := (xf * Vector3(_cx[ci], _b[ci] + _d[ci], _cz[ci])).y
		var top := maxf(wp.y, inside_y)
		var qf := 0.0
		if sea > top:
			qf = discharge_coef * a * sqrt(2.0 * G * (sea - top))
		elif inside_y > wp.y and inside_y > sea:
			qf = -discharge_coef * a * sqrt(2.0 * G * (inside_y - maxf(wp.y, sea)))
		qf *= flood_speed
		h.flow = qf
		h.speed = sqrt(2.0 * G * maxf(sea - wp.y, 0.0))
		h.submerged = inside_y > wp.y
		_d[ci] = clampf(_d[ci] + qf * dt / area, 0.0, _cap[ci])

## CargoSystem: how much cargo is stowed and where (kg, ship-local x and z of its centre).
func set_cargo(kg: float, cx: float, cz: float) -> void:
	cargo_kg = kg
	cargo_cx = cx
	cargo_cz = cz

## Overloaded: past cargo_swamp_sink the sea comes over the rails into the lowest part of the hold. That water
## sinks her further, so the more she's overloaded the faster she goes down (down to max_sink, like any flooded hull).
func _swamp(dt: float, area: float) -> void:
	var over := _sink_depth - cargo_swamp_sink
	if over <= 0.0 or _d.is_empty():
		swamping = false
		return
	if not swamping:
		swamping = true
		_say("overloaded: the sea is coming over the rails!")
	if _low.is_empty():
		var lo := INF
		for b in _b:
			lo = minf(lo, b)
		for i in _b.size():
			if _b[i] <= lo + 0.1:
				_low.append(i)
	if _low.is_empty():
		return
	var add := swamp_rate * over * dt / (area * float(_low.size()))
	for i in _low:
		_d[i] = minf(_d[i] + add, _cap[i])

func _pump(dt: float, area: float) -> void:
	var total := 0.0
	for i in _d.size():
		total += _d[i]
	total *= area
	if total <= 0.0:
		return
	var keep := 1.0 - minf(1.0, pump_rate * dt / total)
	for i in _d.size():
		_d[i] *= keep

func _update_load() -> void:
	var area := cell * cell
	var v := 0.0
	var mx := 0.0
	var mz := 0.0
	for i in _d.size():
		var w := _d[i] * area
		v += w
		mx += w * _cx[i]
		mz += w * _cz[i]
	water_volume = v
	# cargo is weight on the hull too: it displaces the same volume of sea as its mass of water would
	var ve := cargo_kg / 1025.0
	mx += ve * cargo_cx
	mz += ve * cargo_cz
	v += ve
	_sink_depth = v / waterplane_area
	var off := Vector3.ZERO
	if v > 0.0001:
		var xc := mx / v
		var zc := mz / v
		off.x = -clampf(v / waterplane_area, 0.0, max_sink)
		# weight at +x pushes +x down (ship_motion: +roll raises +X)
		off.z = clampf(-atan(v * xc / (displacement * gm_transverse)), -0.6, 0.6)
		# weight toward the bow (-z) pushes the bow down (ship_motion: +pitch raises the bow)
		off.y = clampf(atan(v * zc / (displacement * gm_longitudinal)), -0.3, 0.3)
	if _motion and "load_offset" in _motion:
		_motion.set("load_offset", off)

# ---------------------------------------------------------------- drawing

func _make_visuals() -> void:
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = preload("res://shaders/water_cubes.gdshader")
	_water_mat.set_shader_parameter("deep_color", deep_color)
	_water_mat.set_shader_parameter("shallow_color", shallow_color)
	_water_mat.set_shader_parameter("absorption", absorption)
	_water_mat.set_shader_parameter("cell", cell)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = _water_mat
	_water_mm = MultiMesh.new()
	_water_mm.transform_format = MultiMesh.TRANSFORM_3D
	_water_mm.use_custom_data = true
	_water_mm.mesh = box
	var wi := MultiMeshInstance3D.new()
	wi.name = "FloodWater"
	wi.multimesh = _water_mm
	wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child.call_deferred(wi)

	var smat := StandardMaterial3D.new()
	smat.albedo_color = spray_color
	smat.emission_enabled = true
	smat.emission = spray_color
	smat.emission_energy_multiplier = 0.25
	smat.roughness = 0.6
	var sbox := BoxMesh.new()
	sbox.size = Vector3.ONE
	sbox.material = smat
	_spray_mm = MultiMesh.new()
	_spray_mm.transform_format = MultiMesh.TRANSFORM_3D
	_spray_mm.mesh = sbox
	_spray_mm.instance_count = max_spray
	_spray_mm.visible_instance_count = 0
	_spray_buf.resize(max_spray * 12)
	var si := MultiMeshInstance3D.new()
	si.name = "FloodSpray"
	si.multimesh = _spray_mm
	si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child.call_deferred(si)
	_pp.resize(max_spray)
	_pv.resize(max_spray)
	_pa.resize(max_spray)
	_pl.resize(max_spray)
	_ps.resize(max_spray)
	_pt.resize(max_spray)

	_marker_mat = StandardMaterial3D.new()
	_marker_mat.albedo_color = Color(0.05, 0.04, 0.03)
	_marker_mat.roughness = 1.0

## One box per wet space. Custom data = for each side (+x, -x, +z, -z) the height (above this
## box's floor) up to which the neighbour's water or floor covers that side; the shader drops
## that part of the face, so only the outside of the water body is drawn.
func _draw_water() -> void:
	var n := _d.size()
	if n == 0:
		return
	var step := cell * 0.25
	var cap := _cap
	var bb := _b
	var cx := _cx
	var cz := _cz
	for i in n:
		var di := _d[i]
		_shown[i] = clampf(maxf(snappedf(di, step), 0.03), 0.03, cap[i]) if di >= 0.012 else 0.0
	var shown := _shown
	var st := _adj_start
	var adj := _adj
	var dirs := _adj_dir
	var count := 0
	for i in n:
		var hgt := shown[i]
		if hgt <= 0.0:
			continue
		var c0 := NO_FACE
		var c1 := NO_FACE
		var c2 := NO_FACE
		var c3 := NO_FACE
		var seen := 0
		var base := bb[i]
		for k in range(st[i], st[i + 1]):
			var j := adj[k]
			var dir := dirs[k]
			var cover := bb[j] + shown[j] - base
			var bit := 1 << dir
			var first := (seen & bit) == 0
			seen |= bit
			if dir == 0:
				c0 = cover if first else maxf(c0, cover)
			elif dir == 1:
				c1 = cover if first else maxf(c1, cover)
			elif dir == 2:
				c2 = cover if first else maxf(c2, cover)
			else:
				c3 = cover if first else maxf(c3, cover)
		var o := count * 16
		_water_buf[o + 3] = cx[i]
		_water_buf[o + 5] = hgt
		_water_buf[o + 7] = base + hgt * 0.5
		_water_buf[o + 11] = cz[i]
		_water_buf[o + 12] = c0
		_water_buf[o + 13] = c1
		_water_buf[o + 14] = c2
		_water_buf[o + 15] = c3
		count += 1
	_water_mm.buffer = _water_buf
	_water_mm.visible_instance_count = count

func _make_debug_mesh() -> MeshInstance3D:
	if _cx.is_empty():
		return MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs := cell * 0.42
	for i in _cx.size():
		var y := _b[i] + 0.02
		var x := _cx[i]
		var z := _cz[i]
		st.set_color(Color(0.2, 1.0, 0.3, 0.55))
		st.add_vertex(Vector3(x - hs, y, z - hs))
		st.add_vertex(Vector3(x + hs, y, z - hs))
		st.add_vertex(Vector3(x + hs, y, z + hs))
		st.add_vertex(Vector3(x - hs, y, z - hs))
		st.add_vertex(Vector3(x + hs, y, z + hs))
		st.add_vertex(Vector3(x - hs, y, z + hs))
	var mi := MeshInstance3D.new()
	mi.name = "FloodGridView"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _update_spray(dt: float) -> void:
	if _d.is_empty():
		return
	var grav := _rig.global_transform.basis.inverse() * Vector3(0.0, -G, 0.0)
	# spawn
	for h in _holes:
		if h.flow <= 0.0 or h.speed <= 0.05:
			continue
		var rate := clampf(h.flow * spray_per_m3, 0.0, spray_max_rate)
		if h.submerged:
			rate *= 0.15
		h.acc += rate * dt
		var t1 := h.normal.cross(Vector3.UP if absf(h.normal.y) < 0.9 else Vector3.RIGHT).normalized()
		var t2 := h.normal.cross(t1)
		while h.acc >= 1.0:
			h.acc -= 1.0
			if _pc >= max_spray:
				continue
			var k := _pc
			_pc += 1
			var jit := (t1 * randf_range(-1.0, 1.0) + t2 * randf_range(-1.0, 1.0)) * hole_radius * 0.7
			_pp[k] = h.pos + h.normal * 0.1 + jit
			var dir := (h.normal + t1 * randf_range(-0.25, 0.25) + t2 * randf_range(-0.25, 0.25)).normalized()
			_pv[k] = dir * h.speed * randf_range(0.65, 1.05)
			_pa[k] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			_pl[k] = 2.5
			_ps[k] = randf_range(0.06, 0.13)
			_pt[k] = 0.0
	# move, land, die
	var i := 0
	while i < _pc:
		_pv[i] += grav * dt
		_pp[i] += _pv[i] * dt
		_pt[i] += dt
		_pl[i] -= dt
		var p := _pp[i]
		var dead := _pl[i] <= 0.0
		if not dead and _pt[i] > 0.1:
			var si := _space_at(p)
			if si < 0 or p.y <= _b[si] + _d[si]:
				dead = true
		if dead:
			_pc -= 1
			_pp[i] = _pp[_pc]
			_pv[i] = _pv[_pc]
			_pa[i] = _pa[_pc]
			_pl[i] = _pl[_pc]
			_ps[i] = _ps[_pc]
			_pt[i] = _pt[_pc]
		else:
			i += 1
	_draw_spray()

func _draw_spray() -> void:
	for i in _pc:
		var s := _ps[i] * clampf(_pl[i] / 0.3, 0.0, 1.0)
		var bs := Basis(_pa[i], _pt[i] * 9.0).scaled(Vector3(s, s, s))
		var p := _pp[i]
		var o := i * 12
		_spray_buf[o] = bs.x.x
		_spray_buf[o + 1] = bs.y.x
		_spray_buf[o + 2] = bs.z.x
		_spray_buf[o + 3] = p.x
		_spray_buf[o + 4] = bs.x.y
		_spray_buf[o + 5] = bs.y.y
		_spray_buf[o + 6] = bs.z.y
		_spray_buf[o + 7] = p.y
		_spray_buf[o + 8] = bs.x.z
		_spray_buf[o + 9] = bs.y.z
		_spray_buf[o + 10] = bs.z.z
		_spray_buf[o + 11] = p.z
	_spray_mm.buffer = _spray_buf
	_spray_mm.visible_instance_count = _pc

# ---------------------------------------------------------------- cargo (cargo_system.gd)
# The cargo lattice is this same hold grid (cell squares in x and z) with the layers stacked up from the
# main hold floor. These read-only helpers tell it where there is open space.

var _cargo_floor_y := NAN

## True once the hold grid has been scanned.
func cargo_ready() -> bool:
	return _built and not _cx.is_empty()

## Ship-local height of the main hold floor: the most common space floor (2 cm bins). Layer 0 of the cargo lattice
## starts here.
func cargo_floor_y() -> float:
	if is_nan(_cargo_floor_y):
		var bins := {}
		var best_n := 0
		var best_y := grid_bottom
		for i in _b.size():
			var k := int(round(_b[i] / 0.02))
			var n: int = int(bins.get(k, 0)) + 1
			bins[k] = n
			if n > best_n:
				best_n = n
				best_y = k * 0.02
		_cargo_floor_y = best_y
	return _cargo_floor_y

## Vector2(floor, ceiling) (ship-local heights) of the open space holding ship-local point p, or
## Vector2(INF, INF) if p is solid or outside the hold.
func cargo_range_at(p: Vector3) -> Vector2:
	var si := _space_at(p)
	if si < 0:
		return Vector2(INF, INF)
	return Vector2(_b[si], _b[si] + _cap[si])
