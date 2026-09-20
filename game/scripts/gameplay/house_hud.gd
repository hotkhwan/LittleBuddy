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
const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")
const AffordanceLayerScript := preload("res://scripts/interaction/affordance_layer.gd")
const SafeAreaScript := preload("res://scripts/ui/safe_area.gd")
const Localization := preload("res://scripts/localization/localization.gd")
const HouseGlyphScript := preload("res://scenes/main/house_glyph.gd")
const Palette := preload("res://scripts/ui/palette.gd")

## The grown-ups screen the pause card's third button opens, as an overlay on
## top of the running world so Done returns to the room.
const PARENT_SCENE: String = "res://scenes/parent/parent_settings.tscn"

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

## -- Home -----------------------------------------------------------------------------
##
## Home is the way out. It sits top-right, round, peach, with the title
## screen's own house on it, and it is the one control a grown-up can find
## without being told: the owner's first playtest note was that there was no
## obvious way back. 104 px is under the §8 floor for a CHILD'S target on
## purpose -- it is a grown-up's control that a child may also press -- and
## what it opens is a card whose buttons are all full size.
const HOME_SIZE: float = 104.0
const HOME_TOP: float = 26.0
const HOME_RIGHT: float = -36.0
## Space the level caption gives up so it never runs under Home.
const CAPTION_RIGHT: float = HOME_RIGHT - HOME_SIZE - 20.0

## The build number is NOT shown in the room any more (2026-09-20): it lives on
## the title screen only, where the owner reads it from a screenshot without
## it sharing the child's play space. `has_version_label()` stays false.

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
## The pause card's Home was pressed. Emitted whether or not a world answered.
signal home_requested()
signal pause_opened()
signal pause_closed()


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

## Where the Home button lands in a viewport of `viewport_size`.
static func home_button_rect(viewport_size: Vector2) -> Rect2:
	return Rect2(viewport_size.x + HOME_RIGHT - HOME_SIZE, HOME_TOP, HOME_SIZE, HOME_SIZE)


var _prompt: Label = null
var _hint: Label = null
var _prompt_thai_hint: String = ""
var _home_button: Button = null
var _pause_menu: Control = null
var _settings_overlay: Node = null
var _affordance: Control = null
var _affordance_bound: bool = false
## What the world's input looked like before the pause card took it, so
## Continue puts back exactly that and never re-enables a character somebody
## else had disabled.
var _paused_world: bool = false
var _prior_taps_enabled: bool = true
var _prior_character_disabled: bool = false
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
## True while a full-screen close-up is narrating for itself.
var _narration_covered: bool = false
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

	# The proximity affordances draw UNDER every other piece of chrome, so the
	# badge can never cover a prompt or a button. Bound to the world lazily in
	# `refresh_presentation()`, once this HUD is in a tree that has one.
	_affordance = AffordanceLayerScript.new()
	add_child(_affordance)
	move_child(_affordance, 0)
	_affordance.call("build")

	_caption = _add_label("Caption", CAPTION_FONT_SIZE, LAVENDER)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_caption.offset_left = -400.0
	_caption.offset_top = 30.0
	_caption.offset_right = CAPTION_RIGHT
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
	_set_button_icon(_next_button, "res://assets/ui/icons/next.svg", HORIZONTAL_ALIGNMENT_RIGHT)

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
	_set_button_icon(_speak_button, "res://assets/ui/icons/mic.svg", HORIZONTAL_ALIGNMENT_LEFT)

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

	_home_button = _add_button("HomeButton", "", Palette.HOME_CHROME)
	_home_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_home_button.offset_left = HOME_RIGHT - HOME_SIZE
	_home_button.offset_top = HOME_TOP
	_home_button.offset_right = HOME_RIGHT
	_home_button.offset_bottom = HOME_TOP + HOME_SIZE
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var round_style: StyleBoxFlat = _button_style(Palette.HOME_CHROME, state == "pressed")
		round_style.set_corner_radius_all(int(HOME_SIZE * 0.5))
		round_style.set_border_width_all(4)
		_home_button.add_theme_stylebox_override(state, round_style)
	var house: Control = HouseGlyphScript.new()
	house.name = "HouseGlyph"
	house.set("tint", INK)
	house.set("face_color", Palette.HOME_CHROME)
	house.set("window_color", Palette.HOME_CHROME)
	house.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	house.offset_left = 16.0
	house.offset_top = 14.0
	house.offset_right = -16.0
	house.offset_bottom = -18.0
	_home_button.add_child(house)
	_home_button.pressed.connect(open_pause_menu)

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
	_bind_affordance()
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
	_hint.horizontal_alignment = _helper_alignment(_prompt.horizontal_alignment)

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
	# `_narration_covered` is the care close-up: a full-screen overlay that names
	# the act, gives the hint and shows the progress itself. The HUD saying the
	# same two things underneath it is not redundancy, it is a COLLISION -- at a
	# true 2.17 iPhone aspect the overlay title and the HUD instruction land on
	# the same pixels and overprint each other. Only the duplicated narration is
	# suppressed: the stars, the dots and above all the Next button stay, because
	# Next is the child's escape hatch and hiding it would be the dead end this
	# project keeps banning.
	var objective: bool = _chrome_on and not _free_play and not _narration_covered
	_prompt.visible = objective and bool(l["promptVisible"])
	_hint.visible = objective and bool(l["hintVisible"]) \
			and not _hint.text.strip_edges().is_empty()
	_caption.visible = objective and not _caption.text.strip_edges().is_empty()
	_dots.visible = _chrome_on and not _free_play and _total > 0
	_encouragement.visible = _chrome_on and _encouragement_on
	_stars.visible = _chrome_on
	_home_button.visible = _chrome_on
	# Affordances stand down whenever the room is not the thing being played:
	# a summary, a close-up narrating for itself, the pause card. While the
	# prompt band is up they also keep out from under it.
	_affordance.call("set_enabled", _chrome_on and not _narration_covered and not _paused_world)
	var keep_out: float = 0.0
	if _prompt.visible and String(l["promptAnchor"]) == "topWide":
		keep_out = Presentation.top_stack_height(_mode) + 12.0
	_affordance.call("set_top_keep_out", keep_out)
	_push_keep_outs()


