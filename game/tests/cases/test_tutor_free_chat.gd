extends RefCounted

## Free chat (T2), offline: the cloud flag is OFF, no socket, no HTTP client,
## no key. The REST client is exercised through its pure helpers and the
## recorded exchange in `tests/fixtures/tutor_chat_exchange.json` (recorded
## from the mock server; synthetic adult-authored text only); the controller
## runs on a scripted fake API and a fake presenter, and every reply must
## arrive through the presenter's `turn_ready` -- the classroom's ONE
## presentation path -- never anywhere else.
##
##   * api: `session_body()` keeps the reconciled lesson shape byte-identical
##     and sends `{mode: "chat", clientId}` for chat; `chat_turn_body()` bounds
##     the transcript and clamps the word cap; the recorded replies validate
##     once `none` is mapped to the classroom's `retry`; `feature_disabled`
##     maps from the recorded 403.
##   * controller: lesson mode is a no-op for `intercept_turn`; enter -> chat
##     session -> greeting; a transcript -> `submit_chat_turn` with the key
##     and cap -> the fixture reply presented with `retry`; follow-up context
##     and redirect metadata surface in `chat_turn`; silence answered locally,
##     the third silence returns to the lesson; `return_to_lesson` ends the
##     session and re-opens the step (`jump_step`); `feature_disabled` falls
##     back to the lesson kindly; a transient turn failure is answered locally
##     and the chat goes on; quota exhaustion / session_ended leave chat; the
##     lesson session's own traffic on the shared client is ignored; a
##     transcript typed while opening is sent once the session is up.
##   * privacy: the controller file holds no network class, no URL, no
##     provider name; its log never carries a transcript.

const ApiScript := preload("res://scripts/tutor/cloud/cloud_tutor_api.gd")
const ControllerScript := preload("res://scripts/tutor/cloud/free_chat_controller.gd")
const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")

const FIXTURE: String = "res://tests/fixtures/tutor_chat_exchange.json"
const CONTROLLER_PATH: String = "res://scripts/tutor/cloud/free_chat_controller.gd"


class FakeApi:
	extends RefCounted
	signal completed(kind: String, result: Dictionary)
	var available: bool = true
	var approval: bool = true
	var calls: Array = []
	var replies: Dictionary = {}
	var pending: Array = []
	func is_available() -> bool:
		return available
	func has_approval() -> bool:
		return approval
	func create_session(lesson_id: String, mode: String = "lesson") -> bool:
		return _call("session", {"lessonId": lesson_id, "mode": mode})
	func submit_turn(session_id: String, key: String, transcript: String, context: Dictionary, audio_seconds: float = 0.0) -> bool:
		return _call("turn", {"sessionId": session_id, "key": key, "transcript": transcript, "lessonContext": context, "audioSeconds": audio_seconds})
	func submit_chat_turn(session_id: String, key: String, transcript: String, response_max_words: int = 0) -> bool:
		return _call("turn", {"sessionId": session_id, "key": key, "transcript": transcript, "responseMaxWords": response_max_words, "chat": true})
	func end_session(session_id: String, reason: String) -> bool:
		return _call("end", {"sessionId": session_id, "reason": reason})
	func cancel() -> void:
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


## Stands in for the bound ConversationProvider: only its `turn_ready` matters.
class FakePresenter:
	extends RefCounted
	signal turn_ready(turn: Dictionary)
	var turns: Array = []
	func _init() -> void:
		turn_ready.connect(func(t: Dictionary) -> void: turns.append(t))


class FakeLessonSession:
	extends RefCounted
	var active: bool = true
	var ready_now: bool = true
	func is_active() -> bool:
		return active
	func is_ready() -> bool:
		return ready_now


## Minimal stand-in for the bridge's public surface + Object meta.
class FakeBridge:
	extends RefCounted
	var _api: RefCounted
	var _provider: RefCounted
	var _session: RefCounted
	func _init(api: RefCounted, provider: RefCounted, session: RefCounted) -> void:
		_api = api
		_provider = provider
		_session = session
	func api() -> RefCounted:
		return _api
	func provider() -> RefCounted:
		return _provider
	func session() -> RefCounted:
		return _session


func test_name() -> String:
	return "tutor_free_chat"


