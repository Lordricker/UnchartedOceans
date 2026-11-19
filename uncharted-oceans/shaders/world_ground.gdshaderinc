// The macro ground of the world chart: sea floor below 0, land above, 0 at the waterline.
// Shared by world_terrain.gdshader (which draws it) and ocean.gdshader (which puts its surf where it meets the sea), so
// the white water sits exactly on the terrain's waterline.
// Include it after world_chart.gdshaderinc (for chart_shelf_depth) and after these uniforms: chart_land, chart_shore,
// chart_height16, chart_origin, chart_size, chart_px, chart_mpp, relief_m, coast_level, detail_m.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + 17.3;
		a *= 0.5;
	}
	return s;   // about 0..0.94
}

float h16_texel(ivec2 i) {
	ivec2 n = ivec2(chart_px);
	ivec2 c = ((i % n) + n) % n;      // the world wraps on all four edges
	vec2 t = texelFetch(chart_height16, c, 0).rg;
	return (t.r * 255.0 * 256.0 + t.g * 255.0) / 65535.0;
}

float h16(vec2 uv) {
	vec2 f = uv * chart_px - 0.5;
	ivec2 i = ivec2(floor(f));
	vec2 w = f - vec2(i);
	return mix(mix(h16_texel(i), h16_texel(i + ivec2(1, 0)), w.x),
			mix(h16_texel(i + ivec2(0, 1)), h16_texel(i + ivec2(1, 1)), w.x), w.y);
}

// What kind of coast a stretch of shore is, as weights that add up to 1: x = sandy beach, y = rocky shore with a low
// cliff behind it, z = low green shore (grass and trees down to the water). Slow noise in chart metres (cp) picks it,
// in stretches of a few km; the north runs rockier and the south sandier. It changes looks and the land above the
// water only, never where the waterline is, so the ship's grounding (WorldChart, on the CPU) still matches the view.
vec3 coast_kind(vec2 cp) {
	float lat = clamp(cp.y / chart_size.y, 0.0, 1.0);   // 0 = north edge of the chart, 1 = south edge
	float a = fbm(cp / 2600.0 + vec2(41.3, 7.9)) + (lat - 0.5) * 0.12;
	float b = fbm(cp / 1700.0 + vec2(-13.7, 88.1));
	float rock = 1.0 - smoothstep(0.38, 0.46, a);
	float beach = (1.0 - rock) * smoothstep(0.42, 0.5, b);
	return vec3(beach, rock, 1.0 - rock - beach);
}

// ---- The near-shore profile ----
// The chart only knows the coast to one pixel (~780 m), so on its own the land climbs out of the sea like a wall. Near
// the waterline the ground is instead shaped from the distance to it in metres (shore_d): a beach that shelves gently
// under the water and rises a little above it before the chart's own land takes over. The waterline is the chart's
// land mask at WATERLINE_L (a smooth contour), wiggled a little along the coast so it is not ruler-smooth.
// Must match WorldGround (world_ground.gd), the CPU copy the shore collider and the keel test use.
const float WATERLINE_L = 0.45;
const float SHORE_BAND_M = 900.0;     // the profile is used out to this distance either side of the waterline

