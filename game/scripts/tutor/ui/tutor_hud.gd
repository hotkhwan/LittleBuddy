extends Control

## THE CLASSROOM CHROME. Six touchable things and a banner, nothing else:
##
##   * **Home** -- top-right, round, peach, the title screen's own house. Always
##     works. (104 px: a grown-up's control a child may also press.)
##   * **Mute** -- beside Home, round, lavender, a speaker glyph; waves off when
##     muted, never a slash.
##   * **Microphone** -- the big round mint button bottom-centre (240 px, the
##     art bible section 8 floor for a child's target) with a pulsing ring
##     while listening.
##   * **Repeat** -- left of the mic: Aliz says the prompt again.
##   * **Picture card** -- right of the mic: shows / hides the big flashcard.
##     The button's face IS the current card, small.
##   * **Stop** -- small, bottom-left, lavender: opens "Stop the lesson?".
##
## and the **state banner**, top-centre: "Listening...", "Thinking...",
## Aliz's subtitle while she speaks (a cream strip low on the screen so it
## reads like a caption), "Great job!", "Let's try together!".
##
## ## Nothing covers Aliz's face
##
## Aliz sits across the table, so her face is in the middle third of the
## screen. Every control here is anchored to an edge, and `layout_rects()` is
## the static list of where they land, so `test_tutor_scene.gd` can project her
## head through the real camera and assert that no rect touches it, at every
## aspect ratio the game ships at -- the same discipline the house HUD's
## presentation modes and the affordance layer's keep-outs follow.
##
## Safe-area aware the way `house_hud.gd` is: the whole thing sits under a
## `SafeArea` inset, so nothing lands under a notch or a home indicator.
##
## ## The dev panel
##
## Hidden. It exists so the WHOLE loop -- listen, think, speak, celebrate --
## runs on a Mac with no microphone permission and in the headless suite:
## "Say correct answer / Say wrong answer / Say nothing". It appears only on a
## long-press of the banner or the user arg `-- --tutor-sim`, and the scene
## refuses a simulated transcript unless simulation was explicitly enabled.
## It never fakes a recognition result in normal play.

const Palette := preload("res://scripts/ui/palette.gd")
const SafeAreaScript := preload("res://scripts/ui/safe_area.gd")
const HouseGlyphScript := preload("res://scenes/main/house_glyph.gd")
const IconGlyphScript := preload("res://scripts/progression/icon_glyph.gd")
const GlyphsScript := preload("res://scripts/tutor/ui/tutor_glyphs.gd")
const FlashcardArtScript := preload("res://scripts/tutor/classroom/flashcard_art.gd")
const ExitConfirmScript := preload("res://scripts/tutor/ui/tutor_exit_confirm.gd")

signal home_pressed()
signal mute_toggled(muted: bool)
signal repeat_pressed()
signal card_toggled(shown: bool)
signal mic_pressed()
signal exit_requested()
signal exit_confirmed()
signal exit_kept()
signal sim_requested(kind: String)

const HOME_SIZE: float = 104.0
const HOME_TOP: float = 26.0
const HOME_RIGHT: float = -36.0
const MUTE_SIZE: float = 88.0
const MUTE_GAP: float = 18.0

const BANNER_HALF_WIDTH: float = 300.0
const BANNER_TOP: float = 28.0
const BANNER_HEIGHT: float = 78.0

const MIC_SIZE: float = 240.0
const MIC_BOTTOM: float = -28.0
const SIDE_SIZE: float = 110.0
const SIDE_OFFSET: float = 230.0
const SIDE_BOTTOM: float = -60.0

const STOP_WIDTH: float = 168.0
const STOP_HEIGHT: float = 66.0
const STOP_LEFT: float = 32.0
const STOP_BOTTOM: float = -32.0

