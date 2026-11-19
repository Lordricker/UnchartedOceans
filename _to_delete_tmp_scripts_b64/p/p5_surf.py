# Surf and swash built on metres from the waterline (shore_d), shared by the sea and the terrain.
import sys
root = sys.argv[1]
def edit(p, pairs):
    p = root + '/' + p
    s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (p, o[:90])
        s = s.replace(o, n)
    open(p, 'w').write(s)

# ---------------------------------------------------------------- shared timing
p = root + '/shaders/world_ground.gdshaderinc'
s = open(p).read()
s += '''
// ---- Surf and swash (the sea draws the breaking waves, the terrain the water running up the sand) ----
// Each wave front f runs in from about twice the breaker width and reaches the waterline at SURF_IN of its cycle; for
// the rest of the cycle its water runs up the beach and back. Two fronts per surf period; the line wobbles along the
// coast so it is never ruler-straight. All distances are metres from the waterline (shore_d).
const float SURF_IN = 0.62;

float surf_u(vec2 cp, float t, float period, int f) {
	float wob = fbm(cp / 140.0 + vec2(5.3, 1.7)) + 0.35 * fbm(cp / 37.0 + vec2(2.1, 9.4));
	return fract(t / period + float(f) * 0.5 + wob * 0.9);
}

// Width of the breaker zone (m): waves break in water about as deep as they are high.
float surf_break_x(float swell_a, float slope_under) {
	float hb = clamp(0.35 + swell_a * 0.55, 0.35, 1.6);
	return clamp(hb / max(slope_under, 0.01), 4.0, 45.0);
}

// How far up the beach (m past the waterline) the swash runs.
float swash_x(float swell_a, float rock, float slope_above) {
	float r = clamp(0.2 + swell_a * 0.35, 0.2, 0.8) * mix(1.0, 0.5, rock);
	return r / max(slope_above, 0.02);
}

// The swash's leading edge through its run (s 0..1), as a share of the full run-up: a quick rush up, a slower draining back.
float swash_edge(float s) {
	float q = s < 0.35 ? 0.5 * s / 0.35 : 0.5 + 0.5 * (s - 0.35) / 0.65;
	return sin(3.14159265 * clamp(q, 0.0, 1.0));
}

// Lace: foam of density dens (0..1) drawn from a pattern value pat (0..1, a mix of blobs and veins): solid at 1,
// a net of veins and holes as it thins.
float surf_lace(float dens, float pat) {
	float thr = 1.0 - dens;
	return smoothstep(thr - 0.07, thr + 0.07, pat) * smoothstep(0.02, 0.12, dens);
}
'''
open(p, 'w').write(s)

