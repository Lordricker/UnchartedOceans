class_name NpcHeadLook
extends SkeletonModifier3D
## Turns an NPC's head (and a little of the neck) towards the player when they come close, on top of whatever the
## idle animation is doing. Add it as a child of the NPC's Skeleton3D and set `npc` to the node that stands for the
## NPC (its +Z axis is the way it faces).
##
## The turn is a yaw about world up, worked out in the skeleton's own space, so it does not matter which way the
## bones were rolled in Blender. Needs bones called "Head" (and optionally "Neck").

@export var max_yaw_deg := 70.0
## Beyond this distance (m), or when the player is behind the NPC, the head goes back to looking ahead.
@export var look_range_m := 6.0
@export var turn_speed := 6.0

var npc: Node3D

var _yaw := 0.0
var _last_frame := -1
var _last_msec := 0
var _head := -2
var _neck := -1


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


## The same thing for engine versions that only call the older name.
func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var frame := Engine.get_frames_drawn()
	if frame == _last_frame:
		return
	_last_frame = frame
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_msec) / 1000.0, 0.0, 0.1)
	_last_msec = now
	var sk := get_skeleton()
	if sk == null or npc == null or not is_instance_valid(npc):
		return
	if _head == -2:
		_head = sk.find_bone("Head")
		_neck = sk.find_bone("Neck")
	if _head < 0:
		return
	var target := 0.0
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var to := cam.global_position - npc.global_position
		var flat := Vector2(to.x, to.z)
		if flat.length() < look_range_m and flat.length() > 0.2:
			var fwd := npc.global_transform.basis.z
			var rel := wrapf(atan2(to.x, to.z) - atan2(fwd.x, fwd.z), -PI, PI)
			if absf(rel) < deg_to_rad(110.0):
				target = clampf(rel, -deg_to_rad(max_yaw_deg), deg_to_rad(max_yaw_deg))
	_yaw = lerpf(_yaw, target, 1.0 - exp(-turn_speed * dt))
	if absf(_yaw) < 0.0005:
		return
	var up_s := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	if _neck >= 0:
		_turn_bone(sk, _neck, up_s, _yaw * 0.35)
		_turn_bone(sk, _head, up_s, _yaw * 0.65)
	else:
		_turn_bone(sk, _head, up_s, _yaw)


func _turn_bone(sk: Skeleton3D, bone: int, up_s: Vector3, angle: float) -> void:
	var g := sk.get_bone_global_pose(bone)
	var new_basis := Basis(up_s, angle) * g.basis
	var parent := sk.get_bone_parent(bone)
	var parent_basis := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(bone, (parent_basis.inverse() * new_basis).orthonormalized().get_rotation_quaternion())
