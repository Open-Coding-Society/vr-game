extends "res://scripts/ui/info_panel.gd"
## The picture on a monitor: an InfoPanel the size of the screen, laid over
## it. The screen is off (hidden) until something turns it on.
##
## A mission with "on_complete": "boot" in data/modules.json calls play_boot()
## when its last slot is filled. The mission's "boot_lines" then come up one
## after another, as on a PC that has just been switched on, and the last of
## them is what the screen is left showing: the desktop.
##
## A screen can also start on (start_title, start_lines) and change when a
## status light comes on (link_light), e.g. "Connected" once the network link
## is up. That needs no mission code: the light listens to its slots.

## The boot lines have all been shown.
signal boot_finished

const BOOT_COLOR := Color(0.02, 0.02, 0.03)
const DESKTOP_COLOR := Color(0.09, 0.3, 0.52)

## Seconds each boot line stays up before the next one. Tests set 0.
@export var line_seconds := 0.9
## What the screen shows from the start, for a PC that's already on. Leave
## both empty for a screen that starts off.
@export var start_title := ""
@export var start_lines: PackedStringArray = []
## A status light (scripts/parts/link_light.gd) to watch. When it comes on,
## the screen shows linked_title and linked_lines.
@export var link_light: NodePath
@export var linked_title := ""
@export var linked_lines: PackedStringArray = []

var is_on := false
var is_booting := false


func _ready() -> void:
	super._ready()
	# A screen, not a floating panel: square corners, no border.
	_style.set_border_width_all(0)
	_style.set_corner_radius_all(0)
	if start_title != "" or not start_lines.is_empty():
		show_desktop(start_title, start_lines)
	else:
		visible = false
	var light := get_node_or_null(link_light)
	if light and light.has_signal("lit"):
		light.lit.connect(func() -> void: show_desktop(linked_title, linked_lines))


## Turns the screen on with the desktop's colour and this text.
func show_desktop(new_title: String, new_lines: PackedStringArray) -> void:
	is_on = true
	visible = true
	_style.bg_color = DESKTOP_COLOR
	show_text(new_title, new_lines)


## Shows plain lines on a dark screen, as a PC does when it can't start:
## e.g. why the build won't boot.
func show_message(message_lines: PackedStringArray) -> void:
	is_on = true
	visible = true
	_style.bg_color = BOOT_COLOR
	show_text("", message_lines)


## Plays a start-up: every line but the last comes up in turn on a dark
## screen, then the last line is shown as the desktop.
func play_boot(boot_lines: PackedStringArray) -> void:
	is_on = true
	is_booting = true
	visible = true
	_style.bg_color = BOOT_COLOR
	var shown := PackedStringArray()
	for i in boot_lines.size() - 1:
		shown.append(boot_lines[i])
		show_text("", shown)
		if line_seconds > 0.0:
			await get_tree().create_timer(line_seconds).timeout
			if not is_inside_tree():
				return
	if not boot_lines.is_empty():
		show_desktop(boot_lines[boot_lines.size() - 1], PackedStringArray())
	is_booting = false
	boot_finished.emit()
