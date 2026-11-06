extends SceneTree
## Builds / maintains scenes/ships/cutter.tscn: the cutter model plus the climbing zones and points as real nodes you can move in the editor.
##
##   godot --headless --path uncharted-oceans --script <repo>/tools/cutter_merge/make_cutter_scene.gd
##
## Safe to re-run. If the scene already exists it is loaded as it is (your moved and resized boxes stay exactly as you left them)
## and only nodes that are MISSING are added, from the defaults below. When nothing is missing the file is not touched at all.
## Options (after a lone "--"):
##   --rebuild          ignore the existing scene and start again from the defaults below (overwrites your edits)
##   --in=res://...     read this scene instead of the default one
##   --out=res://...    write to this scene instead (handy for trying a rebuild without touching yours)
##
## The defaults below are the box positions you set in the editor on 2026-11-03 (hull ladders, shroud nets, hold ladder, perch, tops).
## Frame of everything placed here (the ship's own frame): bow is -Z, +X is starboard, +Y up. A zone's +Y is "up the ladder" and its +Z
## points AWAY from the ship (toward where you climb from). Its Box shape is (across, up, in/out) in that frame, and sits at box_pos
## inside the zone (the zone's own origin is only where it is rotated about).

const SCENE := "res://scenes/ships/cutter.tscn"


func _zone(parent: Node, owner_: Node, z: Dictionary) -> void:
	var a := Area3D.new()
	a.name = z["name"]
	a.set_script(load("res://scripts/ship_ladder.gd"))
	var zz: Vector3 = (z["away"] as Vector3).normalized()
	var y: Vector3 = (z["up"] as Vector3).normalized()
	var x := y.cross(zz).normalized()
	a.transform = Transform3D(Basis(x, y, zz), z["pos"])
	var props: Dictionary = z["props"]
	for k in props.keys():
		a.set(k, props[k])
	parent.add_child(a)
	a.owner = owner_
	var cs := CollisionShape3D.new()
	cs.name = "Box"
	var box := BoxShape3D.new()
	box.size = z["size"]
	cs.shape = box
	cs.position = z["box_pos"]
	a.add_child(cs)
	cs.owner = owner_


func _point(parent: Node, owner_: Node, p: Dictionary) -> void:
	var m := Marker3D.new()
	m.name = p["name"]
	m.set_script(load("res://scripts/ship_climb_point.gd"))
	m.set("point_id", p["id"])
	m.set("mast", "main")
	m.position = p["pos"]
	parent.add_child(m)
	m.owner = owner_


func _zones() -> Array:
	var hull := {"grab_slack": 0.35, "snap_depth": false, "center_on_grab": true}
	var net_a := {"grab_slack": 0.5, "snap_depth": true, "center_on_grab": false, "rigging_id": "shroud_a", "rigging_mast": "main"}
	var net_b := {"grab_slack": 0.5, "snap_depth": true, "center_on_grab": false, "rigging_id": "shroud_b", "rigging_mast": "main"}
	return [
		# climbing back aboard from the water: beside the hull, top at the rail
		{"name": "HullLadder_Port", "pos": Vector3(-1.52, 0.65, 0.2), "up": Vector3(0, 1, 0), "away": Vector3(-1, 0, 0),
			"size": Vector3(0.7, 1.1995, 0.1271), "box_pos": Vector3(0.0, -0.1279, 0.1477), "props": hull},
		{"name": "HullLadder_Stbd", "pos": Vector3(1.52, 0.65, 0.2), "up": Vector3(0, 1, 0), "away": Vector3(1, 0, 0),
			"size": Vector3(0.7, 1.2083, 0.1271), "box_pos": Vector3(0.0, -0.1323, 0.1631), "props": hull},
		# the shroud nets: slanted boxes along the ratlines; the top of either takes you to the perch
		{"name": "Shroud_Port", "pos": Vector3(-0.83, 4.85, -1.7), "up": Vector3(0.2374, 0.9714, 0.0), "away": Vector3(-0.9714, 0.2374, 0.0),
			"size": Vector3(1.4, 5.4, 0.175), "box_pos": Vector3(0.0, 0.2924, 0.0), "props": net_a},
		{"name": "Shroud_Stbd", "pos": Vector3(0.83, 4.85, -1.7), "up": Vector3(-0.2374, 0.9714, 0.0), "away": Vector3(0.9714, 0.2374, 0.0),
			"size": Vector3(1.4, 5.4, 0.174), "box_pos": Vector3(0.0, 0.2521, 0.0146), "props": net_b},
		# the ladder at the aft edge of the cargo well (faces the bow: you climb it from inside the well)
		{"name": "HoldLadder", "pos": Vector3(0.0, 0.05, -2.56), "up": Vector3(0, 1, 0), "away": Vector3(0, 0, -1),
			"size": Vector3(0.5, 2.0, 0.1001), "box_pos": Vector3(0.0, 0.0, 0.0647), "props": hull},
	]


func _points() -> Array:
	# where the rigging climb puts you
	return [
		{"name": "Perch", "pos": Vector3(0.0, 8.1, -1.05), "id": "barrel"},
		{"name": "ShroudTop_Port", "pos": Vector3(-0.4, 7.2, -1.7), "id": "shroud_top_a"},
		{"name": "ShroudTop_Stbd", "pos": Vector3(0.4, 7.2, -1.7), "id": "shroud_top_b"},
	]


func _init() -> void:
	var rebuild := false
	var src := SCENE
	var out := SCENE
	for a in OS.get_cmdline_user_args():
		if a == "--rebuild":
			rebuild = true
		elif a.begins_with("--in="):
			src = a.substr(5)
		elif a.begins_with("--out="):
			out = a.substr(6)
	var root_n: Node3D
	var fresh := true
	if not rebuild and ResourceLoader.exists(src):
		root_n = (load(src) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as Node3D
		fresh = false
		print("MAKE keeping the existing scene ", src)
	else:
		root_n = Node3D.new()
		root_n.name = "CutterShip"
		var model := (load("res://assets/ships/cutter/Cutter.glb") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
		model.name = "Cutter"
		root_n.add_child(model)
		model.owner = root_n
		model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)       # the model is exported bow +Z; the game wants the bow at -Z
	var g := root_n.get_node_or_null("Climbing") as Node3D
	var added: Array = []
	if g == null:
		g = Node3D.new()
		g.name = "Climbing"
		root_n.add_child(g)
		g.owner = root_n
		added.append("Climbing")
	for z in _zones():
		if g.get_node_or_null(NodePath(z["name"])) == null:
			_zone(g, root_n, z)
			added.append(z["name"])
	for p in _points():
		if g.get_node_or_null(NodePath(p["name"])) == null:
			_point(g, root_n, p)
			added.append(p["name"])
	if not fresh and added.is_empty() and out == src:
		print("MAKE nothing missing; ", out, " left untouched")
		quit()
		return
	if not added.is_empty():
		print("MAKE added from defaults: ", added)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	var ps := PackedScene.new()
	var err := ps.pack(root_n)
	print("MAKE pack: ", err)
	err = ResourceSaver.save(ps, out)
	print("MAKE save: ", err, " -> ", out)
	quit()
