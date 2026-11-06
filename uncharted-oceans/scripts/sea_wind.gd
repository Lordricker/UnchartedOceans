class_name SeaWind
extends Node
## The wind at the ship. One per world (group "wind"); ShipSails creates it if the scene doesn't have one.
##
## With a WorldWeather in the world (the world scene has one) the wind is whatever the weather says it is at the ship's
## position on the chart, now: the seasonal wind of that part of the world, the daily coastal breeze, and any storm.
## It is smoothed, so it shifts over many seconds rather than jumping, and on top of that it gusts and wanders a little,
## the way real wind does, which is what makes sail trim a continuing job. The sea follows the wind: the swell turns
## slowly to the new direction, and the waves build up in a few minutes after the wind rises and take longer to die down.
## (Ocean.retarget does that without any visible jump in the waves.)
##
## Without a weather node (a plain test scene) it works as it always did: the direction is the Ocean's
## wind_heading_deg and the strength follows the Ocean's sea state.
##
## Keys (in game): 1-4 set the wind to calm / moderate / rough / storm strength, [ and ] swing it 15 degrees to port /
## starboard of where it is going. In the world scene those take the wind over by hand; \ gives it back to the weather.

## True wind speed for each sea state, m/s (calm, moderate, rough, storm). About 6, 16, 27, 43 knots.
@export var speeds := PackedFloat32Array([3.0, 8.5, 14.0, 22.0])
@export var speed_scale := 1.0
## How gusty it is: 0 = steady, 0.25 = a lively breeze (gusts of +-25 %). Storms add to it.
@export_range(0.0, 0.6) var gustiness := 0.2
## How far the direction wanders, degrees either way.
@export_range(0.0, 25.0) var wander_deg := 7.0
@export var ocean_path: NodePath = ^"../Ocean"
## Follow the world's weather when there is one.
@export var use_weather := true
## Seconds the wind takes to settle on a new value (about 63 % of the way).
@export var wind_smoothing_s := 12.0
## The same for the swell's direction, and for the sea building up and dying down.
@export var swell_smoothing_s := 60.0
@export var sea_rise_s := 90.0
@export var sea_fall_s := 240.0
## Without weather: at the start, turn the wind (and the swell with it) to come from behind the ship, so she can sail
## where she points: this many degrees round from dead astern, + = from the port quarter, - = from the starboard quarter.
## Set align_to_ship off to keep the Ocean's own wind_heading_deg.
@export var align_to_ship := true
@export_range(-90.0, 90.0) var from_astern_deg := 45.0
## Close to a port (inside Ocean.port_calm_radius_m, 1.5 km) the sea is held at this level or below: 2 = rough, so
## the big storm swell never reaches a harbour approach, whether the storm is the weather's or the 4 key's. When the
## ship comes within range of a port the swell dies down over about port_calm_s seconds.
@export_range(0.0, 3.0) var port_max_sea_level := 2.0
@export var port_calm_s := 45.0

var _ocean: Ocean
var _noise := FastNoiseLite.new()
var _t := 0.0
var _speed := 6.0
var _heading := 0.0              # degrees, where the air is going (0 = toward -Z, like Ocean)
var _gust := 0.0                 # -1..1

# the weather
const WindFieldS := preload("res://scripts/wind_field.gd")
var _weather: Node               # the WorldWeather
var _streamer: Node              # the WorldStreamer
var _ship: Node3D
var _find_t := 0.0
var _sample_t := 0.0
var _ocean_t := 0.0
var _target := Vector2.ZERO      # what the weather says now (x east, z south, m/s)
var _mean := Vector2.ZERO        # smoothed
var _have_mean := false
var _mean_heading := 0.0
var _swell_heading := 0.0
var _sea_level := 1.0
var _storm := 0.0
var _snap := false
var _manual := false
var _manual_speed := 8.5
var _manual_heading := 0.0
var _near_port := false


func _ready() -> void:
	add_to_group("wind")
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = 11
	_ocean = get_node_or_null(ocean_path) as Ocean
	if _ocean == null:
		_ocean = get_tree().get_first_node_in_group("ocean") as Ocean
	_update(0.0)
	if align_to_ship:
		_align_to_ship()


func _weather_mode() -> bool:
	return use_weather and _weather != null and is_instance_valid(_weather) and _ocean != null


