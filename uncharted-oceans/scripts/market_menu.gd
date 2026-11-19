class_name MarketMenu
extends CanvasLayer
## The stall menu: a plain list of what the stall sells, the price of a box, and Buy 1 / Buy 5 buttons.
## Placeholder UI. All the trading lives in MarketStall and TradeState, so a nicer screen can replace this one
## and call the same things: stall.goods(), stall.price(id), stall.quote(id, n), stall.buy(tree, pos, id, n).
##
## market_director.gd opens it (and frees the mouse / locks the player), and listens for `closed`.
## Esc or the Leave button closes it.

signal closed

const TradeStateScript := preload("res://scripts/trade_state.gd")
const TITLE_FONT := "res://assets/fonts/Ferrum-ExtraCondensed.otf"
const GOLD := Color(1.0, 0.82, 0.25)

var is_open := false

var _stall
var _from := Vector3.ZERO
var _title: Label
var _purse: Label
var _list: VBoxContainer
var _msg: Label


func _ready() -> void:
	layer = 20
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.4)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860.0, 0.0)
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
	if ResourceLoader.exists(TITLE_FONT):
		var font := load(TITLE_FONT) as Font
		if font != null:
			_title.add_theme_font_override("font", font)
	head.add_child(_title)
	_purse = Label.new()
	_purse.add_theme_font_size_override("font_size", 22)
	_purse.add_theme_color_override("font_color", GOLD)
	head.add_child(_purse)
	col.add_child(HSeparator.new())

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	col.add_child(_list)

	col.add_child(HSeparator.new())
	_msg = Label.new()
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(820.0, 0.0)
	col.add_child(_msg)
	var foot := HBoxContainer.new()
	col.add_child(foot)
	var hint := Label.new()
	hint.text = "Purchases wait in the port box at your berth. Sales are unloaded from your hold."
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	var leave := Button.new()
	leave.text = "Leave  (Esc)"
	leave.pressed.connect(close)
	foot.add_child(leave)


func open_for(stall, from: Vector3) -> void:
	_stall = stall
	_from = from
	_msg.text = ""
	TradeStateScript.sync_days(get_tree())      # prices recover for the days that went by
	is_open = true
	visible = true
	_refresh()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	closed.emit()


func _input(e: InputEvent) -> void:
	if not is_open:
		return
	var k := e as InputEventKey
	if k != null:
		if k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE:
			close()
		get_viewport().set_input_as_handled()      # no sleep window, hotkeys or anything else while you shop


func _refresh() -> void:
	_title.text = _stall.title
	_purse.text = "Gold  %d" % TradeStateScript.gold
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if String(_stall.kind) == "dock_office":
		_refresh_harbor_master()
		return
	var goods: Array = _stall.goods()
	var sells: Array = _stall.sellable(get_tree(), _from)
	if goods.is_empty() and sells.is_empty():
		var l := Label.new()
		l.text = _stall.note
		_list.add_child(l)
		return
	if not goods.is_empty():
		_list.add_child(_heading("For sale"))
		for g in goods:
			_list.add_child(_row(g))
	_list.add_child(_heading("We buy   (unloaded from your hold)"))
	if sells.is_empty():
		var none := Label.new()
		none.text = "Nothing in your hold that we deal in."
		none.modulate = Color(1, 1, 1, 0.6)
		_list.add_child(none)
	for s in sells:
		_list.add_child(_sell_row(s["good"], int(s["n"])))


## The harbour master: the ships lying in this harbour. Pick one to make it "the" ship (ship_fleet.gd).
func _refresh_harbor_master() -> void:
	var fleet := get_tree().get_first_node_in_group("ship_fleet") as ShipFleet
	if fleet == null:
		var l := Label.new()
		l.text = "The harbour master has no ledger of ships here."
		_list.add_child(l)
		return
	_list.add_child(_heading("Your other ships in this harbour   (%d)" % fleet.ship_count()))
	var can := fleet.can_switch()
	if not can:
		var warn := Label.new()
		warn.text = "Moor your ship at a berth before changing ships."
		warn.modulate = Color(1, 1, 1, 0.6)
		_list.add_child(warn)
	var shown := 0
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 320.0)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_list.add_child(scroll)
	for r in fleet.roster():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var n := Label.new()
		n.text = "%s" % r["name"]
		n.custom_minimum_size = Vector2(220.0, 0.0)
		row.add_child(n)
		var where := Label.new()
		where.text = "at %s" % r["berth_name"]
		where.modulate = Color(1, 1, 1, 0.6)
		where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(where)
		var b := Button.new()
		if bool(r["sailable"]):
			b.text = "Take command"
			b.disabled = not can
			b.pressed.connect(_take_command.bind(int(r["id"])))
		else:
			b.text = "Not yet sailable"
			b.disabled = true
		row.add_child(b)
		box.add_child(row)
		shown += 1
	if shown == 0:
		var none := Label.new()
		none.text = "None. Ships lying in the berths are for sale: walk aboard one to buy her."
		box.add_child(none)


