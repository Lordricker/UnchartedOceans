@tool
extends EditorScenePostImport
## Post-import script for the port .glb files (PortCapital, PortCapital_Ottoman, PortSmall_*), exported from Blender.
## Reads the Blender custom properties (glTF extras, stored as node metadata):
##   vis_begin / vis_end            -> visibility ranges
##   interaction / marker / npc_role-> groups "interactable", "markers" + meta
##   light_energy / light_range_m / light_color -> an OmniLight3D child
##   vegetation + scene            -> instances res://assets/vegetation/<name>.glb
## Collision: "-colonly"/"-convcolonly" objects already become StaticBody3D. On top of that the big
## static meshes (shells, arcades, floors, quay, interiors) get trimesh collision so the town is walkable.
## Every port collider goes on physics layer 1 (walkable) and 4 (island/port, like the test pier).
##
## Shared textures: the port .glb files embed identical 1K Poly Haven / tinted textures. Extracting them per glb made
## ~30 duplicate files per port. The glb import is set to embed images; this script then swaps every material texture
## whose pixels match a file in res://textures/port/shared/ for that single shared file. Only the shared copy is
## referenced by the saved scene, so it is stored once in the export. Textures with no match are kept as they are
## (and logged), so nothing goes missing.

const FADE := 6.0
const SHARED_DIR := "res://textures/port/shared/"
const TEX_PROPS := ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture", "emission_texture"]
const WALK_PREFIX := ["Cap_Town_", "Cap_Back_House_", "Cap_Bldg_", "Cap_Arcade_", "Cap_Piazza", "Cap_Quay", "Cap_Mole",
	"Cap_Breakwater", "Cap_Fountain", "Cap_Int_", "Cap_TavernInterior", "Cap_HallInterior", "Cap_Warehouse",
	"Cap_Shipyard", "Cap_Smithy", "Cap_Booth", "Cap_Yard", "Cap_Back_Hill", "Cap_Back_ShipYard", "Cap_LighthouseEast",
	"Cap_BeaconWest", "Cap_Stall", "Cap_Civic", "Cap_TreadCrane", "SP_"]

## Anything else a capital is built from (Cap_/Ott_/Asi_ meshes) is solid too, so the player cannot walk through props,
## stalls, fences, domes, trees and so on, except for the things below: decoration, glass, cloth, tiny items and doors.
const AUTO_PREFIX := ["Cap_", "Ott_", "Asi_"]
const SKIP_TOKENS := ["Window", "Glass", "Flag", "Banner", "Pennant", "RopeLine", "Strand", "Cloth", "Awning", "Canvas", "Sign", "Slate",
	"Scroll", "Sword", "Bolt", "Drape", "Tankard", "Bun", "Tart", "Cake", "Slice", "Lantern", "Chandelier", "HangSign",
	"Sack", "Shavings", "Net", "Fish", "Bird", "Smoke", "Steam", "Trim", "Fill", "Details", "Fittings", "HeadLamps",
	"SailCloth", "Bollard", "Ring", "Chain", "Coil", "Door_", "Gate_L", "Gate_R", "Curtain", "Carpet", "Rug"]
## Posts are solid even though their names contain a skipped word (Lantern, Lamp).
const SOLID_TOKENS := ["LanternPost", "LampPost", "PathLantern", "RopeWalk", "Ropewalk"]
const MIN_SOLID_M := 0.35
## Trunk collision for trees whose .glb has none: radius by species, height capped.
const TRUNK_R := {"Baobab": 1.6, "Mango": 0.45, "Palm": 0.25, "Banana": 0.0}

func _auto_solid(mi: MeshInstance3D, ex: Dictionary) -> bool:
	var nm := String(mi.name)
	var ok := false
	for p in AUTO_PREFIX:
		if nm.begins_with(p):
			ok = true
			break
	if not ok or mi.mesh == null or str(ex.get("game_role", "")) == "door":
		return false
	var forced := false
	for t in SOLID_TOKENS:
		if nm.contains(t):
			forced = true
	for t in SKIP_TOKENS:
		if nm.contains(t) and not forced:
			return false
	var sz := mi.mesh.get_aabb().size * mi.scale.abs()
	return maxf(sz.x, maxf(sz.y, sz.z)) >= MIN_SOLID_M

func _add_trunk(inst: Node, owner_scene: Node, species_name: String) -> void:
	if not inst.find_children("*", "StaticBody3D", true, false).is_empty():
		return   # the tree already has collision
	var r := 0.0
	for k in TRUNK_R:
		if species_name.contains(k):
			r = float(TRUNK_R[k])
	if r <= 0.0:
		return
	var h := 5.0 if r < 1.0 else 7.0
	var sb := StaticBody3D.new()
	sb.name = "TrunkCol"
	sb.collision_layer = 1 | 8
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.position = Vector3(0, h * 0.5, 0)
	sb.add_child(cs)
	inst.add_child(sb)
	sb.owner = owner_scene
	cs.owner = owner_scene

