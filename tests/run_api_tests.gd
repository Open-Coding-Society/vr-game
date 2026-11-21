extends SceneTree
## Step 5 checks against a fake server: no backend or network needed.
##
##   godot --headless --script res://tests/run_api_tests.gd
##
## The fake replaces TrainingApi.transport, records every request, and answers
## from a script of replies, so sign-in, sessions, retries and failures can
## each be checked exactly. tests/run_live_api_test.gd does one real round trip.

const TrainingManagerScript := preload("res://scripts/training_manager.gd")
const ScoreReporterScript := preload("res://scripts/net/score_reporter.gd")
const ModuleRegistry := preload("res://scripts/module_registry.gd")
const TrainingApi := preload("res://scripts/net/training_api.gd")
const IdentifyComponents := preload("res://scenes/build_computer/identify_components.tscn")

const MISSION := "build_computer.identify_components"
const LOGIN_OK := {"code": 200, "headers": ["Content-Type: application/json", "Set-Cookie: jwt_python_flask=TOKEN123; Expires=Thu, 26 Nov 2026 00:00:00 GMT; HttpOnly; Path=/"], "body": {"message": "ok"}}

var _failures: Array[String] = []
var manager: Node
var reporter: Node
var requests: Array = []
var replies: Array = []
var reports: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Missions finished here would be recorded in the player's real save; use a
	# throwaway file instead.
	var saves := root.get_node_or_null("SaveService")
	if saves:
		saves.use_backend(preload("res://scripts/save/local_save_backend.gd").new("user://test_ocsvr_save.json"))
	# Use the project's autoloads (loaded for --script runs too), adding them
	# at the same paths only if they're missing.
	manager = root.get_node_or_null("TrainingManager")
	if manager == null:
		manager = TrainingManagerScript.new()
		manager.name = "TrainingManager"
		root.add_child(manager)
	manager.use_registry(ModuleRegistry.load_from())
	reporter = root.get_node_or_null("ScoreReporter")
	if reporter == null:
		reporter = ScoreReporterScript.new()
		reporter.name = "ScoreReporter"
		root.add_child(reporter)
	reporter.api.transport = _fake_server
	reporter.retry_wait_s = 0.0
	reporter.report_finished.connect(func(ok, message): reports.append([ok, message]))
	for test in [_test_jwt_from_cookie, _test_full_round_trip, _test_retries_when_unreachable,
			_test_no_retry_on_client_error, _test_not_configured, _test_practice_not_sent,
			_test_sign_in_refused, _test_start_failed_still_completes, _test_panel_shows_save_status]:
		_reset()
		await test.call()
	print("\n%s" % ("ALL PASSED" if _failures.is_empty() else "%d FAILED" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)


func check(label: String, ok: bool, detail = "") -> void:
	var why := str(detail)
	print(("PASS  " if ok else "FAIL  ") + label + ("" if ok or why == "" else "   [%s]" % why))
	if not ok:
		_failures.append(label)


func _reset() -> void:
	requests.clear()
	replies.clear()
	reports.clear()
	reporter.api.token = ""
	reporter.api.base_url = "http://test.local:8587"
	reporter.uid = "hop"
	reporter.password = "test-password"
	reporter.session_id = ""


## The fake transport: records the request, returns the next scripted reply.
func _fake_server(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	requests.append({"method": method, "path": url.replace("http://test.local:8587", ""), "headers": headers, "body": JSON.parse_string(body), "raw": body})
	var reply: Dictionary = replies.pop_front() if not replies.is_empty() else {"code": 500, "headers": [], "body": null}
	return {"code": reply.code, "headers": PackedStringArray(reply.headers), "body": reply.body}


func _session(extra := {}) -> Dictionary:
	var body := {"session_id": "abc-123", "learner_id": "hop", "module": MISSION, "status": "started"}
	body.merge(extra, true)
	return {"code": 201, "headers": [], "body": body}


## Plays a mission through the TrainingManager: start, grab, optional mistakes, finish.
func _play(mission_id := MISSION, mistakes := 0) -> void:
	manager.now_ms = func() -> int: return 0
	manager.begin(mission_id)
	await process_frame
	manager.note_grab()
	for i in mistakes:
		manager.note_mistake()
	manager.now_ms = func() -> int: return 184000
	manager.complete()
	for i in 5:
		await process_frame


func _paths() -> Array:
	return requests.map(func(r): return r.path)


func _test_jwt_from_cookie() -> void:
	check("the JWT is read from the login cookie",
		TrainingApi._jwt_from(PackedStringArray(LOGIN_OK.headers)) == "TOKEN123")
	check("no cookie means no token", TrainingApi._jwt_from(PackedStringArray(["Content-Type: text/html"])) == "")


func _test_full_round_trip() -> void:
	replies = [LOGIN_OK, _session(), {"code": 200, "headers": [], "body": {"session_id": "abc-123", "learner_id": "hop", "status": "completed", "score": 90}}]
	await _play(MISSION, 1)
	check("it signs in, starts a session, then completes it",
		_paths() == ["/api/authenticate", "/api/sessions/start", "/api/sessions/complete"], _paths())
	check("sign-in sends the configured account", requests[0].body == {"uid": "hop", "password": "test-password"}, requests[0].body)
	check("later requests carry the JWT as a Bearer token",
		"Authorization: Bearer TOKEN123" in requests[1].headers and "Authorization: Bearer TOKEN123" in requests[2].headers)
	check("start sends the mission and device", requests[1].body == {"module": MISSION, "device": "desktop"}, requests[1].body)
	var expected := {"session_id": "abc-123", "module": MISSION, "score": 90, "duration_s": 184, "attempts": 2, "device": "desktop"}
	# Parsed JSON numbers come back as floats, so compare through JSON both ways.
	check("complete sends the API's fields with the session_id",
		requests[2].body == JSON.parse_string(JSON.stringify(expected)), requests[2].body)
	check("numbers go out as whole numbers (the API rejects 90.5)",
		'"score":90' in requests[2].raw and '"attempts":2' in requests[2].raw and '"duration_s":184' in requests[2].raw, requests[2].raw)
	check("and reports success", reports == [[true, "Score saved to hop's progress."]], reports)


func _test_retries_when_unreachable() -> void:
	reporter.api.token = "TOKEN123"
	replies = [_session(), {"code": 0, "headers": [], "body": null}, {"code": 502, "headers": [], "body": null},
		{"code": 200, "headers": [], "body": {"session_id": "abc-123", "learner_id": "hop", "status": "completed"}}]
	await _play()
	check("an unreachable server and a 502 are retried, with the same session_id",
		_paths() == ["/api/sessions/start", "/api/sessions/complete", "/api/sessions/complete", "/api/sessions/complete"]
			and requests.slice(1).all(func(r): return r.body.session_id == "abc-123"), _paths())
	check("the third try succeeds", reports.size() == 1 and reports[0][0], reports)


func _test_no_retry_on_client_error() -> void:
	reporter.api.token = "TOKEN123"
	replies = [_session(), {"code": 400, "headers": [], "body": {"message": "score is required and must be a whole number from 0 to 100"}}]
	await _play()
	check("a 400 isn't retried", _paths().count("/api/sessions/complete") == 1, _paths())
	check("and the server's reason is reported",
		reports.size() == 1 and not reports[0][0] and "score is required" in reports[0][1], reports)


func _test_not_configured() -> void:
	reporter.uid = ""
	reporter.password = ""
	await _play()
	check("with no account set up, nothing is sent", requests.is_empty(), _paths())
	check("and the panel is told why", reports == [[false, "Score not saved: no account is set up on this computer."]], reports)


func _test_practice_not_sent() -> void:
	await _play("build_computer.install_ram")
	check("a practice mission sends nothing and reports nothing", requests.is_empty() and reports.is_empty(), [_paths(), reports])


func _test_sign_in_refused() -> void:
	replies = [{"code": 401, "headers": [], "body": {"message": "Invalid user id or password"}},
		{"code": 401, "headers": [], "body": {"message": "Invalid user id or password"}}]
	await _play()
	check("a refused sign-in sends no scores", not _paths().has("/api/sessions/complete"), _paths())
	check("and says sign-in failed", reports.size() == 1 and not reports[0][0] and "Sign-in failed (HTTP 401)" in reports[0][1], reports)


func _test_start_failed_still_completes() -> void:
	reporter.api.token = "TOKEN123"
	replies = [{"code": 0, "headers": [], "body": null},
		{"code": 201, "headers": [], "body": {"session_id": "new-1", "learner_id": "hop", "status": "completed"}}]
	await _play()
	check("if starting failed, complete still saves the result (without a session_id)",
		_paths() == ["/api/sessions/start", "/api/sessions/complete"] and not requests[1].body.has("session_id"), requests.map(func(r): return r.body))
	check("and reports success", reports.size() == 1 and reports[0][0], reports)


func _test_panel_shows_save_status() -> void:
	reporter.api.token = "TOKEN123"
	replies = [_session(), {"code": 200, "headers": [], "body": {"session_id": "abc-123", "learner_id": "hop", "status": "completed"}}]
	var mission := IdentifyComponents.instantiate()
	root.add_child(mission)
	for i in 3:
		await physics_frame
	manager.note_grab()
	manager.complete()
	for i in 5:
		await process_frame
	check("the success panel ends with the save result",
		mission.panel.lines[-1] == "Score saved to hop's progress." and not mission.panel.lines.has("Saving your score..."), mission.panel.text())
	mission.queue_free()
