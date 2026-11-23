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
		_test_cable_requires_order, _test_cable_fixed_to_a_device]


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
