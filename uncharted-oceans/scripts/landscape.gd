extends RefCounted
## CPU side of landscape.gdshaderinc (the look of open land, shared by the macro terrain and the small ports' plates):
## its textures and the floating origin's share of each tiling.

const LUSH := "res://textures/port/shared/leafy_grass_diff_1k.jpg"
const LUSH_N := "res://textures/port/shared/leafy_grass_nor_gl_1k.jpg"
const DRY := "res://textures/port/shared/sparse_grass_diff_1k.jpg"
const DRY_N := "res://textures/port/shared/sparse_grass_nor_gl_1k.jpg"
const ROCK := "res://assets/world/rocks/Rock_Headland_XL_coastal_cliff_04_diff_1k.jpg"
const FINE_M := 3.5       # LS_FINE_M in the shader
const COARSE_M := 11.0    # LS_COARSE_M


static func apply_textures(mat: ShaderMaterial) -> void:
	for pair in [["ls_lush", LUSH], ["ls_lush_n", LUSH_N], ["ls_dry", DRY], ["ls_dry_n", DRY_N], ["ls_rock", ROCK]]:
		if ResourceLoader.exists(pair[1]):
			mat.set_shader_parameter(pair[0], load(pair[1]))


## ls_uv_off for a floating origin (ox, oz), worked out in 64-bit so the grass never swims when the origin moves.
static func uv_off(ox: float, oz: float) -> Vector4:
	return Vector4(fposmod(ox, FINE_M) / FINE_M, fposmod(oz, FINE_M) / FINE_M,
			fposmod(ox, COARSE_M) / COARSE_M, fposmod(oz, COARSE_M) / COARSE_M)
