extends Control

## Parent Settings overlay, behind a press-and-hold parental gate.
##
## Self-contained and instantiable from anywhere: add it as a child of a
## CanvasLayer (or push it as a scene) and it does the rest. While locked it
## renders nothing but a small, dull gear in a corner and passes every other
## touch straight through to the game underneath.
##
## The caller decides what "done" means -- this scene only emits `closed()` and
## never changes scenes itself.
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

## Emitted when the grown-up taps Done (or the settings panel is closed).
signal closed()
## Emitted once the gate has been held long enough and the panel is showing.
signal opened()

## When false the panel is shown immediately with no gate -- for callers that
## push this as a full scene from their own (already gated) entry point.
@export var show_gate: bool = true

var _model: ParentSettingsModelScript
var _syncing: bool = false

@onready var _entry_gate: ParentalGateScript = %EntryGate
@onready var _backdrop: ColorRect = %Backdrop
@onready var _panel: PanelContainer = %Panel
@onready var _thai_on: Button = %ThaiOnButton
@onready var _thai_off: Button = %ThaiOffButton
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
	if not is_inside_tree():
		return null
	var tree_root: Node = get_tree().root
	return tree_root.get_node_or_null(NodePath("SaveService")) if tree_root != null else null


func _ready() -> void:
	_model = ParentSettingsModelScript.new(_save_service())

	_entry_gate.unlocked.connect(_on_gate_unlocked)
	_confirm_hold.unlocked.connect(_on_reset_confirmed)
	_done_button.pressed.connect(_on_done_pressed)
	_reset_button.pressed.connect(_on_reset_requested)
	_cancel_reset_button.pressed.connect(_hide_reset_confirmation)
	_thai_on.pressed.connect(_on_thai_chosen.bind(true))
	_thai_off.pressed.connect(_on_thai_chosen.bind(false))
	_voice_on.pressed.connect(_on_voice_chosen.bind(true))
	_voice_off.pressed.connect(_on_voice_chosen.bind(false))
	_speed_slow.pressed.connect(_on_speed_chosen.bind(ParentSettingsModelScript.TTS_SPEED_SLOW))
	_speed_normal.pressed.connect(_on_speed_chosen.bind(ParentSettingsModelScript.TTS_SPEED_NORMAL))

	_build_speech_check()
	_build_qa_replay()
	_build_family_club()

	if show_gate:
		_show_locked()
	else:
		open_settings()


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
const PRICE_MONTHLY_THB: String = "THB 99 / month"

## Every line the section prints, in order. Plain, factual, grown-up copy: no
## urgency, no scarcity, no "unlock", nothing addressed to a child.
const FAMILY_CLUB_LINES: Array[String] = [
	"Free Starter -- free forever, no account needed.",
	"Family Club (proposed) -- " + PRICE_MONTHLY_USD,
	"Thailand (proposed) -- " + PRICE_MONTHLY_THB,
	"Annual pricing is not decided yet, so there is none to show.",
	"Nothing can be bought in this app. This build has no payment of any kind; "
			+ "these prices are information only.",
	"Your child's game is never interrupted to ask for money, and Buddy is never "
			+ "sad about a subscription.",
]

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

	for line: String in FAMILY_CLUB_LINES:
		var label := Label.new()
		label.text = line
		_style_body(label)
		_family_club_box.add_child(label)

	# -- Songs for Fun ------------------------------------------------------
	_songs_button = Button.new()
	_songs_button.name = "SongsForFunButton"
	_songs_button.text = SONGS_FOR_FUN_TITLE
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

## The pricing/disclosure copy, exactly as printed.
func family_club_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for line: String in FAMILY_CLUB_LINES:
		out.append(line)
	return out


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
	_backdrop.visible = true
	_panel.visible = true
	_hide_reset_confirmation()
	_collapse_songs_for_fun()
	_set_status("")
	_sync_from_model()
	opened.emit()


## Returns to the locked state (gear only) and emits `closed()`.
func close_settings() -> void:
	_show_locked()
	closed.emit()


func _show_locked() -> void:
	_entry_gate.reset()
	_entry_gate.visible = show_gate
	_backdrop.visible = false
	_panel.visible = false
	_hide_reset_confirmation()
	# The external link never survives a close: locking the panel puts it away.
	_collapse_songs_for_fun()


func _on_gate_unlocked() -> void:
	open_settings()


func _on_done_pressed() -> void:
	close_settings()


# -- settings ----------------------------------------------------------------

func _sync_from_model() -> void:
	_syncing = true
	var thai: bool = _model.get_thai_hints()
	_thai_on.button_pressed = thai
	_thai_off.button_pressed = not thai
	var voice: bool = _model.get_speech_enabled()
	_voice_on.button_pressed = voice
	_voice_off.button_pressed = not voice
	var slow: bool = _model.is_tts_slow()
	_speed_slow.button_pressed = slow
	_speed_normal.button_pressed = not slow
	var stars: int = _model.get_stars()
	_stars_label.text = "%d star earned" % stars if stars == 1 else "%d stars earned" % stars
	_syncing = false


func _on_thai_chosen(enabled: bool) -> void:
	if _syncing:
		return
	_model.set_thai_hints(enabled)


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
