extends Control

## Parent Settings, behind a press-and-hold parental gate.
##
## Self-contained and instantiable from anywhere, in two modes:
##
##   * **Overlay** (the pause card, the Baby Room): added under a CanvasLayer of a
##     running scene. While locked it renders nothing but a small, dull gear in a
##     corner and passes every other touch through to the game. Done / Close
##     emit `closed()` and the host takes the overlay down.
##   * **Standalone** (the title screen's Grown-ups button): pushed as the current
##     scene, with nothing underneath. It shows a full gate card -- a big
##     hold-for-3-seconds bar and a Back button -- and when the grown-up is done
##     it returns to the title itself, because there is nobody else to.
##
## ## The freeze this fixes (2026-09-20)
##
## `main.gd` pushes this scene as a full scene. It used to come up in overlay
## mode regardless: the title was freed, the backdrop and panel were hidden, and
## all that was on screen was the 84 px gear in the top-right corner -- on a
## plain clear-colour background, at 38 % alpha. Nothing said "hold me". A tap
## did nothing (the gate needs a 3 s hold), and even a grown-up who found the
## gear and got in pressed Done and landed back on the same empty screen,
## because `closed()` had no listener and nothing navigated. To the owner that
## was "Grown-ups freezes the game". The fix is mode detection plus the gate
## card plus a way home; nothing in `main.gd` had to change.
##
## Offline only: local settings via the SaveService autoload (accessed
## defensively), no analytics, no network.
##
## ## Purchases: there are none, and there is no code here that could make one
##
## This panel now displays what a Family Club subscription WOULD cost, as words,
## to a grown-up, behind the press-and-hold gate. That is the whole of it. There
## is no payment SDK in this project, no StoreKit, no Play Billing, no product id,
## no receipt, no "buy" button and no code path of any kind that can take money.
## The prices are PROPOSED and the annual price does not exist yet. See
## `docs/FAMILY_CLUB.md`, and `test_entitlement_no_purchase_guard.gd`, which fails
## the build if any of that changes by accident.
##
## The one external link in the game (the Songs for Fun channel) also lives here,
## inside the gated panel, revealed only by an explicit grown-up tap, shown as
## text to copy rather than launched into a browser, and unreachable from any
## child-facing screen.

## Preloaded rather than referenced by `class_name`, so this scene parses even
## before the editor has registered the new global classes.
const ParentSettingsModelScript := preload("res://scripts/parent_settings/parent_settings_model.gd")
const SpeechDiagnosticsScript := preload("res://scripts/ui/speech_diagnostics_panel.gd")
const ParentalGateScript := preload("res://scripts/parent_settings/parental_gate.gd")
const Palette := preload("res://scripts/ui/palette.gd")
const FreeStarter := preload("res://scripts/entitlement/free_starter.gd")
const EntitlementServiceScript := preload("res://scripts/entitlement/entitlement_service.gd")
const Localization := preload("res://scripts/localization/localization.gd")
const HelperFont := preload("res://scripts/localization/helper_font.gd")
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")
const QuotaConfig := preload("res://scripts/tutor/quota/quota_config.gd")
const TutorQuotaScript := preload("res://scripts/tutor/quota/tutor_quota.gd")
const VoiceOptions := preload("res://scripts/parent_settings/voice_options.gd")
const LearningHistory := preload("res://scripts/parent_settings/learning_history.gd")

## Where a standalone panel goes when it is done.
const HOME_SCENE: String = "res://scenes/main/main.tscn"

## Helper-language buttons in the scene, by node name -> language code. Static in
## the .tscn (rather than built in code) so the contrast test can see their
## colours; `test_parent_settings_screen.gd` asserts this list matches
## `Localization.available_languages()` so a language cannot be added to one and
## not the other.
const HELPER_BUTTONS: Dictionary = {
	"HelperOffButton": Localization.HELPER_OFF,
	"HelperThButton": "th",
	"HelperZhButton": "zh",
	"HelperArButton": "ar",
	"HelperHiButton": "hi",
	"HelperJaButton": "ja",
}

## Settings rows whose small helper subtitle is shown in the chosen language.
## Row name -> Localization key.
const ROW_HELPER_KEYS: Dictionary = {
	"Music": "music_volume",
	"VoiceVolume": "voice_volume",
	"AlizVoice": "aliz_voice",
	"BunnyVoice": "bunny_voice",
	"Voice": "voice_practice",
	"Speed": "speaking_speed",
	"Helper": "helper_language",
	"Teaching": "teaching_language",
	"Session": "play_session_reminder",
}

## The play-session reminder buttons, by node name -> minutes (0 = Off).
const SESSION_BUTTONS: Dictionary = {
	"SessionOffButton": 0,
	"Session5Button": 5,
	"Session10Button": 10,
	"Session15Button": 15,
}

## Emitted when the grown-up taps Done (or the settings panel is closed).
signal closed()
## Emitted once the gate has been held long enough and the panel is showing.
signal opened()
## Emitted when the grown-up asks to leave without opening (the gate card's
## Back button). A standalone panel then goes home by itself.
signal back_requested()

## When false the panel is shown immediately with no gate -- for callers that
## push this as a full scene from their own (already gated) entry point.
@export var show_gate: bool = true

var _model: ParentSettingsModelScript
var _syncing: bool = false
## True when this scene IS the current scene (pushed by the title screen), as
## opposed to an overlay inside a running room. Decided once, in `_ready()`.
var _standalone: bool = false
var _going_home: bool = false
## Overlay hosts that opened this on an explicit "Grown-ups" press (the pause
## card) ask for the full gate card instead of the corner gear, so the grown-up
## sees what to hold and has a Back. The Baby Room keeps the gear.
var _card_requested: bool = false

@onready var _entry_gate: ParentalGateScript = %EntryGate
@onready var _gate_screen: Control = %GateScreen
@onready var _gate_hold: ParentalGateScript = %GateHold
@onready var _gate_hold_label: Label = %GateHoldLabel
@onready var _gate_back_button: Button = %GateBackButton
@onready var _backdrop: ColorRect = %Backdrop
@onready var _scroll: ScrollContainer = %Center
@onready var _panel: PanelContainer = %Panel
@onready var _close_button: Button = %CloseButton
@onready var _music_slider: HSlider = %MusicSlider
@onready var _music_value: Label = %MusicValue
@onready var _voice_volume_slider: HSlider = %VoiceVolumeSlider
@onready var _voice_volume_value: Label = %VoiceVolumeValue
@onready var _aliz_voice_slider: HSlider = %AlizVoiceSlider
@onready var _aliz_voice_value: Label = %AlizVoiceValue
@onready var _bunny_voice_slider: HSlider = %BunnyVoiceSlider
@onready var _bunny_voice_value: Label = %BunnyVoiceValue
@onready var _session_buttons: Control = %SessionButtons
@onready var _helper_buttons: Control = %HelperButtons
@onready var _teaching_en: Button = %TeachingEnButton
@onready var _voice_on: Button = %VoiceOnButton
@onready var _voice_off: Button = %VoiceOffButton
@onready var _speed_slow: Button = %SpeedSlowButton
@onready var _speed_normal: Button = %SpeedNormalButton
@onready var _stars_label: Label = %StarsLabel
@onready var _reset_row: Control = %ResetRow
@onready var _reset_button: Button = %ResetButton
@onready var _confirm_box: VBoxContainer = %ConfirmBox
@onready var _confirm_hold: ParentalGateScript = %ConfirmHold
@onready var _cancel_reset_button: Button = %CancelResetButton
@onready var _status_label: Label = %StatusLabel
@onready var _done_button: Button = %DoneButton
var _speech_check: Control = null
var _speech_check_button: Button = null


