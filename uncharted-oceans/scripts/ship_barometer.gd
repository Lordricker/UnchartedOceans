class_name ShipBarometer
extends Node3D
## A brass aneroid barometer standing on the cabin table, beside the compass (ship_map.gd puts it there).
##
## The dial reads inches of mercury, 28 to 31, over a 270 degree sweep with the usual words printed on it (STORMY,
## RAIN, CHANGE, FAIR). The needle follows the pressure at the ship (world_weather.gd, pressure_inhg): about 30 in fair
## weather, drifting a little from day to day, and falling when a storm is on its way, long before the wind rises.
## The dial's top points at the bow. Nothing here is clickable; you read it by standing at the table.

const LOW := 28.0
const HIGH := 31.0
const SWEEP_DEG := 270.0
## The needle's lag behind the pressure, seconds (a real needle is a little sluggish, and a sleep would otherwise jump it).
const LAG_S := 2.5
const INK_COLOR := Color(0.08, 0.07, 0.06)
const RED_COLOR := Color(0.75, 0.08, 0.06)

var radius := 0.075
var _needle: Node3D
var _weather: Node
var _shown := 29.95
var _have := false


## Build the dial. Call after the node is in the ship and placed.
func build(r: float) -> void:
	radius = r
	var s := r / 0.075
	var brass := _mat(Color(0.72, 0.55, 0.22), 0.35, 0.8)
	var cream := _mat(Color(0.93, 0.9, 0.8), 0.9, 0.0)
	var ink := _mat(Color(0.08, 0.07, 0.06), 0.9, 0.0)
	var red := _mat(Color(0.75, 0.08, 0.06), 0.8, 0.0)
	# brass case and the enamel face
	var bowl := CylinderMesh.new()
	bowl.top_radius = r * 1.12
	bowl.bottom_radius = r * 1.08
	bowl.height = 0.02
	bowl.radial_segments = 28
	bowl.rings = 1
	_part(self, bowl, brass, Vector3(0.0, -0.01, 0.0))
	var face := CylinderMesh.new()
	face.top_radius = r
	face.bottom_radius = r
	face.height = 0.003
	face.radial_segments = 32
	face.rings = 1
	_part(self, face, cream, Vector3(0.0, 0.0015, 0.0))
	# ticks every tenth of an inch: longer at each half, longest at each whole inch
	for i in 31:
		var v := LOW + 0.1 * i
		var a := deg_to_rad(_angle_deg(v))
		var tl := 0.011 if i % 10 == 0 else (0.008 if i % 5 == 0 else 0.005)
		var w := 0.002 if i % 10 == 0 else 0.0012
		var tick := BoxMesh.new()
		tick.size = Vector3(w, 0.001, tl * s)
		var mi := _part(self, tick, ink, _dir(v) * (r * 0.93 - tl * s * 0.5) + Vector3(0.0, 0.0035, 0.0))
		mi.rotation.y = -a
	# the inches, read upright from the bow side of the table
	for n in [28, 29, 30, 31]:
		_label(str(n), 48, 0.00034 * s, INK_COLOR, _dir(float(n)) * r * 0.72 + Vector3(0.0, 0.0042, 0.0))
	# the weather words, where the glass stands for them
	_label("STORMY", 48, 0.00022 * s, RED_COLOR, _dir(28.4) * r * 0.46 + Vector3(0.0, 0.0042, 0.0))
	_label("RAIN", 48, 0.00022 * s, INK_COLOR, _dir(29.0) * r * 0.46 + Vector3(0.0, 0.0042, 0.0))
	_label("CHANGE", 48, 0.00022 * s, INK_COLOR, _dir(29.6) * r * 0.46 + Vector3(0.0, 0.0042, 0.0))
	_label("FAIR", 48, 0.00022 * s, INK_COLOR, _dir(30.3) * r * 0.46 + Vector3(0.0, 0.0042, 0.0))
	# the needle, turning about the middle of the face
	_needle = Node3D.new()
	_needle.name = "Needle"
	add_child(_needle)
	var nm := BoxMesh.new()
	nm.size = Vector3(0.0026, 0.0015, r * 0.86)
	_part(_needle, nm, red, Vector3(0.0, 0.0055, -r * 0.43))
	var hub := CylinderMesh.new()
	hub.top_radius = 0.0045 * s
	hub.bottom_radius = 0.0045 * s
	hub.height = 0.003
	hub.radial_segments = 12
	hub.rings = 1
	_part(self, hub, brass, Vector3(0.0, 0.0065, 0.0))
	_needle.rotation.y = -deg_to_rad(_angle_deg(29.95))


func _process(delta: float) -> void:
	if _needle == null:
		return
	if _weather == null or not is_instance_valid(_weather):
		_weather = get_tree().get_first_node_in_group("weather")
	var target := 29.95
	if _weather != null and _weather.has_method("pressure_inhg"):
		target = float(_weather.pressure_inhg())
	if not _have:
		_shown = target
		_have = true
	_shown = lerpf(_shown, target, 1.0 - exp(-delta / LAG_S))
	_needle.rotation.y = -deg_to_rad(_angle_deg(clampf(_shown, LOW - 0.15, HIGH + 0.1)))


## Dial angle for a reading: 0 = straight up the dial (toward the bow), clockwise, -135 at LOW and +135 at HIGH.
func _angle_deg(inhg: float) -> float:
	return -SWEEP_DEG * 0.5 + (inhg - LOW) / (HIGH - LOW) * SWEEP_DEG


## Direction on the face (ship frame: the bow is -Z) for a reading.
func _dir(inhg: float) -> Vector3:
	var a := deg_to_rad(_angle_deg(inhg))
	return Vector3(sin(a), 0.0, -cos(a))


func _label(text: String, font_size: int, pixel: float, col: Color, pos: Vector3) -> void:
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = font_size
	lab.pixel_size = pixel
	lab.modulate = col
	lab.outline_size = 0
	lab.basis = Basis(Vector3.RIGHT, deg_to_rad(-90.0))       # lies flat, its top toward the bow
	lab.position = pos
	add_child(lab)


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
