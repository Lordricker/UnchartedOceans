shader_type spatial;
// The bow spray's drops and blobs (ship_motion.gd), drawn like an unshaded see-through StandardMaterial3D but never
// inside the hull: a drop whose spot lies within the hull's waterline outline (the same half-beam table the sea's hull
// mask uses, widened a little) and below the top of the bulwarks is not drawn. The drops live in world space, so when
// the ship turns, or catches up with drops that have slowed in the air, they would otherwise hang in the hold and
// over the deck.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform bool billboard = false;          // BILLBOARD_PARTICLES with keep scale (the blobs); off for the stretched drops

uniform mat4 ship_inv;                   // world -> the hull model's space (the space the table is in)
uniform float half_beam[43];
uniform int sample_count = 0;
uniform float y_min = 0.0;
uniform float y_step = 1.0;
uniform float flare = 0.35;              // how much wider the hull is per metre above the waterline
uniform float margin = 0.25;             // metres added all round the outline
uniform float top_y = 3.0;               // hull space height of the bulwark tops (no cull above this)

varying vec3 world_pos;

void vertex() {
	if (billboard) {
		mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
		mat_world = mat_world * mat4(vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (sample_count > 0) {
		vec3 l = (ship_inv * vec4(world_pos, 1.0)).xyz;
		float f = (-l.z - y_min) / y_step;
		if (f >= -1.0 && f <= float(sample_count) && l.y < top_y) {
			float fc = clamp(f, 0.0, float(sample_count - 1));
			int i = int(floor(fc));
			int j = min(i + 1, sample_count - 1);
			float hb = mix(half_beam[i], half_beam[j], fract(fc));
			if (hb > 0.01 && abs(l.x) < hb + max(l.y, 0.0) * flare + margin) {
				discard;
			}
		}
	}
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = albedo.rgb * COLOR.rgb * tex.rgb;
	ALPHA = albedo.a * COLOR.a * tex.a;
}
