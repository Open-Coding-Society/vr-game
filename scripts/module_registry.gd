extends RefCounted
## Reads and checks data/modules.json, the module registry: every module, its
## missions, and each mission's parts, slots, text and scoring.
##
## "Data, not code": a new mission is a scene (where things are) plus an entry
## here (what they are, what the student reads, how it's scored). Same idea as
## the backend's model/dataconfigs/.
##
## Bad data is reported with the field that's wrong, e.g.
## `build_computer.install_ram: slot "Motherboard/RamSlot" accepts "rom", but no
## part has that type`, so a typo shows up when the game starts, not mid-mission.

const Compatibility := preload("res://scripts/parts/compatibility.gd")
const PartsCatalog := preload("res://scripts/parts/parts_catalog.gd")

const DEFAULT_PATH := "res://data/modules.json"
## Free Play's two lists. A module says which one its missions go in.
const CATEGORIES := ["computer", "cloud"]
## What a mission can ask for once its last slot is filled, before the success
## panel: "boot" plays its boot_lines on the scene's monitor.
const ON_COMPLETE := ["boot"]
## What a network mission's "goal" can ask for (scripts/missions/
## network_mission.gd has one small check for each). A mission with a goal
## finishes when the goal is met, not when its slots are full.
const GOAL_KINDS := ["connected", "reach", "delivered", "cut_then_restore", "survives_any_single_cut", "jobs_done"]

## Every mission by its full id ("module.mission"), each a Dictionary with the
## mission's fields plus "full_id" and "module_title".
var missions: Dictionary = {}
## The modules in file order: [{id, title, category, mission_ids}].
var modules: Array = []
## What's wrong with the file. Empty means it loaded cleanly.
var errors: PackedStringArray = []


static func load_from(path := DEFAULT_PATH):
	var registry = new()
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		registry.errors.append("%s: missing or empty" % path)
		return registry
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		registry.errors.append("%s: not a JSON object" % path)
		return registry
	registry.read(data)
	return registry


## Fills `missions` and `modules` from parsed JSON, collecting every problem.
func read(data: Dictionary) -> void:
	var module_list = data.get("modules")
	if typeof(module_list) != TYPE_ARRAY or module_list.is_empty():
		errors.append("modules: must be a non-empty list")
		return
	for module in module_list:
		_read_module(module)


func mission(full_id: String) -> Dictionary:
	return missions.get(full_id, {})


## Every mission in a Free Play category ("computer" or "cloud"), in file order.
func missions_in(category: String) -> Array:
	var out := []
	for module in modules:
		if module.category == category:
			for id in module.mission_ids:
				out.append(missions[id])
	return out


func _read_module(module) -> void:
	if typeof(module) != TYPE_DICTIONARY or not _is_id(module.get("id")):
		errors.append("modules: each module needs an id in lower_snake_case")
		return
	var module_id: String = module.id
	if modules.any(func(m) -> bool: return m.id == module_id):
		errors.append("%s: module id used twice" % module_id)
		return
	var category = module.get("category", "computer")
	if not category in CATEGORIES:
		errors.append("%s.category: must be one of %s" % [module_id, ", ".join(CATEGORIES)])
		category = "computer"
	var entry := {"id": module_id, "title": str(module.get("title", module_id)), "category": category, "mission_ids": []}
	modules.append(entry)
	var mission_list = module.get("missions")
	if typeof(mission_list) != TYPE_ARRAY or mission_list.is_empty():
		errors.append("%s.missions: must be a non-empty list" % module_id)
		return
	for m in mission_list:
		var full_id := _read_mission(module_id, entry.title, m, category)
		if full_id != "":
			entry.mission_ids.append(full_id)