func run():
	var failures: Array = []
	if TutorFlags.cloud_enabled():
		return ["this suite must run with the cloud flag OFF"]
	var fixture: Dictionary = _load_fixture()
	if fixture.is_empty():
		return ["could not read %s" % FIXTURE]
	failures.append_array(_test_api_bodies_and_fixture(fixture))
	failures.append_array(_test_controller_exchange(fixture))
	failures.append_array(_test_controller_refusals(fixture))
	failures.append_array(_test_controller_shared_client_and_pending(fixture))
	failures.append_array(_test_controller_file_is_clean())
	return failures


# -- api ---------------------------------------------------------------------------------

func _test_api_bodies_and_fixture(fixture: Dictionary):
	var failures: Array = []
	if ApiScript.session_body("animals_cat_dog", ApiScript.MODE_LESSON, "ld-1") != {"lessonId": "animals_cat_dog", "clientId": "ld-1"}:
		failures.append("lesson session body changed shape")
	if ApiScript.session_body("ignored", ApiScript.MODE_CHAT, "ld-1") != {"mode": "chat", "clientId": "ld-1"}:
		failures.append("chat session body: %s" % str(ApiScript.session_body("ignored", ApiScript.MODE_CHAT, "ld-1")))
	if ApiScript.chat_turn_body("  what do cats eat  ") != {"transcript": "what do cats eat"}:
		failures.append("chat turn body without a cap: %s" % str(ApiScript.chat_turn_body("  what do cats eat  ")))
	if ApiScript.chat_turn_body("hi", 3) != {"transcript": "hi", "responseMaxWords": 8} \
			or ApiScript.chat_turn_body("hi", 500) != {"transcript": "hi", "responseMaxWords": 40} \
			or ApiScript.chat_turn_body("hi", 12) != {"transcript": "hi", "responseMaxWords": 12}:
		failures.append("responseMaxWords is clamped into 8..40")
	var long_text: String = "a".repeat(600)
	if String(ApiScript.chat_turn_body(long_text)["transcript"]).length() != ApiScript.MAX_TRANSCRIPT_CHARS:
		failures.append("chat transcript bounded to %d chars" % ApiScript.MAX_TRANSCRIPT_CHARS)
	# The recorded refusal and session.
	var refused: Dictionary = fixture["refused"]
	if ApiScript.error_code_for(int(refused["status"]), refused["body"]) != ApiScript.CODE_FEATURE_DISABLED:
		failures.append("the recorded 403 maps to feature_disabled")
	var session_body: Dictionary = fixture["session"]["body"]
	if String(session_body.get("mode", "")) != "chat" or String(session_body.get("lessonId", "")) != "free_chat" \
			or int((session_body.get("chat", {}) as Dictionary).get("responseMaxWords", 0)) != 25:
		failures.append("recorded chat session shape: %s" % str(session_body))
	# Every recorded reply is a valid TutorTurn once `none` becomes the classroom's `retry`.
	var expected_action: Dictionary = {}
	for exchange: Dictionary in fixture["exchanges"]:
		var body: Dictionary = exchange["body"]
		var turn: Dictionary = body["turn"]
		if String(turn.get("lessonAction", "")) != "none":
			failures.append("fixture '%s': chat replies carry lessonAction none" % exchange["name"])
		if turn.has("nextQuestion"):
			failures.append("fixture '%s': no nextQuestion on a chat reply" % exchange["name"])
		var mapped: Dictionary = turn.duplicate(true)
		mapped["lessonAction"] = "retry"
		var report: Dictionary = TurnValidator.validate(mapped)
		if not bool(report["valid"]):
			failures.append("fixture '%s' does not validate: %s" % [exchange["name"], str(report["reasons"])])
		if String(body.get("mode", "")) != "chat" or String(body.get("contextSource", "")) != "chat":
			failures.append("fixture '%s': mode/contextSource chat" % exchange["name"])
		expected_action[String(exchange["name"])] = body
	var follow: Dictionary = expected_action["follow_up_why_uses_context"]["turn"]
	if not String(follow["speech"]).begins_with("About dogs?"):
		failures.append("the recorded follow-up used the last topic: %s" % follow["speech"])
	var redirect: Dictionary = expected_action["redirect_personal_data"]
	if String(redirect.get("provider", "")) != "safety" or String((redirect["chat"] as Dictionary).get("redirected", "")) != "personal_data" \
			or String(redirect["turn"]["speech"]).to_lower().contains("phone"):
		failures.append("the recorded redirect: %s" % str(redirect))
	var capped: Dictionary = expected_action["capped_song"]
	if not bool((capped["chat"] as Dictionary).get("capped", false)) or String(capped["turn"]["speech"]).split(" ", false).size() > 8:
		failures.append("the recorded cap to 8 words: %s" % str(capped["turn"]["speech"]))
	if ApiScript.error_code_for(int(fixture["emptyTranscript"]["status"]), fixture["emptyTranscript"]["body"]) != ApiScript.CODE_INVALID_TURN:
		failures.append("an empty chat transcript is invalid_turn on the server")
	return failures


