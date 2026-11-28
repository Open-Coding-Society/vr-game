extends SceneTree
## Builds Phase 5's placeholder scenes from code and saves them as .tscn files,
## so their layout is written down in one place and easy to change:
##
##   godot --headless --script res://tools/make_phase5_scenes.gd
##
## Every part is simple shapes at real size (1 unit = 1 m), with its logic on
## the parent node and its look in a child named "Mesh" (VR rule 7), so
## Aryan's detailed models (Phase 6) swap in by replacing that child. Parts and
## snap points have plain names (Screwdriver, OldSsd, DriveBay/SnapPoint...) for
## the same reason. Run it again after changing a layout below; the scenes it
## writes are the ones in git.

const SnapZone := preload("res://scripts/snap_zone.gd")
const GrabbablePart := preload("res://scripts/grabbable_part.gd")
const Tool := preload("res://scripts/tools/tool.gd")
const Mission := preload("res://scripts/missions/mission.gd")
const InfoPanel := preload("res://scripts/ui/info_panel.gd")
const Room := preload("res://scenes/room.tscn")
const BoardVisual := preload("res://models/board/board_visual.tscn")
const SsdVisual := preload("res://models/ssd_sata/ssd_sata_visual.tscn")
const CpuVisual := preload("res://models/cpu/cpu_visual.tscn")
const MonitorShape := preload("res://scenes/setup_pc/props/monitor.tscn")
const MonitorScreen := preload("res://scripts/parts/monitor_screen.gd")
const OpenWorld := preload("res://scripts/open_world/open_world.gd")
const MenuScreen3D := preload("res://scripts/ui/menu_screen_3d.gd")
const MenuPointer := preload("res://scripts/input/menu_pointer.gd")

## The desk's top, as in scripts/room.gd.
const TABLE_TOP := 0.9
## The info panel's place and tilt in every mission (as in the other scenes).
const PANEL_AT := Vector3(-0.02, 1.12, -0.32)
const PANEL_TILT_DEG := -25.0

## Every scene this makes, by name.
## (_tools makes several; the rest one each. The tools come first: the rack
## and the missions place the saved tool scenes.)
var SCENES := {
	"tools": _tools,
	"tool_rack": _tool_rack,
	"swap_ssd": _swap_ssd,
	"cooler_paste": _cooler_paste,
	"open_world": _open_world,
}


func _initialize() -> void:
	var only := OS.get_cmdline_user_args()
	for scene_name in SCENES:
		if only.is_empty() or scene_name in only:
			var made: Array = SCENES[scene_name].call()
			for scene in (made if made[0] is Array else [made]):
				_save(scene[0], scene[1])
	quit()


# ---------------------------------------------------------------- scenes

## One scene per tool (scenes/tools/<tool type>.tscn), so a mission can use
## a single tool (the multimeter in Diagnose a failure) and Phase 6 can give
## each tool its real model in one file.
func _tools() -> Array:
	var made := []
	for tool_type in TOOL_LOOKS:
		made.append(["res://scenes/tools/%s.tscn" % tool_type, _make_tool(tool_type)])
	return made


## Each tool's node name, grab shape and where its label floats (labels of
## neighbours on the rack are at different heights, so they don't overlap).
const TOOL_LOOKS := {
	"screwdriver": {"name": "Screwdriver", "size": Vector3(0.05, 0.03, 0.19), "tag_y": 0.05},
	"wrist_strap": {"name": "WristStrap", "size": Vector3(0.09, 0.03, 0.09), "tag_y": 0.08},
	"thermal_paste": {"name": "ThermalPaste", "size": Vector3(0.04, 0.03, 0.12), "tag_y": 0.05},
	"multimeter": {"name": "Multimeter", "size": Vector3(0.08, 0.035, 0.14), "tag_y": 0.085},
	"cloth": {"name": "Cloth", "size": Vector3(0.1, 0.02, 0.1), "tag_y": 0.05},
}


