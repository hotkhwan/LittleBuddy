extends RefCounted

## The level-completion summary: the per-level 0..3 rating row, and the Next /
## Replay routing behind it.
##
## Instantiates the real scene, with no autoloads available, so a renamed unique
## node or a broken `ext_resource` fails here rather than on the device.
##
## The rule this file exists to protect: the rating row shows the child's
## BEST-EVER stars, never this run's score on its own. A child who replays a
## 3-star level and does worse must not watch a star disappear.

const SESSION_SUMMARY_SCENE: String = "res://scenes/progression/session_summary.tscn"
const BABY_ROOM_SCRIPT: String = "res://scenes/baby_room/baby_room.gd"

const LevelSystemScript := preload("res://scripts/progression/level_system.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const StarRulesScript := preload("res://scripts/progression/star_rules.gd")

const EARNED_ALPHA: float = 1.0


## Records what the room's rating path asks a SaveService to store.
class StubSaveService extends RefCounted:
	var stars_by_level: Dictionary = {}
	var level_completed: Dictionary = {}
	var unlocked_levels: Array = []

	func get_stars_by_level() -> Dictionary:
		return stars_by_level.duplicate(true)

	func get_level_completed() -> Dictionary:
		return level_completed.duplicate(true)

	func mark_level_completed(level_id: String) -> void:
		level_completed[level_id] = true

	func set_level_stars(level_id: String, stars: int) -> void:
		stars_by_level[level_id] = maxi(int(stars_by_level.get(level_id, 0)), stars)

	func unlock_level(level_id: String) -> void:
		unlocked_levels.append(level_id)


func test_name() -> String:
	return "level_summary"


func run():
	var failures: Array = []

	var root: Node = _root()
	if root == null:
		return ["no SceneTree root available; cannot instantiate scenes"]

	failures.append_array(_test_rating_row(root))
	failures.append_array(_test_no_level_hides_row(root))
	failures.append_array(_test_best_never_regresses(root))
	failures.append_array(_test_next_button_hidden_without_successor(root))
	failures.append_array(_test_signals_exist(root))
	failures.append_array(_test_skip_through_completes_without_a_star(root))
	failures.append_array(_test_baby_room_routes_next_and_replay())

	return failures


# ---------------------------------------------------------------------------
# Completion vs stars, end to end
# ---------------------------------------------------------------------------

## The skip-everything playthrough, run through exactly the pieces the room
## wires together at `mission_completed`: `MissionRunner.get_awarded_task_ids()`
## (empty -- a skipped task is never awarded) -> `StarRules.session()` ->
## `LevelSystem.rate_session()` -> `LevelSystem.apply_completion()` -> the
## summary screen.
##
## Two things must be true at once, and they used to be conflated:
##   - the level IS completed and the next one opens (no dead end, no penalty
##     for using the escape hatch);
##   - it rates 0, not 1, and the child sees an encouraging screen anyway.
func _test_skip_through_completes_without_a_star(root: Node):
	var failures: Array = []

	var library: RefCounted = ContentLibraryScript.create()
	if library == null:
		return ["level_summary: could not load the content library"]
	var system: RefCounted = LevelSystemScript.create(library)
	if system == null:
		return ["level_summary: could not build the level system"]
	var save: StubSaveService = StubSaveService.new()
	system.set_save_service(save)

	var skipped_session: Dictionary = StarRulesScript.session([])
	var rated: int = int(system.rate_session("milkTime", skipped_session))
	if rated != 0:
		failures.append(
			"level_summary: skipping every task rated %d; star 1 means the core objective was "
			% rated + "genuinely completed, and a skip is not a completion"
		)

	var applied: Dictionary = system.apply_completion("milkTime", rated)
	if not bool(save.level_completed.get("milkTime", false)):
		failures.append("level_summary: a skipped-through level was not recorded as completed")
	if int(save.stars_by_level.get("milkTime", 0)) != 0:
		failures.append("level_summary: a skipped-through level was credited %s stars"
				% str(save.stars_by_level.get("milkTime")))
	if not save.unlocked_levels.has("bathTime"):
		failures.append(
			"level_summary: a skipped-through level did not unlock the next one -- the escape "
			+ "hatch must never trap the child"
		)
	if not bool(applied.get("completed", false)):
		failures.append("level_summary: apply_completion did not report the level as completed")

	# Touch alone, with no skipping, still earns the core star.
	var core_only: Dictionary = StarRulesScript.session(
			(system.get_star_rules("milkTime") as Dictionary).get("coreTaskIds", []))
	if int(system.rate_session("milkTime", core_only)) < 1:
		failures.append("level_summary: genuinely completing the core tasks by touch must earn star 1")

	# ...and the child is never shown that 0 as a failure.
	var screen: Control = _make(root, failures)
	if screen == null:
		return failures
	screen.call("show_summary", 0, 40, [], {
		"levelId": "milkTime",
		"levelTitle": "Milk Time",
		"levelStars": 0,
		"bestStars": 0,
		"hasNextLevel": true,
	})
	failures.append_array(_expect_filled(screen, 0, "a level finished by skipping everything"))

	var title: Label = screen.get_node_or_null("%TitleLabel") as Label
	if title == null:
		failures.append("level_summary: %TitleLabel is missing from the scene")
	elif title.text != "Nice playing!":
		failures.append("level_summary: a 0-star run greets the child with '%s'; it must stay kind"
				% title.text)

	var next_button: Button = screen.get_node_or_null("%NextButton") as Button
	if next_button == null or not next_button.visible:
		failures.append("level_summary: Next is hidden after a 0-star completion; the child is stuck")

	_free(root, screen)
	return failures


# ---------------------------------------------------------------------------
# The rating row
# ---------------------------------------------------------------------------

func _test_rating_row(root: Node):
	var failures: Array = []
	var screen: Control = _make(root, failures)
	if screen == null:
		return failures

	screen.call("show_summary", 2, 40, [], {
		"levelId": "bathTime",
		"levelTitle": "Bath Time",
		"levelStars": 2,
		"bestStars": 2,
		"hasNextLevel": true,
	})

	var row: Control = screen.get_node_or_null("%RatingRow") as Control
	if row == null:
		failures.append("level_summary: %RatingRow is missing from the scene")
	elif not row.visible:
		failures.append("level_summary: rating row hidden despite a level result")

	failures.append_array(_expect_filled(screen, 2, "2-star run"))

	var level_label: Label = screen.get_node_or_null("%LevelLabel") as Label
	if level_label == null:
		failures.append("level_summary: %LevelLabel is missing from the scene")
	elif level_label.text != "Bath Time":
		failures.append("level_summary: level title is %s, expected 'Bath Time'" % level_label.text)

	_free(root, screen)
	return failures


func _test_no_level_hides_row(root: Node):
	var failures: Array = []
	var screen: Control = _make(root, failures)
	if screen == null:
		return failures

	# Legacy mode: the old 3-argument call, unchanged. It must still work, and
	# must not paint an all-empty rating row that reads as "you earned nothing".
	screen.call("show_summary", 1, 12, [])

	var row: Control = screen.get_node_or_null("%RatingRow") as Control
	if row != null and row.visible:
		failures.append("level_summary: rating row shown for a mission with no level")

	var next_button: Button = screen.get_node_or_null("%NextButton") as Button
	if next_button != null and next_button.visible:
		failures.append("level_summary: Next offered with no level to go to")

	var level_label: Label = screen.get_node_or_null("%LevelLabel") as Label
	if level_label != null and level_label.visible:
		failures.append("level_summary: level title shown for a mission with no level")

	_free(root, screen)
	return failures


## The regression guard. A weaker replay shows the best rating, not the new one.
func _test_best_never_regresses(root: Node):
	var failures: Array = []
	var screen: Control = _make(root, failures)
	if screen == null:
		return failures

	screen.call("show_summary", 0, 40, [], {
		"levelId": "bathTime",
		"levelTitle": "Bath Time",
		"levelStars": 1,
		"bestStars": 3,
		"hasNextLevel": true,
	})

	failures.append_array(_expect_filled(screen, 3, "1-star replay of a 3-star level"))

	_free(root, screen)
	return failures


func _test_next_button_hidden_without_successor(root: Node):
	var failures: Array = []
	var screen: Control = _make(root, failures)
	if screen == null:
		return failures

	screen.call("show_summary", 3, 40, [], {
		"levelId": "firstWords",
		"levelTitle": "First Words",
		"levelStars": 3,
		"bestStars": 3,
		"hasNextLevel": false,
	})

	var next_button: Button = screen.get_node_or_null("%NextButton") as Button
	if next_button == null:
		failures.append("level_summary: %NextButton is missing from the scene")
	elif next_button.visible:
		failures.append("level_summary: Next shown on the last level of a chapter (dead end)")

	# Replay must still be there, or the last level has no way forward at all.
	var replay: Button = screen.get_node_or_null("%PlayAgainButton") as Button
	if replay == null or not replay.visible:
		failures.append("level_summary: Replay missing when Next is hidden; screen dead-ends")

	_free(root, screen)
	return failures


func _test_signals_exist(root: Node):
	var failures: Array = []
	var screen: Control = _make(root, failures)
	if screen == null:
		return failures

	# `_ready()` does not fire in the headless runner, so the screen wires itself
	# on first use instead. Any public entry point does it; `reset()` is the one
	# with no side effects.
	screen.call("reset")

	for signal_name: String in ["play_again", "next_level", "closed"]:
		if not screen.has_signal(signal_name):
			failures.append("level_summary: SessionSummary is missing signal '%s'" % signal_name)

	# Pressing Next must emit `next_level`, not `play_again`: routing the two
	# together is exactly the bug this separates out.
	var seen: Array = []
	screen.connect("next_level", func() -> void: seen.append("next"))
	screen.connect("play_again", func() -> void: seen.append("replay"))

	var next_button: Button = screen.get_node_or_null("%NextButton") as Button
	if next_button != null:
		next_button.pressed.emit()
	var replay: Button = screen.get_node_or_null("%PlayAgainButton") as Button
	if replay != null:
		replay.pressed.emit()

	if seen != ["next", "replay"]:
		failures.append("level_summary: buttons emitted %s, expected ['next', 'replay']" % str(seen))

	_free(root, screen)
	return failures


# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------

## Static read of the room script. Instantiating `baby_room.tscn` needs a 3D
## viewport and the full autoload set, which the headless runner does not have --
## but the wiring these assertions protect is a source-level fact.
func _test_baby_room_routes_next_and_replay():
	var failures: Array = []

	var source: String = _read(BABY_ROOM_SCRIPT)
	if source.is_empty():
		return ["level_summary: could not read %s" % BABY_ROOM_SCRIPT]

	if not source.contains("_summary.connect(\"next_level\", _on_summary_next_level)"):
		failures.append("level_summary: baby_room does not connect the summary's next_level signal")

	# Replay must restart the level that just finished. If it called
	# `_start_next_mission()` with no argument it would re-enter the random
	# picker, which deliberately AVOIDS an immediate repeat -- so "Replay" would
	# reliably start a different level. That was the pre-Phase-1 behaviour.
	if not source.contains("var replay_id: String = _last_mission_id"):
		failures.append("level_summary: Replay does not restart the level that just finished")

	if not source.contains("func _start_next_mission(preferred_mission_id: String = \"\")"):
		failures.append("level_summary: _start_next_mission cannot be told which mission to start")

	# The two currencies must not be summed anywhere in the rating path.
	if source.contains("get_stars() + ") or source.contains("+ get_total_level_stars"):
		failures.append("level_summary: task stars and level stars are being added together")

	failures.append_array(_test_completion_is_split_from_stars(source))

	return failures


## Completion and rating are two different facts, and the room must keep them
## apart.
##
## This replaces an older assertion that REQUIRED `maxi(rate_session(...), 1)` in
## this same function. That line guaranteed the first star for merely reaching
## the end of a level, which flattered a skipped-through level as a core success.
## The escape hatch is protected here instead by checking the honest half --
## completion is recorded unconditionally -- so the child still moves on while
## the rating still means something.
func _test_completion_is_split_from_stars(source: String):
	var failures: Array = []

	if not source.contains("rate_session"):
		failures.append("level_summary: the room no longer rates the session it just played")

	# The rating must come straight from what the child actually completed. No
	# floor, no "+ 1", no maxi() propping it up.
	if source.contains("maxi(int(system.call(\"rate_session\""):
		failures.append(
			"level_summary: the level rating is being floored to a minimum -- a level "
			+ "finished by skipping every task must honestly rate 0"
		)
	if not source.contains("var rated: int = int(system.call(\"rate_session\", level_id, session))"):
		failures.append("level_summary: the level rating is no longer taken verbatim from rate_session")

	# The rated session must be built from the tasks the child GENUINELY
	# completed. `MissionRunner` never awards a skipped task, so this single
	# expression is what keeps a skip from counting as an achievement.
	if not source.contains("StarRulesScript.session(_runner.call(\"get_awarded_task_ids\"))"):
		failures.append(
			"level_summary: the rating is no longer built from the genuinely-awarded task ids, "
			+ "so skipped tasks could count towards a star"
		)

	# ...and the child must still be carried forward, whatever they scored.
	# `apply_completion` is what marks the level completed and derives the
	# unlocks; removing it would turn the skip button into a permanent lock.
	# Matched at the call site, not anywhere in the file: a passing mention in a
	# comment must not be able to keep this assertion green.
	if not source.contains("system.call(\"apply_completion\", level_id, rated)"):
		failures.append(
			"level_summary: the room no longer records the level as completed, so a child "
			+ "who skipped tasks could be locked out of the next level"
		)

	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Asserts exactly `expected` of the three stars read as earned, and the rest as
## empty. Reads the rendered tint rather than any internal counter, so this
## checks what the child actually sees.
func _expect_filled(screen: Control, expected: int, label: String) -> Array:
	var failures: Array = []
	var filled: int = 0
	var found: int = 0

	for index: int in range(1, 4):
		var star: CanvasItem = screen.get_node_or_null("%%RatingStar%d" % index) as CanvasItem
		if star == null:
			failures.append("level_summary: %%RatingStar%d is missing from the scene" % index)
			continue
		found += 1
		var tint: Color = star.get("tint") as Color if "tint" in star else star.modulate
		if tint.a >= EARNED_ALPHA - 0.01:
			filled += 1

	if found == 3 and filled != expected:
		failures.append("level_summary: %s shows %d earned stars, expected %d" % [label, filled, expected])
	return failures


func _make(root: Node, failures: Array) -> Control:
	if not ResourceLoader.exists(SESSION_SUMMARY_SCENE):
		failures.append("level_summary: %s does not exist" % SESSION_SUMMARY_SCENE)
		return null
	var packed: PackedScene = load(SESSION_SUMMARY_SCENE) as PackedScene
	if packed == null:
		failures.append("level_summary: %s is not a PackedScene" % SESSION_SUMMARY_SCENE)
		return null
	var screen: Control = packed.instantiate() as Control
	if screen == null:
		failures.append("level_summary: %s did not instantiate as a Control" % SESSION_SUMMARY_SCENE)
		return null
	root.add_child(screen)
	return screen


func _free(root: Node, screen: Node) -> void:
	if screen == null or not is_instance_valid(screen):
		return
	root.remove_child(screen)
	screen.free()


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _root() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	var tree: SceneTree = loop as SceneTree
	if tree == null:
		return null
	return tree.root
