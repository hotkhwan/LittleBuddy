@tool
class_name IconGlyph
extends TextureRect

## One UI icon from the bundled Nieobie Game Icon Pack (CC0), sized to fill the
## control and tinted with `tint`.
##
## Every piece of child-facing iconography in the game comes from here, so the
## star on the counter, the star in the celebration and the star on the summary
## are the *same* star. This used to be a `_draw()` polygon per glyph, which is
## why the old UI mixed hand-drawn arrows with an imported mic.
##
## The copies under `assets/ui/icons/` are derived from the pack's `no-padding`
## variants and then re-boxed onto one shared optical grid: each tight viewBox is
## squared around its own centre and expanded so the artwork covers 86% of the
## box. A mic, a star and an arrow therefore match at the same control size
## without per-icon fiddling -- and none of them is left swimming in the ~20% of
## dead margin per side that the pack's `padding` variants carry, which is what
## made the Speak mic read small inside its 240px circle.
##
## They ship `fill="currentColor"` (which Godot resolves to black, and `modulate`
## multiplies, so tinting would silently fail); the bundled copies are re-filled
## white -- see `docs/ASSET_SOURCING_PLAN.md` §6.
##
## Purely decorative -- it never eats a touch (`MOUSE_FILTER_IGNORE`), so it can
## sit inside a `Button` without stealing its input.
##
## `tint` drives `self_modulate`, never `modulate`, so a caller (the celebration
## fade, say) still owns `modulate` for animation.

enum Glyph {
	STAR,
	BACK,
	NEXT,
	PLAY,
	MIC,
	## The sticker book. A treasure chest, not a book: a child who cannot read a
	## spine still knows a chest is where the things they collected live.
	STICKERS,
	SETTINGS,
}

const ICON_PATHS: Dictionary = {
	Glyph.STAR: "res://assets/ui/icons/star.svg",
	Glyph.BACK: "res://assets/ui/icons/arrow_left.svg",
	Glyph.NEXT: "res://assets/ui/icons/next.svg",
	Glyph.PLAY: "res://assets/ui/icons/play.svg",
	Glyph.MIC: "res://assets/ui/icons/mic.svg",
	Glyph.STICKERS: "res://assets/ui/icons/stickers.svg",
	Glyph.SETTINGS: "res://assets/ui/icons/settings.svg",
}

@export var glyph: Glyph = Glyph.STAR:
	set(value):
		glyph = value
		_apply_texture()

@export var tint: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		tint = value
		self_modulate = value

## A coloured disc behind the icon, drawn in `_draw()` before the texture.
##
## Added after the owner called the icons dull: a white glyph tinted ink on a
## cream button is legible but flat, and a child's eye slides off it. A pastel
## disc under the same glyph makes it read as a *sticker* -- brighter,
## rounder, friendlier -- without touching the icon set. Fully transparent
## (the default) draws nothing, so every existing scene is pixel-identical
## until it asks for one. Rim is `Palette.deep()` of the backing, never a new
## colour and never black.
@export var backing_color: Color = Color(1.0, 1.0, 1.0, 0.0):
	set(value):
		backing_color = value
		queue_redraw()

## How much of the control the disc fills. 1.0 touches the edges.
@export_range(0.5, 1.0) var backing_scale: float = 0.96:
	set(value):
		backing_scale = value
		queue_redraw()

const _Palette := preload("res://scripts/ui/palette.gd")
const BACKING_RIM_PX: float = 3.0


func _init() -> void:
	# Set here rather than in the scene files: the TextureRect default
	# (EXPAND_KEEP_SIZE) reports the full 240px source as the minimum size, which
	# would blow every container this sits in wide open.
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_texture()
	self_modulate = tint


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## Runs BEFORE the built-in texture draw (the base class handles its
## `NOTIFICATION_DRAW` after the script's `_draw()`), so the disc sits behind
## the glyph.
func _draw() -> void:
	if backing_color.a <= 0.001:
		return
	var radius: float = minf(size.x, size.y) * 0.5 * clampf(backing_scale, 0.5, 1.0)
	if radius <= 0.0:
		return
	var centre: Vector2 = size * 0.5
	var rim: Color = _Palette.deep(backing_color)
	rim.a = backing_color.a
	draw_circle(centre, radius, rim)
	draw_circle(centre, maxf(radius - BACKING_RIM_PX, 0.0), backing_color)
	# A soft shine top-left, the house's shared shape language.
	var shine: Color = _Palette.CREAM
	shine.a = 0.55 * backing_color.a
	draw_circle(centre + Vector2(-radius * 0.34, -radius * 0.36), radius * 0.2, shine)


func _apply_texture() -> void:
	var path: String = String(ICON_PATHS.get(glyph, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		# A missing icon must never take the screen down with it.
		texture = null
		return
	texture = load(path)
