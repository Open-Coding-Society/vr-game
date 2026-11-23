extends SceneTree
## Checks for the Phase 2 game modes: the cables, the "Set up a pre-built PC"
## missions (Story IRL Act 1) and "Build your own PC". Run from the project
## folder:
##
##   godot --headless --script res://tests/run_mode_tests.gd
##
## Exit code 0 means every check passed. Like tests/run_tests.gd, the tests
## load real scenes, move parts the way a grabber does and step physics, so
## the SnapZones see the overlaps exactly as in the game.

const Cable := preload("res://scenes/parts/cable.tscn")
const Unbox := preload("res://scenes/setup_pc/unbox.tscn")
const ConnectPeripherals := preload("res://scenes/setup_pc/connect_peripherals.tscn")
const PowerOn := preload("res://scenes/setup_pc/power_on.tscn")
const GoOnline := preload("res://scenes/setup_pc/go_online.tscn")
const PartsShelf := preload("res://scenes/build_pc/parts_shelf.tscn")
const BuildYourOwn := preload("res://scenes/build_pc/build_your_own.tscn")
const MonitorScreen := preload("res://scripts/parts/monitor_screen.gd")
const Mission := preload("res://scripts/missions/mission.gd")
const PartsCatalog := preload("res://scripts/parts/parts_catalog.gd")
const Compatibility := preload("res://scripts/parts/compatibility.gd")
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
	# Missions finished here would be recorded in the player's real save; use a
	# throwaway file instead.
	var saves := root.get_node_or_null("SaveService")
	if saves:
		saves.use_backend(preload("res://scripts/save/local_save_backend.gd").new("user://test_ocsvr_save.json"))
	manager = root.get_node_or_null("TrainingManager")
	if manager == null:
		manager = TrainingManagerScript.new()
		manager.name = "TrainingManager"
		root.add_child(manager)
	for test in _tests():
		manager.use_registry(ModuleRegistry.load_from())
		manager.now_ms = Time.get_ticks_msec
		manager.auto_advance = false
		await test.call()
	print("\n%s" % ("ALL PASSED" if _failures.is_empty() else "%d FAILED" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)


func _tests() -> Array:
	return [_test_cable_wire_follows_its_ends, _test_cable_end_fits_its_port_only,
		_test_cable_requires_order, _test_cable_fixed_to_a_device,
		_test_setup_pc_is_in_the_registry, _test_unbox_perfect_run, _test_unbox_wrong_spot,
		_test_connect_perfect_run, _test_connect_wrong_ports, _test_long_title_fits_the_panel,
		_test_cable_fixed_at_both_ends, _test_registry_checks_on_complete, _test_monitor_screen_boot,
		_test_power_wall_goes_last, _test_power_on_boots, _test_boot_needs_a_monitor_screen,
		_test_go_online, _test_go_online_other_way_round,
		_test_parts_catalog_loads, _test_parts_catalog_catches_mistakes, _test_rule_cpu_socket,
		_test_rule_ram_type, _test_rule_storage_slot, _test_rule_gpu_plug, _test_rule_enough_power,
		_test_rules_by_name, _test_matching_builds_pass, _test_balanced_builds,
		_test_shelf_parts_load_their_specs, _test_shelf_layout, _test_part_variants,
		_test_bonus_points, _test_swappable_zone, _test_zone_compat_rule, _test_registry_checks_slot_rules,
		_test_registry_catalog_parts, _test_panel_body_size, _test_long_lists_are_cut_short,
		_test_monitor_screen_message, _test_build_scene, _test_build_board_goes_first,
		_test_build_matching_tiers_boot, _test_build_parts_that_do_not_fit, _test_build_power_rules,
		_test_build_swapping_the_board, _test_build_monitor_says_why, _test_build_balanced_bonus,
		_test_build_results_card, _test_big_parts_are_grabbed_by_the_middle,
		_test_build_is_frozen_once_it_boots, _test_finished_mission_takes_no_more_parts,
		_test_swap_empties_the_whole_chain]


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


## The middle of a slot's drop area: where a carried part has to be for the
## slot to see it.
func _over(mission: Node3D, slot_path: String) -> Vector3:
	return (mission.get_node(slot_path).get_node("CollisionShape3D") as Node3D).global_position


## The real input path, as the mouse does it: press on the part through the
## camera, carry it above the table to over `to`, let go. The press is on the
## middle of the part's grab shape, moved by `press` for a part that is partly
## under another.
func _drag(mission: Node3D, part_path: String, to: Vector3, press := Vector3.ZERO) -> void:
	var part: GrabbablePart = mission.get_node(part_path)
	var grabber = mission.get_node("Room/MouseGrabber")
	var camera: Camera3D = mission.get_node("Room/Camera3D")
	var middle: Vector3 = (part.get_node("CollisionShape3D") as Node3D).global_position + press
	if grabber.try_grab_at(camera.unproject_position(middle)) != part:
		check("pressing on %s through the camera picks it up" % part_path, false)
		return
	grabber.carry_to(camera.unproject_position(Vector3(to.x, grabber.carry_height, to.z)))
	await _settle()
	grabber.release()
	await _settle()


## Drags each [part, slot] pair in turn.
func _drag_all(mission: Node3D, pairs: Array) -> void:
	for pair in pairs:
		await _drag(mission, pair[0], _over(mission, pair[1]))


## A port made in code: a SnapZone at `at` that takes parts of `type`.
func _port(parent: Node3D, port_name: String, type: String, at: Vector3) -> SnapZone:
	var zone := Area3D.new()
	zone.set_script(SnapZone)
	zone.name = port_name
	zone.position = at
	zone.accepts = StringName(type)
	zone.display_name = port_name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.06, 0.06, 0.06)
	shape.shape = box
	zone.add_child(shape)
	parent.add_child(zone)
	return zone


## A bench with one cable whose two ends are both of `type`.
func _bench_with_cable(type: String) -> Array:
	var bench := Node3D.new()
	bench.name = "Bench"
	var cable := Cable.instantiate()
	cable.end_a_position = Vector3(-0.2, 0.0, 0.0)
	cable.end_b_position = Vector3(0.2, 0.0, 0.0)
	bench.add_child(cable)
	await _fresh(bench)
	for end_name in ["EndA", "EndB"]:
		var end: GrabbablePart = cable.get_node(end_name)
		end.part_type = StringName(type)
	return [bench, cable]


# ---- Step 1: cables ----

func _test_cable_wire_follows_its_ends() -> void:
	var made := await _bench_with_cable("hdmi")
	var cable: Node3D = made[1]
	var a: GrabbablePart = cable.get_node("EndA")
	var b: GrabbablePart = cable.get_node("EndB")
	check("a cable's ends start where the scene put them, and that is their home",
		a.global_position.is_equal_approx(Vector3(-0.2, 0, 0)) and b.home_transform.origin.is_equal_approx(Vector3(0.2, 0, 0)),
		"%s %s" % [a.global_position, b.home_transform.origin])
	await process_frame
	var wire: MeshInstance3D = cable.get_node("Wire")
	var ends: Array = cable.wire_ends()
	check("the wire sits halfway between the two plugs", wire.global_position.is_equal_approx((ends[0] + ends[1]) * 0.5), wire.global_position)
	check("and is as long as the gap between them", is_equal_approx(wire.global_transform.basis.y.length(), 0.4), wire.global_transform.basis.y.length())
	b.grab()
	b.global_position = Vector3(0.2, 0.3, 0.4)
	await process_frame
	await process_frame
	check("carrying one plug stretches the wire after it",
		is_equal_approx(wire.global_transform.basis.y.length(), a.global_position.distance_to(b.global_position)),
		wire.global_transform.basis.y.length())
	b.drop()


func _test_cable_end_fits_its_port_only() -> void:
	var made := await _bench_with_cable("hdmi")
	var bench: Node3D = made[0]
	var cable: Node3D = made[1]
	var hdmi := _port(bench, "HdmiPort", "hdmi", Vector3(0.0, 0.0, -0.3))
	var usb := _port(bench, "UsbPort", "usb", Vector3(0.0, 0.0, 0.3))
	await _settle()
	var turned_away := [0]
	usb.rejected.connect(func(_zone, _part) -> void: turned_away[0] += 1)
	var a: GrabbablePart = cable.get_node("EndA")
	await _carry_and_drop(a, usb.global_position)
	check("an HDMI plug dropped on a USB port is turned away and goes home",
		turned_away[0] == 1 and not a.is_installed and a.global_position.is_equal_approx(a.home_transform.origin), a.global_position)
	await _carry_and_drop(a, hdmi.global_position)
	check("the same plug goes into an HDMI port", a.is_installed and hdmi.is_filled() and hdmi.installed_part == a)
	var b: GrabbablePart = cable.get_node("EndB")
	check("the other end is still free to plug in somewhere else", b.can_grab() and not b.is_installed)


func _test_cable_requires_order() -> void:
	var made := await _bench_with_cable("power")
	var bench: Node3D = made[0]
	var cable: Node3D = made[1]
	var inlet := _port(bench, "PowerIn", "power", Vector3(0.0, 0.0, -0.3))
	var wall := _port(bench, "WallSocket", "power", Vector3(0.0, 0.0, 0.3))
	wall.prerequisites.append(inlet)
	await _settle()
	var too_early := [0]
	wall.blocked.connect(func(_zone, _part) -> void: too_early[0] += 1)
	var a: GrabbablePart = cable.get_node("EndA")
	var b: GrabbablePart = cable.get_node("EndB")
	await _carry_and_drop(b, wall.global_position)
	check("the wall end is blocked while the device end is out", too_early[0] == 1 and not b.is_installed and not wall.is_filled())
	await _carry_and_drop(a, inlet.global_position)
	await _carry_and_drop(b, wall.global_position)
	check("once the device end is in, the wall end goes in", a.is_installed and b.is_installed and wall.is_filled())


