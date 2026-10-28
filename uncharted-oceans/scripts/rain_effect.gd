class_name RainEffect
extends GPUParticles3D
## Rain around the camera. Made by WorldWeather, which sets `intensity` (0-1) and `wind` every frame.
##
## One GPUParticles3D box that follows the camera: thin streaks falling at about 11 m/s, slanted by the wind, in world
## space so the ship sails through them. The streaks fade at the tail and are stretched along their fall. The number
## shown follows the intensity (amount_ratio), so light rain is a few drops and a squall is a wall. With nothing
## to draw it costs nothing (emitting is switched off).
##
## Cover: every 0.2 s a ray goes straight up from the camera; if something solid is overhead (a deck, the cabin roof)
## the rain fades out, and back in when you step out. The ray ignores the player.
##
## Cost: max_particles quads of 4 triangles each, no shadows, unshaded. About 2000 on the 10-year-old laptop is fine.

@export var max_particles := 2200
## Half the width of the box of rain round the camera, metres.
@export var box_half_m := 16.0
## How high above the camera the drops start, metres.
@export var height_m := 15.0
@export var fall_speed := 11.0
## Streak size, metres.
@export var streak_length := 0.75
@export var streak_width := 0.014
## Slant of the fall per m/s of wind.
@export var wind_slant := 0.04

## 0-1: how hard it is raining here. Set by the weather.
var intensity := 0.0
## World wind, m/s (x, z). Set by the weather.
var wind := Vector2.ZERO
## 0 = night, 1 = full daylight: dims the streaks. Set by the weather.
var daylight := 1.0

var _shown := 0.0
var _shelter := 1.0
var _ray_t := 0.0
var _covered := false
var _slant_t := 0.0
var _mat: ParticleProcessMaterial
var _draw_mat: StandardMaterial3D
var _player: Node3D


func _ready() -> void:
	amount = max_particles
	lifetime = (height_m + 3.0) / fall_speed
	local_coords = false
	preprocess = lifetime
	explosiveness = 0.0
	randomness = 0.3
	fixed_fps = 30
	interpolate = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	visibility_aabb = AABB(Vector3(-box_half_m * 1.6, -height_m * 1.4, -box_half_m * 1.6), Vector3(box_half_m * 3.2, height_m * 1.8, box_half_m * 3.2))
	_mat = ParticleProcessMaterial.new()
	_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_mat.emission_box_extents = Vector3(box_half_m, 0.2, box_half_m)
	_mat.direction = Vector3.DOWN
	_mat.spread = 1.5
	_mat.initial_velocity_min = fall_speed * 0.92
	_mat.initial_velocity_max = fall_speed * 1.08
	_mat.gravity = Vector3.ZERO
	_mat.particle_flag_align_y = true
	process_material = _mat
	draw_pass_1 = _streak_mesh()
	amount_ratio = 0.0
	emitting = false


## A crossed pair of thin quads, so a streak shows from any side. +Y is the head (the way it falls); the tail end fades out.
func _streak_mesh() -> ArrayMesh:
	var w := streak_width
	var h := streak_length
	var verts := PackedVector3Array([
		Vector3(-w, 0, 0), Vector3(w, 0, 0), Vector3(w, h, 0), Vector3(-w, h, 0),
		Vector3(0, 0, -w), Vector3(0, 0, w), Vector3(0, h, w), Vector3(0, h, -w)])
	var tail := Color(1, 1, 1, 0.0)
	var head := Color(1, 1, 1, 1.0)
	var cols := PackedColorArray([tail, tail, head, head, tail, tail, head, head])
	var norms := PackedVector3Array()
	for i in 4:
		norms.append(Vector3(0, 0, 1))
	for i in 4:
		norms.append(Vector3(1, 0, 0))
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_draw_mat = StandardMaterial3D.new()
	_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_draw_mat.vertex_color_use_as_albedo = true
	_draw_mat.albedo_color = Color(0.78, 0.84, 0.92, 0.5)
	m.surface_set_material(0, _draw_mat)
	m.custom_aabb = AABB(Vector3(-1, 0, -1), Vector3(2, h, 2))
	return m


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# the box follows the camera, its top plane above it
	global_position = cam.global_position + Vector3(0.0, height_m, 0.0)
	global_rotation = Vector3.ZERO
	# fade in and out smoothly: rain starts and stops over a couple of seconds, cover over a fraction of one
	_shown = lerpf(_shown, intensity, 1.0 - exp(-delta / 1.5))
	_shelter = move_toward(_shelter, 0.0 if _covered else 1.0, delta * 3.0)
	var r := clampf(_shown * _shelter, 0.0, 1.0)
	amount_ratio = r
	emitting = r > 0.01
	if not emitting:
		return
	_slant_t -= delta
	if _slant_t <= 0.0:
		_slant_t = 0.25
		_mat.direction = Vector3(wind.x * wind_slant, -1.0, wind.y * wind_slant).normalized()
		var lit := lerpf(0.35, 1.0, clampf(daylight, 0.0, 1.0))
		_draw_mat.albedo_color = Color(0.78 * lit, 0.84 * lit, 0.92 * lit, 0.25 + 0.3 * _shown)


func _physics_process(delta: float) -> void:
	_ray_t -= delta
	if _ray_t > 0.0:
		return
	_ray_t = 0.2
	if _shown < 0.01:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var exclude: Array[RID] = []
	if _player is CollisionObject3D:
		exclude.append((_player as CollisionObject3D).get_rid())
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, 12.0, 0.0))
	q.exclude = exclude
	q.collide_with_areas = false
	_covered = not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
