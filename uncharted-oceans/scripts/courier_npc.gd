class_name CourierNpc
extends MarketNpc
## A person standing about a port with a courier job for you (courier_quests.gd). market_director.gd places a few of
## them round each port, on open ground. They stand still, look at you when you come close and are talked to like the
## stallholders: aim at one, click, and courier_dialog.gd opens.
##
## A gold "?" floats over their head while they have a job on offer. "?" is for side quests; "!" is kept for the
## main quest (MARK_MAIN), so a giver of a main-quest job sets main_quest = true before setup_courier().

const QuestsScript := preload("res://scripts/courier_quests.gd")
const MARK_SIDE := "?"
const MARK_MAIN := "!"

## "<port id>/courier_<n>": the same person every time the port is loaded.
var key := ""
var port_id := ""
var giver := ""
var main_quest := false     ## true: a main-quest giver, marked "!" instead of "?"

var _mark: Label3D
var _mark_y := 2.2
var _t := 0.0


func setup_courier(p_key: String, p_port_id: String, p_name: String, model_name: String) -> void:
	key = p_key
	port_id = p_port_id
	giver = p_name
	setup(model_name, null)
	_make_mark()


func is_courier() -> bool:
	return true


func prompt_text() -> String:
	if QuestsScript.quest_of_npc(key).is_empty():
		return "Click: talk to %s" % giver
	return "Click: talk to %s  (waiting for a parcel)" % giver


func _make_mark() -> void:
	_mark = Label3D.new()
	_mark.text = MARK_MAIN if main_quest else MARK_SIDE
	_mark.font_size = 96
	_mark.pixel_size = 0.004
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.modulate = Color(1.0, 0.82, 0.25)
	_mark.outline_size = 14
	_mark.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	if bounds.size != Vector3.ZERO:
		_mark_y = bounds.end.y + 0.4
	_mark.position = Vector3(0.0, _mark_y, 0.0)
	add_child(_mark)


func _process(delta: float) -> void:
	if _mark == null:
		return
	_t += delta
	_mark.position.y = _mark_y + sin(_t * 2.2) * 0.04
	_mark.visible = QuestsScript.quest_of_npc(key).is_empty()
