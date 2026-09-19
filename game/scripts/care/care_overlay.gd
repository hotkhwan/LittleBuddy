extends Control

## ============================================================================
## THE CARE CLOSE-UP -- brushing, washing and drying, by hand.
## ============================================================================
##
## A full-screen card: Little Buddy's face, large, and one tool the player drags
## across it. Progress fills while the tool is actually ON the face and moving.
##
## ## Why a drawn face and not the 3D child
##
## The rig has no facial animation -- no blendshapes, no jaw bone, nothing. The
## brief is explicit that a facial animation must not be claimed when the mesh
## cannot do it. So the close-up is an honest, deliberately illustrated card in
## the game's own palette: it can smile, blink and react, and it never pretends
## to be the 3D model doing something it cannot. The 3D child is right there
## behind the overlay and reacts in the ways it genuinely can (pose, bubble).
##
## ## The three acts are different verbs, not one tap counter
##
## The brief calls this out specifically, so each is a different GESTURE with
## different feedback:
##
## | Act | Gesture | What it does | Feedback |
## |---|---|---|---|
## | `brushTeeth` | short strokes back and forth over the MOUTH | counts direction CHANGES | foam bubbles build up |
## | `washFace` | circles over the WHOLE face | counts distance travelled | water ripples, dirt fades |
## | `dryFace` | long sweeps that must COVER the face | tracks which patches are dry | wet sheen wipes away |
##
## Brushing rewards scrubbing on the spot; washing rewards covering ground;
## drying rewards reaching every corner. A player who scrubs one spot forever
## finishes brushing and never finishes drying, which is the point.
##
## ## It cannot be failed
##
## There is no timer, no score and no way to lose. `CLAUDE.md`'s child UX rules
## have no failure state, so the only outcomes are "still going" and "done".

const Palette := preload("res://scripts/ui/palette.gd")

signal care_completed(care_kind: String)
signal care_progress(value: float)

const BRUSH: String = "brushTeeth"
const WASH: String = "washFace"
const DRY: String = "dryFace"

## Copy per act: the instruction, the word being taught, and the child's line.
const COPY: Dictionary = {
	BRUSH: {
		"title": "Brush!", "word": "brush", "thai": "แปรงฟัน",
		"hint": "Rub the toothbrush on the teeth.",
		"childLine": "Brush my teeth, please!", "doneLine": "All clean!",
	},
	WASH: {
		"title": "Wash!", "word": "wash", "thai": "ล้างหน้า",
		"hint": "Rub the cloth all over the face.",
		"childLine": "Wash my face!", "doneLine": "So fresh!",
	},
	DRY: {
		"title": "Dry!", "word": "towel", "thai": "ผ้าเช็ดตัว",
		"hint": "Wipe the towel everywhere.",
		"childLine": "I'm all wet!", "doneLine": "Nice and dry!",
	},
}

## How much work each act is. Tuned so every one takes roughly the same few
## seconds of happy scrubbing -- long enough to feel done, short enough that a
## three-year-old does not lose interest.
const BRUSH_STROKES_NEEDED: int = 10
const WASH_DISTANCE_NEEDED: float = 2600.0
const DRY_PATCHES: int = 9

const FACE_RADIUS: float = 190.0
const MOUTH_OFFSET := Vector2(0.0, 92.0)
const MOUTH_RADIUS: float = 96.0
const TOOL_SIZE: float = 96.0

var _kind: String = BRUSH
var _progress: float = 0.0
var _finished: bool = false
var _built: bool = false

var _dragging: bool = false
var _last_pos: Vector2 = Vector2.ZERO
var _last_dir: float = 0.0
var _strokes: int = 0
var _distance: float = 0.0
var _dry_patches: Dictionary = {}
var _foam: Array = []

var _face: Control = null
var _tool: Control = null
var _bar: ProgressBar = null
var _title: Label = null
var _hint: Label = null
var _child_line: Label = null


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	name = "CareOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.42)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	_face = Control.new()
	_face.name = "Face"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_face.draw.connect(_draw_face)
	add_child(_face)

	_tool = Control.new()
	_tool.name = "Tool"
	_tool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tool.draw.connect(_draw_tool)
	add_child(_tool)

	_title = Label.new()
	_title.name = "Title"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_size_override("font_size", 56)
	_title.add_theme_color_override("font_color", Palette.CREAM)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.offset_left = -300.0
	_title.offset_right = 300.0
	_title.offset_top = 48.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", 30)
	_hint.add_theme_color_override("font_color", Palette.CREAM)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_left = -360.0
	_hint.offset_right = 360.0
	_hint.offset_top = 116.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)

	_child_line = Label.new()
	_child_line.name = "ChildLine"
	_child_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_child_line.add_theme_font_size_override("font_size", 36)
	_child_line.add_theme_color_override("font_color", Palette.CREAM)
	_child_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_child_line.offset_left = -400.0
	_child_line.offset_right = 400.0
	_child_line.offset_top = -168.0
	_child_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_child_line)

	_bar = ProgressBar.new()
	_bar.name = "Progress"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.offset_left = -260.0
	_bar.offset_right = 260.0
	_bar.offset_top = -108.0
	_bar.offset_bottom = -72.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.MINT
	fill.set_corner_radius_all(18)
	var back := StyleBoxFlat.new()
	back.bg_color = Palette.CREAM
	back.set_corner_radius_all(18)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	add_child(_bar)


