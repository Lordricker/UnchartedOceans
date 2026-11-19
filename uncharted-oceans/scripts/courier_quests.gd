class_name CourierQuests
extends RefCounted
## Courier side quests: the folk standing about a port (courier_npc.gd) ask you to carry a parcel to another port.
##
##   Talk to one (courier_dialog.gd) and accept: the parcel appears in the port box at your berth. Take it out, stow it
##   in the hold, sail to the named port and put the parcel in a port box there: the job is done and the reward paid
##   (cargo_system.gd calls deliver() whenever a parcel is put into a port box). The town is trusted to get it to the
##   right person.
##
## Every job's parcel is its own good ("parcel_<n>"), registered into CargoData at run time rather than listed in
## goods.json, so the cargo system carries, stows and draws it like any other box and the port boxes' shared pool
## needs no change. It never appears in a market.
##
## Everything here is static, like trade_state.gd, so it survives ports being unloaded and loaded again. The Side
## Quests book on the shelf (ship_bookshelf.gd) reads book_markdown().

const StallScript := preload("res://scripts/market_stall.gd")
const TradeStateScript := preload("res://scripts/trade_state.gd")

## Reward = REWARD_BASE + REWARD_PER_KM x the straight-line km to the destination, give or take 15%, in 5s.
const REWARD_BASE := 30.0
const REWARD_PER_KM := 0.9
## A job's destination is one of this many nearest other ports.
const NEAREST_PORTS := 8
const PARCEL_KG := 10.0
const PARCEL_PREFIX := "parcel_"

## Names by the port's region (the first letter of its id), matching how the ports are named on the chart.
const NAMES := {
	"A": ["Tom Hale", "Edmund Rudd", "Mary Pike", "Jory Penhallow", "Alys Fenn", "Will Cotter", "Hester Bray", "Nat Garrow"],
	"B": ["Chen Wei", "Lin Mei", "Ah Fook", "Zhou Rong", "Wu Tao", "Xiao Lan", "Ma Jin", "Fang Yu"],
	"C": ["Yusuf Demir", "Leyla Aksoy", "Selim Kaya", "Zehra Yildiz", "Murat Celik", "Ayla Sahin", "Kemal Arslan", "Nilufer Ozturk"],
	"D": ["Juma Mwinyi", "Amani Said", "Zawadi Khamis", "Baraka Omari", "Neema Hamisi", "Rashidi Ali", "Tumaini Juma", "Salma Bakari"],
	"F": ["Pieter Voss", "Amara Cole", "Dai Lung", "Mehmet Ince", "Joan Merrow", "Kofi Adair", "Isla Brandt", "Ravi Nair"],
}

const ITEMS := [
	"a box of letters and papers", "a crate of mending thread and needles", "a box of spare clock parts",
	"a parcel of medicines", "a box of glassware, well wrapped", "a bundle of ship's papers",
	"a box of my brother's tools", "a wedding gift, well wrapped", "a box of books", "a small crate of lamp oil flasks",
]

## What the person says when they offer a job: the item, the port, the reward gold.
const ASKS := [
	"Captain! You look like someone who is going places. I have %s that must reach %s. Nothing to trouble the customs, I swear it. It pays %d gold when it gets there. Will you take it?",
	"A word, Captain. I have %s for a cousin in %s, and no ship that will carry it. Take it for me and you will be paid %d gold. Put it in the port box over there and the town will see it to the right hands.",
	"Captain, I have %s that has to reach %s, and the carriers want a fortune for it. I can offer %d gold on delivery. Will you do it?",
	"Captain, you have a hold and I have a problem. %s, bound for %s, and my own boat is on the hard. Carry it and I will see you get %d gold.",
]

## npc key -> the job on offer: {to, to_name, item, reward, km, text}
static var offers := {}
## Jobs taken and not yet delivered: {id, npc_key, giver, from, to, to_name, item, reward, km, day}
static var active: Array = []
## Jobs delivered: {giver, from, to, to_name, reward}
static var done: Array = []
static var total_earned := 0
## npc key -> true once their last parcel arrived (they thank you next time you talk).
static var thanks := {}

## Picked once per run, so the jobs on offer differ every time you play (but stay the same while the run lasts).
static var _salt := 0

static func session_salt() -> int:
	if _salt == 0:
		var r := RandomNumberGenerator.new()
		r.randomize()
		_salt = r.randi_range(1, 2147483646)
	return _salt


