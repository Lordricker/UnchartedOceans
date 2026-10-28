extends Node3D
## Sky test bench: scrub the time of day and the weather, spawn storms, and look at the sky from the deck.
##
## Drag with the mouse to look around. H hides the panel, B hides the ship, F12 saves a screenshot.
## Batch mode: run this scene with the user argument --sky-shots to save a picture of every preset into
## res://tests/sky_shots/ and quit.

const SkySystemScript := preload("res://scripts/sky_system.gd")
const Palette := preload("res://scripts/sky_palette.gd")
const SHOT_DIR := "res://tests/sky_shots"

# "cell" (optional): a storm to spawn with the preset. b = compass bearing, d = distance km, r = radius km, i = intensity.
const PRESETS: Array[Dictionary] = [
	{"name": "clean_sunset", "label": "Clean sunset", "t": 17.95, "a": 0, "b": 0, "mix": 0.0, "cov": 0.40, "cir": 0.55, "ovc": 0.0, "storm": 0.0},
	{"name": "golden_hour", "label": "Golden hour", "t": 17.4, "a": 0, "b": 0, "mix": 0.0, "cov": 0.35, "cir": 0.30, "ovc": 0.0, "storm": 0.0},
	{"name": "dust_sunset", "label": "Dust sunset", "t": 17.95, "a": 2, "b": 2, "mix": 0.0, "cov": 0.35, "cir": 0.60, "ovc": 0.0, "storm": 0.0},
	{"name": "tropical_dusk", "label": "Tropical dusk", "t": 18.25, "a": 3, "b": 3, "mix": 0.0, "cov": 0.50, "cir": 0.50, "ovc": 0.0, "storm": 0.0},
	{"name": "after_storm", "label": "After the storm", "t": 17.8, "a": 4, "b": 4, "mix": 0.0, "cov": 0.60, "cir": 0.35, "ovc": 0.0, "storm": 0.0},
	{"name": "dawn_haze", "label": "Dawn haze", "t": 5.75, "a": 1, "b": 1, "mix": 0.0, "cov": 0.30, "cir": 0.40, "ovc": 0.0, "storm": 0.0},
	{"name": "clear_noon", "label": "Clear noon", "t": 12.0, "a": 0, "b": 0, "mix": 0.0, "cov": 0.30, "cir": 0.15, "ovc": 0.0, "storm": 0.0},
	{"name": "overcast", "label": "Overcast", "t": 12.0, "a": 0, "b": 0, "mix": 0.0, "cov": 0.60, "cir": 0.20, "ovc": 0.85, "storm": 0.15},
	{"name": "storm_sky", "label": "Storm sky", "t": 15.5, "a": 0, "b": 0, "mix": 0.0, "cov": 0.80, "cir": 0.20, "ovc": 0.95, "storm": 0.85},
	{"name": "night", "label": "Night", "t": 0.0, "a": 0, "b": 0, "mix": 0.0, "cov": 0.15, "cir": 0.15, "ovc": 0.0, "storm": 0.0},
	# "moon" (optional): the moon's phase, 0 new .. 0.5 full. The batch shots look at the moon for these.
	{"name": "moon_full_clear", "label": "Full moon, clear", "t": 22.0, "a": 0, "b": 0, "mix": 0.0, "cov": 0.10, "cir": 0.05, "ovc": 0.0, "storm": 0.0, "moon": 0.5},
	{"name": "moon_crescent", "label": "Crescent at dusk", "t": 19.3, "a": 0, "b": 0, "mix": 0.0, "cov": 0.20, "cir": 0.25, "ovc": 0.0, "storm": 0.0, "moon": 0.12},
	{"name": "moon_gibbous", "label": "Gibbous", "t": 21.0, "a": 0, "b": 0, "mix": 0.0, "cov": 0.15, "cir": 0.10, "ovc": 0.0, "storm": 0.0, "moon": 0.38},
	{"name": "moon_thin_cloud", "label": "Moon, thin cloud (fuzzy)", "t": 22.0, "a": 0, "b": 0, "mix": 0.0, "cov": 0.45, "cir": 0.70, "ovc": 0.0, "storm": 0.0, "moon": 0.5},
	{"name": "moon_broken_cloud", "label": "Moon, broken cloud", "t": 22.0, "a": 0, "b": 0, "mix": 0.0, "cov": 0.60, "cir": 0.15, "ovc": 0.0, "storm": 0.0, "moon": 0.5},
	{"name": "moon_overcast", "label": "Moon, overcast", "t": 22.0, "a": 0, "b": 0, "mix": 0.0, "cov": 0.60, "cir": 0.20, "ovc": 0.85, "storm": 0.15, "moon": 0.5},
	{"name": "moon_rising", "label": "Harvest moon rising", "t": 18.5, "a": 1, "b": 1, "mix": 0.0, "cov": 0.20, "cir": 0.25, "ovc": 0.0, "storm": 0.0, "moon": 0.5},
	{"name": "moon_daytime", "label": "Moon by day", "t": 15.5, "a": 0, "b": 0, "mix": 0.0, "cov": 0.25, "cir": 0.15, "ovc": 0.0, "storm": 0.0, "moon": 0.3},
	{"name": "cell_sunset", "label": "Storm at sunset", "t": 17.75, "a": 0, "b": 0, "mix": 0.0, "cov": 0.30, "cir": 0.50, "ovc": 0.0, "storm": 0.0,
		"cell": {"b": 235.0, "d": 32.0, "r": 30.0, "i": 1.0}},
	{"name": "cell_noon", "label": "Storm at noon", "t": 13.5, "a": 0, "b": 0, "mix": 0.0, "cov": 0.35, "cir": 0.15, "ovc": 0.0, "storm": 0.0,
		"cell": {"b": 270.0, "d": 25.0, "r": 30.0, "i": 1.0}},
	{"name": "cell_night", "label": "Storm at night", "t": 22.0, "a": 0, "b": 0, "mix": 0.0, "cov": 0.20, "cir": 0.15, "ovc": 0.0, "storm": 0.0,
		"cell": {"b": 200.0, "d": 24.0, "r": 30.0, "i": 1.0}},
	{"name": "cell_close", "label": "Storm close", "t": 16.2, "a": 3, "b": 3, "mix": 0.0, "cov": 0.40, "cir": 0.20, "ovc": 0.0, "storm": 0.0,
		"cell": {"b": 300.0, "d": 14.0, "r": 30.0, "i": 1.0}},
]

