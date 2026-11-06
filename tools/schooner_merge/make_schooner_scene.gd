extends SceneTree
## Builds / maintains scenes/ships/schooner.tscn: the schooner model plus the climbing zones and points as real nodes you can move in the editor.
##
##   godot --headless --path uncharted-oceans --script <repo>/tools/schooner_merge/make_schooner_scene.gd
##
## Safe to re-run. If the scene already exists it is loaded as it is (your moved and resized boxes stay exactly as you left them)
## and only nodes that are MISSING are added, from the defaults below. When nothing is missing the file is not touched at all.
## Options (after a lone "--"):
##   --rebuild          ignore the existing scene and start again from the defaults below (overwrites your edits)
##   --in=res://...     read this scene instead of the default one
##   --out=res://...    write to this scene instead (handy for trying a rebuild without touching yours)
##
## The defaults below are the zones and points as you left them in the editor on 2026-11-05 (hull ladders, the four shroud nets, hold ladder,
## the two perches and the net tops). Ship frame: bow is -Z, +X is starboard, +Y up. A zone's +Y is "up the ladder" and its +Z points AWAY from
## the ship (toward where you climb from). "xform" is the zone's transform and "box" the Box shape's transform inside it, both as the 12 numbers
## the .tscn writes (the three basis rows, then the origin); "size" is the Box shape's (across, up, in/out).
## To refresh these defaults after moving things again, copy the numbers out of schooner.tscn (or ask for the script to be regenerated).

const SCENE := "res://scenes/ships/schooner.tscn"
const MODEL := "res://assets/ships/schooner/Schooner.glb"


func _t(a: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(a[0], a[3], a[6]), Vector3(a[1], a[4], a[7]), Vector3(a[2], a[5], a[8])), Vector3(a[9], a[10], a[11]))


func _zone(parent: Node, owner_: Node, z: Dictionary) -> void:
	var a := Area3D.new()
	a.name = z["name"]
	a.set_script(load("res://scripts/ship_ladder.gd"))
	a.transform = _t(z["xform"])
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
	cs.transform = _t(z["box"])
	a.add_child(cs)
	cs.owner = owner_


func _point(parent: Node, owner_: Node, p: Dictionary) -> void:
	var m := Marker3D.new()
	m.name = p["name"]
	m.set_script(load("res://scripts/ship_climb_point.gd"))
	m.set("point_id", p["id"])
	m.set("mast", p["mast"])
	m.position = p["pos"]
	parent.add_child(m)
	m.owner = owner_


func _zones() -> Array:
	return [
		{"name": "HullLadder_Port", "xform": [0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0, -2.3, 0.9, -0.7],
			"size": Vector3(0.455884, 2.594788, 0.4), "box": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, -8.5e-05, 0.122394, 0.15], "props": {}},
		{"name": "HullLadder_Stbd", "xform": [0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 2.3, 0.9, -0.7],
			"size": Vector3(0.464795, 2.456909, 0.4), "box": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.009302, 0.053455, 0.15], "props": {}},
		{"name": "Shroud_Fore_Port", "xform": [0.0, 0.233547, -0.972345, -0.036952, 0.971681, 0.233388, 0.999317, 0.03593, 0.00863, -1.17667, 6.43667, -3.11667],
			"size": Vector3(0.560937, 7.864275, 0.175), "box": [1.0, 1e-06, 0.0, -0.0, 1.0, 0.0, 0.0, -1e-06, 1.0, 0.013477, 0.485376, 0.0], "props": {"grab_slack": 0.5, "snap_depth": true, "center_on_grab": false, "rigging_id": "shroud_a", "rigging_mast": "fore"}},
		{"name": "Shroud_Fore_Stbd", "xform": [0.0, -0.233547, 0.972345, 0.036952, 0.971681, 0.233388, -0.999317, 0.03593, 0.00863, 1.17667, 6.43667, -3.11667],
			"size": Vector3(0.668298, 7.901986, 0.175), "box": [1.0, -3e-06, -1e-06, 0.0, 1.000001, 0.0, 0.0, -3e-06, 1.0, 0.008502, 0.46652, 0.0], "props": {"grab_slack": 0.5, "snap_depth": true, "center_on_grab": false, "rigging_id": "shroud_b", "rigging_mast": "fore"}},
		{"name": "Shroud_Main_Port", "xform": [0.0, 0.228723, -0.973491, -0.040546, 0.972691, 0.228535, 0.999178, 0.039471, 0.009274, -1.27167, 6.88667, 2.41667],
			"size": Vector3(0.694971, 8.830811, 0.175), "box": [1.0, 0.0, 0.0, -0.0, 1.000001, 0.0, -0.0, -0.0, 1.000009, 0.002271, 0.463744, 1e-06], "props": {"grab_slack": 0.5, "snap_depth": true, "center_on_grab": false, "rigging_id": "shroud_a"}},
		{"name": "Shroud_Main_Stbd", "xform": [0.0, -0.228723, 0.973491, 0.040546, 0.972691, 0.228535, -0.999178, 0.039471, 0.009274, 1.27167, 6.88667, 2.41667],
			"size": Vector3(0.683496, 8.885498, 0.175), "box": [1.0, 0.0, -0.0, 0.0, 1.000001, 0.0, 0.0, -0.0, 1.000009, 0.009717, 0.436403, 1e-06], "props": {"grab_slack": 0.5, "snap_depth": true, "center_on_grab": false, "rigging_id": "shroud_b"}},
		{"name": "HoldLadder", "xform": [-1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0, 0.0, -1.0, -0.58],
			"size": Vector3(0.376221, 2.3, 0.1), "box": [1.0, 0.0, 0.0, 0.0, 0.990975, 0.134048, 0.0, -0.134048, 0.990975, 0.009644, 1.15, -0.12941], "props": {}},
	]


func _points() -> Array:
	# where the rigging climb puts you ("barrel" is the perch; shroud_top_a / _b are the port / starboard net tops)
	return [
		{"name": "Perch_Main", "pos": Vector3(0.0, 12.3, 2.66), "id": "barrel", "mast": "main"},
		{"name": "ShroudTop_Main_Port", "pos": Vector3(-0.5, 11.38, 2.62), "id": "shroud_top_a", "mast": "main"},
		{"name": "ShroudTop_Main_Stbd", "pos": Vector3(0.5, 11.38, 2.62), "id": "shroud_top_b", "mast": "main"},
		{"name": "Perch_Fore", "pos": Vector3(0.0, 10.9, -2.95), "id": "barrel", "mast": "fore"},
		{"name": "ShroudTop_Fore_Port", "pos": Vector3(-0.5, 10.48, -2.94), "id": "shroud_top_a", "mast": "fore"},
		{"name": "ShroudTop_Fore_Stbd", "pos": Vector3(0.5, 10.48, -2.94), "id": "shroud_top_b", "mast": "fore"},
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
		root_n.name = "SchoonerShip"
		var model := (load(MODEL) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
		model.name = "Schooner"
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