## The subtitle shares the banner's slot at the top: low on the screen it sat
## squarely on Aliz's face (see the first render of this scene), and the top
## band between the two right-hand buttons is the one strip of screen nothing
## else wants. Two lines at most; the turn validator caps speech at 160 chars.
const SUBTITLE_HALF_WIDTH: float = 380.0
const SUBTITLE_HEIGHT: float = 84.0
const SUBTITLE_TOP: float = 22.0

const CARD_WIDTH: float = 330.0
const CARD_HEIGHT: float = 390.0
const CARD_RIGHT: float = -48.0
const CARD_TOP: float = 156.0

const BANNER_FONT_SIZE: int = 34
const SUBTITLE_FONT_SIZE: int = 32
const LONG_PRESS_SECONDS: float = 1.2

const SIM_CORRECT: String = "correct"
const SIM_WRONG: String = "wrong"
const SIM_NOTHING: String = "nothing"

## Banner kinds, so a test can ask what the banner MEANS rather than parse it.
const BANNER_NONE: String = ""
const BANNER_LISTENING: String = "listening"
const BANNER_THINKING: String = "thinking"
const BANNER_SUCCESS: String = "success"
const BANNER_TOGETHER: String = "together"
const BANNER_INFO: String = "info"

const BANNER_TEXTS: Dictionary = {
	BANNER_LISTENING: "Listening...",
	BANNER_THINKING: "Thinking...",
	BANNER_SUCCESS: "Great job!",
	BANNER_TOGETHER: "Let's try together!",
}
const BANNER_COLOURS: Dictionary = {
	BANNER_LISTENING: Palette.MINT,
	BANNER_THINKING: Palette.LAVENDER,
	BANNER_SUCCESS: Palette.STAR_NEXT,
	BANNER_TOGETHER: Palette.PEACH,
	BANNER_INFO: Palette.CREAM,
}

var _safe: Control = null
var _home: Button = null
var _mute: Button = null
var _mute_glyph: Control = null
var _mic: Button = null
var _ring: Control = null
var _repeat: Button = null
var _card_button: Button = null
var _card_thumb: Control = null
var _stop: Button = null
var _banner: PanelContainer = null
var _banner_label: Label = null
var _banner_kind: String = BANNER_NONE
var _subtitle: PanelContainer = null
var _subtitle_label: Label = null
var _card: Control = null
var _card_art: Control = null
var _confirm: Control = null
var _dev_panel: PanelContainer = null
var _built: bool = false
var _muted: bool = false
var _listening: bool = false
var _card_shown: bool = false
var _ring_phase: float = 0.0
var _press_started_msec: int = -1
var _asset_id: String = ""


## Where every control lands in a viewport of `viewport_size`, before the
## safe-area inset, as `{name: Rect2}`. Static and pure, for the layout tests.
static func layout_rects(viewport_size: Vector2) -> Dictionary:
	var w: float = viewport_size.x
	var h: float = viewport_size.y
	var mute_right: float = HOME_RIGHT - HOME_SIZE - MUTE_GAP
	return {
		"home": Rect2(w + HOME_RIGHT - HOME_SIZE, HOME_TOP, HOME_SIZE, HOME_SIZE),
		"mute": Rect2(w + mute_right - MUTE_SIZE, HOME_TOP + (HOME_SIZE - MUTE_SIZE) * 0.5, MUTE_SIZE, MUTE_SIZE),
		"banner": Rect2(w * 0.5 - BANNER_HALF_WIDTH, BANNER_TOP, BANNER_HALF_WIDTH * 2.0, BANNER_HEIGHT),
		"mic": Rect2(w * 0.5 - MIC_SIZE * 0.5, h + MIC_BOTTOM - MIC_SIZE, MIC_SIZE, MIC_SIZE),
		"repeat": Rect2(w * 0.5 - SIDE_OFFSET - SIDE_SIZE * 0.5, h + SIDE_BOTTOM - SIDE_SIZE, SIDE_SIZE, SIDE_SIZE),
		"card": Rect2(w * 0.5 + SIDE_OFFSET - SIDE_SIZE * 0.5, h + SIDE_BOTTOM - SIDE_SIZE, SIDE_SIZE, SIDE_SIZE),
		"stop": Rect2(STOP_LEFT, h + STOP_BOTTOM - STOP_HEIGHT, STOP_WIDTH, STOP_HEIGHT),
		"subtitle": Rect2(w * 0.5 - SUBTITLE_HALF_WIDTH, SUBTITLE_TOP, SUBTITLE_HALF_WIDTH * 2.0, SUBTITLE_HEIGHT),
		"flashcard": Rect2(w + CARD_RIGHT - CARD_WIDTH, CARD_TOP, CARD_WIDTH, CARD_HEIGHT),
	}


