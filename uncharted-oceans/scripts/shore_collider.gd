class_name ShoreCollider
extends Node3D
## Real ground near the player. The world's terrain is only drawn (world_terrain.gdshader), so on its own nothing can
## stand on a beach. When the player (or the ship, if there is no player) comes within active_shore_m of a coast, this
## builds a HeightMapShape3D of the ground around them from WorldGround, the CPU copy of the very function the shader
## draws, so you walk on exactly the sand you see. It is rebuilt on a worker thread whenever they have moved
## rebuild_m from its centre, and dropped again out at sea. Ports cut a hole in the terrain and bring their own
## ground: inside that hole the collider is sunk out of the way.
##
## Physics layer 11 (LAYER_BIT): the player collides with it (player.gd). The ship's keel is tested against the same
## WorldGround by WorldStreamer, so ships stop on the same beach without needing a body.

const LAYER_BIT := 1 << 10
const SUNK_Y := -80.0

@export var cell_m := 2.0
@export var cells := 128                ## per side: 128 x 2 m = a 256 m square
@export var rebuild_m := 48.0
@export var active_shore_m := 900.0

var streamer: Node                      ## WorldStreamer
var ground                  ## world_ground.gd

var _body: StaticBody3D
var _shape: CollisionShape3D
var _center := Vector2(INF, INF)        # chart xz of the patch now in use
var _task := -1
var _task_center := Vector2.ZERO
var _task_data := PackedFloat32Array()
var _check_t := 0.0


func _ready() -> void:
	_body = StaticBody3D.new()
	_body.name = "ShoreGround"
	_body.collision_layer = LAYER_BIT
	_body.collision_mask = 0
	_body.add_to_group("world_ground")
	_shape = CollisionShape3D.new()
	_shape.disabled = true
	_shape.scale = Vector3.ONE * cell_m       # uniform: the heights are stored divided by cell_m
	_body.add_child(_shape)
	add_child(_body)
	_body.top_level = true


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Chart xz of whoever should stand on the ground: the player, else the ship.
func _focus() -> Vector2:
	var n: Node3D = streamer.get("_player")
	if n == null:
		n = streamer.get("_ship")
	if n == null:
		return Vector2(INF, INF)
	return Vector2(float(streamer.get("origin_x")) + n.global_position.x, float(streamer.get("origin_z")) + n.global_position.z)


func _physics_process(delta: float) -> void:
	if streamer == null or ground == null:
		return
	var ox := float(streamer.get("origin_x"))
	var oz := float(streamer.get("origin_z"))
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		var hm := HeightMapShape3D.new()
		hm.map_width = cells + 1
		hm.map_depth = cells + 1
		hm.map_data = _task_data
		_shape.shape = hm
		_shape.disabled = false
		_center = _task_center
	# follows the floating origin: the patch is in chart space, so a rebase only moves it
	if _center.x != INF:
		_body.global_position = Vector3(_center.x - ox, 0.0, _center.y - oz)
	_check_t -= delta
	if _check_t > 0.0 or _task >= 0:
		return
	_check_t = 0.2
	var f := _focus()
	if f.x == INF:
		return
	var chart: WorldChart = streamer.get("chart")
	var near := chart.is_land(f.x, f.y) or chart.shore_distance_m(f.x, f.y) < active_shore_m
	if not near:
		if not _shape.disabled:
			_shape.disabled = true
			_center = Vector2(INF, INF)
		return
	if _center.x != INF and f.distance_to(_center) < rebuild_m:
		return
	var c := (f / cell_m).round() * cell_m
	var hole := _hole_chart()
	_task_center = c
	_task = WorkerThreadPool.add_task(_build.bind(c, hole), false, "shore collider")


## The port's terrain hole in chart xz (x, z, radius); radius <= 0 = none.
func _hole_chart() -> Vector3:
	var t = streamer.get("_terrain")
	if t == null:
		return Vector3(0, 0, -1)
	var h: Vector3 = t.get("hole_world")
	if h.z <= 0.0:
		return h
	return Vector3(h.x + float(streamer.get("origin_x")), h.y + float(streamer.get("origin_z")), h.z)


func _build(c: Vector2, hole: Vector3) -> void:
	var n := cells + 1
	var half := float(cells) * 0.5 * cell_m
	var data := PackedFloat32Array()
	data.resize(n * n)
	var hr2 := hole.z * hole.z
	for j in n:
		var z := c.y - half + float(j) * cell_m
		for i in n:
			var x := c.x - half + float(i) * cell_m
			var y: float
			if hole.z > 0.0 and (x - hole.x) * (x - hole.x) + (z - hole.y) * (z - hole.y) < hr2:
				y = SUNK_Y
			else:
				y = ground.call("terrain_y", x, z)
			data[j * n + i] = y / cell_m
	_task_data = data
