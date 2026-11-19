extends Node
## Temporary check of the quay ladders (delete when done). Swims the player up to a capital quay ladder, holds W and
## logs where he ends up, then walks him off the deck edge at the ladder and holds S. Writes res://tests/pier_ladder_report.txt, then quits.

var out := PackedStringArray()

func _log(s: String) -> void:
	out.append(s)
	print("LADDERPROBE ", s)

func _ready() -> void:
	_run.call_deferred()

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _finish() -> void:
	var f := FileAccess.open("res://tests/pier_ladder_report.txt", FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	get_tree().quit()

func _run() -> void:
	await _wait(1.0)
	var world := get_parent().get_node("World")
	var pl := world.get_node("Player") as CharacterBody3D
	var tries := 0
	var ladders: Array = []
	while tries < 60 and ladders.is_empty():
		await _wait(0.5)
		tries += 1
		ladders = get_tree().get_nodes_in_group("ship_ladders").filter(func(n): return String(n.name).begins_with("QuayLadder_"))
	_log("quay ladders found: %d (after %.1f s)" % [ladders.size(), tries * 0.5])
	if ladders.is_empty():
		_finish()
		return
	# the capital's main-quay ladder at x=-45 (the ship lies at x=+32 so it is clear of it)
	var lad: ShipLadder = null
	for l in ladders:
		var lp: Vector3 = (l.get_parent() as Node3D).to_local(l.global_position)
		if absf(lp.x + 45.0) < 0.1 and absf(lp.z) < 0.5:
			lad = l
	if lad == null:
		lad = ladders[0]
	var port := lad.get_parent() as Node3D
	_log("using %s in %s, fixed=%s snap=%s" % [lad.name, port.name, str(lad.fixed), str(lad.snap_depth)])
	var b := lad.global_transform.basis
	_log("ladder up=%s out=%s" % [str(b.y.snappedf(0.01)), str(b.z.snappedf(0.01))])
	pl.set("use_auto", true)
	# --- 1. swim up and climb: in the water 0.6 m off the wall, W held
	pl.global_position = lad.global_position + b.z * 0.6 + Vector3.UP * (-0.3 - lad.global_position.y)
	pl.velocity = Vector3.ZERO
	pl.set("auto_input", Vector2(0, -1))
	var grabbed_at := -1.0
	var t := 0.0
	for i in 600:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if i % 30 == 0 or (pl.get("ladder") != null and grabbed_at < 0.0):
			if pl.get("ladder") != null and grabbed_at < 0.0:
				grabbed_at = t
			var lp: Vector3 = port.to_local(pl.global_position)
			_log("t=%.1f feet(port-local)=%s on_ladder=%s floor=%s swimming=%s" % [t, str(lp.snappedf(0.01)), str(pl.get("ladder") != null), str(pl.is_on_floor()), str(pl.get("swimming"))])
		if pl.is_on_floor() and pl.global_position.y > 1.5:
			break
	var end: Vector3 = port.to_local(pl.global_position)
	_log("CLIMB UP result: feet(port-local)=%s on_floor=%s ladder=%s (deck is y=1.85, quay is z<0)" % [str(end.snappedf(0.01)), str(pl.is_on_floor()), str(pl.get("ladder") != null)])
	pl.set("auto_input", Vector2.ZERO)
	for i in 30:
		await get_tree().physics_frame
	# --- 2. from the deck: walk off the edge at the ladder (toward the water) and hold S to climb down
	var deck: Vector3 = lad.global_position - b.z * 1.5
	deck.y = 1.9
	pl.global_position = deck
	pl.velocity = Vector3.ZERO
	pl.rotation.y = atan2(-b.z.x, -b.z.z) + PI   # face the water
	pl.set("auto_input", Vector2(0, -1))   # W: walk forward toward the water
	var got := false
	for i in 240:
		await get_tree().physics_frame
		if pl.get("ladder") != null:
			got = true
			break
	_log("walked off the edge: grabbed ladder=%s feet(port-local)=%s" % [str(got), str(port.to_local(pl.global_position).snappedf(0.01))])
	if got:
		pl.set("auto_input", Vector2(0, 1))   # S: down
		for i in 300:
			await get_tree().physics_frame
		_log("climbed down: feet(port-local)=%s ladder=%s swimming=%s" % [str(port.to_local(pl.global_position).snappedf(0.01)), str(pl.get("ladder") != null), str(pl.get("swimming"))])
	_finish()
