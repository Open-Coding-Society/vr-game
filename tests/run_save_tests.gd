extends SceneTree
## SaveService checks (Phase 1, step 3). Uses a throwaway save file under
## user://, never the real one.
##
##   godot --headless --script res://tests/run_save_tests.gd

const SaveServiceScript := preload("res://scripts/save/save_service.gd")
const LocalSaveBackend := preload("res://scripts/save/local_save_backend.gd")
const TrainingManagerScript := preload("res://scripts/training_manager.gd")
const ModuleRegistry := preload("res://scripts/module_registry.gd")

const TEST_PATH := "user://test_ocsvr_save.json"
const MISSION := "build_computer.identify_components"

var _failures: Array[String] = []
var manager: Node
var saves: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	manager = root.get_node_or_null("TrainingManager")
	if manager == null:
		manager = TrainingManagerScript.new()
		manager.name = "TrainingManager"
		root.add_child(manager)
	manager.use_registry(ModuleRegistry.load_from())
	manager.auto_advance = false
	saves = root.get_node_or_null("SaveService")
	if saves == null:
		saves = SaveServiceScript.new()
		saves.name = "SaveService"
		root.add_child(saves)
	for test in [_test_fresh_profile, _test_record_keeps_best, _test_saved_and_reloaded,
			_test_bad_file_kept_and_fresh, _test_old_save_upgraded, _test_mission_end_recorded,
			_test_story_and_settings_saved, _test_world_layout_saved]:
		_clear()
		saves.use_backend(LocalSaveBackend.new(TEST_PATH))
		await test.call()
	_clear()
	print("\n%s" % ("ALL PASSED" if _failures.is_empty() else "%d FAILED" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)


func check(label: String, ok: bool, detail = "") -> void:
	var why := str(detail)
	print(("PASS  " if ok else "FAIL  ") + label + ("" if ok or why == "" else "   [%s]" % why))
	if not ok:
		_failures.append(label)


func _clear() -> void:
	for suffix in ["", ".tmp", ".bad"]:
		if FileAccess.file_exists(TEST_PATH + suffix):
			DirAccess.remove_absolute(TEST_PATH + suffix)


func _test_fresh_profile() -> void:
	var p: Dictionary = saves.profile
	check("a new player gets a fresh profile in the current shape",
		p.schema_version == 1 and p.learner_uid == null and p.tasks.is_empty()
		and p.story.has("irl") and p.story.has("cloud") and p.open_world.layout.is_empty())
	check("nothing is done yet", not saves.is_task_done(MISSION) and saves.task_progress(MISSION).is_empty())


func _test_record_keeps_best() -> void:
	saves.record_task_result(MISSION, 70, 120, 4)
	saves.record_task_result(MISSION, 90, 150, 2)
	saves.record_task_result(MISSION, 80, 95, 3)
	var t: Dictionary = saves.task_progress(MISSION)
	check("the best score is kept", t.best_score == 90, t)
	check("the last score is the newest", t.last_score == 80, t)
	check("attempts and completions add up", t.attempts == 9 and t.completions == 3, t)
	check("the fastest time is kept", t.best_time_s == 95, t)
	check("the task counts as done", saves.is_task_done(MISSION))


func _test_saved_and_reloaded() -> void:
	saves.record_task_result(MISSION, 85, 60, 1)
	check("recording a task writes the save file", FileAccess.file_exists(TEST_PATH))
	check("no half-written .tmp file is left", not FileAccess.file_exists(TEST_PATH + ".tmp"))
	var again = SaveServiceScript.new()
	again.use_backend(LocalSaveBackend.new(TEST_PATH))
	check("a restarted game loads the same progress", again.task_progress(MISSION).get("best_score") == 85,
		again.task_progress(MISSION))
	again.free()


func _test_bad_file_kept_and_fresh() -> void:
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	saves.load_profile()
	check("a broken save starts a fresh profile", saves.profile.tasks.is_empty())
	check("the broken file is kept as .bad", FileAccess.file_exists(TEST_PATH + ".bad"))


func _test_old_save_upgraded() -> void:
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"tasks": {MISSION: {"best_score": 50}}, "future_field": 7}))
	f.close()
	saves.load_profile()
	var p: Dictionary = saves.profile
	check("an older save keeps its progress", p.tasks[MISSION].best_score == 50, p.tasks)
	check("missing parts are filled in", p.schema_version == 1 and p.story.has("bridge") and p.settings.has("input"), p)
	check("unknown keys from a newer game are kept", p.get("future_field") == 7)


func _test_mission_end_recorded() -> void:
	manager.begin(MISSION)
	manager.note_grab()
	manager.note_mistake()
	manager.complete()
	var t: Dictionary = saves.task_progress(MISSION)
	check("finishing a mission records it on its own", t.get("completions") == 1 and t.get("attempts") == 2, t)
	check("its score is the mission's score", t.get("best_score") == manager.score, [t, manager.score])


func _test_story_and_settings_saved() -> void:
	saves.set_story_current("irl", MISSION)
	saves.set_setting("input", "hands")
	var again = SaveServiceScript.new()
	again.use_backend(LocalSaveBackend.new(TEST_PATH))
	check("the Story roadmap position is saved", again.story_current("irl") == MISSION)
	check("settings are saved", again.setting("input") == "hands")
	check("an unknown chapter has no position", again.story_current("nope") == "")
	again.free()


func _test_world_layout_saved() -> void:
	saves.save_world_layout([{"item": "tool_rack", "transform": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0.4, 0, -1.2]}])
	var again = SaveServiceScript.new()
	again.use_backend(LocalSaveBackend.new(TEST_PATH))
	var layout: Array = again.load_world_layout()
	check("the Open World layout is saved", layout.size() == 1 and layout[0].item == "tool_rack", layout)
	again.free()
