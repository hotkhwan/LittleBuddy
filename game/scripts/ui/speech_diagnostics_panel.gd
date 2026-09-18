extends Control

## ============================================================================
## SPEECH DIAGNOSTICS -- for the parent, on the device, in plain words.
## ============================================================================
##
## `SpeechService` already writes `user://speech_diag.json`, and pulling that off
## an iPhone needs `devicectl`, a UDID and a Mac. That is a developer workflow,
## and the question it answers -- "is the microphone actually working?" -- is one
## a parent needs answered standing in the kitchen holding the phone.
##
## So this is the same facts, on screen, one row per question, each with a plain
## verdict rather than a raw value. `PERMISSION: granted` is useful.
## `hasPermission: true` is a log line.
##
## ## Deliberately not for children
##
## It lives behind Parent Corner, it is text-dense, and it is never shown during
## play. `CLAUDE.md` forbids exposing diagnostics prominently to children and
## this is the place that rule matters most: it is the one screen in the game
## that is allowed to look like a tool.
##
## ## No audio, no transcripts leave the device
##
## The last transcript IS shown, because it is the single most useful line when
## telling "the mic is dead" apart from "it heard me and the word did not
## match". It is read from memory, never persisted, and never uploaded --
## `speech_service.gd` keeps it out of the diagnostics file for exactly that
## reason.

const Palette := preload("res://scripts/ui/palette.gd")

const TITLE_FONT_SIZE: int = 32
const ROW_FONT_SIZE: int = 22
const ROW_SEPARATION: int = 6

## Row order is the order a parent would debug in: can it work at all, was it
## allowed, is it running, what did it hear, what went wrong.
const ROWS: Array[Dictionary] = [
	{"key": "platform", "label": "Device"},
	{"key": "backend", "label": "Speech engine"},
	{"key": "nativeSingletonPresent", "label": "iOS plugin found"},
	{"key": "isAvailable", "label": "Recogniser available"},
	{"key": "hasPermission", "label": "Microphone permission"},
	{"key": "speechEnabledSetting", "label": "Speech turned on"},
	{"key": "ttsAvailable", "label": "Voice (speaking)"},
	{"key": "isListening", "label": "Listening now"},
	{"key": "locale", "label": "Language"},
	{"key": "lastTranscript", "label": "Last heard"},
	{"key": "lastFailureReason", "label": "Last problem"},
	{"key": "listenCount", "label": "Times listened"},
	{"key": "recognizedCount", "label": "Times understood"},
	{"key": "failedCount", "label": "Times not understood"},
	{"key": "fallbackActive", "label": "Using fallback"},
]

var _built: bool = false
var _rows: Dictionary = {}
var _verdict: Label = null
var _service: Object = null
## The last recognised words, held HERE rather than in `SpeechService`.
##
## `test_speech_privacy_guard.gd` forbids the service from keeping a transcript
## in a member variable, and that guard is right: the service is a long-lived
## autoload that writes a JSON file, so anything it remembers is one bug away
## from being persisted. This panel is a screen a parent opens and closes, holds
## the words in memory only, writes them nowhere, and loses them when it is
## freed -- which is the whole difference.
var _last_transcript: String = ""


func _ready() -> void:
	build()
	_listen_for_transcripts()
	refresh()


func build() -> void:
	if _built:
		return
	_built = true
	name = "SpeechDiagnosticsPanel"

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.CREAM
	style.set_corner_radius_all(20)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Rows"
	column.add_theme_constant_override("separation", ROW_SEPARATION)
	panel.add_child(column)

	var title := Label.new()
	title.name = "Title"
	title.text = "Speech check"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", Palette.INK)
	column.add_child(title)

	_verdict = Label.new()
	_verdict.name = "Verdict"
	_verdict.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	_verdict.add_theme_color_override("font_color", Palette.INK_SOFT)
	_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_verdict)

	for row: Dictionary in ROWS:
		var line := HBoxContainer.new()
		line.name = "Row_" + String(row["key"])
		line.add_theme_constant_override("separation", 10)
		column.add_child(line)

		var label := Label.new()
		label.text = String(row["label"]) + ":"
		label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		label.add_theme_color_override("font_color", Palette.INK_SOFT)
		label.custom_minimum_size = Vector2(280.0, 0.0)
		line.add_child(label)

		var value := Label.new()
		value.name = "Value"
		value.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		value.add_theme_color_override("font_color", Palette.INK)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(value)
		_rows[String(row["key"])] = value


## Injectable so a test can pass a stub instead of the autoload.
func set_service(service: Object) -> void:
	_service = service
	_listen_for_transcripts()


func _listen_for_transcripts() -> void:
	var service: Object = _service
	if service == null:
		service = get_node_or_null("/root/SpeechService")
	if service == null or not service.has_signal("recognized"):
		return
	if not service.is_connected("recognized", _on_recognized):
		service.connect("recognized", _on_recognized)


func _on_recognized(text: String) -> void:
	_last_transcript = text.strip_edges()
	if _built:
		refresh()


func refresh() -> void:
	build()
	var diag: Dictionary = read_diagnostics()
	# Merged in here, not read from the service -- see `_last_transcript`.
	diag["lastTranscript"] = _last_transcript
	for key: String in _rows.keys():
		(_rows[key] as Label).text = format_value(key, diag.get(key, null))
	if _verdict != null:
		_verdict.text = verdict_line(diag)


func read_diagnostics() -> Dictionary:
	var service: Object = _service
	if service == null:
		service = get_node_or_null("/root/SpeechService")
	if service == null or not service.has_method("describe_diagnostics"):
		return {}
	return service.call("describe_diagnostics")


## Plain words, not raw values. Booleans become yes/no, an empty string becomes
## a dash rather than a blank that reads as a broken row.
static func format_value(key: String, value: Variant) -> String:
	if value == null:
		return "—"
	match typeof(value):
		TYPE_BOOL:
			return "yes" if bool(value) else "no"
		TYPE_STRING:
			var text: String = String(value).strip_edges()
			return text if not text.is_empty() else "—"
		_:
			if key == "":
				return str(value)
			return str(value)


## The one line a parent should read first.
##
## Ordered by what actually blocks speech, most fundamental first, so the verdict
## names the ROOT cause rather than the first symptom -- telling someone "not
## understood" when the real problem is a denied microphone sends them looking in
## the wrong place.
static func verdict_line(diag: Dictionary) -> String:
	if diag.is_empty():
		return "Speech service not running. Touch play is unaffected."
	if not bool(diag.get("speechEnabledSetting", true)):
		return "Speech is switched OFF in settings. Turn it on above to test."
	if not bool(diag.get("isAvailable", false)):
		if not bool(diag.get("nativeSingletonPresent", false)) and String(diag.get("platform", "")) == "iOS":
			return "The iOS speech plugin did not load, so voice is unavailable. Touch play works."
		return "No speech recogniser is available on this device. Touch play works."
	if not bool(diag.get("hasPermission", false)):
		return "Microphone permission has not been granted. Allow it in iOS Settings, then retry."
	if int(diag.get("listenCount", 0)) == 0:
		return "Ready. Nothing has been tried yet — press Speak in the game, then come back."
	if int(diag.get("recognizedCount", 0)) == 0:
		return "Listening works but nothing has been understood yet. Check the Last heard row."
	return "Working. Speech has been understood %d of %d attempts." % [
		int(diag.get("recognizedCount", 0)), int(diag.get("listenCount", 0))
	]