static var _jobs_made := {}      # npc key -> jobs offered so far (so each new job is different)
static var _serial := 0
static var _chart: WorldChart


static func chart() -> WorldChart:
	if _chart == null:
		_chart = WorldChart.load_default()
	return _chart


static func port_name(port_id: String) -> String:
	var c := chart()
	return c.port_name(port_id) if c != null else port_id


## A person's name: the same for the same port and slot within a run, different from run to run.
static func name_for(port_id: String, slot: int) -> String:
	var region := port_id.substr(0, 1).to_upper()
	var list: Array = NAMES.get(region, NAMES["A"])
	return String(list[(absi(hash("%s/%d" % [port_id, session_salt()])) + slot * 3) % list.size()])


static func is_parcel(good_id: String) -> bool:
	return good_id.begins_with(PARCEL_PREFIX)


# ------------------------------------------------------------------ offers

## The job this person has for you (made the first time it is asked for, and kept until you accept it). {} if there is
## no other port to send you to.
static func offer_for(key: String, port_id: String) -> Dictionary:
	if offers.has(key):
		return offers[key]
	var c := chart()
	var here: Dictionary = c.get_port(port_id) if c != null else {}
	if here.is_empty():
		return {}
	var cands: Array = []
	for p in c.ports:
		if String(p["id"]) == port_id:
			continue
		cands.append({"p": p, "d": WorldChart.distance_m(float(p["x"]), float(p["z"]), float(here["x"]), float(here["z"]))})
	if cands.is_empty():
		return {}
	cands.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	var n := int(_jobs_made.get(key, 0))
	_jobs_made[key] = n + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s/job%d/%d" % [key, n, session_salt()])
	var pick: Dictionary = cands[rng.randi_range(0, mini(NEAREST_PORTS, cands.size()) - 1)]
	var km := float(pick["d"]) / 1000.0
	var reward := roundi((REWARD_BASE + REWARD_PER_KM * km) * rng.randf_range(0.85, 1.15) / 5.0) * 5
	var item: String = ITEMS[rng.randi_range(0, ITEMS.size() - 1)]
	var to_name := String(pick["p"]["name"])
	var text := String(ASKS[rng.randi_range(0, ASKS.size() - 1)]) % [item, to_name, reward]
	if thanks.has(key):
		thanks.erase(key)
		text = "Word has come that my last parcel arrived safe. My thanks, Captain. " + text
	var offer := {"to": String(pick["p"]["id"]), "to_name": to_name, "item": item, "reward": reward, "km": km, "text": text}
	offers[key] = offer
	return offer


## The job this person gave you that is still under way, or {}.
static func quest_of_npc(key: String) -> Dictionary:
	for q in active:
		if String(q["npc_key"]) == key:
			return q
	return {}


static func parcel_quest(good_id: String) -> Dictionary:
	for q in active:
		if String(q["id"]) == good_id:
			return q
	return {}


# ------------------------------------------------------------------ accepting

## Take the offered job: the parcel is sent to the port box nearest your ship. {ok, msg}.
static func accept(tree: SceneTree, key: String, port_id: String, giver: String, from: Vector3) -> Dictionary:
	var offer: Dictionary = offers.get(key, {})
	if offer.is_empty():
		return {"ok": false, "msg": ""}
	var box = StallScript.nearest_box(tree, from)
	if box == null:
		return {"ok": false, "msg": "Bring your ship alongside a berth first, Captain, so I know where to send the parcel."}
	_serial += 1
	var q := {
		"id": "%s%d" % [PARCEL_PREFIX, _serial], "npc_key": key, "giver": giver, "from": port_id,
		"to": offer["to"], "to_name": offer["to_name"], "item": offer["item"], "reward": offer["reward"],
		"km": offer["km"], "day": _day(tree),
	}
	_register_good(q)
	box.add_boxes(String(q["id"]), 1)
	active.append(q)
	offers.erase(key)
	return {"ok": true, "msg": "Thank you, Captain. The parcel is in the port box at your berth."}


## Give the job back: the parcel is taken out of the port box, the hold or your hands, and the person may offer a new job.
static func abandon(tree: SceneTree, key: String) -> void:
	var q := quest_of_npc(key)
	if q.is_empty():
		return
	var id := String(q["id"])
	var pool: Array = TradeStateScript.box_stock("")
	while pool.has(id):
		pool.erase(id)
	for k in TradeStateScript._stock:
		var s: Array = TradeStateScript._stock[k]
		while s.has(id):
			s.erase(id)
	var cs := tree.get_first_node_in_group("cargo_system")
	if cs != null:
		if cs.get("carried") != null and (cs.get("carried") as GoodDef).id == id:
			cs.call("_let_go")
		if int(cs.hold_counts().get(id, 0)) > 0:
			cs.remove_from_hold(id, 1)
	active.erase(q)


