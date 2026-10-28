// Flood water in the hold: one box per wet space (from ship_flooding.gd's MultiMesh).
// - Box faces inside the water body are dropped: per side, INSTANCE_CUSTOM holds the height
//   above this box's floor up to which the neighbour's water (or a wall) covers it.
// - See-through like the sea: opacity comes from how much water lies behind each pixel
//   (from the depth buffer), so the floor and anything sunk shows through shallow water and
//   fades into the deep colour.
// - Faint seams every `cell` metres keep the stacked-cube look.
shader_type spatial;
render_mode cull_back, depth_draw_always;

uniform vec3 deep_color : source_color = vec3(0.018, 0.07, 0.085);
uniform vec3 shallow_color : source_color = vec3(0.06, 0.26, 0.26);
uniform vec3 seam_color : source_color = vec3(0.35, 0.55, 0.58);
uniform float absorption = 1.1;          // per metre
uniform float min_alpha = 0.18;          // a thin film still shows
uniform float cell = 0.25;
uniform float seam_width = 0.008;        // m
uniform float seam_strength = 0.35;
uniform float emission_strength = 0.06;  // keeps it readable in a dark hold
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 box_pos;     // position inside the unit box, -0.5..0.5
varying vec3 box_normal;  // face normal in the box's own space
varying vec3 box_size;    // this instance's size in metres
varying vec4 cover;       // per side (+x, -x, +z, -z): covered up to this height (m above the floor)

void vertex() {
	box_pos = VERTEX;
	box_normal = NORMAL;
	box_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	cover = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 p = (box_pos + 0.5) * box_size;   // metres from the box's lower corner
	vec3 an = abs(box_normal);
	if (box_normal.y < -0.5) discard;      // bottom sits on the floor
	if (an.y < 0.5) {                      // a side: drop the part inside the water body
		float c = box_normal.x > 0.5 ? cover.x : (box_normal.x < -0.5 ? cover.y : (box_normal.z > 0.5 ? cover.z : cover.w));
		if (p.y < c - 0.002) discard;
	}

	// cube seams
	float e = 1e3;
	if (an.x < 0.5) e = min(e, min(p.x, box_size.x - p.x));
	if (an.z < 0.5) e = min(e, min(p.z, box_size.z - p.z));
	if (an.y < 0.5) {
		float fy = mod(p.y, cell);
		e = min(e, min(fy, cell - fy));
		e = min(e, box_size.y - p.y);
	}
	float aa = max(fwidth(e), 1e-4);
	float seam = (1.0 - smoothstep(seam_width, seam_width + aa * 1.5, e)) * seam_strength;

	// how much water is behind this pixel, from the depth buffer
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, scene_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
#endif
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	scene_view.xyz /= scene_view.w;
	float thickness = max(VERTEX.z - scene_view.z, 0.0);
	float clarity = exp(-thickness * absorption);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);

	vec3 body = mix(deep_color, shallow_color, clarity);
	vec3 col = mix(body, seam_color, seam);
	ALBEDO = col;
	ROUGHNESS = 0.08;
	SPECULAR = 0.5;
	EMISSION = col * emission_strength;
	ALPHA = clamp(max(max(1.0 - clarity, min_alpha), fresnel) + seam * 0.5, 0.0, 1.0);
}
