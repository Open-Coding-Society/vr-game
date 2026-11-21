extends Node
## The SaveService autoload: the one place the game saves and loads progress.
##
## Menus and missions only call this. It keeps the profile (the save) in memory
## and writes it through a backend: the local file now (local_save_backend.gd),
## the OCS server in phase 5. Swapping the backend changes nothing else.
##
## Finished missions are recorded on their own: this listens to the
## TrainingManager's module_completed signal.
##
## The save's shape (schema_version 1):
##   learner_uid   the OCS account it belongs to, or null when playing locally
##   tasks         task id -> {best_score, last_score, attempts, completions,
##                 best_time_s, completed_at}; the same ids the training API uses
##   story         chapter ("irl" / "cloud" / "bridge") -> {current}: the task
##                 the roadmap is on. What's done comes from `tasks`.
##   open_world    {layout: [], unlocked_items: []} (phase 6)
##   settings      {input, comfort}

const LocalSaveBackend := preload("res://scripts/save/local_save_backend.gd")
const SCHEMA_VERSION := 1

## The profile changed (a task was recorded, a setting changed, a save loaded).
signal profile_changed

var backend = null
var profile: Dictionary = {}


func _ready() -> void:
	if backend == null:
		use_backend(LocalSaveBackend.new())
	var manager := get_node_or_null("/root/TrainingManager")
	if manager:
		manager.module_completed.connect(_on_module_completed)


## Switches the backend (tests use their own file) and loads its save.
func use_backend(new_backend) -> void:
	backend = new_backend
	load_profile()


## A fresh, empty profile in the current shape.
static func new_profile() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"learner_uid": null,
		"updated_at": "",
		"tasks": {},
		"story": {"irl": {"current": ""}, "cloud": {"current": ""}, "bridge": {"current": ""}},
		"open_world": {"layout": [], "unlocked_items": []},
		"settings": {"input": "controllers", "comfort": "standing"},
	}


## Brings an older or partly missing save up to the current shape, keeping what
## it has. Unknown keys are kept too, so a newer game's save isn't damaged.
static func upgrade(data: Dictionary) -> Dictionary:
	var fresh := new_profile()
	var out := data.duplicate(true)
	for key in fresh:
		if not out.has(key) or typeof(out[key]) != typeof(fresh[key]):
			out[key] = fresh[key]
		elif typeof(fresh[key]) == TYPE_DICTIONARY:
			for sub in fresh[key]:
				if not out[key].has(sub):
					out[key][sub] = fresh[key][sub]
	out.schema_version = SCHEMA_VERSION
	return out


func load_profile() -> void:
	profile = upgrade(backend.load_data() if backend else {})
	profile_changed.emit()


func save_profile() -> bool:
	profile.updated_at = Time.get_datetime_string_from_system(true) + "Z"
	return backend.save_data(profile) if backend else false


## Records one finished task: keeps the best score and fastest time, the last
## score, and adds up attempts and completions. Saves straight away.
func record_task_result(task_id: String, score: int, duration_s: int, attempts: int) -> void:
	var tasks: Dictionary = profile.tasks
	var entry: Dictionary = tasks.get(task_id, {
		"best_score": 0, "last_score": 0, "attempts": 0, "completions": 0, "best_time_s": 0, "completed_at": ""})
	entry.best_score = maxi(int(entry.best_score), score)
	entry.last_score = score
	entry.attempts = int(entry.attempts) + attempts
	entry.completions = int(entry.completions) + 1
	entry.best_time_s = duration_s if int(entry.best_time_s) == 0 else mini(int(entry.best_time_s), duration_s)
	entry.completed_at = Time.get_datetime_string_from_system(true) + "Z"
	tasks[task_id] = entry
	save_profile()
	profile_changed.emit()


## A task's saved progress, or {} if it was never finished.
func task_progress(task_id: String) -> Dictionary:
	return profile.tasks.get(task_id, {})


func is_task_done(task_id: String) -> bool:
	return profile.tasks.has(task_id)


## Where the Story roadmap of a chapter is ("" when it hasn't started).
func story_current(chapter: String) -> String:
	return profile.story.get(chapter, {}).get("current", "")


func set_story_current(chapter: String, task_id: String) -> void:
	if not profile.story.has(chapter):
		profile.story[chapter] = {"current": ""}
	profile.story[chapter].current = task_id
	save_profile()
	profile_changed.emit()


func setting(key: String, default = null):
	return profile.settings.get(key, default)


func set_setting(key: String, value) -> void:
	profile.settings[key] = value
	save_profile()
	profile_changed.emit()


## Open World layout (phase 6): a list of {item, transform} entries.
func save_world_layout(layout: Array) -> void:
	profile.open_world.layout = layout.duplicate(true)
	save_profile()


func load_world_layout() -> Array:
	return profile.open_world.layout.duplicate(true)


func _on_module_completed(module_id: String, score: int, duration_s: int) -> void:
	var manager := get_node_or_null("/root/TrainingManager")
	var attempts: int = manager.attempts if manager else 1
	record_task_result(module_id, score, duration_s, attempts)
