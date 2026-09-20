extends Node3D

## The LESSON BOARD on the classroom's back wall: a framed pastel panel that
## shows the current flashcard large. The card is the same `FlashcardArt`
## control the HUD draws, rendered once into a `SubViewport` whose texture is
## the panel's albedo -- so the wall and the HUD can never disagree about what
## the child is being asked. The viewport re-renders only when the card
## changes (`UPDATE_ONCE`), which is what keeps it inside the Mobile renderer
## budget: a static texture between turns, not a second scene every frame.

const FlashcardArtScript := preload("res://scripts/tutor/classroom/flashcard_art.gd")
const Palette := preload("res://scripts/ui/palette.gd")

const CARD_PIXELS: int = 512
const BOARD_WIDTH: float = 1.16
const BOARD_HEIGHT: float = 0.96
const FRAME_DEPTH: float = 0.05
const CARD_SIZE: float = 0.78

var _viewport: SubViewport = null
var _card: Control = null
var _frame: MeshInstance3D = null
var _panel: MeshInstance3D = null
var _card_mesh: MeshInstance3D = null
var _asset_id: String = ""
var _built: bool = false


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	name = "LessonBoard"

	_frame = MeshInstance3D.new()
	_frame.name = "Frame"
	var frame_mesh: BoxMesh = BoxMesh.new()
	frame_mesh.size = Vector3(BOARD_WIDTH, BOARD_HEIGHT, FRAME_DEPTH)
	_frame.mesh = frame_mesh
	_frame.material_override = _flat(Palette.deep(Palette.PEACH))
	add_child(_frame)

	_panel = MeshInstance3D.new()
	_panel.name = "Panel"
	var panel_mesh: BoxMesh = BoxMesh.new()
	panel_mesh.size = Vector3(BOARD_WIDTH - 0.1, BOARD_HEIGHT - 0.1, 0.02)
	_panel.mesh = panel_mesh
	_panel.material_override = _flat(Palette.light(Palette.MINT))
	_panel.position = Vector3(0.0, 0.0, FRAME_DEPTH * 0.5 + 0.005)
	add_child(_panel)

	_viewport = SubViewport.new()
	_viewport.name = "CardViewport"
	_viewport.size = Vector2i(CARD_PIXELS, CARD_PIXELS)
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_card = FlashcardArtScript.new()
	_card.name = "Card"
	_card.size = Vector2(CARD_PIXELS, CARD_PIXELS)
	_viewport.add_child(_card)

	_card_mesh = MeshInstance3D.new()
	_card_mesh.name = "CardQuad"
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(CARD_SIZE, CARD_SIZE)
	_card_mesh.mesh = quad
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.albedo_texture = _viewport.get_texture()
	material.roughness = 1.0
	_card_mesh.material_override = material
	_card_mesh.position = Vector3(0.0, 0.0, FRAME_DEPTH * 0.5 + 0.02)
	add_child(_card_mesh)
	_card_mesh.visible = false


## Shows `asset_id` on the board; an empty id clears it back to the plain panel.
func show_card(asset_id: String) -> void:
	build()
	_asset_id = asset_id
	if asset_id.is_empty():
		_card_mesh.visible = false
		return
	_card.set("asset_id", asset_id)
	_card_mesh.visible = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func current_card() -> String:
	return _asset_id


func is_showing_card() -> bool:
	return _card_mesh != null and _card_mesh.visible


static func _flat(colour: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.95
	material.metallic = 0.0
	return material