static func _register_good(q: Dictionary) -> void:
	var data := CargoData.get_shared()
	var g := GoodDef.new()
	g.id = String(q["id"])
	g.display_name = "Parcel for %s" % q["to_name"]
	g.category = "courier"
	g.container = "small chest"
	var base: Array[Vector3i] = [Vector3i.ZERO]
	g.base_cells = base
	g.cells = GoodDef.scale_cells(base, data.scale)
	g.weight_kg = PARCEL_KG
	g.base_price = 1
	var fl: Array[String] = ["quest"]
	g.flags = fl
	data.goods[g.id] = g


static func _day(tree: SceneTree) -> int:
	var wx := tree.get_first_node_in_group("weather")
	if wx != null and wx.has_method("voyage_day"):
		return int(wx.voyage_day())
	return 0


# ------------------------------------------------------------------ delivering

## What the aim prompt says while you hold a parcel and look at a port box.
static func prompt_for(good_id: String, port_id: String) -> String:
	var q := parcel_quest(good_id)
	if q.is_empty():
		return "Click: hand the parcel in (nobody is waiting for it now)"
	if String(q["to"]) == port_id:
		return "Click: deliver the parcel (%d gold)" % int(q["reward"])
	return "Click: put it back in the port box (it is for %s)" % q["to_name"]


## A parcel is put into a port box of port `port_id`. {ok: it was taken (delivered), msg: what to tell the player}.
## ok false with a msg: wrong port, so the parcel goes back in the box as any box would.
static func deliver(good_id: String, port_id: String) -> Dictionary:
	if not is_parcel(good_id):
		return {"ok": false, "msg": ""}
	var q := parcel_quest(good_id)
	if q.is_empty():
		return {"ok": true, "msg": "Nobody is waiting for that parcel any more. The porters take it off your hands."}
	if String(q["to"]) != port_id:
		return {"ok": false, "msg": "Put back in the port box. That parcel is for %s." % q["to_name"]}
	var reward := int(q["reward"])
	TradeStateScript.gold += reward
	total_earned += reward
	thanks[String(q["npc_key"])] = true
	done.append({"giver": q["giver"], "from": q["from"], "to": q["to"], "to_name": q["to_name"], "reward": reward})
	active.erase(q)
	return {"ok": true, "msg": "Parcel delivered to %s. The town will see it to the right hands.  +%d gold" % [q["to_name"], reward]}


# ------------------------------------------------------------------ the Side Quests book

## The book's text, in the book reader's markdown (ship_bookshelf.gd asks for it each time the book is opened).
static func book_markdown() -> String:
	var s := PackedStringArray()
	s.append("# Side Quests")
	s.append("")
	s.append("*Jobs the folk of the ports have asked of you.*")
	s.append("")
	s.append("## Under way")
	s.append("")
	if active.is_empty():
		s.append("Nothing at present. People standing about the quays sometimes have a parcel that needs carrying to another port. Talk to them.")
	else:
		for q in active:
			s.append("- Parcel for %s, from %s of %s (about %d km). Take it to a port box there. Pays %d gold." % [
				q["to_name"], q["giver"], port_name(String(q["from"])), roundi(float(q["km"])), int(q["reward"])])
	s.append("")
	s.append("## Delivered")
	s.append("")
	if done.is_empty():
		s.append("Nothing delivered yet.")
	else:
		s.append("You have delivered %d parcel%s and earned %d gold." % [done.size(), "" if done.size() == 1 else "s", total_earned])
		s.append("")
		var first := maxi(done.size() - 8, 0)
		for i in range(done.size() - 1, first - 1, -1):
			var d: Dictionary = done[i]
			s.append("- %s of %s: carried to %s. %d gold." % [d["giver"], port_name(String(d["from"])), d["to_name"], int(d["reward"])])
	return "\n".join(s)


## A new run: no jobs on offer, none taken, a new salt.
static func reset() -> void:
	offers.clear()
	active.clear()
	done.clear()
	total_earned = 0
	thanks.clear()
	_jobs_made.clear()
	_serial = 0
	_salt = 0
