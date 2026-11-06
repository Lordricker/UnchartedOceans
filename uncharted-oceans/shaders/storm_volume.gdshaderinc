// Raymarched storm clouds for sky.gdshader (included right before sky()).
//
// Each storm cell is a real volume in the world: an oriented box around the cell, filled by a density function
// (footprint ellipse x height profile x 3D noise erosion), plus rain shafts under the base. The ray starts at the
// camera, is clipped to each cell's box, and is marched front to back with a few steps. Lighting is cheap: two
// density samples toward the sun for self-shadowing, a height-based ambient term, and a forward-scatter phase.
//
// This runs in the sky's half- or quarter-resolution pass (see sky()), and the full-resolution pass only blends the
// result over the sky, so the cost scales with vol_quarter and vol_steps, not with the screen size.
//
// Per cell (up to MAX_STORMS, nearest first, all in metres relative to the camera):
//   vol_a: x, y = cell centre (world x, z)   z = half length of the front   w = half depth (direction of travel)
//   vol_b: x, y = direction of travel (unit)  z = cloud top height          w = fade (distance / intensity), 0 = off
//   vol_c: x = rain 0-1   y = shape seed   z = lightning flash 0-1   w = intensity 0-1
//
// Tuning knobs: vol_sigma (how dark / opaque the cloud is), vol_rain_sigma, the base / top lines in vol_dens().

uniform bool vol_enabled = false;
uniform bool vol_quarter = false;
// The Low quality tier: no fine noise and one sun-shadow sample instead of two (about half the texture reads).
uniform bool vol_lite = false;
// Keep drawing the painted storm wall in the main view too, with the raymarched cloud laid over it.
uniform bool vol_paint_behind = true;
uniform int vol_steps : hint_range(8, 48, 1) = 22;
uniform float vol_max_dist = 84000.0;
uniform float vol_sigma = 0.0007;
// Overall brightness of the storm cloud (1 = as lit; lower = darker, less white).
uniform float vol_brightness = 0.7;
uniform float vol_rain_sigma = 0.00035;
uniform float vol_haze_m = 45000.0;
uniform vec3 vol_drift = vec3(0.0);
uniform vec4 vol_a[MAX_STORMS];
uniform vec4 vol_b[MAX_STORMS];
uniform vec4 vol_c[MAX_STORMS];
uniform sampler3D vol_noise : repeat_enable, filter_linear;

// The noise texture is a soft fbm with a narrow range; stretch it so the clouds get real holes and lumps.
float vol_tex(vec3 uvw) {
	return clamp((textureLod(vol_noise, uvw, 0.0).r - 0.5) * 2.0 + 0.5, 0.0, 1.0);
}

// Cloud density 0-1 at a point in the cell's own frame (x along the front, y up, z along the direction of travel,
// +z = the leading edge). hv = 0 at the cloud base .. 1 at the top, nc = the coarse noise (reused for shading).
float vol_dens(vec3 lp, vec4 A, vec4 B, vec4 C, bool detail, out float hv, out float nc) {
	float R = max(A.z, 1.0);
	float D = max(A.w, 1.0);
	float H = B.z;
	vec3 seed_off = vec3(C.y * 0.173, C.y * 0.311, C.y * 0.097);
	nc = vol_tex(lp * vec3(1.0 / 11000.0, 1.0 / 3600.0, 1.0 / 11000.0) + seed_off + vol_drift);

	float u = lp.x / R;
	float w = lp.z / D;
	float wob = nc - 0.5;

	// footprint: a long thin ellipse (a squall line), ragged at the edge
	float ell = length(vec2(u, w * 0.85)) + wob * 0.35;
	float foot = 1.0 - smoothstep(0.55, 1.0, ell);

	// the top is highest over the core and slopes down toward the edges
	float ec = clamp(ell, 0.0, 1.0);
	float top = H * 0.6 * (1.0 - 0.5 * ec * ec);
	// the base touches the sea in the rain core and lifts toward the flanks and the leading edge (the shelf)
	float base = 150.0 + 1600.0 * smoothstep(0.2, 1.0, abs(u)) + 500.0 * smoothstep(0.2, 1.0, w) + wob * 300.0;

	hv = (lp.y - base) / max(top - base, 800.0);
	float vprof = smoothstep(0.0, 0.1, hv) * (1.0 - smoothstep(0.7, 1.0, hv));
	float shape = foot * vprof * mix(0.5, 1.0, C.w);
	if (shape < 0.01) {
		return 0.0;
	}

	float n = nc;
	if (detail && !vol_lite) {
		// finer, flatter lumps: wider than tall, so the cloud reads as layered bands
		float nf = vol_tex(lp * vec3(1.0 / 4200.0, 1.0 / 1500.0, 1.0 / 4200.0) + seed_off * 2.3 + vol_drift * 2.0);
		n = nc * 0.8 + nf * 0.2;
	}
	// soft ramp (not a hard cut-off) so the cloud edge fades out smoothly instead of speckling
	return smoothstep(0.0, 1.0, clamp((shape - (1.0 - n) * 0.7) * 1.5, 0.0, 1.0));
}

