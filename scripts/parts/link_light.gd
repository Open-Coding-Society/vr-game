extends MeshInstance3D
## A small status light, like the one beside a network port: dark until every
## slot it watches is filled, then lit. It listens to the slots' `snapped`
## and `removed` signals, so a mission needs no code for it: pull a cable out
## of a removable port and the light goes dark again.
##
## A network mission can also mark the link as cut (set_cut), which shows it
## red until the link is restored. A light on a network device's port has no
## zones to watch (the far end can be any port): the mission turns it on and
## off with set_lit.

## The light has just come on.
signal lit
## The light has just gone dark (a cable came out).
signal went_out

## The SnapZones that must all be filled, e.g. both ends of a network cable.
@export var zones: Array[NodePath] = []
@export var off_color := Color(0.16, 0.18, 0.16)
@export var on_color := Color(0.25, 0.73, 0.31)
## The colour of a link that is cut (Phase 3 plan: #F85149).
@export var cut_color := Color(0.97, 0.32, 0.29)

var is_lit := false
var is_cut := false

var _material := StandardMaterial3D.new()


func _ready() -> void:
	material_override = _material
	_show()
	for path in zones:
		var zone := get_node_or_null(path)
		if zone and zone.has_signal("snapped"):
			zone.snapped.connect(_on_snapped)
		if zone and zone.has_signal("removed"):
			zone.removed.connect(_on_removed)


func _on_snapped(_zone, _part) -> void:
	if is_lit:
		return
	for path in zones:
		var zone := get_node_or_null(path)
		if zone == null or not zone.is_filled():
			return
	is_lit = true
	_show()
	lit.emit()


func _on_removed(_zone, _part) -> void:
	if not is_lit:
		return
	is_lit = false
	_show()
	went_out.emit()


## Turns the light on or off by hand, for a light that watches no zones.
func set_lit(on: bool) -> void:
	if on == is_lit:
		return
	is_lit = on
	_show()
	if on:
		lit.emit()
	else:
		went_out.emit()


## Shows the link as cut (red) or not. Lit or dark is still kept underneath.
func set_cut(cut: bool) -> void:
	is_cut = cut
	_show()


## The colour showing now: red when cut, green when lit, else dark.
func shown_color() -> Color:
	if is_cut:
		return cut_color
	return on_color if is_lit else off_color


func _show() -> void:
	_material.albedo_color = shown_color()
	_material.emission_enabled = is_lit or is_cut
	_material.emission = shown_color()
	_material.emission_energy_multiplier = 1.5
