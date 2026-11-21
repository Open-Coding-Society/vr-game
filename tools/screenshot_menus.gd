extends SceneTree
## Saves a picture of every menu page to build/shots/ (git-ignored), to check
## how the menus look without a headset. Needs a real window (not --headless):
##
##   godot --path . --script res://tools/screenshot_menus.gd
##
## Each argument after "--" is a page to shoot as page[:arg], e.g.
## -- home modes free_play:computer; with none, every page is shot.

const MenuScene := preload("res://scenes/menus/menu.tscn")
const DEFAULT_PAGES := ["home", "login", "modes", "coming_soon:Open World"]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var saves := root.get_node_or_null("SaveService")
	if saves:
		saves.use_backend(preload("res://scripts/save/local_save_backend.gd").new("user://test_ocsvr_save.json"))
	var menu: Node3D = MenuScene.instantiate()
	root.add_child(menu)
	for i in 5:
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	var pages: Array = Array(OS.get_cmdline_user_args())
	if pages.is_empty():
		pages = DEFAULT_PAGES
	for spec in pages:
		var bits: PackedStringArray = str(spec).split(":", true, 1)
		menu.show_page(bits[0], bits[1] if bits.size() > 1 else "")
		for i in 6:
			await process_frame
		var image: Image = menu.screen.viewport.get_texture().get_image()
		var file := "res://build/shots/%s.png" % str(spec).replace(":", "_").replace(" ", "_")
		image.save_png(ProjectSettings.globalize_path(file))
		print("saved ", file)
	quit(0)
