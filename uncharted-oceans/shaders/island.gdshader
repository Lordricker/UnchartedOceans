// Island terrain: colours by height and slope, no textures. Sand on the low flat ground (darker where
// the waves wet it), grass above, bare rock on steep slopes and the highest ground, and a sandy sea
// floor that the ocean shows through where the water is shallow.
shader_type spatial;
render_mode cull_back;

uniform vec3 seabed_color : source_color = vec3(0.40, 0.35, 0.25);
uniform vec3 wet_sand_color : source_color = vec3(0.27, 0.23, 0.16);
uniform vec3 sand_color : source_color = vec3(0.56, 0.49, 0.34);
uniform vec3 dry_grass_color : source_color = vec3(0.33, 0.37, 0.17);
uniform vec3 grass_color : source_color = vec3(0.15, 0.29, 0.10);
uniform vec3 rock_color : source_color = vec3(0.30, 0.28, 0.25);
uniform vec3 high_rock_color : source_color = vec3(0.46, 0.44, 0.40);

varying vec3 wpos;
varying vec3 wnrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x),
			   mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	float h = wpos.y;
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	float n1 = vnoise(wpos.xz * 0.35);
	float n2 = vnoise(wpos.xz * 1.7 + 11.0);
	float n3 = vnoise(wpos.xz * 0.06);

	// base: grass, patchy and drier in places
	vec3 c = mix(grass_color, dry_grass_color, smoothstep(0.35, 0.75, n3 * 0.7 + n1 * 0.5));
	// sand on the low ground, with a ragged upper edge
	float sand = 1.0 - smoothstep(1.3, 2.5, h + (n1 - 0.5) * 1.4);
	c = mix(c, sand_color, sand);
	// bare rock on steep slopes and the highest ground
	float rock = smoothstep(0.16, 0.34, slope + (n2 - 0.5) * 0.08) + smoothstep(13.0, 19.0, h + (n1 - 0.5) * 3.0);
	c = mix(c, mix(rock_color, high_rock_color, smoothstep(6.0, 16.0, h)), clamp(rock, 0.0, 1.0));
	// wet sand just above the water line, then the sea floor below it
	float wet = smoothstep(1.1, 0.1, h) * (1.0 - smoothstep(0.0, 0.3, slope)) * step(-0.4, h);
	c = mix(c, wet_sand_color, wet * 0.8);
	float under = smoothstep(0.1, -0.7, h);
	c = mix(c, seabed_color * (0.9 + 0.2 * n2), under);

	ALBEDO = c * (0.93 + 0.14 * n2);
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
