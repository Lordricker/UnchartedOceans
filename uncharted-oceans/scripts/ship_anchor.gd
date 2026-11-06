class_name ShipAnchor
extends Node
## The anchor, the capstan that works it, and the creep through a harbour. Created by ship_motion.gd (anchor_enabled).
##
## The brig has no separate capstan in the model: the capstan and the coil of hemp beside it are part of the merged
## DeckFittings mesh. At startup this cuts those triangles out into their own meshes (the model file is not touched),
## so the capstan can turn, be outlined and be clicked, and gives the capstan a collision so you cannot walk through it.
##
##  - Click the capstan (or the coil of cable beside it; both are outlined in white) to let go the anchor. Four short
##    capstan bars are shipped in the head while the anchor is down, and the head turns as the cable runs out.
##  - Click again to weigh anchor: the crew heave round the capstan (the head turns slowly) and the anchor comes away.
##  - While it is down (and while it is running out or coming up) the ship does not move: no way, no leeway, no turn.
##    Letting go while she has way on brings her up over a few seconds. The sails can stay set; she just heels.
##    No anchoring in water too deep for the cable (max_depth_m, from the chart's seabed).
##  - Inside a harbour (WorldStreamer.harbor_at, a radius round each port) a ship with every sail hauled up (furled) and
##    the anchor up never drops below creep_knots ahead (the boats and sweeps tow her). A minimum, not a cap. With any
##    sail set she is the wind's, as usual: a headwind pushes her back. Not while moored or aground.
## Sleeping with the anchor down (or moored) keeps the ship where she is (WorldStreamer.sleep_speed).
## Not modelled yet: swinging round the anchor to the wind, dragging in a gale, a visible anchor and cable.

const Outline := preload("res://scripts/interact_outline.gd")
const KNOT := 0.514444

enum State { UP, LOWERING, DOWN, RAISING }

## How far you can reach the capstan (m), and the radius of the cylinder you click on (the capstan itself is a bit wider
## at the foot and the head).
@export var reach := 2.4
@export var click_radius := 0.38
## Seconds for the cable to run out, and to heave the anchor up.
@export var drop_time := 4.0
@export var weigh_time := 9.0
## Deepest water she can anchor in (m). 0 = anywhere.
@export var max_depth_m := 70.0
## Least speed with the sails hauled up (furled) inside a harbour (knots).
@export var creep_knots := 1.0
## With no world chart (the test scene), the island's cove counts as a harbour inside this distance (m).
@export var island_harbor_m := 220.0
## Capstan bars: how many, how far they reach from the axis, and how far below the top of the capstan they sit.
@export var bar_count := 4
@export var bar_reach := 1.0
@export var bar_below_top := 0.21
## Where the capstan's axis stands on the deck, in the ship's frame (base of the capstan), and the triangles round it.
@export var capstan_pos := Vector3(0.0, 1.72, 3.6)
@export var capstan_radius := 0.56
## The coil of hemp beside it (centre) and how far its triangles lie from that.
@export var coil_pos := Vector3(-0.55, 1.73, 2.835)
@export var coil_radius := 0.38
@export var fittings_name := "DeckFittings"

var state := State.UP
var in_harbour := false
var harbour_id := ""
var creeping := false
var message := ""

var _ship: Node3D
var _axis: Node3D                   # the capstan's axis on the deck (does not turn)
var _spin: Node3D                   # turns: the capstan and its bars
var _bars: Node3D
var _cap_mi: MeshInstance3D
var _coil_mi: MeshInstance3D
var _body: AnimatableBody3D
var _cap_h := 1.16                  # height of the capstan above its axis point (click cylinder)
var _coil_r := 0.32                 # radius of the cable coil (click disc)
var _t := 0.0                       # 0..1 through the lowering or raising
var _zone_t := 0.0
var _msg_t := 0.0
var _outlined := false
var _cam: Camera3D
var _player: Node
var _label: Label
var _prompt := ""


func _ready() -> void:
	add_to_group("ship_anchor")
	_ship = get_parent() as Node3D
	var ad: Dictionary = ShipClasses.data(_ship_class()).get("anchor", {})
	for k in ad.keys():
		set(k, ad[k])
	_make_label()
	_build()


