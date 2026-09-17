extends RefCounted
## Every child-facing English line in the shipped content must actually reach
## `TtsService`. The player cannot read: a prompt that is only drawn on screen
## does not exist for them.
##
## This drives each task through its REAL mode handler with a REAL `TtsService`
## attached (safety timers captured, so the queue can be inspected a step at a
## time) and asserts:
##
##   * the task's `instruction` is spoken,
##   * the task's `prompt` (the character's own line) is spoken too when it
##     differs, and is NOT truncated by the instruction that follows it,
##   * `sayIt` also speaks the word the child is asked to copy,
##   * `repeatPrompt` is spoken on a gentle retry,
##   * nothing blank is ever handed to the voice,
##   * no Thai text is ever sent to the English voice (the Thai hint is a
##     written hint for the adult, not something an en-US voice should attempt).

const TtsServiceScript := preload("res://scripts/speech/tts_service.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")

const MODE_SCRIPTS: Dictionary = {
	"findIt": "res://scripts/gameplay/find_it_mode.gd",
	"sayIt": "res://scripts/gameplay/say_it_mode.gd",
	"followInstruction": "res://scripts/gameplay/follow_instruction_mode.gd",
}

## Beats named in the slice contract. Each must be spoken somewhere in ch3.
const SLICE_LINES: Array[String] = [
	"Good morning!",
	"Let's brush our teeth.",
	"Can you find the milk?",
	"Good night!",
]

## First codepoint of the Thai Unicode block.
const THAI_BLOCK_START: int = 0x0E00


func test_name() -> String:
	return "tts_prompt_coverage"


func run():
	var failures: Array = []

	var library = ContentLibraryScript.create()
	if library == null:
		return ["could not create ContentLibrary"]

	var spoken_corpus: Dictionary = {}
	var ch3_corpus: Dictionary = {}
	var task_count: int = 0

	for mission in library.get_missions():
		if typeof(mission) != TYPE_DICTIONARY:
			continue
		var chapter_id: String = String((mission as Dictionary).get("chapterId", ""))
		var mission_id: String = String((mission as Dictionary).get("missionId", ""))
		for task in library.get_mission_tasks(mission_id):
			if typeof(task) != TYPE_DICTIONARY:
				continue
			task_count += 1
			var spoken: Array = []
			failures.append_array(_check_task(task, mission_id, library, spoken))
			for line in spoken:
				spoken_corpus[String(line)] = true
				if chapter_id == "ch3":
					ch3_corpus[String(line)] = true

	if task_count == 0:
		failures.append("no mission tasks found -- the coverage check proved nothing")

	failures.append_array(_check_slice_lines(ch3_corpus))
	failures.append_array(_check_nothing_unspeakable(spoken_corpus))
	failures.append_array(_check_consumers_survive_a_missing_service())
	failures.append_array(_check_a_broken_service_is_survivable())
	return failures


# -----------------------------------------------------------------------------


## Runs one task through its handler and appends every string handed to the
## voice into `spoken`.
func _check_task(task: Dictionary, mission_id: String, library, spoken: Array):
	var failures: Array = []
	var task_id: String = String(task.get("taskId", "?"))
	var label: String = "%s/%s" % [mission_id, task_id]
	var mode: String = String(task.get("mode", ""))
	if not MODE_SCRIPTS.has(mode):
		failures.append("%s: unknown mode '%s'" % [label, mode])
		return failures

	var script: GDScript = load(String(MODE_SCRIPTS[mode])) as GDScript
	if script == null:
		failures.append("%s: could not load handler for mode '%s'" % [label, mode])
		return failures

	var tts = TtsServiceScript.new()
	var timers: Array = []
	var started: Array = []
	tts.set_timer_factory(
		func(_duration: float, callback: Callable) -> void: timers.append(callback)
	)
	tts.speech_started.connect(func(text: String) -> void: started.append(text))

	var handler: Node = script.new()
	handler.set_seed(1)
	handler.start(task, {"tts": tts, "library": library, "thaiHints": true})

	# With the clock stopped, exactly one utterance may be in flight; everything
	# else must be waiting behind it rather than having replaced it.
	if started.size() != 1:
		failures.append(
			"%s: expected exactly one utterance in flight at task start, got %d (%s)"
			% [label, started.size(), str(started)]
		)
	var queued: Array = tts.get_pending_texts()
	var at_start: Array = started.duplicate()
	at_start.append_array(queued)

	var prompt: String = String(task.get("prompt", "")).strip_edges()
	var instruction: String = String(task.get("instruction", "")).strip_edges()
	var repeat_prompt: String = String(task.get("repeatPrompt", "")).strip_edges()

	if not instruction.is_empty() and not at_start.has(instruction):
		failures.append(
			"%s: instruction \"%s\" is never spoken (spoken: %s)" % [label, instruction, str(at_start)]
		)
	if not prompt.is_empty() and prompt != instruction and not at_start.has(prompt):
		failures.append(
			"%s: prompt \"%s\" is never spoken (spoken: %s)" % [label, prompt, str(at_start)]
		)
	if not prompt.is_empty() and prompt != instruction:
		if String(started[0] if not started.is_empty() else "") != prompt:
			failures.append(
				"%s: the character's own line should be spoken first, got \"%s\""
				% [label, str(started)]
			)
		if not queued.has(instruction):
			failures.append(
				"%s: the instruction must be QUEUED behind the prompt, not cut it off"
				% label
			)

	if mode == "sayIt":
		var target_word: String = String(handler.get_target_word()).strip_edges()
		if target_word.is_empty():
			failures.append("%s: sayIt task has no target word to copy" % label)
		elif not at_start.has(target_word):
			failures.append(
				"%s: sayIt must speak the word to copy (\"%s\"), spoken: %s"
				% [label, target_word, str(at_start)]
			)

	spoken.append_array(at_start)

	# Gentle retry: the repeat prompt must be spoken, not just displayed.
	started.clear()
	handler.on_object_chosen("zzz_not_a_real_object_id")
	var after_retry: Array = started.duplicate()
	after_retry.append_array(tts.get_pending_texts())
	if not repeat_prompt.is_empty() and not after_retry.has(repeat_prompt):
		failures.append(
			"%s: repeatPrompt \"%s\" is never spoken on a retry (spoken: %s)"
			% [label, repeat_prompt, str(after_retry)]
		)
	spoken.append_array(after_retry)

	handler.cancel()
	handler.free()
	tts.free()
	return failures


