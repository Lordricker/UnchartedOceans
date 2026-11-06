class_name SkyPalette
extends RefCounted
## Sky colours for the sailing game, keyed on how high the sun is and what the air is like.
##
## Real sunsets differ mostly because of what is in the air (dust, smoke, salt haze, humidity) and what the clouds
## are doing, so each air type here has its own sunset and dusk colours. sample() blends two air types, so weather
## can drift from one to another as a front passes.
##
## Each air type is a handful of colours; edit them here to repaint the world's skies.
##   yz / yh   : day zenith / day horizon
##   z, m, h   : sunset zenith / middle / horizon
##   g, c      : sunset glow (wide) / core (hot, near the sun)
##   o, s      : twilight band opposite the sun (pink) / earth-shadow band (blue-grey)
##   cl, ci    : sunset cloud colour where the sun hits it / high cirrus colour
##   dz,dm,dh  : dusk (sun ~6 degrees down) zenith / middle / horizon
##   dg, do    : dusk afterglow / opposite band;  dci: dusk cirrus

const AIR_NAMES: Array[String] = ["Clean & crisp", "Humid haze", "Dust & smoke", "Tropical", "After the storm"]

static var _table: Array = []

static func air_count() -> int:
	return AIR_NAMES.size()

static func _c(hex: String) -> Color:
	return Color.html(hex)

static func _build() -> void:
	_table = [
		{ # 0 clean & crisp: cool deep blue into peach, tidy pink band
			"yz": _c("2a6cc0"), "yh": _c("a8cdee"),
			"z": _c("1f3f7a"), "m": _c("8a82a8"), "h": _c("f0b38a"),
			"g": _c("ff9a4a"), "c": _c("ffd08a"), "o": _c("e89ab4"), "s": _c("3a4a73"),
			"cl": _c("ffb070"), "ci": _c("ff9f7a"),
			"cr": _c("d05a8a"), "csh": _c("4a4078"),
			"dz": _c("131f45"), "dm": _c("3b3d78"), "dh": _c("a24f6c"),
			"dg": _c("c8452f"), "do": _c("8a5a9a"), "dci": _c("d9748a"),
		},
		{ # 1 humid haze: milky, low contrast, peach and cream
			"yz": _c("5f8fc2"), "yh": _c("d9e2e6"),
			"z": _c("5a78a8"), "m": _c("c4a9b0"), "h": _c("f6d3a8"),
			"g": _c("ffbd7a"), "c": _c("ffe2b0"), "o": _c("f0c2cf"), "s": _c("7f8db0"),
			"cl": _c("ffd0a0"), "ci": _c("ffcdb0"),
			"cr": _c("d08aa0"), "csh": _c("7a6a90"),
			"dz": _c("3a4a78"), "dm": _c("8a7590"), "dh": _c("d99a86"),
			"dg": _c("f0a27a"), "do": _c("b890a8"), "dci": _c("f0b8a8"),
		},
		{ # 2 dust and smoke: brick red, burnt orange, heavy glow
			"yz": _c("6f8aa3"), "yh": _c("d0b48f"),
			"z": _c("3b3550"), "m": _c("8a4a3c"), "h": _c("e0622a"),
			"g": _c("ff4a1c"), "c": _c("ffa040"), "o": _c("b86a5a"), "s": _c("4a3548"),
			"cl": _c("ff5a2a"), "ci": _c("e04a2a"),
			"cr": _c("c0301e"), "csh": _c("4a2a3c"),
			"dz": _c("1f1830"), "dm": _c("5a2a3a"), "dh": _c("a8321e"),
			"dg": _c("c8301a"), "do": _c("6a3a48"), "dci": _c("a8321e"),
		},
		{ # 3 tropical: saturated blue, magenta, coral, hot pink cirrus
			"yz": _c("1e7fcf"), "yh": _c("9fe0ea"),
			"z": _c("1c3f8a"), "m": _c("b0508f"), "h": _c("ff8c5a"),
			"g": _c("ff6a4a"), "c": _c("ffc070"), "o": _c("e86aa0"), "s": _c("2a3f7a"),
			"cl": _c("ff7a8a"), "ci": _c("ff6ab0"),
			"cr": _c("d8409a"), "csh": _c("5a2f8a"),
			"dz": _c("1a1a5a"), "dm": _c("6a2f8a"), "dh": _c("d8467a"),
			"dg": _c("e8506a"), "do": _c("8a3fa0"), "dci": _c("e04a9a"),
		},
		{ # 4 after the storm: scrubbed air, deep cobalt, gold and rose, vivid afterglow
			"yz": _c("1b5cab"), "yh": _c("9ed0ee"),
			"z": _c("1a3a8a"), "m": _c("d070a0"), "h": _c("ffc860"),
			"g": _c("ffb030"), "c": _c("fff0a0"), "o": _c("ff8ac0"), "s": _c("2a4090"),
			"cl": _c("ffb84a"), "ci": _c("ff7ab8"),
			"cr": _c("e060a8"), "csh": _c("5a3a9a"),
			"dz": _c("101a5a"), "dm": _c("5a3a9a"), "dh": _c("e0507a"),
			"dg": _c("e8703a"), "do": _c("a050b0"), "dci": _c("f060a8"),
		},
	]

