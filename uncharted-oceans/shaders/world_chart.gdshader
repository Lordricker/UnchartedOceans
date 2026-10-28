shader_type canvas_item;
// Chart look for the world map: sea depth bands from the shore-distance texture,
// land coloured by height, soft relief shading from the heightmap (TEXTURE).

uniform sampler2D land_tex : filter_linear, repeat_disable;
uniform sampler2D shore_tex : filter_linear, repeat_disable;
uniform float shelf_px = 31.0;          // shelf width in pixels (12 km at a 600 km chart)
uniform float relief_strength = 5.0;
uniform vec3 deep_col : source_color = vec3(0.02, 0.07, 0.16);
uniform vec3 mid_col : source_color = vec3(0.04, 0.22, 0.36);
uniform vec3 shelf_col : source_color = vec3(0.14, 0.52, 0.58);
uniform vec3 lowland_col : source_color = vec3(0.30, 0.42, 0.20);
uniform vec3 hill_col : source_color = vec3(0.45, 0.40, 0.28);
uniform vec3 rock_col : source_color = vec3(0.56, 0.54, 0.51);
uniform vec3 snow_col : source_color = vec3(0.92, 0.93, 0.95);

void fragment() {
	vec2 uv = UV;
	float h = texture(TEXTURE, uv).r;
	float land = texture(land_tex, uv).r;
	float shore = texture(shore_tex, uv).r * 255.0;

	float t = 1.0 - clamp(shore / shelf_px, 0.0, 1.0);
	float t2 = 1.0 - clamp(shore / (shelf_px * 3.5), 0.0, 1.0);
	vec3 sea = mix(deep_col, mid_col, t2 * t2);
	sea = mix(sea, shelf_col, t * t * (3.0 - 2.0 * t));

	float e = clamp((h - 0.2) / 0.8, 0.0, 1.0);
	vec3 lc = mix(lowland_col, hill_col, smoothstep(0.25, 0.55, e));
	lc = mix(lc, rock_col, smoothstep(0.55, 0.8, e));
	lc = mix(lc, snow_col, smoothstep(0.88, 1.0, e));

	vec2 ps = TEXTURE_PIXEL_SIZE;
	float dx = texture(TEXTURE, uv + vec2(ps.x, 0.0)).r - texture(TEXTURE, uv - vec2(ps.x, 0.0)).r;
	float dy = texture(TEXTURE, uv + vec2(0.0, ps.y)).r - texture(TEXTURE, uv - vec2(0.0, ps.y)).r;
	vec3 n = normalize(vec3(-dx * relief_strength, -dy * relief_strength, 1.0));
	float s = dot(n, normalize(vec3(-0.5, -0.5, 0.7)));
	lc *= 0.55 + 0.65 * s;

	vec3 col = mix(sea, lc, smoothstep(0.45, 0.55, land));
	float rim = 1.0 - smoothstep(0.0, 0.07, abs(land - 0.5));
	col = mix(col, vec3(0.05, 0.08, 0.07), rim * 0.55);
	COLOR = vec4(col, 1.0);
}
