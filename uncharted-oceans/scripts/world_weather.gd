class_name WorldWeather
extends Node
## The weather of the whole chart: the calendar, the seasonal wind (WindField) and the storm cells that ride on it.
## Created by WorldStreamer (weather_enabled). One per world (group "weather").
##
## Calendar: one year is four seasons of days_per_season game days each, and the game clock runs in real time (a day is
## 24 real hours) plus whatever you sleep. The sun's declination follows the date, so the sun is higher in summer.
## If a SkySystem is in the scene, the clock drives it (time of day, declination, cloud drift) and the storm cells below
## are shown on its horizon.
##
## Wind: wind_at() is what the sails feel at any chart position now: the prevailing wind for the season (WindField), the
## daily coastal breeze, and the wind a storm throws round itself. SeaWind reads it at the ship.
##
## Storm seasons (the lore: each belt of the world has its own bad weather, and a captain who learns the almanac can
## plan around it):
##  - Northern gales   winter, in the westerlies of the north: long fast fronts running west to east.
##  - Hurricanes       late summer into autumn, born in the east of the trade-wind belt, running down the trades
##                     toward the western sea and curving north as they go.
##  - Turning cyclones when the monsoon turns (spring and autumn): they come off the eastern edge of the chart and
##                     cross the monsoon seas going west.
##  - Squalls          small, short and local, in the calm belt, mostly summer afternoons.
## The storm weather is seeded (weather_seed), so the same world makes the same storms; set it to 0 for random weather.

signal season_changed(season: String)
## The clock jumped (a sleep). Things that smooth toward the weather should snap to it.
signal time_jumped

class Track extends RefCounted:
	var kind := ""
	var cell: StormCell
	var cx := 0.0                  # chart metres
	var cz := 0.0
	var heading := 0.0             # degrees, toward
	var speed := 8.0               # m/s
	var curve := 0.0               # degrees per hour, + = turning clockwise
	var age := 0.0                 # game seconds
	var life := 3600.0
	var peak := 1.0
	var wind_boost := 12.0         # m/s of wind it adds in its heart

@export var streamer_path: NodePath = ^".."
## Game days in one season. A year is four of them.
@export var days_per_season := 12.0
## Day of the year the game starts on (0 = spring equinox, days_per_season = summer solstice) and the hour of day.
@export var start_day := 14.0      # the same point in the year as before the seasons were doubled (day 7 of 6-day seasons)
@export var start_hour := 17.8
## The moon: days from one new moon to the next (the real one is 29.53), and how old the moon is at the start of the
## voyage in days (0 = new, 7.4 = first quarter, 14.8 = full). 10.5 is a fat waxing moon already up at dusk.
@export var lunar_cycle_days := 29.53
@export var start_moon_age := 10.5
## Game hours per real second. 1/3600 = real time.
@export var clock_hours_per_second := 1.0 / 3600.0
## Drive the SkySystem's clock, sun declination and cloud drift (when there is one).
@export var drive_sky := true
@export var storms_enabled := true
@export var max_storms := 6
## Game hours of weather made before the start, so the world already has weather in it.
@export var warmup_hours := 30.0
## No storm within this distance of the ship at the start.
@export var clear_start_radius_m := 70000.0
## A storm waiting outside the starting harbour, so there is weather to look at from the first minute. It sits this far
## out from the port in the way the harbour mouth faces and drifts slowly in (turn start_storm off for fair weather).
@export var start_storm := true
@export var start_storm_distance_m := 30000.0
@export var start_storm_speed_mps := 5.0
@export var weather_seed := 1031
@export var coast_breeze := true
## Inside this distance of a port (m) its own breeze takes over from the general coastal breeze: full strength in the
## inner 70% and fading out to nothing at the edge. The breeze blows port_breeze_speed (m/s) along the harbour's axis,
## out of the port in the morning (strongest about 06:00) and into it in the evening (about 18:00), and the land shelters the prevailing wind by port_shelter (0 = not at all,
## 1 = fully) in the harbour proper.
@export var port_breeze := true
@export var port_breeze_m := 1500.0           # the same radius as the no-storm-sea zone (Ocean.port_calm_radius_m)
@export var port_breeze_speed := 3.5
@export_range(0.0, 1.0) var port_shelter := 0.5
## Rain round the camera when a storm's rain reaches the ship (rain_effect.gd).
@export var rain_enabled := true
## Dim the sun, sky and fog in a storm when the scene has no SkySystem (which does that itself).
@export var mood_enabled := true
## A sleep ends, and none can begin, when a storm's weather (0-1, see _proximity) is about to reach the ship at this level.
## Wind starts to rise at about 0.2 and the rain wall arrives at about 0.7, so this is the storm proper: it was 0.2,
## which reached far out into the fringe of a storm. At 0.7 the zone that stops a sleep is roughly half the area.
## (Weak squalls never get this high at all, and are slept through.)
@export var storm_wake_level := 0.7
## How much of a storm's depth is its dangerous part. SkySystem draws the cloud, and the dark sky under it, from the cell's
## own depth_m, so a storm still looks as vast as it should; the wind, the rain and the sleep stop use only this fraction of
## it. With 0.4 the part you must sail or ride through is about 20 km across, not 55: about an hour for a hurricane and half
## that for a gale (at 5 m/s, about 70 minutes for the storm waiting at the start). The barometer still falls over the
## whole cloud's reach, so the glass gives you the early warning. 1 = as deep as the cloud.
@export_range(0.15, 1.0) var danger_depth_scale := 0.4

