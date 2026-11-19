class_name ShipLadder
extends Area3D
## Climbing zone. Give it a CollisionShape3D child with a BoxShape3D and size/move that box in
## the editor to cover where you can climb. While the player's centre is inside the box:
##   W climbs up, S climbs down, A/D shift sideways, Space jumps off (away from the ship).
## You're on the ladder while any part of you (feet to head) is in the box, so line the TOP of
## the box up with the top of the rail: when your feet climb past it, W walks forward again.
## Orientation: the node's green arrow (+Y) is "up the ladder" and its blue arrow (+Z) must
## point AWAY from the ship.
## The box's width and height matter most. Its depth only needs to touch where the player swims
## or stands next to the ladder: once climbing, you stay on it even if the hull's shape pushes
## you out past the box (up to depth_slack). Outside the box W walks forward as usual, so line
## the top of the box up with the rail: climb out the top facing the ship and you step over.
## Put it under the ship so it moves with it. It doesn't block or detect anything by itself;
## player.gd checks whether it's inside the box.

@export var climb_speed := 1.6
## Sideways speed (A/D) as a fraction of climb_speed.
@export_range(0.0, 1.0, 0.05) var side_speed := 0.6
## How far in/out you rock per rung while climbing (looks like stepping rung to rung).
@export_range(0.0, 0.1, 0.005) var rung_bob := 0.03
@export var rung_spacing := 0.3
## Extra depth (in/out of the hull) you can be off the box and still grab / stay on.
@export var grab_slack := 0.35
@export var depth_slack := 1.0
## Draw the climber in to the middle of the box's depth as they climb (rope ladders: the shrouds and the mast
## ladder) instead of keeping the depth they grabbed it at. ShipRigging sets this for the ladders it builds.
@export var snap_depth := false
## Pull the climber onto the middle of the box's width as soon as they grab it, and keep them there (A/D do nothing).
## For the hull ladders, which are one rung wide: grabbing at the edge of the box used to bounce you in and out of it.
## The wide rope nets (the shrouds) turn this off (ship_rigging.gd) so you can still shift along them.
@export var center_on_grab := true
## true: the ladder is ashore (a quay or pier ladder), so the climber is not carried along by the ship's motion.
## world_streamer.gd sets this for the ladders it builds on the ports' quay walls.
@export var fixed := false
## Optional: make this zone one of a ship's rigging climbs (ship_rigging.gd). "shroud_a" / "shroud_b" are the two nets (when you reach the
## top of one you are taken to the perch, the Climb_Barrel point; "mast" is the rung ladder up a mast). Leave empty for an ordinary ladder:
## any Area3D with this script and a BoxShape3D child works on its own, you only have to touch it.
@export var rigging_id := ""
## Which mast the rigging climb belongs to ("main" or "fore").
@export var rigging_mast := "main"

func _ready() -> void:
	add_to_group("ship_ladders")
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0

func _box() -> CollisionShape3D:
	for c in get_children():
		var cs := c as CollisionShape3D
		if cs and not cs.disabled and cs.shape is BoxShape3D:
			return cs
	return null

## The middle of the box, in world space.
func center_world() -> Vector3:
	var cs := _box()
	return cs.global_position if cs else global_position

## World point p in the box's own space (centre of the box = origin).
func local_point(p: Vector3) -> Vector3:
	var cs := _box()
	return cs.global_transform.affine_inverse() * p if cs else Vector3.INF

func half_size() -> Vector3:
	var cs := _box()
	return (cs.shape as BoxShape3D).size * 0.5 if cs else Vector3.ZERO

## True if a body standing from world point feet to head overlaps the box: centre within the
## box's width (and depth, plus z_slack), and any part of the body within its height.
func body_in_box(feet: Vector3, head: Vector3, z_slack := 0.0) -> bool:
	var cs := _box()
	if cs == null:
		return false
	var inv := cs.global_transform.affine_inverse()
	var f := inv * feet
	var t := inv * head
	var c := (f + t) * 0.5
	var h := (cs.shape as BoxShape3D).size * 0.5
	return absf(c.x) <= h.x and absf(c.z) <= h.z + z_slack \
		and minf(f.y, t.y) <= h.y and maxf(f.y, t.y) >= -h.y

## True if world point p is inside the box, allowing z_slack extra depth either way.
func contains(p: Vector3, z_slack := 0.0) -> bool:
	var cs := _box()
	if cs == null:
		return false
	var lp := cs.global_transform.affine_inverse() * p
	var h := (cs.shape as BoxShape3D).size * 0.5
	return absf(lp.x) <= h.x and absf(lp.y) <= h.y and absf(lp.z) <= h.z + z_slack
