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
	ivec2 c = clamp(i, ivec2(0), ivec2(chart_px) - 1);
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

// Ground height at a Godot world xz as the chart gives it: sea floor from the shelf, land from the heightmap, 0 at the
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