const WindFieldS := preload("res://scripts/wind_field.gd")

var field: WindFieldS
var game_hours := 0.0
var tracks: Array[Track] = []

var _streamer: Node            # the WorldStreamer
var _sky: SkySystem
var _rng := RandomNumberGenerator.new()
var _find_t := 0.0
var _sky_t := 0.0
var _last_season := ""

const RainScript := preload("res://scripts/rain_effect.gd")
var rain_fx: GPUParticles3D
var _ship_t := 0.0
var _rain_now := 0.0             # at the ship, as of the last look
var _dark_now := 0.0
var _dark_s := 0.0               # smoothed, drives the sun, sky and fog
var _rain_s := 0.0
var _wind_node: Node
var _env: Environment
var _env_base := {}
var _env_t := 0.0
var _sun: DirectionalLight3D
var _sun_base := 1.0


func _ready() -> void:
	add_to_group("weather")
	add_to_group("logbook_source")           # the Ship's Log asks for logbook_markdown() (ship_bookshelf.gd)
	if weather_seed != 0:
		_rng.seed = weather_seed
	else:
		_rng.randomize()
	_streamer = get_node_or_null(streamer_path)
	var w := 600000.0
	var h := 400000.0
	if _streamer and _streamer.chart:
		w = _streamer.chart.width_m
		h = _streamer.chart.height_m
	field = WindFieldS.new(w, h)
	if _streamer:
		_streamer.rebased.connect(func(_shift: Vector3) -> void: _sync_sky())
	if storms_enabled:
		_warm_up()
	if start_storm:
		call_deferred("_spawn_start_storm")      # after the ship has been put in its berth
	_last_season = season()
	if rain_enabled:
		rain_fx = RainScript.new()
		rain_fx.name = "Rain"
		add_child(rain_fx)


# ------------------------------------------------------------------ calendar

func year_days() -> float:
	return days_per_season * 4.0


## Hour of the day, 0-24.
func hour_of_day() -> float:
	return fposmod(start_hour + game_hours, 24.0)


## Day of the year, counted from the spring equinox (0 .. year_days).
func day_of_year() -> float:
	return fposmod(start_day + (start_hour + game_hours) / 24.0, year_days())


## 0 = spring equinox, 0.25 = summer solstice, 0.5 = autumn equinox, 0.75 = winter solstice.
func year_phase() -> float:
	return fposmod((start_day + (start_hour + game_hours) / 24.0) / year_days(), 1.0)


## Days since the last new moon, 0 .. lunar_cycle_days. It runs on the game clock, so sleeping moves the moon on too.
func moon_age_days() -> float:
	return fposmod(start_moon_age + game_hours / 24.0, lunar_cycle_days)


## 0 = new moon, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
func moon_phase() -> float:
	return moon_age_days() / lunar_cycle_days


## "waxing gibbous, 10 days old": the moon as the ship's log gives it.
func moon_text() -> String:
	var age := int(moon_age_days())
	return "%s, %d day%s old" % [SkySystem.phase_name(moon_phase()), age, "" if age == 1 else "s"]


func season() -> String:
	return WindFieldS.season_name(year_phase())


# ------------------------------------------------------------------ the date, as the ship's log writes it

## Where this node's pages come in the Ship's Log (lower is earlier): see ship_bookshelf.gd, _book_text().
var logbook_order := 10.0
const SEASON_NAMES := ["Spring", "Summer", "Autumn", "Winter"]
## The ship's watches: start hour, end hour, name. The two dog watches are half the length of the others.
const WATCHES := [
	[0.0, 4.0, "middle watch"], [4.0, 8.0, "morning watch"], [8.0, 12.0, "forenoon watch"], [12.0, 16.0, "afternoon watch"],
	[16.0, 18.0, "first dog watch"], [18.0, 20.0, "last dog watch"], [20.0, 24.0, "first watch"],
]
const NUMBER_WORDS := ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"]


## Days since the calendar year began (0 .. year_days). The year runs spring, summer, autumn, winter, and each season is
## centred on its equinox or solstice (see WindField.season_name), so spring begins an eighth of a year before the spring
## equinox. A day begins at midnight.
func calendar_day() -> float:
	return fposmod(day_of_year() - 0.875 * year_days(), year_days())


