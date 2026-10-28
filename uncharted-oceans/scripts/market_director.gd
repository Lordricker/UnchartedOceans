class_name MarketDirector
extends Node
## Runs the port markets. One of these lives under the player (cargo_system.gd makes it the first time it runs).
##
##  - Ports: whenever the world streamer has a real port scene in, it fills the port's market bays with stallholders
##    (market_npc.gd). A bay is a glTF node whose Blender custom properties say game_role = "market_bay" and
##    interaction = <kind>; its children carry marker = "npc_stand" (where the stallholder stands) and
##    marker = "customer_stand" (who they face). market_stall.gd says what each kind sells.
##  - Berths: puts a port box (cargo_generator.gd) on the quay beside every berth once the ship is near, at
##    cargo_system.quay_spot in the berth's frame. Purchases are sent to the box nearest the ship.
##  - Clicking: aim at a stallholder (white outline, prompt at the bottom), click to open the stall menu
##    (market_menu.gd). The mouse is freed and the player locked while it is open.

const StallScript := preload("res://scripts/market_stall.gd")
const NpcScript := preload("res://scripts/market_npc.gd")
const MenuScript := preload("res://scripts/market_menu.gd")
const Outline := preload("res://scripts/interact_outline.gd")

## How far you can reach to talk to someone (m). The customer spot is about 3.3 m from the stallholder.
@export var reach := 4.5
## A berth gets its port box once the ship is within this distance of it (m): its quay has loaded by then.
@export var berth_range_m := 400.0
@export var scan_every_s := 0.5
## How many scans to wait for the quay's collision before trusting the berth's own deck height.
@export var ground_tries := 12

var player: CharacterBody3D
var cam: Camera3D
var menu                # the MarketMenu

var _aim                # the MarketNpc being aimed at, or null
var _label: Label
var _scan_t := 0.0
var _boxes := {}        # berth instance id -> its port box
var _tries := {}        # berth instance id -> scans spent looking for the quay


func _ready() -> void:
	add_to_group("market_director")
	player = get_parent() as CharacterBody3D
	if player != null:
		cam = player.get_node_or_null("Head/Camera3D") as Camera3D
	menu = MenuScript.new()
	menu.name = "MarketMenu"
	add_child(menu)
	menu.closed.connect(_on_menu_closed)
	_make_prompt()


func _make_prompt() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.offset_bottom = -230.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	if ResourceLoader.exists("res://assets/fonts/Ferrum-ExtraCondensed.otf"):
		var font := load("res://assets/fonts/Ferrum-ExtraCondensed.otf") as Font
		if font != null:
			_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", 26)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	layer.add_child(_label)


func _process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = scan_every_s
		_scan_ports()
		_scan_berths()
	_update_aim()


# ------------------------------------------------------------------ ports: stallholders

func _scan_ports() -> void:
	for s in get_tree().get_nodes_in_group("world_streamer"):
		for c in s.get_children():
			var port := c as Node3D
			if port == null or not String(port.name).begins_with("Port_"):
				continue
			if not port.has_meta("own_grounding") or port.has_meta("market_done"):
				continue        # a placeholder beacon, or already done
			port.set_meta("market_done", true)
			_fill_market(port, str(port.get_meta("port_id", "")))


func _fill_market(port: Node3D, port_id: String) -> void:
	var made := 0
	for n in port.find_children("*", "Node3D", true, false):
		var ex := _extras(n)
		if str(ex.get("game_role", "")) != "market_bay":
			continue
		var npc_at: Node3D = null
		var customer_at: Node3D = null
		for c in n.get_children():
			match str(_extras(c).get("marker", "")):
				"npc_stand":
					npc_at = c as Node3D
				"customer_stand":
					customer_at = c as Node3D
		if npc_at == null:
			continue
		var stall := StallScript.new()
		stall.setup(str(ex.get("interaction", "")), port_id)
		var npc := NpcScript.new()
		npc.name = "Npc_" + String(n.name)
		npc_at.add_child(npc)
		if customer_at != null:
			npc.face(customer_at.global_position)
		npc.setup(stall.model, stall)
		made += 1
	print("MarketDirector: %d stallholders in %s" % [made, port_id])


