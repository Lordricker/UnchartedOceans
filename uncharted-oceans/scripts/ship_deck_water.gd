class_name ShipDeckWater
extends Node3D
## Water on the deck: a second grid like the hold's (ship_flooding.gd), on the same 25 cm squares, laid over the main deck.
##
## - The sea comes aboard over the rails. Along the whole edge of the deck each edge square has a rail height (found by
##   probing the ship's collision), and where the sea outside is higher than the rail (the ship rolls, pitches, sits
##   low, or a wave breaks over her) it pours in like water over a weir: flow ~ length x head^1.5. Small freeing ports
##   and scuppers at deck level let the deck drain back out (and the sea in, when the deck dips under) by the head across
##   them, and water piled above the rail spills out over it.
## - On the deck the water is the same pipe model as the hold: a depth per square, moved between neighbours by the
##   difference in surface height along real gravity, so it runs to the low side when she rolls and sloshes back.
## - The squares that lie over the opening of the stair hatch (no deck under them, open straight down into the hold) are
##   marked as DROP squares. Whatever water reaches one falls into the hold space below it (ShipFlooding.hold_add_volume),
##   which spreads it through the hold, so a flooded deck fills the hold through the hatch. If the hold space is full the
##   water stays on the deck.
## - Drawn as one box per wet square (water_cubes.gdshader, like the hold). The water's weight goes to ShipFlooding, which
##   passes it to the ship's sinking and heel.
##
## Made by ship_motion.gd (deck_water_enabled), a child of the ship rig. In game, with the debug screen open (H), G shows
## the grids: green = the hold, cyan = the deck, orange = the squares that drop into the hold. J puts 15 cm of water on the
## whole deck (a test aid) so you can watch it drain.

const G := 9.81
const NO_FACE := 1000.0

@export var enabled := true

@export_group("Grid")
@export var scan_bottom := 1.3            ## ship-local height where the deck scan starts
@export var scan_top := 3.5               ## ... and where it stops
## A deck square's floor must lie between these (the main deck and the cabin floor). A floor higher than that (the top of a
## gun, a rail) is not deck.
@export var floor_min := 1.5
@export var floor_max := 2.4
@export var max_depth := 1.1              ## deepest water away from the rails (m)
## Water can stand this far above the rail top before it spills over (it needs a little head to spill).
@export var spill_margin := 0.35

@export_group("Water")
## Multiplier on the sea coming aboard (1 = as it is; raise it to test).
@export var inflow_scale := 1.0
@export var weir_coef := 1.6              ## water over a rail: flow = coef x length x head^1.5
@export var port_area_per_m := 0.07       ## m² of freeing ports and scuppers per metre of rail
@export var discharge_coef := 0.6
@export var sim_rate := 20.0              ## water updates a second (only while there is water, or the sea is near the deck)
@export var flow_damping := 0.985
@export var min_flow_depth := 0.004       ## thinner films than this stop spreading (m)
@export var draw_every := 2               ## redraw the water every Nth update
@export var sea_node_spacing := 1.0       ## the sea is sampled every this many metres along the rails

@export_group("Look")
@export var drop_color := Color(1.0, 0.55, 0.1, 0.75)
@export var deck_color := Color(0.2, 0.75, 1.0, 0.5)

# --- read by others ---
var active := false                       ## the grid is built and running
var water_volume := 0.0                   ## m³ on the deck
var centre_x := 0.0                       ## ship-local centre of that water
var centre_z := 0.0
var drained_to_hold := 0.0                ## m³ that has fallen down the hatch since the last reset
var rail_inflow := 0.0                    ## m³/s coming aboard over the rails and through the ports right now

var _rig: Node3D
var _flood: ShipFlooding
var _ocean: Ocean
var _built := false
var _acc := 0.0
var _node_t := 0.0
var _draw_tick := 0
var _maybe_inflow := false
var _was_wet := false

