extends Control

## The look of the grown-up entry affordance: a soft cream disc, the bundled
## Nieobie settings icon, and a dusty-blue ring that fills while the gate is
## being held.
##
## Sits as a child of a `ParentalGate` in RING style, which keeps all of the
## input and timing logic (and which is owned by another agent, so its own
## hand-drawn gear is switched off from the scene instead: the gate's
## `self_modulate` alpha is 0, which hides its `_draw()` output without touching
## its children).
##
## Purely decorative: `MOUSE_FILTER_IGNORE`, so every touch still reaches the
## gate underneath. It finds and connects to its own parent, so the scene needs
## nothing but the node.

const ICON: Texture2D = preload("res://assets/ui/icons/settings.svg")

const DISC_COLOR: Color = Color(1.0, 0.957, 0.886, 0.78)
const RIM_COLOR: Color = Color(0.83, 0.78, 0.70, 0.5)
## Dusty blue, matching `ParentalGate.accent_color`.
const ACCENT: Color = Color(0.42, 0.56, 0.72)

## Idle opacity of the gear itself. Deliberately low: this reads as "settings",
## not as part of the game, so a child has no reason to poke it.
const IDLE_ALPHA: float = 0.55

var _progress: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)

	var gate: Node = get_parent()
	if gate != null and gate.has_signal("progress_changed") \
			and not gate.is_connected("progress_changed", set_progress):
		gate.connect("progress_changed", set_progress)


func set_progress(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, _progress):
		return
	_progress = clamped
	queue_redraw()


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	if side <= 4.0:
		return

	var center: Vector2 = size * 0.5
	var radius: float = side * 0.5 - 2.0

	draw_circle(center, radius, DISC_COLOR)
	draw_arc(center, radius, 0.0, TAU, 32, RIM_COLOR, 2.0, true)

	var icon_side: float = side * 0.58
	var icon_rect: Rect2 = Rect2(
		center - Vector2(icon_side, icon_side) * 0.5, Vector2(icon_side, icon_side))
	var gear: Color = Color(ACCENT.r, ACCENT.g, ACCENT.b, lerpf(IDLE_ALPHA, 1.0, _progress))
	draw_texture_rect(ICON, icon_rect, false, gear)

	if _progress > 0.0:
		draw_arc(center, radius - 1.0, -PI * 0.5, -PI * 0.5 + TAU * _progress, 48,
				ACCENT, maxf(side * 0.08, 3.0), true)
