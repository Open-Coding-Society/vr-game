extends Node3D
## The "Back to menu" button every mission has (room.tscn places it beside the
## info panel, off the desk, so it never sits on a mission's parts). It's a
## small 3D plate with its label, turned to face the player.
##
## Three ways to press it, so the laptop and the headset both work (VR rule 5):
## - laptop: click it with the mouse, or press Esc
## - headset: press B or Y (or the menu button) on either controller, or pull
##   the trigger with a controller touching the plate
##
## It only emits `pressed`; the mission decides what leaving means
## (scripts/missions/mission.gd, leave_early()).

signal pressed

## The plate's size in the room (meters).
const SIZE := Vector2(0.17, 0.055)
## How close (meters) a controller must be to the plate for the trigger to press it.
const POKE_REACH := 0.1
## Controller actions that press it from anywhere, and the ones that press it
## only while touching it.
const MENU_ACTIONS: PackedStringArray = ["by_button", "menu_button"]
const POKE_ACTIONS: PackedStringArray = ["trigger_click"]

## The camera the mouse looks through (set by room.gd).
var camera: Camera3D
## The controllers (set by room.gd in the headset; empty on a laptop).
var hands: Array = []

var _body: StaticBody3D


func _ready() -> void:
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	box.size = Vector3(SIZE.x, SIZE.y, 0.008)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.97, 0.95, 0.9)
	mat.roughness = 0.7
	box.material = mat
	plate.mesh = box
	add_child(plate)

	var label := Label3D.new()
	label.name = "Label"
	label.text = "Back to menu"
	label.font_size = 40
	label.pixel_size = 0.0007
	label.modulate = Color(0.15, 0.13, 0.11)
	label.outline_size = 0
	label.position = Vector3(0, 0, 0.0045)
	add_child(label)

	_body = StaticBody3D.new()
	_body.name = "Body"
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(SIZE.x, SIZE.y, 0.02)
	shape.shape = box_shape
	_body.add_child(shape)
	add_child(_body)


## Called by room.gd once it knows which camera and controllers are in use.
func setup(new_camera: Camera3D, new_hands: Array) -> void:
	camera = new_camera
	hands = new_hands
	for hand in hands:
		if hand and not hand.button_pressed.is_connected(_on_hand_pressed):
			hand.button_pressed.connect(_on_hand_pressed.bind(hand))


## Turns the plate to face a point (the player's eyes), so its label reads
## straight on wherever a mission puts it.
func face(point: Vector3) -> void:
	if point.distance_to(global_position) > 0.01:
		look_at(point, Vector3.UP, true)


func press() -> void:
	pressed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		press()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_under(event.position):
			get_viewport().set_input_as_handled()
			press()


## True when a screen position (laptop) points at the plate.
func is_under(screen_pos: Vector2) -> bool:
	if camera == null or not is_inside_tree():
		return false
	var origin := camera.project_ray_origin(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen_pos) * 5.0)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == _body


func _on_hand_pressed(action: String, hand: XRController3D) -> void:
	if action in MENU_ACTIONS:
		press()
	elif action in POKE_ACTIONS and hand.global_position.distance_to(global_position) <= POKE_REACH:
		press()
