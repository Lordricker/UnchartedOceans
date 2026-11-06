extends Node
## The game's music. Autoload "MusicManager", so it keeps going across scene changes.
##
## Tracks live in res://assets/audio/music/:
##   music/*.mp3        PORT music (plays while you are in or near a port)
##   music/calm/        SEA music, one folder per mood. The manager picks the mood from the weather and the time of day:
##   music/upbeat/        dangerous  a heavy sea or a storm close by
##   music/dangerous/     calm       night, or a flat calm and hardly any wind
##                        upbeat     everything else (daytime, fair weather)
## A new mood folder is found by itself; to use it, give _wanted_mood() a case for it.
##
## It is not a playlist, it follows where the ship is (the same things Ambience reads: the world chart's ports,
## ShipHarbor.moored, SeaWind, WorldWeather):
##   leaving port   once the ship is more than leave_ratio x the harbour radius from the port, the port music fades out
##                  slowly (port_fade_out_s), then there are sea_delay_s of just waves and wind, then a sea track
##                  fades in (sea_fade_in_s). The quiet stretch is on purpose: it makes the sea feel big.
##   coming in      inside arrive_ratio x the harbour radius (the harbour approach, before you are docked) the sea
##                  music goes out quickly (sea_fade_out_s) and the port music fades in (port_fade_in_s).
##   in between     the state is kept (leave_ratio < arrive_ratio), so the music does not flip back and forth at the line.
##   port tracks    shuffle with no repeats, overlapping by port_crossfade_s.
##   sea tracks     shuffle with no repeats; when one ends, a random silence of sea_gap_min_s..sea_gap_max_s, then the next.
##   a storm        building while a calm or upbeat track plays crossfades into a dangerous one (mood_change_fade_s).
##                  The other way round it waits for the track to end.
## Fades are in dB (a straight line in dB sounds even) and run on real time, so fast forward does not shorten them.
## Everything plays on the "Music" bus (made by Ambience, or here if it is missing); music_db sets its level.
## The debug HUD (H) shows status_text().

const DIR := "res://assets/audio/music/"
const BUS_MUSIC := "Music"
const POOL_PORT := "port"
const FLOOR_DB := -50.0
const EXTS := ["mp3", "ogg", "wav"]
const DEFAULT_HARBOR_M := 200.0         # same as WorldChart.HARBOR_M_DEFAULT
const ISLAND_HARBOR_M := 220.0          # test scene without a chart: the island's cove (as ShipAnchor.island_harbor_m)

enum State { NONE, IN_PORT, AT_SEA }
enum Phase { IDLE, PLAYING, GAP }

@export var enabled := true
## The player's music slider, 0..1 (GameSettings sets it from the pause menu). It turns music_db down from there.
@export_range(0.0, 1.0, 0.01) var music_volume := 1.0:
	set(v):
		music_volume = clampf(v, 0.0, 1.0)
		_apply_bus_volume()
## Loudest level of the whole Music bus, dB.
@export var music_db := -6.0:
	set(v):
		music_db = v
		_apply_bus_volume()

@export_group("Port")
@export var port_fade_in_s := 5.0
@export var port_fade_out_s := 7.0
@export var port_crossfade_s := 3.0
## Leaving: the ship is farther than this many harbour radii from the port. Arriving: closer than arrive_ratio.
@export var leave_ratio := 1.5
@export var arrive_ratio := 3.0

@export_group("Sea")
## Silence (waves and wind only) between the port music going and the first sea track.
@export var sea_delay_s := 8.0
@export var sea_fade_in_s := 6.0
@export var sea_fade_out_s := 2.5
## Silence between two sea tracks, a random time in this range.
@export var sea_gap_min_s := 8.0
@export var sea_gap_max_s := 25.0
@export var mood_change_fade_s := 4.0
## A track must have played this long before a storm may cut it short.
@export var min_track_s := 20.0

var _pools := {}                 # pool name -> Array[String] of res:// paths ("port", "calm", ...)
var _bags := {}                  # pool name -> shuffled paths still to play
var _last := {}                  # pool name -> the track played last
var _pool_players: Array[AudioStreamPlayer] = []
var _tweens := {}                # AudioStreamPlayer -> Tween

var _state := State.NONE
var _phase := Phase.IDLE
var _gap_t := 0.0
var _main: AudioStreamPlayer     # the track that is "the" music right now (fading in or playing)
var _main_mood := ""
var _track_name := ""
var _track_started := 0.0

