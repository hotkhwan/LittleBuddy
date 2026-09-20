class_name SessionSummary
extends Control

## The "you did it" screen shown after a mission.
##
## Shows three things and nothing else: the stars earned just now, the running
## total, and any sticker that was just unlocked. Then one big friendly
## "Play again" button, plus a back button so there is always a second way out.
##
## No score, no percentage, no timer, no stars-out-of-five rating, no
## "you missed N" -- it is a celebration, not a report card. The headline is
## also spoken, so a child who cannot read still understands it.
##
## Routing is the caller's job: this screen only emits `play_again()` and
## `closed()`.

signal play_again()
signal next_level()
signal closed()

const _Celebration := preload("res://scripts/progression/celebration.gd")
const _RatingStar := preload("res://scripts/ui/rating_star.gd")
## The voice pack (2026-09-20): "You earned a star!" after the headline when
## stars were earned, "A new sticker for you!" when one unlocked. Null-guarded;
## the headline still goes through TtsService when there is no `Voice`.
const VoiceBridge := preload("res://scripts/voice/voice_bridge.gd")
const VoiceCues := preload("res://scripts/voice/voice_cues.gd")

const SFX_GENTLE_TAP: String = "gentle_tap"

## The level rating is a separate currency from `stars`. `stars` is the lifetime
## task total that drives stickers; this is 0..3 for *this* level, best-ever.
## They are never summed -- see docs/PHASE1_CONTRACT.md.
const MAX_LEVEL_STARS: int = 3

## Half stars ("almost") shown on the summary, at most. A halved task is one the
## child finished after a wrong try on the highchair; it pays 0 stars (see
## `feeding_rules.gd`) and is shown here as a half star with a kind word, never
## as a deduction.
const MAX_ALMOST_STARS: int = 3
const ALMOST_LINE: String = "So close!"

## The panel is designed for the 1366x1024 canvas. On a shorter viewport (a
## SubViewport in a harness, a small window) it scales down about its centre
## rather than running off the bottom of the screen.
const DESIGN_HEIGHT: float = 960.0

## What the child is told under the rating row, per rating.
##
## The entry that matters is index 0. `CLAUDE.md` and the slice contract both say
## a 0-star completion is celebrated and never a failure screen, and the screen
## this replaces broke that in two ways at once: a gold star beside the text
## "+0", and three pale filled blobs where the rating should be.
##
## The fix is not softer wording -- the headline was already "Nice playing!" --
## it is removing the zero and giving the child somewhere to go. So at 0 stars
## the tally disappears entirely and this line points forward, at the Replay
## button sitting directly under it. Nothing here names what was missed, counts
## anything, or uses the word "try": there is nothing to try again, only more to
## find.
const ENCOURAGEMENT: Array[String] = [
	"There are stars to find in here!",
	"Two more stars are waiting!",
	"One more star is waiting!",
	"",
]

var _earned_label: Label = null
var _total_label: Label = null
var _title_label: Label = null
var _encourage_label: Label = null
var _earned_row: Control = null
var _sticker_row: Control = null
var _sticker_cell: Control = null
var _sticker_label: Label = null
var _play_again_button: Button = null
var _next_button: Button = null
var _close_button: Button = null
var _level_label: Label = null
var _rating_row: Control = null
var _rating_stars: Array[CanvasItem] = []
var _almost_row: Control = null
var _almost_stars: Array[CanvasItem] = []
var _almost_label: Label = null
var _center: Control = null

var _celebration: Control = null
var _shown: bool = false
var _resolved: bool = false
## -1 means "no level result supplied" (legacy mode), which is different from a
## genuine 0-star rating and must not be shown or spoken as one.
var _rated_stars: int = -1


func _ready() -> void:
	_ensure_resolved()


