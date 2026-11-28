extends SceneTree
## Headless checks. Run from the project folder:
##
##   godot --headless --import          (once, after cloning or adding files)
##   godot --headless --script res://tests/run_tests.gd
##
## Exit code 0 means every check passed. Tests load real scenes, move parts the
## way a grabber does (often through the real mouse grabber and camera) and step
## physics, so the SnapZones' Area3Ds see the overlaps exactly as in the game.

const Workbench := preload("res://scenes/workbench.tscn")
const IdentifyComponents := preload("res://scenes/build_computer/identify_components.tscn")
const AssembleSystem := preload("res://scenes/build_computer/assemble_system.tscn")
const ExecuteTask := preload("res://scenes/build_computer/execute_task.tscn")
const AddCapacity := preload("res://scenes/build_computer/add_capacity.tscn")
const DiagnoseFailure := preload("res://scenes/build_computer/diagnose_failure.tscn")
const GrabbablePart := preload("res://scripts/grabbable_part.gd")
const ModuleRegistry := preload("res://scripts/module_registry.gd")
const TrainingManagerScript := preload("res://scripts/training_manager.gd")

## Nodes under the root that stay between tests.
const AUTOLOADS := [&"TrainingManager", &"ScoreReporter"]

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
	# The project's autoloads (TrainingManager, ScoreReporter) are loaded for
	# --script runs too; add the TrainingManager only if it's missing.
	manager = root.get_node_or_null("TrainingManager")
	if manager == null:
		manager = TrainingManagerScript.new()
		manager.name = "TrainingManager"
		root.add_child(manager)
	for test in [
		_test_registry_loads, _test_registry_catches_mistakes, _test_manager_flow,
		_test_right_part_snaps, _test_drop_outside_goes_home, _test_wrong_part_is_rejected,
		_test_installed_part_cannot_be_grabbed, _test_mouse_grabber_end_to_end,
		_test_practice_mission_from_registry_only, _test_mission_intro, _test_mission_perfect_run,
		_test_mission_mistake_gives_hint_and_costs_points, _test_every_mission_scene_is_clean,
		_test_scoring_is_data, _test_scene_registry_mismatch_is_reported,
		_test_registry_checks_requires, _test_next_mission_order,
		_test_assemble_power_goes_last, _test_assemble_perfect_run,
		_test_execute_task_data_flow, _test_registry_checks_capacity_and_working,
		_test_add_capacity_routes_jobs, _test_diagnose_failure, _test_diagnose_with_the_multimeter,
		_test_registry_checks_probes, _test_registry_messages, _test_success_panel_order, _test_feedback_reads_the_same,
	]:
		manager.use_registry(ModuleRegistry.load_from())
		manager.now_ms = Time.get_ticks_msec
		manager.auto_advance = false
		await test.call()
	print("\n%s" % ("ALL PASSED" if _failures.is_empty() else "%d FAILED" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)


func check(label: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + label + ("" if ok or detail == "" else "   [%s]" % detail))
	if not ok:
		_failures.append(label)


func _fresh(scene: PackedScene = Workbench) -> Node3D:
	for child in root.get_children():
		if not child.name in AUTOLOADS:
			child.queue_free()
	await process_frame
	var node := scene.instantiate()
	root.add_child(node)
	await _settle()
	return node


func _settle(frames := 3) -> void:
	for i in frames:
		await physics_frame


## A fake clock: each call returns the next number from `times` (ms).
func _clock(times: Array) -> Callable:
	return func() -> int: return times.pop_front()


func _above(scene: Node3D, slot_path: String) -> Vector3:
	return (scene.get_node(slot_path) as Node3D).global_position + Vector3(0.0, 0.05, 0.0)


## What a grabber does, without the mouse: pick up, carry to `to`, drop.
func _carry_and_drop(part: GrabbablePart, to: Vector3) -> void:
	part.grab()
	part.global_position = to
	await _settle()
	part.drop()
	await _settle()


## The real input path: grab through the camera, carry, release.
func _place(scene: Node3D, part_name: String, to: Vector3) -> void:
	var part: GrabbablePart = scene.get_node(part_name)
	var grabber = scene.get_node("Room/MouseGrabber")
	var camera: Camera3D = scene.get_node("Room/Camera3D")
	var grabbed = grabber.try_grab_at(camera.unproject_position(part.global_position + Vector3(0, 0.005, 0)))
	if grabbed != part:
		check("grabbing the %s through the camera" % part_name, false, "got %s" % grabbed)
		return
	part.global_position = to
	await _settle()
	grabber.release()
	await _settle()


# ---- Step 4: the module registry and the TrainingManager ----

func _test_registry_loads() -> void:
	var registry = ModuleRegistry.load_from()
	check("data/modules.json loads with no problems", registry.errors.is_empty(), "; ".join(registry.errors))
	check("it lists the Build a Computer missions first, in order",
		registry.modules[0].mission_ids == ["build_computer.install_ram",
			"build_computer.identify_components", "build_computer.assemble_system", "build_computer.execute_task",
			"build_computer.add_capacity", "build_computer.diagnose_failure", "build_computer.build_your_own",
			"build_computer.swap_ssd", "build_computer.cooler_paste"],
		str(registry.modules))
	check("a mission keeps its module title and full id",
		registry.mission("build_computer.identify_components").get("module_title") == "Build a Computer")


func _bad(mutate: Callable) -> PackedStringArray:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules.json"))
	mutate.call(data.modules[0].missions[1])
	var registry = ModuleRegistry.new()
	registry.read(data)
	return registry.errors


func _test_registry_catches_mistakes() -> void:
	var errors := _bad(func(m): m.slots["Motherboard/RamSlot"].accepts = "rom")
	check("a slot that accepts a type no part has is caught, naming the slot",
		errors.size() >= 1 and 'slot "Motherboard/RamSlot" accepts "rom"' in errors[0], str(errors))
	errors = _bad(func(m): m.erase("scoring"))
	check("missing scoring is caught", errors.size() == 1 and ".scoring" in errors[0], str(errors))
	errors = _bad(func(m): m.scene = "res://scenes/nope.tscn")
	check("a scene that doesn't exist is caught", errors.size() == 1 and "doesn't exist" in errors[0], str(errors))
	errors = _bad(func(m): m.id = "install_ram")
	check("a mission id used twice is caught", errors.size() == 1 and "used twice" in errors[0], str(errors))
	errors = _bad(func(m): m.slots["Extra"] = {"accepts": "cpu", "name": "2nd socket", "hint": "x"})
	check("two cpu slots with one CPU is caught (it could never finish)", errors.size() == 1 and 'slots need 2 "cpu" part(s)' in errors[0], str(errors))
	errors = _bad(func(m): m.intro = [])
	check("an empty intro is caught", errors.size() == 1 and ".intro" in errors[0], str(errors))


func _test_manager_flow() -> void:
	check("an unknown mission returns nothing and stays idle",
		manager.begin("build_computer.nope").is_empty() and manager.state == manager.State.IDLE)
	manager.now_ms = _clock([5000, 65000])
	var done := []
	var on_done := func(id, score, secs): done.append([id, score, secs])
	manager.module_completed.connect(on_done)
	manager.begin("build_computer.identify_components")
	manager.note_mistake()
	check("mistakes before the first grab don't count", manager.mistakes == 0)
	manager.note_grab()
	manager.note_mistake()
	manager.complete()
	manager.complete()
	manager.module_completed.disconnect(on_done)
	check("module_completed fires once with (module_id, score, duration_s)",
		done == [["build_computer.identify_components", 90, 60]], str(done))
	check("attempts is 1 plus the mistakes", manager.attempts == 2)


# ---- Step 1: snap mechanics, on the install_ram practice mission ----

func _test_right_part_snaps() -> void:
	var bench := await _fresh()
	var ram: GrabbablePart = bench.get_node("RamStick")
	var slot = bench.get_node("Motherboard/RamSlot")
	var events := []
	slot.snapped.connect(func(zone, part): events.append([zone, part]))
	await _carry_and_drop(ram, _above(bench, "Motherboard/RamSlot"))
	check("RAM dropped over the RAM slot snaps in", ram.is_installed and events.size() == 1)
	check("the slot reports the RAM as installed", slot.installed_part == ram)
	var snap: Transform3D = slot.get_node("SnapPoint").global_transform
	check("the RAM sits exactly on the slot's snap point",
		ram.global_transform.origin.distance_to(snap.origin) < 0.0001, str(ram.global_transform.origin, " vs ", snap.origin))


func _test_drop_outside_goes_home() -> void:
	var bench := await _fresh()
	var ram: GrabbablePart = bench.get_node("RamStick")
	var home := ram.global_transform
	await _carry_and_drop(ram, Vector3(0.4, 0.95, 0.2))
	check("RAM dropped away from the slot is not installed", not ram.is_installed)
	check("and goes back where it was picked up", ram.global_transform.is_equal_approx(home))


func _test_wrong_part_is_rejected() -> void:
	var bench := await _fresh()
	var cpu: GrabbablePart = GrabbablePart.new()
	cpu.part_type = &"cpu"
	cpu.display_name = "CPU"
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(0.04, 0.005, 0.04)
	cpu.add_child(shape)
	cpu.position = Vector3(0.3, 0.9, 0.15)
	bench.add_child(cpu)
	await _settle()
	manager.note_grab()
	var slot = bench.get_node("Motherboard/RamSlot")
	var rejected := []
	slot.rejected.connect(func(zone, part): rejected.append(part))
	var home := cpu.global_transform
	await _carry_and_drop(cpu, _above(bench, "Motherboard/RamSlot"))
	check("a CPU dropped on the RAM slot is rejected", rejected == [cpu] and not cpu.is_installed)
	check("and goes back home", cpu.global_transform.is_equal_approx(home))
	check("the slot stays empty", slot.installed_part == null)
	check("the panel explains with the slot's hint from the registry",
		"The CPU doesn't go there. The long slot is for memory" in bench.panel.text(), bench.panel.text())


func _test_installed_part_cannot_be_grabbed() -> void:
	var bench := await _fresh()
	var ram: GrabbablePart = bench.get_node("RamStick")
	await _carry_and_drop(ram, _above(bench, "Motherboard/RamSlot"))
	check("an installed part can't be picked up again", not ram.grab() and not ram.is_held)


func _test_mouse_grabber_end_to_end() -> void:
	var bench := await _fresh()
	var ram: GrabbablePart = bench.get_node("RamStick")
	var grabber = bench.get_node("Room/MouseGrabber")
	var camera: Camera3D = bench.get_node("Room/Camera3D")
	var on_ram := camera.unproject_position(ram.global_position + Vector3(0, 0.0155, 0))
	var grabbed = grabber.try_grab_at(on_ram)
	check("pressing on the RAM through the camera picks it up", grabbed == ram and ram.is_held, "screen %s" % on_ram)
	var target := _above(bench, "Motherboard/RamSlot")
	target.y = grabber.carry_height
	grabber.carry_to(camera.unproject_position(target))
	await _settle()
	check("moving the mouse carries the RAM over the slot at carry height",
		ram.global_position.distance_to(target) < 0.005, str(ram.global_position, " vs ", target))
	grabber.release()
	await _settle()
	check("releasing the mouse drops it into the slot", ram.is_installed and grabber.held == null)
	check("pressing on empty table picks up nothing",
		grabber.try_grab_at(camera.unproject_position(Vector3(0.45, 0.9, 0.25))) == null)


func _test_practice_mission_from_registry_only() -> void:
	# The step 1 workbench has no script of its own any more: it's the
	# build_computer.install_ram entry in data/modules.json on mission.gd.
	var bench := await _fresh()
	check("the workbench is a registry mission with no problems", bench.problems.is_empty(), "; ".join(bench.problems))
	check("its part and slot got their names from the registry",
		bench.get_node("RamStick").display_name == "RAM stick" and bench.get_node("Motherboard/RamSlot").accepts == &"ram")
	check("its panel shows the registry's intro", "Drag the RAM stick into the RAM slot." in bench.panel.text(), bench.panel.text())
	await _place(bench, "RamStick", _above(bench, "Motherboard/RamSlot"))
	check("installing the RAM completes it with the registry's success text",
		manager.state == manager.State.SUCCESS and "RAM installed!" in bench.panel.text(), bench.panel.text())


# ---- Step 2: the "Identify components" mission ----

func _test_mission_intro() -> void:
	var mission := await _fresh(IdentifyComponents)
	check("the mission starts in Intro", manager.state == manager.State.INTRO)
	check("it has four slots and four parts, all from the registry",
		mission.zones.size() == 4 and mission.parts.size() == 4 and mission.problems.is_empty(), "; ".join(mission.problems))
	check("the intro panel explains the task", "four things" in mission.panel.text(), mission.panel.text())
	check("the part tags show the registry names", mission.get_node("Keyboard/Name").text == "Keyboard", mission.get_node("Keyboard/Name").text)


func _test_mission_perfect_run() -> void:
	var mission := await _fresh(IdentifyComponents)
	manager.now_ms = _clock([1000, 96000])
	var results := []
	var on_done := func(id, score, secs): results.append([id, score, secs, manager.attempts])
	manager.module_completed.connect(on_done)
	await _place(mission, "Cpu", _above(mission, "Motherboard/CpuSocket"))
	check("first grab starts the mission", manager.state == manager.State.ACTIVE)
	check("the checklist ticks the CPU socket", "[x] CPU socket" in mission.panel.text(), mission.panel.text())
	await _place(mission, "Ram", _above(mission, "Motherboard/RamSlot"))
	await _place(mission, "Ssd", _above(mission, "Motherboard/M2Slot"))
	check("three of four placed is not finished yet", manager.state == manager.State.ACTIVE)
	await _place(mission, "Keyboard", _above(mission, "UsbPad"))
	manager.module_completed.disconnect(on_done)
	check("all four placed: Success", manager.state == manager.State.SUCCESS)
	check("module_completed fires once with the API's fields",
		results == [["build_computer.identify_components", 100, 95, 1]], str(results))
	check("the success panel shows score and time", "Score: 100" in mission.panel.text() and "1:35" in mission.panel.text(), mission.panel.text())


func _test_mission_mistake_gives_hint_and_costs_points() -> void:
	var mission := await _fresh(IdentifyComponents)
	manager.now_ms = _clock([0, 60000])
	var results := []
	var on_done := func(id, score, secs): results.append([score, secs, manager.attempts])
	manager.module_completed.connect(on_done)
	await _place(mission, "Ssd", _above(mission, "Motherboard/RamSlot"))
	check("the SSD on the RAM slot is a mistake", manager.mistakes == 1 and not mission.get_node("Ssd").is_installed)
	check("the panel says why, with the RAM slot's hint", "holds what the CPU is working on" in mission.panel.text(), mission.panel.text())
	await _place(mission, "Keyboard", _above(mission, "Motherboard/CpuSocket"))
	check("the keyboard covers three slots but counts as one mistake", manager.mistakes == 2, str(manager.mistakes))
	check("and the CPU socket is the one that explains", "for the processor" in mission.panel.text(), mission.panel.text())
	for pair in [["Cpu", "Motherboard/CpuSocket"], ["Ram", "Motherboard/RamSlot"], ["Ssd", "Motherboard/M2Slot"], ["Keyboard", "UsbPad"]]:
		await _place(mission, pair[0], _above(mission, pair[1]))
	manager.module_completed.disconnect(on_done)
	check("two mistakes: score 80, 3 attempts, 60 s", results == [[80, 60, 3]], str(results))


func _test_every_mission_scene_is_clean() -> void:
	# Every mission in the registry loads with no scene/registry mismatch, and no
	# part starts inside a slot that could take it (it would install itself on
	# its first drop), unless it starts installed there (a network cable that
	# starts plugged in). A part may start inside a slot that can't take it yet:
	# the old SSD in its drive bay, under steps that come first (Phase 5).
	for module in manager.registry.modules:
		for full_id in module.mission_ids:
			var mission := await _fresh(load(manager.registry.mission(full_id).scene))
			var overlapping := []
			for zone in mission.zones:
				for body in zone.get_overlapping_bodies():
					if body is GrabbablePart and body.installed_zone != zone and zone.can_take(body):
						overlapping.append("%s in %s" % [body.name, zone.name])
			check("%s: loads cleanly, no part starts inside a slot" % full_id,
				mission.problems.is_empty() and overlapping.is_empty() and mission.zones.size() > 0,
				"; ".join(mission.problems) + str(overlapping))


func _test_scoring_is_data() -> void:
	# Changing the registry, not code, changes the game.
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules.json"))
	data.modules[0].missions[1].scoring.per_mistake = 25
	var registry = ModuleRegistry.new()
	registry.read(data)
	manager.use_registry(registry)
	var mission := await _fresh(IdentifyComponents)
	await _place(mission, "Ssd", _above(mission, "Motherboard/RamSlot"))
	check("per_mistake 25 in the registry makes one mistake cost 25 points", manager.score == 75, str(manager.score))


func _test_scene_registry_mismatch_is_reported() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules.json"))
	data.modules[0].missions[1].slots["Motherboard/GpuSlot"] = {"accepts": "cpu", "name": "GPU slot", "hint": "x"}
	data.modules[0].missions[1].parts["Gpu"] = {"type": "cpu", "name": "GPU"}
	var registry = ModuleRegistry.new()
	registry.read(data)
	manager.use_registry(registry)
	var mission := await _fresh(IdentifyComponents)
	check("a registry slot missing from the scene is reported",
		mission.problems.has('slot "Motherboard/GpuSlot" isn\'t a SnapZone in res://scenes/build_computer/identify_components.tscn'),
		"; ".join(mission.problems))
	check("so is a registry part missing from the scene", mission.problems.size() == 2, "; ".join(mission.problems))


# ---- Module 1 missions 3 and 4: requires, pass-through, roles ----

func _test_registry_checks_requires() -> void:
	var errors := _bad(func(m): m.slots["UsbPad"]["requires"] = ["Motherboard/Nope"])
	check("requires naming a slot that doesn't exist is caught", errors.size() == 1 and 'requires "Motherboard/Nope"' in errors[0], str(errors))
	errors = _bad(func(m):
		m.slots["UsbPad"]["requires"] = ["Motherboard/CpuSocket"]
		m.slots["Motherboard/CpuSocket"]["requires"] = ["UsbPad"])
	check("a requires loop is caught (it could never finish)", errors.size() == 2 and "requires loop" in errors[0], str(errors))
	errors = _bad(func(m): m.slots["UsbPad"]["pass_through"] = "yes")
	check("pass_through that isn't true/false is caught", errors.size() == 1 and "pass_through" in errors[0], str(errors))


func _test_next_mission_order() -> void:
	check("missions chain in registry order",
		manager.next_mission_id("build_computer.install_ram") == "build_computer.identify_components"
			and manager.next_mission_id("build_computer.assemble_system") == "build_computer.execute_task")
	var last: String = manager.registry.modules[0].mission_ids.back()
	check("the module's last mission has no next one", manager.next_mission_id(last) == "", last)


func _test_assemble_power_goes_last() -> void:
	var mission := await _fresh(AssembleSystem)
	await _place(mission, "PowerCable", _above(mission, "PowerSocket"))
	check("power before the parts is blocked: a mistake, cable goes home",
		manager.mistakes == 1 and not mission.get_node("PowerCable").is_installed, str(manager.mistakes))
	check("the panel says what has to come first",
		"Not yet. First finish: motherboard tray, PSU bay, drive bay." in mission.panel.text(), mission.panel.text())
	check("and the checklist marks the socket as waiting",
		"[  ] power socket  (after: motherboard tray, PSU bay, drive bay)" in mission.panel.text(), mission.panel.text())


func _test_assemble_perfect_run() -> void:
	var mission := await _fresh(AssembleSystem)
	manager.now_ms = _clock([0, 70000])
	var results := []
	var on_done := func(id, score, secs): results.append([id, score, secs])
	manager.module_completed.connect(on_done)
	await _place(mission, "Psu", _above(mission, "PsuBay"))
	check("installing the PSU explains its role", "The PSU turns wall power into the steady voltages" in mission.panel.text(), mission.panel.text())
	await _place(mission, "Motherboard", _above(mission, "MotherboardTray"))
	await _place(mission, "Ssd", _above(mission, "DriveBay"))
	await _place(mission, "PowerCable", _above(mission, "PowerSocket"))
	manager.module_completed.disconnect(on_done)
	check("power last completes the mission with full marks",
		results == [["build_computer.assemble_system", 100, 70]], str(results))


func _test_execute_task_data_flow() -> void:
	var mission := await _fresh(ExecuteTask)
	manager.now_ms = _clock([0, 45000])
	var results := []
	var on_done := func(id, score, secs): results.append([score, secs, manager.attempts])
	manager.module_completed.connect(on_done)
	var photo: GrabbablePart = mission.get_node("PhotoFile")
	await _place(mission, "PhotoFile", _above(mission, "CpuStage"))
	check("straight from storage to the CPU is blocked (data goes to RAM first)",
		manager.mistakes == 1 and "First finish: memory (RAM)." in mission.panel.text(), mission.panel.text())
	await _place(mission, "PhotoFile", _above(mission, "MemoryStage"))
	var ram_snap: Vector3 = mission.get_node("MemoryStage/SnapPoint").global_position
	check("into memory: the photo sits on the RAM and stays free to move on",
		mission.get_node("MemoryStage").is_filled() and not photo.is_installed and photo.global_position.distance_to(ram_snap) < 0.0001)
	check("the panel explains the step", "copied from storage into memory" in mission.panel.text(), mission.panel.text())
	await _place(mission, "PhotoFile", _above(mission, "ScreenStage"))
	check("memory straight to the screen is blocked (the CPU hasn't processed it)",
		manager.mistakes == 2 and photo.global_position.distance_to(ram_snap) < 0.0001, mission.panel.text())
	await _place(mission, "PhotoFile", _above(mission, "CpuStage"))
	await _place(mission, "PhotoFile", _above(mission, "ScreenStage"))
	manager.module_completed.disconnect(on_done)
	check("RAM, then CPU, then screen completes it: score 80, 45 s, 3 attempts",
		results == [[80, 45, 3]] and photo.is_installed, str(results))


# ---- Module 1 advanced missions: capacity and working slots ----

func _test_registry_checks_capacity_and_working() -> void:
	var errors := _bad(func(m): m.slots["UsbPad"]["capacity"] = 2)
	check("a slot needing 2 parts when only 1 has the type is caught", errors.size() == 1 and 'slots need 2 "input"' in errors[0], str(errors))
	errors = _bad(func(m): m.slots["UsbPad"]["capacity"] = 0)
	check("capacity 0 is caught", errors.size() >= 1 and "capacity" in errors[0], str(errors))
	errors = _bad(func(m): m.slots["Extra"] = {"working": true, "name": "fan", "hint": "The fan is fine."})
	check("a working slot needs no accepts and no part", errors.is_empty(), str(errors))
	errors = _bad(func(m): m.slots["Extra"] = {"working": "yes", "name": "fan", "hint": "x"})
	check("working that isn't true/false is caught", errors.size() >= 1, str(errors))


func _test_add_capacity_routes_jobs() -> void:
	var mission := await _fresh(AddCapacity)
	manager.now_ms = _clock([0, 90000])
	var results := []
	var on_done := func(id, score, secs): results.append([score, secs, manager.attempts])
	manager.module_completed.connect(on_done)
	await _place(mission, "Pixels", _above(mission, "GpuJobs"))
	check("a GPU job before the GPU is installed is blocked",
		manager.mistakes == 1 and "First finish: graphics card slot." in mission.panel.text(), mission.panel.text())
	await _place(mission, "Gpu", _above(mission, "GpuSlot"))
	await _place(mission, "Pixels", _above(mission, "CpuJobs"))
	check("a parallel job on the CPU is turned away with the CPU's hint",
		manager.mistakes == 2 and "The CPU has a few very fast cores" in mission.panel.text(), mission.panel.text())
	await _place(mission, "GameRules", _above(mission, "CpuJobs"))
	check("one of two CPU jobs: the checklist counts it", "[  ] CPU jobs (1 of 2)" in mission.panel.text(), mission.panel.text())
	await _place(mission, "Password", _above(mission, "CpuJobs"))
	var a: Vector3 = mission.get_node("GameRules").global_position
	var b: Vector3 = mission.get_node("Password").global_position
	check("two jobs in one queue sit side by side, 5 cm apart", is_equal_approx(a.distance_to(b), 0.05), str(a.distance_to(b)))
	await _place(mission, "Pixels", _above(mission, "GpuJobs"))
	await _place(mission, "TrainAi", _above(mission, "GpuJobs"))
	manager.module_completed.disconnect(on_done)
	check("all jobs routed: done with 2 mistakes, score 80, 90 s", results == [[80, 90, 3]], str(results))


## Phase 5, step 7: the multimeter tests a part instead of guessing. The old
## way (drop a spare on the part you think is broken) still works, above.
func _test_diagnose_with_the_multimeter() -> void:
	var mission := await _fresh(DiagnoseFailure)
	var meter = mission.get_node("Multimeter")
	meter.return_delay_s = 0.0
	meter.return_time_s = 0.0
	check("Diagnose a failure has a multimeter, and still loads cleanly", mission.problems.is_empty(), "; ".join(mission.problems))
	check("the intro says to try it", "Test a part with the multimeter" in mission.panel.text(), mission.panel.text())
	await _place(mission, "Multimeter", _above(mission, "PsuCheck"))
	check("on the power supply it reads 12.1 V on its own display", meter.get_node("Display").text == "12.1 V",
		meter.get_node("Display").text)
	check("and the panel says what that means", "Multimeter on the power supply: 12.1 V. The power supply gives a steady 12 V" in mission.panel.text(),
		mission.panel.text())
	check("testing is never a mistake, and the meter goes back to its place",
		manager.mistakes == 0 and meter.global_position.is_equal_approx(meter.home_transform.origin), str(manager.mistakes))
	await _place(mission, "Multimeter", _above(mission, "RamProblem"))
	check("the dead RAM reads wrong: 0.0 V", meter.get_node("Display").text == "0.0 V" and "it's dead" in mission.panel.text(),
		mission.panel.text())
	check("and testing fills nothing", not mission.get_node("RamProblem").is_filled())
	await _place(mission, "Ram", _above(mission, "RamProblem"))
	await _place(mission, "Multimeter", _above(mission, "RamProblem"))
	check("once the RAM is swapped, it reads right", meter.get_node("Display").text == "1.2 V" and "new RAM stick" in mission.panel.text(),
		mission.panel.text())
	await _place(mission, "Ssd", _above(mission, "DriveProblem"))
	check("then the spare SSD finishes it, with no mistakes", manager.state == manager.State.SUCCESS and manager.score == 100, str(manager.score))


## Phase 5, step 11: the text every mission shares is in data/modules.json.
func _test_registry_messages() -> void:
	var registry = ModuleRegistry.load_from()
	check("the shared text loads from data/modules.json's messages", registry.errors.is_empty()
		and registry.messages.keys() == ModuleRegistry.MESSAGE_DEFAULTS.keys(), str(registry.errors))
	check("say() fills in the names", registry.say("wrong_part", {"part": "RAM stick", "hint": "Memory goes in the RAM slot."})
		== "The RAM stick doesn't go there. Memory goes in the RAM slot.")
	var bad := func(messages: Dictionary) -> PackedStringArray:
		var r = ModuleRegistry.new()
		r.read({"messages": messages, "modules": [{"id": "t", "title": "T", "missions": [{
			"id": "m", "title": "M", "scene": "res://scenes/workbench.tscn", "intro": ["a"], "success": ["b"],
			"scoring": {"full": 100, "per_mistake": 10}, "parts": {"Ram": {"type": "ram", "name": "RAM"}},
			"slots": {"Slot": {"accepts": "ram", "name": "slot", "hint": "h"}}}]}]})
		return r.errors
	check("a message can be reworded", bad.call({"saving": "Sending your score..."}).is_empty())
	var unknown: PackedStringArray = bad.call({"hello": "Hi"})
	check("an unknown message is caught", unknown.size() == 1 and "not a message the game shows" in unknown[0], str(unknown))
	var lost: PackedStringArray = bad.call({"wrong_part": "Wrong! {hint}"})
	check("rewording that drops a {name} is caught", lost.size() == 1 and "must keep {part}" in lost[0], str(lost))


func _test_success_panel_order() -> void:
	var mission := await _fresh(IdentifyComponents)
	manager.return_scene = "res://scenes/menus/menu.tscn"
	manager.return_label = "Free Play"
	var old_opener: Callable = manager.scene_opener
	manager.scene_opener = func(_path: String) -> void: pass
	manager.note_grab()
	manager.complete()
	await _settle()
	var lines: PackedStringArray = mission.panel.lines
	check("the success panel's title, then the score, time and mistakes first",
		mission.panel.title == "Mission complete!" and lines[0].begins_with("Score: ") and "Mistakes: 0" in lines[0], str(lines))
	check("then what the mission taught", lines[1] == mission.config.success[0], str(lines))
	check("then where it goes next, with the saving status last",
		lines[lines.size() - 2].begins_with("Back to Free Play") and (lines[lines.size() - 1].begins_with("Saving your score") or lines[lines.size() - 1].contains("Score")), str(lines))
	manager.return_scene = ""
	manager.return_label = ""
	manager.scene_opener = old_opener


## Every kind of feedback starts the same way: "Yes!" for a part that went
## in (pass-through steps too), and what happened before the hint for a miss.
func _test_feedback_reads_the_same() -> void:
	var mission := await _fresh(ExecuteTask)
	var first: Node = mission.zones[0]
	check("a pass-through step says Yes! like any other", first.pass_through and mission._installed_text(first, mission.parts[0]).begins_with("Yes! "),
		mission._installed_text(first, mission.parts[0]))
	var lines := []
	for key in ["installed", "installed_role", "next_step", "step_progress", "step_done"]:
		lines.append(manager.registry.say(key, {"part": "p", "slot": "s", "role": "r", "done": 1, "total": 2}))
	check("every 'it went in' message starts with Yes!", lines.all(func(l) -> bool: return l.begins_with("Yes! ")), str(lines))
	var misses := []
	for key in ["wrong_part", "working_part", "needs_tool", "too_early"]:
		misses.append(manager.registry.say(key, {"part": "p", "first": "f", "hint": "HINT"}))
	check("every miss says what happened, then the slot's hint", misses.all(func(l) -> bool: return l.ends_with(". HINT") and not l.begins_with("HINT")),
		str(misses))


func _test_registry_checks_probes() -> void:
	var bad := func(probe) -> PackedStringArray:
		var registry = ModuleRegistry.new()
		registry.read({"modules": [{"id": "t", "title": "T", "missions": [{
			"id": "m", "title": "M", "scene": "res://scenes/workbench.tscn", "intro": ["a"], "success": ["b"],
			"scoring": {"full": 100, "per_mistake": 10}, "parts": {"Ram": {"type": "ram", "name": "RAM"}},
			"slots": {"Slot": {"accepts": "ram", "name": "slot", "hint": "h", "probe": probe}}}]}]})
		return registry.errors
	check("a probe with a reading and its meaning loads", bad.call({"reads": "1.2 V", "means": "fine"}).is_empty())
	var errors: PackedStringArray = bad.call({"reads": "1.2 V"})
	check("a probe without what it means is caught", errors.size() == 1 and "probe must be {reads, means}" in errors[0], str(errors))


func _test_diagnose_failure() -> void:
	var mission := await _fresh(DiagnoseFailure)
	check("only the two problems are goals; the working CPU and PSU aren't",
		mission.goals.size() == 2 and mission.zones.size() == 4)
	check("the checklist lists the symptoms, problem 2 waiting on problem 1",
		"four things" not in mission.panel.text() and "beeps and shows no picture" in mission.panel.text(), mission.panel.text())
	await _place(mission, "Cpu", _above(mission, "CpuCheck"))
	check("a spare dropped on a working part is a mistake that explains why it's fine",
		manager.mistakes == 1 and "Not that one. The CPU is fine" in mission.panel.text() and not mission.get_node("Cpu").is_installed, mission.panel.text())
	await _place(mission, "Ssd", _above(mission, "DriveProblem"))
	check("fixing problem 2 before problem 1 is blocked", manager.mistakes == 2, mission.panel.text())
	var old_ram: Node3D = mission.get_node("RamProblem/Replaced")
	await _place(mission, "Ram", _above(mission, "RamProblem"))
	check("the new RAM fixes problem 1, hides the old stick, and reveals problem 2",
		mission.get_node("Ram").is_installed and not old_ram.visible and "No boot device found" in mission.panel.text(), mission.panel.text())
	await _place(mission, "Ssd", _above(mission, "DriveProblem"))
	check("the new SSD fixes problem 2 and finishes the mission",
		manager.state == manager.State.SUCCESS and not mission.get_node("DriveProblem/Replaced").visible and manager.score == 80, str(manager.score))
