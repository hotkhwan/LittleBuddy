extends RefCounted

## Legibility of every piece of child-facing (and grown-up-facing) text.
##
## The palette is deliberately pastel, which makes light-on-light the easy
## mistake to make and the hard one to see on a bright desk. Every label is
## checked against the colour it actually sits on -- the frame face it is
## printed over, or the panel behind it -- using the WCAG 2.1 contrast ratio.
##
## Thresholds are WCAG AA: 4.5:1 for body text, 3.0:1 for large text (>= 24pt
## regular, which at this project's 1366x1024 design scale is a font_size of
## about 32). Text on a child-facing button is held to the large-text rule
## because it is never smaller than that and never carries information the icon
## does not already carry.

const BABY_ROOM_SCENE: String = "res://scenes/baby_room/baby_room.tscn"
const PARENT_SCENE: String = "res://scenes/parent/parent_settings.tscn"
const SUMMARY_SCENE: String = "res://scenes/progression/session_summary.tscn"
const STICKER_BOOK_SCENE: String = "res://scenes/progression/sticker_book.tscn"

const StickerCellScript := preload("res://scripts/progression/sticker_cell.gd")

## Face colours of the re-paletted Kenney frames, i.e. what a label printed on
## one of them is actually sitting on. Kept here rather than read back out of
## the texture so a failure names a colour a human can look up in the SVG.
const CREAM_PANEL: Color = Color(1.0, 0.957, 0.878)     # panel_cream  #FFF4E0
const PINK_FACE: Color = Color(0.973, 0.749, 0.820)     # btn_pink     #F8BFD1
const LAVENDER_FACE: Color = Color(0.780, 0.753, 0.918) # btn_lavender #C7C0EA
const MINT_FACE: Color = Color(0.620, 0.863, 0.765)     # btn_mint     #9EDCC3
const PEACH_FACE: Color = Color(0.984, 0.820, 0.675)    # btn_peach    #FBD1AC
const BLUE_FACE: Color = Color(0.663, 0.784, 0.886)     # btn_blue     #A9C8E2
const CREAM_FLAT: Color = Color(1.0, 0.957, 0.878)      # btn_cream_flat face
const MINT_DOWN_FACE: Color = Color(0.337, 0.698, 0.580) # btn_mint_down #56B294

## Font size at which this project's design scale crosses WCAG "large text".
const LARGE_TEXT_SIZE: int = 32

const AA_NORMAL: float = 4.5
const AA_LARGE: float = 3.0

## `scene path -> { node path: background colour }`
const CHECKS: Dictionary = {
	BABY_ROOM_SCENE: {
		"UI/SafeArea/StarCounter/StarCountLabel": CREAM_PANEL,
		"UI/SafeArea/TopStack/SpeechBubble/SpeechBubbleVBox/PromptLabel": CREAM_PANEL,
		"UI/SafeArea/TopStack/SpeechBubble/SpeechBubbleVBox/ThaiHintLabel": CREAM_PANEL,
		"UI/SafeArea/StickerButton/StickerCaption": PINK_FACE,
		"UI/SafeArea/NextButton/NextCaption": LAVENDER_FACE,
		"UI/SafeArea/MicButton/MicCaption": MINT_FACE,
		"UI/SafeArea/ListeningLabel": CREAM_PANEL,
		"UI/SafeArea/EncouragementLabel": CREAM_PANEL,
	},
	SUMMARY_SCENE: {
		"SafeArea/Center/Panel/Margin/VBox/TitleLabel": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/VBox/LevelLabel": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/VBox/EncourageLabel": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/VBox/ScoreRow/EarnedRow/EarnedLabel": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/VBox/ScoreRow/TotalRow/TotalLabel": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/VBox/StickerRow/StickerLabel": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/VBox/Buttons/PlayAgainButton/PlayAgainLabel": MINT_FACE,
		"SafeArea/Center/Panel/Margin/VBox/Buttons/NextButton/NextLabel": MINT_FACE,
	},
	STICKER_BOOK_SCENE: {
		"SafeArea/Layout/Header/Title": CREAM_PANEL,
		"SafeArea/Layout/Header/Progress/ProgressRow/CountLabel": CREAM_PANEL,
	},
	PARENT_SCENE: {
		"SafeArea/Center/Panel/Margin/Content/Header/Title": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/Subtitle": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/MusicRow/MusicText/MusicTitle": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/MusicRow/MusicText/MusicHelp": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/MusicRow/MusicSliderBox/MusicValue": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/VoiceVolumeRow/VoiceVolumeText/VoiceVolumeTitle": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/VoiceVolumeRow/VoiceVolumeText/VoiceVolumeHelp": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/HelperRow/HelperText/HelperTitle": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/HelperRow/HelperText/HelperHelp": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/TeachingRow/TeachingText/TeachingTitle": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/TeachingRow/TeachingText/TeachingHelp": CREAM_PANEL,
		"SafeArea/GateScreen/GateCard/GateMargin/GateColumn/GateTitle": CREAM_PANEL,
		"SafeArea/GateScreen/GateCard/GateMargin/GateColumn/GateHelp": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/VoiceRow/VoiceText/VoiceTitle": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/VoiceRow/VoiceText/VoiceHelp": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/SpeedRow/SpeedText/SpeedTitle": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/SpeedRow/SpeedText/SpeedHelp": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/BottomRow/StarsBox/StarsLabel": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/ConfirmBox/ConfirmText": CREAM_PANEL,
		"SafeArea/Center/Panel/Margin/Content/StatusLabel": CREAM_PANEL,
	},
}