func _check_slice_lines(ch3_corpus: Dictionary):
	var failures: Array = []
	for line in SLICE_LINES:
		if not ch3_corpus.has(line):
			failures.append(
				"slice line \"%s\" is never spoken anywhere in chapter 3" % line
			)
	return failures


## TTS is an enhancement layered on top of gameplay: the autoload can be absent
## (a scene opened on its own, the headless runner, a platform with no voice) and
## that must degrade to silent on-screen text, never to an error. Every call site
## therefore has to check before it speaks.
func _check_consumers_survive_a_missing_service():
	var failures: Array = []
	var files: Array = []
	_collect_scripts("res://scripts", files)
	_collect_scripts("res://scenes", files)
	if files.is_empty():
		return ["no scripts found to scan for unguarded TTS use"]

	var checked: int = 0
	for path in files:
		var file: FileAccess = FileAccess.open(String(path), FileAccess.READ)
		if file == null:
			continue
		var source: String = file.get_as_text()
		file.close()
		var speaks: bool = source.contains("call(\"speak\"") or source.contains(".speak(")
		if not speaks:
			continue
		# The service's own implementation is where speak() is defined.
		if String(path).ends_with("speech/tts_service.gd"):
			continue
		checked += 1
		if not source.contains("has_method(\"speak\")"):
			failures.append(
				"%s calls speak() without checking the service exists; " % path
				+ "a missing TtsService must degrade to silent text, not error"
			)
	if checked == 0:
		failures.append("no TTS call sites were found -- nothing speaks at all?")
	return failures


func _collect_scripts(dir_path: String, out: Array) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, file_name])
	for sub in dir.get_directories():
		_collect_scripts("%s/%s" % [dir_path, sub], out)


## A service object that exists but cannot speak (a stub, a half-built autoload,
## a future replacement) must not take the task down with it.
func _check_a_broken_service_is_survivable():
	var failures: Array = []
	var script: GDScript = load(String(MODE_SCRIPTS["findIt"])) as GDScript
	if script == null:
		return ["could not load the findIt handler"]

	var task: Dictionary = {
		"taskId": "brokenServiceProbe",
		"mode": "findIt",
		"objectId": "milk",
		"prompt": "I'm hungry.",
		"instruction": "Find the milk.",
		"repeatPrompt": "Can you find the milk?",
		"reward": {"stars": 1},
	}

	for service_name in ["null", "objectWithNoSpeakMethod"]:
		var handler: Node = script.new()
		handler.set_seed(2)
		var prompts: Array = []
		var completed: Array = []
		handler.prompt_changed.connect(
			func(text: String, _thai: String) -> void: prompts.append(text)
		)
		handler.task_completed.connect(
			func(_id: String, _stars: int) -> void: completed.append(true)
		)

		var context: Dictionary = {}
		if service_name == "objectWithNoSpeakMethod":
			context["tts"] = RefCounted.new()

		handler.start(task, context)
		if prompts.is_empty():
			failures.append(
				"%s: the prompt must still be delivered as text with no working voice"
				% service_name
			)
		handler.complete_by_touch()
		if completed.is_empty():
			failures.append("%s: the task must still complete with no working voice" % service_name)
		handler.cancel()
		handler.free()

	return failures


func _check_nothing_unspeakable(corpus: Dictionary):
	var failures: Array = []
	if corpus.is_empty():
		failures.append("no spoken lines were collected at all")
	for key in corpus.keys():
		var line: String = String(key)
		if line.strip_edges().is_empty():
			failures.append("a blank string was handed to the voice")
			continue
		for i in range(line.length()):
			if line.unicode_at(i) >= THAI_BLOCK_START:
				failures.append(
					"\"%s\" contains Thai text; the Thai hint is written for the adult "
					% line
					+ "and must never be sent to the English voice"
				)
				break
	return failures