## 0 spring, 1 summer, 2 autumn, 3 winter.
func season_index() -> int:
	return clampi(int(calendar_day() / days_per_season), 0, 3)


## The day of the season, from 1 (the 5th of Summer).
func day_of_season() -> int:
	return int(fposmod(calendar_day(), days_per_season)) + 1


## Days since the voyage began: 1 on the first day.
func voyage_day() -> int:
	return int(floor((start_hour + game_hours) / 24.0)) + 1


static func ordinal(n: int) -> String:
	var tail := n % 100
	if tail >= 11 and tail <= 13:
		return "%dth" % n
	match n % 10:
		1: return "%dst" % n
		2: return "%dnd" % n
		3: return "%drd" % n
	return "%dth" % n


## "The 5th of Summer".
func date_text() -> String:
	return "The %s of %s" % [ordinal(day_of_season()), SEASON_NAMES[season_index()]]


## The last bell struck, the sailor's way: "Three bells in the first dog watch." A bell is struck every half hour and
## eight bells close a watch; the short dog watches (16-20) make the count start again at 18:30.
func bells_text() -> String:
	var struck := floorf(hour_of_day() * 2.0) / 2.0          # the half hour the last bell was struck
	var n := int(struck * 2.0) % 8
	if struck >= 18.5 and struck < 20.0:
		n = int((struck - 18.0) * 2.0)
	if n == 0:
		n = 8
	var at := fposmod(struck - 0.01, 24.0)                     # a bell struck on the stroke closes the watch before it
	var watch := "first watch"
	for w in WATCHES:
		if at >= float(w[0]) and at < float(w[1]):
			watch = String(w[2])
	return "%s bell%s in the %s." % [NUMBER_WORDS[n], "" if n == 1 else "s", watch]


## What the Ship's Log says about the date, in the book reader's markdown. ship_bookshelf.gd adds it to the book
## "logbook" (data/book/books.json) each time it is opened, so it is always today's date.
func logbook_markdown() -> String:
	var si := season_index()
	var today := floori(calendar_day())
	var lines := PackedStringArray()
	lines.append("- %s is the season now: the %s day of %d." % [SEASON_NAMES[si], ordinal(day_of_season()), int(days_per_season)])
	for k in range(1, 4):
		var until := int(roundf(float(si + k) * days_per_season)) - today
		lines.append("- %s begins %s." % [SEASON_NAMES[(si + k) % 4], "tomorrow" if until == 1 else "in %d days" % until])
	return "## Today\n\n*%s*\n\nDay %d of the voyage. %s\n\nWeather: %s\n\nMoon: %s\n\n## The Year\n\nThe year is %d days long, %d to each season.\n\n%s" % [
		date_text(), voyage_day(), bells_text(), weather_text(), moon_text(), int(year_days()), int(days_per_season), "\n".join(lines)]


# The weather, in a sailor's words.

## Beaufort: the wind speed (m/s) below which each name holds.
const WIND_FORCES := [
	[0.5, "a calm"], [1.6, "light airs"], [3.4, "a light breeze"], [5.5, "a gentle breeze"], [8.0, "a moderate breeze"],
	[10.8, "a fresh breeze"], [13.9, "a strong breeze"], [17.2, "a near gale"], [20.8, "a gale"], [24.5, "a strong gale"],
	[28.5, "a storm"], [32.7, "a violent storm"],
]
const COMPASS_POINTS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]


static func compass_point(deg: float) -> String:
	return COMPASS_POINTS[int(roundf(fposmod(deg, 360.0) / 45.0)) % 8]


## The wind at the ship as a sailor names it: "a fresh breeze from the south-west", or "a calm".
func wind_words() -> String:
	var v := _wind_vec()
	var s := v.length()
	if s < 0.5:
		return "a calm"
	var label := "a hurricane"
	for f in WIND_FORCES:
		if s < float(f[0]):
			label = String(f[1])
			break
	return "%s from the %s" % [label, compass_point(WindFieldS.heading_of(v) + 180.0)]


## A simple account of the weather at the ship, as the log gives it: "Fair, a gentle breeze from the south-west."
## Rain and a storm on the ship change the first word; a storm in sight (inside the sky's view range) is added at the end.
func weather_text() -> String:
	var sky := "Fair"
	if _rain_s >= 0.6:
		sky = "Heavy rain"
	elif _rain_s >= 0.08:
		sky = "Rain"
	elif storm_proximity_at_ship() >= 0.1:
		sky = "Dark and threatening"
	var out := "%s, %s" % [sky, wind_words()]
	var p := ship_chart_pos()
	var view := _sky.storm_view_range_m if _sky != null else 70000.0
	var best: Track = null
	var bd := INF
	for t in tracks:
		if t.cell.intensity < 0.25:
			continue
		var d := Vector2(t.cx, t.cz).distance_to(p)
		if d < bd:
			bd = d
			best = t
	if best != null and bd < view and storm_proximity_at_ship() < 0.3:
		out += ", and a %s on the horizon to the %s" % [best.kind, compass_point(WorldChart.heading_to(p.x, p.y, best.cx, best.cz))]
	return out + "."


