shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// The still water of a fountain basin (FountainFX). A flat disc: ripples run out from where the water lands, foam
// gathers on that ring and around the jet, and a little foam clings to the rim. Everything is procedural (no textures).

uniform vec3 deep_color : source_color = vec3(0.025, 0.14, 0.18);
uniform vec3 shallow_color : source_color = vec3(0.14, 0.40, 0.45);
uniform float alpha_base : hint_range(0.0, 1.0) = 0.8;
uniform float radius = 2.38;
uniform float ring_radius = 1.58;
uniform float ring_width = 0.3;
uniform float ring_strength : hint_range(0.0, 2.0) = 1.0;
uniform float center_strength : hint_range(0.0, 2.0) = 0.3;
uniform float center_radius = 0.55;
uniform float ripple_speed = 3.2;
uniform float normal_scale = 1.0;

varying vec3 lp;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float height(vec2 p, float t) {
	float r = length(p);
	float h = 0.0;
	h += (vnoise(p * 3.2 + vec2(t * 0.22, t * 0.15)) - 0.5) * 0.020;
	h += (vnoise(p * 8.0 - vec2(t * 0.34, -t * 0.28)) - 0.5) * 0.009;
	float d = abs(r - ring_radius);
	h += sin(d * 17.0 - t * ripple_speed) * exp(-d * 1.7) * 0.020 * ring_strength;
	h += sin(d * 33.0 - t * ripple_speed * 1.7) * exp(-d * 3.2) * 0.008 * ring_strength;
	h += sin(r * 19.0 - t * ripple_speed * 1.1) * exp(-r * 1.15) * 0.020 * center_strength;
	return h;
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float t = TIME;
	vec2 p = lp.xz;
	float r = length(p);
	if (r > radius) {
		discard;
	}
	float e = 0.012;
	float h0 = height(p, t);
	float hx = height(p + vec2(e, 0.0), t);
	float hz = height(p + vec2(0.0, e), t);
	vec3 n_local = normalize(vec3(-(hx - h0) / e * normal_scale, 1.0, -(hz - h0) / e * normal_scale));
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_local, 0.0)).xyz);

	float band = 1.0 - smoothstep(0.0, ring_width, abs(r - ring_radius));
	float fn = vnoise(p * 14.0 + vec2(t * 0.55, -t * 0.4)) * 0.65 + vnoise(p * 31.0 - vec2(t * 0.8, t * 0.6)) * 0.35;
	float foam_ring = band * smoothstep(0.30, 0.62, fn + band * 0.45) * ring_strength;
	float cen = 1.0 - smoothstep(0.0, center_radius, r);
	float foam_cen = cen * smoothstep(0.35, 0.65, fn + cen * 0.5) * center_strength;
	float rim = smoothstep(radius - 0.16, radius - 0.01, r);
	float foam_rim = rim * smoothstep(0.45, 0.8, fn) * 0.55;
	float foam = clamp(foam_ring + foam_cen + foam_rim, 0.0, 1.0);

	float depth_mix = clamp(0.45 + h0 * 7.0 + (1.0 - rim) * 0.1, 0.0, 1.0);
	vec3 col = mix(deep_color, shallow_color, depth_mix);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	ALBEDO = mix(col, vec3(0.93, 0.96, 0.98), foam);
	ROUGHNESS = mix(0.04, 0.55, foam);
	SPECULAR = 0.9;
	METALLIC = 0.0;
	ALPHA = clamp(alpha_base + foam * 0.55 + fres * 0.25, 0.0, 1.0) * (1.0 - smoothstep(radius - 0.025, radius, r));
}
