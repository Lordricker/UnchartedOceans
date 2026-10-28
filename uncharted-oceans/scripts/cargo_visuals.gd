class_name CargoVisuals
extends RefCounted
## What a box looks like. Modular: every base block of a good's shape (one block = 0.5 m) is one small model of the
## good's container (barrel, sack, crate, chest or bale), tinted by category, so a 3-block sugar shape is three
## hogsheads stacked and a 4-block rope shape is four coils side by side. The models are drawn in code; to use real
## ones later, swap `unit()` for a lookup of a mesh per container kind.
##
## The mesh uses vertex colours and one shared material (CargoVisuals.material()).

const KIND := {
	"barrel": "barrel", "small barrel": "barrel", "hogshead": "barrel",
	"sack": "sack",
	"bale": "bale", "bundle": "bale", "long bundle": "bale", "log bundle": "bale", "coil": "bale",
	"crate": "crate", "small crate": "crate", "long crate": "crate", "straw crate": "crate", "tea chest": "crate",
	"chest": "chest", "small chest": "chest",
}

static var _units := {}
static var _mat: StandardMaterial3D


## Small mesh builder: flat-shaded quads with a colour each.
class MB:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

	## A quad whose outside is the side `out` points to (the corner order doesn't matter).
	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, out: Vector3, col: Color) -> void:
		var nn := out.normalized()
		var base := v.size()
		v.append_array([a, b, cc, d])
		for k in 4:
			n.append(nn)
			c.append(col)
		# Godot front faces are clockwise seen from outside
		if (b - a).cross(cc - a).dot(nn) > 0.0:
			idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		else:
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func box(lo: Vector3, hi: Vector3, col: Color) -> void:
		quad(Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3.RIGHT, col)
		quad(Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3.LEFT, col)
		quad(Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.UP, col)
		quad(Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3.DOWN, col)
		quad(Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.BACK, col)
		quad(Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3.FORWARD, col)

	## Copy another mesh in, scaled by s and moved by offset.
	func append(other: MB, offset: Vector3, s: float) -> void:
		var base := v.size()
		for p in other.v:
			v.append(p * s + offset)
		n.append_array(other.n)
		c.append_array(other.c)
		for k in other.idx:
			idx.append(k + base)

	func to_mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if v.size() == 0:
			return m
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.albedo_color = Color.WHITE
		_mat.roughness = 0.9
	return _mat


static func kind_of(container: String) -> String:
	return String(KIND.get(container, "crate"))


## The mesh of a shape (cells at the hold grid's cell_m, `block` cells to a base block), min corner at the origin.
@warning_ignore("integer_division")
static func build(cells: Array[Vector3i], container: String, col: Color, cell_m: float, block: int) -> ArrayMesh:
	var blocks := {}
	for c in cells:
		blocks[Vector3i(c.x / block, c.y / block, c.z / block)] = true
	var mb := MB.new()
	var u := unit(kind_of(container), col)
	var s := cell_m * float(block)
	for b in blocks:
		mb.append(u, Vector3(b as Vector3i) * s, s)
	return mb.to_mesh()


## One container, filling the unit cube (0..1 on every axis).
static func unit(kind: String, col: Color) -> MB:
	var key := "%s_%s" % [kind, col.to_html(false)]
	if _units.has(key):
		return _units[key]
	var m := MB.new()
	match kind:
		"barrel":
			_barrel(m, col)
		"sack":
			_sack(m, col)
		"bale":
			_bale(m, col)
		"chest":
			_crate(m, col, true)
		_:
			_crate(m, col, false)
	_units[key] = m
	return m


## A point on a surface of revolution about the unit cube's vertical axis; p = (height, radius).
static func _rev(p: Vector2, a: float) -> Vector3:
	return Vector3(0.5 + p.y * cos(a), p.x, 0.5 + p.y * sin(a))


