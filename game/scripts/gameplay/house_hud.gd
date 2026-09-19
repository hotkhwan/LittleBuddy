extends Control

## The child-facing chrome for a Chapter 3 level: what to do, how far through we
## are, how many stars there are, and the way out.
##
## Built in code rather than as a `.tscn` so it can be added to whatever
## `CanvasLayer` the world already has without either agent owning a scene file
## the other might be editing. It is deliberately small: a pre-reader gets a
## short spoken prompt and four touchable things, not a dashboard.
##
## ## Rules from CLAUDE.md that this file is where they become visible
##
##   * No red anywhere, no `#000000`, no score, no percentage, no timer.
##   * The un-earned progress dot is a warm ghost (`#E8DCC8`), never grey and
##     never an empty slot.
##   * **Next is always there while a task is running.** It is the escape hatch:
##     it completes nothing, costs nothing, blames nobody, and simply moves on.
##   * Speak is HIDDEN, not greyed, when there is nothing to speak to. A child
##     poking a dead button learns the wrong lesson.
##
## ## The presentation mode
##
## This chrome does not sit in one place any more. The text stack used to be four
## lines down the middle of the top third whatever the camera was doing, which
## during a close-up put it squarely on the character's face -- the P0 defect
## recorded in `docs/WORLD_CAMERA_PASS.md` §7.1, and one that provably cannot be
## fixed from the camera.
##
## So the HUD watches the shot and lays itself out around it. The rule, the four
## modes and the measurements behind them are in `scripts/ui/hud_presentation.gd`;
## this file only applies them. The one thing worth repeating here is where the
## information comes from: **the camera**, via `RoomCamera.get_focus_radius()`.
## Nothing new is asked of the director, no new signal is invented, and a HUD
## dropped into a scene with no `RoomCamera` at all simply stays in EXPLORE.

## The locked palette (SLICE_CONTRACT §7 / ART_BIBLE).
const SpeechFeedbackScript := preload("res://scripts/ui/speech_feedback.gd")
const Presentation := preload("res://scripts/ui/hud_presentation.gd")

const CREAM: Color = Color("#FFF6E5")
const DUSTY_BLUE: Color = Color("#9AC0D9")
const SOFT_PINK: Color = Color("#FFC1CC")
const MINT: Color = Color("#A8E6CF")
const LAVENDER: Color = Color("#D6C7F0")
const INK: Color = Color("#59422B")
const STAR_GOLD: Color = Color("#FFC73D")
const STAR_GHOST: Color = Color("#E8DCC8")

const PROMPT_FONT_SIZE: int = 42
const HINT_FONT_SIZE: int = 27
const CAPTION_FONT_SIZE: int = 24
const BUTTON_FONT_SIZE: int = 30
const STAR_FONT_SIZE: int = 34

## Free Play's word card. Much bigger than a prompt, because in Free Play the
## word IS the content: a child taps the fridge and this is the reward, together
## with the voice saying it.
const WORD_FONT_SIZE: int = 84
const WORD_THAI_FONT_SIZE: int = 40

## How long a tapped word stays on screen. Long enough to connect the word to the
## thing that was touched, short enough that the room is not permanently covered.
const WORD_SECONDS: float = 3.2

const DOT_SIZE: float = 26.0
const DOT_GAP: float = 12.0

## -- Where the two child-facing buttons live --------------------------------
##
## Named rather than typed inline, because a second input layer now has to stay
## out of their way: the virtual thumbstick (`scripts/input/virtual_joystick.gd`)
## owns the bottom-left of the screen, and a stick that overlapped Next or Speak
## would swallow a press a child meant for a button. `test_joystick.gd` computes
## both rects from these numbers and asserts the stick clears them at every
## aspect ratio the game ships at, so the layout cannot drift into a collision
## without something going red.

## Both buttons sit on the same line, measured up from the bottom edge.
const BUTTON_TOP: float = -126.0
const BUTTON_BOTTOM: float = -34.0
## Next is anchored bottom-RIGHT; these are offsets from the right edge.
const NEXT_LEFT: float = -260.0
const NEXT_RIGHT: float = -36.0
## Speak is anchored centre-bottom and is this wide either side of the middle.
const SPEAK_HALF_WIDTH: float = 112.0

