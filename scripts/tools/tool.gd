extends "res://scripts/grabbable_part.gd"
## A tool: a part the player picks up to *do* something, not to install
## (design plan §5, "tools, not just hands"). One of each tool, one size.
##
## Its part type is its `tool_type`, so a slot that needs it accepts that type.
## Usually the slot is a tool step (SnapZone `required_tool`, from the
## registry's "tool" field): drop the screwdriver on a screw and the step is
## done, while the screwdriver floats back to its place on the tool rack
## (scenes/tools/tool_rack.tscn). The wrist strap is the exception: it's worn,
## so it stays on the wrist zone it's dropped on.
##
## A tool describes itself (its type and name are here, not in the registry),
## so a mission scene can have the whole rack without listing every tool.

## Every kind of tool, and the name the player reads.
const TYPES := {
	"screwdriver": "screwdriver",
	"wrist_strap": "anti-static wrist strap",
	"thermal_paste": "thermal paste",
	"multimeter": "multimeter",
	"cloth": "cleaning cloth",
}

## Which tool this is: one of TYPES.
@export_enum("screwdriver", "wrist_strap", "thermal_paste", "multimeter", "cloth") var tool_type: String = "screwdriver"
## How long a dropped tool waits before it floats back (seconds), and how long
## the float takes. Tests set both to 0, so it's back at once.
@export var return_delay_s := 0.5
@export var return_time_s := 0.35

var _tween: Tween


func _ready() -> void:
	super._ready()
	part_type = StringName(tool_type)
	display_name = TYPES.get(tool_type, tool_type)
	var tag := get_node_or_null("Name") as Label3D
	if tag:
		tag.text = display_name.left(1).to_upper() + display_name.substr(1)


func grab() -> bool:
	if _tween:
		_tween.kill()
		_tween = null
	return super.grab()


## A dropped tool goes back to its place on the rack: after a short wait, it
## floats there, so the player sees where it lives.
func return_home() -> void:
	if _tween:
		_tween.kill()
		_tween = null
	if not is_inside_tree() or (return_delay_s <= 0.0 and return_time_s <= 0.0):
		super.return_home()
		return
	_tween = create_tween()
	_tween.tween_interval(return_delay_s)
	_tween.tween_property(self, "global_transform", home_transform, return_time_s) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## True once the tool is back in its place.
func is_home() -> bool:
	return global_transform.origin.is_equal_approx(home_transform.origin)


## Shows a reading on the tool's own small display (the multimeter's). Tools
## without a display ignore it.
func show_reading(text: String) -> void:
	var display := get_node_or_null("Display") as Label3D
	if display:
		display.text = text