func _ready() -> void:
	build()
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


## The ring's pulse and the banner long-press. Headless tests drive it.
func advance(delta: float) -> void:
	if _listening and _ring != null:
		_ring_phase = fmod(_ring_phase + delta * 0.9, 1.0)
		_ring.set("phase", _ring_phase)
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

	# -- Banner, top-centre ---------------------------------------------------
	_banner = PanelContainer.new()
	_banner.name = "Banner"
	_banner.mouse_filter = Control.MOUSE_FILTER_STOP
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -BANNER_HALF_WIDTH
	_banner.offset_right = BANNER_HALF_WIDTH
	_banner.offset_top = BANNER_TOP
	_banner.offset_bottom = BANNER_TOP + BANNER_HEIGHT
	_banner.gui_input.connect(_on_banner_input)
	_safe.add_child(_banner)
	_banner_label = Label.new()
	_banner_label.name = "BannerLabel"
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", BANNER_FONT_SIZE)
	_banner_label.add_theme_color_override("font_color", Palette.INK)
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_banner_label)
	_banner.visible = false

	# -- Subtitle strip -------------------------------------------------------
	_subtitle = PanelContainer.new()
	_subtitle.name = "Subtitle"
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_subtitle.offset_left = -SUBTITLE_HALF_WIDTH
	_subtitle.offset_right = SUBTITLE_HALF_WIDTH
	_subtitle.offset_top = SUBTITLE_TOP
	_subtitle.offset_bottom = SUBTITLE_TOP + SUBTITLE_HEIGHT
	var subtitle_style: StyleBoxFlat = _pill(Palette.CREAM, 34, Palette.deep(Palette.PEACH))
	subtitle_style.content_margin_left = 30.0
	subtitle_style.content_margin_right = 30.0
	_subtitle.add_theme_stylebox_override("panel", subtitle_style)
	_safe.add_child(_subtitle)
	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.add_theme_font_size_override("font_size", SUBTITLE_FONT_SIZE)
	_subtitle_label.add_theme_color_override("font_color", Palette.INK)
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.add_child(_subtitle_label)
	_subtitle.visible = false

	# -- Flashcard overlay ----------------------------------------------------
	_card = Control.new()
	_card.name = "Flashcard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_card.offset_left = CARD_RIGHT - CARD_WIDTH
	_card.offset_right = CARD_RIGHT
	_card.offset_top = CARD_TOP
	_card.offset_bottom = CARD_TOP + CARD_HEIGHT
	_safe.add_child(_card)
	_card_art = FlashcardArtScript.new()
	_card_art.name = "Art"
	_card_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.add_child(_card_art)
	_card.visible = false

	# -- Home + Mute ----------------------------------------------------------
	_home = _round_button("HomeButton", Palette.HOME_CHROME, HOME_SIZE)
	_home.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_home.offset_left = HOME_RIGHT - HOME_SIZE
	_home.offset_right = HOME_RIGHT
	_home.offset_top = HOME_TOP
	_home.offset_bottom = HOME_TOP + HOME_SIZE
	var house: Control = HouseGlyphScript.new()
	house.name = "HouseGlyph"
	house.set("tint", Palette.INK)
	house.set("face_color", Palette.HOME_CHROME)
	house.set("window_color", Palette.HOME_CHROME)
	house.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	house.offset_left = 16.0
	house.offset_top = 14.0
	house.offset_right = -16.0
	house.offset_bottom = -18.0
	_home.add_child(house)
	_home.pressed.connect(func() -> void: home_pressed.emit())
	_safe.add_child(_home)

	_mute = _round_button("MuteButton", Palette.LAVENDER, MUTE_SIZE)
	_mute.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	var mute_right: float = HOME_RIGHT - HOME_SIZE - MUTE_GAP
	var mute_top: float = HOME_TOP + (HOME_SIZE - MUTE_SIZE) * 0.5
	_mute.offset_left = mute_right - MUTE_SIZE
	_mute.offset_right = mute_right
	_mute.offset_top = mute_top
	_mute.offset_bottom = mute_top + MUTE_SIZE
	_mute_glyph = GlyphsScript.new()
	_mute_glyph.name = "SpeakerGlyph"
	_mute_glyph.set("kind", "speaker")
	_mute_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mute_glyph.offset_left = 14.0
	_mute_glyph.offset_top = 14.0
	_mute_glyph.offset_right = -14.0
	_mute_glyph.offset_bottom = -14.0
	_mute.add_child(_mute_glyph)
	_mute.pressed.connect(toggle_mute)
	_safe.add_child(_mute)

	# -- Microphone group -----------------------------------------------------
	_ring = GlyphsScript.new()
	_ring.name = "ListeningRing"
	_ring.set("kind", "ring")
	# Deep mint, not mint: the rug under the mic is mint, and a mint ring on a
	# mint rug is no ring at all.
	_ring.set("tint", Palette.deep(Palette.MINT))
	_ring.set("active", false)
	_ring.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	var ring_pad: float = 44.0
	_ring.offset_left = -MIC_SIZE * 0.5 - ring_pad
	_ring.offset_right = MIC_SIZE * 0.5 + ring_pad
	_ring.offset_top = MIC_BOTTOM - MIC_SIZE - ring_pad
	_ring.offset_bottom = MIC_BOTTOM + ring_pad
	_safe.add_child(_ring)

	_mic = _round_button("MicButton", Palette.MINT, MIC_SIZE)
	_mic.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_mic.offset_left = -MIC_SIZE * 0.5
	_mic.offset_right = MIC_SIZE * 0.5
	_mic.offset_top = MIC_BOTTOM - MIC_SIZE
	_mic.offset_bottom = MIC_BOTTOM
	var mic_glyph: Control = IconGlyphScript.new()
	mic_glyph.name = "MicGlyph"
	mic_glyph.set("glyph", 4)
	mic_glyph.set("tint", Palette.INK)
	mic_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mic_glyph.offset_left = 52.0
	mic_glyph.offset_top = 46.0
	mic_glyph.offset_right = -52.0
	mic_glyph.offset_bottom = -58.0
	_mic.add_child(mic_glyph)
	_mic.pressed.connect(func() -> void: mic_pressed.emit())
	_safe.add_child(_mic)

	_repeat = _round_button("RepeatButton", Palette.PEACH, SIDE_SIZE)
	_repeat.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_repeat.offset_left = -SIDE_OFFSET - SIDE_SIZE * 0.5
	_repeat.offset_right = -SIDE_OFFSET + SIDE_SIZE * 0.5
	_repeat.offset_top = SIDE_BOTTOM - SIDE_SIZE
	_repeat.offset_bottom = SIDE_BOTTOM
	var play_glyph: Control = IconGlyphScript.new()
	play_glyph.name = "PlayGlyph"
	play_glyph.set("glyph", 3)
	play_glyph.set("tint", Palette.INK)
	play_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	play_glyph.offset_left = 26.0
	play_glyph.offset_top = 22.0
	play_glyph.offset_right = -22.0
	play_glyph.offset_bottom = -26.0
	_repeat.add_child(play_glyph)
	_repeat.pressed.connect(func() -> void: repeat_pressed.emit())
	_safe.add_child(_repeat)

	_card_button = _round_button("CardButton", Palette.SOFT_PINK, SIDE_SIZE)
	_card_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_card_button.offset_left = SIDE_OFFSET - SIDE_SIZE * 0.5
	_card_button.offset_right = SIDE_OFFSET + SIDE_SIZE * 0.5
	_card_button.offset_top = SIDE_BOTTOM - SIDE_SIZE
	_card_button.offset_bottom = SIDE_BOTTOM
	_card_thumb = FlashcardArtScript.new()
	_card_thumb.name = "Thumb"
	_card_thumb.set("show_word", false)
	_card_thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_thumb.offset_left = 26.0
	_card_thumb.offset_top = 18.0
	_card_thumb.offset_right = -26.0
	_card_thumb.offset_bottom = -22.0
	_card_button.add_child(_card_thumb)
	_card_button.pressed.connect(toggle_card)
	_safe.add_child(_card_button)

	# -- Stop, bottom-left ----------------------------------------------------
	_stop = Button.new()
	_stop.name = "StopButton"
	_stop.text = "Stop"
	_stop.focus_mode = Control.FOCUS_NONE
	_stop.add_theme_font_size_override("font_size", 26)
	_stop.add_theme_color_override("font_color", Palette.INK)
	_stop.add_theme_color_override("font_hover_color", Palette.INK)
	_stop.add_theme_color_override("font_pressed_color", Palette.INK)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		_stop.add_theme_stylebox_override(state, _pill(
			Palette.LAVENDER.darkened(0.08) if state == "pressed" else Palette.LAVENDER, int(STOP_HEIGHT * 0.5), Palette.CREAM))
	_stop.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_stop.offset_left = STOP_LEFT
	_stop.offset_right = STOP_LEFT + STOP_WIDTH
	_stop.offset_top = STOP_BOTTOM - STOP_HEIGHT
	_stop.offset_bottom = STOP_BOTTOM
	var back_glyph: Control = IconGlyphScript.new()
	back_glyph.name = "BackGlyph"
	back_glyph.set("glyph", 1)
	back_glyph.set("tint", Palette.INK)
	back_glyph.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	back_glyph.offset_left = 16.0
	back_glyph.offset_top = 14.0
	back_glyph.offset_right = 54.0
	back_glyph.offset_bottom = -14.0
	_stop.add_child(back_glyph)
	_stop.add_theme_constant_override("h_separation", 0)
	_stop.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stop.add_theme_stylebox_override("normal", _pill(Palette.LAVENDER, int(STOP_HEIGHT * 0.5), Palette.CREAM, 22.0))
	_stop.pressed.connect(request_exit)
	_safe.add_child(_stop)

	# -- Dev panel (hidden) ---------------------------------------------------
	_dev_panel = PanelContainer.new()
	_dev_panel.name = "DevPanel"
	_dev_panel.add_theme_stylebox_override("panel", _pill(Palette.light(Palette.LAVENDER), 18, Palette.deep(Palette.LAVENDER)))
	_dev_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_dev_panel.offset_left = -330.0
	_dev_panel.offset_right = -36.0
	_dev_panel.offset_top = -430.0
	_dev_panel.offset_bottom = -200.0
	_safe.add_child(_dev_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_dev_panel.add_child(column)
	var caption: Label = Label.new()
	caption.text = "DEV: simulated transcript"
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Palette.INK_SOFT)
	column.add_child(caption)
	for entry: Array in [["SimCorrect", "Say correct answer", SIM_CORRECT],
			["SimWrong", "Say wrong answer", SIM_WRONG], ["SimNothing", "Say nothing", SIM_NOTHING]]:
		var button: Button = Button.new()
		button.name = String(entry[0])
		button.text = String(entry[1])
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, 52.0)
		button.add_theme_font_size_override("font_size", 22)
		button.add_theme_color_override("font_color", Palette.INK)
		button.add_theme_stylebox_override("normal", _pill(Palette.CREAM, 16, Palette.deep(Palette.LAVENDER)))
		button.add_theme_stylebox_override("hover", _pill(Palette.CREAM, 16, Palette.deep(Palette.LAVENDER)))
		button.add_theme_stylebox_override("pressed", _pill(Palette.LAVENDER, 16, Palette.deep(Palette.LAVENDER)))
		var kind: String = String(entry[2])
		button.pressed.connect(func() -> void: sim_requested.emit(kind))
		column.add_child(button)
	_dev_panel.visible = false

	# -- Exit confirm ---------------------------------------------------------
	_confirm = ExitConfirmScript.new()
	_confirm.call("build")
	_confirm.keep_going.connect(func() -> void: exit_kept.emit())
	_confirm.stop_confirmed.connect(func() -> void: exit_confirmed.emit())
	add_child(_confirm)

	_apply_banner()


