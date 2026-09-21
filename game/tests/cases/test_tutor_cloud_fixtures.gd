extends RefCounted

## The cloud tutor client, offline (Agent E). Runs in every suite run with
## the cloud flag OFF: no socket, no HTTP client, no key. The realtime
## transport is driven through `attach_test_sink()` + `handle_event()` with
## the recorded events in `tests/fixtures/tutor_realtime_events.json`; the
## REST client is exercised through its pure helpers and its refusal; the
## session state machine runs on a scripted fake API.
##
##   * REST client: the contract's exact headers (parent token, approval,
##     device id), error-code mapping, URL parsing, refusal with the flag off
##     (no request built).
##   * Transport: token normalisation (both shapes); tools-then-speech reply
##     -> validated turn with the flashcard and gesture from the tool calls,
##     outputs returned + one response.create, usage summed, 3 audio chunks;
##     cancel mid-stream -> response.cancel + truncate at the played
##     position, late deltas and the cancelled done ignored; off-allowlist
##     tool arguments dropped; error event; input transcript events.
##   * Session: quota -> session -> token -> connect -> ready; mic frames only
##     when the capture source allows; a reply drives speaking/mouth and ends
##     when the audio drained; a banned word cancels and replaces the reply;
##     402 falls back and marks the mirror exhausted; the mirror's exhaustion
##     ends at the boundary; 503 on the token reconnects once, the second
##     failure falls back and reports the lost turn; idle, background and end
##     post {reason, secondsUsed, usage}.
##   * Provider: exactly one turn_ready per submit (early on the first delta,
##     scripted on timeout / not-ready), open turns local, no cloud call.
##   * Synthesis wrapper: finished exactly once for a cloud reply, for a
##     barge-in and for a no-audio reply voiced locally.
##   * Audio player: virtual clock, level, played_ms, truncate.

const ApiScript := preload("res://scripts/tutor/cloud/cloud_tutor_api.gd")
const TransportScript := preload("res://scripts/tutor/voice/transports/cloud_realtime_transport.gd")
const SessionScript := preload("res://scripts/tutor/cloud/cloud_tutor_session.gd")
const ProviderScript := preload("res://scripts/tutor/cloud/cloud_tutor_provider.gd")
const SynthScript := preload("res://scripts/tutor/cloud/cloud_synthesis_provider.gd")
const PlayerScript := preload("res://scripts/tutor/cloud/cloud_audio_player.gd")
const LessonEngineScript := preload("res://scripts/tutor/lesson/lesson_engine.gd")
const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")

const FIXTURE: String = "res://tests/fixtures/tutor_realtime_events.json"
const CLOUD_DIR: String = "res://scripts/tutor/cloud/"


## A scripted stand-in for CloudTutorApi (the reconciled surface): answers
## each kind from a queue; `replayed` rides in the result like the real one.
class FakeApi:
	extends RefCounted
	signal completed(kind: String, result: Dictionary)
	var available: bool = true
	var approval: bool = true
	var calls: Array = []
	var replies: Dictionary = {}  # kind -> Array of results (popped in order)
	var pending: Array = []
	var cancels: int = 0
	func is_available() -> bool:
		return available
	func has_approval() -> bool:
		return approval
	func sign_in_dev(subject: String = "") -> bool:
		approval = true
		return _call("signIn", {"subject": subject})
	func grant_consent(kind: String = "ai_tutor") -> bool:
		return _call("consent", {"kind": kind})
	func fetch_quota() -> bool:
		return _call("quota", {})
	func create_session(lesson_id: String) -> bool:
		return _call("session", {"lessonId": lesson_id})
	func mint_token(session_id: String) -> bool:
		return _call("token", {"sessionId": session_id})
	func submit_turn(session_id: String, key: String, transcript: String, context: Dictionary, audio_seconds: float = 0.0) -> bool:
		return _call("turn", {"sessionId": session_id, "key": key, "transcript": transcript, "lessonContext": context, "audioSeconds": audio_seconds})
	func end_session(session_id: String, reason: String) -> bool:
		return _call("end", {"sessionId": session_id, "reason": reason})
	func cancel() -> void:
		cancels += 1
		pending.clear()
	func advance(_delta: float) -> void:
		while not pending.is_empty():
			var item: Array = pending.pop_front()
			completed.emit(item[0], item[1])
	func _call(kind: String, body: Dictionary) -> bool:
		calls.append({"kind": kind, "body": body})
		var queue: Array = replies.get(kind, [])
		var result: Dictionary = queue.pop_front() if not queue.is_empty() else FakeApi.ok({})
		pending.append([kind, result])
		return true
	func calls_of(kind: String) -> Array:
		var out: Array = []
		for call: Dictionary in calls:
			if String(call["kind"]) == kind:
				out.append(call)
		return out
	static func ok(body: Dictionary, replayed: bool = false) -> Dictionary:
		return {"ok": true, "status": 200, "body": body, "code": "", "message": "", "retryAfterSeconds": 0.0, "replayed": replayed}
	static func err(status: int, code: String, body: Dictionary = {}) -> Dictionary:
		return {"ok": false, "status": status, "body": body, "code": code, "message": "", "retryAfterSeconds": 0.0, "replayed": false}


class FakeQuota:
	extends RefCounted
	var exhausted: bool = false
	var failures: Array = []
	var blocks: Array = []
	func is_exhausted() -> bool:
		return exhausted
	func apply_server_failure(parsed: Dictionary) -> void:
		failures.append(parsed)
		if String(parsed.get("state", "")) == "exhausted":
			exhausted = true
	func apply_server_quota(quota: Dictionary, _end_at_boundary: bool) -> void:
		blocks.append(quota)


class FakeFace:
	extends RefCounted
	var calls: Array = []
	var mouth: Array = []
	func set_expression(name: String) -> bool:
		calls.append("expression:%s" % name)
		return true
	func play_gesture(name: String) -> float:
		calls.append("gesture:%s" % name)
		return 0.5
	func set_speaking(active: bool) -> void:
		calls.append("speaking:%s" % str(active))
	func set_mouth_open(amount: float) -> void:
		mouth.append(amount)


class FakeInnerSynth:
	extends Node
	signal started(text: String)
	signal finished(text: String)
	var spoken: Array = []
	var cancels: int = 0
	var speaking: bool = false
	var left: float = 0.0
	func speak_turn(turn: Dictionary, line_id: String = "") -> void:
		speak(String(turn.get("speech", "")), line_id)
	func speak(text: String, _line_id: String = "") -> void:
		spoken.append(text)
		speaking = true
		left = 0.3
		started.emit(text)
	func cancel() -> void:
		if speaking:
			cancels += 1
			speaking = false
			finished.emit("")
	func advance(delta: float) -> void:
		if speaking:
			left -= delta
			if left <= 0.0:
				speaking = false
				finished.emit(spoken[-1] if not spoken.is_empty() else "")
	func is_speaking() -> bool:
		return speaking
	func current_text() -> String:
		return spoken[-1] if not spoken.is_empty() else ""
	func voice_used() -> String:
		return "fake"
	func set_muted(_m: bool) -> void:
		pass


## Records what a transport "sent" in sink mode and every signal it raised.
class Tap:
	extends RefCounted
	var sent: Array = []
	var deltas: Array = []
	var chunks: int = 0
	var levels: Array = []
	var done: Array = []
	var cancelled: int = 0
	var tools: Array = []
	var errors: Array = []
	var transcripts: Array = []
	var speech_starts: int = 0
	var connected: int = 0
	func sink(event: Dictionary) -> void:
		sent.append(event)
	func attach(transport: RefCounted) -> void:
		transport.connected.connect(func(_i: Dictionary) -> void: connected += 1)
		transport.response_text_delta.connect(func(t: String) -> void: deltas.append(t))
		transport.response_audio_chunk.connect(func(_p: PackedByteArray) -> void: chunks += 1)
		transport.response_audio_delta.connect(func(l: float, _b: int) -> void: levels.append(l))
		transport.response_done.connect(func(turn: Dictionary) -> void: done.append(turn))
		transport.response_cancelled.connect(func() -> void: cancelled += 1)
		transport.tool_call.connect(func(n: String, a: Dictionary) -> void: tools.append([n, a]))
		transport.error.connect(func(c: String, _m: String) -> void: errors.append(c))
		transport.input_transcript.connect(func(t: String) -> void: transcripts.append(t))
		transport.server_speech_started.connect(func() -> void: speech_starts += 1)
	func sent_types() -> Array:
		var out: Array = []
		for event: Dictionary in sent:
			out.append(String(event.get("type", "")))
		return out