## Without weather: once the ship has been put where she starts (the world streamer places her a moment after the scene
## loads), turn the wind to blow the way she is pointing, off dead astern by from_astern_deg.
func _align_to_ship() -> void:
	await get_tree().create_timer(0.6).timeout
	if _weather_mode() or (use_weather and get_tree().get_first_node_in_group("weather") != null):
		return
	var ship := get_tree().get_first_node_in_group("ships")
	if ship == null or _ocean == null or ship.get("heading_deg") == null:
		return
	# the ship's heading grows to port; the wind's grows to starboard (0 = toward -Z), so "same way" is minus
	set_heading(-float(ship.get("heading_deg")) + from_astern_deg)


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo and _ocean):
		return
	if _streamer != null and _streamer.prompt_open:
		return                                  # digits typed into the sleep window are not wind keys
	if _weather_mode():
		match e.physical_keycode:
			KEY_1, KEY_2, KEY_3, KEY_4:
				if e.physical_keycode == KEY_4 and not _ocean.storm_allowed():
					_ocean.refuse_storm()          # no storm sea close to a port
					return
				_take_over(speeds[e.physical_keycode - KEY_1] * speed_scale, _mean_heading)
			KEY_BRACKETLEFT:
				_take_over(maxf(_mean.length(), 0.1) if not _manual else _manual_speed, _mean_heading - 15.0)
			KEY_BRACKETRIGHT:
				_take_over(maxf(_mean.length(), 0.1) if not _manual else _manual_speed, _mean_heading + 15.0)
			KEY_BACKSLASH:
				_manual = false
				_snap = true
				_sample_t = 0.0
	else:
		if e.physical_keycode == KEY_BRACKETLEFT:
			set_heading(base_heading() - 15.0)
		elif e.physical_keycode == KEY_BRACKETRIGHT:
			set_heading(base_heading() + 15.0)


## Take the wind over by hand (testing): a fixed speed and heading until \ is pressed.
func _take_over(speed_mps: float, heading_deg: float) -> void:
	_manual = true
	_manual_speed = speed_mps
	_manual_heading = fposmod(heading_deg, 360.0)
	_snap = true
	_sample_t = 0.0


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	_t += delta
	_find_world(delta)
	if _weather_mode():
		_update_weather(delta)
	else:
		_update_legacy()


# ------------------------------------------------------------------ with the world's weather

func _find_world(delta: float) -> void:
	_find_t -= delta
	if _find_t > 0.0:
		return
	_find_t = 1.0
	if use_weather and (_weather == null or not is_instance_valid(_weather)):
		_weather = get_tree().get_first_node_in_group("weather")
	if _streamer == null or not is_instance_valid(_streamer):
		_streamer = get_tree().get_first_node_in_group("world_streamer")
		if _streamer != null:
			_streamer.slept.connect(func(_r: Dictionary) -> void: _snap = true)


func _update_weather(delta: float) -> void:
	_sample_t -= delta
	if _sample_t <= 0.0:
		_sample_t = 0.25
		_near_port = _ocean.near_port()
		if _manual:
			_target = WindFieldS.vec(_manual_speed, _manual_heading)
			_storm = 0.0
		else:
			_target = _weather.wind_at_ship() * speed_scale
			_storm = _weather.storm_proximity_at_ship()
	if not _have_mean or _snap:
		_mean = _target
		_have_mean = true
		_swell_heading = WindFieldS.heading_of(_target)
		_sea_level = _capped_level(_level_for(_target.length()))
		_snap = false
	else:
		_mean = _mean.lerp(_target, 1.0 - exp(-delta / maxf(wind_smoothing_s, 0.01)))
	var spd := _mean.length()
	if spd > 0.4:
		_mean_heading = WindFieldS.heading_of(_mean)

	# gusts and wander on top, same bands as always: a ~9 s gust cycle and a ~35 s wander
	var g := _noise.get_noise_1d(_t / 9.0) * 0.7 + _noise.get_noise_1d(_t / 2.5 + 40.0) * 0.3
	_gust = clampf(g * 1.6, -1.0, 1.0)
	_speed = maxf(0.0, spd * (1.0 + (gustiness + 0.3 * _storm) * _gust))
	var wander := _noise.get_noise_1d(_t / 35.0 + 100.0) * 1.6
	_heading = _mean_heading + clampf(wander, -1.0, 1.0) * wander_deg

	# the sea follows: the swell turns slowly, the waves build up fast and die down slowly
	var tgt_level := _capped_level(_level_for(spd))
	_swell_heading = rad_to_deg(lerp_angle(deg_to_rad(_swell_heading), deg_to_rad(_mean_heading), 1.0 - exp(-delta / maxf(swell_smoothing_s, 0.01))))
	var tau := sea_rise_s if tgt_level > _sea_level else (port_calm_s if _near_port else sea_fall_s)
	_sea_level = lerpf(_sea_level, tgt_level, 1.0 - exp(-delta / maxf(tau, 0.01)))
	# The waves follow every frame, in tiny steps. Ocean.retarget keeps them exact only at the ship; this used to wait for
	# a 0.8 degree turn or a 0.015 change of sea level and then step, which made the water away from the ship visibly
	# jump every second or two while the sea built up or died down. Tiny steps every frame swing it round smoothly.
	var turned := absf(angle_difference(deg_to_rad(_swell_heading), deg_to_rad(_ocean.wind_heading_deg)))
	if turned > 1e-5 or absf(_sea_level - _ocean.sea_level) > 1e-5:
		_ocean.retarget(_swell_heading, _sea_level, _pivot())


