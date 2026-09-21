extends Control

## THE CLASSROOM CHROME, hands-free edition (owner change request 2026-09-20,
## `docs/ALIZ_TUTOR_CONTRACTS.md` addendum). The child does not press a
## microphone per turn, so the middle of the bottom edge is an INDICATOR, not
## a button:
##
##   * **Mic indicator** -- bottom-centre, `tutor_mic_indicator.gd`: a live
##     level ring and a word (Listening / I hear you! / Aliz is talking /
##     Muted / Mic off). Mandatory under the addendum's microphone-scope rule.
##   * **Mute** -- bottom-left, LARGE (120 px), lavender, speaker glyph with the
##     waves off when muted (never a slash, never an X) and a word under it.
##   * **Home** -- top-right, round, peach, the title screen's own house.
##   * **End lesson** -- top-left, small lavender pill; opens "Stop the lesson?".
##   * **Repeat** -- left of the indicator: Aliz says the prompt again.
##   * **Picture card** -- right of the indicator: shows / hides the big card.
##     The button's face IS the current card, small.
##   * **Tap to talk** -- the old big mint microphone, shown ONLY when
##     hands-free is unavailable (permission denied, no recogniser) or the
##     parent turned `handsFreeMode` off. It takes the indicator's slot.
##   * **Answer cards** -- the touch fallback for a device with no recogniser:
##     two or three small flashcards above the bottom row; tapping one is the
##     child's answer.
##
## and the **top slot**: the state banner ("Listening...", "Thinking...",
## "Great job!", "Let's try together!", "I'm listening!" when the child
## interrupts) or Aliz's subtitle while she speaks. Partial transcripts show
## softly in the banner (ink-soft, an ellipsis) while the child is talking.
##
## ## Nothing covers Aliz's face
##
## Every control is anchored to an edge and `layout_rects()` is the static
## list of where they land, so `test_tutor_scene.gd` can project her head
## through the real camera and assert no rect touches it at either shipped
## aspect ratio.
##
## ## The dev panel
##
## Hidden. "Simulated child audio": correct / wrong / cough / pause, then
## finish / interrupt Aliz -- through the voice session's test hook, so the
## whole hands-free loop runs on a Mac with no microphone permission and in
## the headless suite. Long-press the banner, or `-- --tutor-sim`. The session
## refuses simulated audio unless simulation was explicitly enabled.

const Palette := preload("res://scripts/ui/palette.gd")
const SafeAreaScript := preload("res://scripts/ui/safe_area.gd")
const HouseGlyphScript := preload("res://scenes/main/house_glyph.gd")
const IconGlyphScript := preload("res://scripts/progression/icon_glyph.gd")
const GlyphsScript := preload("res://scripts/tutor/ui/tutor_glyphs.gd")
const IndicatorScript := preload("res://scripts/tutor/ui/tutor_mic_indicator.gd")
const FlashcardArtScript := preload("res://scripts/tutor/classroom/flashcard_art.gd")
const ExitConfirmScript := preload("res://scripts/tutor/ui/tutor_exit_confirm.gd")

signal home_pressed()
signal mute_toggled(muted: bool)
signal repeat_pressed()
signal card_toggled(shown: bool)
signal tap_to_talk_pressed()
signal answer_card_tapped(asset_id: String)
signal exit_requested()
signal exit_confirmed()
signal exit_kept()
signal resume_pressed()
signal sim_requested(kind: String)

const HOME_SIZE: float = 104.0
const HOME_TOP: float = 26.0
const HOME_RIGHT: float = -36.0

const END_WIDTH: float = 190.0
const END_HEIGHT: float = 66.0
const END_LEFT: float = 32.0
const END_TOP: float = 44.0

const BANNER_HALF_WIDTH: float = 300.0
const BANNER_TOP: float = 28.0
const BANNER_HEIGHT: float = 78.0
const SUBTITLE_HALF_WIDTH: float = 380.0
const SUBTITLE_HEIGHT: float = 84.0
const SUBTITLE_TOP: float = 22.0

