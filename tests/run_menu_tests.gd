extends SceneTree
## Menu checks (Phase 1, steps 4-7): the 3D screen and pointer, then the
## menus themselves. No headset or mouse needed: clicks go through the same
## pointer code a controller or mouse uses.
##
##   godot --headless --script res://tests/run_menu_tests.gd

const MenuScreen3D := preload("res://scripts/ui/menu_screen_3d.gd")
const MenuPointer := preload("res://scripts/input/menu_pointer.gd")
const MenuTheme := preload("res://scripts/ui/menu_theme.gd")
const MenuScene := preload("res://scenes/menus/menu.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


var _opened: Array = []


func _run() -> void:
	var manager := root.get_node_or_null("TrainingManager")
	if manager:
		manager.scene_opener = func(path: String) -> void: _opened.append(path)
		manager.auto_advance = false
	var saves := root.get_node_or_null("SaveService")
	if saves:
		saves.use_backend(preload("res://scripts/save/local_save_backend.gd").new("user://test_ocsvr_save.json"))
	for test in _tests():
		await test.call()
	print("\n%s" % ("ALL PASSED" if _failures.is_empty() else "%d FAILED" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)


func _tests() -> Array:
	return [_test_screen_pixels, _test_pointer_clicks_button, _test_pointer_misses_off_screen,
		_test_theme_placeholder_image, _test_ray_transform, _test_home_page, _test_login_placeholder,
		_test_mode_picker, _test_free_play_lists_tasks, _test_free_play_cloud_empty,
		_test_free_play_starts_task, _test_done_task_shows_best, _test_mission_returns_to_menu,
		_test_menu_reopens_return_page]


func check(label: String, ok: bool, detail = "") -> void:
	var why := str(detail)
	print(("PASS  " if ok else "FAIL  ") + label + ("" if ok or why == "" else "   [%s]" % why))
	if not ok:
		_failures.append(label)


## A screen at the origin facing +z, plus a pointer, in a fresh world.
func _screen_world() -> Array:
	var world := Node3D.new()
	root.add_child(world)
	var screen := MenuScreen3D.new()
	world.add_child(screen)
	var pointer := MenuPointer.new()
	world.add_child(pointer)
	await physics_frame
	await physics_frame
	return [world, screen, pointer]


func _test_screen_pixels() -> void:
	var parts := await _screen_world()
	var screen = parts[1]
	check("the screen's viewport is 1600 x 1000 px", screen.viewport.size == Vector2i(1600, 1000), screen.viewport.size)
	check("the middle of the screen is the middle pixel", screen.world_to_pixel(Vector3.ZERO) == Vector2(800, 500),
		screen.world_to_pixel(Vector3.ZERO))
	check("the top-left corner is pixel (0, 0)", screen.world_to_pixel(Vector3(-0.8, 0.5, 0)).is_equal_approx(Vector2.ZERO),
		screen.world_to_pixel(Vector3(-0.8, 0.5, 0)))
	check("a point off the screen is (-1, -1)", screen.world_to_pixel(Vector3(2, 0, 0)) == Vector2(-1, -1))
	parts[0].queue_free()


func _test_pointer_clicks_button() -> void:
	var parts := await _screen_world()
	var screen = parts[1]
	var pointer = parts[2]
	var button := MenuTheme.primary_button("Play")
	button.position = Vector2(700, 450)
	button.size = Vector2(200, 100)
	screen.ui_root.add_child(button)
	var clicks := [0]
	button.pressed.connect(func(): clicks[0] += 1)
	await process_frame
	# Pixel (800, 500) is the screen's middle, which is world (0, 0, 0).
	check("the pointer reaches the screen", pointer.click_world(Vector3(0, 0, 0)))
	await process_frame
	check("clicking on a button presses it", clicks[0] == 1, clicks[0])
	pointer.click_world(Vector3(0.6, 0.4, 0))
	await process_frame
	check("clicking elsewhere on the screen doesn't", clicks[0] == 1, clicks[0])
	parts[0].queue_free()


func _test_pointer_misses_off_screen() -> void:
	var parts := await _screen_world()
	check("pointing past the screen hits nothing", not parts[2].click_world(Vector3(3, 0, 0)))
	parts[0].queue_free()


func _test_theme_placeholder_image() -> void:
	var img := MenuTheme.image("not_a_real_image_name", Vector2(400, 300))
	check("a missing image shows a named placeholder", img.name == "Placeholder_not_a_real_image_name"
		and img.custom_minimum_size == Vector2(400, 300), img.name)
	img.free()


func _test_ray_transform() -> void:
	var t: Transform3D = MenuPointer._ray_transform(Vector3(0, 1, 0), Vector3(0, 0, -1), 2.0)
	check("the controller ray starts at the hand and points forward",
		t.origin.is_equal_approx(Vector3(0, 1, -1)) and (t.basis.y).is_equal_approx(Vector3(0, 0, -2)), t)


# ---------------------------------------------------------------- menu scene

## The menu scene, loaded fresh, on its Home page.
func _menu() -> Node3D:
	var menu: Node3D = MenuScene.instantiate()
	root.add_child(menu)
	await physics_frame
	await process_frame
	await process_frame
	return menu


## Clicks a named button on the menu's current page the way the pointer does.
func _click(menu: Node3D, button_name: String) -> bool:
	var button: Button = menu.find_button(button_name)
	if button == null:
		return false
	await process_frame
	var hit: bool = menu.pointer.click_world(menu.screen.control_to_world(button))
	await process_frame
	await process_frame
	return hit


func _test_home_page() -> void:
	var menu := await _menu()
	check("the game opens on the Home page", menu.page == "home", menu.page)
	check("Home has Log in and Play locally", menu.find_button("LoginButton") != null
		and menu.find_button("PlayLocallyButton") != null)
	check("Home shows the hero image's placeholder", menu.screen.ui_root.find_child("Placeholder_home_hero", true, false) != null)
	await _click(menu, "PlayLocallyButton")
	check("Play locally opens the mode picker", menu.page == "modes", menu.page)
	menu.queue_free()


func _test_login_placeholder() -> void:
	var menu := await _menu()
	await _click(menu, "LoginButton")
	check("Log in opens the sign-in page", menu.page == "login", menu.page)
	check("the sign-in page offers Play locally", menu.find_button("PlayLocallyButton") != null)
	await _click(menu, "BackButton")
	check("Back returns to Home", menu.page == "home", menu.page)
	menu.queue_free()


func _test_mode_picker() -> void:
	var menu := await _menu()
	menu.show_page("modes")
	await process_frame
	for card in ["FreePlayCard", "StoryCard", "OpenWorldCard"]:
		check("the mode picker has %s" % card, menu.find_button(card) != null)
	await _click(menu, "OpenWorldCard")
	check("Open World says it's coming soon", menu.page == "coming_soon", menu.page)
	await _click(menu, "BackButton")
	check("Back returns to the mode picker", menu.page == "modes", menu.page)
	menu.queue_free()


func _test_free_play_lists_tasks() -> void:
	var menu := await _menu()
	menu.show_page("modes")
	await process_frame
	await _click(menu, "FreePlayCard")
	check("Free Play opens on the Computer tab", menu.page == "free_play", menu.page)
	var manager := root.get_node("TrainingManager")
	var tasks: Array = manager.registry.missions_in("computer")
	check("there are 6 Computer tasks in the registry", tasks.size() == 6, tasks.size())
	var missing := []
	for task in tasks:
		if menu.find_button("Task_" + task.full_id.replace(".", "_")) == null:
			missing.append(task.full_id)
	check("every Computer task has a card", missing.is_empty(), missing)
	check("each card shows its description", menu.screen.ui_root.find_child("TaskList", true, false) != null
		and tasks.all(func(t) -> bool: return t.description != ""))
	await process_frame
	var overlaps := []
	for i in tasks.size() - 1:
		var a: Control = menu.find_button("Task_" + tasks[i].full_id.replace(".", "_")).get_parent()
		var b: Control = menu.find_button("Task_" + tasks[i + 1].full_id.replace(".", "_")).get_parent()
		if a.get_global_rect().end.y > b.get_global_rect().position.y + 0.5:
			overlaps.append(tasks[i].id)
	check("task cards don't overlap", overlaps.is_empty(), overlaps)
	menu.queue_free()


func _test_free_play_cloud_empty() -> void:
	var menu := await _menu()
	menu.show_page("free_play", "computer")
	await process_frame
	await _click(menu, "TabCloud")
	check("the Cloud tab says it has no tasks yet", menu.screen.ui_root.find_child("EmptyList", true, false) != null)
	await _click(menu, "TabComputer")
	check("the Computer tab lists tasks again", menu.screen.ui_root.find_child("TaskList", true, false) != null)
	menu.queue_free()


func _test_free_play_starts_task() -> void:
	_opened.clear()
	var manager := root.get_node("TrainingManager")
	var menu := await _menu()
	menu.show_page("free_play", "computer")
	await process_frame
	await _click(menu, "Task_build_computer_assemble_system")
	check("clicking a task opens its mission scene", _opened == ["res://scenes/build_computer/assemble_system.tscn"], _opened)
	check("the mission will come back to Free Play", manager.return_scene == "res://scenes/menus/menu.tscn"
		and manager.return_page == "free_play:computer" and manager.return_label == "Free Play",
		[manager.return_scene, manager.return_page])
	manager.return_scene = ""
	manager.return_page = ""
	manager.return_label = ""
	menu.queue_free()


func _test_done_task_shows_best() -> void:
	var saves := root.get_node("SaveService")
	saves.record_task_result("build_computer.execute_task", 88, 70, 2)
	var menu := await _menu()
	menu.show_page("free_play", "computer")
	await process_frame
	var row: Button = menu.find_button("Task_build_computer_execute_task")
	var other: Button = menu.find_button("Task_build_computer_add_capacity")
	check("a finished task is marked Done", row != null and row.get_parent().find_child("DoneTag", true, false) != null)
	check("an unfinished task isn't", other != null and other.get_parent().find_child("DoneTag", true, false) == null)
	menu.queue_free()


func _test_mission_returns_to_menu() -> void:
	_opened.clear()
	var manager := root.get_node("TrainingManager")
	manager.return_scene = "res://scenes/menus/menu.tscn"
	manager.return_page = "free_play:computer"
	manager.return_label = "Free Play"
	var old_delay: float = manager.advance_delay_s
	manager.advance_delay_s = 0.05
	var mission: Node3D = load("res://scenes/build_computer/identify_components.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	manager.note_grab()
	manager.complete()
	await create_timer(0.3).timeout
	check("a mission started from the menu goes back to it when done", _opened == ["res://scenes/menus/menu.tscn"], _opened)
	var panel_text: String = str(mission.panel.lines)
	check("its success panel says where it's going", panel_text.contains("Back to Free Play"), panel_text)
	manager.advance_delay_s = old_delay
	mission.queue_free()
	await process_frame


func _test_menu_reopens_return_page() -> void:
	var manager := root.get_node("TrainingManager")
	manager.return_scene = "res://scenes/menus/menu.tscn"
	manager.return_page = "free_play:computer"
	manager.return_label = "Free Play"
	var menu := await _menu()
	check("back from a mission, the menu reopens Free Play", menu.page == "free_play", menu.page)
	check("the return is used once", manager.return_page == "" and manager.return_scene == "")
	menu.queue_free()
