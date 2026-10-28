class_name ShipRope
extends Node3D
## One working rope: a sail's furling / setting line, or a brace. Made by ShipSails.
##
## It is drawn as a real rope: from the sail (or the yardarm) up through a block, down the mast (or
## across the bulwark) to a belaying pin, then a tail hanging from the pin and, on the deck, a coil
## of whatever rope has been hauled in. Hold the left button on the tail and pull the mouse down to
## haul it (hands go hand over hand), move the mouse up to ease it out. Let go and the pin holds it.

enum { HAUL, BRACE }

const Outline := preload("res://scripts/interact_outline.gd")
const ROPE_RADIUS := 0.02
const SIDES := 5
const CYCLE := 0.5                  ## metres of rope per hand stroke
const COIL_RADIUS := 0.13

var sails: ShipSails
var kind := HAUL
var key := 0                        ## HAUL: index into sails.recs; BRACE: mast (0 fore, 1 main)
var side := 0                       ## BRACE: -1 port rope, +1 starboard rope
var label := ""
var pin := Vector3.ZERO             ## belaying pin, ship frame
var block := Vector3.ZERO           ## BRACE: the block the line runs through
var deck_y := 1.8
var travel := 2.5                   ## metres of rope between fully eased and fully hauled
var tail_hang := 0.8

var _mi: MeshInstance3D
var _mat: StandardMaterial3D
var _sig := ""
var _phase := 0.0
var _hand_pos := [Vector3.ZERO, Vector3.ZERO]
var _holding := false
var _hand_init := false
var _hands: Node

static var _tex: ImageTexture

func _ready() -> void:
	_mi = MeshInstance3D.new()
	_mi.name = "Strand"
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.extra_cull_margin = 4.0
	_mi.visibility_range_end = 90.0
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.78, 0.66, 0.44)
	_mat.albedo_texture = _twist_texture()
	_mat.roughness = 0.95
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mi.material_override = _mat
	add_child(_mi)
	refresh()

static func _twist_texture() -> ImageTexture:
	if _tex:
		return _tex
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			var t := float((x * 2 + y) % 16) / 16.0
			var c := 0.74 + 0.26 * (1.0 if t < 0.5 else 0.0)
			img.set_pixel(x, y, Color(c, c * 0.97, c * 0.92))
	img.generate_mipmaps()
	_tex = ImageTexture.create_from_image(img)
	return _tex

# ---------------------------------------------------------------- geometry

## Where the rope goes from the far end to the pin (ship frame).
func _span() -> PackedVector3Array:
	var pts := PackedVector3Array()
	if kind == HAUL:
		var r: ShipSails.SailRec = sails.recs[key]
		var mz: float = ShipSails.MAST_Z[r.mast]
		var down_x := pin.x * 0.35
		var aft := mz + 0.52
		pts.append(sails.anchor_ship(r))
		if r.kind == 0:
			var off := (float(r.level) - 1.0) * 0.12
			pts.append(sails.yard_point(r, Vector3(-off, -0.12, 0.92)))
			pts.append(Vector3(off, r.yard_y - 0.35, aft))
		elif r.id == "Jib":
			pts.append(sails.head_ship(r))
			pts.append(Vector3(0.0, 13.9, mz - 0.15))
			pts.append(Vector3(0.0, 13.5, aft))
		elif r.id == "Staysail":
			pts.append(sails.head_ship(r))
			pts.append(Vector3(0.0, 10.4, mz - 0.15))
			pts.append(Vector3(0.0, 10.0, aft))
		else:
			pts.append(Vector3(0.0, 10.6, mz + 0.1))
			pts.append(Vector3(0.0, 10.3, aft))
		pts.append(Vector3(pin.x * 0.2, 3.5, aft))
		pts.append(Vector3(down_x, 3.0, aft - 0.05).lerp(pin + Vector3(0, 0.12, 0), 0.5))
		pts.append(pin)
	else:
		var yr := sails.rec("Fore_0" if key == 0 else "Main_0")
		var tip := sails.yard_point(yr, Vector3(-5.1 * float(side), 0.0, 0.1))
		pts.append(tip)
		pts.append(block)
		pts.append(pin + Vector3(0, 0.1, 0))
		pts.append(pin)
	return pts

