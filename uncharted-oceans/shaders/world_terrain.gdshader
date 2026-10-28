// Macro terrain for the world chart: land from the smoothed heightmap and the sea floor from the
// chart's shelf, on a camera-following radial grid (world_terrain.gd). No collision; grounding is
// done against the chart (see WorldStreamer). The curvature matches the ocean's, so a coast sinks
// below the horizon the same way the sea does.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/world_chart.gdshaderinc"

uniform sampler2D chart_land : filter_linear, repeat_disable;
uniform sampler2D chart_shore : filter_linear, repeat_disable;
uniform sampler2D chart_height16 : filter_nearest, repeat_disable;  // R = high byte, G = low byte
uniform vec2 chart_origin = vec2(0.0);
uniform vec2 chart_size = vec2(600000.0, 400000.0);
uniform vec2 chart_px = vec2(1536.0, 1024.0);
uniform float chart_mpp = 390.625;
uniform float curve_k = 0.0;
uniform float relief_m = 1100.0;          // height of the highest heightmap value above the coast
uniform float coast_level = 0.2431;       // heightmap value (0..1) at the shoreline
uniform float detail_m = 55.0;            // fine relief added on land
uniform vec3 hole = vec3(0.0, 0.0, -1.0); // (x, z, radius) in Godot world coordinates: a full port scene replaces the terrain here

uniform vec3 sand_color : source_color = vec3(0.55, 0.5, 0.36);
uniform vec3 grass_color : source_color = vec3(0.17, 0.26, 0.1);
uniform vec3 forest_color : source_color = vec3(0.07, 0.14, 0.07);
uniform vec3 rock_color : source_color = vec3(0.3, 0.28, 0.26);
uniform vec3 snow_color : source_color = vec3(0.8, 0.82, 0.85);
uniform vec3 seabed_color : source_color = vec3(0.16, 0.2, 0.16);

varying vec2 world_xz;
varying float terrain_h;

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

// Ground height at a Godot world xz: sea floor below zero, land above, 0 at the shoreline.
float terrain_y(vec2 wxz) {
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

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_xz = wp.xz;
	float y = terrain_y(wp.xz);
	terrain_h = y;
	float d = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	VERTEX.y = y - d * d * curve_k;
}

void fragment() {
	if (hole.z > 0.0 && distance(world_xz, hole.xy) < hole.z) {
		discard;
	}
	float e = 40.0;
	float y0 = terrain_y(world_xz);
	float yx = terrain_y(world_xz + vec2(e, 0.0));
	float yz = terrain_y(world_xz + vec2(0.0, e));
	vec3 n_world = normalize(vec3(-(yx - y0) / e, 1.0, -(yz - y0) / e));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	float slope = 1.0 - n_world.y;
	float h = y0;
	vec3 c = seabed_color;
	if (h > 0.0) {
		float n1 = fbm(world_xz / 120.0 + chart_origin / 120.0);
		vec3 low = mix(grass_color, forest_color, smoothstep(0.35, 0.65, n1));
		c = mix(sand_color, low, smoothstep(2.0, 9.0, h));
		c = mix(c, rock_color, smoothstep(350.0, 650.0, h + (n1 - 0.45) * 200.0));
		c = mix(c, rock_color, smoothstep(0.12, 0.3, slope));
		c = mix(c, snow_color, smoothstep(850.0, 1000.0, h) * (1.0 - smoothstep(0.2, 0.45, slope)));
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
