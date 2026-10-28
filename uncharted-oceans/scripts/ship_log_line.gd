class_name ShipLogLine
extends Node
## Taking the ship's speed with the log line, the way it was done at sea. Created by ship_motion.gd
## (log_line_enabled). There is no speed read-out anywhere: you count. How it is done is in the book
## (data/book/log_line.md).
##
## On the poop deck by the stern rail there is a coil of rope (LogLine_Coil), and a 28 second sand glass standing on the rail.
##   * Click the coil (it is outlined in white when you look at it): the line runs from the coil up to the rail,
##     over it, and down the outside of the stern. Click it again, or walk away, and it is hauled back in.
##   * The line is plain at first (the stray line), then a RED BLOCK (the mark), then a plain wooden block at
##     every fixed distance. They run out over the rail at the speed the ship is making.
##   * When the red block goes over the rail, click the glass (it is outlined too): it turns and runs for 28 s.
##     Count the wooden blocks that go over the rail until the sand is out. That is the speed in knots.
##     When the sand is out the line is held fast.
##
## Real figures, kept: a knot is 14.4 m (47 ft 3 in) of line and the glass is 28 s, so one block per knot of
## speed. The blocks are only 0.3 m apart on the model, so the line runs out slowly (0.3 m per real 14.4 m) and a
## block goes over the rail in the same time it would at sea. It is the timing you count, not the speed of the rope.
## Blocks sit half a spacing off the mark, so a count is the speed to the nearest knot.
##
## The rope's path is the markers LogLine_P0 .. P4 in the brig (coil, along the deck, up the rail, over, down). Godot
## draws the rope along them and slides the blocks. The glass is built here, standing on the deck beside the coil.

const Outline := preload("res://scripts/interact_outline.gd")

@export var glass_seconds := 28.0
## Real figures: metres of line per knot, and the stray line before the mark (about 12 fathoms).
@export var knot_spacing_m := 14.4
@export var stray_m := 22.0
## The model: distance between blocks on the rope.
@export var block_spacing := 0.30
@export var rope_radius := 0.0145
@export var coil_name := "LogLine_Coil"
@export var anchor_name := "LogLine"
## How far you can click the coil or the glass (m), and how far you can walk off before the line is hauled in.
@export var reach := 2.4
@export var stow_distance := 5.0
## Seconds for the line to run out over the rail (and to come in).
@export var run_seconds := 0.9
## The glass, from the coil, in the brig's own frame (y is up): standing on top of the stern rail, to one side of the
## rope where it goes over, so it is up at eye level where you can see it. glass_scale makes it a little bigger than life.
@export var glass_offset := Vector3(0.35, 0.63, -0.65)
@export var glass_scale := 1.4

