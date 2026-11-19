// The ground of a small port's land plate (SP_Land): the same landscape as the macro terrain round it
// (landscape.gdshaderinc), so the town sits in the land with no seam. Set up by WorldStreamer._dress_land().
shader_type spatial;
render_mode cull_back;

#include "res://shaders/landscape.gdshaderinc"

uniform vec2 chart_origin = vec2(0.0);    // the floating origin: chart xz = Godot world xz + this

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 nm;
	float r;
	vec3 n = normalize(wnrm);
	vec3 c = ls_color(wpos.xz, wpos.xz + chart_origin, wpos.y, nm, r);
	// steep banks (the plate's edges where it meets the harbour) are stone, not grass
	float bank = smoothstep(0.55, 0.3, n.y);
	c = mix(c, ls_bank(wpos, n), bank);
	ALBEDO = c;
	ROUGHNESS = r;
	NORMAL = normalize((VIEW_MATRIX * vec4(ls_bump(n, nm, 0.6 * (1.0 - bank)), 0.0)).xyz);
}