## Buttons whose two label colours both have to survive: `font_color` on the
## unselected face and `font_pressed_color` on the selected one.
const TOGGLE_BUTTONS: Array[String] = [
	"SafeArea/Center/Panel/Margin/Content/HelperRow/HelperButtons/HelperOffButton",
	"SafeArea/Center/Panel/Margin/Content/HelperRow/HelperButtons/HelperThButton",
	"SafeArea/Center/Panel/Margin/Content/HelperRow/HelperButtons/HelperZhButton",
	"SafeArea/Center/Panel/Margin/Content/HelperRow/HelperButtons/HelperArButton",
	"SafeArea/Center/Panel/Margin/Content/HelperRow/HelperButtons/HelperHiButton",
	"SafeArea/Center/Panel/Margin/Content/HelperRow/HelperButtons/HelperJaButton",
	"SafeArea/Center/Panel/Margin/Content/VoiceRow/VoiceButtons/VoiceOnButton",
	"SafeArea/Center/Panel/Margin/Content/VoiceRow/VoiceButtons/VoiceOffButton",
	"SafeArea/Center/Panel/Margin/Content/SpeedRow/SpeedButtons/SpeedSlowButton",
	"SafeArea/Center/Panel/Margin/Content/SpeedRow/SpeedButtons/SpeedNormalButton",
]


func test_name() -> String:
	return "ui_contrast"


func run():
	var failures: Array = []
	failures.append_array(_test_labels())
	failures.append_array(_test_toggles())
	failures.append_array(_test_sticker_caption())
	return failures


func _test_labels():
	var failures: Array = []

	for scene_path: Variant in CHECKS.keys():
		var path: String = String(scene_path)
		var packed: PackedScene = load(path) as PackedScene
		if packed == null or not packed.can_instantiate():
			failures.append("%s could not be instantiated" % path)
			continue
		var root: Node = packed.instantiate()

		var entries: Dictionary = CHECKS[scene_path]
		for node_path: Variant in entries.keys():
			var label: Label = root.get_node_or_null(NodePath(String(node_path))) as Label
			if label == null:
				failures.append("%s has no Label at %s" % [path, String(node_path)])
				continue
			failures.append_array(_check(
				"%s %s" % [path.get_file(), String(node_path).get_file()],
				label.get_theme_color("font_color"),
				entries[node_path],
				label.get_theme_font_size("font_size")))

		root.free()

	return failures