const ENCOURAGEMENT_SEC: float = 1.8

## How long the reward presentation holds after a task is marked done.
##
## Matched to `ENCOURAGEMENT_SEC` on purpose: the praise line IS the reward
## presentation, so the mode and the line it exists to show end together. It is
## also cancelled early by the next prompt arriving (`set_prompt()`), which is
## what keeps a completed task from ever hiding the next instruction -- the
## no-dead-ends rule in `CLAUDE.md` applied to a transient layout.
const REWARD_SECONDS: float = ENCOURAGEMENT_SEC

signal skip_pressed()
signal speak_pressed()


## Where Next and Speak land in a viewport of `viewport_size`, as
## `{"next": Rect2, "speak": Rect2}`.
##
## Static and pure: it is the same arithmetic `build()` hands to the anchor
## presets, expressed so another layer can ask the question without a viewport,
## a tree or a rendered frame. The thumbstick's layout test is the only caller
## today, and it is the reason this exists.
static func button_rects(viewport_size: Vector2) -> Dictionary:
	var top: float = viewport_size.y + BUTTON_TOP
	var height: float = BUTTON_BOTTOM - BUTTON_TOP
	return {
		"next": Rect2(
			viewport_size.x + NEXT_LEFT, top, NEXT_RIGHT - NEXT_LEFT, height
		),
		"speak": Rect2(
			viewport_size.x * 0.5 - SPEAK_HALF_WIDTH, top, SPEAK_HALF_WIDTH * 2.0, height
		),
	}

var _prompt: Label = null
var _hint: Label = null
var _caption: Label = null
var _stars: Label = null
var _encouragement: Label = null
var _dots: HBoxContainer = null
var _next_button: Button = null
var _speak_button: Button = null
var _speech_feedback: Control = null
var _word: Label = null
var _word_thai: Label = null

var _total: int = 0
var _current: int = 0
var _done: Dictionary = {}
var _built: bool = false
var _free_play: bool = false
var _word_generation: int = 0

## -- Presentation state --------------------------------------------------------
var _mode: int = Presentation.MODE_EXPLORE
## -1 for "derive it". Set by a test or the shot harness to photograph a mode
## without having to drive the game into it.
var _mode_override: int = -1
## Optional and empty today. `hud_presentation.kind_mode()` explains why.
var _task_kind: String = ""
## What `set_play_chrome_visible()` last said. Tracked rather than read back off
## the labels, because the mode now changes their visibility too and the two
## reasons for a hidden label must not be confused.
var _chrome_on: bool = true
var _encouragement_on: bool = false
var _reward_until_msec: int = -1
## The last radius the camera reported, kept only so a test can see what the HUD
## saw without a viewport of its own.
var _seen_focus_radius: float = 0.0


func _ready() -> void:
	build()


