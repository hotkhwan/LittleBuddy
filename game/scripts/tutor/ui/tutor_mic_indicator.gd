extends Control

## THE MICROPHONE ACTIVITY INDICATOR. The child presses nothing per turn, so
## this is what tells them -- and the grown-up beside them -- what the
## microphone is doing right now. A disc with a mic glyph, a level arc round
## it fed by `TutorVoiceSession.get_input_level()`, and a colour per state:
##
##   listening   mint disc, deep-mint arc that grows with the level
##   hearing     the same, arc near full (a partial arrived)
##   aliz        peach: Aliz is talking, the mic is closed
##   muted       lavender, speaker with no waves
##   off         cream ghost: no session, nothing captured
##
## The word under it says the same thing in English, so the state is never
## colour-only. Drawn in `_draw()`; `level` and `state` are plain properties
## the HUD pushes each frame.

const Palette := preload("res://scripts/ui/palette.gd")
const Typography := preload("res://scripts/ui/typography.gd")
const IconGlyphScript := preload("res://scripts/progression/icon_glyph.gd")
const GlyphsScript := preload("res://scripts/tutor/ui/tutor_glyphs.gd")

const STATE_LISTENING: String = "listening"
const STATE_HEARING: String = "hearing"
const STATE_ALIZ: String = "aliz"
const STATE_MUTED: String = "muted"
const STATE_OFF: String = "off"

const CAPTIONS: Dictionary = {
	STATE_LISTENING: "Listening", STATE_HEARING: "I hear you!", STATE_ALIZ: "Aliz is talking",
	STATE_MUTED: "Muted", STATE_OFF: "Mic off",
}
const DISC_COLOURS: Dictionary = {
	STATE_LISTENING: Palette.MINT, STATE_HEARING: Palette.MINT, STATE_ALIZ: Palette.PEACH,
	STATE_MUTED: Palette.LAVENDER, STATE_OFF: Palette.STAR_GHOST,
}

var state: String = STATE_OFF:
	set(value):
		state = value
		_apply()
var level: float = 0.0:
	set(value):
		level = clampf(value, 0.0, 1.0)
		queue_redraw()

var _mic_glyph: Control = null
var _speaker_glyph: Control = null
var _caption: Label = null
var _built: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	_mic_glyph = IconGlyphScript.new()
	_mic_glyph.name = "MicGlyph"
	_mic_glyph.set("glyph", 4)
	_mic_glyph.set("tint", Palette.INK)
	add_child(_mic_glyph)
	_speaker_glyph = GlyphsScript.new()
	_speaker_glyph.name = "SpeakerGlyph"
	_speaker_glyph.set("kind", "speaker")
	_speaker_glyph.set("active", false)
	_speaker_glyph.visible = false
	add_child(_speaker_glyph)
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Typography.apply(_caption, Typography.HELPER)
	_caption.add_theme_color_override("font_color", Palette.INK)
	_caption.add_theme_color_override("font_outline_color", Palette.CREAM)
	_caption.add_theme_constant_override("outline_size", 0)
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	_layout()
	_apply()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()


func caption_text() -> String:
	return _caption.text if _caption != null else ""


func _layout() -> void:
	if not _built:
		return
	var d: float = _disc_diameter()
	var centre: Vector2 = _disc_centre()
	var glyph_rect: Rect2 = Rect2(centre - Vector2(d * 0.27, d * 0.3), Vector2(d * 0.54, d * 0.58))
	_mic_glyph.position = glyph_rect.position
	_mic_glyph.size = glyph_rect.size
	_speaker_glyph.position = centre - Vector2(d * 0.24, d * 0.24)
	_speaker_glyph.size = Vector2(d * 0.48, d * 0.48)
	_caption.position = Vector2(100.0, 10.0)
	_caption.size = Vector2(size.x - 108.0, size.y - 20.0)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _disc_diameter() -> float:
	return minf(64.0, size.y * 0.62)


func _disc_centre() -> Vector2:
	return Vector2(49.0, size.y * 0.5)


func _apply() -> void:
	if not _built:
		return
	_caption.text = String(CAPTIONS.get(state, ""))
	# Speaking is an output state, not a recording state. Keep the textual
	# contract and pair it with waves; muted keeps the same speaker quiet.
	_speaker_glyph.visible = state == STATE_MUTED or state == STATE_ALIZ
	_speaker_glyph.set("active", state == STATE_ALIZ)
	_mic_glyph.visible = state != STATE_MUTED and state != STATE_ALIZ
	_mic_glyph.set("tint", Palette.INK if state != STATE_OFF else Palette.INK_SOFT)
	queue_redraw()


func _draw() -> void:
	if not _built:
		return
	var d: float = _disc_diameter()
	var c: Vector2 = _disc_centre()
	var radius: float = d * 0.5
	var disc: Color = DISC_COLOURS.get(state, Palette.STAR_GHOST)
	var status_panel := StyleBoxFlat.new()
	status_panel.bg_color = disc.lerp(Palette.CREAM, 0.45)
	status_panel.set_corner_radius_all(26)
	draw_style_box(status_panel, Rect2(Vector2.ZERO, size))
	# The level ring: a ghost track and, while listening, an arc that grows
	# with the level from the top clockwise.
	var track: Color = Palette.CREAM
	track.a = 0.9
	draw_arc(c, radius + 8.0, 0.0, TAU, 64, track, 5.0)
	if state == STATE_LISTENING or state == STATE_HEARING:
		# Ink-leaning mint, because the ring sits over a mint rug.
		var arc: Color = Palette.MINT.lerp(Palette.INK, 0.45)
		var sweep: float = TAU * clampf(0.08 + level * 0.92, 0.0, 1.0)
		draw_arc(c, radius + 8.0, -PI * 0.5, -PI * 0.5 + sweep, 64, arc, 5.0)
	# The disc, with a cream rim and the house's soft shine.
	draw_circle(c, radius + 3.0, Palette.CREAM)
	draw_circle(c, radius, disc)
	var shine: Color = Palette.CREAM
	shine.a = 0.45
	draw_circle(c + Vector2(-radius * 0.38, -radius * 0.4), radius * 0.13, shine)
