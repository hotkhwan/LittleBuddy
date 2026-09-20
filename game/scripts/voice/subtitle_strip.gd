extends Control
## The subtitle strip: the English of whatever recorded line is playing.
##
##     var strip: Control = SubtitleStripScript.new()
##     hud.add_child(strip)
##     strip.call("build")
##     strip.call("set_bottom_margin", 150.0)   # clear of the button row
##
## A cream pill with ink text, bottom-centre, hidden whenever nothing is being
## said. It listens to `Voice.line_started` / `line_finished` when the autoload
## exists and can be driven by hand (`show_line()` / `hide_line()`) when it does
## not -- the headless tests and a build without the voice pack both work.
##
## It is a READER'S aid: the pre-reader hears the line; the adult beside them
## sees it. So it is small, it never covers a button (the mount sets the bottom
## margin to clear its own chrome and the joystick is left-anchored, this is
## centred and no wider than `MAX_WIDTH`), and it ignores the mouse entirely.
##
## The helper (Thai) line is NOT here: this shows the recording's English and
## nothing else. English is the teaching language; the helper stays on the HUD.

const Palette := preload("res://scripts/ui/palette.gd")

const FONT_SIZE: int = 30
## Smaller sizes tried in order when the line does not fit between the side
## clearances (a phone-width viewport); ellipsis only after the smallest.
const FONT_SIZES: Array[int] = [30, 27, 24, 22]
const HEIGHT: float = 58.0
const MAX_WIDTH: float = 760.0
const PAD_X: float = 28.0
const DEFAULT_SIDE_CLEARANCE: float = 24.0
## Design-size fallback when there is no viewport to measure (headless).
const FALLBACK_VIEWPORT: Vector2 = Vector2(1366.0, 1024.0)
const CORNER_RADIUS: int = 29
const BORDER_WIDTH: int = 3
const DEFAULT_BOTTOM_MARGIN: float = 24.0
## A hidden line stays readable for a beat after the audio ends, so a two-word
## line ("Yay!") does not blink.
const LINGER_SECONDS: float = 0.45
## Each character gets a tinted border so a glance says who is talking.
const BORDER_COLORS: Dictionary = {
	"aliz": Palette.PEACH,
	"bunny": Palette.DUSTY_BLUE,
}

const VOICE_PATH: String = "/root/Voice"

var _pill: PanelContainer = null
var _label: Label = null
var _style: StyleBoxFlat = null
var _built: bool = false
var _bottom_margin: float = DEFAULT_BOTTOM_MARGIN
var _side_clearance: float = DEFAULT_SIDE_CLEARANCE
var _current_line: String = ""
var _voice: Node = null
var _linger_serial: int = 0


func _ready() -> void:
	build()
	_bind_voice()


func _exit_tree() -> void:
	_unbind_voice()


## Idempotent. Builds the pill; callable outside the tree.
func build() -> void:
	if _built:
		return
	_built = true
	if String(name).is_empty():
		name = "SubtitleStrip"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_style = StyleBoxFlat.new()
	_style.bg_color = Palette.CREAM
	_style.set_corner_radius_all(CORNER_RADIUS)
	_style.set_border_width_all(BORDER_WIDTH)
	_style.border_color = Palette.PEACH
	_style.content_margin_left = PAD_X
	_style.content_margin_right = PAD_X
	_style.content_margin_top = 8.0
	_style.content_margin_bottom = 8.0
	_style.shadow_color = Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.16)
	_style.shadow_size = 6
	_style.shadow_offset = Vector2(0.0, 3.0)

	_pill = PanelContainer.new()
	_pill.name = "Pill"
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_theme_stylebox_override("panel", _style)
	_pill.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_pill)

	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", Palette.INK)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pill.add_child(_label)

	_layout()
	_pill.visible = false


# -----------------------------------------------------------------------------
# Public
# -----------------------------------------------------------------------------


## Pixels between the pill's bottom edge and the bottom of this control. The
## mount sets it to clear its own buttons.
func set_bottom_margin(pixels: float) -> void:
	build()
	_bottom_margin = maxf(pixels, 0.0)
	_layout()


func get_bottom_margin() -> float:
	return _bottom_margin


## Pixels the pill keeps clear of the left and right screen edges -- the mount
## sets it past its own side chrome (the joystick's rest ring, a Back button).
func set_side_clearance(pixels: float) -> void:
	build()
	_side_clearance = maxf(pixels, 0.0)
	_layout()


func get_side_clearance() -> float:
	return _side_clearance


## The pill's rect in this control's coordinates, for keep-out checks.
func pill_rect() -> Rect2:
	build()
	return Rect2(_pill.position, _pill.size)


