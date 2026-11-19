extends Node3D
## The main menu (the project's main scene). Play, Tutorial, Options, Quit over a live backdrop: the brig riding the
## real ocean under the game's own sky at golden hour, with a slow drifting camera.
##
## Play loads res://scenes/world_capital_start.tscn (GameSession.GAME_SCENE), Tutorial loads GameSession.TUTORIAL_SCENE, in the
## background with a "Setting sail" line and a fade. Tutorial sets GameSession.tutorial = true (no saving).
## Options: Music, Ambient, Graphics (Low/Medium/High), Mouse sensitivity, Fullscreen, all kept by GameSettings in
## user://settings.cfg (saved on Back). Esc closes Options.

const BRIG_PATH := "res://assets/ships/brig/Brig.glb"
const OCEAN_SHADER := "res://shaders/ocean.gdshader"
const TITLE_FONT := "res://assets/fonts/Ferrum-ExtraCondensed.otf"
const BODY_FONT := "res://assets/fonts/IMFellEnglish-Italic.ttf"
const GOLD := Color(0.86, 0.72, 0.45)
const CREAM := Color(1.0, 0.97, 0.9)
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High"]
const QUALITY_NOTES: Array[String] = [
	"The lightest storm clouds and standard water. For older graphics cards.",
	"Full storm clouds, standard water, light haze and soft shadows. The default.",
	"Volumetric cumulus clouds, sharper storms, detailed water and ambient occlusion with bounce light. A heavy load for the graphics card.",
]
const HINTS := {
	"play": "Set out from the capital.",
	"tutorial": "A short first voyage with Captain Cobb: trade, sail, navigate, dock. Nothing is saved.",
	"options": "Sound, graphics and controls.",
	"quit": "Back to dry land.",
}

## Backdrop
@export var time_of_day := 17.4
@export var orbit_distance := 36.0
@export var orbit_center_deg := 40.0     ## 0 = dead ahead of the bow, 90 = starboard beam
@export var orbit_swing_deg := 22.0
@export var orbit_speed := 0.025
@export var screen_shift := -9.0         ## Camera h_offset: pushes the ship to the right, away from the buttons

var _title_font: Font
var _body_font: Font
var _ocean: Ocean
var _brig: Node3D
var _cam: Camera3D
var _t := 0.0
var _pitch := 0.0
var _roll := 0.0

var _main_box: VBoxContainer
var _options: PanelContainer
var _hint: Label
var _loading_label: Label
var _fade: ColorRect
var _buttons: Array[Button] = []
var _music: HSlider
var _music_v: Label
var _amb: HSlider
var _amb_v: Label
var _sens: HSlider
var _sens_v: Label
var _full: CheckButton
var _tiers: Array[Button] = []
var _tier_note: Label
var _loading := false
var _load_t := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	if ResourceLoader.exists(TITLE_FONT):
		_title_font = load(TITLE_FONT)
	if ResourceLoader.exists(BODY_FONT):
		_body_font = load(BODY_FONT)
	_build_world()
	_build_ui()
	_buttons[0].grab_focus()


# ------------------------------------------------------------------ backdrop

