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
		_test_connect_perfect_run, _test_connect_wrong_ports, _test_long_title_fits_the_panel]


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
	check("its missions come in the order they are played",
		ids.slice(0, 2) == ["setup_pc.unbox", "setup_pc.connect_peripherals"], str(ids))
	var thin := []
	for id in ids:
		var m: Dictionary = registry.mission(id)
		if m.description == "" or m.topic == "" or m.difficulty == "":
			thin.append(id)
	check("each one has the description, topic and difficulty Free Play shows", thin.is_empty(), str(thin))
	check("the first two are Beginner tasks",
		registry.mission("setup_pc.unbox").difficulty == "Beginner" and registry.mission("setup_pc.connect_peripherals").difficulty == "Beginner")


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
