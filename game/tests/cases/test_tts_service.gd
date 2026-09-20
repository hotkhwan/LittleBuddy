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
	failures.append_array(_test_voice_chain_prefers_a_bright_natural_voice())
	failures.append_array(_test_voice_chain_never_picks_a_novelty_voice_first())
	failures.append_array(_test_reaction_is_not_cut_by_the_next_prompt())
	failures.append_array(_test_reaction_protection_lapses())
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


# -- Voice choice ---------------------------------------------------------------


## The list this Mac actually returned on 2026-09-20 (en-* entries), plus the
## downloadable voices a parent may have installed, so the chain is exercised
## against real identifiers rather than invented ones.
func _mac_voices():
	return [
		{"name": "Samantha", "id": "com.apple.voice.compact.en-US.Samantha", "language": "en-US"},
		{"name": "Eddy", "id": "com.apple.eloquence.en-US.Eddy", "language": "en-US"},
		{"name": "Flo", "id": "com.apple.eloquence.en-US.Flo", "language": "en-US"},
		{"name": "Junior", "id": "com.apple.speech.synthesis.voice.Junior", "language": "en-US"},
		{"name": "Superstar", "id": "com.apple.speech.synthesis.voice.Princess", "language": "en-US"},
		{"name": "Bubbles", "id": "com.apple.speech.synthesis.voice.Bubbles", "language": "en-US"},
		{"name": "Daniel", "id": "com.apple.voice.super-compact.en-GB.Daniel", "language": "en-GB"},
		{"name": "Karen", "id": "com.apple.voice.super-compact.en-AU.Karen", "language": "en-AU"},
		{"name": "Kyoko", "id": "com.apple.voice.compact.ja-JP.Kyoko", "language": "ja-JP"},
	]


func _test_voice_chain_prefers_a_bright_natural_voice():
	var failures: Array = []

	# What this Mac has today: the only natural en-US voice is compact Samantha,
	# and the chain must land there -- NOT on the list's first entry by accident,
	# and never on "Junior", which is child-named and robot-sounding.
	var today: Dictionary = TtsServiceScript.choose_voice(_mac_voices())
	if String(today.get("id", "")) != "com.apple.voice.compact.en-US.Samantha":
		failures.append("voice: on this Mac's list expected compact Samantha, got %s" % str(today))
	if String(today.get("tier", "")) != "compact":
		failures.append("voice: tier should read 'compact', got '%s'" % String(today.get("tier", "")))

	# Once a parent downloads a better voice it must win without a code change.
	var with_zoe: Array = _mac_voices()
	with_zoe.append({"name": "Zoe", "id": "com.apple.voice.premium.en-US.Zoe", "language": "en-US"})
	with_zoe.append({"name": "Samantha", "id": "com.apple.voice.enhanced.en-US.Samantha", "language": "en-US"})
	var upgraded: Dictionary = TtsServiceScript.choose_voice(with_zoe)
	if String(upgraded.get("id", "")) != "com.apple.voice.premium.en-US.Zoe":
		failures.append("voice: premium Zoe should beat every other voice, got %s" % str(upgraded))

	var with_enhanced: Array = _mac_voices()
	with_enhanced.append({"name": "Samantha", "id": "com.apple.voice.enhanced.en-US.Samantha", "language": "en-US"})
	var enhanced: Dictionary = TtsServiceScript.choose_voice(with_enhanced)
	if String(enhanced.get("id", "")) != "com.apple.voice.enhanced.en-US.Samantha":
		failures.append("voice: enhanced Samantha should beat compact Samantha, got %s" % str(enhanced))

	# A female natural en-US voice that is not on the preferred list still beats
	# a male one and beats every novelty engine.
	var other: Array = [
		{"name": "Tom", "id": "com.apple.voice.enhanced.en-US.Tom", "language": "en-US"},
		{"name": "Kathy", "id": "com.apple.voice.enhanced.en-US.Kathy", "language": "en-US"},
		{"name": "Junior", "id": "com.apple.speech.synthesis.voice.Junior", "language": "en-US"},
	]
	var pick: Dictionary = TtsServiceScript.choose_voice(other)
	if String(pick.get("name", "")) != "Kathy":
		failures.append("voice: a natural female en-US voice should win the fallback rung, got %s" % str(pick))

	# No English voice at all: an empty answer, never a Japanese one.
	var none: Dictionary = TtsServiceScript.choose_voice([
		{"name": "Kyoko", "id": "com.apple.voice.compact.ja-JP.Kyoko", "language": "ja-JP"}])
	if not none.is_empty():
		failures.append("voice: with no English voice the choice must be empty, got %s" % str(none))
	if not TtsServiceScript.choose_voice([]).is_empty():
		failures.append("voice: an empty platform list must give an empty choice")
	return failures


