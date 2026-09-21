extends RefCounted

## Cloud tutor client against the MOCK server (Agent E), end to end over a
## real loopback HTTP + WebSocket connection. Runs only when the mock is up:
##
##   /usr/local/bin/node tools/tutor_mock_server/server.mjs      # 127.0.0.1:8787
##   godot --headless --path game --script res://tests/run_tests.gd
##
## When nothing answers on 127.0.0.1:${LD_TUTOR_MOCK_PORT:-8787} the case
## prints SKIP and passes, so the suite never depends on it. The project
## flag stays OFF: the REST client and the transport are armed with their
## loopback-only `enable_for_tests()` (refused on mobile/release builds), and
## no other address is ever dialled. No provider is involved anywhere: the
## mock is a scripted lesson with synthetic tone audio.
##
## Scenarios (keyed on the clientId prefix, see the mock's header):
##   default    quota -> session -> token -> ws -> "cat" -> tool card + audio
##              + validated turn; barge-in on "dog" (response.cancel +
##              truncate); 2.5 s of synthetic mic audio -> server VAD ->
##              transcript "cat" -> a server-initiated reply plays; end posts
##              usage; GET /quota shows the seconds used.
##   norealtime token mint 503 (the deployed Worker's shape) -> ready on the
##              turns path; a REST turn drives the card and the validated turn.
##   drop       socket closed after the first reply -> reconnect once.
##   exhausted  429 quota_exhausted -> fell_back quota_exhausted, no token minted.
##   banned     the reply carries a banned word -> cancelled and replaced.
##   deny       403 -> fell_back not_approved.
##   chat       (T2) FreeChatController on the real REST client: a lesson
##              session on the turns path, enter_free_chat -> a chat session
##              -> greeting; "what do cats eat" / "and dogs?" / a flagged
##              topic / a capped reply all presented through the bound
##              provider's turn_ready; return_to_lesson ends it
##              (`return_to_lesson`); a `chatoff*` client is refused 403
##              feature_disabled and falls back to the lesson.

const ApiScript := preload("res://scripts/tutor/cloud/cloud_tutor_api.gd")
const TransportScript := preload("res://scripts/tutor/voice/transports/cloud_realtime_transport.gd")
const SessionScript := preload("res://scripts/tutor/cloud/cloud_tutor_session.gd")
const PlayerScript := preload("res://scripts/tutor/cloud/cloud_audio_player.gd")
const ProviderScript := preload("res://scripts/tutor/cloud/cloud_tutor_provider.gd")
const FreeChatScript := preload("res://scripts/tutor/cloud/free_chat_controller.gd")
const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")

const DEFAULT_PORT: int = 8787
const STEP_SECONDS: float = 8.0


class Face:
	extends RefCounted
	var calls: Array = []
	var mouth_max: float = 0.0
	func set_expression(name: String) -> bool:
		calls.append("expression:%s" % name)
		return true
	func play_gesture(name: String) -> float:
		calls.append("gesture:%s" % name)
		return 0.5
	func set_speaking(active: bool) -> void:
		calls.append("speaking:%s" % str(active))
	func set_mouth_open(amount: float) -> void:
		mouth_max = maxf(mouth_max, amount)


func test_name() -> String:
	return "tutor_cloud_integration"


func run():
	var failures: Array = []
	if TutorFlags.cloud_enabled():
		return ["this suite must run with the cloud flag OFF (the loopback test override is used instead)"]
	var port: int = int(OS.get_environment("LD_TUTOR_MOCK_PORT")) if not OS.get_environment("LD_TUTOR_MOCK_PORT").is_empty() else DEFAULT_PORT
	if not _mock_is_up(port):
		print("    SKIP cloud integration: no mock tutor server on 127.0.0.1:%d (node tools/tutor_mock_server/server.mjs)" % port)
		return failures
	var base: String = "http://127.0.0.1:%d" % port
	print("    mock tutor server on %s" % base)
	failures.append_array(_scenario_default(base))
	failures.append_array(_scenario_norealtime(base))
	failures.append_array(_scenario_drop(base))
	failures.append_array(_scenario_exhausted(base))
	failures.append_array(_scenario_banned(base))
	failures.append_array(_scenario_deny(base))
	failures.append_array(_scenario_chat(base))
	return failures


# -- harness ---------------------------------------------------------------------------------------

