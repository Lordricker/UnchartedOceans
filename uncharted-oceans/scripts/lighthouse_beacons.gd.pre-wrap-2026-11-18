extends Node3D
## Far-reaching lighthouse lights, so a port can be found from the horizon.
##
## A port's own scene only spawns inside 6 km (WorldChart.PORT_SPAWN_M), and its lantern is a 40 m point light, so
## without this nothing at all shows of a port until you are almost there. Here every lighthouse port gets one light
## that is always present in the world, whatever the port's scene is doing: a single warm dot.
##   - Far away it is a small dot on the horizon. It swells and fades as the lamp turns (dark, then bright, then dark
##     again every `period`), so the spin is read from the dot itself, with no beams drawn.
##   - Closer, it grows: its size is the lamp's glare radius seen from here, so it gets bigger the nearer you come.
##   - It shows out to the geometric horizon: 3.57 km x (sqrt(eye height) + sqrt(lamp height)), the same sum
##     WorldChart.horizon_m uses. From deck level a 22 m capital light shows from about 23 km, a 14 m small-port light
##     from about 19 km, and higher up (the lookout barrel) from farther. The sea's curve is applied, so land in the way
##     hides it too.
##   - By day it is just a pale glint (day_strength); at night it is bright. Rain and storm dim it.
##   - Each port turns at its own pace (period), so ports can be told apart by how fast the dot pulses.
## Once the port's scene has spawned, the dot sits on its real lantern (the Blender marker "Light_...Lighthouse...")
## and that lantern's OmniLight3D gets a longer range.
##
## Capitals and small "harbor" ports get one. Ports of other types (lagoons, the free port) do not unless listed in
## extra_ports. lighthouse_offsets says where a lighthouse stands from the port's origin (port frame, Godot metres) for
## the far view, before its scene exists.
##
## Added by world_streamer.gd (beacons_enabled), which sets `streamer`.

@export var streamer: Node
@export var enabled := true
## Strength of the dot at night and by day (0..1).
@export var night_strength := 1.0
@export var day_strength := 0.3
## How dark the dot gets at the dark point of each turn (0 = out, 1 = no pulse).
@export_range(0.0, 1.0) var dark_level := 0.12
## The dot's smallest size on screen, in degrees (a point of light, however far).
@export var dot_deg := 0.12
## The lamp's glare radius in metres. Seen from near, the dot is this big, so it grows as you close in.
@export var glare_m := 5.0
## The dot swells to this much of the glare at the bright point of the turn (it is 0.6 of it at the dark point).
@export var bright_swell := 1.0
## The largest the dot ever gets on screen, in degrees (so it does not become a blob right at the foot of the tower).
@export var max_deg := 2.5
## The eye-shaped flare that flashes as the lamp points at you: its width in degrees (far, near) and how strong it is.
## The flare is the almond-shaped streak across the dot, only at the bright peak of each turn.
@export var flare_far_deg := 1.6
@export var flare_near_deg := 7.0
@export var flare_strength := 1.0
## Where in the turn the flare starts (pulse value, 0..1): higher = a shorter, sharper flash.
@export_range(0.5, 0.98) var flare_from := 0.8
## Seconds per turn: each port gets period_min plus a few seconds of its own.
@export var period_min := 8.0
## Range given to the real lantern's light when its port is loaded (m).
@export var near_light_range_m := 120.0
## Lamp height above the water (m).
@export var capital_lamp_m := 22.0
@export var small_lamp_m := 14.0
@export var extra_ports := PackedStringArray()
@export var lighthouse_offsets := {"AC00": Vector3(80.0, 0.0, 215.0)}

const HORIZON_FADE_M := 800.0

var _items := {}                    # port id -> Dictionary
var _glow_mat: StandardMaterial3D
var _quad: QuadMesh
var _flare_mat: StandardMaterial3D
var _flare_quad: QuadMesh
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
	var flare := MeshInstance3D.new()
	flare.name = "Flare_" + id
	flare.mesh = _flare_quad
	flare.material_override = _flare_mat
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flare.visible = false
	add_child(flare)
	_items[id] = {
		"id": id,
		"x": float(p["x"]),
		"z": float(p["z"]),
		"lamp": capital_lamp_m if capital else small_lamp_m,
		"period": period_min + float(h % 7),
		"phase": float((h / 21) % 100) / 100.0,
		"real": null,
		"searched": false,
		"glow": glow,
		"flare": flare,
	}


