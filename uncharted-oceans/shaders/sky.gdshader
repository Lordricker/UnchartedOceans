shader_type sky;
// Stylized weather sky for the sailing game.
// All colour logic (time of day, air type, storms) is worked out on the CPU in SkySystem and handed in as
// uniforms, so this shader stays cheap: one gradient, two glow terms, two cloud layers, a few stars,
// the moon, and up to three storm cells drawn as towering cloud walls on the horizon.

#define MAX_STORMS 3

uniform vec3 sun_dir = vec3(0.0, 0.3, -1.0);

uniform vec4 zenith_color : source_color = vec4(0.18, 0.4, 0.75, 1.0);
uniform vec4 mid_color : source_color = vec4(0.4, 0.6, 0.85, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.7, 0.8, 0.9, 1.0);
uniform vec4 ground_color : source_color = vec4(0.3, 0.4, 0.5, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.6, 0.3, 1.0);
uniform vec4 glow_core_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform vec4 opposite_color : source_color = vec4(0.9, 0.6, 0.7, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.25, 0.3, 0.45, 1.0);
uniform vec4 cloud_lit_color : source_color = vec4(1.0, 0.9, 0.8, 1.0);
uniform vec4 cloud_shade_color : source_color = vec4(0.5, 0.55, 0.65, 1.0);
uniform vec4 cirrus_color : source_color = vec4(1.0, 0.9, 0.85, 1.0);
uniform vec3 sun_color = vec3(3.0, 2.7, 2.2);

uniform float glow_strength = 1.0;
uniform float glow_power = 3.0;
uniform float glow_height = 0.5;
uniform float opposite_strength = 0.0;
uniform float sun_visibility = 1.0;
uniform float sun_radius = 0.022;
uniform float star_visibility = 0.0;

uniform float coverage = 0.45;
uniform float overcast = 0.0;
uniform float cirrus_amount = 0.3;
uniform vec2 wind_offset = vec2(0.0);
uniform vec2 wind_dir = vec2(0.0, -1.0);
uniform float cloud_scale = 1.4;
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;

// Storm cells. storm_a: x = compass direction (radians, atan(x, -z)), y = angular half width, z = angular height
// of the cloud top, w = strength (0 = off).  storm_b: x = distance haze 0-1, y = rain 0-1, z = shape seed,
// w = lightning flash 0-1.
uniform vec4 storm_a[MAX_STORMS];
uniform vec4 storm_b[MAX_STORMS];
uniform vec4 storm_base_color : source_color = vec4(0.12, 0.13, 0.17, 1.0);
uniform vec4 storm_top_color : source_color = vec4(1.0, 0.85, 0.7, 1.0);
uniform float storm_light = 1.0;

// Moon. SkySystem works out where it is, which way its phase faces and how much cloud is in front of it.
// moon_right / moon_up are the disc's own axes on the sky (so the phase can be lit from the real sun direction).
// moon_veil: 0 = clear air (sharp disc, small halo), 1 = thick cloud over it (smeared glow, no crisp edge).
// moon_glow: how much of the glow, halo ring and earthshine shows (0 in daylight, 1 on a dark night).
// moon_ring: thin high cloud over the moon draws the 22 degree halo ring.
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 moon_right = vec3(1.0, 0.0, 0.0);
uniform vec3 moon_up = vec3(0.0, 0.0, -1.0);
uniform vec3 moon_color = vec3(1.4, 1.38, 1.3);
uniform vec3 moon_cloud_light = vec3(0.0);
uniform vec3 moon_sky_lift = vec3(0.0);
uniform float moon_radius = 0.03;
uniform float moon_visibility = 0.0;
uniform float moon_glow = 0.0;
uniform float moon_veil = 0.0;
uniform float moon_ring = 0.0;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float stars(vec3 dir) {
	vec3 sp = dir * 150.0;
	vec3 cell = floor(sp);
	vec3 f = fract(sp);
	float h = hash13(cell);
	vec3 off = vec3(hash13(cell + 1.7), hash13(cell + 3.1), hash13(cell + 5.9));
	float d = length(f - (0.3 + 0.4 * off));
	float bright = step(0.985, h) * (0.4 + 0.6 * fract(h * 57.0));
	return bright * (1.0 - smoothstep(0.0, 0.28, d));
}