func test_name() -> String:
	return "tutor_cloud_fixtures"


func run():
	var failures: Array = []
	if TutorFlags.cloud_enabled():
		return ["this suite must run with the cloud flag OFF"]
	failures.append_array(_test_api_pure_and_gated())
	failures.append_array(_test_transport_token_shapes())
	failures.append_array(_test_transport_happy_reply())
	failures.append_array(_test_transport_cancel())
	failures.append_array(_test_transport_off_allowlist_and_errors())
	failures.append_array(_test_player_clock())
	failures.append_array(_test_session_lifecycle())
	failures.append_array(_test_session_safety_and_quota())
	failures.append_array(_test_session_failures())
	failures.append_array(_test_session_turns_path())
	failures.append_array(_test_provider_one_turn_per_submit())
	failures.append_array(_test_synthesis_wrapper())
	failures.append_array(_test_cloud_files_hold_no_secrets())
	return failures


# -- REST client ------------------------------------------------------------------------------

func _test_api_pure_and_gated():
	var failures: Array = []
	# Tutor routes: the approval token ONLY (never the sign-in header), plus the
	# per-call extras; account routes: the sign-in header only.
	var headers: PackedStringArray = ApiScript.build_headers("approval-2", {"Idempotency-Key": "k1"})
	var expected: Array = ["Content-Type: application/json", "Accept: application/json", "X-Parent-Approval: approval-2", "Idempotency-Key: k1"]
	if Array(headers) != expected:
		failures.append("tutor route headers: %s" % str(headers))
	var account: PackedStringArray = ApiScript.build_account_headers("parent-1")
	if Array(account) != ["Content-Type: application/json", "Accept: application/json", "Authorization: Bearer parent-1"]:
		failures.append("account route headers: %s" % str(account))
	for header: String in headers:
		if header.begins_with(ApiScript.PARENT_AUTH_HEADER):
			failures.append("a tutor route must not carry the parent sign-in header (the Worker would refuse it)")
	var codes: Array = [
		[429, {"error": {"code": "quota_exhausted", "reason": "daily_quota", "quota": {}}}, "quota_exhausted"],
		[402, {"error": "quota_exhausted"}, "quota_exhausted"], [403, {}, "not_approved"],
		[403, {"error": {"code": "consent_required", "kind": "ai_tutor"}}, "consent_required"],
		[429, {}, "rate_limited"], [409, {"error": {"code": "session_ended"}}, "session_ended"], [410, {}, "session_ended"],
		[404, {}, "not_found"], [422, {}, "idempotency_mismatch"], [400, {"error": {"code": "invalid_turn"}}, "invalid_turn"],
		[503, {"error": {"code": "provider_unavailable"}}, "provider_unavailable"],
		[500, {}, "provider_unavailable"], [0, {}, "provider_unavailable"], [418, {}, "http_418"],
	]
	for row: Array in codes:
		var got: String = ApiScript.error_code_for(row[0], row[1])
		if got != row[2]:
			failures.append("error_code_for(%d, %s) = %s, expected %s" % [row[0], str(row[1]), got, row[2]])
	# The quota block sits at the top level, or inside `error` on a 429.
	if ApiScript.quota_of({"quota": {"usedSeconds": 1}}) != {"usedSeconds": 1} \
			or ApiScript.quota_of({"error": {"code": "quota_exhausted", "quota": {"usedSeconds": 300}}}) != {"usedSeconds": 300} \
			or not ApiScript.quota_of({"error": {"code": "x"}}).is_empty():
		failures.append("quota_of reads both places")
	# lessonContext: only the Worker's keys leave; outcome is forced into its enum.
	var context: Dictionary = ApiScript.sanitize_lesson_context({"stepId": "s02_cat", "outcome": "retry", "phase": "answer",
		"progress": {"x": 1}, "expectedAnswers": ["cat", 3, "kitty"], "matched": "cat", "lessonAction": "next_question"})
	if context != {"stepId": "s02_cat", "outcome": "unclear", "expectedAnswers": ["cat", "kitty"], "matched": "cat", "lessonAction": "next_question"}:
		failures.append("sanitize_lesson_context: %s" % str(context))
	if ApiScript.parse_url("http://127.0.0.1:8787") != {"host": "127.0.0.1", "port": 8787, "tls": false, "prefix": ""}:
		failures.append("parse_url loopback")
	if ApiScript.parse_url("https://tutor.example/api/") != {"host": "tutor.example", "port": 443, "tls": true, "prefix": "/api"}:
		failures.append("parse_url https prefix")
	if not ApiScript.parse_url("ftp://x").is_empty():
		failures.append("parse_url rejects ftp")
	# Flag off: refused before any client is built.
	var api: RefCounted = ApiScript.new()
	api.configure("client-1", "approval-2")
	var results: Array = []
	api.completed.connect(func(kind: String, result: Dictionary) -> void: results.append([kind, String(result["code"])]))
	if api.is_available():
		failures.append("the REST client is unavailable while the flag is off")
	if api.create_session("animals_cat_dog"):
		failures.append("create_session must refuse with the flag off")
	api.advance(0.1)
	if results != [["session", "cloud_disabled"]]:
		failures.append("the refusal is reported once as cloud_disabled: %s" % str(results))
	if api.has_request_in_flight():
		failures.append("nothing may be in flight with the flag off")
	for entry: Dictionary in api.request_log():
		if entry.has("path"):
			failures.append("a request was built with the flag off: %s" % str(entry))
	# The development-Worker hatch needs the environment variable and https; a
	# suite run without LD_TUTOR_DEV_URL cannot arm it for any address.
	if OS.get_environment(ApiScript.DEV_URL_ENV).is_empty() and api.enable_dev_api_for_tests("https://tutor.example"):
		failures.append("enable_dev_api_for_tests must refuse without LD_TUTOR_DEV_URL")
	if api.enable_dev_api_for_tests("http://127.0.0.1:1"):
		failures.append("enable_dev_api_for_tests must refuse a plain http address")
	return failures


# -- transport ----------------------------------------------------------------------------------

func _fixture() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _sink_transport() -> Dictionary:
	var transport: RefCounted = TransportScript.new()
	var tap := Tap.new()
	tap.attach(transport)
	if not transport.attach_test_sink(tap.sink):
		return {}
	return {"transport": transport, "tap": tap}


func _feed(transport: RefCounted, events: Array) -> void:
	for event: Variant in events:
		transport.handle_event(event)


func _test_transport_token_shapes():
	var failures: Array = []
	var fixture: Dictionary = _fixture()
	if fixture.is_empty():
		return ["fixture %s missing or invalid" % FIXTURE]
	var contract: Dictionary = TransportScript.normalise_token(fixture["token"])
	if String(contract["token"]) != "mock-rt-fixture" or not String(contract["url"]).begins_with("ws://127.0.0.1"):
		failures.append("contract token normalised: %s" % str(contract))
	if int(contract["expiresUnix"]) != int(Time.get_unix_time_from_datetime_string("2026-09-21T23:59:00")):
		failures.append("ISO expiresAt -> unix: %d" % int(contract["expiresUnix"]))
	if contract["subprotocols"] != ["realtime", "mock-token.mock-rt-fixture"]:
		failures.append("subprotocols pass through: %s" % str(contract["subprotocols"]))
	var legacy: Dictionary = TransportScript.normalise_token({"clientSecret": {"value": "ek_x", "expiresAt": 1756310470}, "wsUrl": "wss://h/v1", "headers": ["X: y"]})
	if String(legacy["token"]) != "ek_x" or String(legacy["url"]) != "wss://h/v1" or int(legacy["expiresUnix"]) != 1756310470 or legacy["headers"] != ["X: y"]:
		failures.append("legacy token normalised: %s" % str(legacy))
	if TransportScript.expires_unix("1700000000") != 1700000000 or TransportScript.expires_unix(1700000000123.0) != 1700000000 or TransportScript.expires_unix(null) != 0:
		failures.append("expires_unix number forms")
	if TransportScript._host_of("ws://127.0.0.1:8787/v1/realtime?model=x") != "127.0.0.1" or TransportScript._host_of("wss://h.example/v1") != "h.example":
		failures.append("_host_of")
	# The flag-off refusal holds for a test-armed transport pointed away from loopback.
	var transport: RefCounted = TransportScript.new()
	var errors: Array = []
	transport.error.connect(func(c: String, _m: String) -> void: errors.append(c))
	if transport.enable_for_tests() and transport.connect_session({"token": "t", "url": "wss://example.invalid/v1"}):
		failures.append("a test-armed transport must not dial a non-loopback host")
	if errors != ["bad_token"]:
		failures.append("non-loopback refusal reason: %s" % str(errors))
	return failures