func _test_cable_fixed_to_a_device() -> void:
	var bench := Node3D.new()
	bench.name = "Bench"
	var device := Node3D.new()
	device.name = "Keyboard"
	device.position = Vector3(-0.3, 0.0, 0.1)
	bench.add_child(device)
	var cable := Cable.instantiate()
	cable.fixed_end = NodePath("../Keyboard")
	cable.end_b_position = Vector3(0.1, 0.0, 0.0)
	bench.add_child(cable)
	await _fresh(bench)
	await process_frame
	check("a device's cable has one plug only", cable.get_node_or_null("EndA") == null and cable.get_node_or_null("EndB") is GrabbablePart)
	var ends: Array = cable.wire_ends()
	check("its wire runs from the device to the plug",
		ends.size() == 2 and ends[0].is_equal_approx(device.global_position + Vector3(0, cable.wire_lift, 0))
			and ends[1].is_equal_approx(cable.get_node("EndB").global_position + Vector3(0, cable.wire_lift, 0)), ends)


# ---- Step 2: unbox the PC, then connect the monitor, keyboard and mouse ----

func _test_setup_pc_is_in_the_registry() -> void:
	var registry = ModuleRegistry.load_from()
	check("data/modules.json still loads with no problems", registry.errors.is_empty(), "; ".join(registry.errors))
	var setup := {}
	for module in registry.modules:
		if module.id == "setup_pc":
			setup = module
	check("it has a Set up a pre-built PC module, listed with the Computer tasks",
		setup.get("title") == "Set up a pre-built PC" and setup.get("category") == "computer", str(setup))
	var ids: Array = setup.get("mission_ids", [])
	check("its four missions come in the order they are played",
		ids == ["setup_pc.unbox", "setup_pc.connect_peripherals", "setup_pc.power_on", "setup_pc.go_online"], str(ids))
	var thin := []
	for id in ids:
		var m: Dictionary = registry.mission(id)
		if m.description == "" or m.topic == "" or m.difficulty == "":
			thin.append(id)
	check("each one has the description, topic and difficulty Free Play shows", thin.is_empty(), str(thin))
	check("the first two are Beginner tasks and the last two Intermediate",
		ids.map(func(id) -> String: return registry.mission(id).difficulty) == ["Beginner", "Beginner", "Intermediate", "Intermediate"])


func _test_unbox_perfect_run() -> void:
	var mission := await _fresh(Unbox.instantiate())
	check("Unbox the PC loads with nothing out of place", mission.problems.is_empty(), "; ".join(mission.problems))
	var tower: GrabbablePart = mission.get_node("Tower")
	var monitor: GrabbablePart = mission.get_node("Monitor")
	check("the tower and the monitor start lying down in the box",
		absf(tower.global_transform.basis.y.y) < 0.01 and absf(monitor.global_transform.basis.y.y) < 0.01,
		"%s %s" % [tower.global_transform.basis.y, monitor.global_transform.basis.y])
	await _drag_all(mission, [["Tower", "Desk/TowerSpot"], ["Monitor", "Desk/MonitorSpot"], ["Keyboard", "Desk/KeyboardSpot"]])
	check("three of the four out of the box is not finished yet", manager.state == manager.State.ACTIVE, manager.state)
	check("the panel ticks off the spots that are filled",
		"[x] tower spot" in mission.panel.text() and "[x] keyboard spot" in mission.panel.text() and "[  ] mouse spot" in mission.panel.text(),
		mission.panel.text())
	check("the tower and the monitor stand up on their spots",
		tower.is_installed and monitor.is_installed and tower.global_transform.basis.y.is_equal_approx(Vector3.UP)
			and monitor.global_transform.basis.y.is_equal_approx(Vector3.UP),
		"%s %s" % [tower.global_transform.basis.y, monitor.global_transform.basis.y])
	check("placing a part says what it is for", "Yes! The keyboard is an input device" in mission.panel.text(), mission.panel.text())
	await _drag(mission, "Mouse", _over(mission, "Desk/MouseSpot"))
	check("with all four on the desk the mission is complete, at full score",
		manager.state == manager.State.SUCCESS and manager.mistakes == 0 and manager.score == 100,
		"%s %s %s" % [manager.state, manager.mistakes, manager.score])
	check("the success panel says what each part does",
		"Mission complete!" in mission.panel.text() and "Unboxed!" in mission.panel.text(), mission.panel.text())


func _test_unbox_wrong_spot() -> void:
	var mission := await _fresh(Unbox.instantiate())
	var keyboard: GrabbablePart = mission.get_node("Keyboard")
	await _drag(mission, "Keyboard", _over(mission, "Desk/TowerSpot"))
	check("the keyboard on the tower's spot is turned away: a mistake, and it goes back in the box",
		manager.mistakes == 1 and not keyboard.is_installed and keyboard.global_position.is_equal_approx(keyboard.home_transform.origin),
		"%s %s" % [manager.mistakes, keyboard.global_position])
	check("the panel says what that spot is for",
		"The keyboard doesn't go there. This spot is for the tower" in mission.panel.text(), mission.panel.text())
	await _drag(mission, "Mouse", _over(mission, "Desk/KeyboardSpot"))
	check("so is the mouse on the keyboard's spot", manager.mistakes == 2 and not mission.get_node("Mouse").is_installed, manager.mistakes)
	await _drag_all(mission, [["Mouse", "Desk/MouseSpot"], ["Keyboard", "Desk/KeyboardSpot"],
		["Monitor", "Desk/MonitorSpot"], ["Tower", "Desk/TowerSpot"]])
	check("finishing after two mistakes scores 80", manager.state == manager.State.SUCCESS and manager.score == 80,
		"%s %s" % [manager.state, manager.score])


func _test_connect_perfect_run() -> void:
	var mission := await _fresh(ConnectPeripherals.instantiate())
	check("Connect the monitor, keyboard and mouse loads with nothing out of place", mission.problems.is_empty(), "; ".join(mission.problems))
	check("the keyboard's and the mouse's cables have one plug each, the HDMI cable has two",
		mission.get_node_or_null("KeyboardCable/EndA") == null and mission.get_node_or_null("MouseCable/EndA") == null
			and mission.get_node_or_null("HdmiCable/EndA") is GrabbablePart and mission.get_node_or_null("HdmiCable/EndB") is GrabbablePart)
	await _drag_all(mission, [["HdmiCable/EndA", "Tower/GpuHdmi"], ["HdmiCable/EndB", "Monitor/HdmiIn"], ["KeyboardCable/EndB", "Tower/Usb1"]])
	check("three of the four plugs in is not finished yet", manager.state == manager.State.ACTIVE, manager.state)
	check("the panel ticks off the ports that are filled",
		"[x] graphics card HDMI port" in mission.panel.text() and "[x] monitor HDMI port" in mission.panel.text()
			and "[x] first USB port" in mission.panel.text() and "[  ] second USB port" in mission.panel.text(),
		mission.panel.text())
	var plug: GrabbablePart = mission.get_node("KeyboardCable/EndB")
	var port: SnapZone = mission.get_node("Tower/Usb1")
	check("a plug let go in front of the tower goes up into its port",
		plug.is_installed and plug.global_position.is_equal_approx(port.snap_transform().origin) and plug.global_position.y > 1.1,
		plug.global_position)
	await _drag(mission, "MouseCable/EndB", _over(mission, "Tower/Usb2"))
	check("with every cable in, the mission is complete at full score",
		manager.state == manager.State.SUCCESS and manager.mistakes == 0 and manager.score == 100,
		"%s %s %s" % [manager.state, manager.mistakes, manager.score])
	await process_frame
	var ends: Array = mission.get_node("HdmiCable").wire_ends()
	check("the HDMI cable's wire now runs from the tower to the monitor",
		ends.size() == 2 and ends[0].distance_to(mission.get_node("Tower/GpuHdmi").snap_transform().origin) < 0.02
			and ends[1].distance_to(mission.get_node("Monitor/HdmiIn").snap_transform().origin) < 0.02, str(ends))


func _test_connect_wrong_ports() -> void:
	var mission := await _fresh(ConnectPeripherals.instantiate())
	var hdmi: GrabbablePart = mission.get_node("HdmiCable/EndA")
	await _drag(mission, "HdmiCable/EndA", _over(mission, "Tower/Usb1"))
	check("an HDMI plug on a USB port is turned away: a mistake, and it goes back to the desk",
		manager.mistakes == 1 and not hdmi.is_installed and hdmi.global_position.is_equal_approx(hdmi.home_transform.origin),
		"%s %s" % [manager.mistakes, hdmi.global_position])
	check("the panel says what USB ports are for",
		"The HDMI plug doesn't go there. Keyboard and mouse are input devices" in mission.panel.text(), mission.panel.text())
	await _drag(mission, "MouseCable/EndB", _over(mission, "Monitor/HdmiIn"))
	check("the mouse's plug on the monitor's HDMI port is turned away too",
		manager.mistakes == 2 and not mission.get_node("MouseCable/EndB").is_installed, manager.mistakes)
	check("and the panel says what that port takes",
		"The mouse plug doesn't go there. The monitor's HDMI port takes the picture" in mission.panel.text(), mission.panel.text())
	await _drag(mission, "KeyboardCable/EndB", _over(mission, "Tower/GpuHdmi"))
	check("the keyboard's plug on the graphics card's port gets the hint about that port",
		manager.mistakes == 3 and "the one lower down on the back" in mission.panel.text(), mission.panel.text())
	# Either end of the HDMI cable fits either HDMI port, and either USB port
	# takes the keyboard or the mouse.
	await _drag_all(mission, [["MouseCable/EndB", "Tower/Usb1"], ["KeyboardCable/EndB", "Tower/Usb2"],
		["HdmiCable/EndB", "Tower/GpuHdmi"], ["HdmiCable/EndA", "Monitor/HdmiIn"]])
	check("the cables go in either way round, and three mistakes leave a score of 70",
		manager.state == manager.State.SUCCESS and manager.score == 70, "%s %s" % [manager.state, manager.score])


