extends SceneTree
## Headless smoke test of one small port (PortSmall_<ID>.glb): does it load as the home port, are the berth, the six market
## stallholders, the colliders, the lights and the trees there, and can you stand on the quay and the pier?
## godot --headless --path <project> --script res://tests/small_ports_probe.gd -- AS04

var fails := 0

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("   " + extra if extra != "" else ""))
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func ray_hit(port: Node3D, x: float, z: float) -> Dictionary:
	var space := root.world_3d.direct_space_state
	var a := port.to_global(Vector3(x, 60.0, z))
	var b := port.to_global(Vector3(x, -10.0, z))
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b))

func ray_y(port: Node3D, x: float, z: float) -> float:
	var h := ray_hit(port, x, z)
	if h.is_empty():
		return -999.0
	return port.to_local(h["position"] as Vector3).y

func count_type(n: Node, t: String) -> int:
	return n.find_children("*", t, true, false).size()

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var pid: String = args[0] if args.size() > 0 else "AS04"
	var scene: Node = (load("res://scenes/world_test.tscn") as PackedScene).instantiate()
	var st: WorldStreamer = scene.get_node("WorldStreamer")
	st.home_port_id = pid
	root.add_child(scene)
	await frames(240)
	var port: Node3D = st.get_node_or_null("Port_" + pid)
	check("port %s spawned as a real scene" % pid, port != null and port.has_meta("own_grounding"))
	if port == null:
		print("RESULT: %d failures" % fails)
		quit(1)
		return
	var mine: Array = []
	for b in get_nodes_in_group("dock_berths"):
		if port.is_ancestor_of(b):
			mine.append(b)
	check("one dock berth in the port", mine.size() == 1, str(mine.size()))
	if mine.size() == 1:
		var lp := port.to_local((mine[0] as Node3D).global_position)
		check("berth sits on the pier's east face, at sea level", absf(lp.x - 2.25) < 0.3 and absf(lp.y) < 0.2 and absf(lp.z - 50.0) < 0.3, str(lp))
	var n_mine := 0
	for n in get_nodes_in_group("market_npcs"):
		if port.is_ancestor_of(n):
			n_mine += 1
	check("six stallholders (market bays filled)", n_mine == 6, str(n_mine))
	check("colliders were made", count_type(port, "StaticBody3D") >= 20, str(count_type(port, "StaticBody3D")))
	check("lights were made", count_type(port, "OmniLight3D") >= 12, str(count_type(port, "OmniLight3D")))
	var veg := 0
	for n in port.find_children("Veg_*", "Node3D", true, false):
		if n.get_child_count() > 0:
			veg += 1
	check("trees and shrubs instanced", veg >= 40, str(veg))
	var ship: Node3D = scene.get_node("ShipRig")
	print("INFO  ship is %.1f m from the berth centre" % ship.global_position.distance_to(port.to_global(Vector3(10.95, 0.0, 50.0))))
	var deck := ray_y(port, 0.0, 30.0)
	check("pier deck is 1.85 m above the water", absf(deck - 1.85) < 0.1, "%.2f" % deck)
	var quay := ray_y(port, 0.0, -15.0)
	check("quay deck is 1.85 m above the water", absf(quay - 1.85) < 0.15, "%.2f" % quay)
	var quay_w := ray_y(port, 24.0, -10.0)
	check("quay reaches the wide corners", absf(quay_w - 1.85) < 0.15, "%.2f" % quay_w)
	check("open water beside the pier", ray_y(port, 30.0, 30.0) < -100.0)
	var land := ray_y(port, 0.0, -120.0)
	check("land behind the quay", land > 1.0, "%.2f" % land)
	var mole := ray_y(port, -40.0, 10.0)
	check("mole is walkable", absf(mole - 1.85) < 0.2, "%.2f" % mole)
	# nothing but the moored brig is solid in the water lane east of the pier
	var hits: Array = []
	for z in range(20, 96, 8):
		for x in range(8, 60, 8):
			var h := ray_hit(port, float(x), float(z))
			if h.is_empty():
				continue
			var c := h["collider"] as Node
			if c != null and (ship.is_ancestor_of(c) or c == ship):
				continue
			hits.append("%s at (%d, %d)" % [c.name if c != null else "?", x, z])
	check("water east of the berth is clear of solids", hits.is_empty(), str(hits))
	# the tavern copied from the capital: four mate seats, a barkeep spot, an entry marker and a floor to stand on
	var seats := 0
	var entry: Node3D = null
	var barkeep := 0
	for m in get_nodes_in_group("markers"):
		if not port.is_ancestor_of(m):
			continue
		var kind := str(m.get_meta("marker", ""))
		if kind == "mate_seat":
			seats += 1
		elif kind == "interior_entry":
			entry = m as Node3D
		elif kind == "npc_stand" and str(m.get_meta("interaction", "")) == "tavern":
			barkeep += 1
	check("tavern has four mate seats", seats == 4, str(seats))
	check("tavern has a barkeep spot", barkeep == 1, str(barkeep))
	check("tavern has an interior entry marker", entry != null)
	if entry != null:
		var space2 := root.world_3d.direct_space_state
		var a2 := entry.global_position + Vector3.UP * 1.2
		var h2 := space2.intersect_ray(PhysicsRayQueryParameters3D.create(a2, a2 + Vector3.DOWN * 3.0))
		check("floor under the tavern entry", not h2.is_empty() and absf(port.to_local(h2["position"] as Vector3).y - 1.85) < 0.3, str(h2.get("position", "none")))
	print("RESULT: %d failures" % fails)
	quit(1 if fails > 0 else 0)