# ---------------------------------------------------------------- the sea
p = root + '/shaders/ocean.gdshader'
s = open(p).read()
a = s.index("	// Surf along the world's coasts (world mode)")
b = s.index("	// High setting: give all of the foam above (crests, the ship's wake and track, the surf) a bubble structure.")
s = s[:a] + '''	// Surf along the world's coasts (world mode), in metres from the waterline (shore_d, the same distance the terrain's
	// beach is shaped from): wave fronts run in, steepen and break over the last tens of metres (their white water a churned
	// line with lace trailing behind it), and the leftover foam thins out as the next one comes. The water then runs up the
	// sand, which the terrain draws (world_terrain.gdshader), in step. Kept apart from the other foam so the High setting's
	// bubble cells do not break it into floes. Skipped (one texture read) far from any coast.
	float shore_depth = 99.0;          // sea depth under this pixel near a world coast (m), for the shallows' colour
	vec3 shore_k = vec3(0.0);
	float surf = 0.0;
	float surf_thick = 0.0;
	// the lace pattern: soft blobs about a metre across plus a net of thin veins (read here, outside the branches)
	float sp1 = texture(foam_noise, world_xz * 0.16 + vec2(0.37, 0.11)).r;
	float sp2 = texture(foam_noise, world_xz * 0.55 + vec2(0.71, 0.23)).r;
	float surf_pat = clamp(0.55 * sp1 + 0.45 * (1.0 - abs(2.0 * sp2 - 1.0)) + (nz - 0.5) * 0.25, 0.0, 1.0);
	if (chart_on > 0.5 && coast_surf > 0.0) {
		vec2 cuv = (world_xz + chart_origin) / chart_size;
		float shore_m = textureLod(chart_shore, cuv, 0.0).r * 255.0 * chart_mpp;
		if (shore_m < 1500.0) {
			vec2 cp = world_xz + chart_origin;
			float gy = chart_ground_y(world_xz);
			if (gy < 0.0) {
				vec3 ck = coast_kind(cp);
				shore_depth = -gy;
				shore_k = ck;
				float x = max(-shore_d(cp), 0.0);
				vec3 sl = shore_slopes(ck);
				float xb = surf_break_x(sea_amplitude, sl.x);
				if (x < xb * 2.6) {
					for (int f = 0; f < 2; f++) {
						float u = surf_u(cp, ocean_time, surf_period, f);
						float amp = f == 0 ? 1.0 : 0.75;
						if (u < SURF_IN) {
							float xf = xb * 2.3 * pow(1.0 - u / SURF_IN, 1.25);       // where the front is now
							float brk = smoothstep(xb * 1.2, xb * 0.7, xf);           // 0 = still a swell, 1 = broken
							float w = mix(0.5, 1.4 + 0.06 * xf, brk);
							float ln = exp(-pow((x - xf) / w, 2.0));
							float trail = x > xf ? exp(-(x - xf) / (2.5 + 5.0 * brk)) * brk : 0.0;
							float dens = max(ln * mix(0.3, 1.0, brk), trail * 0.8) * amp;
							surf = max(surf, surf_lace(dens, surf_pat));
							surf_thick = max(surf_thick, ln * brk * amp);
						} else {
							// the foam the broken wave left in the inner surf zone, thinning out
							float sres = (u - SURF_IN) / (1.0 - SURF_IN);
							float rem = (1.0 - sres) * 0.55 * (1.0 - smoothstep(xb * 0.4, xb * 1.1, x)) * amp;
							surf = max(surf, surf_lace(rem, surf_pat));
						}
					}
					// right at the edge of the water: a thin wash
					surf = max(surf, surf_lace(0.6 * (1.0 - smoothstep(0.0, 1.2, x)), surf_pat));
					surf *= coast_surf;
					surf_thick *= coast_surf;
				}
			}
		}
	}

''' + s[b:]
open(p, 'w').write(s)

edit('shaders/ocean.gdshader', [
# surf is added after the bubble cells
("""	if (hq_w > 0.0) {
		vec3 nf = normalize""", """	foam = max(foam, surf);
	if (hq_w > 0.0) {
		vec3 nf = normalize"""),
# the shallows' colour, both settings, gentler
("""	if (high_water > 0.5 && shore_depth < 10.0) {
		float lat_g = clamp((world_xz.y + chart_origin.y) / chart_size.y, 0.0, 1.0);
		float day = clamp(dot(horizon_color, vec3(0.333)) * 2.0, 0.0, 1.0);
		lagoon = smoothstep(0.1, 0.8, shore_depth) * (1.0 - smoothstep(3.5, 11.0, shore_depth));
		lagoon *= mix(0.2, 1.0, shore_k.x) * mix(0.7, 1.0, smoothstep(0.35, 0.85, lat_g)) * day * (1.0 - water_dark);
		body = mix(body, shore_turq, lagoon * 0.8);
	}
	thick = max(thick, clamp(foam - crest_foam, 0.0, 1.0) * 1.2);   // surf along the shore is thick white water""",
"""	if (shore_depth < 16.0) {
		// over sand the shallows go a clear turquoise (strongest in the south, gone at night and under storm cloud); right at
		// the edge the water is so thin the sand shows through instead, and it deepens to the sea's blue by about 15 m
		float lat_g = clamp((world_xz.y + chart_origin.y) / chart_size.y, 0.0, 1.0);
		float day = clamp(dot(horizon_color, vec3(0.333)) * 2.0, 0.0, 1.0);
		lagoon = smoothstep(0.15, 1.6, shore_depth) * (1.0 - smoothstep(5.0, 16.0, shore_depth));
		lagoon *= mix(0.25, 1.0, shore_k.x) * mix(0.6, 1.0, smoothstep(0.35, 0.85, lat_g)) * day * (1.0 - water_dark);
		body = mix(body, shore_turq, lagoon * 0.62);
	}
	thick = max(thick, clamp(foam - crest_foam, 0.0, 1.0) * 1.2);   // surf along the shore is thick white water
	thick = max(thick, surf_thick);"""),
("uniform vec3 shore_turq : source_color = vec3(0.04, 0.62, 0.6);", "uniform vec3 shore_turq : source_color = vec3(0.07, 0.5, 0.5);"),
])