## Opens the overlay for one care act. Resets everything, so replaying a task
## after a resume starts from zero rather than from a stale half-brushed mouth.
func begin(care_kind: String) -> void:
	build()
	_kind = care_kind if COPY.has(care_kind) else BRUSH
	_progress = 0.0
	_finished = false
	_dragging = false
	_strokes = 0
	_distance = 0.0
	_last_dir = 0.0
	_dry_patches.clear()
	_foam.clear()
	var copy: Dictionary = COPY[_kind]
	_title.text = String(copy["title"])
	_hint.text = String(copy["hint"])
	_child_line.text = String(copy["childLine"])
	_bar.value = 0.0
	visible = true
	_redraw()


func get_care_kind() -> String:
	return _kind


func get_progress() -> float:
	return _progress


func is_finished() -> bool:
	return _finished


static func word_for(care_kind: String) -> String:
	return String((COPY.get(care_kind, {}) as Dictionary).get("word", ""))


static func thai_for(care_kind: String) -> String:
	return String((COPY.get(care_kind, {}) as Dictionary).get("thai", ""))


## -- Input ----------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if _finished:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_set_dragging(touch.pressed, touch.position)
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT:
			_set_dragging(click.pressed, click.position)
	elif event is InputEventScreenDrag:
		_move_tool((event as InputEventScreenDrag).position)
	elif event is InputEventMouseMotion and _dragging:
		_move_tool((event as InputEventMouseMotion).position)


func _set_dragging(pressed: bool, at: Vector2) -> void:
	_dragging = pressed
	_last_pos = at
	if pressed:
		_move_tool(at)


## The whole mini-game, and the one place the three acts differ.
##
## Public so a smoke test can play the game without synthesising touch events --
## the same arrangement `room_camera.step()` uses.
func apply_stroke(to: Vector2) -> void:
	if _finished:
		return
	var centre: Vector2 = size * 0.5
	var delta: Vector2 = to - _last_pos
	var moved: float = delta.length()
	_last_pos = to
	if _tool != null:
		_tool.position = to
	if moved <= 0.5:
		return

	match _kind:
		BRUSH:
			# Only counts near the MOUTH, and only a reversal counts: a stroke is
			# a scrub back and forth, not a finger dragged once across the screen.
			if to.distance_to(centre + MOUTH_OFFSET) > MOUTH_RADIUS * 1.35:
				return
			var dir: float = signf(delta.x)
			if dir != 0.0 and dir != _last_dir:
				if _last_dir != 0.0:
					_strokes += 1
					_add_foam(to)
				_last_dir = dir
			_progress = clampf(float(_strokes) / float(BRUSH_STROKES_NEEDED), 0.0, 1.0)
		WASH:
			# Rewards covering ground anywhere on the face.
			if to.distance_to(centre) > FACE_RADIUS * 1.15:
				return
			_distance += moved
			if _foam.size() < 26 and moved > 6.0:
				_add_foam(to)
			_progress = clampf(_distance / WASH_DISTANCE_NEEDED, 0.0, 1.0)
		DRY:
			# Rewards REACH: the face is a 3x3 grid and every patch must be
			# touched, so scrubbing one corner forever never finishes.
			var local: Vector2 = to - centre
			if local.length() > FACE_RADIUS:
				return
			var col: int = clampi(int((local.x + FACE_RADIUS) / (FACE_RADIUS * 2.0 / 3.0)), 0, 2)
			var row: int = clampi(int((local.y + FACE_RADIUS) / (FACE_RADIUS * 2.0 / 3.0)), 0, 2)
			_dry_patches[row * 3 + col] = true
			_progress = clampf(float(_dry_patches.size()) / float(DRY_PATCHES), 0.0, 1.0)

	if _bar != null:
		_bar.value = _progress
	care_progress.emit(_progress)
	_redraw()
	if _progress >= 1.0:
		_finish()


func _move_tool(to: Vector2) -> void:
	if not _dragging:
		if _tool != null:
			_tool.position = to
			_redraw()
		return
	apply_stroke(to)