func _build_materials() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 0.95, 1.0), Color(1.0, 0.92, 0.7, 0.8),
		Color(1.0, 0.8, 0.5, 0.2), Color(1.0, 0.7, 0.4, 0.0)])
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
	_build_flare()


## The eye: a wide almond (pointed at both ends, fat in the middle) with a hot core, drawn into a texture.
func _build_flare() -> void:
	var w := 256
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var v := (float(y) + 0.5) / float(h) * 2.0 - 1.0
		for x in w:
			var u := (float(x) + 0.5) / float(w) * 2.0 - 1.0
			var au := absf(u)
			# half height of the almond at this x: full in the middle, pointed at the ends
			var hh := pow(maxf(1.0 - au * au, 0.0), 0.9)
			var a := 0.0
			if hh > 0.001:
				var edge := clampf(1.0 - absf(v) / hh, 0.0, 1.0)
				a = pow(edge, 1.4) * pow(maxf(1.0 - au, 0.0), 0.35)
			# the hot core in the middle
			a = maxf(a, exp(-(u * u * 38.0 + v * v * 55.0)))
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_flare_mat = StandardMaterial3D.new()
	_flare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flare_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flare_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flare_mat.billboard_keep_scale = true
	_flare_mat.albedo_texture = tex
	_flare_mat.albedo_color = Color(1.0, 0.93, 0.74, 1.0)
	_flare_mat.disable_fog = true
	_flare_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_flare_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flare_quad = QuadMesh.new()
	_flare_quad.size = Vector2(1.0, 0.25)


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
		var flare: MeshInstance3D = it["flare"]
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
			flare.visible = false
			continue
		# the turn: 0 at the dark point, 1 at the bright point, smooth both ways
		var ph := fposmod(now / float(it["period"]) + float(it["phase"]), 1.0)
		var pulse := 0.5 - 0.5 * cos(TAU * ph)
		pulse = pulse * pulse * (3.0 - 2.0 * pulse)
		var turn := lerpf(dark_level, 1.0, pulse)
		var base := lerpf(day_strength, night_strength, night)
		var haze := lerpf(1.0, 0.55, clampf(d / limit, 0.0, 1.0))
		var k := vis * base * haze * (1.0 - 0.85 * rain) * turn
		glow.visible = k > 0.01
		if glow.visible:
			glow.global_position = pos
			var dist3 := maxf(cp.distance_to(pos), 1.0)
			# size: the lamp's glare seen from here (bigger as you close in), never smaller than a dot; it swells a little as it brightens
			var swell := lerpf(0.6, bright_swell, pulse)
			var deg := clampf(rad_to_deg(atan(glare_m * swell / dist3)), dot_deg, max_deg)
			glow.scale = Vector3.ONE * dist3 * tan(deg_to_rad(deg)) * 2.0
			glow.transparency = 1.0 - clampf(k, 0.0, 1.0)
		# the flash: at the bright peak of the turn (the lamp pointing at you) an eye-shaped flare opens across the dot
		var fk := smoothstep(flare_from, 1.0, pulse) * vis * base * haze * (1.0 - 0.85 * rain) * flare_strength
		flare.visible = fk > 0.01
		if flare.visible:
			flare.global_position = pos
			var dist_f := maxf(cp.distance_to(pos), 1.0)
			var near_t := clampf(1.0 - dist_f / 8000.0, 0.0, 1.0)
			var fdeg := lerpf(flare_far_deg, flare_near_deg, near_t)
			# it opens: a thin slit at first, then the full eye
			var open := smoothstep(flare_from, 1.0, pulse)
			var fw := dist_f * tan(deg_to_rad(fdeg)) * lerpf(0.5, 1.0, open)
			flare.scale = Vector3(fw, fw * lerpf(0.5, 1.0, open), 1.0)
			flare.transparency = 1.0 - clampf(fk, 0.0, 1.0)


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
