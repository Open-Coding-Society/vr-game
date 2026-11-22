extends Node3D
## The menus' one pointer (VR rule 5): the mouse on a laptop, a ray from the
## right controller in the headset. It aims at MenuScreen3D quads and passes
## moves, clicks and scrolls to their UI. Nothing else knows which is in use.
##
## Headset: point with the right controller, pull the trigger to click, push
## the thumbstick up or down to scroll. A thin blue ray shows where it points.

## The camera the mouse looks through (laptop).
@export var camera: Camera3D
## The controller that points (headset). Left empty on a laptop.
@export var hand: XRController3D
## How far the pointer reaches (meters).
@export var reach := 6.0
## Controller actions that click.
@export var click_actions: PackedStringArray = ["trigger_click", "select_button"]

var in_vr := false
var _screen = null
var _pixel := Vector2(-1, -1)
var _ray: MeshInstance3D
var _scroll_cooldown := 0.0


func _ready() -> void:
	_ray = MeshInstance3D.new()
	_ray.name = "Ray"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.002
	mesh.bottom_radius = 0.002
	mesh.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Dark, so the thin ray shows against the light room and screen
	mat.albedo_color = Color("#26231F")
	mesh.material = mat
	_ray.mesh = mesh
	_ray.visible = false
	add_child(_ray)


## Switches to the controller (headset) or the mouse (laptop).
func use_vr(on: bool) -> void:
	in_vr = on and hand != null
	_ray.visible = in_vr
	if in_vr and not hand.button_pressed.is_connected(_on_hand_pressed):
		hand.button_pressed.connect(_on_hand_pressed)
		hand.button_released.connect(_on_hand_released)


func _physics_process(delta: float) -> void:
	if not in_vr:
		return
	var from := hand.global_position
	var forward := -hand.global_transform.basis.z
	var hit := _cast(from, forward)
	var length := reach
	if hit:
		length = from.distance_to(hit.position)
	_ray.global_transform = _ray_transform(from, forward, length)
	_aim(hit)
	_scroll_cooldown = maxf(0.0, _scroll_cooldown - delta)
	var stick := hand.get_vector2("primary")
	if absf(stick.y) > 0.6 and _scroll_cooldown == 0.0 and _screen:
		_screen.pointer_scroll(_pixel, -1 if stick.y > 0 else 1)
		_scroll_cooldown = 0.12


func _unhandled_input(event: InputEvent) -> void:
	if in_vr or camera == null:
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var from := camera.project_ray_origin(event.position)
		_aim(_cast(from, camera.project_ray_normal(event.position)))
		if event is InputEventMouseButton and _screen:
			_screen.pointer_button(_pixel, event.pressed, event.button_index)


## Points at whatever `hit` is: tells the screen under it, and the one it left.
func _aim(hit: Dictionary) -> void:
	var screen = hit.collider.get_meta("menu_screen") if hit and hit.collider.has_meta("menu_screen") else null
	if screen != _screen and _screen:
		_screen.pointer_exit()
	_screen = screen
	if _screen:
		_pixel = _screen.world_to_pixel(hit.position)
		_screen.pointer_move(_pixel)


## The ray mesh is a 1 m cylinder along its y axis: stretch y to `length` along
## `forward`, starting at `from`.
static func _ray_transform(from: Vector3, forward: Vector3, length: float) -> Transform3D:
	var y := forward.normalized()
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x, y * length, z), from + y * length / 2.0)


func _cast(from: Vector3, direction: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * reach)
	return get_world_3d().direct_space_state.intersect_ray(query)


func _on_hand_pressed(action: String) -> void:
	if action in click_actions and _screen:
		_screen.pointer_button(_pixel, true)


func _on_hand_released(action: String) -> void:
	if action in click_actions and _screen:
		_screen.pointer_button(_pixel, false)


## Clicks a point on a screen, as the pointer would (tests and scripted demos).
func click_world(point: Vector3) -> bool:
	_aim(_cast(point + Vector3(0, 0, 0.5), Vector3(0, 0, -1)))
	if _screen == null:
		return false
	_screen.pointer_button(_pixel, true)
	_screen.pointer_button(_pixel, false)
	return true