## Wires the scene up exactly once.
##
## Deliberately not `@onready`: `_ready()` is deferred until the scene tree
## starts processing, so a caller that instantiates this screen and immediately
## calls `show_summary()` would otherwise hit a wall of nulls. Every public
## entry point calls this first, so the screen is usable the moment it exists.
func _ensure_resolved() -> void:
	if _resolved:
		return
	_resolved = true

	_earned_label = get_node_or_null("%EarnedLabel") as Label
	_total_label = get_node_or_null("%TotalLabel") as Label
	_title_label = get_node_or_null("%TitleLabel") as Label
	_encourage_label = get_node_or_null("%EncourageLabel") as Label
	_earned_row = get_node_or_null("%EarnedRow") as Control
	_sticker_row = get_node_or_null("%StickerRow") as Control
	_sticker_cell = get_node_or_null("%StickerCell") as Control
	_sticker_label = get_node_or_null("%StickerLabel") as Label
	_play_again_button = get_node_or_null("%PlayAgainButton") as Button
	_next_button = get_node_or_null("%NextButton") as Button
	_close_button = get_node_or_null("%CloseButton") as Button
	_level_label = get_node_or_null("%LevelLabel") as Label
	_rating_row = get_node_or_null("%RatingRow") as Control

	_rating_stars = []
	for index: int in range(MAX_LEVEL_STARS):
		var star: CanvasItem = get_node_or_null("%%RatingStar%d" % (index + 1)) as CanvasItem
		if star != null:
			_rating_stars.append(star)

	_almost_row = get_node_or_null("%AlmostRow") as Control
	_almost_label = get_node_or_null("%AlmostLabel") as Label
	_almost_stars = []
	for index: int in range(MAX_ALMOST_STARS):
		var half: CanvasItem = get_node_or_null("%%AlmostStar%d" % (index + 1)) as CanvasItem
		if half != null:
			_almost_stars.append(half)
	_center = get_node_or_null("SafeArea/Center") as Control
	if _center != null and not _center.resized.is_connected(_fit_panel):
		_center.resized.connect(_fit_panel)

	if _play_again_button != null and not _play_again_button.pressed.is_connected(_on_play_again_pressed):
		_play_again_button.pressed.connect(_on_play_again_pressed)
	if _next_button != null and not _next_button.pressed.is_connected(_on_next_pressed):
		_next_button.pressed.connect(_on_next_pressed)
	if _close_button != null and not _close_button.pressed.is_connected(_on_close_pressed):
		_close_button.pressed.connect(_on_close_pressed)

	if _celebration == null:
		_celebration = _Celebration.new()
		# Under the SafeArea, not the root: the celebration anchors itself to the
		# top-right corner, which must be the safe corner on a notched device.
		var host: Node = get_node_or_null("SafeArea")
		if host == null:
			host = self
		host.add_child(_celebration)

	if _sticker_row != null:
		_sticker_row.visible = false

	# Hidden until a level result is actually supplied. Legacy mode has no level,
	# and an all-empty rating row would read as "you earned nothing".
	_apply_level_result({})