const INDICATOR_WIDTH: float = 210.0
const INDICATOR_HEIGHT: float = 214.0
const INDICATOR_BOTTOM: float = -22.0
const TALK_SIZE: float = 200.0
const TALK_BOTTOM: float = -36.0
const SIDE_SIZE: float = 110.0
const SIDE_OFFSET: float = 230.0
const SIDE_BOTTOM: float = -60.0

const MUTE_SIZE: float = 120.0
const MUTE_LEFT: float = 32.0
const MUTE_BOTTOM: float = -60.0

## The answer cards sit at the RIGHT, under the board and above the pets:
## centred they would sit on Aliz's chin at 16:9 and on the Tap-to-talk button.
## 100 px cards: four of them (the subject choice, QA C4) end 60 px clear of
## Aliz's hair at 1334 wide; secondary controls, the primary is Tap-to-talk.
const ANSWER_CARD_SIZE: Vector2 = Vector2(100.0, 106.0)
const ANSWER_CARD_GAP: float = 14.0
## Three answers on a question, four subjects on the choice; the row grows
## leftwards from its bottom-right corner.
const MAX_ANSWER_CARDS: int = 4
const ANSWER_CARDS_RIGHT: float = -60.0
const ANSWER_CARDS_BOTTOM: float = -290.0

const CARD_WIDTH: float = 330.0
const CARD_HEIGHT: float = 390.0
const CARD_RIGHT: float = -48.0
const CARD_TOP: float = 156.0

const BANNER_FONT_SIZE: int = 34
const SUBTITLE_FONT_SIZE: int = 32
const LONG_PRESS_SECONDS: float = 1.2

const SIM_KINDS: Array = [
	["SimCorrect", "Correct answer", "correct"],
	["SimWrong", "Wrong answer", "wrong"],
	["SimCough", "Cough", "cough"],
	["SimPause", "Pause, then finish", "pause_then_finish"],
	["SimInterrupt", "Interrupt Aliz", "interrupt"],
]

const BANNER_NONE: String = ""
const BANNER_LISTENING: String = "listening"
const BANNER_HEARING: String = "hearing"
const BANNER_THINKING: String = "thinking"
const BANNER_SUCCESS: String = "success"
const BANNER_TOGETHER: String = "together"
const BANNER_INTERRUPTED: String = "interrupted"
const BANNER_INFO: String = "info"

const BANNER_TEXTS: Dictionary = {
	BANNER_LISTENING: "Listening...",
	BANNER_HEARING: "I hear you...",
	BANNER_THINKING: "Thinking...",
	BANNER_SUCCESS: "Great job!",
	BANNER_TOGETHER: "Let's try together!",
	BANNER_INTERRUPTED: "I'm listening!",
}
const BANNER_COLOURS: Dictionary = {
	BANNER_LISTENING: Palette.MINT,
	BANNER_HEARING: Palette.MINT,
	BANNER_THINKING: Palette.LAVENDER,
	BANNER_SUCCESS: Palette.STAR_NEXT,
	BANNER_TOGETHER: Palette.PEACH,
	BANNER_INTERRUPTED: Palette.SOFT_PINK,
	BANNER_INFO: Palette.CREAM,
}

var _safe: Control = null
var _home: Button = null
var _end: Button = null
var _mute: Button = null
var _mute_glyph: Control = null
var _mute_caption: Label = null
var _indicator: Control = null
var _talk: Button = null
var _repeat: Button = null
var _card_button: Button = null
var _card_thumb: Control = null
var _answer_row: HBoxContainer = null
var _banner: PanelContainer = null
var _banner_label: Label = null
var _banner_kind: String = BANNER_NONE
var _partial: String = ""
var _subtitle: PanelContainer = null
var _subtitle_label: Label = null
var _card: Control = null
var _card_art: Control = null
var _confirm: Control = null
var _resume: Control = null
var _dev_panel: PanelContainer = null
var _built: bool = false
var _muted: bool = false
var _card_shown: bool = false
var _press_started_msec: int = -1
var _asset_id: String = ""
var _answer_ids: Array = []