func _test_toggles():
	var failures: Array = []

	var packed: PackedScene = load(PARENT_SCENE) as PackedScene
	if packed == null or not packed.can_instantiate():
		return ["%s could not be instantiated" % PARENT_SCENE]
	var root: Node = packed.instantiate()

	for node_path: String in TOGGLE_BUTTONS:
		var button: Button = root.get_node_or_null(NodePath(node_path)) as Button
		if button == null:
			failures.append("the parent screen has no Button at %s" % node_path)
			continue
		var size: int = button.get_theme_font_size("font_size")
		# All four states, not just the two that are easy to remember. A toggle
		# that is both selected and under the finger falls through to
		# `font_hover_pressed_color`, which without an override is the engine
		# theme's near-white -- invisible on a pastel face, and reachable on iOS
		# because a touch synthesises a hover.
		failures.append_array(_check(
			"%s (unselected)" % node_path.get_file(),
			button.get_theme_color("font_color"), CREAM_FLAT, size))
		failures.append_array(_check(
			"%s (unselected, touched)" % node_path.get_file(),
			button.get_theme_color("font_hover_color"), CREAM_FLAT, size))
		failures.append_array(_check(
			"%s (selected)" % node_path.get_file(),
			button.get_theme_color("font_pressed_color"), BLUE_FACE, size))
		failures.append_array(_check(
			"%s (selected, touched)" % node_path.get_file(),
			button.get_theme_color("font_hover_pressed_color"), BLUE_FACE, size))

	var done: Button = root.get_node_or_null(
			NodePath("SafeArea/Center/Panel/Margin/Content/BottomRow/DoneButton")) as Button
	if done != null:
		var size: int = done.get_theme_font_size("font_size")
		failures.append_array(_check("DoneButton",
				done.get_theme_color("font_color"), MINT_FACE, size))
		failures.append_array(_check("DoneButton (pressed)",
				done.get_theme_color("font_pressed_color"), MINT_DOWN_FACE, size))
		failures.append_array(_check("DoneButton (pressed, touched)",
				done.get_theme_color("font_hover_pressed_color"), MINT_DOWN_FACE, size))
	else:
		failures.append("the parent screen has no DoneButton")

	# The two plain (non-toggle) buttons, which share the cream frame and so have
	# the same near-white-on-cream trap in their held state.
	for node_path: String in [
		"SafeArea/Center/Panel/Margin/Content/BottomRow/ResetRow/ResetButton",
		"SafeArea/Center/Panel/Margin/Content/ConfirmBox/ConfirmButtons/CancelResetButton",
		"SafeArea/Center/Panel/Margin/Content/Header/CloseButton",
		"SafeArea/GateScreen/GateCard/GateMargin/GateColumn/GateBackButton",
	]:
		var button: Button = root.get_node_or_null(NodePath(node_path)) as Button
		if button == null:
			failures.append("the parent screen has no Button at %s" % node_path)
			continue
		var size: int = button.get_theme_font_size("font_size")
		for state: String in [
			"font_color", "font_hover_color",
			"font_pressed_color", "font_hover_pressed_color",
		]:
			failures.append_array(_check("%s (%s)" % [node_path.get_file(), state],
					button.get_theme_color(state), CREAM_FLAT, size))

	root.free()
	return failures


## The word under an earned sticker, on the cream card it is printed on.
func _test_sticker_caption():
	return _check("StickerCell caption", StickerCellScript.LABEL_COLOR, CREAM_PANEL,
			int(StickerCellScript.MIN_SIZE.y * StickerCellScript.CAPTION_FONT_RATIO))


# ---------------------------------------------------------------------------
# WCAG 2.1 relative luminance and contrast ratio
# ---------------------------------------------------------------------------

func _check(label: String, foreground: Color, background: Color, font_size: int) -> Array:
	# A translucent label is composited over its background before it is read.
	var text: Color = background.lerp(foreground, foreground.a)
	var ratio: float = contrast_ratio(text, background)
	var required: float = AA_LARGE if font_size >= LARGE_TEXT_SIZE else AA_NORMAL
	if ratio + 0.005 < required:
		return ["%s is %.2f:1 on %s (needs %.1f:1 at font_size %d) -- %s is too light"
				% [label, ratio, background.to_html(false), required, font_size,
					foreground.to_html(false)]]
	return []


static func contrast_ratio(a: Color, b: Color) -> float:
	var la: float = relative_luminance(a)
	var lb: float = relative_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## WCAG's own definition, which is not Godot's `Color.get_luminance()`: the
## channels are linearised first, and the weights differ.
static func relative_luminance(color: Color) -> float:
	return 0.2126 * _linearise(color.r) \
		+ 0.7152 * _linearise(color.g) \
		+ 0.0722 * _linearise(color.b)


static func _linearise(channel: float) -> float:
	var c: float = clampf(channel, 0.0, 1.0)
	if c <= 0.03928:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)
