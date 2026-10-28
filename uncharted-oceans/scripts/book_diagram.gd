extends Control
## A diagram drawn in code on a page of a book (no pictures to import). Made by book_reader.gd for a line
## "@diagram name | Title" in a chapter.
##
##   profile  the brig seen from the side, bow to the left
##   decks    the brig seen from above, bow up, port (left hand) on the left
##   sails    the sail plan, every sail numbered, with a key under it
##
## Everything is drawn on a 436 x 600 sheet and scaled to fit the control. Ship numbers are metres in the model's
## frame: y along the ship (the bow is at -y), z up from the waterline, x across the ship (starboard +).

const SHEET := Vector2(436.0, 600.0)
const HW_Y := [-9.5, -8.0, -6.0, -4.0, -1.0, 3.0, 6.0, 8.0, 9.0]
const HW_X := [0.0, 1.0, 2.0, 2.7, 3.1, 3.1, 2.8, 2.1, 1.7]

var kind := "profile"
var ink := Color(0.17, 0.11, 0.07)
var font: Font
var label_size := 21

var _o := Vector2.ZERO
var _s := 14.0

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	if font == null:
		return
	var k := minf(size.x / SHEET.x, size.y / SHEET.y)
	if k <= 0.0:
		return
	draw_set_transform(Vector2((size.x - SHEET.x * k) * 0.5, 0.0), 0.0, Vector2(k, k))
	match kind:
		"profile":
			_profile()
		"decks":
			_decks()
		"sails":
			_sails()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------------------------------------------------------------- helpers

func _ln(a: Vector2, b: Vector2, w := 2.0) -> void:
	draw_line(a, b, ink, w, true)

func _outline(pts: PackedVector2Array, w := 2.0, fill := Color(0, 0, 0, 0)) -> void:
	if fill.a > 0.0:
		draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, ink, w, true)

