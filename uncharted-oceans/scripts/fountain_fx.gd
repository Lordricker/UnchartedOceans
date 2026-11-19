class_name FountainFX
extends Node3D
## Working water for the European capital's piazza fountain (the "Cap_Fountain" mesh in PortCapital.glb).
##
## The mesh is only stone, a flat glass disc for each basin and a brass finial. This node sits on that mesh (its local
## coordinates are the mesh's own) and adds:
##   - a jet of water thrown up from the finial that falls back into the upper bowl,
##   - a thin curtain of water spilling over the upper bowl's rim into the lower basin,
##   - animated water in both basins (ripples running out from where the water lands, foam on that ring),
##   - drops splashing up where the jet and the curtain land, and a little mist over the lower basin.
## Everything is procedural (two small shaders and a few GPUParticles3D); no textures or sounds are needed.
##
## Use FountainFX.attach(port_scene_root): it finds the fountain and adds one of these. WorldStreamer calls it for every
## port it spawns, so no re-import of the .glb is needed.
##
## Cost: about 300 particles at Medium quality (half at Low, with no mist), no shadows, and everything hides beyond
## `visible_range_m` of the camera.

const WATER_SHADER := preload("res://shaders/fountain_water.gdshader")
const SHEET_SHADER := preload("res://shaders/fountain_sheet.gdshader")

## The mesh's own measurements, metres (read off PortCapital.glb: Cap_Fountain).
@export var lower_water_y := 6.42
@export var lower_radius := 2.38
@export var upper_water_y := 8.23
@export var upper_radius := 1.08
@export var rim_y := 8.2          # lip of the upper bowl the curtain pours over
@export var rim_radius := 1.3
@export var spout_y := 9.35       # top of the brass finial, where the jet starts
## Where the curtain lands in the lower basin.
@export var landing_radius := 1.58
## How high the jet climbs above the finial, metres.
@export var jet_height_m := 1.5
@export var visible_range_m := 80.0

var _quality := 1

var _streak_mesh: ArrayMesh
var _dot_mesh: QuadMesh
var _dot_mat: StandardMaterial3D
var _streak_mat: StandardMaterial3D


## Add a FountainFX to the piazza fountain inside a loaded port scene, if it has one and does not already.
static func attach(root: Node) -> void:
	if root == null:
		return
	var f := root.find_child("Cap_Fountain", true, false)
	if f == null or f.get_node_or_null("FountainFX") != null:
		return
	var fx := FountainFX.new()
	fx.name = "FountainFX"
	f.add_child(fx)


func _ready() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("current_quality"):
		_quality = int(gs.call("current_quality"))
	_make_materials()
	_add_water_disc(lower_water_y + 0.035, lower_radius, landing_radius, 0.3, 1.0, 0.25, 0.55)
	_add_water_disc(upper_water_y + 0.03, upper_radius, 0.0, 0.3, 0.0, 1.3, 0.5)
	_add_curtain()
	_add_jet()
	_add_upper_splash()
	_add_lower_splash()
	if _quality >= 1:
		_add_mist()


func _scale_amount(n: int) -> int:
	var f := 0.5 if _quality <= 0 else (1.0 if _quality == 1 else 1.4)
	return maxi(int(round(float(n) * f)), 4)


# ------------------------------------------------------------------ materials and meshes

func _make_materials() -> void:
	# a soft round dot for droplets and mist
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	_dot_mat = StandardMaterial3D.new()
	_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dot_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_dot_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_dot_mat.vertex_color_use_as_albedo = true
	_dot_mat.albedo_texture = gt
	_dot_mat.albedo_color = Color(0.92, 0.96, 1.0, 0.9)
	_dot_mat.render_priority = 64
	_dot_mesh = QuadMesh.new()
	_dot_mesh.size = Vector2(1, 1)
	_dot_mesh.material = _dot_mat
	# a thin streak along +Y (the way the drop is travelling), crossed so it shows from any side
	_streak_mat = StandardMaterial3D.new()
	_streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_streak_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_streak_mat.vertex_color_use_as_albedo = true
	_streak_mat.albedo_color = Color(0.9, 0.96, 1.0, 0.75)
	_streak_mat.render_priority = 64
	var w := 0.018
	var h := 0.2
	var verts := PackedVector3Array([
		Vector3(-w, 0, 0), Vector3(w, 0, 0), Vector3(w, h, 0), Vector3(-w, h, 0),
		Vector3(0, 0, -w), Vector3(0, 0, w), Vector3(0, h, w), Vector3(0, h, -w)])
	var tail := Color(1, 1, 1, 0.15)
	var head := Color(1, 1, 1, 1.0)
	var cols := PackedColorArray([tail, tail, head, head, tail, tail, head, head])
	var norms := PackedVector3Array()
	for i in 4:
		norms.append(Vector3(0, 0, 1))
	for i in 4:
		norms.append(Vector3(1, 0, 0))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	_streak_mesh = ArrayMesh.new()
	_streak_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_streak_mesh.surface_set_material(0, _streak_mat)
	_streak_mesh.custom_aabb = AABB(Vector3(-1, 0, -1), Vector3(2, h, 2))