func _add_foam(at: Vector2) -> void:
	_foam.append({"pos": at - size * 0.5, "r": randf_range(9.0, 19.0)})


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_progress = 1.0
	_child_line.text = String((COPY[_kind] as Dictionary)["doneLine"])
	care_completed.emit(_kind)


## Completes the act without the gesture. The touch fallback that `CLAUDE.md`
## requires: a child who cannot manage the drag must never be stuck.
func complete_by_touch() -> void:
	build()
	_progress = 1.0
	if _bar != null:
		_bar.value = 1.0
	_redraw()
	_finish()


func _redraw() -> void:
	if _face != null:
		_face.queue_redraw()
	if _tool != null:
		_tool.queue_redraw()


## -- Drawing --------------------------------------------------------------------

## An illustrated face, in the locked palette. Honest about being a drawing: see
## the class doc on why this is not the 3D model.
func _draw_face(_unused: Variant = null) -> void:
	var c: Control = _face
	var o := Vector2.ZERO
	c.draw_circle(o, FACE_RADIUS, Color(1.0, 0.886, 0.839))
	# cheeks
	c.draw_circle(o + Vector2(-112.0, 40.0), 34.0, Color(1.0, 0.776, 0.776, 0.75))
	c.draw_circle(o + Vector2(112.0, 40.0), 34.0, Color(1.0, 0.776, 0.776, 0.75))
	# eyes: closed and happy once finished, open while working
	for side: int in [-1, 1]:
		var eye: Vector2 = o + Vector2(float(side) * 66.0, -34.0)
		if _finished:
			c.draw_arc(eye + Vector2(0, 6), 22.0, PI, TAU, 14, Palette.INK, 7.0)
		else:
			c.draw_circle(eye, 25.0, Palette.CREAM)
			c.draw_circle(eye, 16.0, Palette.INK)
			c.draw_circle(eye + Vector2(6, -6), 6.0, Palette.CREAM)
	# nose
	c.draw_circle(o + Vector2(0.0, 40.0), 13.0, Color(1.0, 0.776, 0.776))

	var mouth: Vector2 = o + MOUTH_OFFSET
	if _kind == BRUSH:
		# an open mouth with teeth to brush
		c.draw_circle(mouth, MOUTH_RADIUS * 0.62, Color(0.85, 0.44, 0.44))
		c.draw_rect(Rect2(mouth + Vector2(-46.0, -26.0), Vector2(92.0, 30.0)), Palette.CREAM, true)
	else:
		c.draw_arc(mouth, 44.0, 0.15 * PI, 0.85 * PI, 18, Palette.INK, 8.0)

	# WASH: a wet sheen that clears as progress rises
	if _kind == WASH:
		c.draw_circle(o, FACE_RADIUS, Color(0.604, 0.753, 0.851, 0.30 * (1.0 - _progress)))
	# DRY: the 3x3 patches, each fading as it is reached
	if _kind == DRY:
		var step: float = FACE_RADIUS * 2.0 / 3.0
		for row: int in range(3):
			for col: int in range(3):
				if _dry_patches.has(row * 3 + col):
					continue
				var at := Vector2(-FACE_RADIUS + step * (float(col) + 0.5),
						-FACE_RADIUS + step * (float(row) + 0.5))
				if at.length() > FACE_RADIUS:
					continue
				c.draw_circle(at, step * 0.44, Color(0.604, 0.753, 0.851, 0.38))
	# BRUSH / WASH: foam
	for blob: Dictionary in _foam:
		c.draw_circle(blob["pos"], float(blob["r"]), Color(1.0, 1.0, 1.0, 0.85))


## The tool in the player's hand, drawn as itself so the three acts never look
## the same. Position is the raw pointer; the shape says what it is.
func _draw_tool(_unused: Variant = null) -> void:
	var c: Control = _tool
	var o := Vector2.ZERO
	match _kind:
		BRUSH:
			c.draw_rect(Rect2(o + Vector2(-9.0, -TOOL_SIZE * 0.5),
					Vector2(18.0, TOOL_SIZE * 0.72)), Palette.DUSTY_BLUE, true)
			c.draw_rect(Rect2(o + Vector2(-20.0, TOOL_SIZE * 0.22),
					Vector2(40.0, 18.0)), Palette.CREAM, true)
		WASH:
			c.draw_circle(o, 34.0, Palette.MINT)
			c.draw_circle(o, 22.0, Color(1.0, 1.0, 1.0, 0.7))
		DRY:
			c.draw_rect(Rect2(o + Vector2(-38.0, -30.0), Vector2(76.0, 60.0)),
					Palette.SOFT_PINK, true)
			c.draw_rect(Rect2(o + Vector2(-38.0, -8.0), Vector2(76.0, 8.0)),
					Palette.CREAM, true)
