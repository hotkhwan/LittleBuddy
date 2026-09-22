extends RefCounted

## AI PATH, END TO END -- the SERVER legs of the chain seen from the game's own
## REST client, against the DEPLOYED DEVELOPMENT Worker (AI E2E verification,
## 2026-09-22; see docs/AI_E2E_VERIFICATION.md). Runs ONLY when the operator sets
##
##   LD_TUTOR_DEV_URL=https://<the dev Worker> godot --headless --path game --script res://tests/run_tests.gd
##
## Without it the case prints SKIP and passes; the URL lives nowhere in the
## repository. The project flag stays OFF: the client is armed with
## `enable_dev_api_for_tests(url)` (refused on mobile/release builds).
##
## What it records, per turn, for a LESSON session (three scripted steps of
## `animals_cat_dog`: correct, incorrect, unclear) and a CHAT session (three
## synthetic adult questions): the Worker's `provider` label and `fallback`
## reason, `contextSource`, the server-measured `latencyMs`, token usage, and
## the client validator's verdict on the RAW `turn`. Every transcript is a
## fixed adult string; no audio, no child.
##
## What it ASSERTS (green means the contract held, not that Workers AI served):
##   * every raw server turn passes the client validator (emotion / gesture /
##     visual / lessonAction on the allowlists, text limits, no URL, no banned
##     word) -- the validated-turn stage;
##   * every turn body names its `provider` and carries `usage.latencyMs`;
##   * a chat turn is `mode: chat`, arrives with `lessonAction: "none"` on the
##     wire (mapped to `retry` by the FreeChatController before validation,
##     as the client does) and honours the word cap;
##   * both sessions end with the server's acknowledgement.
## Which provider served is PRINTED as evidence (`AI-E2E: ...`), including the
## mock fallback and its reason when Workers AI did not answer in time; the
## doc reads those lines. Not asserting `workers_ai` here keeps the suite an
## honest reporter rather than a monitor of Cloudflare capacity.

const ApiScript := preload("res://scripts/tutor/cloud/cloud_tutor_api.gd")
const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")

const LESSON: String = "animals_cat_dog"
const LESSON_STEPS: Array = [
	{"transcript": "cat", "context": {"stepId": "s02_cat", "outcome": "correct", "matched": "cat", "lessonAction": "next_question"}},
	{"transcript": "a bird", "context": {"stepId": "s04_dog", "outcome": "incorrect", "matched": "", "lessonAction": "retry"}},
	{"transcript": "why does the dog say woof because it is happy explain", "context": {"stepId": "s05_dog_sound", "outcome": "unclear", "matched": "", "lessonAction": "give_hint"}},
]
const CHAT_LINES: Array = ["What does apple mean?", "Can you tell me a color word?", "Why is the sky blue and can you explain it because I am curious"]
## The Worker waits up to its provider timeout (6 s) before the mock answers; allow for it.
const ROUND_TRIP_SECONDS: float = 25.0


func test_name() -> String:
	return "ai_e2e_dev_provider"


func run():
	var failures: Array = []
	if TutorFlags.cloud_enabled():
		return ["this suite must run with the cloud flag OFF (the LD_TUTOR_DEV_URL hatch is used instead)"]
	var url: String = OS.get_environment(ApiScript.DEV_URL_ENV).strip_edges().trim_suffix("/")
	if url.is_empty():
		print("    SKIP ai e2e dev provider: LD_TUTOR_DEV_URL is not set")
		return failures
	var client_id: String = "ld-e2e-%d-%d" % [int(Time.get_unix_time_from_system()), randi() % 100000]
	var api: RefCounted = ApiScript.new()
	api.configure(client_id)
	if not api.enable_dev_api_for_tests(url):
		return ["ai e2e: enable_dev_api_for_tests refused %s (https only, must equal LD_TUTOR_DEV_URL)" % url]
	api.set_timeout_seconds(ROUND_TRIP_SECONDS)
	var replies: Array = []
	api.completed.connect(func(kind: String, result: Dictionary) -> void: replies.append([kind, result]))

	# Sign in (dev), consent, then the two sessions.
	var r: Dictionary = _call(api, replies, func() -> bool: return api.sign_in_dev(""))
	if not bool(r.get("ok", false)) or not bool(api.has_approval()):
		return ["ai e2e: dev sign-in failed: %s" % str(_brief(r))]
	r = _call(api, replies, func() -> bool: return api.grant_consent(ApiScript.CONSENT_AI_TUTOR))
	if not bool(r.get("ok", false)):
		return ["ai e2e: consent failed: %s" % str(_brief(r))]
	print("    AI-E2E: signed in (dev) + ai_tutor consent on %s" % url.get_slice("://", 1).get_slice("/", 0))

	failures.append_array(_lesson_session(api, replies))
	failures.append_array(_chat_session(api, replies))
	return failures