func _post_import(scene: Node) -> Object:
	_share_textures(scene)
	var trimesh: Array[MeshInstance3D] = []
	for n in _all(scene):
		var ex: Dictionary = _extras(n)
		if n is GeometryInstance3D and (ex.has("vis_begin") or ex.has("vis_end")):
			var g := n as GeometryInstance3D
			var b := float(ex.get("vis_begin", 0.0)); var e := float(ex.get("vis_end", 0.0))
			g.visibility_range_begin = b
			g.visibility_range_end = e
			g.visibility_range_end_margin = FADE if e > 0.0 else 0.0
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if ex.has("interaction"):
			n.add_to_group("interactable", true)
			n.set_meta("interaction", ex["interaction"])
		if ex.has("marker"):
			n.add_to_group("markers", true)
			for k in ["marker", "npc_role", "interaction"]:
				if ex.has(k): n.set_meta(k, ex[k])
		if str(ex.get("game_role", "")) == "door":
			n.add_to_group("doors", true)
		if ex.has("light_energy") and n is Node3D:
			var l := OmniLight3D.new()
			l.name = "Light"
			l.light_energy = float(ex["light_energy"])
			l.omni_range = float(ex.get("light_range_m", 5.0))
			var c = ex.get("light_color", [1.0, 0.75, 0.45])
			l.light_color = Color(float(c[0]), float(c[1]), float(c[2]))
			l.position = Vector3(0, 0.3, 0)
			l.distance_fade_enabled = true
			l.distance_fade_begin = 35.0
			l.distance_fade_length = 10.0
			n.add_child(l); l.owner = scene
		if ex.has("vegetation") and n is Node3D:
			var path := "res://assets/vegetation/%s.glb" % str(ex["vegetation"])
			if ResourceLoader.exists(path):
				var inst := (load(path) as PackedScene).instantiate()
				n.add_child(inst); inst.owner = scene
				_add_trunk(inst, scene, str(ex["vegetation"]))
		if n is MeshInstance3D and not (n.get_parent() is StaticBody3D):
			var walk := false
			for p in WALK_PREFIX:
				if String(n.name).begins_with(p):
					walk = true
					break
			if walk or _auto_solid(n as MeshInstance3D, ex):
				trimesh.append(n as MeshInstance3D)
		if n is StaticBody3D:
			(n as StaticBody3D).collision_layer = 1 | 8
	for mi in trimesh:
		if mi.mesh == null: continue
		var sb := StaticBody3D.new()
		sb.name = String(mi.name) + "_Col"
		sb.collision_layer = 1 | 8
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		sb.add_child(cs)
		mi.add_child(sb)
		sb.owner = scene; cs.owner = scene
	return scene

# ---- shared textures -------------------------------------------------------------------------------------------

## Pixel fingerprint of an image, ignoring format and mipmaps, so a decoded glb image and the same file on disk match.
func _img_key(img: Image) -> String:
	if img == null or img.is_empty():
		return ""
	var c: Image = img.duplicate()
	if c.is_compressed() and c.decompress() != OK:
		return ""
	c.clear_mipmaps()
	if c.get_format() != Image.FORMAT_RGBA8:
		c.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = c.get_data()
	return "%dx%d_%d_%d" % [c.get_width(), c.get_height(), data.size(), hash(data)]

## fingerprint -> shared texture path, built from every image in SHARED_DIR.
func _shared_index() -> Dictionary:
	var idx: Dictionary = {}
	var dir := DirAccess.open(SHARED_DIR)
	if dir == null:
		push_warning("port_import: %s not found, textures left as imported" % SHARED_DIR)
		return idx
	for f in dir.get_files():
		var ext := f.get_extension().to_lower()
		if ext != "jpg" and ext != "png":
			continue
		var img := Image.load_from_file(SHARED_DIR + f)
		var k := _img_key(img)
		if k != "":
			idx[k] = SHARED_DIR + f
	return idx

func _share_textures(scene: Node) -> void:
	var idx := _shared_index()
	if idx.is_empty():
		return
	var cache: Dictionary = {}   # shared path -> loaded Texture2D
	var mats: Array[Material] = []
	for n in _all(scene):
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null: continue
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m != null and not mats.has(m): mats.append(m)
				var o := mi.get_surface_override_material(s)
				if o != null and not mats.has(o): mats.append(o)
	var swapped := 0
	var kept: Array[String] = []
	for m in mats:
		if not (m is BaseMaterial3D):
			continue
		for prop in TEX_PROPS:
			var tex = m.get(prop)
			if not (tex is Texture2D):
				continue
			var path: String = idx.get(_img_key((tex as Texture2D).get_image()), "")
			if path == "":
				kept.append("%s.%s" % [m.resource_name, prop])
				continue
			if not cache.has(path):
				cache[path] = load(path)
			if cache[path] is Texture2D:
				m.set(prop, cache[path])
				swapped += 1
			else:
				kept.append("%s.%s (shared file not imported yet)" % [m.resource_name, prop])
	print("port_import[%s]: %d textures -> shared, %d kept %s" % [get_source_file().get_file(), swapped, kept.size(), kept])

# ---- helpers ---------------------------------------------------------------------------------------------------

func _extras(n: Node) -> Dictionary:
	if n.has_meta("extras"):
		var e = n.get_meta("extras")
		if e is Dictionary: return e
	return {}

func _all(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	var i := 0
	while i < out.size():
		out.append_array(out[i].get_children())
		i += 1
	return out