## Idempotent, and called from every public method: `_ready()` does not fire for
## a node added to the root in the headless runner.
func build() -> void:
	if _built:
		return
	_built = true
	name = "HouseHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# `_process()` is where the camera is watched. Set explicitly for the same
	# reason `room_camera.gd` does it: a node that has its script attached after
	# it is already in the tree never gets the chance to opt in from `_ready()`.
	set_process(true)

	_caption = _add_label("Caption", CAPTION_FONT_SIZE, LAVENDER)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_caption.offset_left = -400.0
	_caption.offset_top = 30.0
	_caption.offset_right = -36.0
	_caption.offset_bottom = 120.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_caption.visible = false

	_prompt = _add_label("Prompt", PROMPT_FONT_SIZE, CREAM)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_prompt.offset_left = 150.0
	_prompt.offset_top = 132.0
	_prompt.offset_right = -150.0
	_prompt.offset_bottom = 232.0
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_hint = _add_label("ThaiHint", HINT_FONT_SIZE, SOFT_PINK)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.visible = false

	# The assist / praise line. It used to be a FOURTH line in the same top
	# column as the prompt and the hint, which is how the stack reached 35% of an
	# iPad's height. It now lives in a band above the buttons in every mode: it
	# is the one line that is always short, always transient and never the thing
	# the child is being asked to look at.
	_encouragement = _add_label("Encouragement", PROMPT_FONT_SIZE, MINT)
	_encouragement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_encouragement.visible = false

	_stars = _add_label("StarCount", STAR_FONT_SIZE, STAR_GOLD)
	_stars.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_stars.offset_left = 36.0
	_stars.offset_top = 26.0
	_stars.offset_right = 260.0
	# 86 rather than 84: COMPLETE grows this label to 42 pt, and a box the text
	# overflows would clip the thing the reward presentation is ABOUT.
	_stars.offset_bottom = 86.0
	_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_stars.text = "★ 0"

	_dots = HBoxContainer.new()
	_dots.name = "ProgressDots"
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.add_theme_constant_override("separation", int(DOT_GAP))
	_dots.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_dots.offset_left = 38.0
	_dots.offset_top = 92.0
	_dots.offset_right = 600.0
	_dots.offset_bottom = 92.0 + DOT_SIZE
	add_child(_dots)

	_next_button = _add_button("NextButton", "Next", DUSTY_BLUE)
	_next_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_next_button.offset_left = NEXT_LEFT
	_next_button.offset_top = BUTTON_TOP
	_next_button.offset_right = NEXT_RIGHT
	_next_button.offset_bottom = BUTTON_BOTTOM
	_next_button.pressed.connect(_on_next_pressed)
	_next_button.visible = false

	# ART_BIBLE section 3 assigns mint to the speak button in two places: the
	# palette row ("go, success, freshness -- speak button") and the semantic
	# roles table ("Success / speak: mint"). It shipped soft pink, which is a
	# legal token but the wrong one -- and semantically backwards, since mint is
	# what this game uses to mean "go", which is exactly what inviting a child to
	# speak is. The Baby Room's speak control has always been mint; this makes
	# the two agree.
	_speak_button = _add_button("SpeakButton", "Speak", MINT)
	_speak_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_speak_button.offset_left = -SPEAK_HALF_WIDTH
	_speak_button.offset_top = BUTTON_TOP
	_speak_button.offset_right = SPEAK_HALF_WIDTH
	_speak_button.offset_bottom = BUTTON_BOTTOM
	_speak_button.pressed.connect(_on_speak_pressed)
	_speak_button.visible = false

	# The panel that tells the child what the microphone is doing. Added last so
	# it draws over the buttons, and it ignores the mouse so it can never eat a
	# tap meant for Speak underneath it.
	_speech_feedback = SpeechFeedbackScript.new()
	_speech_feedback.name = "SpeechFeedback"
	add_child(_speech_feedback)
	_speech_feedback.call("build")

	# The Free Play word card. Low and centred, so it sits under the object the
	# child just touched rather than over it, and above where thumbs rest on an
	# iPad held in landscape.
	# INK on a CREAM outline, the opposite way round from every other label here.
	# The rest of the HUD sits over a 3D room of every colour; the word card sits
	# low, over the cream floor almost every time, and cream-on-cream with a thin
	# ink edge was legible but weak when rendered. Ink is the palette's only dark
	# and reads at a glance against the floor, while the cream outline keeps it
	# readable if it ever lands on a wardrobe.
	_word = _add_label("Word", WORD_FONT_SIZE, INK)
	_word.add_theme_color_override("font_outline_color", CREAM)
	_word.add_theme_constant_override("outline_size", 14)
	_word.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_word.offset_left = -480.0
	_word.offset_top = -288.0
	_word.offset_right = 480.0
	_word.offset_bottom = -172.0
	_word.visible = false

	_word_thai = _add_label("WordThai", WORD_THAI_FONT_SIZE, INK)
	_word_thai.add_theme_color_override("font_outline_color", CREAM)
	_word_thai.add_theme_constant_override("outline_size", 10)
	_word_thai.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_word_thai.offset_left = -480.0
	_word_thai.offset_top = -168.0
	_word_thai.offset_right = 480.0
	_word_thai.offset_bottom = -104.0
	_word_thai.visible = false

	_apply_mode(true)


## -- Presentation mode ---------------------------------------------------------
##
## `hud_presentation.gd` holds the rule and the numbers; everything here is the
## plumbing that applies them and the plumbing that decides when.