func _make_tool(tool_type: String) -> RigidBody3D:
	var holder := Node3D.new()
	var look: Dictionary = TOOL_LOOKS[tool_type]
	var tool := _tool(holder, look.name, tool_type, Vector3.ZERO, look.size)
	holder.remove_child(tool)
	holder.free()
	tool.get_node("Name").position.y = look.tag_y
	var mesh := tool.get_node("Mesh")
	match tool_type:
		"screwdriver":
			_cylinder(mesh, "Handle", 0.014, 0.1, Vector3(0, 0.014, 0.045), Vector3(90, 0, 0), Color(0.85, 0.2, 0.15))
			_cylinder(mesh, "Shaft", 0.003, 0.085, Vector3(0, 0.014, -0.045), Vector3(90, 0, 0), Color(0.75, 0.76, 0.78))
		"wrist_strap":
			var band := MeshInstance3D.new()
			band.name = "Band"
			var torus := TorusMesh.new()
			torus.inner_radius = 0.028
			torus.outer_radius = 0.036
			torus.material = _material(Color(0.15, 0.35, 0.8))
			band.mesh = torus
			band.position = Vector3(0, 0.004, 0)
			mesh.add_child(band)
			_box(mesh, "Clip", Vector3(0.016, 0.01, 0.022), Vector3(0.036, 0.005, 0), Color(0.6, 0.62, 0.66))
		"thermal_paste":
			_cylinder(mesh, "Syringe", 0.008, 0.085, Vector3(0, 0.008, 0.005), Vector3(90, 0, 0), Color(0.82, 0.83, 0.85))
			_cylinder(mesh, "Tip", 0.003, 0.02, Vector3(0, 0.008, -0.047), Vector3(90, 0, 0), Color(0.55, 0.56, 0.58))
			_cylinder(mesh, "Plunger", 0.005, 0.03, Vector3(0, 0.008, 0.06), Vector3(90, 0, 0), Color(0.3, 0.3, 0.32))
		"multimeter":
			_box(mesh, "Body", Vector3(0.072, 0.028, 0.13), Vector3(0, 0.014, 0), Color(0.95, 0.75, 0.1))
			_box(mesh, "Screen", Vector3(0.052, 0.002, 0.032), Vector3(0, 0.029, -0.035), Color(0.55, 0.62, 0.5))
			_cylinder(mesh, "Dial", 0.016, 0.004, Vector3(0, 0.03, 0.02), Vector3.ZERO, Color(0.15, 0.15, 0.16))
			var display := _label(tool, "Display", "--.- V", Vector3(0, 0.031, -0.035), 40)
			display.rotation_degrees = Vector3(-90, 0, 0)
			display.modulate = Color(0.1, 0.12, 0.1)
			display.outline_size = 0
			display.pixel_size = 0.00025
		"cloth":
			_box(mesh, "Sheet", Vector3(0.1, 0.006, 0.1), Vector3(0, 0.003, 0), Color(0.55, 0.78, 0.9))
	return tool


## A tool scene placed under `parent`, named as its own scene names it.
func _place_tool(parent: Node3D, tool_type: String, at: Vector3) -> Node3D:
	var tool: Node3D = ResourceLoader.load("res://scenes/tools/%s.tscn" % tool_type, "", ResourceLoader.CACHE_MODE_REPLACE).instantiate()
	tool.position = at
	parent.add_child(tool)
	return tool