## The SaveService autoload, or null.
##
## Resolved RELATIVE to the tree root rather than as the absolute path
## `/root/SaveService`: an absolute lookup is an engine error ("can't use
## get_node() with absolute paths from outside the active scene tree") whenever
## this panel is instantiated outside the running scene -- a scene preview, or a
## test that drives the real panel. Same node, same "null is fine" contract, no
## error in the log.
func _save_service() -> Node:
	return _autoload("SaveService")


## The running SceneTree, whether or not this node counts as "inside" it yet.
## Under the `--script` runner a node added to the root during `_initialize()`
## reports `is_inside_tree() == false` while its `_ready()` has already run, so
## `get_tree()` cannot be relied on; the main loop can.
static func _scene_tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _ready() -> void:
	_model = ParentSettingsModelScript.new(_save_service())
	_standalone = _detect_standalone()

	_entry_gate.unlocked.connect(_on_gate_unlocked)
	_gate_hold.unlocked.connect(_on_gate_unlocked)
	_gate_back_button.pressed.connect(_on_back_pressed)
	_confirm_hold.unlocked.connect(_on_reset_confirmed)
	_done_button.pressed.connect(_on_done_pressed)
	_close_button.pressed.connect(_on_done_pressed)
	_reset_button.pressed.connect(_on_reset_requested)
	_cancel_reset_button.pressed.connect(_hide_reset_confirmation)
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_voice_volume_slider.value_changed.connect(_on_voice_volume_changed)
	_aliz_voice_slider.value_changed.connect(_on_aliz_voice_volume_changed)
	_bunny_voice_slider.value_changed.connect(_on_bunny_voice_volume_changed)
	for node_name: String in SESSION_BUTTONS.keys():
		var session_button: Button = _session_buttons.get_node_or_null(NodePath(node_name)) as Button
		if session_button != null:
			session_button.pressed.connect(_on_session_reminder_chosen.bind(int(SESSION_BUTTONS[node_name])))
	for node_name: String in HELPER_BUTTONS.keys():
		var button: Button = _helper_buttons.get_node_or_null(NodePath(node_name)) as Button
		if button != null:
			button.pressed.connect(_on_helper_language_chosen.bind(String(HELPER_BUTTONS[node_name])))
			# The native names are in their own scripts; the helper font is the
			# one chain proven to draw them all, and a language this device has no
			# font for is offered as unavailable rather than as tofu.
			HelperFont.apply(button)
			var code: String = String(HELPER_BUTTONS[node_name])
			if code != Localization.HELPER_OFF and not HelperFont.language_available(code):
				button.disabled = true
				button.tooltip_text = "Not available on this device"
	HelperFont.apply(_gate_hold_label)
	for row_name: String in ROW_HELPER_KEYS.keys():
		var label: Label = get_node_or_null(
				NodePath("SafeArea/Center/Panel/Margin/Content/%sRow/%sText/%sHelper" % [row_name, row_name, row_name])) as Label
		if label != null:
			HelperFont.apply(label)
	_voice_on.pressed.connect(_on_voice_chosen.bind(true))
	_voice_off.pressed.connect(_on_voice_chosen.bind(false))
	_speed_slow.pressed.connect(_on_speed_chosen.bind(ParentSettingsModelScript.TTS_SPEED_SLOW))
	_speed_normal.pressed.connect(_on_speed_chosen.bind(ParentSettingsModelScript.TTS_SPEED_NORMAL))

	_build_speech_check()
	_build_qa_replay()
	_build_learn_with_aliz()
	_build_family_club()

	if show_gate:
		_show_locked()
	else:
		open_settings()
	# The gate card's hold instruction carries the family's language too.
	Localization.set_helper_language(_model.get_helper_language())
	_refresh_row_helpers()


## A panel with nothing underneath it: added straight under the tree root, the
## way `main.gd` pushes a scene. An overlay lives under a room's CanvasLayer.
func _detect_standalone() -> bool:
	var tree: SceneTree = _scene_tree()
	return tree != null and tree.root != null and get_parent() == tree.root


func is_standalone() -> bool:
	return _standalone


## Forces the mode. For a harness that hosts the panel in a SubViewport (so it
## cannot be under the root) and wants the standalone gate card photographed.
func set_standalone(value: bool) -> void:
	_standalone = value
	if not _panel.visible:
		_show_locked()


## Shows the gate card (hold bar + Back) rather than the corner gear, for an
## overlay host that was asked for Grown-ups explicitly. Back emits `closed()`
## so the host takes the overlay down and gives the room back.
func show_gate_card() -> void:
	_card_requested = true
	if _panel == null:
		# Asked before the scene is in the tree: _ready() shows the card itself.
		return
	if not _panel.visible:
		_show_locked()


## Back / Escape at any time: the same as Done when the panel is open, the same
## as the gate card's Back when it is not. Nothing here can trap a grown-up.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _panel.visible:
			close_settings()
			get_viewport().set_input_as_handled()
		elif _standalone:
			_on_back_pressed()
			get_viewport().set_input_as_handled()


## The on-device speech check, behind the parental gate.
##
## Added in code rather than in the .tscn so the panel stays one file to
## maintain and cannot drift from `speech_diagnostics_panel.gd`'s row list.
## Collapsed by default: a parent looking for Thai hints should not have to
## scroll past a diagnostic, and a child who gets in here should find settings,
## not a debug screen.
func _build_speech_check() -> void:
	if _status_label == null:
		return
	var parent: Node = _status_label.get_parent()
	if parent == null:
		return

	_speech_check_button = Button.new()
	_speech_check_button.name = "SpeechCheckButton"
	_speech_check_button.text = "Check speech"
	_style_secondary_button(_speech_check_button)
	_speech_check_button.pressed.connect(_on_speech_check_toggled)
	parent.add_child(_speech_check_button)
	parent.move_child(_speech_check_button, _status_label.get_index())

	_speech_check = SpeechDiagnosticsScript.new()
	_speech_check.name = "SpeechCheck"
	_speech_check.custom_minimum_size = Vector2(0.0, 420.0)
	_speech_check.visible = false
	parent.add_child(_speech_check)
	parent.move_child(_speech_check, _speech_check_button.get_index() + 1)


func _on_speech_check_toggled() -> void:
	if _speech_check == null:
		return
	_speech_check.visible = not _speech_check.visible
	if _speech_check.visible and _speech_check.has_method("refresh"):
		_speech_check.call("refresh")
	_speech_check_button.text = "Hide speech check" if _speech_check.visible else "Check speech"


## True while the diagnostic is on screen. Used by the test to assert it is
## hidden by default -- it is a tool, and a tool must not greet a child.
func is_speech_check_visible() -> bool:
	return _speech_check != null and _speech_check.visible


## ---------------------------------------------------------------------------
## QA: replay one mission
## ---------------------------------------------------------------------------

## The level the QA button re-arms. The FIRST level of the house chapter, asked
## for rather than hard-coded, so this cannot drift from `chapters.json` the way
## two other assertions in this repo already have.
const QA_CHAPTER_ID: String = "ch3"

var _qa_replay_button: Button = null
var _qa_replay_level: String = ""


## "Replay Mission 01", behind the same parental gate as everything else on this
## panel -- it is built into the gated body, so a child never reaches it.
##
## It does NOT reset the profile. It clears exactly one level's completion and
## rating (see `scripts/qa/mission_replay.gd`) and leaves the child's star total,
## settings and every other level alone, which is what makes it safe to ship
## rather than something that has to be stripped before release.
func _build_qa_replay() -> void:
	if _status_label == null:
		return
	var parent: Node = _status_label.get_parent()
	if parent == null:
		return

	_qa_replay_level = _first_house_level()
	if _qa_replay_level.is_empty():
		return

	_qa_replay_button = Button.new()
	_qa_replay_button.name = "QaReplayButton"
	_qa_replay_button.text = "Replay Mission 01"
	_style_secondary_button(_qa_replay_button)
	_qa_replay_button.pressed.connect(_on_qa_replay_pressed)
	parent.add_child(_qa_replay_button)
	parent.move_child(_qa_replay_button, _status_label.get_index())