func _mock_is_up(port: int) -> bool:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", port) != OK:
		return false
	var deadline: int = Time.get_ticks_msec() + 800
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var status: int = peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
			return true
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			return false
		OS.delay_msec(10)
	return false


func _make(base: String, child_id: String) -> Dictionary:
	var api: RefCounted = ApiScript.new()
	api.configure(child_id, "dev-parent-approval")
	api.set_base_url(base)
	if not api.enable_for_tests():
		return {}
	var transport: RefCounted = TransportScript.new()
	if not transport.enable_for_tests():
		return {}
	var player: Node = PlayerScript.new()
	player.set_device_enabled(false)
	var session: RefCounted = SessionScript.new()
	session.set_api(api)
	session.set_transport(transport)
	session.set_audio_player(player)
	var face := Face.new()
	session.set_face(face)
	var capture: Array = [true]
	session.set_capture_source(func() -> bool: return capture[0])
	session.configure("animals_cat_dog")
	var ev: Dictionary = {"ready": [], "ended": [], "fell_back": [], "turns": [], "failed": [], "replaced": [], "speaking": [],
		"subtitles": [], "tools": [], "transcripts": [], "cancelled": 0, "quota": []}
	session.ready.connect(func(i: Dictionary) -> void: ev["ready"].append(i))
	session.ended.connect(func(r: String, s: Dictionary) -> void: ev["ended"].append([r, s]))
	session.fell_back.connect(func(r: String) -> void: ev["fell_back"].append(r))
	session.turn_ready.connect(func(t: Dictionary) -> void: ev["turns"].append(t))
	session.turn_failed.connect(func(r: String) -> void: ev["failed"].append(r))
	session.reply_replaced.connect(func(t: Dictionary) -> void: ev["replaced"].append(t))
	session.speaking_changed.connect(func(a: bool) -> void: ev["speaking"].append(a))
	session.subtitle_changed.connect(func(t: String) -> void: ev["subtitles"].append(t))
	session.tool_applied.connect(func(n: String, a: Dictionary) -> void: ev["tools"].append([n, a]))
	session.input_transcript.connect(func(t: String) -> void: ev["transcripts"].append(t))
	session.cancelled.connect(func() -> void: ev["cancelled"] += 1)
	session.quota_updated.connect(func(q: Dictionary) -> void: ev["quota"].append(q))
	return {"api": api, "transport": transport, "session": session, "player": player, "face": face, "capture": capture, "ev": ev}


func _free(h: Dictionary) -> void:
	if h.has("player"):
		(h["player"] as Node).free()


## Pumps the session in real time until `predicate` holds or `seconds` pass.
func _pump(h: Dictionary, predicate: Callable, seconds: float = STEP_SECONDS) -> bool:
	var session: RefCounted = h["session"]
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	var last: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() < deadline:
		var now: int = Time.get_ticks_msec()
		session.advance(float(now - last) / 1000.0)
		last = now
		if bool(predicate.call()):
			return true
		OS.delay_msec(5)
	session.advance(0.001)
	return bool(predicate.call())


func _wait_ready(h: Dictionary) -> bool:
	var session: RefCounted = h["session"]
	var ev: Dictionary = h["ev"]
	session.start()
	return _pump(h, func() -> bool: return session.is_ready() or not ev["fell_back"].is_empty() or not ev["ended"].is_empty())


static func _tone(seconds: float) -> PackedByteArray:
	var frames: int = int(seconds * 24000.0)
	var out: PackedByteArray = PackedByteArray()
	out.resize(frames * 2)
	for i: int in range(frames):
		out.encode_s16(i * 2, int(9000.0 * sin(float(i) * 0.06)))
	return out


# -- scenarios ------------------------------------------------------------------------------------------

