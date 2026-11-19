class_name CourierDialog
extends CanvasLayer
## What a courier person says: the job they offer (where, how much), with Accept and Not now; or, once you have taken
## it, a reminder with Give the job back. Placeholder UI in the style of the stall menu (market_menu.gd).
##
## market_director.gd opens it (and frees the mouse / locks the player), and listens for `closed`. Esc closes it.

signal closed

const QuestsScript := preload("res://scripts/courier_quests.gd")
const TradeStateScript := preload("res://scripts/trade_state.gd")
const TITLE_FONT := "res://assets/fonts/Ferrum-ExtraCondensed.otf"
const GOLD := Color(1.0, 0.82, 0.25)

var is_open := false

var _npc
var _from := Vector3.ZERO
var _title: Label
var _purse: Label
var _body: Label
var _detail: Label
var _msg: Label
var _buttons: HBoxContainer


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
	panel.custom_minimum_size = Vector2(720.0, 0.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.07, 0.97)
	sb.border_color = Color(0.55, 0.42, 0.22)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(18.0)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
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

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(680.0, 0.0)
	_body.add_theme_font_size_override("font_size", 22)
	col.add_child(_body)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 20)
	_detail.add_theme_color_override("font_color", GOLD)
	col.add_child(_detail)
	col.add_child(HSeparator.new())
	_msg = Label.new()
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(680.0, 0.0)
	col.add_child(_msg)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(_buttons)


func open_for(npc, from: Vector3) -> void:
	_npc = npc
	_from = from
	_msg.text = ""
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
		get_viewport().set_input_as_handled()      # no sleep window, hotkeys or anything else while you talk


func _refresh() -> void:
	_title.text = "%s, %s" % [_npc.giver, QuestsScript.port_name(_npc.port_id)]
	_purse.text = "Gold  %d" % TradeStateScript.gold
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	var q: Dictionary = QuestsScript.quest_of_npc(_npc.key)
	if not q.is_empty():
		_body.text = "Have you got my parcel yet, Captain? It is %s, for %s. Put it in a port box there and the town will see it to the right hands." % [q["item"], q["to_name"]]
		_detail.text = "Parcel for %s   (about %d km)\nReward on delivery: %d gold" % [q["to_name"], roundi(float(q["km"])), int(q["reward"])]
		_add_button("Give the job back", _on_abandon)
		_add_button("Goodbye", close)
		return
	var o: Dictionary = QuestsScript.offer_for(_npc.key, _npc.port_id)
	if o.is_empty():
		_body.text = "Good day, Captain. Nothing I need carried, I'm afraid."
		_detail.text = ""
		_add_button("Goodbye", close)
		return
	_body.text = String(o["text"])
	_detail.text = "Destination: %s   (about %d km)\nReward on delivery: %d gold" % [o["to_name"], roundi(float(o["km"])), int(o["reward"])]
	_add_button("Accept", _on_accept)
	_add_button("Not now", close)


func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150.0, 36.0)
	b.pressed.connect(cb)
	_buttons.add_child(b)


func _on_accept() -> void:
	var r: Dictionary = QuestsScript.accept(get_tree(), _npc.key, _npc.port_id, _npc.giver, _from)
	_msg.text = String(r.get("msg", ""))
	_refresh()


func _on_abandon() -> void:
	QuestsScript.abandon(get_tree(), _npc.key)
	_msg.text = "A pity. I will find another way."
	_refresh()