# ------------------------------------------------------------------ the wind

## The wind at a chart position now: air velocity in m/s, x east and y south (before gusts).
func wind_at(cx: float, cz: float) -> Vector2:
	var v := field.prevailing(cx, cz, year_phase())
	if coast_breeze and _streamer and _streamer.chart:
		# near a port the daily breeze blows along the harbour's own axis (and the land takes the edge off the
		# prevailing wind), so a ship in the harbour gets a breeze out of the port in the morning and into it in the evening
		var pz := _port_zone(cx, cz) if port_breeze else Vector2.ZERO
		var hour := hour_of_day()
		var coast := field.coastal(_streamer.chart, cx, cz, hour)
		if pz.x > 0.0:
			var day := cos(TAU * (hour - 18.0) / 24.0)                 # +1 at 18:00 (blowing into the port), -1 at 06:00 (blowing out of it)
			# the sea breeze blows from the harbour mouth toward the land: the way the mouth faces, reversed
			var breeze := WindFieldS.vec(port_breeze_speed * day, fposmod(pz.y + 180.0, 360.0))
			v *= 1.0 - port_shelter * pz.x
			v += coast * (1.0 - pz.x) + breeze * pz.x
		else:
			v += coast
	return v + storm_wind(cx, cz)


## How far inside a port's breeze zone a chart position is: x = 0 (outside) .. 1 (the harbour proper), y = the chart
## heading from that port out to open water (the way its harbour mouth faces).
func _port_zone(cx: float, cz: float) -> Vector2:
	var best := Vector2.ZERO
	for p in _streamer.chart.ports:
		var d := WorldChart.distance_m(cx, cz, p["x"], p["z"])
		if d >= port_breeze_m:
			continue
		var w := 1.0 - smoothstep(port_breeze_m * 0.7, port_breeze_m, d)
		if w > best.x:
			best = Vector2(w, float(_streamer.port_mouth_heading(String(p["id"]))))
	return best


func wind_at_ship() -> Vector2:
	var p := ship_chart_pos()
	return wind_at(p.x, p.y)


## Where the ship is on the chart (metres).
func ship_chart_pos() -> Vector2:
	if _streamer == null:
		return Vector2(field.width_m * 0.5, field.height_m * 0.5)
	var ship := _streamer.get_node_or_null(_streamer.ship_path) as Node3D
	if ship == null:
		return Vector2(field.width_m * 0.5, field.height_m * 0.5)
	return Vector2(_streamer.origin_x + ship.global_position.x, _streamer.origin_z + ship.global_position.z)


## 0-1: how deep in a storm's weather a position is. The weather is as deep as danger_depth_scale of the cloud (the cloud
## itself, and the dark sky, are drawn from the cell's full depth_m); pass scale = 1 for the whole cloud's reach.
func _proximity(t: Track, cx: float, cz: float, scale := -1.0) -> float:
	var dp := maxf(t.cell.depth_m * (danger_depth_scale if scale < 0.0 else scale), 1.0)
	var d := Vector2(cx - t.cx, cz - t.cz).length()
	return t.cell.intensity * (1.0 - smoothstep(0.8 * dp, 3.5 * dp, d))


## The wind the storms add at a position: along their track (the gust front) and in toward their centre.
func storm_wind(cx: float, cz: float) -> Vector2:
	var out := Vector2.ZERO
	for t in tracks:
		var p := _proximity(t, cx, cz)
		if p <= 0.0:
			continue
		var rel := Vector2(t.cx - cx, t.cz - cz)
		var inflow := rel.normalized() if rel.length() > 1.0 else Vector2.ZERO
		out += (WindFieldS.vec(1.0, t.heading) + inflow * 0.45) * t.wind_boost * p
	return out


func storm_proximity_at_ship() -> float:
	var p := ship_chart_pos()
	var best := 0.0
	for t in tracks:
		best = maxf(best, _proximity(t, p.x, p.y))
	return best


## Barometric pressure (inches of mercury) at a chart position: about 29.95 in fair weather with a slow drift and a
## small twice-daily tide, and falling as a storm comes in. It starts to fall well before the wind does (a storm's
## weather reaches 3.5 times its depth out), so a falling glass is the warning to watch for. The cabin barometer
## (ship_barometer.gd) reads it.
const STORM_DROP_INHG := 2.0