@onready var sky: SkySystemScript = $SkySystem
@onready var cam: Camera3D = $Camera3D
@onready var brig: Node3D = $Brig

var _yaw := 90.0
var _pitch := 8.0
var _drag := false
var _panel: PanelContainer
var _readout: Label
var _sliders := {}
var _air_a: OptionButton
var _air_b: OptionButton

func _ready() -> void:
	sky.storm_time_scale = 30.0
	_make_sea()
	_build_ui()
	_apply_cam()
	_sync_ui()
	if "--sky-shots" in OS.get_cmdline_user_args():
		_capture_all.call_deferred()

func _process(_delta: float) -> void:
	var e := sky.sun_elevation_deg()
	var h := int(sky.time_hours)
	var m := int((sky.time_hours - h) * 60.0)
	_readout.text = "%02d:%02d   sun %+.1f deg   moon: %s, %+.0f deg" % [h, m, e, SkySystemScript.phase_name(sky.moon_phase), sky.moon_elevation_deg()]
	if sky.hours_per_second > 0.0:
		(_sliders["time"] as HSlider).set_value_no_signal(sky.time_hours)
	if not sky.storms.is_empty():
		var c: StormCell = sky.storms[0]
		(_sliders["sdist"] as HSlider).set_value_no_signal(clampf(sky.distance_to(c) / 1000.0, 0.0, 70.0))
		(_sliders["sbear"] as HSlider).set_value_no_signal(sky.bearing_to(c))

# ---------------------------------------------------------------- scene bits

func _make_sea() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(40000.0, 40000.0)
	mi.mesh = pm

	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.02
	var nt := NoiseTexture2D.new()
	nt.noise = fn
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 8.0
	nt.generate_mipmaps = true

	var m := StandardMaterial3D.new()
	m.albedo_color = Color("0b2a3a")
	m.roughness = 0.14
	m.metallic_specular = 0.7
	m.normal_enabled = true
	m.normal_texture = nt
	m.normal_scale = 0.5
	m.uv1_scale = Vector3(2500.0, 2500.0, 1.0)
	mi.material_override = m
	add_child(mi)

