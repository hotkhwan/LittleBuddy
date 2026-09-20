class_name HelperFont
extends RefCounted
## The font the helper line is drawn with, and which languages it can draw.
##
##     HelperFont.apply(label)                 # the helper label renders every shipped script
##     HelperFont.language_available("zh")     # false when this device has no CJK font
##
## ## Why this exists
##
## The project ships no font of its own; Godot's default font (Open Sans) covers
## Latin and reaches other scripts through the OS at shaping time
## (`allow_system_fallback`). That has carried Thai on the iPad since the first
## build, and on this Mac it also carries Arabic and Devanagari (see
## `docs/shots/house_helper_*`). It does NOT reliably carry Han: on macOS 26 the
## system hands back `PingFangUI.ttc` from a private, reserved path that
## FreeType cannot open, and the child would see tofu boxes for 中文 and 日本語.
##
## So the helper font is the default font with an EXPLICIT fallback chain of
## system fonts that are proven, at runtime, to load and to hold the glyphs
## (`SystemFont.has_char()` is false for a font FreeType could not open). A
## family that does not validate is simply not added -- an invalid entry in the
## chain breaks shaping for every non-Latin run, which the probe in
## `docs/shots/_fontprobe.png` showed.
##
## A language whose probe string the chain cannot draw is reported to
## `Localization` as unavailable, and the settings selector says so instead of
## offering tofu. Thai, Arabic and Hindi are treated as available regardless,
## because the default font's own fallback demonstrably draws them; only the
## two Han languages depend on the chain.
##
## No bundled font: the candidates below ship with macOS and iOS (PingFang,
## Hiragino), and the free ones (Noto CJK, Droid Sans Fallback) are listed for
## desktops that have them. Nothing here reaches the network.

const Localization := preload("res://scripts/localization/localization.gd")

## Families tried for Han + kana, best first. iOS ships PingFang SC and
## Hiragino Sans; macOS additionally Hiragino Sans GB (which covers Simplified
## Chinese AND Japanese in one file, so it comes first).
const CJK_CANDIDATES: Array[String] = [
	"Hiragino Sans GB", "PingFang SC", "Hiragino Sans", "Hiragino Kaku Gothic ProN",
	"Noto Sans CJK SC", "Noto Sans CJK JP", "Noto Sans SC", "Noto Sans JP",
	"Source Han Sans SC", "Droid Sans Fallback", "Microsoft YaHei", "Meiryo",
]
## Extra families for the other scripts. Optional: the default font already
## reaches them through system fallback; listing them just makes the chain
## explicit where the OS has them.
const SCRIPT_CANDIDATES: Dictionary = {
	"th": ["Thonburi", "Noto Sans Thai"],
	"ar": ["Geeza Pro", "Noto Naskh Arabic", "Noto Sans Arabic"],
	"hi": ["Kohinoor Devanagari", "Devanagari Sangam MN", "Noto Sans Devanagari"],
}
## One character per candidate family that it must hold to count as loaded.
const CJK_PROBE_CHAR: int = 0x8A9E  # 語
const SCRIPT_PROBE_CHAR: Dictionary = {"th": 0x0E44, "ar": 0x0639, "hi": 0x0939}

## What each language must be able to draw before the selector offers it.
const LANGUAGE_PROBES: Dictionary = {
	"zh": "中文我们来冲牛奶吧",
	"ja": "日本語ミルクを作ろう",
	"th": "ไทยดื่มนม",
	"ar": "العربية",
	"hi": "हिन्दी",
}
## Drawn by the default font's system fallback on macOS and iOS (verified in
## frames); never gated on the chain.
const ALWAYS_AVAILABLE: Array[String] = ["th", "ar", "hi"]

static var _font: FontVariation = null
static var _availability: Dictionary = {}
static var _chain_names: Array[String] = []


## The helper font: default base, validated system fallbacks. Built once.
static func font() -> Font:
	if _font == null:
		_build()
	return _font


## Puts the helper font on a Control (Label, Button) as its `font` override.
static func apply(control: Control) -> void:
	if control == null:
		return
	control.add_theme_font_override("font", font())


## Whether the chain can draw `code`'s probe string. Also pushed into
## `Localization` by `_build()`, so the lookup itself honours it.
static func language_available(code: String) -> bool:
	if _font == null:
		_build()
	return bool(_availability.get(code, true))


## `{code: available}` for every shipped language. Diagnostics and tests.
static func availability() -> Dictionary:
	if _font == null:
		_build()
	return _availability.duplicate()


## The family names that validated, in chain order. Diagnostics and the runbook.
static func chain_names() -> Array[String]:
	if _font == null:
		_build()
	return _chain_names.duplicate()


## Forgets the built chain so it is probed again. Tests.
static func reset() -> void:
	_font = null
	_availability.clear()
	_chain_names.clear()


## True when a `SystemFont` for `family` both loads and holds `probe_char`.
## `has_char()` is false for a family the OS names but FreeType cannot open.
static func validate_family(family: String, probe_char: int) -> SystemFont:
	if family.is_empty():
		return null
	# Resolve the file first, so a family the OS names but cannot hand over is
	# skipped without FreeType logging an error for it. macOS 26 answers
	# "PingFang SC" with a reserved file under PrivateFrameworks that FreeType
	# cannot open; iOS keeps the same family under /System/Library/Fonts.
	var path: String = OS.get_system_font_path(family)
	if path.is_empty() or path.contains("/PrivateFrameworks/") or not FileAccess.file_exists(path):
		return null
	var candidate: SystemFont = SystemFont.new()
	candidate.font_names = PackedStringArray([family])
	if not candidate.has_char(probe_char):
		return null
	return candidate


## Whether `font_to_test` holds every non-space character of `text`.
static func can_draw(text: String, font_to_test: Font) -> bool:
	if font_to_test == null:
		return false
	for character: String in text:
		var point: int = character.unicode_at(0)
		if point <= 32:
			continue
		if not font_to_test.has_char(point):
			return false
	return true


static func _build() -> void:
	var variation: FontVariation = FontVariation.new()
	variation.base_font = ThemeDB.fallback_font
	var fallbacks: Array[Font] = []
	_chain_names.clear()
	for family: String in CJK_CANDIDATES:
		var valid: SystemFont = validate_family(family, CJK_PROBE_CHAR)
		if valid != null:
			fallbacks.append(valid)
			_chain_names.append(family)
	for code: String in SCRIPT_CANDIDATES.keys():
		for family: String in SCRIPT_CANDIDATES[code]:
			var valid: SystemFont = validate_family(family, int(SCRIPT_PROBE_CHAR[code]))
			if valid != null:
				fallbacks.append(valid)
				_chain_names.append(family)
				break
	variation.fallbacks = fallbacks
	_font = variation

	_availability.clear()
	for code: String in LANGUAGE_PROBES.keys():
		var available: bool = ALWAYS_AVAILABLE.has(code) \
				or can_draw(String(LANGUAGE_PROBES[code]), _font)
		_availability[code] = available
		Localization.set_language_available(code, available)
