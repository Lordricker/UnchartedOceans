extends SceneTree
## Probe for the cutter test scene (run: godot --headless --path uncharted-oceans --script res://tests/cutter_probe.gd).
## Prints where the cutter lies, where the player stands, whether the gangway is out, and swings the spanker to check its pivot.
func _init() -> void:
	var scn := load("res://scenes/world_cutter_test.tscn") as PackedScene
	var world := scn.instantiate()
	root.add_child(world)
	for i in 240:
		await process_frame
	var rig := world.get_node("ShipRig") as Node3D
	var player := world.get_node("Player") as Node3D
	var harbor = get_first_node_in_group("ship_harbor")
	print("PROBE ship_class=", rig.get("ship_class"), " heading=", snappedf(float(rig.get("heading_deg")), 0.1))
	if harbor != null:
		print("PROBE moored=", harbor.moored, " settle=", snappedf(harbor.settle, 0.1), " berth=", harbor.berth.name if harbor.berth != null else "none")
		var g = harbor.get_node_or_null("Gangway")
		print("PROBE gangway out=", g != null and g.visible)
	var pl := rig.global_transform.affine_inverse() * player.global_position
	print("PROBE player (ship-local) = ", pl, "   (tiller station is z=+4.3, deck 0.3)")
	var sails = rig.get_node_or_null("ShipSails")
	if sails != null:
		var boom := rig.find_child("Spanker_Boom", true, false) as Node3D
		var gaff := rig.find_child("Spanker_Gaff", true, false) as Node3D
		var sail := rig.find_child("Sail_Spanker", true, false) as Node3D
		var inv := rig.global_transform.affine_inverse()
		var o0 := inv * boom.global_position
		var y0 := (inv.basis * boom.global_transform.basis).get_euler().y
		for r in sails.recs:
			if r.id == "Spanker":
				r.model.theta = deg_to_rad(40.0)
				r.model.lee = 1.0
				r.progress = 0.0                      # 0 = set (start_furled puts it at 1)
				for k in 90:
					sails._apply_visual(r, 0.05)
		var tip0 := inv * boom.to_global(Vector3(0, 0, 0))
		var o1 := inv * boom.global_position
		var y1 := (inv.basis * boom.global_transform.basis).get_euler().y
		var s1 := (inv.basis * sail.global_transform.basis).get_euler().y
		var top := rig.find_child("Spanker_Topsail", true, false) as Node3D
		var t1 := (inv.basis * top.global_transform.basis).get_euler().y
		var g1 := (inv.basis * gaff.global_transform.basis).get_euler().y
		print("PROBE spanker pivot z in class data = ", ShipClasses.data(0).get("rig", {}).get("spanker_pivot_z"))
		print("PROBE boom origin before ", o0, " after ", o1, "  (gooseneck must stay put)")
		print("PROBE swing angles deg: boom ", snappedf(rad_to_deg(y1 - y0), 0.1), " gaff ", snappedf(rad_to_deg(g1 - y0), 0.1), " sail ", snappedf(rad_to_deg(s1 - y0), 0.1), " topsail ", snappedf(rad_to_deg(t1 - y0), 0.1))
	quit()
