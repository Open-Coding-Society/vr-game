extends Node3D
## Open World v1 (design plan §4, Phase 5 step 8): your own desk in the cube
## room, the tool rack, and a spawn panel with every part in
## data/parts_catalog.json and every network device. Spawn anything, put it
## anywhere on the desk. No scoring, just building.
##
## The layout is saved through SaveService when you leave ("Back to menu"),
## as the design plan's save shape: a list of {item, transform}, where item is
## a catalog id ("cpu_mid") or a device id ("net_switch"). Coming back loads
## it again, so the desk is as you left it.
##
## Not in v1: "Transfer to Cloud" (the Cloud chapter isn't built yet).

const GrabbablePart := preload("res://scripts/grabbable_part.gd")
const PartsCatalog := preload("res://scripts/parts/parts_catalog.gd")
const MenuTheme := preload("res://scripts/ui/menu_theme.gd")

## Where "Back to menu" goes when Open World wasn't opened from the menu.
const MENU_SCENE := "res://scenes/menus/menu.tscn"
## The desk's top, and how far from its middle a part can be put down
## (meters): parts stay on the desk.
const TABLE_TOP := 0.9
const DESK_HALF := Vector2(0.57, 0.32)
## Where a new part appears, and how far along the next one goes if that
## spot is taken.
const SPAWN_AT := Vector3(-0.05, TABLE_TOP, 0.05)
const SPAWN_STEP := 0.13

## The look of each kind of catalog part (the real models in models/).
const VISUALS := {
	"cpu": "res://models/cpu/cpu_visual.tscn",
	"motherboard": "res://models/board/board_visual.tscn",
	"ram": "res://models/ram/ram_visual.tscn",
	"gpu": "res://models/gpu/gpu_visual.tscn",
	"psu": "res://models/psu/psu_visual.tscn",
	"storage": "res://models/ssd_m2/ssd_m2_visual.tscn",
	"storage_sata": "res://models/ssd_sata/ssd_sata_visual.tscn",
}
## The network devices (Phase 3's scenes), by item id.
const DEVICES := {
	"net_pc": {"scene": "res://scenes/network/devices/pc.tscn", "name": "PC"},
	"net_mac_mini": {"scene": "res://scenes/network/devices/mac_mini.tscn", "name": "Mac mini"},
	"net_switch": {"scene": "res://scenes/network/devices/switch_gs108.tscn", "name": "Switch"},
	"net_router": {"scene": "res://scenes/network/devices/router_glinet.tscn", "name": "Router"},
	"net_server": {"scene": "res://scenes/network/devices/server.tscn", "name": "Server"},
	"net_wall_jack": {"scene": "res://scenes/network/devices/wall_jack.tscn", "name": "Internet wall jack"},
}
## Catalog part types in the spawn list's order, and what the list calls them.
const TYPE_NAMES := {
	"motherboard": "Motherboard", "cpu": "CPU", "ram": "RAM", "storage": "Storage", "gpu": "Graphics card", "psu": "Power supply",
}

@onready var room: Node3D = $Room
@onready var screen = $SpawnScreen
@onready var pointer = $MenuPointer
@onready var items_node: Node3D = $Items
@onready var manager: Node = get_node_or_null("/root/TrainingManager")
@onready var saves: Node = get_node_or_null("/root/SaveService")

var _catalog
var _count := 0
var _leaving := false


func _ready() -> void:
	_catalog = PartsCatalog.shared()
	pointer.camera = room.camera
	pointer.hand = room.get_node("XROrigin3D/RightHand")
	pointer.use_vr(room.in_vr)
	room.grabber.part_dropped.connect(_on_part_dropped)
	room.back_button.pressed.connect(leave)
	_build_panel()
	load_layout()


## Every item id that can be spawned: the catalog's parts, then the devices.
func item_ids() -> Array:
	var out := []
	for type in TYPE_NAMES:
		for id in _catalog.parts:
			if _catalog.parts[id].type == type:
				out.append(id)
	out.append_array(DEVICES.keys())
	return out


## The items on the desk now.
func items() -> Array:
	return items_node.get_children().filter(func(n) -> bool: return not n.is_queued_for_deletion())


## Puts a new item on the desk, at the spawn spot or the next free place along.
func spawn(item_id: String) -> GrabbablePart:
	var at := SPAWN_AT
	for i in 8:
		if items().all(func(n) -> bool: return Vector2(n.global_position.x - at.x, n.global_position.z - at.z).length() > SPAWN_STEP * 0.8):
			break
		at = SPAWN_AT + Vector3(SPAWN_STEP * ((i + 1) % 4), 0, -SPAWN_STEP * ((i + 1) / 4))
	return place(item_id, Transform3D(Basis(), at))


## Makes an item and puts it at `at`. Returns it, or null for an unknown id.
func place(item_id: String, at: Transform3D) -> GrabbablePart:
	var part := _make(item_id)
	if part == null:
		return null
	part.transform = at
	items_node.add_child(part)
	_fit_shape(part)
	return part


## Removes every item from the desk.
func clear_desk() -> void:
	for item in items():
		item.queue_free()


## The layout to save: one {item, transform} per item, the transform as 12
## numbers (basis x, y, z, then the origin), as in the design plan §6.
func layout() -> Array:
	var out := []
	for item in items():
		var t: Transform3D = item.global_transform
		out.append({"item": item.get_meta("item"), "transform": [
			t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
			t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]})
	return out


