extends SceneTree
## End-to-end check of the real game flow with real scene changes (needs a
## window, not --headless): Home -> Play locally -> Free Play -> start a
## mission -> finish it -> back on the Free Play page. Exit 0 when it all works.
##
##   godot --path . --script res://tools/e2e_menu_flow.gd

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
	print("\n%s" % ("E2E PASSED" if _failures == 0 else "%d FAILED" % _failures))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_e2e_save.json"))
	quit(0 if _failures == 0 else 1)
