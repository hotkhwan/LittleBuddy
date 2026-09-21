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
## ## Except `FEED`, which is the real Bunny
##
## The bottle is the one act whose subject can be shown as himself: the rigged
## runtime has a `drink` clip (two hands, head tipped back) and a `mouth` socket
## on the head bone, so there is a real face to aim at and a real reaction to
## see. Drawing a disc over him there did active harm -- the character on the
## rug and the character being fed did not look like the same child. So `FEED`
## draws NO face. The director frames a portrait of Bunny (`focus_portrait()`),
## hands this overlay a way to ask where his mouth is in the world, and the hold
## target follows that point on screen every frame -- through the drink clip's
## head-tip, through camera easing, at any viewport. The scrim becomes two
## bands, top and bottom, so the text stays readable and Bunny stays lit.
##
## `MOUTH_OFFSET` remains the fallback for a build with no camera or no socket
## (a headless test, an unrigged pose), so the gesture can never become
## impossible.
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
const Localization := preload("res://scripts/localization/localization.gd")
const HelperFont := preload("res://scripts/localization/helper_font.gd")

signal care_completed(care_kind: String)
signal care_progress(value: float)

const BRUSH: String = "brushTeeth"
const WASH: String = "washFace"
const DRY: String = "dryFace"
## Mission 01's two acts. `MIX` happens at the kitchen counter and is the only
## act whose subject is an OBJECT rather than Bunny's face; `FEED` is the
## close-up the whole mission has been walking towards.
const MIX: String = "prepareMilk"
const FEED: String = "giveBottle"
## Prepared for Free Play's feeding close-up (2026-09-21): mashing soft food in
## a bowl with a spoon. In COPY and drawable so a later pass in the free-play
## director can `begin(MASH)` it beside `FEED` and `DRY`; nothing opens it yet.
## The gesture is `WASH`'s -- rub anywhere over the bowl until enough ground is
## covered -- because mashing rewards working the whole bowl, not one spot.
const MASH: String = "mashFood"

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
	MIX: {
		"title": "Let's make some milk!", "word": "milk", "thai": "ผสมนม",
		"hint": "Hold the jug over the bottle, then shake it.",
		"childLine": "I'm hungry, Aliz!", "doneLine": "The milk is ready!",
	},
	FEED: {
		"title": "Time to drink!", "word": "drink", "thai": "ดื่มนม",
		"hint": "Hold the bottle at Bunny's mouth.",
		"childLine": "Milk, please, Aliz!", "doneLine": "Thank you, Aliz!",
	},
	MASH: {
		"title": "Mash the food!", "word": "mash", "thai": "บดอาหาร",
		"hint": "Rub the spoon all around the bowl.",
		"childLine": "Yum, food!", "doneLine": "All mashed!",
	},
}

## How much work each act is. Tuned so every one takes roughly the same few
## seconds of happy scrubbing -- long enough to feel done, short enough that a
## three-year-old does not lose interest.
const BRUSH_STROKES_NEEDED: int = 10
const WASH_DISTANCE_NEEDED: float = 2600.0
const DRY_PATCHES: int = 9
## `MIX` is two halves: pour, then shake. The pour is a HOLD, so it is measured
## in seconds rather than in pixels -- the first gesture in this overlay that
## rewards keeping still, which is why `_process` exists below.
const POUR_SECONDS: float = 1.5
const MIX_SHAKES_NEEDED: int = 8
## `FEED` is a pure hold at the mouth, and it LEAKS: let go or wander off the
## mouth and the bottle drains back. A toddler who parks a finger anywhere on
## screen does not feed Bunny.
const FEED_SECONDS: float = 2.2
const FEED_DECAY: float = 0.7

## Acts whose progress advances with TIME rather than with movement.
const HOLD_KINDS: Array[String] = [MIX, FEED]

const FACE_RADIUS: float = 190.0
const MOUTH_OFFSET := Vector2(0.0, 92.0)
const MOUTH_RADIUS: float = 96.0
const TOOL_SIZE: float = 96.0
## `MIX` has no face on screen: the bottle stands where the face would be, and
## this is the opening of its neck, relative to the same centre.
const BOTTLE_NECK := Vector2(0.0, -120.0)
const BOTTLE_SIZE := Vector2(132.0, 210.0)
## FEED: the two scrim bands. Tall enough for the title and hint at the top and
## for the child line, the bar and the `Next` button at the bottom; the space
## between them is Bunny's.
const BAND_TOP_HEIGHT: float = 176.0
const BAND_BOTTOM_HEIGHT: float = 196.0

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
## MIX: seconds poured so far, and shakes counted after the pour finished.
var _poured: float = 0.0
var _shakes: int = 0
## FEED: seconds the bottle has been held at the mouth.
var _fed: float = 0.0