## Chapter 3's first chained level, read from content.
func _first_house_level() -> String:
	var library: Object = load("res://scripts/content/content_library.gd").new()
	library.call("load_all")
	var system: Object = load("res://scripts/progression/level_system.gd").new()
	system.call("load_all", library)
	var chain: PackedStringArray = system.call("get_chapter_chain", QA_CHAPTER_ID)
	return chain[0] if chain.size() > 0 else ""


func _on_qa_replay_pressed() -> void:
	var service: Node = _save_service()
	if service == null or not service.has_method("replay_level"):
		_set_status("Replay is unavailable: no save service.")
		return
	var replay: GDScript = load("res://scripts/qa/mission_replay.gd")
	var before: Dictionary = service.call("get_profile")
	service.call("replay_level", _qa_replay_level)
	# Reported from the BEFORE profile, so the line describes what was actually
	# cleared rather than restating the request.
	_set_status(replay.describe(before, _qa_replay_level))


## The level the button will re-arm, for the test.
func qa_replay_level_id() -> String:
	return _qa_replay_level


## ---------------------------------------------------------------------------
## Family Club -- information for a grown-up. Nothing to buy.
## ---------------------------------------------------------------------------

## What a family gets, and what the club WOULD cost. Read as data so the screen
## cannot describe a different offer from the one recorded in `docs/FAMILY_CLUB.md`.
##
## PRICES ARE PROPOSED, NOT FINAL. There is deliberately **no annual price**: one
## has not been decided, and a made-up number on a parent's screen is worse than
## no number at all. Two monthly prices are listed because Thailand is the launch
## market and USD 2.99 is not what that should cost there.
const PRICE_MONTHLY_USD: String = "USD 2.99 / month"

## Every line the section prints, in order. Plain, factual, grown-up copy: no
## urgency, no scarcity, no "unlock", nothing addressed to a child. The Thai
## monthly price is NOT written here: it is read from the one config file
## (`content/tutor/quota_config.json`, `pricingProposed`) so gameplay code and
## this screen can never quote two different numbers.
static func family_club_lines() -> PackedStringArray:
	var thai: String = QuotaConfig.pricing_line()
	var lines: PackedStringArray = PackedStringArray([
		"Free Starter -- free forever, no account needed.",
		"Family Club (proposed) -- " + PRICE_MONTHLY_USD,
	])
	if not thai.is_empty():
		lines.append("Thailand -- " + thai)
	lines.append_array(PackedStringArray([
		"Annual pricing is not decided yet, so there is none to show.",
		"Nothing can be bought in this app. This build has no payment of any kind; "
				+ "these prices are information only.",
		"Your child's game is never interrupted to ask for money, and Buddy is never "
				+ "sad about a subscription.",
	]))
	return lines

## The one external link in the product. A free YouTube channel, for a parent, on
## a parent's own terms:
##
##   * it is inside the gated panel, so a child never reaches it;
##   * it is hidden until a grown-up taps "Songs for Fun";
##   * it is SHOWN AS TEXT and copied to the clipboard on a second, confirming
##     tap -- this build never calls `OS.shell_open()`, so the game cannot hand a
##     child to a browser, an autoplaying video or a recommendation feed;
##   * nothing about it is ever spoken, animated or offered during play.
const SONGS_FOR_FUN_TITLE: String = "Songs for Fun"
const SONGS_FOR_FUN_URL: String = "https://www.youtube.com/@Songsforfun-1"
const SONGS_FOR_FUN_BLURB: String = ("Free songs on YouTube, made by the same people. "
		+ "It does not open here: copy the link and open it yourself, on your own device, "
		+ "when your child is not playing.")

const SECTION_TITLE_FONT_SIZE: int = 30
const SECTION_BODY_FONT_SIZE: int = 20

## The same re-paletted Kenney frames the scene's own buttons use, for the
## buttons this script builds (speech check, replay, Songs for Fun), so they
## stop looking like engine defaults dropped into a cream panel.
const SECONDARY_BUTTON_NORMAL: StyleBox = preload("res://assets/ui/styles/small/btn_cream.tres")
const SECONDARY_BUTTON_PRESSED: StyleBox = preload("res://assets/ui/styles/small/btn_cream_flat.tres")
const SECONDARY_BUTTON_FONT_SIZE: int = 26
const SECONDARY_BUTTON_HEIGHT: float = 72.0
const SECONDARY_BUTTON_INK: Color = Color(0.36, 0.29, 0.19, 1)


## Cream frame, readable ink in every state, a grown-up-sized height.
static func _style_secondary_button(button: Button) -> void:
	if button == null:
		return
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, SECONDARY_BUTTON_HEIGHT)
	button.add_theme_font_size_override("font_size", SECONDARY_BUTTON_FONT_SIZE)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, SECONDARY_BUTTON_INK)
	for state: String in ["normal", "hover", "focus"]:
		button.add_theme_stylebox_override(state, SECONDARY_BUTTON_NORMAL)
	button.add_theme_stylebox_override("pressed", SECONDARY_BUTTON_PRESSED)

var _family_club_box: VBoxContainer = null
var _songs_button: Button = null
var _songs_box: VBoxContainer = null
var _songs_copy_button: Button = null
var _songs_copy_armed: bool = false
## Read-only, so the section can state what the family actually has rather than
## what a hard-coded string claims. Provider-neutral and offline: in this build it
## grants Free Starter and nothing else, and it cannot be asked to buy anything
## because it has no such method.
var _entitlements: Object = null


