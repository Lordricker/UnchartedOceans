extends RefCounted
## Joins a port's land to the world's generated land (bug reports 2026-11-19: the tutorial town floated in the sea
## as a green slab with vertical sides; the capitals floated in open water).
##
## Built when the port scene loads, from the port's own ground meshes: a grid in the port's frame (u = port-local x,
## v = port-local z, +v = out to sea) that the macro ground is blended with:
##  - inside the ground's footprint the terrain sits under_m below the port's ground (0 for a small port, whose own
##    grass plate is then hidden so the terrain draws the town's ground; a little for a capital, whose meshes stay);
##  - round it the terrain starts at the edge's height and eases back into the chart's ground: over BAND_LAND_M where
##    the chart has land there, over BAND_SEA_M where it is sea (so a town follows the coast instead of pushing lobes
##    of land out into the water);
##  - in front of the quay an oval dredged basin keeps BASIN_DEPTH_M of water, fading out softly.
## Texel (R, G, B, A) = (height, land weight, basin weight, 0).
## The GPU (port_pad_* in world_ground.gdshaderinc) and the CPU (WorldGround) blend with exactly the same numbers,
## so the keel test, the walkable shore collider and the drawn ground agree.
##
## Two steps: prepare() on the main thread (reads the meshes), compute() on a worker thread (a few seconds of
## GDScript; the port loads 6 km out, so nobody waits). Read-only once compute() has returned.
## Loaded by path (preload("res://scripts/port_pad.gd").new()), no class_name, so no editor class cache is needed.

const CELL_M := 5.0
const BAND_LAND_M := 280.0      ## blend back into the chart's land over this
const BAND_SEA_M := 60.0        ## and down into the sea over this
const FRONT_M := 600.0          ## how far beyond the ground the grid reaches out to sea
const BASIN_DEPTH_M := 7.0
const SMOOTH_PASSES := 3        ## separable 3-tap blur passes over the blend round the ground (not inside it)
const Y0_STEP := 4              ## the chart's own ground is sampled every this many cells and interpolated

var u0 := 0.0                   ## port-local u, v of texel (0, 0)'s centre
var v0 := 0.0
var nu := 0
var nv := 0
var data := PackedFloat32Array()   # nu * nv * 4
## Where the port is: chart x, z of its origin and its yaw (Godot rotation.y). Set before compute().
var cx := 0.0
var cz := 0.0
var yaw := 0.0
## Settings (set before compute()): how far under the port's ground the terrain sits, and the basin's half width and
## length (m, port-local).
var under_m := 0.0
var basin_w := 180.0
var basin_l := 520.0
## The chart's ground on the CPU (world_ground.gd), read on the worker thread (read-only, safe). Optional.
var ground = null

var _tris := PackedVector3Array()  # the ground's triangles in port-local space (prepare -> compute)


## Main thread: read the ground meshes' triangles (port root and meshes must be in the tree). False if none.
func prepare(root: Node3D, meshes: Array) -> bool:
	var inv := root.global_transform.affine_inverse()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for mi: MeshInstance3D in meshes:
		var mesh := mi.mesh
		if mesh == null:
			continue
		var rel := inv * mi.global_transform
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var vx: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ixv = arr[Mesh.ARRAY_INDEX]
			var ix := PackedInt32Array() if ixv == null else (ixv as PackedInt32Array)
			var count := vx.size() if ix.is_empty() else ix.size()
			for t in count:
				var p := rel * vx[t if ix.is_empty() else ix[t]]
				_tris.append(p)
				lo = lo.min(p)
				hi = hi.max(p)
	if _tris.size() < 3:
		return false
	u0 = lo.x - BAND_LAND_M
	v0 = lo.z - BAND_LAND_M
	nu = int(ceil((hi.x + BAND_LAND_M - u0) / CELL_M)) + 1
	nv = int(ceil((maxf(hi.z, 0.0) + FRONT_M - v0) / CELL_M)) + 1
	return true