func pressure_inhg_at(cx: float, cz: float) -> float:
	var h := start_hour + game_hours
	var p := 29.95 + 0.03 * sin(TAU * (h - 4.0) / 12.0) + 0.08 * sin(h / 41.0 + 1.3) + 0.04 * sin(h / 17.0)
	var worst := 0.0
	for t in tracks:
		worst = maxf(worst, _proximity(t, cx, cz, 1.0))       # the whole cloud's reach, so the glass falls early
	return p - STORM_DROP_INHG * worst


func pressure_inhg() -> float:
	var p := ship_chart_pos()
	return pressure_inhg_at(p.x, p.y)


## The closest storm to the ship: {kind, dist_m, bearing_deg}, or {} if there is none.
func nearest_storm() -> Dictionary:
	var p := ship_chart_pos()
	var best: Track = null
	var bd := INF
	for t in tracks:
		var d := Vector2(t.cx, t.cz).distance_to(p)
		if d < bd:
			bd = d
			best = t
	if best == null:
		return {}
	return {"kind": best.kind, "dist_m": bd, "bearing_deg": WorldChart.heading_to(p.x, p.y, best.cx, best.cz)}


# ------------------------------------------------------------------ time

func _process(delta: float) -> void:
	_find_sky(delta)
	_advance(delta * clock_hours_per_second * 3600.0)
	if drive_sky and _sky != null:
		_sky.hours_per_second = 0.0
		_sky.time_hours = hour_of_day()
		_sky.declination_deg = WindFieldS.declination_deg(year_phase())
		_sky.season_phase = year_phase()
		_sky.moon_phase = moon_phase()
		_sky.lunar_cycle_days = lunar_cycle_days
		_sky_t -= delta
		if _sky_t <= 0.0:
			_sky_t = 0.5
			var v := wind_at_ship()
			_sky.wind_dir_deg = WindFieldS.heading_of(v)
			_sky.cloud_speed = 0.0006 + 0.0004 * v.length()
	_sync_sky()
	_update_ship_weather(delta)
	var s := season()
	if s != _last_season:
		_last_season = s
		season_changed.emit(s)


## Advance the world clock and the storms by dt game seconds.
func _advance(dt: float) -> void:
	game_hours += dt / 3600.0
	if storms_enabled:
		_step_tracks(dt)
		_maybe_spawn(dt)


## Let hours of game time pass (a sleep). The storms move on and the season may change.
func advance_hours(hours: float) -> void:
	var left := hours * 3600.0
	while left > 0.0:
		var dt := minf(600.0, left)
		_advance(dt)
		left -= dt
	_sync_sky()
	time_jumped.emit()


func _warm_up() -> void:
	var steps := int(warmup_hours * 6.0)
	for i in steps:
		_advance(600.0)
	game_hours = 0.0
	# fair weather at the start
	var sp := ship_chart_pos()
	for i in range(tracks.size() - 1, -1, -1):
		var t := tracks[i]
		if Vector2(t.cx, t.cz).distance_to(sp) < clear_start_radius_m + t.cell.radius_m:
			tracks.remove_at(i)


# ------------------------------------------------------------------ storms

func _step_tracks(dt: float) -> void:
	for i in range(tracks.size() - 1, -1, -1):
		var t := tracks[i]
		t.age += dt
		t.heading = fposmod(t.heading + t.curve * dt / 3600.0, 360.0)
		var v := WindFieldS.vec(t.speed, t.heading)
		t.cx += v.x * dt
		t.cz += v.y * dt
		var u := t.age / t.life
		t.cell.intensity = t.peak * smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.7, 1.0, u))
		var m := 150000.0
		if t.age >= t.life or t.cx < -m or t.cx > field.width_m + m or t.cz < -m or t.cz > field.height_m + m:
			_remove_track(i)


func _remove_track(i: int) -> void:
	var t := tracks[i]
	if _sky != null:
		_sky.storms.erase(t.cell)
	tracks.remove_at(i)


## Storms form at rates that follow the season (see the header).
func _maybe_spawn(dt: float) -> void:
	if tracks.size() >= max_storms:
		return
	var ph := year_phase()
	var winter := WindFieldS.winter_amount(ph)
	var m := WindFieldS.monsoon_sign(ph)
	var afternoon := 0.5 + 0.5 * cos(TAU * (hour_of_day() - 15.0) / 24.0)
	var per_hour := {
		"gale": 0.10 * (0.15 + 0.85 * winter * winter),
		"hurricane": 0.045 * exp(-pow((ph - 0.42) / 0.09, 2.0)),
		"cyclone": 0.05 * pow(1.0 - absf(m), 3.0),
		"squall": 0.10 * (0.4 + 0.3 + 0.3 * m) * (0.4 + 0.6 * afternoon),
	}
	var hours := dt / 3600.0
	for kind in per_hour:
		if tracks.size() >= max_storms:
			return
		if _rng.randf() < 1.0 - exp(-float(per_hour[kind]) * hours):
			_spawn(kind)


