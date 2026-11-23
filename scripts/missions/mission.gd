extends Node3D
## The one script every mission scene uses. The scene says *where* things are;
## data/modules.json says *what* they are, what the student reads and how the
## mission is scored. So a new mission is a new scene plus a registry entry,
## with no new code (build-plan step 4).
##
## On load it asks the TrainingManager autoload for its mission, gives each
## part and slot its type, name and hint from the registry, and then turns
## grabs, installs and wrong drops into TrainingManager calls and panel text.

const SnapZone := preload("res://scripts/snap_zone.gd")
const GrabbablePart := preload("res://scripts/grabbable_part.gd")
const InfoPanel := preload("res://scripts/ui/info_panel.gd")

## Full mission id in the registry, e.g. "build_computer.identify_components".
@export var mission_id: String = ""

var config: Dictionary = {}
## Every slot in the mission, and the ones that must be filled to finish it
## (all but `working` slots, which only turn parts away with a hint).
var zones: Array[SnapZone] = []
var goals: Array[SnapZone] = []
var parts: Array[GrabbablePart] = []
## Where the mission's problems go (also printed as errors), for tests.
var problems: PackedStringArray = []
## The success panel's lines and the score-saving status under them. Either
## can arrive first: a fast server can answer before the panel is drawn.
var _result_lines := PackedStringArray()
var _save_message := ""

@onready var panel: InfoPanel = $InfoPanel
@onready var manager: Node = get_node("/root/TrainingManager")


func _ready() -> void:
	config = manager.begin(mission_id)
	if config.is_empty():
		_problem("no mission %s in data/modules.json" % mission_id)
		panel.show_text("Mission not found", PackedStringArray([mission_id]))
		return
	_apply_registry()
	if config.get("on_complete", "") == "boot" and _monitor_screen() == null:
		_problem('on_complete is "boot" but the scene has no MonitorScreen (scripts/parts/monitor_screen.gd)')
	_apply_monitor_text()
	$Room.grabber.part_grabbed.connect(_on_part_grabbed)
	for zone in zones:
		zone.snapped.connect(_on_snapped)
		zone.rejected.connect(_on_rejected)
		zone.blocked.connect(_on_blocked)
		zone.swapped.connect(_on_swapped)
	manager.module_completed.connect(_on_module_completed)
	var reporter := get_node_or_null("/root/ScoreReporter")
	if reporter:
		reporter.report_finished.connect(_on_report_finished)
	panel.show_text(config.title, PackedStringArray(config.intro))


## Gives the scene's parts and slots their registry data. The registry is the
## one place types, names and hints live; the scene only places the nodes.
func _apply_registry() -> void:
	for path in config.parts:
		var part := get_node_or_null(path) as GrabbablePart
		if part == null:
			_problem('part "%s" isn\'t a GrabbablePart in %s' % [path, scene_file_path])
			continue
		part.part_type = StringName(config.parts[path].type)
		part.display_name = config.parts[path].name
		var tag := part.get_node_or_null("Name") as Label3D
		if tag:
			tag.text = part.display_name.left(1).to_upper() + part.display_name.substr(1)
		parts.append(part)
	for path in config.slots:
		var zone := get_node_or_null(path) as SnapZone
		if zone == null:
			_problem('slot "%s" isn\'t a SnapZone in %s' % [path, scene_file_path])
			continue
		var slot: Dictionary = config.slots[path]
		zone.accepts = StringName(slot.get("accepts", ""))
		zone.display_name = slot.name
		zone.hint = slot.hint
		zone.role = slot.get("role", "")
		zone.pass_through = slot.get("pass_through", false)
		zone.capacity = int(slot.get("capacity", 1))
		zone.working = slot.get("working", false)
		zone.swappable = slot.get("swappable", false)
		zone.compat = StringName(slot.get("compat", ""))
		zones.append(zone)
		if not zone.working:
			goals.append(zone)
	# Prerequisites are other slots of this mission, so link them once all exist.
	for path in config.slots:
		var zone := get_node_or_null(path) as SnapZone
		if zone == null:
			continue
		zone.prerequisites.clear()
		for need in config.slots[path].get("requires", []):
			var other := get_node_or_null(need) as SnapZone
			if other:
				zone.prerequisites.append(other)
	# Anything in the scene the registry doesn't list would never be scored.
	# The exception: with catalog_parts, a part with a `variant` gets its type
	# and name from data/parts_catalog.json instead.
	for node in find_children("*", "Node3D", true, false):
		if node is GrabbablePart and not parts.has(node) and config.catalog_parts and node.variant != "":
			parts.append(node)
			if node.spec.is_empty():
				_problem('part "%s" has the variant "%s", which isn\'t in data/parts_catalog.json' % [get_path_to(node), node.variant])
		elif (node is SnapZone and not zones.has(node)) or (node is GrabbablePart and not parts.has(node)):
			_problem('"%s" is in the scene but not in the registry' % get_path_to(node))


