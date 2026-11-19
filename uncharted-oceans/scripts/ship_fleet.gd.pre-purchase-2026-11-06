class_name ShipFleet
extends Node
## The player's fleet: exactly ONE ship is "the" ship (the full ShipRig with wheel, sails, ropes, gangway, hold...), every
## other ship lying in a berth is a bare PROXY (just the hull model, no scripts, no interaction), which costs next to nothing.
## You change ships by talking to the harbour master (market_menu.gd, "Harbor Master"): the proxy at the berth you pick is
## replaced by a live rig, and the old rig is replaced by a proxy in the berth it lay in.
##
## Version 1 limits: only ships with a full rig (MODELS[...].sailable) can be taken over, which is the cutter today, and
## only by a ship of the same class. Per-ship state (cargo in the hold, flooding, sail trim) is NOT carried across a swap
## yet: a ship you take over starts fresh. The player must be moored to switch.
##
## Add one ShipFleet node to a world scene (group "ship_fleet"); it finds the active rig and the berths by itself.

signal active_ship_changed(rig: Node3D)

## model index == ship class (ShipClasses.Size)
## "rig": the ShipRig (ship_motion.gd) settings that belong to this hull; anything not listed keeps the script's default
## (the brig is the default rig). "spawn": where the player stands, in the rig's frame, when he comes aboard from a
## ship of another class (the same class keeps his exact spot).
static var MODELS := {
	0: {"name": "Cutter", "scene": "res://scenes/ships/cutter.tscn", "sailable": true,
		"rig": {"ship_path": NodePath("CutterShip/Cutter"), "ship_class": 0, "max_turn_rate_deg": 9.0, "turn_lag": 1.2,
			"sample_points": PackedVector2Array([Vector2(0, -5), Vector2(0, 5), Vector2(-1.5, -2), Vector2(1.5, -2),
				Vector2(-1.5, 0.5), Vector2(1.5, 0.5), Vector2(-1.4, 3.5), Vector2(1.4, 3.5)])},
		"spawn": Vector3(0.3, 0.375, 4.6)},
	1: {"name": "Brig", "scene": "res://scenes/ships/brig.tscn", "sailable": true,
		"rig": {"ship_path": NodePath("BrigShip/Brig"), "ship_class": 1},
		"spawn": Vector3(0.0, 3.95, 7.35)},
	3: {"name": "Schooner", "scene": "res://scenes/ships/schooner.tscn", "sailable": true,
		"rig": {"ship_path": NodePath("SchoonerShip/Schooner"), "ship_class": 3, "max_turn_rate_deg": 7.0, "turn_lag": 1.6,
			"sample_points": PackedVector2Array([Vector2(0, -6.5), Vector2(0, 6.5), Vector2(-1.8, -3.5), Vector2(1.8, -3.5),
				Vector2(-2.0, 0.5), Vector2(2.0, 0.5), Vector2(-1.8, 4.5), Vector2(1.8, 4.5)])},
		"spawn": Vector3(0.0, 1.5, 4.5)},
}
## ShipRig settings taken from the rig being left (flags, ocean path) rather than from the new hull.
const HULL_KEYS := ["ship_path", "ship_class", "sample_points", "max_turn_rate_deg", "turn_lag", "heading_deg", "windsock_enabled"]

## Fill every berth with a ship (a test of how the harbour performs).
@export var fill_berths := true
## Seconds between checks for berths without a ship (ports stream in and out as you sail).
@export var refill_interval := 1.0
## A berth this close (m, on the water plane) to the active ship's slot counts as the one she lies in.
@export var own_berth_radius := 8.0

var _t := 0.0
var _count := 0
## berth node -> {"model": int, "node": Node3D, "id": int}
var _by_berth := {}
var _busy := false
var _last_berth_count := -1
## Berths (port name + berth name) your ship has lain in: when she sails away they stay empty (the ship you drive is
## one of the fleet, not a copy), so they are never refilled.
var _vacant := {}
var _ocean: Ocean
var _ocean_searched := false

## A ship is only ever added to a berth while no part of it is in the player's view (and within view_distance, m).
## Berths in view stay empty until the player looks away. (Later: a random chance per check for ships to arrive.)
@export var spawn_out_of_view_only := true
@export var view_distance := 1500.0