func _apply_cam() -> void:
	_pitch = clampf(_pitch, -20.0, 85.0)
	cam.rotation_degrees = Vector3(_pitch, _yaw, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
	elif event is InputEventMouseMotion and _drag:
		_yaw -= event.relative.x * 0.12
		_pitch -= event.relative.y * 0.12
		_apply_cam()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_H:
				_panel.visible = not _panel.visible
			KEY_B:
				brig.visible = not brig.visible
			KEY_F12:
				_save_shot("manual_%d" % Time.get_ticks_msec())

# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_panel = PanelContainer.new()
	_panel.position = Vector2(12.0, 12.0)
	layer.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300.0, minf(900.0, get_viewport().get_visible_rect().size.y - 50.0))
	_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	scroll.add_child(box)

	_readout = Label.new()
	box.add_child(_readout)

	_add_slider(box, "time", "Time of day (hours)", 0.0, 24.0, 0.01, func(v: float) -> void: sky.time_hours = v)
	_add_slider(box, "speed", "Time speed (hours per second)", 0.0, 1.0, 0.01, func(v: float) -> void: sky.hours_per_second = v)
	_add_slider(box, "cov", "Cloud coverage", 0.0, 1.0, 0.01, func(v: float) -> void: sky.coverage = v)
	_add_slider(box, "cir", "Cirrus (high streaks)", 0.0, 1.0, 0.01, func(v: float) -> void: sky.cirrus = v)
	_add_slider(box, "ovc", "Overcast", 0.0, 1.0, 0.01, func(v: float) -> void: sky.overcast = v)
	_add_slider(box, "storm", "Storm darkness", 0.0, 1.0, 0.01, func(v: float) -> void: sky.storm = v)
	_add_slider(box, "wind", "Cloud drift direction (deg)", 0.0, 360.0, 1.0, func(v: float) -> void: sky.wind_dir_deg = v)
	_add_slider(box, "moon", "Moon phase (0 new, 0.25 first quarter, 0.5 full)", 0.0, 1.0, 0.01, func(v: float) -> void: sky.moon_phase = v)

	_air_a = _add_option(box, "Air type", func(i: int) -> void: sky.air_a = i)
	_air_b = _add_option(box, "Blend toward", func(i: int) -> void: sky.air_b = i)
	_add_slider(box, "mix", "Blend amount", 0.0, 1.0, 0.01, func(v: float) -> void: sky.air_mix = v)

	box.add_child(HSeparator.new())
	var sl := Label.new()
	sl.text = "STORM CELL"
	box.add_child(sl)
	_add_slider(box, "sbear", "Storm direction (compass deg, 0 = N, 90 = E)", 0.0, 360.0, 1.0, _on_storm_moved)
	_add_slider(box, "sdist", "Storm distance (km)", 0.0, 70.0, 0.1, _on_storm_moved)
	_add_slider(box, "srad", "Storm front length (half, km; 25-75 = squall line)", 5.0, 80.0, 1.0, func(v: float) -> void:
		if not sky.storms.is_empty():
			sky.storms[0].set_size(v * 1000.0))
	_add_slider(box, "sint", "Storm strength", 0.0, 1.0, 0.01, func(v: float) -> void:
		if not sky.storms.is_empty():
			sky.storms[0].intensity = v)
	_add_slider(box, "sts", "Storm speed (x real life; 30 = fast)", 0.0, 200.0, 1.0, func(v: float) -> void: sky.storm_time_scale = v)
	var srow := HBoxContainer.new()
	box.add_child(srow)
	var sp := Button.new()
	sp.text = "Spawn storm"
	sp.pressed.connect(_spawn_from_sliders)
	srow.add_child(sp)
	var cl := Button.new()
	cl.text = "Clear storms"
	cl.pressed.connect(func() -> void: sky.clear_storms())
	srow.add_child(cl)

	box.add_child(HSeparator.new())
	var presets_label := Label.new()
	presets_label.text = "Presets"
	box.add_child(presets_label)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for p in PRESETS:
		var b := Button.new()
		b.text = p["label"]
		b.pressed.connect(_apply_preset.bind(p))
		grid.add_child(b)

	var hint := Label.new()
	hint.text = "Drag: look   H: panel   B: ship   F12: screenshot"
	box.add_child(hint)

func _add_slider(parent: Container, key: String, text: String, lo: float, hi: float, step: float, on_change: Callable) -> void:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(260.0, 18.0)
	s.value_changed.connect(on_change)
	parent.add_child(s)
	_sliders[key] = s

func _add_option(parent: Container, text: String, on_pick: Callable) -> OptionButton:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	var ob := OptionButton.new()
	for n in Palette.AIR_NAMES:
		ob.add_item(n)
	ob.item_selected.connect(on_pick)
	parent.add_child(ob)
	return ob

