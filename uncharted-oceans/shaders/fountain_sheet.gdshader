shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
// The thin curtain of water that spills over the upper bowl's rim into the lower basin (FountainFX).
// UV.x runs round the ring, UV.y from the lip (0) down to the basin (1). Streaks run down and fade at the ends.

uniform vec4 tint : source_color = vec4(0.82, 0.92, 0.96, 1.0);
uniform float fall_speed = 1.6;
uniform float streaks = 46.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.55;

float hash11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void fragment() {
	float u = UV.x * streaks;
	float id = floor(u);
	float fu = fract(u);
	float w = 0.25 + 0.5 * hash11(id);
	float line = smoothstep(0.0, 0.18, fu) * (1.0 - smoothstep(w, w + 0.25, fu));
	float y = UV.y * 3.0 + TIME * fall_speed * (0.7 + 0.6 * hash11(id + 7.0)) + hash11(id + 3.0) * 10.0;
	float pulse = 0.55 + 0.45 * sin(y * 6.2831);
	float top = smoothstep(0.0, 0.08, UV.y);
	float bot = 1.0 - smoothstep(0.82, 1.0, UV.y);
	float a = (0.25 + 0.75 * line) * pulse * top * bot * opacity;
	ALBEDO = tint.rgb;
	ALPHA = a;
}
