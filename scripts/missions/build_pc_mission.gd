extends "res://scripts/missions/mission.gd"
## Build your own PC: the mission script plus the few things only this mission
## does. What fits where is still data: the slots' `compat` rules are in
## data/modules.json and the parts' specs in data/parts_catalog.json.

const Compatibility := preload("res://scripts/parts/compatibility.gd")


## The build that started the PC, kept for the results card.
var _booted: Array = []


## The specs of the parts now in the case, in checklist order.
func build_specs() -> Array:
	var specs := []
	for zone in goals:
		for part in zone.installed_parts:
			if not part.spec.is_empty():
				specs.append(part.spec)
	return specs


## The PC started (the finger went onto the power button, so the power rules
## passed). A balanced build, with no part more than one tier from another,
## earns the registry's scoring.balanced_bonus before the mission is scored.
func _on_snapped(zone: SnapZone, part: GrabbablePart) -> void:
	if manager.state == manager.State.ACTIVE and zone.compat == &"power":
		_booted = build_specs()
		if Compatibility.is_balanced(_booted):
			manager.add_bonus(config.scoring.balanced_bonus)
	super._on_snapped(zone, part)


## A press of the power button that fails a power rule: the reason goes on
## the monitor too, as a PC that won't start would show it.
func _on_rejected(zone: SnapZone, part: GrabbablePart) -> void:
	var counts: bool = manager.state == manager.State.ACTIVE
	super._on_rejected(zone, part)
	var screen := _monitor_screen()
	if counts and screen and zone.compat == &"power" and zone.last_problem != "":
		screen.show_message(PackedStringArray([zone.last_problem]))


## The results card lists the build, and says when it earned the bonus.
func _result_extras() -> PackedStringArray:
	var out := PackedStringArray(["Your build: " + Compatibility.summary(_booted)])
	if manager.bonus > 0:
		out.append("Balanced build: +%d" % manager.bonus)
	return out
