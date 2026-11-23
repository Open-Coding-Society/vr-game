extends MeshInstance3D
## A small status light, like the one beside a network port: dark until every
## slot it watches is filled, then lit. It listens to the slots' `snapped`
## signal, so a mission needs no code for it.

## The light has just come on.
signal lit

## The SnapZones that must all be filled, e.g. both ends of a network cable.
@export var zones: Array[NodePath] = []
@export var off_color := Color(0.16, 0.18, 0.16)
@export var on_color := Color(0.25, 0.73, 0.31)

var is_lit := false

var _material := StandardMaterial3D.new()


func _ready() -> void:
	material_override = _material
	_show()
	for path in zones:
		var zone := get_node_or_null(path)
		if zone and zone.has_signal("snapped"):
			zone.snapped.connect(_on_snapped)


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


func _show() -> void:
	_material.albedo_color = on_color if is_lit else off_color
	_material.emission_enabled = is_lit
	_material.emission = on_color
	_material.emission_energy_multiplier = 1.5
