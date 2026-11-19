class_name InteractOutline
extends RefCounted
## One white outline for everything on the ship that you can click.
## InteractOutline.set_on(node, true) puts it on every mesh at or under node; false takes it off.
## (Use it through preload("res://scripts/interact_outline.gd"), as the ship scripts do.)
##
## It is an overlay material that draws the mesh again, shrunk-wrapped a little bigger and turned inside out,
## so only a rim shows. The rim is about the same width on screen near or far.
##
## The name of whatever is outlined shows along the bottom of the screen: InteractOutline.show_name(owner, "Capstan")
## when the outline goes on, hide_name(owner) when it comes off. If two things name themselves at once the newest wins.

const SHADER_CODE := """
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;
uniform vec3 colour : source_color = vec3(1.0, 1.0, 1.0);
uniform float width = 0.0035;
void vertex() {
	float d = max(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z, 0.3);
	VERTEX += NORMAL * width * d;
}
void fragment() {
	ALBEDO = colour;
}
"""

static var _mat: ShaderMaterial

static func material() -> ShaderMaterial:
	if _mat == null:
		var s := Shader.new()
		s.code = SHADER_CODE
		_mat = ShaderMaterial.new()
		_mat.shader = s
	return _mat

static func set_on(root: Node, on: bool) -> void:
	if root == null or not is_instance_valid(root):
		return
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_overlay = material() if on else null
	for c in root.get_children():
		set_on(c, on)


# ---------------------------------------------------------------- the name along the bottom of the screen

const NAME_BOTTOM := -110.0          ## px up from the bottom edge (clear of the wheel's hints at -40)
const NAME_FONT := "res://assets/fonts/Ferrum-ExtraCondensed.otf"

static var _names: Dictionary = {}   ## owner -> text, oldest first
static var _layer: CanvasLayer
static var _name_label: Label

## Show `text` as the name of what `owner` is outlining (call it every frame if you like: same text is a no-op).
static func show_name(owner: Object, text: String) -> void:
	if text == "":
		hide_name(owner)
		return
	if _names.has(owner) and _names[owner] == text and _names.keys()[-1] == owner:
		return
	_names.erase(owner)
	_names[owner] = text
	refresh_name()

static func hide_name(owner: Object) -> void:
	if _names.erase(owner):
		refresh_name()

static func refresh_name() -> void:
	for k in _names.keys():
		if not is_instance_valid(k):
			_names.erase(k)
	var text := ""
	if not _names.is_empty():
		text = String(_names.values()[-1])
	if text == "" and (_name_label == null or not is_instance_valid(_name_label)):
		return
	_ensure_label()
	if _name_label == null:
		return
	_name_label.text = text
	_name_label.visible = text != ""

static func _ensure_label() -> void:
	if _layer != null and is_instance_valid(_layer):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_layer = _NameLayer.new()
	_layer.name = "HoverName"
	_layer.layer = 5
	_name_label = Label.new()
	_name_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_name_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_name_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_name_label.offset_bottom = NAME_BOTTOM
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.9))
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("outline_size", 6)
	if ResourceLoader.exists(NAME_FONT):
		_name_label.add_theme_font_override("font", load(NAME_FONT) as Font)
		_name_label.add_theme_font_size_override("font_size", 28)
	else:
		_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.visible = false
	_layer.add_child(_name_label)
	tree.root.add_child.call_deferred(_layer)

## Holds the label; each frame drops names whose owner is gone and hides the name while the mouse is free
## (a menu or a window is open) or the game is paused.
class _NameLayer extends CanvasLayer:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _process(_delta: float) -> void:
		InteractOutline.refresh_name()
		var lbl := InteractOutline._name_label
		if lbl != null and lbl.visible and (Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or get_tree().paused):
			lbl.visible = false