## The tool rack (Phase 5 step 3): a tray with one of each tool, one size
## (design plan §5, "keep it simple"). Each tool's place on the tray is its
## home: a dropped tool floats back to it. Missions instance the rack.
func _tool_rack() -> Array:
	var rack := Node3D.new()
	rack.name = "ToolRack"
	_box(rack, "Tray", Vector3(0.4, 0.012, 0.15), Vector3(0, 0.006, 0), Color(0.22, 0.23, 0.25))
	_box(rack, "Lip", Vector3(0.4, 0.02, 0.008), Vector3(0, 0.01, -0.071), Color(0.22, 0.23, 0.25))
	var sign := _label(rack, "Sign", "Tool rack", Vector3(0, 0.026, -0.071), 40)
	sign.rotation_degrees = Vector3(-35, 0, 0)
	_place_tool(rack, "screwdriver", Vector3(-0.135, 0.012, 0))
	_place_tool(rack, "wrist_strap", Vector3(-0.045, 0.012, 0))
	_place_tool(rack, "thermal_paste", Vector3(0.045, 0.012, 0))
	_place_tool(rack, "multimeter", Vector3(0.14, 0.012, 0))
	return ["res://scenes/tools/tool_rack.tscn", rack]


## Act 2, "Swap in an SSD" (step 4): a small PC case lies open side up on the
## right of the desk. Strap on, unscrew the side panel (4 screws) and put it
## down, unscrew the drive, take out the old SSD, fit the new one, screw it
## down, close the case. data/modules.json gives the order with `requires`.
func _swap_ssd() -> Array:
	var root := _mission("SwapSsd", "build_computer.swap_ssd", 34)
	_place_rack(root)
	_zone(root, "Wrist", Vector3(-0.06, TABLE_TOP, 0.25), Vector3(0.1, 0.12, 0.1), Vector2(0.09, 0.09), "Your wrist")

	# The case: a tray with walls (a low lip at the front, so the laptop camera
	# sees in), the motherboard inside, and a drive bay in the free strip
	# behind the board.
	var case_node := Node3D.new()
	case_node.name = "Case"
	case_node.position = Vector3(0.2, TABLE_TOP, 0.02)
	root.add_child(case_node)
	var shell := Node3D.new()
	shell.name = "Shell"
	case_node.add_child(shell)
	var steel := Color(0.3, 0.31, 0.33)
	_box(shell, "Floor", Vector3(0.36, 0.006, 0.36), Vector3(0, 0.003, 0), steel)
	_box(shell, "Back", Vector3(0.36, WALL, 0.006), Vector3(0, WALL / 2.0, -0.177), steel)
	_box(shell, "Front", Vector3(0.36, LIP, 0.006), Vector3(0, LIP / 2.0, 0.177), steel)
	_box(shell, "Left", Vector3(0.006, WALL, 0.36), Vector3(-0.177, WALL / 2.0, 0), steel)
	_box(shell, "Right", Vector3(0.006, WALL, 0.36), Vector3(0.177, WALL / 2.0, 0), steel)
	var board := BoardVisual.instantiate()
	board.name = "Motherboard"
	board.position = Vector3(0, 0.008, 0.055)
	shell.add_child(board)
	_box(shell, "DriveBracket", Vector3(0.12, 0.004, 0.08), Vector3(0.07, 0.008, -0.125), Color(0.55, 0.56, 0.58))

	var bay := Vector3(0.07, 0.01, -0.125)
	var screw_at := Vector3(0.135, 0.01, -0.125)
	var panel_top := Vector3(0, WALL + 0.003, 0)
	# Tool steps and the panel's slot cover the whole case, top to floor, so a
	# tool carried at any height over the case reaches them.
	var screws := _zone(case_node, "PanelScrews", Vector3.ZERO, Vector3(0.38, 0.16, 0.38))
	var fasteners := Node3D.new()
	fasteners.name = "Fasteners"
	screws.add_child(fasteners)
	for i in 4:
		var corner := Vector3(0.16 * (1 if i % 2 else -1), WALL + 0.008, 0.16 * (1 if i >= 2 else -1))
		_cylinder(fasteners, "Screw%d" % (i + 1), 0.005, 0.006, corner, Vector3.ZERO, Color(0.8, 0.8, 0.82))
	_zone(case_node, "DriveScrew", screw_at, Vector3(0.05, 0.16, 0.06))
	var drive_screw_look := Node3D.new()
	drive_screw_look.name = "Fasteners"
	case_node.get_node("DriveScrew").add_child(drive_screw_look)
	_cylinder(drive_screw_look, "Screw", 0.004, 0.008, Vector3(0, 0.004, 0), Vector3.ZERO, Color(0.8, 0.8, 0.82))
	_zone(case_node, "DriveBay", bay, Vector3(0.12, 0.16, 0.09))
	var screw_down := _zone(case_node, "ScrewDown", screw_at, Vector3(0.05, 0.16, 0.06))
	var fastens := Node3D.new()
	fastens.name = "Fastens"
	screw_down.add_child(fastens)
	_cylinder(fastens, "Screw", 0.004, 0.008, Vector3(0, 0.004, 0), Vector3.ZERO, Color(0.8, 0.8, 0.82)).visible = false
	_zone(case_node, "CloseCase", Vector3.ZERO, Vector3(0.38, 0.16, 0.38), Vector2.ZERO, "", panel_top)

	# The side panel sits on the case to start; its home moves to the spot
	# on the desk (a pass-through slot), then it goes back on the case.
	var side_panel := _part(root, "SidePanel", Vector3(0.2, TABLE_TOP, 0.02) + panel_top, Vector3(0.36, 0.012, 0.36), Vector3(0, 0.003, 0))
	_box(side_panel.get_node("Mesh"), "Sheet", Vector3(0.36, 0.006, 0.36), Vector3(0, 0.003, 0), Color(0.42, 0.43, 0.46))
	_label(side_panel, "Name", "Side panel", Vector3(-0.1, 0.03, 0.1), 48).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_zone(root, "PanelSpot", Vector3(-0.33, TABLE_TOP, -0.12), Vector3(0.38, 0.12, 0.3), Vector2(0.37, 0.29), "Side panel")

	var old_ssd := _part(root, "OldSsd", Vector3(0.2, TABLE_TOP, 0.02) + bay, Vector3(0.1, 0.012, 0.07), Vector3(0, 0.003, 0))
	old_ssd.get_node("Mesh").add_child(SsdVisual.instantiate())
	_label(old_ssd, "Name", "Old SSD", Vector3(0, 0.03, 0), 48).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var new_ssd := _part(root, "NewSsd", Vector3(0.5, TABLE_TOP, 0.08), Vector3(0.1, 0.012, 0.07), Vector3(0, 0.003, 0))
	new_ssd.get_node("Mesh").add_child(SsdVisual.instantiate())
	_label(new_ssd, "Name", "New SSD", Vector3(0, 0.03, 0), 48).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_zone(root, "OldTray", Vector3(0.5, TABLE_TOP, 0.26), Vector3(0.13, 0.12, 0.11), Vector2(0.12, 0.1), "Old parts")
	return ["res://scenes/build_computer/swap_ssd.tscn", root]