var _face: Control = null
var _tool: Control = null
var _scrim: ColorRect = null
var _band_top: ColorRect = null
var _band_bottom: ColorRect = null
## FEED: answers with the world-space `Vector3` of Bunny's mouth, or null.
var _mouth_provider: Callable = Callable()
## FEED: the last on-screen mouth target, so drawing and the hold test agree
## within a frame.
var _mouth_screen: Vector2 = Vector2.ZERO
var _bar: ProgressBar = null
var _title: Label = null
## The helper line under the title: the family's language (Thai by default,
## from the act's own `thai` copy), through `Localization`. Never English.
var _helper: Label = null
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

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.42)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)

	# FEED only: the world stays visible in the middle, and the two strips of
	# copy get their own darkening so cream text is never laid on a cream wall.
	_band_top = ColorRect.new()
	_band_top.name = "BandTop"
	_band_top.color = _scrim.color
	_band_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_band_top.offset_bottom = BAND_TOP_HEIGHT
	_band_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band_top.visible = false
	add_child(_band_top)
	_band_bottom = ColorRect.new()
	_band_bottom.name = "BandBottom"
	_band_bottom.color = _scrim.color
	_band_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_band_bottom.offset_top = -BAND_BOTTOM_HEIGHT
	_band_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band_bottom.visible = false
	add_child(_band_bottom)

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
	_title.offset_left = -440.0
	_title.offset_right = 440.0
	_title.offset_top = 48.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)

	_helper = Label.new()
	_helper.name = "Helper"
	_helper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_helper.add_theme_font_size_override("font_size", 28)
	_helper.add_theme_color_override("font_color", Palette.SOFT_PINK)
	_helper.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_helper.offset_left = -440.0
	_helper.offset_right = 440.0
	_helper.offset_top = 112.0
	_helper.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_helper.visible = false
	HelperFont.apply(_helper)
	add_child(_helper)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", 30)
	_hint.add_theme_color_override("font_color", Palette.CREAM)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_left = -360.0
	_hint.offset_right = 360.0
	_hint.offset_top = 152.0
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
	_poured = 0.0
	_shakes = 0
	_fed = 0.0
	set_process(HOLD_KINDS.has(_kind))
	var copy: Dictionary = COPY[_kind]
	_title.text = String(copy["title"])
	_refresh_helper()
	_hint.text = String(copy["hint"])
	_child_line.text = String(copy["childLine"])
	_bar.value = 0.0
	_mouth_screen = Vector2.ZERO
	var portrait: bool = _kind == FEED
	if _scrim != null:
		_scrim.visible = not portrait
	if _band_top != null:
		_band_top.visible = portrait
	if _band_bottom != null:
		_band_bottom.visible = portrait
	visible = true
	_redraw()


## FEED: how the overlay finds Bunny's mouth. `provider` returns a world-space
## `Vector3` (or null when it cannot answer). Set by the director for the
## duration of the bottle and cleared afterwards; the overlay never holds a
## reference to the character itself.
func set_mouth_provider(provider: Callable) -> void:
	_mouth_provider = provider


func clear_mouth_provider() -> void:
	_mouth_provider = Callable()


## Where the bottle has to be held, in this overlay's own coordinates.
##
## For `FEED` with a live provider and a camera, that is Bunny's real mouth
## projected to the screen -- so it is wherever his head actually is this frame.
## Everything else, and every fallback, is the drawn face's mouth. Public so the
## smoke test aims at the same point the child does.
func get_mouth_target() -> Vector2:
	var centre: Vector2 = size * 0.5
	if _kind != FEED:
		return centre + MOUTH_OFFSET
	var projected: Variant = _project_mouth()
	if projected is Vector2:
		_mouth_screen = projected
		return projected
	return centre + MOUTH_OFFSET


