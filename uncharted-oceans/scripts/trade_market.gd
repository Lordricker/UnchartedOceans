class_name TradeMarket
extends RefCounted
## Per-port market, modelled on Uncharted Waters: New Horizons.
## price = base x region multiplier x prosperity/100 x rate/100 (x markup or markdown).
## Each box bought or sold nudges that good's rate; same-category goods are
## nudged by a spill fraction and everything else slightly. Every settle_days
## game days the rates drift back toward 100, faster in rich ports.

var data: CargoData
var port_id: String = ""
var region: String = "A"
var prosperity: float = 100.0
var economy: float = 300.0
var rates: Dictionary = {}  # good id -> percent
var _day_acc: int = 0


func _init(p_data: CargoData = null, p_port: String = "", p_region: String = "A") -> void:
	data = p_data if p_data != null else CargoData.get_shared()
	port_id = p_port
	region = p_region
	prosperity = _m("prosperity_default")
	economy = _m("economy_default")


func _m(key: String) -> float:
	return float(data.market.get(key, 0.0))


func rate_of(id: String) -> float:
	return float(rates.get(id, _m("rate_default")))


func sells(id: String) -> bool:
	var g := data.get_good(id)
	if g == null:
		return false
	if g.has_flag("locked") and economy < _m("locked_economy"):
		return false
	if g.produced_in.has(region):
		return true
	return economy >= _m("import_economy")


func buy_price(id: String) -> int:
	return _price(id, rate_of(id), _m("buy_markup"))


func sell_price(id: String) -> int:
	return _price(id, rate_of(id), _m("sell_markdown"))


func _price(id: String, rate: float, factor: float) -> int:
	var g := data.get_good(id)
	if g == null:
		return 0
	var p := float(g.base_price) * g.multiplier_for(region) * local_mult(id) * (prosperity / 100.0) * (rate / 100.0) * factor
	return maxi(1, roundi(p))


## A small fixed difference between ports of the same region (+-8%, the same every run), so no two ports
## quote exactly alike and a short hop between neighbours can still pay a little.
func local_mult(id: String) -> float:
	var h := absi(hash(port_id + "/" + id)) % 1000
	return 1.0 + (float(h) / 1000.0 - 0.5) * 0.16


## How this port's price for a good compares with the good's plain base price (1.0 = base, 0.6 = very cheap).
## The sell side is a markdown, so this is the quoted price without the dealer's cut.
func price_ratio(id: String) -> float:
	var g := data.get_good(id)
	if g == null or g.base_price <= 0:
		return 1.0
	return (float(g.base_price) * g.multiplier_for(region) * local_mult(id) * (prosperity / 100.0) * (rate_of(id) / 100.0)) / float(g.base_price)


## Step size per box, scaled so rich ports absorb more.
func _step() -> float:
	var f := clampf(_m("economy_default") / maxf(economy, 1.0), 0.3, 2.0)
	return _m("rate_step_per_box") * f


## Rate after n boxes would be bought (rates fall? no: buying raises price).
func _after(id: String, boxes: int, dir: float) -> Dictionary:
	var out: Dictionary = rates.duplicate()
	var cat := data.get_good(id).category
	var step := _step()
	for i in boxes:
		for gid in data.order:
			var g: GoodDef = data.goods[gid]
			var w := _m("global_spill")
			if gid == id:
				w = 1.0
			elif g.category == cat:
				w = _m("category_spill")
			var r: float = float(out.get(gid, _m("rate_default")))
			out[gid] = clampf(r + dir * step * w, _m("rate_min"), _m("rate_max"))
	return out


## Total cost of buying n boxes (does not mutate). Price moves per box.
func quote_buy(id: String, boxes: int) -> int:
	var total := 0
	var sim := _clone_with(rates)
	for i in boxes:
		total += sim.buy_price(id)
		sim.rates = sim._after(id, 1, 1.0)
	return total


func quote_sell(id: String, boxes: int) -> int:
	var total := 0
	var sim := _clone_with(rates)
	for i in boxes:
		total += sim.sell_price(id)
		sim.rates = sim._after(id, 1, -1.0)
	return total


func buy(id: String, boxes: int) -> int:
	var total := quote_buy(id, boxes)
	rates = _after(id, boxes, 1.0)
	return total


func sell(id: String, boxes: int) -> int:
	var total := quote_sell(id, boxes)
	rates = _after(id, boxes, -1.0)
	return total


func _clone_with(r: Dictionary) -> TradeMarket:
	var m := TradeMarket.new(data, port_id, region)
	m.prosperity = prosperity
	m.economy = economy
	m.rates = r.duplicate()
	return m


## One settlement: drift every rate toward the default.
func settle() -> void:
	var rec := lerpf(_m("recovery_min"), _m("recovery_max"), clampf(economy / _m("economy_max"), 0.0, 1.0))
	var base := _m("rate_default")
	for gid in rates.keys():
		var r: float = rates[gid]
		r = lerpf(r, base, rec)
		if absf(r - base) < 0.25:
			rates.erase(gid)
		else:
			rates[gid] = r


func advance_days(days: int) -> void:
	_day_acc += days
	var n := int(_m("settle_days"))
	while _day_acc >= n:
		_day_acc -= n
		settle()


func to_dict() -> Dictionary:
	return {
		"port": port_id, "region": region, "prosperity": prosperity,
		"economy": economy, "rates": rates.duplicate(), "acc": _day_acc,
	}


static func from_dict(d: Dictionary, p_data: CargoData = null) -> TradeMarket:
	var m := TradeMarket.new(p_data, str(d.get("port", "")), str(d.get("region", "A")))
	m.prosperity = float(d.get("prosperity", m.prosperity))
	m.economy = float(d.get("economy", m.economy))
	m.rates = d.get("rates", {})
	m._day_acc = int(d.get("acc", 0))
	return m