func _test_long_title_fits_the_panel() -> void:
	var mission := await _fresh(ConnectPeripherals.instantiate())
	var panel = mission.panel
	check("a mission title too long for the panel is drawn smaller, so it fits on one line",
		panel.title_size() < panel.TITLE_SIZE and panel.title_size() >= panel.TITLE_SIZE_MIN and panel.title_width() <= panel.title_room(),
		"%s %s %s" % [panel.title_size(), panel.title_width(), panel.title_room()])
	panel.show_text("Unbox the PC", PackedStringArray(["A short title."]))
	check("a short title keeps its full size", panel.title_size() == panel.TITLE_SIZE, panel.title_size())


# ---- Step 3: power and the boot sequence, the network and the link light ----

func _test_cable_fixed_at_both_ends() -> void:
	var bench := Node3D.new()
	bench.name = "Bench"
	for spot in [["Tower", Vector3(-0.3, 0.2, 0.0)], ["Monitor", Vector3(0.3, 0.1, -0.1)]]:
		var node := Node3D.new()
		node.name = spot[0]
		node.position = spot[1]
		bench.add_child(node)
	var cable := Cable.instantiate()
	cable.fixed_end = NodePath("../Tower")
	cable.fixed_end_b = NodePath("../Monitor")
	bench.add_child(cable)
	await _fresh(bench)
	await process_frame
	check("a cable that is already plugged in at both ends has no plugs to grab",
		cable.get_node_or_null("EndA") == null and cable.get_node_or_null("EndB") == null)
	var ends: Array = cable.wire_ends()
	var lift := Vector3(0, cable.wire_lift, 0)
	check("its wire joins the two things it is plugged into",
		ends.size() == 2 and ends[0].is_equal_approx(Vector3(-0.3, 0.2, 0.0) + lift) and ends[1].is_equal_approx(Vector3(0.3, 0.1, -0.1) + lift)
			and cable.get_node("Wire").visible, str(ends))


## The registry's errors after `mutate` has changed the power_on mission.
func _bad_power_on(mutate: Callable) -> PackedStringArray:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules.json"))
	for module in data.modules:
		if module.id == "setup_pc":
			for m in module.missions:
				if m.id == "power_on":
					mutate.call(m)
	var registry = ModuleRegistry.new()
	registry.read(data)
	return registry.errors


## The registry's errors after `mutate` has changed the Build your own PC mission.
func _bad_build(mutate: Callable) -> PackedStringArray:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules.json"))
	for module in data.modules:
		for m in module.missions:
			if m.id == "build_your_own":
				mutate.call(m)
	var registry = ModuleRegistry.new()
	registry.read(data)
	return registry.errors


func _test_registry_checks_on_complete() -> void:
	var power: Dictionary = ModuleRegistry.load_from().mission("setup_pc.power_on")
	check("the power mission asks for a boot, with its lines in the registry",
		power.get("on_complete") == "boot" and power.get("boot_lines", []).size() == 4, str(power.get("boot_lines")))
	var errors := _bad_power_on(func(m): m.on_complete = "reboot")
	check("an on_complete the game doesn't know is caught",
		errors.size() == 1 and "setup_pc.power_on.on_complete: must be one of boot" in errors[0], "; ".join(errors))
	errors = _bad_power_on(func(m): m.erase("boot_lines"))
	check("a boot with no lines is caught",
		errors.size() == 1 and "setup_pc.power_on.boot_lines: must be a non-empty list of text" in errors[0], "; ".join(errors))
	errors = _bad_power_on(func(m): m.erase("on_complete"))
	check("boot lines with no on_complete are caught too", errors.size() == 1 and "on_complete" in errors[0], "; ".join(errors))


func _test_monitor_screen_boot() -> void:
	var screen := Node3D.new()
	screen.set_script(MonitorScreen)
	screen.line_seconds = 0.03
	await _fresh(screen)
	check("a monitor's screen starts off", not screen.visible and not screen.is_on)
	var seen := []
	screen.play_boot(PackedStringArray(["one", "two", "three", "Desktop ready"]))
	check("starting a boot turns the screen on", screen.visible and screen.is_on and screen.is_booting)
	while screen.is_booting:
		if seen.is_empty() or seen[-1] != screen.text():
			seen.append(screen.text())
		await process_frame
	seen.append(screen.text())
	check("the boot lines come up one after another, and the last one is left as the desktop",
		seen == ["\none", "\none\ntwo", "\none\ntwo\nthree", "Desktop ready\n"], str(seen))
	screen.line_seconds = 0.0
	screen.play_boot(PackedStringArray(["a", "b"]))
	check("with no wait between lines the boot is over at once", not screen.is_booting and screen.text() == "b\n", screen.text())


func _test_power_wall_goes_last() -> void:
	var mission := await _fresh(PowerOn.instantiate())
	check("Plug in power loads with nothing out of place", mission.problems.is_empty(), "; ".join(mission.problems))
	mission.get_node("Monitor/MonitorScreen").line_seconds = 0.0
	var wall_plug: GrabbablePart = mission.get_node("TowerPower/EndB")
	await _drag(mission, "TowerPower/EndB", _over(mission, "Wall/Socket"))
	check("power into the wall before the tower is blocked: a mistake, and the plug goes back",
		manager.mistakes == 1 and not wall_plug.is_installed and wall_plug.global_position.is_equal_approx(wall_plug.home_transform.origin),
		"%s %s" % [manager.mistakes, wall_plug.global_position])
	check("the panel says what has to come first, and why",
		"Not yet. First finish: tower power inlet, monitor power inlet. Always plug into the wall last" in mission.panel.text(), mission.panel.text())
	check("and the checklist marks the wall socket as waiting",
		"[  ] wall socket (0 of 2)  (after: tower power inlet, monitor power inlet)" in mission.panel.text(), mission.panel.text())
	await _drag(mission, "TowerPower/EndA", _over(mission, "Tower/PowerIn"))
	await _drag(mission, "TowerPower/EndB", _over(mission, "Wall/Socket"))
	check("with only the tower's cable in, the wall is still blocked: the monitor's comes first too",
		manager.mistakes == 2 and "First finish: monitor power inlet." in mission.panel.text(), mission.panel.text())
	await _drag(mission, "MonitorPower/EndA", _over(mission, "Wall/Socket"))
	check("the end that goes into a device doesn't fit the wall",
		manager.mistakes == 3 and "The monitor power cable doesn't go there." in mission.panel.text(), mission.panel.text())
	await _drag_all(mission, [["MonitorPower/EndA", "Monitor/PowerIn"], ["MonitorPower/EndB", "Wall/Socket"]])
	check("once both devices have their cable, a wall plug goes in",
		mission.get_node("MonitorPower/EndB").is_installed and "[  ] wall socket (1 of 2)" in mission.panel.text(), mission.panel.text())
	await _drag(mission, "TowerPower/EndB", _over(mission, "Wall/Socket"))
	check("both wall plugs in finishes the mission, three mistakes down",
		manager.state == manager.State.SUCCESS and manager.score == 70, "%s %s" % [manager.state, manager.score])
	check("the two plugs sit side by side in the strip",
		absf(wall_plug.global_position.x - mission.get_node("MonitorPower/EndB").global_position.x) > 0.05, wall_plug.global_position)


func _test_power_on_boots() -> void:
	var mission := await _fresh(PowerOn.instantiate())
	var screen = mission.get_node("Monitor/MonitorScreen")
	screen.line_seconds = 0.05
	check("before power the monitor is off", not screen.visible and not screen.is_on)
	await _drag_all(mission, [["TowerPower/EndA", "Tower/PowerIn"], ["MonitorPower/EndA", "Monitor/PowerIn"], ["TowerPower/EndB", "Wall/Socket"]])
	check("with one wall plug still out, nothing boots", not screen.is_on and manager.state == manager.State.ACTIVE)
	await _drag(mission, "MonitorPower/EndB", _over(mission, "Wall/Socket"))
	check("the last plug starts the boot: the monitor comes on with the registry's first boot line",
		manager.state == manager.State.SUCCESS and screen.is_booting and "POST: checking CPU, memory, storage" in screen.text(), screen.text())
	check("the success panel waits while it plays, with the checklist all ticked",
		not "Mission complete!" in mission.panel.text() and "[x] wall socket (2 of 2)" in mission.panel.text(), mission.panel.text())
	await screen.boot_finished
	await process_frame
	check("the boot ends on the desktop", screen.text() == "Desktop ready\n" and not screen.is_booting, screen.text())
	check("and then the success panel comes up, with the score",
		"Mission complete!" in mission.panel.text() and "It boots!" in mission.panel.text() and "Score: 100" in mission.panel.text(),
		mission.panel.text())


func _test_boot_needs_a_monitor_screen() -> void:
	# A registry that asks for a boot in a scene with no monitor screen is
	# reported when the mission loads, like any other scene/registry mismatch.
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules.json"))
	for module in data.modules:
		if module.id == "setup_pc":
			module.missions[0].on_complete = "boot"
			module.missions[0].boot_lines = ["one", "two"]
	var registry = ModuleRegistry.new()
	registry.read(data)
	manager.use_registry(registry)
	var mission := await _fresh(Unbox.instantiate())
	check("asking for a boot in a scene with no monitor screen is reported",
		mission.problems.size() == 1 and "no MonitorScreen" in mission.problems[0], "; ".join(mission.problems))
	await _drag_all(mission, [["Tower", "Desk/TowerSpot"], ["Monitor", "Desk/MonitorSpot"], ["Keyboard", "Desk/KeyboardSpot"], ["Mouse", "Desk/MouseSpot"]])
	check("and the mission still finishes without it",
		manager.state == manager.State.SUCCESS and "Mission complete!" in mission.panel.text(), mission.panel.text())