func _project_mouth() -> Variant:
	if not _mouth_provider.is_valid():
		return null
	var world: Variant = _mouth_provider.call()
	if not (world is Vector3):
		return null
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null or camera.is_position_behind(world):
		return null
	var on_screen: Vector2 = camera.unproject_position(world)
	if not (is_finite(on_screen.x) and is_finite(on_screen.y)):
		return null
	# Viewport pixels -> this control's local frame. The overlay is a full-rect
	# child of a CanvasLayer, so this is normally the identity, but it is not
	# assumed to be.
	return get_global_transform_with_canvas().affine_inverse() * on_screen


func get_care_kind() -> String:
	return _kind


func get_progress() -> float:
	return _progress


func is_finished() -> bool:
	return _finished


## The helper line for the current act, in the chosen language. Thai uses the
## act's own `thai` copy; other languages use the Localization table keyed by
## the English title; Arabic is laid out right-to-left; Off hides it.
func _refresh_helper() -> void:
	if _helper == null:
		return
	var save: Node = null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		save = tree.root.get_node_or_null(NodePath("SaveService"))
	if save != null:
		Localization.sync_from_settings(save)
	var text: String = Localization.helper_line(_title.text, thai_for(_kind))
	_helper.text = text
	_helper.visible = not text.is_empty()
	_helper.text_direction = Control.TEXT_DIRECTION_RTL if Localization.is_rtl() \
			else Control.TEXT_DIRECTION_AUTO


## Re-derives the helper line after a language change. The HUD calls its own
## `refresh_helper_language()` when Parent Corner closes; a host may call this.
func refresh_helper_language() -> void:
	_refresh_helper()


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
		WASH, MASH:
			# Rewards covering ground anywhere on the face (or, for MASH, the bowl).
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
		MIX:
			# The SECOND half only. Pouring is a hold and is counted in `_process`;
			# once the jug is empty the same finger shakes the bottle, and only a
			# reversal counts -- a shake is back AND forth.
			if _poured < POUR_SECONDS:
				return
			var shake_dir: float = signf(delta.x)
			if shake_dir != 0.0 and shake_dir != _last_dir:
				if _last_dir != 0.0:
					_shakes += 1
				_last_dir = shake_dir
			_progress = _mix_progress()
		FEED:
			# Movement does not feed Bunny; `_process` does. Moving is only how the
			# bottle gets to the mouth in the first place.
			_progress = clampf(_fed / FEED_SECONDS, 0.0, 1.0)

	if _bar != null:
		_bar.value = _progress
	care_progress.emit(_progress)
	_redraw()
	if _progress >= 1.0:
		_finish()


## The hold half of `MIX` and all of `FEED`.
##
## Separate from `apply_stroke` and taking its own delta, so a test can advance a
## hold deterministically instead of waiting on real seconds -- the same reason
## `apply_stroke` is public.
func apply_hold(delta: float, at: Vector2) -> void:
	if _finished or delta <= 0.0:
		return
	var centre: Vector2 = size * 0.5
	match _kind:
		MIX:
			if _poured >= POUR_SECONDS:
				return
			# Only over the bottle's neck, so the jug has to be aimed.
			if at.distance_to(centre + BOTTLE_NECK) > MOUTH_RADIUS:
				return
			_poured = minf(_poured + delta, POUR_SECONDS)
			_progress = _mix_progress()
			if _foam.size() < 20:
				_add_foam(centre + BOTTLE_NECK + Vector2(randf_range(-22.0, 22.0), 0.0))
		FEED:
			if at.distance_to(get_mouth_target()) <= MOUTH_RADIUS:
				_fed = minf(_fed + delta, FEED_SECONDS)
			else:
				# Leaks back. Holding the bottle in the wrong place is not feeding.
				_fed = maxf(_fed - delta * FEED_DECAY, 0.0)
			_progress = clampf(_fed / FEED_SECONDS, 0.0, 1.0)
		_:
			return
	if _bar != null:
		_bar.value = _progress
	care_progress.emit(_progress)
	_redraw()
	if _progress >= 1.0:
		_finish()


func _process(delta: float) -> void:
	if _kind == FEED and not _finished:
		# The ring sits on a head that is animating and a camera that is easing;
		# it has to be re-placed whether or not a finger is down.
		_redraw()
	if _finished or not _dragging:
		return
	apply_hold(delta, _last_pos)