func _scenario_default(base: String) -> Array:
	var failures: Array = []
	var h: Dictionary = _make(base, "child-default-%d" % (Time.get_ticks_usec() % 100000))
	if h.is_empty():
		return ["loopback test override refused on a desktop run"]
	var session: RefCounted = h["session"]
	var transport: RefCounted = h["transport"]
	var ev: Dictionary = h["ev"]
	if not _wait_ready(h):
		_free(h)
		return ["default: not ready in %.0f s: state=%s fell_back=%s" % [STEP_SECONDS, session.get_state(), str(ev["fell_back"])]]
	print("      default: ready session=%s history=%s" % [session.session_id(), str(session.state_history())])
	if session.state_history() != ["quota", "creating", "minting", "connecting", "ready"]:
		failures.append("default: state order %s" % str(session.state_history()))
	# "cat": tool card first (a function-call-only response), then the spoken reply with audio.
	var context: Dictionary = {"phase": "answer", "stepId": "s02_cat", "outcome": "correct", "lessonAction": "next_question", "visualAssetId": "cat"}
	session.send_transcript("cat", context)
	if not _pump(h, func() -> bool: return ev["turns"].size() >= 1 and not session.is_reply_open()):
		failures.append("default: no finished reply for 'cat' (turns=%d open=%s)" % [ev["turns"].size(), str(session.is_reply_open())])
	else:
		var turn: Dictionary = ev["turns"][0]
		print("      default: turn %s" % str(turn))
		if String(turn["speech"]) != "Great! It's a cat!" or turn["visual"] != {"type": "flashcard", "assetId": "cat"} or String(turn["gesture"]) != "clap" or String(turn["lessonAction"]) != "next_question":
			failures.append("default: validated turn with the tool card: %s" % str(turn))
		if ev["tools"] != [["show_card", {"assetId": "cat"}], ["gesture", {"name": "clap"}]]:
			failures.append("default: tool calls %s" % str(ev["tools"]))
		if ev["speaking"] != [true, false] or (h["face"] as Face).mouth_max <= 0.05:
			failures.append("default: audio drove speaking + mouth: %s / %f" % [str(ev["speaking"]), (h["face"] as Face).mouth_max])
		var types: Array = []
		for event: Dictionary in transport.sent_events():
			types.append(String(event.get("type", "")))
		if types.count("response.create") != 2 or types.count("conversation.item.create") != 3:
			failures.append("default: outputs returned + one response.create after the tool round: %s" % str(types))
		var usage: Dictionary = session.usage()
		if int(usage["tokensIn"]) <= 0 or int(usage["tokensOut"]) <= 0 or float(usage["audioSecondsOut"]) < 0.3:
			failures.append("default: usage metered %s" % str(usage))
		print("      default: usage %s" % str(usage))
	# Barge-in on "dog".
	session.send_transcript("dog", {"phase": "answer", "outcome": "correct", "lessonAction": "next_question", "visualAssetId": "dog"})
	if not _pump(h, func() -> bool: return session.is_speaking()):
		failures.append("default: 'dog' never started playing")
	session.barge_in()
	var sent_types: Array = []
	for event: Dictionary in transport.sent_events():
		sent_types.append(String(event.get("type", "")))
	if ev["cancelled"] != 1 or session.is_reply_open() or not sent_types.has("response.cancel") or not sent_types.has("conversation.item.truncate"):
		failures.append("default: barge-in sent response.cancel + truncate: cancelled=%d %s" % [ev["cancelled"], str(sent_types.slice(-3))])
	var turns_after_cancel: int = ev["turns"].size()
	_pump(h, func() -> bool: return false, 0.6)  # the server's cancelled done and late deltas
	if ev["turns"].size() != turns_after_cancel or ev["speaking"][-1] != false:
		failures.append("default: nothing of the cancelled reply is played or turned")
	print("      default: barge-in ok, played_ms=%d" % int(transport.played_ms()))
	# Synthetic mic audio -> server VAD -> transcript -> a server-initiated reply.
	var chunk: PackedByteArray = _tone(0.1)
	for _i: int in range(26):
		session.push_audio(chunk)
	if not _pump(h, func() -> bool: return not ev["transcripts"].is_empty()):
		failures.append("default: no server transcript after 2.6 s of audio")
	elif ev["transcripts"] != ["cat"]:
		failures.append("default: server transcript %s" % str(ev["transcripts"]))
	if not _pump(h, func() -> bool: return ev["speaking"].size() >= 4 and ev["speaking"][-1] == false):
		failures.append("default: the server-initiated reply did not play out: %s" % str(ev["speaking"]))
	print("      default: mic audio -> transcript %s, server reply played (speaking %s)" % [str(ev["transcripts"]), str(ev["speaking"])])
	if float(session.usage()["audioSecondsIn"]) < 2.5:
		failures.append("default: input audio seconds metered: %s" % str(session.usage()))
	# End: usage posted, quota reflects the session.
	session.parent_stop()
	if not _pump(h, func() -> bool: return not ev["ended"].is_empty()):
		failures.append("default: end did not complete")
	else:
		var summary: Dictionary = ev["ended"][0][1]
		print("      default: ended %s serverAck=%s quota=%s" % [ev["ended"][0][0], str(summary["serverAck"]), str(summary["quota"])])
		if not bool(summary["serverAck"]) or float(summary["quota"]["usedSeconds"]) <= 0.0:
			failures.append("default: the server acknowledged the end and charged the session: %s" % str(summary))
	_free(h)
	return failures


