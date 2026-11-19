# The terrain's detail patch: a fine world-locked grid round the camera near coasts (the coarse rings start at 40 m).
import sys
root = sys.argv[1]
def edit(p, pairs):
    p = root + '/' + p
    s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (p, o[:80])
        s = s.replace(o, n)
    open(p, 'w').write(s)

edit('scripts/world_terrain.gd', [
("""var hole_world := Vector3(0.0, 0.0, -1.0)
""", """var hole_world := Vector3(0.0, 0.0, -1.0)

## The detail patch: a fine grid locked to the world (so the waterline does not crawl as the camera moves) that draws
## the ground round the camera instead of the coarse rings, out to patch_size_m / 2. Only shown near a coast.
@export var patch_size_m := 640.0
@export var patch_cell_high_m := 2.5      ## High water setting
@export var patch_cell_std_m := 5.0       ## Standard (the old laptop)
@export var patch_show_shore_m := 1500.0
var _patch: MeshInstance3D
var _patch_cell := 0.0
var _chart: WorldChart
var _ox := 0.0
var _oz := 0.0
var _vis_t := 0.0
"""),
("""	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
""", """	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_patch = MeshInstance3D.new()
	_patch.name = "DetailPatch"
	_patch.material_override = _mat
	_patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_patch.top_level = true
	_patch.visible = false
	add_child(_patch)
	_patch.set_instance_shader_parameter("patch_layer", 1.0)
"""),
("""func set_world(c: WorldChart, ox: float, oz: float) -> void:
""", """func set_world(c: WorldChart, ox: float, oz: float) -> void:
	_chart = c
	_ox = ox
	_oz = oz
	_vis_t = 0.0
"""),
("""		global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z)
""", """		global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z)
		_update_patch(cam.global_position, _delta)
"""),
("""func _build_mesh() -> ArrayMesh:""", """## Shows the detail patch round the camera near a coast, its grid snapped to the world so it never slides, and tells the
## coarse rings to leave that square to it.
func _update_patch(cam: Vector3, delta: float) -> void:
	if _patch == null or _chart == null:
		return
	_vis_t -= delta
	if _vis_t <= 0.0:
		_vis_t = 0.5
		var cx := _ox + cam.x
		var cz := _oz + cam.z
		var near := _chart.is_land(cx, cz) or _chart.shore_distance_m(cx, cz) < patch_show_shore_m
		_patch.visible = near
		var cell := patch_cell_high_m if _high() else patch_cell_std_m
		if near and cell != _patch_cell:
			_patch_cell = cell
			_patch.mesh = _build_patch(cell)
	if not _patch.visible:
		_mat.set_shader_parameter("patch_rect", Vector4.ZERO)
		return
	# snap in chart space (64-bit), so the vertices sit on the same world points whatever the origin
	var sx := roundf((_ox + cam.x) / _patch_cell) * _patch_cell - _ox
	var sz := roundf((_oz + cam.z) / _patch_cell) * _patch_cell - _oz
	_patch.global_position = Vector3(sx, 0.0, sz)
	var h := patch_size_m * 0.5
	_mat.set_shader_parameter("patch_rect", Vector4(sx - h, sz - h, sx + h, sz + h))


func _high() -> bool:
	if ocean == null:
		return true
	return int(ocean.get("water_quality")) >= 1


## A square grid patch_size_m across in cells of `cell` m, with a skirt hanging round its edge (COLOR.r = 1, the shader
## drops it) to hide any crack against the coarse rings.
func _build_patch(cell: float) -> ArrayMesh:
	var n := int(round(patch_size_m / cell))
	var h := patch_size_m * 0.5
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize((n + 1) * (n + 1))
	cols.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			verts[j * (n + 1) + i] = Vector3(-h + i * cell, 0.0, -h + j * cell)
			cols[j * (n + 1) + i] = Color(0, 0, 0)
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			idx.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	var ring := PackedInt32Array()
	for i in n:
		ring.append(i)
	for j in n:
		ring.append(j * (n + 1) + n)
	for i in range(n, 0, -1):
		ring.append(n * (n + 1) + i)
	for j in range(n, 0, -1):
		ring.append(j * (n + 1))
	var base := verts.size()
	for k in ring.size():
		verts.append(verts[ring[k]])
		cols.append(Color(1, 0, 0))
	var m := ring.size()
	for k in m:
		var k2 := (k + 1) % m
		var a := ring[k]
		var b := ring[k2]
		var sa := base + k
		var sb := base + k2
		idx.append_array([a, sa, b, b, sa, sb, a, b, sa, b, sb, sa])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.custom_aabb = AABB(Vector3(-h, -3000.0, -h), Vector3(patch_size_m, 6000.0, patch_size_m))
	return am


func _build_mesh() -> ArrayMesh:"""),
])
edit('shaders/world_terrain.gdshader', [
("""uniform float cliff_m = 26.0;""", """// The detail patch (world_terrain.gd): a fine grid round the camera near coasts; the coarse rings leave it alone
instance uniform float patch_layer = 0.0; // 1 on the patch
uniform vec4 patch_rect = vec4(0.0);      // (min x, min z, max x, max z), Godot world; zero size = no patch
uniform float cliff_m = 26.0;"""),
("""	VERTEX.y = y - d * d * curve_k;
}""", """	VERTEX.y = y - d * d * curve_k;
	if (patch_layer > 0.5 && COLOR.r > 0.5) {
		VERTEX.y -= 30.0;      // the patch's skirt
	}
}"""),
("""	if (hole.z > 0.0 && distance(world_xz, hole.xy) < hole.z) {
		discard;
	}""", """	if (hole.z > 0.0 && distance(world_xz, hole.xy) < hole.z) {
		discard;
	}
	// the coarse rings give way to the detail patch (overlapping it by a metre so no seam opens)
	if (patch_layer < 0.5 && patch_rect.z > patch_rect.x && world_xz.x > patch_rect.x + 1.0 && world_xz.x < patch_rect.z - 1.0
			&& world_xz.y > patch_rect.y + 1.0 && world_xz.y < patch_rect.w - 1.0) {
		discard;
	}"""),
])
