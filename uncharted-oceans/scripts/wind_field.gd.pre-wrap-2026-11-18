class_name WindField
extends RefCounted
## The prevailing wind of the whole chart, as pure maths: where the air is going at any chart position and
## any time of year. No scene needed, so tests can run it headless.
##
## Chart frame: x east, z south (north is -Z), metres from the chart's top-left. A wind vector is the air's
## velocity, Vector2(x, z) in m/s. Headings are "toward" bearings, 0 = north, 90 = east, clockwise.
##
## The world's wind (a stylised globe, in the order a sailor meets it going south):
##  - Westerlies  (north, the top third)   blow from the west-southwest. Strong in winter. Fast way east.
##  - Calm belt   (the middle band)        the two systems cancel: light, shifting airs. The central archipelago and the
##                                         free port sit in it.
##  - Trade winds (south)                  blow steadily from the northeast. The fast way west.
##  - Monsoon     (the eastern third)      replaces all of that: from the southwest in summer, from the northeast in winter,
##                                         and in the changeover months it falls light and unsettled.
## Where the winds meet (the monsoon's western edge, the calm belt) the vectors blend, so the changes are gradual and
## real lulls appear there on their own.
## On top of that, near any coast there is a daily breeze: onto the land by day, off it at night (coastal()).
##
## Year phase: 0 = spring equinox, 0.25 = summer solstice, 0.5 = autumn equinox, 0.75 = winter solstice.

const WESTERLY_TOWARD_DEG := 78.0
const TRADE_TOWARD_DEG := 235.0
const SW_MONSOON_TOWARD_DEG := 48.0      # the summer monsoon blows from the southwest, toward the northeast
const NE_MONSOON_TOWARD_DEG := 228.0     # the winter monsoon blows from the northeast, toward the southwest
## Distance from the coast inside which the daily breeze blows, metres.
const COAST_RANGE_M := 20000.0

var width_m := 600000.0
var height_m := 400000.0
## Speeds in m/s as (summer, winter).
var westerly_speed := Vector2(7.0, 11.0)
var trade_speed := Vector2(6.0, 8.0)
var monsoon_peak_speed := 9.0
## Typical speed in the calm belt and the monsoon changeover.
var lull_speed := 4.0
## Strength of the coastal breeze, m/s.
var coast_speed := 3.0

var _noise := FastNoiseLite.new()


func _init(w: float = 600000.0, h: float = 400000.0) -> void:
	width_m = w
	height_m = h
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = 4242


## Air velocity (x east, z south) for a heading it is going toward and a speed.
static func vec(speed: float, toward_deg: float) -> Vector2:
	var r := deg_to_rad(toward_deg)
	return Vector2(sin(r), -cos(r)) * speed


## Heading the air is going toward, degrees.
static func heading_of(v: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)


## +1 at the summer solstice (peak southwest monsoon), -1 at the winter solstice (peak northeast monsoon), 0 at the equinoxes.
static func monsoon_sign(phase: float) -> float:
	return sin(TAU * phase)


## 0 in summer, 1 in winter.
static func winter_amount(phase: float) -> float:
	return 0.5 - 0.5 * sin(TAU * phase)


## The sun's declination for the date, degrees.
static func declination_deg(phase: float) -> float:
	return 23.5 * sin(TAU * phase)


static func season_name(phase: float) -> String:
	var p := fposmod(phase, 1.0)
	if p < 0.125 or p >= 0.875:
		return "spring"
	if p < 0.375:
		return "summer"
	if p < 0.625:
		return "autumn"
	return "winter"


## A slow, smooth variable wind (light airs that wander through the whole compass).
func _variable(cx: float, cz: float, speed: float) -> Vector2:
	var ang := _noise.get_noise_2d(cx / 90000.0, cz / 90000.0) * 270.0
	var s := 0.5 + 0.5 * _noise.get_noise_2d(cx / 70000.0 + 50.0, cz / 70000.0 - 30.0)
	return vec(speed * (0.7 + 0.6 * s), ang + 180.0)


## The prevailing wind at a chart position and year phase, before the coastal breeze and any storm.
func prevailing(cx: float, cz: float, phase: float) -> Vector2:
	var f := clampf(cz / height_m, 0.0, 1.0)         # 0 north .. 1 south
	var g := clampf(cx / width_m, 0.0, 1.0)          # 0 west .. 1 east
	var winter := winter_amount(phase)

	var westerly := vec(lerpf(westerly_speed.x, westerly_speed.y, winter), WESTERLY_TOWARD_DEG)
	var trade := vec(lerpf(trade_speed.x, trade_speed.y, winter), TRADE_TOWARD_DEG)
	var belt := westerly.lerp(trade, smoothstep(0.25, 0.62, f))
	# the middle band: the two cancel, and what is left wanders
	var lull := 1.0 - smoothstep(0.0, 0.17, absf(f - 0.44))
	belt += _variable(cx, cz, lull_speed) * lull

	# the monsoon replaces the belt in the east; weak and unsettled while it turns
	var m := monsoon_sign(phase)
	var mons := vec(monsoon_peak_speed * pow(absf(m), 0.8), SW_MONSOON_TOWARD_DEG if m > 0.0 else NE_MONSOON_TOWARD_DEG)
	var turning := pow(1.0 - absf(m), 2.0)
	mons += _variable(cx + 200000.0, cz, lull_speed) * turning
	return belt.lerp(mons, smoothstep(0.52, 0.72, g))


## The daily breeze near a coast: onto the land in the afternoon, off it in the small hours. hour = hour of the day, 0-24.
func coastal(chart: WorldChart, cx: float, cz: float, hour: float) -> Vector2:
	var sd := chart.shore_distance_m(cx, cz)
	if sd <= 0.0 or sd >= COAST_RANGE_M:
		return Vector2.ZERO
	var e := chart.mpp * 2.0
	var grad := Vector2(
		chart.shore_distance_m(cx + e, cz) - chart.shore_distance_m(cx - e, cz),
		chart.shore_distance_m(cx, cz + e) - chart.shore_distance_m(cx, cz - e))
	if grad.length() < 1.0:
		return Vector2.ZERO
	var onshore := -grad.normalized()                       # toward the land
	var day := cos(TAU * (hour - 14.0) / 24.0)              # +1 at 14:00 (sea breeze), -1 at 02:00 (land breeze)
	var fall := 1.0 - smoothstep(3000.0, COAST_RANGE_M, sd)
	return onshore * coast_speed * day * fall


## Which wind belt a position is in, for the almanac and the debug readout.
func region_name(cx: float, cz: float, phase: float) -> String:
	var f := clampf(cz / height_m, 0.0, 1.0)
	var g := clampf(cx / width_m, 0.0, 1.0)
	if g > 0.62:
		var m := monsoon_sign(phase)
		if absf(m) < 0.35:
			return "monsoon changeover"
		return "southwest monsoon" if m > 0.0 else "northeast monsoon"
	if f < 0.30:
		return "westerlies"
	if f < 0.60:
		return "calm belt"
	return "trade winds"
