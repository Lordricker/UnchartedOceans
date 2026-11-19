class_name ShipRopeRigs
extends Node
## The fixed running rigging of a ship model: lifts, sheets (and braces) that are meshes of the model, tied to a yard at one end and to a
## yard or sail at the other. Put one under the ship's scene root. For every node with the glTF extra game_role = "rope_rig" it
##   * remembers the rope's rest pose and where its far end ("end" = the name of a RopeEnd_* empty) sat at rest,
##   * every frame turns the rope the shortest way from its rest direction to where the end is now (in the rope's parent's space)
##     and stretches it along that direction by the ratio of the lengths.
## So the rope's origin must be its fixed end and it must be a straight tube; the far end follows its RopeEnd_* node, whatever moves it.
## A sheet is hidden while its sail is furled (the sail's shape key "Furled" is the sail's pull-up, see ShipSails).
## The braces are drawn and worked by the game (ship_rope.gd, a pair per mast), so the model's own are hidden when hide_braces is on.

@export var hide_braces := true
## Hide a sheet when its sail has been drawn up this far (0..1).
@export var furled_hide_at := 0.55

class Rig:
	var node: MeshInstance3D
	var end: Node3D
	var rest: Transform3D          ## the rope's transform in its parent at rest
	var rest_dir := Vector3.UP     ## rest direction origin -> end, in the parent's space
	var rest_len := 1.0
	var axis := Vector3.UP         ## the same direction in the rope's own (mesh) space
	var sail: MeshInstance3D
	var furl_idx := -1
	var last := Vector3(1e9, 1e9, 1e9)

var _rigs: Array[Rig] = []

func _ready() -> void:
	process_priority = 100         # after ShipSails has moved the yards
	var root := get_parent()
	for n in root.find_children("Rope_*", "MeshInstance3D", true, false):
		var ex = n.get_meta("extras") if n.has_meta("extras") else {}
		if not (ex is Dictionary) or String(ex.get("game_role", "")) != "rope_rig":
			continue
		var mi := n as MeshInstance3D
		if hide_braces and String(mi.name).begins_with("Rope_Brace"):
			mi.visible = false
			continue
		var end := root.find_child(String(ex.get("end", "")), true, false) as Node3D
		if end == null:
			push_warning("ShipRopeRigs: %s has no end node %s" % [mi.name, ex.get("end", "")])
			continue
		var p := mi.get_parent() as Node3D
		if p == null:
			continue
		var r := Rig.new()
		r.node = mi
		r.end = end
		r.rest = mi.transform
		var e_rest := p.global_transform.affine_inverse() * end.global_position
		var d := e_rest - r.rest.origin
		r.rest_len = d.length()
		if r.rest_len < 0.01:
			continue
		var want := float(ex.get("rope_len", r.rest_len))
		if absf(want - r.rest_len) > 0.15 * want:
			push_warning("ShipRopeRigs: %s is %.2f m between its ends at rest but the model says %.2f m" % [mi.name, r.rest_len, want])
		r.rest_dir = d / r.rest_len
		r.axis = (r.rest.basis.inverse() * r.rest_dir).normalized()
		var ep := end.get_parent() as MeshInstance3D
		if ep != null and String(mi.name).begins_with("Rope_Sheet"):
			r.sail = ep
			r.furl_idx = ep.find_blend_shape_by_name("Furled")
		_rigs.append(r)

func _process(_delta: float) -> void:
	for r in _rigs:
		if not is_instance_valid(r.node) or not is_instance_valid(r.end):
			continue
		if r.sail != null and r.furl_idx >= 0:
			r.node.visible = r.sail.get_blend_shape_value(r.furl_idx) < furled_hide_at
			if not r.node.visible:
				continue
		var p := r.node.get_parent() as Node3D
		var e := p.global_transform.affine_inverse() * r.end.global_position
		if e.is_equal_approx(r.last):
			continue
		r.last = e
		var d := e - r.rest.origin
		var l := d.length()
		if l < 0.01:
			continue
		var rot := Basis(Quaternion(r.rest_dir, d / l))
		var s := l / r.rest_len - 1.0
		var a := r.axis
		# S = 1 + s * a a^T : stretch along the rope's own long axis only
		var st := Basis(Vector3(1.0 + s * a.x * a.x, s * a.x * a.y, s * a.x * a.z),
			Vector3(s * a.y * a.x, 1.0 + s * a.y * a.y, s * a.y * a.z),
			Vector3(s * a.z * a.x, s * a.z * a.y, 1.0 + s * a.z * a.z))
		r.node.transform = Transform3D(rot * r.rest.basis * st, r.rest.origin)