void sky() {
	vec3 dir = EYEDIR;
	float y = dir.y;
	float sd = dot(dir, sun_dir);

	// ---- base gradient: horizon -> mid -> zenith ----
	float k = pow(max(y, 0.0), 0.5);
	vec3 col = mix(horizon_color.rgb, mid_color.rgb, smoothstep(0.0, 0.45, k));
	col = mix(col, zenith_color.rgb, smoothstep(0.35, 1.0, k));
	col = mix(col, ground_color.rgb, smoothstep(0.0, 0.25, -y));

	// ---- moonlit night: the whole sky is a touch lighter (a bit more near the horizon) ----
	col += moon_sky_lift * (0.55 + 0.45 * (1.0 - smoothstep(0.0, 0.6, max(y, 0.0))));

	// ---- twilight bands opposite the sun: blue shadow low down, pink "belt of Venus" above it ----
	float anti = pow(max(-sd, 0.0), 2.0);
	float shadow_band = anti * (1.0 - smoothstep(0.0, 0.14, y)) * smoothstep(-0.02, 0.01, y);
	col = mix(col, shadow_color.rgb, shadow_band * opposite_strength * 0.8);
	float venus = anti * smoothstep(0.03, 0.12, y) * (1.0 - smoothstep(0.12, 0.5, y));
	col = mix(col, opposite_color.rgb, venus * opposite_strength);

	// ---- sun glow: wide coloured glow hugging the horizon plus a tight hot core ----
	float g = max(sd, 0.0);
	float vmask = 1.0 - smoothstep(0.0, glow_height, max(y, 0.0));
	float broad = pow(g, glow_power) * (0.3 + 0.7 * vmask);
	float tight = pow(g, glow_power * 6.0);
	col = mix(col, glow_color.rgb, clamp(broad * glow_strength, 0.0, 1.0));
	col = mix(col, glow_core_color.rgb, clamp(tight * glow_strength * 1.3, 0.0, 1.0));

	// ---- low clouds: big soft cumulus on a flat layer, shaded by looking toward the sun ----
	float dl = 0.0;
	vec3 low_col = col;
	if (y > 0.0) {
		vec2 uv = dir.xz / (y + 0.10) * 0.10 * cloud_scale + wind_offset;
		float n = texture(cloud_noise, uv).r * 0.8 + texture(cloud_noise, uv * 3.1 + vec2(0.37, 0.11)).r * 0.2;
		float thr = mix(0.66, 0.36, coverage);
		float d = smoothstep(thr, thr + 0.30, n);
		d = mix(d, 0.7 + 0.3 * n, overcast);

		// density a little way toward the sun: thinner there means this part faces the light
		vec2 toward = normalize(sun_dir.xz + vec2(0.0001, 0.0));
		vec2 uvs = uv + toward * 0.014 * cloud_scale;
		float ns = texture(cloud_noise, uvs).r * 0.8 + texture(cloud_noise, uvs * 3.1 + vec2(0.37, 0.11)).r * 0.2;
		float ds = mix(smoothstep(thr, thr + 0.30, ns), 0.7 + 0.3 * ns, overcast);
		// shading lives INSIDE the cloud only: thin edges stay bright so nothing looks like a drop shadow on the sky
		float interior = smoothstep(0.25, 0.85, d);
		float lit = clamp(0.62 + (d - ds) * 2.0, 0.0, 1.0);
		lit *= mix(1.0, 0.6, smoothstep(0.7, 1.0, d) * (1.0 - overcast * 0.5));   // thick cores are a bit darker underneath
		lit *= mix(0.8, 1.0, 0.5 + 0.5 * sd);
		lit = mix(1.0, lit, interior);
		vec3 cc = mix(cloud_shade_color.rgb, cloud_lit_color.rgb, lit);

		// bright rim on cloud edges facing the sun (silver lining)
		float rim = d * (1.0 - d) * 4.0;
		cc += glow_core_color.rgb * rim * pow(max(sd, 0.0), 5.0) * 0.5 * (1.0 - overcast);

		// moonlight on the clouds: a faint silver wash everywhere, strongest round the moon, with a bright rim on thin edges
		float mdc = max(dot(dir, moon_dir), 0.0);
		cc += moon_cloud_light * (0.12 + 0.88 * pow(mdc, 3.0) + rim * pow(mdc, 5.0) * 1.5) * (0.4 + 0.6 * lit);

		float fade = smoothstep(0.0, 0.3, y);
		low_col = mix(col, cc, 0.25 + 0.75 * fade);
		dl = d * smoothstep(0.0, 0.18, y);
	}

	// ---- cirrus: thin, high, stretched a little along the wind, stays lit after the sun has set ----
	float dc = 0.0;
	if (y > 0.0) {
		vec2 uvc = dir.xz / (y + 0.30) * 0.10 * cloud_scale;
		vec2 wd = normalize(wind_dir);
		vec2 st = vec2(dot(uvc, wd) * 0.6, dot(uvc, vec2(-wd.y, wd.x)) * 1.2) + wind_offset * 0.6;
		float nc = texture(cloud_noise, st).r * 0.65 + texture(cloud_noise, st * 2.3 + vec2(0.2, 0.7)).r * 0.35;
		float thrc = mix(0.62, 0.4, cirrus_amount);
		dc = smoothstep(thrc, thrc + 0.4, nc) * smoothstep(0.02, 0.25, y) * smoothstep(0.0, 0.1, cirrus_amount) * (1.0 - overcast * 0.85) * 0.5;
	}

	// ---- composite: sky -> stars -> cirrus -> sun -> moon -> low clouds ----
	float up = smoothstep(0.0, 0.04, y);
	float cover = clamp(dl + dc, 0.0, 1.0);
	col += vec3(0.75, 0.82, 1.0) * stars(dir) * star_visibility * up * (1.0 - cover);
	col = mix(col, cirrus_color.rgb, dc);

	if (!AT_CUBEMAP_PASS) {
		float ang = acos(clamp(sd, -1.0, 1.0));
		float disc = 1.0 - smoothstep(sun_radius * 0.8, sun_radius * 1.15, ang);
		float halo = exp(-ang * 18.0) * 0.35;
		float vis = sun_visibility * up * (1.0 - dl * 0.9);
		col += sun_color * disc * vis;
		col += glow_core_color.rgb * halo * vis;
	}

	// ---- moon: phase disc, glow and halo ring. The cloud in front decides clear vs fuzzy (moon_veil), and the clouds
	// drifting over it hide it pixel by pixel (they are mixed in on top, below). ----
	if (moon_visibility > 0.001) {
		float mang = acos(clamp(dot(dir, moon_dir), -1.0, 1.0));
		float mup = smoothstep(-0.015, 0.03, y);
		// low in the sky the moon goes warm, like the sun does
		vec3 mcol = mix(moon_color, moon_color * vec3(1.0, 0.62, 0.38), (1.0 - smoothstep(0.0, 0.28, moon_dir.y)) * 0.7);

		// glow: tight and small in clear air, wide and soft when cloud veils the moon
		float mhalo = exp(-mang * mix(26.0, 7.0, moon_veil)) * mix(0.16, 0.55, moon_veil);
		col += mcol * mhalo * moon_glow * mup;

		// 22 degree ring through thin high cloud
		float rx = (mang - 0.384) / 0.035;
		col += mcol * exp(-rx * rx) * moon_ring * moon_glow * mup * 0.22;

		if (!AT_CUBEMAP_PASS && mang < moon_radius * 3.5) {
			vec3 off = dir - moon_dir;
			vec2 q = vec2(dot(off, moon_right), dot(off, moon_up)) / moon_radius;
			float rr = length(q);
			// sharp edge in clear air, smeared edge when veiled
			float soft = mix(0.035, 1.1, moon_veil);
			float edge = 1.0 - smoothstep(1.0 - soft, 1.0 + soft * 0.8, rr);
			// a point on the ball: past the limb we hold the limb's shading so the smear stays moon-coloured
			vec2 qc = rr > 0.985 ? q * (0.985 / rr) : q;
			float z = sqrt(max(1.0 - dot(qc, qc), 0.0));
			vec3 n = qc.x * moon_right + qc.y * moon_up - z * moon_dir;
			// the phase: the half of the ball that faces the sun is lit
			float lit_m = smoothstep(-0.03, 0.12, dot(n, sun_dir));
			float mm = textureLod(cloud_noise, qc * 0.16 + vec2(0.31, 0.62), 1.0).r;
			float maria = smoothstep(0.46, 0.62, mm);
			float surf = mix(1.0, 0.6, maria * 0.9) * (0.82 + 0.18 * z);
			float bright = mix(1.0, 0.5, moon_veil);
			col = mix(col, mcol * surf * bright, edge * lit_m * moon_visibility * mup);
			// earthshine: the dark side of a crescent shows faintly on a dark night
			col = mix(col, vec3(0.035, 0.045, 0.075) + mcol * 0.02, edge * (1.0 - lit_m) * moon_glow * 0.3 * moon_visibility * mup);
		}
	}

	col = mix(col, low_col, dl);

	// ---- storm cells: a wide shelf cloud / rain wall, layered and dark, with a bright gap under its lifted edge ----
	if (y > -0.02) {
		float az = atan(dir.x, -dir.z);
		float el = asin(clamp(y, -1.0, 1.0));
		for (int i = 0; i < MAX_STORMS; i++) {
			vec4 a = storm_a[i];
			vec4 b = storm_b[i];
			if (a.w < 0.01) {
				continue;
			}
			float da = az - a.x;
			da = atan(sin(da), cos(da));                          // wrap to -pi..pi
			float u = da / a.y;                                   // -1..1 across the storm front
			float au = abs(u);
			if (au > 1.3) {
				continue;
			}
			float persp = max(cos(da) * cos(da), 0.08);                     // a straight front is farther away off to the sides, so it sits lower: pyramid
			float h = el / max(a.z * persp, 0.001);               // 0 at the sea, 1 at the top of the cloud

			float lump_a = textureLod(cloud_noise, vec2(az * 3.0 + b.z, el * 4.0), 0.0).r - 0.5;
			float lump_b = textureLod(cloud_noise, vec2(az * 9.0 + b.z, el * 12.0), 0.0).r - 0.5;
			float edge_n = lump_a * 0.5 + lump_b * 0.25;

			// outline: soft sides, a soft ragged top that fades up into the sky
			float side = 1.0 - smoothstep(0.65, 1.25, au + edge_n * 0.3);
			float top_h = 1.05 + edge_n * 0.25;
			float topfade = 1.0 - smoothstep(top_h * 0.15, top_h * 1.1, h);
			// the shelf: the cloud base touches the sea in the middle (the rain core) and lifts toward the sides,
			// leaving a gap of open sky under the leading edge
			float base_h = 0.08 + 0.05 * au + edge_n * 0.05;
			float above = smoothstep(base_h - 0.02, base_h + 0.035, h);
			float dens = clamp(side * topfade * above, 0.0, 1.0) * a.w;

			// layered bands that curve with the front
			float band = textureLod(cloud_noise, vec2(u * 0.25 + b.z, h * 1.1 + u * u * 0.35 + u * 0.12 + edge_n * 0.12), 0.0).r
				* 0.75 + textureLod(cloud_noise, vec2(u * 0.6 + b.z, h * 3.0 + u * u * 1.2), 0.0).r * 0.25;
			float stripe = smoothstep(0.25, 0.75, band);

			// colour: dark blue-grey, lighter toward the top and in the lit bands
			float shade = 0.08 + 0.42 * smoothstep(0.15, 1.0, h) + (stripe - 0.5) * 0.5 + edge_n * 0.3;
			shade = clamp(shade, 0.0, 1.0) * mix(0.3, 1.0, storm_light);
			shade *= 1.0 - 0.55 * pow(max(sd, 0.0), 2.0) * storm_light;      // looking toward the sun we see the shadowed side
			vec3 body_lit = mix(storm_base_color.rgb, mix(storm_top_color.rgb, zenith_color.rgb * 1.3, 0.5), 0.5);
			vec3 sc = mix(storm_base_color.rgb, body_lit, shade);

			// the lip of the shelf catches light, and the sides facing the sun glow warm
			float lip = smoothstep(base_h - 0.01, base_h + 0.04, h) * (1.0 - smoothstep(base_h + 0.04, base_h + 0.2, h));
			float toward_sun = pow(max(sd, 0.0), 3.0) * storm_light;
			sc += (storm_top_color.rgb * 0.4 + glow_color.rgb * 0.6) * lip * (0.12 + 0.5 * toward_sun);
			sc += glow_color.rgb * toward_sun * 0.18 * smoothstep(0.3, 1.0, au) * (1.0 - h) * dens;

			// rain curtain under the middle of the storm
			float streak = smoothstep(0.2, 0.9, textureLod(cloud_noise, vec2(az * 2.5 + b.z, 0.5), 0.0).r);   // a few broad, soft rain shafts, not streaks
			float rain_zone = (1.0 - smoothstep(0.0, base_h + 0.22, h)) * (0.35 + 0.65 * smoothstep(-0.02, base_h * 0.8, h)) * (1.0 - smoothstep(0.1, 0.7, au + edge_n * 0.3));
			float rain = b.y * rain_zone * (0.6 + 0.4 * streak) * a.w * 1.5;

			// lightning inside the cloud
			float lf = b.w * (0.1 + 1.2 * pow(textureLod(cloud_noise, vec2(az * 5.0 + b.z, el * 9.0), 0.0).r, 2.0));
			sc += vec3(0.65, 0.75, 1.0) * lf * 0.9;

			// far away: fade toward the haze
			sc = mix(sc, horizon_color.rgb * 0.85, b.x);
			vec3 rain_col = mix(storm_base_color.rgb * 2.4 + vec3(0.02), horizon_color.rgb * 0.72, 0.3 + 0.7 * b.x);   // soft grey
			rain_col += vec3(0.65, 0.75, 1.0) * b.w * 0.4;

			col = mix(col, rain_col, clamp(rain * (1.0 - b.x * 0.3), 0.0, 0.7));
			col = mix(col, sc, clamp(dens * (1.0 - b.x * 0.3), 0.0, 1.0));
		}
	}

	COLOR = col;
}
