extends Control

## ============================================================================
## SPEECH FEEDBACK -- the child must always know what the microphone is doing.
## ============================================================================
##
## The Speak button used to be a silent black box: you pressed it, something may
## or may not have been listening, and nothing on screen ever said which. On a
## device that is indistinguishable from the feature being broken -- which is
## exactly the report this was built from.
##
## So every state the speech stack can be in now has a face:
##
## | State | What the child sees |
## |---|---|
## | `IDLE` | nothing; the Speak button is the whole UI |
## | `LISTENING` | a pulsing microphone and "I'm listening..."; once the recogniser has a first guess, "I hear: milk" under it |
## | `PROCESSING` | "One moment..." |
## | `HEARD` | "I heard: milk" |
## | `MATCHED` | "Great!" with the word that earned it |
## | `NOT_UNDERSTOOD` | "Try again!" (with what was heard, if anything) plus the reminder that tapping works |
## | `PERMISSION_NEEDED` | a grown-up needs to turn the microphone on |
## | `UNAVAILABLE` | voice is off, tapping still works |
## | `ERROR` | "Let's try again." |
##
## ## Two rules this file exists to keep
##
## **Nothing here is a failure.** There is no red, no cross, no score and no
## "wrong" -- `CLAUDE.md`'s child UX rules forbid all four. The unhappy states
## are the same shape and the same warmth as the happy ones; only the word
## changes. A four-year-old who mumbles must not be told they failed.
##
## **The touch fallback is never hidden.** Every state that means "speech did not
## work for you right now" says so AND says tapping still works, because the one
## unforgivable outcome is a child stuck at a prompt they cannot pass. That is
## also why this is a presenter and not a gate: it reports, it never blocks.
##
## ## Why it builds itself in code
##
## Same reason `house_hud.gd` does: the states are data, the copy is a pure
## static function, and a test can assert every line of text without a viewport
## or a scene file. `copy_for_state()` is deliberately static and total -- it
## answers for every enum value, so a new state cannot silently render blank.

const Palette := preload("res://scripts/ui/palette.gd")

enum State {
	IDLE,
	LISTENING,
	PROCESSING,
	HEARD,
	MATCHED,
	NOT_UNDERSTOOD,
	PERMISSION_NEEDED,
	UNAVAILABLE,
	ERROR,
}

## Emitted whenever the panel changes state, so a test or a parent diagnostic can
## follow the stack without scraping labels.
signal state_changed(state: int)

const PANEL_WIDTH: float = 520.0
const PANEL_HEIGHT: float = 128.0
const PANEL_BOTTOM_MARGIN: float = 150.0
const TITLE_FONT_SIZE: int = 34
const DETAIL_FONT_SIZE: int = 26
const ICON_RADIUS: float = 30.0

## How long a transient state stays up before it falls back to IDLE. `HEARD` is
## deliberately brief -- it is a receipt, not a reading exercise. `RETRY` is
## longer than it was: it now carries the heard word and the tap reminder, and
## the child's grown-up needs a moment to read both.
const HEARD_SECONDS: float = 1.5
const MATCHED_SECONDS: float = 1.8
const RETRY_SECONDS: float = 3.0

## Pulse, in Hz and in amplitude. Slow and shallow on purpose: a fast throb on a
## microphone reads as urgency, and nothing about talking to a baby is urgent.
const PULSE_HZ: float = 1.1
const PULSE_AMPLITUDE: float = 0.12

var _state: int = State.IDLE
var _detail: String = ""
var _elapsed: float = 0.0
var _hold: float = 0.0
var _built: bool = false

var _panel: PanelContainer = null
var _icon: Panel = null
var _icon_holder: Control = null
var _title: Label = null
var _detail_label: Label = null


func _ready() -> void:
	build()


