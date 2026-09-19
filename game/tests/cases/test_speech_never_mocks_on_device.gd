extends RefCounted

## The mock must never be reachable on a real device.
##
## This guards a bug that shipped and was found during the Android audit. The
## backend selector tested `OS.has_feature("ios")` before falling through to
## `MockSpeechBackend`. On Android neither branch matched, so a real device got
## the MOCK -- whose `is_available()` returns true and whose `next_transcript` is
## the canned string `"milk"`.
##
## The consequence is the reason this test exists rather than a comment: the
## Speak button would appear on a build with no speech support, and shortly after
## any tap the game would accept `"milk"` whether or not the child had made a
## sound. Every speaking task would pass without speech. For a product whose
## whole purpose is a child practising English aloud, that failure mode is worse
## than a missing feature, because it looks like success.
##
## Asserted on the SOURCE rather than by running the selector, because the
## selector's answer depends on the platform the suite happens to run on -- and
## the suite runs on macOS, which is exactly the one platform where choosing the
## mock is correct. A behavioural test here would pass on the desktop while the
## device build was broken, which is how this survived in the first place.

const SERVICE_PATH: String = "res://scripts/speech/speech_service.gd"
const MOCK_PATH: String = "res://scripts/speech/mock_speech_backend.gd"


func test_name() -> String:
	return "speech_never_mocks_on_device"


func run():
	var failures: Array = []
	failures.append_array(_test_the_device_guard_covers_every_mobile_platform())
	failures.append_array(_test_the_mock_is_still_dangerous_enough_to_guard())
	failures.append_array(_test_the_fallback_is_honest())
	return failures


func _source() -> String:
	if not FileAccess.file_exists(SERVICE_PATH):
		return ""
	return FileAccess.get_file_as_string(SERVICE_PATH)


func _test_the_device_guard_covers_every_mobile_platform():
	var failures: Array = []
	var source: String = _source()
	if source.is_empty():
		return ["speech_service.gd could not be read"]

	if not source.contains('OS.has_feature("mobile")'):
		failures.append('the device guard does not test `OS.has_feature("mobile")`. '
				+ 'Testing one platform by name lets the NEXT mobile export fall '
				+ 'through to the mock by omission, which is how this bug happened.')

	# The narrow test must not come back as the thing that gates the mock.
	var ios_guard: int = source.find('if OS.has_feature("ios"):')
	if ios_guard >= 0:
		var after: String = source.substr(ios_guard, 900)
		if after.contains("MockSpeechBackend.new()"):
			failures.append('`OS.has_feature("ios")` guards the fallthrough to the mock '
					+ "again. Android is not iOS; it would get the mock.")
	return failures


## If the mock ever became inert, this guard would be protecting nothing and
## should be re-read rather than trusted. So the danger is asserted too.
func _test_the_mock_is_still_dangerous_enough_to_guard():
	var failures: Array = []
	if not FileAccess.file_exists(MOCK_PATH):
		return failures
	var mock: String = FileAccess.get_file_as_string(MOCK_PATH)
	var claims_available: bool = mock.contains("func is_available() -> bool:") \
			and mock.contains("return true")
	var has_canned: bool = mock.contains("next_transcript")
	if not (claims_available and has_canned):
		failures.append("the mock no longer reports itself available with a canned "
				+ "transcript. That may be fine -- but this guard was written against "
				+ "that behaviour, so re-read it rather than assuming it still applies.")
	return failures


## Reporting "unavailable" is only safe because the game is fully playable
## without speech. That is asserted elsewhere (`test_speech_never_required`);
## here we only check the selector reaches for the honest no-op rather than
## inventing something.
func _test_the_fallback_is_honest():
	var failures: Array = []
	var source: String = _source()
	if source.is_empty():
		return failures
	var guard: int = source.find('OS.has_feature("mobile")')
	if guard < 0:
		return failures
	var branch: String = source.substr(guard, 1400)
	if not branch.contains('_set_backend(SpeechBackend.new(), "unavailable")'):
		failures.append("a mobile device with no recognizer does not fall back to the "
				+ "plain, honest `SpeechBackend` reporting 'unavailable'")
	return failures
