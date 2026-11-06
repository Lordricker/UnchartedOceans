extends Node3D
## Spray off the sea. Made by ship_motion.gd (wave_spray_enabled) as a child of the Ocean.
##
## 1. Crest spray (storm sea only): a few emitters ride the crests that are about to break, the same crests the water
##    shader paints as whitecaps (Ocean.get_fold_z), and throw soft white puffs up and downwind. Each one follows its crest
##    along the wind for a second or two and stops when the crest stops breaking, then a new one is picked near the
##    camera. Nothing happens below sea state 3.5 or so, and it fades in from there.
## 2. Hull slams (any rough water): where the sea comes up fast against the hull (the water rising at the side, bow or
##    stern points faster than the hull itself is rising) a burst of droplets goes up and outward from the hull.
##
## Cost: CREST_N * 20 + BURST_N * 24 puffs at most, in two small particle systems that sit idle in calm water. Unshaded
## soft puffs, no shadows, so about the cost of the bow spray.

const CREST_N := 8
const BURST_N := 8
## How fast a spray emitter rides its crest along the wind (about the speed of the chop's longer waves), m/s.
const CREST_SPEED := 10.0

class Crest:
	var node: GPUParticles3D
	var pm: ParticleProcessMaterial
	var on := false
	var x := 0.0
	var z := 0.0
	var f := 0.0           # the fold score at the crest now
	var age := 0.0
	var life := 2.0
	var fold_t := 0.0
	var low_t := 0.0

var ocean: Ocean
var motion: Node3D

var _crests: Array[Crest] = []
var _bursts: Array[GPUParticles3D] = []
var _burst_next := 0
var _mat_blob: StandardMaterial3D
var _mat_drop: StandardMaterial3D
var _lit := 1.0
var _lit_t := 0.0
var _spawn_t := 0.0
var _slam_gap := 0.0
var _pt_prev := PackedFloat32Array()
var _pt_cool := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_make_materials()
	for i in CREST_N:
		var c := Crest.new()
		c.node = _make_system(false)
		c.pm = c.node.process_material as ParticleProcessMaterial
		_crests.append(c)
	for i in BURST_N:
		_bursts.append(_make_system(true))


## Two kinds of water in every spray: drops (thin streaks stretched along their flight, solid white) and a few hard-edged
## blobs of whitewater among them. Soft round gradient puffs looked like white dandelion fluff.
func _make_materials() -> void:
	# a round blob with only a narrow soft rim, so it reads as a lump of white water rather than a fuzzy ball
	var blob := Gradient.new()
	blob.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	blob.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = blob
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_mat_blob = StandardMaterial3D.new()
	_mat_blob.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_blob.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_blob.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mat_blob.billboard_keep_scale = true
	_mat_blob.vertex_color_use_as_albedo = true
	_mat_blob.albedo_texture = tex
	_mat_blob.albedo_color = Color(1, 1, 1, 0.9)
	_mat_blob.render_priority = 63     # the sea is see-through too: draw the spray after it so far waves do not paint over it
	_mat_drop = StandardMaterial3D.new()
	_mat_drop.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_drop.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_drop.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_drop.vertex_color_use_as_albedo = true
	_mat_drop.albedo_color = Color(1, 1, 1, 0.95)
	_mat_drop.render_priority = 63


## A crossed pair of thin quads, +Y along the flight (the head), the tail end fading: a drop of water in motion.
func _drop_mesh() -> ArrayMesh:
	var w := 0.03
	var h := 0.5
	var verts := PackedVector3Array([
		Vector3(-w, 0, 0), Vector3(w, 0, 0), Vector3(w, h, 0), Vector3(-w, h, 0),
		Vector3(0, 0, -w), Vector3(0, 0, w), Vector3(0, h, w), Vector3(0, h, -w)])
	var tail := Color(1, 1, 1, 0.2)
	var head := Color(1, 1, 1, 1.0)
	var cols := PackedColorArray([tail, tail, head, head, tail, tail, head, head])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, _mat_drop)
	m.custom_aabb = AABB(Vector3(-1, 0, -1), Vector3(2, h, 2))
	return m