// How much sunlight reaches a point inside the cloud (0 = in its own shadow .. 1 = lit).
float vol_light(vec3 lp, vec3 ld, vec4 A, vec4 B, vec4 C) {
	float h;
	float n;
	float d1 = vol_dens(lp + ld * 450.0, A, B, C, false, h, n);
	if (vol_lite) {
		return exp(-d1 * 1500.0 * vol_sigma * 1.1);
	}
	float d2 = vol_dens(lp + ld * 1500.0, A, B, C, false, h, n);
	return exp(-(d1 * 450.0 + d2 * 1050.0) * vol_sigma * 1.1);
}

// Marches the storms along one sky direction. Returns premultiplied light in rgb and coverage (1 - transmittance)
// in a, ready to be laid over the sky: sky * (1 - a) + rgb.
vec4 storm_volume(vec3 dir) {
	if (dir.y < -0.02) {
		return vec4(0.0);
	}
	vec3 ro = vec3(0.0, 12.0, 0.0);
	// a small random offset per ray hides stepping bands without turning the edges to grain
	float jit = 0.5 + (hash13(dir * 311.7 + vec3(1.3, 7.1, 3.7)) - 0.5) * 0.3;

	float cs = dot(dir, sun_dir);
	float g = 0.5;
	float hg = (1.0 - g * g) / pow(max(1.0 + g * g - 2.0 * g * cs, 0.05), 1.5);
	float phase = 0.55 + 0.225 * min(hg, 4.0);

	vec3 haze_col = horizon_color.rgb * 0.55;
	vec3 rain_col = mix(storm_base_color.rgb * 2.4 + vec3(0.02), horizon_color.rgb * 0.72, 0.4);
	vec3 amb_lo = storm_base_color.rgb * 1.8 + moon_cloud_light * 0.5;
	vec3 amb_hi = mix(amb_lo, zenith_color.rgb * 1.15 + storm_top_color.rgb * 0.15 * storm_light + moon_cloud_light, 0.5);
	vec3 direct_col = storm_top_color.rgb * 0.9 * storm_light;

	int n = clamp(vol_steps, 4, 48);
	float T = 1.0;
	vec3 L = vec3(0.0);

	for (int i = 0; i < MAX_STORMS; i++) {
		vec4 A = vol_a[i];
		vec4 B = vol_b[i];
		vec4 C = vol_c[i];
		if (B.w < 0.01 || T < 0.02) {
			continue;
		}

		// into the cell's own frame
		vec2 tr = B.xy;
		vec2 fr = vec2(-tr.y, tr.x);
		vec2 cxz = A.xy;
		vec3 ro_l = vec3(dot(ro.xz - cxz, fr), ro.y, dot(ro.xz - cxz, tr));
		vec3 rd_l = vec3(dot(dir.xz, fr), dir.y, dot(dir.xz, tr));
		vec3 ld = vec3(dot(sun_dir.xz, fr), sun_dir.y, dot(sun_dir.xz, tr));

		// ray against the cell's box
		vec3 bmin = vec3(-A.z * 1.1, -100.0, -A.w * 1.25);
		vec3 bmax = vec3(A.z * 1.1, B.z, A.w * 1.25);
		vec3 rs = vec3(abs(rd_l.x) < 1e-5 ? 1e-5 : rd_l.x, abs(rd_l.y) < 1e-5 ? 1e-5 : rd_l.y, abs(rd_l.z) < 1e-5 ? 1e-5 : rd_l.z);
		vec3 inv = 1.0 / rs;
		vec3 t0 = (bmin - ro_l) * inv;
		vec3 t1 = (bmax - ro_l) * inv;
		vec3 tn = min(t0, t1);
		vec3 tf = max(t0, t1);
		float tmin = max(max(tn.x, tn.y), max(tn.z, 0.0));
		float tmax = min(min(tf.x, tf.y), min(tf.z, vol_max_dist));
		if (tmax <= tmin) {
			continue;
		}
		float len = tmax - tmin;

		for (int k = 0; k < 48; k++) {
			if (k >= n || T < 0.02) {
				break;
			}
			// steps get longer with distance (the near face of the cloud matters most); jitter hides the banding
			float f0 = pow((float(k) + jit) / float(n), 1.4);
			float f1 = pow((float(k) + 1.0 + jit) / float(n), 1.4);
			float ds = len * (f1 - f0);
			float s = tmin + len * 0.5 * (f0 + f1);
			vec3 lp = ro_l + rd_l * s;

			float hv;
			float nc;
			float d = vol_dens(lp, A, B, C, true, hv, nc);

			// rain shafts below the base in the core of the storm
			float rain_d = 0.0;
			if (C.x > 0.01 && lp.y < 2600.0) {
				float u = lp.x / max(A.z, 1.0);
				float w = lp.z / max(A.w, 1.0);
				float rf = (1.0 - smoothstep(0.1, 0.5, abs(u) + (nc - 0.5) * 0.2)) * (1.0 - smoothstep(0.0, 0.9, abs(w + 0.2)));
				if (rf > 0.01) {
					float rnz = vol_tex(vec3(lp.x / 1400.0, lp.y / 7000.0, lp.z / 1400.0) + vec3(C.y * 0.41));
					rain_d = C.x * rf * smoothstep(0.25, 0.8, rnz) * (1.0 - smoothstep(300.0, 2200.0, lp.y));
				}
			}

			float sig_c = d * vol_sigma;
			float sig_r = rain_d * vol_rain_sigma;
			float sig = (sig_c + sig_r) * B.w;
			if (sig < 1e-7) {
				continue;
			}
			float a = 1.0 - exp(-sig * ds);

			vec3 sc_c = vec3(0.0);
			if (d > 0.003) {
				float lt = vol_light(lp, ld, A, B, C);
				vec3 amb = mix(amb_lo, amb_hi, smoothstep(0.1, 1.0, hv));
				sc_c = amb + direct_col * lt * phase;
				sc_c *= 0.82 + 0.36 * smoothstep(0.25, 0.75, nc);
				// lightning inside the cloud
				sc_c += vec3(0.65, 0.75, 1.0) * C.z * C.w * (0.1 + 1.2 * nc * nc) * 0.9;
			}
			vec3 rc = rain_col + vec3(0.65, 0.75, 1.0) * C.z * 0.4;
			vec3 sc = (sc_c * sig_c + rc * sig_r) / max(sig_c + sig_r, 1e-7);

			// far away: fade toward the haze
			float hz = 1.0 - exp(-s / max(vol_haze_m, 1.0));
			sc = mix(sc, haze_col, hz * 0.55);

			L += T * a * sc;
			T *= 1.0 - a;
		}
	}
	return vec4(L * vol_brightness, 1.0 - T);
}