## Hides the HUD's own narration while a full-screen close-up is doing the
## talking. Never hides the escape hatch -- see `_refresh_visibility()`.
func set_narration_covered(value: bool) -> void:
	build()
	if _narration_covered == value:
		return
	_narration_covered = value
	_refresh_visibility()


func is_narration_covered() -> bool:
	return _narration_covered


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
	_set_helper_text(_word_thai, text, thai_hint)

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
	_prompt_thai_hint = thai_hint
	_set_helper_text(_hint, text, thai_hint)
	refresh_presentation()
	_refresh_visibility()


## Re-derives the helper lines from the current language without a new prompt.
## The parent settings apply a language change to `Localization` at once; a HUD
## that is on screen at the time calls this (the pause path does, on close) so
## the line under the prompt changes with no restart.
func refresh_helper_language() -> void:
	build()
	_set_helper_text(_hint, _prompt.text, _prompt_thai_hint)
	_refresh_visibility()


## The helper line under an English line: the family's language, from
## `Localization`, honouring the content author's Thai when Thai is chosen and
## laying Arabic out right-to-left. Empty (and hidden) when the helper is off or
## nothing is translated.
func _set_helper_text(label: Label, english: String, thai_hint: String) -> void:
	if label == null:
		return
	# The profile is the source of truth when there is one; without a SaveService
	# (a test, a bare scene) whatever `Localization` was last told stands.
	var service: Node = _save_service()
	if service != null:
		Localization.sync_from_settings(service)
	var text: String = Localization.helper_line(english, thai_hint)
	label.text = text
	label.visible = not text.is_empty()
	var rtl: bool = Localization.is_rtl()
	label.text_direction = Control.TEXT_DIRECTION_RTL if rtl else Control.TEXT_DIRECTION_AUTO
	if not rtl:
		label.language = ""
	else:
		label.language = Localization.helper_language()
	label.horizontal_alignment = _helper_alignment(label.horizontal_alignment)


