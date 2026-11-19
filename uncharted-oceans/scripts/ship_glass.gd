extends Node
## Clear glass for the brig: the stern windows, the skylight (roof light) and any other glass.
##
## The brig's glass comes out of Blender with its own material (the bake kept the glass, glow and flame materials
## apart from the atlases). Whatever it arrives as, this swaps every glass surface for one clear, glossy, see-through
## material, so you can look out of the cabin windows and up through the skylight.
##
## A surface counts as glass when its material's name has one of material_words in it (glass, window, skylight, ...),
## or when the mesh node's name has one of node_words in it (glass, pane). Glowing materials (emission on, or a
## flame / fire / glow name) are left alone, so lantern flames and lit lamp glass still shine.
## A mesh that is glass all over also stops casting a shadow, so a skylight does not shade the cabin.
##
## The cabin windows and the skylight are the exception to that: in the game brig they are baked into the big Hull
## mesh with the glowing amber materials BR_GlassDim (cabin front window, skylight) and BR_Glow (stern windows), which
## is why they showed up as solid yellow. The galley stove below deck uses the same two materials, so they cannot be
## swapped whole. Instead, for the materials in split_words, only the triangles higher than glass_min_y above the ship's
## origin are cut out into their own clear mesh (a child of the hull piece, casting no shadow), and the stove keeps its glow.
##
## Added by ship_motion.gd (glass_enabled). It prints what it changed when the ship loads: look for "ShipGlass:" in
## the output. If it says it found nothing, the glass material has a name that is not in material_words.

@export var enabled := true
## 0 = invisible, 1 = solid. 0.1 to 0.2 reads as clean glass with a faint tint.
@export_range(0.0, 1.0) var glass_alpha := 0.12
@export var glass_tint := Color(0.82, 0.92, 0.96)
@export_range(0.0, 1.0) var glass_roughness := 0.03
@export var material_words := PackedStringArray(["glass", "window", "skylight", "rooflight", "roof_light", "pane"])
@export var node_words := PackedStringArray(["glass", "pane"])
@export var skip_words := PackedStringArray(["flame", "fire", "glow", "candle"])
## Glowing materials that are cut up instead of swapped whole (lower case; see above), and the height in the ship's
## frame (m) above which their triangles are glass. The deck is at about 1.7 and the windows start near 2.9, the stove tops out near 1.9.
@export var split_words := PackedStringArray(["br_glassdim", "br_glow"])
@export var glass_min_y := 2.5

## Glass you can stand on: every roof-like glass face (skylights, deck lights) also gets an invisible collision
## surface on the ship's walkable body (ShipBody), so the player cannot drop through the pane into the cabin.
## Upright glass (windows) is left alone. Meshes whose node name has one of collide_skip_words are skipped.
@export var glass_collision := true
## A glass face counts as roof-like when its normal points up or down by at least this much (0.5 = within 60 degrees of flat).
@export_range(0.0, 1.0) var collide_min_up := 0.5
@export var collide_skip_words := PackedStringArray(["binnacle", "compass", "lamp", "lantern"])

## What was made clear, as "mesh/material" (for checking).
var cleared: Array[String] = []

var _glass_surfaces: Array = []   # [MeshInstance3D, surface index] for every surface made clear

var _clear_mat: StandardMaterial3D
var _frame: Node3D


func _ready() -> void:
	if not enabled:
		return
	call_deferred("_apply")


func _apply() -> void:
	var par := get_parent()
	if par == null:
		return
	var root: Node = null
	var sp = par.get("ship_path")
	if sp is NodePath:
		root = par.get_node_or_null(sp)
	if root == null:
		root = par
	# the ship's own frame, the same one the capstan and the deck heights are given in
	_frame = par as Node3D
	if _frame == null:
		_frame = root as Node3D
	_clear_mat = _make_clear()
	_glass_surfaces.clear()
	var n := _walk(root)
	if glass_collision:
		_add_glass_collision(root)
	if n == 0:
		push_warning("ShipGlass: found no glass surfaces on %s (no material named like %s)" % [root.name, ", ".join(material_words)])
	else:
		print("ShipGlass: made %d glass surfaces clear: %s" % [n, ", ".join(cleared)])


func _make_clear() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "ShipGlass_clear"
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(glass_tint.r, glass_tint.g, glass_tint.b, glass_alpha)
	m.roughness = glass_roughness
	m.metallic = 0.0
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.emission_enabled = false
	m.render_priority = 1
	return m


func _walk(n: Node) -> int:
	var count := 0
	if n is MeshInstance3D:
		count += _fix(n as MeshInstance3D)
	for c in n.get_children():
		if c.name.ends_with("_ClearGlass"):
			continue                         # the pieces we cut out ourselves
		count += _walk(c)
	return count


func _fix(mi: MeshInstance3D) -> int:
	if mi.mesh == null:
		return 0
	var changed := _split(mi)
	var by_node := _has_word(String(mi.name), node_words)
	var all_glass := true
	for s in mi.mesh.get_surface_count():
		var m: Material = mi.get_active_material(s)
		var is_glass := false
		var nm := ""
		if m != null:
			nm = String(m.resource_name)
			var skip := _has_word(nm, skip_words)
			if m is BaseMaterial3D and (m as BaseMaterial3D).emission_enabled:
				skip = true
			is_glass = (not skip) and (by_node or _has_word(nm, material_words))
		if is_glass:
			mi.set_surface_override_material(s, _clear_mat)
			_glass_surfaces.append([mi, s])
			cleared.append("%s/%s" % [mi.name, nm])
			changed += 1
		else:
			all_glass = false
	if changed > 0 and all_glass:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return changed


