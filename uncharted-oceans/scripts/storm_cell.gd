class_name StormCell
extends RefCounted
## One weather system on the world map: a storm cell that moves, rains and throws lightning.
## SkySystem draws it on the horizon from where the observer is standing, and the same object is what the
## wind, waves, rain and sound will read later, so the storm you see is the storm that hits you.

## Where it is, in world metres (x, z).
var pos := Vector2.ZERO
## How it drifts, metres per second.
var velocity := Vector2.ZERO
## Half the length of the storm front, metres. A squall line is 50-150 km long, so this is 25-75 km.
var radius_m := 25000.0
## Half the depth of the stormy band in the direction it travels, metres: closer than this and you are in it.
var depth_m := 11000.0
## Height of the cloud top, metres.
var height_m := 12000.0
## 0 = nothing, 1 = a full mature storm.
var intensity := 1.0
## How much rain falls from it, 0-1.
var rain := 0.85
## Distinguishes this cell's cloud shapes from other cells'.
var shape_seed := 0.0

# lightning
var flash := 0.0
var _next_flash_s := 3.0
var _second_pulse_s := -1.0

## Sets the size of the front and works out matching height and depth.
func set_size(front_half_length_m: float) -> void:
	radius_m = front_half_length_m
	height_m = clampf(6000.0 + front_half_length_m * 0.25, 6000.0, 13000.0)
	depth_m = clampf(front_half_length_m * 0.45, 5000.0, 15000.0)

func step(dt: float) -> void:
	pos += velocity * dt

## Advances the lightning. Returns true on the frame a new flash starts.
func step_lightning(dt: float, rng: RandomNumberGenerator) -> bool:
	var fired := false
	flash = maxf(0.0, flash - dt * 7.0)
	if _second_pulse_s >= 0.0:
		_second_pulse_s -= dt
		if _second_pulse_s < 0.0:
			flash = maxf(flash, 0.8)
	if intensity < 0.35:
		return false
	_next_flash_s -= dt
	if _next_flash_s <= 0.0:
		flash = 1.0
		_second_pulse_s = rng.randf_range(0.09, 0.2)
		_next_flash_s = rng.randf_range(2.5, 9.0) / (0.4 + intensity)
		fired = true
	return fired
