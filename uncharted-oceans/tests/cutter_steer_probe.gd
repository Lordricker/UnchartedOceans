extends SceneTree
## Steering probe for the cutter test scene: godot --headless --path uncharted-oceans --script res://tests/cutter_steer_probe.gd
func _init() -> void:
	var world := (load("res://scenes/world_cutter_test.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 240:
		await process_frame
	var rig := world.get_node("ShipRig") as Node3D
	var wheel = rig.get_node_or_null("ShipWheel")
	var helm = rig.get_node_or_null("ShipHelm")
	print("PROBE wheel node=", wheel != null, " tiller_mode=", wheel.get("_tiller_mode") if wheel else "-", " grabs='", wheel.get("_wheel").name if wheel and wheel.get("_wheel") else "none", "' helm=", helm != null)
	if wheel == null or wheel.get("_wheel") == null:
		quit(); return
	var tiller := wheel.get("_wheel") as Node3D
	var tip_local: Vector3 = wheel.get("_tiller_tip")
	var inv := rig.global_transform.affine_inverse()
	var cam := world.get_node("Player/Head/Camera3D") as Camera3D
	# 1. can the player take hold of it from the start spot?
	var mid := tiller.global_transform * (tip_local * 0.8)
	cam.look_at(mid)
	print("PROBE aim at handle -> ", wheel.call("_aim_point") != null, " | looking dead ahead -> ", _look_ahead(cam, wheel))
	# 2. steer: mouse right pushes the handle to starboard
	cam.look_at(mid)
	var p = wheel.call("_aim_point")
	wheel.call("_grab", p)
	var tip0 := inv * (tiller.global_transform * tip_local)
	wheel.call("_drag", Vector2(150, 0))
	for i in 4:
		await process_frame
	var tip1 := inv * (tiller.global_transform * tip_local)
	print("PROBE mouse right 150px: turn(deg)=", snappedf(rad_to_deg(wheel.get("turn")), 0.1), " ship.rudder=", snappedf(rig.rudder, 0.01), " handle x ", snappedf(tip0.x, 0.01), " -> ", snappedf(tip1.x, 0.01), " (+x = starboard)")
	wheel.call("_release")
	# 3. the ship answers the rudder (sail physics off so the plain underway branch of ship_motion is used)
	var sails = rig.get_node_or_null("ShipSails")
	sails.set_physics_process(false)
	var harbor = get_first_node_in_group("ship_harbor")
	harbor.call("cast_off")
	print("PROBE after cast_off moored=", harbor.moored)
	rig.underway = true
	var res := {}
	for side in [1.0, -1.0]:
		wheel.set("turn", side * deg_to_rad(20.0))
		var h0 := float(rig.heading_deg)
		for i in 300:
			await physics_frame
		res[side] = snappedf(float(rig.heading_deg) - h0, 0.1)
		var tipx := (inv * (tiller.global_transform * tip_local)).x
		print("PROBE rudder ", "+20 (starboard)" if side > 0 else "-20 (port)", ": heading change ", res[side], " deg in 5 s (heading grows to port); handle x = ", snappedf(tipx, 0.01))
	quit()

func _look_ahead(cam: Camera3D, wheel) -> bool:
	cam.global_transform = Transform3D(cam.global_transform.basis.looking_at(Vector3.FORWARD * 1.0 + Vector3(0, 0.1, 0)), cam.global_position)
	return wheel.call("_aim_point") != null
