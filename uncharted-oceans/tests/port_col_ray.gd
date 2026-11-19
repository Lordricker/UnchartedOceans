extends SceneTree
## Rays at props to prove the player can't walk through them. godot --headless --path uncharted-oceans --script res://tests/port_col_ray.gd
const CASES := {
	"PortCapital": ["Cap_Prop_Barrel", "Cap_Prop_Crate_A", "Cap_Prop_LampPost", "Cap_Terrace_Table", "Cap_Prop_Bale"],
	"PortCapital_Ottoman": ["Ott_Prop_Barrel", "Ott_Prop_CrateA", "Ott_Prop_LampPost", "Ott_Int_Tavern_Table"],
	"PortCapital_African": ["Cap_Prop_WaterPot", "Cap_Animal_Goat", "Cap_Prop_HedgeSeg", "Cap_Mosque_Dome", "Cap_Prop_LanternPost", "Cap_Palace_Column"],
	"PortCapital_Asian": ["Cap_Ropewalk_Shed", "Cap_Tavern_Barrel", "Cap_Back_PathLantern", "Cap_Plaza_Well", "Cap_Ropewalk_SpinningWheel"],
}
func _init() -> void:
	_run()
func _run() -> void:
	for p in CASES:
		var inst := (load("res://assets/port/%s.glb" % p) as PackedScene).instantiate()
		root.add_child(inst)
		await physics_frame
		await physics_frame
		var space := root.get_world_3d().direct_space_state
		var hit := 0
		var tot := 0
		var miss := []
		for pat in CASES[p]:
			var ms := inst.find_children(pat + "*", "MeshInstance3D", true, false)
			for m in ms.slice(0, 4):
				var mi := m as MeshInstance3D
				var c: Vector3 = mi.global_transform * mi.mesh.get_aabb().get_center()
				var r := maxf(mi.mesh.get_aabb().size.x, mi.mesh.get_aabb().size.z) * 0.5 * maxf(mi.global_transform.basis.get_scale().x, 0.001)
				var found := false
				for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
					var q := PhysicsRayQueryParameters3D.create(c + dir * (r + 1.5), c)
					q.collision_mask = 1
					if not space.intersect_ray(q).is_empty():
						found = true
						break
				tot += 1
				if found: hit += 1
				else: miss.append(String(mi.name))
		print("RAY %s %d/%d solid  missing=%s" % [p, hit, tot, miss])
		inst.queue_free()
		await process_frame
	quit()
