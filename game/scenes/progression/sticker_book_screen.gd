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
## Gap between cards, matching the grid's `h_separation` / `v_separation`.
const GAP: float = 20.0
## One cell plus one gap, matching `StickerCell.MIN_SIZE.x`.
const COLUMN_WIDTH: float = StickerCell.MIN_SIZE.x + GAP
## How far below the widest fitting count we will drop to get a tidier last row.
const COLUMN_SLACK: int = 3
## Room for the vertical scrollbar, so a card is never clipped by it.
const SCROLLBAR_ALLOWANCE: float = 28.0

## How far a card may grow past its minimum to fill the page. Two rows of
## sixteen used to sit in the top 60% of a phone-shaped screen with nothing
## underneath, which read as "the book is nearly empty" rather than "these are
## the ones left to earn".
const CELL_MAX_WIDTH: float = 330.0

var _grid: GridContainer = null
var _count_label: Label = null
var _back_button: Button = null

## The sticker cards, in library order, held apart from the grid's children --
## the grid also carries the invisible spacers that centre the final row, and
## counting those as stickers would pick the wrong column count.
var _cells: Array[Control] = []

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

	# The page only knows how tall a card may grow once the scroll area has been
	# laid out, which happens a frame after the viewport reports its size.
	var scroll: Control = get_node_or_null("%Scroll") as Control
	if scroll != null and not scroll.resized.is_connected(_update_columns):
		scroll.resized.connect(_update_columns)

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
	_cells.clear()

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
		_cells.append(cell)
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
	# Measured from the safe area and the scroll viewport, never from the grid's
	# own row: the row is sized by the grid, so reading it back would feed the
	# column count into itself and settle on whatever it guessed first.
	var available: float = get_viewport_rect().size.x
	var host: Control = get_node_or_null("SafeArea") as Control
	if host != null and host.size.x > COLUMN_WIDTH:
		available = host.size.x
	available -= SCROLLBAR_ALLOWANCE
	if available <= 0.0:
		return

	var total: int = _cells.size()
	var columns: int = pick_columns(available, total)
	_grid.columns = columns

	var page_height: float = 0.0
	var scroll: Control = get_node_or_null("%Scroll") as Control
	if scroll != null and scroll.size.y > 1.0:
		page_height = scroll.size.y

	_centre_last_row(columns, total)

	var cell: Vector2 = cell_size(available, page_height, columns, total)
	for child: Node in _grid.get_children():
		var card: Control = child as Control
		if card != null:
			card.custom_minimum_size = cell


## Indents the final row so it sits under the middle of the page.
##
## A `GridContainer` packs its last row hard against the left edge. With sixteen
## stickers over six columns that leaves four cards huddled in the corner under
## two full rows, and the page stops reading as a collection and starts reading
## as a list that ran out. There is no alignment property for this, so the row is
## indented with invisible cards: half the shortfall before the last row's first
## real sticker, which centres it.
##
## The spacers are `MOUSE_FILTER_IGNORE` and draw nothing, so nothing about the
## touch behaviour changes -- and they are rebuilt here rather than in
## `refresh()` because the column count changes with the viewport.
func _centre_last_row(columns: int, total: int) -> void:
	if _grid == null:
		return

	var lead: int = 0
	if columns > 1 and total > columns:
		# Integer division on purpose: an odd shortfall leans left by half a
		# card, which is far less noticeable than leaning right.
		lead = _last_row_gap(columns, total) / 2

	# Rebuild the child order: full rows, then the indent, then the last row.
	for child: Node in _grid.get_children():
		if child is Control and not _cells.has(child):
			_grid.remove_child(child)
			child.queue_free()

	var before_last_row: int = maxi(total - (columns - _last_row_gap(columns, total)), 0)
	var index: int = 0
	for cell: Control in _cells:
		if index == before_last_row:
			for _i: int in range(lead):
				var spacer: Control = Control.new()
				spacer.name = "RowIndent%d" % _i
				spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_grid.add_child(spacer)
				_grid.move_child(spacer, index)
				index += 1
		_grid.move_child(cell, index)
		index += 1


## The card size that fills the page without overflowing it.
##
## Square-ish cards grown from `StickerCell.MIN_SIZE` until either the row runs
## out of width or the column runs out of height, so the book fills an iPad page
## and a phone-shaped landscape page equally rather than hugging the top.
##
## `page_height <= 0` means "not laid out yet" -- fall back to the minimum, which
## is always safe, and the next `resized` pass will grow it.
##
## Static and pure so it can be reasoned about (and tested) without a viewport.
static func cell_size(available_width: float, page_height: float, columns: int,
		total: int) -> Vector2:
	var minimum: Vector2 = StickerCell.MIN_SIZE
	if columns <= 0 or total <= 0:
		return minimum

	if page_height <= 1.0:
		# Not laid out yet. Growing on width alone would size the cards from half
		# the information and show one wrong frame before the next pass corrects
		# it; the minimum always fits.
		return minimum

	var rows: int = _row_count(columns, total)
	var width: float = (available_width - GAP * float(columns - 1)) / float(columns)
	var height: float = (page_height - GAP * float(rows - 1)) / float(rows)
	width = clampf(minf(width, height / StickerCell.ASPECT), minimum.x, CELL_MAX_WIDTH)
	return Vector2(width, width * StickerCell.ASPECT)


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