# -- controller ------------------------------------------------------------------------------

func _make(fixture: Dictionary) -> Dictionary:
	var api := FakeApi.new()
	var presenter := FakePresenter.new()
	var lesson := FakeLessonSession.new()
	var bridge := FakeBridge.new(api, presenter, lesson)
	var controller: RefCounted = ControllerScript.attach_to_bridge(bridge)
	var ev: Dictionary = {"modes": [], "ready": [], "chat": [], "unavailable": [], "ended": []}
	controller.mode_changed.connect(func(m: String) -> void: ev["modes"].append(m))
	controller.chat_ready.connect(func(i: Dictionary) -> void: ev["ready"].append(i))
	controller.chat_turn.connect(func(t: Dictionary, m: Dictionary) -> void: ev["chat"].append([t, m]))
	controller.chat_unavailable.connect(func(c: String) -> void: ev["unavailable"].append(c))
	controller.chat_ended.connect(func(r: String) -> void: ev["ended"].append(r))
	api.replies["session"] = [FakeApi.ok(fixture["session"]["body"])]
	return {"api": api, "presenter": presenter, "lesson": lesson, "bridge": bridge, "controller": controller, "ev": ev}


static func _reply(fixture: Dictionary, name: String) -> Dictionary:
	for exchange: Dictionary in fixture["exchanges"]:
		if String(exchange["name"]) == name:
			return FakeApi.ok(exchange["body"])
	return {}


