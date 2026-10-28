class_name CargoData
extends RefCounted
## Loads res://data/goods.json into typed GoodDef objects.

const PATH := "res://data/goods.json"

static var _shared: CargoData = null

var cell_m: float = 0.25
var scale: int = 2
var goods: Dictionary = {}  # id -> GoodDef
var order: Array[String] = []
var regions: Dictionary = {}
var categories: Dictionary = {}
var market: Dictionary = {}


static func get_shared() -> CargoData:
	if _shared == null:
		_shared = CargoData.new()
		_shared.load_file()
	return _shared


func load_file(path: String = PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_error("CargoData: missing " + path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CargoData: bad JSON in " + path)
		return false
	var d: Dictionary = parsed
	cell_m = float(d.get("cell_m", 0.25))
	scale = int(d.get("scale", 2))
	regions = d.get("regions", {})
	categories = d.get("categories", {})
	market = d.get("market", {})
	goods.clear()
	order.clear()
	for gd in d.get("goods", []):
		var g := GoodDef.from_dict(gd, scale)
		goods[g.id] = g
		order.append(g.id)
	return true


func get_good(id: String) -> GoodDef:
	return goods.get(id) as GoodDef


func goods_in_category(cat: String) -> Array[GoodDef]:
	var out: Array[GoodDef] = []
	for id in order:
		var g: GoodDef = goods[id]
		if g.category == cat:
			out.append(g)
	return out


func goods_for_stall(stall: String) -> Array[GoodDef]:
	var out: Array[GoodDef] = []
	for id in order:
		var g: GoodDef = goods[id]
		var c: Dictionary = categories.get(g.category, {})
		if c.get("stall", null) == stall:
			out.append(g)
	return out


## Returns human-readable problems; empty array means the table is sound.
func validate() -> Array[String]:
	var warns: Array[String] = []
	var seen: Dictionary = {}
	for id in order:
		var g: GoodDef = goods[id]
		if g.base_price <= 0:
			warns.append(id + ": non-positive price")
		if g.weight_kg <= 0.0:
			warns.append(id + ": non-positive weight")
		if not categories.has(g.category):
			warns.append(id + ": unknown category " + g.category)
		if g.base_cells.is_empty():
			warns.append(id + ": no cells")
			continue
		if not _connected(g.base_cells):
			warns.append(id + ": shape not connected")
		var key := _canon_key(g.base_cells)
		if seen.has(key):
			pass   # shapes may repeat between goods: the container model and the tint tell them apart
		else:
			seen[key] = id
	return warns


static func _connected(cells: Array[Vector3i]) -> bool:
	var set: Dictionary = {}
	for c in cells:
		set[c] = true
	var stack: Array[Vector3i] = [cells[0]]
	var vis: Dictionary = {cells[0]: true}
	var dirs := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.BACK, Vector3i.FORWARD]
	while not stack.is_empty():
		var p: Vector3i = stack.pop_back()
		for d in dirs:
			var n: Vector3i = p + d
			if set.has(n) and not vis.has(n):
				vis[n] = true
				stack.append(n)
	return vis.size() == set.size()


## Canonical key over the 24 proper rotations (mirror images count as different).
static func _canon_key(cells: Array[Vector3i]) -> String:
	var best := ""
	for perm in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]:
		for sx in [1, -1]:
			for sy in [1, -1]:
				for sz in [1, -1]:
					var m := [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
					m[0][perm[0]] = sx
					m[1][perm[1]] = sy
					m[2][perm[2]] = sz
					var det: int = (
						m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
						- m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
						+ m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
					)
					if det != 1:
						continue
					var pts: Array = []
					var mn := [1 << 30, 1 << 30, 1 << 30]
					for c in cells:
						var v := [c.x, c.y, c.z]
						var r := [0, 0, 0]
						for i in 3:
							for j in 3:
								r[i] += m[i][j] * v[j]
						for i in 3:
							mn[i] = mini(mn[i], r[i])
						pts.append(r)
					var strs: Array[String] = []
					for r in pts:
						strs.append("%d,%d,%d" % [r[0] - mn[0], r[1] - mn[1], r[2] - mn[2]])
					strs.sort()
					var key := ";".join(strs)
					if best == "" or key < best:
						best = key
	return best