var _t := 0.0                    # real seconds (Engine.time_scale taken out)
var _find_t := 0.0
var _sample_t := 0.0

var _streamer: Node
var _weather: Node
var _wind: Node
var _ocean: Node
var _ship: Node3D
var _harbor: Node
var _island: Node3D

var _have_world := false
var _wind_mps := 6.0
var _sea_level := 1.0
var _storm := 0.0
var _daylight := 1.0
var _danger_on := false
var _ratio := INF


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("music")
	randomize()
	_ensure_bus()
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.name = "Music_%d" % i
		p.bus = StringName(BUS_MUSIC)
		p.volume_db = FLOOR_DB
		add_child(p)
		_pool_players.append(p)
	_scan_pools()


# ------------------------------------------------------------------ set-up

func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_MUSIC) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS_MUSIC)
		AudioServer.set_bus_send(i, "Master")
	_apply_bus_volume()


func _apply_bus_volume() -> void:
	var i := AudioServer.get_bus_index(BUS_MUSIC)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, music_db + (linear_to_db(music_volume) if music_volume > 0.001 else -80.0))


## Port music is the files straight in DIR, every subfolder is a sea mood.
func _scan_pools() -> void:
	_pools.clear()
	var port := _files_in(DIR)
	if not port.is_empty():
		_pools[POOL_PORT] = port
	for d in DirAccess.get_directories_at(DIR):
		var files := _files_in(DIR.path_join(d))
		if not files.is_empty():
			_pools[d] = files
	if _pools.is_empty():
		push_warning("MusicManager: no music found in %s (open the project in the editor once so Godot imports the files)" % DIR)


## The audio files in a folder. A built game lists "x.mp3.import" / "x.mp3.remap" instead of the mp3, so those count too.
func _files_in(path: String) -> Array[String]:
	var names: Array[String] = []
	for f in DirAccess.get_files_at(path):
		var n := f
		if n.ends_with(".import"):
			n = n.trim_suffix(".import")
		elif n.ends_with(".remap"):
			n = n.trim_suffix(".remap")
		if EXTS.has(n.get_extension().to_lower()) and not names.has(n):
			names.append(n)
	names.sort()
	var out: Array[String] = []
	for n in names:
		out.append(path.path_join(n))
	return out


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("MusicManager: %s is not imported yet (open the project in the editor once)" % path)
		return null
	var s := load(path) as AudioStream
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = false
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = false
	return s


# ------------------------------------------------------------------ shuffle

## Next track of a pool: a shuffled bag, so every track plays once before any repeats, and the first track of a
## new bag is never the one that just played.
func _pick(pool: String) -> String:
	var paths: Array = _pools.get(pool, [])
	if paths.is_empty():
		return ""
	var bag: Array = _bags.get(pool, [])
	if bag.is_empty():
		bag = paths.duplicate()
		bag.shuffle()
		if bag.size() > 1 and bag[0] == _last.get(pool, ""):
			var tmp = bag[0]
			bag[0] = bag[bag.size() - 1]
			bag[bag.size() - 1] = tmp
	var path: String = bag.pop_front()
	_bags[pool] = bag
	_last[pool] = path
	return path


func _sea_pools() -> Array[String]:
	var out: Array[String] = []
	for k in _pools:
		if String(k) != POOL_PORT:
			out.append(String(k))
	return out


# ------------------------------------------------------------------ looking round

func _find_nodes() -> void:
	var tree := get_tree()
	if _streamer == null or not is_instance_valid(_streamer):
		_streamer = tree.get_first_node_in_group("world_streamer")
	if _weather == null or not is_instance_valid(_weather):
		_weather = tree.get_first_node_in_group("weather")
	if _wind == null or not is_instance_valid(_wind):
		_wind = tree.get_first_node_in_group("wind")
	if _ship == null or not is_instance_valid(_ship):
		_ship = tree.get_first_node_in_group("ships") as Node3D
	if _harbor == null or not is_instance_valid(_harbor):
		_harbor = tree.get_first_node_in_group("ship_harbor")
	if _island == null or not is_instance_valid(_island):
		_island = tree.get_first_node_in_group("islands") as Node3D
	if _ocean == null or not is_instance_valid(_ocean):
		_ocean = null
		if _wind != null:
			var np = _wind.get("ocean_path")
			if np is NodePath:
				_ocean = _wind.get_node_or_null(np)