func _scenario_norealtime(base: String) -> Array:
	var failures: Array = []
	var h: Dictionary = _make(base, "norealtime-%d" % (Time.get_ticks_usec() % 100000))
	var session: RefCounted = h["session"]
	var ev: Dictionary = h["ev"]
	if not _wait_ready(h):
		failures.append("norealtime: not ready: %s fell_back=%s" % [str(session.state_history()), str(ev["fell_back"])])
	elif session.transport_mode() != "turns":
		failures.append("norealtime: expected the turns path, got %s" % session.transport_mode())
	session.send_transcript("cat", {"phase": "answer", "stepId": "s02_cat", "outcome": "correct", "matched": "cat", "lessonAction": "next_question"})
	if not _pump(h, func() -> bool: return ev["turns"].size() >= 1):
		failures.append("norealtime: no REST turn reply")
	elif String(ev["turns"][0]["speech"]) != "Great! It's a cat!" or ev["tools"] != [["show_card", {"assetId": "cat"}]]:
		failures.append("norealtime: validated turn + card: %s / %s" % [str(ev["turns"][0]), str(ev["tools"])])
	print("      norealtime: %s transport=%s turn_log=%s" % [str(session.state_history()), session.transport_mode(), str(session.turn_log())])
	session.end("scene")
	_pump(h, func() -> bool: return not ev["ended"].is_empty(), 3.0)
	if ev["ended"].is_empty() or not bool(ev["ended"][0][1]["serverAck"]):
		failures.append("norealtime: end acknowledged: %s" % str(ev["ended"]))
	_free(h)
	return failures


func _scenario_drop(base: String) -> Array:
	var failures: Array = []
	var h: Dictionary = _make(base, "drop-%d" % (Time.get_ticks_usec() % 100000))
	var session: RefCounted = h["session"]
	var ev: Dictionary = h["ev"]
	if not _wait_ready(h):
		_free(h)
		return ["drop: not ready"]
	session.send_transcript("apple", {"phase": "answer", "outcome": "correct", "lessonAction": "next_question"})
	if not _pump(h, func() -> bool: return ev["turns"].size() >= 1 and not session.is_reply_open()):
		failures.append("drop: the first reply did not finish")
	# The mock closes the socket after that reply; the client reconnects once.
	if not _pump(h, func() -> bool: return session.reconnect_count() == 1 and session.is_ready()):
		failures.append("drop: no reconnect after the socket closed: state=%s history=%s" % [session.get_state(), str(session.state_history())])
	print("      drop: %s reconnects=%d ready=%s" % [str(session.state_history()), session.reconnect_count(), str(session.is_ready())])
	# Still usable after the reconnect.
	session.send_transcript("banana", {"phase": "answer", "outcome": "correct", "lessonAction": "next_question"})
	if not _pump(h, func() -> bool: return ev["turns"].size() >= 2 and not session.is_reply_open()):
		failures.append("drop: no reply after the reconnect")
	session.end("scene")
	_pump(h, func() -> bool: return not ev["ended"].is_empty(), 3.0)
	_free(h)
	return failures


func _scenario_exhausted(base: String) -> Array:
	var failures: Array = []
	var h: Dictionary = _make(base, "exhausted-%d" % (Time.get_ticks_usec() % 100000))
	var session: RefCounted = h["session"]
	var ev: Dictionary = h["ev"]
	_wait_ready(h)
	_pump(h, func() -> bool: return not ev["ended"].is_empty(), 3.0)
	if ev["fell_back"] != ["quota_exhausted"] or session.is_ready():
		failures.append("exhausted: fell_back quota_exhausted expected, got %s (state %s)" % [str(ev["fell_back"]), session.get_state()])
	var minted: bool = false
	for entry: Dictionary in (h["api"] as RefCounted).request_log():
		if String(entry.get("kind", "")) == "token" and entry.has("path"):
			minted = true
	if minted:
		failures.append("exhausted: no token may be minted")
	print("      exhausted: fell_back=%s quota=%s" % [str(ev["fell_back"]), str(session.server_quota())])
	_free(h)
	return failures


