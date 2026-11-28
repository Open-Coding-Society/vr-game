extends SceneTree
## Checks for Phase 5's tools: the tool system (scripts/tools/tool.gd and a
## SnapZone's `required_tool`), the tool rack, the wrist strap, and the
## missions that use them. Run from the project folder:
##
##   godot --headless --script res://tests/run_tool_tests.gd
##
## Exit code 0 means every check passed. Like the other suites, the tests load
## real scenes, move parts the way a grabber does and step physics, so the
## SnapZones see the overlaps exactly as in the game.

const ToolRack := preload("res://scenes/tools/tool_rack.tscn")
const Tool := preload("res://scripts/tools/tool.gd")
const GrabbablePart := preload("res://scripts/grabbable_part.gd")
const SnapZone := preload("res://scripts/snap_zone.gd")
const ModuleRegistry := preload("res://scripts/module_registry.gd")
const TrainingManagerScript := preload("res://scripts/training_manager.gd")

## Nodes under the root that stay between tests.
const AUTOLOADS := [&"TrainingManager", &"ScoreReporter", &"SaveService"]

var _failures: Array[String] = []
var manager: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var saves := root.get_node_or_null("SaveService")
	if saves:
		saves.use_backend(preload("res://scripts/save/local_save_backend.gd").new("user://test_ocsvr_save.json"))
	manager = root.get_node_or_null("TrainingManager")
	if manager == null:
		manager = TrainingManagerScript.new()
		manager.name = "TrainingManager"
		root.add_child(manager)
	manager.scene_opener = func(_path: String) -> void: pass
	for test in _tests():
		manager.use_registry(ModuleRegistry.load_from())
		manager.now_ms = Time.get_ticks_msec
		manager.auto_advance = false
		await test.call()
	print("\n%s" % ("ALL PASSED" if _failures.is_empty() else "%d FAILED" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)


func _tests() -> Array:
	return [_test_tool_describes_itself, _test_tool_step_takes_its_tool, _test_tool_step_counts_uses,
		_test_bare_hands_on_a_tool_step, _test_dropped_tool_floats_home, _test_registry_tool_steps,
		_test_registry_needs_strap,
		_test_rack_has_one_of_each, _test_rack_tools_go_home, _test_strap_is_worn]


func check(label: String, ok: bool, detail = "") -> void:
	var why := str(detail)
	print(("PASS  " if ok else "FAIL  ") + label + ("" if ok or why == "" else "   [%s]" % why))
	if not ok:
		_failures.append(label)


## Clears the last test's nodes, then adds `node` under the root.
func _fresh(node: Node) -> Node:
	for child in root.get_children():
		if not child.name in AUTOLOADS:
			child.queue_free()
	await process_frame
	root.add_child(node)
	await _settle()
	return node


func _settle(frames := 3) -> void:
	for i in frames:
		await physics_frame


## Picks a part up, carries it to `to` and lets go, as a grabber does.
func _carry_and_drop(part: GrabbablePart, to: Vector3) -> void:
	part.grab()
	part.global_position = to
	await _settle()
	part.drop()
	await _settle()


## A zone made in code at `at`: a tool step for `tool` with `uses` uses, or an
## ordinary slot for parts of `accepts`.
func _zone(parent: Node3D, zone_name: String, at: Vector3, accepts: String, tool := "", uses := 1) -> SnapZone:
	var zone := Area3D.new()
	zone.set_script(SnapZone)
	zone.name = zone_name
	zone.position = at
	zone.accepts = StringName(tool if tool != "" else accepts)
	zone.required_tool = StringName(tool)
	zone.capacity = uses
	zone.display_name = zone_name
	zone.hint = "Use the %s for that." % tool if tool != "" else ""
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.08, 0.08, 0.08)
	shape.shape = box
	zone.add_child(shape)
	if uses > 1:
		var fasteners := Node3D.new()
		fasteners.name = "Fasteners"
		for i in uses:
			var screw := Node3D.new()
			screw.name = "Screw%d" % (i + 1)
			fasteners.add_child(screw)
		zone.add_child(fasteners)
	parent.add_child(zone)
	return zone


## A loose part made in code: a GrabbablePart of `type` at `at`.
func _part(parent: Node3D, part_name: String, type: String, at: Vector3, script = GrabbablePart) -> GrabbablePart:
	var part := RigidBody3D.new()
	part.set_script(script)
	part.name = part_name
	part.position = at
	if script == Tool:
		part.tool_type = type
		part.return_delay_s = 0.0
		part.return_time_s = 0.0
	else:
		part.part_type = StringName(type)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.04, 0.04, 0.04)
	shape.shape = box
	part.add_child(shape)
	parent.add_child(part)
	return part