## Built in code rather than in the .tscn for the same reason as the speech check:
## the copy, the prices and the rules about them live in one file that can be
## reviewed as a whole, instead of being split between a script and a scene where
## the two can drift.
func _build_family_club() -> void:
	if _status_label == null:
		return
	var parent: Node = _status_label.get_parent()
	if parent == null:
		return

	if _entitlements == null:
		_entitlements = EntitlementServiceScript.new()

	_family_club_box = VBoxContainer.new()
	_family_club_box.name = "FamilyClubBox"
	_family_club_box.add_theme_constant_override("separation", 6)
	parent.add_child(_family_club_box)
	parent.move_child(_family_club_box, _status_label.get_index())

	_family_club_box.add_child(HSeparator.new())

	var title := Label.new()
	title.name = "FamilyClubTitle"
	title.text = "Family Club"
	title.add_theme_font_size_override("font_size", SECTION_TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", Palette.INK)
	_family_club_box.add_child(title)

	var included := Label.new()
	included.name = "FreeStarterLabel"
	included.text = FreeStarter.summary_line()
	_style_body(included)
	_family_club_box.add_child(included)

	for line: String in family_club_lines():
		var label := Label.new()
		label.text = line
		_style_body(label)
		_family_club_box.add_child(label)

	# -- Songs for Fun ------------------------------------------------------
	_songs_button = Button.new()
	_songs_button.name = "SongsForFunButton"
	_songs_button.text = SONGS_FOR_FUN_TITLE
	_style_secondary_button(_songs_button)
	_songs_button.pressed.connect(_on_songs_for_fun_toggled)
	_family_club_box.add_child(_songs_button)

	_songs_box = VBoxContainer.new()
	_songs_box.name = "SongsForFunBox"
	_songs_box.visible = false
	_family_club_box.add_child(_songs_box)

	var blurb := Label.new()
	blurb.name = "SongsForFunBlurb"
	blurb.text = SONGS_FOR_FUN_BLURB
	_style_body(blurb)
	_songs_box.add_child(blurb)

	var link := Label.new()
	link.name = "SongsForFunUrl"
	link.text = SONGS_FOR_FUN_URL
	_style_body(link)
	_songs_box.add_child(link)

	_songs_copy_button = Button.new()
	_songs_copy_button.name = "SongsForFunCopyButton"
	_songs_copy_button.text = "Copy link"
	_style_secondary_button(_songs_copy_button)
	_songs_copy_button.pressed.connect(_on_songs_copy_pressed)
	_songs_box.add_child(_songs_copy_button)


func _style_body(label: Label) -> void:
	label.add_theme_font_size_override("font_size", SECTION_BODY_FONT_SIZE)
	label.add_theme_color_override("font_color", Palette.INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(520.0, 0.0)


## Step 1: a grown-up asks to see the link. Collapsed again the moment the panel
## closes, so it is never sitting open behind the gear.
func _on_songs_for_fun_toggled() -> void:
	if _songs_box == null:
		return
	_songs_box.visible = not _songs_box.visible
	_disarm_songs_copy()
	_songs_button.text = ("Hide " + SONGS_FOR_FUN_TITLE) if _songs_box.visible \
			else SONGS_FOR_FUN_TITLE


## Step 2, and step 3: copying needs a second, confirming tap, and even then the
## link only reaches the clipboard. The game never opens it.
func _on_songs_copy_pressed() -> void:
	if not _songs_copy_armed:
		_songs_copy_armed = true
		_songs_copy_button.text = "Tap again to copy the link"
		_set_status("")
		return
	DisplayServer.clipboard_set(SONGS_FOR_FUN_URL)
	_disarm_songs_copy()
	_set_status("Link copied. Open it in your own browser, not here.")


func _disarm_songs_copy() -> void:
	_songs_copy_armed = false
	if _songs_copy_button != null:
		_songs_copy_button.text = "Copy link"


func _collapse_songs_for_fun() -> void:
	if _songs_box != null:
		_songs_box.visible = false
	if _songs_button != null:
		_songs_button.text = SONGS_FOR_FUN_TITLE
	_disarm_songs_copy()


## -- read-only accessors, for the tests ------------------------------------

func songs_for_fun_url() -> String:
	return SONGS_FOR_FUN_URL


## True only when the link is actually on screen: the gated panel is showing AND a
## grown-up has tapped to reveal it.
func is_songs_for_fun_visible() -> bool:
	if _songs_box == null or not _songs_box.visible:
		return false
	return _panel != null and _panel.visible


## True when the informational section is on screen (i.e. the panel is unlocked).
func is_family_club_visible() -> bool:
	if _family_club_box == null or not _family_club_box.visible:
		return false
	return _panel != null and _panel.visible


## The provider-neutral entitlement service this panel reads. Exposed so a test
## can assert what it grants -- and that it has no way to buy anything.
func entitlement_service() -> Object:
	return _entitlements


## Opens the panel directly, bypassing the gate (for callers with their own
## grown-up entry point).
func open_settings() -> void:
	_entry_gate.visible = false
	_gate_screen.visible = false
	_backdrop.visible = true
	_scroll.visible = true
	_panel.visible = true
	_scroll.scroll_vertical = 0
	_hide_reset_confirmation()
	_collapse_songs_for_fun()
	_collapse_learn_with_aliz()
	_set_status("")
	_sync_from_model()
	opened.emit()


## Returns to the locked state and emits `closed()`. A standalone panel then
## goes home to the title, because a grown-up who pressed Done is finished here
## and there is no scene underneath to come back to.
func close_settings() -> void:
	_show_locked()
	closed.emit()
	if _standalone:
		_go_home()


func _show_locked() -> void:
	_entry_gate.reset()
	_gate_hold.reset()
	var card: bool = _standalone or _card_requested
	_entry_gate.visible = show_gate and not card
	_gate_screen.visible = show_gate and card
	# Standalone there is nothing behind us: the backdrop stays, so the gate card
	# sits on cream rather than on the bare clear colour. An overlay's card sits
	# on the same cream over the paused room.
	_backdrop.visible = card
	_scroll.visible = false
	_panel.visible = false
	_hide_reset_confirmation()
	# The external link never survives a close: locking the panel puts it away.
	_collapse_songs_for_fun()
	_collapse_learn_with_aliz()


func _on_gate_unlocked() -> void:
	open_settings()


func _on_done_pressed() -> void:
	close_settings()


## The gate card's Back: leave without opening anything.
func _on_back_pressed() -> void:
	back_requested.emit()
	if _standalone:
		_go_home()
	elif _card_requested:
		# The host removes the overlay on `closed()`, exactly as after Done.
		closed.emit()


## Replaces this scene with the title. Deferred, so it never happens in the
## middle of the button signal that asked for it, and once only.
##
## A SceneTree that runs a script -- the headless test runner, a screenshot
## harness -- owns its own navigation, and here that call is skipped: the
## harness asked for this panel and is the one that takes it down.
func _go_home() -> void:
	if _going_home:
		return
	var tree: SceneTree = _scene_tree()
	if tree == null or tree.get_script() != null:
		return
	if not ResourceLoader.exists(HOME_SCENE):
		return
	_going_home = true
	tree.call_deferred("change_scene_to_file", HOME_SCENE)


## True while the standalone gate card is showing. Tests.
func is_gate_card_visible() -> bool:
	return _gate_screen != null and _gate_screen.visible


## True while the settings panel itself is on screen. Tests.
func is_panel_visible() -> bool:
	return _panel != null and _panel.visible


# -- settings ----------------------------------------------------------------

func _sync_from_model() -> void:
	_syncing = true
	var helper_language: String = _model.get_helper_language()
	Localization.set_helper_language(helper_language)
	for node_name: String in HELPER_BUTTONS.keys():
		var button: Button = _helper_buttons.get_node_or_null(NodePath(node_name)) as Button
		if button != null:
			button.set_pressed_no_signal(String(HELPER_BUTTONS[node_name]) == helper_language)
	_teaching_en.set_pressed_no_signal(true)
	_music_slider.set_value_no_signal(_model.get_music_volume())
	_music_value.text = _percent(_model.get_music_volume())
	_voice_volume_slider.set_value_no_signal(_model.get_voice_volume())
	_voice_volume_value.text = _percent(_model.get_voice_volume())
	_aliz_voice_slider.set_value_no_signal(_model.get_aliz_voice_volume())
	_aliz_voice_value.text = _percent(_model.get_aliz_voice_volume())
	_bunny_voice_slider.set_value_no_signal(_model.get_bunny_voice_volume())
	_bunny_voice_value.text = _percent(_model.get_bunny_voice_volume())
	var reminder: int = _model.get_session_reminder_minutes()
	for node_name: String in SESSION_BUTTONS.keys():
		var session_button: Button = _session_buttons.get_node_or_null(NodePath(node_name)) as Button
		if session_button != null:
			session_button.set_pressed_no_signal(int(SESSION_BUTTONS[node_name]) == reminder)
	_refresh_row_helpers()
	var voice: bool = _model.get_speech_enabled()
	_voice_on.button_pressed = voice
	_voice_off.button_pressed = not voice
	var slow: bool = _model.is_tts_slow()
	_speed_slow.button_pressed = slow
	_speed_normal.button_pressed = not slow
	var stars: int = _model.get_stars()
	_stars_label.text = "%d star earned" % stars if stars == 1 else "%d stars earned" % stars
	_refresh_learn_with_aliz()
	_syncing = false


func _on_helper_language_chosen(code: String) -> void:
	if _syncing:
		return
	_model.set_helper_language(code)
	_refresh_row_helpers()


## The small second line under each row title, in the chosen helper language --
## the same thing the child sees under an English prompt, applied to the
## parent's own screen so a Thai (or Japanese, or Arabic) grown-up can read
## what each control does. Hidden when the helper is off.
func _refresh_row_helpers() -> void:
	var content: Node = _status_label.get_parent() if _status_label != null else null
	if content == null:
		return
	var rtl: bool = Localization.is_rtl()
	for row_name: String in ROW_HELPER_KEYS.keys():
		var label: Label = content.get_node_or_null(
				NodePath("%sRow/%sText/%sHelper" % [row_name, row_name, row_name])) as Label
		if label == null:
			continue
		var text: String = Localization.helper(String(ROW_HELPER_KEYS[row_name]), "")
		label.text = text
		label.visible = not text.is_empty()
		label.text_direction = Control.TEXT_DIRECTION_RTL if rtl else Control.TEXT_DIRECTION_AUTO
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if rtl else HORIZONTAL_ALIGNMENT_LEFT
	# The gate card's own helper, so the hold instruction is readable too.
	var hold_hint: String = Localization.helper("hold_for_3_seconds_to_open", "")
	_gate_hold_label.text = "Hold for 3 seconds to open" \
			if hold_hint.is_empty() else "Hold for 3 seconds to open\n%s" % hold_hint


## -- volumes -------------------------------------------------------------------

## The music slider, applied live through the `Audio` autoload (`AudioDirector`)
## and persisted as `musicVolume` 0..1. `slider_to_db` puts the bottom of the
## slider at a true mute (-40 dB floor -> off) rather than a whisper.
func _on_music_volume_changed(value: float) -> void:
	if _syncing:
		return
	_model.set_music_volume(value)
	_music_value.text = _percent(value)
	var audio: Node = _autoload("Audio")
	if audio != null and audio.has_method("set_music_volume_linear"):
		audio.call("set_music_volume_linear", value)


## The voice slider: TTS volume (and any bundled voice line) through
## `TtsService`, persisted as `voiceVolume` 0..1.
func _on_voice_volume_changed(value: float) -> void:
	if _syncing:
		return
	_model.set_voice_volume(value)
	_voice_volume_value.text = _percent(value)
	var tts: Node = _autoload("TtsService")
	if tts != null and tts.has_method("set_voice_volume"):
		tts.call("set_voice_volume", value)


## Aliz's own level: the voice director when there is one
## (`/root/Voice.set_character_volume("aliz", v)`), and until then the single
## TTS level, so the slider always does something audible.
func _on_aliz_voice_volume_changed(value: float) -> void:
	if _syncing:
		return
	_model.set_aliz_voice_volume(value)
	_aliz_voice_value.text = _percent(value)
	if _apply_character_volume("aliz", value):
		return
	var tts: Node = _autoload("TtsService")
	if tts != null and tts.has_method("set_voice_volume"):
		tts.call("set_voice_volume", value)


## Bunny's own level: the voice director when there is one; persisted either way.
func _on_bunny_voice_volume_changed(value: float) -> void:
	if _syncing:
		return
	_model.set_bunny_voice_volume(value)
	_bunny_voice_value.text = _percent(value)
	_apply_character_volume("bunny", value)


## True when a voice director took the level.
func _apply_character_volume(character: String, value: float) -> bool:
	var voice: Node = _autoload("Voice")
	if voice == null or not voice.has_method("set_character_volume"):
		return false
	voice.call("set_character_volume", character, value)
	return true


## The play-session reminder: persisted, and applied to the running clock at
## once (it re-reads the setting anyway; this makes the change immediate).
func _on_session_reminder_chosen(minutes: int) -> void:
	if _syncing:
		return
	_model.set_session_reminder_minutes(minutes)
	var session: Node = _autoload("PlaySession")
	if session != null and session.has_method("set_threshold_minutes"):
		session.call("set_threshold_minutes", minutes)


## The reminder buttons' minutes, by node name. Tests.
func session_button_minutes() -> Dictionary:
	return SESSION_BUTTONS.duplicate()


static func _percent(value: float) -> String:
	return "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))


## An autoload by name, resolved relative to the tree root so a detached panel
## (a preview, a test) gets null instead of an engine error.
func _autoload(node_name: String) -> Node:
	var tree: SceneTree = _scene_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(node_name))


## The language code each helper button selects. Tests.
func helper_button_languages() -> Dictionary:
	return HELPER_BUTTONS.duplicate()


## Languages the selector offers but this device cannot draw. Tests, runbook.
func unavailable_languages() -> Array:
	var out: Array = []
	for code: Variant in HELPER_BUTTONS.values():
		if String(code) != Localization.HELPER_OFF and not HelperFont.language_available(String(code)):
			out.append(String(code))
	return out


## The model behind the controls. Tests.
func model() -> RefCounted:
	return _model


func _on_voice_chosen(enabled: bool) -> void:
	if _syncing:
		return
	_model.set_speech_enabled(enabled)


func _on_speed_chosen(speed: String) -> void:
	if _syncing:
		return
	_model.set_tts_speed(speed)


# -- reset progress ----------------------------------------------------------

func _on_reset_requested() -> void:
	# Step 1 of 2: reveal the confirmation. Nothing is erased yet.
	_set_status("")
	_confirm_box.visible = true
	_confirm_hold.reset()
	# Swapped out rather than greyed out: the panel sizes itself to its content,
	# and leaving a dead button above the confirmation only made it taller.
	_reset_row.visible = false


func _hide_reset_confirmation() -> void:
	_confirm_box.visible = false
	_confirm_hold.reset()
	_reset_row.visible = true


func _on_reset_confirmed() -> void:
	# Step 2 of 2: only a deliberate multi-second hold gets here.
	_model.reset_progress()
	_hide_reset_confirmation()
	_sync_from_model()
	_set_status("Progress reset. Stars and stickers are back to zero.")


## Hidden when empty so an empty label never reserves a gap in the panel.
func _set_status(text: String) -> void:
	_status_label.text = text
	_status_label.visible = not text.is_empty()


## ---------------------------------------------------------------------------
## Learn with Aliz -- the AI tutor's grown-up controls. Behind the gate.
## ---------------------------------------------------------------------------
##
## Built in code, like the Family Club section, so the copy and the rules live in
## one reviewable file. Everything here is information or a grown-up switch:
## there is no purchase, no link, no upload. The cloud tutor is gated by
## `TutorFlags.cloud_enabled()`, which no row on this screen can turn on.

const ALIZ_SECTION_TITLE: String = "Learn with Aliz"
const ALIZ_TUTOR_HELP: String = ("Short English lessons with Aliz, on this device. "
		+ "Off hides Learn with Aliz from the title screen.")
const ALIZ_CLOUD_OFF_TEXT: String = "Cloud tutor: not available in this build."
const ALIZ_CLOUD_ON_TEXT: String = "Cloud tutor: enabled for this developer run."
const ALIZ_ALLOWANCE_HELP: String = "Aliz's lesson time counts only while a lesson is running."
const ALIZ_MIC_NOT_CHECKED: String = "Not checked"
const ALIZ_MIC_ALLOWED: String = "Allowed"
const ALIZ_MIC_NOT_ALLOWED: String = "Not allowed (tapping always works)"
const ALIZ_LANGUAGE_FIXED: String = "English"
const ALIZ_LANGUAGE_HELP: String = "Fixed to English in this version."
const ALIZ_VOICE_NOTE: String = ("Aliz's loudness is the Voice volume and Aliz voice sliders above; "
		+ "they apply to lessons too.")
const ALIZ_HANDS_FREE_HELP: String = ("Aliz listens for the whole lesson and answers when your child "
		+ "stops talking. Off: your child taps to talk.")
const ALIZ_VOICE_HELP: String = "The voice Aliz speaks with in lessons."
const ALIZ_HISTORY_TITLE: String = "Learning history"
const ALIZ_HISTORY_HELP: String = "Lessons your child has finished with Aliz."
## The in-app privacy text, verbatim from docs/ALIZ_TUTOR_PARENT_INFO.md
## (Agent G): a static label, no button, no link. The sentence "The online AI
## tutor is switched off in this build." is the claim the privacy guards keep
## true and must not be shortened.
const ALIZ_PRIVACY_TITLE: String = "Privacy information"
const ALIZ_PRIVACY_LINES: Array[String] = [
	"Learn with Aliz runs on this device. Lessons, pictures and Aliz's voice are built into "
			+ "the app. During a lesson the device's own speech recognition listens for your child's "
			+ "answers and stops when the lesson ends. Nothing is recorded, saved or sent anywhere: no audio, "
			+ "no words your child says, no name, no location.",
	"The app keeps only stars, lesson progress and today's tutor minutes, stored on this device. "
			+ "You can erase them from Parent Corner at any time.",
	"The online AI tutor is switched off in this build. It cannot be turned on from the app. "
			+ "If a future version offers it, we will ask a parent first and explain exactly what "
			+ "would be shared.",
]
## The Thai helper block from the same document, shown under the English when
## the family's helper language is Thai.
const ALIZ_PRIVACY_LINES_TH: Array[String] = [
	"เรียนกับอลิซทำงานบนเครื่องนี้ทั้งหมด บทเรียน รูปภาพ และเสียงของอลิซถูกบรรจุมาในแอป "
			+ "ระหว่างบทเรียน ระบบรู้จำเสียงของตัวเครื่องจะฟังคำตอบของลูก และหยุดฟังเมื่อจบบทเรียน "
			+ "ไม่มีการบันทึกเสียง ไม่เก็บคำที่ลูกพูด ไม่ส่งข้อมูลใด ๆ ออกไป ไม่มีชื่อ ไม่มีตำแหน่งที่อยู่",
	"แอปเก็บเพียงดาว ความคืบหน้าของบทเรียน และเวลาเรียนของวันนี้ไว้ในเครื่องนี้เท่านั้น "
			+ "ผู้ปกครองลบได้ทุกเมื่อจากมุมผู้ปกครอง",
	"ครูสอนออนไลน์ (AI) ปิดอยู่ในเวอร์ชันนี้ และเปิดจากในแอปไม่ได้ "
			+ "หากเวอร์ชันในอนาคตมีฟีเจอร์นี้ เราจะขออนุญาตผู้ปกครองก่อน และอธิบายให้ชัดเจนว่าจะแบ่งปันข้อมูลอะไรบ้าง",
]
const ALIZ_DELETE_TITLE: String = "Delete learning history"
const ALIZ_DELETE_ARMED: String = "Tap again to delete"
const ALIZ_DELETE_HELP: String = "Clears Aliz's lesson progress and today's lesson time. Stars are never touched."
const ALIZ_DELETE_DONE: String = "Learning history deleted. Stars and stickers are untouched."
const ALIZ_BILLING_TEXT: String = "Billing is not available yet."

const ALIZ_TOGGLE_PRESSED: StyleBox = preload("res://assets/ui/styles/small/btn_blue.tres")
const ALIZ_TOGGLE_INK_PRESSED: Color = Color(0.11, 0.22, 0.35, 1)
const ALIZ_ROW_TITLE_INK: Color = Color(0.29, 0.22, 0.12, 1)
const ALIZ_ROW_HELP_INK: Color = Color(0.43, 0.35, 0.24, 1)

var _aliz_box: VBoxContainer = null
var _aliz_on: Button = null
var _aliz_off: Button = null
var _aliz_cloud_label: Label = null
var _aliz_allowance_label: Label = null
var _aliz_mic_label: Label = null
var _aliz_language_button: Button = null
var _aliz_hands_free_on: Button = null
var _aliz_hands_free_off: Button = null
var _aliz_voice_buttons: Control = null
var _aliz_voice_note: Label = null
var _aliz_history_box: VBoxContainer = null
var _aliz_privacy_box: VBoxContainer = null
var _aliz_privacy_th: VBoxContainer = null
var _aliz_delete_button: Button = null
var _aliz_delete_armed: bool = false
var _aliz_subscription_label: Label = null
var _aliz_pricing_label: Label = null
## The read-only meter this screen displays. Local mirror in every public
## build; it shares the panel's entitlement service so "Family Club" here and
## the allowance agree.
var _aliz_quota: TutorQuotaScript = null


func _build_learn_with_aliz() -> void:
	if _status_label == null:
		return
	var parent: Node = _status_label.get_parent()
	if parent == null:
		return
	if _entitlements == null:
		_entitlements = EntitlementServiceScript.new()
	_aliz_quota = TutorQuotaScript.new(_save_service(), _entitlements)

	_aliz_box = VBoxContainer.new()
	_aliz_box.name = "LearnWithAlizBox"
	_aliz_box.add_theme_constant_override("separation", 14)
	parent.add_child(_aliz_box)
	parent.move_child(_aliz_box, _status_label.get_index())

	_aliz_box.add_child(HSeparator.new())
	var title := Label.new()
	title.name = "LearnWithAlizTitle"
	title.text = ALIZ_SECTION_TITLE
	title.add_theme_font_size_override("font_size", SECTION_TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", Palette.INK)
	_aliz_box.add_child(title)

	# -- AI Tutor on / off ---------------------------------------------------
	var tutor_row: HBoxContainer = _aliz_row("AiTutor", "AI Tutor", ALIZ_TUTOR_HELP)
	var toggles := HBoxContainer.new()
	toggles.name = "AiTutorButtons"
	toggles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggles.add_theme_constant_override("separation", 12)
	tutor_row.add_child(toggles)
	var group := ButtonGroup.new()
	_aliz_on = _aliz_toggle("AiTutorOnButton", "On", group)
	_aliz_off = _aliz_toggle("AiTutorOffButton", "Off", group)
	toggles.add_child(_aliz_on)
	toggles.add_child(_aliz_off)
	_aliz_on.pressed.connect(_on_ai_tutor_chosen.bind(true))
	_aliz_off.pressed.connect(_on_ai_tutor_chosen.bind(false))
	_aliz_cloud_label = _aliz_help_label("AiTutorCloudLabel", "")
	_aliz_box.add_child(_aliz_cloud_label)

	# -- Hands-free on / off -------------------------------------------------
	var hands_free_row: HBoxContainer = _aliz_row("HandsFree", "Hands-free", ALIZ_HANDS_FREE_HELP)
	var hands_free_toggles := HBoxContainer.new()
	hands_free_toggles.name = "HandsFreeButtons"
	hands_free_toggles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hands_free_toggles.add_theme_constant_override("separation", 12)
	hands_free_row.add_child(hands_free_toggles)
	var hands_free_group := ButtonGroup.new()
	_aliz_hands_free_on = _aliz_toggle("HandsFreeOnButton", "On", hands_free_group)
	_aliz_hands_free_off = _aliz_toggle("HandsFreeOffButton", "Off", hands_free_group)
	hands_free_toggles.add_child(_aliz_hands_free_on)
	hands_free_toggles.add_child(_aliz_hands_free_off)
	_aliz_hands_free_on.pressed.connect(_on_hands_free_chosen.bind(true))
	_aliz_hands_free_off.pressed.connect(_on_hands_free_chosen.bind(false))

	# -- Aliz's voice (configured list; cloud voices disabled while the flag is off)
	var voice_row: HBoxContainer = _aliz_row("AlizVoice", "Aliz's voice", ALIZ_VOICE_HELP)
	_aliz_voice_buttons = HFlowContainer.new()
	_aliz_voice_buttons.name = "AlizVoiceButtons"
	_aliz_voice_buttons.size_flags_horizontal = Control.SIZE_SHRINK_END
	_aliz_voice_buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_aliz_voice_buttons.custom_minimum_size = Vector2(620.0, 0.0)
	_aliz_voice_buttons.alignment = FlowContainer.ALIGNMENT_END
	_aliz_voice_buttons.add_theme_constant_override("h_separation", 12)
	_aliz_voice_buttons.add_theme_constant_override("v_separation", 12)
	voice_row.add_child(_aliz_voice_buttons)
	var voice_group := ButtonGroup.new()
	var unavailable: PackedStringArray = PackedStringArray()
	for option: Dictionary in VoiceOptions.options():
		var voice_id: String = String(option["id"])
		var button: Button = _aliz_toggle("AlizVoice_%s" % voice_id, String(option["label"]), voice_group)
		button.custom_minimum_size = Vector2(0.0, 78.0)
		button.add_theme_constant_override("h_separation", 8)
		button.set_meta("voiceId", voice_id)
		if not VoiceOptions.is_selectable(voice_id):
			button.disabled = true
			button.tooltip_text = VoiceOptions.availability_note(voice_id).capitalize()
			# Muted ink: unavailable, not "off".
			button.add_theme_color_override("font_disabled_color", ALIZ_ROW_HELP_INK)
			unavailable.append(String(option["label"]))
		else:
			button.tooltip_text = String(option.get("description", ""))
		button.pressed.connect(_on_aliz_voice_chosen.bind(voice_id))
		_aliz_voice_buttons.add_child(button)
	_aliz_voice_note = _aliz_help_label("AlizVoiceNote", "")
	if not unavailable.is_empty():
		_aliz_voice_note.text = "%s: %s." % [", ".join(unavailable), VoiceOptions.CLOUD_NOTE]
		_aliz_voice_note.visible = true
	_aliz_box.add_child(_aliz_voice_note)

	# -- Daily allowance (read-only) ----------------------------------------
	var allowance_row: HBoxContainer = _aliz_row("AlizAllowance", "Daily AI allowance", ALIZ_ALLOWANCE_HELP)
	_aliz_allowance_label = _aliz_value_label("AlizAllowanceValue")
	allowance_row.add_child(_aliz_allowance_label)

	# -- Microphone permission (read-only) ----------------------------------
	var mic_row: HBoxContainer = _aliz_row("AlizMicrophone", "Microphone permission",
			"Voice answers need the microphone. Tapping always works without it.")
	_aliz_mic_label = _aliz_value_label("AlizMicrophoneValue")
	mic_row.add_child(_aliz_mic_label)

	# -- Learning language (fixed) ------------------------------------------
	var language_row: HBoxContainer = _aliz_row("AlizLanguage", "Learning language", ALIZ_LANGUAGE_HELP)
	_aliz_language_button = _aliz_toggle("AlizLanguageEnButton", ALIZ_LANGUAGE_FIXED, null)
	_aliz_language_button.set_pressed_no_signal(true)
	_aliz_language_button.disabled = true
	_aliz_language_button.tooltip_text = ALIZ_LANGUAGE_HELP
	language_row.add_child(_aliz_language_button)

	# -- Voice volume: the existing sliders, pointed at, not duplicated ------
	_aliz_box.add_child(_aliz_help_label("AlizLoudnessNote", ALIZ_VOICE_NOTE))

	# -- Privacy information: a static label, no button, no link -------------
	var privacy_title := Label.new()
	privacy_title.name = "AlizPrivacyTitle"
	privacy_title.text = ALIZ_PRIVACY_TITLE
	privacy_title.add_theme_font_size_override("font_size", 30)
	privacy_title.add_theme_color_override("font_color", ALIZ_ROW_TITLE_INK)
	_aliz_box.add_child(privacy_title)
	_aliz_privacy_box = VBoxContainer.new()
	_aliz_privacy_box.name = "AlizPrivacyBox"
	_aliz_privacy_box.add_theme_constant_override("separation", 8)
	_aliz_box.add_child(_aliz_privacy_box)
	for index: int in range(ALIZ_PRIVACY_LINES.size()):
		var line := Label.new()
		line.name = "AlizPrivacyLine%d" % index
		line.text = ALIZ_PRIVACY_LINES[index]
		_style_body(line)
		_aliz_privacy_box.add_child(line)
	_aliz_privacy_th = VBoxContainer.new()
	_aliz_privacy_th.name = "AlizPrivacyThai"
	_aliz_privacy_th.visible = false
	_aliz_privacy_th.add_theme_constant_override("separation", 8)
	_aliz_privacy_box.add_child(_aliz_privacy_th)
	for index: int in range(ALIZ_PRIVACY_LINES_TH.size()):
		var thai := Label.new()
		thai.name = "AlizPrivacyThaiLine%d" % index
		thai.text = ALIZ_PRIVACY_LINES_TH[index]
		_style_body(thai)
		HelperFont.apply(thai)
		_aliz_privacy_th.add_child(thai)

	# -- Learning history (read-only), just above the delete -----------------
	var history_title := Label.new()
	history_title.name = "AlizHistoryTitle"
	history_title.text = ALIZ_HISTORY_TITLE
	history_title.add_theme_font_size_override("font_size", 30)
	history_title.add_theme_color_override("font_color", ALIZ_ROW_TITLE_INK)
	_aliz_box.add_child(history_title)
	_aliz_box.add_child(_aliz_help_label("AlizHistoryHelp", ALIZ_HISTORY_HELP))
	_aliz_history_box = VBoxContainer.new()
	_aliz_history_box.name = "AlizHistoryBox"
	_aliz_history_box.add_theme_constant_override("separation", 4)
	_aliz_box.add_child(_aliz_history_box)

	# -- Delete learning history (two taps) ---------------------------------
	_aliz_box.add_child(_aliz_help_label("AlizDeleteHelp", ALIZ_DELETE_HELP))
	_aliz_delete_button = Button.new()
	_aliz_delete_button.name = "AlizDeleteHistoryButton"
	_aliz_delete_button.text = ALIZ_DELETE_TITLE
	_style_secondary_button(_aliz_delete_button)
	_aliz_delete_button.pressed.connect(_on_aliz_delete_pressed)
	_aliz_box.add_child(_aliz_delete_button)

	# -- Subscription status (information) ----------------------------------
	var subscription_row: HBoxContainer = _aliz_row("AlizSubscription", "Subscription", "")
	_aliz_subscription_label = _aliz_value_label("AlizSubscriptionValue")
	subscription_row.add_child(_aliz_subscription_label)
	_aliz_pricing_label = _aliz_help_label("AlizPricingLabel", "")
	_aliz_box.add_child(_aliz_pricing_label)

	_refresh_learn_with_aliz()


## A settings row shaped like the scene's own: title + help on the left, the
## control on the right.
func _aliz_row(row_name: String, title_text: String, help_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name + "Row"
	row.add_theme_constant_override("separation", 24)
	_aliz_box.add_child(row)
	var text := VBoxContainer.new()
	text.name = row_name + "Text"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	var title := Label.new()
	title.name = row_name + "Title"
	title.text = title_text
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", ALIZ_ROW_TITLE_INK)
	text.add_child(title)
	if not help_text.is_empty():
		var help: Label = _aliz_help_label(row_name + "Help", help_text)
		text.add_child(help)
	return row


func _aliz_help_label(label_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_color", ALIZ_ROW_HELP_INK)
	label.visible = not text.is_empty()
	return label


## The right-hand read-only value of a row.
func _aliz_value_label(label_name: String) -> Label:
	var label := Label.new()
	label.name = label_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420.0, 0.0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Palette.INK)
	return label


## The scene's On/Off toggle, rebuilt in code with the same frames and inks.
func _aliz_toggle(button_name: String, text: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(148.0, 78.0)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if group != null:
		button.button_group = group
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", SECONDARY_BUTTON_INK)
	button.add_theme_color_override("font_hover_color", SECONDARY_BUTTON_INK)
	button.add_theme_color_override("font_pressed_color", ALIZ_TOGGLE_INK_PRESSED)
	button.add_theme_color_override("font_hover_pressed_color", ALIZ_TOGGLE_INK_PRESSED)
	button.add_theme_color_override("font_disabled_color", ALIZ_TOGGLE_INK_PRESSED)
	for state: String in ["normal", "hover", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, SECONDARY_BUTTON_PRESSED)
	button.add_theme_stylebox_override("pressed", ALIZ_TOGGLE_PRESSED)
	return button


## Re-reads every value in the section. Called from `_sync_from_model()`.
func _refresh_learn_with_aliz() -> void:
	if _aliz_box == null:
		return
	var enabled: bool = _model.get_ai_tutor_enabled()
	_aliz_on.set_pressed_no_signal(enabled)
	_aliz_off.set_pressed_no_signal(not enabled)
	_aliz_cloud_label.text = ALIZ_CLOUD_ON_TEXT if TutorFlags.cloud_enabled() else ALIZ_CLOUD_OFF_TEXT
	_aliz_cloud_label.visible = true

	if _aliz_quota != null:
		_aliz_quota.refresh()
		var quota: Dictionary = _aliz_quota.state()
		_aliz_allowance_label.text = "Used %s of %s today\n%s" % [
			TutorQuotaScript.format_clock(float(quota["usedSeconds"])),
			TutorQuotaScript.format_clock(float(quota["dailyAllowanceSeconds"])),
			String(quota["resetAtLocalText"]),
		]
		var club: bool = String(quota["entitlement"]) == QuotaConfig.ENTITLEMENT_FAMILY_CLUB
		_aliz_subscription_label.text = "Family Club" if club else "Free"

	_aliz_mic_label.text = _microphone_permission_text()
	var hands_free: bool = _model.get_hands_free_mode()
	_aliz_hands_free_on.set_pressed_no_signal(hands_free)
	_aliz_hands_free_off.set_pressed_no_signal(not hands_free)
	var voice_id: String = _model.get_ai_voice_id()
	for child: Node in _aliz_voice_buttons.get_children():
		if child is Button:
			(child as Button).set_pressed_no_signal(String(child.get_meta("voiceId", "")) == voice_id)
	_refresh_learning_history()
	if _aliz_privacy_th != null:
		_aliz_privacy_th.visible = _model.get_helper_language() == "th"

	var pricing: String = QuotaConfig.pricing_line()
	_aliz_pricing_label.text = ALIZ_BILLING_TEXT if pricing.is_empty() \
			else "Family Club -- %s. %s" % [pricing, ALIZ_BILLING_TEXT]
	_aliz_pricing_label.visible = true
	_disarm_aliz_delete()


## From the speech service's own diagnostics when the autoload is up; the
## screen never asks for the permission itself.
func _microphone_permission_text() -> String:
	var speech: Node = _autoload("SpeechService")
	if speech == null or not speech.has_method("describe_diagnostics"):
		return ALIZ_MIC_NOT_CHECKED
	var diagnostics: Variant = speech.call("describe_diagnostics")
	if typeof(diagnostics) != TYPE_DICTIONARY or not (diagnostics as Dictionary).has("hasPermission"):
		return ALIZ_MIC_NOT_CHECKED
	return ALIZ_MIC_ALLOWED if bool((diagnostics as Dictionary)["hasPermission"]) else ALIZ_MIC_NOT_ALLOWED


func _on_ai_tutor_chosen(enabled: bool) -> void:
	if _syncing:
		return
	_model.set_ai_tutor_enabled(enabled)


func _on_hands_free_chosen(enabled: bool) -> void:
	if _syncing:
		return
	_model.set_hands_free_mode(enabled)


func _on_aliz_voice_chosen(voice_id: String) -> void:
	if _syncing:
		return
	_model.set_ai_voice_id(voice_id)
	# The model may have refused (unknown or cloud-only): show what it kept.
	var kept: String = _model.get_ai_voice_id()
	for child: Node in _aliz_voice_buttons.get_children():
		if child is Button:
			(child as Button).set_pressed_no_signal(String(child.get_meta("voiceId", "")) == kept)


## One line per completed lesson (title, stars, date), or "No lessons yet".
func _refresh_learning_history() -> void:
	if _aliz_history_box == null:
		return
	for child: Node in _aliz_history_box.get_children():
		_aliz_history_box.remove_child(child)
		child.queue_free()
	var lines: PackedStringArray = _model.learning_history_lines()
	for index: int in range(lines.size()):
		var label := Label.new()
		label.name = "AlizHistoryLine%d" % index
		label.text = lines[index]
		_style_body(label)
		_aliz_history_box.add_child(label)


## Two taps: arm, then delete. Closing the panel disarms.
func _on_aliz_delete_pressed() -> void:
	if not _aliz_delete_armed:
		_aliz_delete_armed = true
		_aliz_delete_button.text = ALIZ_DELETE_ARMED
		_set_status("")
		return
	_model.delete_learning_history()
	_disarm_aliz_delete()
	if _aliz_quota != null:
		_aliz_quota.ledger().load_from_save()
	_refresh_learn_with_aliz()
	_set_status(ALIZ_DELETE_DONE)


func _disarm_aliz_delete() -> void:
	_aliz_delete_armed = false
	if _aliz_delete_button != null:
		_aliz_delete_button.text = ALIZ_DELETE_TITLE


func _collapse_learn_with_aliz() -> void:
	_disarm_aliz_delete()


## -- read-only accessors, for the tests and the shots --------------------------

func is_learn_with_aliz_visible() -> bool:
	if _aliz_box == null or not _aliz_box.visible:
		return false
	return _panel != null and _panel.visible


## The privacy text is a static label: on screen whenever the section is.
func is_aliz_privacy_visible() -> bool:
	return _aliz_privacy_box != null and _aliz_privacy_box.visible and is_learn_with_aliz_visible()


func aliz_learning_history_lines() -> PackedStringArray:
	return _model.learning_history_lines()


## Voice id -> whether its button can be pressed in this build. Tests.
func aliz_voice_choices() -> Dictionary:
	var out: Dictionary = {}
	if _aliz_voice_buttons == null:
		return out
	for child: Node in _aliz_voice_buttons.get_children():
		if child is Button:
			out[String(child.get_meta("voiceId", ""))] = not (child as Button).disabled
	return out


func aliz_allowance_text() -> String:
	return _aliz_allowance_label.text if _aliz_allowance_label != null else ""


func aliz_subscription_text() -> String:
	return _aliz_subscription_label.text if _aliz_subscription_label != null else ""


func aliz_pricing_text() -> String:
	return _aliz_pricing_label.text if _aliz_pricing_label != null else ""


func aliz_cloud_text() -> String:
	return _aliz_cloud_label.text if _aliz_cloud_label != null else ""


func aliz_microphone_text() -> String:
	return _aliz_mic_label.text if _aliz_mic_label != null else ""


func aliz_privacy_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for line: String in ALIZ_PRIVACY_LINES:
		out.append(line)
	return out


func is_aliz_delete_armed() -> bool:
	return _aliz_delete_armed


## The meter the section reads. Tests.
func tutor_quota() -> RefCounted:
	return _aliz_quota