## Where every control lands in a viewport of `viewport_size`, before the
## safe-area inset, as `{name: Rect2}`. Static and pure, for the layout tests.
static func layout_rects(viewport_size: Vector2) -> Dictionary:
	var w: float = viewport_size.x
	var h: float = viewport_size.y
	var answers_width: float = ANSWER_CARD_SIZE.x * MAX_ANSWER_CARDS + ANSWER_CARD_GAP * (MAX_ANSWER_CARDS - 1)
	return {
		"home": Rect2(w + HOME_RIGHT - HOME_SIZE, HOME_TOP, HOME_SIZE, HOME_SIZE),
		"end": Rect2(END_LEFT, END_TOP, END_WIDTH, END_HEIGHT),
		"banner": Rect2(w * 0.5 - BANNER_HALF_WIDTH, BANNER_TOP, BANNER_HALF_WIDTH * 2.0, BANNER_HEIGHT),
		"subtitle": Rect2(w * 0.5 - SUBTITLE_HALF_WIDTH, SUBTITLE_TOP, SUBTITLE_HALF_WIDTH * 2.0, SUBTITLE_HEIGHT),
		"indicator": Rect2(w * 0.5 - INDICATOR_WIDTH * 0.5, h + INDICATOR_BOTTOM - INDICATOR_HEIGHT, INDICATOR_WIDTH, INDICATOR_HEIGHT),
		"tapToTalk": Rect2(w * 0.5 - TALK_SIZE * 0.5, h + TALK_BOTTOM - TALK_SIZE, TALK_SIZE, TALK_SIZE),
		"repeat": Rect2(w * 0.5 - SIDE_OFFSET - SIDE_SIZE * 0.5, h + SIDE_BOTTOM - SIDE_SIZE, SIDE_SIZE, SIDE_SIZE),
		"card": Rect2(w * 0.5 + SIDE_OFFSET - SIDE_SIZE * 0.5, h + SIDE_BOTTOM - SIDE_SIZE, SIDE_SIZE, SIDE_SIZE),
		"mute": Rect2(MUTE_LEFT, h + MUTE_BOTTOM - MUTE_SIZE - 30.0, MUTE_SIZE, MUTE_SIZE + 30.0),
		"answerCards": Rect2(w + ANSWER_CARDS_RIGHT - answers_width, h + ANSWER_CARDS_BOTTOM - ANSWER_CARD_SIZE.y, answers_width, ANSWER_CARD_SIZE.y),
		"flashcard": Rect2(w + CARD_RIGHT - CARD_WIDTH, CARD_TOP, CARD_WIDTH, CARD_HEIGHT),
	}


func _ready() -> void:
	build()
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


## The banner long-press. Headless tests drive it.
func advance(_delta: float) -> void:
	if _press_started_msec >= 0 and Time.get_ticks_msec() - _press_started_msec >= int(LONG_PRESS_SECONDS * 1000.0):
		_press_started_msec = -1
		set_dev_panel_visible(not is_dev_panel_visible())