# ------------------------------------------------------------------ water and curtain

func _add_water_disc(y: float, radius: float, ring_r: float, ring_w: float, ring_s: float, centre_s: float, centre_r: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0 + 0.1, radius * 2.0 + 0.1)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("ring_radius", ring_r)
	m.set_shader_parameter("ring_width", ring_w)
	m.set_shader_parameter("ring_strength", ring_s)
	m.set_shader_parameter("center_strength", centre_s)
	m.set_shader_parameter("center_radius", centre_r)
	mi.material_override = m
	mi.position = Vector3(0, y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = visible_range_m
	add_child(mi)


## A short open tube from the upper rim down to where it lands in the lower basin; a shader draws the falling streaks.
func _add_curtain() -> void:
	var seg := 48
	var rows := 6
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var bottom_y := lower_water_y + 0.04
	for r in rows + 1:
		var t := float(r) / float(rows)
		# the water arcs out a little as it falls
		var rad := lerpf(rim_radius, landing_radius, pow(t, 0.7))
		var y := lerpf(rim_y, bottom_y, t)
		for s in seg + 1:
			var a := TAU * float(s) / float(seg)
			verts.append(Vector3(cos(a) * rad, y, sin(a) * rad))
			uvs.append(Vector2(float(s) / float(seg), t))
	for r in rows:
		for s in seg:
			var i0 := r * (seg + 1) + s
			var i1 := i0 + 1
			var i2 := i0 + seg + 1
			var i3 := i2 + 1
			idx.append_array([i0, i2, i1, i1, i2, i3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := ShaderMaterial.new()
	m.shader = SHEET_SHADER
	m.render_priority = 63
	mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.name = "Curtain"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = visible_range_m
	add_child(mi)


# ------------------------------------------------------------------ particles

func _particles(nm: String, amount: int, life: float, pos: Vector3, mesh: Mesh, mat: ParticleProcessMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = nm
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.preprocess = life
	p.explosiveness = 0.0
	p.randomness = 0.4
	p.fixed_fps = 30
	p.interpolate = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 8, 8))
	p.visibility_range_end = visible_range_m
	p.process_material = mat
	p.draw_pass_1 = mesh
	p.position = pos
	add_child(p)
	return p


## The jet: streaks thrown up from the finial that arc and fall into the upper bowl.
func _add_jet() -> void:
	var g := 9.8
	var v := sqrt(2.0 * g * jet_height_m)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.03
	m.direction = Vector3.UP
	m.spread = 5.0
	m.initial_velocity_min = v * 0.93
	m.initial_velocity_max = v * 1.07
	m.gravity = Vector3(0, -g, 0)
	m.particle_flag_align_y = true
	m.scale_min = 0.8
	m.scale_max = 1.3
	var life := (v / g) * 2.0 + sqrt(2.0 * (spout_y - upper_water_y) / g) * 0.6
	_particles("Jet", _scale_amount(150), life, Vector3(0, spout_y, 0), _streak_mesh, m)


## Drops thrown up where the jet comes down in the upper bowl.
func _add_upper_splash() -> void:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.18
	m.direction = Vector3.UP
	m.spread = 55.0
	m.initial_velocity_min = 0.7
	m.initial_velocity_max = 1.9
	m.gravity = Vector3(0, -9.8, 0)
	m.scale_min = 0.025
	m.scale_max = 0.06
	m.scale_curve = _fade_curve()
	_particles("UpperSplash", _scale_amount(60), 0.55, Vector3(0, upper_water_y + 0.03, 0), _dot_mesh, m)


## Drops thrown up all round the ring where the curtain lands in the lower basin.
func _add_lower_splash() -> void:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_radius = landing_radius
	m.emission_ring_inner_radius = landing_radius - 0.08
	m.emission_ring_height = 0.02
	m.emission_ring_cone_angle = 90.0
	m.direction = Vector3.UP
	m.spread = 40.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 1.7
	m.gravity = Vector3(0, -9.8, 0)
	m.scale_min = 0.025
	m.scale_max = 0.055
	m.scale_curve = _fade_curve()
	_particles("LowerSplash", _scale_amount(110), 0.5, Vector3(0, lower_water_y + 0.04, 0), _dot_mesh, m)


## A faint drifting haze over the lower basin; skipped at Low quality.
func _add_mist() -> void:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_radius = landing_radius
	m.emission_ring_inner_radius = landing_radius - 0.25
	m.emission_ring_height = 0.05
	m.emission_ring_cone_angle = 90.0
	m.direction = Vector3.UP
	m.spread = 25.0
	m.initial_velocity_min = 0.15
	m.initial_velocity_max = 0.4
	m.gravity = Vector3.ZERO
	m.scale_min = 0.45
	m.scale_max = 0.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.add_point(0.25, Color(1, 1, 1, 0.16))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	_particles("Mist", _scale_amount(14), 2.4, Vector3(0, lower_water_y + 0.12, 0), _dot_mesh, m)


func _fade_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0, 1.0))
	c.add_point(Vector2(1, 0.2))
	var t := CurveTexture.new()
	t.curve = c
	return t
