class_name StickerBookScreen
extends Control

## The child-facing sticker book: a grid of every sticker in the content
## library, earned ones in full colour and not-yet-earned ones as soft
## silhouettes.
##
## Tapping an earned sticker speaks its English word and plays a soft pop --
## that is the whole interaction. Tapping a locked one gives a gentle tap sound
## and nothing else: no scolding, no score, no "locked" message.
##
## Never a dead end: the big back button is always on screen and always enabled,
## and it only emits `closed()` -- this screen never decides where to go next,
## so scene routing stays with whoever opened it.
##
## Offline only: content comes from `res://`, progress from the local profile.

signal closed()
signal sticker_tapped(sticker_id: String, unlocked: bool)

const _ContentLibrary := preload("res://scripts/content/content_library.gd")
const _StickerBook := preload("res://scripts/progression/sticker_book.gd")
const _StickerCell := preload("res://scripts/progression/sticker_cell.gd")

const SFX_SOFT_POP: String = "soft_pop"
const SFX_GENTLE_TAP: String = "gentle_tap"

## Grid sizing. A fixed six columns left a phone-shaped landscape screen almost
## half empty, so the count is derived from the width that is actually there.
const COLUMNS_MIN: int = 3
const COLUMNS_MAX: int = 8
## One cell plus one gap, matching `StickerCell.MIN_SIZE.x` and the grid's
## `h_separation`.
const COLUMN_WIDTH: float = 210.0
## How far below the widest fitting count we will drop to get a tidier last row.
const COLUMN_SLACK: int = 3

var _grid: GridContainer = null
var _count_label: Label = null
var _back_button: Button = null

var _library: Object = null
var _book: Object = null
var _resolved: bool = false


func _ready() -> void:
	_ensure_resolved()


## Wires the screen up exactly once.
##
## Deliberately not `@onready`: `_ready()` is deferred until the scene tree
## starts processing, so a caller that instantiates this screen and immediately
## calls `refresh()` would otherwise see an empty grid. Every public entry point
## calls this first.
func _ensure_resolved() -> void:
	if _resolved:
		return
	_resolved = true

	_grid = get_node_or_null("%StickerGrid") as GridContainer
	_count_label = get_node_or_null("%CountLabel") as Label
	_back_button = get_node_or_null("%BackButton") as Button

	if _back_button != null and not _back_button.pressed.is_connected(_on_back_pressed):
		_back_button.pressed.connect(_on_back_pressed)

	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_update_columns):
		viewport.size_changed.connect(_update_columns)

	if _library == null:
		_library = _ContentLibrary.create()
	if _book == null:
		_book = _StickerBook.create(_autoload("SaveService"))

	_sync_with_save()
	refresh()


## Rebuilds the grid from the current library + save state. Cheap enough to call
## whenever the screen is shown again.
func refresh() -> void:
	_ensure_resolved()
	if _grid == null:
		return

	for child: Node in _grid.get_children():
		# Remove before freeing: `queue_free()` alone leaves the old cells in the
		# grid until the end of the frame, which would double up the layout.
		_grid.remove_child(child)
		child.queue_free()

	var entries: Array = []
	if _book != null and _library != null:
		entries = _book.call("build_grid_entries", _library)

	var unlocked_count: int = 0
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var entry_dict: Dictionary = entry
		var sticker: Dictionary = entry_dict.get("sticker", {})
		var unlocked: bool = bool(entry_dict.get("unlocked", false))
		if unlocked:
			unlocked_count += 1

		var cell: Control = _StickerCell.new()
		_grid.add_child(cell)
		cell.call("setup", sticker, unlocked, true)
		cell.connect("pressed", _on_sticker_pressed)

	if _count_label != null:
		_count_label.text = "%d / %d" % [unlocked_count, entries.size()]

	# After the cells exist: the column count depends on how many there are.
	_update_columns()


## Lets a caller (or a test harness) drive the screen with its own library and
## book instead of the bundled ones.
func configure(library: Object, book: Object) -> void:
	_ensure_resolved()
	_library = library
	_book = book
	refresh()


