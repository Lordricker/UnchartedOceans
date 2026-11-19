extends Node
var world: Node
var dir: Node
var rig: Node3D
func p(s: String) -> void:
	print("[TT] ", s)
func _ready() -> void:
	GameSession.start_game(true)
	world = load("res://scenes/world_tutorial.tscn").instantiate()
	add_child(world)
	_run()
func wait_step(n: int, limit := 150.0) -> bool:
	var t := 0.0
	while dir.index < n and t < limit:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	if dir.index < n:
		p("FAIL waiting for step %d (now %d) flags %s" % [n, dir.index, dir.flags])
		get_tree().quit(1)
	return dir.index >= n
func steer() -> void:
	while is_inside_tree():
		await get_tree().create_timer(1.0).timeout
		if dir.index >= 6 and dir.index < 9:
			rig.heading_deg = fposmod(360.0 - st_bearing(), 360.0)

func st_bearing() -> float:
	return get_tree().get_first_node_in_group("world_streamer").waypoint_bearing()

func _run() -> void:
	await get_tree().create_timer(4.0).timeout
	dir = world.get_node("TutorialDirector")
	rig = get_tree().get_first_node_in_group("ships")
	Engine.time_scale = 6.0
	dir.subtitle.line_started.connect(func(id): p("SAY %s: %s" % [id, dir.subtitle._label.text]))
	dir.step_changed.connect(func(i, id): p("STEP %d %s (silas at %s)" % [i, id, dir.silas.at_station]))
	dir.flag_set.connect(func(f): p("FLAG %s" % f))
	dir.subtitle.line_finished.connect(func(id): p('FIN %s' % id))
	dir.subtitle.queue_empty.connect(func(): p('QUEUE EMPTY'))
	var shelf = rig.get_node("ShipBookshelf")
	var harbor = rig.get_node("ShipHarbor")
	var sails = rig.get_node("ShipSails")
	var map = rig.get_node("ShipMap")
	var st = get_tree().get_first_node_in_group("world_streamer")
	await get_tree().create_timer(3.0).timeout
	# out of order: open the chart and set the sails before anything else
	map._open = true
	for r in sails.recs: sails.set_progress(r.id, 0.0)
	await get_tree().create_timer(1.0).timeout
	map._open = false
	shelf.book_opened.emit("tutorial_01")
	if not await wait_step(1): return
	await get_tree().create_timer(30.0).timeout
	p('--- click on Silas ---')
	dir.silas.clicked.emit()
	await get_tree().create_timer(14.0).timeout
	TradeState.gold -= 25
	if not await wait_step(2): return
	dir._set_flag("stowed")
	if not await wait_step(3): return
	harbor.cast_off()
	# tips: aground (any time after cast off) and the harbour creep
	await get_tree().create_timer(3.0).timeout
	harbor.aground = true
	await get_tree().create_timer(20.0).timeout
	harbor.aground = false
	var fake := Node.new()
	fake.set_script(load("res://tests/fake_anchor.gd"))
	dir._anchor = fake                       # the real one resets 'creeping' every physics frame
	await get_tree().create_timer(40.0).timeout
	p("tips said: %s" % [dir._tips_said.keys()])
	if not (dir._tips_said.has("tip_aground") and dir._tips_said.has("tip_creep")): p("FAIL tips"); get_tree().quit(1); return
	if not await wait_step(5): return        # sails already set: skipped with a short line
	# put her on the open leg and let her sail
	var w: Vector2 = st.route[2]
	rig.global_position = Vector3(w.x - st.origin_x, 0.0, w.y - st.origin_z)
	p("after teleport: route_i %d of %d, bearing %.0f" % [st.route_i, st.route.size(), st.waypoint_bearing()])
	steer()
	if not await wait_step(6): return         # speed_good by real sailing
	p("speed %.2f m/s; bearing %.0f heading %.0f" % [rig.speed, st.waypoint_bearing(), st.ship_chart_heading()])
	if not await wait_step(7): return         # heading_ok by real heading
	var logl = rig.get_node("ShipLogLine")
	dir._set_flag("log_read")
	if not await wait_step(8): return
	await get_tree().create_timer(30.0).timeout
	st.slept.emit({})                        # woke at a marker: not arrival
	await get_tree().create_timer(15.0).timeout
	if dir.index != 8: p("FAIL: moved on after a wake at a marker (index %d)" % dir.index); get_tree().quit(1); return
	st.slept.emit({})
	await get_tree().create_timer(15.0).timeout
	if dir.index != 8: p("FAIL: moved on after 2nd wake"); get_tree().quit(1); return
	st.arrived.emit("AS06")                   # port loads in at 6 km: a line, but no docking lesson yet
	await get_tree().create_timer(15.0).timeout
	if dir.index != 8: p("FAIL: docking lesson started at 6 km (index %d)" % dir.index); get_tree().quit(1); return
	st.route_i = st.route.size() - 1
	var pt: Vector2 = st.route[st.route.size() - 1]
	var away := Vector2(0, 400.0)
	rig.global_position = Vector3(pt.x + away.x - st.origin_x, 0.0, pt.y + away.y - st.origin_z)
	p("placed %.0f m from the port" % st.waypoint_distance_m())
	if not await wait_step(9): return
	dir._set_flag("docked")
	if not await wait_step(10): return
	TradeState.gold += 10
	if not await wait_step(11): return
	await get_tree().create_timer(45.0).timeout
	p("DONE index=%d ending=%s busy=%s queue=%d idle=%s steps=%d" % [dir.index, dir._ending, dir.subtitle._busy, dir.subtitle._queue.size(), dir.subtitle.is_idle(), dir._steps.size()])
	get_tree().quit(0)
