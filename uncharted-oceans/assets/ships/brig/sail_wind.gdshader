// Sail / flag cloth for Brig.glb, lit like the rest of the ship (PBR, stylized-realistic).
//
// COLOR (glTF COLOR_0 "PinWeights", exported from Blender):
//   r = billow / flutter weight (0 where the cloth is held, 1 at the free belly)
//   g = height down the sail (0 head .. 1 foot)     b = position across the sail (0..1)
// For flags r is the distance from the hoist (0 at the pole, 1 at the fly).
//
// The meshes are modelled with the sail full of wind: the belly bulges along billow_dir by
// belly_depth. ShipSails (scripts/ship_sails.gd) drives, per sail:
//   fill  1 = the shape as modelled (full), 0 = slack and flat, -1 = belly pushed through the
//         other way (sail aback: the wind is on the front of it)
//   luff  0..1  the sail shaking because it is not filled (too close to the wind, eased too far)
//   gust  0..1  small extra shiver in a gusty breeze
//   slack 0..1  how much of the cloth is hanging free (0 = furled to the yard, no flutter)
// The Furled / Reefed blend shapes on the mesh are applied before this runs.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 billow_dir = vec3(0.0, 0.0, 1.0);   // mesh-local direction the belly pushes (local +Z = bow)
uniform float belly_depth = 0.5;                  // metres between the held edge and the belly's peak
uniform float fill = 1.0;
uniform float luff = 0.0;
uniform float gust = 0.0;
uniform float slack = 1.0;
uniform float flutter_amp = 0.035;                // metres, base shiver of a filled sail
uniform float flutter_speed = 6.0;
uniform float cloth_roughness = 0.92;
uniform float translucency = 0.10;                // sun glowing through the canvas
uniform vec3 tint : source_color = vec3(0.93, 0.92, 0.9);

void vertex() {
	float w = COLOR.r;
	float belly = (fill - 1.0) * w * belly_depth;
	float t = TIME * flutter_speed * (1.0 + luff * 0.8);
	float ph = COLOR.b * 9.0 + COLOR.g * 5.0;
	float wave = sin(t + ph) * 0.6 + sin(t * 1.73 + ph * 1.9 + 1.3) * 0.4;
	float amp = (flutter_amp + gust * 0.04 + luff * 0.30) * slack;
	VERTEX += normalize(billow_dir) * (belly + wave * amp * w);
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * tint;
	ROUGHNESS = cloth_roughness;
	SPECULAR = 0.15;
	BACKLIGHT = ALBEDO * translucency;
	// Cloth that has been pushed around has no baked normal to trust: lean on the face normal.
	vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(fn, NORMAL) < 0.0) fn = -fn;
	float moved = clamp(abs(fill - 1.0) * 0.5 + luff, 0.0, 1.0);
	NORMAL = normalize(mix(NORMAL, fn, moved * 0.6));
	if (!FRONT_FACING) NORMAL = -NORMAL;       // both sides of the cloth are lit
}
