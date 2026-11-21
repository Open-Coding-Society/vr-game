extends SceneTree
## Makes the interim menu images in ui/images/: one Google Material Symbol
## (ui/icons/material/, Apache 2.0) drawn in the menu's OCS blue, centered on the
## flat card color, at each image's size from docs/IMAGES_NEEDED.md. Flat, no
## gradients. Phase 8's Canva art replaces these files with the same names.
##
##   godot --headless --path . --script res://tools/make_menu_images.gd

const ACCENT := "#2F81F7"
const BACKGROUND := Color("#202733")

## image name -> [icon, width, height]
const IMAGES := {
	"home_hero": ["view_in_ar", 1240, 1240],
	"mode_free_play": ["grid_view", 860, 680],
	"mode_story": ["route", 860, 680],
	"mode_open_world": ["handyman", 860, 680],
	"story_irl": ["memory", 860, 680],
	"story_cloud": ["cloud", 860, 680],
	"story_bridge": ["hub", 860, 680],
	"task_install_ram": ["memory_alt", 460, 300],
	"task_identify_components": ["developer_board", 460, 300],
	"task_assemble_system": ["build", 460, 300],
	"task_execute_task": ["swap_horiz", 460, 300],
	"task_add_capacity": ["speed", 460, 300],
	"task_diagnose_failure": ["bug_report", 460, 300],
}


func _initialize() -> void:
	var out_dir := ProjectSettings.globalize_path("res://ui/images")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var failed := 0
	for name in IMAGES:
		var spec: Array = IMAGES[name]
		var svg := FileAccess.get_file_as_string("res://ui/icons/material/%s.svg" % spec[0])
		if svg == "":
			push_error("missing icon " + spec[0])
			failed += 1
			continue
		svg = svg.replace("<svg ", '<svg fill="%s" ' % ACCENT)
		var size := Vector2i(spec[1], spec[2])
		# The icon is 48 px at scale 1; make it 45% of the shorter side.
		var scale := (mini(size.x, size.y) * 0.45) / 48.0
		var icon := Image.new()
		if icon.load_svg_from_string(svg, scale) != OK:
			push_error("couldn't draw " + spec[0])
			failed += 1
			continue
		icon.convert(Image.FORMAT_RGBA8)
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(BACKGROUND)
		image.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), (size - icon.get_size()) / 2)
		image.save_png(out_dir.path_join(name + ".png"))
		print("made ", name, ".png ", size)
	quit(1 if failed else 0)
