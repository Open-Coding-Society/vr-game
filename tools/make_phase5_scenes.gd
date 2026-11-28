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
const ToolRack := preload("res://scenes/tools/tool_rack.tscn")
const BoardVisual := preload("res://models/board/board_visual.tscn")
const SsdVisual := preload("res://models/ssd_sata/ssd_sata_visual.tscn")

## The desk's top, as in scripts/room.gd.
const TABLE_TOP := 0.9
## The info panel's place and tilt in every mission (as in the other scenes).
const PANEL_AT := Vector3(-0.02, 1.12, -0.32)
const PANEL_TILT_DEG := -25.0

## Every scene this makes, by name.
var SCENES := {
	"tool_rack": _tool_rack,
	"swap_ssd": _swap_ssd,
}


func _initialize() -> void:
	var only := OS.get_cmdline_user_args()
	for scene_name in SCENES:
		if only.is_empty() or scene_name in only:
			var made: Array = SCENES[scene_name].call()
			_save(made[0], made[1])
	quit()


# ---------------------------------------------------------------- scenes

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

	var screwdriver := _tool(rack, "Screwdriver", "screwdriver", Vector3(-0.135, 0.012, 0), Vector3(0.05, 0.03, 0.19))
	var look := screwdriver.get_node("Mesh")
	_cylinder(look, "Handle", 0.014, 0.1, Vector3(0, 0.014, 0.045), Vector3(90, 0, 0), Color(0.85, 0.2, 0.15))
	_cylinder(look, "Shaft", 0.003, 0.085, Vector3(0, 0.014, -0.045), Vector3(90, 0, 0), Color(0.75, 0.76, 0.78))

	var strap := _tool(rack, "WristStrap", "wrist_strap", Vector3(-0.045, 0.012, 0), Vector3(0.09, 0.03, 0.09))
	var band := MeshInstance3D.new()
	band.name = "Band"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.028
	torus.outer_radius = 0.036
	torus.material = _material(Color(0.15, 0.35, 0.8))
	band.mesh = torus
	band.position = Vector3(0, 0.004, 0)
	strap.get_node("Mesh").add_child(band)
	_box(strap.get_node("Mesh"), "Clip", Vector3(0.016, 0.01, 0.022), Vector3(0.036, 0.005, 0), Color(0.6, 0.62, 0.66))

	var paste := _tool(rack, "ThermalPaste", "thermal_paste", Vector3(0.045, 0.012, 0), Vector3(0.04, 0.03, 0.12))
	_cylinder(paste.get_node("Mesh"), "Syringe", 0.008, 0.085, Vector3(0, 0.008, 0.005), Vector3(90, 0, 0), Color(0.82, 0.83, 0.85))
	_cylinder(paste.get_node("Mesh"), "Tip", 0.003, 0.02, Vector3(0, 0.008, -0.047), Vector3(90, 0, 0), Color(0.55, 0.56, 0.58))
	_cylinder(paste.get_node("Mesh"), "Plunger", 0.005, 0.03, Vector3(0, 0.008, 0.06), Vector3(90, 0, 0), Color(0.3, 0.3, 0.32))

	var meter := _tool(rack, "Multimeter", "multimeter", Vector3(0.14, 0.012, 0), Vector3(0.08, 0.035, 0.14))
	_box(meter.get_node("Mesh"), "Body", Vector3(0.072, 0.028, 0.13), Vector3(0, 0.014, 0), Color(0.95, 0.75, 0.1))
	_box(meter.get_node("Mesh"), "Screen", Vector3(0.052, 0.002, 0.032), Vector3(0, 0.029, -0.035), Color(0.55, 0.62, 0.5))
	_cylinder(meter.get_node("Mesh"), "Dial", 0.016, 0.004, Vector3(0, 0.03, 0.02), Vector3.ZERO, Color(0.15, 0.15, 0.16))
	var display := _label(meter, "Display", "--.- V", Vector3(0, 0.031, -0.035), 40)
	display.rotation_degrees = Vector3(-90, 0, 0)
	display.modulate = Color(0.1, 0.12, 0.1)
	display.outline_size = 0
	display.pixel_size = 0.00025
	return ["res://scenes/tools/tool_rack.tscn", rack]


## Act 2, "Swap in an SSD" (step 4): a small PC case lies open side up on the
## right of the desk. Strap on, unscrew the side panel (4 screws) and put it
## down, unscrew the drive, take out the old SSD, fit the new one, screw it
## down, close the case. data/modules.json gives the order with `requires`.
func _swap_ssd() -> Array:
	var root := _mission("SwapSsd", "build_computer.swap_ssd", 34)
	var rack := ToolRack.instantiate()
	rack.position = Vector3(-0.33, TABLE_TOP, 0.2)
	root.add_child(rack)
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


## How tall the placeholder case's walls are, and its front lip (meters).
const WALL := 0.12
const LIP := 0.04


# ---------------------------------------------------------------- pieces

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
	# Every other label a little higher, so neighbours on the rack don't overlap.
	tag.position = Vector3(0, size.y + (0.02 if parent.get_child_count() % 2 else 0.05), 0)
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