func _sample() -> void:
	_have_world = _streamer != null or _wind != null or _ship != null
	if _wind != null and _wind.has_method("speed"):
		_wind_mps = float(_wind.call("speed"))
	else:
		_wind_mps = 6.0
	if _ocean != null:
		_sea_level = float(_ocean.get("sea_level"))
	else:
		_sea_level = clampf(remap(_wind_mps, 3.0, 22.0, 0.0, 3.0), 0.0, 3.0)
	_storm = 0.0
	_daylight = 1.0
	if _weather != null:
		if _weather.has_method("storm_proximity_at_ship"):
			_storm = float(_weather.call("storm_proximity_at_ship"))
		if _weather.has_method("daylight"):
			_daylight = float(_weather.call("daylight"))
	_ratio = _port_ratio()
	# danger has a margin (on at 0.6, off at 0.3) so one wave does not flip the mood
	var d := maxf(smoothstep(1.8, 2.8, _sea_level), smoothstep(0.15, 0.6, _storm))
	_danger_on = d > 0.3 if _danger_on else d > 0.6


## How far the ship is from the nearest port, in harbour radii (0 when moored, INF when no port is known).
func _port_ratio() -> float:
	if _harbor != null and is_instance_valid(_harbor) and bool(_harbor.get("moored")):
		return 0.0
	if _streamer != null and is_instance_valid(_streamer) and _streamer.has_method("ship_cx"):
		var chart = _streamer.get("chart")
		if chart != null:
			var np: Dictionary = chart.call("nearest_port", float(_streamer.call("ship_cx")), float(_streamer.call("ship_cz")))
			if np.is_empty() or not np.has("dist_m"):
				return INF
			var r := maxf(float(np.get("harbor_m", DEFAULT_HARBOR_M)), 50.0)
			return float(np["dist_m"]) / r
	# the test scene has no chart, only an island with a cove
	if _island != null and is_instance_valid(_island) and _ship != null and bool(_island.get("harbor")):
		return _ship.global_position.distance_to(_island.global_position) / ISLAND_HARBOR_M
	return INF


func _wanted_mood() -> String:
	if _danger_on and _pools.has("dangerous"):
		return "dangerous"
	if _daylight < 0.2 or (_sea_level < 0.6 and _wind_mps < 4.0):
		return "calm"
	return "upbeat"


# ------------------------------------------------------------------ the main loop

func _process(delta: float) -> void:
	var dt := delta / maxf(Engine.time_scale, 0.01)       # fast forward must not speed the music up
	_t += dt
	if not enabled:
		if _state != State.NONE:
			_fade_out_main(1.5)
			_state = State.NONE
			_phase = Phase.IDLE
		return
	_find_t -= dt
	if _find_t <= 0.0:
		_find_t = 1.0
		_find_nodes()
	_sample_t -= dt
	if _sample_t <= 0.0:
		_sample_t = 0.5
		_sample()
		_decide()
		_mood_check()
	if _state == State.NONE:
		return
	match _phase:
		Phase.GAP:
			_gap_t -= dt
			if _gap_t <= 0.0:
				_play_next(sea_fade_in_s if _state == State.AT_SEA else port_fade_in_s)
		Phase.PLAYING:
			_watch_track()


## Port or sea, with a margin between leaving and arriving (leave_ratio < arrive_ratio).
func _decide() -> void:
	if not _have_world:
		return
	match _state:
		State.NONE:
			if _ratio <= (leave_ratio + arrive_ratio) * 0.5:
				_enter_port(true)
			else:
				_enter_sea(true)
		State.IN_PORT:
			if _ratio > leave_ratio:
				_enter_sea(false)
		State.AT_SEA:
			if _ratio < arrive_ratio:
				_enter_port(false)


func _enter_port(initial: bool) -> void:
	_state = State.IN_PORT
	_fade_out_main(0.0 if initial else sea_fade_out_s)
	_start_port_track(3.0 if initial else port_fade_in_s)


func _enter_sea(initial: bool) -> void:
	_state = State.AT_SEA
	_fade_out_main(0.0 if initial else port_fade_out_s)
	_phase = Phase.GAP
	_gap_t = 2.0 if initial else sea_delay_s


