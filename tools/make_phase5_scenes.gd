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

## Every scene this makes, by name.
var SCENES := {
	"tool_rack": _tool_rack,
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


# ---------------------------------------------------------------- pieces

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
	tag.text = Tool.TYPES[tool_type].left(1).to_upper() + Tool.TYPES[tool_type].substr(1)
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
