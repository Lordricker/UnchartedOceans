class_name BookReader
extends Node3D
## A readable book. Closed, it lies flat; open() swings the front cover over; then pages turn with a
## curl. The text comes from a markdown chapter (data/book/*.md) that is paginated and drawn onto the
## pages, so adding a chapter is adding a file.
##
##   var book := BookReader.new()
##   add_child(book)
##   await book.open_file("res://data/book/log_line.md")   # lays out the pages
##   book.open()                                           # cover swings over
##   book.next_page() / book.prev_page()                   # or arrow keys, A/D, wheel, click right/left half
##   book.close()                                          # pages turn back, cover closes; Esc emits close_requested
##
## Fonts: drop .ttf/.otf files in res://assets/fonts. Titles use the file with title_font_hint in its
## name ("ferrum"), body text the one with body_font_hint ("" = a serif from the system).
## The book lies on the XZ plane, spine along Z at x = 0, pages to +X (right) and -X (left), viewed from +Z / above.
## A page is page_w x page_h metres; the whole thing is small (a hand-sized book), so scale or move the
## node to put it in front of the camera.

signal opened
signal closed
signal page_changed(spread: int)
signal close_requested

@export var page_w := 0.15
@export var page_h := 0.21
@export var page_px := Vector2i(540, 756)
@export var cover_color := Color(0.30, 0.17, 0.09)
@export var paper_color := Color(0.90, 0.82, 0.65)
@export var ink_color := Color(0.17, 0.11, 0.07)
@export var fonts_dir := "res://assets/fonts"
@export var title_font_hint := "ferrum"
@export var body_font_hint := "imfellenglish-regular"
@export var italic_font_hint := "imfellenglish-italic"
@export var body_size := 28
@export var h1_size := 58
@export var h2_size := 40
@export var margin := Vector2(52, 60)
@export var open_time := 1.1
@export var turn_time := 0.7
## Take the keys / wheel / clicks itself (turn off if the game drives the book).
@export var take_input := true

enum S { CLOSED, OPENING, READING, TURNING, CLOSING }
const COVER_T := 0.006

