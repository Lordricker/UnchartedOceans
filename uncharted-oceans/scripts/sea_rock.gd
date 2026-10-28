class_name SeaRock
extends Node3D
## A big procedural rock standing in the sea, so you can see the ship turn and move against it.
## Pure scenery: no collision (ships and players pass through). ship_motion.gd spawns one near
## the ship's start (test_rock), or drop this script on any Node3D.

## Half-width x/z and half-height of the rock before the noise (metres).
@export var size := Vector3(9.0, 10.0, 7.0)
## Height of the rock's middle above the waterline, so about (centre + size.y) shows above water.
@export var centre_height := 2.0
@export var roughness := 0.3        ## how lumpy (fraction of the radius)
@export var rock_seed := 7

func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 28
	sphere.rings = 14
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = rock_seed
	noise.frequency = 0.9
	noise.fractal_octaves = 3
	var cols := PackedColorArray()
	cols.resize(verts.size())
	for i in verts.size():
		var v := verts[i] * 2.0                      # unit sphere (SphereMesh radius is 0.5)
		var n := 1.0 + roughness * noise.get_noise_3d(v.x * 1.6, v.y * 1.6, v.z * 1.6)
		var p := Vector3(v.x * size.x, v.y * size.y, v.z * size.z) * n
		p.y += centre_height
		verts[i] = p
		# dark wet rock at the waterline, paler dry rock above, a little bird-lime on top
		var h := p.y
		var c := Color(0.3, 0.29, 0.28)
		if h > 1.5:
			c = c.lerp(Color(0.5, 0.48, 0.44), clampf((h - 1.5) / 6.0, 0.0, 1.0))
		if h > size.y * 0.7:
			c = c.lerp(Color(0.72, 0.7, 0.64), clampf((h - size.y * 0.7) / 3.0, 0.0, 0.8))
		cols[i] = c
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.deindex()
	st.generate_normals()                            # flat facets: a chunky stylized rock
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mi.material_override = mat
	add_child(mi)
