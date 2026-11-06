class_name ShipDeckPatch
extends Node3D
## Closes holes in the fore deck (the gap by the anchor spools you could fall through).
##
## A few physics frames after the ship appears, this probes the deck collision (layer 1) with rays straight down over the
## fore part of the ship, in a grid. Any run of grid squares that has no deck under it but is ringed all the way round by
## deck is a hole; small ones (up to max_hole_m2) get a thin floor box at the height of the deck around them, in a
## body that rides on the ship like the rest of the deck. Big enclosed openings (hatches, stair wells) are left alone.
## The holes it found/filled are printed once to the log as "ShipDeckPatch: ...".
## Real fix, when you have Blender open: close the gap in the Col_ deck mesh, rebuild and copy Brig.glb.

@export var enabled := true
## Area probed, ship-local metres. Bow is -Z.
@export var x_range := Vector2(-3.6, 3.6)
@export var z_range := Vector2(-10.5, -2.0)
@export var step := 0.2
## Rays start this high above the ship's origin and end this far below it.
@export var ray_top := 10.0
@export var ray_bottom := -1.0
## Biggest enclosed hole (m2) that gets filled.
@export var max_hole_m2 := 4.0
@export var floor_thickness := 0.25
## Grow each filled hole by this much (m) so its edges overlap the deck.
@export var overlap := 0.1
@export var debug_draw := false

var _frames := 0
var _done := false

func _physics_process(_delta: float) -> void:
	if not enabled or _done:
		return
	_frames += 1
	if _frames < 4:
		return
	_done = true
	_scan()

func _scan() -> void:
	var ship := get_parent() as Node3D
	if ship == null:
		return
	var space := ship.get_world_3d().direct_space_state
	var nx := int(ceil((x_range.y - x_range.x) / step))
	var nz := int(ceil((z_range.y - z_range.x) / step))
	var h := PackedFloat32Array()
	h.resize(nx * nz)
	var has := PackedByteArray()
	has.resize(nx * nz)
	var up := ship.global_transform.basis.y.normalized()
	var any := 0
	for j in nz:
		for i in nx:
			var lx := x_range.x + (float(i) + 0.5) * step
			var lz := z_range.x + (float(j) + 0.5) * step
			var from := ship.to_global(Vector3(lx, ray_top, lz))
			var to := ship.to_global(Vector3(lx, ray_bottom, lz))
			var q := PhysicsRayQueryParameters3D.create(from, to, 1)
			q.collide_with_areas = false
			q.hit_from_inside = false
			var excl: Array[RID] = []
			var y := NAN
			for _k in 6:
				q.exclude = excl
				var r := space.intersect_ray(q)
				if r.is_empty():
					break
				var col = r["collider"]
				if col is CollisionObject3D and ship.is_ancestor_of(col):
					if (r["normal"] as Vector3).dot(up) > 0.5:
						y = ship.to_local(r["position"]).y
						break
				excl.append(r["rid"])
			var idx := j * nx + i
			if not is_nan(y):
				h[idx] = y
				has[idx] = 1
				any += 1
	if any == 0:
		print("ShipDeckPatch: no deck collision found under the probe area, nothing done")
		return
	# flood the empty squares; a region that never reaches the edge of the grid is enclosed by deck
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var filled := 0
	var skipped := 0
	for j0 in nz:
		for i0 in nx:
			var s0 := j0 * nx + i0
			if has[s0] == 1 or seen[s0] == 1:
				continue
			var cells: Array[int] = []
			var stack: Array[int] = [s0]
			seen[s0] = 1
			var touches_edge := false
			var ring: Array[float] = []
			while not stack.is_empty():
				var c: int = stack.pop_back()
				cells.append(c)
				var ci := c % nx
				var cj := c / nx
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var ni: int = ci + d.x
					var nj: int = cj + d.y
					if ni < 0 or nj < 0 or ni >= nx or nj >= nz:
						touches_edge = true
						continue
					var n := nj * nx + ni
					if has[n] == 1:
						ring.append(h[n])
					elif seen[n] == 0:
						seen[n] = 1
						stack.append(n)
			if touches_edge:
				continue
			var area := float(cells.size()) * step * step
			var mn := Vector2(1e9, 1e9)
			var mx := Vector2(-1e9, -1e9)
			for c in cells:
				var p := Vector2(x_range.x + (float(c % nx) + 0.5) * step, z_range.x + (float(c / nx) + 0.5) * step)
				mn = mn.min(p)
				mx = mx.max(p)
			ring.sort()
			var level: float = ring[ring.size() / 2] if not ring.is_empty() else 0.0
			if area > max_hole_m2 or ring.is_empty():
				skipped += 1
				print("ShipDeckPatch: left a %.1f m2 opening alone at x %.1f..%.1f z %.1f..%.1f (deck about y %.2f)" % [area, mn.x, mx.x, mn.y, mx.y, level])
				continue
			_add_floor(ship, Vector3((mn.x + mx.x) * 0.5, level - floor_thickness * 0.5, (mn.y + mx.y) * 0.5),
				Vector3(mx.x - mn.x + step + overlap * 2.0, floor_thickness, mx.y - mn.y + step + overlap * 2.0))
			filled += 1
			print("ShipDeckPatch: filled a %.1f m2 hole at x %.1f..%.1f z %.1f..%.1f (deck about y %.2f)" % [area, mn.x, mx.x, mn.y, mx.y, level])
	print("ShipDeckPatch: probed %d squares, %d with deck, filled %d hole(s), left %d alone" % [nx * nz, any, filled, skipped])

func _add_floor(ship: Node3D, centre: Vector3, size: Vector3) -> void:
	var body := ship.get_node_or_null("DeckPatchBody") as AnimatableBody3D
	if body == null:
		body = AnimatableBody3D.new()
		body.name = "DeckPatchBody"
		body.sync_to_physics = false
		body.collision_layer = 1
		body.collision_mask = 0
		ship.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = centre
	body.add_child(cs)
	if debug_draw:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position = centre
		body.add_child(mi)
