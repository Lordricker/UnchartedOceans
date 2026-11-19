import sys
root = sys.argv[1]
def edit(p, pairs):
    p = root + '/' + p
    s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (p, o[:90])
        s = s.replace(o, n)
    open(p, 'w').write(s)
edit('shaders/ocean.gdshader', [
# bigger lace
("""	float sp1 = texture(foam_noise, world_xz * 0.16 + vec2(0.37, 0.11)).r;
	float sp2 = texture(foam_noise, world_xz * 0.55 + vec2(0.71, 0.23)).r;""",
"""	float sp1 = texture(foam_noise, world_xz * 0.065 + vec2(0.37, 0.11)).r;
	float sp2 = texture(foam_noise, world_xz * 0.21 + vec2(0.71, 0.23)).r;"""),
# turquoise only in the first few metres of depth
("""		lagoon = smoothstep(0.15, 1.6, shore_depth) * (1.0 - smoothstep(5.0, 16.0, shore_depth));""",
"""		lagoon = smoothstep(0.15, 1.2, shore_depth) * (1.0 - smoothstep(2.5, 8.0, shore_depth));"""),
# the waves you can see rolling in: each front stands up as a crest as it reaches the breaker line and drops as it breaks
("""	wave_h = w.x * sc;
	VERTEX.y += w.x * sc - dist * dist * curve_k + wake_height(wp.xz) + trail_height(wp.xz);""",
"""	wave_h = w.x * sc;
	float roll = 0.0;
	if (chart_on > 0.5 && coast_surf > 0.0 && sc < 0.999) {
		vec2 cp = wp.xz + chart_origin;
		float x = -shore_d(cp);
		if (x > 0.0 && x < 120.0) {
			vec3 ck = coast_kind(cp);
			float xb = surf_break_x(sea_amplitude, shore_slopes(ck).x);
			for (int f = 0; f < 2; f++) {
				float u = surf_u(cp, ocean_time, surf_period, f);
				if (u < SURF_IN) {
					float xf = xb * 2.3 * pow(1.0 - u / SURF_IN, 1.25);
					// grows as it shoals, peaks at the breaker line, collapses into the white water after it
					float hgt_f = (0.18 + 0.32 * sea_amplitude) * smoothstep(xb * 2.4, xb * 1.1, xf) * smoothstep(xb * 0.25, xb * 0.85, xf);
					float dx = x - xf;
					float shape = dx < 0.0 ? exp(-dx * dx / 2.0) : exp(-dx * dx / 18.0);   // steep face toward the beach
					roll = max(roll, hgt_f * shape * (f == 0 ? 1.0 : 0.75));
				}
			}
			roll *= coast_surf * smoothstep(0.0, 0.5, x);
		}
	}
	VERTEX.y += w.x * sc + roll - dist * dist * curve_k + wake_height(wp.xz) + trail_height(wp.xz);"""),
])
edit('shaders/world_terrain.gdshader', [
("uniform vec3 sand_south_color : source_color = vec3(0.8, 0.76, 0.64);", "uniform vec3 sand_south_color : source_color = vec3(0.66, 0.6, 0.48);"),
("uniform float caustic_strength : hint_range(0.0, 3.0) = 1.15;", "uniform float caustic_strength : hint_range(0.0, 3.0) = 0.45;"),
("""			float sp1 = textureLod(foam_noise, world_xz * 0.16 + vec2(0.37, 0.11), 0.0).r;
			float sp2 = textureLod(foam_noise, world_xz * 0.55 + vec2(0.71, 0.23), 0.0).r;""",
"""			float sp1 = textureLod(foam_noise, world_xz * 0.065 + vec2(0.37, 0.11), 0.0).r;
			float sp2 = textureLod(foam_noise, world_xz * 0.21 + vec2(0.71, 0.23), 0.0).r;"""),
])
