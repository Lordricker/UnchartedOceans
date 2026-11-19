class_name TradeState
extends RefCounted
## What the whole run knows about trade: the player's gold, each port's market (prices drift as you buy and sell,
## trade_market.gd) and what is waiting in each port box. All static, so it survives ports being unloaded and
## loaded again as you sail.
##
## Anything that wants to read or change these (the stall menus, a future save game, a real UI) goes through here.

## Placeholder purse for testing until money is earned.
static var gold := 5000

## Port id -> TradeMarket.
static var markets := {}

## Port box key ("<port id>/<berth name>") -> Array of good ids, one entry per box waiting.
static var _stock := {}


## The market of a port, made the first time it is asked for. The region is the port id's first letter
## (AC00 is region A, CC02 is region C), falling back to A.
static func market_for(port_id: String) -> TradeMarket:
	var m = markets.get(port_id)
	if m == null:
		var data := CargoData.get_shared()
		var region := port_id.substr(0, 1).to_upper()
		if not data.regions.has(region):
			region = "A"
		m = TradeMarket.new(data, port_id, region)
		var tier := _tier_of(port_id)
		m.economy = float(TIER_ECONOMY.get(tier, m.economy))
		m.prosperity = float(TIER_PROSPERITY.get(tier, m.prosperity))
		markets[port_id] = m
	return m as TradeMarket


## Rich ports absorb more trade before the price moves, recover faster, import goods and stock the locked luxuries
## (trade_market.gd: import_economy 400, locked_economy 700). A small port sells only what its region makes.
const TIER_ECONOMY := {"capital": 800.0, "free_port": 550.0, "small": 250.0}
const TIER_PROSPERITY := {"capital": 112.0, "free_port": 100.0, "small": 94.0}

static func _tier_of(port_id: String) -> String:
	var chart := WorldChart.load_default()
	if chart != null:
		var p := chart.get_port(port_id)
		if not p.is_empty():
			return String(p.get("tier", "small"))
	return "small"


## Game days seen so far (the weather's voyage day), so the markets can be settled for the days that passed.
static var _last_day := -1

## Call when a market is about to be looked at: lets every market recover for the game days that went by since
## the last look (a sleep counts). Safe with no weather node (does nothing).
static func sync_days(tree: SceneTree) -> void:
	var wx := tree.get_first_node_in_group("weather")
	if wx == null or not wx.has_method("voyage_day"):
		return
	var day := int(wx.voyage_day())
	if _last_day < 0:
		_last_day = day
		return
	var passed := day - _last_day
	if passed <= 0:
		return
	_last_day = day
	for id in markets:
		(markets[id] as TradeMarket).advance_days(passed)


## What you paid, per good: {good id: {"n": boxes still held, "paid": total gold for them}}. Boxes sold take their
## share off, so the average cost stays right. Only the purchases made through the stalls count.
static var cost_basis := {}

static func note_bought(good_id: String, n: int, gold_paid: int) -> void:
	var c: Dictionary = cost_basis.get(good_id, {"n": 0, "paid": 0.0})
	c["n"] = int(c["n"]) + n
	c["paid"] = float(c["paid"]) + float(gold_paid)
	cost_basis[good_id] = c


## Average gold paid per box, or -1 if you hold nothing you bought.
static func avg_cost(good_id: String) -> float:
	var c: Dictionary = cost_basis.get(good_id, {})
	if c.is_empty() or int(c["n"]) <= 0:
		return -1.0
	return float(c["paid"]) / float(c["n"])


static func note_sold(good_id: String, n: int) -> void:
	var c: Dictionary = cost_basis.get(good_id, {})
	if c.is_empty():
		return
	var avg := float(c["paid"]) / maxf(float(c["n"]), 1.0)
	var k := mini(n, int(c["n"]))
	c["n"] = int(c["n"]) - k
	c["paid"] = maxf(float(c["paid"]) - avg * float(k), 0.0)
	cost_basis[good_id] = c


## True: every port box, at every berth and port, opens onto the same pool (a connected void: buy anywhere, take it
## out of any port box). Set false for a separate store per port box, e.g. when ports get warehouses.
static var connected := true

## The one pool all port boxes share while `connected` is on.
static var _pool: Array = []

## The boxes waiting in one port box (the live array: edit it in place).
static func box_stock(key: String) -> Array:
	if connected:
		return _pool
	if not _stock.has(key):
		_stock[key] = []
	return _stock[key]
