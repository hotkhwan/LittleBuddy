extends RefCounted

## SpeechRecognitionProvider -- the tutor's view of "the child is talking".
##
## One LISTENING SESSION at a time, and every session ends in EXACTLY ONE
## terminal state:
##
##   idle -> start -> listening -> partial* -> processing? -> final
##                                                        |-> retry
##                                     (never opened)    |-> unavailable
##
##   start        the microphone was asked for (an intentional press, or the
##                hands-free session re-arming between turns);
##   listening    it is open;
##   partial      an interim hypothesis arrived (UI may show it; nothing acts on it);
##   processing   we asked the recogniser to wrap up and are waiting for its
##                final hypothesis (a manual stop, or the hard cap);
##   final        a recognised transcript -- the ONLY state a lesson acts on;
##   retry        nothing usable: timeout, cancelled, misheard by the backend;
##                voiced by the scene as "Let's try together!", never a failure;
##   unavailable  no recogniser / no permission: the scene offers the offline
##                path ("Let's play with Bunny instead!").
##
## Rules every implementation keeps (tests drive them):
##   * the mic opens only on `begin_listening()` -- never on construction,
##     never on a timer;
##   * it NEVER opens while synthesis is speaking (`begin_listening()` returns
##     false) and a synthesis `started` while listening CANCELS the session
##     (echo prevention: the speaker and the mic are inches apart);
##   * hard caps: `NO_PARTIAL_CAP_SECONDS` (4 s) without a partial, then
##     `AFTER_PARTIAL_CAP_SECONDS` (6 s) after the last partial; the provider
##     keeps its own watchdog even though `SpeechService` has one;
##   * a final is never fabricated: `simulated_transcript()` exists for the
##     headless suite and the dev panel only, and is refused on a mobile build
##     (the same guard that keeps `MockSpeechBackend` off devices);
##   * no transcript is retained after the session: it is emitted and dropped.

signal state_changed(from_state: String, to_state: String)
signal partial(text: String)
signal final(text: String)
## Accompanies the `retry` / `unavailable` terminal: why.
signal failed(reason: String)
## After the terminal state of every session, exactly once: `final`, `retry` or `unavailable`.
signal session_ended(terminal_state: String)
## A `begin_listening()` that opened nothing (speaking, already listening).
signal refused(reason: String)

const STATE_IDLE: String = "idle"
const STATE_START: String = "start"
const STATE_LISTENING: String = "listening"
const STATE_PARTIAL: String = "partial"
const STATE_PROCESSING: String = "processing"
const STATE_FINAL: String = "final"
const STATE_RETRY: String = "retry"
const STATE_UNAVAILABLE: String = "unavailable"
const TERMINAL_STATES: Array[String] = [STATE_FINAL, STATE_RETRY, STATE_UNAVAILABLE]

const REASON_SPEAKING: String = "synthesis_speaking"
const REASON_BUSY: String = "already_listening"
const REASON_PLAYBACK: String = "playback_started"
const REASON_CANCELLED: String = "cancelled"
const REASON_TIMEOUT: String = "timeout"
const REASON_UNAVAILABLE: String = "unavailable"
const REASON_NO_RESULT: String = "no_result"

## Mirror `SpeechService`'s caps; the provider's own watchdog fires a little
## after the service's grace so the service gets the first word.
const NO_PARTIAL_CAP_SECONDS: float = 4.0
const AFTER_PARTIAL_CAP_SECONDS: float = 6.0
const WATCHDOG_GRACE_SECONDS: float = 1.0

var _state: String = STATE_IDLE
var _session_id: int = 0
var _session_open: bool = false
var _age: float = 0.0
var _since_partial: float = 0.0
var _had_partial: bool = false
var _history: Array = []
var _synth: Object = null
var _continuous: bool = false
var _rearm_pending: bool = false
var _rearm_delay: float = 0.0
var _rearm_delay_left: float = 0.0
var _locale: String = "en-US"
## Session age at which a wrap-up (manual stop or cap) gives up: -> retry/timeout.
var _stop_deadline: float = 0.0


func provider_name() -> String:
	return "base"


func state() -> String:
	return _state


func is_listening() -> bool:
	return _session_open and (_state == STATE_LISTENING or _state == STATE_PARTIAL or _state == STATE_START)


func has_active_session() -> bool:
	return _session_open


func session_id() -> int:
	return _session_id


## The states of the LAST session in order, e.g. [start, listening, partial, final].
func state_history() -> Array:
	return _history.duplicate()


func is_available() -> bool:
	return false


## Bind the synthesis provider (or anything with `is_speaking()` and a
## `started` signal): a start of playback cancels a live session, and
## `begin_listening()` is refused while it speaks.
func bind_synthesis(synth: Object) -> void:
	if _synth != null and _synth.has_signal("started") and _synth.is_connected("started", on_synthesis_started):
		_synth.disconnect("started", on_synthesis_started)
	_synth = synth
	if _synth != null and _synth.has_signal("started") and not _synth.is_connected("started", on_synthesis_started):
		_synth.connect("started", on_synthesis_started)


## Playback is live somewhere: the bound synthesis provider, the voice pack or
## the platform voice. The mic never opens over any of them.
func is_playback_active() -> bool:
	if _synth != null and _synth.has_method("is_speaking") and bool(_synth.call("is_speaking")):
		return true
	for autoload_name: String in ["Voice", "TtsService"]:
		var node: Node = _autoload(autoload_name)
		if node != null and node.has_method("is_speaking") and bool(node.call("is_speaking")):
			return true
	return false