func _test_transport_happy_reply():
	var failures: Array = []
	var scenario: Dictionary = _fixture()["scenarios"]["happy_tools_then_speech"]
	var h: Dictionary = _sink_transport()
	if h.is_empty():
		return ["attach_test_sink refused on a desktop run"]
	var transport: RefCounted = h["transport"]
	var tap: Tap = h["tap"]
	var events: Array = scenario["events"]
	_feed(transport, [events[0]])
	if tap.connected != 1 or not transport.is_connected_session():
		failures.append("session.created -> connected")
	if not transport.send_text("cat", scenario["lessonContext"]):
		failures.append("send_text on an open transport")
	if tap.sent_types() != ["conversation.item.create", "response.create"]:
		failures.append("send_text sends item.create + response.create: %s" % str(tap.sent_types()))
	var sent_before: int = tap.sent.size()
	# Everything up to and including the first response.done (function calls only).
	var first_done: int = 7
	_feed(transport, events.slice(1, first_done + 1))
	if tap.tools != [["show_card", {"assetId": "cat"}], ["gesture", {"name": "clap"}]]:
		failures.append("validated tool calls: %s" % str(tap.tools))
	var after: Array = tap.sent_types().slice(sent_before)
	if after != scenario["expect"]["sentTypesAfterFirstDone"]:
		failures.append("a function-call-only response gets outputs + response.create: %s" % str(after))
	if not transport.is_responding() or not tap.done.is_empty():
		failures.append("the turn is still open after the tool round")
	_feed(transport, events.slice(first_done + 1))
	if tap.done.size() != 1:
		return failures + ["exactly one response_done, got %d" % tap.done.size()]
	if tap.done[0] != scenario["expect"]["turn"]:
		failures.append("validated turn with the tool card and gesture: %s" % str(tap.done[0]))
	if tap.chunks != int(scenario["expect"]["audioChunks"]) or tap.levels.size() != tap.chunks:
		failures.append("audio chunks %d / levels %d" % [tap.chunks, tap.levels.size()])
	for level: float in tap.levels:
		if level <= 0.05 or level > 1.0:
			failures.append("tone chunk RMS is a real envelope, got %f" % level)
			break
	if "".join(tap.deltas) != "Great! It's a cat!":
		failures.append("subtitle deltas: %s" % str(tap.deltas))
	var usage: Dictionary = transport.usage()
	if int(usage["tokensIn"]) != int(scenario["expect"]["tokensIn"]) or int(usage["tokensOut"]) != int(scenario["expect"]["tokensOut"]) or int(usage["responses"]) != 2:
		failures.append("usage summed over both responses: %s" % str(usage))
	if absf(float(usage["audioSecondsOut"]) - 0.03) > 0.001:
		failures.append("3 x 10 ms of audio = 0.03 s out, got %s" % str(usage["audioSecondsOut"]))
	if transport.is_responding():
		failures.append("the turn closed at response.done")
	# Mic frames are counted as input audio seconds, never logged in full.
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(4800)
	transport.send_audio(pcm)
	if absf(float(transport.usage()["audioSecondsIn"]) - 0.1) > 0.001:
		failures.append("100 ms of mic audio counted: %s" % str(transport.usage()))
	if tap.sent[-1].get("type", "") != "input_audio_buffer.append" or not tap.sent[-1].has("audio"):
		failures.append("mic frames go out as input_audio_buffer.append")
	if transport.sent_events()[-1] != {"type": "input_audio_buffer.append", "bytes": 4800}:
		failures.append("the sent log keeps only the byte count of audio: %s" % str(transport.sent_events()[-1]))
	return failures


func _test_transport_cancel():
	var failures: Array = []
	var scenario: Dictionary = _fixture()["scenarios"]["cancel_mid_stream"]
	var h: Dictionary = _sink_transport()
	var transport: RefCounted = h["transport"]
	var tap: Tap = h["tap"]
	transport.handle_event({"type": "session.created", "session": {"id": "x"}})
	var played: Array = [0.0]
	transport.set_played_ms_source(func() -> float: return played[0])
	transport.send_text("dog", scenario["lessonContext"])
	_feed(transport, scenario["events"])
	if tap.deltas != ["Great!"] or tap.chunks != 1:
		failures.append("the first delta and chunk streamed")
	played[0] = 7.0
	transport.cancel()
	transport.cancel()
	if tap.cancelled != 1 or transport.is_responding():
		failures.append("cancel emits response_cancelled once and closes the turn")
	var types: Array = tap.sent_types()
	if types.slice(2) != ["response.cancel", "conversation.item.truncate"]:
		failures.append("cancel sends response.cancel + truncate: %s" % str(types))
	var truncate: Dictionary = tap.sent[-1]
	if String(truncate.get("item_id", "")) != "item_m_9" or int(truncate.get("audio_end_ms", -1)) != 7 or int(truncate.get("content_index", -1)) != 0:
		failures.append("truncate names the item and the PLAYED position: %s" % str(truncate))
	_feed(transport, scenario["afterCancel"])
	if tap.deltas != ["Great!"] or tap.cancelled != 1 or not tap.done.is_empty():
		failures.append("late deltas and the cancelled done are ignored: deltas=%s cancelled=%d done=%d" % [str(tap.deltas), tap.cancelled, tap.done.size()])
	if int(transport.usage()["tokensIn"]) != 10:
		failures.append("the cancelled response's usage is still counted")
	# A new turn right after the cancel is untouched by the old response's events.
	transport.send_text("a dog", scenario["lessonContext"])
	transport.handle_event({"type": "response.output_audio_transcript.delta", "response_id": "resp_9", "delta": "ghost"})
	transport.handle_event({"type": "response.done", "response": {"id": "resp_9", "status": "cancelled"}})
	if not transport.is_responding() or tap.deltas != ["Great!"]:
		failures.append("the old response cannot reach the new turn")
	return failures


func _test_transport_off_allowlist_and_errors():
	var failures: Array = []
	var scenarios: Dictionary = _fixture()["scenarios"]
	var h: Dictionary = _sink_transport()
	var transport: RefCounted = h["transport"]
	var tap: Tap = h["tap"]
	transport.handle_event({"type": "session.created", "session": {"id": "x"}})
	var off: Dictionary = scenarios["off_allowlist_tool_is_dropped"]
	transport.send_text("meow", off["lessonContext"])
	_feed(transport, off["events"])
	if not tap.tools.is_empty():
		failures.append("off-allowlist tool arguments never surface: %s" % str(tap.tools))
	if tap.done.size() != 1 or tap.done[0] != off["expect"]["turn"]:
		failures.append("the words still carry the turn: %s" % str(tap.done))
	# A tool round that never spoke: outputs are returned once, never twice.
	transport.send_text("x", {"lessonAction": "retry"})
	var before: int = tap.sent.size()
	for _round: int in range(2):
		transport.handle_event({"type": "response.output_item.added", "item": {"id": "fc", "type": "function_call", "name": "gesture", "call_id": "c"}})
		transport.handle_event({"type": "response.function_call_arguments.done", "item_id": "fc", "call_id": "c", "name": "gesture", "arguments": "{\"name\":\"nod\"}"})
		transport.handle_event({"type": "response.done", "response": {"id": "r", "status": "completed"}})
	var rounds: Array = tap.sent_types().slice(before)
	if rounds.count("response.create") != 1 or tap.done.size() != 2:
		failures.append("at most one tool round per turn, then the turn closes: %s" % str(rounds))
	if tap.done[1] != TurnValidator.fallback_turn():
		failures.append("a wordless reply becomes the fallback turn: %s" % str(tap.done[1]))
	# Error event.
	_feed(transport, scenarios["server_error_event"]["events"])
	if tap.errors != ["server_error"]:
		failures.append("error event -> error signal: %s" % str(tap.errors))
	# Input transcript events.
	_feed(transport, scenarios["audio_input_round_trip"]["events"])
	if tap.transcripts != ["cat"] or tap.speech_starts != 1:
		failures.append("input transcript + server speech start surfaced: %s / %d" % [str(tap.transcripts), tap.speech_starts])
	# A failed response status is an error, not a turn.
	transport.send_text("y", {})
	transport.handle_event({"type": "response.done", "response": {"id": "f", "status": "failed", "status_details": {"error": {"message": "boom"}}}})
	if tap.errors != ["server_error", "response_failed"] or transport.is_responding():
		failures.append("a failed response surfaces as an error: %s" % str(tap.errors))
	return failures


