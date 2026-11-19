class_name ShipSaleSign
extends Node3D
## A wooden A-frame sign standing on the quay beside a ship that is for sale (made by ship_fleet.gd).
## Look at it (it gets the white outline like everything clickable) and click: the ship's stats and price open
## (ship_purchase.gd). Both faces carry the ship's name and price. The frame lies across the berth, so one face
## looks at the quay and the other at the ship.

const Outline := preload("res://scripts/interact_outline.gd")
const TITLE_FONT := "res://assets/fonts/Ferrum-ExtraCondensed.otf"

const HEIGHT := 1.0
const WIDTH := 0.75
const LEAN_DEG := 14.0

## Which for-sale ship (ShipFleet entry id) this sign belongs to, and what to print on it.
var entry_id := 0
var model := 0
var ship_name := ""
var price := 0

var _meshes: Array[MeshInstance3D] = []
var _lit := false


func setup(p_id: int, p_model: int, p_name: String, p_price: int) -> void:
	entry_id = p_id
	model = p_model
	ship_name = p_name
	price = p_price


func _ready() -> void:
	add_to_group("sale_signs")
	_build()


func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.62, 0.48, 0.3)
	wood.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.3, 0.21, 0.13)
	dark.roughness = 0.9
	var font: Font = null
	if ResourceLoader.exists(TITLE_FONT):
		font = load(TITLE_FONT) as Font
	var lean := deg_to_rad(LEAN_DEG)
	var half := HEIGHT * 0.5 * tan(lean)
	var panel_len := HEIGHT / cos(lean)
	for side in [-1, 1]:
		var panel := MeshInstance3D.new()
		panel.name = "Panel%s" % ("Quay" if side < 0 else "Ship")
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, panel_len, WIDTH)
		panel.mesh = bm
		panel.material_override = wood
		# the top meets at x = 0, the foot stands out to its own side
		panel.position = Vector3(side * half, HEIGHT * 0.5, 0.0)
		panel.rotation.z = side * lean
		add_child(panel)
		_meshes.append(panel)
		# a darker plank across the foot, so it reads as boards and not a slab
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.06, 0.07, WIDTH + 0.04)
		rail.mesh = rm
		rail.material_override = dark
		rail.position = Vector3(0.0, -panel_len * 0.5 + 0.06, 0.0)
		panel.add_child(rail)
		_meshes.append(rail)
		_label(panel, side, "FOR SALE", 0.27, 80, font)
		_label(panel, side, ship_name.to_upper(), 0.04, 70, font)
		_label(panel, side, "%s gold" % _fmt(price), -0.2, 46, font)
	var hinge := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.03
	cm.height = WIDTH + 0.06
	hinge.mesh = cm
	hinge.material_override = dark
	hinge.position = Vector3(0.0, HEIGHT, 0.0)
	hinge.rotation.x = PI * 0.5
	add_child(hinge)
	_meshes.append(hinge)
	# solid for the player (physics layer 4, like the quay and the gangways)
	var body := StaticBody3D.new()
	body.name = "SignBody"
	body.collision_layer = Island.LAYER_BIT
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(half * 2.0 + 0.1, HEIGHT, WIDTH)
	cs.shape = bs
	cs.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	body.add_child(cs)
	add_child(body)


## One line of ink on one face (side -1 looks along -x, +1 along +x).
func _label(panel: Node3D, side: int, text: String, y: float, size: int, font: Font) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0017
	l.modulate = Color(0.12, 0.07, 0.04)
	l.outline_size = 0
	l.double_sided = false
	l.shaded = false
	if font != null:
		l.font = font
	l.position = Vector3(side * 0.0215, y, 0.0)
	l.rotation.y = side * PI * 0.5
	panel.add_child(l)


func set_lit(on: bool) -> void:
	if on == _lit:
		return
	_lit = on
	for m in _meshes:
		m.material_overlay = Outline.material() if on else null


## Distance along the ray (m) to this sign, or -1 if the ray misses it.
func ray_distance(origin: Vector3, dir: Vector3) -> float:
	var best := -1.0
	for m in _meshes:
		if not is_instance_valid(m):
			continue
		var inv := m.global_transform.affine_inverse()
		var hit = m.get_aabb().grow(0.04).intersects_ray(inv * origin, (inv.basis * dir).normalized())
		if hit != null:
			var d := origin.distance_to(m.global_transform * (hit as Vector3))
			if best < 0.0 or d < best:
				best = d
	return best


## The nearest sign in front of the camera within reach, or null.
static func pick(tree: SceneTree, origin: Vector3, dir: Vector3, reach: float) -> ShipSaleSign:
	var best: ShipSaleSign = null
	var best_d := reach
	for n in tree.get_nodes_in_group("sale_signs"):
		var s := n as ShipSaleSign
		if s == null or not s.is_inside_tree() or s.global_position.distance_to(origin) > reach + 1.5:
			continue
		var d := s.ray_distance(origin, dir)
		if d >= 0.0 and d < best_d:
			best_d = d
			best = s
	return best


static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