func _spawn(kind: String) -> void:
	var w := field.width_m
	var h := field.height_m
	var t := Track.new()
	t.kind = kind
	var radius := 30000.0
	var rain := 0.85
	match kind:
		"gale":
			t.cx = -40000.0
			t.cz = _rng.randf_range(0.02, 0.32) * h
			t.heading = _rng.randf_range(70.0, 100.0)
			t.speed = _rng.randf_range(9.0, 12.0)
			t.life = _rng.randf_range(16.0, 22.0) * 3600.0
			t.peak = _rng.randf_range(0.85, 1.0)
			t.wind_boost = 15.0
			radius = _rng.randf_range(35000.0, 65000.0)
			rain = 0.8
		"hurricane":
			t.cx = _rng.randf_range(0.70, 0.90) * w
			t.cz = _rng.randf_range(0.52, 0.72) * h
			t.heading = _rng.randf_range(238.0, 255.0)
			t.speed = _rng.randf_range(5.5, 7.5)
			t.curve = 2.0
			t.life = _rng.randf_range(20.0, 28.0) * 3600.0
			t.peak = 1.0
			t.wind_boost = 20.0
			radius = _rng.randf_range(45000.0, 75000.0)
			rain = 1.0
		"cyclone":
			t.cx = w + 40000.0
			t.cz = _rng.randf_range(0.10, 0.85) * h
			t.heading = _rng.randf_range(255.0, 290.0)
			t.speed = _rng.randf_range(5.0, 7.0)
			t.curve = 1.0
			t.life = _rng.randf_range(18.0, 26.0) * 3600.0
			t.peak = _rng.randf_range(0.9, 1.0)
			t.wind_boost = 18.0
			radius = _rng.randf_range(40000.0, 70000.0)
			rain = 0.95
		_:
			t.kind = "squall"
			t.cx = _rng.randf_range(0.15, 0.85) * w
			t.cz = _rng.randf_range(0.36, 0.56) * h
			t.heading = _rng.randf_range(0.0, 360.0)
			t.speed = _rng.randf_range(2.5, 4.5)
			t.life = _rng.randf_range(2.5, 4.0) * 3600.0
			t.peak = _rng.randf_range(0.55, 0.8)
			t.wind_boost = 9.0
			radius = _rng.randf_range(8000.0, 14000.0)
			rain = 0.6
	var c := StormCell.new()
	c.set_size(radius)
	c.intensity = 0.0
	c.rain = rain
	c.shape_seed = _rng.randf() * 50.0
	c.velocity = Vector2.ZERO          # we move it ourselves, in chart metres (the sky's own stepping does nothing)
	t.cell = c
	tracks.append(t)
	if _sky != null:
		_sky.storms.append(c)


## The storm waiting outside the starting harbour (start_storm): out from the port in the way its mouth faces, heading
## slowly back in, already at full strength.
func _spawn_start_storm() -> void:
	if not storms_enabled or not start_storm:
		return
	var sp := ship_chart_pos()
	var pz := Vector2.ZERO
	if _streamer != null and _streamer.chart != null:
		pz = _port_zone(sp.x, sp.y)
	var bearing := pz.y                          # 0 (north) if the ship is not in a harbour
	var off := WindFieldS.vec(start_storm_distance_m, bearing)
	var t := Track.new()
	t.kind = "gale"
	t.cx = sp.x + off.x
	t.cz = sp.y + off.y
	t.heading = fposmod(bearing + 180.0, 360.0)
	t.speed = start_storm_speed_mps
	t.life = 14.0 * 3600.0
	t.age = 0.2 * t.life
	t.peak = 1.0
	t.wind_boost = 15.0
	var c := StormCell.new()
	c.set_size(30000.0)
	c.intensity = 1.0
	c.rain = 0.85
	c.shape_seed = 17.0
	c.velocity = Vector2.ZERO
	t.cell = c
	tracks.append(t)
	if _sky != null:
		_sky.storms.append(c)
	_sync_sky()


# ------------------------------------------------------------------ the sky

func _find_sky(delta: float) -> void:
	_find_t -= delta
	if _find_t > 0.0:
		return
	_find_t = 1.0
	if _sky != null and is_instance_valid(_sky):
		return
	var root := get_tree().current_scene
	if root == null:
		return
	for n in root.find_children("*", "SkySystem", true, false):
		_sky = n as SkySystem
		break
	if _sky != null:
		for t in tracks:
			if not _sky.storms.has(t.cell):
				_sky.storms.append(t.cell)


