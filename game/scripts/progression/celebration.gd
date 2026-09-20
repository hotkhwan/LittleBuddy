class_name Celebration
extends Control

## A short, gentle reward moment: a few stars pop and float up, a soft chime
## plays, and -- when a sticker was just earned -- the sticker itself springs in
## once before fading.
##
## It plays in the top-right corner by default, deliberately away from the
## middle of the screen: the baby lives there, and hiding the character at the
## happiest moment of the loop is exactly the wrong thing to do.
##
## Deliberately cheap: everything is procedurally drawn `Control` nodes animated
## with `Tween`. No particle systems, no shaders, no post-processing, no glow, no
## GI. It costs a handful of small draw calls for about a second and then frees
## its own children, so it is safe to fire after every task on a phone.
##
## Self-contained -- it builds its own children, so a caller only needs:
##
##     var celebration := preload("res://scripts/progression/celebration.gd").new()
##     safe_area.add_child(celebration)
##     celebration.celebrate(1, new_stickers)
##
## It never blocks touch (`MOUSE_FILTER_IGNORE` on every node it makes) and it
## never blocks gameplay: `finished` always fires, even with no stars to show.

signal finished()
signal sticker_shown(sticker_id: String)

const _StickerArt := preload("res://scripts/progression/sticker_art.gd")
const _IconGlyph := preload("res://scripts/progression/icon_glyph.gd")
const _StickerCell := preload("res://scripts/progression/sticker_cell.gd")
## The glossy star -- the same one the summary's rating row and the highchair's
## counter draw, so a star looks like the same star wherever it appears.
const _RatingStar := preload("res://scripts/ui/rating_star.gd")

# SFX names. Literal strings on purpose: this keeps the celebration decoupled
# from the audio script's load order, and they match `SfxPlayer`'s constants.
const SFX_STAR_EARNED: String = "star_earned"
const SFX_STICKER_UNLOCK: String = "sticker_unlock"
const SFX_SUCCESS_CHIME: String = "success_chime"

## Hard cap on simultaneous star sprites -- delight, not a fireworks display.
const MAX_STARS: int = 5

const STAR_SIZE: float = 84.0
const STAR_DURATION: float = 0.85
const STICKER_SIZE: Vector2 = Vector2(200.0, 220.0)
const STICKER_DURATION: float = 1.25

## Inset of the default anchor from the top-right corner.
##
## The reward moment used to default to the middle of the screen, which put a
## 210x230 sticker card squarely over the baby at the one moment the child most
## wants to see them react. It now plays in the top-right corner instead: empty
## in both landscape aspects, clear of the speech bubble and the progress dots,
## and below the parent gear.
const EDGE_MARGIN: float = 10.0
const TOP_MARGIN: float = 96.0

## How far a star drifts as it fades. Shorter when a card is on screen, so the
## rise stays in the gap under it instead of disappearing behind it.
const STAR_RISE: float = 130.0
const STAR_RISE_WITH_CARD: float = 56.0

## Stars burst below the card so the sticker never hides them.
##
## Derived rather than a round number, and derived from the *end* of the flight
## rather than its start: at a flat 118 the stars began inside the card's bottom
## edge and then rose straight up behind it, so most of the reward moment
## happened where nobody could see it. Half the card, half a star, the whole
## rise, and a 16px gap.
const STAR_DROP: float = STICKER_SIZE.y * 0.5 + STAR_SIZE * 0.5 \
	+ STAR_RISE_WITH_CARD + 16.0

## Warm gold, matching the star on the counter and on the summary.
const STAR_COLOR: Color = Color(1.0, 0.78, 0.24)

## Centre of the reward moment, in this control's local space. `Vector2.INF`
## means "use the default top-right anchor"; `set_origin_global()` overrides it
## (the session summary points it at its own star row).
var origin: Vector2 = Vector2.INF

var _playing: bool = false
var _pending: int = 0


func _init() -> void:
	# In `_init`, not `_ready`: an overlay that has not entered the tree yet must
	# already be incapable of swallowing a touch.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	# `set_anchors_preset()` defaults to keep_offsets = TRUE, which pinned this
	# node at its original zero size and left `_effective_size()` silently
	# falling back to the whole viewport -- so the reward moment ignored the safe
	# area entirely and could spill past the screen edge. The offsets have to be
	# reset with the anchors.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# An overlay must never swallow a child's touch on the room underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_playing() -> bool:
	return _playing


## Points the star burst at a position given in *global* (viewport) coordinates.
func set_origin_global(global_pos: Vector2) -> void:
	origin = global_pos - global_position


func clear_origin() -> void:
	origin = Vector2.INF


## Plays the reward moment.
##
## `star_count` is the number of star sprites to pop (clamped, purely visual).
## `stickers` is an optional list of content-library sticker dictionaries to
## show as a flourish -- pass the result of
## `StickerBook.register_star_change()` so a sticker is celebrated only once.
func celebrate(star_count: int = 1, stickers: Array = []) -> void:
	if not is_inside_tree():
		# Nothing to animate against; still complete so callers never hang.
		finished.emit()
		return

	_playing = true
	_pending = 0

	var stars: int = clampi(star_count, 1, MAX_STARS)
	_play_sfx(SFX_STAR_EARNED)

	var first_sticker: Dictionary = _first_sticker(stickers)

	# With a card on screen the stars start below it, so the card never hides
	# them; on their own they pop right at the anchor.
	var has_card: bool = not first_sticker.is_empty()
	var burst_origin: Vector2 = _moment_origin()
	var rise: float = STAR_RISE
	if has_card:
		burst_origin += Vector2(0.0, STAR_DROP)
		rise = STAR_RISE_WITH_CARD
		# The card goes down first so it sits *under* the stars. They should not
		# overlap at all, but if a clamp on a narrow screen ever pushes them
		# together, a star over the card reads better than half a star behind it.
		_spawn_sticker(first_sticker)

	for i: int in range(stars):
		_spawn_star(burst_origin, i, stars, rise)

	if _pending == 0:
		_playing = false
		finished.emit()