## Night -> dusk -> sunset -> day, picked by how high the sun is (degrees above the horizon).
static func _phase(e: float, night: Variant, dusk: Variant, sunset: Variant, day: Variant) -> Variant:
	if e < -6.0:
		return lerp(night, dusk, smoothstep(-16.0, -6.0, e))
	if e < 0.0:
		return lerp(dusk, sunset, smoothstep(-6.0, 0.0, e))
	return lerp(sunset, day, smoothstep(0.0, 22.0, e))

static func _blend(i: int, e: float) -> Dictionary:
	var t: Dictionary = _table[i]
	var d := {}
	d["zenith"] = _phase(e, _c("04060f"), t["dz"], t["z"], t["yz"])
	var day_mid: Color = (t["yz"] as Color).lerp(t["yh"], 0.5)
	d["mid"] = _phase(e, _c("080d1c"), t["dm"], t["m"], day_mid)
	d["horizon"] = _phase(e, _c("0f1a30"), t["dh"], t["h"], t["yh"])
	d["glow"] = _phase(e, _c("0f1a30"), t["dg"], t["g"], _c("fff0cf"))
	d["core"] = _phase(e, _c("0f1a30"), (t["dg"] as Color).lightened(0.35), t["c"], _c("fffbea"))
	d["opp"] = _phase(e, t["do"], t["do"], t["o"], t["o"])
	d["shadow"] = t["s"]
	d["cloud_lit"] = _phase(e, _c("101828"), (t["dci"] as Color).darkened(0.55), t["cl"], _c("fcfbf8"))
	d["cirrus"] = _phase(e, _c("0c1424"), t["dci"], t["ci"], _c("f4f7ff"))
	# sunset clouds: the side facing away from the sun goes rose / magenta / red (cr), the shaded sides and undersides
	# go purple (csh). sunset_k is how much of that there is: none by day, most as the sun touches the horizon.
	d["cloud_accent"] = _phase(e, _c("101828"), (t["do"] as Color).darkened(0.35), t["cr"], _c("fcfbf8"))
	d["cloud_dark"] = _phase(e, _c("0c1020"), (t["dm"] as Color).darkened(0.2), t["csh"], _c("8090a8"))
	d["sunset_k"] = smoothstep(-8.0, -1.0, e) * (1.0 - smoothstep(2.0, 20.0, e))
	d["glow_strength"] = _phase(e, 0.0, 0.55, 1.0, 0.4)
	d["glow_power"] = _phase(e, 3.0, 2.5, 3.2, 7.0)
	d["glow_height"] = _phase(e, 0.3, 0.45, 0.6, 0.18)
	d["opp_strength"] = _phase(e, 0.0, 0.8, 0.55, 0.0)
	d["sun_vis"] = smoothstep(-1.5, 1.0, e)
	d["star_vis"] = 1.0 - smoothstep(-16.0, -8.0, e)
	d["light_energy"] = smoothstep(-1.0, 10.0, e) * 1.15
	return d

## Everything the sky needs for a sun elevation `e` (degrees) and a blend of two air types.
static func sample(air_a: int, air_b: int, mix_t: float, e: float) -> Dictionary:
	if _table.is_empty():
		_build()
	var n := _table.size()
	var a := clampi(air_a, 0, n - 1)
	var b := clampi(air_b, 0, n - 1)
	var pa := _blend(a, e)
	if a == b or mix_t <= 0.001:
		return pa
	var pb := _blend(b, e)
	var out := {}
	for key in pa:
		out[key] = lerp(pa[key], pb[key], clampf(mix_t, 0.0, 1.0))
	return out