func _on_part_grabbed(_part: GrabbablePart) -> void:
	var was_intro: bool = manager.state == manager.State.INTRO
	manager.note_grab()
	if was_intro:
		_show_checklist("")


func _on_snapped(zone: SnapZone, part: GrabbablePart) -> void:
	if manager.state != manager.State.ACTIVE:
		return
	if goals.all(func(z: SnapZone) -> bool: return z.is_filled()):
		# The mission is over: what is in the slots now is what gets scored and
		# shown, so nothing can be added or swapped while the ending plays.
		for z in zones:
			z.locked = true
		# Something plays before the success panel (the monitor boots): the
		# ticked checklist stays up while it does.
		if config.get("on_complete", "") != "":
			_show_checklist(_installed_text(zone, part))
		manager.complete()
	else:
		_show_checklist(_installed_text(zone, part))


## What the panel says when a part goes in.
func _installed_text(zone: SnapZone, part: GrabbablePart) -> String:
	if zone.pass_through:
		return zone.role if zone.role != "" else "Yes! On to the next step."
	if zone.role != "":
		return "Yes! " + zone.role
	return "Yes! The %s goes in the %s." % [part.display_name, zone.display_name]


func _on_rejected(zone: SnapZone, part: GrabbablePart) -> void:
	if manager.state != manager.State.ACTIVE:
		return
	manager.note_mistake()
	if zone.last_problem != "":
		# The right kind of part, but it doesn't work with the others.
		_show_checklist(zone.last_problem)
	elif zone.working:
		_show_checklist("Not that one. " + zone.hint)
	else:
		_show_checklist("The %s doesn't go there. %s" % [part.display_name, zone.hint])


## A part was swapped out. Whatever was plugged into it can't stay: every slot
## that needed this one filled first is emptied, and so on down the chain, and
## their parts go back home.
func _on_swapped(zone: SnapZone, _old_part: GrabbablePart) -> void:
	_empty_dependents(zone, [zone])


func _empty_dependents(zone: SnapZone, seen: Array) -> void:
	for other in zones:
		if other.prerequisites.has(zone) and not seen.has(other):
			seen.append(other)
			other.eject_all()
			_empty_dependents(other, seen)


func _on_blocked(zone: SnapZone, part: GrabbablePart) -> void:
	if manager.state != manager.State.ACTIVE:
		return
	manager.note_mistake()
	var first := zone.missing_prerequisites().map(func(z) -> String: return z.display_name)
	_show_checklist("Not yet. First finish: %s. %s" % [name_list(first), zone.hint])