# ---------------------------------------------------------------------------
# State the scene drives
# ---------------------------------------------------------------------------

func set_banner(kind: String, text: String = "") -> void:
	build()
	_banner_kind = kind
	if kind != BANNER_NONE:
		_banner_label.text = text if not text.is_empty() else String(BANNER_TEXTS.get(kind, ""))
		_apply_banner()
	_refresh_top_slot()


## What the banner says right now, or "" while it is hidden -- including while
## the subtitle has the top slot.
func banner_text() -> String:
	return _banner_label.text if _banner != null and _banner.visible else ""


## The banner's meaning, whether or not it is currently showing.
func banner_kind() -> String:
	return _banner_kind


func set_subtitle(text: String) -> void:
	build()
	_subtitle_label.text = text
	_refresh_top_slot()


## One slot at the top: the subtitle while Aliz speaks, the banner otherwise.
func _refresh_top_slot() -> void:
	var has_subtitle: bool = not _subtitle_label.text.strip_edges().is_empty()
	_subtitle.visible = has_subtitle
	_banner.visible = _banner_kind != BANNER_NONE and not has_subtitle


func subtitle_text() -> String:
	return _subtitle_label.text if _subtitle != null and _subtitle.visible else ""


func set_listening(listening: bool) -> void:
	build()
	_listening = listening
	_ring.set("active", listening)
	_ring_phase = 0.0
	_ring.set("phase", 0.0)
	_mic.disabled = listening