func _take_command(id: int) -> void:
	var fleet := get_tree().get_first_node_in_group("ship_fleet") as ShipFleet
	if fleet == null:
		return
	var err := fleet.activate(id)
	if err != "":
		_msg.text = err
		_refresh()
		return
	close()


func _heading(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", GOLD)
	return l


## "cheap -32%" / "fair" / "dear +45%": this port's price against the good's plain base price, which is what to
## compare between ports.
func _tag(ratio: float) -> Label:
	var pct := roundi((ratio - 1.0) * 100.0)
	var l := Label.new()
	l.custom_minimum_size = Vector2(90.0, 0.0)
	if pct <= -12:
		l.text = "cheap %d%%" % pct
		l.add_theme_color_override("font_color", Color(0.55, 0.9, 0.5))
	elif pct >= 12:
		l.text = "dear +%d%%" % pct
		l.add_theme_color_override("font_color", Color(0.95, 0.5, 0.4))
	else:
		l.text = "fair"
		l.modulate = Color(1, 1, 1, 0.6)
	return l


func _sell_row(g: GoodDef, have: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_l := Label.new()
	name_l.text = "%s  x%d" % [g.display_name, have]
	name_l.custom_minimum_size = Vector2(220.0, 0.0)
	row.add_child(name_l)
	var paid := TradeStateScript.avg_cost(g.id)
	var info := Label.new()
	info.text = ("you paid %d" % roundi(paid)) if paid >= 0.0 else ""
	info.modulate = Color(1, 1, 1, 0.6)
	info.custom_minimum_size = Vector2(150.0, 0.0)
	row.add_child(info)
	var price := Label.new()
	price.text = "%d each" % _stall.sell_price(g.id)
	price.custom_minimum_size = Vector2(80.0, 0.0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price)
	row.add_child(_tag(_stall.market().price_ratio(g.id)))
	for n in [1, 5]:
		if n > have and n != 1:
			continue
		var b := Button.new()
		b.text = "Sell %d" % n
		b.pressed.connect(_sell.bind(g.id, n))
		row.add_child(b)
	if have > 1:
		var all := Button.new()
		all.text = "Sell all"
		all.pressed.connect(_sell.bind(g.id, have))
		row.add_child(all)
	return row


func _sell(good_id: String, n: int) -> void:
	_msg.text = _stall.sell(get_tree(), _from, good_id, n)
	_refresh()


func _row(g: GoodDef) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_l := Label.new()
	name_l.text = g.display_name
	name_l.custom_minimum_size = Vector2(220.0, 0.0)
	row.add_child(name_l)
	var info := Label.new()
	info.text = "%s, %d kg" % [g.container, roundi(g.weight_kg)]
	info.modulate = Color(1, 1, 1, 0.6)
	info.custom_minimum_size = Vector2(150.0, 0.0)
	row.add_child(info)
	var price := Label.new()
	price.text = "%d each" % _stall.price(g.id)
	price.custom_minimum_size = Vector2(80.0, 0.0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price)
	row.add_child(_tag(_stall.market().price_ratio(g.id)))
	for n in [1, 5]:
		var b := Button.new()
		b.text = "Buy %d" % n
		b.disabled = _stall.quote(g.id, n) > TradeStateScript.gold
		b.pressed.connect(_buy.bind(g.id, n))
		row.add_child(b)
	return row


func _buy(good_id: String, n: int) -> void:
	_msg.text = _stall.buy(get_tree(), _from, good_id, n)
	_refresh()
