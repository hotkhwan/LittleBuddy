extends PanelContainer

## DEVELOPMENT-ONLY recognition diagnostic for Learn with Aliz (owner playtest
## 2026-09-21). Shows which stage of the hands-free pipeline is live:
## provider, permission, capture, VAD, recognition, lesson, audio, and the
## session's stage counters. Built only by a debug build (see TutorHud); a
## release build never instantiates this script. Shows names, states and
## counts -- NEVER a transcript.

const Palette := preload("res://scripts/ui/palette.gd")

var _label: Label = null


func build() -> void:
	if _label != null:
		return
	name = "TutorDiagnostics"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.78)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.92, 0.96, 0.92))
	add_child(_label)
	visible = false


func refresh(data: Dictionary) -> void:
	build()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("TUTOR DIAG (dev only)  build=%s" % ("debug" if OS.is_debug_build() else "release"))
	lines.append("Speech provider: %s  backend=%s" % [str(data.get("provider", "?")), str(data.get("backend", "?"))])
	lines.append("Permission: %s   available=%s" % [str(data.get("permission", "unknown")), str(data.get("available", "?"))])
	lines.append("Capture: %s   level=%s   levelSource=%s" % [
		"running" if bool(data.get("capturing", false)) else "stopped", str(data.get("level", 0.0)), str(data.get("levelSource", "?"))])
	lines.append("VAD: %s%s   starts=%s ends=%s pauses=%s" % [str(data.get("vad", "?")),
		" (gated)" if bool(data.get("vadGated", false)) else "", str(data.get("vadStarts", 0)), str(data.get("vadEnds", 0)), str(data.get("longPauses", 0))])
	lines.append("Recognition: %s   open=%s   armed=%s partials=%s finals=%s empty=%s" % [
		str(data.get("recognition", "?")), str(data.get("recognitionOpen", false)), str(data.get("armed", 0)),
		str(data.get("partials", 0)), str(data.get("finals", 0)), str(data.get("emptyFinals", 0))])
	lines.append("  timeouts=%s unavailable=%s refused(busy=%s playback=%s) lastEnd=%s" % [
		str(data.get("timeouts", 0)), str(data.get("unavailable", 0)), str(data.get("refusedBusy", 0)),
		str(data.get("refusedPlayback", 0)), str(data.get("lastRecognitionEnd", ""))])
	lines.append("Session: %s   handsFree=%s   rearm=%s   latchedOff=%s" % [str(data.get("state", "?")),
		str(data.get("handsFreeLive", "?")), str(data.get("rearmPending", false)), str(data.get("unavailableLatched", false))])
	lines.append("Lesson: %s   step=%s   heard=%s" % [str(data.get("lesson", "?")), str(data.get("step", "")), str(data.get("heard", "none"))])
	lines.append("Audio: %s   synth=%s voice=%s tts=%s" % ["playing" if bool(data.get("audioPlaying", false)) else "stopped",
		str(data.get("synthSpeaking", false)), str(data.get("voiceSpeaking", false)), str(data.get("ttsSpeaking", false))])
	_label.text = "\n".join(lines)


func toggle() -> bool:
	build()
	visible = not visible
	return visible
