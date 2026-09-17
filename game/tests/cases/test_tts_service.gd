extends RefCounted
## Contract tests for `TtsService` -- the only path by which a child hears
## English in this game.
##
## What is being defended here:
##   * Two prompts never talk over each other, and a queued prompt never
##     truncates the one before it. A prompt that gets cut off is, for a
##     pre-reader, a prompt that was never spoken.
##   * The platform call gets PITCH and RATE in the right argument slots.
##     `DisplayServer.tts_speak()` takes (text, voice, volume, pitch, rate,
##     utterance_id, interrupt); swapping the middle two silently produces a
##     deeper adult voice at unchanged speed -- the exact opposite of the slower
##     delivery a four-year-old needs. That bug shipped once.
##   * The delivery is slower than an adult default, and "slow" is slower again.
##   * Nothing crashes, hangs or stays "speaking" forever when there is no voice,
##     no SaveService and no SceneTree.
##
## Headless note: there is no frame loop in the `--script` runner, so the service
## is given a timer factory that captures its safety-timer callbacks; the test
## fires them by hand, one utterance at a time.

const TtsServiceScript := preload("res://scripts/speech/tts_service.gd")
const SERVICE_PATH: String = "res://scripts/speech/tts_service.gd"


func test_name() -> String:
	return "tts_service"


func run():
	var failures: Array = []
	failures.append_array(_test_queue_does_not_truncate())
	failures.append_array(_test_interrupt_clears_queue())
	failures.append_array(_test_empty_text_is_ignored())
	failures.append_array(_test_stale_timer_cannot_cut_a_later_prompt())
	failures.append_array(_test_stop_releases_listeners())
	failures.append_array(_test_queue_is_bounded())
	failures.append_array(_test_child_friendly_rate_and_pitch())
	failures.append_array(_test_duration_estimate_scales_with_rate())
	failures.append_array(_test_platform_argument_order())
	failures.append_array(_test_degrades_without_voice_or_tree())
	return failures


# -- Harness ------------------------------------------------------------------


## Builds a service plus a captured-timer harness.
## Returns { service, timers: Array[Callable], started: Array, finished: Array }.
func _make_service():
	var service = TtsServiceScript.new()
	var timers: Array = []
	var started: Array = []
	var finished: Array = []
	service.set_timer_factory(
		func(_duration: float, callback: Callable) -> void: timers.append(callback)
	)
	service.speech_started.connect(func(text: String) -> void: started.append(text))
	service.speech_finished.connect(func(text: String) -> void: finished.append(text))
	return {"service": service, "timers": timers, "started": started, "finished": finished}


## Fires the safety timer scheduled at `index`, as the platform's "utterance
## ended" callback would.
func _fire(harness, index):
	var timers: Array = harness["timers"]
	if index >= timers.size():
		return false
	var callback: Callable = timers[index]
	callback.call()
	return true


# -- Cases --------------------------------------------------------------------


func _test_queue_does_not_truncate():
	var failures: Array = []
	var harness = _make_service()
	var service = harness["service"]

	service.speak("Good morning!")
	if not service.is_speaking():
		failures.append("queue: speak() should start speaking immediately")
	if service.get_current_text() != "Good morning!":
		failures.append("queue: current text should be the first prompt")

	service.speak("Let's brush our teeth.", false)
	if service.get_current_text() != "Good morning!":
		failures.append(
			"queue: a queued prompt must NOT replace the one being spoken (got '%s')"
			% service.get_current_text()
		)
	if service.get_pending_count() != 1:
		failures.append(
			"queue: expected 1 pending utterance, got %d" % service.get_pending_count()
		)

	_fire(harness, 0)
	if service.get_current_text() != "Let's brush our teeth.":
		failures.append(
			"queue: the queued prompt should start once the first finishes (got '%s')"
			% service.get_current_text()
		)
	if service.get_pending_count() != 0:
		failures.append("queue: pending count should drop to 0 after the queue advances")

	var started: Array = harness["started"]
	var finished: Array = harness["finished"]
	if started != ["Good morning!", "Let's brush our teeth."]:
		failures.append("queue: unexpected speech_started order %s" % str(started))
	if finished != ["Good morning!"]:
		failures.append("queue: unexpected speech_finished order %s" % str(finished))

	service.free()
	return failures