func _build_world() -> void:
	# the same environment as the game's world scenes (world_capital_start.tscn); SkySystem takes the sky over
	var sky_mat := ProceduralSkyMaterial.new()
	var sky_res := Sky.new()
	sky_res.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky_res
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.52, 0.56, 0.6)
	env.fog_density = 0.0004
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)

	_cam = Camera3D.new()
	_cam.name = "Camera3D"
	_cam.far = 60000.0
	_cam.fov = 60.0
	_cam.h_offset = screen_shift
	add_child(_cam)
	_cam.current = true

	_ocean = Ocean.new()
	_ocean.name = "Ocean"
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	fn.fractal_octaves = 4
	var foam := NoiseTexture2D.new()
	foam.width = 256
	foam.height = 256
	foam.seamless = true
	foam.generate_mipmaps = true
	foam.noise = fn
	var sea := ShaderMaterial.new()
	sea.shader = load(OCEAN_SHADER)
	sea.set_shader_parameter("foam_noise", foam)
	_ocean.material_override = sea
	_ocean.curvature_radius_m = 6370000.0
	_ocean.radius = 24000.0
	add_child(_ocean)

	var sky := SkySystem.new()
	sky.name = "SkySystem"
	sky.debug_overlay = false
	sky.world_environment = we
	sky.sun = sun
	sky.observer = _cam
	sky.time_hours = time_of_day
	sky.hours_per_second = 0.0
	sky.coverage = 0.38
	sky.cirrus = 0.4
	add_child(sky)

	if ResourceLoader.exists(BRIG_PATH):
		_brig = (load(BRIG_PATH) as PackedScene).instantiate() as Node3D
		_brig.name = "Brig"
		add_child(_brig)
	_place(0.0)


func _process(delta: float) -> void:
	_t += delta
	_place(delta)
	if _loading:
		_poll_load(delta)


## The brig rides the waves (heave, pitch, roll from the ocean's own heights) and the camera drifts round her bow quarter.
func _place(delta: float) -> void:
	var center := Vector3.ZERO
	if _brig != null and _ocean != null and _ocean.is_node_ready():
		var h := _ocean.get_height(0.0, 0.0)
		var hf := _ocean.get_height(0.0, 8.0)     # the bow is +Z in the glb
		var ha := _ocean.get_height(0.0, -8.0)
		var hs := _ocean.get_height(3.0, 0.0)
		var hp := _ocean.get_height(-3.0, 0.0)
		var k := 1.0 - exp(-delta * 2.0) if delta > 0.0 else 1.0
		_pitch = lerpf(_pitch, atan2(hf - ha, 16.0) * 0.6, k)
		_roll = lerpf(_roll, atan2(hs - hp, 6.0) * 0.6, k)
		_brig.position = Vector3(0.0, lerpf(_brig.position.y, h * 0.8, k), 0.0)
		_brig.basis = Basis.from_euler(Vector3(-_pitch, 0.0, _roll))
		center = _brig.position
	var a := deg_to_rad(orbit_center_deg + sin(_t * orbit_speed) * orbit_swing_deg)
	var pos := center + Vector3(sin(a) * orbit_distance, 5.5 + sin(_t * 0.21) * 0.35, cos(a) * orbit_distance)
	_cam.look_at_from_position(pos, center + Vector3(0.0, 6.5, 0.0), Vector3.UP)


# ------------------------------------------------------------------ buttons

var _scene := ""


func _scene_for(tutorial: bool) -> String:
	return GameSession.TUTORIAL_SCENE if tutorial else GameSession.GAME_SCENE


func _on_play(tutorial: bool) -> void:
	if _loading:
		return
	var gs := get_node_or_null("/root/GameSession")
	if gs != null:
		gs.call("start_game", tutorial)
	_scene = _scene_for(tutorial)
	if ResourceLoader.load_threaded_request(_scene) != OK:
		get_tree().change_scene_to_file(_scene)
		return
	_loading = true
	_load_t = 0.0
	for b in _buttons:
		b.disabled = true
	_hint.text = ""
	_loading_label.visible = true
	_fade.visible = true


func _poll_load(delta: float) -> void:
	_load_t += delta
	var dots := ".".repeat(1 + int(_load_t * 2.0) % 3)
	var scene := _scene
	var progress := []
	var st := ResourceLoader.load_threaded_get_status(scene, progress)
	var pct := int(100.0 * float(progress[0])) if progress.size() > 0 else 0
	_loading_label.text = "Setting sail%s  %d%%" % [dots, pct]
	_fade.color.a = clampf(_load_t / 1.2, 0.0, 0.85)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		_loading = false
		var packed := ResourceLoader.load_threaded_get(scene) as PackedScene
		get_tree().change_scene_to_packed(packed)
	elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_loading = false
		push_error("MainMenu: could not load %s" % scene)
		_loading_label.text = "The game scene failed to load (see the Output panel)."
		_fade.visible = false
		for b in _buttons:
			b.disabled = false


