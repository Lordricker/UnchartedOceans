extends CanvasLayer
## The "buy this ship" window (made by ship_fleet.gd).
##
## A ship that is for sale has an A-frame sign on the quay beside her (ship_sale_sign.gd). Look at it (white outline) and
## click: a window shows the ship's price and stats with a Purchase button. Esc leaves. Buying takes the gold
## (TradeState.gold) and the ship is yours: change to her at the harbour master like any ship of yours.
##
## The mouse is freed and the player locked while the window is open, the same way the market menu does it.

const TradeStateScript := preload("res://scripts/trade_state.gd")
const TITLE_FONT := "res://assets/fonts/Ferrum-ExtraCondensed.otf"
const GOLD := Color(1.0, 0.82, 0.25)

## The ShipFleet (set by the fleet before this node enters the tree).
var fleet
var is_open := false

## How far (m) you can read a sign from.
const SIGN_REACH := 3.2

var _entry := {}
var _hover: ShipSaleSign
var _root: Control
var _title: Label
var _purse: Label
var _price: Label
var _stats: GridContainer
var _msg: Label
var _buy: Button
var _bought := false


func _ready() -> void:
	layer = 19
	_make_window()


func _font() -> Font:
	if ResourceLoader.exists(TITLE_FONT):
		return load(TITLE_FONT) as Font
	return null


func _make_window() -> void:
	_root = Control.new()
	_root.visible = false
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.4)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640.0, 0.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.07, 0.97)
	sb.border_color = Color(0.55, 0.42, 0.22)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(18.0)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 36)
	_title.add_theme_color_override("font_color", GOLD)
	var f := _font()
	if f != null:
		_title.add_theme_font_override("font", f)
	head.add_child(_title)
	_purse = Label.new()
	_purse.add_theme_font_size_override("font_size", 22)
	_purse.add_theme_color_override("font_color", GOLD)
	head.add_child(_purse)
	col.add_child(HSeparator.new())

	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", 30)
	_stats.add_theme_constant_override("v_separation", 6)
	col.add_child(_stats)

	col.add_child(HSeparator.new())
	_price = Label.new()
	_price.add_theme_font_size_override("font_size", 28)
	_price.add_theme_color_override("font_color", GOLD)
	if f != null:
		_price.add_theme_font_override("font", f)
	col.add_child(_price)
	_msg = Label.new()
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(600.0, 0.0)
	col.add_child(_msg)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	_buy = Button.new()
	_buy.custom_minimum_size = Vector2(220.0, 44.0)
	_buy.pressed.connect(_on_buy)
	foot.add_child(_buy)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	var leave := Button.new()
	leave.text = "Leave  (Esc)"
	leave.pressed.connect(_close)
	foot.add_child(leave)


func _player() -> Node:
	return get_tree().get_first_node_in_group("player")


func _camera() -> Camera3D:
	var pl := _player()
	return pl.get_node_or_null("Head/Camera3D") as Camera3D if pl != null else null


## Outline the sign you are looking at (the white outline means "click me", like everything else in the game).
func _process(_delta: float) -> void:
	var best: ShipSaleSign = null
	var pl := _player()
	var cam := _camera()
	if not is_open and cam != null and pl != null and not bool(pl.get("input_locked")) \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		best = ShipSaleSign.pick(get_tree(), cam.global_position, -cam.global_transform.basis.z, SIGN_REACH)
	if best != _hover:
		if _hover != null and is_instance_valid(_hover):
			_hover.set_lit(false)
		_hover = best
		if _hover != null:
			_hover.set_lit(true)


func _input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if is_open:
		if k != null:
			if k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE:
				_close()
			get_viewport().set_input_as_handled()       # no hotkeys while you shop
		return
	var m := e as InputEventMouseButton
	if m != null and m.pressed and m.button_index == MOUSE_BUTTON_LEFT \
			and _hover != null and is_instance_valid(_hover):
		_open_sign(_hover)
		get_viewport().set_input_as_handled()


func _open_sign(sg: ShipSaleSign) -> void:
	if fleet == null:
		return
	_entry = {"id": sg.entry_id, "model": sg.model, "name": sg.ship_name, "price": sg.price}
	_bought = false
	var model := int(_entry["model"])
	_title.text = String(_entry["name"])
	_msg.text = ""
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	for row in fleet.stats_of(model):
		var l := Label.new()
		l.text = String(row[0])
		l.modulate = Color(1, 1, 1, 0.65)
		_stats.add_child(l)
		var v := Label.new()
		v.text = String(row[1])
		_stats.add_child(v)
	_refresh_buy()
	var pl := _player()
	if pl != null:
		pl.set("input_locked", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	is_open = true
	_root.visible = true


func _refresh_buy() -> void:
	var price := int(_entry["price"])
	var gold: int = TradeStateScript.gold
	_price.text = "Price  %s gold" % _fmt(price)
	_purse.text = "Gold  %s" % _fmt(gold)
	if _bought:
		_buy.text = "Purchased"
		_buy.disabled = true
	elif gold < price:
		_buy.text = "Purchase"
		_buy.disabled = true
		_msg.text = "You need %s more gold." % _fmt(price - gold)
	else:
		_buy.text = "Purchase  (%s)" % _fmt(price)
		_buy.disabled = false


func _on_buy() -> void:
	var err: String = fleet.purchase(int(_entry["id"]))
	if err != "":
		_msg.text = err
		_refresh_buy()
		return
	_bought = true
	_msg.text = "The %s is yours. Moor your ship and see the harbour master to take command of her." % String(_entry["name"]).to_lower()
	_refresh_buy()


func _close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	var pl := _player()
	if pl != null:
		pl.set("input_locked", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
