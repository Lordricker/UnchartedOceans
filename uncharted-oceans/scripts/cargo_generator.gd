class_name CargoGenerator
extends Node3D
## The port box. One stands on the quay at every berth (market_director.gd puts them there) and holds whatever
## you have bought in the port's market (market_stall.gd). Click it with empty hands and the next box comes out into
## them, ready to carry to the hold (cargo_system.gd does the clicking and carrying).
##
## What it holds is kept in TradeState under stock_key, not in this node, so the contents are still there when the
## port is unloaded and comes back.

const TradeStateScript := preload("res://scripts/trade_state.gd")
const SIZE := Vector3(1.0, 0.75, 0.75)

## "<port id>/<berth name>". Set before the box is added to the tree.
var stock_key := ""

var _label: Label3D
var _shown_n := -1


func _ready() -> void:
	add_to_group("cargo_generators")
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.46, 0.33, 0.21)
	wood.roughness = 0.9
	var strap := StandardMaterial3D.new()
	strap.albedo_color = Color(0.17, 0.13, 0.1)
	strap.roughness = 0.8
	_box(Vector3(0.0, SIZE.y * 0.5, 0.0), SIZE, wood)
	for x in [-0.3, 0.3]:
		_box(Vector3(x, SIZE.y * 0.5, 0.0), Vector3(0.08, SIZE.y + 0.02, SIZE.z + 0.02), strap)
	_box(Vector3(0.0, SIZE.y + 0.01, 0.0), Vector3(SIZE.x + 0.06, 0.05, SIZE.z + 0.06), strap)
	# solid for the player (pier layer), so you can't walk through it
	var body := StaticBody3D.new()
	body.collision_layer = Island.LAYER_BIT
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = SIZE
	cs.shape = bs
	cs.position = Vector3(0.0, SIZE.y * 0.5, 0.0)
	body.add_child(cs)
	add_child(body)
	_label = Label3D.new()
	_label.font_size = 40
	_label.pixel_size = 0.0035
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.outline_size = 10
	_label.position = Vector3(0.0, SIZE.y + 0.4, 0.0)
	add_child(_label)
	_refresh_label()


func _box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _stock() -> Array:
	return TradeStateScript.box_stock(stock_key)


## How many boxes are waiting.
func count() -> int:
	return _stock().size()


## Put n boxes of a good into the box (a purchase being delivered).
func add_boxes(good_id: String, n: int) -> void:
	var s := _stock()
	for i in n:
		s.append(good_id)
	_refresh_label()


## Put a box back in (you changed your mind, or you are unloading the hold).
func put_good(g: GoodDef) -> void:
	_stock().append(g.id)
	_refresh_label()


## Keeps the sign right when another port box (same pool) changed.
func _process(_delta: float) -> void:
	var n := count()
	if n != _shown_n:
		_refresh_label()


## Take the next box out (the oldest purchase first). Null if there is nothing in it.
func take_good(data: CargoData) -> GoodDef:
	var s := _stock()
	if s.is_empty():
		return null
	var id: String = s.pop_front()
	_refresh_label()
	return data.get_good(id)


## What the aim prompt says while you look at it.
func prompt() -> String:
	var s := _stock()
	if s.is_empty():
		return "Port box: empty"
	var g := CargoData.get_shared().get_good(String(s[0]))
	var next := g.display_name if g != null else String(s[0])
	return "Click: take %s  (%d in the port box)" % [next, s.size()]


func _refresh_label() -> void:
	if _label == null:
		return
	var n := count()
	_shown_n = n
	_label.text = "PORT BOX" if n == 0 else "PORT BOX (%d)" % n