func _test_go_online() -> void:
	var mission := await _fresh(GoOnline.instantiate())
	check("Connect to the network loads with nothing out of place", mission.problems.is_empty(), "; ".join(mission.problems))
	var screen = mission.get_node("Monitor/MonitorScreen")
	var light = mission.get_node("Router/Lan1Light")
	check("the PC is on, and says it has no network", screen.is_on and screen.text() == "Desktop\nNetwork: not connected", screen.text())
	check("the router's link light starts dark", not light.is_lit and not light.material_override.emission_enabled)
	await _drag(mission, "EthernetCable/EndA", _over(mission, "Tower/Ethernet"))
	check("one end in is no link yet: the light stays dark and the PC is still offline",
		not light.is_lit and "not connected" in screen.text() and manager.state == manager.State.ACTIVE, screen.text())
	check("the panel says what the port is for", "Yes! The network port is how the PC sends and receives data" in mission.panel.text(), mission.panel.text())
	await _drag(mission, "EthernetCable/EndB", _over(mission, "Router/Lan1"))
	check("with both ends in, the link light turns green",
		light.is_lit and light.material_override.emission_enabled and light.material_override.albedo_color.is_equal_approx(light.on_color))
	check("the monitor shows Connected", screen.text() == "Connected\nThis PC is on the network.", screen.text())
	check("and the mission is complete at full score",
		manager.state == manager.State.SUCCESS and manager.score == 100 and "You're online!" in mission.panel.text(), mission.panel.text())


func _test_go_online_other_way_round() -> void:
	var mission := await _fresh(GoOnline.instantiate())
	var light = mission.get_node("Router/Lan1Light")
	await _drag(mission, "EthernetCable/EndA", _over(mission, "Router/Lan1"))
	check("the router end first works too, and the light waits for the other end",
		mission.get_node("EthernetCable/EndA").is_installed and not light.is_lit and manager.mistakes == 0)
	await _drag(mission, "EthernetCable/EndB", _over(mission, "Tower/Ethernet"))
	check("then the tower end brings the link up", light.is_lit and manager.state == manager.State.SUCCESS)


# ---- Step 5: the parts catalog and the compatibility rules (no scene) ----

## A part's specs from the real catalog.
func _spec(id: String) -> Dictionary:
	return PartsCatalog.shared().spec(id)


func _test_parts_catalog_loads() -> void:
	var catalog = PartsCatalog.load_from()
	check("data/parts_catalog.json loads with no problems", catalog.errors.is_empty(), "; ".join(catalog.errors))
	check("it has 18 parts", catalog.parts.size() == 18, catalog.parts.size())
	var uneven := []
	for type in PartsCatalog.FIELDS:
		var tiers: Array = catalog.of_type(type).map(func(id) -> String: return catalog.spec(id).tier)
		if tiers != PartsCatalog.TIERS:
			uneven.append("%s: %s" % [type, tiers])
	check("every type of part comes in the three tiers, lowest first", uneven.is_empty(), str(uneven))
	var cpu: Dictionary = catalog.spec("cpu_mid")
	check("a part keeps its id and its specs",
		cpu.get("id") == "cpu_mid" and cpu.get("name") == "AMD Ryzen 5 7600" and cpu.get("socket") == "AM5" and cpu.get("watts") == 65, str(cpu))
	check("a part the catalog doesn't have is an empty spec", catalog.spec("cpu_quantum").is_empty())
	check("each tier has a name and a colour",
		PartsCatalog.TIER_NAMES["high"] == "High-end" and PartsCatalog.TIER_COLORS["mid"].is_equal_approx(Color("2F81F7")))


func _bad_catalog(mutate: Callable) -> PackedStringArray:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/parts_catalog.json"))
	mutate.call(data.parts)
	var catalog = PartsCatalog.new()
	catalog.read(data)
	return catalog.errors


func _test_parts_catalog_catches_mistakes() -> void:
	var errors := _bad_catalog(func(parts): parts.cpu_mid.erase("socket"))
	check("a CPU with no socket is caught, naming the field", errors.size() == 1 and errors[0] == "cpu_mid.socket: must be text", "; ".join(errors))
	errors = _bad_catalog(func(parts): parts.psu_mid.watts = "850 W")
	check("watts that aren't a number are caught", errors.size() == 1 and errors[0] == "psu_mid.watts: must be a number", "; ".join(errors))
	errors = _bad_catalog(func(parts): parts.gpu_high.tier = "ultra")
	check("a tier the game doesn't have is caught", errors.size() == 1 and "gpu_high.tier: must be one of starter, mid, high" in errors[0], "; ".join(errors))
	errors = _bad_catalog(func(parts): parts.ram_mid.type = "memory")
	check("a type the game doesn't have is caught", errors.size() == 1 and "ram_mid.type: must be one of" in errors[0], "; ".join(errors))


func _test_rule_cpu_socket() -> void:
	check("an AM5 CPU fits an AM5 board", Compatibility.cpu_socket(_spec("cpu_mid"), _spec("board_mid")) == "")
	check("so does the high-end AM5 CPU in the mid board", Compatibility.cpu_socket(_spec("cpu_high"), _spec("board_mid")) == "")
	check("an AM5 CPU in an LGA1151 board is refused, with both sockets named",
		Compatibility.cpu_socket(_spec("cpu_mid"), _spec("board_starter")) == "This CPU's socket (AM5) doesn't match the motherboard (LGA1151).",
		Compatibility.cpu_socket(_spec("cpu_mid"), _spec("board_starter")))
	check("and the other way round",
		Compatibility.cpu_socket(_spec("cpu_starter"), _spec("board_high")) == "This CPU's socket (LGA1151) doesn't match the motherboard (AM5).")


func _test_rule_ram_type() -> void:
	check("DDR4 RAM fits a DDR4 board", Compatibility.ram_type(_spec("ram_starter"), _spec("board_starter")) == "")
	check("DDR5 RAM fits either DDR5 board",
		Compatibility.ram_type(_spec("ram_mid"), _spec("board_high")) == "" and Compatibility.ram_type(_spec("ram_high"), _spec("board_mid")) == "")
	check("DDR5 RAM in a DDR4 board is refused",
		Compatibility.ram_type(_spec("ram_mid"), _spec("board_starter")) == "DDR5 RAM won't fit a DDR4 slot: the notch is in a different place.",
		Compatibility.ram_type(_spec("ram_mid"), _spec("board_starter")))
	check("and DDR4 RAM in a DDR5 board",
		Compatibility.ram_type(_spec("ram_starter"), _spec("board_mid")) == "DDR4 RAM won't fit a DDR5 slot: the notch is in a different place.")


func _test_rule_storage_slot() -> void:
	var no_m2 := {"type": "motherboard", "tier": "starter", "name": "An old board", "socket": "LGA1151", "ram": "DDR4", "m2": false}
	check("an M.2 drive fits a board with an M.2 slot", Compatibility.storage_slot(_spec("storage_mid"), _spec("board_mid")) == "")
	check("a SATA drive fits a board with an M.2 slot", Compatibility.storage_slot(_spec("storage_starter"), _spec("board_high")) == "")
	check("a SATA drive fits a board with no M.2 slot", Compatibility.storage_slot(_spec("storage_starter"), no_m2) == "")
	check("an M.2 drive on a board with no M.2 slot is refused",
		Compatibility.storage_slot(_spec("storage_high"), no_m2) == "This board has no M.2 slot for that drive.",
		Compatibility.storage_slot(_spec("storage_high"), no_m2))


func _test_rule_gpu_plug() -> void:
	check("a card with an 8-pin plug works with a supply that has one", Compatibility.gpu_plug(_spec("gpu_mid"), _spec("psu_starter")) == "")
	check("the RTX 5090 works with the supply that has a 12V-2x6 cable", Compatibility.gpu_plug(_spec("gpu_high"), _spec("psu_high")) == "")
	check("the RTX 5090 with a supply that has no 12V-2x6 cable is refused",
		Compatibility.gpu_plug(_spec("gpu_high"), _spec("psu_mid")) == "The RTX 5090 needs a 12V-2x6 cable, and this power supply doesn't have one.",
		Compatibility.gpu_plug(_spec("gpu_high"), _spec("psu_mid")))


func _test_rule_enough_power() -> void:
	check("a starter CPU and card need about 394 W", is_equal_approx(Compatibility.watts_needed(_spec("cpu_starter"), _spec("gpu_starter")), 393.75),
		Compatibility.watts_needed(_spec("cpu_starter"), _spec("gpu_starter")))
	check("so the 500 W supply is enough", Compatibility.enough_power(_spec("cpu_starter"), _spec("gpu_starter"), _spec("psu_starter")) == "")
	check("the high-end CPU and card (1056 W) run on the 1300 W supply",
		Compatibility.enough_power(_spec("cpu_high"), _spec("gpu_high"), _spec("psu_high")) == "")
	check("a supply exactly as big as needed is enough",
		Compatibility.enough_power({"watts": 100.0}, {"watts": 200.0}, {"watts": 500.0}) == "")
	check("the high-end CPU with a mid card is too much for 500 W, and the message says how much is needed",
		Compatibility.enough_power(_spec("cpu_high"), _spec("gpu_mid"), _spec("psu_starter"))
			== "The power supply is too small: the PC shuts off under load. You need about 550 W.",
		Compatibility.enough_power(_spec("cpu_high"), _spec("gpu_mid"), _spec("psu_starter")))
	check("the high-end CPU and card are too much for 850 W",
		Compatibility.enough_power(_spec("cpu_high"), _spec("gpu_high"), _spec("psu_mid"))
			== "The power supply is too small: the PC shuts off under load. You need about 1100 W.")