## Berthed ships rock on the waves (3 cheap height samples each) when this close to the player (m).
@export var bob_distance := 300.0
## How much of the sea's motion a berthed ship follows (1 = all of it).
@export var bob_amount := 0.8


func _ready() -> void:
	add_to_group("ship_fleet")
	print("[ShipFleet] ready, fill_berths=%s" % fill_berths)


func _process(delta: float) -> void:
	if _busy:
		return
	_bob(delta)
	if not fill_berths:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = refill_interval
	_refill()


# ------------------------------------------------------------------ queries

func active_rig() -> Node3D:
	return get_tree().get_first_node_in_group("ships") as Node3D


func active_harbor() -> Node:
	return get_tree().get_first_node_in_group("ship_harbor")


## True while the active ship lies in a berth (you can only change ships then).
func can_switch() -> bool:
	var hb := active_harbor()
	return hb != null and bool(hb.get("moored")) and not _busy


func berth_of_active() -> DockBerth:
	var hb := active_harbor()
	if hb != null and hb.get("berth") != null and bool(hb.get("moored")):
		return hb.get("berth") as DockBerth
	return _nearest_berth_to(active_rig())


## The ships you could change to: [{id, name, model, sailable, berth_name}], oldest first.
func roster() -> Array:
	var out: Array = []
	for b in _by_berth:
		if not is_instance_valid(b):
			continue
		var e: Dictionary = _by_berth[b]
		if not is_instance_valid(e["node"]):
			continue
		var m: Dictionary = MODELS[int(e["model"])]
		out.append({"id": int(e["id"]), "name": String(m["name"]), "model": int(e["model"]),
			"sailable": bool(m["sailable"]), "berth_name": String((b as Node).name)})
	out.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return int(a["id"]) < int(c["id"]))
	return out


func ship_count() -> int:
	return _by_berth.size()


# ------------------------------------------------------------------ proxies

func _ship_class_of(rig: Node3D) -> int:
	var c = rig.get("ship_class")
	return int(c) if c != null else 0


func _nearest_berth_to(rig: Node3D) -> DockBerth:
	if rig == null:
		return null
	var cls := _ship_class_of(rig)
	var best: DockBerth = null
	var bd := own_berth_radius
	for n in get_tree().get_nodes_in_group("dock_berths"):
		var b := n as DockBerth
		if b == null or not b.is_inside_tree():
			continue
		var s := b.slot_position(cls)
		var d := Vector2(s.x - rig.global_position.x, s.z - rig.global_position.z).length()
		if d < bd:
			bd = d
			best = b
	return best


func _model_for(b: DockBerth, index: int) -> int:
	# every ship type that berths here, cycling so each shows up where it can (biggest first)
	var fits: Array = []
	for cls in MODELS:
		if ShipClasses.berth_class(int(cls)) <= b.max_ship_class:
			fits.append(int(cls))
	fits.sort()
	fits.reverse()
	return int(fits[index % fits.size()]) if not fits.is_empty() else 0


func _refill() -> void:
	var own := berth_of_active()
	var berths: Array = get_tree().get_nodes_in_group("dock_berths")
	berths.sort_custom(func(a: Node, c: Node) -> bool: return String(a.name) < String(c.name))
	if berths.size() != _last_berth_count:
		_last_berth_count = berths.size()
		print("[ShipFleet] %d berths in the harbour, %d proxies, active ship at %s" % [berths.size(), _by_berth.size(), own.name if own != null else "no berth"])
	var hb := active_harbor()
	if own != null and hb != null and bool(hb.get("moored")):
		_vacant[_berth_key(own)] = true       # when she sails off, nobody takes her place
	var i := 0
	for n in berths:
		var b := n as DockBerth
		i += 1
		if b == null or not b.is_inside_tree() or b == own:
			continue
		if _by_berth.has(b):
			if is_instance_valid(_by_berth[b]["node"]):
				continue
			_by_berth.erase(b)
		if _vacant.has(_berth_key(b)):
			continue
		var model := _model_for(b, i)
		if _in_view(b, model):
			continue        # never pop a ship in where the player can see it: try again next check
		_spawn_proxy(b, model)
	# forget berths that went away with their port
	for k in _by_berth.keys():
		if not is_instance_valid(k):
			_by_berth.erase(k)


