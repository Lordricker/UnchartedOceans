extends SceneTree
## Wave-following probe: godot --headless --fixed-fps 60 --path uncharted-oceans --script res://tests/cutter_wave_probe.gd -- lag=cur|new [scene=res://...] [level=2]
func _init() -> void:
	var variant := "cur"
	var scene_path := "res://scenes/world_cutter_test.tscn"
	var level := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("lag="): variant = a.substr(4)
		if a.begins_with("scene="): scene_path = a.substr(6)
		if a.begins_with("level="): level = int(a.substr(6))
	var world := (load(scene_path) as PackedScene).instantiate()
	root.add_child(world)
	for i in 300: await physics_frame
	var rig := world.get_node("ShipRig")
	var ocean := world.get_node("Ocean")
	var hb := get_first_node_in_group("ship_harbor")
	if hb != null and bool(hb.get("moored")): hb.call("cast_off")
	for n in world.find_children("*", "", true, false):
		var sc = n.get_script()
		if sc != null and (str(sc.resource_path).ends_with("sea_wind.gd") or str(sc.resource_path).ends_with("world_weather.gd")):
			n.set_process(false)
			n.set_physics_process(false)
	ocean.set("sea_state", level)
	for i in 60: await physics_frame
	var cls: int = int(rig.get("ship_class"))
	if variant == "new":
		for k in NEWVALS: rig.set(k, NEWVALS[k])
	print("PROBE variant=", variant, " scene=", scene_path.get_file(), " class=", cls, " heave_lag=", rig.get("heave_lag"), " rise_lag=", rig.get("rise_lag"), " pitch_lag=", rig.get("pitch_lag"), " roll_lag=", rig.get("roll_lag"), " max_sink=", rig.get("max_sink"), " draft_offset=", rig.get("draft_offset"))
	var foot = ShipClasses.data(cls).get("foot", [])
	var keel: Array[Vector3] = []
	for p in foot:
		if p is Vector3: keel.append(Vector3(p.x, -p.z, p.y))
	print("PROBE keel points=", keel.size(), " deepest=", keel.map(func(v): return v.y).min())
	for i in 480: await physics_frame
	var n := 0
	var up_sum := 0.0; var up_max := -9.0; var up_min := 9.0
	var dp_sum := 0.0; var dr_sum := 0.0; var roll_max := 0.0; var pitch_max := 0.0
	var out_n := 0; var out_max := -9.0; var out_deep := 0; var awash_n := 0
	for i in 2400:
		await physics_frame
		var wp: Vector3 = rig.call("water_pose")
		var up: float = rig.position.y - wp.x
		up_sum += up; up_max = maxf(up_max, up); up_min = minf(up_min, up)
		dp_sum += absf(rad_to_deg(float(rig.get("_pitch")) - wp.y)); dr_sum += absf(rad_to_deg(float(rig.get("_roll")) - wp.z))
		roll_max = maxf(roll_max, absf(rad_to_deg(float(rig.get("_roll")))))
		pitch_max = maxf(pitch_max, absf(rad_to_deg(float(rig.get("_pitch")))))
		var lowest := 1e9
		for k in keel:
			var w: Vector3 = rig.global_transform * k
			lowest = minf(lowest, w.y - float(ocean.call("get_height", w.x, w.z)))
		if lowest > 0.05: out_n += 1
		if lowest > 0.5: out_deep += 1
		out_max = maxf(out_max, lowest)
		var awash := false
		for sp in rig.get("sample_points"):
			var w2: Vector3 = rig.global_transform * Vector3(sp.x, 0.85, sp.y)
			if w2.y < float(ocean.call("get_height", w2.x, w2.z)): awash = true
		if awash: awash_n += 1
		n += 1
	print("PROBE sea_state=", ocean.get("sea_state"), " frames=", n)
	print("PROBE hull height above the plane through the water (m): mean ", snappedf(up_sum / n, 0.01), " max ", snappedf(up_max, 0.01), " min ", snappedf(up_min, 0.01))
	print("PROBE pose error vs the wave (deg): pitch ", snappedf(dp_sum / n, 0.1), " roll ", snappedf(dr_sum / n, 0.1), " | peak pitch ", snappedf(pitch_max, 0.1), " peak roll ", snappedf(roll_max, 0.1))
	print("PROBE keel clear of the water: ", snappedf(100.0 * out_n / n, 0.1), "% of the time (>0.5 m clear: ", snappedf(100.0 * out_deep / n, 0.1), "%), worst ", snappedf(out_max, 0.01), " m")
	print("PROBE deck level under the water at a sample point: ", snappedf(100.0 * awash_n / n, 0.1), "% of the time")
	quit()
const NEWVALS := {"heave_lag": 0.25, "rise_lag": 0.12, "max_sink": 0.3, "pitch_lag": 0.35, "roll_lag": 0.45}