func _test_controller_exchange(fixture: Dictionary):
	var failures: Array = []
	var h: Dictionary = _make(fixture)
	var api: FakeApi = h["api"]
	var presenter: FakePresenter = h["presenter"]
	var controller: RefCounted = h["controller"]
	var ev: Dictionary = h["ev"]
	if ControllerScript.attach_to_bridge(h["bridge"]) != controller:
		failures.append("attach_to_bridge is idempotent (one controller per bridge, kept in meta)")
	if not (h["bridge"] as Object).has_meta(ControllerScript.FREE_CHAT_META):
		failures.append("the controller registers itself under the bridge meta '%s'" % ControllerScript.FREE_CHAT_META)
	# Lesson mode: the hook is a no-op and nothing is sent.
	if controller.intercept_turn("cat", "answer") or not api.calls.is_empty() or controller.mode() != "lesson":
		failures.append("lesson mode: intercept_turn must return false and send nothing")
	# Enter chat: the session is opened in chat mode, then the greeting is presented.
	controller.set_response_max_words(12)
	if not controller.enter_free_chat():
		failures.append("enter_free_chat refused: %s" % str(ev["unavailable"]))
	if api.calls_of("session") != [{"kind": "session", "body": {"lessonId": "", "mode": "chat"}}]:
		failures.append("chat session request: %s" % str(api.calls_of("session")))
	if ev["modes"] != ["chat"] or controller.get_state() != "opening":
		failures.append("mode chat / state opening expected: %s %s" % [str(ev["modes"]), controller.get_state()])
	api.advance(0.1)
	if controller.get_state() != "ready" or controller.session_id() != String(fixture["session"]["body"]["sessionId"]):
		failures.append("ready after the session reply: state=%s" % controller.get_state())
	if ev["ready"].size() != 1 or int((ev["ready"][0]["chat"] as Dictionary).get("responseMaxWords", 0)) != 25:
		failures.append("chat_ready carries the server's chat config: %s" % str(ev["ready"]))
	if presenter.turns.size() != 1 or String(presenter.turns[0]["speech"]) != ControllerScript.GREETING \
			or String(presenter.turns[0]["lessonAction"]) != "retry":
		failures.append("the greeting goes through the presenter's turn_ready with retry: %s" % str(presenter.turns))
	# A transcript: submit_chat_turn with the key and the cap; the reply presented with retry.
	api.replies["turn"] = [_reply(fixture, "cats"), _reply(fixture, "follow_up_dogs"), _reply(fixture, "follow_up_why_uses_context"),
		_reply(fixture, "redirect_personal_data"), _reply(fixture, "capped_song")]
	if not controller.intercept_turn("what do cats eat", "answer"):
		failures.append("chat mode: intercept_turn consumes the transcript")
	if controller.get_state() != "waiting" or not controller.has_turn_in_flight():
		failures.append("waiting while the turn is in flight")
	if controller.intercept_turn("what do cats eat", "answer") or api.calls_of("turn").size() != 1:
		failures.append("the scene re-asking while waiting sends nothing more") if api.calls_of("turn").size() != 1 else null
	var sent: Dictionary = api.calls_of("turn")[0]["body"]
	var sid: String = controller.session_id()
	if sent != {"sessionId": sid, "key": "%s:c1" % sid, "transcript": "what do cats eat", "responseMaxWords": 12, "chat": true}:
		failures.append("chat turn request: %s" % str(sent))
	api.advance(0.1)
	if presenter.turns.size() != 2 or String(presenter.turns[1]["speech"]) != "Cats eat cat food and drink water." \
			or presenter.turns[1]["visual"] != {"type": "flashcard", "assetId": "cat"} or String(presenter.turns[1]["lessonAction"]) != "retry":
		failures.append("the server's reply presented with retry: %s" % str(presenter.turns.slice(1)))
	if ev["chat"].size() != 1 or String(ev["chat"][0][1]["provider"]) != "mock" or int(ev["chat"][0][1]["words"]) != 7:
		failures.append("chat_turn meta: %s" % str(ev["chat"]))
	# Follow-ups, the redirect and the cap flow through untouched.
	controller.intercept_turn("and dogs?", "answer")
	api.advance(0.1)
	controller.intercept_turn("why?", "answer")
	api.advance(0.1)
	controller.intercept_turn("what is your phone number", "answer")
	api.advance(0.1)
	controller.intercept_turn("sing a song please", "answer")
	api.advance(0.1)
	if presenter.turns.size() != 6:
		failures.append("one presented turn per exchange: %d" % presenter.turns.size())
	else:
		if not String(presenter.turns[3]["speech"]).begins_with("About dogs?"):
			failures.append("follow-up context reached the presenter: %s" % presenter.turns[3]["speech"])
		if String(ev["chat"][3][1]["redirected"]) != "personal_data" or String(ev["chat"][3][1]["provider"]) != "safety" \
				or String(presenter.turns[4]["speech"]).to_lower().contains("phone"):
			failures.append("redirect metadata + safe line: %s" % str(ev["chat"][3]))
		if not bool(ev["chat"][4][1]["capped"]) or int(ev["chat"][4][1]["responseMaxWords"]) != 8:
			failures.append("cap metadata: %s" % str(ev["chat"][4][1]))
	for call: Dictionary in api.calls_of("turn"):
		if not bool(call["body"].get("chat", false)) or call["body"].has("lessonContext"):
			failures.append("every chat turn used submit_chat_turn (no lessonContext)")
	# Silence: answered locally twice, the third returns to the lesson.
	var before: int = api.calls.size()
	controller.intercept_turn("", "together")
	controller.intercept_turn("", "timeout")
	if api.calls.size() != before or presenter.turns.size() != 8 or String(presenter.turns[7]["speech"]) != ControllerScript.LISTENING_PROMPT:
		failures.append("silence is answered locally, nothing sent: %s" % str(presenter.turns.slice(6)))
	controller.intercept_turn("", "together")
	if controller.mode() != "lesson" or ev["ended"] != ["chat_silent"] or api.calls_of("end").size() != 1 \
			or String(api.calls_of("end")[0]["body"]["reason"]) != "chat_silent":
		failures.append("the third silence returns to the lesson and ends the chat session: mode=%s ended=%s ends=%s" % [controller.mode(), str(ev["ended"]), str(api.calls_of("end"))])
	if presenter.turns.size() != 9 or String(presenter.turns[8]["speech"]) != ControllerScript.BACK_TO_LESSON \
			or String(presenter.turns[8]["lessonAction"]) != "jump_step":
		failures.append("the return line re-opens the current step via jump_step: %s" % str(presenter.turns.slice(8)))
	api.advance(0.1)
	if controller.get_state() != "idle":
		failures.append("idle after the end ack: %s" % controller.get_state())
	# Back in lesson mode the hook is a no-op again, and a fresh enter works.
	if controller.intercept_turn("cat", "answer"):
		failures.append("lesson mode again after return")
	api.replies["session"] = [FakeApi.ok(fixture["session"]["body"])]
	if not controller.enter_free_chat():
		failures.append("re-enter refused")
	api.advance(0.1)
	controller.return_to_lesson()
	api.advance(0.1)
	if ev["modes"] != ["chat", "lesson", "chat", "lesson"] or controller.get_state() != "idle":
		failures.append("mode history %s state %s" % [str(ev["modes"]), controller.get_state()])
	# Never a transcript in the log.
	var log_text: String = str(controller.turn_log())
	if log_text.contains("cats eat") or log_text.contains("phone number") or controller.turn_log().size() < 5:
		failures.append("turn_log carries words or is empty: %s" % log_text)
	return failures


