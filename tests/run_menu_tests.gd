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
const StoryMap := preload("res://scripts/menus/story_map.gd")

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


## Build a Network's seven missions (Phase 3), in order.
const BUILD_NETWORK := ["build_network.connect_two", "build_network.switch", "build_network.router",
	"build_network.send_packets", "build_network.interrupt", "build_network.redundancy", "build_network.distribute"]


func _tests() -> Array:
	return [_test_screen_pixels, _test_pointer_clicks_button, _test_pointer_misses_off_screen,
		_test_theme_placeholder_image, _test_theme_text_is_readable, _test_tag_keeps_its_size,
		_test_ray_transform, _test_home_page, _test_login_placeholder,
		_test_mode_picker, _test_free_play_lists_tasks, _test_free_play_lists_the_new_modes, _test_free_play_cloud_empty,
		_test_free_play_starts_task, _test_done_task_shows_best, _test_mission_returns_to_menu,
		_test_back_to_menu_leaves_early, _test_back_to_menu_without_the_menu, _test_back_button_in_every_mission,
		_test_menu_reopens_return_page, _test_story_map_states, _test_story_act_1_unlocks_in_order,
		_test_story_act_2_plays_the_new_tasks, _test_free_play_lists_act_2, _test_story_act_3_starts_with_build_your_own, _test_story_act_4_unlocks_in_order,
		_test_free_play_lists_build_network, _test_roadmap_plays_act_4,
		_test_story_map_bad_mission,
		_test_story_chapters, _test_roadmap_plays_next, _test_roadmap_cloud_planned,
		_test_roadmap_rows_fill_the_screen]


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


## How far apart two colors are in brightness, from 1 (the same) to 21 (black
## on white). Text needs 4.5 or more to read easily.
static func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var parts := []
	for v in [c.r, c.g, c.b]:
		parts.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]


## The light theme only works if every kind of text stands out from what it
## sits on: a pale accent or a pale grey on white is the easy mistake.
func _test_theme_text_is_readable() -> void:
	var pairs := [
		["text on the screen", MenuTheme.TEXT, MenuTheme.PANEL],
		["text on a card", MenuTheme.TEXT, MenuTheme.CARD],
		["quiet text on the screen", MenuTheme.MUTED, MenuTheme.PANEL],
		["quiet text on a card", MenuTheme.MUTED, MenuTheme.CARD],
		["quiet text on a tag", MenuTheme.MUTED, MenuTheme.CARD_HOVER],
		["accent text on a card", MenuTheme.ACCENT, MenuTheme.CARD],
		["accent text on the screen", MenuTheme.ACCENT, MenuTheme.PANEL],
		["text on the main button", MenuTheme.ON_PRIMARY, MenuTheme.PRIMARY],
		["text on the main button when pointed at", MenuTheme.ON_PRIMARY, MenuTheme.PRIMARY_HOVER],
		["the Done word on a card", MenuTheme.DONE, MenuTheme.CARD],
	]
	for pair in pairs:
		var ratio := _contrast(pair[1], pair[2])
		check("%s is readable" % pair[0], ratio >= 4.5, "contrast %.2f" % ratio)


## A tag in a column or a tall row used to be stretched to the container's size.
func _test_tag_keeps_its_size() -> void:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(600, 300)
	var wide := MenuTheme.label("A much longer line than the tag", MenuTheme.SIZE_BODY)
	wide.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(wide)
	var tag := MenuTheme.tag("Done")
	column.add_child(tag)
	root.add_child(column)
	await process_frame
	await process_frame
	var want: float = tag.get_combined_minimum_size().x
	check("a tag in a column stays as wide as its text", is_equal_approx(tag.size.x, want) and tag.size.x < wide.size.x,
		"%s wide, text needs %s" % [tag.size.x, want])
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(600, 120)
	var tall := MenuTheme.tag("Playing locally")
	row.add_child(tall)
	root.add_child(row)
	await process_frame
	await process_frame
	check("a tag in a tall row stays as tall as its text", is_equal_approx(tall.size.y, tall.get_combined_minimum_size().y),
		"%s tall in a row %s tall" % [tall.size.y, row.size.y])
	column.queue_free()
	row.queue_free()


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
	check("Home shows the hero image (or its placeholder)", menu.screen.ui_root.find_child("Image_home_hero", true, false) != null
		or menu.screen.ui_root.find_child("Placeholder_home_hero", true, false) != null)
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
	check("the registry's Computer tasks start with the six Build a Computer ones",
		tasks.size() >= 6 and tasks[0].full_id == "build_computer.install_ram" and tasks[5].full_id == "build_computer.diagnose_failure",
		tasks.size())
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


