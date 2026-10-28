extends Node3D
## Far-reaching lighthouse lights, so a port can be found from the horizon.
##
## A port's own scene only spawns inside 6 km (WorldChart.PORT_SPAWN_M), and its lantern is a 40 m point light, so
## without this nothing at all shows of a port until you are almost there. Here every lighthouse port gets a light
## that is always present in the world, whatever the port's scene is doing:
##   - a warm glow that stays a small, constant size on screen (a point of light, however far) and is visible out to the
##     geometric horizon: 3.57 km x (sqrt(eye height) + sqrt(lamp height)), the same sum WorldChart.horizon_m uses. From
##     deck level a 22 m capital light shows from about 23 km, a 14 m small-port light from about 19 km, and higher up
##     (the lookout barrel) it shows from farther. The sea's curve is applied, so land in the way hides it too.
##   - a turning beam (a long thin ribbon), at night only, visible out to beam_visible_m. The glow flashes each time the
##     beam points at you. Each port turns at its own pace and shows 1 to 3 flashes a turn, so ports can be told apart.
##   - by day the glow is just a pale glint (day_strength); at night it is bright. Rain and storm dim it.
## Once the port's scene has spawned, the beacon sits on its real lantern (the Blender marker "Light_...Lighthouse...")
## and that lantern's OmniLight3D gets a longer range.
##
## Capitals and small "harbor" ports get one. Ports of other types (lagoons, the free port) do not unless listed in
## extra_ports. lighthouse_offsets says where a lighthouse stands from the port's origin (port frame, Godot metres) for
## the far view, before its scene exists.
##
## Added by world_streamer.gd (beacons_enabled), which sets `streamer`.

@export var streamer: Node
@export var enabled := true
## Strength of the glow at night and by day (0..1).
@export var night_strength := 1.0
@export var day_strength := 0.3
## How much of the glow stays on between flashes.
@export_range(0.0, 1.0) var steady_glow := 0.35
## Size of the glow on screen, in degrees: resting, and at the peak of a flash.
@export var glow_deg := 0.3
@export var flash_glow_deg := 0.7
@export var beams_enabled := true
@export var beam_length_m := 5000.0
@export var beam_visible_m := 12000.0
## Range given to the real lantern's light when its port is loaded (m).
@export var near_light_range_m := 120.0
## Lamp height above the water (m).
@export var capital_lamp_m := 22.0
@export var small_lamp_m := 14.0
@export var extra_ports := PackedStringArray()
@export var lighthouse_offsets := {"AC00": Vector3(80.0, 0.0, 215.0)}

const FLASH_SIGMA_DEG := 8.0
const BEAM_SPACING_DEG := 24.0
const HORIZON_FADE_M := 800.0

var _items := {}                    # port id -> Dictionary
var _glow_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
var _quad: QuadMesh
var _beam_mesh: ArrayMesh
var _sky: Node = null
var _sky_t := 0.0


func _ready() -> void:
	if streamer == null or not enabled or streamer.chart == null:
		set_process(false)
		return
	_build_materials()
	var ports: Array = streamer.chart.ports
	for p in ports:
		if _wants(p):
			_make_item(p)


func _wants(p: Dictionary) -> bool:
	var id := String(p["id"])
	if extra_ports.has(id):
		return true
	var tier := String(p["tier"])
	if tier == "capital":
		return true
	return tier == "small" and String(p["type"]) == "harbor"


