extends RigidBody3D
## A part the player can pick up and drop: a RAM stick, a CPU, a network cable...
##
## VR rule 7: this node holds the logic and a simple collision shape, and the
## visual mesh is a child, so swapping in a real model only replaces that child.
## VR rule 8: the node's origin is the snap point (e.g. the bottom edge of a RAM
## stick), so a SnapZone can place it by matching transforms.
##
## The part never knows what is moving it. A grabber (mouse now, controllers or
## hands later) calls grab(), moves the part, then calls drop().
##
## SnapZones tell the part when it is over them. On drop() the part asks one
## zone to judge it: a zone that takes this type, if it's over one, otherwise
## the nearest zone (which turns it away). One drop is one decision, even when
## a big part like a keyboard covers several slots at once.

const PartsCatalog := preload("res://scripts/parts/parts_catalog.gd")

## Emitted by drop(), before a zone judges the part.
signal dropped(part)
## Emitted when a SnapZone accepts the part.
signal installed(part, zone)
## Emitted when the part leaves the zone it was installed in: pulled out of a
## removable slot, swapped for another part, or sent home.
signal removed(part, zone)

## What kind of part this is. A SnapZone accepts parts whose type matches its own.
@export var part_type: StringName = &"ram"
## The name shown to students in hints and on the success panel.
@export var display_name: String = "RAM stick"
## For a part that comes in several versions: its id in data/parts_catalog.json
## (e.g. "cpu_mid"). The catalog then gives the part its type, its name, the
## text of its Name label and its tier's colour, and `spec` holds its specs.
@export var variant: String = ""

## The part's catalog entry ({} for a part with no variant).
var spec: Dictionary = {}

var is_held := false
var is_installed := false
## The SnapZone the part is installed in (null when it isn't).
var installed_zone: Area3D = null
## Where the part goes back to when it's dropped somewhere that isn't its slot.
var home_transform: Transform3D
## SnapZones the part is over right now (they add and remove themselves).
var zones_under: Array[Area3D] = []


func _ready() -> void:
	# Kinematic: parts never fall or tumble. Dropping one outside a slot sends it
	# home instead, so nothing ends up on the floor out of reach (VR rule 2).
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	home_transform = global_transform
	if variant != "":
		apply_variant()


## Makes the part the catalog's `variant`: type, name, label and tier colour.
func apply_variant() -> void:
	spec = PartsCatalog.shared().spec(variant)
	if spec.is_empty():
		push_error('%s: "%s" isn\'t a part in data/parts_catalog.json' % [name, variant])
		return
	part_type = StringName(spec.type)
	display_name = spec.name
	var tag := get_node_or_null("Name") as Label3D
	if tag:
		tag.text = spec.name
	var tint := StandardMaterial3D.new()
	tint.albedo_color = PartsCatalog.TIER_COLORS[spec.tier]
	tint.roughness = 0.8
	var mesh := get_node_or_null("Mesh")
	if mesh:
		for piece in [mesh] + mesh.find_children("*", "MeshInstance3D", true, false):
			if piece is MeshInstance3D:
				piece.material_override = tint


func can_grab() -> bool:
	if is_held:
		return false
	# An installed part stays put, unless its slot lets it be pulled out again.
	return not is_installed or (installed_zone != null and installed_zone.can_remove(self))


## Where a hand reaches for the part: its origin, or a child Marker3D named
## GrabPoint, for a big part whose origin (its snap point) is at one edge.
func grab_position() -> Vector3:
	var point := get_node_or_null("GrabPoint") as Node3D
	return point.global_position if point else global_position


func grab() -> bool:
	if not can_grab():
		return false
	if is_installed:
		# Pulled out of a removable slot: the slot is empty again.
		installed_zone.remove(self)
	is_held = true
	return true


## Lets go of the part. SnapZones it is over get the chance to take it;
## if none does, it goes back home.
func drop() -> void:
	if not is_held:
		return
	is_held = false
	dropped.emit(self)
	var zone := zone_for_drop()
	if zone:
		zone.judge(self)
	if not is_installed:
		return_home()


## The one zone that decides about this drop, or null when over none:
## the nearest zone that takes this part, else the nearest zone at all.
func zone_for_drop() -> Area3D:
	var taking := zones_under.filter(func(z) -> bool: return z.can_take(self))
	var pool := taking if not taking.is_empty() else zones_under
	var best: Area3D = null
	for zone in pool:
		if best == null or _distance_to(zone) < _distance_to(best):
			best = zone
	return best


func _distance_to(zone: Area3D) -> float:
	return global_position.distance_to(zone.snap_transform().origin)


func return_home() -> void:
	global_transform = home_transform


## Puts the part somewhere new and makes that its home, still free to grab.
## Used by pass-through zones (data moving from one stage to the next).
func move_home(at: Transform3D) -> void:
	global_transform = at
	home_transform = at


## Called by the SnapZone that accepted the part.
func install(zone: Node3D, at: Transform3D) -> void:
	global_transform = at
	is_installed = true
	installed_zone = zone
	installed.emit(self, zone)


## Called by a SnapZone that gives the part up (it was swapped for another):
## the part is free again and goes back where it came from.
func uninstall() -> void:
	_leave_zone()
	return_home()


## Called by a removable SnapZone as the player pulls the part out: free
## again, and still in the hand (it doesn't jump home).
func pull_out() -> void:
	_leave_zone()


func _leave_zone() -> void:
	var zone := installed_zone
	is_installed = false
	installed_zone = null
	if zone:
		removed.emit(self, zone)
