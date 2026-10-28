class_name SkySystem
extends Node
## Drives the weather sky: sun position from the time of day, sky colours from the air type and weather, the sun
## light, fog, drifting clouds and storm cells. Drop one in a scene that has a WorldEnvironment and a
## DirectionalLight3D; it finds them itself (or point `world_environment` and `sun` at them). It replaces the
## Environment's sky.
##
## Storms: add_storm() puts a StormCell in the world. It is drawn on the horizon in the right compass direction at
## the right distance, moves, rains and throws lightning, and when it reaches the observer the whole sky goes
## stormy. The world's weather system will create and move these cells; the sky only displays them.
##
## Moon: moon_phase (0 new, 0.5 full) sets where the moon is in the sky and how much of it is lit. The disc is lit from
## the real sun direction, so crescents and gibbous phases point the right way. At night the moon takes over the scene's
## one DirectionalLight3D from the sun (same shadows, no second light), lifts the ambient light and the fog, and
## silvers the clouds near it. How much cloud is in front of the moon decides whether you get a sharp disc (clear) or a
## smeared glow (veiled); thin high cloud near it can draw the 22 degree ring. The cloud cover at the moon is read back
## from the same noise the shader draws the clouds with, so what is lit and what you see agree.
##
## Debugging: F1 swaps between the shader sky and a plain built-in sky fed the same colours, and the text at the
## bottom left shows what the system is feeding the renderer. Turn debug_overlay off when it is no longer needed.

const Palette := preload("res://scripts/sky_palette.gd")
const MAX_STORMS := 3
## The tilt of the earth's axis (23.44 degrees), radians.
const OBLIQUITY := 0.409105
const MOON_NAMES: Array[String] = ["new moon", "waxing crescent", "first quarter", "waxing gibbous", "full moon", "waning gibbous", "last quarter", "waning crescent"]

## Fired when a storm throws lightning. Thunder reaches the observer thunder_delay_s later (distance / 343 m/s).
signal lightning(cell: StormCell, distance_m: float, thunder_delay_s: float)

@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
## Whose position the storms are seen from. Empty = whatever the active camera is.
@export var observer: Node3D

@export_group("Time")
## Hour of the day, 0-24. 6 is sunrise and 18 sunset when declination is 0.
@export_range(0.0, 24.0, 0.01) var time_hours := 17.8
## Game hours that pass per real second (0 = frozen).
@export_range(0.0, 2.0, 0.01) var hours_per_second := 0.0
@export_range(-80.0, 80.0) var latitude_deg := 25.0
## Sun's declination: 0 at the equinoxes, about +-23.5 at the solstices.
@export_range(-23.5, 23.5) var declination_deg := 0.0
## Where the sun is in the year: 0 = spring equinox, 0.25 = summer solstice, 0.5 = autumn equinox, 0.75 = winter
## solstice. The moon's path needs it. -1 = work it out from declination_deg (WorldWeather sets the real one).
@export_range(-1.0, 1.0) var season_phase := -1.0

@export_group("Weather")
@export_range(0.0, 1.0) var coverage := 0.45
@export_range(0.0, 1.0) var cirrus := 0.35
## 0 = broken cloud, 1 = full grey ceiling.
@export_range(0.0, 1.0) var overcast := 0.0
## 0 = ordinary cloud, 1 = dark storm light.
@export_range(0.0, 1.0) var storm := 0.0
## What is in the air, picked from SkyPalette.AIR_NAMES; air_mix blends from air_a toward air_b.
@export var air_a := 0
@export var air_b := 0
@export_range(0.0, 1.0) var air_mix := 0.0
## Compass direction the clouds drift toward.
@export_range(0.0, 360.0) var wind_dir_deg := 70.0
@export var cloud_speed := 0.004
@export var cloud_scale := 1.4

@export_group("Moon")
## Shows the moon: sky disc, moonlight, moonlit clouds. Off = no moon at all.
@export var moon_enabled := true
## Where the moon is in its cycle: 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
## WorldWeather sets it from the calendar.
@export_range(0.0, 1.0) var moon_phase := 0.4
## Game days from new moon to new moon (the real one is 29.53).
@export var lunar_cycle_days := 29.53
## The light a full, clear moon gives the scene. The sun at noon is about 1.1.
@export_range(0.0, 1.0) var moon_light_energy := 0.25
@export var moon_light_color := Color(0.68, 0.78, 1.0)
## Extra ambient light on a clear moonlit night (without it the sky lights the world almost nothing after dark).
@export_range(0.0, 1.0) var moon_ambient := 0.3
@export var moon_ambient_color := Color(0.16, 0.22, 0.36)
## Apparent radius of the moon in the sky, radians. The real one is 0.0045; it is drawn bigger so it reads.
@export_range(0.005, 0.08) var moon_radius := 0.03

