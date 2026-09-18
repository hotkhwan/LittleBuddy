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
## defensively), no links, no purchases, no analytics, no network.

## Preloaded rather than referenced by `class_name`, so this scene parses even
## before the editor has registered the new global classes.
const ParentSettingsModelScript := preload("res://scripts/parent_settings/parent_settings_model.gd")
const SpeechDiagnosticsScript := preload("res://scripts/ui/speech_diagnostics_panel.gd")
const ParentalGateScript := preload("res://scripts/parent_settings/parental_gate.gd")

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


func _ready() -> void:
	_model = ParentSettingsModelScript.new(get_node_or_null("/root/SaveService"))

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


## Opens the panel directly, bypassing the gate (for callers with their own
## grown-up entry point).
func open_settings() -> void:
	_entry_gate.visible = false
	_backdrop.visible = true
	_panel.visible = true
	_hide_reset_confirmation()
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
