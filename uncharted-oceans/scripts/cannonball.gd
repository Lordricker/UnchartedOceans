class_name Cannonball
extends Node3D
## A round shot in flight. Launched by ship_cannons.gd (ShipCannons.fire_balls).
##
## No physics body: each physics tick the ball steps along its arc under gravity, and a ray from where it was to
## where it will be is tested against the ship hulls, ship decks and rocks (layers 1 and 2) and the island terrain
## (layer 4), and against the sea surface (Ocean.get_height). The ray means a fast ball can never skip through a
## hull. The first thing the ray meets decides the hit:
##   the sea         a splash: a spout of drops and a column of foam
##   a ship's hull   wood chips and dust, and a hole where it hit (ShipFlooding.punch_hole_local), so the hold
##                   floods; a hit on a deck, rail or mast only chips and dusts
##   land or a rock  dust and dirt
## The ship that fired is skipped (exclude), so a ball leaving the muzzle can't hit its own hull.
## A faint trail of smoke follows the ball so the player can see it fly. Costs nothing when nothing is in the air,
## and MAX_LIVE balls at once is far more than two big ships ever fire.

signal landed(kind: String, pos: Vector3, ship: Node3D)

const MASK := 1 | 2 | 8
const GRAVITY := 9.8
const MAX_LIVE := 48

static var live := 0
static var _puff_tex: ImageTexture
static var _iron_mat: StandardMaterial3D

var vel := Vector3.ZERO
var ocean                  # the Ocean (untyped: its methods are called by name)
var exclude: Array[RID] = []
var shooter: Node3D
var tint := 1.0
var trail := true
## Drawn bigger than a real ball (about 12 cm radius) so it can be seen at range.
var radius := 0.13
var max_life := 9.0
var max_dist := 1800.0

var _age := 0.0
var _dead := false
var _start := Vector3.ZERO
var _trail: GPUParticles3D


static func launch(parent: Node, pos: Vector3, velocity: Vector3, sea: Node, skip: Array[RID], from_ship: Node3D, with_trail := true) -> Cannonball:
	if live >= MAX_LIVE:
		return null
	var b := Cannonball.new()
	b.name = "Cannonball"
	b.vel = velocity
	b.ocean = sea
	b.exclude = skip
	b.shooter = from_ship
	b.trail = with_trail
	b.tint = sun_tint(sea)
	parent.add_child(b)
	b.global_position = pos
	b._start = pos
	return b


func _ready() -> void:
	live += 1
	tree_exiting.connect(func() -> void: Cannonball.live -= 1)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = _iron()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if trail:
		_make_trail()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_age += delta
	var from := global_position
	if _age > max_life or from.distance_to(_start) > max_dist:
		_die()
		return
	vel.y -= GRAVITY * delta
	var to := from + vel * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, MASK, exclude)
	var hit := space.intersect_ray(q)
	var seg := maxf(from.distance_to(to), 0.0001)
	var t_hit := INF
	if not hit.is_empty():
		t_hit = from.distance_to(hit["position"] as Vector3) / seg
	var t_water := INF
	if ocean != null:
		var fa := from.y - float(ocean.get_height(from.x, from.z))
		var fb := to.y - float(ocean.get_height(to.x, to.z))
		if fb <= 0.0:
			t_water = clampf(fa / (fa - fb), 0.0, 1.0) if fa > 0.0 else 0.0
	if t_hit == INF and t_water == INF:
		global_position = to
		return
	if t_hit <= t_water:
		_hit_solid(hit)
	else:
		_hit_water(from.lerp(to, t_water))


func _hit_water(pos: Vector3) -> void:
	global_position = pos
	burst(get_parent(), pos, Vector3.UP, "water", tint)
	landed.emit("water", pos, null)
	_die()