@export_group("Storms")
## Storm cells move this many times faster than real life (for testing; 1 = real speed).
@export_range(0.0, 200.0) var storm_time_scale := 1.0
## Beyond this distance a storm cannot be seen at all, metres.
@export var storm_view_range_m := 70000.0

@export_group("Rendering")
## The custom sky shader. Off = the built-in sky with the same colours (no clouds, no stars, no storms).
@export var use_shader_sky := true:
	set(v):
		use_shader_sky = v
		if _env != null:
			_build_sky()
## Ambient light from a single colour worked out here (cheap, never goes black), instead of from a cubemap
## of the sky (nicer, but costs a sky redraw and can go wrong).
@export var ambient_from_sky := false
@export var debug_overlay := true

## The storms in the world.
var storms: Array[StormCell] = []

var _mat: ShaderMaterial
var _proc: ProceduralSkyMaterial
var _env: Environment
var _wind_off := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _dbg: Label
var _last_zen := Color.BLACK
var _last_hor := Color.BLACK
var _last_energy := 0.0
var _last_ambient := 0.0
var _last_thunder := ""
var _storm_exposure := 0.0
var _ocean_mat: ShaderMaterial
var _ocean_find_t := 0.0
# the cloud noise, read back so the CPU can see the cloud in front of the moon
var _noise_tex: NoiseTexture2D
var _noise_img: Image
var _noise_try_t := 0.0
var _moon_t := 0.0
var _moon_cloud := 0.0           # smoothed: 0 = clear air in front of the moon .. 1 = hidden behind thick cloud
var _moon_cloud_target := 0.0
var _moon_ring := 0.0
var _moon_ring_target := 0.0
var _last_moon_str := 0.0

func _ready() -> void:
	_rng.randomize()
	_find_scene_nodes()
	_setup()
	_apply()
	if debug_overlay:
		_make_debug()
	print("SkySystem: shader loaded=", _mat.shader != null, "  sky mode=", "shader" if use_shader_sky else "procedural",
		"  environment=", world_environment.get_path(), "  sun=", sun.get_path() if sun else "none")

## Finds the scene's WorldEnvironment and sun if they were not assigned (a Node export saved in a scene file does
## not always resolve in time, and falling back to a fresh WorldEnvironment makes a second one that Godot ignores).
func _find_scene_nodes() -> void:
	var root: Node = get_parent()
	if root == null:
		return
	if world_environment == null:
		for n in root.find_children("*", "WorldEnvironment", true, false):
			world_environment = n as WorldEnvironment
			break
	if sun == null:
		for n in root.find_children("*", "DirectionalLight3D", true, false):
			sun = n as DirectionalLight3D
			break

func _setup() -> void:
	if world_environment == null:
		world_environment = WorldEnvironment.new()
		add_child(world_environment)
	_env = world_environment.environment
	if _env == null:
		_env = Environment.new()
		world_environment.environment = _env

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.012
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	_noise_tex = tex

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/sky.gdshader")
	_mat.set_shader_parameter("cloud_noise", tex)
	_proc = ProceduralSkyMaterial.new()

	_env.background_mode = Environment.BG_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if ambient_from_sky else Environment.AMBIENT_SOURCE_COLOR
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_sky_affect = 0.0
	_build_sky()

func _build_sky() -> void:
	var sky := Sky.new()
	sky.sky_material = _mat if use_shader_sky else _proc
	# The reflection cubemap is only a small 64 map and is redrawn gradually over several frames. (Realtime mode
	# forces a 256 map redrawn in full every frame, which froze the first version.)
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	_env.sky = sky

# ---------------------------------------------------------------- storms