func _test_rules_by_name() -> void:
	var starter_board := [_spec("board_starter")]
	check("a slot's rule is called by name with the parts already in",
		Compatibility.check("cpu_socket", _spec("cpu_mid"), starter_board) == Compatibility.cpu_socket(_spec("cpu_mid"), _spec("board_starter"))
			and Compatibility.check("ram_type", _spec("ram_mid"), starter_board) != ""
			and Compatibility.check("storage_slot", _spec("storage_mid"), starter_board) == "")
	check("with no motherboard in yet there is nothing to clash with", Compatibility.check("cpu_socket", _spec("cpu_mid"), []) == "")
	var build := [_spec("board_high"), _spec("cpu_high"), _spec("ram_high"), _spec("storage_high"), _spec("gpu_high"), _spec("psu_mid")]
	check("the power check finds the missing cable first",
		Compatibility.check("power", {}, build) == "The RTX 5090 needs a 12V-2x6 cable, and this power supply doesn't have one.",
		Compatibility.check("power", {}, build))
	build[4] = _spec("gpu_mid")
	build[5] = _spec("psu_starter")
	check("then a supply that is too small",
		Compatibility.check("power", {}, build) == "The power supply is too small: the PC shuts off under load. You need about 550 W.",
		Compatibility.check("power", {}, build))
	build[5] = _spec("psu_mid")
	check("and passes when both are right", Compatibility.check("power", {}, build) == "")
	check("every rule the game uses has a name", Compatibility.RULES == Compatibility.ON_DROP + Compatibility.ON_POWER + ["power"])


## The six parts of one tier.
func _tier_build(tier: String) -> Array:
	return ["board", "cpu", "ram", "storage", "gpu", "psu"].map(func(kind) -> Dictionary: return _spec("%s_%s" % [kind, tier]))


func _test_matching_builds_pass() -> void:
	for tier in PartsCatalog.TIERS:
		var build := _tier_build(tier)
		var failed := []
		for part in build:
			for rule in Compatibility.ON_DROP:
				if part.type == rule.split("_")[0] and Compatibility.check(rule, part, build) != "":
					failed.append(rule)
		if Compatibility.check("power", {}, build) != "":
			failed.append("power")
		check("a build with every part from the %s tier passes every rule" % tier, failed.is_empty(), str(failed))


func _test_balanced_builds() -> void:
	check("a build from one tier is balanced", Compatibility.is_balanced(_tier_build("mid")))
	var build := _tier_build("mid")
	build[5] = _spec("psu_high")
	build[2] = _spec("ram_high")
	check("so is one that mixes neighbouring tiers", Compatibility.is_balanced(build))
	build[3] = _spec("storage_starter")
	check("a starter part beside a high-end one is not", not Compatibility.is_balanced(build))
	check("nothing at all is not a build", not Compatibility.is_balanced([]))


# ---- Step 6: the parts shelf, and a part's `variant` ----

const SHELF_ROWS := [["Starter", "starter"], ["Mid", "mid"], ["High", "high"]]
const SHELF_KINDS := [["Cpu", "cpu"], ["Ram", "ram"], ["Storage", "storage"], ["Gpu", "gpu"], ["Psu", "psu"]]


## The colour a part is drawn in: its Mesh's, or its Mesh's first piece.
func _part_color(part: Node) -> Color:
	var mesh := part.get_node("Mesh")
	var piece: MeshInstance3D = mesh if mesh is MeshInstance3D else mesh.find_children("*", "MeshInstance3D", true, false)[0]
	return piece.material_override.albedo_color if piece.material_override else Color.BLACK


func _test_shelf_parts_load_their_specs() -> void:
	var shelf := await _fresh(PartsShelf.instantiate())
	var catalog = PartsCatalog.shared()
	check("the shelf holds 15 parts: five kinds in three tiers",
		shelf.find_children("*", "RigidBody3D", true, false).size() == 15, shelf.find_children("*", "RigidBody3D", true, false).size())
	var specs := []
	var labels := []
	var colors := []
	for row in SHELF_ROWS:
		for kind in SHELF_KINDS:
			var where := "%s/%s" % [row[0], kind[0]]
			var part: GrabbablePart = shelf.get_node_or_null(where)
			var want: Dictionary = catalog.spec("%s_%s" % [kind[1], row[1]])
			if part == null or want.is_empty():
				specs.append(where + " is missing")
				continue
			if part.spec != want or part.part_type != StringName(kind[1]) or part.display_name != want.name:
				specs.append("%s: %s %s" % [where, part.part_type, part.spec])
			if (part.get_node("Name") as Label3D).text != want.name:
				labels.append("%s: %s" % [where, (part.get_node("Name") as Label3D).text])
			if not _part_color(part).is_equal_approx(PartsCatalog.TIER_COLORS[row[1]]):
				colors.append("%s: %s" % [where, _part_color(part)])
	check("each shelf part has its catalog specs, type and name", specs.is_empty(), str(specs))
	check("each part's label shows its name", labels.is_empty(), str(labels))
	check("each part is drawn in its tier's colour", colors.is_empty(), str(colors))
	var psu: GrabbablePart = shelf.get_node("High/Psu")
	check("for example the high-end power supply",
		psu.display_name == "Antec HCP 1300 W" and psu.spec.watts == 1300 and psu.spec.plugs == ["pcie8", "12v2x6"]
			and _part_color(psu).is_equal_approx(Color("3FB950")), str(psu.spec))


func _test_shelf_layout() -> void:
	var shelf := await _fresh(PartsShelf.instantiate())
	check("the rows run Starter, Mid, High-end from the front of the desk to the back",
		shelf.get_node("Starter").position.z > shelf.get_node("Mid").position.z and shelf.get_node("Mid").position.z > shelf.get_node("High").position.z)
	check("each row says which tier it is",
		SHELF_ROWS.map(func(row) -> String: return (shelf.get_node(row[0] + "/Label") as Label3D).text) == ["Starter", "Mid", "High-end"])
	await _settle()
	var touching := []
	var parts := shelf.find_children("*", "RigidBody3D", true, false)
	for i in parts.size():
		for j in range(i + 1, parts.size()):
			var a := _grab_box(parts[i])
			var b := _grab_box(parts[j])
			if a.intersects(b):
				touching.append("%s and %s" % [shelf.get_path_to(parts[i]), shelf.get_path_to(parts[j])])
	check("no two parts' grab shapes overlap, so each can be picked up on its own", touching.is_empty(), str(touching))
	var part: GrabbablePart = shelf.get_node("Mid/Gpu")
	await _carry_and_drop(part, Vector3(0.0, 0.5, 0.6))
	check("a shelf part let go away from any slot goes back to its place",
		not part.is_installed and part.global_position.is_equal_approx(part.home_transform.origin), part.global_position)


## A part's grab shape as a box in world space (the shelf's parts aren't turned).
func _grab_box(part: Node3D) -> AABB:
	var shape: CollisionShape3D = part.get_node("CollisionShape3D")
	var size: Vector3 = (shape.shape as BoxShape3D).size
	return AABB(shape.global_position - size * 0.5, size)


func _test_part_variants() -> void:
	var plain := RigidBody3D.new()
	plain.set_script(GrabbablePart)
	plain.part_type = &"hdmi"
	plain.display_name = "HDMI plug"
	await _fresh(plain)
	check("a part with no variant keeps the type and name it was given, and has no specs",
		plain.part_type == &"hdmi" and plain.display_name == "HDMI plug" and plain.spec.is_empty())
	var odd := RigidBody3D.new()
	odd.set_script(GrabbablePart)
	odd.name = "Odd"
	odd.variant = "cpu_quantum"
	await _fresh(odd)
	check("a variant the catalog doesn't have leaves the part as it was (and logs an error)",
		odd.spec.is_empty() and odd.part_type == &"ram")
	var cpu := RigidBody3D.new()
	cpu.set_script(GrabbablePart)
	cpu.variant = "cpu_high"
	var tag := Label3D.new()
	tag.name = "Name"
	cpu.add_child(tag)
	await _fresh(cpu)
	check("a variant gives any part its type, name, label and specs, with or without a mesh",
		cpu.part_type == &"cpu" and cpu.display_name == "AMD Ryzen 9 9950X" and tag.text == "AMD Ryzen 9 9950X" and cpu.spec.socket == "AM5",
		str(cpu.spec))


# ---- Step 7: Build your own PC ----

func _test_bonus_points() -> void:
	manager.begin("setup_pc.unbox")
	manager.add_bonus(10)
	check("a bonus before the mission is under way is ignored", manager.bonus == 0 and manager.score == 100, manager.score)
	manager.note_grab()
	manager.note_mistake()
	manager.add_bonus(5)
	check("a bonus is added on top of what the mistakes leave", manager.bonus == 5 and manager.score == 95, manager.score)
	manager.note_mistake()
	check("and a later mistake doesn't lose it", manager.score == 85 and manager.mistakes == 2, manager.score)
	manager.begin("setup_pc.unbox")
	check("the next mission starts with no bonus", manager.bonus == 0 and manager.score == 100, manager.score)