## The two Phase 2 modes are in Free Play: Build your own PC and the four
## Set up a pre-built PC tasks, after the six that were there.
func _test_free_play_lists_the_new_modes() -> void:
	_opened.clear()
	var manager := root.get_node("TrainingManager")
	var ids: Array = manager.registry.missions_in("computer").map(func(task) -> String: return task.full_id)
	check("Free Play's Computer list has Phase 2's tasks after the first six, then Phase 5's Act 2 tasks, then Build a Network's seven",
		ids.size() == 20 and ids.slice(6, 9) == ["build_computer.build_your_own", "build_computer.swap_ssd", "build_computer.cooler_paste"]
			and ids.slice(9, 13) == ["setup_pc.unbox", "setup_pc.connect_peripherals", "setup_pc.power_on", "setup_pc.go_online"]
			and ids.slice(13) == BUILD_NETWORK, ids)
	var menu := await _menu()
	menu.show_page("free_play", "computer")
	await process_frame
	var card: Button = menu.find_button("Task_build_computer_build_your_own")
	check("Build your own PC has a card", card != null)
	if card == null:
		menu.queue_free()
		return
	var words := []
	for label in card.get_parent().find_children("*", "Label", true, false):
		words.append(label.text)
	check("the card shows the plan's description, topic and difficulty",
		words.has("Build your own PC") and words.has("Pick parts from three tiers and build a PC that works.")
			and words.has("Compatibility") and words.has("Intermediate"), words)
	# It is far down the list: scroll to it, as a player would, then click.
	var list := menu.screen.ui_root.find_child("TaskList", true, false) as ScrollContainer
	list.ensure_control_visible(card)
	await process_frame
	await process_frame
	await _click(menu, "Task_build_computer_build_your_own")
	check("clicking it opens the Build your own PC scene", _opened == ["res://scenes/build_pc/build_your_own.tscn"], _opened)
	check("and it will come back to Free Play", manager.return_page == "free_play:computer" and manager.return_label == "Free Play",
		manager.return_page)
	manager.return_scene = ""
	manager.return_page = ""
	manager.return_label = ""
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


# ---- Phase 5, step 1: leave a mission early ----