## Centred lines stay centred in every script; a left-aligned helper line
## flips to the right for a right-to-left language, and back when it changes.
static func _helper_alignment(base: int) -> int:
	if Localization.is_rtl():
		return HORIZONTAL_ALIGNMENT_RIGHT if base == HORIZONTAL_ALIGNMENT_LEFT else base
	return HORIZONTAL_ALIGNMENT_LEFT if base == HORIZONTAL_ALIGNMENT_RIGHT else base


## The current helper language's code, for tests and the runbook.
func get_helper_language() -> String:
	return Localization.helper_language()


## The SaveService autoload, or null. Resolved through the main loop so a HUD
## built outside a running scene (a test) gets null instead of an engine error.
func _save_service() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath("SaveService"))


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
	_push_keep_outs()


func is_skip_visible() -> bool:
	build()
	return _next_button.visible


func set_speak_visible(value: bool) -> void:
	build()
	_speak_button.visible = value
	_push_keep_outs()


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


## Speak: the press goes out, and if it opened a listening session the button
## is held disabled until that session ends -- one session at a time, and a
## child cannot stack presses into a queue of microphones. Re-enabled on
## `SpeechService.session_ended` (every terminal state emits it) and, as a belt
## to that brace, by `SPEAK_LOCK_MAX_SECONDS` regardless.
func _on_speak_pressed() -> void:
	speak_pressed.emit()
	_lock_speak_while_listening()


## Longer than the service's own worst case (6 s after a partial + grace), so
## the service ends the session first in every real path and this only ever
## fires if the service itself is gone.
const SPEAK_LOCK_MAX_SECONDS: float = 9.0

var _speak_lock_generation: int = 0


func _lock_speak_while_listening() -> void:
	var speech: Node = _speech_service()
	if speech == null or not speech.has_method("has_active_session") \
			or not bool(speech.call("has_active_session")):
		return  # nothing opened (unavailable, refused): the button stays live
	_speak_button.disabled = true
	if speech.has_signal("session_ended") \
			and not speech.is_connected("session_ended", _on_speech_session_ended):
		speech.connect("session_ended", _on_speech_session_ended)
	_speak_lock_generation += 1
	var generation: int = _speak_lock_generation
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or not is_inside_tree():
		return
	tree.create_timer(SPEAK_LOCK_MAX_SECONDS).timeout.connect(
		func() -> void:
			if generation == _speak_lock_generation:
				_release_speak(),
		CONNECT_ONE_SHOT
	)


func _on_speech_session_ended(_outcome: String) -> void:
	_release_speak()


func _release_speak() -> void:
	_speak_lock_generation += 1
	if _speak_button != null:
		_speak_button.disabled = false


## True while a listening session holds the Speak button. Tests.
func is_speak_locked() -> bool:
	build()
	return _speak_button.disabled


func _speech_service() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath("SpeechService"))


## The speech state panel, so the director can bind it to `SpeechService`. The
## HUD owns the node; it deliberately does not own the wiring, because the HUD
## must stay renderable in a test with no autoloads.
func get_speech_feedback() -> Control:
	build()
	return _speech_feedback


## -- Home / pause ----------------------------------------------------------------
##
## The HUD owns the button and the card and the input gating around them. What
## "home" actually DOES belongs to the world: `HouseWorld.leave_to_home()` saves
## the location and the profile and swaps to the title screen. It is called
## through `has_method()` so this HUD is renderable in a tree with no world, and
## when no world answers, Home simply closes the card -- never a dead end,
## never a scene swap of its own.

func open_pause_menu() -> void:
	build()
	if not _chrome_on:
		return
	var menu: Control = _ensure_pause_menu()
	if menu == null or bool(menu.call("is_open")):
		return
	_set_world_paused(true)
	# On top of everything in the layer, including the care overlay.
	var host: Node = menu.get_parent()
	if host != null:
		host.move_child(menu, host.get_child_count() - 1)
	menu.call("open")
	pause_opened.emit()


func close_pause_menu() -> void:
	build()
	if _pause_menu == null or not bool(_pause_menu.call("is_open")):
		return
	_pause_menu.call("close")


func is_pause_menu_open() -> bool:
	build()
	return _pause_menu != null and bool(_pause_menu.call("is_open"))


