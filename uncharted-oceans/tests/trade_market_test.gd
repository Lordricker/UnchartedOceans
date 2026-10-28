extends SceneTree
## Run: godot --headless --path <project> --script res://tests/trade_market_test.gd

var fails := 0


func check(name: String, ok: bool) -> void:
	if ok:
		print("PASS ", name)
	else:
		print("FAIL ", name)
		fails += 1


func _init() -> void:
	var data := CargoData.new()
	check("load", data.load_file())
	check("39 goods", data.goods.size() == 39)
	var warns := data.validate()
	for w in warns:
		print("  warn: ", w)
	check("goods table valid (connected shapes, prices, weights)", warns.is_empty())

	var grain := data.get_good("grain")
	check("grain scaled to 8 cells", grain.cells.size() == 8)
	check("grain size 2x2x2", grain.size_cells() == Vector3i(2, 2, 2))
	var timber := data.get_good("timber")
	var rot := GoodDef.rotated_yaw(timber.cells, 1)
	check("rotation keeps cell count", rot.size() == timber.cells.size())
	check("rotation swaps long axis", GoodDef.new() != null and _span(rot).x == _span(timber.cells).z)

	# price formula: grain, region A (cheap), 100/100 -> 18 * 0.6 * 1.08 = 11.66 -> 12
	var mk := TradeMarket.new(data, "test", "A")
	check("grain buy price A", mk.buy_price("grain") == 12)
	check("grain sell price A", mk.sell_price("grain") == 10)
	var mb := TradeMarket.new(data, "test", "B")
	check("grain dearer in B", mb.buy_price("grain") > mk.buy_price("grain"))

	# buying pushes the price up, spills into category, barely into others
	var before := mk.buy_price("salt")
	mk.buy("grain", 5)
	check("grain rate rose", mk.rate_of("grain") > 100.0)
	check("same category spill", mk.rate_of("salt") > 100.0 and mk.rate_of("salt") < mk.rate_of("grain"))
	check("global spill smallest", mk.rate_of("pepper") > 100.0 and mk.rate_of("pepper") < mk.rate_of("salt"))
	check("salt price moved", mk.buy_price("salt") >= before)

	# no sell-buy loop profit
	var loop := TradeMarket.new(data, "loop", "A")
	var paid := loop.buy("grain", 10)
	var got := loop.sell("grain", 10)
	check("buy then sell loses money", got < paid)

	# quotes do not mutate
	var q := TradeMarket.new(data, "q", "A")
	q.quote_buy("grain", 10)
	check("quote is non-mutating", q.rates.is_empty())

	# clamp
	var c := TradeMarket.new(data, "c", "A")
	c.buy("grain", 500)
	check("rate clamped high", c.rate_of("grain") <= 150.0)
	c.sell("grain", 2000)
	check("rate clamped low", c.rate_of("grain") >= 50.0)

	# settlement recovers toward 100, richer ports faster
	var poor := TradeMarket.new(data, "p", "A")
	poor.economy = 100.0
	poor.buy("grain", 20)
	var rich := TradeMarket.new(data, "r", "A")
	rich.economy = 900.0
	rich.buy("grain", 20)
	var p0 := poor.rate_of("grain")
	var r0 := rich.rate_of("grain")
	poor.advance_days(4)
	rich.advance_days(4)
	check("poor recovers", poor.rate_of("grain") < p0)
	check("rich recovers faster (relative)", (rich.rate_of("grain") - 100.0) / (r0 - 100.0) < (poor.rate_of("grain") - 100.0) / (p0 - 100.0))
	var half := TradeMarket.new(data, "h", "A")
	half.buy("grain", 10)
	var h0 := half.rate_of("grain")
	half.advance_days(3)
	check("no settle before 4 days", half.rate_of("grain") == h0)

	# availability gating
	var low := TradeMarket.new(data, "l", "A")
	check("local produce sold", low.sells("grain"))
	check("import blocked at default economy", not low.sells("salt"))
	low.economy = 450.0
	check("import sold with economy", low.sells("salt"))
	check("locked blocked", not low.sells("silk"))
	low.economy = 750.0
	check("locked unlocked", low.sells("silk"))

	# save round trip
	var back := TradeMarket.from_dict(mk.to_dict(), data)
	check("save round trip", is_equal_approx(back.rate_of("grain"), mk.rate_of("grain")))

	quit(fails)


func _span(cells: Array[Vector3i]) -> Vector3i:
	var mx := Vector3i.ZERO
	for c in cells:
		mx = Vector3i(maxi(mx.x, c.x), maxi(mx.y, c.y), maxi(mx.z, c.z))
	return mx + Vector3i.ONE
