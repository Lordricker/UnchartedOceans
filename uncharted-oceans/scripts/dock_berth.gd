class_name DockBerth
extends Node3D
## One berth on a pier. Put one beside each place a ship can lie.
##
## Its frame: the origin is the point on the pier's face at the middle of the berth (at sea level).
## Local +X points away from the pier, which is the docked ship's starboard side (the ships lie port side to
## the pier). Local -Z is the way the docked ship points. berth_heading sets that turn, in ship heading
## degrees (0 = north, 90 = west).
##
## Four shafts of light stand up out of the water at the corners of the docking zone (two just off the pier's
## face, two on the open-water side). The zone is sized for the ship that is sailing (ShipClasses), always quite
## a bit bigger than the hull, and the shafts fade in as the ship comes near. They are amber until the ship is
## inside the zone, slow enough and lined up (green: press E, ship_harbor.gd). Once the ship is moored they fade
## out. ship_harbor.gd drives the docking itself; this node does the geometry and the light.

## Biggest ship class this berth takes (ShipClasses.Size). Smaller ships fit too.
@export_enum("Small", "Medium", "Large") var max_ship_class := 1
## Gap kept between the hull and the pier's face (the fenders), metres.
@export var gap := 0.25
@export_range(0.0, 360.0) var berth_heading := 0.0
## The light shows up inside this distance (m) and fades in over the outer 40 m.
@export var show_distance := 130.0
## A berth on a port scene (made by world_streamer.gd) turns with its port: its heading is read from the way the node
## faces every tick, instead of being set once.
@export var follow_parent_yaw := false
## Height of the quay deck above the water (m): the mooring bollards stand on it.
@export var deck_y := 1.85
## The light shafts: how tall and how wide (m).
@export var shaft_height := 10.0
@export var shaft_width := 1.4
## The outline of the zone: a thin curtain of light round its edge, this tall (m), brightest at the water.
@export var curtain_height := 4.0

var _holder: Node3D
var _shafts: Array[MeshInstance3D] = []
var _mat: ShaderMaterial
var _curtain: MeshInstance3D
var _curtain_mat: ShaderMaterial
var _fade := 0.0
var _ready_amt := 0.0
var _want_fade := 0.0
var _want_ready := 0.0
var _zone_class := -1
var _ocean: Ocean
var _ocean_searched := false

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.78, 0.3);
uniform vec3 ready_tint : source_color = vec3(0.35, 1.0, 0.5);
uniform float strength = 1.0;
uniform float ready_amt = 0.0;
void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;                          // 0 on the shaft's axis, 1 at its edge
	float core = pow(clamp(1.0 - x, 0.0, 1.0), 1.6);
	float h = UV.y;                                            // 0 at the water, 1 at the top
	float fade = (1.0 - smoothstep(0.15, 1.0, h)) * smoothstep(0.0, 0.04, h);
	float streak = 0.8 + 0.2 * sin(h * 24.0 - TIME * 2.5);     // the light drifts upward
	float pulse = 0.88 + 0.12 * sin(TIME * 2.2);
	vec3 col = mix(tint, ready_tint, ready_amt);
	ALBEDO = col;
	ALPHA = clamp(core * fade * streak * pulse * strength * 1.3, 0.0, 1.0);
}
"""

## The outline: an open box of four upright walls, bright along the water and fading upward. Nothing inside it.
const CURTAIN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.78, 0.3);
uniform vec3 ready_tint : source_color = vec3(0.35, 1.0, 0.5);
uniform float strength = 1.0;
uniform float ready_amt = 0.0;
void fragment() {
	float h = UV.y;                                            // 0 at the water, 1 at the top
	float base = exp(-h * 9.0);                                // a bright line along the water
	float up = pow(1.0 - smoothstep(0.0, 1.0, h), 1.5) * 0.35; // a faint veil above it
	float pulse = 0.88 + 0.12 * sin(TIME * 2.2);
	ALBEDO = mix(tint, ready_tint, ready_amt);
	ALPHA = clamp((base * 0.8 + up) * pulse * strength, 0.0, 1.0);
}
"""