## Pour first, then shake: half the bar each, so the child can see that the act
## has two parts and which one they are on.
func _mix_progress() -> float:
	var pour: float = clampf(_poured / POUR_SECONDS, 0.0, 1.0)
	var shake: float = clampf(float(_shakes) / float(MIX_SHAKES_NEEDED), 0.0, 1.0)
	return clampf(pour * 0.5 + shake * 0.5, 0.0, 1.0)


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
	set_process(false)
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
	if _kind == MIX:
		_draw_bottle(c, o)
		return
	if _kind == FEED:
		_draw_feed_target(c)
		return
	if _kind == MASH:
		_draw_bowl(c, o)
		return
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


## FEED: no face -- Bunny is the face. Only the guidance a child gets, drawn
## around his REAL mouth: a soft ring that shows where the bottle has to be held
## (the only cue there is, since there is no fail), which brightens while the
## bottle is there and shrinks away as he drinks; then a few drops of milk while
## it flows, and hearts once he is full.
func _draw_feed_target(c: Control) -> void:
	var mouth: Vector2 = get_mouth_target() - _face.position
	if _finished:
		for i: int in range(3):
			var at: Vector2 = mouth + Vector2(-54.0 + 54.0 * float(i), -70.0 - 18.0 * float(i % 2))
			_draw_heart(c, at, 13.0)
		return
	var holding: bool = _dragging and _last_pos.distance_to(mouth + _face.position) <= MOUTH_RADIUS
	var ring_alpha: float = (0.85 if holding else 0.55) * (1.0 - 0.45 * _progress)
	var ring_radius: float = MOUTH_RADIUS * (1.0 - 0.25 * _progress)
	# a soft halo first, so the ring reads over a pale face as well as a dark wall
	c.draw_circle(mouth, ring_radius + 10.0, Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.10))
	c.draw_arc(mouth, ring_radius, 0.0, TAU, 48,
			Color(Palette.CREAM.r, Palette.CREAM.g, Palette.CREAM.b, ring_alpha), 6.0)
	# the filled part of the ring is the progress, so the child sees the drink
	# happening on Bunny rather than only on the bar at the bottom
	if _progress > 0.0:
		c.draw_arc(mouth, ring_radius, -PI * 0.5, -PI * 0.5 + TAU * _progress, 48,
				Palette.MINT, 8.0)
	if holding and _fed > 0.0:
		var t: float = float(Time.get_ticks_msec() % 900) / 900.0
		for i: int in range(3):
			var phase: float = fmod(t + float(i) / 3.0, 1.0)
			var at: Vector2 = mouth + Vector2(-16.0 + 16.0 * float(i), 18.0 + 34.0 * phase)
			c.draw_circle(at, 5.0 * (1.0 - phase) + 2.0, Color(1.0, 0.988, 0.949, 0.9 * (1.0 - phase)))


func _draw_heart(c: Control, at: Vector2, r: float) -> void:
	c.draw_circle(at + Vector2(-r * 0.55, -r * 0.35), r * 0.62, Palette.SOFT_PINK)
	c.draw_circle(at + Vector2(r * 0.55, -r * 0.35), r * 0.62, Palette.SOFT_PINK)
	c.draw_colored_polygon(PackedVector2Array([
		at + Vector2(-r * 1.12, -r * 0.2), at + Vector2(r * 1.12, -r * 0.2), at + Vector2(0.0, r * 1.05),
	]), Palette.SOFT_PINK)


## MASH: a bowl of soft food standing in for the face. The lumps smooth out as
## progress rises -- the same "the picture answers the gesture" rule as WASH's
## sheen and DRY's patches. Foam blobs double as spoon marks.
func _draw_bowl(c: Control, o: Vector2) -> void:
	var rim: float = FACE_RADIUS * 0.95
	c.draw_circle(o + Vector2(0.0, 30.0), rim, Palette.PEACH)
	c.draw_circle(o + Vector2(0.0, 30.0), rim * 0.82, Color(1.0, 0.882, 0.600))
	var lumps: int = int(round(7.0 * (1.0 - _progress)))
	for i: int in range(lumps):
		var a: float = TAU * float(i) / 7.0
		var at: Vector2 = o + Vector2(0.0, 30.0) + Vector2.from_angle(a) * rim * 0.45
		c.draw_circle(at, 16.0, Palette.STAR_EARNED)
	for blob: Dictionary in _foam:
		c.draw_circle(blob["pos"], float(blob["r"]), Color(1.0, 1.0, 1.0, 0.55))
	c.draw_arc(o + Vector2(0.0, 30.0), rim, 0.0, TAU, 48, Palette.INK, 5.0)


