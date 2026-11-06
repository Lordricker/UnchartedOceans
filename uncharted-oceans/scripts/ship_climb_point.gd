class_name ShipClimbPoint
extends Marker3D
## A spot the rigging climb puts you at (ship_rigging.gd): place it in the ship's scene and move it where you want.
##   barrel      where you stand at the top of the nets (the perch / lookout); the script moves you a little toward the bow
##   shroud_top_a / shroud_top_b   where you are put back on the port / starboard net when you leave the perch
##   mast_base / nest_exit         the brig's mast-ladder stages (not needed without a mast ladder)
## Ship frame: bow is -Z, +X is starboard.

@export var point_id := "barrel"
@export var mast := "main"

func _ready() -> void:
	add_to_group("role_climb_point")
	set_meta("extras", {"point_id": point_id, "mast": mast})
