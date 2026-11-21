extends Node3D
## A flat screen in the room that shows normal Godot UI (buttons, lists, text).
##
## VR rule 4: screen UI doesn't show in the headset, so the UI is drawn in a
## SubViewport and shown on a quad. A pointer (menu_pointer.gd) aims at the
## quad, and this turns where it hits into mouse events for the UI, so normal
## Buttons and ScrollContainers just work, with the mouse or a controller.

## Screen size in the room (meters).
@export var size := Vector2(1.6, 1.0)
## Pixels per meter for the UI; 1000 means a 1.6 m screen is 1600 px wide.
@export var pixels_per_meter := 1000

var viewport: SubViewport
## Put the menu's controls under this; it fills the screen.
var ui_root: Control
## The body pointers hit (it carries a "menu_screen" meta pointing back here).
var body: StaticBody3D

var _last_pixel := Vector2.ZERO


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.size = Vector2i(size * pixels_per_meter)
	viewport.transparent_bg = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	ui_root = Control.new()
	ui_root.name = "UI"
	ui_root.size = Vector2(viewport.size)
	viewport.add_child(ui_root)

	var quad := QuadMesh.new()
	quad.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = viewport.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mesh := MeshInstance3D.new()
	mesh.name = "Screen"
	mesh.mesh = quad
	mesh.material_override = material
	add_child(mesh)

	body = StaticBody3D.new()
	body.name = "Body"
	body.set_meta("menu_screen", self)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.01)
	shape.shape = box
	body.add_child(shape)
	add_child(body)


## The UI pixel under a point on the screen (world space), or (-1, -1) when the
## point is off the screen.
func world_to_pixel(world_point: Vector3) -> Vector2:
	var local := to_local(world_point)
	var uv := Vector2(local.x / size.x + 0.5, 0.5 - local.y / size.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv * Vector2(viewport.size)


## The pointer moved over the screen.
func pointer_move(pixel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pixel
	e.global_position = pixel
	e.relative = pixel - _last_pixel
	_last_pixel = pixel
	viewport.push_input(e, true)


## The pointer's button went down or up over the screen (a click is both).
func pointer_button(pixel: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.position = pixel
	e.global_position = pixel
	e.button_index = button
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	viewport.push_input(e, true)


## Scrolls whatever is under the pointer: positive `steps` scrolls down.
func pointer_scroll(pixel: Vector2, steps: int) -> void:
	var button := MOUSE_BUTTON_WHEEL_DOWN if steps > 0 else MOUSE_BUTTON_WHEEL_UP
	for i in absi(steps):
		pointer_button(pixel, true, button)
		pointer_button(pixel, false, button)


## The pointer left the screen.
func pointer_exit() -> void:
	pointer_move(Vector2(-100, -100))
