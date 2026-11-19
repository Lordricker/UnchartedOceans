extends SceneTree
## Does the ship still follow the waves after a relocate (sleep teleport)? godot --headless --fixed-fps 60 --path uncharted-oceans --script res://tests/wake_snap_probe.gd -- [scene=res://scenes/world_tutorial.tscn]
func _init() -> void:
	var scene_path := "res://scenes/world_tutorial.tscn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("scene="): scene_path = a.substr(6)
	var world := (load(scene_path) as PackedScene).instantiate()
	root.add_child(world)
	for i in 300: await physics_frame
	var rig := world.get_node("ShipRig")
	var ocean := world.get_node("Ocean")
	var st = null
	for n in world.find_children("*", "", true, false):
		if n.has_method("relocate") and n.has_method("sleep"):
			st = n
	var hb := get_first_node_in_group("ship_harbor")
	if hb != null and bool(hb.get("moored")): hb.call("cast_off")
	ocean.set("sea_state", 2)
	for i in 120: await physics_frame
	print("PROBE floating=", rig.get("floating"), " streamer=", st != null)
	_measure(rig, "before")
	await _run(rig, 600, "before")
	if st != null:
		var cx: float = float(st.call("ship_cx")); var cz: float = float(st.call("ship_cz"))
		st.call("relocate", cx + 1234.0, cz + 777.0)
		print("PROBE relocated")
	await _run(rig, 600, "after_a")
	await _run(rig, 600, "after_b")
	quit()
func _measure(rig, tag): pass
func _run(rig: Node, frames: int, tag: String) -> void:
	var y0 := 1e9; var y1 := -1e9; var p0 := 1e9; var p1 := -1e9
	var nan := false
	for i in frames:
		await physics_frame
		var y: float = rig.position.y
		if is_nan(y): nan = true
		y0 = minf(y0, y); y1 = maxf(y1, y)
		var p: float = rig.rotation.x
		p0 = minf(p0, p); p1 = maxf(p1, p)
	print("PROBE ", tag, " y range ", snapped(y0, 0.001), "..", snapped(y1, 0.001), " pitch range ", snapped(p0, 0.001), "..", snapped(p1, 0.001), " nan=", nan, " amount=", rig.get("_amount"), " heave=", rig.get("_heave"))
