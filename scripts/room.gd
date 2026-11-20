extends Node3D
## The room every mission happens in: light, floor, the work table, the
## standing camera and the grab layer. Missions instance this scene and put
## their own parts and slots on the table.
##
## Two ways in, picked once at start: in a Quest headset (OpenXR is running)
## the player stands at the XROrigin3D and grabs with the controllers
## (VRGrabber); on a laptop the fixed Camera3D and the mouse (MouseGrabber) are
## used. Either way `grabber` has the same signals, so missions don't care.

const MouseGrabber := preload("res://scripts/input/mouse_grabber.gd")
const VRGrabber := preload("res://scripts/input/vr_grabber.gd")

## Standing eye height for the laptop camera (meters). VR rule 2; replace with
## the comfortable height measured in step 0.
const EYE_HEIGHT := 1.6
## Height of the table top (meters). The table mesh is 0.05 m thick at 0.875.
const TABLE_TOP := 0.9

## Where the camera looks: the middle of the work area on the table.
@export var focus := Vector3(0, TABLE_TOP, -0.1)

@onready var camera: Camera3D = $Camera3D
@onready var mouse_grabber: MouseGrabber = $MouseGrabber
@onready var vr_grabber: VRGrabber = $VRGrabber
@onready var xr_origin: XROrigin3D = $XROrigin3D

## The grab layer in use: vr_grabber in the headset, mouse_grabber on a laptop.
## Missions connect to its part_grabbed signal.
var grabber: Node
## True when the game is running in a headset.
var in_vr := false


func _ready() -> void:
	# Placed and aimed once, then never moved by the game (VR rule 6).
	camera.position.y = EYE_HEIGHT
	camera.look_at(focus)
	mouse_grabber.camera = camera
	var xr := XRServer.find_interface("OpenXR")
	in_vr = xr != null and xr.is_initialized()
	if in_vr:
		# The headset sets the frame rate, so the window's vsync must not hold it back.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		$XROrigin3D/XRCamera3D.make_current()
		mouse_grabber.set_process_unhandled_input(false)
		grabber = vr_grabber
	else:
		camera.make_current()
		xr_origin.visible = false
		vr_grabber.set_physics_process(false)
		grabber = mouse_grabber