## Puts a storm in the world, `distance_m` away from the observer in compass direction `bearing_deg`
## (0 = north / -Z, 90 = east / +X). `radius_m` is half the length of the storm front (squall lines are 50-150 km
## long, so 25000-75000). It drifts toward the observer at `speed_mps` unless you set its velocity.
func add_storm(bearing_deg: float, distance_m: float, radius_m := 25000.0, intensity := 1.0, speed_mps := 12.0) -> StormCell:
	var c := StormCell.new()
	var obs := _observer_pos()
	var b := deg_to_rad(bearing_deg)
	c.pos = obs + Vector2(sin(b), -cos(b)) * distance_m
	c.set_size(radius_m)
	c.intensity = intensity
	c.shape_seed = _rng.randf() * 50.0
	c.velocity = (obs - c.pos).normalized() * speed_mps
	storms.append(c)
	return c

func clear_storms() -> void:
	storms.clear()
	_storm_exposure = 0.0

## How much of a storm the observer is in right now, 0-1. Wind, waves, rain and the like can read this.
func storm_exposure() -> float:
	return _storm_exposure

## Compass bearing (degrees) from the observer to a cell.
func bearing_to(c: StormCell) -> float:
	var d := c.pos - _observer_pos()
	return fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)

func distance_to(c: StormCell) -> float:
	return (c.pos - _observer_pos()).length()

func _observer_pos() -> Vector2:
	var n: Node3D = observer
	if n == null:
		n = get_viewport().get_camera_3d()
	if n == null:
		return Vector2.ZERO
	return Vector2(n.global_position.x, n.global_position.z)

func _step_storms(delta: float) -> void:
	for c in storms:
		c.step(delta * storm_time_scale)
		if c.step_lightning(delta, _rng):
			var d := distance_to(c)
			var delay := d / 343.0
			_last_thunder = "last lightning: %.1f km away, thunder in %.0f s" % [d / 1000.0, delay]
			lightning.emit(c, d, delay)

func _sun_az_el() -> Vector2:
	var sd := sun_direction()
	return Vector2(atan2(sd.x, -sd.z), asin(clampf(sd.y, -1.0, 1.0)))

## Works out what the storms look like from the observer and fills the shader. Returns [exposure, sun_block, flash_light].
func _apply_storms(p: Dictionary, e: float, mid: Color, cloud_lit: Color) -> Array:
	var obs := _observer_pos()
	var order: Array[StormCell] = storms.duplicate()
	order.sort_custom(func(a: StormCell, b: StormCell) -> bool: return (a.pos - obs).length_squared() < (b.pos - obs).length_squared())

	var sa := PackedVector4Array()
	var sb := PackedVector4Array()
	sa.resize(MAX_STORMS)
	sb.resize(MAX_STORMS)
	var exposure := 0.0
	var sun_block := 0.0
	var flash_light := 0.0
	var sun_ae := _sun_az_el()

	var n := mini(order.size(), MAX_STORMS)
	for i in n:
		var c: StormCell = order[i]
		var rel := c.pos - obs
		var dist := maxf(rel.length(), 1.0)
		var r := maxf(c.radius_m, 1.0)         # half the length of the front
		var dp := maxf(c.depth_m, 1.0)         # half the depth of the stormy band
		var az := atan2(rel.x, -rel.y)

		# fades out when the observer is inside it (then the whole sky is the storm), and with distance
		var vis := c.intensity * smoothstep(0.55 * dp, 1.25 * dp, dist) * (1.0 - smoothstep(0.8 * storm_view_range_m, storm_view_range_m, dist))
		var half_w := clampf(atan(r / maxf(dist, dp)), 0.06, 1.35)
		var top := clampf(atan(0.9 * c.height_m / maxf(dist, dp * 0.9)), 0.03, 0.95)
		var haze := smoothstep(12000.0, storm_view_range_m, dist) * 0.8

		sa[i] = Vector4(az, half_w, top, vis)
		sb[i] = Vector4(haze, c.rain, c.shape_seed, c.flash)

		# the observer being inside / near the storm
		exposure = maxf(exposure, c.intensity * (1.0 - smoothstep(0.45 * dp, 1.0 * dp, dist)))
		exposure = maxf(exposure, c.intensity * (1.0 - smoothstep(dp, 3.5 * dp, dist)) * 0.6)
		# the storm standing between the observer and the sun
		var dsun := atan2(sin(sun_ae.x - az), cos(sun_ae.x - az))
		var u := absf(dsun) / half_w
		var storm_top := top * (1.0 - 0.45 * u * u)
		if u < 0.95 and sun_ae.y < storm_top * 0.7:
			sun_block = maxf(sun_block, vis * (1.0 - smoothstep(0.6, 0.95, u)))
		flash_light = maxf(flash_light, c.flash * c.intensity * (1.0 - smoothstep(0.5 * dp, 3.0 * dp, dist)))

	_mat.set_shader_parameter("storm_a", sa)
	_mat.set_shader_parameter("storm_b", sb)
	_mat.set_shader_parameter("storm_base_color", _tone(mid.darkened(0.88), 0.3, 0.0))
	_mat.set_shader_parameter("storm_top_color", _tone(cloud_lit, 0.15, 0.0))
	var light := maxf(float(p["sun_vis"]), 0.55 * smoothstep(-8.0, -1.0, e))
	_mat.set_shader_parameter("storm_light", light)
	return [exposure, sun_block, flash_light]

# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if hours_per_second > 0.0:
		time_hours = fposmod(time_hours + hours_per_second * delta, 24.0)
	var a := deg_to_rad(wind_dir_deg)
	_wind_off += Vector2(sin(a), -cos(a)) * cloud_speed * delta
	_step_storms(delta)
	_update_moon_cloud(delta)
	_apply()
	_update_debug()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		use_shader_sky = not use_shader_sky

# ---------------------------------------------------------------- sun and moon positions

func _hour_angle() -> float:
	return deg_to_rad((time_hours - 12.0) * 15.0)

## Unit vector toward a point of the sky given its hour angle and declination (radians). +X is east, -Z is north, +Y is up.
func _sky_dir(h: float, dec: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var east := -sin(h) * cos(dec)
	var north := sin(dec) * cos(lat) - cos(dec) * sin(lat) * cos(h)
	var up := sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h)
	return Vector3(east, up, -north).normalized()

## Unit vector from the viewer toward the sun. +X is east, -Z is north, +Y is up.
func sun_direction() -> Vector3:
	return _sky_dir(_hour_angle(), deg_to_rad(declination_deg))

func sun_elevation_deg() -> float:
	return rad_to_deg(asin(clampf(sun_direction().y, -1.0, 1.0)))

## Where the sun is along the ecliptic, radians.
func _sun_longitude() -> float:
	if season_phase >= 0.0:
		return TAU * season_phase
	return asin(clampf(sin(deg_to_rad(declination_deg)) / sin(OBLIQUITY), -1.0, 1.0))

## A point on the ecliptic (longitude, latitude in radians) as x = right ascension, y = declination.
static func _ecliptic_to_equatorial(lon: float, lat_b: float) -> Vector2:
	var sl := sin(lon)
	var ra := atan2(sl * cos(OBLIQUITY) - tan(lat_b) * sin(OBLIQUITY), cos(lon))
	var dec := asin(clampf(sin(lat_b) * cos(OBLIQUITY) + cos(lat_b) * sin(OBLIQUITY) * sl, -1.0, 1.0))
	return Vector2(ra, dec)

## The moon's age in days since the new moon.
func moon_age_days() -> float:
	return moon_phase * lunar_cycle_days

## How much of the moon's face is lit, 0 (new) .. 1 (full).
func moon_illumination() -> float:
	return 0.5 * (1.0 - cos(TAU * moon_phase))

## The moon moves round the sky once every lunar day: it sits (phase x 360 degrees) of ecliptic longitude ahead of the
## sun, so a new moon rises with the sun, a full moon rises at sunset, and every day it comes up about 50 minutes
## later. Its orbit is tilted about 5 degrees to the sun's path, which is why it rides higher and lower than the sun.
func moon_direction() -> Vector3:
	var ls := _sun_longitude()
	var lm := ls + TAU * moon_phase
	var beta := deg_to_rad(5.1) * sin(TAU * moon_age_days() / 27.32)
	var es := _ecliptic_to_equatorial(ls, 0.0)
	var em := _ecliptic_to_equatorial(lm, beta)
	return _sky_dir(_hour_angle() - (em.x - es.x), em.y)

func moon_elevation_deg() -> float:
	return rad_to_deg(asin(clampf(moon_direction().y, -1.0, 1.0)))

## "full moon", "waxing crescent" and so on, for a phase 0-1.
static func phase_name(phase: float) -> String:
	return MOON_NAMES[int(floorf(fposmod(phase, 1.0) * 8.0 + 0.5)) % 8]