func _test_voice_chain_never_picks_a_novelty_voice_first():
	var failures: Array = []
	# Only last-resort engines available: the chain still answers (something is
	# better than silence) but a natural voice anywhere in English beats them.
	var novelty_only: Array = [
		{"name": "Junior", "id": "com.apple.speech.synthesis.voice.Junior", "language": "en-US"},
		{"name": "Flo", "id": "com.apple.eloquence.en-US.Flo", "language": "en-US"},
	]
	if TtsServiceScript.choose_voice(novelty_only).is_empty():
		failures.append("voice: with only novelty voices the service must still speak")
	var with_au: Array = novelty_only.duplicate()
	with_au.append({"name": "Karen", "id": "com.apple.voice.compact.en-AU.Karen", "language": "en-AU"})
	var pick: Dictionary = TtsServiceScript.choose_voice(with_au)
	if String(pick.get("name", "")) != "Karen":
		failures.append("voice: a natural en-AU voice must beat en-US novelty engines, got %s" % str(pick))
	for prefix: String in TtsServiceScript.LAST_RESORT_ID_PREFIXES:
		for wanted: String in TtsServiceScript.PREFERRED_VOICE_IDS:
			if wanted.begins_with(prefix):
				failures.append("voice: preferred list contains a last-resort engine: %s" % wanted)
	return failures


# -- Reactions ------------------------------------------------------------------


func _test_reaction_is_not_cut_by_the_next_prompt():
	var failures: Array = []
	var harness = _make_service()
	var service = harness["service"]

	# Drag the bottle: "Great!" then, in the same call stack, the next task's
	# prompt with interrupt=true. The prompt must wait its turn.
	service.react("Great!")
	if service.get_current_text() != "Great!":
		failures.append("react: the reaction should start at once, got '%s'" % service.get_current_text())
	if not service.is_reaction_protected():
		failures.append("react: a fresh reaction must be protected")
	service.speak("I'm hungry, Aliz!")
	service.speak("Go to Bunny.", false)
	if service.get_current_text() != "Great!":
		failures.append("react: an interrupting prompt cut the reaction ('%s' is speaking)"
				% service.get_current_text())
	if service.get_pending_texts() != ["I'm hungry, Aliz!", "Go to Bunny."]:
		failures.append("react: the prompts should be queued behind the reaction in order, got %s"
				% str(service.get_pending_texts()))

	# A second reaction during a protected one goes NEXT, ahead of the prompts.
	service.react("You can tap it too!")
	if service.get_current_text() != "Great!":
		failures.append("react: a second reaction must not cut the first")
	if service.get_pending_texts()[0] != "You can tap it too!":
		failures.append("react: a second reaction should be spoken before the queued prompts, got %s"
				% str(service.get_pending_texts()))

	# The reaction finishing releases the queue in that order.
	_fire(harness, 0)
	if service.get_current_text() != "You can tap it too!":
		failures.append("react: expected the second reaction next, got '%s'" % service.get_current_text())
	_fire(harness, 1)
	if service.get_current_text() != "I'm hungry, Aliz!":
		failures.append("react: expected the prompt after the reactions, got '%s'" % service.get_current_text())

	# An ordinary prompt is NOT protected: a reaction may cut it (the child acted).
	service.react("Nice!")
	if service.get_current_text() != "Nice!":
		failures.append("react: a reaction should interrupt an ordinary prompt")
	if service.get_pending_count() != 0:
		failures.append("react: interrupting clears the stale queue, %d left" % service.get_pending_count())

	# stop() still stops everything, protection or not.
	service.stop()
	if service.is_speaking() or service.is_reaction_protected():
		failures.append("react: stop() must end a protected reaction too")

	# Empty reactions are ignored like empty prompts.
	service.react("   ")
	if service.is_speaking():
		failures.append("react: blank text must not start an utterance")

	service.free()
	return failures


func _test_reaction_protection_lapses():
	var failures: Array = []
	var harness = _make_service()
	var service = harness["service"]
	service.react("Great!")
	# Rewind the protection deadline instead of sleeping.
	service._reaction_protected_until_msec = Time.get_ticks_msec() - 1
	if service.is_reaction_protected():
		failures.append("react: protection must lapse after REACTION_PROTECT_SECONDS")
	service.speak("Where is the bottle?")
	if service.get_current_text() != "Where is the bottle?":
		failures.append("react: once protection lapses an interrupting prompt takes over, got '%s'"
				% service.get_current_text())
	if TtsServiceScript.REACTION_PROTECT_SECONDS < 1.0 or TtsServiceScript.REACTION_PROTECT_SECONDS > 4.0:
		failures.append("react: protection window %.1f s is outside the sensible 1-4 s band"
				% TtsServiceScript.REACTION_PROTECT_SECONDS)
	service.free()
	return failures
