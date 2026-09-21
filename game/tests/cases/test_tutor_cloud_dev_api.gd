extends RefCounted

## The cloud tutor client against the DEPLOYED DEVELOPMENT Worker (Agent C,
## 2026-09-21). Runs ONLY when the operator sets the environment variable:
##
##   LD_TUTOR_DEV_URL=https://<the dev Worker> godot --headless --path game --script res://tests/run_tests.gd
##
## Without it the case prints SKIP and passes; the URL lives nowhere in the
## repository. The project flag stays OFF: the REST client is armed with
## `enable_dev_api_for_tests(url)`, which is refused on mobile/release builds
## and dials exactly the address in the variable. Everything sent is
## synthetic (a random clientId, scripted transcripts); no audio exists.
##
## What it proves against the live API (DEV_MODE, mock provider):
##   * DEV sign-in -> consent -> entitlement -> session -> realtime token 503
##     -> READY on the turns path (never a dead classroom);
##   * a turn returns a validated TutorTurn with its card; the same key
##     replays (`idempotent-replayed`) without a second charge;
##   * `X-Debug-Now` drives the server clock so the daily allowance runs out:
##     the boundary turn is served (`endAtBoundary`), the session ends
##     `quota_expired`, the mirror is told, no further turn is sent;
##   * `/end` is posted once; a turn after the end is refused locally and,
##     sent by hand, answers 409 session_ended; a bogus approval answers 403.

const ApiScript := preload("res://scripts/tutor/cloud/cloud_tutor_api.gd")
const TransportScript := preload("res://scripts/tutor/voice/transports/cloud_realtime_transport.gd")
const SessionScript := preload("res://scripts/tutor/cloud/cloud_tutor_session.gd")
const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")

const LESSON: String = "english_colors_fruits"
const STEP: Dictionary = {"stepId": "s02_apple_name", "outcome": "correct", "matched": "apple", "lessonAction": "next_question"}
const ROUND_TRIP_SECONDS: float = 12.0
## The Worker caps each server-clock gap at 45 s; 300 s / 45 s -> the 7th turn lands on the boundary.
const TURN_CAP_MS: int = 45000


class Mirror:
	extends RefCounted
	var exhausted: bool = false
	var blocks: Array = []
	func is_exhausted() -> bool:
		return exhausted
	func apply_server_quota(quota: Dictionary, _end_at_boundary: bool) -> void:
		blocks.append(quota)
	func apply_server_failure(parsed: Dictionary) -> void:
		if String(parsed.get("state", "")) == "exhausted":
			exhausted = true


func test_name() -> String:
	return "tutor_cloud_dev_api"