float land_texel(ivec2 i) {
	ivec2 n = ivec2(chart_px);
	return texelFetch(chart_land, ((i % n) + n) % n, 0).r;      // the world wraps
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
// ---- The port pad (port_pad.gd): joins a loaded small port's land plate to the chart's land ----
// Under the plate the ground sits just below it, round it the ground rises to the plate's rim and eases back into the
// chart's land, and a dredged basin keeps the water deep in front of the quay. Must match PortPad / WorldGround.
uniform sampler2D port_pad_tex : filter_nearest, repeat_disable;
uniform vec4 port_pad_frame = vec4(0.0, 0.0, 1.0, 0.0);   // Godot world x, z of the port's origin, cos(yaw), sin(yaw)
uniform vec4 port_pad_grid = vec4(0.0);                   // u0, v0 (port-local m of texel 0's centre), cell m, 1 = on
const float PORT_PAD_BASIN_M = 7.0;   // PortPad.BASIN_DEPTH_M

vec3 port_pad_tx(ivec2 i) {
	return texelFetch(port_pad_tex, i, 0).rgb;
}

// (height, land weight, basin weight) at a Godot world xz; zeros away from the pad.
vec3 port_pad_sample(vec2 wxz) {
	if (port_pad_grid.w < 0.5) {
		return vec3(0.0);
	}
	vec2 d = wxz - port_pad_frame.xy;
	vec2 l = vec2(d.x * port_pad_frame.z - d.y * port_pad_frame.w, d.x * port_pad_frame.w + d.y * port_pad_frame.z);
	vec2 g = (l - port_pad_grid.xy) / port_pad_grid.z;
	ivec2 n = textureSize(port_pad_tex, 0);
	if (g.x < 0.0 || g.y < 0.0 || g.x > float(n.x - 1) || g.y > float(n.y - 1)) {
		return vec3(0.0);
	}
	ivec2 i = min(ivec2(floor(g)), n - 2);
	vec2 f = g - vec2(i);
	return mix(mix(port_pad_tx(i), port_pad_tx(i + ivec2(1, 0)), f.x),
			mix(port_pad_tx(i + ivec2(0, 1)), port_pad_tx(i + ivec2(1, 1)), f.x), f.y);
}

float port_pad_blend(float y, vec3 s) {
	y = mix(y, s.x, s.y);
	return mix(y, min(y, -PORT_PAD_BASIN_M), s.z);
}

// How much a port pad owns this spot (0..1): the surf stays out of it.
float port_pad_w(vec2 wxz) {
	vec3 s = port_pad_sample(wxz);
	return max(s.y, s.z);
}

float chart_ground_y0(vec2 wxz) {
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
	// the beach rises only across its own width (a few metres), then the land comes in over the next 600 m. (It used
	// to keep climbing at the beach's slope all the way to SHORE_BAND_M, 360 m up on a rocky shore, and then dropped to
	// the chart's land where the band ended: the "vertical slabs" on the hills.)
	float beach = min(d, sl.z) * sl.y;
	float k = smoothstep(sl.z, sl.z + 600.0, d);
	return max(mix(beach, max(land_y, beach), k), 0.0);
}

// The ground with the port pad (if one is loaded).
float chart_ground_y(vec2 wxz) {
	return port_pad_blend(chart_ground_y0(wxz), port_pad_sample(wxz));
}


// ---- Surf and swash (the sea draws the breaking waves, the terrain the water running up the sand) ----
// Each wave front f runs in from about twice the breaker width and reaches the waterline at SURF_IN of its cycle; for
// the rest of the cycle its water runs up the beach and back. Two fronts per surf period; the line wobbles along the
// coast so it is never ruler-straight. All distances are metres from the waterline (shore_d).
const float SURF_IN = 0.62;

float surf_u(vec2 cp, float t, float p_period, int f) {
	float wob = fbm(cp / 140.0 + vec2(5.3, 1.7)) + 0.35 * fbm(cp / 37.0 + vec2(2.1, 9.4));
	return fract(t / p_period + float(f) * 0.5 + wob * 0.9);
}

// Width of the breaker zone (m): waves break in water about as deep as they are high.
float surf_break_x(float p_amp, float p_slope) {
	float hb = clamp(0.35 + p_amp * 0.55, 0.35, 1.6);
	return clamp(hb / max(p_slope, 0.01), 4.0, 45.0);
}

// How far up the beach (m past the waterline) the swash runs.
float swash_x(float p_amp, float p_rock, float p_slope) {
	float r = clamp(0.2 + p_amp * 0.35, 0.2, 0.8) * mix(1.0, 0.5, p_rock);
	return r / max(p_slope, 0.02);
}

// The swash's leading edge through its run (s 0..1), as a share of the full run-up: a quick rush up, a slower draining back.
float swash_edge(float s) {
	float q = s < 0.35 ? 0.5 * s / 0.35 : 0.5 + 0.5 * (s - 0.35) / 0.65;
	return sin(3.14159265 * clamp(q, 0.0, 1.0));
}

// Lace: foam of density dens (0..1) drawn from a pattern value pat (0..1, a mix of blobs and veins): solid at 1,
// a net of veins and holes as it thins.
float surf_lace(float p_dens, float p_pat) {
	float thr = 1.0 - p_dens;
	return smoothstep(thr - 0.07, thr + 0.07, p_pat) * smoothstep(0.02, 0.12, p_dens);
}