## True while the anchor is down, running out or coming up: the ship is held where she is.
func holds_ship() -> bool:
	return state != State.UP


# ------------------------------------------------------------------ building the capstan

func _build() -> void:
	var fit := _ship.find_child(fittings_name, true, false) as MeshInstance3D
	if fit == null or fit.mesh == null:
		push_warning("ShipAnchor: no %s mesh in the ship; no capstan to click (the harbour creep still works)" % fittings_name)
		return
	var info := _carve(fit)
	if info.is_empty():
		return
	_make_bars(info["cap_aabb"])
	_make_body(info)


## Which part a triangle belongs to by where its centre lies (ship frame): 1 the capstan, 2 the coil, 0 neither.
func _region(m: Vector3) -> int:
	if m.y > capstan_pos.y - 0.04 and m.y < capstan_pos.y + 1.3 \
			and Vector2(m.x - capstan_pos.x, m.z - capstan_pos.z).length() < capstan_radius:
		return 1
	if m.y > coil_pos.y - 0.1 and m.y < coil_pos.y + 0.25 \
			and Vector2(m.x - coil_pos.x, m.z - coil_pos.z).length() < coil_radius:
		return 2
	return 0


## Cut the capstan and the coil out of the fittings mesh into their own meshes. Returns {} if nothing was found.
func _carve(fit: MeshInstance3D) -> Dictionary:
	var src: Mesh = fit.mesh
	var to_ship := _ship.global_transform.affine_inverse() * fit.global_transform
	var surf_n := src.get_surface_count()
	var arrs: Array = []
	var mats: Array = []
	var keeps: Array = []
	var caps: Array = []
	var coils: Array = []
	var n_cap := 0
	var n_coil := 0
	var coil_sum := Vector3.ZERO
	var coil_low := 1.0e9
	for s in surf_n:
		var arr: Array = src.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx := PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] is PackedInt32Array and (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
			idx = arr[Mesh.ARRAY_INDEX]
		else:
			idx.resize(v.size())
			for i in v.size():
				idx[i] = i
		var keep := PackedInt32Array()
		var cap := PackedInt32Array()
		var coil := PackedInt32Array()
		for t in range(0, idx.size() - 2, 3):
			var pa: Vector3 = to_ship * v[idx[t]]
			var pb: Vector3 = to_ship * v[idx[t + 1]]
			var pc: Vector3 = to_ship * v[idx[t + 2]]
			var mid := (pa + pb + pc) / 3.0
			var which := _region(mid)
			if which == 1:
				cap.append(idx[t])
				cap.append(idx[t + 1])
				cap.append(idx[t + 2])
				n_cap += 1
			elif which == 2:
				coil.append(idx[t])
				coil.append(idx[t + 1])
				coil.append(idx[t + 2])
				n_coil += 1
				coil_sum += mid
				coil_low = minf(coil_low, minf(pa.y, minf(pb.y, pc.y)))
			else:
				keep.append(idx[t])
				keep.append(idx[t + 1])
				keep.append(idx[t + 2])
		arrs.append(arr)
		mats.append(fit.get_active_material(s))
		keeps.append(keep)
		caps.append(cap)
		coils.append(coil)
	if n_cap == 0:
		push_warning("ShipAnchor: no capstan triangles near %s in %s; nothing to click (check capstan_pos)" % [capstan_pos, fittings_name])
		return {}
	if n_coil == 0:
		push_warning("ShipAnchor: no coil of cable near %s in %s (check coil_pos); the capstan alone is the anchor control" % [coil_pos, fittings_name])
	var coil_c := coil_pos
	if n_coil > 0:
		coil_c = Vector3(coil_sum.x / float(n_coil), coil_low, coil_sum.z / float(n_coil))
	var keep_mesh := ArrayMesh.new()
	var cap_mesh := ArrayMesh.new()
	var coil_mesh := ArrayMesh.new()
	for s in surf_n:
		var arr: Array = arrs[s]
		var mat: Material = mats[s]
		var base: Array = arr.duplicate()
		var keep: PackedInt32Array = keeps[s]
		if keep.size() == 0:
			keep = PackedInt32Array([0, 0, 0])       # a surface may not be empty; this one triangle has no area
		base[Mesh.ARRAY_INDEX] = keep
		keep_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base)
		if mat != null:
			keep_mesh.surface_set_material(keep_mesh.get_surface_count() - 1, mat)
		var cap: PackedInt32Array = caps[s]
		if cap.size() > 0:
			cap_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _piece(arr, cap, to_ship, capstan_pos))
			if mat != null:
				cap_mesh.surface_set_material(cap_mesh.get_surface_count() - 1, mat)
		var coil: PackedInt32Array = coils[s]
		if coil.size() > 0:
			coil_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _piece(arr, coil, to_ship, coil_c))
			if mat != null:
				coil_mesh.surface_set_material(coil_mesh.get_surface_count() - 1, mat)
	fit.mesh = keep_mesh
	# the capstan: an axis fixed on the deck, a spinning part on it
	_axis = Node3D.new()
	_axis.name = "CapstanAxis"
	_axis.position = capstan_pos
	_ship.add_child(_axis)
	_spin = Node3D.new()
	_spin.name = "CapstanSpin"
	_axis.add_child(_spin)
	_cap_mi = MeshInstance3D.new()
	_cap_mi.name = "Capstan"
	_cap_mi.mesh = cap_mesh
	_spin.add_child(_cap_mi)
	var cap_aabb := cap_mesh.get_aabb()
	_cap_h = cap_aabb.end.y
	if n_coil > 0:
		_coil_mi = MeshInstance3D.new()
		_coil_mi.name = "CableCoil"
		_coil_mi.mesh = coil_mesh
		_coil_mi.position = coil_c
		_ship.add_child(_coil_mi)
		var cab := coil_mesh.get_aabb()
		_coil_r = maxf(cab.size.x, cab.size.z) * 0.5
	return {"cap_aabb": cap_aabb, "coil_c": coil_c, "has_coil": n_coil > 0, "coil_aabb": coil_mesh.get_aabb()}


