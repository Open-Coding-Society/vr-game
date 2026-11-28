extends Node
## The laptop's grab/drop layer: press on a part to pick it up, move the mouse
## to carry it above the table, release to drop it.
##
## VR rule 5: this is the only script that knows about the mouse. Parts and
## SnapZones only see grab() and drop(), so a controller or hand grabber can
## replace this node later without touching the game.

const GrabbablePart := preload("res://scripts/grabbable_part.gd")

## Emitted when a part is picked up or let go, for hints and sounds.
signal part_grabbed(part)
signal part_dropped(part)

## The camera the mouse looks through.
@export var camera: Camera3D
## Height (meters) a held part is carried at: a little above the table top so
## it clears the other parts.
@export var carry_height: float = 0.95
## How far the mouse ray reaches (meters).
@export var reach: float = 5.0

var held: GrabbablePart = null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			try_grab_at(event.position)
		else:
			release()
	elif event is InputEventMouseMotion and held:
		carry_to(event.position)


## Picks up the part under a screen position, if there is one. Returns it, or null.
func try_grab_at(screen_pos: Vector2) -> GrabbablePart:
	if held or camera == null:
		return null
	var part := part_at(screen_pos)
	if part and part.grab():
		held = part
		part_grabbed.emit(part)
		carry_to(screen_pos)
		return part
	return null


## Moves the held part to where the mouse ray meets the carry plane.
func carry_to(screen_pos: Vector2) -> void:
	if held == null or camera == null:
		return
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var hit = Plane(Vector3.UP, carry_height).intersects_ray(origin, direction)
	if hit != null:
		held.global_position = hit


## Lets go of the held part without dropping it anywhere: it goes straight
## back home. Missions use it for a part that can't be touched yet.
func cancel() -> void:
	if held == null:
		return
	var part := held
	held = null
	part.cancel_grab()


func release() -> void:
	if held == null:
		return
	var part := held
	held = null
	part.drop()
	part_dropped.emit(part)


## The grabbable part under a screen position, or null.
func part_at(screen_pos: Vector2) -> GrabbablePart:
	var origin := camera.project_ray_origin(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen_pos) * reach)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	var part := (hit.collider as GrabbablePart) if hit else null
	return part if part and part.can_grab() else null