func _spawn_proxy(b: DockBerth, model: int) -> Node3D:
	var m: Dictionary = MODELS[model]
	var ps := load(String(m["scene"])) as PackedScene
	if ps == null:
		push_warning("ship_fleet: cannot load %s" % m["scene"])
		return null
	var node := ps.instantiate() as Node3D
	if node == null:
		return null
	# a proxy is a picture of a ship: nothing to climb, nothing to click
	var climb := node.find_child("Climbing", true, false)
	if climb != null:
		climb.get_parent().remove_child(climb)
		climb.free()
	_count += 1
	node.name = "Moored_%s_%d" % [m["name"], _count]
	b.get_parent().add_child(node)
	var pos := b.slot_position(model)
	node.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(b.berth_heading)), Vector3(pos.x, 0.0, pos.z))
	_by_berth[b] = {"model": model, "node": node, "id": _count, "yaw": deg_to_rad(b.berth_heading), "h": 0.0, "pitch": 0.0, "roll": 0.0}
	return node


## True if any part of a ship lying in this berth (bow, middle, stern, and the masts above) would be inside the
## camera's view and closer than view_distance. Walls and buildings are not counted: if the camera frustum has it, it is "in view".
func _in_view(b: DockBerth, model: int) -> bool:
	if not spawn_out_of_view_only:
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var s := b.slot_position(model)
	var half := float(ShipClasses.data(model).length) * 0.5
	var f := b.forward2()
	for along in [-half, 0.0, half]:
		for y in [0.0, 12.0]:
			var pt := Vector3(s.x + f.x * along, y, s.z + f.y * along)
			if cam.global_position.distance_to(pt) <= view_distance and cam.is_position_in_frustum(pt):
				return true
	return false


func _berth_key(b: Node) -> String:
	return "%s/%s" % [b.get_parent().name if b.get_parent() != null else "", b.name]


## Berthed ships rise and fall with the sea: height from the mean of four samples (bow, stern, port, starboard), pitch
## and roll from their differences, eased so it never jerks. Only ships near the player are updated.
func _bob(delta: float) -> void:
	if _ocean == null:
		if not _ocean_searched:
			_ocean_searched = true
			var found := get_tree().root.find_children("*", "Ocean", true, false)
			if found.size() > 0:
				_ocean = found[0] as Ocean
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var ref := player.global_position if player != null else Vector3.ZERO
	var k := 1.0 - exp(-delta * 4.0)
	for b in _by_berth:
		var e: Dictionary = _by_berth[b]
		var n := e["node"] as Node3D
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var p := n.global_position
		if Vector2(p.x - ref.x, p.z - ref.z).length() > bob_distance:
			continue
		var d := ShipClasses.data(int(e["model"]))
		var hl := float(d.length) * 0.4
		var hbm := float(d.beam) * 0.5
		var yaw: float = e["yaw"]
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var rgt := Vector3(cos(yaw), 0.0, -sin(yaw))
		var h_bow := _ocean.get_height(p.x + fwd.x * hl, p.z + fwd.z * hl)
		var h_stn := _ocean.get_height(p.x - fwd.x * hl, p.z - fwd.z * hl)
		var h_stb := _ocean.get_height(p.x + rgt.x * hbm, p.z + rgt.z * hbm)
		var h_prt := _ocean.get_height(p.x - rgt.x * hbm, p.z - rgt.z * hbm)
		var th := (h_bow + h_stn + h_stb + h_prt) * 0.25 * bob_amount
		var tp := atan2(h_bow - h_stn, hl * 2.0) * bob_amount      # bow up = +
		var tr := atan2(h_stb - h_prt, hbm * 2.0) * bob_amount     # starboard up = +
		e["h"] = lerpf(float(e["h"]), th, k)
		e["pitch"] = lerpf(float(e["pitch"]), tp, k)
		e["roll"] = lerpf(float(e["roll"]), tr, k)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, float(e["pitch"])) * Basis(Vector3.BACK, float(e["roll"]))
		n.global_transform = Transform3D(basis, Vector3(p.x, float(e["h"]), p.z))


# ------------------------------------------------------------------ changing ship