func run():
	var failures: Array = []
	if TutorFlags.cloud_enabled():
		return ["this suite must run with the cloud flag OFF (the LD_TUTOR_DEV_URL hatch is used instead)"]
	var url: String = OS.get_environment(ApiScript.DEV_URL_ENV).strip_edges().trim_suffix("/")
	if url.is_empty():
		print("    SKIP dev api: LD_TUTOR_DEV_URL is not set")
		return failures
	var client_id: String = "ld-test-%d-%d" % [int(Time.get_unix_time_from_system()), randi() % 100000]
	var api: RefCounted = ApiScript.new()
	api.configure(client_id)
	if not api.enable_dev_api_for_tests(url):
		return ["dev api: enable_dev_api_for_tests refused %s (https only, must equal LD_TUTOR_DEV_URL)" % url]
	var transport: RefCounted = TransportScript.new()
	transport.enable_for_tests()
	var session: RefCounted = SessionScript.new()
	session.set_api(api)
	session.set_transport(transport)
	var mirror := Mirror.new()
	session.set_quota(mirror)
	session.configure(LESSON)
	var ev: Dictionary = {"ready": [], "ended": [], "fell_back": [], "turns": [], "failed": [], "tools": [], "api": []}
	session.ready.connect(func(i: Dictionary) -> void: ev["ready"].append(i))
	session.ended.connect(func(r: String, s: Dictionary) -> void: ev["ended"].append([r, s]))
	session.fell_back.connect(func(r: String) -> void: ev["fell_back"].append(r))
	session.turn_ready.connect(func(t: Dictionary) -> void: ev["turns"].append(t))
	session.turn_failed.connect(func(r: String) -> void: ev["failed"].append(r))
	session.tool_applied.connect(func(n: String, a: Dictionary) -> void: ev["tools"].append([n, a]))
	api.completed.connect(func(kind: String, result: Dictionary) -> void: ev["api"].append([kind, result]))

	# 1. Bring-up over the live API.
	session.start()
	if not _pump(session, func() -> bool: return session.is_ready() or not ev["fell_back"].is_empty() or not ev["ended"].is_empty(), 30.0):
		return ["dev api: not ready in 30 s: state=%s history=%s fell_back=%s" % [session.get_state(), str(session.state_history()), str(ev["fell_back"])]]
	print("    dev api: ready transport=%s session=%s history=%s quota=%s" % [session.transport_mode(), session.session_id(), str(session.state_history()), str(session.server_quota())])
	if session.transport_mode() != "turns" or session.state_history() != ["signing_in", "consenting", "quota", "creating", "minting", "ready"]:
		failures.append("dev api: sign-in -> consent -> quota -> session -> token 503 -> turns: %s" % str(session.state_history()))
	if float(session.server_quota().get("allowanceSeconds", 0.0)) != 300.0:
		failures.append("dev api: the free allowance is 300 s: %s" % str(session.server_quota()))
	var sid: String = session.session_id()

	# 2. A turn: the validated TutorTurn with its card.
	session.send_transcript("apple", STEP)
	if not _pump(session, func() -> bool: return ev["turns"].size() >= 1 or not ev["failed"].is_empty()):
		failures.append("dev api: no turn reply: failed=%s" % str(ev["failed"]))
	else:
		var turn: Dictionary = ev["turns"][0]
		print("    dev api: turn 1 %s log=%s" % [str(turn), str(session.turn_log())])
		if TurnValidator.coerce(turn) != turn or turn["visual"] != {"type": "flashcard", "assetId": "apple_red"} or ev["tools"] != [["show_card", {"assetId": "apple_red"}]]:
			failures.append("dev api: validated turn with the apple card: %s" % str(turn))
	# 3. Idempotent replay: the same key, the same body, by hand -> replayed, not charged again.
	var used_turns: int = int(session.server_quota().get("usedTurns", 0))
	var key: String = String(session.turn_log()[0]["key"]) if not session.turn_log().is_empty() else "%s:t1" % sid
	var before: int = ev["api"].size()
	api.submit_turn(sid, key, "apple", STEP, 0.0)
	if not _pump(session, func() -> bool: return ev["api"].size() > before):
		failures.append("dev api: replay never answered")
	else:
		var replay: Dictionary = ev["api"][-1][1]
		var replay_turns: int = int(ApiScript.quota_of(replay["body"]).get("usedTurns", -1))
		print("    dev api: replay ok=%s replayed=%s usedTurns=%d (was %d)" % [str(replay["ok"]), str(replay["replayed"]), replay_turns, used_turns])
		if not bool(replay["ok"]) or not bool(replay["replayed"]) or replay_turns != used_turns:
			failures.append("dev api: the replay is flagged and not charged: %s" % str(replay))

	# 4. Quota boundary: X-Debug-Now advances the server clock 45 s per turn.
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var boundary_hit: bool = false
	for i: int in range(1, 12):
		if not session.is_ready():
			break
		api.set_debug_now_ms(now_ms + i * TURN_CAP_MS)
		var count: int = ev["turns"].size()
		if not session.send_transcript("apple", STEP):
			failures.append("dev api: turn %d refused while ready" % i)
			break
		if not _pump(session, func() -> bool: return ev["turns"].size() > count or not ev["ended"].is_empty() or not ev["failed"].is_empty()):
			failures.append("dev api: turn %d never answered" % i)
			break
		var row: Dictionary = session.turn_log()[-1]
		if bool(row.get("endAtBoundary", false)):
			boundary_hit = true
			print("    dev api: boundary at turn %d: %s" % [i, str(row)])
			break
	_pump(session, func() -> bool: return not ev["ended"].is_empty(), ROUND_TRIP_SECONDS)
	api.set_debug_now_ms(0)
	if not boundary_hit:
		failures.append("dev api: the allowance never ran out: log=%s" % str(session.turn_log()))
	if ev["ended"].size() != 1 or String(ev["ended"][0][0]) != "quota_expired" or not mirror.exhausted:
		failures.append("dev api: ended once for quota with the mirror told: %s exhausted=%s" % [str(ev["ended"]), str(mirror.exhausted)])
	if not ev["failed"].is_empty():
		failures.append("dev api: no turn was lost: %s" % str(ev["failed"]))
	if session.send_transcript("apple", STEP) or session.is_streaming_allowed():
		failures.append("dev api: nothing is sent after the boundary")
	var ends: int = 0
	for entry: Dictionary in api.request_log():
		if String(entry.get("kind", "")) == "end" and entry.has("path"):
			ends += 1
	if ends != 1:
		failures.append("dev api: /end posted %d times" % ends)
	var summary: Dictionary = session.last_summary()
	print("    dev api: ended %s serverAck=%s quota=%s serverUsage=%s" % [String(summary.get("reason", "")), str(summary.get("serverAck", false)), str(summary.get("quota", {})), str(summary.get("serverUsage", {}))])
	if not bool(summary.get("serverAck", false)) or float(summary.get("quota", {}).get("remainingSeconds", 1.0)) > 0.0:
		failures.append("dev api: the server acknowledged the end with nothing left: %s" % str(summary))

	# 5. After the end: 409 by hand; a bogus approval: 403.
	before = ev["api"].size()
	api.submit_turn(sid, "%s:late" % sid, "apple", STEP, 0.0)
	_pump(session, func() -> bool: return ev["api"].size() > before)
	var late: Dictionary = ev["api"][-1][1] if ev["api"].size() > before else {}
	if int(late.get("status", 0)) != 409 or String(late.get("code", "")) != "session_ended":
		failures.append("dev api: a turn after the end answers 409 session_ended: %s" % str(late))
	var bogus: RefCounted = ApiScript.new()
	bogus.configure(client_id, "pa1.bogus.bogus")
	bogus.enable_dev_api_for_tests(url)
	var denied: Array = []
	bogus.completed.connect(func(_k: String, r: Dictionary) -> void: denied.append(r))
	bogus.create_session(LESSON)
	var deadline: int = Time.get_ticks_msec() + int(ROUND_TRIP_SECONDS * 1000.0)
	while denied.is_empty() and Time.get_ticks_msec() < deadline:
		bogus.advance(0.01)
		OS.delay_msec(10)
	if denied.is_empty() or int(denied[0]["status"]) != 403 or String(denied[0]["code"]) != "not_approved":
		failures.append("dev api: a bogus approval answers 403 not_approved: %s" % str(denied))
	print("    dev api: after end -> %d %s; bogus approval -> %s" % [int(late.get("status", 0)), String(late.get("code", "")), str(denied[0]["code"]) if not denied.is_empty() else "none"])
	return failures


## Pumps the session in real time until `predicate` holds or `seconds` pass.
func _pump(session: RefCounted, predicate: Callable, seconds: float = ROUND_TRIP_SECONDS) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	var last: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() < deadline:
		var now: int = Time.get_ticks_msec()
		session.advance(maxf(float(now - last) / 1000.0, 0.001))
		last = now
		if bool(predicate.call()):
			return true
		OS.delay_msec(5)
	session.advance(0.001)
	return bool(predicate.call())
