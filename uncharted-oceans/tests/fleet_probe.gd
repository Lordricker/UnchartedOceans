extends Node
## Temporary: dumps the home port's berths, market bays and the start state to res://tests/fleet_probe_report.txt, then quits.

var out := PackedStringArray()

func _ready() -> void:
	_run.call_deferred()

func _log(s: String) -> void:
	out.append(s)

func _extras(n: Node) -> Dictionary:
	if n.has_meta("extras"):
		var e = n.get_meta("extras")
		if e is Dictionary:
			return e
	return {}

func _run() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(4.0).timeout
	var world := get_parent().get_node("World")
	var st := world.get_node("WorldStreamer") as WorldStreamer
	var ship := world.get_node("ShipRig") as Node3D
	var player := world.get_node("Player") as Node3D
	_log("ports: %s" % str(st.port_ids()))
	_log("ship at %s heading %.1f class %s" % [str(ship.global_position), float(ship.get("heading_deg")), str(ship.get("ship_class"))])
	_log("player at %s" % str(player.global_position))
	var port := st.get_node_or_null("Port_AC00") as Node3D
	if port == null:
		_log("no Port_AC00")
	else:
		_log("port node at %s yaw %.1f deg" % [str(port.global_position), rad_to_deg(port.rotation.y)])
		var berths := get_tree().get_nodes_in_group("dock_berths")
		_log("dock berths: %d" % berths.size())
		for n in berths:
			var b := n as DockBerth
			var loc := port.to_local(b.global_position)
			_log("  %s class=%d heading=%.1f world=%s portlocal=%s slot_cutter=%s" % [b.name, b.max_ship_class, b.berth_heading, str(b.global_position), str(loc), str(b.slot_position(0))])
		var bays := 0
		for n in port.find_children("*", "Node3D", true, false):
			var ex := _extras(n)
			if str(ex.get("game_role", "")) == "market_bay":
				bays += 1
				_log("  bay %s interaction=%s world=%s" % [n.name, str(ex.get("interaction", "")), str(n.global_position)])
		_log("market bays: %d" % bays)
	_log("npcs in group: %d" % get_tree().get_nodes_in_group("market_npcs").size())
	_log("groups: ships=%d ship_harbor=%d ship_flooding=%d ship_sails=%d ship_anchor=%d" % [
		get_tree().get_nodes_in_group("ships").size(), get_tree().get_nodes_in_group("ship_harbor").size(),
		get_tree().get_nodes_in_group("ship_flooding").size(), get_tree().get_nodes_in_group("ship_sails").size(),
		get_tree().get_nodes_in_group("ship_anchor").size()])
	_log("fps %.1f  draw calls %d  objects %d  nodes %d" % [Engine.get_frames_per_second(),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	var f := FileAccess.open("res://tests/fleet_probe_report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out) + "\n")
		f.close()
	get_tree().quit()