func _on_module_completed(_module_id: String, score: int, duration_s: int) -> void:
	if config.get("on_complete", "") == "boot":
		var screen := _monitor_screen()
		if screen:
			await screen.play_boot(PackedStringArray(config.boot_lines))
		if not is_inside_tree() or manager.mission.get("full_id", "") != mission_id:
			return
	_result_lines = PackedStringArray(config.success)
	_result_lines.append_array(_result_extras())
	_result_lines.append("Score: %d   Time: %s   Mistakes: %d" % [score, _clock(duration_s), manager.mistakes])
	next_mission = manager.next_mission_id(mission_id)
	if manager.return_scene != "":
		_result_lines.append("Back to %s in %d seconds" % [manager.return_label, roundi(manager.advance_delay_s)])
		get_tree().create_timer(manager.advance_delay_s).timeout.connect(_return_to_menu)
	elif next_mission != "" and manager.auto_advance:
		_result_lines.append("Next: %s in %d seconds" % [manager.registry.mission(next_mission).title, roundi(manager.advance_delay_s)])
		get_tree().create_timer(manager.advance_delay_s).timeout.connect(_open_next)
	_show_result()


## The mission that comes after this one ("" when it's the module's last).
var next_mission := ""


## Hands the registry's "monitor" text to the scene's monitor screen: what it
## shows from the start, and what it shows once its link light comes on.
func _apply_monitor_text() -> void:
	var text: Dictionary = config.get("monitor", {})
	if text.is_empty():
		return
	var screen := _monitor_screen()
	if screen == null:
		_problem("the registry has monitor text but the scene has no MonitorScreen (scripts/parts/monitor_screen.gd)")
		return
	if text.has("start"):
		screen.show_desktop(text.start[0], PackedStringArray(text.start.slice(1)))
	if text.has("linked"):
		screen.linked_title = text.linked[0]
		screen.linked_lines = PackedStringArray(text.linked.slice(1))


## The scene's monitor screen (a node named MonitorScreen with play_boot), for
## missions whose registry entry says "on_complete": "boot". Null without one.
func _monitor_screen() -> Node:
	var screen := find_child("MonitorScreen", true, false)
	return screen if screen and screen.has_method("play_boot") else null


## Lines a mission adds to its success panel, between the registry's success
## text and the score. None by default; a mission script of its own can say more.
func _result_extras() -> PackedStringArray:
	return PackedStringArray()


## Started from the menu: go back to it (it reopens manager.return_page).
func _return_to_menu() -> void:
	if is_inside_tree() and manager.state == manager.State.SUCCESS and manager.mission.full_id == mission_id:
		manager.open_scene(manager.return_scene)


func _open_next() -> void:
	if is_inside_tree() and manager.state == manager.State.SUCCESS and manager.mission.full_id == mission_id:
		manager.open_scene(manager.registry.mission(next_mission).scene)


func _on_report_finished(_ok: bool, message: String) -> void:
	_save_message = message
	if not _result_lines.is_empty() and is_inside_tree():
		_show_result()


func _show_result() -> void:
	var out := _result_lines.duplicate()
	if not config.practice:
		out.append(_save_message if _save_message != "" else "Saving your score...")
	panel.show_text("Mission complete!", out)


## One line per slot, ticked once its part is in, then any feedback.
## A slot still waiting on another says so.
func _show_checklist(feedback: String) -> void:
	var out := PackedStringArray()
	for zone in goals:
		var line := ("[x] " if zone.is_filled() else "[  ] ") + zone.display_name
		if zone.capacity > 1:
			line += " (%d of %d)" % [zone.installed_parts.size(), zone.capacity]
		if not zone.is_filled() and not zone.is_unlocked():
			line += "  (after: %s)" % name_list(zone.missing_prerequisites().map(func(z) -> String: return z.display_name))
		out.append(line)
	if feedback != "":
		out.append("")
		out.append(feedback)
	panel.show_text(config.title, out)


## Names for the panel: "a, b, c", or "a, b and 4 more" when the list is long
## enough to push the rest of the panel's text out of sight.
static func name_list(names: Array, most := 3) -> String:
	if names.size() <= most:
		return ", ".join(names)
	return "%s and %d more" % [", ".join(names.slice(0, most - 1)), names.size() - most + 1]


func _problem(text: String) -> void:
	problems.append(text)
	push_error("Mission %s: %s" % [mission_id, text])


static func _clock(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]