## Fills in and (optionally) celebrates.
##
## `new_stickers` should be the list returned by
## `StickerBook.register_star_change()` -- already de-duplicated, so a sticker
## cannot be celebrated a second time by re-showing this screen.
## `level_result` is optional and additive, so every existing caller keeps working
## unchanged. Recognised keys:
##   `levelTitle`  String  -- shown above the rating
##   `levelStars`  int     -- 0..3 earned in *this* run
##   `bestStars`   int     -- 0..3 best ever, so a weaker replay never looks like
##                            a demotion (the row shows the best, never less)
##   `hasNextLevel` bool   -- false hides Next, so the button never dead-ends
func show_summary(stars_earned: int, total_stars: int, new_stickers: Array = [], level_result: Dictionary = {}) -> void:
	_ensure_resolved()

	var earned: int = maxi(stars_earned, 0)
	var total: int = maxi(total_stars, 0)

	_apply_level_result(level_result)
	_apply_almost(int(level_result.get("almostStars", 0)) if typeof(level_result) == TYPE_DICTIONARY else 0)

	if _earned_label != null:
		_earned_label.text = "+%d" % earned
	# "+0" beside a gold star is the single unkindest thing this screen could
	# say, and it is also information the child cannot use. When nothing was
	# added, the tally is simply not there -- the rating row and the
	# encouragement line carry the moment instead.
	if _earned_row != null:
		_earned_row.visible = earned > 0
	if _total_label != null:
		_total_label.text = str(total)
	if _title_label != null:
		_title_label.text = "Great job!" if earned > 0 else "Nice playing!"

	var sticker: Dictionary = _first_sticker(new_stickers)
	if _sticker_row != null:
		_sticker_row.visible = not sticker.is_empty()
	if not sticker.is_empty():
		if _sticker_cell != null:
			# No caption on the card: the label beside it already prints the word,
			# and this screen used to say "Milk" twice, a centimetre apart.
			_sticker_cell.call("setup", sticker, true, false, false)
		if _sticker_label != null:
			_sticker_label.text = String(sticker.get("displayName", sticker.get("word", "")))

	visible = true
	# Now and again after the layout pass: the first `resized` can fire before
	# `_ensure_resolved()` has connected to it.
	_fit_panel()
	if is_inside_tree():
		call_deferred("_fit_panel")

	# Only celebrate the first time this instance is shown, so reopening the
	# summary never replays the reward moment (or its sound) for the same run.
	if not _shown:
		_shown = true
		# A level rating is the more meaningful number when there is one: "two
		# stars on Bath Time" is what the child just achieved, whereas `earned`
		# is a running task tally they have no way to see.
		if _rated_stars >= 0:
			_speak(_level_headline(_rated_stars))
		else:
			_speak(_headline(earned))
		var reward_lines: Array = []
		if earned > 0 or _rated_stars > 0:
			reward_lines.append_array(VoiceCues.for_event(VoiceCues.EVENT_STAR))
		if not sticker.is_empty():
			reward_lines.append_array(VoiceCues.for_event(VoiceCues.EVENT_STICKER))
		VoiceBridge.say_lines(self, reward_lines, {"queue": true})
		if _celebration != null:
			# In the celebration's own top-right corner, the same place the
			# reward moment plays in the baby room -- not over the panel.
			# Anywhere over the panel puts a rising 74px star through either the
			# "Great job!" headline or the new sticker, and the panel is centred,
			# so a proportional guess lands somewhere different at every aspect
			# ratio. The corner is empty dim backdrop at all of them.
			_celebration.call("clear_origin")
			# Stars only. The panel behind already shows the new sticker on its
			# own card, and the flourish used to spring an identical second card
			# straight on top of it.
			_celebration.call("celebrate", maxi(earned, 1), [])


## Lets the same instance be reused for the next mission.
func reset() -> void:
	_ensure_resolved()
	_shown = false
	_rated_stars = -1
	if _sticker_row != null:
		_sticker_row.visible = false
	if _earned_row != null:
		_earned_row.visible = true
	_apply_level_result({})
	_apply_almost(0)


## The "almost" row: one half star per halved task (capped), and a kind word.
func _apply_almost(count: int) -> void:
	var shown: int = clampi(count, 0, MAX_ALMOST_STARS)
	if _almost_row != null:
		_almost_row.visible = shown > 0
	for index: int in range(_almost_stars.size()):
		_almost_stars[index].visible = index < shown
	if _almost_label != null:
		_almost_label.text = ALMOST_LINE


func get_almost_count() -> int:
	var count: int = 0
	for star: CanvasItem in _almost_stars:
		if star.visible and _almost_row != null and _almost_row.visible:
			count += 1
	return count


