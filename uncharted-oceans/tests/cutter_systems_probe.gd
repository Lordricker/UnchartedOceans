extends SceneTree
## Systems probe for the cutter: godot --headless --path uncharted-oceans --script res://tests/cutter_systems_probe.gd
func _init() -> void:
	var world := (load("res://scenes/world_cutter_test.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 240:
		await process_frame
	var rig := world.get_node("ShipRig") as Node3D
	var inv := rig.global_transform.affine_inverse()
	for n in ["ShipPump", "ShipBookshelf", "ShipBed", "ShipMap", "ShipLogLine", "ShipAnchor", "ShipGlass", "ShipInteract", "ShipDeckWater", "ShipDeckPatch", "Windsock", "ShipWheel", "ShipHelm", "ShipSails", "ShipRigging"]:
		print("PROBE system ", n, ": ", rig.get_node_or_null(n) != null)
	var pump = rig.get_node_or_null("ShipPump")
	if pump != null and pump.get("_brake") != null:
		var b := pump.get("_brake") as Node3D
		print("PROBE pump brake ", b.name, " at ship-local ", (inv * b.global_position).snappedf(0.01), " (starboard-aft cockpit: x~-0.6? z~2.5)")
	var shelf = rig.get_node_or_null("ShipBookshelf")
	if shelf != null:
		var sh := shelf.get("_shelf") as Node3D
		var vo: Vector3 = shelf.get("view_offset")
		var vt: Vector3 = shelf.get("view_target")
		print("PROBE shelf at ", (inv * sh.global_position).snappedf(0.01), " books ", shelf.get("_books").size(), " | camera spot ", (inv * (sh.global_transform * vo)).snappedf(0.01), " looking at ", (inv * (sh.global_transform * vt)).snappedf(0.01), "  (camera should be aft of the shelf, in the cabin)")
	var bed = rig.get_node_or_null("ShipBed")
	if bed != null:
		print("PROBE bed box in ship frame ", bed.get("_bed_box"), " ready=", bed.get("_bed_ready"))
	var map = rig.get_node_or_null("ShipMap")
	if map != null and map.get("_chart_mi") != null:
		print("PROBE chart ", (map.get("_chart_mi") as Node3D).name, " at ", (inv * (map.get("_chart_mi") as Node3D).global_position).snappedf(0.01))
	var sg := rig.find_child("SandGlass", true, false) as Node3D
	if sg != null:
		print("PROBE sand glass at ship-local ", (inv * sg.global_position).snappedf(0.01), "  (transom rim: x=-0.55, y~1.34, z~5.47)")
	var anc = rig.get_node_or_null("ShipAnchor")
	if anc != null:
		print("PROBE capstan mesh ", anc.get("_cap_mi") != null, " body ", anc.get("_body") != null, " | state before ", anc.state)
		get_first_node_in_group("ship_harbor").call("cast_off")
		for i in 20:
			await physics_frame
		anc.call("toggle")
		for i in 30:
			await physics_frame
		print("PROBE after toggle: state ", anc.state, " holds_ship ", anc.holds_ship())
	var fl = rig.get_node_or_null("Flooding")
	print("PROBE flooding node ", fl != null, " | pumps_on ", fl.get("pumps_on") if fl else "-")
	quit()