## The disc's own right and up directions on the sky (what the shader needs to light the phase).
func _moon_axes(md: Vector3) -> Array[Vector3]:
	var up_ref := Vector3.UP if absf(md.y) < 0.98 else Vector3.RIGHT
	var mr := md.cross(up_ref).normalized()
	var mu := mr.cross(md).normalized()
	var axes: Array[Vector3] = [mr, mu]
	return axes

# ---------------------------------------------------------------- cloud in front of the moon

## The shader draws the clouds from a noise texture; the CPU reads the same texture back and repeats the maths here
## for the few sky directions round the moon. That is what makes the moon fuzzy behind thin cloud and dims its light.
func _update_moon_cloud(delta: float) -> void:
	if _noise_img == null:
		_noise_try_t -= delta
		if _noise_try_t <= 0.0:
			_noise_try_t = 0.25
			if _noise_tex != null:
				var img := _noise_tex.get_image()
				if img != null and not img.is_empty() and not img.is_compressed():
					_noise_img = img
	_moon_t -= delta
	if _moon_t <= 0.0:
		_moon_t = 0.1
		_sample_moon_cloud()
	var k := 1.0 - exp(-delta / 0.6)
	_moon_cloud = lerpf(_moon_cloud, _moon_cloud_target, k)
	_moon_ring = lerpf(_moon_ring, _moon_ring_target, k)

func _sample_moon_cloud() -> void:
	var md := moon_direction()
	if _noise_img == null or md.y <= 0.0:
		# the noise is not ready yet, or the moon is down: judge from the sliders
		_moon_cloud_target = clampf(coverage * 0.4 + overcast * 0.8, 0.0, 1.0)
		_moon_ring_target = 0.0
		return
	var axes := _moon_axes(md)
	var offs: Array[Vector2] = [Vector2.ZERO, Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)]
	var low := 0.0
	var cir := 0.0
	for off in offs:
		var d := (md + (axes[0] * off.x + axes[1] * off.y) * 0.05).normalized()
		low += _cloud_low(d)
		cir += _cloud_cirrus(d)
	low /= float(offs.size())
	cir /= float(offs.size())
	_moon_cloud_target = clampf(low * 1.25 + cir * 1.6, 0.0, 1.0)
	_moon_ring_target = clampf(cir * 4.0, 0.0, 1.0) * (1.0 - clampf(low * 2.5, 0.0, 1.0))

## One pixel of the cloud noise (0-1), wrapped and smoothed like the texture the shader reads.
func _noise_at(uv: Vector2) -> float:
	var w := _noise_img.get_width()
	var h := _noise_img.get_height()
	var x := uv.x * w - 0.5
	var y := uv.y * h - 0.5
	var fx := floorf(x)
	var fy := floorf(y)
	var tx := x - fx
	var ty := y - fy
	var x0 := posmod(int(fx), w)
	var y0 := posmod(int(fy), h)
	var x1 := (x0 + 1) % w
	var y1 := (y0 + 1) % h
	var a := lerpf(_noise_img.get_pixel(x0, y0).r, _noise_img.get_pixel(x1, y0).r, tx)
	var b := lerpf(_noise_img.get_pixel(x0, y1).r, _noise_img.get_pixel(x1, y1).r, tx)
	return lerpf(a, b, ty)

## Density of the low cloud layer in a sky direction: the same sums as the shader's low clouds.
func _cloud_low(dir: Vector3) -> float:
	if dir.y <= 0.0:
		return 0.0
	var uv := Vector2(dir.x, dir.z) / (dir.y + 0.10) * 0.10 * cloud_scale + _wind_off
	var n := _noise_at(uv) * 0.8 + _noise_at(uv * 3.1 + Vector2(0.37, 0.11)) * 0.2
	var thr := lerpf(0.66, 0.36, coverage)
	var d := smoothstep(thr, thr + 0.30, n)
	d = lerpf(d, 0.7 + 0.3 * n, overcast)
	return d * smoothstep(0.0, 0.18, dir.y)

