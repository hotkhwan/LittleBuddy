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

const EARNED_ALPHA: float = 1.0


func test_name() -> String:
	return "level_summary"


func run() -> Array:
	var failures: Array = []

	var root: Node = _root()
	if root == null:
		return ["no SceneTree root available; cannot instantiate scenes"]

	failures.append_array(_test_rating_row(root))
	failures.append_array(_test_no_level_hides_row(root))
	failures.append_array(_test_best_never_regresses(root))
	failures.append_array(_test_next_button_hidden_without_successor(root))
	failures.append_array(_test_signals_exist(root))
	failures.append_array(_test_baby_room_routes_next_and_replay())

	return failures


# ---------------------------------------------------------------------------
# The rating row
# ---------------------------------------------------------------------------

func _test_rating_row(root: Node) -> Array:
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


func _test_no_level_hides_row(root: Node) -> Array:
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
func _test_best_never_regresses(root: Node) -> Array:
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


func _test_next_button_hidden_without_successor(root: Node) -> Array:
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


func _test_signals_exist(root: Node) -> Array:
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
func _test_baby_room_routes_next_and_replay() -> Array:
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

	# The completion star. Removing the `maxi(..., 1)` would let a child who used
	# the skip button on every task fail to unlock the next level -- turning the
	# no-penalty escape hatch into a permanent lock.
	if not source.contains("rate_session") or not source.contains("maxi(int(system.call(\"rate_session\", level_id, session)), 1)"):
		failures.append("level_summary: finishing a level no longer guarantees the completion star")

	# The two currencies must not be summed anywhere in the rating path.
	if source.contains("get_stars() + ") or source.contains("+ get_total_level_stars"):
		failures.append("level_summary: task stars and level stars are being added together")

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