## Act 2, "Reseat the cooler" (step 5): a motherboard on the desk with its
## CPU and cooler, and a monitor showing the CPU's temperature. Unscrew the
## cooler and put it down, wipe the old paste off with the cloth, put a dot of
## new paste on, put the cooler back and screw it down, plug its fan into
## CPU_FAN. The monitor then restarts and shows the cooler CPU. Every step at
## the CPU is a slot over the socket; `requires` decides which one is next.
func _cooler_paste() -> Array:
	var root := _mission("CoolerPaste", "build_computer.cooler_paste", 36)
	_place_rack(root)

	var board := Node3D.new()
	board.name = "Motherboard"
	board.position = Vector3(0, TABLE_TOP + 0.002, 0)
	root.add_child(board)
	board.add_child(BoardVisual.instantiate())
	var socket := Vector3(0.056, 0.0015, 0.008)
	var cpu := CpuVisual.instantiate()
	cpu.name = "Cpu"
	cpu.position = socket
	board.add_child(cpu)
	var socket_at: Vector3 = board.position + socket
	var at_cpu := Vector3(0.12, 0.16, 0.12)

	var unscrew := _zone(root, "CoolerScrews", socket_at, at_cpu)
	var screws := Node3D.new()
	screws.name = "Fasteners"
	unscrew.add_child(screws)
	for i in 2:
		_cylinder(screws, "Screw%d" % (i + 1), 0.005, 0.006, Vector3(0.045 * (1 if i else -1), COOLER_H + 0.003, 0.045 * (-1 if i else 1)), Vector3.ZERO, Color(0.8, 0.8, 0.82))
	var wipe := _zone(root, "WipePaste", socket_at, at_cpu)
	var old_paste := Node3D.new()
	old_paste.name = "Fasteners"
	wipe.add_child(old_paste)
	_cylinder(old_paste, "OldPaste", 0.014, 0.0012, Vector3(0, 0.0045, 0), Vector3.ZERO, Color(0.55, 0.55, 0.5))
	var paste := _zone(root, "NewPaste", socket_at, at_cpu)
	var dot := Node3D.new()
	dot.name = "Fastens"
	paste.add_child(dot)
	_cylinder(dot, "Dot", 0.005, 0.002, Vector3(0, 0.0045, 0), Vector3.ZERO, Color(0.85, 0.86, 0.88)).visible = false
	_zone(root, "CoolerBack", socket_at, at_cpu)
	var fasten := _zone(root, "CoolerFasten", socket_at, at_cpu)
	var new_screws := Node3D.new()
	new_screws.name = "Fastens"
	fasten.add_child(new_screws)
	for i in 2:
		_cylinder(new_screws, "Screw%d" % (i + 1), 0.005, 0.006, Vector3(0.045 * (1 if i else -1), COOLER_H + 0.003, 0.045 * (-1 if i else 1)), Vector3.ZERO, Color(0.8, 0.8, 0.82)).visible = false
	var header := _zone(root, "FanHeader", board.position + Vector3(0.0, 0.0015, -0.085), Vector3(0.04, 0.12, 0.04))
	var header_label := _label(header, "Label", "CPU_FAN", Vector3(0, 0.006, 0.018), 32)
	header_label.rotation_degrees = Vector3(-90, 0, 0)
	_box(header, "Pins", Vector3(0.012, 0.006, 0.005), Vector3(0, 0.003, 0), Color(0.95, 0.95, 0.95))

	# The cooler starts on the CPU; its home moves to the spot on the desk (a
	# pass-through slot), then it goes back on the CPU.
	var cooler := _part(root, "Cooler", socket_at + Vector3(0, 0.004, 0), Vector3(0.1, COOLER_H, 0.1), Vector3(0, COOLER_H / 2.0, 0))
	var fins := cooler.get_node("Mesh")
	_box(fins, "Heatsink", Vector3(0.092, 0.04, 0.092), Vector3(0, 0.02, 0), Color(0.72, 0.73, 0.75))
	_cylinder(fins, "Fan", 0.043, 0.016, Vector3(0, 0.048, 0), Vector3.ZERO, Color(0.12, 0.12, 0.13))
	_cylinder(fins, "Hub", 0.014, 0.018, Vector3(0, 0.049, 0), Vector3.ZERO, Color(0.25, 0.25, 0.27))
	_label(cooler, "Name", "CPU cooler", Vector3(0, COOLER_H + 0.03, 0), 48).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_zone(root, "CoolerSpot", Vector3(-0.38, TABLE_TOP, -0.15), Vector3(0.17, 0.12, 0.17), Vector2(0.16, 0.16), "Cooler")

	var plug := _part(root, "FanPlug", Vector3(0.15, TABLE_TOP + 0.004, 0.07), Vector3(0.03, 0.02, 0.02), Vector3(0, 0.006, 0))
	_box(plug.get_node("Mesh"), "Plug", Vector3(0.012, 0.008, 0.006), Vector3(0, 0.004, 0), Color(0.1, 0.1, 0.1))
	_box(plug.get_node("Mesh"), "Wire", Vector3(0.05, 0.002, 0.003), Vector3(-0.03, 0.002, 0), Color(0.15, 0.15, 0.15))
	_label(plug, "Name", "Fan plug", Vector3(0, 0.03, 0), 40).billboard = BaseMaterial3D.BILLBOARD_ENABLED

	_place_tool(root, "cloth", Vector3(0.47, TABLE_TOP, 0.24))

	var monitor := Node3D.new()
	monitor.name = "Monitor"
	monitor.position = Vector3(0.46, TABLE_TOP, -0.2)
	monitor.rotation_degrees = Vector3(0, -40, 0)
	root.add_child(monitor)
	var shape := MonitorShape.instantiate()
	shape.name = "Shape"
	monitor.add_child(shape)
	var screen := Node3D.new()
	screen.set_script(MonitorScreen)
	screen.name = "MonitorScreen"
	screen.position = Vector3(0, 0.185, -0.002)
	screen.size = Vector2(0.34, 0.21)
	screen.pixels_per_meter = 2400
	monitor.add_child(screen)
	return ["res://scenes/build_computer/cooler_paste.tscn", root]


