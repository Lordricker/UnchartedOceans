// Flat test sea that is not drawn inside the ship's hull.
// The hull's waterline half-width is sampled every 0.5 m along the keel (exported from Blender
// as Brig root extras "waterline_half_beam") and fed in by ship_motion.gd with the ship's inverse
// transform each frame, so the mask follows roll, pitch and heave.
shader_type spatial;

uniform vec3 water_color : source_color = vec3(0.08, 0.2, 0.23);
uniform float roughness_value = 0.25;
uniform mat4 ship_inv;                 // world -> ship (glTF) local
uniform float half_beam[43];
uniform float y_min = -10.5;           // Blender Y of the first sample (bow is -Y)
uniform float y_step = 0.5;
uniform int sample_count = 43;
uniform float inset = 0.02;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 l = (ship_inv * vec4(world_pos, 1.0)).xyz;
	float yb = -l.z;                     // glTF local -> Blender Y
	float f = (yb - y_min) / y_step;
	if (f >= 0.0 && f <= float(sample_count - 1)) {
		int i = int(floor(f));
		int j = min(i + 1, sample_count - 1);
		float hb = mix(half_beam[i], half_beam[j], fract(f));
		if (abs(l.x) < hb - inset) {
			discard;
		}
	}
	ALBEDO = water_color;
	ROUGHNESS = roughness_value;
}
