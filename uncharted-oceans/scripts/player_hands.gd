class_name PlayerHands
extends Node3D
## First-person floating welding-glove hands (assets/player/Hand_R.glb, Hand_L.glb).
## Lives under the player's Camera3D (player.gd adds scenes/player_hands.tscn at startup).
##
## Each glove has one blend shape, "Closed" (0 = relaxed, slightly cupped; 1 = fist). Everything
## else is whole-object motion, driven by the state player.gd feeds in every physics frame:
##   walking / running: hands swing alternately, bob with each step, and curl a little at a run
##   jumping / falling: hands lag behind, then float up while you fall and dip when you land
##   climbing: alternating reach-and-pull with the fists closed on the rungs
##   swimming: alternating paddle strokes (a slow tread when you're not swimming anywhere)
##   looking around: the hands trail the camera a little
##
## Hand-offs for later grabbing: call grab(true/false) to hold both fists shut, or set
## closed_override[0] (right) / [1] (left) to a value 0..1 (-1 = no override).
## Pose values below are for the right hand; the left hand mirrors them.

@export_group("Models")
@export_file("*.glb") var right_hand_path := "res://assets/player/Hand_R.glb"
@export_file("*.glb") var left_hand_path := "res://assets/player/Hand_L.glb"
@export var cast_shadows := false

@export_group("Rest pose")
@export var rest_position := Vector3(0.27, -0.29, -0.38)     # down at the sides: just the tops of the gloves show at the bottom of the screen
## Pitch (+ = fingers up), yaw (+ = fingers inward), roll (- = palm turns inward), in degrees.
@export var rest_rotation_deg := Vector3(22.0, 5.0, -28.0)
@export_range(0.0, 1.0) var rest_closed := 0.0

@export_group("Walking")
@export var stride_length := 1.5           ## metres per left+right step cycle
@export var swing_distance := 0.055        ## hand swing forward/back
@export var swing_lift := 0.02             ## the forward-swinging hand rises a little
@export var bob_height := 0.012
@export var side_sway := 0.01
@export var run_closed := 0.3              ## how much the fingers curl at a full run

@export_group("Air")
@export var air_follow := 0.012            ## hand offset per m/s of vertical speed (rise = drop, fall = float)
@export var landing_kick := 0.45           ## how hard the hands dip when you land
@export var spring_stiffness := 120.0

@export_group("Climbing")
@export var climb_cycle_length := 0.6      ## metres climbed per left+right cycle (two rungs)
@export var climb_high := Vector3(0.15, 0.09, -0.50)
@export var climb_low := Vector3(0.15, -0.13, -0.44)
@export var climb_rotation_deg := Vector3(52.0, 0.0, -25.0)
@export var grip_fraction := 0.65          ## share of each cycle spent gripping (hand moving down)

@export_group("Swimming")
@export var swim_position := Vector3(0.19, -0.19, -0.42)
@export var swim_rotation_deg := Vector3(22.0, 6.0, -30.0)
@export var stroke_radius := Vector3(0.05, 0.08, 0.15)   ## paddle circle, x / y / z
@export var stroke_rate := 0.9             ## strokes per second while swimming along

@export_group("Holding (the wheel, the ropes)")
## Pose of the right hand's fist on a rim, relative to the camera; the position is where it's held.
@export var hold_rotation_deg := Vector3(0.0, 0.0, -20.0)
@export var hold_offset := Vector3(0.0, 0.0, 0.03)

@export_group("Carrying a box")
## Hand pose against the box's sides (pitch, yaw, roll in degrees; the left hand mirrors it) and how tight the fingers are.
@export var carry_rotation_deg := Vector3(8.0, -10.0, -75.0)
@export var carry_grip := 0.55
@export var carry_squeeze := 0.02          ## how far the palms sit out from the box faces

@export_group("Feel")
@export var look_sway := 0.00045           ## hand lag per pixel of mouse movement
@export var blend_time := 0.18             ## seconds to change between ground / air / ladder / water

# ---- set by ShipWheel (or anything else the right hand grabs) ----
var hold_active := false
var hold_point := Vector3.ZERO             ## world position the right hand holds
## The left hand can hold something too (the sail ropes use both, hand over hand).
var hold_active_l := false
var hold_point_l := Vector3.ZERO
## Carrying a cargo box (set by CargoSystem): both hands grip its sides. The centre is in the camera's frame and
## carry_half is half the box's width, so the hands stay on its left and right faces.
var carry_active := false
var carry_centre := Vector3(0.0, -0.46, -0.8)
var carry_half := 0.2

