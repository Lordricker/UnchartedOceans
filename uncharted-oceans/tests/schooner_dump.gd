extends SceneTree
## Dumps the schooner's node tree (names, types, positions, glTF extras) to res://tests/schooner_tree.txt, so its rig
## data for ShipClasses can be written from the real model.
## Run:  godot --headless --path . -s res://tests/schooner_dump.gd

func _init() -> void:
	var root := (load("res://scenes/ships/schooner.tscn") as PackedScene).instantiate()
	var lines: Array[String] = []
	_walk(root, 0, lines)
	var f := FileAccess.open("res://tests/schooner_tree.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("wrote %d nodes" % lines.size())
	quit()


func _walk(n: Node, depth: int, out: Array[String]) -> void:
	var s := "%s%s [%s]" % ["  ".repeat(depth), n.name, n.get_class()]
	if n is Node3D:
		s += " pos=%s" % str((n as Node3D).position)
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		s += " aabb=%s" % str((n as MeshInstance3D).get_aabb())
	if n.has_meta("extras"):
		s += " extras=%s" % str(n.get_meta("extras"))
	out.append(s)
	for c in n.get_children():
		_walk(c, depth + 1, out)
