extends Node
## Temporary check of the port berths (delete when done). Writes res://tests/berth_report.txt, then quits.

var out := PackedStringArray()
var world: Node
var streamer: WorldStreamer
var ship: Node3D
var harbor: ShipHarbor

func _ready() -> void:
	_run.call_deferred()

func _log(s: String) -> void:
	out.append(s)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _wall_check(b: DockBerth) -> String:
	var space := get_viewport().world_3d.direct_space_state
	var r := b.right2()
	var o := b.global_position
	var res := []
	for side in [-1.0, 1.0]:
		var p := o + Vector3(r.x, 0.0, r.y) * side * 1.0
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 8.0, p + Vector3.DOWN * 4.0)
		var h := space.intersect_ray(q)
		res.append("none" if h.is_empty() else "%.2f" % h.position.y)
	return "pier-side ray y=%s, water-side ray y=%s" % [res[0], res[1]]

func _run() -> void:
	await _wait(0.5)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _wait(2.0)
	world = get_parent().get_node("World")
	streamer = world.get_node("WorldStreamer") as WorldStreamer
	ship = world.get_node("ShipRig") as Node3D
	harbor = ship.get_node_or_null("ShipHarbor") as ShipHarbor
	_log("ShipHarbor present: %s" % str(harbor != null))
	_log("ports loaded: %s" % str(streamer.port_ids()))
	var berths := get_tree().get_nodes_in_group("dock_berths")
	_log("dock_berths in the home port: %d" % berths.size())
	for n in berths:
		var b := n as DockBerth
		_log("  %s class=%d heading=%.1f pos=(%.1f, %.1f, %.1f)  %s" % [b.name, b.max_ship_class, b.berth_heading,
			b.global_position.x, b.global_position.y, b.global_position.z, _wall_check(b)])
	if harbor == null or harbor.berth == null:
		_log("no nearest berth: stopping")
		_finish()
		return
	var nb := harbor.berth
	_log("nearest berth: %s, ship %.1f m from its wall point" % [nb.name, ship.global_position.distance_to(nb.global_position)])
	_log("start state (brig, Medium): %s" % str(harbor.berth_state()))
	_log("start status: %s" % harbor.status_text().replace("\n", " | "))
	# park her exactly in the slot, lined up, no way on, and moor
	var slot := nb.slot_position(harbor._ship_class())
	ship.global_position = Vector3(slot.x, ship.global_position.y, slot.z)
	ship.set("heading_deg", nb.berth_heading)
	harbor._set_velocity(Vector2.ZERO)
	await _wait(1.0)
	_log("in the slot: can_moor=%s state=%s" % [str(harbor.can_moor()), str(harbor.berth_state())])
	harbor.toggle_moor()
	await _wait(5.0)
	var sl2 := nb.slot_position(harbor._ship_class())
	_log("after E: moored=%s settle=%.2f gangway_out=%s ropes_visible=%s" % [str(harbor.moored), harbor.settle, str(harbor._gang_out), str(harbor._rope_node.visible)])
	_log("ship at (%.2f, %.2f), slot (%.2f, %.2f), heading %.1f vs berth %.1f" % [ship.global_position.x, ship.global_position.z, sl2.x, sl2.z, float(ship.get("heading_deg")), nb.berth_heading])
	var bol := nb.bollards_world()
	_log("bollards: %s" % str(bol))
	_log("status: %s" % harbor.status_text().replace("\n", " | "))
	harbor.cast_off()
	await _wait(1.0)
	_log("after cast off: moored=%s" % str(harbor.moored))
	# the quay wall: start her in the slot and drive her at the pier at 2 m/s; the hull must stop at the wall
	var r2 := nb.right2()
	ship.global_position = Vector3(slot.x, ship.global_position.y, slot.z)
	ship.set("heading_deg", nb.berth_heading)
	harbor._set_velocity(-r2 * 2.0)
	for t in 8:
		await _wait(0.25)
		var off := Vector2(ship.global_position.x - nb.global_position.x, ship.global_position.z - nb.global_position.z).dot(r2)
		_log("  wall test t=%.2f s: centre %.2f m off the wall (hull edge %.2f m), speed %.2f m/s" % [0.25 * (t + 1), off, off - 3.5, harbor._velocity().length()])
	_log("wall test: _push_sign=%.0f, message='%s'" % [harbor._push_sign, harbor.message])
	# the second capital: load its scene, run the same berth maker on it, free it again
	var path: String = String(streamer.port_scenes.get("CC02", ""))
	if path != "" and ResourceLoader.exists(path):
		var node := (load(path) as PackedScene).instantiate() as Node3D
		node.position = Vector3(3000.0, 0.0, 3000.0)
		world.add_child(node)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var made := streamer._make_berths(node)
		_log("Ottoman scene: %d berths made" % made)
		for d in node.find_children("*Berth_*", "Node3D", true, false):
			if d is DockBerth:
				var db := d as DockBerth
				_log("  %s class=%d heading=%.1f  %s" % [db.name, db.max_ship_class, db.berth_heading, _wall_check(db)])
		node.queue_free()
	else:
		_log("Ottoman scene not found: %s" % path)
	_finish()

func _finish() -> void:
	var f := FileAccess.open("res://tests/berth_report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out) + "\n")
		f.close()
	get_tree().quit()
