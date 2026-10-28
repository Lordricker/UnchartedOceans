class_name ShipClasses
extends RefCounted
## Size classes for docking. Every ship is Small, Medium or Large (ship_motion.gd: ship_class).
## The class decides the size of the light rectangle at a berth, and how gently the ship has to arrive.
## All numbers are first guesses: change them here and every berth follows.

enum Size { SMALL, MEDIUM, LARGE }

const NAMES := ["small", "medium", "large"]

## length / beam in metres (hull, bow to stern and side to side); max_speed in m/s through the water
## (the brig's hull speed is about 5.3 m/s); max_heading in degrees off the berth's heading.
const DATA := [
	{"length": 13.0, "beam": 4.4, "max_speed": 1.5, "max_heading": 28.0},   # small: sloop / cutter
	{"length": 19.0, "beam": 7.0, "max_speed": 1.3, "max_heading": 25.0},   # medium: the merchant brig
	{"length": 32.0, "beam": 9.5, "max_speed": 1.2, "max_heading": 20.0},   # large: frigate / big merchantman
]

## The light rectangle is the ship's size times these.
const ZONE_LENGTH_SCALE := 1.6
const ZONE_WIDTH_SCALE := 2.0

static func data(size: int) -> Dictionary:
	return DATA[clampi(size, 0, DATA.size() - 1)]

## Rectangle (width across the berth, length along it) in metres.
static func zone_size(size: int) -> Vector2:
	var d := data(size)
	return Vector2(float(d.beam) * ZONE_WIDTH_SCALE, float(d.length) * ZONE_LENGTH_SCALE)

## Heading in degrees (0 = north, 90 = west, the way heading_deg grows) as a word.
static func compass(heading_deg: float) -> String:
	var names := ["north", "north-west", "west", "south-west", "south", "south-east", "east", "north-east"]
	return names[int(round(fposmod(heading_deg, 360.0) / 45.0)) % 8]