## Density of the high cirrus layer in a sky direction: the same sums as the shader's cirrus.
func _cloud_cirrus(dir: Vector3) -> float:
	if dir.y <= 0.0:
		return 0.0
	var uvc := Vector2(dir.x, dir.z) / (dir.y + 0.30) * 0.10 * cloud_scale
	var a := deg_to_rad(wind_dir_deg)
	var wd := Vector2(sin(a), -cos(a)).normalized()
	var st := Vector2(uvc.dot(wd) * 0.6, uvc.dot(Vector2(-wd.y, wd.x)) * 1.2) + _wind_off * 0.6
	var nc := _noise_at(st) * 0.65 + _noise_at(st * 2.3 + Vector2(0.2, 0.7)) * 0.35
	var thrc := lerpf(0.62, 0.4, cirrus)
	return smoothstep(thrc, thrc + 0.4, nc) * smoothstep(0.02, 0.25, dir.y) * smoothstep(0.0, 0.1, cirrus) * (1.0 - overcast * 0.85) * 0.5

static func _tone(c: Color, gray_amt: float, dark: float) -> Color:
	var l := c.get_luminance()
	return c.lerp(Color(l, l, l), gray_amt).darkened(dark)

func _apply() -> void:
	if _mat == null:
		return
	var sd := sun_direction()
	var e := rad_to_deg(asin(clampf(sd.y, -1.0, 1.0)))
	var p: Dictionary = Palette.sample(air_a, air_b, air_mix, e)

	# storms first: they can darken the whole sky and block the sun
	var base_mid := _tone(p["mid"], 0.0, 0.0)
	var st: Array = _apply_storms(p, e, base_mid, p["cloud_lit"])
	_storm_exposure = st[0]
	var sun_block: float = st[1]
	var flash_light: float = st[2]

	var o := maxf(overcast, _storm_exposure * 0.95)
	var s := maxf(storm, _storm_exposure)
	var gray_amt := clampf(o * 0.6 + s * 0.3, 0.0, 0.9)
	var dark := s * 0.45

	var zen := _tone(p["zenith"], gray_amt, dark)
	var mid := _tone(p["mid"], gray_amt, dark)
	var hor := _tone(p["horizon"], gray_amt, dark)
	var core: Color = p["core"]
	var core_lin := core.srgb_to_linear()

	# ---- the moon: where it is, how bright, how much of it the cloud lets through ----
	var md := moon_direction()
	var m_elev := rad_to_deg(asin(clampf(md.y, -1.0, 1.0)))
	var night_k := 1.0 - smoothstep(0.0, 0.35, float(p["light_energy"]) / 1.15)      # 1 in the dark, 0 in daylight
	var m_str := 0.0                  # how much moonlight reaches the scene (clear sky, moon up, a fat phase)
	var m_cloudlit := 0.0             # the same without the cloud in front: what lights the clouds themselves
	var m_vis := 0.0                  # how much of the disc shows (pale by day)
	var m_glow := 0.0                 # glow, halo ring and earthshine: night things
	if moon_enabled:
		var illum := moon_illumination()
		var above := smoothstep(-1.5, 7.0, m_elev)
		var phase_k := lerpf(0.10, 1.0, pow(illum, 1.4))
		m_cloudlit = phase_k * above * night_k * (1.0 - s * 0.5)
		m_str = phase_k * above * (1.0 - _moon_cloud * 0.8) * (1.0 - s * 0.5)
		m_vis = smoothstep(-0.8, 1.5, m_elev) * lerpf(0.55, 1.0, night_k) * (1.0 - s * 0.6)
		m_glow = night_k * lerpf(0.25, 1.0, illum)
	_last_moon_str = m_str
	var mlc := moon_light_color
	var axes := _moon_axes(md)

	# ---- the shader sky ----
	_mat.set_shader_parameter("sun_dir", sd)
	_mat.set_shader_parameter("zenith_color", zen)
	_mat.set_shader_parameter("mid_color", mid)
	_mat.set_shader_parameter("horizon_color", hor)
	_mat.set_shader_parameter("ground_color", hor.darkened(0.35))
	_mat.set_shader_parameter("glow_color", _tone(p["glow"], gray_amt * 0.6, dark * 0.5))
	_mat.set_shader_parameter("glow_core_color", core)
	_mat.set_shader_parameter("opposite_color", _tone(p["opp"], gray_amt, dark))
	_mat.set_shader_parameter("shadow_color", _tone(p["shadow"], gray_amt, dark))
	_mat.set_shader_parameter("cloud_lit_color", _tone(p["cloud_lit"], o * 0.5, s * 0.55))
	_mat.set_shader_parameter("cloud_shade_color", _tone(mid.darkened(0.35), o * 0.4 + s * 0.3, s * 0.4))
	_mat.set_shader_parameter("cirrus_color", p["cirrus"])
	_mat.set_shader_parameter("sun_color", Vector3(core_lin.r, core_lin.g, core_lin.b) * 3.0)

	_mat.set_shader_parameter("glow_strength", float(p["glow_strength"]) * (1.0 - o * 0.75))
	_mat.set_shader_parameter("glow_power", p["glow_power"])
	_mat.set_shader_parameter("glow_height", p["glow_height"])
	_mat.set_shader_parameter("opposite_strength", float(p["opp_strength"]) * (1.0 - o * 0.6))
	_mat.set_shader_parameter("sun_visibility", float(p["sun_vis"]) * (1.0 - o) * (1.0 - s) * (1.0 - sun_block))
	# a bright moon washes the stars out
	_mat.set_shader_parameter("star_visibility", float(p["star_vis"]) * (1.0 - o) * (1.0 - coverage * 0.6) * (1.0 - 0.55 * m_glow * float(moon_enabled)))

	_mat.set_shader_parameter("coverage", coverage)
	_mat.set_shader_parameter("overcast", o)
	_mat.set_shader_parameter("cirrus_amount", cirrus)
	_mat.set_shader_parameter("wind_offset", _wind_off)
	_mat.set_shader_parameter("wind_dir", Vector2(sin(deg_to_rad(wind_dir_deg)), -cos(deg_to_rad(wind_dir_deg))))
	_mat.set_shader_parameter("cloud_scale", cloud_scale)

	_mat.set_shader_parameter("moon_dir", md)
	_mat.set_shader_parameter("moon_right", axes[0])
	_mat.set_shader_parameter("moon_up", axes[1])
	_mat.set_shader_parameter("moon_radius", moon_radius)
	_mat.set_shader_parameter("moon_color", Vector3(0.96, 0.95, 0.88) * lerpf(0.95, 1.5, night_k))
	_mat.set_shader_parameter("moon_visibility", m_vis)
	_mat.set_shader_parameter("moon_glow", m_glow)
	_mat.set_shader_parameter("moon_veil", _moon_cloud)
	_mat.set_shader_parameter("moon_ring", _moon_ring)
	_mat.set_shader_parameter("moon_cloud_light", Vector3(mlc.r, mlc.g, mlc.b) * 0.55 * m_cloudlit)
	_mat.set_shader_parameter("moon_sky_lift", Vector3(mlc.r, mlc.g, mlc.b) * 0.05 * m_cloudlit)

	# ---- the plain built-in sky (fallback / comparison), same colours ----
	_proc.sky_top_color = zen
	_proc.sky_horizon_color = hor
	_proc.sky_curve = 0.25
	_proc.ground_horizon_color = hor
	_proc.ground_bottom_color = hor.darkened(0.45)
	_proc.sun_angle_max = 0.0
	_proc.sun_curve = 0.01

	# ---- lights ----
	# One DirectionalLight3D does both jobs: by day it is the sun, and once the sun's light has faded it is handed to the
	# moon (when the moon is up and giving any), so the moonlight casts the same shadows and the sea glints with it.
	# Between the two the direction, colour and strength blend, so nothing pops.
	var energy: float = float(p["light_energy"]) * (1.0 - o * 0.65 - s * 0.2) * (1.0 - 0.85 * sun_block)
	var moon_e := moon_light_energy * m_str if moon_enabled else 0.0
	var out_energy := energy
	if sun:
		var w_m := 0.0
		var ld := sd
		if moon_e > 0.0:
			w_m = (1.0 - smoothstep(0.0, 0.15, energy)) * smoothstep(0.0, 0.02, moon_e)
			if w_m > 0.0:
				ld = sd.lerp(md, w_m)
				ld = md if ld.length() < 0.05 else ld.normalized()
		out_energy = lerpf(energy, moon_e, w_m)
		var up := Vector3.UP if absf(ld.y) < 0.98 else Vector3.RIGHT
		sun.basis = Basis.looking_at(-ld, up)
		sun.light_energy = out_energy
		sun.visible = out_energy > 0.02
		var lc: Color = core.lerp(Color.WHITE, 0.3)
		sun.light_color = _tone(lc, gray_amt * 0.8, 0.0).lerp(moon_light_color, w_m)

	var moon_amb_k := m_str * night_k
	var amb := 0.3 + 0.6 * clampf(float(p["light_energy"]), 0.0, 1.0) + flash_light * 0.9 + moon_ambient * moon_amb_k
	if _env:
		if not ambient_from_sky:
			var ac := mid.lerp(hor, 0.5).lerp(Color(0.7, 0.8, 1.0), clampf(flash_light, 0.0, 1.0) * 0.6)
			_env.ambient_light_color = ac.lerp(moon_ambient_color, clampf(moon_amb_k * 0.85, 0.0, 1.0))
			_env.ambient_light_energy = amb
		var fog_c := hor.lerp(mid, 0.15)
		_env.fog_light_color = fog_c.lerp(moon_ambient_color.lightened(0.1), clampf(moon_amb_k * 0.6, 0.0, 1.0))
		_env.fog_density = lerpf(0.00018, 0.0011, clampf(s * 0.8 + o * 0.25, 0.0, 1.0))

	_last_zen = zen
	_last_hor = hor
	_last_energy = out_energy
	_last_ambient = amb
	_feed_ocean(hor, o, s, gray_amt)