func _read_mission(module_id: String, module_title: String, m, category := "computer") -> String:
	if typeof(m) != TYPE_DICTIONARY or not _is_id(m.get("id")):
		errors.append("%s.missions: each mission needs an id in lower_snake_case" % module_id)
		return ""
	var full_id := "%s.%s" % [module_id, m.id]
	if missions.has(full_id):
		errors.append("%s: mission id used twice" % full_id)
		return ""
	var before := errors.size()
	for field in ["title", "scene"]:
		if typeof(m.get(field)) != TYPE_STRING or m[field] == "":
			errors.append("%s.%s: must be text" % [full_id, field])
	if typeof(m.get("scene")) == TYPE_STRING and not ResourceLoader.exists(m.scene):
		errors.append("%s.scene: %s doesn't exist" % [full_id, m.scene])
	# Free Play's card text: optional, but text when given.
	for field in ["description", "topic", "difficulty"]:
		if m.has(field) and (typeof(m[field]) != TYPE_STRING or m[field] == ""):
			errors.append("%s.%s: must be text" % [full_id, field])
	for field in ["intro", "success"]:
		if not _is_text_list(m.get(field)):
			errors.append("%s.%s: must be a non-empty list of text" % [full_id, field])
	var scoring = m.get("scoring")
	if typeof(scoring) != TYPE_DICTIONARY or not _is_whole(scoring.get("full"), 1, 1000) \
			or not _is_whole(scoring.get("per_mistake"), 0, 1000):
		errors.append("%s.scoring: needs whole numbers full (1-1000) and per_mistake (0-1000)" % full_id)
	# Optional: extra points for a balanced build (Build your own PC).
	elif scoring.has("balanced_bonus") and not _is_whole(scoring.balanced_bonus, 0, 1000):
		errors.append("%s.scoring.balanced_bonus: must be a whole number from 0 to 1000" % full_id)
	var types := _read_parts(full_id, m.get("parts"))
	# With catalog_parts, the scene also has parts that take their type from
	# data/parts_catalog.json (a `variant`), so slots can accept those types.
	if m.has("catalog_parts") and typeof(m.catalog_parts) != TYPE_BOOL:
		errors.append("%s.catalog_parts: must be true or false" % full_id)
	elif m.get("catalog_parts", false):
		var catalog = PartsCatalog.shared()
		types.append_array(catalog.parts.values().map(func(part) -> String: return part.type))
	_read_slots(full_id, m.get("slots"), types)
	_read_on_complete(full_id, m)
	_read_monitor(full_id, m)
	_read_goal(full_id, m)
	if errors.size() > before:
		return ""
	var copy: Dictionary = m.duplicate(true)
	copy.full_id = full_id
	copy.module_title = module_title
	copy.category = category
	copy.description = str(m.get("description", ""))
	copy.topic = str(m.get("topic", ""))
	copy.difficulty = str(m.get("difficulty", ""))
	copy.practice = bool(m.get("practice", false))
	copy.catalog_parts = bool(m.get("catalog_parts", false))
	copy.scoring = {"full": int(scoring.full), "per_mistake": int(scoring.per_mistake),
		"balanced_bonus": int(scoring.get("balanced_bonus", 0))}
	missions[full_id] = copy
	return full_id


## Optional mission fields: on_complete ("boot") and, with it, boot_lines (the
## lines the monitor shows; the last one is left on the screen).
func _read_on_complete(full_id: String, m: Dictionary) -> void:
	if not m.has("on_complete") and not m.has("boot_lines"):
		return
	if not m.get("on_complete") in ON_COMPLETE:
		errors.append("%s.on_complete: must be one of %s" % [full_id, ", ".join(ON_COMPLETE)])
	if not _is_text_list(m.get("boot_lines")):
		errors.append("%s.boot_lines: must be a non-empty list of text" % full_id)


## Optional mission field "goal": one of GOAL_KINDS and what it needs, e.g.
## {"connected": ["pc_a", "pc_b"]} or {"jobs_done": 12, "min_machines": 3}.
func _read_goal(full_id: String, m: Dictionary) -> void:
	if not m.has("goal"):
		return
	var goal = m.goal
	var kinds: Array = goal.keys().filter(func(k) -> bool: return k in GOAL_KINDS) if typeof(goal) == TYPE_DICTIONARY else []
	if kinds.size() != 1:
		errors.append("%s.goal: must be one of %s" % [full_id, ", ".join(GOAL_KINDS)])
		return
	var kind: String = kinds[0]
	var value = goal[kind]
	var ok := true
	match kind:
		"connected", "survives_any_single_cut":
			ok = _is_text_list(value) and value.size() >= 2
		"reach":
			ok = typeof(value) == TYPE_STRING and value != "" and _is_text_list(goal.get("from"))
		"delivered":
			ok = typeof(value) == TYPE_DICTIONARY and typeof(value.get("from")) == TYPE_STRING \
				and typeof(value.get("to")) == TYPE_STRING and _is_whole(value.get("packets"), 1, 20)
		"cut_then_restore":
			ok = _is_text_list(value) and value.size() == 2 and value.all(func(p) -> bool: return p.contains(":"))
		"jobs_done":
			ok = _is_whole(value, 1, 100) and _is_whole(goal.get("min_machines", 1), 1, 100)
	if not ok:
		errors.append("%s.goal.%s: %s" % [full_id, kind, GOAL_SHAPES[kind]])