var _cell := 0.25
var _nx := 0
var _nz := 0
var _gx0 := 0.0
var _gz0 := 0.0
var _sq := PackedInt32Array()             # per square: its deck cell, or -1
# per cell
var _cx := PackedFloat32Array()
var _cz := PackedFloat32Array()
var _b := PackedFloat32Array()            # floor height (ship-local)
var _cap := PackedFloat32Array()          # deepest the water can stand
var _d := PackedFloat32Array()            # water depth
var _h := PackedFloat32Array()            # surface height along gravity, per step
var _shown := PackedFloat32Array()
var _hold := PackedInt32Array()           # drop squares: the hold space below, else -1
var _drops := PackedInt32Array()          # the cells that drop into the hold
var _nb := PackedInt32Array()             # 4 neighbours per cell (0 +x, 1 -x, 2 +z, 3 -z): cell index or -1
var _f := PackedFloat32Array()            # outflow along each of those links (m³/s)
var _wet := PackedInt32Array()
# rail edge records: a cell that has the outside beyond it
var _e_cell := PackedInt32Array()
var _e_nx := PackedFloat32Array()         # outward direction (ship-local x, z)
var _e_nz := PackedFloat32Array()
var _e_rail := PackedFloat32Array()       # ship-local height of the rail top (floor + 2 cm where there is none)
var _e_node := PackedInt32Array()         # which sea sample it reads
# sea samples just outside the rails
var _node_x := PackedFloat32Array()
var _node_z := PackedFloat32Array()
var _node_sea := PackedFloat32Array()     # world height of the sea there, refreshed 15 times a second

var _mm: MultiMesh
var _buf := PackedFloat32Array()
var _debug: MeshInstance3D

func _ready() -> void:
	_rig = get_parent() as Node3D
	add_to_group("ship_deck_water")
	_flood = get_tree().get_first_node_in_group("ship_flooding") as ShipFlooding
	if _flood == null or _rig == null:
		push_warning("ship_deck_water: no ShipFlooding next to the ship, so there is no deck water")
		set_physics_process(false)
		return
	_ocean = _flood._ocean
	_make_visuals()

func _make_visuals() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/water_cubes.gdshader")
	mat.set_shader_parameter("deep_color", _flood.deep_color)
	mat.set_shader_parameter("shallow_color", _flood.shallow_color)
	mat.set_shader_parameter("absorption", _flood.absorption)
	mat.set_shader_parameter("cell", _flood.cell)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = box
	var mi := MultiMeshInstance3D.new()
	mi.name = "DeckWater"
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ---------------------------------------------------------------- public

## Drain the deck.
func reset() -> void:
	_d.fill(0.0)
	_f.fill(0.0)
	water_volume = 0.0
	drained_to_hold = 0.0
	rail_inflow = 0.0
	if _built:
		_draw_water()

## World height of the water standing on the deck at world point p, or -INF if there is none there (not over the deck,
## dry, or p is well above it). ShipFlooding.water_surface_at asks this first, so the player wades through deck water.
func surface_at(p: Vector3) -> float:
	if not active or water_volume <= 0.0001:
		return -INF
	var xf := _rig.global_transform
	var lp := xf.affine_inverse() * p
	var ix := int(floor((lp.x - _gx0) / _cell))
	var iz := int(floor((lp.z - _gz0) / _cell))
	if ix < 0 or iz < 0 or ix >= _nx or iz >= _nz:
		return -INF
	var i := _sq[ix + iz * _nx]
	if i < 0 or _d[i] < 0.012:
		return -INF
	if lp.y < _b[i] - 0.3 or lp.y > _b[i] + 3.0:
		return -INF
	return (xf * Vector3(lp.x, _b[i] + _d[i], lp.z)).y

## Show or hide the deck grid: a cyan tile on every deck square, orange where it drops into the hold.
func show_grid(on: bool) -> void:
	if not _built:
		return
	if _debug == null:
		_debug = _make_debug_mesh()
		add_child(_debug)
	_debug.visible = on

# ---------------------------------------------------------------- per frame

## Test aid, only with the debug screen open (H): J puts 15 cm of water on the whole deck, to watch it run off the sides
## through the freeing ports and drop down the hatch into the hold.
func _unhandled_input(e: InputEvent) -> void:
	if not active or not Engine.get_meta("debug_ui", false):
		return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_J:
		for i in _d.size():
			_d[i] = minf(0.15, _cap[i])
		_measure(_cell * _cell)
		_draw_water()

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if not _built:
		if _flood.cargo_ready():          # the hold grid has been scanned, so physics is up
			_built = true
			_build()
		return
	if not active:
		return
	_node_t -= delta
	if _node_t <= 0.0:
		_node_t = 1.0 / 15.0
		_update_nodes()
	if water_volume <= 0.00001 and not _maybe_inflow:
		# nothing on the deck and the sea is nowhere near it: nothing to work out
		_acc = 0.0
		rail_inflow = 0.0
		if _was_wet:
			_was_wet = false
			_draw_water()
		return
	_was_wet = true
	_acc += delta
	var step := 1.0 / sim_rate
	var guard := 0
	while _acc >= step and guard < 3:
		_acc -= step
		guard += 1
		_sim_step(step)
	if guard > 0:
		_draw_tick += guard
		if _draw_tick >= draw_every:
			_draw_tick = 0
			_draw_water()