## Gives the sea the sky's mood: its body takes on some of the horizon colour under cloud, goes greyer and duller in
## weather and darker in storms (the distance haze is the Environment's fog, which this node already sets). Finds the
## scene's Ocean by itself.
func _feed_ocean(hor: Color, o: float, s: float, gray_amt: float) -> void:
	if _ocean_mat == null:
		_ocean_find_t -= get_process_delta_time()
		if _ocean_find_t > 0.0:
			return
		_ocean_find_t = 1.0
		var root := get_parent()
		if root == null:
			return
		for n in root.find_children("*", "MeshInstance3D", true, false):
			if n is Ocean:
				_ocean_mat = (n as Ocean).get_ocean_material()
				break
		if _ocean_mat == null:
			return
	_ocean_mat.set_shader_parameter("horizon_color", hor)
	_ocean_mat.set_shader_parameter("sky_tint", clampf(0.08 + 0.3 * o, 0.0, 0.4))
	_ocean_mat.set_shader_parameter("water_gray", gray_amt)
	_ocean_mat.set_shader_parameter("water_dark", s)

# ---------------------------------------------------------------- debug text

func _make_debug() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_dbg = Label.new()
	_dbg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_dbg.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dbg.offset_left = 12.0
	_dbg.offset_bottom = -10.0
	_dbg.add_theme_color_override("font_color", Color.WHITE)
	_dbg.add_theme_color_override("font_outline_color", Color.BLACK)
	_dbg.add_theme_constant_override("outline_size", 6)
	layer.add_child(_dbg)

