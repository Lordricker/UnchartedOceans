class_name MarketNpc
extends Node3D
## A stallholder. market_director.gd puts one on each market bay's "npc_stand" marker, turned towards the bay's
## "customer_stand" marker. It plays the model's idle loop and looks at the player when they come close
## (npc_head_look.gd). Clicking it opens the stall's menu (market_director.gd does the aiming and clicking).
##
## The models are the placeholders in res://assets/npcs. Their root may sit anywhere in the file, so the model is
## re-centred on this node's origin with its feet on the ground.

const HeadLookScript := preload("res://scripts/npc_head_look.gd")

## The stall this person runs (a MarketStall).
var stall

## Where the body is, in this node's frame (used to aim at it).
var bounds := AABB()

var _model: Node3D


## What the aim prompt says while you look at this person (courier_npc.gd says its own).
func prompt_text() -> String:
	return "Click: talk to %s" % stall.title


## Turn to face a world position (+Z is the front of the models).
func face(target: Vector3) -> void:
	var d := target - global_position
	d.y = 0.0
	if d.length() > 0.01:
		global_rotation = Vector3(0.0, atan2(d.x, d.z), 0.0)


func setup(model_name: String, p_stall) -> void:
	stall = p_stall
	add_to_group("market_npcs")
	var ps := load("res://assets/npcs/NPC_%s.glb" % model_name) as PackedScene
	if ps == null:
		ps = load("res://assets/npcs/NPC_Sailor.glb") as PackedScene
	if ps == null:
		push_warning("MarketNpc: no NPC model found")
		return
	_model = ps.instantiate() as Node3D
	add_child(_model)
	_ground_fit()
	_start_idle()
	_add_head_look()


## Feet on the marker, body centred on it.
func _ground_fit() -> void:
	var inv := global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mi.global_transform
		var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		if sk != null:
			xf = sk.global_transform
		var b: AABB = (inv * xf) * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	if first:
		return
	var c := box.get_center()
	_model.position = Vector3(-c.x, -box.position.y, -c.z)
	bounds = AABB(box.position + _model.position, box.size)


## Play the idle loop, each person at a different point in it so a row of them does not sway together.
func _start_idle() -> void:
	for a in _model.find_children("*", "AnimationPlayer", true, false):
		var ap := a as AnimationPlayer
		var pick := ""
		for n in ap.get_animation_list():
			if n == &"RESET":
				continue
			if pick == "" or String(n).to_lower().contains("idle"):
				pick = String(n)
		if pick == "":
			continue
		var anim := ap.get_animation(pick)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR
		ap.play(pick)
		if anim != null:
			ap.seek(randf() * anim.length, true)
		return


func _add_head_look() -> void:
	var skels := _model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var m = HeadLookScript.new()
	m.npc = self
	(skels[0] as Skeleton3D).add_child(m)


## Distance along a world ray to this person's body, or -1.
func ray_hit(o: Vector3, d: Vector3, max_d: float) -> float:
	if bounds.size == Vector3.ZERO:
		return -1.0
	var inv := global_transform.affine_inverse()
	var hit = bounds.grow(0.1).intersects_ray(inv * o, (inv.basis * d).normalized())
	if hit == null:
		return -1.0
	var dist := o.distance_to(global_transform * (hit as Vector3))
	return dist if dist <= max_d else -1.0
