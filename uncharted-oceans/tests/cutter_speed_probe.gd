extends SceneTree
## Cutter speed vs point of sail: godot --headless --fixed-fps 60 --path uncharted-oceans --script res://tests/cutter_speed_probe.gd -- [wind=8.5] [scene=res://scenes/world_cutter_test.tscn]
func _init() -> void:
	var wind := 8.5
	var scene_path := "res://scenes/world_cutter_test.tscn"
	var area_mul := 1.0; var drag_mul := 1.0; var swing := -1.0
	var angles := [45, 60, 75, 90, 110, 130, 150, 170]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("wind="): wind = float(a.substr(5))
		if a.begins_with("scene="): scene_path = a.substr(6)
		if a.begins_with("area="): area_mul = float(a.substr(5))
		if a.begins_with("drag="): drag_mul = float(a.substr(5))
		if a.begins_with("swing="): swing = float(a.substr(6))
		if a.begins_with("angles="): angles = Array(a.substr(7).split(",")).map(func(x): return int(x))
	var world := (load(scene_path) as PackedScene).instantiate()
	root.add_child(world)
	for i in 240: await physics_frame
	var rig := world.get_node("ShipRig")
	var sw = null
	for n in world.find_children("*", "", true, false):
		var sc = n.get_script()
		if sc != null and str(sc.resource_path).ends_with("sea_wind.gd"): sw = n
		if sc != null and str(sc.resource_path).ends_with("world_weather.gd"):
			n.set_process(false); n.set_physics_process(false)
	var hb := get_first_node_in_group("ship_harbor")
	if hb != null and bool(hb.get("moored")): hb.call("cast_off")
	var ocean := world.get_node("Ocean")
	ocean.set("sea_state", 1)
	if sw != null:
		sw.set("gustiness", 0.0); sw.set("wander_deg", 0.0); sw.set("align_to_ship", false)
	var sails = rig.get_node("ShipSails")
	sails.call("set_all", false)
	for i in 600: await physics_frame
	var m = sails.model
	for s in m.sails: s.area *= area_mul
	m.hull_drag *= drag_mul
	if swing > 0.0: sails.set("spanker_swing_max_deg", swing)
	print("PROBE swing_max=", sails.get("spanker_swing_max_deg"), " area_mul=", area_mul, " drag_mul=", drag_mul)
	print("PROBE class=", rig.get("ship_class"), " mass=", m.mass, " hull_drag=", m.hull_drag, " hull_speed_kn=", snappedf(m.hull_speed / 0.514444, 0.1), " side_drag=", m.side_drag, " keel_lat=", m.keel_lat, " nsails=", m.sails.size())
	for s in m.sails:
		print("PROBE sail area=", snappedf(s.area, 0.1), " kind=", s.get("kind"))
	print("PROBE wind m/s=", wind)
	for rel in angles:
		# wind blows FROM absolute bearing 0 (north); ship heading chosen so the wind is `rel` deg off the bow on the starboard side
		sw.call("_take_over", wind, 0.0)
		var hdg := fposmod(float(rel), 360.0)
		var v := 0.0
		for i in 1200:
			rig.heading_deg = hdg
			await physics_frame
			if i >= 900: v += float(m.v_f)
		v /= 300.0
		var tw: Vector2 = m.apparent + Vector2(m.v_f, m.v_s)
		var off := rad_to_deg(acos(clampf(-tw.x / maxf(tw.length(), 0.001), -1.0, 1.0)))
		print("PROBE heading ", rel, ": true wind ", snappedf(off, 1.0), " deg off the bow -> ", snappedf(v / 0.514444, 0.1), " kn  (drive ", snappedf(m.drive, 1.0), " N, heel ", snappedf(rad_to_deg(m.heel), 0.1), ")")
	quit()
