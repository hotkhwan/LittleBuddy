class_name Celebration
extends Control

## A short, gentle reward moment: a few stars pop and float up, a soft chime
## plays, and -- when a sticker was just earned -- the sticker itself springs in
## once before fading.
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

# SFX names. Literal strings on purpose: this keeps the celebration decoupled
# from the audio script's load order, and they match `SfxPlayer`'s constants.
const SFX_STAR_EARNED: String = "star_earned"
const SFX_STICKER_UNLOCK: String = "sticker_unlock"
const SFX_SUCCESS_CHIME: String = "success_chime"

## Hard cap on simultaneous star sprites -- delight, not a fireworks display.
const MAX_STARS: int = 5

const STAR_SIZE: float = 74.0
const STAR_DURATION: float = 0.85
const STICKER_SIZE: Vector2 = Vector2(210.0, 230.0)
const STICKER_DURATION: float = 1.25

## Where the stars burst from, in this control's local space. Defaults to the
## centre; `set_origin()` moves it (e.g. over the star counter).
var origin: Vector2 = Vector2.INF

var _playing: bool = false
var _pending: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
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

	var area: Vector2 = _effective_size()
	var burst_origin: Vector2 = origin
	if burst_origin == Vector2.INF:
		burst_origin = Vector2(area.x * 0.5, area.y * 0.55)

	for i: int in range(stars):
		_spawn_star(burst_origin, i, stars)

	var first_sticker: Dictionary = _first_sticker(stickers)
	if not first_sticker.is_empty():
		_spawn_sticker(first_sticker)

	if _pending == 0:
		_playing = false
		finished.emit()


## Convenience: just the chime, no visuals. For small "nice try" moments.
func chime() -> void:
	_play_sfx(SFX_SUCCESS_CHIME)


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _spawn_star(burst_origin: Vector2, index: int, total: int) -> void:
	var star: Control = _IconGlyph.new()
	star.set("glyph", _IconGlyph.Glyph.STAR)
	star.custom_minimum_size = Vector2(STAR_SIZE, STAR_SIZE)
	star.size = Vector2(STAR_SIZE, STAR_SIZE)
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.pivot_offset = Vector2(STAR_SIZE, STAR_SIZE) * 0.5
	star.scale = Vector2(0.2, 0.2)
	star.modulate = Color(1.0, 1.0, 1.0, 0.0)

	# Fan the stars out symmetrically -- deterministic, so it looks composed
	# rather than random, and never lands off-screen.
	var spread: float = 0.0 if total <= 1 else (float(index) / float(total - 1)) - 0.5
	var start: Vector2 = burst_origin + Vector2(spread * 150.0, 0.0) - star.size * 0.5
	star.position = start
	add_child(star)
	_pending += 1

	var rise: Vector2 = start + Vector2(spread * 90.0, -130.0)
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
	cell.position = (_effective_size() - STICKER_SIZE) * 0.5
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