func _make_item(p: Dictionary) -> void:
	var id := String(p["id"])
	var h: int = absi(hash(id))
	var capital := String(p["tier"]) == "capital"
	var glow := MeshInstance3D.new()
	glow.name = "Glow_" + id
	glow.mesh = _quad
	glow.material_override = _glow_mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.visible = false
	add_child(glow)
	var groups: int = 1 + (h / 7) % 3
	var rig := Node3D.new()
	rig.name = "Beams_" + id
	rig.visible = false
	for j in groups:
		var b := MeshInstance3D.new()
		b.mesh = _beam_mesh
		b.material_override = _beam_mat
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.rotation.y = -deg_to_rad(BEAM_SPACING_DEG) * float(j)
		rig.add_child(b)
	add_child(rig)
	_items[id] = {
		"id": id,
		"x": float(p["x"]),
		"z": float(p["z"]),
		"lamp": capital_lamp_m if capital else small_lamp_m,
		"period": 8.0 + float(h % 7),
		"groups": groups,
		"phase": float((h / 21) % 100) / 100.0,
		"real": null,
		"searched": false,
		"glow": glow,
		"rig": rig,
	}


func _build_materials() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 0.95, 0.8, 0.85),
		Color(1.0, 0.8, 0.5, 0.25), Color(1.0, 0.7, 0.4, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glow_mat.billboard_keep_scale = true
	_glow_mat.albedo_texture = tex
	_glow_mat.albedo_color = Color(1.0, 0.86, 0.56, 1.0)
	_glow_mat.disable_fog = true
	_glow_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad = QuadMesh.new()
	_quad.size = Vector2(1.0, 1.0)

	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.vertex_color_use_as_albedo = true
	_beam_mat.albedo_color = Color(1.0, 0.88, 0.6, 1.0)
	_beam_mat.disable_fog = true
	_beam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mesh = _build_beam_mesh()


## One beam: two thin ribbons (one flat, one upright) running out along -Z from the lamp, widening and fading away.
func _build_beam_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plane in 2:
		var a := Vector3.RIGHT if plane == 0 else Vector3.UP
		var far := Vector3(0.0, 0.0, -beam_length_m)
		var vs: Array[Vector3] = [-a * 0.6, a * 0.6, a * 60.0 + far, -a * 60.0 + far]
		var cs: Array[Color] = [Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0), Color(1, 1, 1, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(cs[idx])
			st.add_vertex(vs[idx])
	return st.commit()


func _process(delta: float) -> void:
	if streamer == null or streamer.chart == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp: Vector3 = cam.global_position
	var eye := maxf(cp.y, 1.5)
	var radius := 6370000.0
	var ocean = streamer._ocean
	if ocean != null:
		radius = float(ocean.curvature_radius_m)
	var kh := sqrt(2.0 * radius)
	var night := _night_amount(delta)
	var rain := _rain_amount()
	var now := Time.get_ticks_msec() * 0.001
	var ox: float = streamer.origin_x
	var oz: float = streamer.origin_z
	for id in _items:
		var it: Dictionary = _items[id]
		var glow: MeshInstance3D = it["glow"]
		var rig: Node3D = it["rig"]
		var lamp_h: float = it["lamp"]
		var pos: Vector3
		var real := _real_lamp(it)
		if real != null:
			pos = real.global_position + Vector3(0.0, 0.4, 0.0)
		else:
			var sx: float = float(it["x"]) - ox
			var sz: float = float(it["z"]) - oz
			if lighthouse_offsets.has(id) and streamer.port_scenes.has(id):
				var o: Vector3 = Basis(Vector3.UP, float(streamer.port_yaw(id))) * (lighthouse_offsets[id] as Vector3)
				sx += o.x
				sz += o.z
			var dh := Vector2(cp.x - sx, cp.z - sz).length()
			# the sea curves away: the lamp sits that much lower, as it would seen from here
			pos = Vector3(sx, lamp_h - dh * dh / (2.0 * radius), sz)
		var d := Vector2(cp.x - pos.x, cp.z - pos.z).length()
		var limit := kh * (sqrt(eye) + sqrt(lamp_h))
		var vis := clampf((limit - d) / HORIZON_FADE_M, 0.0, 1.0)
		if vis <= 0.0:
			glow.visible = false
			rig.visible = false
			continue
		# where the beam points, and whether it points at the camera right now
		var period: float = it["period"]
		var yaw0 := TAU * fposmod(now / period + float(it["phase"]), 1.0)
		var to_cam := Vector2(cp.x - pos.x, cp.z - pos.z)
		var flash := 1.0
		if to_cam.length() > 1.0:
			flash = 0.0
			var dir_c := to_cam.normalized()
			for j in int(it["groups"]):
				var yj := yaw0 - deg_to_rad(BEAM_SPACING_DEG) * float(j)
				var bd := Vector2(-sin(yj), -cos(yj))
				var ang := rad_to_deg(acos(clampf(bd.dot(dir_c), -1.0, 1.0)))
				flash = maxf(flash, exp(-pow(ang / FLASH_SIGMA_DEG, 2.0)))
		var base := lerpf(day_strength, night_strength, night)
		var haze := lerpf(1.0, 0.55, clampf(d / limit, 0.0, 1.0))
		var k := vis * base * haze * (1.0 - 0.85 * rain)
		var gk := k * (steady_glow + (1.0 - steady_glow) * flash)
		glow.visible = gk > 0.01
		if glow.visible:
			glow.global_position = pos
			var dist3 := cp.distance_to(pos)
			var deg := lerpf(glow_deg, flash_glow_deg, flash)
			glow.scale = Vector3.ONE * maxf(dist3 * tan(deg_to_rad(deg)), 0.6)
			glow.transparency = 1.0 - clampf(gk, 0.0, 1.0)
		var show_beam := beams_enabled and night > 0.05 and d < beam_visible_m
		rig.visible = show_beam
		if show_beam:
			rig.global_position = pos
			rig.rotation.y = yaw0
			var bt := clampf(night * vis * (1.0 - 0.85 * rain), 0.0, 1.0) * 0.8
			for m in rig.get_children():
				(m as MeshInstance3D).transparency = 1.0 - bt


## The real lantern marker in the port's scene, once that port has spawned (null before, or if it has none).
func _real_lamp(it: Dictionary) -> Node3D:
	var r = it["real"]
	if r != null and is_instance_valid(r):
		return r as Node3D
	it["real"] = null
	var port = streamer._ports.get(it["id"])
	if port == null or not is_instance_valid(port):
		it["searched"] = false
		return null
	if it["searched"]:
		return null
	it["searched"] = true
	for c in port.find_children("*", "Node3D", true, false):
		var n := String(c.name).to_lower()
		if n.begins_with("light") and n.contains("lighthouse"):
			it["real"] = c
			var l := (c as Node).get_node_or_null("Light") as OmniLight3D
			if l != null:
				l.omni_range = maxf(l.omni_range, near_light_range_m)
				l.distance_fade_begin = maxf(l.distance_fade_begin, 400.0)
				l.distance_fade_length = 100.0
				l.shadow_enabled = false
			return c as Node3D
	return null


## 1 in the dark, 0 in daylight: from the sky system's sun if there is one, else the weather's clock.
func _night_amount(delta: float) -> float:
	if _sky == null or not is_instance_valid(_sky):
		_sky = null
		_sky_t -= delta
		if _sky_t <= 0.0:
			_sky_t = 1.0
			var scene := get_tree().current_scene
			if scene != null:
				_sky = scene.find_child("SkySystem", true, false)
	if _sky != null and _sky.has_method("sun_elevation_deg"):
		var e: float = _sky.sun_elevation_deg()
		return 1.0 - smoothstep(-6.0, 3.0, e)
	var wx := get_tree().get_first_node_in_group("weather")
	if wx != null and wx.has_method("hour_of_day"):
		var hr: float = wx.hour_of_day()
		if hr < 12.0:
			return 1.0 - smoothstep(5.0, 7.0, hr)
		return smoothstep(17.5, 19.5, hr)
	return 0.7


func _rain_amount() -> float:
	var wx := get_tree().get_first_node_in_group("weather")
	if wx != null and wx.has_method("rain_at_ship"):
		return clampf(float(wx.rain_at_ship()), 0.0, 1.0)
	return 0.0
