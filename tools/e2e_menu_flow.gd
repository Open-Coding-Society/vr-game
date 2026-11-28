extends SceneTree
## End-to-end check of the real game flow with real scene changes (needs a
## window, not --headless): Home -> Play locally -> Free Play -> start a
## mission -> finish it -> back on the Free Play page. Then Story Mode -> IRL
## -> the roadmap's first task -> finish it -> back on the roadmap with the
## next task open. Then Free Play again -> Build your own PC -> build a PC
## that works -> back on Free Play. Exit 0 when it all works.
##
##   godot --path . --script res://tools/e2e_menu_flow.gd

const StoryMap := preload("res://scripts/menus/story_map.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, detail = "") -> void:
	print(("PASS  " if ok else "FAIL  ") + label + ("" if ok else "   [%s]" % str(detail)))
	if not ok:
		_failures += 1


func _wait(frames := 6) -> void:
	for i in frames:
		await process_frame


func _click(menu: Node, button_name: String) -> bool:
	var b: Button = menu.find_button(button_name)
	if b == null:
		return false
	await _wait(2)
	return menu.pointer.click_world(menu.screen.control_to_world(b))


## Puts a part on a slot the way a grabber does.
func _put(mission: Node, manager: Node, part_path: String, slot_path: String) -> void:
	var part: Node3D = mission.get_node(part_path)
	var slot: Node3D = mission.get_node(slot_path)
	part.grab()
	manager.note_grab()
	part.global_position = (slot.get_node("CollisionShape3D") as Node3D).global_position
	for i in 4:
		await physics_frame
	part.drop()
	await _wait(4)


## Story Mode: play the IRL roadmap's first task and come back to the roadmap.
func _story_leg(menu: Node, manager: Node, saves: Node) -> void:
	menu.show_page("modes")
	await _wait()
	await _click(menu, "StoryCard")
	await _wait()
	await _click(menu, "Chapter_irl")
	await _wait()
	check("Story Mode's IRL roadmap is open", menu.page == "roadmap", menu.page)
	await _click(menu, "Play_setup_pc_unbox")
	await _wait(20)
	var mission := current_scene
	check("the roadmap's first task opens Unbox the PC", mission != null and mission.scene_file_path == "res://scenes/setup_pc/unbox.tscn",
		mission.scene_file_path if mission else "none")
	if mission == null or mission.scene_file_path != "res://scenes/setup_pc/unbox.tscn":
		return
	for pair in [["Tower", "Desk/TowerSpot"], ["Monitor", "Desk/MonitorSpot"], ["Keyboard", "Desk/KeyboardSpot"], ["Mouse", "Desk/MouseSpot"]]:
		await _put(mission, manager, pair[0], pair[1])
	check("putting all four parts on the desk finishes it", manager.state == manager.State.SUCCESS, manager.state)
	await create_timer(1.5).timeout
	await _wait(10)
	var back := current_scene
	check("after the task the game is back on the roadmap", back != null and back.scene_file_path == "res://scenes/menus/menu.tscn"
		and back.page == "roadmap", back.page if back and back.scene_file_path == "res://scenes/menus/menu.tscn" else "not the menu")
	check("the task was saved", saves.is_task_done("setup_pc.unbox"))
	var next_step: Node = back.screen.ui_root.find_child("Node_setup_pc_connect_peripherals", true, false) if back else null
	check("and the next task on the roadmap is open", next_step != null and next_step.get_meta("state") == StoryMap.NEXT
		and back.find_button("Play_setup_pc_connect_peripherals") != null)


## Free Play: start Build your own PC, build the mid tier PC and come back.
func _build_leg(menu: Node, manager: Node, saves: Node) -> void:
	menu.show_page("free_play", "computer")
	await _wait()
	var card: Button = menu.find_button("Task_build_computer_build_your_own")
	check("Free Play has a Build your own PC card", card != null)
	if card == null:
		return
	(menu.screen.ui_root.find_child("TaskList", true, false) as ScrollContainer).ensure_control_visible(card)
	await _wait()
	await _click(menu, "Task_build_computer_build_your_own")
	await _wait(20)
	var mission := current_scene
	check("the card opens Build your own PC", mission != null and mission.scene_file_path == "res://scenes/build_pc/build_your_own.tscn",
		mission.scene_file_path if mission else "none")
	if mission == null or mission.scene_file_path != "res://scenes/build_pc/build_your_own.tscn":
		return
	mission.get_node("Monitor/MonitorScreen").line_seconds = 0.1
	for pair in [["Boards/Mid", "Case/BoardTray"], ["Shelf/Mid/Cpu", "Case/CpuSocket"], ["Shelf/Mid/Ram", "Case/RamSlots"],
			["Shelf/Mid/Storage", "Case/StorageBay"], ["Shelf/Mid/Gpu", "Case/GpuSlot"], ["Shelf/Mid/Psu", "Case/PsuBay"],
			["Finger", "Case/PowerButton"]]:
		await _put(mission, manager, pair[0], pair[1])
	check("a mid tier build boots and finishes the mission with the balanced bonus",
		manager.state == manager.State.SUCCESS and manager.score == 100, "%s %s" % [manager.state, manager.score])
	await create_timer(2.0).timeout
	await _wait(10)
	var back := current_scene
	check("after the build the game is back on Free Play", back != null and back.scene_file_path == "res://scenes/menus/menu.tscn"
		and back.page == "free_play", back.page if back and back.scene_file_path == "res://scenes/menus/menu.tscn" else "not the menu")
	check("the build was saved", saves.is_task_done("build_computer.build_your_own"))


## Story Mode, a later act: with the acts before it done, the roadmap's
## task `task` is next; play it with `steps` ([part, slot] pairs, as the
## mouse does it) and come back to the roadmap.
func _act_leg(menu: Node, manager: Node, saves: Node, act_label: String, task: String, scene: String, steps: Array) -> void:
	var map = StoryMap.load_from(manager.registry)
	for t in map.tasks_of("irl"):
		if t.id == task:
			break
		if t.mission != "" and not saves.is_task_done(t.id):
			saves.record_task_result(t.id, 100, 30, 1)
	menu.show_page("roadmap", "irl")
	await _wait()
	var button: Button = menu.find_button("Play_" + task.replace(".", "_"))
	check("%s: the roadmap has %s next" % [act_label, task], button != null)
	if button == null:
		return
	(menu.screen.ui_root.find_child("Roadmap", true, false) as ScrollContainer).ensure_control_visible(button)
	await _wait()
	await _click(menu, "Play_" + task.replace(".", "_"))
	await _wait(20)
	var mission := current_scene
	check("%s: it opens the mission" % act_label, mission != null and mission.scene_file_path == scene, mission.scene_file_path if mission else "none")
	if mission == null or mission.scene_file_path != scene:
		return
	for step in steps:
		await _put(mission, manager, step[0], step[1])
	check("%s: playing it through finishes it" % act_label, manager.state == manager.State.SUCCESS, manager.state)
	await create_timer(1.5).timeout
	await _wait(10)
	var back := current_scene
	check("%s: then the game is back on the roadmap" % act_label, back != null and back.scene_file_path == "res://scenes/menus/menu.tscn"
		and back.page == "roadmap", back.scene_file_path if back else "none")
	check("%s: and it was saved" % act_label, saves.is_task_done(task))


## Back to menu in the middle of a mission: back on the page it came from,
## and nothing saved for it.
func _leave_early_leg(menu: Node, manager: Node, saves: Node) -> void:
	menu.show_page("free_play", "computer")
	await _wait()
	await _click(menu, "Task_build_computer_identify_components")
	await _wait(20)
	var mission := current_scene
	check("leave early: Identify the components opens", mission != null and mission.scene_file_path == "res://scenes/build_computer/identify_components.tscn")
	if mission == null:
		return
	await _put(mission, manager, "Cpu", "Motherboard/CpuSocket")
	mission.get_node("Room/BackButton").press()
	await _wait(10)
	var back := current_scene
	check("leave early: Back to menu goes straight back to Free Play", back != null and back.scene_file_path == "res://scenes/menus/menu.tscn"
		and back.page == "free_play", back.page if back and back.scene_file_path == "res://scenes/menus/menu.tscn" else "not the menu")
	check("leave early: nothing is saved for the unfinished mission", not saves.is_task_done("build_computer.identify_components"))


## Open World: spawn two parts, leave, come back: the desk is as it was left.
func _open_world_leg(menu: Node, manager: Node, saves: Node) -> void:
	saves.save_world_layout([])
	menu.show_page("modes")
	await _wait()
	await _click(menu, "OpenWorldCard")
	await _wait(20)
	var world := current_scene
	check("open world: the card opens Open World", world != null and world.scene_file_path == "res://scenes/open_world/open_world.tscn",
		world.scene_file_path if world else "none")
	if world == null or world.scene_file_path != "res://scenes/open_world/open_world.tscn":
		return
	world.spawn("cpu_high")
	world.spawn("net_router")
	await _wait()
	world.get_node("Room/BackButton").press()
	await _wait(10)
	check("open world: Back to menu returns to the mode picker", current_scene.scene_file_path == "res://scenes/menus/menu.tscn"
		and current_scene.page == "modes", current_scene.page)
	check("open world: the layout was saved", saves.load_world_layout().size() == 2, saves.load_world_layout())
	await _click(current_scene, "OpenWorldCard")
	await _wait(20)
	world = current_scene
	check("open world: coming back, the two parts are on the desk", world.scene_file_path == "res://scenes/open_world/open_world.tscn"
		and world.items().size() == 2, world.items().size() if world.has_method("items") else "not Open World")
	world.clear_desk()
	world.get_node("Room/BackButton").press()
	await _wait(10)


## Settings: choose Seated, and a mission then lowers the desk in the headset.
func _settings_leg(menu: Node, manager: Node, saves: Node) -> void:
	menu.show_page("modes")
	await _wait()
	await _click(menu, "SettingsButton")
	await _wait()
	check("settings: the mode picker opens Settings", menu.page == "settings", menu.page)
	await _click(menu, "Setting_comfort_seated")
	await _wait()
	check("settings: Seated is saved", saves.setting("comfort") == "seated")
	await _click(menu, "BackButton")
	await _wait()
	await _click(menu, "FreePlayCard")
	await _wait()
	await _click(menu, "Task_build_computer_install_ram")
	await _wait(20)
	var mission := current_scene
	check("settings: in a mission, the headset origin is raised for a seated player",
		mission != null and mission.has_node("Room") and is_equal_approx(mission.get_node("Room").xr_origin.position.y, 0.2))
	if mission and mission.has_node("Room"):
		mission.get_node("Room/BackButton").press()
		await _wait(10)
	saves.set_setting("comfort", "standing")


func _run() -> void:
	var saves := root.get_node("SaveService")
	saves.use_backend(preload("res://scripts/save/local_save_backend.gd").new("user://test_e2e_save.json"))
	saves.profile.tasks.clear()
	var manager := root.get_node("TrainingManager")
	manager.advance_delay_s = 0.5
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _wait(10)
	var menu := current_scene
	check("the game starts on the menu scene", menu != null and menu.scene_file_path == "res://scenes/menus/menu.tscn",
		menu.scene_file_path if menu else "none")
	check("on the Home page", menu.page == "home", menu.page)
	await _click(menu, "PlayLocallyButton")
	await _wait()
	await _click(menu, "FreePlayCard")
	await _wait()
	check("Free Play is open", menu.page == "free_play", menu.page)
	await _click(menu, "Task_build_computer_install_ram")
	await _wait(20)
	var mission := current_scene
	check("clicking a task really opens the mission scene", mission != null and mission.scene_file_path == "res://scenes/workbench.tscn",
		mission.scene_file_path if mission else "none")
	# Play it: put the RAM in its slot the way the mouse grabber does.
	var ram: Node3D = mission.get_node("RamStick")
	var slot: Node3D = mission.get_node("Motherboard/RamSlot")
	ram.grab()
	manager.note_grab()
	ram.global_position = slot.global_position
	for i in 4:
		await physics_frame
	ram.drop()
	await _wait(4)
	check("dropping the RAM in its slot finishes the mission", manager.state == manager.State.SUCCESS, manager.state)
	await create_timer(1.5).timeout
	await _wait(10)
	var back := current_scene
	check("after the mission the game is back on the menu", back != null and back.scene_file_path == "res://scenes/menus/menu.tscn",
		back.scene_file_path if back else "none")
	check("it reopened Free Play", back != null and back.page == "free_play", back.page if back else "")
	check("the finished task was saved", saves.is_task_done("build_computer.install_ram"))
	await _story_leg(back, manager, saves)
	await _build_leg(current_scene, manager, saves)
	# Phase 5: leaving early (before the acts below mark earlier tasks done),
	# one task from each later act, Open World, Settings.
	await _leave_early_leg(current_scene, manager, saves)
	await _act_leg(current_scene, manager, saves, "Act 2", "build_computer.swap_ssd", "res://scenes/build_computer/swap_ssd.tscn", [
		["ToolRack/WristStrap", "Wrist"],
		["ToolRack/Screwdriver", "Case/PanelScrews"], ["ToolRack/Screwdriver", "Case/PanelScrews"],
		["ToolRack/Screwdriver", "Case/PanelScrews"], ["ToolRack/Screwdriver", "Case/PanelScrews"],
		["SidePanel", "PanelSpot"], ["ToolRack/Screwdriver", "Case/DriveScrew"], ["OldSsd", "OldTray"],
		["NewSsd", "Case/DriveBay"], ["ToolRack/Screwdriver", "Case/ScrewDown"], ["SidePanel", "Case/CloseCase"]])
	await _act_leg(current_scene, manager, saves, "Act 4", "build_network.server_rack", "res://scenes/network/server_rack.tscn", [
		["Server1", "Rack/Bay1"], ["Server2", "Rack/Bay2"], ["Server3", "Rack/Bay3"], ["SwitchUnit", "Rack/Bay4"],
		["CableA/EndA", "Server1/Device/Eth0"], ["CableA/EndB", "SwitchUnit/Device/Port1"],
		["CableB/EndA", "Server2/Device/Eth0"], ["CableB/EndB", "SwitchUnit/Device/Port2"],
		["CableC/EndA", "Server3/Device/Eth0"], ["CableC/EndB", "SwitchUnit/Device/Port3"]])
	await _open_world_leg(current_scene, manager, saves)
	await _settings_leg(current_scene, manager, saves)
	print("\n%s" % ("E2E PASSED" if _failures == 0 else "%d FAILED" % _failures))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_e2e_save.json"))
	quit(0 if _failures == 0 else 1)