func _tail() -> PackedVector3Array:
	var pts := PackedVector3Array()
	var hang := minf(tail_hang, pin.y - deck_y - 0.15)
	var inward := -signf(pin.x) * 0.04 if kind == BRACE else 0.0
	var zoff := 0.05
	pts.append(pin)
	pts.append(pin + Vector3(inward * 0.5, -hang * 0.5, zoff * 0.6))
	pts.append(pin + Vector3(inward, -hang, zoff))
	return pts

## The excess rope lying on the deck: a few stacked turns, taking whatever has been hauled in.
func _coil(length: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var hang := minf(tail_hang, pin.y - deck_y - 0.15)
	var end := pin + Vector3(0, -hang, 0.05)
	var cdir := Vector3(0, 0, 1.0) if kind == HAUL else Vector3(-signf(pin.x) * 0.9, 0, 0.45).normalized()
	var centre := Vector3(pin.x, deck_y + 0.03, pin.z) + cdir * (0.16 + COIL_RADIUS)
	if kind == BRACE:
		centre = Vector3(pin.x, deck_y + 0.03, pin.z) + cdir * (0.22 + COIL_RADIUS)
	if length < 0.04:
		# nothing hauled: the tail just touches the deck
		pts.append(Vector3(end.x, deck_y + 0.03, end.z + 0.04))
		return pts
	pts.append(Vector3(end.x, deck_y + 0.18, end.z + 0.04))
	var first := centre + Vector3(COIL_RADIUS, 0.0, 0.0)
	first.y = deck_y + 0.03
	pts.append(first)
	var ang := 0.0
	var run := 0.0
	var r := COIL_RADIUS
	var y := deck_y + 0.03
	var step := 0.05
	var last := first
	while run < length:
		var dth := step / r
		ang += dth
		y = deck_y + 0.03 + 0.034 * (ang / TAU)
		var p := centre + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		p.y = y
		run += last.distance_to(p)
		last = p
		pts.append(p)
	return pts

func refresh() -> void:
	if sails == null:
		return
	var value := sails.rope_value(self)
	var sig := ""
	if kind == HAUL:
		var r: ShipSails.SailRec = sails.recs[key]
		sig = "%.4f|%.4f|%.3f" % [value, r.node.get_blend_shape_value(maxi(r.idx_furled, 0)) if r.idx_furled >= 0 else 0.0, deck_y]
		if r.yard:
			sig += "|%.4f" % r.yard.transform.basis.get_euler().y
		else:
			sig += "|%.3f" % r.node.transform.basis.get_euler().length()
	else:
		var yr := sails.rec("Fore_0" if key == 0 else "Main_0")
		sig = "%.4f|%.3f|%.4f" % [value, deck_y, yr.yard.transform.basis.get_euler().y]
	if sig == _sig:
		return
	_sig = sig
	var span := _span()
	var tail := _tail()
	var coil := _coil(travel * value)
	var all := PackedVector3Array()
	all.append_array(span)
	for i in range(1, tail.size()):
		all.append(tail[i])
	all.append_array(coil)
	_mi.mesh = _tube(all)

func _tube(pts: PackedVector3Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := pts.size()
	# drop duplicate points
	var clean := PackedVector3Array()
	for p in pts:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(p) > 0.004:
			clean.append(p)
	pts = clean
	n = pts.size()
	if n < 2:
		return null
	var normal := Vector3.UP
	var tan0 := (pts[1] - pts[0]).normalized()
	if absf(tan0.dot(normal)) > 0.95:
		normal = Vector3.RIGHT
	normal = (normal - tan0 * normal.dot(tan0)).normalized()
	var dist := 0.0
	for i in n:
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == n - 1:
			t = (pts[i] - pts[i - 1]).normalized()
		else:
			t = ((pts[i] - pts[i - 1]).normalized() + (pts[i + 1] - pts[i]).normalized())
			t = t.normalized() if t.length() > 0.001 else (pts[i + 1] - pts[i]).normalized()
		normal = normal - t * normal.dot(t)
		if normal.length() < 0.001:
			normal = t.cross(Vector3.UP)
			if normal.length() < 0.001:
				normal = t.cross(Vector3.RIGHT)
		normal = normal.normalized()
		var binorm := t.cross(normal)
		if i > 0:
			dist += pts[i].distance_to(pts[i - 1])
		for s in SIDES + 1:
			var a := TAU * float(s) / SIDES
			var dir := normal * cos(a) + binorm * sin(a)
			verts.append(pts[i] + dir * ROPE_RADIUS)
			norms.append(dir)
			uvs.append(Vector2(float(s) / SIDES, dist / 0.14))
	var ring := SIDES + 1
	for i in n - 1:
		for s in SIDES:
			var a := i * ring + s
			var b := a + ring
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

# ---------------------------------------------------------------- grabbing

## How far up the line above the pin you can take hold of it (0 = from just under the pin, 1 = all the way to the
## first block). A tall grab means you can look up along the rope and still get it.
@export var grab_up := 0.75

## The part of the rope you can take hold of (ship frame): the tail below the pin and the line rising from it.
func grab_segment() -> Array:
	var hang := minf(tail_hang, pin.y - deck_y - 0.15)
	var inward := -signf(pin.x) * 0.04 if kind == BRACE else 0.0
	var top := pin + Vector3(0.0, -0.12, 0.04)
	if sails != null and grab_up > 0.0:
		if kind == HAUL:
			var r: ShipSails.SailRec = sails.recs[key]
			var mz: float = ShipSails.MAST_Z[r.mast]
			# the line runs up from the pin to this point (see _span)
			top = pin.lerp(Vector3(pin.x * 0.2, 3.5, mz + 0.52), grab_up)
		else:
			top = pin.lerp(block, grab_up)
	var b := pin + Vector3(inward, -hang + 0.06, 0.05)
	return [top, b]

func grab_segment_world() -> Array:
	var s := grab_segment()
	var xf := sails.ship.global_transform
	return [xf * (s[0] as Vector3), xf * (s[1] as Vector3)]

func set_highlight(on: bool) -> void:
	_mi.material_overlay = Outline.material() if on else null

func too_far(cam: Camera3D) -> bool:
	var seg := grab_segment_world()
	var mid: Vector3 = (seg[0] + seg[1]) * 0.5
	return cam.global_position.distance_to(mid) > 3.4

func begin_hold(cam: Camera3D) -> void:
	_holding = true
	_hand_init = false
	_hands = sails._hands
	_phase = 0.0
	# first grip: where you're looking
	_update_hands(0.0)

func end_hold() -> void:
	_holding = false
	if _hands and is_instance_valid(_hands):
		_hands.set("hold_active", false)
		_hands.set("hold_active_l", false)
		_hands.set("closed_override", [-1.0, -1.0])
	set_highlight(false)

## Mouse moved rel_y pixels (+ = down): haul or ease.
func drag(rel_y: float, pixels_per_metre: float) -> void:
	var m := rel_y / pixels_per_metre
	if m > 0.0:
		var load := sails.rope_load(self)
		m /= (1.0 + sails.load_effort * load)
	var moved := sails.rope_move(self, m)
	_phase += moved / CYCLE

func _update_hands(delta: float) -> void:
	if not _holding or _hands == null or not is_instance_valid(_hands):
		return
	var seg := grab_segment_world()
	var top: Vector3 = seg[0]
	var bot: Vector3 = seg[1]
	var closed := [1.0, 1.0]
	for i in 2:
		var g := fposmod(_phase + 0.5 * float(i), 1.0)
		var target := top.lerp(bot, g)
		if not _hand_init:
			_hand_pos[i] = target
		else:
			_hand_pos[i] = _hand_pos[i].lerp(target, 1.0 - exp(-22.0 * maxf(delta, 0.016)))
		closed[i] = 1.0 if g < 0.82 else 0.4
	_hand_init = true
	_hands.set("hold_active", true)
	_hands.set("hold_point", _hand_pos[0])
	_hands.set("hold_active_l", true)
	_hands.set("hold_point_l", _hand_pos[1])
	_hands.set("closed_override", closed)

func _process(delta: float) -> void:
	_update_hands(delta)
