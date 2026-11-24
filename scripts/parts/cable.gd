extends Node3D
## A cable: a plug at each end and a wire between them. Each plug is a
## GrabbablePart, so the grab layer and the SnapZones treat it like any other
## part: a mission's registry gives each end its type ("hdmi", "usb",
## "ethernet", or "power_plug" and "wall_plug" for the two ends of a power
## cable) and a port is a SnapZone that accepts that type.
##
## This script only looks after the wire, stretching it between the two ends
## every frame, and puts the ends where the mission scene wants them.
##
## It also tells whoever listens (a network mission) when the cable joins two
## ports: `plugged` once both ends are in, `unplugged` when either comes out.

## Both ends are in ports: the cable now joins port_a and port_b (SnapZones).
signal plugged(cable, port_a, port_b)
## One end came out of its port, so the cable no longer joins them.
signal unplugged(cable, port_a, port_b)

## Where each plug starts, relative to the cable (meters). Set these on the
## instance; the plugs are moved before they note where their home is.
@export var end_a_position := Vector3(-0.1, 0.0, 0.0)
@export var end_b_position := Vector3(0.1, 0.0, 0.0)
## For a cable that is part of a device, such as a keyboard's: the node the
## wire comes out of. When set, EndA is taken out and the cable has one plug.
@export var fixed_end: NodePath
## For a cable that is already plugged in: the node its far end stays at. When
## set, EndB is taken out too. With both fixed, the cable is only a wire
## between two nodes, e.g. last mission's HDMI cable still in place.
@export var fixed_end_b: NodePath
## How far above a plug's origin the wire leaves it (meters).
@export var wire_lift := 0.012

var _from: Node3D
var _to: Node3D
## The plugs are put at their start positions the first time only, so a cable
## that leaves the scene tree and comes back keeps its plugs where they are.
var _placed := false
## The ports the two ends are in right now (null when an end is free).
var port_a: Area3D = null
var port_b: Area3D = null

@onready var wire: MeshInstance3D = $Wire


func _enter_tree() -> void:
	if _placed:
		return
	_placed = true
	# This runs before the plugs' own _ready, which is when a part notes its home.
	var a := get_node_or_null("EndA") as Node3D
	var b := get_node_or_null("EndB") as Node3D
	if a and not fixed_end.is_empty():
		a.free()
	elif a:
		a.position = end_a_position
	if b and not fixed_end_b.is_empty():
		b.free()
	elif b:
		b.position = end_b_position


func _ready() -> void:
	_from = get_node_or_null(fixed_end if not fixed_end.is_empty() else NodePath("EndA")) as Node3D
	_to = get_node_or_null(fixed_end_b if not fixed_end_b.is_empty() else NodePath("EndB")) as Node3D
	for end in [get_node_or_null("EndA"), get_node_or_null("EndB")]:
		if end and end.has_signal("installed"):
			end.installed.connect(_on_end_installed)
			end.removed.connect(_on_end_removed)
	_stretch()


## True when both ends are in ports.
func is_plugged() -> bool:
	return port_a != null and port_b != null


func _on_end_installed(end: Node, zone: Area3D) -> void:
	if end.name == "EndA":
		port_a = zone
	else:
		port_b = zone
	if is_plugged():
		plugged.emit(self, port_a, port_b)


func _on_end_removed(end: Node, _zone: Area3D) -> void:
	var was := is_plugged()
	var a := port_a
	var b := port_b
	if end.name == "EndA":
		port_a = null
	else:
		port_b = null
	if was:
		unplugged.emit(self, a, b)


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