## Recomputes the mode and re-lays the text out if it changed.
##
## `_process()` does nothing else, so a headless test drives exactly the same
## code a device does -- the convention `room_camera.gd` and
## `house_level_director.gd` both already follow -- and it is cheap enough to run
## every frame: one method call on the camera and an integer comparison.
func refresh_presentation() -> void:
	build()
	_seen_focus_radius = _observed_focus_radius()
	var wanted: int = _mode_override
	if wanted < 0:
		wanted = Presentation.derive({
			"freePlay": _free_play,
			"rewarding": _is_rewarding(),
			"focusRadius": _seen_focus_radius,
			"taskKind": _task_kind,
		})
	if wanted == _mode:
		return
	_mode = wanted
	_apply_mode(false)


func get_presentation_mode() -> int:
	build()
	return _mode


func get_presentation_mode_name() -> String:
	build()
	return Presentation.mode_name(_mode)


## Pins the mode, for a test or for `scenes/spike/shot_harness.gd`. A real run
## never calls this: the whole point is that the HUD works it out.
func set_presentation_mode(mode: int) -> void:
	build()
	_mode_override = mode if mode >= 0 and mode < Presentation.MODE_NAMES.size() else -1
	refresh_presentation()


func clear_presentation_override() -> void:
	build()
	_mode_override = -1
	refresh_presentation()


## An optional, authoritative statement of what kind of beat this is.
##
## Nothing calls it today and the HUD does not need it -- see
## `hud_presentation.kind_mode()`. It is the seam for the one-line change a
## director would make if a future beat's shot ever stopped describing it.
func set_task_kind(kind: String) -> void:
	build()
	_task_kind = kind.strip_edges()
	refresh_presentation()


func get_task_kind() -> String:
	build()
	return _task_kind


## The radius the camera last reported, so a test can prove the HUD is reading
## the real shot rather than a default.
func get_seen_focus_radius() -> float:
	build()
	return _seen_focus_radius


func _process(_delta: float) -> void:
	refresh_presentation()


## The live close-up's half-width, straight from whichever camera is rendering.
##
## Duck-typed on purpose. The HUD must stay renderable with no camera at all --
## `test_freeplay.gd` and half a dozen others build it into a bare tree -- and it
## must not acquire a 3D type to ask a one-number question. No camera, or a
## camera that is not a `RoomCamera`, means no close-up, which means EXPLORE.
func _observed_focus_radius() -> float:
	if not is_inside_tree():
		return 0.0
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return 0.0
	var camera: Object = viewport.get_camera_3d()
	if camera == null or not camera.has_method("get_focus_radius"):
		return 0.0
	return float(camera.call("get_focus_radius"))


func _is_rewarding() -> bool:
	if _reward_until_msec < 0:
		return false
	if Time.get_ticks_msec() >= _reward_until_msec:
		_reward_until_msec = -1
		return false
	return true


## Ends the reward presentation early. Called the moment a DIFFERENT prompt
## arrives: the next instruction always outranks the last one's applause.
func _end_reward() -> void:
	_reward_until_msec = -1


func _apply_mode(initial: bool) -> void:
	var l: Dictionary = Presentation.layout(_mode)

	if String(l["promptAnchor"]) == "topLeft":
		_prompt.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	else:
		_prompt.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_place(_prompt, l["promptRect"])
	_prompt.add_theme_font_size_override("font_size", int(l["promptSize"]))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT \
			if bool(l["promptLeftAligned"]) else HORIZONTAL_ALIGNMENT_CENTER
	_set_inverted(_prompt, bool(l["promptInverted"]), CREAM)
	_set_inverted(_hint, bool(l["promptInverted"]), SOFT_PINK)

	if String(l["promptAnchor"]) == "topLeft":
		_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	else:
		_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_place(_hint, l["hintRect"])
	_hint.add_theme_font_size_override("font_size", int(l["hintSize"]))
	_hint.horizontal_alignment = _prompt.horizontal_alignment

	_encouragement.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_place(_encouragement, l["encouragementRect"])
	_encouragement.add_theme_font_size_override("font_size", int(l["encouragementSize"]))

	_stars.add_theme_font_size_override("font_size", int(l["starSize"]))

	if not initial:
		_refresh_visibility()


## Swaps a label between "pale text, ink edge" and "ink text, cream edge".
##
## Both are palette-legal and both are already used in this file; which one
## reads depends entirely on what is behind the line, and the mode is exactly
## the thing that knows. `#000000` appears in neither: `ink` is the only dark
## this game has (ART_BIBLE §3).
func _set_inverted(label: Label, inverted: bool, normal_color: Color) -> void:
	label.add_theme_color_override("font_color", INK if inverted else normal_color)
	label.add_theme_color_override("font_outline_color", CREAM if inverted else INK)