func is_listening_shown() -> bool:
	return _listening


func set_mic_enabled(enabled: bool) -> void:
	build()
	_mic.disabled = not enabled


func is_mic_enabled() -> bool:
	return _mic != null and not _mic.disabled


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


func set_dev_panel_visible(shown: bool) -> void:
	build()
	_dev_panel.visible = shown


func is_dev_panel_visible() -> bool:
	return _dev_panel != null and _dev_panel.visible


## Every touchable control, by name, for the routing tests.
func buttons() -> Dictionary:
	build()
	return {"home": _home, "mute": _mute, "mic": _mic, "repeat": _repeat, "card": _card_button, "stop": _stop}


func press(button_name: String) -> void:
	var button: Button = buttons().get(button_name, null)
	if button != null and not button.disabled:
		button.pressed.emit()


func press_sim(kind: String) -> void:
	sim_requested.emit(kind)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

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


func _round_button(node_name: String, tint: Color, diameter: float) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = _pill(tint.darkened(0.08) if state == "pressed" else tint, int(diameter * 0.5), Palette.CREAM)
		style.set_border_width_all(4)
		button.add_theme_stylebox_override(state, style)
	# Held (listening): quieter, never greyed to "broken".
	var held: StyleBoxFlat = _pill(tint.lerp(Palette.CREAM, 0.45), int(diameter * 0.5), Palette.CREAM)
	held.set_border_width_all(4)
	button.add_theme_stylebox_override("disabled", held)
	return button


static func _pill(fill: Color, radius: int, rim: Color, left_margin: float = -1.0) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.set_border_width_all(3)
	style.border_color = rim
	if left_margin >= 0.0:
		style.content_margin_left = left_margin
		style.content_margin_right = 22.0
	return style