# ---------------------------------------------------------------- building the grid

func _build() -> void:
	var t0 := Time.get_ticks_usec()
	var fl := _flood
	_cell = fl.cell
	_nx = fl._nx
	_nz = fl._nz
	_gx0 = -fl.grid_half_width
	_gz0 = fl.grid_z_min
	var space := get_world_3d().direct_space_state
	var xf: Transform3D = fl._physics_xf()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * _cell * 0.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1
	var ny := int(ceil((scan_top - scan_bottom) / _cell))
	var blocked := PackedByteArray()
	blocked.resize(ny)
	_sq.resize(_nx * _nz)
	_sq.fill(-1)
	var cx := []
	var cz := []
	var cb := []
	var ccap := []
	var chold := []
	# 1. the deck: for every square, the lowest open run that sits on something solid with its floor in the deck band
	for iz in _nz:
		var z := _gz0 + (iz + 0.5) * _cell
		for ix in _nx:
			var x := _gx0 + (ix + 0.5) * _cell
			for iy in ny:
				q.transform = xf * Transform3D(Basis(), Vector3(x, scan_bottom + (iy + 0.5) * _cell, z))
				blocked[iy] = 1 if fl._hits_ship(space.intersect_shape(q, 6)) else 0
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
				var cy := scan_bottom + (start + 0.5) * _cell
				var b := scan_bottom + start * _cell
				var down := fl._local_ray(space, xf, Vector3(x, cy, z), Vector3(x, cy - _cell * 1.5, z))
				if not down.is_empty():
					b = (xf.affine_inverse() * (down["position"] as Vector3)).y
				if b < floor_min or b > floor_max:
					continue
				if not _supported(space, xf, x, z, b):
					continue          # the top of a thin wall or a rail, not deck
				var top := scan_bottom + (end + 1) * _cell
				_sq[ix + iz * _nx] = cx.size()
				cx.append(x)
				cz.append(z)
				cb.append(b)
				ccap.append(minf(maxf(top - b, 0.05), max_depth))
				chold.append(-1)
				break                     # one deck level to a square
	var n_deck := cx.size()
	if n_deck == 0:
		push_warning("ship_deck_water: found no deck squares (floor between %.2f and %.2f m); no deck water" % [floor_min, floor_max])
		return
	var ref_floor := 0.0
	for b in cb:
		ref_floor += float(b)
	ref_floor /= float(n_deck)
	# 2. the squares over the stair hatch: no deck under them, and the hold below is open all the way up to where the deck
	# should be. They only count inside the deck (deck squares to both sides in the same row).
	var drop_cells := []
	for iz in _nz:
		var z := _gz0 + (iz + 0.5) * _cell
		for ix in _nx:
			if _sq[ix + iz * _nx] >= 0:
				continue
			var x := _gx0 + (ix + 0.5) * _cell
			var hs := fl.top_space_at(x, z)
			if hs < 0 or not _deck_both_sides(ix, iz):
				continue
			_sq[ix + iz * _nx] = cx.size()
			drop_cells.append(cx.size())
			cx.append(x)
			cz.append(z)
			cb.append(ref_floor)
			ccap.append(max_depth)
			chold.append(hs)
	var n := cx.size()
	_cx = PackedFloat32Array(cx)
	_cz = PackedFloat32Array(cz)
	_b = PackedFloat32Array(cb)
	_cap = PackedFloat32Array(ccap)
	_hold = PackedInt32Array(chold)
	_drops = PackedInt32Array(drop_cells)
	_d.resize(n)
	_d.fill(0.0)
	_h.resize(n)
	_h.fill(0.0)
	_shown.resize(n)
	_shown.fill(0.0)
	# 3. neighbours
	_nb.resize(n * 4)
	_nb.fill(-1)
	_f.resize(n * 4)
	_f.fill(0.0)
	var offs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for iz in _nz:
		for ix in _nx:
			var i := _sq[ix + iz * _nx]
			if i < 0:
				continue
			for dir in 4:
				var o: Vector2i = offs[dir]
				var jx: int = ix + o.x
				var jz: int = iz + o.y
				if jx >= 0 and jz >= 0 and jx < _nx and jz < _nz:
					_nb[i * 4 + dir] = _sq[jx + jz * _nx]
	# a drop square's floor sits just under its deck neighbours' (so water runs in)
	for i in _drops:
		var lowest := INF
		for dir in 4:
			var j := _nb[i * 4 + dir]
			if j >= 0 and j < n_deck:
				lowest = minf(lowest, _b[j])
		_b[i] = (lowest if lowest < INF else ref_floor) - 0.02
	# 4. the rails: the first and last square of each row and column is an edge. The rail top is found by probing the
	# collision just outside it (the bulwark's top; no hit = no rail there, like the entry ports).
	_e_cell.clear()
	_e_nx.clear()
	_e_nz.clear()
	_e_rail.clear()
	_e_node.clear()
	_node_x.clear()
	_node_z.clear()
	var node_key := {}
	var with_rail := 0
	var rail_lo := INF
	var rail_hi := -INF
	var edge_list := []
	for iz in _nz:
		var lo := -1
		var hi := -1
		for ix in _nx:
			var i := _sq[ix + iz * _nx]
			if i >= 0 and i < n_deck:
				if lo < 0:
					lo = ix
				hi = ix
		if lo >= 0:
			edge_list.append([_sq[lo + iz * _nx], -1.0, 0.0])
			edge_list.append([_sq[hi + iz * _nx], 1.0, 0.0])
	for ix in _nx:
		var lo := -1
		var hi := -1
		for iz in _nz:
			var i := _sq[ix + iz * _nx]
			if i >= 0 and i < n_deck:
				if lo < 0:
					lo = iz
				hi = iz
		if lo >= 0:
			edge_list.append([_sq[ix + lo * _nx], 0.0, -1.0])
			edge_list.append([_sq[ix + hi * _nx], 0.0, 1.0])
	for e in edge_list:
		var i: int = e[0]
		var enx: float = e[1]
		var enz: float = e[2]
		var rail := -INF
		for k in [0.5, 0.9, 1.3, 1.7]:
			var ox: float = _cx[i] + enx * _cell * float(k)
			var oz: float = _cz[i] + enz * _cell * float(k)
			var hit := fl._local_ray(space, xf, Vector3(ox, 5.0, oz), Vector3(ox, _b[i] - 0.2, oz))
			if not hit.is_empty():
				rail = maxf(rail, (xf.affine_inverse() * (hit["position"] as Vector3)).y)
		if rail < _b[i] + 0.08:
			rail = _b[i] + 0.02       # no rail here: the deck is open to the sea
		else:
			with_rail += 1
			rail_lo = minf(rail_lo, rail)
			rail_hi = maxf(rail_hi, rail)
		_cap[i] = minf(_cap[i], maxf(rail - _b[i], 0.05) + spill_margin)
		# the sea is sampled just outside the rail, every sea_node_spacing metres
		var px: float = _cx[i] + enx * (_cell * 0.5 + 0.5)
		var pz: float = _cz[i] + enz * (_cell * 0.5 + 0.5)
		var key := Vector2i(roundi(px / sea_node_spacing), roundi(pz / sea_node_spacing))
		if not node_key.has(key):
			node_key[key] = _node_x.size()
			_node_x.append(px)
			_node_z.append(pz)
		_e_cell.append(i)
		_e_nx.append(enx)
		_e_nz.append(enz)
		_e_rail.append(rail)
		_e_node.append(int(node_key[key]))
	_node_sea.resize(_node_x.size())
	_node_sea.fill(-1000.0)
	# the drawing
	_mm.instance_count = maxi(n, 1)
	_mm.visible_instance_count = 0
	_buf.resize(maxi(n, 1) * 16)
	_buf.fill(0.0)
	for k in maxi(n, 1):
		_buf[k * 16] = _cell
		_buf[k * 16 + 10] = _cell
	active = true
	print("ship_deck_water: deck grid %d squares + %d that drop into the hold, %d rail edges (%d with a rail, tops %.2f to %.2f m), %d sea samples, built in %.0f ms" % [
		n_deck, _drops.size(), _e_cell.size(), with_rail, rail_lo if with_rail > 0 else 0.0, rail_hi if with_rail > 0 else 0.0,
		_node_x.size(), (Time.get_ticks_usec() - t0) / 1000.0])

