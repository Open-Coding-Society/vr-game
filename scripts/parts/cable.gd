extends Node3D
## A cable: a plug at each end and a wire between them. Each plug is a
## GrabbablePart, so the grab layer and the SnapZones treat it like any other
## part: a mission's registry gives each end its type ("hdmi", "usb", "power",
## "ethernet") and a port is a SnapZone that accepts that type.
##
## This script only looks after the wire, stretching it between the two ends
## every frame, and puts the ends where the mission scene wants them.

## Where each plug starts, relative to the cable (meters). Set these on the
## instance; the plugs are moved before they note where their home is.
@export var end_a_position := Vector3(-0.1, 0.0, 0.0)
@export var end_b_position := Vector3(0.1, 0.0, 0.0)
## For a cable that is part of a device, such as a keyboard's: the node the
## wire comes out of. When set, the cable has one plug only (EndB), and EndA
## is taken out.
@export var fixed_end: NodePath
## How far above a plug's origin the wire leaves it (meters).
@export var wire_lift := 0.012

var _from: Node3D
var _to: Node3D

@onready var wire: MeshInstance3D = $Wire


func _enter_tree() -> void:
	# This runs before the plugs' own _ready, which is when a part notes its home.
	var a := get_node_or_null("EndA") as Node3D
	var b := get_node_or_null("EndB") as Node3D
	if a and not fixed_end.is_empty():
		a.free()
	elif a:
		a.position = end_a_position
	if b:
		b.position = end_b_position


func _ready() -> void:
	_from = get_node_or_null(fixed_end) as Node3D if not fixed_end.is_empty() else get_node_or_null("EndA") as Node3D
	_to = get_node_or_null("EndB") as Node3D
	_stretch()


func _process(_delta: float) -> void:
	_stretch()


## The two points the wire runs between, in world space.
func wire_ends() -> Array[Vector3]:
	if _from == null or _to == null:
		return []
	var lift := Vector3(0.0, wire_lift, 0.0)
	return [_from.global_position + lift, _to.global_position + lift]


func _stretch() -> void:
	var ends := wire_ends()
	if ends.is_empty() or ends[0].distance_to(ends[1]) < 0.001:
		wire.visible = false
		return
	wire.visible = true
	# The wire's mesh is a cylinder 1 m tall along its y axis: point y from one
	# end to the other and make it as long as the gap.
	var along := ends[1] - ends[0]
	var up := along.normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	wire.global_transform = Transform3D(Basis(side, along, side.cross(up)), (ends[0] + ends[1]) * 0.5)
