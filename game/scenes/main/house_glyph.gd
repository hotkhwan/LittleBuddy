@tool
extends Control

## The Home icon: the house.
##
## This used to draw a house from rounded rectangles as a stand-in, with the
## note that once an art pass produced a house icon the drawing would go. The
## owner's UI pack (2026-09-21) produced it -- the pink-roofed house the title
## logo shows -- so this is now a thin shim over that picture
## (`IconGlyph.Glyph.PICTURE_HOUSE`), kept as a script so the five Home buttons
## that construct it (`house_hud.gd`, `tutor_hud.gd`, `pause_menu.gd`,
## `break_card.gd`, `tutor_break_card.gd`) and the tests that look for a node
## named `HouseGlyph` all change picture at once and edit nothing.
##
## `tint`, `face_color` and `window_color` are accepted and ignored: the picture
## is already coloured. Drawn on the same 86% optical box as every other icon,
## with mipmaps, because the 256 px source is always shown smaller than it is.
##
## Purely decorative -- `MOUSE_FILTER_IGNORE`, so it never eats the press meant
## for the `Button` it sits inside.

const _IconGlyph := preload("res://scripts/progression/icon_glyph.gd")
const TEXTURE_PATH: String = "res://assets/ui/icons/pictures/house.png"

## Kept for the callers that set them. They no longer affect the picture.
@export var tint: Color = Color(0.349, 0.259, 0.169):
	set(value):
		tint = value
@export var face_color: Color = Color(0.984, 0.820, 0.675):
	set(value):
		face_color = value
@export var window_color: Color = Color(0.984, 0.820, 0.675):
	set(value):
		window_color = value

var _texture: Texture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## The picture this draws, for tests: the same file `IconGlyph` uses for Home.
static func texture_path() -> String:
	return String(_IconGlyph.ICON_PATHS.get(_IconGlyph.Glyph.PICTURE_HOUSE, TEXTURE_PATH))


func _load() -> void:
	if _texture != null:
		return
	var path: String = texture_path()
	# A missing picture must never take the screen down with it.
	if ResourceLoader.exists(path):
		_texture = load(path) as Texture2D


func _draw() -> void:
	_load()
	if _texture == null:
		return
	var box: float = minf(size.x, size.y)
	if box <= 0.0:
		return
	var origin: Vector2 = Vector2((size.x - box) * 0.5, (size.y - box) * 0.5)
	draw_texture_rect(_texture, Rect2(origin, Vector2(box, box)), false)