## Worker thread: rasterise the ground's top and build the blend.
func compute() -> void:
	var n := nu * nv
	var top := PackedFloat32Array()
	top.resize(n)
	top.fill(-INF)
	for t in range(0, _tris.size() - 2, 3):
		_raster(_tris[t], _tris[t + 1], _tris[t + 2], top)
	_tris = PackedVector3Array()
	# nearest ground cell for every cell outside it (two-pass propagation of the nearest one)
	var near := PackedInt32Array()
	near.resize(n)
	near.fill(-1)
	for i in n:
		if top[i] > -INF:
			near[i] = i
	_propagate(near, true)
	_propagate(near, false)
	var y0 := _chart_ground()
	data.resize(n * 4)
	for j in nv:
		var v := v0 + float(j) * CELL_M
		for i in nu:
			var u := u0 + float(i) * CELL_M
			var k := j * nu + i
			var t_h := 0.0
			var wl := 0.0
			if top[k] > -INF:
				t_h = top[k] - under_m
				wl = 1.0
			elif near[k] >= 0:
				var si := near[k] % nu
				var sj := near[k] / nu
				var d := Vector2(float(i - si), float(j - sj)).length() * CELL_M
				t_h = top[near[k]] - under_m
				var band := lerpf(BAND_SEA_M, BAND_LAND_M, smoothstep(-4.0, 1.0, y0[k])) if not y0.is_empty() else BAND_LAND_M
				wl = 1.0 - smoothstep(0.0, band, d)
			# the basin: an oval in front of the quay, fading softly
			var e := Vector2(u / basin_w, maxf(v, 0.0) / basin_l).length()
			var wb := (1.0 - smoothstep(0.55, 1.0, e)) * smoothstep(-8.0, 2.0, v)
			if i == 0 or j == 0 or i == nu - 1 or j == nv - 1:
				wl = 0.0      # the grid's own border is plain chart ground, so nothing jumps where the pad ends
				wb = 0.0
			data[k * 4] = t_h
			data[k * 4 + 1] = wl
			data[k * 4 + 2] = wb
			data[k * 4 + 3] = 0.0
	# smooth the blend round the ground (the nearest-cell distance comes in steps, which showed as terraces); the
	# ground's own cells and the grid border stay exact
	for _pass in SMOOTH_PASSES:
		for axis in 2:
			var src := data.duplicate()
			var step := 1 if axis == 0 else nu
			for j in range(1, nv - 1):
				for i in range(1, nu - 1):
					var k := j * nu + i
					if top[k] > -INF:
						continue
					for ch in 3:
						data[k * 4 + ch] = (src[(k - step) * 4 + ch] + src[k * 4 + ch] + src[(k + step) * 4 + ch]) / 3.0


## The chart's own ground (no pad) at every cell, sampled every Y0_STEP cells and interpolated. Empty if no ground.
func _chart_ground() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if ground == null:
		return out
	var cu := (nu - 1) / Y0_STEP + 2
	var cv := (nv - 1) / Y0_STEP + 2
	var coarse := PackedFloat32Array()
	coarse.resize(cu * cv)
	var c := cos(yaw)
	var s := sin(yaw)
	for j in cv:
		for i in cu:
			var u := u0 + float(i * Y0_STEP) * CELL_M
			var v := v0 + float(j * Y0_STEP) * CELL_M
			# port-local (u, v) back to chart: the inverse of to_local()
			coarse[j * cu + i] = ground._ground_y0(cx + u * c + v * s, cz - u * s + v * c)
	out.resize(nu * nv)
	for j in nv:
		var fj := float(j) / float(Y0_STEP)
		var j0 := mini(int(fj), cv - 2)
		var ty := fj - float(j0)
		for i in nu:
			var fi := float(i) / float(Y0_STEP)
			var i0 := mini(int(fi), cu - 2)
			var tx := fi - float(i0)
			var a := lerpf(coarse[j0 * cu + i0], coarse[j0 * cu + i0 + 1], tx)
			var b := lerpf(coarse[(j0 + 1) * cu + i0], coarse[(j0 + 1) * cu + i0 + 1], tx)
			out[j * nu + i] = lerpf(a, b, ty)
	return out