func _lesson_session(api: RefCounted, replies: Array):
	var failures: Array = []
	var r: Dictionary = _call(api, replies, func() -> bool: return api.create_session(LESSON, ApiScript.MODE_LESSON))
	var body: Dictionary = r.get("body", {})
	var sid: String = String(body.get("sessionId", ""))
	if not bool(r.get("ok", false)) or sid.is_empty() or not bool(body.get("lessonKnown", false)):
		return ["ai e2e lesson: session not created: %s" % str(_brief(r))]
	print("    AI-E2E lesson: session=%s mode=%s entitlement=%s quota=%s" % [sid, String(body.get("mode", "")), String(body.get("entitlement", "")), str(ApiScript.quota_of(body))])
	var providers: Dictionary = {}
	for i: int in range(LESSON_STEPS.size()):
		var step: Dictionary = LESSON_STEPS[i]
		var key: String = "%s:e2e%d" % [sid, i + 1]
		var t: Dictionary = _call(api, replies, func() -> bool: return api.submit_turn(sid, key, String(step["transcript"]), step["context"], 0.0))
		var tb: Dictionary = t.get("body", {})
		if not bool(t.get("ok", false)) or not tb.has("turn"):
			failures.append("ai e2e lesson: turn %d failed: %s" % [i + 1, str(_brief(t))])
			continue
		var verdict: Dictionary = TurnValidator.validate(tb["turn"])
		var provider: String = String(tb.get("provider", ""))
		var fallback: String = str(tb.get("fallback", "")) if tb.get("fallback", null) != null else ""
		var usage: Dictionary = tb.get("usage", {})
		var label: String = provider + ("/" + fallback if not fallback.is_empty() else "")
		providers[label] = int(providers.get(label, 0)) + 1
		var turn: Dictionary = tb["turn"]
		print("    AI-E2E lesson turn %d: provider=%s fallback=%s contextSource=%s latencyMs=%d tokens=%d/%d valid=%s reasons=%s emotion=%s gesture=%s visual=%s action=%s speech=\"%s\"" % [
			i + 1, provider, fallback if not fallback.is_empty() else "null", String(tb.get("contextSource", "")), int(_num(usage.get("latencyMs", 0))),
			int(_num(usage.get("llmInputTokens", 0))), int(_num(usage.get("llmOutputTokens", 0))), str(verdict.get("valid", false)), str(verdict.get("reasons", [])),
			String(turn.get("emotion", "")), String(turn.get("gesture", "")), str(turn.get("visual", {})), String(turn.get("lessonAction", "")), String(turn.get("speech", ""))])
		if not bool(verdict.get("valid", false)):
			failures.append("ai e2e lesson: turn %d failed the client validator: %s" % [i + 1, str(verdict.get("reasons", []))])
		if provider.is_empty() or not usage.has("latencyMs"):
			failures.append("ai e2e lesson: turn %d body must name its provider and latency: %s" % [i + 1, str(tb.keys())])
		if String(tb.get("contextSource", "")) != "server":
			failures.append("ai e2e lesson: a known lesson's context must be resolved by the server, got %s" % String(tb.get("contextSource", "")))
	print("    AI-E2E lesson: provider histogram=%s" % str(providers))
	var e: Dictionary = _call(api, replies, func() -> bool: return api.end_session(sid, "e2e_done"))
	if not bool(e.get("ok", false)) or String(e.get("body", {}).get("sessionId", "")) != sid:
		failures.append("ai e2e lesson: /end not acknowledged: %s" % str(_brief(e)))
	else:
		print("    AI-E2E lesson: ended, server usage=%s" % str(e.get("body", {}).get("usage", {})))
	return failures