## What each goal kind needs, for the error message when it's written wrong.
const GOAL_SHAPES := {
	"connected": "must list two or more device ids",
	"survives_any_single_cut": "must list two or more device ids",
	"reach": "must be a device id, with \"from\": a list of device ids",
	"delivered": "must be {from, to, packets (1-20)}",
	"cut_then_restore": "must be the two ports the cable joins, e.g. [\"switch:port3\", \"server:eth0\"]",
	"jobs_done": "must be a whole number, with \"min_machines\" a whole number too",
}


## Optional mission field "monitor": text for the scene's monitor screen.
## "start" is shown from the beginning and "linked" once the screen's link
## light comes on; in each, the first line is the heading.
func _read_monitor(full_id: String, m: Dictionary) -> void:
	if not m.has("monitor"):
		return
	if typeof(m.monitor) != TYPE_DICTIONARY or m.monitor.is_empty():
		errors.append("%s.monitor: must have start or linked text" % full_id)
		return
	for key in m.monitor:
		if not key in ["start", "linked"]:
			errors.append("%s.monitor.%s: only start and linked are known" % [full_id, key])
		elif not _is_text_list(m.monitor[key]):
			errors.append("%s.monitor.%s: must be a non-empty list of text" % [full_id, key])


func _read_parts(full_id: String, parts) -> Array:
	var types := []
	if typeof(parts) != TYPE_DICTIONARY or parts.is_empty():
		errors.append("%s.parts: must map node paths to {type, name}" % full_id)
		return types
	for path in parts:
		var part = parts[path]
		if typeof(part) != TYPE_DICTIONARY or not _is_id(part.get("type")) or typeof(part.get("name")) != TYPE_STRING:
			errors.append('%s: part "%s" needs a type in lower_snake_case and a name' % [full_id, path])
		else:
			types.append(part.type)
			_read_message(full_id, path, part)
	return types


## A message card (Build a Network) says who it goes to, and optionally how
## many packets it's split into (1-20) and its text.
func _read_message(full_id: String, path: String, part: Dictionary) -> void:
	if not part.has("to") and not part.has("packets") and not part.has("text"):
		return
	if typeof(part.get("to")) != TYPE_STRING or part.to == "":
		errors.append('%s: part "%s" needs "to", the device the message goes to' % [full_id, path])
	if part.has("packets") and not _is_whole(part.packets, 1, 20):
		errors.append('%s: part "%s" packets must be a whole number from 1 to 20' % [full_id, path])
	if part.has("text") and typeof(part.text) != TYPE_STRING:
		errors.append('%s: part "%s" text must be text' % [full_id, path])


func _read_slots(full_id: String, slots, part_types: Array) -> void:
	if typeof(slots) != TYPE_DICTIONARY or slots.is_empty():
		errors.append("%s.slots: must map node paths to {accepts, name, hint}" % full_id)
		return
	var filled := {}
	for path in slots:
		var slot = slots[path]
		var is_working: bool = typeof(slot) == TYPE_DICTIONARY and typeof(slot.get("working")) == TYPE_BOOL and slot.working
		if typeof(slot) != TYPE_DICTIONARY or (not is_working and not _is_id(slot.get("accepts"))) \
				or typeof(slot.get("name")) != TYPE_STRING or typeof(slot.get("hint")) != TYPE_STRING:
			errors.append('%s: slot "%s" needs accepts, name and hint' % [full_id, path])
			continue
		if is_working:
			continue  # a part that isn't broken: it takes nothing, so no part needs to fit
		if not part_types.has(slot.accepts):
			errors.append('%s: slot "%s" accepts "%s", but no part has that type' % [full_id, path, slot.accepts])
		var capacity = slot.get("capacity", 1)
		if not _is_whole(capacity, 1, 20):
			errors.append('%s: slot "%s" capacity must be a whole number from 1 to 20' % [full_id, path])
			capacity = 1
		# An optional slot (any of a switch's ports) doesn't have to be filled.
		if not slot.get("pass_through", false) and not slot.get("optional", false):
			filled[slot.accepts] = filled.get(slot.accepts, 0) + int(capacity)
	_read_slot_options(full_id, slots)
	# Every slot needs its own part, or the mission could never finish. A
	# pass-through slot doesn't keep its part, so the part can fill several.
	for type in filled:
		if part_types.count(type) < filled[type]:
			errors.append('%s: slots need %d "%s" part(s) but only %d have that type' % [full_id, filled[type], type, part_types.count(type)])