# -- audio player ------------------------------------------------------------------------------

func _test_player_clock():
	var failures: Array = []
	var player: Node = PlayerScript.new()
	player.set_device_enabled(false)
	var levels: Array = []
	var drained: Array = []
	player.level_changed.connect(func(l: float) -> void: levels.append(l))
	player.drained.connect(func() -> void: drained.append(true))
	var tone: PackedByteArray = Marshalls.base64_to_raw(String(_fixture()["scenarios"]["cancel_mid_stream"]["events"][3]["delta"]))
	if tone.size() != 480:
		failures.append("fixture tone is 240 frames, got %d bytes" % tone.size())
	player.begin_reply()
	player.push_pcm16(tone)
	player.push_pcm16(tone)
	if absf(player.queued_ms() - 20.0) > 0.01 or not player.is_playing_audio():
		failures.append("20 ms queued")
	player.advance(0.005)
	if absf(player.played_ms() - 5.0) > 0.05 or levels.is_empty() or float(levels[-1]) <= 0.0:
		failures.append("5 ms played with a level: %f / %s" % [player.played_ms(), str(levels)])
	player.advance(0.005)
	player.mark_complete()
	player.advance(0.5)
	if absf(player.played_ms() - 20.0) > 0.05 or drained.size() != 1 or player.is_playing_audio():
		failures.append("played to the end and drained once: %f / %d" % [player.played_ms(), drained.size()])
	player.begin_reply()
	player.push_pcm16(tone)
	player.advance(0.002)
	player.truncate()
	if player.has_audio() or player.is_playing_audio() or float(levels[-1]) != 0.0:
		failures.append("truncate drops the rest and closes the mouth")
	player.advance(1.0)
	if drained.size() != 1:
		failures.append("a truncated reply does not drain again")
	player.free()
	return failures


# -- session ------------------------------------------------------------------------------------------

func _session_harness(api: FakeApi = null, with_player: bool = true) -> Dictionary:
	var fake: FakeApi = api if api != null else FakeApi.new()
	var h: Dictionary = _sink_transport()
	var transport: RefCounted = h["transport"]
	var tap: Tap = h["tap"]
	var session: RefCounted = SessionScript.new()
	session.set_api(fake)
	session.set_transport(transport)
	var player: Node = null
	if with_player:
		player = PlayerScript.new()
		player.set_device_enabled(false)
		session.set_audio_player(player)
	var face := FakeFace.new()
	session.set_face(face)
	var quota := FakeQuota.new()
	session.set_quota(quota)
	var capture: Array = [true]
	session.set_capture_source(func() -> bool: return capture[0])
	session.configure("animals_cat_dog")
	var events: Dictionary = {"ready": [], "ended": [], "fell_back": [], "turns": [], "failed": [], "replaced": [], "speaking": [], "subtitles": [], "tools": [], "quota": [], "cancelled": 0}
	session.ready.connect(func(i: Dictionary) -> void: events["ready"].append(i))
	session.ended.connect(func(r: String, s: Dictionary) -> void: events["ended"].append([r, s]))
	session.fell_back.connect(func(r: String) -> void: events["fell_back"].append(r))
	session.turn_ready.connect(func(t: Dictionary) -> void: events["turns"].append(t))
	session.turn_failed.connect(func(r: String) -> void: events["failed"].append(r))
	session.reply_replaced.connect(func(t: Dictionary) -> void: events["replaced"].append(t))
	session.speaking_changed.connect(func(a: bool) -> void: events["speaking"].append(a))
	session.subtitle_changed.connect(func(t: String) -> void: events["subtitles"].append(t))
	session.tool_applied.connect(func(n: String, a: Dictionary) -> void: events["tools"].append([n, a]))
	session.quota_updated.connect(func(q: Dictionary) -> void: events["quota"].append(q))
	session.cancelled.connect(func() -> void: events["cancelled"] += 1)
	return {"api": fake, "transport": transport, "tap": tap, "session": session, "player": player, "face": face,
		"quota": quota, "capture": capture, "events": events}


func _free_session(h: Dictionary) -> void:
	if h.get("player", null) != null:
		(h["player"] as Node).free()


## Drives start() through quota/session/token to READY (the sink transport
## "connects" when the fixture's session.created is fed).
func _bring_up(h: Dictionary) -> bool:
	var session: RefCounted = h["session"]
	if not session.start():
		return false
	for _i: int in range(6):
		session.advance(0.05)
	if session.get_state() != SessionScript.STATE_CONNECTING:
		return false
	(h["transport"] as RefCounted).handle_event({"type": "session.created", "session": {"id": "rt"}})
	return session.is_ready()


func _test_session_lifecycle():
	var failures: Array = []
	var api := FakeApi.new()
	api.replies = {
		"quota": [FakeApi.ok({"allowanceSeconds": 300, "usedSeconds": 12, "resetAtUtc": "2026-09-22T00:00:00.000Z"})],
		"session": [FakeApi.ok({"sessionId": "s-1", "quota": {"allowanceSeconds": 300, "usedSeconds": 12}, "entitlement": "free"})],
		"token": [FakeApi.ok(_fixture()["token"])],
		"end": [FakeApi.ok({"ok": true, "quota": {"allowanceSeconds": 300, "usedSeconds": 40}})],
	}
	var h: Dictionary = _session_harness(api)
	var session: RefCounted = h["session"]
	var events: Dictionary = h["events"]
	var tap: Tap = h["tap"]
	if session.is_streaming_allowed() or session.push_audio(PackedByteArray([1, 2])):
		failures.append("nothing streams before ready")
	if not _bring_up(h):
		_free_session(h)
		return ["session did not come up: state=%s history=%s" % [session.get_state(), str(session.state_history())]]
	if session.state_history() != ["quota", "creating", "minting", "connecting", "ready"]:
		failures.append("state order: %s" % str(session.state_history()))
	var kinds: Array = []
	for call: Dictionary in api.calls:
		kinds.append(call["kind"])
	if kinds != ["quota", "session", "token"]:
		failures.append("REST order quota -> session -> token: %s" % str(kinds))
	if String(api.calls[1]["body"]["lessonId"]) != "animals_cat_dog" or api.calls[1]["body"].has("mode") \
			or String(api.calls[2]["body"]["sessionId"]) != "s-1":
		failures.append("session body {lessonId} / token body {sessionId}: %s" % str(api.calls))
	if events["ready"].size() != 1 or String(events["ready"][0]["sessionId"]) != "s-1" or String(events["ready"][0]["entitlement"]) != "free":
		failures.append("ready carries the session and entitlement: %s" % str(events["ready"]))
	if events["quota"].size() < 2 or float(events["quota"][0]["remainingSeconds"]) != 288.0:
		failures.append("server quota mirrored as allowance - used: %s" % str(events["quota"]))
	if (h["quota"] as FakeQuota).blocks.is_empty() or float((h["quota"] as FakeQuota).blocks[0]["dailyAllowanceSeconds"]) != 300.0:
		failures.append("TutorQuota gets the block under its own key names: %s" % str((h["quota"] as FakeQuota).blocks))
	# Mic frames: gated by the capture source and by mute.
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(960)
	if not session.push_audio(pcm) or tap.sent_types()[-1] != "input_audio_buffer.append":
		failures.append("frames stream while capturing")
	h["capture"][0] = false
	var sent_count: int = tap.sent.size()
	if session.push_audio(pcm) or tap.sent.size() != sent_count:
		failures.append("frames never stream while the hands-free session is not capturing / gated")
	h["capture"][0] = true
	session.mute(true)
	if session.push_audio(pcm):
		failures.append("frames never stream while muted")
	session.mute(false)
	# A reply: text deltas -> subtitle; audio -> speaking + mouth; done -> turn; drained -> speaking false.
	var scenario: Dictionary = _fixture()["scenarios"]["happy_tools_then_speech"]
	if not session.send_transcript("cat", scenario["lessonContext"]):
		failures.append("send_transcript while ready")
	if not session.is_reply_open():
		failures.append("a reply is open after send_transcript")
	_feed(h["transport"], (scenario["events"] as Array).slice(1))
	if events["tools"] != [["show_card", {"assetId": "cat"}], ["gesture", {"name": "clap"}]]:
		failures.append("tool calls applied: %s" % str(events["tools"]))
	if not (h["face"] as FakeFace).calls.has("gesture:clap"):
		failures.append("the gesture tool reaches TutorFace.play_gesture: %s" % str((h["face"] as FakeFace).calls))
	if events["subtitles"].is_empty() or String(events["subtitles"][-1]) != "Great! It's a cat!":
		failures.append("subtitle grows to the final line: %s" % str(events["subtitles"]))
	if events["turns"].size() != 1 or events["turns"][0] != scenario["expect"]["turn"]:
		failures.append("one validated turn: %s" % str(events["turns"]))
	if events["speaking"] != [true] or not session.is_speaking():
		failures.append("speaking while the audio is still playing: %s" % str(events["speaking"]))
	if not session.is_reply_open() or not session.is_reply_done():
		failures.append("the reply stays open until the audio drained")
	session.advance(0.05)  # 30 ms of audio + drain
	if events["speaking"] != [true, false] or session.is_reply_open():
		failures.append("speaking ends when the player drained: %s open=%s" % [str(events["speaking"]), str(session.is_reply_open())])
	var mouth: Array = (h["face"] as FakeFace).mouth
	if mouth.is_empty() or float(mouth.max()) <= 0.05 or float(mouth[-1]) != 0.0:
		failures.append("the mouth followed the played level and closed: %s" % str(mouth))
	if not (h["face"] as FakeFace).calls.has("speaking:true") or not (h["face"] as FakeFace).calls.has("speaking:false"):
		failures.append("TutorFace.set_speaking bracketed the reply: %s" % str((h["face"] as FakeFace).calls))
	# Barge-in on a fresh reply.
	session.send_transcript("dog", scenario["lessonContext"])
	(h["transport"] as RefCounted).handle_event({"type": "response.output_item.added", "item": {"id": "m", "type": "message"}})
	(h["transport"] as RefCounted).handle_event({"type": "response.output_audio_transcript.delta", "delta": "Great"})
	session.barge_in()
	if events["cancelled"] != 1 or session.is_reply_open() or tap.sent_types()[-2] != "response.cancel":
		failures.append("barge-in cancels the reply: cancelled=%d sent=%s" % [events["cancelled"], str(tap.sent_types().slice(-3))])
	# End: the server is told the reason, the seconds and the usage.
	session.advance(1.0)
	session.parent_stop()
	session.advance(0.05)
	if events["ended"].size() != 1 or String(events["ended"][0][0]) != "parent_stop":
		failures.append("ended once with the reason: %s" % str(events["ended"]))
	var end_call: Dictionary = api.calls[-1]
	if String(end_call["kind"]) != "end" or String(end_call["body"]["reason"]) != "parent_stop" or end_call["body"].has("secondsUsed"):
		failures.append("POST end carries {reason} only (the server clock is the authority): %s" % str(end_call))
	if api.calls_of("end").size() != 1:
		failures.append("/end is posted exactly once")
	var usage: Dictionary = session.usage()
	if int(usage["tokensIn"]) != 105 or int(usage["tokensOut"]) != 44 or float(usage["audioSeconds"]) < 0.04:
		failures.append("usage metered client-side: %s" % str(usage))
	if float(session.last_summary()["quota"]["usedSeconds"]) != 40.0:
		failures.append("the end reply's quota is kept for the break card: %s" % str(session.last_summary()))
	if not transport_closed(h["transport"]):
		failures.append("the socket is closed at end")
	if session.push_audio(pcm) or session.send_transcript("x", {}):
		failures.append("nothing streams after end")
	_free_session(h)
	return failures


