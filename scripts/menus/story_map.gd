extends RefCounted
## Reads data/story.json, the Story Mode roadmap: chapters (IRL, Cloud), their
## acts, and each act's tasks, and works out each task's state from what's done.
##
## A task with "mission" is playable (a mission in data/modules.json); one with
## only an id and title is planned. A chapter's playable tasks unlock in order:
## done ones stay open, the first one not done is "next", and the rest are
## locked until it's done. Planned tasks never block the path.

const DEFAULT_PATH := "res://data/story.json"

const DONE := "done"
const NEXT := "next"
const LOCKED := "locked"
const PLANNED := "planned"

## [{id, title, subtitle, acts: [{title, tasks: [{id, title, mission}]}]}]
var chapters: Array = []
var bridge: Dictionary = {}
var errors: PackedStringArray = []


## Loads the roadmap. `registry` (module_registry.gd) checks that each mission
## exists and gives playable tasks their title.
static func load_from(registry, path := DEFAULT_PATH):
	var map = new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		map.errors.append("%s: missing, or not a JSON object" % path)
		return map
	map.read(data, registry)
	return map


func read(data: Dictionary, registry) -> void:
	bridge = data.get("bridge", {}) if typeof(data.get("bridge")) == TYPE_DICTIONARY else {}
	var list = data.get("chapters")
	if typeof(list) != TYPE_ARRAY or list.is_empty():
		errors.append("chapters: must be a non-empty list")
		return
	var seen := {}
	for c in list:
		if typeof(c) != TYPE_DICTIONARY or typeof(c.get("id")) != TYPE_STRING or typeof(c.get("acts")) != TYPE_ARRAY:
			errors.append("chapters: each chapter needs an id and a list of acts")
			continue
		var chapter := {"id": c.id, "title": str(c.get("title", c.id)), "subtitle": str(c.get("subtitle", "")), "acts": []}
		for a in c.acts:
			var act := {"title": str(a.get("title", "")) if typeof(a) == TYPE_DICTIONARY else "", "tasks": []}
			var tasks = a.get("tasks") if typeof(a) == TYPE_DICTIONARY else null
			if typeof(tasks) != TYPE_ARRAY:
				errors.append("%s: act \"%s\" needs a list of tasks" % [c.id, act.title])
				continue
			for t in tasks:
				var task := _read_task(c.id, t, registry)
				if task.is_empty():
					continue
				if seen.has(task.id):
					errors.append("%s: task %s is listed twice" % [c.id, task.id])
					continue
				seen[task.id] = true
				act.tasks.append(task)
			chapter.acts.append(act)
		chapters.append(chapter)


func _read_task(chapter_id: String, t, registry) -> Dictionary:
	if typeof(t) != TYPE_DICTIONARY:
		errors.append("%s: each task must be an object" % chapter_id)
		return {}
	if t.has("mission"):
		var mission: Dictionary = registry.mission(str(t.mission)) if registry else {}
		if mission.is_empty():
			errors.append("%s: task mission %s isn't in data/modules.json" % [chapter_id, t.mission])
			return {}
		return {"id": mission.full_id, "title": str(t.get("title", mission.title)).strip_edges(), "mission": mission.full_id}
	if typeof(t.get("id")) != TYPE_STRING or typeof(t.get("title")) != TYPE_STRING:
		errors.append("%s: a planned task needs an id and a title" % chapter_id)
		return {}
	return {"id": t.id, "title": t.title, "mission": ""}


func chapter(id: String) -> Dictionary:
	for c in chapters:
		if c.id == id:
			return c
	return {}


## Every task of a chapter, in order.
func tasks_of(id: String) -> Array:
	var out := []
	for act in chapter(id).get("acts", []):
		out.append_array(act.tasks)
	return out


## task id -> state (done / next / locked / planned) for a chapter.
## `is_done` is a Callable(task_id) -> bool, e.g. SaveService.is_task_done.
func states(id: String, is_done: Callable) -> Dictionary:
	var out := {}
	var found_next := false
	for task in tasks_of(id):
		if task.mission == "":
			out[task.id] = PLANNED
		elif is_done.call(task.id):
			out[task.id] = DONE
		elif not found_next:
			out[task.id] = NEXT
			found_next = true
		else:
			out[task.id] = LOCKED
	return out


## [done, total] counting only playable tasks.
func progress(id: String, is_done: Callable) -> Array:
	var playable := tasks_of(id).filter(func(t) -> bool: return t.mission != "")
	var done := playable.filter(func(t) -> bool: return is_done.call(t.id))
	return [done.size(), playable.size()]


## True when every playable task of a chapter is done (and it has some).
func chapter_complete(id: String, is_done: Callable) -> bool:
	var p := progress(id, is_done)
	return p[1] > 0 and p[0] == p[1]