func _test_back_to_menu_leaves_early() -> void:
	_opened.clear()
	var manager := root.get_node("TrainingManager")
	var saves := root.get_node("SaveService")
	saves.profile.tasks.clear()
	manager.return_scene = "res://scenes/menus/menu.tscn"
	manager.return_page = "roadmap:irl"
	manager.return_label = "Story Mode"
	var mission: Node3D = load("res://scenes/build_computer/assemble_system.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	var button = mission.get_node("Room/BackButton")
	check("every mission has a Back to menu button", button != null and button.get_node("Label").text == "Back to menu")
	var left := []
	manager.mission_left.connect(func(id: String) -> void: left.append(id))
	var finished := []
	var on_done := func(id: String, _score: int, _time: int) -> void: finished.append(id)
	manager.module_completed.connect(on_done)
	manager.note_grab()
	button.press()
	check("pressing it opens the menu scene the mission came from", _opened == ["res://scenes/menus/menu.tscn"], _opened)
	check("the mission ends with no result", manager.state == manager.State.IDLE and left == ["build_computer.assemble_system"] and finished.is_empty(),
		"%s %s %s" % [manager.state, left, finished])
	check("nothing is saved for it", not saves.is_task_done("build_computer.assemble_system"))
	check("the menu will reopen the page it came from", manager.return_page == "roadmap:irl", manager.return_page)
	check("its slots take nothing more once it's left", mission.zones.all(func(z) -> bool: return z.locked))
	button.press()
	check("a second press does nothing more", _opened.size() == 1, _opened)
	manager.module_completed.disconnect(on_done)
	mission.queue_free()
	await process_frame
	var menu: Node3D = MenuScene.instantiate()
	root.add_child(menu)
	await process_frame
	check("back on the menu, the roadmap it was started from is open", menu.page == "roadmap", menu.page)
	menu.queue_free()
	await process_frame


func _test_back_to_menu_without_the_menu() -> void:
	_opened.clear()
	var manager := root.get_node("TrainingManager")
	manager.return_scene = ""
	manager.return_page = ""
	var mission: Node3D = load("res://scenes/workbench.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	mission.get_node("Room/BackButton")._unhandled_input(esc)
	check("Esc on the laptop does the same, and a mission opened on its own goes to the menu's Home",
		_opened == ["res://scenes/menus/menu.tscn"] and manager.state == manager.State.IDLE, "%s %s" % [_opened, manager.state])
	mission.queue_free()
	await process_frame


## The button is beside the info panel, off the desk, in sight of the laptop
## camera, and nothing in any mission's scene sits in front of it.
func _test_back_button_in_every_mission() -> void:
	# Headless runs use a 100x100 window; look through the game's real one.
	var old_size := root.size
	root.size = Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	var manager := root.get_node("TrainingManager")
	var bad := []
	for id in manager.registry.missions:
		var mission: Node3D = load(manager.registry.mission(id).scene).instantiate()
		root.add_child(mission)
		await process_frame
		await physics_frame
		var button: Node3D = mission.get_node("Room/BackButton")
		var camera: Camera3D = mission.get_node("Room/Camera3D")
		var at := camera.unproject_position(button.global_position)
		var view := Rect2(Vector2.ZERO, mission.get_viewport().get_visible_rect().size)
		if camera.is_position_behind(button.global_position) or not view.has_point(at):
			bad.append("%s: off screen" % id)
		elif not button.is_under(at):
			bad.append("%s: something is in front of it" % id)
		else:
			var blocking := _meshes_between(mission, camera.global_position, button)
			if not blocking.is_empty():
				bad.append("%s: hidden by %s" % [id, ", ".join(blocking)])
		mission.queue_free()
		await process_frame
	manager.leave()
	root.size = old_size
	check("every mission's Back to menu button can be seen and clicked from the laptop camera", bad.is_empty(), bad)


## Meshes of a mission (not the room's) on the line from the eye to any of the
## button's corners: the laptop camera couldn't see the whole button.
func _meshes_between(mission: Node3D, eye: Vector3, button: Node3D) -> Array:
	var out := []
	var half: Vector2 = button.SIZE / 2.0
	var corners := []
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO]:
		corners.append(button.global_transform * Vector3(c.x * half.x, c.y * half.y, 0.006))
	for node in mission.find_children("*", "MeshInstance3D", true, false):
		if mission.get_node("Room").is_ancestor_of(node) or not node.is_visible_in_tree() or node.mesh == null:
			continue
		var box: AABB = node.global_transform * node.mesh.get_aabb()
		for corner in corners:
			if box.intersects_segment(eye, corner):
				out.append(str(mission.get_path_to(node)))
				break
	return out


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


func _test_story_map_states() -> void:
	var manager := root.get_node("TrainingManager")
	var map = StoryMap.load_from(manager.registry)
	check("data/story.json loads cleanly", map.errors.is_empty(), map.errors)
	check("Story has the IRL and Cloud chapters", not map.chapter("irl").is_empty() and not map.chapter("cloud").is_empty())
	var done := {}
	var is_done := func(id: String) -> bool: return done.has(id)
	var s: Dictionary = map.states("irl", is_done)
	check("with nothing done, the first playable task is next", s["setup_pc.unbox"] == StoryMap.NEXT, s)
	check("later playable tasks are locked", s["setup_pc.connect_peripherals"] == StoryMap.LOCKED
		and s["build_computer.install_ram"] == StoryMap.LOCKED)
	check("tasks without a mission are planned", map.states("cloud", is_done)["cloud.internet.follow_a_packet"] == StoryMap.PLANNED)
	done["setup_pc.unbox"] = true
	s = map.states("irl", is_done)
	check("finishing it makes the next one playable", s["setup_pc.unbox"] == StoryMap.DONE
		and s["setup_pc.connect_peripherals"] == StoryMap.NEXT, s)
	check("progress counts playable tasks only", map.progress("irl", is_done) == [1, 20], map.progress("irl", is_done))
	check("the IRL chapter isn't complete yet", not map.chapter_complete("irl", is_done))


## Act 1, "Set up a pre-built PC", is four missions that open one at a time.
func _test_story_act_1_unlocks_in_order() -> void:
	var manager := root.get_node("TrainingManager")
	var map = StoryMap.load_from(manager.registry)
	var act: Dictionary = map.chapter("irl").acts[0]
	var ids: Array = act.tasks.map(func(task) -> String: return task.mission)
	check("Act 1 is the four Set up a pre-built PC missions",
		ids == ["setup_pc.unbox", "setup_pc.connect_peripherals", "setup_pc.power_on", "setup_pc.go_online"], ids)
	check("each roadmap step takes its title from the mission",
		act.tasks.map(func(task) -> String: return task.title) == ids.map(func(id) -> String: return manager.registry.mission(id).title))
	var done := {}
	var is_done := func(id: String) -> bool: return done.has(id)
	var wrong := []
	for at in ids.size():
		var s: Dictionary = map.states("irl", is_done)
		for i in ids.size():
			var want: String = StoryMap.DONE if i < at else (StoryMap.NEXT if i == at else StoryMap.LOCKED)
			if s[ids[i]] != want:
				wrong.append("%s done: %s is %s" % [at, ids[i], s[ids[i]]])
		done[ids[at]] = true
	check("its tasks unlock in order: done ones Done, one Next, the rest Locked", wrong.is_empty(), wrong)
	var after: Dictionary = map.states("irl", is_done)
	check("finishing Act 1 opens the first task of Act 2",
		ids.all(func(id) -> bool: return after[id] == StoryMap.DONE) and after["build_computer.install_ram"] == StoryMap.NEXT, after)
	check("and counts as four of the chapter's twenty playable tasks", map.progress("irl", is_done) == [4, 20], map.progress("irl", is_done))


## Phase 5, step 6: Act 2 ("Inside the PC") is four playable missions now:
## the two from Module 1, then Swap in an SSD and Reseat the cooler.
func _test_story_act_2_plays_the_new_tasks() -> void:
	var manager := root.get_node("TrainingManager")
	var saves := root.get_node("SaveService")
	var map = StoryMap.load_from(manager.registry)
	var act: Dictionary = map.chapter("irl").acts[1]
	var ids: Array = act.tasks.map(func(task) -> String: return task.mission)
	check("Act 2 has no planned tasks left: four missions",
		ids == ["build_computer.install_ram", "build_computer.identify_components", "build_computer.swap_ssd", "build_computer.cooler_paste"], ids)
	check("the cooler keeps the roadmap's longer title", act.tasks[3].title == "Reseat the cooler with thermal paste", act.tasks[3].title)
	var done := {"setup_pc.unbox": true, "setup_pc.connect_peripherals": true, "setup_pc.power_on": true,
		"setup_pc.go_online": true, "build_computer.install_ram": true, "build_computer.identify_components": true}
	var is_done := func(id: String) -> bool: return done.has(id)
	var s: Dictionary = map.states("irl", is_done)
	check("after Module 1's two, Swap in an SSD is next and the cooler is locked",
		s["build_computer.swap_ssd"] == StoryMap.NEXT and s["build_computer.cooler_paste"] == StoryMap.LOCKED, s)
	done["build_computer.swap_ssd"] = true
	s = map.states("irl", is_done)
	check("then the cooler", s["build_computer.cooler_paste"] == StoryMap.NEXT, s)
	saves.load_profile()
	saves.profile.tasks.clear()
	for id in done:
		saves.record_task_result(id, 100, 30, 1)
	_opened.clear()
	var menu := await _menu()
	menu.show_page("roadmap", "irl")
	await process_frame
	await _click(menu, "Play_build_computer_cooler_paste")
	check("the roadmap plays Reseat the cooler", _opened == ["res://scenes/build_computer/cooler_paste.tscn"], _opened)
	manager.return_scene = ""
	manager.return_page = ""
	manager.return_label = ""
	saves.profile.tasks.clear()
	menu.queue_free()


func _test_free_play_lists_act_2() -> void:
	_opened.clear()
	var menu := await _menu()
	menu.show_page("free_play", "computer")
	await process_frame
	check("Free Play has a card for Swap in an SSD and for Reseat the cooler",
		menu.find_button("Task_build_computer_swap_ssd") != null and menu.find_button("Task_build_computer_cooler_paste") != null)
	await _scroll_to(menu, "Task_build_computer_swap_ssd")
	await _click(menu, "Task_build_computer_swap_ssd")
	check("its card starts the mission", _opened == ["res://scenes/build_computer/swap_ssd.tscn"], _opened)
	var manager := root.get_node("TrainingManager")
	manager.return_scene = ""
	manager.return_page = ""
	manager.return_label = ""
	menu.queue_free()


## Act 3 opens with Build your own PC, under the roadmap's own title for it.
func _test_story_act_3_starts_with_build_your_own() -> void:
	var manager := root.get_node("TrainingManager")
	var map = StoryMap.load_from(manager.registry)
	var first: Dictionary = map.chapter("irl").acts[2].tasks[0]
	check("Act 3's first task is the Build your own PC mission", first.mission == "build_computer.build_your_own", first)
	check("the roadmap keeps its own name for it", first.title == "Pick parts that work together", first.title)
	var done := {}
	var is_done := func(id: String) -> bool: return done.has(id)
	check("it is locked until the acts before it are done", map.states("irl", is_done)["build_computer.build_your_own"] == StoryMap.LOCKED)
	for id in ["setup_pc.unbox", "setup_pc.connect_peripherals", "setup_pc.power_on", "setup_pc.go_online",
			"build_computer.install_ram", "build_computer.identify_components", "build_computer.swap_ssd",
			"build_computer.cooler_paste"]:
		done[id] = true
	var s: Dictionary = map.states("irl", is_done)
	check("then it is the next task, ahead of Assemble the system",
		s["build_computer.build_your_own"] == StoryMap.NEXT and s["build_computer.assemble_system"] == StoryMap.LOCKED, s)


func _test_story_map_bad_mission() -> void:
	var manager := root.get_node("TrainingManager")
	var map = StoryMap.new()
	map.read({"chapters": [{"id": "irl", "acts": [{"title": "A", "tasks": [{"mission": "build_computer.nope"}]}]}]}, manager.registry)
	check("a task naming a mission that doesn't exist is reported", map.errors.size() == 1
		and map.errors[0].contains("build_computer.nope"), map.errors)


func _test_story_chapters() -> void:
	var menu := await _menu()
	menu.show_page("modes")
	await process_frame
	await _click(menu, "StoryCard")
	check("Story Mode opens the chapter picker", menu.page == "story", menu.page)
	check("it offers IRL, Cloud and Bridge", menu.find_button("Chapter_irl") != null
		and menu.find_button("Chapter_cloud") != null and menu.find_button("Chapter_bridge") != null)
	check("Bridge is locked until both chapters are done", menu.find_button("Chapter_bridge").disabled)
	await _click(menu, "Chapter_irl")
	check("IRL opens its roadmap", menu.page == "roadmap", menu.page)
	menu.queue_free()


func _test_roadmap_plays_next() -> void:
	_opened.clear()
	var manager := root.get_node("TrainingManager")
	var saves := root.get_node("SaveService")
	saves.load_profile()
	saves.profile.tasks.clear()
	saves.record_task_result("setup_pc.unbox", 100, 30, 1)
	var menu := await _menu()
	menu.show_page("roadmap", "irl")
	await process_frame
	var node := func(id: String) -> Node: return menu.screen.ui_root.find_child("Node_" + id.replace(".", "_"), true, false)
	check("the done task shows as done", node.call("setup_pc.unbox").get_meta("state") == StoryMap.DONE)
	check("the next task shows as next", node.call("setup_pc.connect_peripherals").get_meta("state") == StoryMap.NEXT)
	check("the tasks after it show as locked", node.call("setup_pc.power_on").get_meta("state") == StoryMap.LOCKED
		and node.call("setup_pc.go_online").get_meta("state") == StoryMap.LOCKED)
	check("a locked task can't be played", menu.find_button("Play_setup_pc_power_on") == null
		and menu.find_button("Play_build_computer_install_ram") == null)
	check("Act 2's new tasks are locked this early", menu.find_button("Play_build_computer_swap_ssd") == null
		and node.call("build_computer.swap_ssd").get_meta("state") == StoryMap.LOCKED)
	await _click(menu, "Play_setup_pc_connect_peripherals")
	check("playing the next task opens its mission", _opened == ["res://scenes/setup_pc/connect_peripherals.tscn"], _opened)
	check("it will come back to this roadmap", manager.return_page == "roadmap:irl" and manager.return_label == "Story Mode",
		manager.return_page)
	check("the roadmap position is saved", saves.story_current("irl") == "setup_pc.connect_peripherals")
	manager.return_scene = ""
	manager.return_page = ""
	manager.return_label = ""
	menu.queue_free()


func _test_roadmap_cloud_planned() -> void:
	var menu := await _menu()
	menu.show_page("roadmap", "cloud")
	await process_frame
	var node: Node = menu.screen.ui_root.find_child("Node_cloud_internet_follow_a_packet", true, false)
	check("Cloud's tasks are all planned for now", node != null and node.get_meta("state") == StoryMap.PLANNED)
	check("a planned task can't be played", menu.find_button("Play_cloud_internet_follow_a_packet") == null)
	menu.queue_free()



## Each act's steps share the screen's width evenly, so a row has no gap at its
## end and a title has room to wrap between words.
func _test_roadmap_rows_fill_the_screen() -> void:
	var menu := await _menu()
	menu.show_page("roadmap", "irl")
	await process_frame
	await process_frame
	var first := menu.screen.ui_root.find_child("Node_setup_pc_unbox", true, false) as Control
	var last := menu.screen.ui_root.find_child("Node_setup_pc_go_online", true, false) as Control
	var roadmap := menu.screen.ui_root.find_child("Roadmap", true, false) as Control
	check("the roadmap's first act is on the page", first != null and last != null and roadmap != null)
	if first == null or last == null or roadmap == null:
		menu.queue_free()
		return
	var row: Control = first.get_parent()
	check("the four steps of an act are the same width", is_equal_approx(first.size.x, last.size.x), "%s and %s" % [first.size.x, last.size.x])
	check("the row of steps is as wide as the roadmap's list", is_equal_approx(row.size.x, row.get_parent().size.x) and row.size.x > roadmap.size.x * 0.9,
		"row %s, list %s, roadmap %s" % [row.size.x, row.get_parent().size.x, roadmap.size.x])
	check("the last step ends where the row ends", is_equal_approx(last.position.x + last.size.x, row.size.x),
		"%s of %s" % [last.position.x + last.size.x, row.size.x])
	menu.queue_free()


## Act 4, "Small rigs", is Build a Network's seven missions in Mr. Mortensen's
## order, then two tasks that are still planned. They open one at a time
## once Act 3 is done.
func _test_story_act_4_unlocks_in_order() -> void:
	var manager := root.get_node("TrainingManager")
	var map = StoryMap.load_from(manager.registry)
	var act: Dictionary = map.chapter("irl").acts[3]
	var ids: Array = act.tasks.map(func(task) -> String: return task.mission)
	check("Act 4 is called Small rigs", act.title == "Act 4: Small rigs", act.title)
	check("Act 4 is the seven Build a Network missions, then two planned tasks", ids == BUILD_NETWORK + ["", ""], ids)
	check("the planned ones are the server rack and the Raspberry Pi cluster",
		act.tasks.slice(7).map(func(t) -> String: return t.title) == ["Build a mini server rack", "A Raspberry Pi cluster"])
	check("each step takes its title from the mission",
		act.tasks.slice(0, 7).map(func(task) -> String: return task.title) == BUILD_NETWORK.map(func(id) -> String: return manager.registry.mission(id).title))
	var done := {}
	var is_done := func(id: String) -> bool: return done.has(id)
	for task in map.tasks_of("irl"):
		if task.mission != "" and not task.mission.begins_with("build_network."):
			done[task.id] = true
	check("with Acts 1 to 3 done, Connect two computers is next", map.states("irl", is_done)["build_network.connect_two"] == StoryMap.NEXT)
	var wrong := []
	for at in BUILD_NETWORK.size():
		var s: Dictionary = map.states("irl", is_done)
		for i in BUILD_NETWORK.size():
			var want: String = StoryMap.DONE if i < at else (StoryMap.NEXT if i == at else StoryMap.LOCKED)
			if s[BUILD_NETWORK[i]] != want:
				wrong.append("%s done: %s is %s" % [at, BUILD_NETWORK[i], s[BUILD_NETWORK[i]]])
		done[BUILD_NETWORK[at]] = true
	check("its missions unlock in order: done ones Done, one Next, the rest Locked", wrong.is_empty(), wrong)
	var after: Dictionary = map.states("irl", is_done)
	check("the planned tasks stay planned", after["irl.rigs.server_rack"] == StoryMap.PLANNED and after["irl.rigs.pi_cluster"] == StoryMap.PLANNED)
	check("with Act 4 done, every playable IRL task is done", map.progress("irl", is_done) == [20, 20] and map.chapter_complete("irl", is_done), map.progress("irl", is_done))


func _test_free_play_lists_build_network() -> void:
	var manager := root.get_node("TrainingManager")
	var difficulty: Array = BUILD_NETWORK.map(func(id) -> String: return manager.registry.mission(id).difficulty)
	check("Build a Network goes Beginner, Intermediate, Advanced",
		difficulty == ["Beginner", "Beginner", "Beginner", "Intermediate", "Intermediate", "Advanced", "Advanced"], difficulty)
	var topics: Array = BUILD_NETWORK.map(func(id) -> String: return manager.registry.mission(id).topic)
	check("its topics are Networks, Packets, Fault tolerance and Parallel computing",
		topics == ["Networks", "Networks", "Networks", "Packets", "Fault tolerance", "Fault tolerance", "Parallel computing"], topics)
	var menu := await _menu()
	menu.show_page("free_play", "computer")
	await process_frame
	var missing: Array = BUILD_NETWORK.filter(func(id) -> bool: return menu.find_button("Task_" + id.replace(".", "_")) == null)
	check("each of the seven has a card in Free Play", missing.is_empty(), missing)
	var card: Node = menu.screen.ui_root.find_child("TaskCard_build_network_router", true, false)
	check("its card shows its image, task_build_network_router (a placeholder for now)",
		card != null and card.find_child("Placeholder_task_build_network_router", true, false) != null)
	_opened.clear()
	await _scroll_to(menu, "Task_build_network_redundancy")
	await _click(menu, "Task_build_network_redundancy")
	check("a card starts its mission", _opened == ["res://scenes/network/redundancy.tscn"], _opened)
	manager.return_scene = ""
	manager.return_page = ""
	manager.return_label = ""
	menu.queue_free()


func _test_roadmap_plays_act_4() -> void:
	_opened.clear()
	var manager := root.get_node("TrainingManager")
	var saves := root.get_node("SaveService")
	saves.load_profile()
	saves.profile.tasks.clear()
	var map = StoryMap.load_from(manager.registry)
	for task in map.tasks_of("irl"):
		if task.mission != "" and not task.mission.begins_with("build_network."):
			saves.record_task_result(task.id, 100, 30, 1)
	saves.record_task_result("build_network.connect_two", 100, 30, 1)
	var menu := await _menu()
	menu.show_page("roadmap", "irl")
	await process_frame
	var node := func(id: String) -> Node: return menu.screen.ui_root.find_child("Node_" + id.replace(".", "_"), true, false)
	check("Act 4's first mission shows as done", node.call("build_network.connect_two").get_meta("state") == StoryMap.DONE)
	check("Add a switch shows as next", node.call("build_network.switch").get_meta("state") == StoryMap.NEXT)
	check("the rest of Act 4 shows as locked", BUILD_NETWORK.slice(2).all(func(id) -> bool: return node.call(id).get_meta("state") == StoryMap.LOCKED))
	check("a locked mission can't be played", menu.find_button("Play_build_network_router") == null)
	check("the server rack is planned and can't be played", node.call("irl.rigs.server_rack").get_meta("state") == StoryMap.PLANNED
		and menu.find_button("Play_irl_rigs_server_rack") == null)
	await _scroll_to(menu, "Play_build_network_switch")
	await _click(menu, "Play_build_network_switch")
	check("playing it opens Add a switch", _opened == ["res://scenes/network/switch.tscn"], _opened)
	check("the roadmap position is saved", saves.story_current("irl") == "build_network.switch")
	saves.profile.tasks.clear()
	manager.return_scene = ""
	manager.return_page = ""
	manager.return_label = ""
	menu.queue_free()


## Scrolls the list a button is in until the button is on screen, as a
## player would before clicking something far down.
func _scroll_to(menu: Node3D, button_name: String) -> void:
	var button: Control = menu.find_button(button_name)
	var at: Node = button
	while at != null and not at is ScrollContainer:
		at = at.get_parent()
	if at:
		(at as ScrollContainer).ensure_control_visible(button)
	await process_frame
	await process_frame
