extends SceneTree
func _init() -> void:
	var inst := (load("res://assets/port/PortCapital_African.glb") as PackedScene).instantiate()
	root.add_child(inst)
	var n := 0
	for m in inst.find_children("Cap_Prop_Barrel*", "MeshInstance3D", true, false):
		print("BARREL ", m.name, " aabb=", m.mesh.get_aabb().size, " scale=", m.scale, " children=", m.get_child_count(), " parent=", m.get_parent().name)
		n += 1
		if n > 3: break
	for m in inst.find_children("Tree_Palm_A*", "Node3D", true, false):
		print("PALM ", m.name, " ", m.get_class(), " children=", m.get_child_count(), " parent=", m.get_parent().name, " parentcls=", m.get_parent().get_class())
		n += 1
		if n > 6: break
	quit()
