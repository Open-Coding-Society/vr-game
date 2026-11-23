extends Node
## The headset's grab/drop layer: hold the grip (or trigger) with a controller
## near a part to pick it up, move your hand to carry it, let go to drop it.
##
## VR rule 5: this is the VR twin of mouse_grabber.gd. It has the same signals
## and the same `held` field, and only calls grab() and drop() on parts, so
## missions and SnapZones work the same with either grabber (room.gd picks one).

const GrabbablePart := preload("res://scripts/grabbable_part.gd")

## Emitted when a part is picked up or let go, for hints and sounds.
signal part_grabbed(part)
signal part_dropped(part)

## The two controllers (set by room.gd).
@export var left_hand: XRController3D
@export var right_hand: XRController3D
## How close (meters) a controller must be to a part to grab it: to its
## origin, or to its GrabPoint if it has one (see GrabbablePart.grab_position).
## Small parts like a CPU are a few centimeters, so this is generous on purpose.
@export var grab_radius: float = 0.12
## Controller actions that count as "grab", from openxr_action_map.tres.
@export var grab_actions: PackedStringArray = ["grip_click", "trigger_click"]

## The part being carried, and the hand carrying it (one part at a time, like
## the mouse grabber).
var held: GrabbablePart = null
var _holding_hand: XRController3D = null
## The part's offset from the hand when it was picked up, so it doesn't jump.
var _offset := Vector3.ZERO


func _ready() -> void:
	for hand in [left_hand, right_hand]:
		if hand:
			hand.button_pressed.connect(_on_pressed.bind(hand))
			hand.button_released.connect(_on_released.bind(hand))


func _physics_process(_delta: float) -> void:
	if held and _holding_hand:
		held.global_position = _holding_hand.global_position + _offset


func _on_pressed(action: String, hand: XRController3D) -> void:
	if action in grab_actions:
		try_grab_with(hand)


func _on_released(action: String, hand: XRController3D) -> void:
	if action in grab_actions and hand == _holding_hand:
		release()


## Picks up the part nearest the hand, if one is within grab_radius. Returns it, or null.
func try_grab_with(hand: XRController3D) -> GrabbablePart:
	if held or hand == null:
		return null
	var part := part_near(hand.global_position)
	if part and part.grab():
		held = part
		_holding_hand = hand
		_offset = part.global_position - hand.global_position
		part_grabbed.emit(part)
		return part
	return null


## The nearest grabbable part within grab_radius of a point, or null.
func part_near(point: Vector3) -> GrabbablePart:
	var best: GrabbablePart = null
	var best_distance := grab_radius
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for node in scene.find_children("*", "RigidBody3D", true, false):
		var part := node as GrabbablePart
		if part == null or not part.can_grab():
			continue
		var distance := part.grab_position().distance_to(point)
		if distance <= best_distance:
			best = part
			best_distance = distance
	return best


func release() -> void:
	if held == null:
		return
	var part := held
	held = null
	_holding_hand = null
	part.drop()
	part_dropped.emit(part)