## A loose part made in code, of `type`, at `at`.
func _loose_part(parent: Node3D, part_name: String, type: String, at: Vector3) -> GrabbablePart:
	var part := RigidBody3D.new()
	part.set_script(GrabbablePart)
	part.name = part_name
	part.position = at
	part.part_type = StringName(type)
	part.display_name = part_name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.04, 0.04, 0.04)
	shape.shape = box
	part.add_child(shape)
	parent.add_child(part)
	return part


func _test_swappable_zone() -> void:
	var bench := Node3D.new()
	bench.name = "Bench"
	var bay := _port(bench, "PsuBay", "psu", Vector3(0.0, 0.0, -0.3))
	var first := _loose_part(bench, "First", "psu", Vector3(-0.3, 0.0, 0.2))
	var second := _loose_part(bench, "Second", "psu", Vector3(0.0, 0.0, 0.2))
	var gpu := _loose_part(bench, "Card", "gpu", Vector3(0.3, 0.0, 0.2))
	await _fresh(bench)
	await _carry_and_drop(first, bay.global_position)
	await _carry_and_drop(second, bay.global_position)
	check("a full slot that isn't swappable leaves a second part of its type out",
		first.is_installed and not second.is_installed and bay.installed_part == first)
	bay.swappable = true
	var given_up := []
	var order := []
	bay.swapped.connect(func(_zone, old) -> void:
		given_up.append(old)
		order.append("swapped"))
	bay.snapped.connect(func(_zone, _part) -> void: order.append("snapped"))
	await _carry_and_drop(second, bay.global_position)
	check("a swappable slot takes the new part and sends the old one back to where it came from",
		second.is_installed and bay.installed_part == second and bay.installed_parts == [second] and given_up == [first]
			and not first.is_installed and first.global_position.is_equal_approx(first.home_transform.origin), first.global_position)
	check("the swap is announced before the new part's install", order == ["swapped", "snapped"], str(order))
	check("the part that came out can be picked up again", first.can_grab())
	var turned_away := [0]
	bay.rejected.connect(func(_zone, _part) -> void: turned_away[0] += 1)
	await _carry_and_drop(gpu, bay.global_position)
	check("a swappable slot still turns away a part of the wrong type", turned_away[0] == 1 and not gpu.is_installed and bay.installed_part == second)
	bay.eject_all()
	check("emptying a slot sends its part home and leaves it ready for another",
		not bay.is_filled() and bay.installed_part == null and not second.is_installed
			and second.global_position.is_equal_approx(second.home_transform.origin))


## A loose part made in code from the catalog's `variant`.
func _catalog_part(parent: Node3D, variant: String, at: Vector3) -> GrabbablePart:
	var part := _loose_part(parent, variant, "", at)
	part.variant = variant
	return part


func _test_zone_compat_rule() -> void:
	var bench := Node3D.new()
	bench.name = "Bench"
	var tray := _port(bench, "BoardTray", "motherboard", Vector3(-0.3, 0.0, -0.3))
	var socket := _port(bench, "CpuSocket", "cpu", Vector3(0.0, 0.0, -0.3))
	socket.prerequisites.append(tray)
	socket.compat = &"cpu_socket"
	var board := _catalog_part(bench, "board_starter", Vector3(-0.3, 0.0, 0.2))
	var wrong := _catalog_part(bench, "cpu_mid", Vector3(0.0, 0.0, 0.2))
	var right := _catalog_part(bench, "cpu_starter", Vector3(0.3, 0.0, 0.2))
	await _fresh(bench)
	await _carry_and_drop(board, tray.global_position)
	var turned_away := [0]
	socket.rejected.connect(func(_zone, _part) -> void: turned_away[0] += 1)
	await _carry_and_drop(wrong, socket.global_position)
	check("a CPU whose socket doesn't match the board in the slot it needs is turned away",
		turned_away[0] == 1 and not wrong.is_installed and wrong.global_position.is_equal_approx(wrong.home_transform.origin))
	check("the zone keeps the rule's message for the mission to show",
		socket.last_problem == "This CPU's socket (AM5) doesn't match the motherboard (LGA1151).", socket.last_problem)
	await _carry_and_drop(right, socket.global_position)
	check("the CPU that matches goes in, and the message is cleared",
		right.is_installed and socket.installed_part == right and socket.last_problem == "" and turned_away[0] == 1)
	socket.swappable = true
	await _carry_and_drop(wrong, socket.global_position)
	check("a swap for a part that fails the rule is refused, and the part that was in stays",
		turned_away[0] == 2 and socket.installed_part == right and right.is_installed and not wrong.is_installed)


func _test_registry_checks_slot_rules() -> void:
	var errors := _bad_power_on(func(m): m.slots["Tower/PowerIn"].compat = "cpu_sockets")
	check("a slot with a compat rule the game doesn't have is caught, naming the slot",
		errors.size() == 1 and 'slot "Tower/PowerIn" compat must be one of cpu_socket' in errors[0], "; ".join(errors))
	errors = _bad_power_on(func(m): m.slots["Tower/PowerIn"].swappable = "yes")
	check("swappable must be true or false",
		errors.size() == 1 and 'slot "Tower/PowerIn" swappable must be true or false' in errors[0], "; ".join(errors))
	errors = _bad_power_on(func(m): m.slots["Tower/PowerIn"].swappable = true)
	check("a true or false swappable is fine", errors.is_empty(), "; ".join(errors))
	check("the build mission's own rules are all on slots that fit them", ModuleRegistry.load_from().errors.is_empty())
	errors = _bad_build(func(m): m.slots["Case/RamSlots"].compat = "cpu_socket")
	check("a rule on a slot for another kind of part is caught",
		errors.size() == 1 and 'slot "Case/RamSlots" compat cpu_socket is for a slot that accepts cpu' in errors[0], "; ".join(errors))
	errors = _bad_build(func(m): m.slots["Case/CpuSocket"].requires = [])
	check("a rule whose slot doesn't require the part it compares with is caught",
		errors.size() == 1 and 'slot "Case/CpuSocket" compat cpu_socket needs a slot that accepts motherboard in its requires' in errors[0],
		"; ".join(errors))
	errors = _bad_build(func(m): m.slots["Case/PowerButton"].requires = ["Case/BoardTray", "Case/CpuSocket", "Case/GpuSlot"])
	check("the power rule needs the power supply's slot too",
		errors.size() == 1 and 'slot "Case/PowerButton" compat power needs a slot that accepts psu' in errors[0], "; ".join(errors))
	var ram: Dictionary = PartsCatalog.shared().spec("ram_mid")
	check("a rule handed a part of another kind passes it rather than failing on a spec it doesn't have",
		Compatibility.check("cpu_socket", ram, [PartsCatalog.shared().spec("board_starter")]) == "")


func _test_registry_catalog_parts() -> void:
	# A slot that takes a type only the parts catalog has.
	var add_bay := func(m): m.slots["Case/PsuBay"] = {"accepts": "psu", "name": "power supply bay", "hint": "The power supply goes here."}
	var errors := _bad_power_on(add_bay)
	check("a slot for a catalog part type is caught in a mission that doesn't use the catalog",
		not errors.is_empty() and 'slot "Case/PsuBay" accepts "psu", but no part has that type' in errors[0], "; ".join(errors))
	errors = _bad_power_on(func(m):
		add_bay.call(m)
		m.catalog_parts = true)
	check("with catalog_parts the catalog's part types can fill slots", errors.is_empty(), "; ".join(errors))
	errors = _bad_power_on(func(m): m.catalog_parts = "yes")
	check("catalog_parts must be true or false",
		errors.size() == 1 and "setup_pc.power_on.catalog_parts: must be true or false" in errors[0], "; ".join(errors))
	check("a mission says whether it uses the catalog",
		ModuleRegistry.load_from().mission("setup_pc.power_on").catalog_parts == false)


func _test_panel_body_size() -> void:
	var holder := Node3D.new()
	var small := Node3D.new()
	small.set_script(preload("res://scripts/ui/info_panel.gd"))
	small.name = "Small"
	small.body_size = 30
	holder.add_child(small)
	var usual := Node3D.new()
	usual.set_script(preload("res://scripts/ui/info_panel.gd"))
	usual.name = "Usual"
	holder.add_child(usual)
	await _fresh(holder)
	check("a panel draws its lines at the size it is given, 40 unless told otherwise",
		small._body_label.get_theme_font_size("font_size") == 30 and usual._body_label.get_theme_font_size("font_size") == 40,
		"%s %s" % [small._body_label.get_theme_font_size("font_size"), usual._body_label.get_theme_font_size("font_size")])


func _test_long_lists_are_cut_short() -> void:
	check("up to three names are all listed", Mission.name_list(["tray", "PSU bay", "drive bay"]) == "tray, PSU bay, drive bay")
	check("one name is just that name", Mission.name_list(["tray"]) == "tray")
	check("a longer list names the first two and counts the rest",
		Mission.name_list(["tray", "socket", "slots", "bay", "card slot", "PSU bay"]) == "tray, socket and 4 more",
		Mission.name_list(["tray", "socket", "slots", "bay", "card slot", "PSU bay"]))


func _test_monitor_screen_message() -> void:
	var screen := Node3D.new()
	screen.set_script(MonitorScreen)
	await _fresh(screen)
	screen.show_message(PackedStringArray(["The power supply is too small."]))
	check("a message turns the screen on and shows only its lines",
		screen.visible and screen.is_on and not screen.is_booting and screen.text() == "\nThe power supply is too small.", screen.text())
	check("on the dark start-up screen, not the desktop", screen._style.bg_color.is_equal_approx(MonitorScreen.BOOT_COLOR))
	screen.show_desktop("Desktop ready", PackedStringArray())
	check("the desktop replaces it once the PC starts",
		screen.text() == "Desktop ready\n" and screen._style.bg_color.is_equal_approx(MonitorScreen.DESKTOP_COLOR))