func _place(control: Control, rect: Variant) -> void:
	var r: Array = rect as Array
	control.offset_left = float(r[0])
	control.offset_top = float(r[1])
	control.offset_right = float(r[2])
	control.offset_bottom = float(r[3])


## The single place any of the chrome labels decides whether it is on screen.
##
## Three independent reasons overlap -- Free Play has no objective, the summary
## turns the whole play chrome off, and the presentation mode stands some lines
## down -- and before this they were applied from three different methods that
## each overwrote the others. `visible` is now derived from all three, every
## time, so the order the calls arrive in cannot change the outcome.
func _refresh_visibility() -> void:
	var l: Dictionary = Presentation.layout(_mode)
	var objective: bool = _chrome_on and not _free_play
	_prompt.visible = objective and bool(l["promptVisible"])
	_hint.visible = objective and bool(l["hintVisible"]) \
			and not _hint.text.strip_edges().is_empty()
	_caption.visible = objective and not _caption.text.strip_edges().is_empty()
	_dots.visible = objective and _total > 0
	_encouragement.visible = _chrome_on and _encouragement_on
	_stars.visible = _chrome_on


## -- Free Play -----------------------------------------------------------------

## Free Play has **no objective**, so it has no progress dots, no Next and no
## Speak: there is nothing to be part-way through, nothing to skip and no
## question to answer. What it keeps is the star total -- stars are the one
## number in this game that only ever goes up -- and it gains the word card.
##
## Written as one call rather than four, so "Free Play looks like this" is a
## single fact that a test can assert and a later edit cannot half-apply.
func set_free_play_mode(enabled: bool) -> void:
	build()
	_free_play = enabled
	if not enabled:
		_refresh_visibility()
		return
	configure_progress(0)
	_next_button.visible = false
	_speak_button.visible = false
	_end_reward()
	_refresh_visibility()


func is_free_play_mode() -> bool:
	build()
	return _free_play


## Shows the English word for the thing the child just touched, and optionally
## the Thai hint underneath it.
##
## The Thai half is **only** passed on a long press (ART_BIBLE section 9): a hint
## that is always on screen is not a hint, it is a translation, and the child
## stops reaching for the English.
func show_word(word: String, thai_hint: String = "") -> void:
	build()
	var text: String = word.strip_edges()
	if text.is_empty():
		hide_word()
		return
	_word.text = text
	_word.visible = true
	_word_thai.text = thai_hint.strip_edges()
	_word_thai.visible = not _word_thai.text.is_empty()

	_word_generation += 1
	var generation: int = _word_generation
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	# Generation-guarded, so a second tap does not get its card taken away early
	# by the first tap's timer. A child taps a lot.
	tree.create_timer(WORD_SECONDS).timeout.connect(
		func() -> void:
			if generation == _word_generation:
				hide_word(),
		CONNECT_ONE_SHOT
	)


func hide_word() -> void:
	build()
	_word.visible = false
	_word_thai.visible = false


func get_word_text() -> String:
	build()
	return _word.text if _word.visible else ""


func get_word_thai_text() -> String:
	build()
	return _word_thai.text if _word_thai.visible else ""


## -- Prompt --------------------------------------------------------------------

func set_prompt(text: String, thai_hint: String = "") -> void:
	build()
	# A new instruction ends the previous task's reward presentation immediately.
	# Without this the applause for task N would hide the prompt for task N+1 for
	# up to `REWARD_SECONDS`, which is a dead end with a timer on it.
	if text != _prompt.text:
		_end_reward()
	_prompt.text = text
	_hint.text = thai_hint
	refresh_presentation()
	_refresh_visibility()


func get_prompt() -> String:
	build()
	return _prompt.text


func set_caption(text: String) -> void:
	build()
	_caption.text = text
	_refresh_visibility()


func show_encouragement(text: String) -> void:
	build()
	if text.strip_edges().is_empty():
		return
	_encouragement.text = text
	_encouragement_on = true
	_refresh_visibility()
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	tree.create_timer(ENCOURAGEMENT_SEC).timeout.connect(hide_encouragement, CONNECT_ONE_SHOT)