func _scenario_banned(base: String) -> Array:
	var failures: Array = []
	var h: Dictionary = _make(base, "banned-%d" % (Time.get_ticks_usec() % 100000))
	var session: RefCounted = h["session"]
	var ev: Dictionary = h["ev"]
	if not _wait_ready(h):
		_free(h)
		return ["banned: not ready"]
	session.send_transcript("cat", {"phase": "answer", "outcome": "retry", "lessonAction": "retry"})
	if not _pump(h, func() -> bool: return not ev["replaced"].is_empty()):
		failures.append("banned: the reply was not replaced: subtitles=%s" % str(ev["subtitles"]))
	else:
		if ev["replaced"][0] != TurnValidator.fallback_turn() or not ev["turns"].is_empty():
			failures.append("banned: replaced by the fallback, no turn: %s / %s" % [str(ev["replaced"]), str(ev["turns"])])
		for line: String in ev["subtitles"]:
			if line.to_lower().contains("stupid"):
				failures.append("banned: the banned word reached a subtitle")
	_pump(h, func() -> bool: return false, 0.5)
	if session.is_reply_open() or (h["transport"] as RefCounted).is_responding():
		failures.append("banned: the reply is closed after the replacement")
	print("      banned: replaced=%d last_subtitle='%s'" % [ev["replaced"].size(), str(ev["subtitles"][-1]) if not ev["subtitles"].is_empty() else ""])
	session.end("scene")
	_pump(h, func() -> bool: return not ev["ended"].is_empty(), 3.0)
	_free(h)
	return failures


func _scenario_deny(base: String) -> Array:
	var failures: Array = []
	var h: Dictionary = _make(base, "deny-%d" % (Time.get_ticks_usec() % 100000))
	var ev: Dictionary = h["ev"]
	_wait_ready(h)
	_pump(h, func() -> bool: return not ev["ended"].is_empty(), 3.0)
	if ev["fell_back"] != ["not_approved"]:
		failures.append("deny: fell_back not_approved expected, got %s" % str(ev["fell_back"]))
	print("      deny: fell_back=%s" % str(ev["fell_back"]))
	_free(h)
	return failures


## The bridge's public surface, as FreeChatController.attach_to_bridge reads it.
class BridgeStub:
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