## Where the pill lands in a viewport of `viewport_size` for `bottom_margin`
## and `side_clearance`, as a static rect so layout tests need no frame.
## `text_width` defaults to the widest the pill can be.
static func rect_for(viewport_size: Vector2, bottom_margin: float,
		side_clearance: float = DEFAULT_SIDE_CLEARANCE, text_width: float = MAX_WIDTH) -> Rect2:
	var width: float = clampf(text_width + PAD_X * 2.0, HEIGHT, max_pill_width(viewport_size, side_clearance))
	var top: float = viewport_size.y - bottom_margin - HEIGHT
	return Rect2(viewport_size.x * 0.5 - width * 0.5, top, width, HEIGHT)


static func max_pill_width(viewport_size: Vector2, side_clearance: float) -> float:
	return maxf(minf(MAX_WIDTH, viewport_size.x - 2.0 * side_clearance), HEIGHT)


func show_line(line_id: String, character: String, text: String) -> void:
	build()
	_linger_serial += 1
	_current_line = line_id
	_label.text = text.strip_edges()
	_style.border_color = BORDER_COLORS.get(character, Palette.PEACH)
	_pill.visible = not _label.text.is_empty()
	_layout()


func hide_line(line_id: String = "") -> void:
	build()
	if not line_id.is_empty() and line_id != _current_line:
		return  # an older line finishing must not hide the newer one
	_current_line = ""
	_linger_serial += 1
	var serial: int = _linger_serial
	if not is_inside_tree() or LINGER_SECONDS <= 0.0:
		_pill.visible = false
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		_pill.visible = false
		return
	tree.create_timer(LINGER_SECONDS).timeout.connect(func() -> void:
		if serial == _linger_serial and _current_line.is_empty():
			_pill.visible = false
	, CONNECT_ONE_SHOT)


func is_showing() -> bool:
	return _built and _pill.visible and not _current_line.is_empty()


func get_text() -> String:
	return _label.text if _built else ""


func get_current_line() -> String:
	return _current_line


## Binds to `voice` (anything with `line_started`/`line_finished`). Called
## automatically for `/root/Voice`; a test hands in its own director.
func bind_voice(voice: Node) -> void:
	_unbind_voice()
	_voice = voice
	if _voice == null:
		return
	if _voice.has_signal("line_started") and not _voice.line_started.is_connected(show_line):
		_voice.line_started.connect(show_line)
	if _voice.has_signal("line_finished") and not _voice.line_finished.is_connected(hide_line):
		_voice.line_finished.connect(hide_line)
	# Already mid-line when mounted (a HUD built during a welcome): show it.
	if _voice.has_method("is_speaking") and bool(_voice.call("is_speaking")) \
			and _voice.has_method("current_line") and _voice.has_method("current_character") \
			and _voice.has_method("current_text"):
		show_line(String(_voice.call("current_line")), String(_voice.call("current_character")),
				String(_voice.call("current_text")))


func is_bound() -> bool:
	return _voice != null and is_instance_valid(_voice)


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------


func _bind_voice() -> void:
	if is_bound():
		return
	var found: Node = get_node_or_null(VOICE_PATH)
	if found != null:
		bind_voice(found)


func _unbind_voice() -> void:
	if _voice == null or not is_instance_valid(_voice):
		_voice = null
		return
	if _voice.has_signal("line_started") and _voice.line_started.is_connected(show_line):
		_voice.line_started.disconnect(show_line)
	if _voice.has_signal("line_finished") and _voice.line_finished.is_connected(hide_line):
		_voice.line_finished.disconnect(hide_line)
	_voice = null


func _layout() -> void:
	if _pill == null:
		return
	var view: Vector2 = FALLBACK_VIEWPORT
	if is_inside_tree():
		var rect_size: Vector2 = get_viewport_rect().size
		if rect_size.x > 0.0 and rect_size.y > 0.0:
			view = rect_size
	var available: float = max_pill_width(view, _side_clearance)
	var font: Font = _label.get_theme_font("font")
	var text_width: float = 0.0
	var size: int = FONT_SIZE
	if font != null and not _label.text.is_empty():
		for candidate: int in FONT_SIZES:
			size = candidate
			text_width = font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, candidate).x
			if text_width + PAD_X * 2.0 <= available:
				break
	_label.add_theme_font_size_override("font_size", size)
	var width: float = clampf(text_width + PAD_X * 2.0, HEIGHT, available)
	_pill.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pill.offset_left = -width * 0.5
	_pill.offset_right = width * 0.5
	_pill.offset_top = -_bottom_margin - HEIGHT
	_pill.offset_bottom = -_bottom_margin
	_pill.custom_minimum_size = Vector2(width, HEIGHT)
	_pill.size = Vector2(width, HEIGHT)
