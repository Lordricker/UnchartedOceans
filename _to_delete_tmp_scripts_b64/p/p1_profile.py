# Near-shore beach profile: shared by the terrain, the sea and (in world_ground.gd) the CPU.
import sys
root = sys.argv[1]
def edit(p, pairs):
    p = root + '/' + p
    s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (p, o[:80])
        s = s.replace(o, n)
    open(p, 'w').write(s)

edit('shaders/world_ground.gdshaderinc', [(
"""// Ground height at a Godot world xz as the chart gives it: sea floor from the shelf, land from the heightmap, 0 at the
// shoreline. (The terrain adds its cliffs on top of this, but only above the water, so the waterline stays put.)
float chart_ground_y(vec2 wxz) {
	vec2 cp = wxz + chart_origin;
	vec2 uv = cp / chart_size;
	float land = textureLod(chart_land, uv, 0.0).r;
	float shore = textureLod(chart_shore, uv, 0.0).r;
	float sea_y = -(chart_shelf_depth(shore * 255.0 * chart_mpp / 1000.0) - 2.0);
	float lh = max(0.0, (h16(uv) - coast_level) / (1.0 - coast_level));
	float rough = (fbm(cp / 900.0) - 0.45) * detail_m * smoothstep(0.0, 0.08, lh);
	float land_y = lh * relief_m + rough * 0.5 + 1.0;
	return mix(sea_y, land_y, smoothstep(0.42, 0.58, land));
}
""",
"""// ---- The near-shore profile ----
// The chart only knows the coast to one pixel (~780 m), so on its own the land climbs out of the sea like a wall. Near
// the waterline the ground is instead shaped from the distance to it in metres (shore_d): a beach that shelves gently
// under the water and rises a little above it before the chart's own land takes over. The waterline is the chart's
// land mask at WATERLINE_L (a smooth contour), wiggled a little along the coast so it is not ruler-smooth.
// Must match WorldGround (world_ground.gd), the CPU copy the shore collider and the keel test use.
const float WATERLINE_L = 0.45;
const float SHORE_BAND_M = 900.0;     // the profile is used out to this distance either side of the waterline

float land_texel(ivec2 i) {
	return texelFetch(chart_land, clamp(i, ivec2(0), ivec2(chart_px) - 1), 0).r;
}

// Signed distance (m) from chart xz to the waterline: + on land, - at sea. From the land mask and its slope (exact
// bilinear, from the four texels, so it has none of the GPU filter's 8-bit steps). Big when far from any coast.
float shore_d(vec2 cp) {
	vec2 f = cp / chart_mpp - 0.5;
	ivec2 i = ivec2(floor(f));
	vec2 w = f - vec2(i);
	float a = land_texel(i);
	float b = land_texel(i + ivec2(1, 0));
	float c = land_texel(i + ivec2(0, 1));
	float e = land_texel(i + ivec2(1, 1));
	float l = mix(mix(a, b, w.x), mix(c, e, w.x), w.y);
	vec2 g = vec2(mix(b - a, e - c, w.y), mix(c - a, e - b, w.x)) / chart_mpp;   // per metre
	float gl = max(length(g), 0.12 / chart_mpp);
	float d = (l - WATERLINE_L) / gl;
	// coves and points of a few tens of metres along the coast
	d += (fbm(cp / 90.0 + vec2(7.7, 3.1)) - 0.47) * 28.0 + (fbm(cp / 23.0 + vec2(1.9, 5.3)) - 0.47) * 6.0;
	return d;
}

// The coast's slopes: (gradient under the water, gradient of the beach above it, width of the beach in m), by kind
// (coast_kind: x sand, y rock, z green).
vec3 shore_slopes(vec3 k) {
	return k.x * vec3(1.0 / 32.0, 1.0 / 16.0, 55.0) + k.y * vec3(1.0 / 6.0, 1.0 / 2.5, 6.0) + k.z * vec3(1.0 / 16.0, 1.0 / 9.0, 18.0);
}

// The chart's own ground (what the terrain was before the profile): sea floor from the shelf, land from the heightmap.
float chart_ground_raw(vec2 cp, out float land_y) {
	vec2 uv = cp / chart_size;
	float land = textureLod(chart_land, uv, 0.0).r;
	float shore = textureLod(chart_shore, uv, 0.0).r;
	float sea_y = -(chart_shelf_depth(shore * 255.0 * chart_mpp / 1000.0) - 2.0);
	float lh = max(0.0, (h16(uv) - coast_level) / (1.0 - coast_level));
	float rough = (fbm(cp / 900.0) - 0.45) * detail_m * smoothstep(0.0, 0.08, lh);
	land_y = lh * relief_m + rough * 0.5 + 1.0;
	return mix(sea_y, land_y, smoothstep(0.42, 0.58, land));
}

// Ground height at a Godot world xz: 0 at the waterline, sea floor below, land above. (The terrain adds its cliffs on
// top of this, but only above the water, so the waterline stays put.)
float chart_ground_y(vec2 wxz) {
	vec2 cp = wxz + chart_origin;
	float land_y;
	float raw = chart_ground_raw(cp, land_y);
	float d = shore_d(cp);
	if (abs(d) >= SHORE_BAND_M) {
		return raw;
	}
	vec3 sl = shore_slopes(coast_kind(cp));
	if (d < 0.0) {
		// under the water: shelving down at the coast's slope to about 12 m, then easing into the chart's shelf
		float x = -d;
		float cap = 12.0 * (1.0 - smoothstep(550.0, SHORE_BAND_M, x));
		return -max(min(x * sl.x, cap), max(-raw, 0.0) * smoothstep(300.0, SHORE_BAND_M, x));
	}
	// above the water: the beach, then the chart's land (its heights reach the coast from a pixel away, so they come in
	// over the next couple of hundred metres)
	float beach = d * sl.y;
	float k = smoothstep(sl.z, sl.z + 220.0, d);
	return max(mix(beach, max(land_y, beach), k), 0.0) + 0.0 * raw;
}
""")])

# the sea's shoaling: from the same ground, so the swell dies away over the beach's own slope
edit('shaders/ocean.gdshader', [(
"""float chart_scale(vec2 p) {
	vec2 uv = (p + chart_origin) / chart_size;
	float land = textureLod(chart_land, uv, 0.0).r;
	float shore = textureLod(chart_shore, uv, 0.0).r;
	float depth = land >= 0.5 ? 0.0 : chart_shelf_depth(shore * 255.0 * chart_mpp / 1000.0);
	return pow(clamp(depth / shoal_depth, 0.0, 1.0), shoal_pow);
}""",
"""float chart_scale(vec2 p) {
	vec2 uv = (p + chart_origin) / chart_size;
	float land = textureLod(chart_land, uv, 0.0).r;
	float shore = textureLod(chart_shore, uv, 0.0).r;
	float depth = land >= 0.5 ? 0.0 : chart_shelf_depth(shore * 255.0 * chart_mpp / 1000.0);
	if (shore * 255.0 * chart_mpp < 1500.0) {
		depth = max(-chart_ground_y(p), 0.0);      // near a coast: the beach profile (WorldGround.depth_m on the CPU)
	}
	return pow(clamp(depth / shoal_depth, 0.0, 1.0), shoal_pow);
}""")])