## A bench with a screwdriver, a RAM stick and a 4-screw tool step.
func _bench() -> Dictionary:
	var bench := Node3D.new()
	bench.name = "Bench"
	var screwdriver := _part(bench, "Screwdriver", "screwdriver", Vector3(-0.3, 0, 0), Tool)
	var paste := _part(bench, "ThermalPaste", "thermal_paste", Vector3(-0.2, 0, 0), Tool)
	var ram := _part(bench, "Ram", "ram", Vector3(0.3, 0, 0))
	var screws := _zone(bench, "Screws", Vector3(0, 0, 0), "", "screwdriver", 4)
	await _fresh(bench)
	return {"bench": bench, "screwdriver": screwdriver, "paste": paste, "ram": ram, "screws": screws}


# ---- Step 2: the tool system ----

func _test_tool_describes_itself() -> void:
	var b := await _bench()
	var screwdriver: GrabbablePart = b.screwdriver
	check("a tool's part type is its tool type", screwdriver.part_type == &"screwdriver", screwdriver.part_type)
	check("and it names itself", screwdriver.display_name == "screwdriver", screwdriver.display_name)
	check("every tool type has a name the player reads",
		["screwdriver", "wrist_strap", "thermal_paste", "multimeter", "cloth"].all(func(t) -> bool: return Tool.TYPES.has(t)),
		Tool.TYPES.keys())


func _test_tool_step_takes_its_tool() -> void:
	var b := await _bench()
	var screws: SnapZone = b.screws
	var used := []
	screws.snapped.connect(func(_z, part) -> void: used.append(part.name))
	await _carry_and_drop(b.screwdriver, screws.global_position)
	check("the screwdriver on a screwdriver step is one use of it", used == [&"Screwdriver"] and screws.installed_parts.size() == 1, used)
	check("the tool isn't installed: it's free and back home",
		not b.screwdriver.is_installed and b.screwdriver.global_position.is_equal_approx(b.screwdriver.home_transform.origin),
		b.screwdriver.global_position)
	var screw_1: Node3D = screws.get_node("Fasteners/Screw1")
	var screw_2: Node3D = screws.get_node("Fasteners/Screw2")
	check("one screw comes out per use", not screw_1.visible and screw_2.visible)


func _test_tool_step_counts_uses() -> void:
	var b := await _bench()
	var screws: SnapZone = b.screws
	for i in 3:
		await _carry_and_drop(b.screwdriver, screws.global_position)
	check("three of four screws out: the step isn't done", not screws.is_filled(), screws.installed_parts.size())
	await _carry_and_drop(b.screwdriver, screws.global_position)
	check("the fourth finishes it", screws.is_filled())
	check("every screw is gone", screws.get_node("Fasteners").get_children().all(func(n) -> bool: return not n.visible))
	var before := screws.installed_parts.size()
	await _carry_and_drop(b.screwdriver, screws.global_position)
	check("a done step takes no more uses", screws.installed_parts.size() == before, screws.installed_parts.size())
	screws.eject_all()
	check("undoing the step puts the screws back", screws.get_node("Fasteners").get_children().all(func(n) -> bool: return n.visible))


func _test_bare_hands_on_a_tool_step() -> void:
	var b := await _bench()
	var screws: SnapZone = b.screws
	var turned_away := []
	screws.rejected.connect(func(_z, part) -> void: turned_away.append(part.name))
	await _carry_and_drop(b.ram, screws.global_position)
	check("a part (bare hands) on a tool step is turned away", turned_away == [&"Ram"] and screws.installed_parts.is_empty(), turned_away)
	await _carry_and_drop(b.paste, screws.global_position)
	check("so is the wrong tool", turned_away == [&"Ram", &"ThermalPaste"] and screws.installed_parts.is_empty(), turned_away)
	check("both go back where they were", b.ram.global_position.is_equal_approx(b.ram.home_transform.origin)
		and b.paste.global_position.is_equal_approx(b.paste.home_transform.origin))
	check("the step's hint says which tool it needs", screws.hint == "Use the screwdriver for that.", screws.hint)


func _test_dropped_tool_floats_home() -> void:
	var b := await _bench()
	var screwdriver = b.screwdriver
	screwdriver.return_delay_s = 0.1
	screwdriver.return_time_s = 0.1
	await _carry_and_drop(screwdriver, Vector3(0, 0.5, 0.5))
	check("a dropped tool waits a moment before it goes back", not screwdriver.is_home(), screwdriver.global_position)
	await create_timer(0.35).timeout
	check("then it floats back to its place", screwdriver.is_home(), screwdriver.global_position)
	await _carry_and_drop(screwdriver, Vector3(0, 0.5, 0.5))
	screwdriver.grab()
	await create_timer(0.35).timeout
	check("picked up again on the way, it stays in the hand", not screwdriver.is_home() and screwdriver.is_held)
	screwdriver.drop()


