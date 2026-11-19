import sys
root = sys.argv[1]
p = root + '/scripts/world_ground.gd'
s = open(p).read()
start = s.index("## The chart's ground without the cliffs")
end = s.index("## (beach, rocky, green) weights")
s = s[:start] + '''## Signed distance (m) from chart x, z to the waterline: + on land, - at sea (shore_d in world_ground.gdshaderinc).
func shore_d(x: float, z: float) -> float:
	var u := x / _mpp - 0.5
	var v := z / _mpp - 0.5
	var x0 := int(floor(u))
	var y0 := int(floor(v))
	var fx := u - float(x0)
	var fy := v - float(y0)
	var a := _texel(_land, x0, y0) / 255.0
	var b := _texel(_land, x0 + 1, y0) / 255.0
	var c := _texel(_land, x0, y0 + 1) / 255.0
	var e := _texel(_land, x0 + 1, y0 + 1) / 255.0
	var l := lerpf(lerpf(a, b, fx), lerpf(c, e, fx), fy)
	var g := Vector2(lerpf(b - a, e - c, fy), lerpf(c - a, e - b, fx)) / _mpp
	var gl := maxf(g.length(), 0.12 / _mpp)
	var d := (l - WATERLINE_L) / gl
	var cp := Vector2(x, z)
	d += (fbm(cp / 90.0 + Vector2(7.7, 3.1)) - 0.47) * 28.0 + (fbm(cp / 23.0 + Vector2(1.9, 5.3)) - 0.47) * 6.0
	return d


## (gradient under the water, gradient of the beach, beach width m) by coast kind (shore_slopes in the shader).
func shore_slopes(k: Vector3) -> Vector3:
	return k.x * Vector3(1.0 / 32.0, 1.0 / 16.0, 55.0) + k.y * Vector3(1.0 / 6.0, 1.0 / 2.5, 6.0) + k.z * Vector3(1.0 / 16.0, 1.0 / 9.0, 18.0)


## Water depth (m) at chart x, z over the ground the terrain draws (0 on land).
func depth_m(x: float, z: float) -> float:
	return maxf(-ground_y(x, z), 0.0)


## The ground without the cliffs (chart_ground_y in world_ground.gdshaderinc): the near-shore profile within
## SHORE_BAND_M of the waterline, the chart's own ground beyond.
func ground_y(x: float, z: float) -> float:
	var land := _bilinear(_land, x, z) / 255.0
	var t := smoothstep(0.42, 0.58, land)
	var shore := _bilinear(_shore, x, z)
	var sea_y := -(_shelf_depth(shore * _mpp / 1000.0) - 2.0)
	var lh := maxf(0.0, (_h16_at(x, z) - COAST_LEVEL) / (1.0 - COAST_LEVEL))
	var rough := 0.0
	if lh > 0.0:
		rough = (fbm(Vector2(x, z) / 900.0) - 0.45) * DETAIL_M * smoothstep(0.0, 0.08, lh)
	var land_y := lh * RELIEF_M + rough * 0.5 + 1.0
	var raw := lerpf(sea_y, land_y, t)
	var d := shore_d(x, z)
	if absf(d) >= SHORE_BAND_M:
		return raw
	var sl := shore_slopes(coast_kind(Vector2(x, z)))
	if d < 0.0:
		var xx := -d
		var cap := 12.0 * (1.0 - smoothstep(550.0, SHORE_BAND_M, xx))
		return -maxf(minf(xx * sl.x, cap), maxf(-raw, 0.0) * smoothstep(300.0, SHORE_BAND_M, xx))
	var beach := d * sl.y
	var k := smoothstep(sl.z, sl.z + 220.0, d)
	return maxf(lerpf(beach, maxf(land_y, beach), k), 0.0)


''' + s[end:]
s = s.replace("const BEACH_DROP_M := 0.0\n", "const WATERLINE_L := 0.45\nconst SHORE_BAND_M := 900.0\n")
open(p, 'w').write(s)

# the sea's float height on the CPU follows the same shoaling
p = root + '/scripts/ocean.gd'
s = open(p).read()
o = """	if chart:
		s *= chart.wave_scale(x + _ox, z + _oz)
	return s"""
assert s.count(o) == 1
s = s.replace(o, """	if chart:
		var cx := x + _ox
		var cz := z + _oz
		if ground and chart.shore_distance_m(cx, cz) < 1500.0 and not chart.is_land(cx, cz) or ground and chart.is_land(cx, cz):
			# near a coast: the beach profile, as chart_scale() in ocean.gdshader
			s *= pow(clampf(ground.depth_m(cx, cz) / 12.0, 0.0, 1.0), 0.6)
		else:
			s *= chart.wave_scale(cx, cz)
	return s""")
open(p, 'w').write(s)