## True while the world's weather owns the 1-4 keys here (the Ocean leaves them alone then).
func owns_sea_keys() -> bool:
	return _weather_mode()


## The sea level held down to port_max_sea_level while the ship is close to a port.
func _capped_level(level: float) -> float:
	return minf(level, port_max_sea_level) if _near_port else level


## Sea level (0 calm .. 3 storm, between the presets) for a wind speed, from the speeds table.
func _level_for(spd: float) -> float:
	var n := speeds.size()
	if spd <= speeds[0]:
		return 0.0
	for i in range(1, n):
		if spd <= speeds[i]:
			return float(i - 1) + inverse_lerp(speeds[i - 1], speeds[i], spd)
	return float(n - 1)


## The point the waves are kept steady around when they are retargeted: the ship, in the Godot scene.
func _pivot() -> Vector2:
	if _ship == null or not is_instance_valid(_ship):
		_ship = get_tree().get_first_node_in_group("ships") as Node3D
	if _ship == null:
		return Vector2.ZERO
	return Vector2(_ship.global_position.x, _ship.global_position.z)


# ------------------------------------------------------------------ without weather (as before)

func _update_legacy() -> void:
	var sea := 1
	if _ocean:
		sea = int(_ocean.sea_state)
	var base := speeds[clampi(sea, 0, speeds.size() - 1)] * speed_scale
	# two slow noise bands: a ~9 s gust cycle and a ~35 s wander
	var g := _noise.get_noise_1d(_t / 9.0) * 0.7 + _noise.get_noise_1d(_t / 2.5 + 40.0) * 0.3
	_gust = clampf(g * 1.6, -1.0, 1.0)
	_speed = maxf(0.0, base * (1.0 + gustiness * _gust))
	var wander := _noise.get_noise_1d(_t / 35.0 + 100.0) * 1.6
	_heading = base_heading() + clampf(wander, -1.0, 1.0) * wander_deg


# ------------------------------------------------------------------ what the rest of the game reads

## Direction the air is going, degrees, before gusts and wander.
func base_heading() -> float:
	if _weather_mode():
		return _mean_heading
	return _ocean.wind_heading_deg if _ocean else 0.0


## Swing the wind by hand. With weather, this takes the wind over until \ is pressed.
func set_heading(deg: float) -> void:
	if _ocean == null:
		return
	if _weather_mode():
		_take_over(maxf(_mean.length(), 0.1) if not _manual else _manual_speed, deg)
		return
	_ocean.wind_heading_deg = fposmod(deg, 360.0)
	_ocean.sea_state = _ocean.sea_state          # re-makes the waves for the new direction


## Velocity of the air in the world (m/s), with gusts. Y is zero.
func velocity() -> Vector3:
	var a := deg_to_rad(_heading)
	return Vector3(sin(a), 0.0, -cos(a)) * _speed


func speed() -> float:
	return _speed


func gust_amount() -> float:
	return _gust


## Where the wind is coming FROM as a compass-style bearing (0 = from -Z / "north").
func from_bearing_deg() -> float:
	return fposmod(_heading + 180.0, 360.0)
