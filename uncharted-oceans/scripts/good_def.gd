class_name GoodDef
extends RefCounted
## One tradeable good: its box shape (in hold-grid cells), weight and price data.
## Shapes in goods.json are in BASE units; they are scaled so one base unit is
## scale^3 grid cells (the 25 cm hold cells that flood).

var id: String = ""
var display_name: String = ""
var category: String = ""
var container: String = ""
var base_cells: Array[Vector3i] = []
var cells: Array[Vector3i] = []  # grid cells, min corner at (0,0,0), y up
var weight_kg: float = 0.0
var base_price: int = 0
var produced_in: Array[String] = []
var region_mult: Dictionary = {}  # region id -> float
var flags: Array[String] = []


static func from_dict(d: Dictionary, scale: int) -> GoodDef:
	var g := GoodDef.new()
	g.id = str(d.get("id", ""))
	g.display_name = str(d.get("name", g.id))
	g.category = str(d.get("category", ""))
	g.container = str(d.get("container", ""))
	for c in d.get("cells", []):
		g.base_cells.append(Vector3i(int(c[0]), int(c[1]), int(c[2])))
	g.cells = scale_cells(g.base_cells, scale)
	g.weight_kg = float(d.get("weight_kg", 0))
	g.base_price = int(d.get("base_price", 0))
	for r in d.get("produced_in", []):
		g.produced_in.append(str(r))
	g.region_mult = d.get("region_mult", {})
	for f in d.get("flags", []):
		g.flags.append(str(f))
	return g


static func scale_cells(base: Array[Vector3i], s: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for b in base:
		for x in s:
			for y in s:
				for z in s:
					out.append(Vector3i(b.x * s + x, b.y * s + y, b.z * s + z))
	return out


func size_cells() -> Vector3i:
	var mx := Vector3i.ZERO
	for c in cells:
		mx = Vector3i(maxi(mx.x, c.x), maxi(mx.y, c.y), maxi(mx.z, c.z))
	return mx + Vector3i.ONE


func volume_m3(cell_m: float) -> float:
	return cells.size() * cell_m * cell_m * cell_m


func has_flag(f: String) -> bool:
	return flags.has(f)


func multiplier_for(region: String) -> float:
	return float(region_mult.get(region, 1.0))


## Rotate a cell set about the vertical axis by quarter_turns * 90 degrees and
## re-normalise so the minimum corner is (0,0,0).
static func rotated_yaw(src: Array[Vector3i], quarter_turns: int) -> Array[Vector3i]:
	var q := posmod(quarter_turns, 4)
	var out: Array[Vector3i] = []
	for c in src:
		var x := c.x
		var z := c.z
		for i in q:
			var nx := -z
			var nz := x
			x = nx
			z = nz
		out.append(Vector3i(x, c.y, z))
	var mn := Vector3i(1 << 30, 1 << 30, 1 << 30)
	for c in out:
		mn = Vector3i(mini(mn.x, c.x), mini(mn.y, c.y), mini(mn.z, c.z))
	for i in out.size():
		out[i] -= mn
	return out