func get_pause_menu() -> Control:
	build()
	return _ensure_pause_menu()


func get_home_button() -> Button:
	build()
	return _home_button


## The room shows no build number; the title screen does. Kept as a method so
## a test can state the rule.
func has_version_label() -> bool:
	build()
	return find_child("Version", true, false) != null


func get_affordance_layer() -> Control:
	build()
	return _affordance


## The world this HUD is mounted in, or null. Duck-typed: the nearest ancestor
## that answers `get_character()`.
func get_world() -> Node:
	var node: Node = get_parent()
	var guard: int = 0
	while node != null and guard < 16:
		guard += 1
		if node.has_method("get_character"):
			return node
		node = node.get_parent()
	return null


## Home, as an API. Flushes the profile, then asks the world to leave.
func request_home() -> void:
	build()
	_flush_save()
	home_requested.emit()
	var world: Node = get_world()
	if world != null and world.has_method("leave_to_home"):
		close_pause_menu()
		world.call("leave_to_home")
		return
	# No world to leave (a preview, a test, a build without the hook): the card
	# closes and play carries on. A press that does nothing visible is the one
	# outcome this HUD must not produce.
	close_pause_menu()


## The grown-ups gate, over the running room. Done brings the room back.
func open_grown_ups() -> void:
	build()
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		return
	if not ResourceLoader.exists(PARENT_SCENE):
		close_pause_menu()
		return
	var packed: Resource = load(PARENT_SCENE)
	if not (packed is PackedScene):
		close_pause_menu()
		return
	var overlay: Node = (packed as PackedScene).instantiate()
	if overlay == null:
		close_pause_menu()
		return
	_settings_overlay = overlay
	if overlay.has_signal("closed"):
		overlay.connect("closed", _on_grown_ups_closed, CONNECT_ONE_SHOT)
	var host: Node = get_parent() if get_parent() != null else self
	host.add_child(overlay)
	host.move_child(overlay, host.get_child_count() - 1)
	# The card steps aside but the world stays held until Done.
	if _pause_menu != null and bool(_pause_menu.call("is_open")):
		_pause_menu.call("close")
	_set_world_paused(true)


func is_grown_ups_open() -> bool:
	return _settings_overlay != null and is_instance_valid(_settings_overlay)


func _on_grown_ups_closed() -> void:
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		var overlay: Node = _settings_overlay
		_settings_overlay = null
		if overlay.get_parent() != null:
			overlay.get_parent().remove_child(overlay)
		overlay.queue_free()
	else:
		_settings_overlay = null
	# A grown-up may have changed the helper language: the line under the prompt
	# follows at once, no restart.
	refresh_helper_language()
	_set_world_paused(false)


func _ensure_pause_menu() -> Control:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		return _pause_menu
	var menu: Control = PauseMenuScript.new()
	menu.call("build")
	menu.connect("home_pressed", request_home)
	menu.connect("settings_pressed", open_grown_ups)
	menu.connect("closed", _on_pause_menu_closed)
	var host: Node = get_parent() if get_parent() != null else self
	host.add_child(menu)
	_pause_menu = menu
	return menu


func _on_pause_menu_closed() -> void:
	if not is_grown_ups_open():
		_set_world_paused(false)
	pause_closed.emit()


## Takes the room's input away (taps, walking, affordances) and gives back
## exactly what was there before. Tracked, not toggled: the summary disables the
## same character, and Continue must never undo the summary's decision.
func _set_world_paused(paused: bool) -> void:
	if paused == _paused_world:
		return
	_paused_world = paused
	var world: Node = get_world()
	var nav: Node = world.get_node_or_null("NavigationController") if world != null else null
	var character: Node = null
	if world != null and world.has_method("get_character"):
		character = world.call("get_character")
	if paused:
		if nav != null and nav.get("taps_enabled") != null:
			_prior_taps_enabled = bool(nav.get("taps_enabled"))
			nav.set("taps_enabled", false)
		if character != null and character.has_method("get_state_name") \
				and character.has_method("set_disabled"):
			_prior_character_disabled = String(character.call("get_state_name")) == "disabled"
			if not _prior_character_disabled:
				character.call("set_disabled", true)
	else:
		if nav != null and nav.get("taps_enabled") != null:
			nav.set("taps_enabled", _prior_taps_enabled)
		if character != null and character.has_method("set_disabled") \
				and not _prior_character_disabled:
			character.call("set_disabled", false)
	_refresh_visibility()