func _test_controller_refusals(fixture: Dictionary):
	var failures: Array = []
	# feature_disabled: back to the lesson kindly, re-opening the step.
	var h: Dictionary = _make(fixture)
	var api: FakeApi = h["api"]
	var presenter: FakePresenter = h["presenter"]
	var controller: RefCounted = h["controller"]
	var ev: Dictionary = h["ev"]
	api.replies["session"] = [FakeApi.err(int(fixture["refused"]["status"]), "feature_disabled", fixture["refused"]["body"])]
	controller.enter_free_chat()
	api.advance(0.1)
	if ev["unavailable"] != ["feature_disabled"] or controller.mode() != "lesson" or controller.get_state() != "idle":
		failures.append("feature_disabled -> chat_unavailable + lesson mode: %s %s" % [str(ev["unavailable"]), controller.mode()])
	if presenter.turns.size() != 1 or String(presenter.turns[0]["speech"]) != ControllerScript.NOT_AVAILABLE or String(presenter.turns[0]["lessonAction"]) != "jump_step":
		failures.append("the not-available line re-opens the step: %s" % str(presenter.turns))
	if ev["modes"] != ["chat", "lesson"]:
		failures.append("modes on refusal: %s" % str(ev["modes"]))
	# Cloud off / no approval / lesson session mid-handshake: refused up front, nothing sent.
	var h2: Dictionary = _make(fixture)
	(h2["api"] as FakeApi).available = false
	if (h2["controller"] as RefCounted).enter_free_chat() or (h2["ev"]["unavailable"] as Array) != ["cloud_disabled"]:
		failures.append("cloud off refuses: %s" % str(h2["ev"]["unavailable"]))
	var h3: Dictionary = _make(fixture)
	(h3["api"] as FakeApi).approval = false
	if (h3["controller"] as RefCounted).enter_free_chat() or (h3["ev"]["unavailable"] as Array) != ["not_approved"]:
		failures.append("no approval refuses: %s" % str(h3["ev"]["unavailable"]))
	var h4: Dictionary = _make(fixture)
	(h4["lesson"] as FakeLessonSession).ready_now = false
	if (h4["controller"] as RefCounted).enter_free_chat() or (h4["ev"]["unavailable"] as Array) != ["lesson_session_busy"] or not (h4["api"] as FakeApi).calls.is_empty():
		failures.append("a lesson session mid-handshake refuses chat: %s" % str(h4["ev"]["unavailable"]))
	# A transient turn failure: local line, chat continues; quota exhaustion leaves chat.
	var h5: Dictionary = _make(fixture)
	var api5: FakeApi = h5["api"]
	var c5: RefCounted = h5["controller"]
	var p5: FakePresenter = h5["presenter"]
	c5.enter_free_chat()
	api5.advance(0.1)
	api5.replies["turn"] = [FakeApi.err(0, "timeout"), FakeApi.err(429, "quota_exhausted", {"error": {"code": "quota_exhausted", "reason": "daily_quota", "quota": {"remainingSeconds": 0}}})]
	c5.intercept_turn("hello", "answer")
	api5.advance(0.1)
	if c5.mode() != "chat" or p5.turns.size() != 2 or String(p5.turns[1]["speech"]) != ControllerScript.TROUBLE_LINE:
		failures.append("a timeout is answered locally and the chat goes on: %s" % str(p5.turns))
	c5.intercept_turn("hello again", "answer")
	api5.advance(0.1)
	if c5.mode() != "lesson" or (h5["ev"]["unavailable"] as Array) != ["quota_exhausted"] or (h5["ev"]["ended"] as Array) != ["quota_exhausted"] \
			or float(c5.server_quota().get("remainingSeconds", 1.0)) != 0.0:
		failures.append("quota exhaustion leaves chat: mode=%s %s quota=%s" % [c5.mode(), str(h5["ev"]), str(c5.server_quota())])
	if String(p5.turns[-1]["lessonAction"]) != "jump_step":
		failures.append("leaving chat re-opens the step")
	# endAtBoundary on a reply: the reply is presented, then chat mode is over.
	var h6: Dictionary = _make(fixture)
	var api6: FakeApi = h6["api"]
	var c6: RefCounted = h6["controller"]
	c6.enter_free_chat()
	api6.advance(0.1)
	var boundary: Dictionary = (_reply(fixture, "cats")["body"] as Dictionary).duplicate(true)
	boundary["endAtBoundary"] = true
	api6.replies["turn"] = [FakeApi.ok(boundary)]
	c6.intercept_turn("cats?", "answer")
	api6.advance(0.1)
	if c6.mode() != "lesson" or (h6["ev"]["ended"] as Array) != ["quota_exhausted"] or (h6["presenter"] as FakePresenter).turns.size() != 2 \
			or not (h6["api"] as FakeApi).calls_of("end").is_empty():
		failures.append("endAtBoundary: reply presented, chat over, no /end (the server ended it): %s" % str(h6["ev"]))
	return failures