func _ready() -> void:
	add_to_group("dock_berths")
	if follow_parent_yaw:
		_read_heading()
	else:
		rotation.y = deg_to_rad(berth_heading)
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_mat.render_priority = 64        # the sea is see-through too: draw the light after it, on top
	_holder = Node3D.new()
	_holder.name = "DockZoneLight"
	_holder.visible = false
	add_child(_holder)
	var mesh := _shaft_mesh()
	for i in 4:
		var mi := MeshInstance3D.new()
		mi.name = "Shaft%d" % i
		mi.mesh = mesh
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 20.0
		_holder.add_child(mi)
		_shafts.append(mi)
	_curtain_mat = ShaderMaterial.new()
	var csh := Shader.new()
	csh.code = CURTAIN_SHADER
	_curtain_mat.shader = csh
	_curtain_mat.render_priority = 64
	_curtain = MeshInstance3D.new()
	_curtain.name = "Outline"
	_curtain.mesh = _outline_mesh()
	_curtain.material_override = _curtain_mat
	_curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_curtain.extra_cull_margin = 40.0
	_holder.add_child(_curtain)

## A unit outline: four upright walls round the square x, z in -0.5..0.5, one unit tall (scaled to the zone when placed).
## UV.y runs 0 (water) to 1 (top).
func _outline_mesh() -> ArrayMesh:
	var corners := [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var base := verts.size()
		verts.append(Vector3(a.x, 0.0, a.y))
		verts.append(Vector3(b.x, 0.0, b.y))
		verts.append(Vector3(b.x, 1.0, b.y))
		verts.append(Vector3(a.x, 1.0, a.y))
		uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## One shaft: two upright quads crossing at right angles, so it reads from every side. UV.y runs 0 (water) to 1 (top).
func _shaft_mesh() -> ArrayMesh:
	var hw := shaft_width * 0.5
	var h := shaft_height
	var verts := PackedVector3Array([
		Vector3(-hw, 0.0, 0.0), Vector3(hw, 0.0, 0.0), Vector3(hw, h, 0.0), Vector3(-hw, h, 0.0),
		Vector3(0.0, 0.0, -hw), Vector3(0.0, 0.0, hw), Vector3(0.0, h, hw), Vector3(0.0, h, -hw)])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

# ------------------------------------------------------------------ geometry (world xz)

func forward2() -> Vector2:
	var y := deg_to_rad(berth_heading)
	return Vector2(-sin(y), -cos(y))

func right2() -> Vector2:
	var y := deg_to_rad(berth_heading)
	return Vector2(cos(y), -sin(y))

## Heading in ship degrees (0 = north, grows to port) of the way this node's -Z points in the world.
func _read_heading() -> void:
	var f := -global_transform.basis.z
	berth_heading = fposmod(rad_to_deg(atan2(-f.x, -f.z)), 360.0)

func _physics_process(_delta: float) -> void:
	if follow_parent_yaw:
		_read_heading()

## The four mooring bollards on the pier's face, from the bow end to the stern end (ship_harbor.gd sends its four
## lines to these in order). Local +X points away from the pier, so they stand a little to the -X side of the origin.
func bollards_world() -> PackedVector3Array:
	var out := PackedVector3Array()
	for along in [9.0, 3.0, -3.0, -9.0]:
		out.append(to_global(Vector3(-0.35, deck_y + 0.5, -along)))
	return out

## Where the docked ship's origin rests, for a ship of this class. A class can ask to lie further out (slot_offset in
## ShipClasses, e.g. the cutter on the outer edge of the light so its gangway is gentler).
func slot_position(cls: int) -> Vector3:
	var d := ShipClasses.data(cls)
	var r := right2() * (float(d.beam) * 0.5 + gap + float(d.get("slot_offset", 0.0)))
	return global_position + Vector3(r.x, 0.0, r.y)

## How a ship stands against the berth. lat / along are the centre's offsets from the slot (m):
## lat > 0 = too far from the pier, along > 0 = too far aft (still has to go forward).
## out_lat / out_fwd are how far the hull sticks out of the zone sideways / lengthways (<= 0 = inside).
func evaluate(ship_pos: Vector3, heading_deg: float, speed: float, cls: int) -> Dictionary:
	var d := ShipClasses.data(cls)
	var zone := ShipClasses.zone_size(cls)
	var slot := slot_position(cls)
	var f2 := forward2()
	var r2 := right2()
	var rel := Vector2(ship_pos.x - slot.x, ship_pos.z - slot.z)
	var lat := rel.dot(r2)
	var along := -rel.dot(f2)
	var dh := fposmod(heading_deg - berth_heading + 180.0, 360.0) - 180.0
	# the hull as a rectangle: are all four corners inside the zone?
	var h := deg_to_rad(heading_deg)
	var sf := Vector2(-sin(h), -cos(h))
	var sr := Vector2(cos(h), -sin(h))
	var hb := float(d.beam) * 0.5
	var hl := float(d.length) * 0.5
	var out_lat := -1.0e9
	var out_fwd := -1.0e9
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c: Vector2 = Vector2(ship_pos.x, ship_pos.z) + sr * (sx * hb) + sf * (sz * hl) - Vector2(slot.x, slot.z)
			out_lat = maxf(out_lat, absf(c.dot(r2)) - zone.x * 0.5)
			out_fwd = maxf(out_fwd, absf(c.dot(f2)) - zone.y * 0.5)
	var inside := out_lat <= 0.0 and out_fwd <= 0.0
	var speed_ok := speed <= float(d.max_speed)
	var heading_ok := absf(dh) <= float(d.max_heading)
	return {
		"lat": lat, "along": along, "heading": dh, "speed": speed,
		"out_lat": out_lat, "out_fwd": out_fwd,
		"inside": inside, "speed_ok": speed_ok, "heading_ok": heading_ok,
		"max_speed": float(d.max_speed), "max_heading": float(d.max_heading),
		"ok": inside and speed_ok and heading_ok,
	}

# ------------------------------------------------------------------ the light

## Called every physics tick by ship_harbor.gd. ready = the ship could moor right now.
func set_light(ship_pos: Vector3, cls: int, can_dock: bool, moored: bool) -> void:
	var slot := slot_position(cls)
	var dist := Vector2(ship_pos.x - slot.x, ship_pos.z - slot.z).length()
	var fits := ShipClasses.berth_class(cls) <= max_ship_class
	if moored or not fits:
		_want_fade = 0.0
	else:
		_want_fade = clampf((show_distance - dist) / 40.0, 0.0, 1.0)
	_want_ready = 1.0 if can_dock else 0.0
	_zone_class = cls

## Only the nearest berth shows its light; ship_harbor.gd tells the others to go dark.
func hide_light() -> void:
	_want_fade = 0.0
	_want_ready = 0.0

func _process(delta: float) -> void:
	_fade = move_toward(_fade, _want_fade, delta * 1.5)
	_ready_amt = move_toward(_ready_amt, _want_ready, delta * 4.0)
	var lit := _fade > 0.01 and _zone_class >= 0
	_holder.visible = lit
	if not lit:
		return
	_mat.set_shader_parameter("strength", _fade)
	_mat.set_shader_parameter("ready_amt", _ready_amt)
	_curtain_mat.set_shader_parameter("strength", _fade)
	_curtain_mat.set_shader_parameter("ready_amt", _ready_amt)
	if _ocean == null and not _ocean_searched:
		_ocean_searched = true
		var found := get_tree().root.find_children("*", "Ocean", true, false)
		if found.size() > 0:
			_ocean = found[0] as Ocean
	# the corners of the zone: the two near the pier stand on the water just off its face, the other two on the open side
	var d := ShipClasses.data(_zone_class)
	var zone := ShipClasses.zone_size(_zone_class)
	var x_pier := 0.35
	var x_open := float(d.beam) * 0.5 + gap + zone.x * 0.5
	var i := 0
	for lx: float in [x_pier, x_open]:
		for lz: float in [-zone.y * 0.5, zone.y * 0.5]:
			var g := to_global(Vector3(lx, 0.0, lz))
			var y := (_ocean.get_height(g.x, g.z) if _ocean else 0.0) - 0.4
			_shafts[i].global_position = Vector3(g.x, y, g.z)
			i += 1
	# the outline joins the four shafts: an open box from the pier's face to the open side, as long as the zone
	var mid := to_global(Vector3((x_pier + x_open) * 0.5, 0.0, 0.0))
	var ym := (_ocean.get_height(mid.x, mid.z) if _ocean else 0.0) - 0.4
	var local_mid := to_local(Vector3(mid.x, ym, mid.z))
	_curtain.transform = Transform3D(Basis.from_scale(Vector3(x_open - x_pier, curtain_height, zone.y)), local_mid)