const ROPE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float grow = 1.0;
uniform float path_len = 2.0;
uniform float scroll = 0.0;
uniform vec3 col_a : source_color = vec3(0.62, 0.50, 0.30);
uniform vec3 col_b : source_color = vec3(0.34, 0.25, 0.13);
varying float v_along;
void vertex() {
	v_along = UV.y;
}
void fragment() {
	if (v_along > grow) {
		discard;
	}
	float t = fract(UV.x * 3.0 + (v_along * path_len - scroll) * 14.0);
	float s = smoothstep(0.30, 0.45, t) - smoothstep(0.80, 0.95, t);
	ALBEDO = mix(col_b, col_a, s);
	ROUGHNESS = 0.95;
}
"""

enum Line { STOWED, OUT, HELD }

var _ship: Node3D
var _anchor: Node3D
var _coil: MeshInstance3D
var _state := Line.STOWED
var _p := 0.0                     # line paid out since the coil was clicked, model metres
var _k := 0.02                    # model metres per real metre
var _grow := 0.0                  # 0 = in the coil, 1 = the whole line out
# the rope
var _root: Node3D
var _pts := PackedVector3Array()
var _cum := PackedFloat32Array()
var _total := 1.0
var _crest := 0.6                 # distance along the path to the top of the rail
var _rope_mat: ShaderMaterial
var _blocks: MultiMesh
var _weight: MeshInstance3D
# the glass
var _glass: Node3D
var _glass_parts: Array[MeshInstance3D] = []
var _sand_top: Node3D
var _sand_bot: Node3D
var _stream: MeshInstance3D
var _top := 0.0                   # sand in the top bulb, 0..1
var _spin := 0.0
var _flipped := false
# who we are looking at
var _cam: Camera3D
var _player: Node
var _aim := 0                     # 0 nothing, 1 the coil, 2 the glass

func _ready() -> void:
	_ship = get_parent() as Node3D
	_k = block_spacing / knot_spacing_m
	_anchor = _ship.find_child(anchor_name, true, false) as Node3D
	_coil = _ship.find_child(coil_name, true, false) as MeshInstance3D
	var marks: Array[Vector3] = []
	for i in 5:
		var m := _ship.find_child("LogLine_P%d" % i, true, false) as Node3D
		if m == null:
			push_warning("ShipLogLine: no LogLine_P%d marker in the ship; log line left alone" % i)
			set_process(false)
			set_process_input(false)
			return
		marks.append(_ship.to_local(m.global_position))
	if _anchor == null or _coil == null:
		push_warning("ShipLogLine: no %s / %s in the ship; log line left alone" % [anchor_name, coil_name])
		set_process(false)
		set_process_input(false)
		return
	_build_path(marks)
	_build_rope()
	_build_glass(_anchor)

# ---------------------------------------------------------------- the rope

func _spline(pts: Array[Vector3]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in pts.size() - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		var n := maxi(4, int(p1.distance_to(p2) / 0.02))
		for s in n:
			var t := float(s) / n
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(pts[pts.size() - 1])
	return out

func _build_path(marks: Array[Vector3]) -> void:
	_pts = _spline(marks)
	_cum.resize(_pts.size())
	_cum[0] = 0.0
	for i in range(1, _pts.size()):
		_cum[i] = _cum[i - 1] + _pts[i].distance_to(_pts[i - 1])
	_total = _cum[_pts.size() - 1]
	# the crest is where the path is nearest the third marker, the top of the rail
	var best := 1e9
	for i in _pts.size():
		var d := _pts[i].distance_to(marks[2])
		if d < best:
			best = d
			_crest = _cum[i]

func _along(u: float) -> int:
	var lo := 0
	var hi := _pts.size() - 1
	while lo < hi - 1:
		var mid := (lo + hi) >> 1
		if _cum[mid] <= u:
			lo = mid
		else:
			hi = mid
	return lo

func _pos_at(u: float) -> Vector3:
	var i := _along(clampf(u, 0.0, _total))
	var seg := _cum[i + 1] - _cum[i]
	var f := 0.0 if seg < 1e-6 else (clampf(u, 0.0, _total) - _cum[i]) / seg
	return _pts[i].lerp(_pts[i + 1], f)

func _tangent_at(u: float) -> Vector3:
	var i := _along(clampf(u, 0.0, _total))
	return (_pts[i + 1] - _pts[i]).normalized()

func _build_rope() -> void:
	_root = Node3D.new()
	_root.name = "LogLineRope"
	_ship.add_child(_root)
	# the rope: a thin tube along the path; the shader draws it out to `grow` and slides the twist
	var sides := 6
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var normal := Vector3.UP
	for i in _pts.size():
		var t := (_pts[mini(i + 1, _pts.size() - 1)] - _pts[maxi(i - 1, 0)]).normalized()
		normal = normal - t * normal.dot(t)
		if normal.length() < 0.001:
			normal = t.cross(Vector3.RIGHT)
		normal = normal.normalized()
		var bi := t.cross(normal)
		for s in sides + 1:
			var a := TAU * float(s) / sides
			var dir := normal * cos(a) + bi * sin(a)
			verts.append(_pts[i] + dir * rope_radius)
			norms.append(dir)
			uvs.append(Vector2(float(s) / sides, _cum[i] / _total))
	var ring := sides + 1
	for i in _pts.size() - 1:
		for s in sides:
			var a := i * ring + s
			var b := a + ring
			idx.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var shader := Shader.new()
	shader.code = ROPE_SHADER
	_rope_mat = ShaderMaterial.new()
	_rope_mat.shader = shader
	_rope_mat.set_shader_parameter("path_len", _total)
	var rope := MeshInstance3D.new()
	rope.mesh = am
	rope.material_override = _rope_mat
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(rope)
	# the blocks: small wooden blocks seized to the line (one is red, the mark), moved every frame
	var bm := BoxMesh.new()
	bm.size = Vector3(0.034, 0.034, 0.05)
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.roughness = 0.8
	bm.material = bmat
	_blocks = MultiMesh.new()
	_blocks.transform_format = MultiMesh.TRANSFORM_3D
	_blocks.use_colors = true
	_blocks.mesh = bm
	_blocks.instance_count = int(_total / block_spacing) + 6
	_blocks.visible_instance_count = 0
	var bi_node := MultiMeshInstance3D.new()
	bi_node.multimesh = _blocks
	bi_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(bi_node)
	# a small lead weight on the free end
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	sm.radial_segments = 10
	sm.rings = 5
	_weight = MeshInstance3D.new()
	_weight.mesh = sm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.16, 0.16, 0.18)
	wm.roughness = 0.5
	wm.metallic = 0.6
	_weight.material_override = wm
	_weight.position = _pts[_pts.size() - 1]
	_weight.visible = false
	_root.add_child(_weight)

func _update_blocks() -> void:
	var l_mark := stray_m * _k
	var n := 0
	var wood := Color(0.30, 0.20, 0.10)
	var red := Color(0.72, 0.07, 0.05)
	# item 0 is the red mark; block k (k >= 1) sits (k - 0.5) spacings behind it, so a count is the speed rounded
	var k := 0
	while n < _blocks.instance_count:
		var line_pos := l_mark + (0.0 if k == 0 else (float(k) - 0.5) * block_spacing)
		var u := _p - line_pos                    # how far along the path it has got (0 = out of the coil)
		if u > _total:
			k += 1
			if k > 4000:
				break
			continue
		if u < 0.0:
			break
		if u / _total <= _grow:
			var tg := _tangent_at(u)
			var basis := Basis.looking_at(tg, Vector3.UP if absf(tg.y) < 0.95 else Vector3.RIGHT)
			if k == 0:
				basis = basis.scaled(Vector3(1.5, 1.5, 1.2))
			_blocks.set_instance_transform(n, Transform3D(basis, _pos_at(u)))
			_blocks.set_instance_color(n, red if k == 0 else wood)
			n += 1
		k += 1
	_blocks.visible_instance_count = n

# ---------------------------------------------------------------- the glass

func _mat(c: Color, rough: float, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.roughness = rough
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _mesh_at(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_glass_parts.append(mi)
	return mi

func _cone(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = 14
	c.rings = 1
	return c

## Two glass cones meeting at a neck between two wooden plates, held by three posts; sand in the top and bottom
## (scaled as it runs). About 17 cm tall.
func _build_glass(host: Node3D) -> void:
	_glass = Node3D.new()
	_glass.name = "SandGlass"
	_glass.position = glass_offset
	_glass.scale = Vector3.ONE * glass_scale
	host.add_child(_glass)
	var wood := _mat(Color(0.20, 0.12, 0.07), 0.8)
	var glass := _mat(Color(0.80, 0.90, 0.90), 0.1, 0.22)
	var sand := _mat(Color(0.85, 0.72, 0.45), 0.95)
	var plate := _cone(0.048, 0.048, 0.012)
	_mesh_at(_glass, plate, wood, Vector3(0.0, 0.081, 0.0))
	_mesh_at(_glass, plate, wood, Vector3(0.0, -0.081, 0.0))
	var post := _cone(0.004, 0.004, 0.162)
	for i in 3:
		var a := TAU * i / 3.0
		_mesh_at(_glass, post, wood, Vector3(cos(a), 0.0, sin(a)) * 0.038)
	_mesh_at(_glass, _cone(0.030, 0.004, 0.075), glass, Vector3(0.0, 0.0375, 0.0))
	_mesh_at(_glass, _cone(0.004, 0.030, 0.075), glass, Vector3(0.0, -0.0375, 0.0))
	_sand_top = Node3D.new()
	_glass.add_child(_sand_top)
	_mesh_at(_sand_top, _cone(0.028, 0.0035, 0.073), sand, Vector3(0.0, 0.0365, 0.0))
	_sand_bot = Node3D.new()
	_sand_bot.position = Vector3(0.0, -0.075, 0.0)
	_glass.add_child(_sand_bot)
	_mesh_at(_sand_bot, _cone(0.002, 0.027, 0.06), sand, Vector3(0.0, 0.03, 0.0))
	var sm := CylinderMesh.new()
	sm.top_radius = 0.0012
	sm.bottom_radius = 0.0012
	sm.height = 1.0
	sm.radial_segments = 5
	sm.rings = 1
	_stream = _mesh_at(_glass, sm, sand, Vector3.ZERO)

func _animate_glass(delta: float) -> void:
	if _glass == null:
		return
	if _spin > 0.0:
		_spin += delta / 0.6
		if _spin >= 0.5 and not _flipped:
			_flipped = true
			_top = 1.0 - _top              # what had run through is now on top
		if _spin >= 1.0:
			_spin = 0.0
	_glass.rotation.x = _spin * TAU
	_glass.position = glass_offset + Vector3(0.0, sin(_spin * PI) * 0.04, 0.0)
	var top := clampf(_top, 0.0, 1.0)
	var bot := 1.0 - top
	_sand_top.visible = top > 0.002
	_sand_top.scale = Vector3.ONE * maxf(top, 0.001)
	_sand_bot.visible = bot > 0.002
	var heap := pow(maxf(bot, 0.001), 1.0 / 3.0)
	_sand_bot.scale = Vector3(heap, heap, heap)
	var falling := _top > 0.001 and _spin == 0.0
	_stream.visible = falling
	if falling:
		var apex := -0.075 + 0.06 * heap
		_stream.scale.y = -apex
		_stream.position.y = apex * 0.5

# ---------------------------------------------------------------- aiming and clicking

func _camera() -> Camera3D:
	if _cam == null or not is_instance_valid(_cam):
		_player = get_tree().get_first_node_in_group("player")
		if _player:
			_cam = _player.get_node_or_null("Head/Camera3D") as Camera3D
	return _cam

func _ray_dist(mi: MeshInstance3D, o: Vector3, d: Vector3, grow_by: float) -> float:
	var inv := mi.global_transform.affine_inverse()
	var hit = mi.get_aabb().grow(grow_by).intersects_ray(inv * o, (inv.basis * d).normalized())
	return o.distance_to(mi.global_transform * (hit as Vector3)) if hit != null else INF

## What you are looking at: 1 the coil, 2 the glass, 0 nothing (the nearer one wins).
func _aimed() -> int:
	var cam := _camera()
	if cam == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return 0
	if bool(_player.get("input_locked")) or bool(_player.get_meta("grab_busy", false)):
		return 0
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var dc := _ray_dist(_coil, o, d, 0.12)
	var dg := INF
	var gbox := AABB(Vector3(-0.07, -0.11, -0.07), Vector3(0.14, 0.22, 0.14))
	var ginv := _glass.global_transform.affine_inverse()
	var gh = gbox.intersects_ray(ginv * o, (ginv.basis * d).normalized())
	if gh != null:
		dg = o.distance_to(_glass.global_transform * (gh as Vector3))
	if minf(dc, dg) > reach:
		return 0
	return 1 if dc <= dg else 2

func _input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var a := _aimed()
	if a == 1:
		if _state == Line.STOWED:
			_state = Line.OUT
			_p = 0.0
		else:
			_state = Line.STOWED
		get_viewport().set_input_as_handled()
	elif a == 2 and _spin == 0.0:
		_spin = 0.0001
		_flipped = false
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	# the sand runs whether or not you are looking
	if _top > 0.0:
		_top = maxf(0.0, _top - delta / glass_seconds)
		if _top == 0.0 and _state == Line.OUT:
			_state = Line.HELD          # the sand's out: the line is held fast
	# walk away and the line is hauled in
	var cam := _camera()
	if _state != Line.STOWED and cam != null and cam.global_position.distance_to(_coil.global_position) > stow_distance:
		_state = Line.STOWED
	# the line runs out at the ship's speed (backwards if she goes astern)
	if _state == Line.OUT:
		_p = maxf(0.0, _p + float(_ship.get("speed")) * _k * delta)
	_grow = move_toward(_grow, 0.0 if _state == Line.STOWED else 1.0, delta / maxf(run_seconds, 0.05))
	var shown := _grow > 0.001
	_root.visible = shown
	if shown:
		_rope_mat.set_shader_parameter("grow", _grow)
		_rope_mat.set_shader_parameter("scroll", _p)
		_update_blocks()
		_weight.visible = _grow > 0.98
	_animate_glass(delta)
	# the white outline on whatever you can click
	var a := _aimed()
	Outline.set_on(_coil, a == 1)
	for m in _glass_parts:
		m.material_overlay = Outline.material() if a == 2 else null