# ---- state, set by player.gd each physics frame (or by a test) ----
var on_floor := true
var ground_speed := 0.0
var sprinting := false
var vertical_speed := 0.0
var climbing := false
var climb_rate := 0.0                      ## m/s up the ladder (negative = down)
## The ladder's own orientation (up the ladder = +Y, away from what is climbed = +Z), set by player.gd while climbing:
## the hands reach toward the ladder in this frame, so they stay on it however the head is turned.
var climb_face := Basis.IDENTITY
var climb_face_set := false
var swimming := false
var swim_effort := 0.0                     ## 0..1, how hard you're pushing WASD in the water
## -1 = no override. Index 0 = right hand, 1 = left hand.
var closed_override := [-1.0, -1.0]

var _pivots: Array[Node3D] = [null, null]
var _meshes: Array[MeshInstance3D] = [null, null]
var _shape_idx := [-1, -1]
var _closed := [0.0, 0.0]

var _time := 0.0
var _walk_phase := 0.0
var _walk_amp := 0.0
var _run_amp := 0.0
var _climb_phase := 0.0
var _swim_phase := 0.0
var _swim_amp := 0.0
var _w_air := 0.0
var _w_climb := 0.0
var _w_swim := 0.0
var _w_hold := 0.0
var _w_hold_l := 0.0
var _w_carry := 0.0
var _oy := 0.0
var _ovy := 0.0
var _was_grounded := true
var _last_vy := 0.0
var _look := Vector2.ZERO

func _ready() -> void:
	_pivots[0] = _load_hand(right_hand_path, 0)
	_pivots[1] = _load_hand(left_hand_path, 1)
	_apply_pose(0.0)

func grab(closed: bool) -> void:
	closed_override = [1.0, 1.0] if closed else [-1.0, -1.0]

# ---------------------------------------------------------------- loading

func _load_hand(path: String, i: int) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "RightHand" if i == 0 else "LeftHand"
	add_child(pivot)
	if not ResourceLoader.exists(path):
		push_warning("PlayerHands: %s not found (open the project in the editor once so it imports)" % path)
		return pivot
	var scene := load(path) as PackedScene
	if scene == null:
		return pivot
	var inst := scene.instantiate()
	pivot.add_child(inst)
	var mi := _find_mesh(inst)
	if mi:
		_meshes[i] = mi
		_shape_idx[i] = mi.find_blend_shape_by_name("Closed")
		mi.material_override = _make_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 1.0   # always drawn, even when the blend shape moves the bounds
	return pivot

func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _find_mesh(c)
		if m:
			return m
	return null

## Worn dark leather: mottled colour plus fine grain, triplanar so it needs no UV layout.
func _make_material() -> StandardMaterial3D:
	var mottle := FastNoiseLite.new()
	mottle.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mottle.frequency = 0.012
	mottle.fractal_octaves = 5
	mottle.seed = 7
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.32, 0.68])
	ramp.colors = PackedColorArray([Color(0.035, 0.020, 0.012), Color(0.20, 0.115, 0.06)])
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = mottle
	tex.color_ramp = ramp

	var grain := FastNoiseLite.new()
	grain.noise_type = FastNoiseLite.TYPE_CELLULAR
	grain.frequency = 0.05
	grain.seed = 3
	var nrm := NoiseTexture2D.new()
	nrm.width = 256
	nrm.height = 256
	nrm.seamless = true
	nrm.as_normal_map = true
	nrm.bump_strength = 3.0
	nrm.noise = grain

	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.6
	m.normal_enabled = true
	m.normal_texture = nrm
	m.normal_scale = 0.5
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(7.0, 7.0, 7.0)
	return m

# ---------------------------------------------------------------- input

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look += Vector2(-e.relative.x, e.relative.y) * look_sway
		_look = _look.clampf(-0.07, 0.07)

# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_time += delta
	_update_state(delta)
	_apply_pose(delta)