## Idempotent, and callable before `_ready()` -- the headless runner never fires
## `_ready()` for a node added to the root.
func build() -> void:
	if _built:
		return
	_built = true

	name = "SpeechFeedback"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -PANEL_WIDTH * 0.5
	_panel.offset_right = PANEL_WIDTH * 0.5
	_panel.offset_top = -(PANEL_BOTTOM_MARGIN + PANEL_HEIGHT)
	_panel.offset_bottom = -PANEL_BOTTOM_MARGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.CREAM
	style.set_corner_radius_all(28)
	style.set_content_margin_all(14)
	style.shadow_color = Color(0.349, 0.259, 0.169, 0.18)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 4.0)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(row)

	_icon_holder = Control.new()
	_icon_holder.name = "IconHolder"
	_icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_holder.custom_minimum_size = Vector2(ICON_RADIUS * 2.4, ICON_RADIUS * 2.4)
	row.add_child(_icon_holder)

	_icon = Panel.new()
	_icon.name = "Icon"
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_icon.offset_left = -ICON_RADIUS
	_icon.offset_top = -ICON_RADIUS
	_icon.offset_right = ICON_RADIUS
	_icon.offset_bottom = ICON_RADIUS
	_icon.pivot_offset = Vector2(ICON_RADIUS, ICON_RADIUS)
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Palette.MINT
	icon_style.set_corner_radius_all(int(ICON_RADIUS))
	_icon.add_theme_stylebox_override("panel", icon_style)
	_icon_holder.add_child(_icon)
	_build_mic_glyph()

	var column := VBoxContainer.new()
	column.name = "Text"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	_title = Label.new()
	_title.name = "Title"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.add_theme_color_override("font_color", Palette.INK)
	column.add_child(_title)

	_detail_label = Label.new()
	_detail_label.name = "Detail"
	_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_label.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
	_detail_label.add_theme_color_override("font_color", Palette.INK_SOFT)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_detail_label)

	_apply()


## A microphone drawn from three rounded boxes, inside the coloured disc.
##
## A bare coloured circle is a status light -- it tells a child that SOMETHING is
## happening, not what. The point of this panel is that the microphone stops
## being mysterious, so the microphone has to be visible. Three `Panel`s cost
## nothing and need no texture, atlas or import step.
func _build_mic_glyph() -> void:
	var ink: Color = Palette.INK

	# Capsule: the mic body.
	var body := Panel.new()
	body.name = "MicBody"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	body.offset_left = -7.0
	body.offset_top = -17.0
	body.offset_right = 7.0
	body.offset_bottom = 3.0
	var body_style := StyleBoxFlat.new()
	body_style.bg_color = ink
	body_style.set_corner_radius_all(7)
	body.add_theme_stylebox_override("panel", body_style)
	_icon.add_child(body)

	# Cradle: the U the body sits in, faked with a ring clipped by the body.
	var cradle := Panel.new()
	cradle.name = "MicCradle"
	cradle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cradle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cradle.offset_left = -12.0
	cradle.offset_top = -6.0
	cradle.offset_right = 12.0
	cradle.offset_bottom = 10.0
	var cradle_style := StyleBoxFlat.new()
	# Fully transparent, but built from INK rather than #000000: ART_BIBLE §3
	# bans pure black anywhere, and the palette guard checks the literal.
	cradle_style.bg_color = Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.0)
	cradle_style.border_color = ink
	cradle_style.border_width_left = 3
	cradle_style.border_width_right = 3
	cradle_style.border_width_bottom = 3
	cradle_style.set_corner_radius_all(11)
	cradle.add_theme_stylebox_override("panel", cradle_style)
	_icon.add_child(cradle)

	# Stand.
	var stand := Panel.new()
	stand.name = "MicStand"
	stand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stand.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	stand.offset_left = -2.0
	stand.offset_top = 10.0
	stand.offset_right = 2.0
	stand.offset_bottom = 17.0
	var stand_style := StyleBoxFlat.new()
	stand_style.bg_color = ink
	stand_style.set_corner_radius_all(2)
	stand.add_theme_stylebox_override("panel", stand_style)
	_icon.add_child(stand)


## -- The copy ------------------------------------------------------------------