static func transport_closed(transport: RefCounted) -> bool:
	return not transport.is_connected_session()


func _test_session_safety_and_quota():
	var failures: Array = []
	# Banned word mid-stream: cancel, truncate, replace.
	var api := FakeApi.new()
	api.replies = {"session": [FakeApi.ok({"sessionId": "s-2", "quota": {"allowanceSeconds": 300, "usedSeconds": 0}})], "token": [FakeApi.ok(_fixture()["token"])]}
	var h: Dictionary = _session_harness(api)
	var session: RefCounted = h["session"]
	var events: Dictionary = h["events"]
	var tap: Tap = h["tap"]
	if not _bring_up(h):
		_free_session(h)
		return ["safety: session did not come up"]
	var banned: Dictionary = _fixture()["scenarios"]["banned_word_is_replaced"]
	session.send_transcript("cat", banned["lessonContext"])
	_feed(h["transport"], banned["events"])
	if events["replaced"].size() != 1 or events["replaced"][0] != TurnValidator.fallback_turn():
		failures.append("a banned word replaces the reply with the fallback: %s" % str(events["replaced"]))
	if not tap.sent_types().has("response.cancel") or session.is_reply_open() or (h["transport"] as RefCounted).is_responding():
		failures.append("the reply was cancelled at the offending delta")
	if events["subtitles"].size() != 1 or String(events["subtitles"][0]) != "That was a":
		failures.append("the offending words never reached the subtitle: %s" % str(events["subtitles"]))
	if not events["turns"].is_empty():
		failures.append("no turn is emitted for a replaced reply")
	# The client mirror is authoritative for the safe-point closing.
	var scenario: Dictionary = _fixture()["scenarios"]["happy_tools_then_speech"]
	session.send_transcript("cat", scenario["lessonContext"])
	(h["quota"] as FakeQuota).exhausted = true
	session.advance(0.01)
	if not session.is_ready() or not session.ends_at_boundary():
		failures.append("mirror exhaustion arms the boundary without cutting the reply")
	_feed(h["transport"], (scenario["events"] as Array).slice(1))
	session.advance(0.05)
	session.advance(0.05)
	if events["turns"].size() != 1 or events["ended"].size() != 1 or String(events["ended"][0][0]) != "quota_expired":
		failures.append("the reply finished, then the session ended for quota: turns=%d ended=%s" % [events["turns"].size(), str(events["ended"])])
	_free_session(h)
	# Server 402 on the session call: fall back and mark the mirror exhausted.
	api = FakeApi.new()
	api.replies = {"session": [FakeApi.err(429, "quota_exhausted", {"error": {"code": "quota_exhausted", "reason": "daily_quota", "quota": {"dailyAllowanceSeconds": 300, "usedSeconds": 300, "remainingSeconds": 0}}})]}
	h = _session_harness(api)
	session = h["session"]
	events = h["events"]
	session.start()
	for _i: int in range(4):
		session.advance(0.05)
	if events["fell_back"] != ["quota_exhausted"] or session.get_state() != SessionScript.STATE_ENDED:
		failures.append("429 quota_exhausted -> fell_back quota_exhausted + ended: %s / %s" % [str(events["fell_back"]), session.get_state()])
	if not (h["quota"] as FakeQuota).exhausted:
		failures.append("the mirror learns the server's 429")
	for call: Dictionary in api.calls:
		if String(call["kind"]) == "token":
			failures.append("no token is minted after a 429")
	_free_session(h)
	# Zero remaining on GET /quota: no session is even created.
	api = FakeApi.new()
	api.replies = {"quota": [FakeApi.ok({"allowanceSeconds": 300, "usedSeconds": 300})]}
	h = _session_harness(api)
	session = h["session"]
	session.start()
	session.advance(0.05)
	session.advance(0.05)
	if h["events"]["fell_back"] != ["quota_exhausted"] or api.calls.size() != 1:
		failures.append("an exhausted GET /quota stops before POST /sessions: %s calls=%d" % [str(h["events"]["fell_back"]), api.calls.size()])
	_free_session(h)
	return failures