## Free chat over the real client. The presenter is a real CloudTutorProvider
## (what the classroom binds); only its `turn_ready` is observed, exactly as
## `tutor_scene._on_turn_ready` would.
func _scenario_chat(base: String) -> Array:
	var failures: Array = []
	var h: Dictionary = _make(base, "norealtime-chat-%d" % (Time.get_ticks_usec() % 100000))
	if h.is_empty():
		return ["chat: loopback test override refused"]
	var session: RefCounted = h["session"]
	var api: RefCounted = h["api"]
	if not _wait_ready(h) or not session.is_turns_mode():
		_free(h)
		return ["chat: the lesson session did not come up on the turns path: %s" % str(session.state_history())]
	var provider: RefCounted = ProviderScript.new()
	provider.set_cloud_session(session)
	var presented: Array = []
	provider.turn_ready.connect(func(t: Dictionary) -> void: presented.append(t))
	var controller: RefCounted = FreeChatScript.attach_to_bridge(BridgeStub.new(api, provider, session))
	var ev: Dictionary = {"ready": [], "chat": [], "unavailable": [], "ended": [], "modes": []}
	controller.chat_ready.connect(func(i: Dictionary) -> void: ev["ready"].append(i))
	controller.chat_turn.connect(func(t: Dictionary, m: Dictionary) -> void: ev["chat"].append([t, m]))
	controller.chat_unavailable.connect(func(c: String) -> void: ev["unavailable"].append(c))
	controller.chat_ended.connect(func(r: String) -> void: ev["ended"].append(r))
	controller.mode_changed.connect(func(m: String) -> void: ev["modes"].append(m))
	controller.set_response_max_words(8)
	if not controller.enter_free_chat():
		_free(h)
		return ["chat: enter_free_chat refused: %s" % str(ev["unavailable"])]
	if not _pump(h, func() -> bool: return not ev["ready"].is_empty() or not ev["unavailable"].is_empty()):
		failures.append("chat: no session reply: %s" % str(ev))
	if ev["unavailable"].is_empty() and (presented.size() != 1 or String(presented[0]["speech"]) != FreeChatScript.GREETING):
		failures.append("chat: greeting through turn_ready: %s" % str(presented))
	print("      chat: session=%s config=%s" % [controller.session_id(), str(controller.chat_config())])
	var script: Array = [
		["what do cats eat", "Cats eat cat food and drink water.", "mock", ""],
		["and dogs?", "Dogs eat dog food and love bones.", "mock", ""],
		["what is your phone number", "Let's keep that private! Tell me your favorite animal instead.", "safety", "personal_data"],
		["sing a song please", "I love to sing! La la la.", "mock", ""],
	]
	for row: Array in script:
		var count: int = presented.size()
		if not controller.intercept_turn(String(row[0]), "answer"):
			failures.append("chat: intercept_turn refused '%s'" % row[0])
			continue
		if not _pump(h, func() -> bool: return presented.size() > count):
			failures.append("chat: no reply for '%s'" % row[0])
			continue
		var turn: Dictionary = presented[-1]
		var meta: Dictionary = ev["chat"][-1][1]
		if String(turn["speech"]) != String(row[1]) or String(turn["lessonAction"]) != "retry":
			failures.append("chat: '%s' -> %s" % [row[0], str(turn)])
		if String(meta["provider"]) != String(row[2]) or String(meta["redirected"]) != String(row[3]):
			failures.append("chat: meta for '%s': %s" % [row[0], str(meta)])
		if String(row[0]) == "sing a song please" and (not bool(meta["capped"]) or int(meta["responseMaxWords"]) != 8):
			failures.append("chat: the 8-word cap was applied server side: %s" % str(meta))
	if not ev["chat"].is_empty() and int(ev["chat"][-1][1]["historyTurns"]) != 4:
		failures.append("chat: the server's rolling window counted 4 exchanges: %s" % str(ev["chat"][-1][1]))
	var used: bool = false
	for entry: Dictionary in api.request_log():
		if entry.has("path") and String(entry["kind"]) == "turn":
			used = true
			if (entry["headerNames"] as Array).has("Authorization"):
				failures.append("chat: a tutor route carried the sign-in header")
	if not used:
		failures.append("chat: no turn request left the client")
	controller.return_to_lesson()
	if not _pump(h, func() -> bool: return controller.get_state() == "idle", 3.0):
		failures.append("chat: /end not acknowledged: state=%s" % controller.get_state())
	if controller.mode() != "lesson" or ev["ended"] != ["return_to_lesson"] or String(presented[-1]["lessonAction"]) != "jump_step":
		failures.append("chat: return_to_lesson: mode=%s ended=%s last=%s" % [controller.mode(), str(ev["ended"]), str(presented[-1])])
	if not session.is_ready():
		failures.append("chat: the lesson session must still be ready afterwards: %s" % session.get_state())
	print("      chat: %d replies, log=%s" % [ev["chat"].size(), str(controller.turn_log())])
	session.end("scene")
	_pump(h, func() -> bool: return not h["ev"]["ended"].is_empty(), 3.0)
	_free(h)
	# chatoff*: the Worker's 403 feature_disabled -> back to the lesson kindly.
	var h2: Dictionary = _make(base, "chatoff-norealtime-%d" % (Time.get_ticks_usec() % 100000))
	if not _wait_ready(h2):
		_free(h2)
		return failures + ["chatoff: lesson session not ready"]
	var provider2: RefCounted = ProviderScript.new()
	provider2.set_cloud_session(h2["session"])
	var presented2: Array = []
	provider2.turn_ready.connect(func(t: Dictionary) -> void: presented2.append(t))
	var c2: RefCounted = FreeChatScript.attach_to_bridge(BridgeStub.new(h2["api"], provider2, h2["session"]))
	var refused: Array = []
	c2.chat_unavailable.connect(func(c: String) -> void: refused.append(c))
	c2.enter_free_chat()
	if not _pump(h2, func() -> bool: return not refused.is_empty()):
		failures.append("chatoff: no refusal arrived")
	elif refused != ["feature_disabled"] or c2.mode() != "lesson" or presented2.size() != 1 or String(presented2[0]["speech"]) != FreeChatScript.NOT_AVAILABLE:
		failures.append("chatoff: %s mode=%s presented=%s" % [str(refused), c2.mode(), str(presented2)])
	print("      chatoff: refused=%s" % str(refused))
	(h2["session"] as RefCounted).end("scene")
	_pump(h2, func() -> bool: return not h2["ev"]["ended"].is_empty(), 3.0)
	_free(h2)
	return failures