func build() -> void:
	if _built:
		return
	_built = true
	name = "TutorHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_safe = SafeAreaScript.new()
	_safe.name = "SafeArea"
	add_child(_safe)

	# -- Top slot: banner and subtitle ---------------------------------------
	_banner = PanelContainer.new()
	_banner.name = "Banner"
	_banner.mouse_filter = Control.MOUSE_FILTER_STOP
	_place(_banner, Control.PRESET_CENTER_TOP, -BANNER_HALF_WIDTH, BANNER_TOP, BANNER_HALF_WIDTH, BANNER_TOP + BANNER_HEIGHT)
	_banner.gui_input.connect(_on_banner_input)
	_safe.add_child(_banner)
	_banner_label = _label("BannerLabel", BANNER_FONT_SIZE, Palette.INK)
	_banner.add_child(_banner_label)
	_banner.visible = false

	_subtitle = PanelContainer.new()
	_subtitle.name = "Subtitle"
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_subtitle, Control.PRESET_CENTER_TOP, -SUBTITLE_HALF_WIDTH, SUBTITLE_TOP, SUBTITLE_HALF_WIDTH, SUBTITLE_TOP + SUBTITLE_HEIGHT)
	var subtitle_style: StyleBoxFlat = _pill(Palette.CREAM, 34, Palette.deep(Palette.PEACH))
	subtitle_style.content_margin_left = 30.0
	subtitle_style.content_margin_right = 30.0
	_subtitle.add_theme_stylebox_override("panel", subtitle_style)
	_safe.add_child(_subtitle)
	_subtitle_label = _label("SubtitleLabel", SUBTITLE_FONT_SIZE, Palette.INK)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_child(_subtitle_label)
	_subtitle.visible = false

	# -- Flashcard overlay ----------------------------------------------------
	_card = Control.new()
	_card.name = "Flashcard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_card, Control.PRESET_TOP_RIGHT, CARD_RIGHT - CARD_WIDTH, CARD_TOP, CARD_RIGHT, CARD_TOP + CARD_HEIGHT)
	_safe.add_child(_card)
	_card_art = FlashcardArtScript.new()
	_card_art.name = "Art"
	_card_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.add_child(_card_art)
	_card.visible = false

	# -- Home (top-right) and End lesson (top-left) ---------------------------
	_home = _round_button("HomeButton", Palette.HOME_CHROME, HOME_SIZE)
	_place(_home, Control.PRESET_TOP_RIGHT, HOME_RIGHT - HOME_SIZE, HOME_TOP, HOME_RIGHT, HOME_TOP + HOME_SIZE)
	var house: Control = HouseGlyphScript.new()
	house.name = "HouseGlyph"
	house.set("tint", Palette.INK)
	house.set("face_color", Palette.HOME_CHROME)
	house.set("window_color", Palette.HOME_CHROME)
	_place(house, Control.PRESET_FULL_RECT, 16.0, 14.0, -16.0, -18.0)
	_home.add_child(house)
	_home.pressed.connect(func() -> void: home_pressed.emit())
	_safe.add_child(_home)

	_end = Button.new()
	_end.name = "EndButton"
	_end.text = "End lesson"
	_end.focus_mode = Control.FOCUS_NONE
	_end.add_theme_font_size_override("font_size", 24)
	_end.add_theme_color_override("font_color", Palette.INK)
	_end.add_theme_color_override("font_hover_color", Palette.INK)
	_end.add_theme_color_override("font_pressed_color", Palette.INK)
	_end.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var pill: StyleBoxFlat = _pill(Palette.LAVENDER.darkened(0.08) if state == "pressed" else Palette.LAVENDER, int(END_HEIGHT * 0.5), Palette.CREAM)
		pill.content_margin_left = 54.0
		pill.content_margin_right = 20.0
		_end.add_theme_stylebox_override(state, pill)
	_place(_end, Control.PRESET_TOP_LEFT, END_LEFT, END_TOP, END_LEFT + END_WIDTH, END_TOP + END_HEIGHT)
	var back_glyph: Control = IconGlyphScript.new()
	back_glyph.name = "BackGlyph"
	back_glyph.set("glyph", 1)
	back_glyph.set("tint", Palette.INK)
	_place(back_glyph, Control.PRESET_LEFT_WIDE, 16.0, 14.0, 52.0, -14.0)
	_end.add_child(back_glyph)
	_end.pressed.connect(request_exit)
	_safe.add_child(_end)

	# -- Mute (bottom-left, large) --------------------------------------------
	_mute = _round_button("MuteButton", Palette.LAVENDER, MUTE_SIZE)
	_place(_mute, Control.PRESET_BOTTOM_LEFT, MUTE_LEFT, MUTE_BOTTOM - MUTE_SIZE, MUTE_LEFT + MUTE_SIZE, MUTE_BOTTOM)
	_mute_glyph = GlyphsScript.new()
	_mute_glyph.name = "SpeakerGlyph"
	_mute_glyph.set("kind", "speaker")
	_place(_mute_glyph, Control.PRESET_FULL_RECT, 22.0, 22.0, -22.0, -22.0)
	_mute.add_child(_mute_glyph)
	_mute.pressed.connect(toggle_mute)
	_safe.add_child(_mute)
	_mute_caption = _label("MuteCaption", 22, Palette.INK)
	_mute_caption.text = "Mute"
	_mute_caption.add_theme_color_override("font_outline_color", Palette.CREAM)
	_mute_caption.add_theme_constant_override("outline_size", 8)
	_place(_mute_caption, Control.PRESET_BOTTOM_LEFT, MUTE_LEFT - 20.0, MUTE_BOTTOM, MUTE_LEFT + MUTE_SIZE + 20.0, MUTE_BOTTOM + 30.0)
	_safe.add_child(_mute_caption)

	# -- Bottom centre: indicator, tap-to-talk, repeat, card -----------------
	_indicator = IndicatorScript.new()
	_indicator.name = "MicIndicator"
	_place(_indicator, Control.PRESET_CENTER_BOTTOM, -INDICATOR_WIDTH * 0.5, INDICATOR_BOTTOM - INDICATOR_HEIGHT, INDICATOR_WIDTH * 0.5, INDICATOR_BOTTOM)
	_safe.add_child(_indicator)
	_indicator.call("build")

	_talk = _round_button("TapToTalkButton", Palette.MINT, TALK_SIZE)
	_place(_talk, Control.PRESET_CENTER_BOTTOM, -TALK_SIZE * 0.5, TALK_BOTTOM - TALK_SIZE, TALK_SIZE * 0.5, TALK_BOTTOM)
	var talk_glyph: Control = IconGlyphScript.new()
	talk_glyph.name = "MicGlyph"
	talk_glyph.set("glyph", 4)
	talk_glyph.set("tint", Palette.INK)
	_place(talk_glyph, Control.PRESET_FULL_RECT, 58.0, 22.0, -58.0, -74.0)
	_talk.add_child(talk_glyph)
	var talk_caption: Label = _label("TalkCaption", 24, Palette.INK)
	talk_caption.text = "Tap to talk"
	_place(talk_caption, Control.PRESET_BOTTOM_WIDE, 0.0, -58.0, 0.0, -22.0)
	_talk.add_child(talk_caption)
	_talk.pressed.connect(func() -> void: tap_to_talk_pressed.emit())
	_talk.visible = false
	_safe.add_child(_talk)

	_repeat = _round_button("RepeatButton", Palette.PEACH, SIDE_SIZE)
	_place(_repeat, Control.PRESET_CENTER_BOTTOM, -SIDE_OFFSET - SIDE_SIZE * 0.5, SIDE_BOTTOM - SIDE_SIZE, -SIDE_OFFSET + SIDE_SIZE * 0.5, SIDE_BOTTOM)
	var play_glyph: Control = IconGlyphScript.new()
	play_glyph.name = "PlayGlyph"
	play_glyph.set("glyph", 3)
	play_glyph.set("tint", Palette.INK)
	_place(play_glyph, Control.PRESET_FULL_RECT, 26.0, 22.0, -22.0, -26.0)
	_repeat.add_child(play_glyph)
	_repeat.pressed.connect(func() -> void: repeat_pressed.emit())
	_safe.add_child(_repeat)

	_card_button = _round_button("CardButton", Palette.SOFT_PINK, SIDE_SIZE)
	_place(_card_button, Control.PRESET_CENTER_BOTTOM, SIDE_OFFSET - SIDE_SIZE * 0.5, SIDE_BOTTOM - SIDE_SIZE, SIDE_OFFSET + SIDE_SIZE * 0.5, SIDE_BOTTOM)
	_card_thumb = FlashcardArtScript.new()
	_card_thumb.name = "Thumb"
	_card_thumb.set("show_word", false)
	_place(_card_thumb, Control.PRESET_FULL_RECT, 26.0, 18.0, -26.0, -22.0)
	_card_button.add_child(_card_thumb)
	_card_button.pressed.connect(toggle_card)
	_safe.add_child(_card_button)

	# -- Answer cards (touch fallback) ---------------------------------------
	_answer_row = HBoxContainer.new()
	_answer_row.name = "AnswerCards"
	_answer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_answer_row.add_theme_constant_override("separation", int(ANSWER_CARD_GAP))
	var answers_width: float = ANSWER_CARD_SIZE.x * MAX_ANSWER_CARDS + ANSWER_CARD_GAP * (MAX_ANSWER_CARDS - 1)
	_place(_answer_row, Control.PRESET_BOTTOM_RIGHT, ANSWER_CARDS_RIGHT - answers_width, ANSWER_CARDS_BOTTOM - ANSWER_CARD_SIZE.y, ANSWER_CARDS_RIGHT, ANSWER_CARDS_BOTTOM)
	_answer_row.alignment = BoxContainer.ALIGNMENT_END
	_answer_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_answer_row.visible = false
	_safe.add_child(_answer_row)

	# -- Dev panel (hidden) ---------------------------------------------------
	_dev_panel = PanelContainer.new()
	_dev_panel.name = "DevPanel"
	_dev_panel.add_theme_stylebox_override("panel", _pill(Palette.light(Palette.LAVENDER), 18, Palette.deep(Palette.LAVENDER)))
	_place(_dev_panel, Control.PRESET_BOTTOM_RIGHT, -330.0, -560.0, -36.0, -200.0)
	_safe.add_child(_dev_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_dev_panel.add_child(column)
	var caption: Label = _label("DevCaption", 18, Palette.INK_SOFT)
	caption.text = "DEV: simulated child audio"
	column.add_child(caption)
	for entry: Array in SIM_KINDS:
		var button: Button = Button.new()
		button.name = String(entry[0])
		button.text = String(entry[1])
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, 50.0)
		button.add_theme_font_size_override("font_size", 21)
		button.add_theme_color_override("font_color", Palette.INK)
		button.add_theme_stylebox_override("normal", _pill(Palette.CREAM, 16, Palette.deep(Palette.LAVENDER)))
		button.add_theme_stylebox_override("hover", _pill(Palette.CREAM, 16, Palette.deep(Palette.LAVENDER)))
		button.add_theme_stylebox_override("pressed", _pill(Palette.LAVENDER, 16, Palette.deep(Palette.LAVENDER)))
		var kind: String = String(entry[2])
		button.pressed.connect(func() -> void: sim_requested.emit(kind))
		column.add_child(button)
	_dev_panel.visible = false

	# -- Exit confirm and resume card -----------------------------------------
	_confirm = ExitConfirmScript.new()
	_confirm.call("build")
	_confirm.keep_going.connect(func() -> void: exit_kept.emit())
	_confirm.stop_confirmed.connect(func() -> void: exit_confirmed.emit())
	add_child(_confirm)

	_resume = _build_resume_card()
	add_child(_resume)

	_apply_banner()
	set_indicator(IndicatorScript.STATE_OFF, 0.0)