## A registry with one mission, for the registry checks: `mutate` changes it.
func _registry_with(mutate: Callable) -> PackedStringArray:
	var m := {
		"id": "tool_test", "title": "Tool test", "scene": "res://scenes/workbench.tscn",
		"intro": ["a"], "success": ["b"], "scoring": {"full": 100, "per_mistake": 10},
		"parts": {"Ram": {"type": "ram", "name": "RAM stick", "sensitive": true}},
		"slots": {
			"Screws": {"tool": "screwdriver", "name": "screws", "hint": "Use the screwdriver for that.", "capacity": 4},
			"Slot": {"accepts": "ram", "name": "slot", "hint": "h", "requires": ["Screws"]},
			"Wrist": {"accepts": "wrist_strap", "name": "your wrist", "hint": "h"},
		},
		"needs_strap": true,
	}
	mutate.call(m)
	var registry = ModuleRegistry.new()
	registry.read({"modules": [{"id": "test", "title": "Test", "missions": [m]}]})
	return registry.errors


func _test_registry_tool_steps() -> void:
	check("a mission with tool steps and a strap loads cleanly", _registry_with(func(_m) -> void: pass).is_empty(),
		_registry_with(func(_m) -> void: pass))
	var unknown := _registry_with(func(m) -> void: m.slots.Screws.tool = "hammer")
	check("an unknown tool is caught", unknown.size() == 1 and "tool must be one of" in unknown[0], unknown)
	var other := _registry_with(func(m) -> void: m.slots.Screws.accepts = "ram")
	check("a tool step that accepts something else is caught", other.size() == 1 and "can only accept" in other[0], other)
	var flags := _registry_with(func(m) -> void: m.slots.Screws.pass_through = true)
	check("a tool step can't also be pass_through", flags.size() == 1 and "tool step" in flags[0], flags)
	var no_part := _registry_with(func(m) -> void: m.slots["Spare"] = {"accepts": "multimeter", "name": "s", "hint": "h", "optional": true})
	check("a slot can take a tool without the mission listing it as a part", no_part.is_empty(), no_part)


func _test_registry_needs_strap() -> void:
	var no_wrist := _registry_with(func(m) -> void: m.slots.erase("Wrist"))
	check("needs_strap without a wrist slot is caught", no_wrist.size() == 1 and "wrist_strap" in no_wrist[0], no_wrist)
	var none_sensitive := _registry_with(func(m) -> void: m.parts.Ram.erase("sensitive"))
	check("needs_strap with no sensitive part is caught", none_sensitive.size() == 1 and "sensitive" in none_sensitive[0], none_sensitive)
	var bad := _registry_with(func(m) -> void: m.needs_strap = "yes")
	check("needs_strap must be true or false", bad.size() == 1 and "true or false" in bad[0], bad)


# ---- Step 3: the tool rack ----

func _test_rack_has_one_of_each() -> void:
	var rack: Node3D = await _fresh(ToolRack.instantiate())
	var found := {}
	for node in rack.find_children("*", "RigidBody3D", true, false):
		if node.get("tool_type") != null:
			found[node.tool_type] = found.get(node.tool_type, 0) + 1
	check("the rack has one each of the screwdriver, wrist strap, thermal paste and multimeter",
		found == {"screwdriver": 1, "wrist_strap": 1, "thermal_paste": 1, "multimeter": 1}, found)
	var names := ["Screwdriver", "WristStrap", "ThermalPaste", "Multimeter"].filter(func(n) -> bool: return rack.has_node(n))
	check("each tool has a plain name, for Phase 6's models", names.size() == 4, names)
	check("each has a Mesh child for its look", names.all(func(n) -> bool: return rack.get_node(n + "/Mesh").get_child_count() > 0))
	check("the multimeter has a display", rack.get_node("Multimeter/Display") is Label3D)
	var on_tray := names.all(func(n) -> bool: return absf(rack.get_node(n).position.y - 0.012) < 0.001)
	check("every tool sits on the tray", on_tray)


func _test_rack_tools_go_home() -> void:
	var rack: Node3D = await _fresh(ToolRack.instantiate())
	var meter = rack.get_node("Multimeter")
	meter.return_delay_s = 0.0
	meter.return_time_s = 0.05
	await _carry_and_drop(meter, Vector3(0.3, 0.3, 0.3))
	await create_timer(0.2).timeout
	check("a tool dropped off the rack goes back to its place on it", meter.is_home(), meter.global_position)
	meter.show_reading("12.1 V")
	check("the multimeter shows a reading on its display", rack.get_node("Multimeter/Display").text == "12.1 V")


func _test_strap_is_worn() -> void:
	var bench := Node3D.new()
	bench.name = "Bench"
	var rack := ToolRack.instantiate()
	bench.add_child(rack)
	var wrist := _zone(bench, "Wrist", Vector3(0.4, 0, 0.3), "wrist_strap")
	await _fresh(bench)
	var strap = rack.get_node("WristStrap")
	strap.return_delay_s = 0.0
	strap.return_time_s = 0.0
	await _carry_and_drop(strap, wrist.global_position)
	check("the strap dropped on the wrist is worn: it stays there", strap.is_installed and wrist.is_filled()
		and strap.global_position.distance_to(wrist.global_position) < 0.01, strap.global_position)