func get_book() -> Object:
	_ensure_resolved()
	return _book


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Catch up the book with the saved star total, in case stars were earned while
## this screen did not exist. Purely additive, so it can never revoke a sticker.
func _sync_with_save() -> void:
	if _book == null or _library == null:
		return
	var save_service: Node = _autoload("SaveService")
	if save_service == null or not save_service.has_method("get_stars"):
		return
	_book.call("sync_with_stars", int(save_service.call("get_stars")), _library)


func _update_columns() -> void:
	if _grid == null or not is_inside_tree():
		return
	# Measured from the safe area, never from the grid's own row: the row is
	# sized by the grid, so reading it back would feed the column count into
	# itself and settle on whatever it guessed first.
	var available: float = get_viewport_rect().size.x
	var host: Control = get_node_or_null("SafeArea") as Control
	if host != null and host.size.x > COLUMN_WIDTH:
		available = host.size.x
	# Leave room for the vertical scrollbar.
	available -= 28.0
	if available <= 0.0:
		return
	_grid.columns = pick_columns(available, _grid.get_child_count())


## The column count that needs the fewest rows within the width that fits,
## breaking ties on the tidiest last row.
##
## Fewest rows first, not tidiest last row first: a narrower grid can always
## square off the last row, but it does so by pushing the book onto an extra row
## the child then has to scroll to. 16 stickers land on 8 x 2 on a phone-shaped
## landscape screen and 6 + 6 + 4 on an iPad -- both fit without scrolling.
##
## Static and pure so it can be reasoned about (and tested) without a viewport.
static func pick_columns(available_width: float, total: int) -> int:
	var widest: int = clampi(int(floor(available_width / COLUMN_WIDTH)), COLUMNS_MIN, COLUMNS_MAX)
	if total <= 0:
		return widest
	if total <= widest:
		return total

	var best: int = widest
	var best_rows: int = _row_count(widest, total)
	var best_gap: int = _last_row_gap(widest, total)
	for candidate: int in range(widest - 1, maxi(widest - COLUMN_SLACK, COLUMNS_MIN) - 1, -1):
		var rows: int = _row_count(candidate, total)
		var gap: int = _last_row_gap(candidate, total)
		if rows < best_rows or (rows == best_rows and gap < best_gap):
			best = candidate
			best_rows = rows
			best_gap = gap
	return best


static func _row_count(columns: int, total: int) -> int:
	if columns <= 0:
		return total
	return int(ceil(float(total) / float(columns)))


## Empty slots left in the final row.
static func _last_row_gap(columns: int, total: int) -> int:
	if columns <= 0:
		return total
	var remainder: int = total % columns
	return 0 if remainder == 0 else columns - remainder


func _on_sticker_pressed(sticker_id: String, unlocked: bool) -> void:
	sticker_tapped.emit(sticker_id, unlocked)

	if not unlocked:
		# Gentle acknowledgement only -- a locked sticker is a "soon", never a
		# mistake, so there is no error sound and no spoken correction.
		_play_sfx(SFX_GENTLE_TAP)
		return

	_play_sfx(SFX_SOFT_POP)

	var sticker: Dictionary = {}
	if _library != null and _library.has_method("get_sticker"):
		sticker = _library.call("get_sticker", sticker_id)
	var word: String = String(sticker.get("word", "")).strip_edges()
	if word.is_empty():
		return

	var tts: Node = _autoload("TtsService")
	if tts != null and tts.has_method("speak"):
		tts.call("speak", word)


func _on_back_pressed() -> void:
	_play_sfx(SFX_GENTLE_TAP)
	closed.emit()


func _play_sfx(sfx_name: String) -> void:
	var sfx: Node = _autoload("Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", sfx_name)


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
	# Hardware/OS back (Android back button, Esc while testing on desktop) must
	# leave the same way the on-screen button does.
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_on_back_pressed()