## True if the four rays straight down from just around (x, z) all hit the ship: a real stretch of deck, not the top of a
## thin wall.
func _supported(space: PhysicsDirectSpaceState3D, xf: Transform3D, x: float, z: float, b: float) -> bool:
	for o in [Vector2(0.1, 0.1), Vector2(-0.1, 0.1), Vector2(0.1, -0.1), Vector2(-0.1, -0.1)]:
		var ox: float = x + o.x
		var oz: float = z + o.y
		if _flood._local_ray(space, xf, Vector3(ox, b + 0.12, oz), Vector3(ox, b - 0.2, oz)).is_empty():
			return false
	return true

## Is there a deck square somewhere to the left and somewhere to the right of square (ix, iz) in its row?
func _deck_both_sides(ix: int, iz: int) -> bool:
	var left := false
	var right := false
	for jx in range(0, ix):
		if _sq[jx + iz * _nx] >= 0:
			left = true
			break
	for jx in range(ix + 1, _nx):
		if _sq[jx + iz * _nx] >= 0:
			right = true
			break
	return left and right

# ---------------------------------------------------------------- simulation

## The sea just outside the rails, 15 times a second (only a few dozen samples), and whether it is anywhere near the deck.
func _update_nodes() -> void:
	var xf := _rig.global_transform
	for k in _node_x.size():
		var wp := xf * Vector3(_node_x[k], 0.0, _node_z[k])
		_node_sea[k] = _ocean.get_height(wp.x, wp.z) if _ocean else -1000.0
	var oy := xf.origin.y
	var bx := xf.basis.x.y
	var by := xf.basis.y.y
	var bz := xf.basis.z.y
	_maybe_inflow = false
	for k in _e_cell.size():
		var i := _e_cell[k]
		var floor_w := oy + bx * _cx[i] + by * _b[i] + bz * _cz[i]
		if _node_sea[_e_node[k]] > floor_w - 0.02:
			_maybe_inflow = true
			break