func _show_options(on: bool) -> void:
	_options.visible = on
	_main_box.visible = not on
	if on:
		_sync_options()
	else:
		var gs := _settings()
		if gs != null:
			gs.call("save")
		_buttons[2].grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE and _options.visible:
		_show_options(false)
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ options

func _settings() -> Node:
	return get_node_or_null("/root/GameSettings")


func _sync_options() -> void:
	var gs := _settings()
	if gs == null:
		return
	_music.set_value_no_signal(roundf(float(gs.get("music_volume")) * 100.0))
	_music_v.text = "%d%%" % int(_music.value)
	_amb.set_value_no_signal(roundf(float(gs.get("ambience_volume")) * 100.0))
	_amb_v.text = "%d%%" % int(_amb.value)
	_sens.set_value_no_signal(roundf(float(gs.get("mouse_sensitivity")) * 100.0))
	_sens_v.text = "%d%%" % int(_sens.value)
	_full.set_pressed_no_signal(bool(gs.get("fullscreen")))
	_show_tier(int(gs.call("current_quality")))


func _show_tier(level: int) -> void:
	level = clampi(level, 0, 2)
	for i in _tiers.size():
		_tiers[i].set_pressed_no_signal(i == level)
	_tier_note.text = QUALITY_NOTES[level]


# ------------------------------------------------------------------ the screen

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	# a dark wash on the left so the words read over the sky
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.02, 0.03, 0.82))
	grad.set_color(1, Color(0.02, 0.02, 0.03, 0.0))
	grad.set_offset(1, 1.0)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var wash := TextureRect.new()
	wash.texture = gt
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.anchor_right = 0.55
	wash.anchor_bottom = 1.0
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wash)

	var column := VBoxContainer.new()
	column.anchor_top = 0.0
	column.anchor_bottom = 1.0
	column.offset_left = 130.0
	column.offset_right = 900.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	root.add_child(column)

	column.add_child(_label("Uncharted Oceans", _title_font, 120, GOLD))
	var sub := _label("A voyage in the age of sail", _body_font, 30, Color(CREAM, 0.75))
	column.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 48)
	column.add_child(gap)

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 4)
	column.add_child(_main_box)
	_add_menu_button("Play", "play", _on_play.bind(false))
	_add_menu_button("Tutorial", "tutorial", _on_play.bind(true))
	_add_menu_button("Options", "options", _show_options.bind(true))
	_add_menu_button("Quit", "quit", func() -> void: get_tree().quit())
	var hint_gap := Control.new()
	hint_gap.custom_minimum_size = Vector2(0, 14)
	_main_box.add_child(hint_gap)
	_hint = _label("", _body_font, 24, Color(CREAM, 0.7))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(560, 70)
	_main_box.add_child(_hint)

	_options = _make_options()
	_options.visible = false
	column.add_child(_options)

	_loading_label = _label("Setting sail", _title_font, 40, GOLD)
	_loading_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_loading_label.offset_left = -520.0
	_loading_label.offset_top = -110.0
	_loading_label.offset_right = -80.0
	_loading_label.offset_bottom = -50.0
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_loading_label.visible = false

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade.visible = false
	root.add_child(_fade)
	root.add_child(_loading_label)