## Take over the ship with this roster id. Returns "" on success, else the reason it could not be done.
func activate(id: int) -> String:
	if _busy:
		return "Busy."
	if not can_switch():
		return "Moor your ship first."
	var target_berth: DockBerth = null
	for b in _by_berth:
		if int(_by_berth[b]["id"]) == id:
			target_berth = b
	if target_berth == null or not is_instance_valid(target_berth):
		return "That ship is not in the harbour any more."
	var e: Dictionary = _by_berth[target_berth]
	var model := int(e["model"])
	if not bool(MODELS[model]["sailable"]):
		return "The %s is not ready to sail yet." % String(MODELS[model]["name"]).to_lower()
	var old := active_rig()
	if old == null:
		return "No ship to leave."
	var old_berth := berth_of_active()
	if old_berth == null:
		return "Your ship is not at a berth."
	if target_berth.max_ship_class < ShipClasses.berth_class(model):
		return "That berth is too small for her."
	_do_switch(old, old_berth, _ship_class_of(old), model, target_berth, e)
	return ""


func _do_switch(old: Node3D, old_berth: DockBerth, old_model: int, model: int, new_berth: DockBerth, entry: Dictionary) -> void:
	_busy = true
	var parent := old.get_parent()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var local_pos := Vector3.ZERO
	if player != null:
		local_pos = old.global_transform.affine_inverse() * player.global_position
	var proxy := entry["node"] as Node
	_by_berth.erase(new_berth)
	if is_instance_valid(proxy):
		proxy.get_parent().remove_child(proxy)
		proxy.queue_free()
	# the old rig leaves the groups at once so nothing finds it any more
	var old_name := old.name
	old.remove_from_group("ships")
	var oh := old.get_node_or_null("ShipHarbor")
	if oh != null:
		oh.remove_from_group("ship_harbor")
	old.name = "%s_parked" % old_name
	old.visible = false
	old.process_mode = Node.PROCESS_MODE_DISABLED
	# the new rig, with the old one's exported settings
	var rig := _build_rig(old, model)
	rig.name = old_name
	var slot := new_berth.slot_position(model)
	rig.set("heading_deg", new_berth.berth_heading)
	parent.add_child(rig)
	rig.global_position = Vector3(slot.x, 0.0, slot.z)
	_spawn_proxy(old_berth, old_model)
	# the spray follows the new rig
	var oc = rig.get("_ocean")
	if oc != null:
		var ws := (oc as Node).get_node_or_null("WaveSpray")
		if ws != null:
			ws.set("motion", rig)
	# let the new rig finish _ready, then moor it and carry the player aboard
	await get_tree().process_frame
	await get_tree().process_frame
	var oc2 = rig.get("_ocean")
	if oc2 != null:
		var ws2 := (oc2 as Node).get_node_or_null("WaveSpray")
		if ws2 != null:
			ws2.set("motion", rig)
	var hb := rig.get_node_or_null("ShipHarbor")
	if hb != null and hb.has_method("start_moored_at"):
		hb.start_moored_at(new_berth)
	if player != null:
		var stand := local_pos if old_model == model else (MODELS[model]["spawn"] as Vector3)
		player.global_position = rig.global_transform * stand
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer != null:
		streamer.set("_ship", rig)
	old.queue_free()
	_busy = false
	active_ship_changed.emit(rig)


## A fresh rig of the same class: a ShipRig (ship_motion.gd) holding the hull scene and the flooding node, with every
## @export copied from the rig it replaces (paths, flags, turn rates, ...).
func _build_rig(template: Node3D, model: int) -> Node3D:
	var rig := Node3D.new()
	rig.set_script(template.get_script())
	_copy_exports(template, rig, HULL_KEYS)
	var ov: Dictionary = MODELS[model]["rig"]
	for k in ov:
		rig.set(k, ov[k])
	rig.add_child((load(String(MODELS[model]["scene"])) as PackedScene).instantiate())
	var flood_src := template.get_node_or_null("Flooding")
	if flood_src != null:
		var fl := Node3D.new()
		fl.set_script(flood_src.get_script())
		_copy_exports(flood_src, fl)
		fl.name = "Flooding"
		rig.add_child(fl)
	return rig


## Only the script's own @export variables (not the Node3D transform or visibility, which belong to the old rig).
func _copy_exports(from: Object, to: Object, skip: Array = []) -> void:
	for p in from.get_property_list():
		var usage := int(p["usage"])
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		var pname := String(p["name"])
		if skip.has(pname):
			continue
		to.set(pname, from.get(pname))
