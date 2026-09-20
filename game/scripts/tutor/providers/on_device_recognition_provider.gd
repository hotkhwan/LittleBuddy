extends "res://scripts/tutor/providers/speech_recognition_provider.gd"

## The on-device recogniser behind the tutor: wraps the `SpeechService`
## autoload (iOS plugin on a device, the mock on a desktop, honestly
## `unavailable` on a device without the plugin). No second microphone path
## exists here: the only calls are `start_listening()` / `stop_listening()` on
## the service, whose own privacy tests hold.
##
## ## Simulation (tests and the dev panel only)
##
## `set_simulation_enabled(true)` -- REFUSED on a mobile build, the same
## `OS.has_feature("mobile")` guard that keeps `MockSpeechBackend` off devices
## -- makes `begin_listening()` open a session with NO microphone; the panel
## then calls `simulated_transcript("apple")` (-> partial -> final) or
## `simulated_silence()` (-> retry/timeout). The same caps, the same echo rule,
## the same single terminal apply, so the whole loop is testable headless.
## A simulated transcript never reaches a session that has a real mic open,
## and nothing here can produce a final on its own.

const SPEECH_SERVICE_PATH: String = "SpeechService"

var _service: Node = null
var _bound: Node = null
var _simulation: bool = false
var _session_is_simulated: bool = false


func provider_name() -> String:
	return "on_device"


## Inject the service (a test builds one with a scripted backend); default is
## the autoload.
func set_speech_service(service: Node) -> void:
	_unbind()
	_service = service
	_bind()


func speech_service() -> Node:
	if _service == null or not is_instance_valid(_service):
		_service = _autoload(SPEECH_SERVICE_PATH)
		_bind()
	return _service


func is_available() -> bool:
	if _simulation:
		return true
	var service: Node = speech_service()
	return service != null and service.has_method("is_available") and bool(service.call("is_available"))


func is_simulation_enabled() -> bool:
	return _simulation


## Desktop / headless only. Returns the resulting flag.
func set_simulation_enabled(enabled: bool) -> bool:
	if enabled and not simulation_allowed():
		_simulation = false
		return false
	_simulation = enabled
	return _simulation


## The mock guard, verbatim in spirit: never on a phone or tablet.
static func simulation_allowed() -> bool:
	return not OS.has_feature("mobile")


## Feeds a transcript into the open SIMULATED session exactly as a recognised
## final would arrive: partial, then final. False when refused.
func simulated_transcript(text: String) -> bool:
	if not simulation_allowed() or not _simulation or not _session_is_simulated or not _session_open:
		return false
	_on_listening_started()
	_on_partial(text)
	_on_final(text)
	return true


## The child said nothing: the simulated session times out (-> retry).
func simulated_silence() -> bool:
	if not simulation_allowed() or not _simulation or not _session_is_simulated or not _session_open:
		return false
	_on_listening_started()
	_on_failed(REASON_TIMEOUT)
	return true


# -- Base hooks ------------------------------------------------------------------

func _open_microphone(locale: String) -> void:
	_session_is_simulated = false
	if _simulation:
		_session_is_simulated = true
		_on_listening_started()
		return
	var service: Node = speech_service()
	if service == null or not service.has_method("start_listening"):
		_terminate(STATE_UNAVAILABLE, REASON_UNAVAILABLE)
		return
	if service.has_method("is_available") and not bool(service.call("is_available")):
		_terminate(STATE_UNAVAILABLE, REASON_UNAVAILABLE)
		return
	service.call("start_listening", locale)
	# The service reports `listening_started` (-> listening) or fails at once.


func _request_stop() -> void:
	if _session_is_simulated:
		return
	var service: Node = _service if _service != null and is_instance_valid(_service) else null
	if service != null and service.has_method("stop_listening"):
		service.call("stop_listening")


func _bind() -> void:
	if _service == null or _bound == _service:
		return
	_bound = _service
	_connect(_service, "listening_started", _on_service_listening_started)
	_connect(_service, "partial_recognized", _on_service_partial)
	_connect(_service, "recognized", _on_service_recognized)
	_connect(_service, "recognition_failed", _on_service_failed)
	_connect(_service, "session_ended", _on_service_ended)


func _unbind() -> void:
	if _bound == null or not is_instance_valid(_bound):
		_bound = null
		return
	for pair: Array in [["listening_started", _on_service_listening_started], ["partial_recognized", _on_service_partial],
			["recognized", _on_service_recognized], ["recognition_failed", _on_service_failed], ["session_ended", _on_service_ended]]:
		if _bound.has_signal(pair[0]) and _bound.is_connected(pair[0], pair[1]):
			_bound.disconnect(pair[0], pair[1])
	_bound = null


static func _connect(node: Node, signal_name: String, callable: Callable) -> void:
	if node.has_signal(signal_name) and not node.is_connected(signal_name, callable):
		node.connect(signal_name, callable)


func _on_service_listening_started() -> void:
	if not _session_is_simulated:
		_on_listening_started()


func _on_service_partial(text: String) -> void:
	if not _session_is_simulated:
		_on_partial(text)


func _on_service_recognized(text: String) -> void:
	if not _session_is_simulated:
		_on_final(text)


func _on_service_failed(reason: String) -> void:
	if not _session_is_simulated:
		_on_failed(reason)


func _on_service_ended(outcome: String) -> void:
	if not _session_is_simulated:
		_on_service_session_ended(outcome)
