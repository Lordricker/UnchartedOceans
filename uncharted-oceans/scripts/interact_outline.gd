class_name InteractOutline
extends RefCounted
## One white outline for everything on the ship that you can click.
## InteractOutline.set_on(node, true) puts it on every mesh at or under node; false takes it off.
## (Use it through preload("res://scripts/interact_outline.gd"), as the ship scripts do.)
##
## It is an overlay material that draws the mesh again, shrunk-wrapped a little bigger and turned inside out,
## so only a rim shows. The rim is about the same width on screen near or far.

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
