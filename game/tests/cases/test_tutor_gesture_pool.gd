extends RefCounted

## TutorGesturePool (scripts/tutor/tutor_gesture_pool.gd) and the gesture enum's
## parity across the four places it lives:
##   * the pool never hands out the same gesture for consecutive seeds of the
##     same event, is deterministic for a seed, and every entry gets a turn;
##   * every name the pool can return is a clip on the layer
##     (`buddy_gesture_clips.gd::GESTURE_NAMES`) and a member of the TutorTurn
##     enum (`tutor_turn.gd::GESTURES`);
##   * the client enum, the shared fixtures (`content/tutor/turn_fixtures.json`,
##     which must exercise every member as a valid input) and the Worker
##     validator (`cloud/src/tutor/turn_validator.ts`, read as text) agree.
##
## Pure: no nodes, no rig. Runs in the headless suite in milliseconds.

const Pool := preload("res://scripts/tutor/tutor_gesture_pool.gd")
const TurnValidator := preload("res://scripts/tutor/turn/tutor_turn.gd")
const GestureClips := preload("res://scripts/characters/buddy/buddy_gesture_clips.gd")

const FIXTURES_PATH: String = "res://content/tutor/turn_fixtures.json"
## Repo-relative (outside res://): resolved through `_repo_file()`.
const WORKER_VALIDATOR_PATH: String = "cloud/src/tutor/turn_validator.ts"
const WORKER_TYPES_PATH: String = "cloud/src/tutor/types.ts"
const WORKER_TEST_PATH: String = "cloud/test/validator.test.ts"


func test_name() -> String:
	return "tutor_gesture_pool"


func run():
	var failures: Array = []
	failures.append_array(_test_table())
	failures.append_array(_test_no_consecutive_repeat())
	failures.append_array(_test_deterministic_and_covering())
	failures.append_array(_test_positive_event())
	failures.append_array(_test_pool_names_are_real_gestures())
	failures.append_array(_test_enum_parity())
	return failures


## -- the table: each event has its pool, expression and hook --------------------------------

func _test_table():
	var failures: Array = []
	var expected: Dictionary = {
		"correct": [["thumbsUp", "clap", "nod"], "happy", ""],
		"excellent": [["celebrate"], "happy", "confetti"],
		"greeting": [["wave"], "smile", ""],
		"listening": [["listening"], "listening", ""],
		"thinking": [["thinking"], "thinking", ""],
		"encourage": [["encourage"], "encouraging", ""],
		"farewell": [["wave"], "happy", ""],
	}
	for event: String in expected.keys():
		var want: Array = expected[event]
		if not Pool.is_event(event):
			failures.append("'%s' is not an event the pool knows" % event)
			continue
		if Pool.pool_for(event) != want[0]:
			failures.append("pool for '%s' is %s, expected %s" % [event, str(Pool.pool_for(event)), str(want[0])])
		if Pool.expression_for(event) != String(want[1]):
			failures.append("expression for '%s' is '%s', expected '%s'" % [event, Pool.expression_for(event), String(want[1])])
		if Pool.reward_hook_for(event) != String(want[2]):
			failures.append("reward hook for '%s' is '%s', expected '%s'" % [event, Pool.reward_hook_for(event), String(want[2])])
	for event: String in Pool.EVENTS:
		if not expected.has(event):
			failures.append("the pool has an event '%s' this table does not document" % event)
	# An unknown event: nothing to play, a neutral face, no hook.
	if Pool.pick("tantrum", 3) != "none" or Pool.expression_for("tantrum") != "neutral" \
			or Pool.reward_hook_for("tantrum") != "" or not Pool.pool_for("tantrum").is_empty():
		failures.append("an unknown event should give 'none' / 'neutral' / '' / []")
	return failures


## -- never the same gesture twice in a row, for any seed sequence -----------------------------