## One spray: a crest emitter (steady stream) or a burst (one-shot, all at once). The drops are the node itself, the
## blobs a child sharing its process material, so moving, aiming and starting the node does both.
func _make_system(burst: bool) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.5, 0.1, 0.5) if burst else Vector3(0.7, 0.1, 0.7)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 35.0
	pm.initial_velocity_min = 3.0 if burst else 1.5
	pm.initial_velocity_max = 6.0 if burst else 4.5
	pm.gravity = Vector3(0.0, -9.8 if burst else -7.0, 0.0)
	pm.damping_min = 0.1
	pm.damping_max = 0.4
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.04, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	var drops := _make_particles(burst, 40 if burst else 28, 0.9 if burst else 1.1, pm)
	drops.draw_pass_1 = _drop_mesh()
	var blobs := _make_particles(burst, 9 if burst else 8, 0.8 if burst else 1.0, pm)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	quad.material = _mat_blob
	blobs.draw_pass_1 = quad
	drops.add_child(blobs)
	drops.set_meta("blobs", blobs)
	add_child(drops)
	return drops


func _make_particles(burst: bool, count: int, life: float, pm: ParticleProcessMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = life
	p.local_coords = false
	p.one_shot = burst
	p.explosiveness = 0.9 if burst else 0.0
	p.randomness = 0.5
	p.fixed_fps = 30
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-18.0, -4.0, -18.0), Vector3(36.0, 24.0, 36.0))
	p.amount_ratio = 0.0
	p.emitting = false
	p.process_material = pm
	return p


## Switch a spray's emitting and amount on (drops and blobs together).
func _emit(node: GPUParticles3D, ratio: float, on: bool) -> void:
	node.amount_ratio = ratio
	node.emitting = on
	var blobs := node.get_meta("blobs") as GPUParticles3D
	blobs.amount_ratio = ratio
	blobs.emitting = on


func _process(delta: float) -> void:
	if ocean == null or delta <= 0.0:
		return
	_lit_t -= delta
	if _lit_t <= 0.0:
		_lit_t = 0.5
		_update_light()
	_update_crests(delta, smoothstep(2.5, 3.0, ocean.sea_level))
	_update_slams(delta, smoothstep(0.8, 3.0, ocean.sea_level))


## Unshaded puffs would glow at night, so dim them with the sun (same as the bow spray).
func _update_light() -> void:
	var lit := 1.0
	var sun := ocean.get_node_or_null(ocean.sun_path) as DirectionalLight3D
	if sun:
		lit = (0.2 + 0.8 * clampf(sun.light_energy, 0.0, 1.0)) if sun.visible else 0.2
	_lit = lit
	_mat_blob.albedo_color = Color(lit * 0.97, lit * 0.99, lit, 0.9)
	_mat_drop.albedo_color = Color(lit * 0.97, lit * 0.99, lit, 0.95)