func _sim_step(dt: float) -> void:
	var area := _cell * _cell
	_edges(dt, area)
	_flow(dt, area)
	_drop(area)
	_measure(area)

## The sea against each edge square: over the rail like a weir, through the freeing ports by the head across them.
func _edges(dt: float, area: float) -> void:
	var xf := _rig.global_transform
	var oy := xf.origin.y
	var bx := xf.basis.x.y
	var by := xf.basis.y.y
	var bz := xf.basis.z.y
	var port_a := port_area_per_m * _cell
	var total := 0.0
	for k in _e_cell.size():
		var i := _e_cell[k]
		var sea := _node_sea[_e_node[k]]
		var lx := _cx[i] + _e_nx[k] * _cell * 0.5
		var lz := _cz[i] + _e_nz[k] * _cell * 0.5
		var base := oy + bx * lx + bz * lz
		var rail_w := base + by * _e_rail[k]
		var floor_w := base + by * _b[i]
		var surf_w := base + by * (_b[i] + _d[i])
		var q := 0.0
		var crest := maxf(rail_w, surf_w)
		if sea > crest:
			q += weir_coef * _cell * pow(sea - crest, 1.5)                    # the sea over the rail
		elif surf_w > rail_w and surf_w > sea:
			q -= weir_coef * _cell * pow(surf_w - maxf(rail_w, sea), 1.5)     # water piled above the rail spills out
		var inside := maxf(surf_w, floor_w)
		var outside := maxf(sea, floor_w)
		var dh := outside - inside
		if dh > 0.0:
			q += discharge_coef * port_a * sqrt(2.0 * G * dh)                 # in through the ports
		elif dh < 0.0:
			q -= discharge_coef * port_a * sqrt(2.0 * G * (-dh))              # out through the ports
		if q > 0.0:
			q *= inflow_scale
			total += q
		_d[i] = clampf(_d[i] + q * dt / area, 0.0, _cap[i])
	rail_inflow = total

