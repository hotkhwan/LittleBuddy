extends RefCounted

## What the game is allowed to say to a four-year-old who just finished a level.
##
## `CLAUDE.md` and `docs/SLICE_CONTRACT.md` section 6 both say it outright:
##
## > **0-star completion is celebrated, never a failure screen.**
##
## The screen already had a kind headline when this was written, and it was
## still a failure screen, which is why this is a test and not a style note. It
## printed a gold star next to the text **"+0"** and drew the three unearned
## stars as pale filled blobs. The words were fine; the numbers were the
## message.
##
## So this case asserts the three things that actually make a 0-star summary
## kind, in the order a child meets them:
##
##   1. **No zero is ever shown.** The tally row hides itself rather than
##      reporting nothing gained.
##   2. **The words look forward, not back.** Every string the screen can print
##      or speak is checked against a list of report-card vocabulary, and the
##      0-star line has to name something still to find.
##   3. **There is always a way on.** Replay is there, and Next is not taken
##      away for doing badly -- a child who cannot get a star must never be
##      stuck on the level that beat them.
##
## It also sweeps the child-facing screens for the things `CLAUDE.md` bans
## outright: percentages, scores, "X" marks and timers.

const SUMMARY_SCENE: String = "res://scenes/progression/session_summary.tscn"
const SummaryScript := preload("res://scenes/progression/session_summary.gd")

## Words a report card uses. None of them belongs on a screen a pre-reader sees,
## and several of them are things a well-meaning later edit reaches for.
const UNKIND_WORDS: Array[String] = [
	"fail", "failed", "wrong", "incorrect", "missed", "lost", "oops",
	"sorry", "unlucky", "no star", "zero", "score", "rank", "percent",
	"almost", "not quite", "better luck", "you only", "you didn't",
]

## Never on a child-facing screen, per `CLAUDE.md` and ART_BIBLE section 8.
const BANNED_SUBSTRINGS: Array[String] = ["%", " / 3", "out of 3", "0 stars"]


func test_name() -> String:
	return "ui_kindness"


func run():
	var failures: Array = []
	failures.append_array(_test_zero_shows_no_zero())
	failures.append_array(_test_every_line_is_kind())
	failures.append_array(_test_zero_star_line_points_forward())
	failures.append_array(_test_zero_stars_is_never_a_dead_end())
	failures.append_array(_test_no_scores_in_the_scene())
	return failures


# ---------------------------------------------------------------------------

## The tally row is hidden at 0 and shown as soon as there is something to show.
func _test_zero_shows_no_zero():
	var failures: Array = []

	var screen: Control = _make(failures)
	if screen == null:
		return failures

	screen.call("show_summary", 0, 12, [], {
		"levelId": "breakfast", "levelTitle": "Breakfast",
		"levelStars": 0, "bestStars": 0, "hasNextLevel": true,
	})

	var earned_row: Control = screen.get_node_or_null("%EarnedRow") as Control
	if earned_row == null:
		failures.append("ui_kindness: %EarnedRow is missing from the summary scene")
	elif earned_row.visible:
		failures.append(
			"a 0-star summary still shows the 'stars earned' row. A gold star beside the text "
			+ "'+0' is the unkindest thing this screen can say, and it is also a number a "
			+ "four-year-old cannot use. SLICE_CONTRACT.md section 6: celebrated, never a failure screen.")

	# ...and it comes back the moment there is something to celebrate.
	screen.call("reset")
	screen.call("show_summary", 2, 14, [], {
		"levelId": "breakfast", "levelTitle": "Breakfast",
		"levelStars": 2, "bestStars": 2, "hasNextLevel": true,
	})
	if earned_row != null and not earned_row.visible:
		failures.append("the 'stars earned' row stayed hidden after a 2-star run; the child earned those")

	_free(screen)
	return failures


## Every headline and encouragement string the screen can produce, at every
## rating, read together.
func _test_every_line_is_kind():
	var failures: Array = []

	var lines: Array = []
	for stars: int in range(0, 4):
		lines.append(["headline at %d stars" % stars, String(SummaryScript._level_headline(stars))])
		lines.append(["encouragement at %d stars" % stars, String(SummaryScript.encouragement_for(stars))])
	for earned: int in range(0, 4):
		lines.append(["legacy headline for %d" % earned, String(SummaryScript._headline(earned))])

	for entry: Array in lines:
		var label: String = String(entry[0])
		var line: String = String(entry[1])
		var lowered: String = line.to_lower()
		for word: String in UNKIND_WORDS:
			if lowered.contains(word):
				failures.append("the %s says \"%s\", which contains \"%s\" -- this screen never tells a child what they did not do"
						% [label, line, word])
		for banned: String in BANNED_SUBSTRINGS:
			if lowered.contains(banned.to_lower()):
				failures.append("the %s says \"%s\", which contains \"%s\" -- CLAUDE.md bans scores and percentages"
						% [label, line, banned])

	return failures