func _test_session_failures():
	var failures: Array = []
	# A transport error while a reply is open: one reconnect with a fresh
	# token (the lost turn reported), then a second failure falls back.
	var api := FakeApi.new()
	api.replies = {
		"session": [FakeApi.ok({"sessionId": "s-3", "quota": {"allowanceSeconds": 300, "usedSeconds": 0}})],
		"token": [FakeApi.ok(_fixture()["token"]), FakeApi.ok(_fixture()["token"])],
	}
	var h: Dictionary = _session_harness(api)
	var session: RefCounted = h["session"]
	var events: Dictionary = h["events"]
	if not _bring_up(h):
		_free_session(h)
		return ["failures: session did not come up"]
	session.send_transcript("cat", {"lessonAction": "next_question"})
	(h["transport"] as RefCounted).handle_event({"type": "error", "error": {"code": "server_error", "message": "outage"}})
	if events["failed"] != ["server_error"] or session.get_state() != SessionScript.STATE_MINTING or session.reconnect_count() != 1:
		failures.append("first failure: turn_failed + one reconnect: %s state=%s" % [str(events["failed"]), session.get_state()])
	for _i: int in range(14):
		session.advance(0.05)  # past RETRY_DELAY_SECONDS, the fresh token, dialling
	if session.get_state() != SessionScript.STATE_CONNECTING:
		failures.append("the fresh token is minted and dialled: %s" % str(session.state_history()))
	(h["transport"] as RefCounted).handle_event({"type": "session.created", "session": {"id": "rt"}})
	if not session.is_ready() or events["ready"].size() != 2 or int(events["ready"][1]["reconnects"]) != 1:
		failures.append("ready after the reconnect: %s" % str(events["ready"]))
	session.send_transcript("cat", {"lessonAction": "next_question"})
	(h["transport"] as RefCounted).handle_event({"type": "error", "error": {"code": "server_error", "message": "outage"}})
	session.advance(0.05)
	if events["failed"] != ["server_error", "server_error"] or events["fell_back"] != ["server_error"]:
		failures.append("second failure: turn_failed + fell_back: %s / %s" % [str(events["failed"]), str(events["fell_back"])])
	if events["ended"].size() != 1 or not String(events["ended"][0][0]).begins_with("provider_failed"):
		failures.append("the server is told the session failed: %s" % str(events["ended"]))
	if not transport_closed(h["transport"]):
		failures.append("the socket is closed on fallback")
	_free_session(h)
	# Idle ends the session.
	api = FakeApi.new()
	api.replies = {"session": [FakeApi.ok({"sessionId": "s-4", "quota": {"allowanceSeconds": 300, "usedSeconds": 0}})], "token": [FakeApi.ok(_fixture()["token"])]}
	h = _session_harness(api)
	session = h["session"]
	events = h["events"]
	if not _bring_up(h):
		_free_session(h)
		return failures + ["idle: session did not come up"]
	for _i: int in range(int(SessionScript.IDLE_SECONDS) + 2):
		session.advance(1.0)
	if events["ended"].size() != 1 or String(events["ended"][0][0]) != "idle":
		failures.append("idle ends the session: %s" % str(events["ended"]))
	_free_session(h)
	# Background ends the session at once; a token past its expiry ends at the boundary.
	api = FakeApi.new()
	api.replies = {"session": [FakeApi.ok({"sessionId": "s-5", "quota": {"allowanceSeconds": 300, "usedSeconds": 0}})], "token": [FakeApi.ok(_fixture()["token"])]}
	h = _session_harness(api)
	session = h["session"]
	events = h["events"]
	_bring_up(h)
	session.on_app_background()
	session.advance(0.05)
	if events["ended"].size() != 1 or String(events["ended"][0][0]) != "background":
		failures.append("background ends the session: %s" % str(events["ended"]))
	_free_session(h)
	api = FakeApi.new()
	api.replies = {"session": [FakeApi.ok({"sessionId": "s-6", "quota": {"allowanceSeconds": 300, "usedSeconds": 0}})], "token": [FakeApi.ok(_fixture()["token"])]}
	h = _session_harness(api)
	session = h["session"]
	events = h["events"]
	var clock: Array = [0]
	session.set_clock(func() -> int: return clock[0])
	_bring_up(h)
	clock[0] = int(Time.get_unix_time_from_datetime_string("2026-09-21T23:59:00")) + 1
	session.advance(0.05)
	session.advance(0.05)  # the fake API delivers the end ack on the next pump
	if events["ended"].size() != 1 or String(events["ended"][0][0]) != "token_expired":
		failures.append("an expired token ends the session at the boundary: %s" % str(events["ended"]))
	_free_session(h)
	# Rate limited once: retried after retryAfterSeconds.
	api = FakeApi.new()
	var limited: Dictionary = FakeApi.err(429, "rate_limited")
	limited["retryAfterSeconds"] = 0.2
	api.replies = {"session": [limited, FakeApi.ok({"sessionId": "s-7", "quota": {}})], "token": [FakeApi.ok(_fixture()["token"])]}
	h = _session_harness(api)
	session = h["session"]
	session.start()
	for _i: int in range(8):
		session.advance(0.05)
	if session.get_state() != SessionScript.STATE_CONNECTING:
		failures.append("429 on /sessions is retried once: %s" % str(session.state_history()))
	_free_session(h)
	return failures


## The deployed Worker has no realtime provider: the token endpoint answers
## 503 and the session runs on REST turns. The server's validated TutorTurn
## drives the classroom; a transient failure is retried once with the SAME
## Idempotency-Key; `endAtBoundary` ends the session after the reply and
## nothing further is sent; `/end` leaves once; a lesson switch restarts.
func _test_session_turns_path():
	var failures: Array = []
	var turn: Dictionary = {"speech": "Yes! Red!", "subtitle": "Yes! Red!", "emotion": "happy", "gesture": "clap",
		"visual": {"type": "flashcard", "assetId": "color_red"}, "lessonAction": "next_question"}
	var quota_block: Dictionary = {"entitlement": "free", "dailyAllowanceSeconds": 300, "usedSeconds": 45, "remainingSeconds": 255, "dailyTurnAllowance": 60, "usedTurns": 1}
	var api := FakeApi.new()
	api.approval = false  # no token held: the DEV sign-in mints one first
	api.replies = {
		"session": [FakeApi.ok({"sessionId": "s-t", "quota": {"dailyAllowanceSeconds": 300, "usedSeconds": 0, "remainingSeconds": 300}, "entitlement": "free"})],
		"token": [FakeApi.err(503, "provider_unavailable", {"error": {"code": "provider_unavailable", "message": "Realtime tutoring is not configured on this server."}})],
		"turn": [
			FakeApi.ok({"turn": turn, "quota": quota_block, "endAtBoundary": false, "turnIndex": 1, "chargedSeconds": 2.5, "provider": "mock", "fallback": null}),
			FakeApi.err(503, "provider_unavailable"),
			FakeApi.ok({"turn": turn, "quota": quota_block, "endAtBoundary": false, "turnIndex": 2, "chargedSeconds": 1.0}, true),
			FakeApi.ok({"turn": turn, "quota": {"dailyAllowanceSeconds": 300, "usedSeconds": 300, "remainingSeconds": 0, "usedTurns": 3}, "endAtBoundary": true, "turnIndex": 3}),
		],
		"end": [FakeApi.ok({"sessionId": "s-t", "endedAt": "2026-09-21T10:00:00.000Z", "quota": {"dailyAllowanceSeconds": 300, "usedSeconds": 300, "remainingSeconds": 0}, "usage": {"turns": 3}})],
	}
	var h: Dictionary = _session_harness(api)
	var session: RefCounted = h["session"]
	var events: Dictionary = h["events"]
	session.start()
	for _i: int in range(8):
		session.advance(0.05)
	if not session.is_ready() or session.transport_mode() != "turns" or not session.is_turns_mode():
		_free_session(h)
		return ["turns: not ready on the turns path after a 503 token: %s" % str(session.state_history())]
	if session.state_history() != ["signing_in", "consenting", "quota", "creating", "minting", "ready"]:
		failures.append("turns: DEV sign-in, consent, quota, session, token 503 -> ready: %s" % str(session.state_history()))
	if events["ready"].size() != 1 or String(events["ready"][0]["transport"]) != "turns" or String(events["ready"][0]["realtimeFallback"]) != "provider_unavailable":
		failures.append("turns: ready names the transport and why: %s" % str(events["ready"]))
	if session.is_streaming_allowed() or session.push_audio(PackedByteArray([1, 2])):
		failures.append("turns: no microphone frames ever stream on the turns path")
	# Turn 1: the server's validated turn drives the classroom.
	if not session.send_transcript("red", {"stepId": "s02_red", "outcome": "correct", "phase": "answer"}):
		failures.append("turns: send_transcript while ready")
	var sent: Dictionary = api.calls_of("turn")[0]["body"]
	if String(sent["key"]) != "s-t:t1" or sent["lessonContext"].has("phase") or String(sent["lessonContext"]["outcome"]) != "correct":
		failures.append("turns: Idempotency-Key per turn, sanitized lessonContext: %s" % str(sent))
	session.advance(0.05)
	if events["turns"].size() != 1 or events["turns"][0] != TurnValidator.coerce(turn) or events["tools"] != [["show_card", {"assetId": "color_red"}]]:
		failures.append("turns: the server turn + its card reach the classroom: %s / %s" % [str(events["turns"]), str(events["tools"])])
	if events["subtitles"].is_empty() or String(events["subtitles"][-1]) != "Yes! Red!" or session.is_reply_open():
		failures.append("turns: subtitle set, reply closed at once: %s" % str(events["subtitles"]))
	if float(session.server_quota()["usedSeconds"]) != 45.0 or int(session.turn_log()[0]["turnIndex"]) != 1:
		failures.append("turns: the reply's quota block is mirrored: %s" % str(session.server_quota()))
	# Turn 2: a 503 is retried once with the same key; the replay is not a new charge.
	session.send_transcript("red", {"stepId": "s02_red", "outcome": "correct"})
	for _i: int in range(14):
		session.advance(0.05)
	var turn_calls: Array = api.calls_of("turn")
	if turn_calls.size() != 3 or String(turn_calls[1]["body"]["key"]) != "s-t:t2" or String(turn_calls[2]["body"]["key"]) != "s-t:t2":
		failures.append("turns: one retry with the SAME Idempotency-Key: %s" % str(turn_calls))
	if events["turns"].size() != 2 or not events["failed"].is_empty() or not bool(session.turn_log()[1]["replayed"]):
		failures.append("turns: the replayed reply counts once, no turn lost: turns=%d failed=%s log=%s" % [events["turns"].size(), str(events["failed"]), str(session.turn_log())])
	# Barge-in mid-request: the request is dropped, nothing is charged twice.
	session.send_transcript("red", {"stepId": "s02_red", "outcome": "correct"})
	session.barge_in()
	if session.has_turn_in_flight() or events["cancelled"] != 1 or api.cancels != 1:
		failures.append("turns: barge-in drops the in-flight request: cancelled=%d cancels=%d" % [events["cancelled"], api.cancels])
	api.pending.clear()
	# Turn 3 lands on the boundary: the reply plays, then the session ends, nothing more is sent.
	session.send_transcript("red", {"stepId": "s02_red", "outcome": "correct"})
	session.advance(0.05)
	session.advance(0.05)
	if events["turns"].size() != 3 or not (h["quota"] as FakeQuota).exhausted:
		failures.append("turns: endAtBoundary hands the turn over and tells the mirror: turns=%d exhausted=%s" % [events["turns"].size(), str((h["quota"] as FakeQuota).exhausted)])
	if events["ended"].size() != 1 or String(events["ended"][0][0]) != "quota_expired" or session.get_state() != SessionScript.STATE_ENDED:
		failures.append("turns: ended at the boundary for quota: %s state=%s" % [str(events["ended"]), session.get_state()])
	if session.send_transcript("red", {"stepId": "s02_red", "outcome": "correct"}) or api.calls_of("turn").size() != 5:
		failures.append("turns: no further turn after the boundary: %d turn calls" % api.calls_of("turn").size())
	if api.calls_of("end").size() != 1 or String(api.calls_of("end")[0]["body"]["reason"]) != "quota_expired":
		failures.append("turns: /end posted once with the reason: %s" % str(api.calls_of("end")))
	session.end("scene")
	session.advance(0.05)
	if api.calls_of("end").size() != 1:
		failures.append("turns: a second end() posts nothing")
	if float(session.last_summary()["quota"]["usedSeconds"]) != 300.0 or int(session.last_summary()["serverUsage"]["turns"]) != 3:
		failures.append("turns: the end reply's quota + usage kept for the break card: %s" % str(session.last_summary()))
	# A lesson switch: start() again after end; the old session's late ack is ignored.
	api.replies["session"] = [FakeApi.ok({"sessionId": "s-u", "quota": {"dailyAllowanceSeconds": 300, "usedSeconds": 0, "remainingSeconds": 0}})]
	api.replies["token"] = [FakeApi.err(503, "provider_unavailable")]
	(h["quota"] as FakeQuota).exhausted = false
	session.configure("colors_red_blue")
	if not session.start():
		failures.append("turns: start() again after end (lesson switch)")
	for _i: int in range(8):
		session.advance(0.05)
	if session.session_id() != "s-u" or not session.is_ready() or String(api.calls_of("session")[-1]["body"]["lessonId"]) != "colors_red_blue":
		failures.append("turns: the new session is for the new lesson: %s %s" % [session.session_id(), session.get_state()])
	if api.calls_of("signIn").size() != 1:
		failures.append("turns: the approval token is reused, no second sign-in")
	_free_session(h)
	return failures


