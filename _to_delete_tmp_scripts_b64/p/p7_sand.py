# Sand grain up close from the shared Poly Haven sand (textures/port/shared/sand_01, the same files the ports use).
import sys
root = sys.argv[1]
def edit(p, pairs):
    p = root + '/' + p
    s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (p, o[:90])
        s = s.replace(o, n)
    open(p, 'w').write(s)
edit('shaders/world_terrain.gdshader', [
("""uniform vec4 patch_rect = vec4(0.0);      // (min x, min z, max x, max z), Godot world; zero size = no patch""",
"""uniform vec4 patch_rect = vec4(0.0);      // (min x, min z, max x, max z), Godot world; zero size = no patch
// sand up close: the shared Poly Haven sand (textures/port/shared/sand_01)
uniform sampler2D sand_detail : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec2 sand_uv_off = vec2(0.0);     // the origin's share of the tiling, worked out on the CPU in 64-bit
uniform float sand_tile_m = 3.0;"""),
("""	rock *= 0.82 + 0.36 * mott;
""", """	rock *= 0.82 + 0.36 * mott;
	// up close (the patch), the real sand's grain and ripples over the regional colour, fading out with distance
	float near_k = patch_layer * (1.0 - smoothstep(40.0, 160.0, length(world_xz - CAMERA_POSITION_WORLD.xz)));
	vec2 suv = world_xz / sand_tile_m + sand_uv_off;
	if (near_k > 0.0) {
		vec3 sd = texture(sand_detail, suv).rgb;
		vec3 sav = textureLod(sand_detail, vec2(0.5), 10.0).rgb;
		sand = mix(sand, sand * clamp(sd / max(sav, vec3(0.05)), 0.55, 1.5), near_k);
	}
"""),
("""	ALBEDO = c;""", """	if (near_k > 0.0 && h > -0.5 && h < 6.0) {
		vec3 nm = texture(sand_normal, suv).xyz * 2.0 - 1.0;
		float nk = near_k * k.x * (1.0 - 0.6 * wet_k);
		vec3 nw = normalize(n_world + vec3(nm.x, 0.0, -nm.y) * 0.5 * nk);
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}
	ALBEDO = c;"""),
])
edit('scripts/world_terrain.gd', [
("""	_patch = MeshInstance3D.new()
""", """	if ResourceLoader.exists(SAND_DIFF):
		_mat.set_shader_parameter("sand_detail", load(SAND_DIFF))
	if ResourceLoader.exists(SAND_NOR):
		_mat.set_shader_parameter("sand_normal", load(SAND_NOR))
	_mat.set_shader_parameter("sand_tile_m", SAND_TILE_M)
	_patch = MeshInstance3D.new()
"""),
("""	_chart = c
	_ox = ox
	_oz = oz
	_vis_t = 0.0
""", """	_chart = c
	_ox = ox
	_oz = oz
	_vis_t = 0.0
	if _mat:
		_mat.set_shader_parameter("sand_uv_off", Vector2(fposmod(ox, SAND_TILE_M), fposmod(oz, SAND_TILE_M)) / SAND_TILE_M)
"""),
("""var _vis_t := 0.0
""", """var _vis_t := 0.0
const SAND_DIFF := "res://textures/port/shared/sand_01_diff_1k.jpg"
const SAND_NOR := "res://textures/port/shared/sand_01_nor_gl_1k.jpg"
const SAND_TILE_M := 3.0
"""),
])