func hide_encouragement() -> void:
	build()
	_encouragement_on = false
	_refresh_visibility()


## -- Progress ------------------------------------------------------------------

## One dot per task. A dot is a *place in the story*, never a mark out of ten:
## a skipped task fills its dot exactly like a completed one.
func configure_progress(total: int) -> void:
	build()
	_total = maxi(0, total)
	_current = 0
	_done = {}
	for child: Node in _dots.get_children():
		_dots.remove_child(child)
		child.free()
	for index: int in range(_total):
		var dot: Panel = Panel.new()
		dot.name = "Dot%d" % index
		dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel", _dot_style(STAR_GHOST))
		_dots.add_child(dot)
	_end_reward()
	_refresh_visibility()


func set_current(index: int) -> void:
	build()
	_current = clampi(index, 0, _total)
	_refresh_dots()


## Also opens the reward presentation: this is the only call the HUD receives
## that means "a task just ended", and it arrives for a SKIP as well as for a
## completion. That is deliberate and it is safe -- COMPLETE shows praise and a
## filled dot and never a score, so it cannot congratulate a child for something
## they did not do, and `CLAUDE.md` forbids marking a skip as a failure anyway.
func mark_current_done() -> void:
	build()
	if _current >= 1:
		_done[_current] = true
	_refresh_dots()
	_reward_until_msec = Time.get_ticks_msec() + int(REWARD_SECONDS * 1000.0)
	refresh_presentation()


func clear_progress() -> void:
	configure_progress(0)


func get_total() -> int:
	build()
	return _total


## How many dots are filled. Used by the tests as the child-visible measure of
## "did the level move forward", which is true for a skip as well as a star.
func get_done_count() -> int:
	build()
	return _done.size()


func _refresh_dots() -> void:
	for index: int in range(_dots.get_child_count()):
		var dot: Panel = _dots.get_child(index) as Panel
		if dot == null:
			continue
		var position_number: int = index + 1
		var color: Color = STAR_GHOST
		if _done.has(position_number):
			color = STAR_GOLD
		elif position_number == _current:
			color = MINT
		dot.add_theme_stylebox_override("panel", _dot_style(color))


## -- Stars ---------------------------------------------------------------------

func set_stars(total: int) -> void:
	build()
	_stars.text = "★ %d" % maxi(0, total)


func get_star_text() -> String:
	build()
	return _stars.text


## -- Buttons -------------------------------------------------------------------

func set_skip_visible(value: bool) -> void:
	build()
	_next_button.visible = value


func is_skip_visible() -> bool:
	build()
	return _next_button.visible


func set_speak_visible(value: bool) -> void:
	build()
	_speak_button.visible = value


func is_speak_visible() -> bool:
	build()
	return _speak_button.visible


## Everything off, for an overlay (the summary) or the end of a level.
func set_play_chrome_visible(value: bool) -> void:
	build()
	_chrome_on = value
	if not value:
		_next_button.visible = false
		_speak_button.visible = false
		_encouragement_on = false
		_end_reward()
		hide_word()
	_refresh_visibility()


func _on_next_pressed() -> void:
	skip_pressed.emit()


func _on_speak_pressed() -> void:
	speak_pressed.emit()


## The speech state panel, so the director can bind it to `SpeechService`. The
## HUD owns the node; it deliberately does not own the wiring, because the HUD
## must stay renderable in a test with no autoloads.
func get_speech_feedback() -> Control:
	build()
	return _speech_feedback


## -- Construction helpers ------------------------------------------------------

func _add_label(node_name: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	# An ink outline rather than a shadow: it keeps the text readable over a
	# cream wall and a dusty-blue floor alike, and ink is the palette's darkest
	# colour -- `#000000` is banned everywhere.
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 10)
	add_child(label)
	return label


func _add_button(node_name: String, text: String, tint: Color) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, _button_style(tint, state == "pressed"))
	add_child(button)
	return button


func _button_style(tint: Color, pressed: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = tint.darkened(0.08) if pressed else tint
	style.set_corner_radius_all(28)
	style.set_border_width_all(3)
	style.border_color = CREAM
	return style


func _dot_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(DOT_SIZE * 0.5))
	return style