func _test_interrupt_clears_queue():
	var failures: Array = []
	var harness = _make_service()
	var service = harness["service"]

	service.speak("Put on your shoes.")
	service.speak("Shoes.", false)
	service.speak("Can you find the milk?")

	if service.get_current_text() != "Can you find the milk?":
		failures.append(
			"interrupt: an interrupting prompt should become current, got '%s'"
			% service.get_current_text()
		)
	if service.get_pending_count() != 0:
		failures.append("interrupt: an interrupting prompt must drop anything queued behind it")

	var finished: Array = harness["finished"]
	if not finished.has("Put on your shoes."):
		failures.append("interrupt: the interrupted prompt must still emit speech_finished")

	service.free()
	return failures


func _test_empty_text_is_ignored():
	var failures: Array = []
	var harness = _make_service()
	var service = harness["service"]

	service.speak("")
	service.speak("   ")
	service.speak("\t\n", false)
	if service.is_speaking():
		failures.append("empty: blank text must never start an utterance")
	if not harness["started"].is_empty():
		failures.append("empty: blank text must not emit speech_started")

	service.speak("Great job!")
	service.speak("", false)
	if service.get_pending_count() != 0:
		failures.append("empty: blank text must not occupy a queue slot")

	service.free()
	return failures


func _test_stale_timer_cannot_cut_a_later_prompt():
	var failures: Array = []
	var harness = _make_service()
	var service = harness["service"]

	service.speak("Good night!")
	service.speak("Sleep well.")  # interrupts; timer 0 is now stale
	_fire(harness, 0)

	if not service.is_speaking():
		failures.append("stale: a stale safety timer must not end the current utterance")
	if service.get_current_text() != "Sleep well.":
		failures.append("stale: current text changed unexpectedly to '%s'" % service.get_current_text())

	var finished: Array = harness["finished"]
	var night_count: int = 0
	for text in finished:
		if text == "Good night!":
			night_count += 1
	if night_count != 1:
		failures.append(
			"stale: speech_finished for an interrupted prompt should fire exactly once, got %d"
			% night_count
		)

	service.free()
	return failures


func _test_stop_releases_listeners():
	var failures: Array = []
	var harness = _make_service()
	var service = harness["service"]

	service.speak("Let's tidy up.")
	service.speak("Toys away.", false)
	service.stop()

	if service.is_speaking():
		failures.append("stop: service should not still be speaking")
	if service.get_pending_count() != 0:
		failures.append("stop: stop() must clear the queue")
	if not harness["finished"].has("Let's tidy up."):
		failures.append("stop: stop() must release anything awaiting speech_finished")

	# A stale timer arriving after stop() must do nothing at all.
	var finished_before: int = harness["finished"].size()
	_fire(harness, 0)
	if harness["finished"].size() != finished_before:
		failures.append("stop: a timer firing after stop() must not emit again")

	service.stop()  # idempotent
	service.free()
	return failures


func _test_queue_is_bounded():
	var failures: Array = []
	var harness = _make_service()
	var service = harness["service"]

	service.speak("First.")
	for i in range(TtsServiceScript.MAX_QUEUED + 6):
		service.speak("Line %d." % i, false)

	if service.get_pending_count() > TtsServiceScript.MAX_QUEUED:
		failures.append(
			"bounded: queue grew to %d, cap is %d"
			% [service.get_pending_count(), TtsServiceScript.MAX_QUEUED]
		)
	var pending: Array = service.get_pending_texts()
	if pending.is_empty() or String(pending[0]) != "Line 0.":
		failures.append("bounded: the oldest queued prompt should be kept, got %s" % str(pending))

	service.free()
	return failures


func _test_child_friendly_rate_and_pitch():
	var failures: Array = []

	if TtsServiceScript.NORMAL_SPEECH_RATE >= 1.0:
		failures.append(
			"rate: default rate %.2f is not slower than the adult platform default"
			% TtsServiceScript.NORMAL_SPEECH_RATE
		)
	if TtsServiceScript.NORMAL_SPEECH_RATE < 0.6:
		failures.append("rate: default rate is so slow it would sound broken")
	if TtsServiceScript.SLOW_SPEECH_RATE >= TtsServiceScript.NORMAL_SPEECH_RATE:
		failures.append("rate: the \"slow\" setting must be slower than the default")
	if TtsServiceScript.SLOW_SPEECH_RATE < 0.5:
		failures.append("rate: the \"slow\" setting is below the platform's useful range")

	if TtsServiceScript.SPEECH_PITCH < 0.9 or TtsServiceScript.SPEECH_PITCH > 1.2:
		failures.append(
			"pitch: %.2f is outside the warm-but-not-cartoonish band 0.9-1.2"
			% TtsServiceScript.SPEECH_PITCH
		)

	if TtsServiceScript.SPEECH_VOLUME < 60 or TtsServiceScript.SPEECH_VOLUME > 100:
		failures.append(
			"volume: %d must be audible over the sound effects but never maxed by surprise"
			% TtsServiceScript.SPEECH_VOLUME
		)

	var service = TtsServiceScript.new()
	if not is_equal_approx(service.get_speech_rate(), TtsServiceScript.NORMAL_SPEECH_RATE):
		failures.append("rate: with no SaveService the rate should be the child-friendly default")
	service.free()
	return failures