# ---------------------------------------------------------------- the terrain: the swash on the sand
edit('shaders/world_terrain.gdshader', [
("""uniform float cliff_m = 26.0;""", """uniform float cliff_m = 26.0;
// The swash (both settings; pushed by world_terrain.gd from the sea): the water each wave sends up the sand
uniform float swell_a = 0.7;              // the sea's sea_amplitude
uniform float surf_period = 9.0;
uniform sampler2D foam_noise : hint_default_white, filter_linear_mipmap, repeat_enable;"""),
])
p = root + '/shaders/world_terrain.gdshader'
s = open(p).read()
a = s.index("		// wet band just above the water")
b = s.index("	} else {\n		// the sea floor")
s = s[:a] + '''		// The swash: each wave's water runs up the sand and drains back (the sea's surf, in step: surf_u). A thin sheet of
		// water over darker wet sand, a lacy white lip at its leading edge, and the sand stays wet below the highest it
		// reaches. Distances in metres from the waterline.
		float dsh = shore_d(cp);
		vec3 sl = shore_slopes(k);
		float xs = swash_x(swell_a, k.y, sl.y);
		if (dsh < xs * 1.3 + 1.0) {
			float sp1 = textureLod(foam_noise, world_xz * 0.16 + vec2(0.37, 0.11), 0.0).r;
			float sp2 = textureLod(foam_noise, world_xz * 0.55 + vec2(0.71, 0.23), 0.0).r;
			float pat = clamp(0.55 * sp1 + 0.45 * (1.0 - abs(2.0 * sp2 - 1.0)), 0.0, 1.0);
			float sheet = 0.0;
			float lip = 0.0;
			for (int f = 0; f < 2; f++) {
				float u = surf_u(cp, ocean_time, surf_period, f);
				if (u >= SURF_IN) {
					float s = (u - SURF_IN) / (1.0 - SURF_IN);
					float amp = f == 0 ? 1.0 : 0.75;
					float edge = xs * amp * swash_edge(s);
					float up = s < 0.35 ? 1.0 : 0.0;                         // still rushing up: a fuller lip
					sheet = max(sheet, 1.0 - smoothstep(edge - 0.6, edge + 0.05, dsh));
					float lw = mix(0.45, 1.1, up) * amp;
					float band = smoothstep(edge - lw, edge - lw * 0.3, dsh) * (1.0 - smoothstep(edge - 0.05, edge + 0.08, dsh));
					lip = max(lip, surf_lace(band * mix(0.55, 0.95, up) * smoothstep(0.02, 0.12, swash_edge(s)), pat));
				}
			}
			float top = xs * (0.85 + 0.25 * fbm(cp / 31.0 + vec2(1.3, 7.1)));
			wet_k = 1.0 - smoothstep(top * 0.85, top * 1.05 + 0.3, dsh);
			c *= mix(1.0, 0.68, wet_k);                                   // wet sand
			vec3 film = mix(c * 0.85, vec3(0.32, 0.55, 0.52) * (0.5 + 0.5 * c), 0.35);
			c = mix(c, film, sheet);                                      // under a thin sheet of water
			c = mix(c, vec3(0.93, 0.95, 0.94), lip);
			wet_k = max(wet_k, sheet);
			wet_k *= 1.0 - lip;
		}
		c *= mix(0.85, 1.0, smoothstep(0.0, 0.6, h));
''' + s[b:]
open(p, 'w').write(s)

# ---------------------------------------------------------------- the terrain script: feed it the sea's swell and clock
edit('scripts/world_terrain.gd', [
("""	var hw = om.get_shader_parameter("high_water")
	var high: bool = hw != null and float(hw) > 0.5
	_mat.set_shader_parameter("high_water", 1.0 if high else 0.0)
	if not high:
		return
	_mat.set_shader_parameter("ocean_time", float(ocean.get("time")))
""", """	var hw = om.get_shader_parameter("high_water")
	var high: bool = hw != null and float(hw) > 0.5
	_mat.set_shader_parameter("high_water", 1.0 if high else 0.0)
	# the swash on the sand (both settings) runs on the sea's clock and swell
	_mat.set_shader_parameter("ocean_time", float(ocean.get("time")))
	var sa = om.get_shader_parameter("sea_amplitude")
	_mat.set_shader_parameter("swell_a", 0.7 if sa == null else float(sa))
	var sp = om.get_shader_parameter("surf_period")
	_mat.set_shader_parameter("surf_period", 9.0 if sp == null else float(sp))
	if not _foam_set:
		var fn = om.get_shader_parameter("foam_noise")
		if fn != null:
			_mat.set_shader_parameter("foam_noise", fn)
			_foam_set = true
	if not high:
		return
"""),
("var _vis_t := 0.0\n", "var _vis_t := 0.0\nvar _foam_set := false\n"),
])
