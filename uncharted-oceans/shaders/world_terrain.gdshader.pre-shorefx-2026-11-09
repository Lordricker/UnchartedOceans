// Macro terrain for the world chart: land from the smoothed heightmap and the sea floor from the
// chart's shelf, on a camera-following radial grid (world_terrain.gd). No collision; grounding is
// done against the chart (see WorldStreamer). The curvature matches the ocean's, so a coast sinks
// below the horizon the same way the sea does.
//
// Coasts: each stretch of shore is a sandy beach, a rocky shore with a low cliff behind it, or a low green shore
// (coast_kind() in world_ground.gdshaderinc, shared with the ocean so its surf knows the kind too). Sand and rock take
// a regional colour by latitude: dark grey shingle and stone in the north, warm sand in the middle, pale coral sand
// and rock in the south. The cliffs only raise land that is already above the water, so the waterline (and the ship's
// grounding on the CPU) is unchanged.
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

uniform vec3 sand_color : source_color = vec3(0.55, 0.5, 0.36);          // middle latitudes
uniform vec3 sand_north_color : source_color = vec3(0.4, 0.38, 0.33);    // dark grey-brown sand and shingle
uniform vec3 sand_south_color : source_color = vec3(0.8, 0.76, 0.64);    // pale coral sand
uniform vec3 grass_color : source_color = vec3(0.17, 0.26, 0.1);
uniform vec3 forest_color : source_color = vec3(0.07, 0.14, 0.07);
uniform vec3 rock_color : source_color = vec3(0.3, 0.28, 0.26);          // middle latitudes
uniform vec3 rock_north_color : source_color = vec3(0.22, 0.22, 0.23);   // dark granite
uniform vec3 rock_south_color : source_color = vec3(0.52, 0.48, 0.41);   // pale limestone and coral rock
uniform vec3 snow_color : source_color = vec3(0.8, 0.82, 0.85);
uniform vec3 seabed_color : source_color = vec3(0.16, 0.2, 0.16);
uniform float cliff_m = 26.0;             // average height of the low cliffs along rocky stretches

#include "res://shaders/world_ground.gdshaderinc"

varying vec2 world_xz;
varying float terrain_h;

// Height of the cliff along a rocky stretch at chart xz: varies along the coast, about 10 to 42 m.
float cliff_height(vec2 cp) {
	return cliff_m * (0.4 + 1.2 * fbm(cp / 650.0 + vec2(3.1, 9.7)));
}

// Ground height at a Godot world xz: the chart's ground, plus the cliffs of rocky stretches on the land side.
float terrain_y(vec2 wxz) {
	float y = chart_ground_y(wxz);
	if (y <= 0.0) {
		return y;
	}
	vec2 cp = wxz + chart_origin;
	float rock = coast_kind(cp).y;
	if (rock > 0.0) {
		// 0 at the waterline, all of the cliff once the shore is fully land (a few tens of metres in)
		y += rock * cliff_height(cp) * smoothstep(0.15, 1.0, y);
	}
	return y;
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
	vec2 cp = world_xz + chart_origin;
	vec3 k = coast_kind(cp);

	// regional sand and rock by latitude
	float lat = clamp(cp.y / chart_size.y, 0.0, 1.0);
	vec3 sand = mix(sand_north_color, sand_color, smoothstep(0.15, 0.4, lat));
	sand = mix(sand, sand_south_color, smoothstep(0.6, 0.85, lat));
	vec3 rock = mix(rock_north_color, rock_color, smoothstep(0.15, 0.4, lat));
	rock = mix(rock, rock_south_color, smoothstep(0.6, 0.85, lat));
	// fine mottling of sand and rock up close, fading to its average before it can shimmer
	float mf = 1.0 - smoothstep(1.5, 6.0, length(fwidth(world_xz)));
	float mott = mix(0.47, fbm(cp / 14.0), mf);
	rock *= 0.82 + 0.36 * mott;

	vec3 c;
	if (h > 0.0) {
		float n1 = fbm(world_xz / 120.0 + chart_origin / 120.0);
		vec3 low = mix(grass_color, forest_color, smoothstep(0.35, 0.65, n1));
		// how high the sand reaches: a wide strand on beaches, a thin line on green and rocky shores
		float s_lo = dot(k, vec3(5.0, 0.4, 0.3));
		float s_hi = dot(k, vec3(16.0, 2.0, 1.4));
		c = mix(sand * (0.92 + 0.16 * mott), low, smoothstep(s_lo, s_hi, h));
		// rocky stretches: bare rock from the water up to the cliff top
		float ctop = cliff_height(cp);
		c = mix(c, rock, k.y * (1.0 - smoothstep(ctop * 0.75, ctop * 1.1, h)));
		c = mix(c, rock, smoothstep(350.0, 650.0, h + (n1 - 0.45) * 200.0));
		c = mix(c, rock, smoothstep(0.12, 0.3, slope));
		c = mix(c, snow_color, smoothstep(850.0, 1000.0, h) * (1.0 - smoothstep(0.2, 0.45, slope)));
		// wet band just above the water
		c *= mix(0.66, 1.0, smoothstep(0.0, 0.8, h));
	} else {
		// the sea floor: in the shallows it takes the colour of its shore (pale sand off a beach, dark stone off rock)
		vec3 bed = mix(sand * 0.75, rock * 0.6, k.y);
		c = mix(bed, seabed_color, smoothstep(1.5, 14.0, -h));
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
