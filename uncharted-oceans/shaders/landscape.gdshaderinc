// The look of open land: real grass (Poly Haven leafy_grass and sparse_grass) at two scales so it does not tile,
// meadow and dry patches, a slow drift between greener and more golden ground, and darker scrub and woodland that
// thickens with height. Shared by the macro terrain (world_terrain.gdshader) and the small ports' land plates
// (port_ground.gdshader), so the town's ground and the land round it are one landscape with no seam.
// Colours come out linear (albedo). The caller passes chart coordinates (cp) for the noise, so it is stable when the
// floating origin moves; the texture UVs use ls_uv_off (the origin's share of each tiling, worked out on the CPU).

uniform sampler2D ls_lush : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ls_dry : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ls_lush_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ls_dry_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ls_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 ls_uv_off = vec4(0.0);    // (fine x, fine z, coarse x, coarse z): fposmod(origin, tile) / tile
const float LS_FINE_M = 3.5;
const float LS_COARSE_M = 11.0;

float ls_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float ls_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(ls_hash(i), ls_hash(i + vec2(1.0, 0.0)), u.x), mix(ls_hash(i + vec2(0.0, 1.0)), ls_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float ls_fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * ls_noise(p);
		p = p * 2.03 + 17.3;
		a *= 0.5;
	}
	return s;
}

// Albedo of the land at Godot world xz / chart xz cp, height h (m above the sea). nmap: a tangent-space normal for
// NORMAL_MAP (use it where the mesh has tangents). rough: roughness.
vec3 ls_color(vec2 wxz, vec2 cp, float h, out vec3 nmap, out float rough) {
	vec2 uf = wxz / LS_FINE_M + ls_uv_off.xy;
	vec2 uc = wxz / LS_COARSE_M + ls_uv_off.zw;
	vec3 lush = mix(texture(ls_lush, uf).rgb, texture(ls_lush, uc).rgb, 0.45);
	vec3 dry = mix(texture(ls_dry, uf).rgb, texture(ls_dry, uc).rgb, 0.45);
	vec3 nl = mix(texture(ls_lush_n, uf).rgb, texture(ls_lush_n, uc).rgb, 0.45);
	vec3 nd = mix(texture(ls_dry_n, uf).rgb, texture(ls_dry_n, uc).rgb, 0.45);
	// meadow (lush) and drier, thinner grass in drifting patches a couple of hundred metres across
	float meadow = smoothstep(0.18, 0.5, ls_fbm(cp / 230.0 + vec2(4.1, 1.3)) + 0.08 * (ls_noise(cp / 23.0) - 0.5));
	vec3 c = mix(dry, lush, meadow);
	nmap = mix(nd, nl, meadow);
	// a slow drift between greener and more golden ground
	float drift = ls_fbm(cp / 900.0 + vec2(-7.3, 2.9));
	c *= mix(vec3(1.04, 1.02, 0.86), vec3(0.86, 1.04, 0.92), smoothstep(0.25, 0.65, drift));
	// scrub and woodland: dark, cooler patches, thicker up the hills, thin by the shore
	float wood = smoothstep(0.5, 0.68, ls_fbm(cp / 140.0 + vec2(11.7, -3.4)));
	wood *= mix(0.35, 1.0, smoothstep(8.0, 70.0, h));
	c = mix(c, c * vec3(0.42, 0.55, 0.42), wood * 0.85);
	rough = 0.93;
	return c;
}

// The grass's normal map on ground with no tangents: the texture is laid flat in world xz (u along +x, v along +z),
// so its tangent frame is built from the world axes. strength 0..1.
vec3 ls_bump(vec3 n_world, vec3 nm_rgb, float strength) {
	vec3 nm = nm_rgb * 2.0 - 1.0;
	vec3 t = normalize(vec3(1.0, 0.0, 0.0) - n_world * n_world.x);
	vec3 b = cross(n_world, t);
	return normalize(t * nm.x * strength + b * nm.y * strength + n_world * max(nm.z, 0.2));
}

// Bare earth and stone for steep banks (a vertical face would only smear the grass): the coastal rock texture laid on
// the face (world xz along it, height up it).
vec3 ls_bank(vec3 wpos, vec3 n_world) {
	vec2 uv = (abs(n_world.x) > abs(n_world.z) ? wpos.zy : wpos.xy) / 6.0;
	return texture(ls_rock, uv).rgb * 0.85;
}

// Rock on any steep ground: the rock texture projected three ways (top, and on both upright axes) and blended by the
// normal, so a cliff face is not smeared. wpos: Godot world position (y = height). Scale about 14 m.
vec3 ls_rock_tri(vec3 wpos, vec3 n_world) {
	vec3 w = pow(abs(n_world), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 o = ls_uv_off.zw * (11.0 / 14.0);
	vec3 top = texture(ls_rock, wpos.xz / 14.0 + o).rgb;
	vec3 sx = texture(ls_rock, vec2(wpos.z / 14.0 + o.y, -wpos.y / 14.0)).rgb;
	vec3 sz = texture(ls_rock, vec2(wpos.x / 14.0 + o.x, -wpos.y / 14.0)).rgb;
	return top * w.y + sx * w.x + sz * w.z;
}