# ---------------------------------------------------------------------------
# State the scene drives
# ---------------------------------------------------------------------------

func set_banner(kind: String, text: String = "") -> void:
	build()
	_banner_kind = kind
	_partial = ""
	if kind != BANNER_NONE:
		_banner_label.text = text if not text.is_empty() else String(BANNER_TEXTS.get(kind, ""))
		_banner_label.add_theme_color_override("font_color", Palette.INK)
		_apply_banner()
	_refresh_top_slot()


## What the banner says right now, or "" while it is hidden.
func banner_text() -> String:
	return _banner_label.text if _banner != null and _banner.visible else ""


## The banner's meaning, whether or not it is currently showing.
func banner_kind() -> String:
	return _banner_kind


## A partial transcript, shown softly in the banner while the child talks.
func show_partial(text: String) -> void:
	build()
	_partial = text.strip_edges()
	if _partial.is_empty():
		set_banner(BANNER_LISTENING)
		return
	_banner_kind = BANNER_HEARING
	_banner_label.text = "%s..." % _partial
	_banner_label.add_theme_color_override("font_color", Palette.INK_SOFT)
	_apply_banner()
	_refresh_top_slot()


func partial_text() -> String:
	return _partial


func set_subtitle(text: String) -> void:
	build()
	_subtitle_label.text = text
	_refresh_top_slot()


