extends "res://scripts/missions/mission.gd"
## Build your own PC: the mission script plus the few things only this mission
## does. What fits where is still data: the slots' `compat` rules are in
## data/modules.json and the parts' specs in data/parts_catalog.json.


## A press of the power button that fails a power rule: the reason goes on
## the monitor too, as a PC that won't start would show it.
func _on_rejected(zone: SnapZone, part: GrabbablePart) -> void:
	var counts: bool = manager.state == manager.State.ACTIVE
	super._on_rejected(zone, part)
	var screen := _monitor_screen()
	if counts and screen and zone.compat == &"power" and zone.last_problem != "":
		screen.show_message(PackedStringArray([zone.last_problem]))