func save_layout() -> void:
	if saves:
		saves.save_world_layout(layout())


## Puts back what the saved layout has. Unknown items (a part since removed
## from the catalog) are skipped, so an old save still loads.
func load_layout() -> void:
	if saves == null:
		return
	for entry in saves.load_world_layout():
		var n = entry.get("transform", [])
		if typeof(n) != TYPE_ARRAY or n.size() != 12:
			continue
		var t := Transform3D(Vector3(n[0], n[1], n[2]), Vector3(n[3], n[4], n[5]), Vector3(n[6], n[7], n[8]), Vector3(n[9], n[10], n[11]))
		place(str(entry.get("item", "")), t)


## "Back to menu": save the desk, then go back where Open World was opened from.
func leave() -> void:
	if _leaving:
		return
	_leaving = true
	save_layout()
	var target := MENU_SCENE
	if manager and manager.return_scene != "":
		target = manager.return_scene
	if manager:
		manager.open_scene(target)
	else:
		get_tree().change_scene_to_file.call_deferred(target)


## A part was let go: it stays where it is, set down on the desk (and moved
## back onto it if it was dropped off the edge).
func _on_part_dropped(part) -> void:
	if not items_node.is_ancestor_of(part):
		return
	var t: Transform3D = part.global_transform
	t.origin = Vector3(clampf(t.origin.x, -DESK_HALF.x, DESK_HALF.x), TABLE_TOP, clampf(t.origin.z, -DESK_HALF.y, DESK_HALF.y))
	part.move_home(t)


func _make(item_id: String) -> GrabbablePart:
	var look: Node3D
	var type := ""
	var title := ""
	if DEVICES.has(item_id):
		look = load(DEVICES[item_id].scene).instantiate()
		_quiet(look)
		type = "device"
		title = DEVICES[item_id].name
	else:
		var spec: Dictionary = _catalog.spec(item_id)
		if spec.is_empty():
			return null
		var visual: String = VISUALS["storage_sata"] if spec.type == "storage" and "SATA" in spec.name else VISUALS.get(spec.type, "")
		if visual == "":
			return null
		look = load(visual).instantiate()
		type = spec.type
		title = spec.name
	_count += 1
	var part := RigidBody3D.new()
	part.set_script(GrabbablePart)
	part.name = "%s_%d" % [item_id, _count]
	part.part_type = StringName(type)
	part.display_name = title
	part.free_placement = true
	part.set_meta("item", item_id)
	var mesh := Node3D.new()
	mesh.name = "Mesh"
	mesh.add_child(look)
	part.add_child(mesh)
	var tag := Label3D.new()
	tag.name = "Name"
	tag.text = title
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.0003
	tag.font_size = 40
	tag.outline_size = 10
	tag.no_depth_test = true
	part.add_child(tag)
	return part


## A device here is only something to place: its own collisions and ports
## are switched off, so the part around it is what the hand grabs.
func _quiet(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is Area3D:
		node.monitoring = false
		node.monitorable = false
	for child in node.get_children():
		_quiet(child)


## Gives an item a grab box around its look, and puts its label above it.
func _fit_shape(part: Node3D) -> void:
	var box := AABB()
	var first := true
	var to_part: Transform3D = part.global_transform.affine_inverse()
	for node in part.get_node("Mesh").find_children("*", "VisualInstance3D", true, false):
		if node is Label3D or not node.is_visible_in_tree():
			continue
		var piece: AABB = (to_part * node.global_transform) * node.get_aabb()
		box = piece if first else box.merge(piece)
		first = false
	if first:
		box = AABB(Vector3(-0.05, 0, -0.05), Vector3(0.1, 0.05, 0.1))
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var bs := BoxShape3D.new()
	bs.size = box.size.max(Vector3(0.02, 0.01, 0.02))
	shape.shape = bs
	shape.position = box.get_center()
	part.add_child(shape)
	part.get_node("Name").position = Vector3(box.get_center().x, box.end.y + 0.03, box.get_center().z)


func _build_panel() -> void:
	var frame := MenuTheme.panel()
	frame.name = "Page_open_world"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	frame.add_child(column)
	var top := HBoxContainer.new()
	var title := MenuTheme.label("Open World", MenuTheme.SIZE_HEADING)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var clear := MenuTheme.secondary_button("Clear the desk")
	clear.name = "ClearDesk"
	clear.pressed.connect(clear_desk)
	top.add_child(clear)
	column.add_child(top)
	column.add_child(MenuTheme.label("Spawn any part, then drag it anywhere on the desk. Your desk is saved when you leave.",
		MenuTheme.SIZE_SMALL, MenuTheme.MUTED))
	var scroll := MenuTheme.scroll()
	scroll.name = "SpawnList"
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for id in item_ids():
		var text: String
		if DEVICES.has(id):
			text = "Network: " + DEVICES[id].name
		else:
			var spec: Dictionary = _catalog.spec(id)
			text = "%s: %s" % [TYPE_NAMES[spec.type], spec.name]
		var b := MenuTheme.secondary_button(text)
		b.name = "Spawn_" + id
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.add_theme_font_size_override("font_size", MenuTheme.SIZE_SMALL)
		b.pressed.connect(spawn.bind(id))
		grid.add_child(b)
	scroll.add_child(grid)
	column.add_child(scroll)
	screen.ui_root.add_child(frame)


## The spawn panel's button named `button_name`, or null.
func find_button(button_name: String) -> Button:
	return screen.ui_root.find_child(button_name, true, false) as Button