# -- provider -----------------------------------------------------------------------------------------

func _test_provider_one_turn_per_submit():
	var failures: Array = []
	var api := FakeApi.new()
	api.replies = {"session": [FakeApi.ok({"sessionId": "s-p", "quota": {"allowanceSeconds": 300, "usedSeconds": 0}})], "token": [FakeApi.ok(_fixture()["token"])]}
	var h: Dictionary = _session_harness(api)
	var session: RefCounted = h["session"]
	var engine: RefCounted = LessonEngineScript.new()
	engine.load_lesson("animals_cat_dog")
	var provider: RefCounted = ProviderScript.new()
	provider.set_engine(engine)
	provider.set_cloud_session(session)
	var turns: Array = []
	var fallbacks: Array = []
	var metas: Array = []
	provider.turn_ready.connect(func(t: Dictionary) -> void: turns.append(t))
	provider.fallback_used.connect(func(r: String) -> void: fallbacks.append(r))
	provider.turn_meta.connect(func(m: Dictionary) -> void: metas.append(m))
	# Not ready yet: the answer is scripted, exactly once.
	provider.begin_session("animals_cat_dog")
	engine.advance()  # -> s02_cat (ask)
	provider.submit_turn("cat", {"phase": "answer"})
	if turns.size() != 1 or fallbacks != ["cloud_not_ready"] or String(turns[0]["emotion"]) != "happy":
		failures.append("before ready: one scripted turn, announced: %s / %s" % [str(fallbacks), str(turns)])
	# Bring the cloud up (the provider started it).
	for _i: int in range(6):
		provider.advance(0.05)
	(h["transport"] as RefCounted).handle_event({"type": "session.created", "session": {"id": "rt"}})
	if not provider.is_available():
		failures.append("provider available once the session is ready: %s" % str(session.state_history()))
	# Open turns are local: no cloud call.
	var sent_before: int = (h["tap"] as Tap).sent.size()
	provider.submit_turn("", {"phase": "open"})
	if turns.size() != 2 or (h["tap"] as Tap).sent.size() != sent_before:
		failures.append("open turns never go to the cloud")
	# An answer: early turn on the first delta, final in turn_meta, exactly one turn_ready.
	engine.evaluate("cat")  # the engine judged already once above; reset attempts by re-asking
	var scenario: Dictionary = _fixture()["scenarios"]["happy_tools_then_speech"]
	provider.submit_turn("cat", {"phase": "answer"})
	var sent: Array = (h["tap"] as Tap).sent
	if sent.size() < 2:
		_free_session(h)
		return failures + ["the transcript never left: sent=%s state=%s ready=%s fallbacks=%s log=%s" % [str(sent), session.get_state(), str(session.is_ready()), str(fallbacks), str(provider.turn_log())]]
	var item: Dictionary = sent[-2]
	if String(item.get("type", "")) != "conversation.item.create" or String(((item["item"]["content"] as Array)[0] as Dictionary)["text"]) != "cat":
		failures.append("the transcript went to the cloud as input_text: %s" % str(item))
	if turns.size() != 2:
		failures.append("no turn before the first delta")
	# The scene re-asks every frame while it waits: no second request, no second judgement.
	var sent_pending: int = (h["tap"] as Tap).sent.size()
	provider.submit_turn("cat", {"phase": "answer"})
	provider.submit_turn("cat", {"phase": "answer"})
	if (h["tap"] as Tap).sent.size() != sent_pending or turns.size() != 2 or fallbacks.size() != 1:
		failures.append("a repeated request while the reply streams is ignored: sent=%d turns=%d fallbacks=%s" % [(h["tap"] as Tap).sent.size(), turns.size(), str(fallbacks)])
	_feed(h["transport"], (scenario["events"] as Array).slice(1, 11))  # through the first text delta "Great!"
	if turns.size() != 3 or String(turns[2]["speech"]) != "Great!" or turns[2]["visual"] != {"type": "flashcard", "assetId": "cat"} \
			or String(turns[2]["lessonAction"]) != "next_question" or String(turns[2]["emotion"]) != "happy":
		failures.append("early turn: the local verdict's shape with the streamed words: %s" % str(turns.slice(2)))
	_feed(h["transport"], (scenario["events"] as Array).slice(11))
	if turns.size() != 3:
		failures.append("exactly one turn_ready per submit, got %d" % turns.size())
	if metas.size() != 1 or String(metas[0]["final"]["speech"]) != "Great! It's a cat!":
		failures.append("the final validated turn arrives as turn_meta: %s" % str(metas))
	if provider.has_pending_turn():
		failures.append("nothing pending after the final")
	provider.advance(0.05)
	# Timeout: no delta within FIRST_DELTA_SECONDS -> scripted turn, cloud reply cancelled.
	provider.submit_turn("dog", {"phase": "answer"})
	for _i: int in range(int(ProviderScript.FIRST_DELTA_SECONDS * 2) + 2):
		provider.advance(0.5)
	if turns.size() != 4 or fallbacks[-1] != "timeout" or not (h["tap"] as Tap).sent_types().has("response.cancel"):
		failures.append("a silent cloud is answered by the scripted line and the reply cancelled: %s / %s" % [str(fallbacks), turns.size()])
	# Lost reply: reconnect reports turn_failed -> scripted turn once.
	provider.submit_turn("dog", {"phase": "answer"})
	(h["transport"] as RefCounted).handle_event({"type": "error", "error": {"code": "server_error", "message": "x"}})
	provider.advance(0.05)
	if turns.size() != 5 or fallbacks[-1] != "server_error":
		failures.append("a lost reply is answered once by the scripted line: %s" % str(fallbacks))
	provider.end_session()
	provider.advance(0.05)
	if session.is_active():
		failures.append("end_session ends the cloud session")
	_free_session(h)
	return failures