## Scales the centred panel down when the viewport is shorter than the design
## height, so the buttons never fall off the bottom of a small frame.
func _fit_panel() -> void:
	if _center == null:
		return
	# The HOST's height, not the centre container's: a container grows to its
	# children's minimum size, so its own height is never short.
	var host: Control = _center.get_parent() as Control
	var height: float = host.size.y if host != null else _center.size.y
	if height <= 0.0:
		return
	var factor: float = clampf(height / DESIGN_HEIGHT, 0.6, 1.0)
	_center.pivot_offset = _center.size * 0.5
	_center.scale = Vector2.ONE * factor


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Paints the per-level rating row. Safe to call with `{}`, which hides it.
func _apply_level_result(level_result: Variant) -> void:
	var result: Dictionary = level_result as Dictionary if typeof(level_result) == TYPE_DICTIONARY else {}

	var has_level: bool = result.has("levelStars") or result.has("bestStars")
	if not has_level:
		_rated_stars = -1
		if _rating_row != null:
			_rating_row.visible = false
		if _level_label != null:
			_level_label.visible = false
		if _encourage_label != null:
			_encourage_label.visible = false
		# Without a level there is no "next level", so Replay is the only
		# forward move and Next would lead nowhere.
		if _next_button != null:
			_next_button.visible = false
		return

	var earned_now: int = clampi(int(result.get("levelStars", 0)), 0, MAX_LEVEL_STARS)
	# Show the best ever, never this run's score on its own: a child who replays
	# a 3-star level and gets 2 must not watch a star disappear.
	var shown: int = maxi(earned_now, clampi(int(result.get("bestStars", 0)), 0, MAX_LEVEL_STARS))
	_rated_stars = earned_now

	var title: String = String(result.get("levelTitle", "")).strip_edges()
	if _level_label != null:
		_level_label.text = title
		_level_label.visible = not title.is_empty()

	if _rating_row != null:
		_rating_row.visible = true
	for index: int in range(_rating_stars.size()):
		var star: CanvasItem = _rating_stars[index]
		if star == null:
			continue
		# Earned, next-one-to-find, or ghost -- `rating_star.gd` owns which
		# texture and which palette colour each of those means. The row never
		# paints a faded *filled* star, which is what made three unearned stars
		# read as three empty slots.
		if star.has_method("set_state"):
			star.call("set_state", _RatingStar.state_for(index, shown))
		elif "tint" in star:
			star.set("tint", _RatingStar.color_for(_RatingStar.state_for(index, shown)))

	# Something to look forward to, never something that was missed. Blank at
	# three stars, because there is nothing left to point at.
	if _encourage_label != null:
		var line: String = encouragement_for(shown)
		_encourage_label.text = line
		_encourage_label.visible = not line.is_empty()

	if _next_button != null:
		_next_button.visible = bool(result.get("hasNextLevel", true))


## The line printed under the rating row for a `stars`-out-of-three result.
##
## Public and static so `test_ui_kindness.gd` can read every one of them and
## assert that none of them is a report card.
static func encouragement_for(stars: int) -> String:
	var index: int = clampi(stars, 0, ENCOURAGEMENT.size() - 1)
	return ENCOURAGEMENT[index]


static func _level_headline(stars: int) -> String:
	if stars <= 0:
		# Spoken as well as printed, so a pre-reader gets the same message. The
		# second sentence is the same forward-looking promise as
		# `ENCOURAGEMENT[0]`, not a note about what went wrong.
		return "Nice playing! There are stars to find in here."
	if stars == 1:
		return "Well done! One star."
	if stars >= MAX_LEVEL_STARS:
		return "Amazing! Three stars!"
	return "Great! %d stars." % stars


static func _headline(earned: int) -> String:
	if earned <= 0:
		return "Nice playing!"
	if earned == 1:
		return "Great! You got one star."
	return "Great! You got %d stars." % earned


static func _first_sticker(stickers: Array) -> Dictionary:
	for entry: Variant in stickers:
		if typeof(entry) == TYPE_DICTIONARY and not (entry as Dictionary).is_empty():
			return entry
	return {}


func _on_play_again_pressed() -> void:
	_play_sfx(SFX_GENTLE_TAP)
	play_again.emit()


func _on_next_pressed() -> void:
	_play_sfx(SFX_GENTLE_TAP)
	next_level.emit()


func _on_close_pressed() -> void:
	_play_sfx(SFX_GENTLE_TAP)
	closed.emit()


func _play_sfx(sfx_name: String) -> void:
	var sfx: Node = _autoload("Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", sfx_name)


func _speak(text: String) -> void:
	if VoiceBridge.say_text(self, text):
		return
	var tts: Node = _autoload("TtsService")
	if tts != null and tts.has_method("speak"):
		tts.call("speak", text)


## Guarded: autoloads are absent in the headless runner and unreachable before
## the scene tree is active. A missing one means a silent screen, not a crash.
func _autoload(autoload_name: String) -> Node:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_on_close_pressed()