func is_world_paused() -> bool:
	return _paused_world


func _flush_save() -> void:
	if not is_inside_tree():
		return
	var save: Node = get_node_or_null(NodePath("/root/SaveService"))
	if save != null and save.has_method("save_profile"):
		save.call("save_profile")


## Joins the affordance layer to the world once there is one to join.
##
## When the world already mounts a layer of its own (`house_world.gd`'s
## `_build_affordance_layer()`), this HUD ADOPTS it: its own copy is freed and
## every rule below -- chrome off, narration covered, pause, prompt keep-out,
## the button keep-outs -- is applied to the world's layer from then on. The
## first version merely switched its own copy off, which left the world's copy
## deaf to all of them: the toy box's OPEN badge sat under the bottle close-up
## (`docs/shots/copy_ipad_feed.png`).
func _bind_affordance() -> void:
	if _affordance_bound:
		return
	var world: Node = get_world()
	if world == null:
		return
	_affordance_bound = true
	var host: Node = get_parent()
	var adopted: Control = null
	if host != null:
		for sibling: Node in host.get_children():
			if sibling != self and sibling != _affordance and sibling.name == "AffordanceLayer" \
					and sibling is Control and sibling.has_method("set_enabled"):
				adopted = sibling
				break
	if adopted != null:
		var mine: Control = _affordance
		_affordance = adopted
		if mine != null and is_instance_valid(mine):
			remove_child(mine)
			mine.queue_free()
	else:
		_affordance.call("bind", world)
	# The layer may have been live for frames before this HUD arrived: push
	# the current state at it now rather than waiting for the next change.
	_refresh_visibility()


## The screen rects the badge must never cover, from this HUD's own layout:
## Home, the star counter, and Next / Speak while they are up. The thumbstick's
## zone the layer reads from the world itself.
func _push_keep_outs() -> void:
	if _affordance == null or not is_instance_valid(_affordance) \
			or not _affordance.has_method("set_keep_out"):
		return
	var view: Vector2 = Vector2(1366.0, 1024.0)
	if is_inside_tree():
		var rect_size: Vector2 = get_viewport_rect().size
		if rect_size.x > 0.0 and rect_size.y > 0.0:
			view = rect_size
	var buttons: Dictionary = button_rects(view)
	_affordance.call("set_keep_out", "home", home_button_rect(view) if _home_button.visible else Rect2())
	_affordance.call("set_keep_out", "next", buttons["next"] if _next_button.visible else Rect2())
	_affordance.call("set_keep_out", "speak", buttons["speak"] if _speak_button.visible else Rect2())
	_affordance.call("set_keep_out", "stars",
			Rect2(_stars.offset_left, _stars.offset_top,
				_stars.offset_right - _stars.offset_left, _stars.offset_bottom - _stars.offset_top)
			if _stars.visible else Rect2())
	_affordance.call("set_keep_out", "version", Rect2())


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
	# Held (a live listening session): the same shape, quieter, never greyed to
	# "broken" -- and the ink stays ink so the word is still readable.
	var held: StyleBoxFlat = _button_style(tint.lerp(CREAM, 0.45), false)
	button.add_theme_stylebox_override("disabled", held)
	button.add_theme_color_override("font_disabled_color", INK.lerp(CREAM, 0.35))
	button.add_theme_color_override("icon_disabled_color", INK.lerp(CREAM, 0.35))
	add_child(button)
	return button


## A picture beside the word, for the reader who cannot read yet. The pack's
## icons are white, so the button tints them ink like its text.
func _set_button_icon(button: Button, path: String, side: int) -> void:
	if not ResourceLoader.exists(path):
		return
	var texture: Resource = load(path)
	if not (texture is Texture2D):
		return
	button.icon = texture
	button.expand_icon = true
	button.icon_alignment = side
	for state: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_constant_override("h_separation", 10)


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