func _test_duration_estimate_scales_with_rate():
	var failures: Array = []
	var service = TtsServiceScript.new()

	var long_line: String = "Can you put the teddy in the toy box please"
	var estimate: float = service._estimate_duration(long_line)
	var words: int = long_line.split(" ", false).size()
	var at_full_rate: float = float(words) / TtsServiceScript.WORDS_PER_SECOND
	if estimate <= at_full_rate:
		failures.append(
			"duration: a slower rate must produce a LONGER estimate (%.2f vs %.2f); "
			% [estimate, at_full_rate]
			+ "an estimate computed at rate 1.0 would cut slow speech short"
		)
	if service._estimate_duration("Hi") < TtsServiceScript.MIN_DURATION_SECONDS:
		failures.append("duration: a one-word prompt should still get the minimum duration")

	service.free()
	return failures


## Source-level guard on the platform call. There is no real voice in the
## headless runner, so the argument ORDER cannot be observed at runtime -- and
## getting it wrong is silent (it sounds like a slightly odd voice, not an
## error). This asserts the order directly.
func _test_platform_argument_order():
	var failures: Array = []
	var file: FileAccess = FileAccess.open(SERVICE_PATH, FileAccess.READ)
	if file == null:
		failures.append("argorder: could not read %s" % SERVICE_PATH)
		return failures
	var source: String = file.get_as_text()
	file.close()

	# rfind: the doc comment at the top of the file also mentions the call.
	var call_start: int = source.rfind("DisplayServer.tts_speak(")
	if call_start == -1:
		failures.append("argorder: no DisplayServer.tts_speak() call found")
		return failures
	# The call spans several lines; take everything up to the closing paren that
	# is on a line of its own.
	var call_end: int = source.find("\n\t)", call_start)
	if call_end == -1:
		call_end = source.find(")", call_start)
	var call_text: String = source.substr(call_start, call_end - call_start)

	var arg_source: String = call_text.substr(call_text.find("(") + 1)
	var args: Array = []
	for raw in arg_source.split(","):
		var arg: String = String(raw).strip_edges()
		# Drop trailing comments and blank fragments.
		var comment: int = arg.find("#")
		if comment != -1:
			arg = arg.substr(0, comment).strip_edges()
		if not arg.is_empty():
			args.append(arg)

	if args.size() < 6:
		failures.append("argorder: expected at least 6 arguments, parsed %s" % str(args))
		return failures

	# (text, voice, volume, pitch, rate, utterance_id, interrupt)
	if not String(args[2]).contains("VOLUME"):
		failures.append("argorder: argument 3 should be the volume, got '%s'" % args[2])
	if not String(args[3]).contains("PITCH"):
		failures.append("argorder: argument 4 must be the PITCH, got '%s'" % args[3])
	if not String(args[4]).contains("rate"):
		failures.append(
			"argorder: argument 5 must be the RATE, got '%s' -- pitch and rate are swapped"
			% args[4]
		)
	return failures


func _test_degrades_without_voice_or_tree():
	var failures: Array = []
	# No timer factory this time: with no SceneTree and no tree membership the
	# service must resolve the utterance itself rather than stay "speaking"
	# forever (that would hang anything awaiting speech_finished).
	var service = TtsServiceScript.new()
	var finished: Array = []
	service.speech_finished.connect(func(text: String) -> void: finished.append(text))

	service.speak("Good night!")
	service.speak("Sleep tight.", false)

	if service.is_speaking():
		failures.append("degrade: with no clock the utterance must resolve, not hang")
	if finished != ["Good night!", "Sleep tight."]:
		failures.append(
			"degrade: both prompts should complete in order even with no voice, got %s"
			% str(finished)
		)
	if service.get_pending_count() != 0:
		failures.append("degrade: the queue must drain rather than stall")

	# is_available() must answer, never throw, on a headless build.
	var available = service.is_available()
	if typeof(available) != TYPE_BOOL:
		failures.append("degrade: is_available() must return a bool")

	service.free()
	return failures