## The 0-star line has to do more than avoid being unkind: it has to give the
## child somewhere to go. "Nice playing!" on its own is a shrug.
func _test_zero_star_line_points_forward():
	var failures: Array = []

	var line: String = String(SummaryScript.encouragement_for(0))
	if line.strip_edges().is_empty():
		failures.append(
			"there is no encouragement line after a 0-star run. Without it the screen is a kind "
			+ "headline over three empty outlines, which is a failure screen in a nice jumper.")
	elif not line.to_lower().contains("star"):
		failures.append(
			"the 0-star line is \"%s\"; it should name the thing still to find, so the row of " % line
			+ "outlines above it reads as a promise rather than as a gap.")

	# And at three stars it must fall silent -- there is nothing left to point at
	# and a child who did everything should not be told to keep going.
	if not String(SummaryScript.encouragement_for(3)).strip_edges().is_empty():
		failures.append("a 3-star run is still being told what is left to find")

	return failures


func _test_zero_stars_is_never_a_dead_end():
	var failures: Array = []

	var screen: Control = _make(failures)
	if screen == null:
		return failures

	screen.call("show_summary", 0, 12, [], {
		"levelId": "breakfast", "levelTitle": "Breakfast",
		"levelStars": 0, "bestStars": 0, "hasNextLevel": true,
	})

	for entry: Array in [["%PlayAgainButton", "Replay"], ["%NextButton", "Next"]]:
		var button: Button = screen.get_node_or_null(String(entry[0])) as Button
		if button == null:
			failures.append("ui_kindness: %s is missing from the summary scene" % String(entry[0]))
			continue
		if not button.visible:
			failures.append("%s is hidden after a 0-star run; a child who could not find a star must not be stuck on that level"
					% String(entry[1]))
		if button.disabled:
			failures.append("%s is disabled after a 0-star run" % String(entry[1]))

	_free(screen)
	return failures


## Nothing printed in the scene file is a score either.
func _test_no_scores_in_the_scene():
	var failures: Array = []

	var screen: Control = _make(failures)
	if screen == null:
		return failures

	var labels: Array = []
	_collect(screen, labels)
	if labels.is_empty():
		failures.append("ui_kindness: the summary scene has no labels; the sweep is vacuous")

	for label: Label in labels:
		var text: String = label.text.to_lower()
		for banned: String in BANNED_SUBSTRINGS:
			if text.contains(banned.to_lower()):
				failures.append("%s is authored as \"%s\", which contains \"%s\""
						% [String(screen.get_path_to(label)), label.text, banned])
		for word: String in UNKIND_WORDS:
			if text.contains(word):
				failures.append("%s is authored as \"%s\", which contains \"%s\""
						% [String(screen.get_path_to(label)), label.text, word])

	_free(screen)
	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _collect(node: Node, into: Array) -> void:
	if node is Label:
		into.append(node)
	for child: Node in node.get_children():
		_collect(child, into)


func _make(failures: Array) -> Control:
	if not ResourceLoader.exists(SUMMARY_SCENE):
		failures.append("ui_kindness: %s does not exist" % SUMMARY_SCENE)
		return null
	var packed: PackedScene = load(SUMMARY_SCENE) as PackedScene
	if packed == null or not packed.can_instantiate():
		failures.append("ui_kindness: %s cannot be instantiated" % SUMMARY_SCENE)
		return null
	var screen: Control = packed.instantiate() as Control
	if screen == null:
		failures.append("ui_kindness: %s did not instantiate as a Control" % SUMMARY_SCENE)
		return null

	# Into the tree, because `show_summary()` reaches for autoloads and a
	# celebration child. `_ensure_resolved()` makes it safe to drive immediately.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.add_child(screen)
	return screen


func _free(screen: Control) -> void:
	if screen == null:
		return
	var parent: Node = screen.get_parent()
	if parent != null:
		parent.remove_child(screen)
	screen.queue_free()
