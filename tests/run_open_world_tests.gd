extends SceneTree
## Checks for Open World v1 (Phase 5, step 8): the spawn panel, placing parts
## on the desk, and the layout saved through SaveService. Run from the
## project folder:
##
##   godot --headless --script res://tests/run_open_world_tests.gd
##
## Exit code 0 means every check passed.

const OpenWorld := preload("res://scenes/open_world/open_world.tscn")
const MenuScene := preload("res://scenes/menus/menu.tscn")
const PartsCatalog := preload("res://scripts/parts/parts_catalog.gd")

const AUTOLOADS := [&"TrainingManager", &"ScoreReporter", &"SaveService"]

var _failures: Array[String] = []
var _opened: Array = []
var manager: Node
var saves: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	saves = root.get_node("SaveService")
	saves.use_backend(preload("res://scripts/save/local_save_backend.gd").new("user://test_ocsvr_save.json"))
	manager = root.get_node("TrainingManager")
	manager.scene_opener = func(path: String) -> void: _opened.append(path)
	for test in [_test_spawn_panel_lists_everything, _test_spawn_puts_parts_on_the_desk, _test_parts_stay_where_dropped,
			_test_parts_stay_on_the_desk, _test_layout_is_saved_and_loaded, _test_clear_the_desk,
			_test_old_save_still_loads, _test_menu_opens_open_world]:
		saves.profile.open_world.layout = []
		await test.call()
	print("\n%s" % ("ALL PASSED" if _failures.is_empty() else "%d FAILED" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)


func check(label: String, ok: bool, detail = "") -> void:
	var why := str(detail)
	print(("PASS  " if ok else "FAIL  ") + label + ("" if ok or why == "" else "   [%s]" % why))
	if not ok:
		_failures.append(label)


func _fresh(node: Node) -> Node:
	for child in root.get_children():
		if not child.name in AUTOLOADS:
			child.queue_free()
	await process_frame
	root.add_child(node)
	for i in 3:
		await physics_frame
	return node


func _world() -> Node3D:
	return await _fresh(OpenWorld.instantiate())


## Clicks a button on the spawn panel the way the pointer does.
func _click(world: Node3D, button_name: String) -> void:
	var button: Button = world.find_button(button_name)
	if button == null:
		check("the spawn panel has %s" % button_name, false)
		return
	var scroll: ScrollContainer = world.screen.ui_root.find_child("SpawnList", true, false)
	scroll.ensure_control_visible(button)
	await process_frame
	await process_frame
	world.pointer.click_world(world.screen.control_to_world(button))
	await process_frame
	await process_frame


## Drags an item through the laptop camera to `to` on the desk.
func _drag(world: Node3D, part: Node3D, to: Vector3) -> bool:
	var grabber = world.get_node("Room/MouseGrabber")
	var camera: Camera3D = world.get_node("Room/Camera3D")
	var got = grabber.try_grab_at(camera.unproject_position((part.get_node("CollisionShape3D") as Node3D).global_position))
	if got != part:
		if got:
			grabber.cancel()
		return false
	grabber.carry_to(camera.unproject_position(Vector3(to.x, grabber.carry_height, to.z)))
	for i in 3:
		await physics_frame
	grabber.release()
	await physics_frame
	return true


func _test_spawn_panel_lists_everything() -> void:
	var world := await _world()
	var catalog = PartsCatalog.shared()
	var missing: Array = catalog.parts.keys().filter(func(id) -> bool: return world.find_button("Spawn_" + id) == null)
	check("the spawn panel lists every part in the catalog", missing.is_empty() and catalog.parts.size() == 18, missing)
	var devices := ["net_pc", "net_mac_mini", "net_switch", "net_router", "net_server", "net_wall_jack"]
	check("and every network device", devices.all(func(id) -> bool: return world.find_button("Spawn_" + id) != null))
	check("the desk has the tool rack", world.get_node_or_null("ToolRack/Screwdriver") != null)
	check("and a Back to menu button", world.get_node_or_null("Room/BackButton") != null)
	check("it starts empty", world.items().is_empty())


func _test_spawn_puts_parts_on_the_desk() -> void:
	var world := await _world()
	await _click(world, "Spawn_cpu_mid")
	check("clicking a part on the panel puts it on the desk", world.items().size() == 1, world.items().size())
	var cpu: Node3D = world.items()[0]
	check("it's the part the button named, with its catalog name", cpu.get_meta("item") == "cpu_mid" and cpu.display_name == "AMD Ryzen 5 7600",
		cpu.display_name)
	check("it sits on the desk", absf(cpu.global_position.y - world.TABLE_TOP) < 0.001, cpu.global_position)
	await _click(world, "Spawn_net_switch")
	var switch: Node3D = world.items()[1]
	check("a network device spawns too", switch.get_meta("item") == "net_switch")
	check("the next one goes beside the first, not on top of it",
		Vector2(switch.global_position.x - cpu.global_position.x, switch.global_position.z - cpu.global_position.z).length() > 0.1)
	check("the device's own ports are off, so the part is what the hand grabs",
		switch.find_children("*", "Area3D", true, false).all(func(a) -> bool: return not a.monitoring))


func _test_parts_stay_where_dropped() -> void:
	var world := await _world()
	var gpu = world.spawn("gpu_mid")
	await physics_frame
	var to := Vector3(0.35, 0.9, 0.15)
	check("a spawned part can be picked up through the camera", await _drag(world, gpu, to))
	check("let go, it stays where it was put, on the desk",
		Vector2(gpu.global_position.x - to.x, gpu.global_position.z - to.z).length() < 0.02 and absf(gpu.global_position.y - 0.9) < 0.001,
		gpu.global_position)
	check("and that is its new home", gpu.home_transform.origin.is_equal_approx(gpu.global_position))
	check("nothing is scored: no mission is running", manager.state == manager.State.IDLE, manager.state)


func _test_parts_stay_on_the_desk() -> void:
	var world := await _world()
	var psu = world.spawn("psu_mid")
	await physics_frame
	psu.grab()
	psu.global_position = Vector3(2.0, 1.4, -3.0)
	psu.drop()
	world.get_node("Room/MouseGrabber").part_dropped.emit(psu)
	check("dropped off the edge, a part is put back on the desk",
		absf(psu.global_position.x) <= 0.58 and absf(psu.global_position.z) <= 0.33 and absf(psu.global_position.y - 0.9) < 0.001,
		psu.global_position)


func _test_layout_is_saved_and_loaded() -> void:
	_opened.clear()
	manager.return_scene = "res://scenes/menus/menu.tscn"
	manager.return_page = "modes"
	var world := await _world()
	var board = world.spawn("board_mid")
	var router = world.spawn("net_router")
	await physics_frame
	await _drag(world, router, Vector3(-0.2, 0.9, -0.2))
	var where: Vector3 = router.global_position
	world.get_node("Room/BackButton").press()
	check("Back to menu goes back where Open World was opened from", _opened == ["res://scenes/menus/menu.tscn"], _opened)
	var saved: Array = saves.load_world_layout()
	check("the layout is saved: one {item, transform} per item", saved.size() == 2
		and saved.map(func(e) -> String: return e.item) == ["board_mid", "net_router"]
		and saved.all(func(e) -> bool: return e.transform.size() == 12), saved)
	saves.load_profile()
	check("it's in the save file, not only in memory", saves.load_world_layout().size() == 2, saves.load_world_layout())
	var again := await _world()
	check("coming back puts the same items on the desk", again.items().map(func(n) -> String: return n.get_meta("item")) == ["board_mid", "net_router"])
	var back_router: Node3D = again.items()[1]
	check("where they were left", back_router.global_position.distance_to(where) < 0.001, "%s vs %s" % [back_router.global_position, where])
	manager.return_scene = ""
	manager.return_page = ""


func _test_clear_the_desk() -> void:
	var world := await _world()
	world.spawn("ram_mid")
	world.spawn("storage_high")
	await _click(world, "ClearDesk")
	await process_frame
	check("Clear the desk takes every item away", world.items().is_empty(), world.items().size())


func _test_old_save_still_loads() -> void:
	saves.profile.open_world.layout = [
		{"item": "cpu_starter", "transform": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0.1, 0.9, 0.1]},
		{"item": "a_part_since_removed", "transform": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0.2, 0.9, 0.1]},
		{"item": "cpu_mid", "transform": [1, 2]},
	]
	var world := await _world()
	check("a layout with an unknown item or a broken transform still loads what it can",
		world.items().size() == 1 and world.items()[0].get_meta("item") == "cpu_starter", world.items().size())


func _test_menu_opens_open_world() -> void:
	_opened.clear()
	var menu: Node3D = MenuScene.instantiate()
	await _fresh(menu)
	menu.show_page("modes")
	await process_frame
	var card: Button = menu.find_button("OpenWorldCard")
	var page_text: Array = menu.screen.ui_root.find_children("*", "Label", true, false).map(func(l) -> String: return l.text)
	check("the Open World card no longer says Coming soon", card != null and "Open World" in page_text and not "Coming soon" in page_text,
		page_text)
	menu.pointer.click_world(menu.screen.control_to_world(card))
	await process_frame
	check("clicking it opens Open World", _opened == ["res://scenes/open_world/open_world.tscn"], _opened)
	check("which will come back to the mode picker", manager.return_page == "modes", manager.return_page)
	manager.return_scene = ""
	manager.return_page = ""
	manager.return_label = ""
