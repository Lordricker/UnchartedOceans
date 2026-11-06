extends SceneTree
## Climbing + wind-vane probe for the cutter test scene: godot --headless --path uncharted-oceans --script res://tests/cutter_climb_probe.gd
func _init() -> void:
	var world := (load("res://scenes/world_cutter_test.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 240:
		await process_frame
	var rig := world.get_node("ShipRig") as Node3D
	var inv := rig.global_transform.affine_inverse()
	var rigging = rig.get_node_or_null("ShipRigging")
	print("PROBE rigging node=", rigging != null, " masts=", rigging._masts.keys() if rigging else "-", " hull ladders=", rigging._hull_ladders if rigging else "-")
	var ladders := get_nodes_in_group("ship_ladders")
	for lad in ladders:
		var cs := lad.call("_box") as CollisionShape3D
		var c: Vector3 = inv * cs.global_position
		var b: Basis = inv.basis * cs.global_transform.basis
		print("PROBE ladder ", lad.name, " id=", lad.get("rigging_id"), " centre ", c.snappedf(0.01), " size ", (cs.shape as BoxShape3D).size.snappedf(0.01), " up ", b.y.snappedf(0.01), " away ", b.z.snappedf(0.01))
	# a swimmer beside the starboard side (+x) and the port side: do the boxes catch them?
	for side in [1.0, -1.0]:
		var feet := rig.to_global(Vector3(side * 1.62, -0.35, 0.2))
		var head := feet + Vector3.UP * 1.0
		var hit := false
		for lad in ladders:
			if String(lad.name).begins_with("HullLadder_") and lad.call("body_in_box", feet, head, 0.0):
				hit = true
		print("PROBE swimmer at x=", side * 1.62, " caught by a hull ladder: ", hit)
	# the shroud: climb to the top of the port net and see where we end up
	var pl := world.get_node("Player") as CharacterBody3D
	var net = null
	for lad in ladders:
		if lad.get("rigging_id") == "shroud_a": net = lad
	if net != null and rigging != null:
		var cs2 := net.call("_box") as CollisionShape3D
		var half: Vector3 = net.call("half_size")
		pl.global_position = cs2.global_transform * Vector3(0, half.y - 0.12, 0) - Vector3.UP * float(pl.get("player_height")) * 0.5
		pl.set("ladder", net)
		for i in 90:
			await physics_frame
		print("PROBE at the top of the net -> in nest=", rigging._in_nest, " player ship-local ", (inv * pl.global_position).snappedf(0.01), "  (perch is around x=0, y=8.1, z=-1.35)")
	# the wind-vane
	var sock = rig.get_node_or_null("Windsock")
	print("PROBE windsock node=", sock != null, " at ship-local ", sock.position.snappedf(0.01) if sock else "-", " pole ", sock.pole_height if sock else "-", "  (staff foot should be x=+0.57, y=1.5, z=1.6)")
	quit()
