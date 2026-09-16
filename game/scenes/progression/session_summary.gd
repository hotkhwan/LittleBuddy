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
signal closed()

const _Celebration := preload("res://scripts/progression/celebration.gd")

const SFX_GENTLE_TAP: String = "gentle_tap"

var _earned_label: Label = null
var _total_label: Label = null
var _title_label: Label = null
var _sticker_row: Control = null
var _sticker_cell: Control = null
var _sticker_label: Label = null
var _play_again_button: Button = null
var _close_button: Button = null

var _celebration: Control = null
var _shown: bool = false
var _resolved: bool = false


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
	_sticker_row = get_node_or_null("%StickerRow") as Control
	_sticker_cell = get_node_or_null("%StickerCell") as Control
	_sticker_label = get_node_or_null("%StickerLabel") as Label
	_play_again_button = get_node_or_null("%PlayAgainButton") as Button
	_close_button = get_node_or_null("%CloseButton") as Button

	if _play_again_button != null and not _play_again_button.pressed.is_connected(_on_play_again_pressed):
		_play_again_button.pressed.connect(_on_play_again_pressed)
	if _close_button != null and not _close_button.pressed.is_connected(_on_close_pressed):
		_close_button.pressed.connect(_on_close_pressed)

	if _celebration == null:
		_celebration = _Celebration.new()
		add_child(_celebration)

	if _sticker_row != null:
		_sticker_row.visible = false


## Fills in and (optionally) celebrates.
##
## `new_stickers` should be the list returned by
## `StickerBook.register_star_change()` -- already de-duplicated, so a sticker
## cannot be celebrated a second time by re-showing this screen.
func show_summary(stars_earned: int, total_stars: int, new_stickers: Array = []) -> void:
	_ensure_resolved()

	var earned: int = maxi(stars_earned, 0)
	var total: int = maxi(total_stars, 0)

	if _earned_label != null:
		_earned_label.text = "+%d" % earned
	if _total_label != null:
		_total_label.text = str(total)
	if _title_label != null:
		_title_label.text = "Great job!" if earned > 0 else "Nice playing!"

	var sticker: Dictionary = _first_sticker(new_stickers)
	if _sticker_row != null:
		_sticker_row.visible = not sticker.is_empty()
	if not sticker.is_empty():
		if _sticker_cell != null:
			_sticker_cell.call("setup", sticker, true, false)
		if _sticker_label != null:
			_sticker_label.text = String(sticker.get("displayName", sticker.get("word", "")))

	visible = true

	# Only celebrate the first time this instance is shown, so reopening the
	# summary never replays the reward moment (or its sound) for the same run.
	if not _shown:
		_shown = true
		_speak(_headline(earned))
		if _celebration != null:
			_celebration.call("celebrate", maxi(earned, 1), new_stickers)


## Lets the same instance be reused for the next mission.
func reset() -> void:
	_ensure_resolved()
	_shown = false
	if _sticker_row != null:
		_sticker_row.visible = false


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

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


func _on_close_pressed() -> void:
	_play_sfx(SFX_GENTLE_TAP)
	closed.emit()


func _play_sfx(sfx_name: String) -> void:
	var sfx: Node = _autoload("Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", sfx_name)


func _speak(text: String) -> void:
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