func _update_debug() -> void:
	if _dbg == null:
		return
	var storm_line := "no storms"
	if not storms.is_empty():
		var nearest: StormCell = storms[0]
		for c in storms:
			if distance_to(c) < distance_to(nearest):
				nearest = c
		var d := distance_to(nearest)
		var closing := -nearest.velocity.dot((nearest.pos - _observer_pos()).normalized()) * storm_time_scale
		var eta := ""
		if closing > 0.5:
			eta = "   reaches you in %.0f min" % maxf((d - nearest.depth_m * 0.6) / closing / 60.0, 0.0)
		storm_line = "nearest storm: %.1f km at bearing %.0f%s\n%s" % [d / 1000.0, bearing_to(nearest), eta, _last_thunder]
	var moon_line := "moon off"
	if moon_enabled:
		moon_line = "moon: %s (day %.1f)   %+.0f deg   moonlight %.2f   cloud over moon %.2f   ring %.2f" % [
			phase_name(moon_phase), moon_age_days(), moon_elevation_deg(), _last_moon_str, _moon_cloud, _moon_ring]
	_dbg.text = "SKY DEBUG   F1 = swap sky renderer\nrenderer: %s   ambient: %s\nsun %+.1f deg   light %.2f   ambient %.2f\nzenith #%s   horizon #%s\n%s\n%s" % [
		"custom shader" if use_shader_sky else "built-in (same colours)",
		"sky cubemap" if ambient_from_sky else "single colour",
		sun_elevation_deg(), _last_energy, _last_ambient,
		_last_zen.to_html(false), _last_hor.to_html(false), moon_line, storm_line]
