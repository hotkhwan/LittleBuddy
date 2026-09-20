extends Control

## Two small chunky-ink glyphs the icon pack does not have: a SPEAKER (the mute
## toggle, waves off when muted -- never a slash, never an X) and a LISTENING
## RING (the pulse round the microphone). Drawn in `_draw()` in the sheet's
## style: rounded, filled, ink on pastel. `kind` picks which.

const Palette := preload("res://scripts/ui/palette.gd")

const KIND_SPEAKER: String = "speaker"
const KIND_RING: String = "ring"

var kind: String = KIND_SPEAKER:
	set(value):
		kind = value
		queue_redraw()
var tint: Color = Palette.INK:
	set(value):
		tint = value
		queue_redraw()
## Speaker: waves shown. Ring: pulsing.
var active: bool = true:
	set(value):
		active = value
		queue_redraw()
## 0..1 pulse phase for the ring; the HUD advances it.
var phase: float = 0.0:
	set(value):
		phase = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	if s <= 2.0:
		return
	var c: Vector2 = size * 0.5
	match kind:
		KIND_SPEAKER:
			# Body: a small box and a trapezoid cone, ink.
			draw_rect(Rect2(c + Vector2(-s * 0.36, -s * 0.13), Vector2(s * 0.16, s * 0.26)), tint)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 0.22, -s * 0.13), c + Vector2(-s * 0.02, -s * 0.32),
				c + Vector2(-s * 0.02, s * 0.32), c + Vector2(-s * 0.22, s * 0.13),
			]), tint)
			if active:
				draw_arc(c + Vector2(-s * 0.02, 0.0), s * 0.17, -0.9, 0.9, 12, tint, s * 0.07)
				draw_arc(c + Vector2(-s * 0.02, 0.0), s * 0.3, -0.9, 0.9, 14, tint, s * 0.07)
			else:
				# Quiet: a single soft dot where the sound would be.
				var quiet: Color = tint
				quiet.a = 0.45
				draw_circle(c + Vector2(s * 0.18, 0.0), s * 0.05, quiet)
		KIND_RING:
			if not active:
				return
			# Two rings breathing outward from just outside the button's rim
			# (the control is the button plus a pad either side, so the rim is
			# at ~0.37 of the control's size) to the control's edge.
			var t: float = fmod(phase, 1.0)
			for i: int in range(2):
				var k: float = fmod(t + float(i) * 0.5, 1.0)
				var radius: float = s * (0.40 + 0.09 * k)
				var colour: Color = tint
				colour.a = (1.0 - k) * 0.9
				draw_arc(c, radius, 0.0, TAU, 48, colour, s * 0.03)
