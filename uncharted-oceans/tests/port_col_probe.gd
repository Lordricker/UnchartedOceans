extends SceneTree
## godot --headless --path uncharted-oceans --script res://tests/port_col_probe.gd -- ports=PortCapital,PortCapital_Asian
func _init() -> void:
	var names := PackedStringArray(["PortCapital"])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("ports="): names = a.substr(6).split(",")
	for p in names:
		var ps := load("res://assets/port/%s.glb" % p) as PackedScene
		var inst := ps.instantiate()
		root.add_child(inst)
		var bodies := inst.find_children("*", "StaticBody3D", true, false)
		var trunks := 0
		var auto_cols := 0
		var meshes := inst.find_children("*", "MeshInstance3D", true, false)
		var uncovered := {}
		for b in bodies:
			if String(b.name) == "TrunkCol": trunks += 1
			if String(b.name).ends_with("_Col"): auto_cols += 1
		for m in meshes:
			var covered := false
			for c in m.get_children():
				if c is StaticBody3D: covered = true
			if m.get_parent() is StaticBody3D: covered = true
			if not covered:
				var key := String(m.name).split(".")[0]
				key = key.rstrip("0123456789_")
				uncovered[key] = int(uncovered.get(key, 0)) + 1
		print("PROBE %s bodies=%d trimesh_cols=%d trunks=%d meshes=%d uncovered_groups=%d" % [p, bodies.size(), auto_cols, trunks, meshes.size(), uncovered.size()])
		var keys := uncovered.keys()
		keys.sort_custom(func(a, b): return uncovered[a] > uncovered[b])
		for k in keys.slice(0, 25):
			print("   UNCOVERED ", k, " x", uncovered[k])
		inst.queue_free()
	quit()
