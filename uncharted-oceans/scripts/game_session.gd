extends Node
## How the current game was started from the main menu. Autoload "GameSession".
##   tutorial  true when the player pressed Tutorial: the tutorial scene is loaded and saving/loading is off.
## The menu calls start_game(); the pause menu calls to_main_menu().

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/world_capital_start.tscn"
## The first voyage: the cutter, Captain Cobb and a short run (tutorial_director.gd). Writes no save.
const TUTORIAL_SCENE := "res://scenes/world_tutorial.tscn"

var tutorial := false


func start_game(with_tutorial: bool) -> void:
	tutorial = with_tutorial
	TradeState.reset()
	CourierQuests.reset()
	_note("new game from the main menu%s" % (" (tutorial)" if with_tutorial else ""))


func to_main_menu() -> void:
	var tree := get_tree()
	tree.paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tutorial = false
	tree.change_scene_to_file(MENU_SCENE)


func _note(t: String) -> void:
	var ss := get_node_or_null("/root/SaveSystem")
	if ss != null:
		ss.call("note", t)