## Put the storm cells where the sky expects them: the Godot scene's own coordinates (the chart less the origin).
func _sync_sky() -> void:
	if _sky == null or _streamer == null:
		return
	var o := Vector2(_streamer.origin_x, _streamer.origin_z)
	for t in tracks:
		t.cell.pos = Vector2(t.cx, t.cz) - o
		t.cell.velocity = Vector2.ZERO


# ------------------------------------------------------------------ readout

func status_text() -> String:
	var p := ship_chart_pos()
	var v := wind_at(p.x, p.y)
	var ph := year_phase()
	var s := "%s, day %d of %d   %02d:%02d   %s\nwind %.1f m/s (%d kn) toward %03d" % [
		date_text(), int(calendar_day()) + 1, int(year_days()), int(hour_of_day()), int(fmod(hour_of_day(), 1.0) * 60.0),
		field.region_name(p.x, p.y, ph), v.length(), roundi(v.length() / 0.5144), int(WindFieldS.heading_of(v))]
	var n := nearest_storm()
	if n.is_empty():
		s += "   no storms"
	else:
		s += "   nearest storm: %s, %.0f km at bearing %03d   (%d active)" % [n["kind"], float(n["dist_m"]) / 1000.0, int(n["bearing_deg"]), tracks.size()]
	if _rain_now > 0.01:
		s += "   rain %d%%" % int(_rain_now * 100.0)
	return s


# ------------------------------------------------------------------ sleeping through weather

## Hours until a ship sailing straight on (heading, speed) from a chart position would come into a storm's weather
## (storm_wake_level), looking ahead with the storms moving on; -1 if not within `hours`. 0 = already in it.
## Only the storms that exist now are looked at (a sleep itself checks as it goes, see sleep_advance).
func storm_wake_in(cx: float, cz: float, heading_deg: float, speed_mps: float, hours: float, curve_per_m := 0.0) -> float:
	if tracks.is_empty() or hours <= 0.0:
		return -1.0
	var total := hours * 3600.0
	var n := tracks.size()
	var tx := PackedFloat64Array()
	var tz := PackedFloat64Array()
	var th := PackedFloat64Array()
	var ta := PackedFloat64Array()
	tx.resize(n)
	tz.resize(n)
	th.resize(n)
	ta.resize(n)
	for i in n:
		tx[i] = tracks[i].cx
		tz[i] = tracks[i].cz
		th[i] = tracks[i].heading
		ta[i] = tracks[i].age
	var t := 0.0
	while true:
		var sp := WorldChart.arc_pos(cx, cz, heading_deg, speed_mps * t, curve_per_m)
		var sx := sp.x
		var sz := sp.y
		for i in n:
			var trk := tracks[i]
			var u := ta[i] / trk.life
			var inten := trk.peak * smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.7, 1.0, u))
			var dp := maxf(trk.cell.depth_m * danger_depth_scale, 1.0)
			var d := Vector2(sx - tx[i], sz - tz[i]).length()
			if inten * (1.0 - smoothstep(0.8 * dp, 3.5 * dp, d)) >= storm_wake_level:
				return t / 3600.0
		if t >= total:
			break
		var dt := minf(600.0, total - t)
		for i in n:
			th[i] = fposmod(th[i] + tracks[i].curve * dt / 3600.0, 360.0)
			var v := WindFieldS.vec(tracks[i].speed, th[i])
			tx[i] += v.x * dt
			tz[i] += v.y * dt
			ta[i] += dt
		t += dt
	return -1.0


## A sleep: let up to `hours` of game time pass while the ship sails straight on (heading, speed) from a chart position.
## The weather moves for real, in ten-minute steps, and the sleep ends early if a storm's weather (storm_wake_level) is
## about to reach the ship, new storms included. Returns the hours that did pass.
## ride_out: she is under bare poles and sleeps through it. Nothing ends the sleep, and out["storm_hours"] says how many
## hours of it she lay in the storm's weather (storm_wake_level), for the damage to be worked out from.
func sleep_advance(cx: float, cz: float, heading_deg: float, speed_mps: float, hours: float, ride_out := false, out: Dictionary = {}, curve_per_m := 0.0) -> float:
	var total := hours * 3600.0
	var t := 0.0
	var stopped := false
	var storm_s := 0.0
	out["storm_hours"] = 0.0
	while t < total and not stopped:
		var dt := minf(600.0, total - t)
		_advance(dt)
		t += dt
		var sp := WorldChart.arc_pos(cx, cz, heading_deg, speed_mps * t, curve_per_m)
		var sx := sp.x
		var sz := sp.y
		for trk in tracks:
			if _proximity(trk, sx, sz) >= storm_wake_level:
				if ride_out:
					storm_s += dt
					out["storm_hours"] = storm_s / 3600.0
				else:
					stopped = true
				break
	_sync_sky()
	time_jumped.emit()
	return t / 3600.0


# ------------------------------------------------------------------ rain and the mood of a storm