## The bottle being filled, standing in for the face during `MIX`. The milk level
## rises with the POUR half only -- so a child can see that shaking a half-empty
## bottle is not what the first half of the bar was asking for.
func _draw_bottle(c: Control, o: Vector2) -> void:
	var pour: float = clampf(_poured / POUR_SECONDS, 0.0, 1.0)
	var body := Rect2(o + Vector2(-BOTTLE_SIZE.x * 0.5, -BOTTLE_SIZE.y * 0.5), BOTTLE_SIZE)
	# glass
	c.draw_rect(body, Color(Palette.CREAM.r, Palette.CREAM.g, Palette.CREAM.b, 0.55), true)
	# milk, filling from the bottom
	var milk_h: float = BOTTLE_SIZE.y * 0.86 * pour
	if milk_h > 1.0:
		c.draw_rect(Rect2(body.position + Vector2(6.0, body.size.y - 6.0 - milk_h),
				Vector2(body.size.x - 12.0, milk_h)), Color(1.0, 0.988, 0.949), true)
	c.draw_rect(body, Palette.DUSTY_BLUE, false, 5.0)
	# neck and teat, at BOTTLE_NECK, which is what the pour has to be aimed at
	var neck: Vector2 = o + BOTTLE_NECK
	c.draw_rect(Rect2(neck + Vector2(-30.0, 0.0), Vector2(60.0, 40.0)), Palette.SOFT_PINK, true)
	c.draw_circle(neck + Vector2(0.0, -12.0), 24.0, Palette.SOFT_PINK)
	if pour < 1.0:
		c.draw_arc(neck, MOUTH_RADIUS, 0.0, TAU, 40,
				Color(Palette.CREAM.r, Palette.CREAM.g, Palette.CREAM.b, 0.45), 5.0)
	# the shake half, shown as the bottle rocking rather than as a number
	if pour >= 1.0 and _shakes > 0 and not _finished:
		var lean: float = float(_shakes % 2) * 2.0 - 1.0
		c.draw_line(o + Vector2(lean * 46.0, -BOTTLE_SIZE.y * 0.62),
				o + Vector2(-lean * 46.0, -BOTTLE_SIZE.y * 0.62),
				Color(1.0, 1.0, 1.0, 0.7), 6.0)
	for blob: Dictionary in _foam:
		c.draw_circle(blob["pos"], float(blob["r"]) * 0.7, Color(1.0, 1.0, 1.0, 0.7))


## The tool in the player's hand, drawn as itself so the acts never look
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
		MIX:
			# A little jug, tipped, with a spout that points where the milk lands.
			c.draw_rect(Rect2(o + Vector2(-34.0, -30.0), Vector2(60.0, 56.0)),
					Palette.DUSTY_BLUE, true)
			c.draw_line(o + Vector2(26.0, -18.0), o + Vector2(52.0, 4.0),
					Palette.DUSTY_BLUE, 12.0)
			if _poured < POUR_SECONDS and _dragging:
				c.draw_line(o + Vector2(52.0, 6.0), o + Vector2(52.0, 46.0),
						Color(1.0, 0.988, 0.949), 9.0)
		MASH:
			# A spoon: a long handle and a round bowl at the working end.
			c.draw_line(o + Vector2(0.0, -TOOL_SIZE * 0.5), o + Vector2(0.0, TOOL_SIZE * 0.1),
					Palette.DUSTY_BLUE, 12.0)
			c.draw_circle(o + Vector2(0.0, TOOL_SIZE * 0.26), 22.0, Palette.DUSTY_BLUE)
			c.draw_circle(o + Vector2(0.0, TOOL_SIZE * 0.26), 14.0, Palette.CREAM)
		FEED:
			# The bottle itself, held teat-down, so it is obvious which end goes in.
			c.draw_rect(Rect2(o + Vector2(-26.0, -46.0), Vector2(52.0, 74.0)),
					Color(1.0, 0.988, 0.949), true)
			c.draw_rect(Rect2(o + Vector2(-26.0, -46.0), Vector2(52.0, 74.0)),
					Palette.DUSTY_BLUE, false, 4.0)
			c.draw_circle(o + Vector2(0.0, 40.0), 18.0, Palette.SOFT_PINK)
