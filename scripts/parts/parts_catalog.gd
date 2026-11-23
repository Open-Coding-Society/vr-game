extends RefCounted
## Reads and checks data/parts_catalog.json: the versions of each PC part the
## player can pick from (three tiers of each), with the specs the
## compatibility rules use (scripts/parts/compatibility.gd).
##
## Like the module registry, bad data is reported with the field that's wrong,
## e.g. `cpu_mid.socket: must be text`.

const DEFAULT_PATH := "res://data/parts_catalog.json"
## The three tiers, lowest first, with the name and placeholder colour of each.
const TIERS := ["starter", "mid", "high"]
const TIER_NAMES := {"starter": "Starter", "mid": "Mid", "high": "High-end"}
const TIER_COLORS := {"starter": Color("9AA4B2"), "mid": Color("2F81F7"), "high": Color("3FB950")}
## What each type of part must say about itself, and the JSON type of each
## field (numbers are floats once parsed).
const FIELDS := {
	"cpu": {"socket": TYPE_STRING, "watts": TYPE_FLOAT},
	"motherboard": {"socket": TYPE_STRING, "ram": TYPE_STRING, "m2": TYPE_BOOL},
	"ram": {"ram": TYPE_STRING},
	"gpu": {"watts": TYPE_FLOAT, "plug": TYPE_STRING},
	"storage": {"bus": TYPE_STRING},
	"psu": {"watts": TYPE_FLOAT, "plugs": TYPE_ARRAY},
}
const FIELD_KINDS := {TYPE_STRING: "text", TYPE_FLOAT: "a number", TYPE_BOOL: "true or false", TYPE_ARRAY: "a list"}

## Every part by its id ("cpu_mid"), each a Dictionary of its specs plus "id".
var parts: Dictionary = {}
## What's wrong with the file. Empty means it loaded cleanly.
var errors: PackedStringArray = []

static var _shared


## The game's catalog, read once.
static func shared():
	if _shared == null:
		_shared = load_from()
		for problem in _shared.errors:
			push_error("parts_catalog.json: " + problem)
	return _shared


static func load_from(path := DEFAULT_PATH):
	var catalog = new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		catalog.errors.append("%s: missing, empty or not a JSON object" % path)
		return catalog
	catalog.read(data)
	return catalog


## Fills `parts` from parsed JSON, collecting every problem.
func read(data: Dictionary) -> void:
	var list = data.get("parts")
	if typeof(list) != TYPE_DICTIONARY or list.is_empty():
		errors.append("parts: must map part ids to their specs")
		return
	for id in list:
		_read_part(id, list[id])


## A part's specs, or {} when the catalog has no such part.
func spec(id: String) -> Dictionary:
	return parts.get(id, {})


## The ids of every part of a type ("cpu", "psu"...), in file order.
func of_type(type: String) -> Array:
	return parts.keys().filter(func(id) -> bool: return parts[id].type == type)


func _read_part(id: String, part) -> void:
	if typeof(part) != TYPE_DICTIONARY:
		errors.append("%s: must be an object" % id)
		return
	var before := errors.size()
	if not FIELDS.has(part.get("type")):
		errors.append("%s.type: must be one of %s" % [id, ", ".join(FIELDS.keys())])
	if not part.get("tier") in TIERS:
		errors.append("%s.tier: must be one of %s" % [id, ", ".join(TIERS)])
	if typeof(part.get("name")) != TYPE_STRING or part.name == "":
		errors.append("%s.name: must be text" % id)
	var fields: Dictionary = FIELDS.get(part.get("type"), {})
	for field in fields:
		if typeof(part.get(field)) != fields[field]:
			errors.append("%s.%s: must be %s" % [id, field, FIELD_KINDS[fields[field]]])
	if errors.size() > before:
		return
	var copy: Dictionary = part.duplicate(true)
	copy.id = id
	parts[id] = copy