func _hit_solid(hit: Dictionary) -> void:
	var pos: Vector3 = hit["position"]
	var nrm: Vector3 = hit["normal"]
	var col := hit["collider"] as Node
	global_position = pos
	var ship := _ship_of(col)
	if ship != null:
		var body := col as CollisionObject3D
		if body != null and (body.collision_layer & 2) != 0:
			_punch(ship, pos, nrm)         # the hull itself: a hole
		burst(get_parent(), pos, nrm, "hull", tint)
		landed.emit("hull", pos, ship)
	else:
		burst(get_parent(), pos, nrm, "land", tint)
		landed.emit("land", pos, null)
	_die()


## The ship (the node in group "ships") a collider belongs to, or null.
func _ship_of(n: Node) -> Node3D:
	var p := n
	while p != null:
		if p.is_in_group("ships"):
			return p as Node3D
		p = p.get_parent()
	return null


func _punch(ship: Node3D, pos: Vector3, nrm: Vector3) -> void:
	for f in get_tree().get_nodes_in_group("ship_flooding"):
		if ship.is_ancestor_of(f):
			var inv := ship.global_transform.affine_inverse()
			var lp: Vector3 = inv * pos
			var ln: Vector3 = (ship.global_transform.basis.inverse() * nrm).normalized()
			f.call("punch_hole_local", lp, ln)
			return


func _die() -> void:
	if _dead:
		return
	_dead = true
	if _trail != null and is_instance_valid(_trail):
		# let the last of the trail drift away instead of vanishing with the ball
		var t := _trail
		t.emitting = false
		t.reparent(get_parent())
		get_tree().create_timer(t.lifetime + 0.3).timeout.connect(t.queue_free)
	queue_free()


# ---------------------------------------------------------------- the trail