const BUILD_SLOTS := {"board": "Case/BoardTray", "cpu": "Case/CpuSocket", "ram": "Case/RamSlots",
	"storage": "Case/StorageBay", "gpu": "Case/GpuSlot", "psu": "Case/PsuBay"}
const BUILD_NODES := {"cpu": "Cpu", "ram": "Ram", "storage": "Storage", "gpu": "Gpu", "psu": "Psu"}
const BUILD_ROWS := {"starter": "Starter", "mid": "Mid", "high": "High"}
const BUILD_ORDER := ["board", "cpu", "ram", "storage", "gpu", "psu"]


## Build your own PC, loaded fresh, with a monitor that doesn't wait between boot lines.
func _build_mission() -> Node3D:
	var mission := await _fresh(BuildYourOwn.instantiate())
	mission.get_node("Monitor/MonitorScreen").line_seconds = 0.0
	return mission


## The `tier` version of a kind of part: a board on the stand or a part on the shelf.
func _build_part(mission: Node3D, kind: String, tier: String) -> GrabbablePart:
	if kind == "board":
		return mission.get_node("Boards/" + BUILD_ROWS[tier])
	return mission.get_node("Shelf/%s/%s" % [BUILD_ROWS[tier], BUILD_NODES[kind]])


## Carries the `tier` version of `kind` to its slot, with the mouse. A board
## is pressed on its front edge, the part of it the stand leaves showing.
func _fit(mission: Node3D, kind: String, tier: String) -> void:
	var path := str(mission.get_path_to(_build_part(mission, kind, tier)))
	await _drag(mission, path, _over(mission, BUILD_SLOTS[kind]), Vector3(0, 0, 0.1) if kind == "board" else Vector3.ZERO)


## Fits a whole build: `tiers` gives each kind's tier, and any kind left out gets `tier`.
func _fit_all(mission: Node3D, tier: String, tiers := {}) -> void:
	for kind in BUILD_ORDER:
		await _fit(mission, kind, tiers.get(kind, tier))


func _press_power(mission: Node3D) -> void:
	await _drag(mission, "Finger", _over(mission, "Case/PowerButton"))


func _test_build_scene() -> void:
	var mission := await _build_mission()
	check("Build your own PC loads with nothing out of place", mission.problems.is_empty(), "; ".join(mission.problems))
	check("it has seven slots and nineteen parts: three boards, the shelf's fifteen and the finger",
		mission.zones.size() == 7 and mission.parts.size() == 19, "%s %s" % [mission.zones.size(), mission.parts.size()])
	var boards := ["Starter", "Mid", "High"].map(func(row) -> String: return mission.get_node("Boards/" + row).display_name)
	check("the stand holds the three motherboards", boards == ["ASRock H110 Pro BTC+", "B650", "X870E"], str(boards))
	check("the registry lists it with the Computer tasks, with the plan's card text",
		mission.config.description == "Pick parts from three tiers and build a PC that works"
			and mission.config.topic == "Compatibility" and mission.config.difficulty == "Intermediate" and mission.config.category == "computer")
	check("the monitor is off until the PC starts", not mission.get_node("Monitor/MonitorScreen").is_on)


func _test_build_board_goes_first() -> void:
	var mission := await _build_mission()
	await _fit(mission, "cpu", "mid")
	check("a CPU before any motherboard is blocked: a mistake, and it goes back to the shelf",
		manager.mistakes == 1 and not _build_part(mission, "cpu", "mid").is_installed
			and "Not yet. First finish: motherboard tray." in mission.panel.text(), mission.panel.text())
	await _press_power(mission)
	check("the power button waits for every part, and the long list is cut short",
		manager.mistakes == 2 and "Not yet. First finish: motherboard tray, CPU socket and 4 more." in mission.panel.text(), mission.panel.text())
	await _fit(mission, "board", "mid")
	check("the motherboard goes in the tray, lying flat",
		_build_part(mission, "board", "mid").is_installed and "[x] motherboard tray" in mission.panel.text()
			and "Yes! The motherboard joins every part together." in mission.panel.text(), mission.panel.text())
	await _fit(mission, "gpu", "mid")
	await _drag(mission, "Shelf/Mid/Psu", _over(mission, "Case/CpuSocket"))
	check("a power supply on the CPU socket is turned away with the socket's hint",
		manager.mistakes == 3 and "The EVGA SuperNOVA 850 P2 doesn't go there. The socket takes the processor" in mission.panel.text(),
		mission.panel.text())


func _test_build_matching_tiers_boot() -> void:
	for tier in PartsCatalog.TIERS:
		var mission := await _build_mission()
		var screen = mission.get_node("Monitor/MonitorScreen")
		await _fit_all(mission, tier)
		check("%s tier: all six parts go in with no mistakes, and nothing starts yet" % tier,
			manager.mistakes == 0 and manager.state == manager.State.ACTIVE and not screen.is_on
				and BUILD_ORDER.all(func(kind) -> bool: return _build_part(mission, kind, tier).is_installed), mission.panel.text())
		await _press_power(mission)
		check("%s tier: pressing power boots the PC and finishes the mission" % tier,
			manager.state == manager.State.SUCCESS and screen.text() == "Desktop ready\n" and "It boots!" in mission.panel.text(),
			"%s | %s" % [screen.text(), mission.panel.text()])


func _test_build_parts_that_do_not_fit() -> void:
	var mission := await _build_mission()
	await _fit(mission, "board", "starter")
	await _fit(mission, "cpu", "mid")
	check("an AM5 CPU on the LGA1151 board is turned away with the socket message, and counts as a mistake",
		manager.mistakes == 1 and not _build_part(mission, "cpu", "mid").is_installed
			and "This CPU's socket (AM5) doesn't match the motherboard (LGA1151)." in mission.panel.text(), mission.panel.text())
	await _fit(mission, "ram", "high")
	check("DDR5 memory on the DDR4 board is turned away with the notch message",
		manager.mistakes == 2 and not _build_part(mission, "ram", "high").is_installed
			and "DDR5 RAM won't fit a DDR4 slot: the notch is in a different place." in mission.panel.text(), mission.panel.text())
	await _fit(mission, "storage", "high")
	check("an NVMe drive is fine: this board has an M.2 slot", manager.mistakes == 2 and _build_part(mission, "storage", "high").is_installed)
	await _fit(mission, "cpu", "starter")
	await _fit(mission, "ram", "starter")
	check("the parts that match the board go in",
		_build_part(mission, "cpu", "starter").is_installed and _build_part(mission, "ram", "starter").is_installed and manager.mistakes == 2)


func _test_build_power_rules() -> void:
	var mission := await _build_mission()
	var screen = mission.get_node("Monitor/MonitorScreen")
	var finger: GrabbablePart = mission.get_node("Finger")
	await _fit_all(mission, "high", {"psu": "mid"})
	await _press_power(mission)
	check("an RTX 5090 on a supply with no 12V-2x6 cable won't start: a mistake, with the reason on the panel",
		manager.mistakes == 1 and manager.state == manager.State.ACTIVE and not finger.is_installed
			and "The RTX 5090 needs a 12V-2x6 cable, and this power supply doesn't have one." in mission.panel.text(), mission.panel.text())
	await _fit(mission, "psu", "high")
	check("the player can swap the power supply: the new one goes in and the old one is back on the shelf",
		_build_part(mission, "psu", "high").is_installed and not _build_part(mission, "psu", "mid").is_installed
			and _build_part(mission, "psu", "mid").global_position.is_equal_approx(_build_part(mission, "psu", "mid").home_transform.origin)
			and manager.mistakes == 1)
	await _press_power(mission)
	check("with the right supply it boots, one mistake down",
		manager.state == manager.State.SUCCESS and screen.text() == "Desktop ready\n" and manager.mistakes == 1, screen.text())
	mission = await _build_mission()
	await _fit_all(mission, "mid", {"cpu": "high", "psu": "starter"})
	await _press_power(mission)
	check("a supply that is too small won't start either, and the message says how big it should be",
		manager.mistakes == 1 and manager.state == manager.State.ACTIVE
			and "The power supply is too small: the PC shuts off under load. You need about 550 W." in mission.panel.text(), mission.panel.text())
	await _fit(mission, "cpu", "mid")
	await _press_power(mission)
	check("swapping the CPU for one that draws less also fixes it", manager.state == manager.State.SUCCESS and manager.mistakes == 1)


func _test_build_swapping_the_board() -> void:
	var mission := await _build_mission()
	await _fit(mission, "board", "mid")
	await _fit(mission, "cpu", "mid")
	await _fit(mission, "ram", "mid")
	await _fit(mission, "board", "starter")
	check("a different motherboard takes the tray, and the first one goes back to the stand",
		_build_part(mission, "board", "starter").is_installed and not _build_part(mission, "board", "mid").is_installed
			and _build_part(mission, "board", "mid").global_position.is_equal_approx(_build_part(mission, "board", "mid").home_transform.origin))
	check("the parts that were on the old board go back to the shelf, with no mistake counted",
		not _build_part(mission, "cpu", "mid").is_installed and not _build_part(mission, "ram", "mid").is_installed
			and not mission.get_node("Case/CpuSocket").is_filled() and not mission.get_node("Case/RamSlots").is_filled() and manager.mistakes == 0)
	check("and the checklist shows them as still to do",
		"[x] motherboard tray" in mission.panel.text() and "[  ] CPU socket" in mission.panel.text() and "[  ] memory slots" in mission.panel.text(),
		mission.panel.text())


