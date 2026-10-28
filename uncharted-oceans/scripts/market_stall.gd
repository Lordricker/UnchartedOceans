class_name MarketStall
extends RefCounted
## One stall of a port's market: what it is called, which goods it sells, and buying from it.
## It holds no UI. The menu (market_menu.gd) asks it what to list and calls buy(); a future real UI can do the same.
##
## Buying takes gold (TradeState.gold), moves the port's prices (trade_market.gd) and sends the boxes to the port
## box at the berth where your ship lies (cargo_generator.gd). You then carry them to the hold yourself.

const TradeStateScript := preload("res://scripts/trade_state.gd")

## The Blender bay's "interaction" property -> the stall.
##   goods  : the "stall" id in goods.json whose categories this stall sells ("" = no goods yet)
##   model  : which res://assets/npcs/NPC_<model>.glb stands behind the counter (placeholders)
##   note   : shown in the menu instead of goods when there are none
const KINDS := {
	"food_market": {"title": "Grocer", "goods": "food_market", "model": "Provisions"},
	"fishmonger": {"title": "Fishmonger", "goods": "food_market", "model": "Provisions"},
	"bakery": {"title": "Bakery", "goods": "", "model": "Provisions", "note": "Buns and tarts. Nothing for sale yet."},
	"spice_trader": {"title": "Spice Trader", "goods": "spice_trader", "model": "SpiceTrader"},
	"tool_shop": {"title": "Metals and Tools", "goods": "tool_shop", "model": "Smith"},
	"cloth_merchant": {"title": "Cloth Merchant", "goods": "cloth_merchant", "model": "Navigator"},
	"charts": {"title": "Cartographer", "goods": "", "model": "Navigator", "note": "Charts and instruments. Nothing for sale yet."},
	"provisions": {"title": "Ship Chandler", "goods": "provisions", "model": "Chandler"},
	"drink_market": {"title": "Wine and Spirits", "goods": "tavern", "model": "Sailor"},
	"armory": {"title": "Armoury", "goods": "armory", "model": "Smith"},
	"dock_office": {"title": "Dock Office", "goods": "", "model": "Sailor", "note": "Harbour business. Nothing here yet."},
}

var kind := ""
var title := ""
var goods_stall := ""
var model := "Sailor"
var note := ""
var port_id := ""


func setup(p_kind: String, p_port_id: String) -> void:
	kind = p_kind
	port_id = p_port_id
	var info: Dictionary = KINDS.get(p_kind, {})
	title = String(info.get("title", p_kind.replace("_", " ").capitalize()))
	goods_stall = String(info.get("goods", ""))
	model = String(info.get("model", "Sailor"))
	note = String(info.get("note", "Nothing for sale here yet."))


func market() -> TradeMarket:
	return TradeStateScript.market_for(port_id)


## The goods this stall sells in this port (what the port makes, plus imports if it is rich enough).
func goods() -> Array[GoodDef]:
	var out: Array[GoodDef] = []
	if goods_stall == "":
		return out
	var mk := market()
	for g in mk.data.goods_for_stall(goods_stall):
		if mk.sells(g.id):
			out.append(g)
	return out


## Price of one box right now.
func price(good_id: String) -> int:
	return market().buy_price(good_id)


## Total for n boxes (the price climbs a little with each one).
func quote(good_id: String, n: int) -> int:
	return market().quote_buy(good_id, n)


## Buy n boxes. Returns the line to show the player.
func buy(tree: SceneTree, from: Vector3, good_id: String, n: int) -> String:
	var mk := market()
	var good := mk.data.get_good(good_id)
	if good == null or not mk.sells(good_id):
		return "That is not for sale here."
	var cost := mk.quote_buy(good_id, n)
	if cost > TradeStateScript.gold:
		return "You cannot afford that."
	var box := nearest_box(tree, from)
	if box == null:
		return "There is no port box to send it to. Bring the ship alongside a berth first."
	var paid := mk.buy(good_id, n)
	TradeStateScript.gold -= paid
	TradeStateScript.note_bought(good_id, n, paid)
	box.add_boxes(good_id, n)
	return "Bought %d x %s for %d gold. It is waiting in the port box at your berth." % [n, good.display_name, paid]


## The goods this stall deals in (anything of its categories, made here or not) that are stowed in the ship's hold,
## with how many: [{good: GoodDef, n: int}]. Selling takes them straight out of the hold (the dockhands unload).
func sellable(tree: SceneTree, _from: Vector3) -> Array:
	var out: Array = []
	var cs := tree.get_first_node_in_group("cargo_system")
	if goods_stall == "" or cs == null:
		return out
	var counts: Dictionary = cs.hold_counts()
	for g in market().data.goods_for_stall(goods_stall):
		if counts.has(g.id):
			out.append({"good": g, "n": int(counts[g.id])})
	return out


## Price the stall pays for one box right now.
func sell_price(good_id: String) -> int:
	return market().sell_price(good_id)


func quote_sell(good_id: String, n: int) -> int:
	return market().quote_sell(good_id, n)


## Sell n boxes out of the hold. Returns the line to show the player.
func sell(tree: SceneTree, _from: Vector3, good_id: String, n: int) -> String:
	var mk := market()
	var good := mk.data.get_good(good_id)
	var cs := tree.get_first_node_in_group("cargo_system")
	if good == null or cs == null:
		return "Nobody wants that."
	var have := int(cs.hold_counts().get(good_id, 0))
	if have < n:
		return "There are only %d in your hold." % have
	var avg := TradeStateScript.avg_cost(good_id)
	n = int(cs.remove_from_hold(good_id, n))
	if n <= 0:
		return "Nothing was unloaded."
	var got := mk.sell(good_id, n)
	TradeStateScript.gold += got
	TradeStateScript.note_sold(good_id, n)
	var line := "Sold %d x %s for %d gold." % [n, good.display_name, got]
	if avg >= 0.0:
		var profit := got - roundi(avg * n)
		line += "  %s %d gold on what you paid." % ["A profit of" if profit >= 0 else "A loss of", absi(profit)]
	return line


## The boxes waiting in the port box the player means (the nearest one; any one, when they share a pool).
func _stock(tree: SceneTree, from: Vector3) -> Array:
	var box := nearest_box(tree, from)
	return TradeStateScript.box_stock(box.stock_key if box != null else "")


## The port box nearest the ship (or to `from` if there is no ship).
static func nearest_box(tree: SceneTree, from: Vector3) -> CargoGenerator:
	var ref := from
	var ship := tree.get_first_node_in_group("ships") as Node3D
	if ship != null:
		ref = ship.global_position
	var best: CargoGenerator = null
	var best_d := INF
	for n in tree.get_nodes_in_group("cargo_generators"):
		var b := n as CargoGenerator
		if b == null:
			continue
		var d := b.global_position.distance_to(ref)
		if d < best_d:
			best_d = d
			best = b
	return best