# -- synthesis wrapper --------------------------------------------------------------------------------

func _test_synthesis_wrapper():
	var failures: Array = []
	var api := FakeApi.new()
	api.replies = {"session": [FakeApi.ok({"sessionId": "s-w", "quota": {"allowanceSeconds": 300, "usedSeconds": 0}})], "token": [FakeApi.ok(_fixture()["token"])]}
	var h: Dictionary = _session_harness(api)
	var session: RefCounted = h["session"]
	var inner := FakeInnerSynth.new()
	var synth: Node = SynthScript.new()
	synth.set_inner(inner)
	synth.set_cloud_session(session)
	var finished: Array = []
	synth.finished.connect(func(t: String) -> void: finished.append(t))
	if not _bring_up(h):
		return ["wrapper: session did not come up"]
	# A local line while nothing streams goes to the inner voice.
	synth.speak_turn({"speech": "Hi there!"})
	if inner.spoken != ["Hi there!"] or synth.mode() != "inner":
		failures.append("local lines go to the wrapped voice")
	synth.advance(0.4)
	if finished != ["Hi there!"]:
		failures.append("inner finished forwarded once: %s" % str(finished))
	# A local line while a reply streams is NOT the reply: it supersedes it.
	var cut: Dictionary = _fixture()["scenarios"]["cancel_mid_stream"]
	session.send_transcript("dog", cut["lessonContext"])
	_feed(h["transport"], cut["events"])
	synth.speak_turn({"speech": "Hi there!"})
	if synth.mode() != "inner" or session.is_reply_open() or (h["tap"] as Tap).sent_types().count("response.cancel") != 1:
		failures.append("an unclaimed speak_turn during a reply barges in and goes local: mode=%s" % synth.mode())
	synth.advance(0.4)
	# A cloud reply: attach, finish when drained, once.
	var scenario: Dictionary = _fixture()["scenarios"]["happy_tools_then_speech"]
	session.send_transcript("cat", scenario["lessonContext"])
	_feed(h["transport"], (scenario["events"] as Array).slice(1, 11))
	session.offer_reply_for_speech()
	synth.speak_turn({"speech": "Great!"})
	if synth.mode() != "cloud" or not synth.is_speaking():
		failures.append("a streaming reply is voiced by the cloud: mode=%s" % synth.mode())
	_feed(h["transport"], (scenario["events"] as Array).slice(11))
	if finished.size() != 2:
		failures.append("not finished while the audio still plays: %s" % str(finished))
	synth.advance(0.05)
	if finished.size() != 3 or inner.spoken.size() != 2:
		failures.append("finished once when the cloud audio drained, nothing spoken twice: %s / %s" % [str(finished), str(inner.spoken)])
	# Barge-in: cancel -> response.cancel + finished once.
	session.send_transcript("dog", scenario["lessonContext"])
	(h["transport"] as RefCounted).handle_event({"type": "response.output_item.added", "item": {"id": "m", "type": "message"}})
	(h["transport"] as RefCounted).handle_event({"type": "response.output_audio_transcript.delta", "delta": "Great"})
	session.offer_reply_for_speech()
	synth.speak_turn({"speech": "Great"})
	synth.cancel()
	synth.cancel()
	if finished.size() != 4 or (h["tap"] as Tap).sent_types().count("response.cancel") != 2 or synth.is_speaking():
		failures.append("barge-in: one cancel, one finished: %s" % str(finished))
	# No-audio reply: the final words are voiced locally, finished once.
	session.send_transcript("meow", {"lessonAction": "retry"})
	(h["transport"] as RefCounted).handle_event({"type": "response.output_item.added", "item": {"id": "m2", "type": "message"}})
	(h["transport"] as RefCounted).handle_event({"type": "response.output_audio_transcript.delta", "delta": "Good try!"})
	session.offer_reply_for_speech()
	synth.speak_turn({"speech": "Good try!"})
	(h["transport"] as RefCounted).handle_event({"type": "response.done", "response": {"id": "r2", "status": "completed"}})
	if inner.spoken.size() != 3 or inner.spoken[-1] != "Good try!":
		failures.append("a reply without audio is voiced by the local provider: %s" % str(inner.spoken))
	synth.advance(0.4)
	if finished.size() != 5:
		failures.append("finished once for the locally voiced reply: %s" % str(finished))
	# Safety replacement: the fallback line is voiced locally.
	var banned: Dictionary = _fixture()["scenarios"]["banned_word_is_replaced"]
	session.send_transcript("cat", banned["lessonContext"])
	_feed(h["transport"], (banned["events"] as Array).slice(0, 3))
	session.offer_reply_for_speech()
	synth.speak_turn({"speech": "That was a"})
	_feed(h["transport"], (banned["events"] as Array).slice(3))
	if inner.spoken[-1] != TurnValidator.fallback_turn()["speech"]:
		failures.append("the replaced reply is voiced as the fallback line: %s" % str(inner.spoken))
	synth.advance(0.4)
	if finished.size() != 6:
		failures.append("finished once after the replacement: %s" % str(finished))
	synth.free()
	inner.free()
	_free_session(h)
	return failures


# -- hygiene ------------------------------------------------------------------------------------------

func _test_cloud_files_hold_no_secrets():
	var failures: Array = []
	var dir: DirAccess = DirAccess.open(CLOUD_DIR)
	if dir == null:
		return ["cannot open %s" % CLOUD_DIR]
	var count: int = 0
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".gd"):
			continue
		count += 1
		var text: String = FileAccess.get_file_as_string(CLOUD_DIR + file_name)
		var code: String = _strip_comments(text)
		for needle: String in ["wss://", "https://", "http://", "openai", "api_key", "sk-proj", "AudioStreamMicrophone", "AudioEffectRecord"]:
			if code.to_lower().contains(needle.to_lower()):
				failures.append("%s carries '%s'" % [file_name, needle])
		for forbidden: String in ["Node3D", "MeshInstance3D", "Camera3D"]:
			if code.contains(forbidden):
				failures.append("%s references a 3D node type; domain logic stays engine-agnostic" % file_name)
		if file_name != "cloud_tutor_api.gd":
			for primitive: String in ["HTTPClient", "HTTPRequest", "WebSocketPeer", "StreamPeerTCP"]:
				if code.contains(primitive):
					failures.append("%s constructs %s; only cloud_tutor_api.gd (allowlisted) may" % [file_name, primitive])
	if count < 6:
		failures.append("expected the six cloud scripts, found %d" % count)
	# The scene loads the bridge lazily and only behind the flag.
	var scene: String = _strip_comments(FileAccess.get_file_as_string("res://scripts/tutor/tutor_scene.gd"))
	if scene.contains("preload(CLOUD_BRIDGE_PATH)") or scene.contains("preload(\"res://scripts/tutor/cloud"):
		failures.append("tutor_scene.gd must not preload anything under cloud/")
	var hook: int = scene.find("func _select_cloud_tutor")
	var gate: int = scene.find("cloud_enabled()", hook)
	var loaded: int = scene.find("load(CLOUD_BRIDGE_PATH)", hook)
	if hook < 0 or gate < 0 or loaded < 0 or gate > loaded:
		failures.append("tutor_scene.gd's hook must read TutorFlags.cloud_enabled() before load(CLOUD_BRIDGE_PATH)")
	return failures


static func _strip_comments(source: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		var hash_at: int = line.find("#")
		out.append(line if hash_at < 0 else line.left(hash_at))
	return "\n".join(out)