func _add_menu_button(text: String, key: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.custom_minimum_size = Vector2(320, 64)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if _title_font != null:
		b.add_theme_font_override("font", _title_font)
	b.add_theme_font_size_override("font_size", 56)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_pressed_color", Color(GOLD, 0.8))
	b.add_theme_color_override("font_disabled_color", Color(CREAM, 0.35))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("outline_size", 5)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	b.mouse_entered.connect(func() -> void:
		b.grab_focus())
	b.focus_entered.connect(func() -> void:
		if not _loading:
			_hint.text = HINTS[key])
	_main_box.add_child(b)
	_buttons.append(b)


func _make_options() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.085, 0.07, 0.055, 0.92)
	sb.border_color = Color(0.62, 0.48, 0.28)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label("Options", _title_font, 46, GOLD))
	box.add_child(HSeparator.new())

	var r := _slider_row(box, "Music", 0.0, 100.0)
	_music = r[0]
	_music_v = r[1]
	_music.value_changed.connect(func(v: float) -> void:
		_music_v.text = "%d%%" % int(v)
		if _settings() != null: _settings().call("set_music_volume", v / 100.0))
	r = _slider_row(box, "Ambient", 0.0, 100.0)
	_amb = r[0]
	_amb_v = r[1]
	_amb.value_changed.connect(func(v: float) -> void:
		_amb_v.text = "%d%%" % int(v)
		if _settings() != null: _settings().call("set_ambience_volume", v / 100.0))
	r = _slider_row(box, "Mouse", 25.0, 200.0)
	_sens = r[0]
	_sens_v = r[1]
	_sens.value_changed.connect(func(v: float) -> void:
		_sens_v.text = "%d%%" % int(v)
		if _settings() != null: _settings().call("set_mouse_sensitivity", v / 100.0))

	box.add_child(_label("Graphics", _title_font, 26, CREAM))
	var tiers := HBoxContainer.new()
	tiers.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for i in QUALITY_NAMES.size():
		var b := _tier_button(QUALITY_NAMES[i], group)
		b.pressed.connect(func() -> void:
			if _settings() != null: _settings().call("set_quality", i)
			_show_tier(i))
		tiers.add_child(b)
		_tiers.append(b)
	box.add_child(tiers)
	_tier_note = _label(QUALITY_NOTES[1], _title_font, 18, Color(1, 1, 1, 0.55))
	_tier_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tier_note.custom_minimum_size = Vector2(500, 0)
	box.add_child(_tier_note)

	_full = CheckButton.new()
	_full.text = "Fullscreen"
	if _title_font != null:
		_full.add_theme_font_override("font", _title_font)
	_full.add_theme_font_size_override("font_size", 26)
	_full.add_theme_color_override("font_color", CREAM)
	_full.toggled.connect(func(on: bool) -> void:
		if _settings() != null: _settings().call("set_fullscreen", on))
	box.add_child(_full)

	box.add_child(HSeparator.new())
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 48)
	if _title_font != null:
		back.add_theme_font_override("font", _title_font)
	back.add_theme_font_size_override("font_size", 28)
	back.pressed.connect(_show_options.bind(false))
	box.add_child(back)
	return panel


## "Music  ----o----  80%". Returns [slider, value label].
func _slider_row(parent: Control, text: String, lo: float, hi: float) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var n := _label(text, _title_font, 26, CREAM)
	n.custom_minimum_size = Vector2(110, 0)
	row.add_child(n)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1.0
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(240, 28)
	row.add_child(s)
	var v := _label("100%", _title_font, 26, CREAM)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.custom_minimum_size = Vector2(70, 0)
	row.add_child(v)
	parent.add_child(row)
	return [s, v]


func _tier_button(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 46)
	if _title_font != null:
		b.add_theme_font_override("font", _title_font)
	b.add_theme_font_size_override("font_size", 26)
	var off := StyleBoxFlat.new()
	off.bg_color = Color(0.16, 0.13, 0.10)
	off.border_color = Color(CREAM, 0.55)
	off.set_border_width_all(2)
	off.set_corner_radius_all(4)
	var hover := off.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.24, 0.19, 0.13)
	var on := off.duplicate() as StyleBoxFlat
	on.bg_color = GOLD
	on.border_color = CREAM
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	var dark := Color(0.10, 0.07, 0.04)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", CREAM)
	b.add_theme_color_override("font_pressed_color", dark)
	b.add_theme_color_override("font_hover_pressed_color", dark)
	return b


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