## The pipe model over the deck (as the hold's, with one square on top of another never happening here).
func _flow(dt: float, area: float) -> void:
	var n := _d.size()
	var up := (_rig.global_transform.basis.inverse() * Vector3.UP).normalized()
	for i in n:
		_h[i] = up.x * _cx[i] + up.y * (_b[i] + _d[i]) + up.z * _cz[i]
	var kk := dt * G * _cell
	var max_scale := area / dt
	_wet.clear()
	for i in n:
		var o := i * 4
		var di := _d[i]
		if di <= min_flow_depth:
			_f[o] = 0.0
			_f[o + 1] = 0.0
			_f[o + 2] = 0.0
			_f[o + 3] = 0.0
			continue
		_wet.append(i)
		var hi := _h[i]
		var total := 0.0
		for dir in 4:
			var j := _nb[o + dir]
			var fl := 0.0
			if j >= 0 and _d[j] < _cap[j]:
				fl = maxf(0.0, _f[o + dir] * flow_damping + kk * (hi - _h[j]))
			_f[o + dir] = fl
			total += fl
		var maxout := di * max_scale
		if total > maxout:
			var sc := maxout / total
			for dir in 4:
				_f[o + dir] *= sc
	var to_depth := dt / area
	for i in _wet:
		var o := i * 4
		for dir in 4:
			var fl := _f[o + dir]
			if fl > 0.0:
				var j := _nb[o + dir]
				_d[i] = maxf(_d[i] - fl * to_depth, 0.0)
				_d[j] = minf(_d[j] + fl * to_depth, _cap[j])

## The squares over the hatch: what has reached them falls into the hold space below (as much as that has room for).
func _drop(area: float) -> void:
	for i in _drops:
		var di := _d[i]
		if di <= 0.0005:
			continue
		var taken := _flood.hold_add_volume(_hold[i], di * area)
		if taken > 0.0:
			_d[i] = maxf(di - taken / area, 0.0)
			drained_to_hold += taken

func _measure(area: float) -> void:
	var v := 0.0
	var mx := 0.0
	var mz := 0.0
	for i in _d.size():
		var di := _d[i]
		if di > 0.0:
			var w := di * area
			v += w
			mx += w * _cx[i]
			mz += w * _cz[i]
	water_volume = v
	if v > 0.0:
		centre_x = mx / v
		centre_z = mz / v

# ---------------------------------------------------------------- drawing

## One box per wet square. Custom data = for each side (+x, -x, +z, -z) the height (above this box's floor) up to which the
## neighbour's water or floor covers that side; the shader drops that part of the face, so only the outside of the water
## body is drawn (the same as the hold's water).
func _draw_water() -> void:
	var n := _d.size()
	if n == 0:
		return
	var step := _cell * 0.25
	for i in n:
		var di := _d[i]
		_shown[i] = clampf(maxf(snappedf(di, step), 0.03), 0.03, _cap[i]) if di >= 0.012 else 0.0
	var count := 0
	for i in n:
		var hgt := _shown[i]
		if hgt <= 0.0:
			continue
		var base := _b[i]
		var c0 := NO_FACE
		var c1 := NO_FACE
		var c2 := NO_FACE
		var c3 := NO_FACE
		for dir in 4:
			var j := _nb[i * 4 + dir]
			if j < 0:
				continue
			var cover := _b[j] + _shown[j] - base
			if dir == 0:
				c0 = cover
			elif dir == 1:
				c1 = cover
			elif dir == 2:
				c2 = cover
			else:
				c3 = cover
		var o := count * 16
		_buf[o + 3] = _cx[i]
		_buf[o + 5] = hgt
		_buf[o + 7] = base + hgt * 0.5
		_buf[o + 11] = _cz[i]
		_buf[o + 12] = c0
		_buf[o + 13] = c1
		_buf[o + 14] = c2
		_buf[o + 15] = c3
		count += 1
	_mm.buffer = _buf
	_mm.visible_instance_count = count

func _make_debug_mesh() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs := _cell * 0.42
	var dropset := {}
	for i in _drops:
		dropset[i] = true
	for i in _cx.size():
		var y := _b[i] + 0.03
		var x := _cx[i]
		var z := _cz[i]
		st.set_color(drop_color if dropset.has(i) else deck_color)
		st.add_vertex(Vector3(x - hs, y, z - hs))
		st.add_vertex(Vector3(x + hs, y, z - hs))
		st.add_vertex(Vector3(x + hs, y, z + hs))
		st.add_vertex(Vector3(x - hs, y, z - hs))
		st.add_vertex(Vector3(x + hs, y, z + hs))
		st.add_vertex(Vector3(x - hs, y, z + hs))
	var mi := MeshInstance3D.new()
	mi.name = "DeckGridView"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