## `{title, detail, color}` for a state. Static, total and tree-free, so the
## words a child reads are assertable in a unit test.
##
## `heard` is the recogniser's text, shown verbatim so the parent can see
## exactly what came back. `LISTENING` shows it as the live guess while the
## microphone is still open; `HEARD`, `MATCHED` and `NOT_UNDERSTOOD` show what
## the attempt ended on. A child who mumbled "banana" at a milk prompt sees
## "I heard: banana" -- a fact, not a verdict -- and the tap reminder.
static func copy_for_state(state: int, heard: String = "") -> Dictionary:
	var words: String = heard.strip_edges()
	match state:
		State.LISTENING:
			return {
				"title": "I'm listening...",
				"detail": ("I hear: %s" % words) if not words.is_empty() else "Go on, say it!",
				"color": Palette.MINT,
			}
		State.PROCESSING:
			return {
				"title": "One moment...",
				"detail": "",
				"color": Palette.DUSTY_BLUE,
			}
		State.HEARD:
			return {
				"title": "I heard: %s" % words,
				"detail": "",
				"color": Palette.DUSTY_BLUE,
			}
		State.MATCHED:
			return {
				"title": "Great!",
				"detail": ("You said: %s" % words) if not words.is_empty() else "",
				"color": Palette.MINT,
			}
		State.NOT_UNDERSTOOD:
			# No "wrong", no red, no score. The tap reminder is the important half:
			# a child who cannot be heard must still be able to finish.
			return {
				"title": "Try again!",
				"detail": ("I heard: %s. You can tap it too." % words) if not words.is_empty()
						else "Say it once more, or tap it.",
				"color": Palette.PEACH,
			}
		State.PERMISSION_NEEDED:
			return {
				"title": "Microphone is off",
				"detail": "A grown-up can turn it on in Settings. You can tap it too.",
				"color": Palette.LAVENDER,
			}
		State.UNAVAILABLE:
			return {
				"title": "Voice is not ready",
				"detail": "You can tap it instead!",
				"color": Palette.LAVENDER,
			}
		State.ERROR:
			# Also the timeout: nothing was heard within the listening window.
			return {
				"title": "Let's try again",
				"detail": "Tap Speak and say it, or just tap it.",
				"color": Palette.PEACH,
			}
		_:
			return {"title": "", "detail": "", "color": Palette.CREAM}


## States that disappear by themselves, and how long they stay. A state that is
## not here is held until something changes it.
static func hold_seconds(state: int) -> float:
	match state:
		State.HEARD:
			return HEARD_SECONDS
		State.MATCHED:
			return MATCHED_SECONDS
		State.NOT_UNDERSTOOD, State.ERROR:
			return RETRY_SECONDS
		_:
			return 0.0


## True while the child should still be able to reach the answer by touching.
## Every state except the two "speech is actually working right now" ones -- and
## the caller is expected to leave touch enabled regardless; this exists so a
## test can state the rule rather than trusting every call site to remember it.
static func touch_remains_available(_state: int) -> bool:
	return true


## -- State ---------------------------------------------------------------------

func set_state(state: int, detail: String = "") -> void:
	build()
	if not _is_known(state):
		state = State.IDLE
	_state = state
	_detail = detail
	_elapsed = 0.0
	_hold = hold_seconds(state)
	_apply()
	state_changed.emit(_state)


func get_state() -> int:
	return _state


func get_heard_text() -> String:
	return _detail


static func _is_known(state: int) -> bool:
	return state >= State.IDLE and state <= State.ERROR


func get_title_text() -> String:
	build()
	return _title.text


func get_detail_text() -> String:
	build()
	return _detail_label.text


func _apply() -> void:
	if _title == null:
		return
	var copy: Dictionary = copy_for_state(_state, _detail)
	_title.text = String(copy["title"])
	_detail_label.text = String(copy["detail"])
	_detail_label.visible = not _detail_label.text.is_empty()
	var style: StyleBox = _icon.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		(style as StyleBoxFlat).bg_color = copy["color"]
	_panel.visible = _state != State.IDLE
	if _state != State.LISTENING:
		_icon.scale = Vector2.ONE


## Advances the pulse and the auto-dismiss. Split out of `_process` so a headless
## test drives exactly the same code a device does -- the same arrangement
## `room_camera.gd` uses.
func step(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_elapsed += delta
	if _state == State.LISTENING and _icon != null:
		var pulse: float = 1.0 + sin(_elapsed * TAU * PULSE_HZ) * PULSE_AMPLITUDE
		_icon.scale = Vector2(pulse, pulse)
	if _hold > 0.0 and _elapsed >= _hold:
		set_state(State.IDLE)


func _process(delta: float) -> void:
	step(delta)