func _raster(a: Vector3, b: Vector3, c: Vector3, top: PackedFloat32Array) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 1e-8:
		return
	if absf(nrm.normalized().y) < 0.25:      # walls and sides: not the top
		return
	var i0 := maxi(int(ceil((minf(a.x, minf(b.x, c.x)) - u0) / CELL_M)), 0)
	var i1 := mini(int(floor((maxf(a.x, maxf(b.x, c.x)) - u0) / CELL_M)), nu - 1)
	var j0 := maxi(int(ceil((minf(a.z, minf(b.z, c.z)) - v0) / CELL_M)), 0)
	var j1 := mini(int(floor((maxf(a.z, maxf(b.z, c.z)) - v0) / CELL_M)), nv - 1)
	var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(den) < 1e-9:
		return
	for j in range(j0, j1 + 1):
		var pz := v0 + float(j) * CELL_M
		for i in range(i0, i1 + 1):
			var px := u0 + float(i) * CELL_M
			var l1 := ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / den
			var l2 := ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / den
			var l3 := 1.0 - l1 - l2
			if l1 < -1e-4 or l2 < -1e-4 or l3 < -1e-4:
				continue
			var h := l1 * a.y + l2 * b.y + l3 * c.y
			var k := j * nu + i
			if h > top[k]:
				top[k] = h


func _propagate(near: PackedInt32Array, fwd: bool) -> void:
	var offs: Array
	if fwd:
		offs = [Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
	else:
		offs = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1)]
	var jr: Array = range(nv) if fwd else range(nv - 1, -1, -1)
	var ir: Array = range(nu) if fwd else range(nu - 1, -1, -1)
	for j: int in jr:
		for i: int in ir:
			var k := j * nu + i
			var best := near[k]
			var bd := INF
			if best >= 0:
				bd = _d2(i, j, best)
			for o: Vector2i in offs:
				var ni := i + o.x
				var nj := j + o.y
				if ni < 0 or nj < 0 or ni >= nu or nj >= nv:
					continue
				var s := near[nj * nu + ni]
				if s < 0:
					continue
				var d := _d2(i, j, s)
				if d < bd:
					bd = d
					best = s
			near[k] = best


func _d2(i: int, j: int, s: int) -> float:
	var di := float(i - s % nu)
	var dj := float(j - s / nu)
	return di * di + dj * dj


## (height, land weight, basin weight) at port-local u, v; zeros off the grid. Bilinear from the four texels, exactly
## as port_pad_sample() in world_ground.gdshaderinc does it.
func sample_local(u: float, v: float) -> Vector3:
	var gx := (u - u0) / CELL_M
	var gy := (v - v0) / CELL_M
	if gx < 0.0 or gy < 0.0 or gx > float(nu - 1) or gy > float(nv - 1):
		return Vector3.ZERO
	var i := mini(int(floor(gx)), nu - 2)
	var j := mini(int(floor(gy)), nv - 2)
	var fx := gx - float(i)
	var fy := gy - float(j)
	return _tx(i, j).lerp(_tx(i + 1, j), fx).lerp(_tx(i, j + 1).lerp(_tx(i + 1, j + 1), fx), fy)


func _tx(i: int, j: int) -> Vector3:
	var k := (j * nu + i) * 4
	return Vector3(data[k], data[k + 1], data[k + 2])


## Port-local (u, v) of chart x, z (the world wraps: the shortest way round).
func to_local(x: float, z: float, wrap_w: float, wrap_h: float) -> Vector2:
	var dx := x - cx
	var dz := z - cz
	dx -= roundf(dx / wrap_w) * wrap_w
	dz -= roundf(dz / wrap_h) * wrap_h
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector2(dx * c - dz * s, dx * s + dz * c)


## The ground blended with the pad: the same as port_pad_blend() in the shader.
static func blend(y: float, s: Vector3) -> float:
	y = lerpf(y, s.x, s.y)
	return lerpf(y, minf(y, -BASIN_DEPTH_M), s.z)


func texture() -> ImageTexture:
	var img := Image.create_from_data(nu, nv, false, Image.FORMAT_RGBAF, data.to_byte_array())
	return ImageTexture.create_from_image(img)


## Shader uniform port_pad_grid: (u0, v0, cell, 1 = on).
func grid_uniform() -> Vector4:
	return Vector4(u0, v0, CELL_M, 1.0)