## Open World v1 (step 8): the room and its desk, the tool rack, the spawn
## panel where a mission's info panel would be, the menu pointer for it, and
## an empty "Items" node the spawned parts go under (scripts/open_world/
## open_world.gd does the rest).
func _open_world() -> Array:
	var root := Node3D.new()
	root.set_script(OpenWorld)
	root.name = "OpenWorld"
	var room := Room.instantiate()
	room.name = "Room"
	root.add_child(room)
	_place_rack(root)
	var screen := Node3D.new()
	screen.set_script(MenuScreen3D)
	screen.name = "SpawnScreen"
	screen.position = Vector3(-0.02, 1.09, -0.34)
	screen.rotation_degrees = Vector3(PANEL_TILT_DEG, 0, 0)
	screen.size = Vector2(0.74, 0.38)
	screen.pixels_per_meter = 1500
	root.add_child(screen)
	var pointer := Node3D.new()
	pointer.set_script(MenuPointer)
	pointer.name = "MenuPointer"
	root.add_child(pointer)
	var items := Node3D.new()
	items.name = "Items"
	root.add_child(items)
	return ["res://scenes/open_world/open_world.tscn", root]


## How tall the placeholder cooler is (meters).
const COOLER_H := 0.065


## How tall the placeholder case's walls are, and its front lip (meters).
const WALL := 0.12
const LIP := 0.04


