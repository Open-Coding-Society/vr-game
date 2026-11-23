extends Node
## The TrainingManager autoload (Mr. Mortensen's plan): runs one mission at a
## time through Intro -> Active -> Success, keeps the clock, the mistakes and the
## score, and announces the result with `module_completed`.
##
## It knows nothing about scenes, parts or the mouse. A mission scene (see
## scripts/missions/mission.gd) calls begin(), then tells it about grabs,
## installs and mistakes. Step 5 listens to `module_completed` to send the
## result to the Flask training API (POST /api/sessions/complete).

const ModuleRegistry := preload("res://scripts/module_registry.gd")

enum State { IDLE, INTRO, ACTIVE, SUCCESS }

## A mission was loaded and is waiting for the student's first grab.
signal mission_started(module_id: String)
signal state_changed(state: State)
## The plan's success signal. `attempts` and `mistakes` are on the manager too.
signal module_completed(module_id: String, score: int, duration_s: int)

var registry = null
var state := State.IDLE
## The mission being played, from the registry (empty when IDLE).
var mission: Dictionary = {}
var mistakes := 0
## Extra points a mission has given on top of its score (see add_bonus).
var bonus := 0
var score := 0
var duration_s := 0
## Tries the student needed: 1 plus the mistakes. The API's `attempts` field.
var attempts := 1
## Overridable clock (milliseconds), so tests can control time.
var now_ms: Callable = Time.get_ticks_msec
## After a mission ends, open the next one in the registry's order on its own.
## Tests turn this off.
var auto_advance := true
var advance_delay_s := 6.0
## Set by the menu when it starts a mission (Free Play, Story Mode): when the
## mission ends, go back to this scene instead of on to the next mission.
## return_page is the menu page to reopen (e.g. "free_play:computer") and
## return_label what the success panel calls it ("Free Play").
var return_scene := ""
var return_page := ""
var return_label := ""
## Opens a scene by path. Tests swap it so nothing really changes scene.
var scene_opener: Callable = func(path: String) -> void: get_tree().change_scene_to_file(path)
var _started_ms := 0


func _ready() -> void:
	if registry == null:
		use_registry(ModuleRegistry.load_from())


## Swaps in a registry (tests use their own). Problems in it are printed as
## errors, so a typo in data/modules.json is the first thing you see.
func use_registry(new_registry) -> void:
	registry = new_registry
	for problem in registry.errors:
		push_error("modules.json: " + problem)


## Loads a mission by its full id ("module.mission") and goes to Intro.
## Returns the mission's registry entry, or {} if there's no such mission.
func begin(full_id: String) -> Dictionary:
	if registry == null:
		use_registry(ModuleRegistry.load_from())
	mission = registry.mission(full_id)
	if mission.is_empty():
		push_error("TrainingManager: no mission %s in data/modules.json" % full_id)
		_set_state(State.IDLE)
		return {}
	mistakes = 0
	bonus = 0
	attempts = 1
	duration_s = 0
	score = mission.scoring.full
	_set_state(State.INTRO)
	mission_started.emit(full_id)
	return mission


## The mission after `full_id` in its module, by registry order, or "" if it's the last.
func next_mission_id(full_id: String) -> String:
	for module in registry.modules:
		var at: int = module.mission_ids.find(full_id)
		if at != -1:
			return module.mission_ids[at + 1] if at + 1 < module.mission_ids.size() else ""
	return ""


## The student picked something up. The first grab starts the mission's clock.
func note_grab() -> void:
	if state == State.INTRO:
		_started_ms = now_ms.call()
		_set_state(State.ACTIVE)


## A part went in the wrong place. Each one costs `per_mistake` points.
func note_mistake() -> void:
	if state != State.ACTIVE:
		return
	mistakes += 1
	attempts = mistakes + 1
	_update_score()


## A mission gives extra points for something done well (e.g. a balanced PC
## build). They are added on top of what the mistakes leave.
func add_bonus(points: int) -> void:
	if state != State.ACTIVE:
		return
	bonus += points
	_update_score()


func _update_score() -> void:
	score = maxi(0, mission.scoring.full - mission.scoring.per_mistake * mistakes) + bonus


## Every slot is filled: stop the clock and announce the result.
func complete() -> void:
	if state != State.ACTIVE:
		return
	duration_s = roundi((now_ms.call() - _started_ms) / 1000.0)
	_set_state(State.SUCCESS)
	module_completed.emit(mission.full_id, score, duration_s)


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(state)


## Opens a scene (a mission or the menu) through scene_opener.
func open_scene(path: String) -> void:
	scene_opener.call(path)