func _test_no_consecutive_repeat():
	var failures: Array = []
	for event: String in Pool.EVENTS:
		if Pool.pool_for(event).size() < 2:
			continue
		var previous: String = Pool.pick(event, -21)
		for seed: int in range(-20, 200):
			var now: String = Pool.pick(event, seed)
			if now == previous:
				failures.append("'%s' gave '%s' for both seed %d and %d" % [event, now, seed - 1, seed])
				break
			previous = now
	return failures


## -- deterministic for a seed; the walk visits every entry ------------------------------------

func _test_deterministic_and_covering():
	var failures: Array = []
	for event: String in Pool.EVENTS:
		var pool: Array = Pool.pool_for(event)
		var seen: Array = []
		for seed: int in range(0, pool.size() * 2):
			var a: String = Pool.pick(event, seed)
			var b: String = Pool.pick(event, seed)
			if a != b:
				failures.append("'%s' at seed %d gave '%s' then '%s'; the pool must be deterministic" % [event, seed, a, b])
			if not pool.has(a):
				failures.append("'%s' at seed %d gave '%s', which is not in its pool %s" % [event, seed, a, str(pool)])
			if not seen.has(a):
				seen.append(a)
		if seen.size() != pool.size():
			failures.append("'%s' only ever hands out %s of %s" % [event, str(seen), str(pool)])
	# The documented sequence for `correct` (docs/ALIZ_GESTURES.md).
	var sequence: Array = []
	for seed: int in range(6):
		sequence.append(Pool.pick("correct", seed))
	if sequence != ["thumbsUp", "nod", "clap", "thumbsUp", "nod", "clap"]:
		failures.append("'correct' over seeds 0..5 is %s; docs/ALIZ_GESTURES.md documents thumbsUp, nod, clap, ..." % str(sequence))
	return failures


## -- three in a row, or the lesson done, is `excellent` ---------------------------------------

func _test_positive_event():
	var failures: Array = []
	var got: Array = []
	for streak: int in range(1, 7):
		got.append(Pool.positive_event(streak))
	if got != ["correct", "correct", "excellent", "correct", "correct", "excellent"]:
		failures.append("positive_event over streaks 1..6 is %s" % str(got))
	if Pool.positive_event(1, true) != "excellent":
		failures.append("a completed lesson should be 'excellent' whatever the streak")
	if Pool.positive_event(0) != "correct":
		failures.append("streak 0 should be 'correct', not a celebration")
	return failures


## -- every name the pool can return is a real clip and a TutorTurn gesture ----------------------

func _test_pool_names_are_real_gestures():
	var failures: Array = []
	for event: String in Pool.EVENTS:
		for name: String in Pool.pool_for(event):
			if not GestureClips.GESTURE_NAMES.has(name):
				failures.append("pool '%s' names '%s', which is not a clip in buddy_gesture_clips.gd" % [event, name])
			if not TurnValidator.GESTURES.has(name):
				failures.append("pool '%s' names '%s', which is not in the TutorTurn enum" % [event, name])
			if GestureClips.duration_of(name) <= 0.0:
				failures.append("'%s' has no duration" % name)
		if not TurnValidator.EMOTIONS.has(Pool.expression_for(event)):
			failures.append("pool '%s' wants expression '%s', which is not a TutorTurn emotion" % [event, Pool.expression_for(event)])
	return failures


## -- enum parity: client enum == clips + none == fixtures' coverage == Worker validator --------