# ---------------------------------------------------------------- pieces

## The tool rack at its usual place: the front left of the desk.
func _place_rack(root: Node3D) -> Node3D:
	var rack: Node3D = ResourceLoader.load("res://scenes/tools/tool_rack.tscn", "", ResourceLoader.CACHE_MODE_REPLACE).instantiate()
	rack.position = Vector3(-0.33, TABLE_TOP, 0.2)
	root.add_child(rack)
	return rack

## A mission scene's root: the mission script, the room and the info panel.
func _mission(node_name: String, mission_id: String, body_size := 40) -> Node3D:
	var root := Node3D.new()
	root.set_script(Mission)
	root.name = node_name
	root.mission_id = mission_id
	var room := Room.instantiate()
	room.name = "Room"
	root.add_child(room)
	var panel := Node3D.new()
	panel.set_script(InfoPanel)
	panel.name = "InfoPanel"
	panel.position = PANEL_AT
	panel.rotation_degrees = Vector3(PANEL_TILT_DEG, 0, 0)
	panel.body_size = body_size
	root.add_child(panel)
	return root


## A SnapZone at `at`: a drop area of `area` sitting on the surface, a
## SnapPoint (at `snap`, on the surface by default) and, when `pad` isn't
## zero, a thin pad with `text` on it so the player sees where it is.
func _zone(parent: Node3D, node_name: String, at: Vector3, area: Vector3, pad := Vector2.ZERO, text := "", snap := Vector3(0, 0.002, 0)) -> Area3D:
	var zone := Area3D.new()
	zone.set_script(SnapZone)
	zone.name = node_name
	zone.position = at
	parent.add_child(zone)
	_shape(zone, area, Vector3(0, area.y / 2.0, 0))
	var point := Marker3D.new()
	point.name = "SnapPoint"
	point.position = snap
	zone.add_child(point)
	if pad != Vector2.ZERO:
		_box(zone, "Mesh", Vector3(pad.x, 0.002, pad.y), Vector3(0, 0.001, 0), Color(0.2, 0.3, 0.5))
		var label := _label(zone, "Label", text, Vector3(0, 0.003, 0), 48)
		label.rotation_degrees = Vector3(-90, 0, 0)
	return zone