## Convenience: just the chime, no visuals. For small "nice try" moments.
func chime() -> void:
	_play_sfx(SFX_SUCCESS_CHIME)


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _spawn_star(burst_origin: Vector2, index: int, total: int,
		rise_distance: float = STAR_RISE) -> void:
	var star: Control = _RatingStar.new()
	star.call("set_state", _RatingStar.State.EARNED)
	star.custom_minimum_size = Vector2(STAR_SIZE, STAR_SIZE)
	star.size = Vector2(STAR_SIZE, STAR_SIZE)
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.pivot_offset = Vector2(STAR_SIZE, STAR_SIZE) * 0.5
	star.scale = Vector2(0.2, 0.2)
	star.modulate = Color(1.0, 1.0, 1.0, 0.0)

	# Fan the stars out symmetrically -- deterministic, so it looks composed
	# rather than random, and never lands off-screen.
	var spread: float = 0.0 if total <= 1 else (float(index) / float(total - 1)) - 0.5
	var start: Vector2 = _clamped(
		burst_origin + Vector2(spread * 120.0, 0.0) - star.size * 0.5, star.size)
	star.position = start
	add_child(star)
	_pending += 1

	# The end of the drift is clamped as well as the start: an unclamped target
	# is what let the outermost star slide off the edge of an iPad.
	var rise: Vector2 = _clamped(start + Vector2(spread * 70.0, -rise_distance), star.size)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(star, "position", rise, STAR_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
		.set_delay(float(index) * 0.05)
	tween.tween_property(star, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.set_delay(float(index) * 0.05)
	tween.tween_property(star, "modulate:a", 1.0, 0.18) \
		.set_delay(float(index) * 0.05)
	tween.tween_property(star, "modulate:a", 0.0, 0.3) \
		.set_delay(float(index) * 0.05 + STAR_DURATION - 0.3)
	tween.chain().tween_callback(_on_piece_finished.bind(star))


func _spawn_sticker(sticker: Dictionary) -> void:
	var cell: Control = _StickerCell.new()
	cell.custom_minimum_size = STICKER_SIZE
	cell.size = STICKER_SIZE
	# Belt and braces: `setup(..., interactive = false)` also does this, but the
	# cell is in the tree for an instant before that call and must never be able
	# to swallow a touch meant for the room underneath.
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.position = _clamped(_moment_origin() - STICKER_SIZE * 0.5, STICKER_SIZE)
	cell.pivot_offset = STICKER_SIZE * 0.5
	cell.scale = Vector2(0.4, 0.4)
	cell.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(cell)
	cell.call("setup", sticker, true, false)
	_pending += 1

	_play_sfx(SFX_STICKER_UNLOCK)
	_speak(String(sticker.get("celebrationPhrase", "")))
	sticker_shown.emit(String(sticker.get("stickerId", "")))

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(cell, "scale", Vector2.ONE, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12)
	tween.tween_property(cell, "modulate:a", 1.0, 0.24).set_delay(0.12)
	tween.tween_property(cell, "position:y", cell.position.y - 26.0, STICKER_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.12)
	tween.tween_property(cell, "modulate:a", 0.0, 0.32) \
		.set_delay(STICKER_DURATION)
	tween.chain().tween_callback(_on_piece_finished.bind(cell))


func _on_piece_finished(piece: Node) -> void:
	if is_instance_valid(piece):
		piece.queue_free()
	_pending -= 1
	if _pending <= 0:
		_pending = 0
		_playing = false
		finished.emit()


## Centre of the reward moment in local space: whatever `set_origin_global()`
## was given, else the default top-right anchor.
func _moment_origin() -> Vector2:
	if origin != Vector2.INF:
		return origin
	var area: Vector2 = _effective_size()
	return Vector2(
		area.x - EDGE_MARGIN - STICKER_SIZE.x * 0.5,
		TOP_MARGIN + STICKER_SIZE.y * 0.5)


## Keeps a `piece_size` box fully inside this control, so a narrow phone in
## landscape can never push the card out past the safe area.
func _clamped(pos: Vector2, piece_size: Vector2) -> Vector2:
	var area: Vector2 = _effective_size()
	return Vector2(
		clampf(pos.x, 0.0, maxf(area.x - piece_size.x, 0.0)),
		clampf(pos.y, 0.0, maxf(area.y - piece_size.y, 0.0)))


## `size` can still be zero on the frame this node is added, which would pile the
## whole burst into the top-left corner. Fall back to the viewport in that case.
func _effective_size() -> Vector2:
	if size.x > 1.0 and size.y > 1.0:
		return size
	return get_viewport_rect().size


static func _first_sticker(stickers: Array) -> Dictionary:
	for entry: Variant in stickers:
		if typeof(entry) == TYPE_DICTIONARY and not (entry as Dictionary).is_empty():
			return entry
	return {}


func _play_sfx(sfx_name: String) -> void:
	var sfx: Node = _autoload("Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", sfx_name)


func _speak(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	var tts: Node = _autoload("TtsService")
	if tts != null and tts.has_method("speak"):
		tts.call("speak", text)


## Autoloads are absent in the headless test runner and unreachable before the
## scene tree is active, so every lookup is guarded. A missing autoload only
## means a silent celebration, never a crash.
func _autoload(autoload_name: String) -> Node:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)