func _extras(n: Node) -> Dictionary:
	if n.has_meta("extras"):
		var e = n.get_meta("extras")
		if e is Dictionary:
			return e
	return {}


# ------------------------------------------------------------------ berths: port boxes

func _scan_berths() -> void:
	var ship := get_tree().get_first_node_in_group("ships") as Node3D
	if ship == null or player == null:
		return
	var quay := Vector3(-1.5, 0.0, 2.0)
	var cs = player.get("cargo")
	if cs != null and cs.get("quay_spot") != null:
		quay = cs.get("quay_spot")
	for n in get_tree().get_nodes_in_group("dock_berths"):
		var b := n as DockBerth
		if b == null:
			continue
		var id := b.get_instance_id()
		if _boxes.has(id) and is_instance_valid(_boxes[id]):
			continue
		if b.global_position.distance_to(ship.global_position) > berth_range_m:
			continue
		var port := b.get_parent() as Node3D
		if port == null:
			continue
		var tries := int(_tries.get(id, 0)) + 1
		_tries[id] = tries
		var from := b.to_global(Vector3(quay.x, 8.0, quay.z))
		var to := b.to_global(Vector3(quay.x, -2.0, quay.z))
		var q := PhysicsRayQueryParameters3D.create(from, to, Island.LAYER_BIT)
		var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
		var pos: Vector3
		if not hit.is_empty():
			pos = hit["position"] as Vector3
		elif tries >= ground_tries:
			pos = b.to_global(Vector3(quay.x, b.deck_y, quay.z))     # the quay's collision never showed up: trust the berth's deck height
		else:
			continue
		var box := CargoGenerator.new()
		box.name = "PortBox_" + String(b.name)
		box.stock_key = "%s/%s" % [str(port.get_meta("port_id", port.name)), String(b.name)]
		port.add_child(box)
		box.global_transform = Transform3D(b.global_transform.basis, pos)
		_boxes[id] = box


# ------------------------------------------------------------------ aiming and clicking

func _update_aim() -> void:
	if player == null or cam == null or menu.is_open:
		_set_aim(null)
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not bool(player.get("input_locked"))
	var cg = player.get("cargo")
	if not captured or (cg != null and cg.get("carried") != null):
		_set_aim(null)         # hands full: the cargo system has the clicks
		return
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var best := reach
	var hit: Node3D = null
	for n in get_tree().get_nodes_in_group("market_npcs"):
		var dist: float = n.ray_hit(o, d, best)
		if dist >= 0.0 and dist <= best:
			best = dist
			hit = n as Node3D
	if hit != null:
		# a wall or counter in the way: no
		var q := PhysicsRayQueryParameters3D.create(o, o + d * best, 1 | Island.LAYER_BIT, [player.get_rid()])
		var w := cam.get_world_3d().direct_space_state.intersect_ray(q)
		if not w.is_empty() and o.distance_to(w["position"] as Vector3) < best - 0.25:
			hit = null
	_set_aim(hit)


func _set_aim(n) -> void:
	if n != _aim:
		if _aim != null and is_instance_valid(_aim):
			Outline.set_on(_aim, false)
		_aim = n
		if n != null:
			Outline.set_on(n, true)
	if _aim != null and is_instance_valid(_aim):
		_label.text = "Click: talk to %s" % _aim.stall.title
		_label.visible = true
	else:
		_label.visible = false


func _input(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _aim == null or not is_instance_valid(_aim) or menu.is_open:
		return
	var stall = _aim.stall
	_set_aim(null)
	player.set("input_locked", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.open_for(stall, player.global_position)
	get_viewport().set_input_as_handled()


func _on_menu_closed() -> void:
	if player != null:
		player.set("input_locked", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