## The arrays of a piece cut from a surface: only the vertices its triangles use, moved into the ship's frame and
## then relative to `origin`.
func _piece(arr: Array, tris: PackedInt32Array, to_ship: Transform3D, origin: Vector3) -> Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm_a := PackedVector3Array()
	if arr[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		nrm_a = arr[Mesh.ARRAY_NORMAL]
	var uv_a := PackedVector2Array()
	if arr[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
		uv_a = arr[Mesh.ARRAY_TEX_UV]
	var uv2_a := PackedVector2Array()
	if arr[Mesh.ARRAY_TEX_UV2] is PackedVector2Array:
		uv2_a = arr[Mesh.ARRAY_TEX_UV2]
	var col_a := PackedColorArray()
	if arr[Mesh.ARRAY_COLOR] is PackedColorArray:
		col_a = arr[Mesh.ARRAY_COLOR]
	var tan_a := PackedFloat32Array()
	if arr[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
		tan_a = arr[Mesh.ARRAY_TANGENT]
	var has_n := nrm_a.size() == v.size()
	var has_uv := uv_a.size() == v.size()
	var has_uv2 := uv2_a.size() == v.size()
	var has_col := col_a.size() == v.size()
	var has_tan := tan_a.size() == v.size() * 4
	var nb := to_ship.basis.inverse().transposed()
	var remap := {}
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ou := PackedVector2Array()
	var ou2 := PackedVector2Array()
	var oc := PackedColorArray()
	var ot := PackedFloat32Array()
	var oi := PackedInt32Array()
	for i in tris:
		var j: int
		if remap.has(i):
			j = remap[i]
		else:
			j = ov.size()
			remap[i] = j
			ov.append(to_ship * v[i] - origin)
			if has_n:
				on.append((nb * nrm_a[i]).normalized())
			if has_uv:
				ou.append(uv_a[i])
			if has_uv2:
				ou2.append(uv2_a[i])
			if has_col:
				oc.append(col_a[i])
			if has_tan:
				var tv: Vector3 = to_ship.basis * Vector3(tan_a[i * 4], tan_a[i * 4 + 1], tan_a[i * 4 + 2])
				tv = tv.normalized()
				ot.append(tv.x)
				ot.append(tv.y)
				ot.append(tv.z)
				ot.append(tan_a[i * 4 + 3])
		oi.append(j)
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = ov
	if has_n:
		out[Mesh.ARRAY_NORMAL] = on
	if has_tan:
		out[Mesh.ARRAY_TANGENT] = ot
	if has_col:
		out[Mesh.ARRAY_COLOR] = oc
	if has_uv:
		out[Mesh.ARRAY_TEX_UV] = ou
	if has_uv2:
		out[Mesh.ARRAY_TEX_UV2] = ou2
	out[Mesh.ARRAY_INDEX] = oi
	return out


## The capstan bars: short wooden spars run out of the sockets in the capstan head, shown while the anchor is down.
func _make_bars(cap_aabb: AABB) -> void:
	_bars = Node3D.new()
	_bars.name = "CapstanBars"
	_bars.visible = false
	_spin.add_child(_bars)
	var bar_y := cap_aabb.end.y - bar_below_top
	var start := 0.30                                   # inside the head, hidden
	var length := maxf(bar_reach - start, 0.2)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.40, 0.28, 0.17)
	wood.roughness = 0.9
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = length
	cyl.radial_segments = 6
	cyl.rings = 1
	cyl.material = wood
	for i in bar_count:
		var ang := TAU * float(i) / float(maxi(bar_count, 1)) + PI * 0.25
		var yaw := Basis(Vector3.UP, ang)
		var mi := MeshInstance3D.new()
		mi.name = "Bar%d" % i
		mi.mesh = cyl
		mi.transform = Transform3D(yaw * Basis(Vector3.BACK, PI * 0.5), yaw * Vector3(start + length * 0.5, bar_y, 0.0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bars.add_child(mi)


## Solid capstan: a body on the deck's layer that rides with the ship like the deck bodies do. (The coil of cable is a
## flat disc 2 cm thick lying on the planking, so it stays walk-over; it is only there to be clicked.)
func _make_body(info: Dictionary) -> void:
	_body = AnimatableBody3D.new()
	_body.name = "AnchorBody"
	_body.sync_to_physics = false
	_body.collision_layer = 1
	_body.collision_mask = 0
	_ship.add_child(_body)
	var cap_aabb: AABB = info["cap_aabb"]
	# start just above the planking: the flood grid reads the deck layer only below y = 1.6
	var y0 := capstan_pos.y + 0.06
	var y1 := capstan_pos.y + cap_aabb.end.y
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.5
	cyl.height = maxf(y1 - y0, 0.3)
	cs.shape = cyl
	cs.position = Vector3(capstan_pos.x, (y0 + y1) * 0.5, capstan_pos.z)
	_body.add_child(cs)


# ------------------------------------------------------------------ aiming and clicking

func _camera() -> Camera3D:
	if _cam == null or not is_instance_valid(_cam):
		_player = get_tree().get_first_node_in_group("player")
		if _player:
			_cam = _player.get_node_or_null("Head/Camera3D") as Camera3D
	return _cam


## Distance along the view ray to a vertical cylinder (radius, from y0 to y1 in the frame xf), or INF if it is missed
## or farther than reach.
func _cyl_dist(xf: Transform3D, o: Vector3, d: Vector3, radius: float, y0: float, y1: float) -> float:
	var inv := xf.affine_inverse()
	var lo: Vector3 = inv * o
	var ld: Vector3 = (inv.basis * d).normalized()
	var scale_k: float = (inv.basis * d).length()          # local distance per world metre along d
	var best := INF
	var a: float = ld.x * ld.x + ld.z * ld.z
	if a > 0.00000001:
		var b: float = 2.0 * (lo.x * ld.x + lo.z * ld.z)
		var c: float = lo.x * lo.x + lo.z * lo.z - radius * radius
		var disc: float = b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq: float = sqrt(disc)
			for k in 2:
				var t: float = (-b - sq) / (2.0 * a) if k == 0 else (-b + sq) / (2.0 * a)
				if t >= 0.0:
					var y: float = lo.y + ld.y * t
					if y >= y0 and y <= y1:
						best = minf(best, t)
	if absf(ld.y) > 0.000001:
		for k in 2:
			var yc: float = y0 if k == 0 else y1
			var t2: float = (yc - lo.y) / ld.y
			if t2 >= 0.0:
				var px: float = lo.x + ld.x * t2
				var pz: float = lo.z + ld.z * t2
				if px * px + pz * pz <= radius * radius:
					best = minf(best, t2)
	if best == INF:
		return INF
	var dist: float = best / maxf(scale_k, 0.000001)
	return dist if dist <= reach else INF


## How far along the view ray the sails' rope you are aiming at is (INF if none): a rope in front of the capstan wins.
func _rope_dist(o: Vector3, d: Vector3) -> float:
	var sl = _ship.get("sails")
	if sl == null or not sl.has_method("aimed_rope"):
		return INF
	var rope = sl.aimed_rope()
	if rope == null:
		return INF
	var seg: Array = rope.grab_segment_world()
	var cp: PackedVector3Array = Geometry3D.get_closest_points_between_segments(o, o + d * 3.0, seg[0], seg[1])
	return o.distance_to(cp[0])


## True while you look at the capstan (a slim cylinder) or the coil (a flat disc) from within reach with the mouse
## captured, and no sail rope is nearer the crosshair.
func _aimed() -> bool:
	if _axis == null:
		return false
	var cam := _camera()
	if cam == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if bool(_player.get("input_locked")) or bool(_player.get_meta("grab_busy", false)):
		return false
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var hit := _cyl_dist(_axis.global_transform, o, d, click_radius, 0.0, _cap_h)
	if _coil_mi != null:
		hit = minf(hit, _cyl_dist(_coil_mi.global_transform, o, d, _coil_r, -0.03, 0.06))
	if hit == INF:
		return false
	return hit < _rope_dist(o, d)


func _input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed):
		return
	if _axis == null or not _aimed():
		return
	get_viewport().set_input_as_handled()            # no hole punching
	toggle()


func toggle() -> void:
	match state:
		State.UP:
			_lower()
		State.DOWN:
			_raise()
		State.LOWERING:
			_say("The cable is still running out")
		State.RAISING:
			_say("Still heaving in")


func _lower() -> void:
	var hb := _harbor()
	if hb != null and bool(hb.get("moored")):
		_say("She is made fast to the pier")
		return
	var depth := _water_depth()
	if max_depth_m > 0.0 and depth > max_depth_m:
		_say("No bottom to be had here (%d m of water)" % roundi(depth))
		return
	state = State.LOWERING
	_t = 0.0
	if _bars != null:
		_bars.visible = true
	_say("Letting go the anchor")


func _raise() -> void:
	state = State.RAISING
	_t = 0.0
	_say("Heaving up the anchor")


func _say(text: String, seconds := 3.0) -> void:
	message = text
	_msg_t = seconds


# ------------------------------------------------------------------ per tick

func _harbor() -> Node:
	return _ship.get_node_or_null("ShipHarbor")


func _model() -> SailModel:
	var s = _ship.get("sails")
	return s.model if s != null else null


func _water_depth() -> float:
	var st := get_tree().get_first_node_in_group("world_streamer")
	if st != null and st.has_method("ship_depth_m"):
		return float(st.ship_depth_m())
	return 0.0


func _refresh_zone() -> void:
	in_harbour = false
	harbour_id = ""
	var st := get_tree().get_first_node_in_group("world_streamer")
	if st != null and st.has_method("harbor_at"):
		var h: Dictionary = st.harbor_at(float(st.ship_cx()), float(st.ship_cz()))
		if not h.is_empty():
			in_harbour = true
			harbour_id = String(h["id"])
		return
	# no world chart (the test scene): the island's cove
	var isl := get_tree().get_first_node_in_group("islands") as Island
	if isl != null and isl.harbor and isl.global_position.distance_to(_ship.global_position) <= island_harbor_m:
		in_harbour = true
		harbour_id = "cove"


## Runs after the sails have stepped this tick (it was added right after them), so what it sets is what the ship
## moves with on the next tick.
func _physics_process(delta: float) -> void:
	if _ship == null:
		return
	_msg_t = maxf(_msg_t - delta, 0.0)
	_zone_t -= delta
	if _zone_t <= 0.0:
		_zone_t = 0.25
		_refresh_zone()
	_advance(delta)
	var m := _model()
	if m == null:
		return
	match state:
		State.UP:
			_creep(m)
		State.LOWERING:
			creeping = false
			_drag(m, delta, lerpf(0.4, 2.5, clampf(_t, 0.0, 1.0)))
		_:
			creeping = false
			m.v_f = 0.0
			m.v_s = 0.0
			m.yaw_rate = 0.0


func _advance(delta: float) -> void:
	if state == State.LOWERING:
		_t += delta / maxf(drop_time, 0.1)
		if _t >= 1.0:
			state = State.DOWN
			_t = 0.0
			_say("The anchor bites")
	elif state == State.RAISING:
		_t += delta / maxf(weigh_time, 0.1)
		if _t >= 1.0:
			state = State.UP
			_t = 0.0
			if _bars != null:
				_bars.visible = false
			_say("Anchor aweigh")


## Way coming off as the anchor takes hold (rate in 1/s).
func _drag(m: SailModel, delta: float, rate: float) -> void:
	var f := exp(-rate * delta)
	m.v_f *= f
	m.v_s *= f
	m.yaw_rate *= f


## Inside a harbour, with any sail set, she never goes slower than creep_knots ahead.
func _creep(m: SailModel) -> void:
	creeping = false
	if not in_harbour or creep_knots <= 0.0:
		return
	var hb := _harbor()
	if hb != null and (bool(hb.get("moored")) or bool(hb.get("aground"))):
		return
	# sails hauled up (furled) = the boats and sweeps take her along; with any sail set she is the wind's, as usual
	for s in m.sails:
		if s.set_frac > 0.1:
			return
	creeping = true
	m.v_f = maxf(m.v_f, creep_knots * KNOT)


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if _spin != null:
		var w := 0.0
		if state == State.LOWERING:
			w = lerpf(-3.2, -0.4, clampf(_t, 0.0, 1.0))      # the cable runs out and the head spins, slowing
		elif state == State.RAISING:
			w = 0.8                                            # heaved round steadily
		if w != 0.0:
			_spin.rotation.y = wrapf(_spin.rotation.y + w * delta, -PI, PI)
	var want := _aimed()
	if want != _outlined:
		_outlined = want
		if _spin != null:
			Outline.set_on(_spin, want)
		if _coil_mi != null:
			Outline.set_on(_coil_mi, want)
	_update_label()


# ------------------------------------------------------------------ text

func _make_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.offset_top = 66.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1, 0.97, 0.9))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_label)


func _update_label() -> void:
	# only the short event messages show on their own; the prompt under the crosshair is for H (debug)
	var text := ""
	if _msg_t > 0.0:
		text = message
	elif _outlined and Engine.get_meta("debug_ui", false):
		match state:
			State.UP:
				text = "Click: let go the anchor"
			State.DOWN:
				text = "Click: weigh anchor"
			State.LOWERING:
				text = "The cable is running out..."
			State.RAISING:
				text = "Heaving in..."
	if text != _prompt:
		_prompt = text
		_label.text = text


## A line for the H readout.
func status_text() -> String:
	var names: Array[String] = ["up", "running out", "DOWN - holding her", "heaving in"]
	var s: String = "anchor: " + names[state]
	if in_harbour:
		s += "   in the harbour (%s)" % harbour_id
		if creeping:
			s += ", creeping at %.1f kn" % creep_knots
	return s

## The ship's size class (ShipClasses.Size), for the class's own numbers.
func _ship_class() -> int:
	var c = _ship.get("ship_class")
	return int(c) if c != null else ShipClasses.Size.MEDIUM