func _test_controller_shared_client_and_pending(fixture: Dictionary):
	var failures: Array = []
	var h: Dictionary = _make(fixture)
	var api: FakeApi = h["api"]
	var presenter: FakePresenter = h["presenter"]
	var controller: RefCounted = h["controller"]
	# The lesson session's own traffic on the shared client is not ours.
	api.completed.emit("turn", FakeApi.ok({"turn": TurnValidator.fallback_turn()}))
	api.completed.emit("session", FakeApi.ok({"sessionId": "lesson-1"}))
	api.completed.emit("end", FakeApi.ok({}))
	if not presenter.turns.is_empty() or controller.mode() != "lesson" or not controller.session_id().is_empty():
		failures.append("lesson traffic on the shared client must be ignored")
	# A transcript that arrives while the session is still opening is sent once, after the greeting is skipped.
	controller.enter_free_chat()
	api.replies["turn"] = [_reply(fixture, "cats")]
	controller.intercept_turn("what do cats eat", "answer")
	if not api.calls_of("turn").is_empty():
		failures.append("nothing sent before the session is up")
	api.advance(0.1)  # session reply -> the pending transcript is sent (the fake drains its reply in the same pump)
	if api.calls_of("turn").size() != 1:
		failures.append("the pending transcript is sent exactly once when the session is up: %d" % api.calls_of("turn").size())
	api.advance(0.1)
	if presenter.turns.size() != 1 or String(presenter.turns[0]["speech"]) != "Cats eat cat food and drink water.":
		failures.append("no greeting; the pending transcript's reply is the first presented turn: %s" % str(presenter.turns))
	# Word cap setter bounds.
	controller.set_response_max_words(3)
	var low: int = controller.response_max_words()
	controller.set_response_max_words(999)
	var high: int = controller.response_max_words()
	controller.set_response_max_words(0)
	if low != 8 or high != 40 or controller.response_max_words() != 0:
		failures.append("response_max_words bounds: %d %d %d" % [low, high, controller.response_max_words()])
	# Scene exit ends quietly.
	controller.on_scene_exiting()
	if controller.mode() != "lesson" or presenter.turns.size() != 1 or String(api.calls_of("end")[-1]["body"]["reason"]) != "scene":
		failures.append("on_scene_exiting ends the chat without speaking")
	return failures


# -- privacy -----------------------------------------------------------------------------

func _test_controller_file_is_clean():
	var failures: Array = []
	var text: String = FileAccess.get_file_as_string(CONTROLLER_PATH)
	if text.is_empty():
		return ["could not read %s" % CONTROLLER_PATH]
	var code: String = ""
	for line: String in text.split("\n"):
		var hash_at: int = line.find("#")
		code += (line if hash_at < 0 else line.left(hash_at)) + "\n"
	for primitive: String in ["HTTPRequest", "HTTPClient", "WebSocketPeer", "StreamPeerTCP", "PacketPeerUDP"]:
		if code.contains(primitive):
			failures.append("free_chat_controller.gd must hold no network class (%s); the REST client is cloud_tutor_api.gd" % primitive)
	for token: String in ["http://", "https://", "wss://", "openai", "api_key", "Bearer "]:
		if code.to_lower().contains(token.to_lower()):
			failures.append("free_chat_controller.gd contains '%s'" % token)
	return failures


func _load_fixture() -> Dictionary:
	if not FileAccess.file_exists(FIXTURE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