func _update_state(delta: float) -> void:
	var grounded := on_floor and not climbing and not swimming
	# jump / landing kicks for the vertical spring
	if _was_grounded and not grounded and not climbing and not swimming and vertical_speed > 0.5:
		_ovy -= vertical_speed * 0.06
	elif not _was_grounded and grounded:
		_ovy += clampf(_last_vy, -9.0, 0.0) * landing_kick
	_was_grounded = grounded
	_last_vy = vertical_speed

	var fall := not grounded and not climbing and not swimming
	var k := 1.0 / maxf(blend_time, 0.01)
	_w_air = move_toward(_w_air, 1.0 if fall else 0.0, k * delta)
	_w_climb = move_toward(_w_climb, 1.0 if climbing else 0.0, k * delta)
	_w_swim = move_toward(_w_swim, 1.0 if (swimming and not climbing) else 0.0, k * delta)
	_w_hold = move_toward(_w_hold, 1.0 if hold_active else 0.0, 1.0 / 0.12 * delta)
	_w_hold_l = move_toward(_w_hold_l, 1.0 if hold_active_l else 0.0, 1.0 / 0.12 * delta)
	_w_carry = move_toward(_w_carry, 1.0 if (carry_active and not climbing and not swimming) else 0.0, 1.0 / 0.15 * delta)

	# walking: phase follows distance, amplitude follows speed
	var speed := ground_speed if grounded else 0.0
	_walk_phase += speed * delta / stride_length * TAU
	_walk_amp = move_toward(_walk_amp, clampf(speed / 3.0, 0.0, 1.6), 6.0 * delta)
	_run_amp = move_toward(_run_amp, clampf((speed - 3.0) / 2.5, 0.0, 1.0) if sprinting else 0.0, 4.0 * delta)
	# climbing: phase follows height climbed (negative when climbing down)
	if climbing:
		_climb_phase += climb_rate * delta / climb_cycle_length
	# swimming: strokes speed up with effort, but you always tread water a little
	_swim_amp = move_toward(_swim_amp, 0.45 + 0.55 * swim_effort, 3.0 * delta)
	_swim_phase += TAU * stroke_rate * (0.45 + 0.55 * swim_effort) * delta

	var tgt := -air_follow * vertical_speed if fall else 0.0
	tgt = clampf(tgt, -0.05, 0.09)
	_ovy += (spring_stiffness * (tgt - _oy) - 2.0 * sqrt(spring_stiffness) * 0.55 * _ovy) * delta
	_oy += _ovy * delta
	_oy = clampf(_oy, -0.12, 0.14)

	_look = _look.lerp(Vector2.ZERO, 1.0 - exp(-7.0 * delta))

func _apply_pose(delta: float) -> void:
	for i in 2:
		var pivot := _pivots[i]
		if pivot == null:
			continue
		var s := 1.0 if i == 0 else -1.0
		var ground := _ground_pose(s, i)
		var pos: Vector3 = ground[0]
		var rot: Vector3 = ground[1]
		var closed: float = ground[2]

		# airborne: hands trail the body
		pos.y += _oy
		rot.x += clampf(-vertical_speed * 1.2, -9.0, 9.0) * _w_air

		if _w_climb > 0.0:
			var cp := _climb_pose(s, i)
			var cpos: Vector3 = cp[0]
			var crot: Vector3 = cp[1]
			if climb_face_set:
				# The hands stay on the thing being climbed, whichever way you look. The pose above is made for a head
				# looking straight at the ladder (its +Z points away from the ship); here it is moved from that
				# ladder-facing frame (at the camera) into the camera's own frame.
				var want := Transform3D(climb_face, global_position) * Transform3D(Basis.from_euler(Vector3(deg_to_rad(crot.x), deg_to_rad(crot.y), deg_to_rad(crot.z))), cpos)
				var tl := global_transform.affine_inverse() * want
				cpos = tl.origin
				crot = tl.basis.get_euler() * (180.0 / PI)
			pos = pos.lerp(cpos, _w_climb)
			rot = Vector3(
				rad_to_deg(lerp_angle(deg_to_rad(rot.x), deg_to_rad(crot.x), _w_climb)),
				rad_to_deg(lerp_angle(deg_to_rad(rot.y), deg_to_rad(crot.y), _w_climb)),
				rad_to_deg(lerp_angle(deg_to_rad(rot.z), deg_to_rad(crot.z), _w_climb)))
			closed = lerpf(closed, cp[2], _w_climb)
		if _w_swim > 0.0:
			var sp := _swim_pose(s, i)
			pos = pos.lerp(sp[0], _w_swim)
			rot = rot.lerp(sp[1], _w_swim)
			closed = lerpf(closed, sp[2], _w_swim)

		var wh := _w_hold if i == 0 else _w_hold_l
		if wh > 0.0:
			# the hand reaches out and closes on what you're holding
			var hp := hold_point if i == 0 else hold_point_l
			pos = pos.lerp(to_local(hp) + _mirror_pos(hold_offset, s), wh)
			rot = rot.lerp(_mirror_rot(hold_rotation_deg, s), wh)
			closed = lerpf(closed, 1.0, wh)

		if _w_carry > 0.0:
			# both hands reach forward and grip the box's sides, low in the view
			var cp := carry_centre + Vector3(s * (carry_half + carry_squeeze), 0.0, 0.0)
			pos = pos.lerp(cp, _w_carry)
			rot = rot.lerp(_mirror_rot(carry_rotation_deg, s), _w_carry)
			closed = lerpf(closed, carry_grip, _w_carry)

		# trailing the camera when you look around
		pos.x += _look.x
		pos.y += _look.y
		rot.y += _look.x * 90.0
		rot.x += _look.y * 90.0

		pivot.position = pos
		pivot.rotation_degrees = rot
		if closed_override[i] >= 0.0:
			closed = closed_override[i]
		_closed[i] = lerpf(_closed[i], closed, 1.0 - exp(-14.0 * maxf(delta, 0.0))) if delta > 0.0 else closed
		if _meshes[i] and _shape_idx[i] >= 0:
			_meshes[i].set_blend_shape_value(_shape_idx[i], _closed[i])

