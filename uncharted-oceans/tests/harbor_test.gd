extends SceneTree
## Island + harbour logic tests. Run headless:
##   godot --headless --path <project> --script res://tests/harbor_test.gd
## Prints one PASS/FAIL line per check.

var scene: Node
var ship: Node3D
var harbor: ShipHarbor
var isl: Island
var player: CharacterBody3D
var ocean: Ocean
var fails := 0
var step := 0
var t := 0.0
var phase := 0
var phase_t := 0.0
var data := {}

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("   " + info if info != "" else ""))
	if not ok:
		fails += 1

func _initialize() -> void:
	scene = load("res://scenes/ship_test.tscn").instantiate()
	root.add_child(scene)

func _hold_still_player() -> void:
	player.use_auto = true
	player.auto_input = Vector2.ZERO

func _heading_to(from: Vector2, to: Vector2) -> float:
	var d := (to - from).normalized()
	return rad_to_deg(atan2(-d.x, -d.y))

func _wait(seconds: float) -> bool:
	return phase_t >= seconds

func _next() -> void:
	phase += 1
	phase_t = 0.0

func _physics_process(delta: float) -> bool:
	step += 1
	if step < 10:
		return false
	if ship == null:
		ship = scene.get_node("ShipRig")
		harbor = ship.get_node_or_null("ShipHarbor") as ShipHarbor
		isl = scene.get_node_or_null("Island") as Island
		ocean = scene.get_node("Ocean") as Ocean
		player = scene.get_node("Player") as CharacterBody3D
		check("island exists", isl != null)
		check("harbor exists", harbor != null)
		if isl == null or harbor == null:
			quit(1)
			return true
		_hold_still_player()
		data["shallow"] = _shallow_point()
	phase_t += delta
	t += delta
	var b := isl.berth_world()
	match phase:
		0:
			# ---- shoaling: calm harbour vs open sea
			var amp_open := 0.0
			var amp_berth := 0.0
			for i in 200:
				ocean.time = float(i) * 0.37
				var ho := ocean.get_height(isl.global_position.x + 250.0, isl.global_position.z)
				var hb := ocean.get_height(b.x, b.z)
				amp_open = maxf(amp_open, absf(ho))
				amp_berth = maxf(amp_berth, absf(hb))
			check("waves shrink in the harbour", amp_berth < amp_open * 0.4, "open %.2f m, berth %.2f m" % [amp_open, amp_berth])
			_next()
		1:
			# ---- run aground on the beach: heading straight in from open water at 2.6 m/s
			if phase_t < 0.05:
				var s: Vector3 = data["shallow"]
				var c := Vector2(isl.global_position.x, isl.global_position.z)
				var from := Vector2(s.x, s.z)
				ship.global_position = Vector3(from.x, 0.0, from.y)
				ship.set("heading_deg", _heading_to(from, c))
				ship.set("_heave", 0.0)
				ship.set("underway", true)
				data["aground_seen"] = false
			if harbor.aground:
				data["aground_seen"] = true
			if _wait(60.0):
				var sd := isl.shore_distance(ship.global_position.x, ship.global_position.z)
				var v: float = (ship.get("sails").model as SailModel).v_f
				check("ship runs aground heading for the beach", data["aground_seen"], "shore distance %.1f m" % sd)
				check("grounded ship stays off the beach", sd > 8.0 and harbor.clearance > -0.8, "shore %.1f m, under keel %.2f m" % [sd, harbor.clearance])
				check("grounded ship has stopped", absf(v) < 0.4, "v_f %.2f" % v)
				ship.set("underway", false)
				_next()
		2:
			# ---- bump the pier: sail west into its east face
			if phase_t < 0.05:
				ship.global_position = Vector3(b.x + 22.0, 0.0, b.z)
				ship.set("heading_deg", 90.0)
				ship.set("underway", true)
				harbor.message = ""
				data["bumped"] = false
			if harbor.message.begins_with("Bumped"):
				data["bumped"] = true
			if _wait(25.0):
				var rect := isl.pier_rect_world()
				var hull_edge: float = ship.global_position.x - 9.5
				check("hull cannot pass through the pier", hull_edge >= rect.end.x - 0.05, "hull bow edge x %.2f, pier east face %.2f" % [hull_edge, rect.end.x])
				check("pier hit reported", data["bumped"])
				ship.set("underway", false)
				_next()
		3:
			# ---- too fast to moor, then moor slowly
			if phase_t < 0.05:
				harbor.teleport_to_approach()
				ship.set("ahead_speed", 2.6)
				ship.set("underway", true)
			var s := harbor.berth_state()
			if s.along < 0.0 or phase_t > 60.0:
				var fast := harbor.can_moor()
				check("cannot moor while moving fast", not fast, "speed %.2f along %.1f lat %.1f" % [s.speed, s.along, s.lat])
				harbor.toggle_moor()
				check("E refused when too fast", not harbor.moored, harbor.message)
				_next()
		4:
			if phase_t < 0.05:
				harbor.teleport_to_approach()
				ship.set("ahead_speed", 0.8)
				ship.set("underway", true)
			var s := harbor.berth_state()
			if (s.along <= 1.0 and harbor.can_moor()) or phase_t > 120.0:
				data["moor_state"] = s
				harbor.toggle_moor()
				check("moors alongside at slow speed", harbor.moored, "lat %.2f along %.2f heading %.1f speed %.2f" % [s.lat, s.along, s.heading, s.speed])
				_next()
		5:
			if _wait(8.0):
				var p := ship.global_position
				var err := Vector2(p.x - b.x, p.z - b.z).length()
				check("hauled in to the berth point", err < 0.2, "error %.3f m" % err)
				check("gangway out when settled", harbor._gang_out, "settle %.1f" % harbor.settle)
				check("speed zero while moored", harbor._velocity().length() < 0.05)
				# pier-side clearance
				var rect := isl.pier_rect_world()
				var gap: float = (p.x - 3.5) - rect.end.x
				check("hull rests on the fenders", absf(gap) < 0.4, "gap to pier face %.2f m" % gap)
				# put the player on the pier next to the gangway, facing the ship
				player.use_auto = true
				player.auto_input = Vector2.ZERO
				player.global_position = Vector3(isl.global_position.x + 1.0, isl.pier_deck_y + 0.3, b.z + harbor.gangway_z)
				player.velocity = Vector3.ZERO
				player.rotation.y = -PI * 0.5
				_next()
		6:
			if phase_t > 1.0 and phase_t < 1.05:
				player.auto_input = Vector2(0, -1)
			var local := ship.global_transform.affine_inverse() * player.global_position
			if phase_t > 0.0 and int(phase_t * 10) % 10 == 0 and phase_t < 0.15:
				pass
			if local.x > -1.0 and local.y > 1.5 or _wait(15.0):
				var deck_y := local.y
				check("player walks over the gangway onto the deck", local.x > -1.5 and local.y > 1.5 and local.y < 3.2, "ship-local (%.2f, %.2f, %.2f)" % [local.x, local.y, local.z])
				player.auto_input = Vector2.ZERO
				data["on_deck"] = local.x > -1.5
				_next()
		7:
			if phase_t < 0.05:
				harbor.cast_off()
				check("cast off with the player aboard", not harbor.moored)
			if _wait(10.0):
				var p := ship.global_position
				check("ship drifts clear of the pier", p.x > b.x + 0.3, "x offset %.2f" % (p.x - b.x))
				print("DONE fails=", fails)
				quit(fails)
				return true
	return false

func _shallow_point() -> Vector3:
	# open water on the west side of the island, 70 m off the beach, on the ray from the island centre
	var c := Vector3(isl.global_position.x, 0.0, isl.global_position.z)
	var dir := Vector3(-1, 0, 0.4).normalized()
	var r := 200.0
	while r > 0.0:
		var p := c + dir * r
		if isl.height_at(p.x, p.z) > 0.0:
			break
		r -= 1.0
	return c + dir * (r + 70.0)
