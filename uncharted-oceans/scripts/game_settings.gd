extends Node
## The player's settings (the pause menu's sliders and graphics quality buttons). Autoload "GameSettings".
##   music_volume     0..1, turns the Music bus down from MusicManager.music_db. Starts at 50 %.
##   ambience_volume  0..1, turns the Ambience bus down from Ambience.ambience_db.
##   quality_level    0 Low, 1 Medium, 2 High. It sets SkySystem.volumetric_quality to the same number and the water:
##                      Low     Standard water, Low volumetric storms (fewer steps, no fine detail), flat fair-weather clouds
##                      Medium  Standard water, Medium storms, flat clouds. This is the project's own default.
##                      High    High water (Ocean.water_quality = 1, the O key), High storms and volumetric cumulus clouds
##   mouse_sensitivity  0.25..2, a multiplier on the player's own mouse_sensitivity (1 = as the scene sets it).
##   fullscreen         the window mode. Until the player has touched it, the project's own window setting stands.
## Saved in user://settings.cfg (call save() when a change is done). Until the player has touched the quality
## buttons nothing here changes the scene's own quality settings. An older settings file only has a high_quality
## yes/no: yes becomes High, no becomes Medium.

const PATH := "user://settings.cfg"
const DEFAULT_MUSIC := 0.5
const DEFAULT_AMBIENCE := 1.0

const LOW := 0
const MEDIUM := 1
const HIGH := 2
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High"]

var music_volume := DEFAULT_MUSIC
var ambience_volume := DEFAULT_AMBIENCE
var quality_level := MEDIUM
var mouse_sensitivity := 1.0
var fullscreen := false

var _quality_chosen := false
var _fullscreen_chosen := false
var _ocean: Ocean


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_apply_music()
	_apply_ambience()
	if _fullscreen_chosen:
		_apply_fullscreen()
	else:
		fullscreen = DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	get_tree().node_added.connect(_on_node_added)
	if _quality_chosen:
		_apply_quality.call_deferred()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_music()


func set_ambience_volume(v: float) -> void:
	ambience_volume = clampf(v, 0.0, 1.0)
	_apply_ambience()


func set_mouse_sensitivity(v: float) -> void:
	mouse_sensitivity = clampf(v, 0.25, 2.0)
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null:
		_apply_mouse(pl)


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_fullscreen_chosen = true
	_apply_fullscreen()


func set_quality(level: int) -> void:
	quality_level = clampi(level, LOW, HIGH)
	_quality_chosen = true
	_apply_quality()


## What the buttons show: the tier the player chose, or until they have chosen one, what the scene is running with.
func current_quality() -> int:
	if _quality_chosen:
		return quality_level
	var oc := _find_ocean()
	if oc != null and oc.water_quality >= 1:
		return HIGH
	var sky := get_tree().get_first_node_in_group("sky_system")
	if sky != null and int(sky.get("volumetric_quality")) <= 0:
		return LOW
	return MEDIUM


## Old yes/no form, kept so nothing that still calls it breaks.
func set_high_quality(on: bool) -> void:
	set_quality(HIGH if on else MEDIUM)


func is_high_quality() -> bool:
	return current_quality() >= HIGH


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)            # keep anything else in the file; a missing file is fine
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "ambience_volume", ambience_volume)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	if _fullscreen_chosen:
		cfg.set_value("display", "fullscreen", fullscreen)
	if _quality_chosen:
		cfg.set_value("graphics", "quality", quality_level)
	cfg.save(PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	ambience_volume = clampf(float(cfg.get_value("audio", "ambience_volume", ambience_volume)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)), 0.25, 2.0)
	if cfg.has_section_key("display", "fullscreen"):
		fullscreen = bool(cfg.get_value("display", "fullscreen"))
		_fullscreen_chosen = true
	if cfg.has_section_key("graphics", "quality"):
		quality_level = clampi(int(cfg.get_value("graphics", "quality")), LOW, HIGH)
		_quality_chosen = true
	elif cfg.has_section_key("graphics", "high_quality"):
		quality_level = HIGH if bool(cfg.get_value("graphics", "high_quality")) else MEDIUM
		_quality_chosen = true


func _apply_music() -> void:
	var m := get_tree().get_first_node_in_group("music")
	if m != null:
		m.set("music_volume", music_volume)


func _apply_ambience() -> void:
	var a := get_tree().get_first_node_in_group("ambience")
	if a != null:
		a.set("ambience_volume", ambience_volume)


## The player's base sensitivity is kept on it as metadata the first time, so changing the slider never compounds.
func _apply_mouse(pl: Node) -> void:
	if not ("mouse_sensitivity" in pl):
		return
	if not pl.has_meta("base_mouse_sensitivity"):
		pl.set_meta("base_mouse_sensitivity", float(pl.get("mouse_sensitivity")))
	pl.set("mouse_sensitivity", float(pl.get_meta("base_mouse_sensitivity")) * mouse_sensitivity)


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_quality() -> void:
	if not _quality_chosen:
		return
	var oc := _find_ocean()
	if oc != null:
		oc.water_quality = 1 if quality_level >= HIGH else 0
	var sky := get_tree().get_first_node_in_group("sky_system")
	if sky != null:
		sky.set("volumetric_quality", quality_level)


## A new scene's ocean or sky gets the chosen quality too (deferred: they are not ready yet when they are added).
func _on_node_added(n: Node) -> void:
	if n is CharacterBody3D and ("mouse_sensitivity" in n):
		_apply_mouse.call_deferred(n)
	if _quality_chosen and (n is Ocean or n is SkySystem):
		_ocean = null
		_apply_quality.call_deferred()


func _find_ocean() -> Ocean:
	if _ocean != null and is_instance_valid(_ocean):
		return _ocean
	_ocean = _search(get_tree().current_scene)
	return _ocean


func _search(n: Node) -> Ocean:
	if n == null:
		return null
	if n is Ocean:
		return n as Ocean
	for c in n.get_children():
		var r := _search(c)
		if r != null:
			return r
	return null
