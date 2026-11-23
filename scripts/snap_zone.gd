extends Area3D
## A place a part goes: a RAM slot, a CPU socket, a switch port.
##
## Mr. Mortensen's plan: one reusable SnapZone handles drop detection, and
## "that's your whole task system". The zone tells a part when it is over it;
## when the part is dropped, the zone it picks judges it: right type and empty,
## it's installed (`snapped`); wrong type, it's turned away (`rejected`, a failed
## attempt); right type but too early, it's `blocked` (also a failed attempt).
## Missions only listen to the signals.
##
## Two options come from the module registry:
## - `prerequisites`: zones that must be filled first ("plug in power last").
## - `pass_through`: the part only passes through. It's placed here and the zone
##   counts as done, but the part stays free to carry on to the next zone, like
##   data moving from storage to memory to the CPU.
## - `capacity`: how many parts it takes before it's full (a job queue takes
##   several, side by side, `stack_spacing` apart along the SnapPoint's x axis).
## - `working`: a part that isn't broken (Diagnose a failure). It never takes a
##   part; anything dropped on it is turned away with its hint.
## - `swappable`: a full zone still takes a part of its type. The part that was
##   in it goes back home, so the player can change their mind (`swapped`).
##
## A child named "Replaced" (e.g. the old, faulty part's mesh) is hidden once
## the zone is full, so the new part doesn't sit on top of the old one.

const GrabbablePart := preload("res://scripts/grabbable_part.gd")

## A part of the right type was dropped here and is now installed.
signal snapped(zone, part)
## A part of the wrong type was dropped here; it went back home.
signal rejected(zone, part)
## A part of the right type came too early (a prerequisite isn't filled yet).
signal blocked(zone, part)
## A swappable zone gave up `old_part` for a new one. Emitted before `snapped`.
signal swapped(zone, old_part)

## The part type this zone takes, e.g. &"ram". Matches GrabbablePart.part_type.
@export var accepts: StringName = &"ram"
## What the zone is called in hints, e.g. "RAM slot".
@export var display_name: String = "RAM slot"
## One sentence on what goes here and why, shown after a wrong drop,
## e.g. "Memory goes here: it holds what the CPU is working on right now."
@export_multiline var hint: String = ""
## What this part does in the computer, shown when it's installed.
@export_multiline var role: String = ""
## See above: the part is placed here and stays free to move on.
@export var pass_through := false

## How many parts fill this zone, and how far apart they sit (meters).
@export var capacity := 1
@export var stack_spacing := 0.05
## See above: a part that works; nothing is installed here.
@export var working := false
## See above: a full zone swaps its part for a new one of the same type.
@export var swappable := false

## Zones that must be filled before this one takes its part.
var prerequisites: Array[Area3D] = []
## Parts installed here, oldest first; `installed_part` is the latest.
var installed_parts: Array[GrabbablePart] = []
var installed_part: GrabbablePart = null

@onready var _snap_point: Node3D = get_node_or_null("SnapPoint")


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func is_filled() -> bool:
	return installed_parts.size() >= capacity


## Where an installed part's origin goes. A child Marker3D named SnapPoint sets
## it; without one, the zone's own origin is used.
func snap_transform() -> Transform3D:
	return _snap_point.global_transform if _snap_point else global_transform


## True when this zone would install the part right now.
func can_take(part: GrabbablePart) -> bool:
	return not working and (not is_filled() or swappable) and part.part_type == accepts and is_unlocked()


## True once every prerequisite zone is filled.
func is_unlocked() -> bool:
	return prerequisites.all(func(z) -> bool: return z.is_filled())


## The prerequisites still empty, for "not yet" messages.
func missing_prerequisites() -> Array[Area3D]:
	return prerequisites.filter(func(z) -> bool: return not z.is_filled())


## Decides about a part dropped on this zone: install it, turn it away, or (a
## part of the right type over a slot that's already full) do nothing, so it
## just goes home without counting as a mistake.
func judge(part: GrabbablePart) -> void:
	if part.is_installed:
		return
	if working:
		rejected.emit(self, part)
	elif can_take(part):
		if is_filled():
			# Swappable: the newest part makes room for this one.
			var old: GrabbablePart = installed_parts.pop_back()
			installed_part = installed_parts.back() if not installed_parts.is_empty() else null
			old.uninstall()
			swapped.emit(self, old)
		var at := snap_transform() * Transform3D(Basis(), Vector3(stack_spacing * installed_parts.size(), 0, 0))
		installed_parts.append(part)
		installed_part = part
		if pass_through:
			part.move_home(at)
		else:
			part.install(self, at)
		if is_filled() and has_node("Replaced"):
			get_node("Replaced").visible = false
		snapped.emit(self, part)
	elif part.part_type != accepts:
		rejected.emit(self, part)
	elif not is_filled():
		blocked.emit(self, part)


## Sends every installed part back home and leaves the zone empty, e.g. when
## the part they were plugged into has been taken out.
func eject_all() -> void:
	var leaving := installed_parts.duplicate()
	installed_parts.clear()
	installed_part = null
	for part in leaving:
		part.uninstall()
	if has_node("Replaced"):
		get_node("Replaced").visible = true


func _on_body_entered(body: Node) -> void:
	var part := body as GrabbablePart
	if part and not part.zones_under.has(self):
		part.zones_under.append(self)


func _on_body_exited(body: Node) -> void:
	var part := body as GrabbablePart
	if part:
		part.zones_under.erase(self)
