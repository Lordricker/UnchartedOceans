class_name WorldTerrain
extends MeshInstance3D
## Macro terrain for the world chart: land from the heightmap, sea floor from the shelf.
## A camera-following radial grid (like the Ocean) displaced in world_terrain.gdshader; no collision.
## The streamer calls set_world() after every rebase of the origin.

@export var radius := 110000.0     ## mountains show over the horizon, so this reaches far
@export var segments := 288
@export var first_ring := 40.0
@export var ring_growth := 1.04
@export var relief_m := 1100.0
@export var curvature_radius_m := 6370000.0

var _mat: ShaderMaterial

func _ready() -> void:
	var sh := load("res://shaders/world_terrain.gdshader") as Shader
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("relief_m", relief_m)
	_mat.set_shader_parameter("curve_k", 0.5 / curvature_radius_m if curvature_radius_m > 0.0 else 0.0)
	mesh = _build_mesh()
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func set_world(c: WorldChart, ox: float, oz: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("chart_origin", Vector2(ox, oz))
	_mat.set_shader_parameter("chart_size", Vector2(c.width_m, c.height_m))
	_mat.set_shader_parameter("chart_px", Vector2(c.px_w, c.px_h))
	_mat.set_shader_parameter("chart_mpp", c.mpp)
	_mat.set_shader_parameter("chart_land", c.texture_of("land"))
	_mat.set_shader_parameter("chart_shore", c.texture_of("shore"))
	var h16 := c.texture_of("height16")
	if h16:
		_mat.set_shader_parameter("chart_height16", h16)

## Cut a hole in the terrain (Godot world xz and radius) where a full port scene brings its own ground; radius <= 0 clears it.
func set_hole(x: float, z: float, r: float) -> void:
	if _mat:
		_mat.set_shader_parameter("hole", Vector3(x, z, r))

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z)

func _build_mesh() -> ArrayMesh:
	var radii := PackedFloat32Array([0.0])
	var step := first_ring
	while radii[radii.size() - 1] < radius:
		radii.append(radii[radii.size() - 1] + step)
		step *= ring_growth
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3.ZERO)
	for r in range(1, radii.size()):
		for s in segments:
			var a := TAU * float(s) / segments
			verts.append(Vector3(cos(a) * radii[r], 0.0, sin(a) * radii[r]))
	for s in segments:
		var s2 := (s + 1) % segments
		idx.append_array([0, 1 + s, 1 + s2])
	for r in range(1, radii.size() - 1):
		var b0 := 1 + (r - 1) * segments
		var b1 := 1 + r * segments
		for s in segments:
			var s2 := (s + 1) % segments
			idx.append_array([b0 + s, b1 + s, b0 + s2, b0 + s2, b1 + s, b1 + s2])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.custom_aabb = AABB(Vector3(-radius, -3000.0, -radius), Vector3(radius * 2.0, 6000.0, radius * 2.0))
	return am