func _test_enum_parity():
	var failures: Array = []
	var client: Array = TurnValidator.GESTURES.duplicate()
	# The clip vocabulary plus "none" IS the client enum, in the same order.
	var clips: Array = ["none"]
	clips.append_array(GestureClips.GESTURE_NAMES)
	if client != clips:
		failures.append("tutor_turn.gd GESTURES %s != 'none' + buddy_gesture_clips.gd GESTURE_NAMES %s" % [str(client), str(clips)])
	# The shared fixtures exercise every member as a valid input.
	var fixtures_text: String = FileAccess.get_file_as_string(FIXTURES_PATH)
	var fixtures: Variant = JSON.parse_string(fixtures_text)
	if not (fixtures is Dictionary):
		return ["could not parse %s" % FIXTURES_PATH]
	var covered: Array = []
	var seen_in_fixtures: Array = []
	for entry: Variant in (fixtures as Dictionary).get("cases", []):
		if not (entry is Dictionary):
			continue
		var c: Dictionary = entry
		var input: Variant = c.get("input", {})
		if not (input is Dictionary):
			continue  # a fixture that feeds the validator a non-object on purpose
		var gesture: Variant = (input as Dictionary).get("gesture", null)
		if gesture is String and not seen_in_fixtures.has(gesture):
			seen_in_fixtures.append(gesture)
		if String(c.get("expect", "")) == "valid" and gesture is String and not covered.has(gesture):
			covered.append(gesture)
	for name: String in client:
		if not covered.has(name):
			failures.append("turn_fixtures.json has no valid case with gesture '%s'" % name)
	for name: String in seen_in_fixtures:
		if not client.has(name) and TurnValidator.is_valid({"speech": "Hi!", "emotion": "happy",
				"gesture": name, "visual": {"type": "none"}, "lessonAction": "retry"}):
			failures.append("the client accepts fixture gesture '%s', which is outside its enum" % name)
	# The Worker validator's GESTURES line, read as text.
	var worker: Array = _ts_string_list(_repo_file(WORKER_VALIDATOR_PATH), "export const GESTURES")
	if worker.is_empty():
		failures.append("could not read the GESTURES list from %s" % WORKER_VALIDATOR_PATH)
	elif worker != client:
		failures.append("Worker validator GESTURES %s != client %s" % [str(worker), str(client)])
	# Its type alias and its enum test carry the same names.
	var types_text: String = _repo_file(WORKER_TYPES_PATH)
	var alias_line: String = _line_containing(types_text, "export type Gesture")
	var test_text: String = _repo_file(WORKER_TEST_PATH)
	var test_line: String = _line_containing(test_text, "for (const gesture of [")
	for name: String in client:
		if not alias_line.contains("'%s'" % name):
			failures.append("cloud/src/tutor/types.ts Gesture alias lacks '%s'" % name)
		if not test_line.contains("'%s'" % name):
			failures.append("cloud/test/validator.test.ts enum loop lacks '%s'" % name)
	print("      gesture enum parity: %d names -- %s" % [client.size(), ", ".join(PackedStringArray(client))])
	return failures


## The text of a file at `relative` from the repository root (game/..), or ""
## when it is not there (a packaged build has no cloud/ directory).
static func _repo_file(relative: String) -> String:
	var absolute: String = ProjectSettings.globalize_path("res://").path_join("..").path_join(relative).simplify_path()
	if not FileAccess.file_exists(absolute):
		return ""
	return FileAccess.get_file_as_string(absolute)


## The `['a', 'b', ...]` list on the line that starts with `prefix`.
static func _ts_string_list(text: String, prefix: String) -> Array:
	var line: String = _line_containing(text, prefix)
	var out: Array = []
	if line.is_empty():
		return out
	# After the "=": `readonly Gesture[]` has its own brackets before it.
	var open_at: int = line.find("[", maxi(line.find("="), 0))
	var close_at: int = line.find("]", open_at)
	if open_at == -1 or close_at == -1:
		return out
	for part: String in line.substr(open_at + 1, close_at - open_at - 1).split(","):
		var trimmed: String = part.strip_edges().trim_prefix("'").trim_suffix("'")
		if not trimmed.is_empty():
			out.append(trimmed)
	return out


static func _line_containing(text: String, needle: String) -> String:
	for line: String in text.split("\n"):
		if line.contains(needle):
			return line
	return ""