## Hands-free: after each terminal state, listen again on the next `advance()`
## while playback is silent (the session layer turns this on and off).
func set_continuous(enabled: bool, rearm_delay_seconds: float = 0.2) -> void:
	_continuous = enabled
	_rearm_delay = maxf(rearm_delay_seconds, 0.0)
	if not enabled:
		_rearm_pending = false


func is_continuous() -> bool:
	return _continuous


## Opens a session. False (with `refused`) when playback is live or a session
## is already open. A session that cannot open because the recogniser is
## unavailable DOES open and ends at once in `unavailable`.
func begin_listening(locale: String = "en-US") -> bool:
	_locale = locale
	if _session_open:
		refused.emit(REASON_BUSY)
		return false
	if is_playback_active():
		refused.emit(REASON_SPEAKING)
		return false
	_rearm_pending = false
	_open_session()
	_open_microphone(locale)
	return true


## Asks the recogniser to wrap up and hand over its hypothesis (-> final or retry).
func stop_listening() -> void:
	if not _session_open or _state == STATE_PROCESSING:
		return
	_set_state(STATE_PROCESSING)
	if _stop_deadline <= 0.0:
		_stop_deadline = _age + WATCHDOG_GRACE_SECONDS
	_request_stop()


## Ends the session now as `retry`; a late final for it is dropped.
func cancel(reason: String = REASON_CANCELLED) -> void:
	if not _session_open:
		return
	# Terminal FIRST: the recogniser's stop may hand over a hypothesis
	# synchronously, and a cancelled session must never turn into a final.
	_terminate(STATE_RETRY, reason)
	_request_stop()


## Echo prevention: playback started, so whatever the mic hears next is Aliz.
func on_synthesis_started(_text: Variant = null) -> void:
	_rearm_pending = false
	if _session_open:
		cancel(REASON_PLAYBACK)


## Playback ended: a continuous provider may re-arm on the next `advance()`.
func notify_playback_finished() -> void:
	if _continuous and not _session_open:
		_rearm_pending = true
		_rearm_delay_left = _rearm_delay


## The watchdog and the hands-free re-arm. Called every frame by the owner
## (session or scene); a headless test drives it directly.
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	if _session_open:
		_age += delta
		if _had_partial:
			_since_partial += delta
		if _state == STATE_PROCESSING:
			if _age >= _stop_deadline:
				_terminate(STATE_RETRY, REASON_TIMEOUT)
			return
		var capped: bool = (_had_partial and _since_partial >= AFTER_PARTIAL_CAP_SECONDS) \
				or (not _had_partial and _age >= NO_PARTIAL_CAP_SECONDS)
		if capped:
			# The service caps at the same moment and hands over its hypothesis;
			# our stop is the belt to its braces, and the grace is ours.
			_stop_deadline = _age + WATCHDOG_GRACE_SECONDS
			stop_listening()
		return
	if _continuous and _rearm_pending:
		_rearm_delay_left -= delta
		if _rearm_delay_left <= 0.0 and not is_playback_active():
			_rearm_pending = false
			begin_listening(_locale)


## -- For subclasses ------------------------------------------------------------

func _open_microphone(_locale_value: String) -> void:
	_terminate(STATE_UNAVAILABLE, REASON_UNAVAILABLE)


func _request_stop() -> void:
	pass


## Subclass hooks report what the recogniser did. Each is ignored unless it
## belongs to the open session.
func _on_listening_started() -> void:
	if _session_open and _state == STATE_START:
		_set_state(STATE_LISTENING)


func _on_partial(text: String) -> void:
	if not _session_open or _state == STATE_PROCESSING:
		return
	if text.strip_edges().is_empty():
		return
	_had_partial = true
	_since_partial = 0.0
	if _state != STATE_PARTIAL:
		_set_state(STATE_PARTIAL)
	partial.emit(text)


func _on_final(text: String) -> void:
	if not _session_open:
		return  # a late final for a session that already ended: dropped
	if text.strip_edges().is_empty():
		_terminate(STATE_RETRY, REASON_NO_RESULT)
		return
	_terminate(STATE_FINAL, "", text)


func _on_failed(reason: String) -> void:
	if not _session_open:
		return
	if reason == REASON_UNAVAILABLE or reason.contains("permission") or reason.contains("denied"):
		_terminate(STATE_UNAVAILABLE, reason)
	else:
		_terminate(STATE_RETRY, reason)


func _on_service_session_ended(_outcome: String) -> void:
	if _session_open:
		_terminate(STATE_RETRY, REASON_NO_RESULT)


# -- Internals -------------------------------------------------------------------

func _open_session() -> void:
	_session_id += 1
	_session_open = true
	_age = 0.0
	_since_partial = 0.0
	_had_partial = false
	_stop_deadline = 0.0
	_history.clear()
	_set_state(STATE_START)


func _terminate(terminal: String, reason: String, text: String = "") -> void:
	if not _session_open:
		return
	_session_open = false
	_set_state(terminal)
	match terminal:
		STATE_FINAL:
			final.emit(text)
		_:
			failed.emit(reason)
	session_ended.emit(terminal)
	if _continuous:
		_rearm_pending = true
		_rearm_delay_left = _rearm_delay


func _set_state(next: String) -> void:
	if next == _state and next != STATE_START:
		return
	var previous: String = _state
	_state = next
	_history.append(next)
	state_changed.emit(previous, next)


func _autoload(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(node_name))