func subtitle_text() -> String:
	return _subtitle_label.text if _subtitle != null and _subtitle.visible else ""


func _refresh_top_slot() -> void:
	var has_subtitle: bool = not _subtitle_label.text.strip_edges().is_empty()
	_subtitle.visible = has_subtitle
	_banner.visible = _banner_kind != BANNER_NONE and not has_subtitle


## The indicator's state and level (0..1), every frame from the session.
func set_indicator(state: String, level: float) -> void:
	build()
	_indicator.set("state", state)
	_indicator.set("level", level)


func indicator_state() -> String:
	return String(_indicator.get("state")) if _indicator != null else ""


func indicator_caption() -> String:
	return String(_indicator.call("caption_text")) if _indicator != null else ""


## Hands-free off: the indicator gives way to the Tap-to-talk button.
func set_tap_to_talk_visible(shown: bool) -> void:
	build()
	_talk.visible = shown
	_indicator.visible = not shown


func is_tap_to_talk_visible() -> bool:
	return _talk != null and _talk.visible


func set_tap_to_talk_enabled(enabled: bool) -> void:
	build()
	_talk.disabled = not enabled


## The touch fallback: up to three cards the child can tap as an answer.
func show_answer_cards(asset_ids: Array) -> void:
	build()
	for child: Node in _answer_row.get_children():
		_answer_row.remove_child(child)
		child.queue_free()
	_answer_ids = asset_ids.slice(0, MAX_ANSWER_CARDS)
	for asset_id in _answer_ids:
		var id: String = String(asset_id)
		var button: Button = Button.new()
		button.name = "Answer_%s" % id
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = ANSWER_CARD_SIZE
		for state: String in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, _pill(Palette.CREAM.darkened(0.06) if state == "pressed" else Palette.CREAM, 22, Palette.deep(Palette.PEACH)))
		var art: Control = FlashcardArtScript.new()
		art.name = "Art"
		art.set("asset_id", id)
		_place(art, Control.PRESET_FULL_RECT, 8.0, 8.0, -8.0, -8.0)
		button.add_child(art)
		button.pressed.connect(func() -> void: answer_card_tapped.emit(id))
		_answer_row.add_child(button)
	_answer_row.visible = not asset_ids.is_empty()