## A part (GrabbablePart) whose origin is at `at`: a grab shape of `size`
## centred at `center`, and an empty "Mesh" for its look.
func _part(parent: Node3D, node_name: String, at: Vector3, size: Vector3, center: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(GrabbablePart)
	body.name = node_name
	body.position = at
	parent.add_child(body)
	_shape(body, size, center)
	var look := Node3D.new()
	look.name = "Mesh"
	body.add_child(look)
	return body


## A tool (scripts/tools/tool.gd) standing at `at` on its parent: a grab shape
## of `size` sitting on the surface, an empty "Mesh" to put its look in, and
## a "Name" label above it.
func _tool(parent: Node3D, node_name: String, tool_type: String, at: Vector3, size: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(Tool)
	body.name = node_name
	body.tool_type = tool_type
	body.position = at
	parent.add_child(body)
	_shape(body, size, Vector3(0, size.y / 2.0, 0))
	var look := Node3D.new()
	look.name = "Mesh"
	body.add_child(look)
	var tag := Label3D.new()
	tag.name = "Name"
	tag.text = Tool.TAGS[tool_type]
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.0003
	tag.font_size = 40
	tag.outline_size = 10
	tag.no_depth_test = true
	tag.position = Vector3(0, size.y + 0.02, 0)
	body.add_child(tag)
	return body


func _shape(parent: Node3D, size: Vector3, at: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	parent.add_child(shape)
	return shape


func _material(color: Color, roughness := 0.75) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


func _box(parent: Node, node_name: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(color)
	mesh.mesh = box
	mesh.position = at
	parent.add_child(mesh)
	return mesh


func _cylinder(parent: Node, node_name: String, radius: float, height: float, at: Vector3, rot_deg: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 16
	cyl.material = _material(color)
	mesh.mesh = cyl
	mesh.position = at
	mesh.rotation_degrees = rot_deg
	parent.add_child(mesh)
	return mesh


func _label(parent: Node, node_name: String, text: String, at: Vector3, font_size := 48) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.0004
	label.outline_size = 8
	label.position = at
	parent.add_child(label)
	return label


# ---------------------------------------------------------------- saving

func _save(path: String, root_node: Node) -> void:
	_own(root_node, root_node)
	var packed := PackedScene.new()
	var err := packed.pack(root_node)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		err = ResourceSaver.save(packed, path)
	print("%s %s" % ["wrote" if err == OK else "FAILED (%d)" % err, path])
	root_node.free()


## Every node below `root_node` belongs to it, so it's saved; an instanced
## scene's own children stay inside its instance.
func _own(node: Node, root_node: Node) -> void:
	for child in node.get_children():
		child.owner = root_node
		if child.scene_file_path == "":
			_own(child, root_node)