## 0-1: how hard it is raining at a chart position. The rain is held nearer a storm's heart than its wind is, so you
## feel the wind come first and see the rain wall after.
func rain_at(cx: float, cz: float) -> float:
	var best := 0.0
	for t in tracks:
		var dp := maxf(t.cell.depth_m * danger_depth_scale, 1.0)
		var d := Vector2(cx - t.cx, cz - t.cz).length()
		best = maxf(best, t.cell.rain * t.cell.intensity * (1.0 - smoothstep(0.5 * dp, 1.7 * dp, d)))
	return best


func rain_at_ship() -> float:
	var p := ship_chart_pos()
	return rain_at(p.x, p.y)


## 0 at night, 1 in full daylight, from the clock and date (same sun as SkySystem, latitude 25).
func daylight() -> float:
	var h := deg_to_rad((hour_of_day() - 12.0) * 15.0)
	var lat := deg_to_rad(25.0)
	var dec := deg_to_rad(WindFieldS.declination_deg(year_phase()))
	var up := sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h)
	return smoothstep(-0.1, 0.3, up)


func _wind_vec() -> Vector2:
	if _wind_node == null or not is_instance_valid(_wind_node):
		_wind_node = get_tree().get_first_node_in_group("wind")
	if _wind_node != null and _wind_node.has_method("velocity"):
		var v: Vector3 = _wind_node.velocity()
		return Vector2(v.x, v.z)
	return wind_at_ship()


## What the weather is doing to the ship right now: looked at ten times a second, smoothed every frame.
func _update_ship_weather(delta: float) -> void:
	_ship_t -= delta
	if _ship_t <= 0.0:
		_ship_t = 0.1
		var p := ship_chart_pos()
		_rain_now = rain_at(p.x, p.y)
		var best := 0.0
		for t in tracks:
			best = maxf(best, _proximity(t, p.x, p.y))
		_dark_now = best
		if rain_fx != null:
			rain_fx.set("intensity", _rain_now)
			rain_fx.set("wind", _wind_vec())
			rain_fx.set("daylight", daylight())
	_rain_s = lerpf(_rain_s, _rain_now, 1.0 - exp(-delta / 1.5))
	_dark_s = lerpf(_dark_s, _dark_now, 1.0 - exp(-delta / 4.0))
	_apply_mood(delta)


## With no SkySystem in the scene, darken it ourselves: a grey sky, a dimmer sun and thicker fog as a storm comes in,
## and a short view in the rain. (A SkySystem does all of this itself, from the same storm cells.)
func _apply_mood(delta: float) -> void:
	if not mood_enabled or _sky != null:
		return
	if _env == null:
		_env_t -= delta
		if _env_t > 0.0:
			return
		_env_t = 1.0
		_find_env()
		if _env == null:
			return
	var k := clampf(_dark_s, 0.0, 1.0)
	_env.fog_density = float(_env_base["fog"]) + 0.0010 * _rain_s + 0.0004 * k
	_env.fog_light_color = (_env_base["fog_color"] as Color).lerp(Color(0.24, 0.27, 0.31), clampf(k * 0.85, 0.0, 1.0))
	var sm = _env_base.get("sky")
	if sm is ProceduralSkyMaterial:
		var kk := clampf(k * 0.9, 0.0, 1.0)
		sm.sky_top_color = (_env_base["top"] as Color).lerp(Color(0.14, 0.16, 0.20), kk)
		sm.sky_horizon_color = (_env_base["horizon"] as Color).lerp(Color(0.30, 0.33, 0.37), kk)
		sm.ground_horizon_color = (_env_base["ground_horizon"] as Color).lerp(Color(0.30, 0.33, 0.37), kk)
		sm.ground_bottom_color = (_env_base["ground_bottom"] as Color).lerp(Color(0.06, 0.08, 0.10), kk)
	if _sun != null and is_instance_valid(_sun):
		_sun.light_energy = _sun_base * (1.0 - 0.7 * k)


func _find_env() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var we: WorldEnvironment = null
	for n in root.find_children("*", "WorldEnvironment", true, false):
		we = n as WorldEnvironment
		break
	if we == null or we.environment == null:
		return
	_env = we.environment
	_env_base = {"fog": _env.fog_density, "fog_color": _env.fog_light_color}
	if _env.sky != null and _env.sky.sky_material is ProceduralSkyMaterial:
		var p := _env.sky.sky_material as ProceduralSkyMaterial
		_env_base["sky"] = p
		_env_base["top"] = p.sky_top_color
		_env_base["horizon"] = p.sky_horizon_color
		_env_base["ground_horizon"] = p.ground_horizon_color
		_env_base["ground_bottom"] = p.ground_bottom_color
	for n in root.find_children("*", "DirectionalLight3D", true, false):
		_sun = n as DirectionalLight3D
		_sun_base = _sun.light_energy
		break