func _update_crests(delta: float, k: float) -> void:
	var wind := deg_to_rad(ocean.wind_heading_deg)
	var wdir := Vector2(sin(wind), -cos(wind))
	var zmin := ocean.foam_z_now
	# pick a new crest every so often: the most breaking of a few random spots round the camera
	_spawn_t -= delta
	var cam := get_viewport().get_camera_3d()
	if k > 0.01 and cam != null and _spawn_t <= 0.0:
		_spawn_t = 0.12
		var spare: Crest = null
		for c in _crests:
			if not c.on:
				spare = c
				break
		if spare != null:
			var cp := cam.global_position
			var best := -1000.0
			var bx := 0.0
			var bz := 0.0
			for j in 10:
				var u := _rng.randf()
				var r := 6.0 + 74.0 * u * u          # more of them near than far
				var a := _rng.randf() * TAU
				var x := cp.x + cos(a) * r
				var z := cp.z + sin(a) * r
				var f := ocean.get_fold_z(x, z)
				if f > best:
					best = f
					bx = x
					bz = z
			if best > zmin + 0.4:
				spare.on = true
				spare.x = bx
				spare.z = bz
				spare.f = best
				spare.age = 0.0
				spare.low_t = 0.0
				spare.fold_t = 0.0
				spare.life = _rng.randf_range(1.5, 3.5)
				spare.pm.direction = Vector3(wdir.x * 0.8, 1.0, wdir.y * 0.8).normalized()
	for c in _crests:
		if not c.on:
			continue
		c.age += delta
		c.x += wdir.x * CREST_SPEED * delta
		c.z += wdir.y * CREST_SPEED * delta
		c.fold_t -= delta
		if c.fold_t <= 0.0:
			c.fold_t = 0.15
			c.f = ocean.get_fold_z(c.x, c.z)
		var want := smoothstep(zmin - 0.1, zmin + 0.8, c.f) * k
		var fade_in := minf(c.age / 0.25, 1.0)
		var fade_out := clampf((c.life - c.age) / 0.5, 0.0, 1.0)
		var w := want * fade_in * fade_out
		c.node.global_position = Vector3(c.x, ocean.get_height(c.x, c.z) + 0.2, c.z)
		_emit(c.node, w, w > 0.03)
		c.low_t = c.low_t + delta if want < 0.05 else 0.0
		if c.age >= c.life or c.low_t > 0.4:
			c.on = false
			_emit(c.node, 0.0, false)


## Where the sea hits the hull: watch the water height at points just outside the hull's sides, bow and stern. If it
## is rising at the hull's waterline much faster than the hull is, that is the sea slamming into her.
func _update_slams(delta: float, k: float) -> void:
	if motion == null or k < 0.02:
		return
	var pts: PackedVector2Array = motion.sample_points
	var n := pts.size()
	if _pt_prev.size() != n:
		_pt_prev.resize(n)
		_pt_prev.fill(NAN)
		_pt_cool.resize(n)
		_pt_cool.fill(0.0)
	_slam_gap -= delta
	for i in n:
		var lp := Vector3(pts[i].x * 1.12, 0.0, pts[i].y)
		var wp: Vector3 = motion.global_transform * lp
		var h := ocean.get_height(wp.x, wp.z)
		var hp := _pt_prev[i]
		_pt_prev[i] = h
		_pt_cool[i] -= delta
		if is_nan(hp) or _pt_cool[i] > 0.0 or _slam_gap > 0.0:
			continue
		var rel := (h - hp) / delta - (motion.velocity_at(wp) as Vector3).y
		var gap := h - wp.y                          # the sea above (+) or below (-) the hull's waterline here
		if rel > 2.0 and gap > -0.4 and gap < 1.5:
			var power := clampf((rel - 2.0) / 4.0, 0.0, 1.0) * k
			if power < 0.05:
				continue
			_pt_cool[i] = 0.6
			_slam_gap = 0.1
			var out := Vector3(lp.x, 0.0, lp.z)
			out = (motion.global_transform.basis * out)
			out.y = 0.0
			out = out.normalized() if out.length() > 0.01 else Vector3.ZERO
			_burst(Vector3(wp.x, h + 0.1, wp.z), out, power)


func _burst(pos: Vector3, out: Vector3, power: float) -> void:
	var b := _bursts[_burst_next]
	_burst_next = (_burst_next + 1) % _bursts.size()
	var pm := b.process_material as ParticleProcessMaterial
	pm.direction = Vector3(out.x * 0.6, 1.0, out.z * 0.6).normalized()
	pm.initial_velocity_min = 2.5 + 3.0 * power
	pm.initial_velocity_max = 4.5 + 5.0 * power
	b.global_position = pos
	b.amount_ratio = 0.35 + 0.65 * power
	var bl := b.get_meta("blobs") as GPUParticles3D
	bl.amount_ratio = 0.35 + 0.65 * power
	b.restart()
	bl.restart()
