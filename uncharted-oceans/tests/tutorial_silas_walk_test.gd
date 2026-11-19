extends Node
## Drives the tutorial scene: builds the world, prints Silas's graph, walks him to every station, then runs the steps.
var world: Node
var dir: Node
var silas: Node
var rig: Node3D
var log := []

func p(s: String) -> void:
	print("[TT] ", s, "  (frames=", Engine.get_frames_drawn(), ")")

func _ready() -> void:
	GameSession.start_game(true)
	world = load("res://scenes/world_tutorial.tscn").instantiate()
	add_child(world)
	_run()

func _run() -> void:
	await get_tree().create_timer(6.0).timeout
	dir = world.get_node("TutorialDirector")
	silas = dir.silas
	rig = get_tree().get_first_node_in_group("ships")
	if silas == null:
		p("FAIL: no silas"); get_tree().quit(1); return
	p("real model %s anims %s" % [silas._real, silas._anim.get_animation_list() if silas._anim else []])
	var info: Dictionary = silas.graph_info()
	p("graph points=%d main=%d" % [info["points"], info["main"]])
	for s in info["stations"]:
		p("  station %s -> %s  (graph gap %.2f)" % [s, info["stations"][s]["point"], info["stations"][s]["dist_to_graph"]])
	print(silas.ascii_map())
	p("rig pos %s speed %.2f moored %s" % [rig.global_position, rig.speed, rig.get_node("ShipHarbor").moored])
	# Silas walks
	for st in ["bookshelf", "gangway", "hold", "tiller", "chart", "log", "bed", "mast", "tiller"]:
		var t0 := Time.get_ticks_msec()
		silas.go_to(st)
		var ok := true
		var guard := 0
		var seen := {}
		while silas.is_walking() and guard < 900:
			await get_tree().create_timer(0.1).timeout
			guard += 1
			if silas._anim: seen[String(silas._anim.current_animation)] = true
		await get_tree().create_timer(0.5).timeout
		p("   clips while walking %s, now %s" % [seen.keys(), silas._anim.current_animation if silas._anim else "-"])
		p("silas -> %s %s in %.1fs, at %s" % [st, "ok" if guard < 900 else "TIMEOUT", (Time.get_ticks_msec() - t0) / 1000.0, silas.position])
	p("step now %d flags %s" % [dir.index, dir.flags])
	get_tree().quit(0)