func hide_answer_cards() -> void:
	build()
	_answer_row.visible = false


func answer_cards_shown() -> Array:
	return _answer_ids if _answer_row != null and _answer_row.visible else []


func tap_answer_card(asset_id: String) -> void:
	if answer_cards_shown().has(asset_id):
		answer_card_tapped.emit(asset_id)


func set_card(asset_id: String) -> void:
	build()
	_asset_id = asset_id
	_card_art.set("asset_id", asset_id)
	_card_thumb.set("asset_id", asset_id)
	_card_button.visible = not asset_id.is_empty()
	if asset_id.is_empty():
		show_card(false)


func current_card() -> String:
	return _asset_id


func show_card(shown: bool) -> void:
	build()
	_card_shown = shown and not _asset_id.is_empty()
	_card.visible = _card_shown


func is_card_shown() -> bool:
	return _card_shown


func toggle_card() -> void:
	show_card(not _card_shown)
	card_toggled.emit(_card_shown)


func set_muted(muted: bool) -> void:
	build()
	_muted = muted
	_mute_glyph.set("active", not muted)
	_mute_caption.text = "Muted" if muted else "Mute"
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var tint: Color = Palette.deep(Palette.LAVENDER) if muted else Palette.LAVENDER
		var style: StyleBoxFlat = _pill(tint.darkened(0.08) if state == "pressed" else tint, int(MUTE_SIZE * 0.5), Palette.CREAM)
		style.set_border_width_all(4)
		_mute.add_theme_stylebox_override(state, style)


func is_muted() -> bool:
	return _muted


func toggle_mute() -> void:
	set_muted(not _muted)
	mute_toggled.emit(_muted)


func request_exit() -> void:
	build()
	_confirm.call("open")
	exit_requested.emit()


func is_exit_confirm_open() -> bool:
	return _confirm != null and _confirm.visible


func exit_confirm() -> Control:
	return _confirm