## Cut the high triangles of the split_words materials out of this mesh into a clear mesh of their own. Returns how
## many glass pieces were made (0 if this mesh has none, or cannot be cut).
func _split(mi: MeshInstance3D) -> int:
	var src := mi.mesh as ArrayMesh
	if src == null or src.get_blend_shape_count() > 0 or _frame == null:
		return 0
	var wanted := false
	for s in src.get_surface_count():
		var m: Material = mi.get_active_material(s)
		if m != null and _has_word(String(m.resource_name), split_words):
			wanted = true
	if not wanted:
		return 0
	var to_frame := _frame.global_transform.affine_inverse() * mi.global_transform
	var rest := ArrayMesh.new()
	var glass := ArrayMesh.new()
	var tris := 0
	for s in src.get_surface_count():
		var arr: Array = src.surface_get_arrays(s)
		var mat: Material = mi.get_active_material(s)
		var cut := mat != null and _has_word(String(mat.resource_name), split_words)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx := PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] is PackedInt32Array and (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
			idx = arr[Mesh.ARRAY_INDEX]
		else:
			idx.resize(v.size())
			for i in v.size():
				idx[i] = i
		var keep := PackedInt32Array()
		var high := PackedInt32Array()
		if cut:
			for t in range(0, idx.size() - 2, 3):
				var mid := (to_frame * v[idx[t]] + to_frame * v[idx[t + 1]] + to_frame * v[idx[t + 2]]) / 3.0
				if mid.y >= glass_min_y:
					high.append(idx[t])
					high.append(idx[t + 1])
					high.append(idx[t + 2])
				else:
					keep.append(idx[t])
					keep.append(idx[t + 1])
					keep.append(idx[t + 2])
		if not cut or high.is_empty():
			rest.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			if mat != null:
				rest.surface_set_material(rest.get_surface_count() - 1, mat)
			continue
		if not keep.is_empty():
			var a_keep := arr.duplicate()
			a_keep[Mesh.ARRAY_INDEX] = keep
			rest.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a_keep)
			rest.surface_set_material(rest.get_surface_count() - 1, mat)
		var a_high := arr.duplicate()
		a_high[Mesh.ARRAY_INDEX] = high
		glass.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a_high)
		glass.surface_set_material(glass.get_surface_count() - 1, _clear_mat)
		tris += high.size() / 3
	if glass.get_surface_count() == 0:
		return 0
	# the hull piece keeps what is left; the glass is a child with no shadow (the skylight must not shade the cabin)
	for s in mi.get_surface_override_material_count():
		mi.set_surface_override_material(s, null)
	mi.mesh = rest
	var gi := MeshInstance3D.new()
	gi.name = "%s_ClearGlass" % mi.name
	gi.mesh = glass
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi.layers = mi.layers
	gi.visibility_range_begin = mi.visibility_range_begin
	gi.visibility_range_begin_margin = mi.visibility_range_begin_margin
	gi.visibility_range_end = mi.visibility_range_end
	gi.visibility_range_end_margin = mi.visibility_range_end_margin
	gi.visibility_range_fade_mode = mi.visibility_range_fade_mode
	mi.add_child(gi)
	for gs in glass.get_surface_count():
		_glass_surfaces.append([gi, gs])
	cleared.append("%s/cut %d glass triangles" % [mi.name, tris])
	return 1


## One invisible trimesh from every roof-like glass face, added to the ship's walkable body (ShipBody) so it
## rides with the ship. Built in ShipBody's own space, so the shape needs no transform.
func _add_glass_collision(root: Node) -> void:
	var body := root.find_child("ShipBody", true, false) as Node3D
	if body == null:
		push_warning("ShipGlass: no ShipBody on %s, glass has no collision (skylights can be fallen through)" % root.name)
		return
	var to_body := body.global_transform.affine_inverse()
	var faces := PackedVector3Array()
	for pair in _glass_surfaces:
		var mi: MeshInstance3D = pair[0]
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		if _has_word(String(mi.name), collide_skip_words) or _has_word(String(mi.get_parent().name), collide_skip_words):
			continue
		var s: int = pair[1]
		if s >= mi.mesh.get_surface_count():
			continue
		var arr: Array = mi.mesh.surface_get_arrays(s)
		if arr.size() <= Mesh.ARRAY_VERTEX or not (arr[Mesh.ARRAY_VERTEX] is PackedVector3Array):
			continue
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx := PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] is PackedInt32Array and (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
			idx = arr[Mesh.ARRAY_INDEX]
		else:
			idx.resize(v.size())
			for i in v.size():
				idx[i] = i
		var xf := to_body * mi.global_transform
		for t in range(0, idx.size() - 2, 3):
			var a := xf * v[idx[t]]
			var b := xf * v[idx[t + 1]]
			var c := xf * v[idx[t + 2]]
			var nrm := (b - a).cross(c - a)
			if nrm.length() < 0.000001:
				continue
			if absf(nrm.normalized().y) >= collide_min_up:
				faces.append(a)
				faces.append(b)
				faces.append(c)
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.name = "Col_GlassRoof"
	cs.shape = shape
	body.add_child(cs)
	cs.set_meta("collision_group", "Col_GlassRoof")
	print("ShipGlass: %d roof-like glass triangles now solid (Col_GlassRoof on %s)" % [faces.size() / 3, body.name])


func _has_word(text: String, words: PackedStringArray) -> bool:
	var t := text.to_lower()
	for w in words:
		if t.contains(w):
			return true
	return false