func _test_build_monitor_says_why() -> void:
	var mission := await _build_mission()
	var screen = mission.get_node("Monitor/MonitorScreen")
	await _fit(mission, "board", "starter")
	await _fit(mission, "cpu", "mid")
	check("a part that doesn't fit is explained on the panel only: the PC isn't on", not screen.is_on and manager.mistakes == 1)
	await _fit_all(mission, "high", {"psu": "mid"})
	await _press_power(mission)
	check("a press of the power button that fails puts the reason on the monitor as well",
		screen.is_on and screen.text() == "\nThe RTX 5090 needs a 12V-2x6 cable, and this power supply doesn't have one."
			and "The RTX 5090 needs a 12V-2x6 cable" in mission.panel.text(), screen.text())
	await _fit(mission, "psu", "high")
	await _press_power(mission)
	check("once it starts, the desktop replaces the message", manager.state == manager.State.SUCCESS and screen.text() == "Desktop ready\n", screen.text())


func _test_build_balanced_bonus() -> void:
	var scoring: Dictionary = ModuleRegistry.load_from().mission("build_computer.build_your_own").scoring
	check("the registry scores a working build at 90, with 10 more for a balanced one",
		scoring.full == 90 and scoring.per_mistake == 10 and scoring.balanced_bonus == 10, str(scoring))
	check("missions with no bonus have a bonus of zero", ModuleRegistry.load_from().mission("setup_pc.unbox").scoring.balanced_bonus == 0)
	var errors := _bad_power_on(func(m): m.scoring.balanced_bonus = 2.5)
	check("a bonus that isn't a whole number is caught",
		errors.size() == 1 and "setup_pc.power_on.scoring.balanced_bonus: must be a whole number" in errors[0], "; ".join(errors))
	var mission := await _build_mission()
	await _fit_all(mission, "mid")
	check("nothing is added before the PC starts", manager.bonus == 0 and manager.score == 90, manager.score)
	await _press_power(mission)
	check("a build from one tier is balanced: 90 plus the bonus is 100",
		manager.state == manager.State.SUCCESS and manager.bonus == 10 and manager.score == 100, "%s %s" % [manager.bonus, manager.score])
	mission = await _build_mission()
	await _fit_all(mission, "mid", {"cpu": "high", "ram": "high", "psu": "high"})
	await _press_power(mission)
	check("mixing neighbouring tiers is still balanced", manager.state == manager.State.SUCCESS and manager.score == 100, manager.score)
	mission = await _build_mission()
	await _fit_all(mission, "mid", {"storage": "starter", "psu": "high"})
	await _press_power(mission)
	check("a starter part beside a high-end one works but earns no bonus: 90",
		manager.state == manager.State.SUCCESS and manager.bonus == 0 and manager.score == 90, "%s %s" % [manager.bonus, manager.score])
	mission = await _build_mission()
	await _fit(mission, "cpu", "starter")
	await _fit_all(mission, "starter")
	await _press_power(mission)
	check("a mistake on the way still costs its points: a balanced build after one mistake is 90",
		manager.state == manager.State.SUCCESS and manager.mistakes == 1 and manager.score == 90, "%s %s" % [manager.mistakes, manager.score])


func _test_build_results_card() -> void:
	check("a build is summed up by its parts' names, CPU and graphics card first",
		Compatibility.summary(_tier_build("mid")) == "AMD Ryzen 5 7600 + RTX 4060 Ti + DDR5-5600 2x16 GB + 1 TB NVMe Gen4 + B650 + EVGA SuperNOVA 850 P2",
		Compatibility.summary(_tier_build("mid")))
	check("a part that is missing is left out", Compatibility.summary([_spec("psu_high"), _spec("cpu_starter")]) == "Intel Core i5-6500 + Antec HCP 1300 W")
	var mission := await _build_mission()
	await _fit_all(mission, "mid")
	await _press_power(mission)
	check("the success panel lists the build",
		"Your build: AMD Ryzen 5 7600 + RTX 4060 Ti + DDR5-5600 2x16 GB + 1 TB NVMe Gen4 + B650 + EVGA SuperNOVA 850 P2" in mission.panel.text(),
		mission.panel.text())
	check("with the bonus and the score", "Balanced build: +10" in mission.panel.text() and "Score: 100" in mission.panel.text(), mission.panel.text())
	mission = await _build_mission()
	await _fit_all(mission, "mid", {"storage": "starter", "psu": "high"})
	await _press_power(mission)
	check("a build with no bonus lists its parts and its score only",
		"Your build: AMD Ryzen 5 7600 + RTX 4060 Ti + DDR5-5600 2x16 GB + Samsung 860 EVO 250 GB (SATA) + B650 + Antec HCP 1300 W" in mission.panel.text()
			and not "Balanced build" in mission.panel.text() and "Score: 90" in mission.panel.text(), mission.panel.text())
	var other := await _fresh(Unbox.instantiate())
	check("other missions add nothing of their own to the success panel", other._result_extras().is_empty())


# ---- The headset: reaching for a big part ----

func _test_big_parts_are_grabbed_by_the_middle() -> void:
	var mission := await _fresh(Unbox.instantiate())
	var hands = mission.get_node("Room/VRGrabber")
	var tower: GrabbablePart = mission.get_node("Tower")
	var keyboard: GrabbablePart = mission.get_node("Keyboard")
	var middle: Vector3 = (tower.get_node("CollisionShape3D") as Node3D).global_position
	check("the boxed tower's origin is at one end, too far from its middle for a hand there",
		tower.global_position.distance_to(middle) > hands.grab_radius, tower.global_position.distance_to(middle))
	check("so it has a grab point at its middle", tower.grab_position().is_equal_approx(middle), tower.grab_position())
	check("a part with no grab point is reached for at its origin", keyboard.grab_position() == keyboard.global_position)
	# The headset's grabber looks through the scene being played.
	current_scene = mission
	check("a hand at the middle of the tower picks the tower", hands.part_near(middle) == tower, hands.part_near(middle))
	check("a hand over the keyboard picks the keyboard", hands.part_near(keyboard.global_position + Vector3(0, 0.03, 0)) == keyboard)
	check("a hand away from every part picks nothing", hands.part_near(Vector3(0, 1.5, 0)) == null)
	current_scene = null


# ---- After review: a finished mission stays as it ended ----

func _test_build_is_frozen_once_it_boots() -> void:
	var mission := await _fresh(BuildYourOwn.instantiate())
	var screen = mission.get_node("Monitor/MonitorScreen")
	screen.line_seconds = 0.2
	await _fit_all(mission, "mid")
	await _press_power(mission)
	check("the PC is starting up, so there is time to reach for another part",
		manager.state == manager.State.SUCCESS and screen.is_booting, manager.state)
	await _fit(mission, "gpu", "high")
	check("a graphics card dropped in during the boot is not swapped in",
		_build_part(mission, "gpu", "mid").is_installed and not _build_part(mission, "gpu", "high").is_installed
			and mission.get_node("Finger").is_installed)
	await _fit(mission, "board", "high")
	check("nor is another motherboard: every part stays in the case",
		BUILD_ORDER.all(func(kind) -> bool: return _build_part(mission, kind, "mid").is_installed))
	if screen.is_booting:
		await screen.boot_finished
	await process_frame
	check("the results card lists the build that booted, with its bonus",
		"Your build: AMD Ryzen 5 7600 + RTX 4060 Ti" in mission.panel.text() and not "RTX 5090" in mission.panel.text()
			and "Balanced build: +10" in mission.panel.text() and manager.score == 100, mission.panel.text())
	await _fit(mission, "psu", "starter")
	check("and the case stays as it was after the card is up", _build_part(mission, "psu", "mid").is_installed
		and not _build_part(mission, "psu", "starter").is_installed and manager.mistakes == 0)


func _test_finished_mission_takes_no_more_parts() -> void:
	var mission := await _fresh(ConnectPeripherals.instantiate())
	await _drag_all(mission, [["HdmiCable/EndA", "Tower/GpuHdmi"], ["HdmiCable/EndB", "Monitor/HdmiIn"],
		["KeyboardCable/EndB", "Tower/Usb1"], ["MouseCable/EndB", "Tower/Usb2"]])
	check("when a mission ends its slots are locked",
		manager.state == manager.State.SUCCESS and mission.zones.all(func(z) -> bool: return z.locked))
	var bench_part := _loose_part(mission, "Spare", "usb", Vector3(0.0, 0.9, 0.3))
	await _settle()
	var port: SnapZone = mission.get_node("Tower/Usb1")
	port.swappable = true
	await _carry_and_drop(bench_part, _over(mission, "Tower/Usb1"))
	check("a locked slot takes nothing and counts nothing, even one that could swap",
		not bench_part.is_installed and port.installed_part == mission.get_node("KeyboardCable/EndB") and manager.mistakes == 0)


func _test_swap_empties_the_whole_chain() -> void:
	# A registry where the graphics card waits on the CPU, not on the board.
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules.json"))
	for module in data.modules:
		for m in module.missions:
			if m.id == "build_your_own":
				m.slots["Case/GpuSlot"].requires = ["Case/CpuSocket"]
	var registry = ModuleRegistry.new()
	registry.read(data)
	check("that registry is still a valid one", registry.errors.is_empty(), "; ".join(registry.errors))
	manager.use_registry(registry)
	var mission := await _build_mission()
	await _fit(mission, "board", "mid")
	await _fit(mission, "cpu", "mid")
	await _fit(mission, "gpu", "mid")
	await _fit(mission, "board", "high")
	check("swapping the motherboard sends the CPU back, and the graphics card that was waiting on the CPU",
		not _build_part(mission, "cpu", "mid").is_installed and not _build_part(mission, "gpu", "mid").is_installed
			and not mission.get_node("Case/GpuSlot").is_filled() and manager.mistakes == 0)
	check("the checklist shows the graphics card slot as waiting on the CPU again",
		"[  ] graphics card slot  (after: CPU socket)" in mission.panel.text(), mission.panel.text())
