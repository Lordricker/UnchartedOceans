extends SceneTree
## Builds / maintains scenes/ships/fluyt.tscn: the fluyt model, the moving ropes, and the climbing zones and points as real nodes you can move in the editor.
##
##   godot --headless --path uncharted-oceans --script <repo>/tools/fluyt_merge/make_fluyt_scene.gd
##
## Safe to re-run: an existing scene is loaded as it is (your moved boxes stay) and only MISSING nodes are added from the defaults below.
## Options (after a lone "--"): --rebuild (start again from the defaults), --in=res://..., --out=res://...
##
## Ship frame: bow is -Z, +X is starboard, +Y up (the model is exported bow +Z and turned 180 degrees about Y here). A climbing zone's +Y is "up the ladder"
## and its +Z points AWAY from the ship. The nets are given by where they start and end (ship frame) and are turned to fit: measured from the
## Ratlines / FuttockShrouds meshes of FluytShip.blend (Blender x is minus ship x, Blender y is ship z).

const SCENE := "res://scenes/ships/fluyt.tscn"
const MODEL := "res://assets/ships/fluyt/Fluyt.glb"

# name, base (bottom of the net, a little under the rail), top, width, rigging_id (shroud_a = port, shroud_b = starboard), mast, which side is outward (-1 port, +1 starboard)
func _nets() -> Array:
	var out: Array = []
	for s in [[-1, "Port", "shroud_a"], [1, "Stbd", "shroud_b"]]:
		var sg: float = s[0]
		out.append({"name": "Shroud_Fore_" + s[1], "base": Vector3(2.9 * sg, 2.6, -6.25), "top": Vector3(0.9 * sg, 11.3, -6.3), "width": 1.5, "id": s[2], "mast": "fore", "out": sg})
		out.append({"name": "Shroud_Main_" + s[1], "base": Vector3(3.3 * sg, 2.6, -0.45), "top": Vector3(0.85 * sg, 13.4, -0.45), "width": 1.6, "id": s[2], "mast": "main", "out": sg})
		out.append({"name": "Shroud_Mizzen_" + s[1], "base": Vector3(1.9 * sg, 4.6, 9.8), "top": Vector3(0.7 * sg, 8.9, 10.3), "width": 1.4, "id": s[2], "mast": "mizzen", "out": sg})
	return out


func _points() -> Array:
	# "barrel" is the top of the nets (the lookout); shroud_top_a / _b are the port / starboard net tops
	return [
		{"name": "Perch_Fore", "pos": Vector3(0.0, 13.2, -6.61), "id": "barrel", "mast": "fore"},
		{"name": "Perch_Main", "pos": Vector3(0.0, 15.2, -0.85), "id": "barrel", "mast": "main"},
		{"name": "ShroudTop_Fore_Port", "pos": Vector3(-0.7, 11.4, -6.67), "id": "shroud_top_a", "mast": "fore"},
		{"name": "ShroudTop_Fore_Stbd", "pos": Vector3(0.7, 11.4, -6.67), "id": "shroud_top_b", "mast": "fore"},
		{"name": "ShroudTop_Main_Port", "pos": Vector3(-0.7, 13.4, -0.9), "id": "shroud_top_a", "mast": "main"},
		{"name": "ShroudTop_Main_Stbd", "pos": Vector3(0.7, 13.4, -0.9), "id": "shroud_top_b", "mast": "main"},
		{"name": "ShroudTop_Mizzen_Port", "pos": Vector3(-0.64, 8.9, 10.32), "id": "shroud_top_a", "mast": "mizzen"},
		{"name": "ShroudTop_Mizzen_Stbd", "pos": Vector3(0.64, 8.9, 10.32), "id": "shroud_top_b", "mast": "mizzen"},
	]


func _add_zone(parent: Node, owner_: Node, name_: String, xf: Transform3D, size: Vector3, box_off: Vector3, props: Dictionary) -> void:
	var a := Area3D.new()
	a.name = name_
	a.set_script(load("res://scripts/ship_ladder.gd"))
	a.transform = xf
	for k in props.keys():
		a.set(k, props[k])
	parent.add_child(a)
	a.owner = owner_
	var cs := CollisionShape3D.new()
	cs.name = "Box"
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = box_off
	a.add_child(cs)
	cs.owner = owner_


func _net(parent: Node, owner_: Node, n: Dictionary) -> void:
	var b: Vector3 = n["base"]
	var t: Vector3 = n["top"]
	var up := (t - b).normalized()
	var outward := Vector3(float(n["out"]), 0.0, 0.0)
	var z := (outward - up * outward.dot(up)).normalized()
	var x := up.cross(z).normalized()
	var xf := Transform3D(Basis(x, up, z), (b + t) * 0.5)
	_add_zone(parent, owner_, n["name"], xf, Vector3(float(n["width"]), (t - b).length(), 0.175), Vector3.ZERO,
		{"grab_slack": 0.5, "snap_depth": true, "center_on_grab": false, "rigging_id": n["id"], "rigging_mast": n["mast"]})


func _point(parent: Node, owner_: Node, p: Dictionary) -> void:
	var m := Marker3D.new()
	m.name = p["name"]
	m.set_script(load("res://scripts/ship_climb_point.gd"))
	m.set("point_id", p["id"])
	m.set("mast", p["mast"])
	m.position = p["pos"]
	parent.add_child(m)
	m.owner = owner_


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
		root_n.name = "FluytShip"
		var model := (load(MODEL) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
		model.name = "Fluyt"
		root_n.add_child(model)
		model.owner = root_n
		model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)       # the model is exported bow +Z; the game wants the bow at -Z
	var added: Array = []
	if root_n.get_node_or_null("RopeRigs") == null:
		var rr := Node.new()
		rr.name = "RopeRigs"
		rr.set_script(load("res://scripts/ship_rope_rigs.gd"))
		root_n.add_child(rr)
		rr.owner = root_n
		added.append("RopeRigs")
	var g := root_n.get_node_or_null("Climbing") as Node3D
	if g == null:
		g = Node3D.new()
		g.name = "Climbing"
		root_n.add_child(g)
		g.owner = root_n
		added.append("Climbing")
	for n in _nets():
		if g.get_node_or_null(NodePath(n["name"])) == null:
			_net(g, root_n, n)
			added.append(n["name"])
	# the ladder down into the hold (against the aft bulkhead of the hold, z 2.0; you climb it facing aft, so the zone's +Z points forward)
	if g.get_node_or_null("HoldLadder") == null:
		_add_zone(g, root_n, "HoldLadder", Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.32, 1.9)), Vector3(0.8, 4.2, 0.1), Vector3(0.0, 0.0, 0.15), {})
		added.append("HoldLadder")
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
