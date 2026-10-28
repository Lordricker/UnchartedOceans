extends SceneTree
## Headless polar diagram for SailModel: godot --headless -s tests/sail_polar.gd -- [wind m/s]
func mk(kind: int, area: float, f: float, h: float, group: int, head := false) -> SailModel.Sail:
	var s := SailModel.Sail.new()
	s.kind = kind; s.area = area; s.f = f; s.h = h; s.group = group; s.headsail = head
	return s

func rig(sets := {}) -> Array[SailModel.Sail]:
	var a: Array[SailModel.Sail] = []
	var spec := [
		["Fore_0", 0, 29.6, 5.12, 6.14, 0, false], ["Fore_1", 0, 36.3, 5.46, 10.6, 0, false], ["Fore_2", 0, 13.0, 5.6, 13.9, 0, false],
		["Main_0", 0, 33.4, -0.78, 6.18, 1, false], ["Main_1", 0, 41.0, -0.47, 11.0, 1, false], ["Main_2", 0, 14.0, -0.32, 14.6, 1, false],
		["Jib", 1, 25.0, 12.9, 8.3, 0, true], ["Stay", 1, 13.1, 10.5, 6.8, 0, true], ["Spanker", 1, 23.6, -5.4, 8.0, 1, false]]
	for sp in spec:
		var s := mk(sp[1], sp[2], sp[3], sp[4], sp[5], sp[6])
		s.set_frac = sets.get(sp[0], 1.0)
		a.append(s)
	return a

func run_case(m: SailModel, twa_deg: float, tws: float, beta_deg: float, secs := 240.0) -> void:
	m.v_f = 0.0; m.v_s = 0.0; m.heel = 0.0
	var psi := deg_to_rad(twa_deg)
	var wind := -tws * Vector2(cos(psi), sin(psi))   # air goes away from where it comes from
	for s in m.sails:
		if s.kind == 0:
			s.beta = deg_to_rad(beta_deg)
	var t := 0.0
	while t < secs:
		m.step(0.05, wind, 0.0)
		t += 0.05

func _init():
	var args := OS.get_cmdline_user_args()
	var tws := float(args[0]) if args.size() > 0 else 9.0
	var m := SailModel.new()
	m.sails = rig()
	print("true wind %.1f m/s (%.0f kn).  columns: TWA (from bow, + = starboard)  best brace(deg)  speed kn  leeway deg  heel deg  yaw bias deg/s  drive kN  side kN" % [tws, tws / 0.5144])
	for twa in [0, 20, 40, 50, 55, 60, 65, 70, 80, 90, 110, 130, 150, 170, 180]:
		var best := -1e9; var bb := 0.0
		var bres := []
		for b in range(-40, 41, 4):
			run_case(m, twa, tws, b, 160.0)
			if m.v_f > best:
				best = m.v_f; bb = b
				var lee := rad_to_deg(atan2(m.v_s, maxf(absf(m.v_f), 0.2)))
				bres = [m.v_f / 0.5144, lee, rad_to_deg(m.heel), m.yaw_rate, m.drive / 1000.0, m.force_total.y / 1000.0]
		print("TWA %3d  brace %4d  %5.2f kn  lee %5.1f  heel %5.1f  yaw %5.2f  drive %5.1f  side %5.1f" % [twa, bb, bres[0], bres[1], bres[2], bres[3], bres[4], bres[5]])
	# acceleration from rest on a beam reach, all sail set
	var m2 := SailModel.new(); m2.sails = rig()
	for sl in m2.sails:
		if sl.kind == 0: sl.beta = deg_to_rad(22.0)
	var wind := -tws * Vector2(cos(deg_to_rad(90.0)), sin(deg_to_rad(90.0)))
	var out := "accel from rest (beam reach, braced 22): "
	var t := 0.0
	for mark in [10, 20, 30, 45, 60, 90, 120]:
		while t < mark:
			m2.step(0.05, wind, 0.0); t += 0.05
		out += " %ds=%.1fkn" % [mark, m2.v_f / 0.5144]
	print(out)
	# only courses, only topsails etc.
	for label in ["only courses", "only topsails", "courses+topsails", "headsails+spanker only"]:
		var m3 := SailModel.new()
		var sets := {}
		match label:
			"only courses": sets = {"Fore_0": 1.0, "Main_0": 1.0}
			"only topsails": sets = {"Fore_1": 1.0, "Main_1": 1.0}
			"courses+topsails": sets = {"Fore_0": 1.0, "Main_0": 1.0, "Fore_1": 1.0, "Main_1": 1.0}
			_: sets = {"Jib": 1.0, "Stay": 1.0, "Spanker": 1.0}
		var all := rig({})
		for sl in all:
			var key := ""
			for k in ["Fore_0","Fore_1","Fore_2","Main_0","Main_1","Main_2"]:
				pass
		m3.sails = rig({"Fore_0": sets.get("Fore_0", 0.0), "Fore_1": sets.get("Fore_1", 0.0), "Fore_2": sets.get("Fore_2", 0.0), "Main_0": sets.get("Main_0", 0.0), "Main_1": sets.get("Main_1", 0.0), "Main_2": sets.get("Main_2", 0.0), "Jib": sets.get("Jib", 0.0), "Stay": sets.get("Stay", 0.0), "Spanker": sets.get("Spanker", 0.0)})
		for sl in m3.sails:
			if sl.kind == 0: sl.beta = deg_to_rad(22.0)
		var tt := 0.0
		while tt < 200.0:
			m3.step(0.05, wind, 0.0); tt += 0.05
		print("beam reach, %s: %.2f kn  heel %.1f" % [label, m3.v_f / 0.5144, rad_to_deg(m3.heel)])
	quit()