func _make_trail() -> void:
	var p := GPUParticles3D.new()
	p.name = "Trail"
	p.amount = 60
	p.lifetime = 0.8
	p.local_coords = false
	p.fixed_fps = 30
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-200.0, -100.0, -200.0), Vector3(400.0, 200.0, 400.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = 0.5
	pm.scale_max = 0.8
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(1.0, 2.0))
	var ct := CurveTexture.new()
	ct.curve = sc
	pm.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.1, 1.0])
	g.colors = PackedColorArray([Color(0.9, 0.9, 0.9, 0.0), Color(0.9, 0.9, 0.9, 0.4), Color(0.75, 0.75, 0.75, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _puff_quad(0.5, tint)
	add_child(p)
	p.emitting = true
	_trail = p


# ---------------------------------------------------------------- impacts and shared bits

## Brightness for unlit effects: dimmed with the sun so they don't glow at night (the same rule as the bow spray).
static func sun_tint(sea: Node) -> float:
	if sea == null:
		return 1.0
	var path = sea.get("sun_path")
	if path == null:
		return 1.0
	var sun := sea.get_node_or_null(path) as DirectionalLight3D
	if sun == null:
		return 1.0
	return (0.2 + 0.8 * clampf(sun.light_energy, 0.0, 1.0)) if sun.visible else 0.2


static func _iron() -> StandardMaterial3D:
	if _iron_mat == null:
		_iron_mat = StandardMaterial3D.new()
		_iron_mat.albedo_color = Color(0.1, 0.1, 0.11)
		_iron_mat.roughness = 0.55
		_iron_mat.metallic = 0.5
	return _iron_mat


## A soft round puff with a little noise in it.
static func puff_texture() -> ImageTexture:
	if _puff_tex != null:
		return _puff_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.045
	for y in n:
		for x in n:
			var dx := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var dy := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var r := sqrt(dx * dx + dy * dy)
			var nv := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var a := smoothstep(0.0, 0.7, clampf(1.0 - r, 0.0, 1.0)) * (0.65 + 0.5 * nv)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex


static func _puff_quad(size: float, bright: float) -> QuadMesh:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = puff_texture()
	m.albedo_color = Color(bright, bright, bright, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	return q


## A crossed pair of thin quads, +Y along the flight, the tail end fading: a drop or chip in motion.
static func _drop_mesh(w: float, h: float) -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(-w, 0, 0), Vector3(w, 0, 0), Vector3(w, h, 0), Vector3(-w, h, 0),
		Vector3(0, 0, -w), Vector3(0, 0, w), Vector3(0, h, w), Vector3(0, h, -w)])
	var tail := Color(1, 1, 1, 0.15)
	var head := Color(1, 1, 1, 0.95)
	var cols := PackedColorArray([tail, tail, head, head, tail, tail, head, head])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	m.surface_set_material(0, mat)
	m.custom_aabb = AABB(Vector3(-1, 0, -1), Vector3(2, h, 2))
	return m


## One impact: drops (or chips) and puffs thrown away from the surface, in the world, gone after a few seconds.
## kind is "water", "hull" or "land"; normal points away from what was hit.
static func burst(parent: Node, pos: Vector3, normal: Vector3, kind: String, bright: float) -> void:
	if parent == null:
		return
	var root := Node3D.new()
	root.name = "Impact"
	parent.add_child(root)
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
	root.global_transform = Transform3D(Basis.looking_at(normal.normalized(), up), pos)
	match kind:
		"water":
			_drops(root, 44, 1.3, _lit(Color(0.88, 0.94, 1.0, 0.9), bright), 4.0, 9.0, 24.0, 0.014)
			_puffs(root, 10, 1.8, _lit(Color(0.92, 0.96, 1.0, 0.6), bright), 1.5, 4.0, 18.0, 0.8, 2.6)
		"hull":
			_drops(root, 16, 0.9, _lit(Color(0.45, 0.29, 0.14, 1.0), bright), 2.5, 7.0, 55.0, 0.022)
			_puffs(root, 6, 1.4, _lit(Color(0.62, 0.58, 0.5, 0.5), bright), 0.8, 2.2, 50.0, 0.4, 1.3)
		_:
			_drops(root, 14, 0.9, _lit(Color(0.5, 0.4, 0.28, 1.0), bright), 2.5, 7.0, 55.0, 0.022)
			_puffs(root, 8, 1.8, _lit(Color(0.66, 0.58, 0.44, 0.55), bright), 0.8, 2.6, 50.0, 0.5, 1.6)
	parent.get_tree().create_timer(3.5).timeout.connect(root.queue_free)


static func _lit(c: Color, bright: float) -> Color:
	return Color(c.r * bright, c.g * bright, c.b * bright, c.a)


static func _drops(root: Node3D, amount: int, life: float, col: Color, vmin: float, vmax: float, spread: float, w: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.4
	p.local_coords = false
	p.fixed_fps = 30
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-25.0, -10.0, -25.0), Vector3(50.0, 30.0, 50.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3(0.0, 0.0, -1.0)
	pm.spread = spread
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3(0.0, -GRAVITY, 0.0)
	pm.particle_flag_align_y = true
	pm.scale_min = 0.7
	pm.scale_max = 1.5
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	g.colors = PackedColorArray([col, col, Color(col.r, col.g, col.b, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _drop_mesh(w, 0.5)
	root.add_child(p)
	p.emitting = true       # only once it is in the tree, or a one-shot burst can be missed


static func _puffs(root: Node3D, amount: int, life: float, col: Color, vmin: float, vmax: float, spread: float, smin: float, smax: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.9
	p.randomness = 0.5
	p.local_coords = false
	p.fixed_fps = 30
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-25.0, -10.0, -25.0), Vector3(50.0, 30.0, 50.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3(0.0, 0.0, -1.0)
	pm.spread = spread
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3(0.0, 0.3, 0.0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = smin
	pm.scale_max = smax
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.4))
	sc.add_point(Vector2(1.0, 1.5))
	var ct := CurveTexture.new()
	ct.curve = sc
	pm.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.1, 1.0])
	g.colors = PackedColorArray([Color(col.r, col.g, col.b, 0.0), col, Color(col.r, col.g, col.b, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _puff_quad(1.0, 1.0)
	root.add_child(p)
	p.emitting = true