static func _barrel(m: MB, col: Color) -> void:
	var prof: Array[Vector2] = [Vector2(0.0, 0.38), Vector2(0.1, 0.43), Vector2(0.5, 0.485), Vector2(0.9, 0.43), Vector2(1.0, 0.38)]
	var segs := 10
	var dark := col.darkened(0.55)
	var lid := col.darkened(0.2)
	var mid := Vector3(0.5, 0.0, 0.5)
	for k in segs:
		var a0 := TAU * float(k) / segs
		var a1 := TAU * float(k + 1) / segs
		var am := (a0 + a1) * 0.5
		var out := Vector3(cos(am), 0.0, sin(am))
		var stave := col if k % 2 == 0 else col.darkened(0.07)
		for j in prof.size() - 1:
			m.quad(_rev(prof[j], a0), _rev(prof[j], a1), _rev(prof[j + 1], a1), _rev(prof[j + 1], a0), out, stave)
		m.quad(mid, _rev(prof[0], a0), _rev(prof[0], a1), mid, Vector3.DOWN, lid)
		var top := Vector3(0.5, 1.0, 0.5)
		m.quad(top, _rev(prof[prof.size() - 1], a0), _rev(prof[prof.size() - 1], a1), top, Vector3.UP, lid)
	# iron hoops: narrow dark bands a hair outside the staves
	for hy in [0.2, 0.8]:
		var r := _prof_radius(prof, hy) + 0.012
		for k in segs:
			var a0 := TAU * float(k) / segs
			var a1 := TAU * float(k + 1) / segs
			var am := (a0 + a1) * 0.5
			m.quad(_rev(Vector2(hy - 0.04, r), a0), _rev(Vector2(hy - 0.04, r), a1), _rev(Vector2(hy + 0.04, r), a1), _rev(Vector2(hy + 0.04, r), a0), Vector3(cos(am), 0.0, sin(am)), dark)


static func _prof_radius(prof: Array[Vector2], y: float) -> float:
	for j in prof.size() - 1:
		if y <= prof[j + 1].x:
			var t := (y - prof[j].x) / maxf(prof[j + 1].x - prof[j].x, 0.0001)
			return lerpf(prof[j].y, prof[j + 1].y, t)
	return prof[prof.size() - 1].y


## A plump sack: a squashed ball with a knot on top.
static func _sack(m: MB, col: Color) -> void:
	var segs := 8
	var bands := 6
	var rings: Array[Vector2] = []
	for j in bands + 1:
		var t := float(j) / bands
		rings.append(Vector2(0.5 - 0.485 * cos(PI * t), 0.47 * pow(sin(PI * t), 0.6) + 0.04))
	var centre := Vector3(0.5, 0.5, 0.5)
	for k in segs:
		var a0 := TAU * float(k) / segs
		var a1 := TAU * float(k + 1) / segs
		for j in bands:
			var shade := col.lightened(0.06) if j % 2 == 0 else col
			var qa := _rev(rings[j], a0)
			var qb := _rev(rings[j], a1)
			var qc := _rev(rings[j + 1], a1)
			var qd := _rev(rings[j + 1], a0)
			m.quad(qa, qb, qc, qd, (qa + qb + qc + qd) * 0.25 - centre, shade)
	m.box(Vector3(0.42, 0.955, 0.42), Vector3(0.58, 1.0, 0.58), col.darkened(0.45))


## A bundle or bale: a body tied with two straps.
static func _bale(m: MB, col: Color) -> void:
	m.box(Vector3(0.02, 0.02, 0.02), Vector3(0.98, 0.98, 0.98), col)
	var strap := Color(0.24, 0.18, 0.11)
	for y0 in [0.2, 0.68]:
		m.box(Vector3(0.0, y0, 0.0), Vector3(1.0, y0 + 0.1, 1.0), strap)


## A slatted wooden crate; a chest also has a brass clasp.
static func _crate(m: MB, col: Color, chest: bool) -> void:
	var rail := col.darkened(0.35)
	for j in 4:
		var lo := 0.09 + 0.205 * j
		m.box(Vector3(0.03, lo, 0.03), Vector3(0.97, lo + 0.205, 0.97), col.darkened(0.05 * (j % 2)))
	m.box(Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.09, 1.0), rail)
	m.box(Vector3(0.0, 0.91, 0.0), Vector3(1.0, 1.0, 1.0), rail)
	for sx in [0.0, 0.9]:
		for sz in [0.0, 0.9]:
			m.box(Vector3(sx, 0.09, sz), Vector3(sx + 0.1, 0.91, sz + 0.1), rail)
	if chest:
		m.box(Vector3(0.44, 0.55, 0.96), Vector3(0.56, 0.75, 1.015), Color(0.85, 0.7, 0.25))