## "Welcome back -- tap to continue": after the app was in the background the
## microphone is never reopened on its own.
func show_resume_card(shown: bool) -> void:
	build()
	_resume.visible = shown


func is_resume_card_shown() -> bool:
	return _resume != null and _resume.visible


func press_resume() -> void:
	if is_resume_card_shown():
		_resume.visible = false
		resume_pressed.emit()


func set_dev_panel_visible(shown: bool) -> void:
	build()
	_dev_panel.visible = shown


func is_dev_panel_visible() -> bool:
	return _dev_panel != null and _dev_panel.visible


## Every touchable control, by name, for the routing tests.
func buttons() -> Dictionary:
	build()
	return {"home": _home, "end": _end, "mute": _mute, "tapToTalk": _talk, "repeat": _repeat, "card": _card_button}


func press(button_name: String) -> void:
	var button: Button = buttons().get(button_name, null)
	if button != null and not button.disabled:
		button.pressed.emit()


func press_sim(kind: String) -> void:
	sim_requested.emit(kind)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _build_resume_card() -> Control:
	var overlay: Control = Control.new()
	overlay.name = "ResumeCard"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	var scrim: ColorRect = ColorRect.new()
	scrim.color = Palette.SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(scrim)
	var card: PanelContainer = PanelContainer.new()
	card.name = "Card"
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Palette.CREAM
	style.border_color = Palette.deep(Palette.MINT)
	style.set_border_width_all(4)
	style.set_corner_radius_all(36)
	style.content_margin_left = 40.0
	style.content_margin_right = 40.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 28.0
	card.add_theme_stylebox_override("panel", style)
	_place(card, Control.PRESET_CENTER_LEFT, 44.0, -110.0, 584.0, 150.0)
	overlay.add_child(card)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	card.add_child(column)
	var title: Label = _label("Title", 38, Palette.INK)
	title.text = "Welcome back!"
	column.add_child(title)
	var line: Label = _label("Line", 24, Palette.INK_SOFT)
	line.text = "The microphone is off. Tap to keep learning."
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(line)
	var button: Button = Button.new()
	button.name = "ContinueButton"
	button.text = "Tap to continue"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(400.0, 88.0)
	button.add_theme_font_size_override("font_size", 32)
	button.add_theme_color_override("font_color", Palette.INK)
	button.add_theme_color_override("font_hover_color", Palette.INK)
	button.add_theme_color_override("font_pressed_color", Palette.INK)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, _pill(Palette.MINT.darkened(0.08) if state == "pressed" else Palette.MINT, 44, Palette.CREAM))
	button.pressed.connect(press_resume)
	column.add_child(button)
	return overlay


func _apply_banner() -> void:
	var colour: Color = BANNER_COLOURS.get(_banner_kind, Palette.CREAM)
	_banner.add_theme_stylebox_override("panel", _pill(colour, int(BANNER_HEIGHT * 0.5), Palette.CREAM))


func _on_banner_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_press_started_msec = Time.get_ticks_msec() if mouse.pressed else -1
	elif event is InputEventScreenTouch:
		_press_started_msec = Time.get_ticks_msec() if (event as InputEventScreenTouch).pressed else -1


static func _place(control: Control, preset: int, left: float, top: float, right: float, bottom: float) -> void:
	control.set_anchors_and_offsets_preset(preset)
	control.offset_left = left
	control.offset_top = top
	control.offset_right = right
	control.offset_bottom = bottom


func _label(node_name: String, font_size: int, colour: Color) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _round_button(node_name: String, tint: Color, diameter: float) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = _pill(tint.darkened(0.08) if state == "pressed" else tint, int(diameter * 0.5), Palette.CREAM)
		style.set_border_width_all(4)
		button.add_theme_stylebox_override(state, style)
	var held: StyleBoxFlat = _pill(tint.lerp(Palette.CREAM, 0.45), int(diameter * 0.5), Palette.CREAM)
	held.set_border_width_all(4)
	button.add_theme_stylebox_override("disabled", held)
	return button


static func _pill(fill: Color, radius: int, rim: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.set_border_width_all(3)
	style.border_color = rim
	return style