func _chat_session(api: RefCounted, replies: Array):
	var failures: Array = []
	var r: Dictionary = _call(api, replies, func() -> bool: return api.create_session("", ApiScript.MODE_CHAT))
	var body: Dictionary = r.get("body", {})
	var sid: String = String(body.get("sessionId", ""))
	if not bool(r.get("ok", false)) or sid.is_empty():
		# FREE_CHAT_ENABLED is a DEV_MODE-only feature; a 403 feature_disabled is a valid Worker answer.
		print("    AI-E2E chat: not available on this Worker (%s); chat legs NOT REACHED" % str(_brief(r)))
		return failures
	var max_words: int = int(_num(body.get("chat", {}).get("responseMaxWords", 0)))
	print("    AI-E2E chat: session=%s mode=%s chat=%s" % [sid, String(body.get("mode", "")), str(body.get("chat", {}))])
	var providers: Dictionary = {}
	for i: int in range(CHAT_LINES.size()):
		var key: String = "%s:e2ec%d" % [sid, i + 1]
		var line: String = String(CHAT_LINES[i])
		var t: Dictionary = _call(api, replies, func() -> bool: return api.submit_chat_turn(sid, key, line, 0))
		var tb: Dictionary = t.get("body", {})
		if not bool(t.get("ok", false)) or not tb.has("turn"):
			failures.append("ai e2e chat: turn %d failed: %s" % [i + 1, str(_brief(t))])
			continue
		# The Worker pins a chat reply to `lessonAction: "none"` (chat_provider.ts);
		# the FreeChatController maps it to `retry` ("keep listening") before the
		# validator sees it -- validated here the same way.
		var candidate: Dictionary = (tb["turn"] as Dictionary).duplicate(true)
		var wire_action: String = String(candidate.get("lessonAction", ""))
		if wire_action == "none":
			candidate["lessonAction"] = "retry"
		var verdict: Dictionary = TurnValidator.validate(candidate)
		var provider: String = String(tb.get("provider", ""))
		var fallback: String = str(tb.get("fallback", "")) if tb.get("fallback", null) != null else ""
		var usage: Dictionary = tb.get("usage", {})
		var label: String = provider + ("/" + fallback if not fallback.is_empty() else "")
		providers[label] = int(providers.get(label, 0)) + 1
		var turn: Dictionary = tb["turn"]
		if wire_action != "none":
			failures.append("ai e2e chat: turn %d must arrive with lessonAction none on the wire, got %s" % [i + 1, wire_action])
		var words: int = String(turn.get("speech", "")).split(" ", false).size()
		print("    AI-E2E chat turn %d: provider=%s fallback=%s mode=%s chat=%s latencyMs=%d valid=%s reasons=%s emotion=%s gesture=%s words=%d speech=\"%s\"" % [
			i + 1, provider, fallback if not fallback.is_empty() else "null", String(tb.get("mode", "")), str(tb.get("chat", {})), int(_num(usage.get("latencyMs", 0))),
			str(verdict.get("valid", false)), str(verdict.get("reasons", [])), String(turn.get("emotion", "")), String(turn.get("gesture", "")), words, String(turn.get("speech", ""))])
		if not bool(verdict.get("valid", false)):
			failures.append("ai e2e chat: turn %d failed the client validator: %s" % [i + 1, str(verdict.get("reasons", []))])
		if String(tb.get("mode", "")) != "chat" or provider.is_empty():
			failures.append("ai e2e chat: turn %d must be mode=chat with a provider label: %s" % [i + 1, str(tb.keys())])
		if max_words > 0 and words > max_words:
			failures.append("ai e2e chat: turn %d has %d words over the %d cap" % [i + 1, words, max_words])
	print("    AI-E2E chat: provider histogram=%s" % str(providers))
	var e: Dictionary = _call(api, replies, func() -> bool: return api.end_session(sid, "e2e_done"))
	if not bool(e.get("ok", false)) or String(e.get("body", {}).get("sessionId", "")) != sid:
		failures.append("ai e2e chat: /end not acknowledged: %s" % str(_brief(e)))
	return failures


## Sends one request and pumps the client until its reply lands (or the round trip times out).
func _call(api: RefCounted, replies: Array, send: Callable) -> Dictionary:
	var before: int = replies.size()
	if not bool(send.call()):
		return {"ok": false, "code": "not_sent"}
	var deadline: int = Time.get_ticks_msec() + int(ROUND_TRIP_SECONDS * 1000.0)
	var last: int = Time.get_ticks_msec()
	while replies.size() <= before and Time.get_ticks_msec() < deadline:
		var now: int = Time.get_ticks_msec()
		api.advance(maxf(float(now - last) / 1000.0, 0.001))
		last = now
		OS.delay_msec(5)
	return replies[-1][1] if replies.size() > before else {"ok": false, "code": "no_reply"}


static func _brief(result: Dictionary) -> Dictionary:
	return {"ok": result.get("ok", false), "status": result.get("status", 0), "code": result.get("code", ""), "message": result.get("message", "")}


static func _num(value: Variant) -> float:
	return float(value) if value is float or value is int else 0.0