## Optional slot fields: role (text), pass_through, working, swappable,
## removable and optional (true/false), compat (a rule in scripts/parts/compatibility.gd) and requires
## (other slots of this mission that must be filled first, with no loops).
func _read_slot_options(full_id: String, slots: Dictionary) -> void:
	for path in slots:
		var slot = slots[path]
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		if slot.has("role") and typeof(slot.role) != TYPE_STRING:
			errors.append('%s: slot "%s" role must be text' % [full_id, path])
		for flag in ["pass_through", "working", "swappable", "removable", "optional"]:
			if slot.has(flag) and typeof(slot[flag]) != TYPE_BOOL:
				errors.append('%s: slot "%s" %s must be true or false' % [full_id, path, flag])
		if slot.has("compat") and not slot.compat in Compatibility.RULES:
			errors.append('%s: slot "%s" compat must be one of %s' % [full_id, path, ", ".join(Compatibility.RULES)])
		elif slot.has("compat"):
			_read_compat(full_id, slots, path)
		var needs = slot.get("requires", [])
		if typeof(needs) != TYPE_ARRAY:
			errors.append('%s: slot "%s" requires must be a list of slot paths' % [full_id, path])
			continue
		for need in needs:
			if not slots.has(need):
				errors.append('%s: slot "%s" requires "%s", which isn\'t a slot in this mission' % [full_id, path, need])
	# A loop (a needs b, b needs a) could never be finished.
	for path in slots:
		if _requires_loop(slots, path, path, {}):
			errors.append('%s: slot "%s" is in a requires loop' % [full_id, path])


## A compat rule has to be on a slot it can judge: one that takes the rule's
## kind of part, and that requires the slots holding what the rule compares
## it with. Otherwise the rule would pass everything without a word.
func _read_compat(full_id: String, slots: Dictionary, path: String) -> void:
	var slot: Dictionary = slots[path]
	var needs: Dictionary = Compatibility.NEEDS[slot.compat]
	if needs.part != "" and slot.get("accepts") != needs.part:
		errors.append('%s: slot "%s" compat %s is for a slot that accepts %s' % [full_id, path, slot.compat, needs.part])
	var required := []
	var listed = slot.get("requires", [])
	for need in listed if typeof(listed) == TYPE_ARRAY else []:
		if slots.has(need) and typeof(slots[need]) == TYPE_DICTIONARY:
			required.append(slots[need].get("accepts"))
	for type in needs.others:
		if slot.get("accepts") != type and not required.has(type):
			errors.append('%s: slot "%s" compat %s needs a slot that accepts %s in its requires' % [full_id, path, slot.compat, type])


## True when following `requires` from `at` leads back to `start`.
func _requires_loop(slots: Dictionary, start: String, at: String, seen: Dictionary) -> bool:
	if typeof(slots[at]) != TYPE_DICTIONARY or typeof(slots[at].get("requires", [])) != TYPE_ARRAY:
		return false
	for need in slots[at].get("requires", []):
		if need == start:
			return true
		if slots.has(need) and not seen.has(need):
			seen[need] = true
			if _requires_loop(slots, start, need, seen):
				return true
	return false


static func _is_id(value) -> bool:
	return typeof(value) == TYPE_STRING and RegEx.create_from_string("^[a-z0-9_]+$").search(value) != null


static func _is_text_list(value) -> bool:
	if typeof(value) != TYPE_ARRAY or value.is_empty():
		return false
	return value.all(func(line) -> bool: return typeof(line) == TYPE_STRING and line != "")


static func _is_whole(value, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and float(value) == floor(float(value)) and low <= value and value <= high
