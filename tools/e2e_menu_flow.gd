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
	print("\n%s" % ("E2E PASSED" if _failures == 0 else "%d FAILED" % _failures))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_e2e_save.json"))
	quit(0 if _failures == 0 else 1)