func _txt(at: Vector2, s: String, align := 0, size_px := -1) -> void:
	var sz := label_size if size_px < 0 else size_px
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var x := at.x
	if align == 1:
		x -= w * 0.5
	elif align == 2:
		x -= w
	draw_string(font, Vector2(x, at.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, ink)

## A name with a thin leader line to the part. align 0: text starts at "at"; 2: text ends at "at"; 1: centred.
## "\n" in the text starts another line under the first.
func _tag(anchor: Vector2, at: Vector2, s: String, align := 0) -> void:
	var end_x := at.x - 3.0 if align == 0 else (at.x + 3.0 if align == 2 else at.x)
	draw_line(anchor, Vector2(end_x, at.y - 6.0), ink.lightened(0.2), 1.3, true)
	draw_circle(anchor, 2.6, ink)
	var lines := s.split("\n")
	for i in lines.size():
		_txt(at + Vector2(0.0, label_size * i), lines[i], align)

func _pp(y: float, z: float) -> Vector2:          # side view
	return Vector2(_o.x + y * _s, _o.y - z * _s)

func _dd(x: float, y: float) -> Vector2:          # plan view
	return Vector2(_o.x + x * _s, _o.y + y * _s)

func _hw(y: float) -> float:
	if y <= float(HW_Y[0]):
		return float(HW_X[0])
	for i in range(1, HW_Y.size()):
		if y <= float(HW_Y[i]):
			var t := (y - float(HW_Y[i - 1])) / (float(HW_Y[i]) - float(HW_Y[i - 1]))
			return lerpf(float(HW_X[i - 1]), float(HW_X[i]), t)
	return float(HW_X[HW_X.size() - 1])

func _disc(c: Vector2, r: float) -> void:
	draw_circle(c, r, Color(ink.r, ink.g, ink.b, 0.25))
	draw_arc(c, r, 0.0, TAU, 24, ink, 2.0, true)

func _hull_side() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p: Vector2 in [Vector2(-9.5, 2.7), Vector2(-9.2, 0.9), Vector2(-8.0, -0.9), Vector2(-5.0, -2.0),
			Vector2(-1.0, -2.3), Vector2(4.0, -2.1), Vector2(7.5, -1.3), Vector2(9.0, 0.3), Vector2(9.0, 2.8),
			Vector2(7.0, 2.2), Vector2(4.0, 1.8), Vector2(0.0, 1.6), Vector2(-4.0, 1.9), Vector2(-7.5, 2.3)]:
		pts.append(_pp(p.x, p.y))
	return pts

func _masts() -> void:
	for m: Vector2 in [Vector2(-4.3, 14.0), Vector2(1.6, 15.0)]:
		_ln(_pp(m.x, 1.6), _pp(m.x, m.y * 0.62), 4.5)
		_ln(_pp(m.x, m.y * 0.62), _pp(m.x, m.y), 2.6)

# ---------------------------------------------------------------- the profile

func _profile() -> void:
	_s = 14.0
	_o = Vector2(SHEET.x * 0.5 + 4.75 * _s, 345.0)
	# the sea
	draw_dashed_line(_pp(-20.0, 0.0), _pp(10.8, 0.0), ink.lightened(0.15), 1.6, 7.0)
	# hull
	_outline(_hull_side(), 2.6, Color(ink.r, ink.g, ink.b, 0.14))
	# gun ports
	for gy: float in [-2.2, -0.4, 4.0]:
		draw_rect(Rect2(_pp(gy - 0.3, 1.45), Vector2(0.6 * _s, 0.5 * _s)), ink, false, 1.8)
	# poop deck and cabin front
	_ln(_pp(5.2, 3.875), _pp(9.0, 3.875), 3.0)
	_ln(_pp(5.2, 1.78), _pp(5.2, 3.875), 2.4)
	for py: float in [5.2, 6.6, 8.0, 9.0]:
		_ln(_pp(py, 3.875), _pp(py, 4.75), 1.6)
	_ln(_pp(5.2, 4.75), _pp(9.0, 4.75), 1.6)
	# rudder
	_outline(PackedVector2Array([_pp(9.0, 1.4), _pp(9.5, 1.0), _pp(9.5, -1.8), _pp(9.0, -1.8)]), 2.0,
			Color(ink.r, ink.g, ink.b, 0.3))
	# wheel
	var wc := _pp(6.7, 4.9)
	draw_arc(wc, 0.55 * _s, 0.0, TAU, 20, ink, 2.0, true)
	_ln(wc - Vector2(0.55 * _s, 0.0), wc + Vector2(0.55 * _s, 0.0), 1.4)
	_ln(wc - Vector2(0.0, 0.55 * _s), wc + Vector2(0.0, 0.55 * _s), 1.4)
	# bowsprit and jib boom, stays
	_ln(_pp(-9.0, 2.4), _pp(-14.0, 4.1), 4.4)
	_ln(_pp(-14.0, 4.1), _pp(-17.8, 5.5), 2.6)
	_ln(_pp(-4.3, 14.0), _pp(-17.8, 5.5), 1.1)
	_ln(_pp(-4.3, 14.0), _pp(1.6, 12.0), 1.1)
	_ln(_pp(1.6, 15.0), _pp(9.0, 5.5), 1.1)
	# masts, and the yards (seen end on, so only a short bar each)
	_masts()
	for m: Vector2 in [Vector2(-4.3, 14.0), Vector2(1.6, 15.0)]:
		for f: float in [0.40, 0.78, 0.95]:
			var yc := _pp(m.x, m.y * f)
			_ln(yc - Vector2(0.9 * _s * (1.0 - f * 0.5), 0.0), yc + Vector2(0.9 * _s * (1.0 - f * 0.5), 0.0), 3.0)
	# lookout barrel
	var bc := _pp(1.6, 9.3)
	_outline(PackedVector2Array([bc + Vector2(-0.6 * _s, -0.4 * _s), bc + Vector2(0.6 * _s, -0.4 * _s),
			bc + Vector2(0.45 * _s, 0.5 * _s), bc + Vector2(-0.45 * _s, 0.5 * _s)]), 2.0, Color(ink.r, ink.g, ink.b, 0.3))
	# flags
	_ln(_pp(9.0, 2.8), _pp(9.0, 6.6), 2.0)
	_outline(PackedVector2Array([_pp(9.0, 6.6), _pp(10.4, 6.4), _pp(10.4, 5.4), _pp(9.0, 5.4)]), 1.6,
			Color(ink.r, ink.g, ink.b, 0.3))
	_outline(PackedVector2Array([_pp(1.6, 15.0), _pp(4.0, 14.8), _pp(1.6, 14.5)]), 1.4, Color(ink.r, ink.g, ink.b, 0.3))
	# names, above
	_tag(_pp(-17.2, 5.3), Vector2(6.0, 30.0), "Jib boom", 0)
	_tag(_pp(-12.0, 3.5), Vector2(6.0, 58.0), "Bowsprit", 0)
	_tag(_pp(-4.3, 11.5), Vector2(6.0, 86.0), "Foremast", 0)
	_tag(_pp(9.7, 5.9), Vector2(SHEET.x - 6.0, 30.0), "Ensign", 2)
	_tag(_pp(1.6, 12.0), Vector2(SHEET.x - 6.0, 58.0), "Mainmast", 2)
	_tag(_pp(2.1, 9.2), Vector2(SHEET.x - 6.0, 86.0), "Lookout barrel", 2)
	_tag(_pp(6.9, 5.3), Vector2(SHEET.x - 6.0, 114.0), "Wheel", 2)
	_tag(_pp(1.6, 0.4 * 15.0), Vector2(SHEET.x - 6.0, 142.0), "Yards: course,\ntopsail, topgallant", 2)
	# names, below
	_tag(_pp(-13.0, 0.0), Vector2(6.0, 430.0), "Waterline", 0)
	_tag(_pp(-2.2, 1.2), Vector2(6.0, 462.0), "Gun ports,\nthree a side", 0)
	_tag(_pp(-6.5, -1.2), Vector2(6.0, 520.0), "Hull", 0)
	_tag(_pp(9.3, -1.0), Vector2(SHEET.x - 6.0, 430.0), "Rudder", 2)
	_tag(_pp(3.0, -2.1), Vector2(SHEET.x - 6.0, 462.0), "Keel", 2)
	_tag(_pp(7.0, 3.875), Vector2(SHEET.x - 6.0, 490.0), "Poop deck", 2)
	_tag(_pp(6.5, 2.6), Vector2(SHEET.x - 6.0, 518.0), "Captain's cabin,\nunder the poop", 2)
	_txt(Vector2(6.0, 586.0), "Bow, the fore end", 0, 24)
	_txt(Vector2(SHEET.x - 6.0, 586.0), "Stern, the aft end", 2, 24)

# ---------------------------------------------------------------- the decks

func _decks() -> void:
	_s = 24.0
	_o = Vector2(SHEET.x * 0.5, 330.0)
	# hull
	var right := PackedVector2Array()
	var left := PackedVector2Array()
	var y := -9.5
	while y <= 9.0001:
		right.append(_dd(_hw(y), y))
		left.append(_dd(-_hw(y), y))
		y += 0.5
	var hull := PackedVector2Array()
	hull.append_array(right)
	left.reverse()
	hull.append_array(left)
	_outline(hull, 2.8, Color(ink.r, ink.g, ink.b, 0.07))
	# poop deck
	var poop := PackedVector2Array()
	for py: float in [5.2, 6.0, 7.0, 8.0, 9.0]:
		poop.append(_dd(_hw(py), py))
	for py: float in [9.0, 8.0, 7.0, 6.0, 5.2]:
		poop.append(_dd(-_hw(py), py))
	_outline(poop, 2.0, Color(ink.r, ink.g, ink.b, 0.12))
	# bowsprit
	_ln(_dd(0.0, -9.3), _dd(0.0, -13.0), 4.4)
	# masts
	_disc(_dd(0.0, -4.3), 0.45 * _s)
	_disc(_dd(0.0, 1.6), 0.5 * _s)
	# main hatch (the stairs down)
	var hr := Rect2(_dd(-0.85, -2.0), Vector2(1.7 * _s, 1.4 * _s))
	draw_rect(hr, ink, false, 2.0)
	for i in range(1, 4):
		_ln(Vector2(hr.position.x, hr.position.y + hr.size.y * i / 4.0), Vector2(hr.end.x, hr.position.y + hr.size.y * i / 4.0), 1.0)
	# guns: carriage and barrel, three a side
	for gy: float in [-2.2, -0.4, 4.0]:
		for sx: float in [-1.0, 1.0]:
			draw_rect(Rect2(_dd(sx * 2.0 - 0.4, gy - 0.33), Vector2(0.8 * _s, 0.66 * _s)), Color(ink.r, ink.g, ink.b, 0.3))
			draw_rect(Rect2(_dd(sx * 2.0 - 0.4, gy - 0.33), Vector2(0.8 * _s, 0.66 * _s)), ink, false, 1.6)
			_ln(_dd(sx * 1.6, gy), _dd(sx * 3.2, gy), 4.0)
	# entry steps, both sides
	for sx: float in [-1.0, 1.0]:
		draw_rect(Rect2(_dd(sx * 3.1 - 0.25, -1.75), Vector2(0.5 * _s, 0.9 * _s)), ink, false, 1.8)
	# the gangway, port side, between the first two guns
	var gw := Rect2(_dd(-4.9, -1.75), Vector2(1.7 * _s, 0.9 * _s))
	draw_rect(gw, Color(ink.r, ink.g, ink.b, 0.12))
	draw_dashed_line(gw.position, Vector2(gw.end.x, gw.position.y), ink, 1.6, 5.0)
	draw_dashed_line(Vector2(gw.position.x, gw.end.y), gw.end, ink, 1.6, 5.0)
	draw_dashed_line(gw.position, Vector2(gw.position.x, gw.end.y), ink, 1.6, 5.0)
	# capstan and its cable coil
	_disc(_dd(0.0, 3.6), 0.45 * _s)
	draw_arc(_dd(-0.55, 2.84), 0.3 * _s, 0.0, TAU, 16, ink, 1.8, true)
	# binnacle and wheel
	draw_rect(Rect2(_dd(-0.2, 5.85), Vector2(0.4 * _s, 0.4 * _s)), ink, false, 2.0)
	draw_arc(_dd(0.0, 6.7), 0.55 * _s, 0.0, TAU, 20, ink, 2.0, true)
	_ln(_dd(-0.55, 6.7), _dd(0.55, 6.7), 1.4)
	_ln(_dd(0.0, 6.15), _dd(0.0, 7.25), 1.4)
	# the log line coil by the stern rail
	draw_arc(_dd(0.0, 8.5), 0.3 * _s, 0.0, TAU, 16, ink, 1.8, true)
	# bow and the two sides
	_txt(Vector2(SHEET.x * 0.5, 16.0), "Bow", 1, 24)
	_txt(Vector2(4.0, 592.0), "Port side, to the left", 0, 22)
	_txt(Vector2(SHEET.x - 4.0, 592.0), "Starboard, to the right", 2, 22)
	# names, left
	_tag(_dd(-0.85, -1.3), Vector2(4.0, 215.0), "Main hatch,\nstairs down", 0)
	_tag(_dd(-4.2, -1.3), Vector2(4.0, 275.0), "Gangway, run\nout at a\nberth", 0)
	_tag(_dd(-0.55, 2.84), Vector2(4.0, 395.0), "Cable coil", 0)
	_tag(_dd(-0.3, 6.15), Vector2(4.0, 470.0), "Binnacle\n(compass)\nand wheel", 0)
	_tag(_dd(-0.3, 8.5), Vector2(4.0, 530.0), "Log line and\nglass, by the\nstern rail", 0)
	# names, right
	_tag(_dd(0.2, -11.5), Vector2(SHEET.x - 4.0, 54.0), "Bowsprit", 2)
	_tag(_dd(0.45, -4.3), Vector2(SHEET.x - 4.0, 215.0), "Foremast", 2)
	_tag(_dd(3.2, -1.3), Vector2(SHEET.x - 4.0, 268.0), "Entry steps,\nboth sides", 2)
	_tag(_dd(2.9, -0.4), Vector2(SHEET.x - 4.0, 335.0), "Guns, three\na side", 2)
	_tag(_dd(0.5, 1.6), Vector2(SHEET.x - 4.0, 400.0), "Mainmast", 2)
	_tag(_dd(0.35, 3.6), Vector2(SHEET.x - 4.0, 450.0), "Capstan", 2)
	_tag(_dd(2.0, 7.6), Vector2(SHEET.x - 4.0, 500.0), "Poop deck", 2)
	_tag(_dd(1.6, 5.7), Vector2(SHEET.x - 4.0, 540.0), "Captain's cabin,\nunder the poop", 2)

# ---------------------------------------------------------------- the sail plan

func _sails() -> void:
	_s = 13.0
	_o = Vector2(SHEET.x * 0.5 + 4.75 * _s, 285.0)
	draw_dashed_line(_pp(-20.0, 0.0), _pp(10.8, 0.0), ink.lightened(0.15), 1.6, 7.0)
	_outline(_hull_side(), 2.2, Color(ink.r, ink.g, ink.b, 0.12))
	_ln(_pp(5.2, 3.875), _pp(9.0, 3.875), 2.4)
	_ln(_pp(-9.0, 2.4), _pp(-14.0, 4.1), 4.0)
	_ln(_pp(-14.0, 4.1), _pp(-17.8, 5.5), 2.4)
	_masts()
	var paper := Color(1.0, 0.97, 0.88, 0.75)
	var sails: Array = []      # [name, polygon]
	sails.append(["Jib", PackedVector2Array([_pp(-17.5, 5.5), _pp(-5.0, 11.0), _pp(-9.5, 3.0)])])
	sails.append(["Fore staysail", PackedVector2Array([_pp(-4.6, 9.0), _pp(-8.5, 2.9), _pp(-4.6, 2.2)])])
	var fm := [["Fore", -4.3, 14.0, [6.4, 5.0, 3.4]], ["Main", 1.6, 15.0, [7.4, 5.8, 4.0]]]
	var tops := [0.95, 0.78, 0.40]
	var bots := [0.80, 0.43, 0.14]
	var names := ["topgallant", "topsail", "course"]
	for m in fm:
		for i in 3:
			var w: float = float(m[3][i]) * 0.5
			var y0: float = float(m[1])
			var h: float = float(m[2])
			var zt := float(tops[i]) * h
			var zb := float(bots[i]) * h
			sails.append(["%s %s" % [m[0], names[i]], PackedVector2Array([_pp(y0 - w, zt), _pp(y0 + w, zt), _pp(y0 + w, zb), _pp(y0 - w, zb)])])
	sails.append(["Spanker", PackedVector2Array([_pp(1.9, 4.4), _pp(1.9, 10.0), _pp(6.0, 8.4), _pp(8.6, 4.4)])])
	# order the key the way a sailor reads the rig: jib, staysail, the foremast aloft to alow, the main, the spanker
	var order := [0, 1, 2, 3, 4, 5, 6, 7, 8]
	var key_y := 395.0
	for n in order.size():
		var sail: Array = sails[order[n]]
		var poly: PackedVector2Array = sail[1]
		_outline(poly, 1.8, paper)
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= float(poly.size())
		draw_circle(c, 10.0, Color(0.9, 0.82, 0.65))
		draw_arc(c, 10.0, 0.0, TAU, 18, ink, 1.6, true)
		_txt(c + Vector2(0.0, 6.0), str(n + 1), 1, 17)
		_txt(Vector2(20.0, key_y + 24.0 * n), "%d   %s" % [n + 1, sail[0]], 0, 22)
	# yards over the sails, and the spanker's boom
	for m in fm:
		for f: float in [0.40, 0.78, 0.95]:
			var wy: float = float(m[3][[0.95, 0.78, 0.40].find(f)]) * 0.5
			_ln(_pp(float(m[1]) - wy, f * float(m[2])), _pp(float(m[1]) + wy, f * float(m[2])), 3.0)
	_ln(_pp(1.9, 4.4), _pp(8.8, 4.4), 3.0)
	_txt(Vector2(6.0, 24.0), "Sails shown laid flat to the eye", 0, 22)
	_txt(Vector2(SHEET.x - 6.0, 24.0), "Bow to the left", 2, 22)