const PAGE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D front_tex : source_color, filter_linear;
uniform sampler2D back_tex : source_color, filter_linear;
uniform float angle = 0.0;
uniform float curl = 0.0;
uniform float page_w = 0.15;
uniform float rest_height = 0.0;
void vertex() {
	float x = VERTEX.x;
	float c = -curl * sin(angle) / page_w;
	float a = angle + c * x;
	vec2 p;
	if (abs(c) < 0.0001) {
		p = vec2(cos(angle), sin(angle)) * x;
	} else {
		p = vec2(sin(a) - sin(angle), cos(angle) - cos(a)) / c;
	}
	VERTEX = vec3(p.x, p.y + rest_height, VERTEX.z);
	NORMAL = vec3(-sin(a), cos(a), 0.0);
}
void fragment() {
	vec4 col;
	if (FRONT_FACING) {
		col = texture(front_tex, UV);
	} else {
		col = texture(back_tex, vec2(1.0 - UV.x, UV.y));
	}
	ALBEDO = col.rgb;
	ROUGHNESS = 0.95;
}
"""

var _state := S.CLOSED
var _spread := 0
var _spreads := 1
var _pages: Array[Texture2D] = []
var _blank: Texture2D
var _viewports: Array[SubViewport] = []
var _thick := 0.02
var _cover: Node3D
var _right_block: MeshInstance3D
var _left_block: MeshInstance3D
var _page_l: MeshInstance3D
var _page_r: MeshInstance3D
var _page_f: MeshInstance3D
var _built := false
var _title_font: Font
var _body_font: Font
var _italic_font: Font
var _vignette: GradientTexture2D

# ---------------------------------------------------------------- loading and layout

## Reads a markdown chapter, paginates it and draws the pages. Await it, then call open().
func open_file(path: String) -> void:
	var text := ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		text = f.get_as_text()
	else:
		# An exported game leaves .md files out unless the export preset's include filter lists them, but .json files
		# do get exported: tools/build_book_json.py bundles every chapter into data/book/chapters.json.
		var bundle := FileAccess.open("res://data/book/chapters.json", FileAccess.READ)
		if bundle:
			var d = JSON.parse_string(bundle.get_as_text())
			if d is Dictionary and d.has(path):
				text = String(d[path])
	if text == "":
		# Never leave the reader with nothing to show (it would sit there half open): a plain page says so.
		push_warning("BookReader: can't read %s (not on disk and not in data/book/chapters.json: run tools/build_book_json.py)" % path)
		await show_text("# Missing pages\n\n*The pages of this book could not be found.*")
		return
	await show_text(text)

func show_text(md: String) -> void:
	for v in _viewports:
		v.queue_free()
	_viewports.clear()
	_pages.clear()
	_title_font = _find_font(title_font_hint, true)
	_body_font = _find_font(body_font_hint, false)
	_italic_font = _find_font(italic_font_hint, false)
	_vignette = _make_vignette()
	var pages := _paginate(_parse(md))
	if pages.is_empty():
		pages = [[]]
	_blank = _render_page([], 0)
	for i in pages.size():
		_pages.append(_render_page(pages[i], i + 1))
	_spreads = int(ceil((_pages.size() + 1) / 2.0))
	_thick = clampf(0.006 + 0.0015 * _pages.size(), 0.01, 0.05)
	_spread = 0
	_state = S.CLOSED
	if _built:
		_clear_geometry()
	_build_geometry()
	# the page viewports draw on the next frame or two
	await get_tree().process_frame
	await get_tree().process_frame
	_cover_set(0.0)
	_place_static()

func _find_font(hint: String, bold: bool) -> Font:
	if hint != "":
		var d := DirAccess.open(fonts_dir)
		if d:
			for f in d.get_files():
				var nm := f.trim_suffix(".import")
				var low := nm.to_lower()
				if low.contains(hint.to_lower()) and (low.ends_with(".ttf") or low.ends_with(".otf")):
					var res = load(fonts_dir.path_join(nm))
					if res is Font:
						return res
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Times New Roman", "serif"])
	sf.font_weight = 700 if bold else 400
	return sf

func _make_vignette() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.55, 1.0])
	g.colors = PackedColorArray([Color(0.40, 0.25, 0.08, 0.0), Color(0.40, 0.25, 0.08, 0.5)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 1.0)
	t.width = 128
	t.height = 128
	return t

## Markdown to blocks: {t: h1|h2|sub|p|li, text, pre, post}. Stops at the chapter's closing rule
## (anything after it, such as development notes, is not part of the book).
func _parse(md: String) -> Array:
	var lines := md.split("\n")
	var i := 0
	if lines.size() > 0 and lines[0].strip_edges() == "---":
		i = 1
		while i < lines.size() and lines[i].strip_edges() != "---":
			i += 1
		i += 1
	var blocks: Array = []
	var para := ""
	var num := RegEx.create_from_string("^\\d+\\. ")
	for j in range(i, lines.size()):
		var raw: String = lines[j]
		var t := raw.strip_edges()
		if t == "---" or t.begins_with("### "):
			break
		if t == "":
			_flush(blocks, para)
			para = ""
		elif t.begins_with("@diagram "):
			_flush(blocks, para)
			para = ""
			var parts := t.substr(9).split("|")
			blocks.append({"t": "dia", "name": parts[0].strip_edges(), "text": _plain(parts[1]) if parts.size() > 1 else "", "pre": 0, "post": 0})
		elif t.begins_with("# "):
			_flush(blocks, para)
			para = ""
			blocks.append({"t": "h1", "text": _plain(t.substr(2)), "pre": 0, "post": 18})
		elif t.begins_with("## "):
			_flush(blocks, para)
			para = ""
			blocks.append({"t": "h2", "text": _plain(t.substr(3)), "pre": 22, "post": 8})
		elif t.begins_with("- ") or num.search(t) != null:
			_flush(blocks, para)
			para = ""
			blocks.append({"t": "li", "text": _plain(t.substr(2) if t.begins_with("- ") else t), "pre": 0, "post": 8})
		elif t.begins_with("*") and t.ends_with("*") and not t.begins_with("**") and blocks.size() > 0 and para == "":
			blocks.append({"t": "sub", "text": _plain(t), "pre": 0, "post": 22})
		else:
			para = (para + " " + t).strip_edges()
	_flush(blocks, para)
	return blocks

func _flush(blocks: Array, para: String) -> void:
	if para != "":
		blocks.append({"t": "p", "text": _plain(para), "pre": 0, "post": 12})

func _plain(s: String) -> String:
	return s.replace("**", "").replace("*", "").replace("`", "").strip_edges()

func _font_for(b: Dictionary) -> Font:
	if b["t"] == "h1" or b["t"] == "h2":
		return _title_font
	return _italic_font if b["t"] == "sub" else _body_font

func _size_for(b: Dictionary) -> int:
	match b["t"]:
		"h1":
			return h1_size
		"h2":
			return h2_size
		"sub":
			return body_size - 3
	return body_size

func _text_for(b: Dictionary) -> String:
	return ("•  " + String(b["text"])) if b["t"] == "li" else String(b["text"])

func _h(font: Font, size: int, text: String, width: float) -> float:
	return font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, size).y + 2.0

func _paginate(blocks: Array) -> Array:
	var width := float(page_px.x) - margin.x * 2.0
	var avail := float(page_px.y) - margin.y * 2.0 - 34.0
	var pages: Array = []
	var cur: Array = []
	var y := 0.0
	for b0 in blocks:
		var b: Dictionary = b0
		var font := _font_for(b)
		var size := _size_for(b)
		if b["t"] == "dia":
			# a drawing gets a page to itself
			if not cur.is_empty():
				pages.append(cur)
			pages.append([{"t": "dia", "name": b["name"], "text": b["text"], "pre": 0.0, "post": 0.0}])
			cur = []
			y = 0.0
			continue
		var is_head: bool = b["t"] == "h1" or b["t"] == "h2"
		var pre := 0.0 if cur.is_empty() else float(b["pre"])
		var post := float(b["post"])
		var text := _text_for(b)
		var h := _h(font, size, text, width)
		# a heading never sits at the foot of a page with nothing under it
		if is_head and not cur.is_empty() and y + pre + h + body_size * 3.0 > avail:
			pages.append(cur)
			cur = []
			y = 0.0
			pre = 0.0
		if y + pre + h <= avail:
			cur.append({"t": b["t"], "text": text, "pre": pre, "post": post})
			y += pre + h + post
			continue
		# too long for what is left: fill the page, carry the rest over
		var words := text.split(" ")
		while words.size() > 0:
			var room := avail - y - pre
			var lo := 0
			var hi := words.size()
			while lo < hi:
				var mid := (lo + hi + 1) / 2
				if _h(font, size, " ".join(words.slice(0, mid)), width) <= room:
					lo = mid
				else:
					hi = mid - 1
			if lo == 0:
				if cur.is_empty():
					lo = 1
				else:
					pages.append(cur)
					cur = []
					y = 0.0
					pre = 0.0
					continue
			var part := " ".join(words.slice(0, lo))
			cur.append({"t": b["t"], "text": part, "pre": pre, "post": post})
			y += pre + _h(font, size, part, width) + post
			words = words.slice(lo)
			if words.size() > 0:
				pages.append(cur)
				cur = []
				y = 0.0
				pre = 0.0
	if not cur.is_empty():
		pages.append(cur)
	return pages

func _render_page(blocks: Array, number: int) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = page_px
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	_viewports.append(vp)
	var bg := ColorRect.new()
	bg.color = paper_color
	bg.size = Vector2(page_px)
	vp.add_child(bg)
	var vg := TextureRect.new()
	vg.texture = _vignette
	vg.size = Vector2(page_px)
	vg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vg.stretch_mode = TextureRect.STRETCH_SCALE
	vp.add_child(vg)
	var width := float(page_px.x) - margin.x * 2.0
	var box := VBoxContainer.new()
	box.position = margin
	box.size = Vector2(width, float(page_px.y) - margin.y * 2.0)
	box.add_theme_constant_override("separation", 0)
	vp.add_child(box)
	for b0 in blocks:
		var b: Dictionary = b0
		if b["t"] == "dia":
			_add_diagram(box, b, width)
			continue
		if float(b["pre"]) > 0.0:
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(0, float(b["pre"]))
			box.add_child(sp)
		var l := Label.new()
		l.text = b["text"]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(width, 0)
		l.add_theme_font_override("font", _font_for(b))
		l.add_theme_font_size_override("font_size", _size_for(b))
		l.add_theme_color_override("font_color", ink_color.lightened(0.18) if b["t"] == "sub" else ink_color)
		l.add_theme_constant_override("line_spacing", 0)
		box.add_child(l)
		var post := Control.new()
		post.custom_minimum_size = Vector2(0, float(b["post"]))
		box.add_child(post)
	if number > 0:
		var n := Label.new()
		n.text = "~ %d ~" % number
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.size = Vector2(width, 28)
		n.position = Vector2(margin.x, float(page_px.y) - margin.y * 0.75)
		n.add_theme_font_override("font", _body_font)
		n.add_theme_font_size_override("font_size", 20)
		n.add_theme_color_override("font_color", ink_color.lightened(0.3))
		vp.add_child(n)
	return vp.get_texture()

## A drawing (book_diagram.gd) with its title above it, filling the page. Chapter line: "@diagram profile | Her Profile".
func _add_diagram(box: VBoxContainer, b: Dictionary, width: float) -> void:
	var t := Label.new()
	t.text = b["text"]
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(width, 0)
	t.add_theme_font_override("font", _title_font)
	t.add_theme_font_size_override("font_size", h2_size)
	t.add_theme_color_override("font_color", ink_color)
	box.add_child(t)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	box.add_child(gap)
	var d: Control = load("res://scripts/book_diagram.gd").new()
	d.set("kind", String(b["name"]))
	d.set("ink", ink_color)
	d.set("font", _body_font)
	d.custom_minimum_size = Vector2(width, float(page_px.y) - margin.y * 2.0 - 34.0 - 64.0)
	box.add_child(d)

# ---------------------------------------------------------------- geometry

func _grid_mesh(w: float, h: float, nx: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in nx + 1:
		var u := float(i) / nx
		verts.append(Vector3(u * w, 0.0, -h * 0.5))
		uvs.append(Vector2(u, 0.0))
		norms.append(Vector3.UP)
		verts.append(Vector3(u * w, 0.0, h * 0.5))
		uvs.append(Vector2(u, 1.0))
		norms.append(Vector3.UP)
	for i in nx:
		var a := i * 2
		idx.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-w, -0.01, -h * 0.5), Vector3(2.0 * w, w + 0.02, h))
	return m

func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _leaf(shader: Shader, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("page_w", page_w)
	mi.material_override = m
	add_child(mi)
	return mi

func _clear_geometry() -> void:
	for n in get_children():
		if not (n is SubViewport):
			n.queue_free()
	_built = false

func _build_geometry() -> void:
	var cover := _mat(cover_color, 0.7)
	var paper := _mat(paper_color.darkened(0.12), 0.95)
	var total := _thick + COVER_T * 2.0
	_box(self, Vector3(page_w, COVER_T, page_h), Vector3(page_w * 0.5, COVER_T * 0.5, 0.0), cover)           # back cover
	_box(self, Vector3(0.008, total, page_h), Vector3(-0.004, total * 0.5, 0.0), cover)                      # spine
	_right_block = _box(self, Vector3(page_w * 0.985, 1.0, page_h * 0.985), Vector3(page_w * 0.5, 0.0, 0.0), paper)
	_left_block = _box(self, Vector3(page_w * 0.985, 1.0, page_h * 0.985), Vector3(-page_w * 0.5, 0.0, 0.0), paper)
	_cover = Node3D.new()
	add_child(_cover)
	_box(_cover, Vector3(page_w, COVER_T, page_h), Vector3(page_w * 0.5, 0.0, 0.0), cover)                    # front cover
	var inside := MeshInstance3D.new()                                                                        # its paper lining
	var pm := PlaneMesh.new()
	pm.size = Vector2(page_w * 0.985, page_h * 0.985)
	inside.mesh = pm
	inside.material_override = _mat(paper_color.darkened(0.04), 0.95)
	inside.position = Vector3(page_w * 0.5, -COVER_T * 0.5 - 0.0004, 0.0)
	inside.rotation.x = PI
	_cover.add_child(inside)
	var shader := Shader.new()
	shader.code = PAGE_SHADER
	var grid := _grid_mesh(page_w * 0.985, page_h * 0.985, 20)
	_page_r = _leaf(shader, grid)
	_page_l = _leaf(shader, grid)
	_page_f = _leaf(shader, grid)
	_page_f.visible = false
	_built = true

func _L(s: int) -> Texture2D:
	var i := 2 * s - 1
	return _pages[i] if i >= 0 and i < _pages.size() else _blank

func _R(s: int) -> Texture2D:
	var i := 2 * s
	return _pages[i] if i >= 0 and i < _pages.size() else _blank

## Left and right stack heights when the book stands at this spread.
func _heights(s: int) -> Vector2:
	var frac := float(s) / float(maxi(1, _spreads - 1))
	return Vector2(_thick * frac, _thick * (1.0 - frac))

func _blocks(h: Vector2) -> void:
	_left_block.scale.y = maxf(h.x, 0.0001)
	_left_block.position.y = COVER_T + h.x * 0.5
	_left_block.visible = h.x > 0.0004
	_right_block.scale.y = maxf(h.y, 0.0001)
	_right_block.position.y = COVER_T + h.y * 0.5
	_right_block.visible = h.y > 0.0004

func _set_leaf(mi: MeshInstance3D, angle: float, rest: float, front: Texture2D, back: Texture2D, curl: float = 0.0) -> void:
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("angle", angle)
	m.set_shader_parameter("curl", curl)
	m.set_shader_parameter("rest_height", rest)
	if front:
		m.set_shader_parameter("front_tex", front)
	if back:
		m.set_shader_parameter("back_tex", back)

## The pages lying on the two stacks for the current spread.
func _place_static() -> void:
	var h := _heights(_spread)
	_blocks(h)
	_set_leaf(_page_r, 0.0, COVER_T + h.y + 0.0004, _R(_spread), _blank)
	_set_leaf(_page_l, PI, COVER_T + h.x + 0.0004, _blank, _L(_spread))
	_page_l.visible = _spread > 0

func _cover_set(a: float) -> void:
	_cover.rotation.z = a
	var k := smoothstep(0.0, PI, a)
	_cover.position.y = lerpf(COVER_T + _thick + COVER_T * 0.5, COVER_T * 0.5, k)

# ---------------------------------------------------------------- opening, turning, closing

func is_open() -> bool:
	return _state == S.READING or _state == S.TURNING

func open() -> void:
	if _state != S.CLOSED or not _built:
		return
	_state = S.OPENING
	var tw := create_tween()
	tw.tween_method(_cover_set, 0.0, PI, open_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_state = S.READING
	opened.emit()

func close() -> void:
	if _state != S.READING:
		return
	while _spread > 0:
		await _turn(-1, 0.28)
	_state = S.CLOSING
	var tw := create_tween()
	tw.tween_method(_cover_set, PI, 0.0, open_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_state = S.CLOSED
	closed.emit()

func next_page() -> void:
	if _state == S.READING:
		_turn(1, turn_time)

func prev_page() -> void:
	if _state == S.READING:
		_turn(-1, turn_time)

func _turn(dir: int, time: float) -> void:
	var s := _spread
	var t := s + dir
	if t < 0 or t >= _spreads:
		return
	_state = S.TURNING
	var from_h := _heights(s)
	var to_h := _heights(t)
	if dir > 0:
		_set_leaf(_page_f, 0.0, COVER_T + from_h.y + 0.0012, _R(s), _L(t), 1.0)
		_set_leaf(_page_r, 0.0, COVER_T + to_h.y + 0.0004, _R(t), _blank)     # what the leaf uncovers
	else:
		_set_leaf(_page_f, PI, COVER_T + from_h.x + 0.0012, _R(t), _L(s), -1.0)
		_set_leaf(_page_l, PI, COVER_T + to_h.x + 0.0004, _blank, _L(t))      # what the leaf uncovers
		_page_l.visible = true
	_page_f.visible = true
	var tw := create_tween()
	tw.tween_method(func(f: float): _turn_step(dir, f, from_h, to_h), 0.0, 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_spread = t
	_page_f.visible = false
	_place_static()
	_state = S.READING
	page_changed.emit(_spread)

func _turn_step(dir: int, f: float, from_h: Vector2, to_h: Vector2) -> void:
	var angle := PI * f if dir > 0 else PI * (1.0 - f)
	var h := from_h.lerp(to_h, f)
	_blocks(h)
	var m := _page_f.material_override as ShaderMaterial
	m.set_shader_parameter("angle", angle)
	m.set_shader_parameter("rest_height", COVER_T + maxf(h.x, h.y) + 0.0012)

# ---------------------------------------------------------------- input

## _input so a click or key meant for the book is not also seen by the rest of the game.
func _input(e: InputEvent) -> void:
	if not take_input or _state != S.READING:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_RIGHT, KEY_D, KEY_PAGEDOWN:
				next_page()
				get_viewport().set_input_as_handled()
			KEY_LEFT, KEY_A, KEY_PAGEUP:
				prev_page()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				close_requested.emit()
				get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				next_page()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				prev_page()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_LEFT:
				if e.position.x > get_viewport().get_visible_rect().size.x * 0.5:
					next_page()
				else:
					prev_page()
				get_viewport().set_input_as_handled()