func _sync_ui() -> void:
	(_sliders["time"] as HSlider).set_value_no_signal(sky.time_hours)
	(_sliders["speed"] as HSlider).set_value_no_signal(sky.hours_per_second)
	(_sliders["cov"] as HSlider).set_value_no_signal(sky.coverage)
	(_sliders["cir"] as HSlider).set_value_no_signal(sky.cirrus)
	(_sliders["ovc"] as HSlider).set_value_no_signal(sky.overcast)
	(_sliders["storm"] as HSlider).set_value_no_signal(sky.storm)
	(_sliders["wind"] as HSlider).set_value_no_signal(sky.wind_dir_deg)
	(_sliders["moon"] as HSlider).set_value_no_signal(sky.moon_phase)
	(_sliders["mix"] as HSlider).set_value_no_signal(sky.air_mix)
	(_sliders["sts"] as HSlider).set_value_no_signal(sky.storm_time_scale)
	if sky.storms.is_empty():
		(_sliders["sbear"] as HSlider).set_value_no_signal(250.0)
		(_sliders["sdist"] as HSlider).set_value_no_signal(30.0)
		(_sliders["srad"] as HSlider).set_value_no_signal(30.0)
		(_sliders["sint"] as HSlider).set_value_no_signal(1.0)
	else:
		var c: StormCell = sky.storms[0]
		(_sliders["srad"] as HSlider).set_value_no_signal(c.radius_m / 1000.0)
		(_sliders["sint"] as HSlider).set_value_no_signal(c.intensity)
	_air_a.select(sky.air_a)
	_air_b.select(sky.air_b)

func _apply_preset(p: Dictionary) -> void:
	sky.time_hours = p["t"]
	sky.air_a = p["a"]
	sky.air_b = p["b"]
	sky.air_mix = p["mix"]
	sky.coverage = p["cov"]
	sky.cirrus = p["cir"]
	sky.overcast = p["ovc"]
	sky.storm = p["storm"]
	if p.has("moon"):
		sky.moon_phase = p["moon"]
	sky.clear_storms()
	if p.has("cell"):
		var c: Dictionary = p["cell"]
		var r: float = c["r"]
		sky.add_storm(c["b"], c["d"] * 1000.0, r * 1000.0, c["i"])
		_yaw = -float(c["b"])
		_apply_cam()
	_sync_ui()

# ---------------------------------------------------------------- storm controls

func _spawn_from_sliders() -> void:
	sky.clear_storms()
	var r: float = (_sliders["srad"] as HSlider).value
	sky.add_storm((_sliders["sbear"] as HSlider).value, maxf((_sliders["sdist"] as HSlider).value, 1.0) * 1000.0,
		r * 1000.0, (_sliders["sint"] as HSlider).value)
	_yaw = -(_sliders["sbear"] as HSlider).value
	_apply_cam()

## Dragging the direction or distance slider moves the first storm there.
func _on_storm_moved(_v: float) -> void:
	if sky.storms.is_empty():
		return
	var c: StormCell = sky.storms[0]
	var obs := Vector2(cam.global_position.x, cam.global_position.z)
	var b := deg_to_rad((_sliders["sbear"] as HSlider).value)
	var d := maxf((_sliders["sdist"] as HSlider).value, 0.5) * 1000.0
	c.pos = obs + Vector2(sin(b), -cos(b)) * d
	c.velocity = (obs - c.pos).normalized() * c.velocity.length()

# ---------------------------------------------------------------- screenshots

func _save_shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s.png" % [dir, file_name]
	img.save_png(path)
	print("saved ", path)

func _capture_all() -> void:
	_panel.visible = false
	brig.visible = false
	sky.hours_per_second = 0.0
	sky.storm_time_scale = 0.0
	for i in 15:
		await get_tree().process_frame   # let the noise textures finish generating
	for p in PRESETS:
		_apply_preset(p)
		var sd: Vector3 = sky.sun_direction()
		var toward := rad_to_deg(atan2(-sd.x, -sd.z))
		var views := [["sun", toward], ["away", toward + 180.0]]
		if p.has("cell"):
			views = [["storm", -float(p["cell"]["b"])], ["sun", toward]]
		if p.has("moon"):
			var md: Vector3 = sky.moon_direction()
			views = [["moon", rad_to_deg(atan2(-md.x, -md.z)), clampf(sky.moon_elevation_deg(), 4.0, 55.0)]]
		for view in views:
			_yaw = view[1]
			_pitch = float(view[2]) if view.size() > 2 else 14.0
			_apply_cam()
			for i in 4:
				if p["name"] == "cell_night" and not sky.storms.is_empty():
					sky.storms[0].flash = 1.0   # show a lightning flash in the picture
				await get_tree().process_frame
			if p["name"] == "cell_night" and not sky.storms.is_empty():
				sky.storms[0].flash = 1.0
			await _save_shot("%s_%s" % [p["name"], view[0]])
	get_tree().quit()
