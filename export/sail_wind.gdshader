// Starter sail/flag shader for Brig.glb.
// COLOR (glTF COLOR_0 "PinWeights", exported from Blender):
//   r = billow / flutter weight (0 where the cloth is held, 1 at the free belly)
//   g = height down the sail (0 head .. 1 foot)     b = position across the sail (0..1)
// Furled / Reefed are blend shapes on the same mesh; this shader stacks on top of them.
// Drive wind_strength / luff from gameplay (0 = slack, 1 = full). Set per sail with
// set_instance_shader_parameter() so every sail can share one material.
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 shadow_tint : source_color = vec3(0.32, 0.36, 0.52);   // blue-violet shadow, per art direction
instance uniform float wind_strength = 1.0;   // 0..1
instance uniform float luff = 0.0;            // 0..1, sail shaking when pointed too high
uniform vec3 billow_dir = vec3(0.0, 0.0, 1.0); // mesh-local direction the belly pushes (Godot: ship +Z is the bow)
uniform float billow_depth = 0.6;              // metres at full wind
uniform float flutter_amp = 0.06;
uniform float flutter_speed = 7.0;

void vertex() {
	float w = COLOR.r;
	float belly = w * billow_depth * wind_strength;
	float t = TIME * flutter_speed;
	float flutter = sin(t + COLOR.b * 9.0 + COLOR.g * 5.0) * (flutter_amp + luff * 0.25) * w;
	VERTEX += normalize(billow_dir) * (belly + flutter);
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb;
}

void light() {
	float n = dot(NORMAL, LIGHT);
	n = FRONT_FACING ? n : -n;                  // light both faces of the cloth
	float lit = step(0.05, n * ATTENUATION);    // hard two-tone
	vec3 c = mix(ALBEDO * shadow_tint, ALBEDO, lit);
	DIFFUSE_LIGHT += c * LIGHT_COLOR / PI;
}
