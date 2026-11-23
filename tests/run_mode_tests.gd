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
const MonitorScreen := preload("res://scripts/parts/monitor_screen.gd")
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
		_test_rules_by_name, _test_matching_builds_pass, _test_balanced_builds]


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
## camera, carry it above the table to over `to`, let go.
func _drag(mission: Node3D, part_path: String, to: Vector3) -> void:
	var part: GrabbablePart = mission.get_node(part_path)
	var grabber = mission.get_node("Room/MouseGrabber")
	var camera: Camera3D = mission.get_node("Room/Camera3D")
	var middle: Vector3 = (part.get_node("CollisionShape3D") as Node3D).global_position
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