func _mirror_rot(r: Vector3, s: float) -> Vector3:
	return Vector3(r.x, r.y * s, r.z * s)

func _mirror_pos(p: Vector3, s: float) -> Vector3:
	return Vector3(p.x * s, p.y, p.z)

## Standing / walking / running, plus a little idle breathing.
func _ground_pose(s: float, i: int) -> Array:
	var pos := _mirror_pos(rest_position, s)
	var rot := _mirror_rot(rest_rotation_deg, s)
	var ph := _walk_phase + (0.0 if i == 0 else PI)
	var a := _walk_amp
	pos.z += sin(ph) * swing_distance * a
	pos.y += sin(ph) * swing_lift * a + sin(2.0 * _walk_phase + 1.2) * bob_height * a
	pos.x += s * cos(ph) * side_sway * a
	rot.x += sin(ph) * 7.0 * a
	rot.z += s * cos(ph) * 4.0 * a
	# breathing / idle drift, slightly different per hand
	var t := _time + (0.0 if i == 0 else 1.7)
	pos.y += sin(t * 1.5) * 0.0035
	pos.x += s * sin(t * 0.9) * 0.003
	rot.x += sin(t * 1.1) * 1.2
	rot.z += s * sin(t * 0.8) * 1.0
	return [pos, rot, clampf(rest_closed + run_closed * _run_amp, 0.0, 1.0)]

## Reach up, grip, pull: each hand is fixed on a rung while you rise, so it slides down
## relative to the camera, then lets go and reaches for the next one.
func _climb_pose(s: float, i: int) -> Array:
	var c := fposmod(_climb_phase + (0.0 if i == 0 else 0.5), 1.0)
	var hi := _mirror_pos(climb_high, s)
	var lo := _mirror_pos(climb_low, s)
	var pos: Vector3
	var closed: float
	if c < grip_fraction:
		pos = hi.lerp(lo, c / grip_fraction)
		closed = 1.0
	else:
		var u := (c - grip_fraction) / (1.0 - grip_fraction)
		pos = lo.lerp(hi, smoothstep(0.0, 1.0, u))
		pos.z -= sin(u * PI) * 0.05
		closed = 1.0 - 0.7 * sin(u * PI)
	return [pos, _mirror_rot(climb_rotation_deg, s), closed]

## Paddle: each hand circles in the vertical plane, the two half a stroke apart.
func _swim_pose(s: float, i: int) -> Array:
	var ph := _swim_phase + (0.0 if i == 0 else PI)
	var pos := _mirror_pos(swim_position, s)
	var r := stroke_radius * _swim_amp
	pos.x += s * sin(ph) * r.x
	pos.y += sin(ph) * r.y
	pos.z += cos(ph) * r.z
	var rot := _mirror_rot(swim_rotation_deg, s)
	rot.x += cos(ph) * 14.0 * _swim_amp
	return [pos, rot, 0.0]