## A storm building while a gentler track plays, or while the sea is in its silence: bring in the dangerous music.
func _mood_check() -> void:
	if _state != State.AT_SEA or _wanted_mood() != "dangerous":
		return
	if _phase == Phase.GAP:
		_gap_t = minf(_gap_t, 1.0)
	elif _phase == Phase.PLAYING and _main != null and _main_mood != "dangerous" and _t - _track_started > min_track_s:
		var path := _pick("dangerous")
		if path != "":
			_fade_out_main(mood_change_fade_s)
			_play_path(path, "dangerous", mood_change_fade_s)


## Watches the current track: port tracks overlap into the next one, a sea track that ends leaves a silence.
func _watch_track() -> void:
	if _main == null or not _main.playing:
		_main = null
		if _state == State.AT_SEA:
			_phase = Phase.GAP
			_gap_t = randf_range(sea_gap_min_s, maxf(sea_gap_min_s, sea_gap_max_s))
		else:
			_start_port_track(port_crossfade_s)
		return
	if _state == State.IN_PORT and _main.stream != null:
		var length := _main.stream.get_length()
		if length > 0.0 and length - _main.get_playback_position() <= port_crossfade_s + 0.1:
			_fade_out_main(port_crossfade_s)
			_start_port_track(port_crossfade_s)


func _play_next(fade_in: float) -> void:
	if _state == State.IN_PORT:
		_start_port_track(fade_in)
	elif _state == State.AT_SEA:
		_start_sea_track(fade_in)


func _start_port_track(fade_in: float) -> void:
	_play_path(_pick(POOL_PORT), POOL_PORT, fade_in)


func _start_sea_track(fade_in: float) -> void:
	var mood := _wanted_mood()
	if not _pools.has(mood):
		var any := _sea_pools()
		if any.is_empty():
			_phase = Phase.IDLE
			return
		mood = any[randi() % any.size()]
	_play_path(_pick(mood), mood, fade_in)


# ------------------------------------------------------------------ playing and fading

func _play_path(path: String, mood: String, fade_in: float) -> void:
	if path == "":
		_phase = Phase.IDLE
		return
	var s := _load_stream(path)
	if s == null:
		_phase = Phase.GAP          # try again later, do not spam warnings
		_gap_t = 30.0
		return
	var p := _free_player()
	_kill_tween(p)
	p.stream = s
	p.volume_db = FLOOR_DB
	p.play()
	_fade_to(p, 0.0, fade_in)
	_main = p
	_main_mood = mood
	_track_name = path.get_file()
	_track_started = _t
	_phase = Phase.PLAYING


func _free_player() -> AudioStreamPlayer:
	var quietest: AudioStreamPlayer = null
	for p in _pool_players:
		if not p.playing:
			return p
		if p != _main and (quietest == null or p.volume_db < quietest.volume_db):
			quietest = p
	return quietest


func _fade_out_main(secs: float) -> void:
	if _main == null:
		return
	if _main.playing:
		_fade_to(_main, FLOOR_DB, secs, true)
	_main = null


func _fade_to(p: AudioStreamPlayer, db: float, secs: float, stop_after := false) -> void:
	_kill_tween(p)
	if secs <= 0.0:
		p.volume_db = db
		if stop_after:
			p.stop()
		return
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p, "volume_db", db, secs)
	if stop_after:
		tw.tween_callback(p.stop)
	_tweens[p] = tw


func _kill_tween(p: AudioStreamPlayer) -> void:
	var tw = _tweens.get(p)
	if tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()
	_tweens.erase(p)


# ------------------------------------------------------------------ debug

## Lines for the debug HUD.
func status_text() -> String:
	var st := "none"
	match _state:
		State.IN_PORT:
			st = "PORT"
		State.AT_SEA:
			st = "SEA"
	var ph := "idle"
	match _phase:
		Phase.PLAYING:
			ph = "playing"
		Phase.GAP:
			ph = "silence, %.0f s to go" % maxf(_gap_t, 0.0)
	var track := "-"
	if _main != null and _main.playing:
		track = "%s  [%s]  %.0f / %.0f s" % [_track_name, _main_mood, _main.get_playback_position(), _main.stream.get_length()]
	var dist := "n/a" if _ratio == INF else "%.1f x harbour radius" % _ratio
	return "music: %s, %s   %s\n  port distance %s (leave > %.1f, arrive < %.1f)   mood wanted %s%s" % [
		st, ph, track, dist, leave_ratio, arrive_ratio, _wanted_mood(), "  (danger)" if _danger_on else ""]
