extends Node3D

## DRESS UP -- a small, complete screen, never a dead one.
##
## The title screen's Dress Up button used to open
## `scenes/activities/dressing.tscn`, an `ActivityScene` that only works with
## the Baby Room's director around it. Opened on its own it showed a grey
## screen with nothing to press, which is the one thing a title-screen button
## must never do (contract §6: no dead ends).
##
## This is what it opens now: the real Aliz, through her production wrapper,
## on a pastel stage; four big colour swatches down the right that recolour
## her OUTFIT ACCENTS at once; a friendly "More outfits soon!" line; and one
## big Back button that returns to the title screen.
##
## ## What the swatches recolour, and why not the dress itself
##
## Her model is a single surface with one 512-square atlas -- the dress, hair
## and skin are all painted into one texture -- so tinting the dress material
## would tint her hair and face with it. Instead the swatch tints ACCESSORY
## primitives pinned to her sockets: a hair bow at `head`, a tutu at `hips`
## and a matching pair of shoe bows at the feet. They follow her sockets the
## way a carried item follows a hand (`carry_controller.gd`: position from
## the socket, orientation the character's own), so a bow does not roll with
## a bone through her idle. The colour of the whole set is one material.
##
## ## Nothing is saved
##
## The chosen colour is remembered for the session only, in
## `SaveService.settings.dressUpTint` when a save service is around, as a
## single string -- a convenience, never progress. Nothing else is written.
##
## ## Budget
##
## One `DirectionalLight3D`, shadows off, no post-processing, primitives.

const Palette := preload("res://scripts/ui/palette.gd")

const MENU_SCENE_PATH: String = "res://scenes/main/main.tscn"
const BUDDY_AVATAR_SCENE_PATH: String = "res://scenes/characters/buddy/PinkGirlBuddy.tscn"

const ALIZ_POSITION := Vector3(-0.2, 0.06, 0.0)
const ALIZ_YAW_DEG: float = 180.0
const CAMERA_POSITION := Vector3(-0.3, 1.25, 3.9)
const CAMERA_TARGET := Vector3(-0.2, 0.8, 0.0)

## The swatches: name -> colour. Four, big, in the order the eye reads them.
const SWATCHES: Dictionary = {
	"pink": Palette.SOFT_PINK,
	"mint": Palette.MINT,
	"lavender": Palette.LAVENDER,
	"sunny": Palette.STAR_EARNED,
}
const DEFAULT_SWATCH: String = "pink"
const SWATCH_SIDE: float = 150.0
const SWATCH_CORNER: int = 40
const TINT_SETTING_KEY: String = "dressUpTint"

const PRESS_SCALE: Vector2 = Vector2(0.92, 0.92)
const PRESS_SECONDS: float = 0.08
const TAP_SFX: String = "gentle_tap"

## World offsets from each socket to its accessory, for a character facing +Z
## (yaw 180). Position only, exactly as a carried item is placed.
const BOW_OFFSET := Vector3(0.15, 0.37, 0.03)
## The frill sits at the hem of her dress, a little below the hips socket.
const TUTU_OFFSET := Vector3(0.0, -0.34, 0.0)
const SHOE_BOW_HEIGHT: float = 0.05

@onready var _back_button: Button = %BackButton
@onready var _swatch_row: BoxContainer = %SwatchRow
@onready var _hint_label: Label = %HintLabel

var _aliz: Node3D = null
var _accent_material: StandardMaterial3D = null
var _accessories: Node3D = null
var _bow: Node3D = null
var _tutu: Node3D = null
var _shoe_bows: Array = []
var _swatch_buttons: Dictionary = {}
var _current_swatch: String = ""
var _leaving: bool = false
var _built: bool = false


func _ready() -> void:
	build()
	var camera: Camera3D = get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET, Vector3.UP)
		camera.current = true
	_back_button.pressed.connect(_on_back_pressed)
	_back_button.button_down.connect(_on_button_down.bind(_back_button))
	_back_button.button_up.connect(_on_button_up.bind(_back_button))
	_build_swatches()
	# Restored, not re-saved: opening the screen writes nothing.
	apply_swatch(_remembered_swatch(), false)


func _process(_delta: float) -> void:
	_pin_accessories()


## Idempotent; callable before `_ready()` (the headless runner).
func build() -> void:
	if _built:
		return
	_built = true
	_build_stage()
	_add_aliz()
	_build_accessories()


## Both worlds answer this (`main.gd::build_scene()` calls it when present);
## Dress Up has no progression at all, so it is accepted and ignored.
func set_progression_mode(_mode: int) -> void:
	pass


# ---------------------------------------------------------------------------
# Swatches
# ---------------------------------------------------------------------------

## Recolours the accents to `swatch_name`. False for a name that is not a
## swatch. Public so a test can press the colour without a button. `remember`
## writes the choice to the save settings (one string) -- the only write here.
func apply_swatch(swatch_name: String, remember: bool = true) -> bool:
	if not SWATCHES.has(swatch_name):
		return false
	build()
	_current_swatch = swatch_name
	var colour: Color = SWATCHES[swatch_name]
	if _accent_material != null:
		_accent_material.albedo_color = colour
	for name: String in _swatch_buttons.keys():
		_style_swatch(_swatch_buttons[name] as Button, name, name == swatch_name)
	if remember:
		_remember_swatch(swatch_name)
	return true


func get_current_swatch() -> String:
	return _current_swatch


## The colour on the accents right now.
func get_accent_colour() -> Color:
	return _accent_material.albedo_color if _accent_material != null else Color.WHITE


func get_swatch_buttons() -> Dictionary:
	return _swatch_buttons.duplicate()


func _build_swatches() -> void:
	if _swatch_row == null:
		return
	for name: String in SWATCHES.keys():
		var button := Button.new()
		button.name = "Swatch_" + name
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(SWATCH_SIDE, SWATCH_SIDE)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_style_swatch(button, name, false)
		button.pressed.connect(_on_swatch_pressed.bind(name))
		button.button_down.connect(_on_button_down.bind(button))
		button.button_up.connect(_on_button_up.bind(button))
		_swatch_row.add_child(button)
		_swatch_buttons[name] = button


## A round pastel tile with a soft shadow; the chosen one wears a cream ring.
func _style_swatch(button: Button, name: String, chosen: bool) -> void:
	if button == null:
		return
	var colour: Color = SWATCHES[name]
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Palette.deep(colour) if state == "pressed" else colour
		style.set_corner_radius_all(SWATCH_CORNER)
		style.border_color = Palette.CREAM if chosen else Color(Palette.INK, 0.10)
		style.set_border_width_all(10 if chosen else 4)
		style.shadow_color = Color(Palette.INK, 0.18)
		style.shadow_size = 14
		style.shadow_offset = Vector2(0.0, 8.0)
		button.add_theme_stylebox_override(state, style)


func _on_swatch_pressed(name: String) -> void:
	apply_swatch(name)


func _remembered_swatch() -> String:
	var save: Node = _autoload("SaveService")
	if save != null and save.has_method("get_setting"):
		var remembered: String = String(save.call("get_setting", TINT_SETTING_KEY, ""))
		if SWATCHES.has(remembered):
			return remembered
	return DEFAULT_SWATCH


func _remember_swatch(name: String) -> void:
	var save: Node = _autoload("SaveService")
	if save != null and save.has_method("set_setting"):
		save.call("set_setting", TINT_SETTING_KEY, name)


# ---------------------------------------------------------------------------
# Back
# ---------------------------------------------------------------------------

func _on_back_pressed() -> void:
	go_back()


## Returns to the title screen by hand -- instantiate, add, make current, free
## this -- rather than `change_scene_to_file()`, which is deferred and so cannot
## be asserted by the headless runner. Idempotent: a second tap in flight does
## nothing. False only when the menu scene is not in the build.
func go_back() -> bool:
	if _leaving:
		return false
	if not ResourceLoader.exists(MENU_SCENE_PATH):
		return false
	var packed: Resource = load(MENU_SCENE_PATH)
	if not (packed is PackedScene):
		return false
	var tree: SceneTree = _scene_tree()
	if tree == null:
		return false
	var menu: Node = (packed as PackedScene).instantiate()
	if menu == null:
		return false
	_leaving = true
	tree.root.add_child(menu)
	tree.current_scene = menu
	queue_free()
	return true


func is_leaving() -> bool:
	return _leaving


# ---------------------------------------------------------------------------
# The stage, Aliz, and her accents
# ---------------------------------------------------------------------------

func _build_stage() -> void:
	var stage := Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	# The floor and a round cream stage to stand on.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(40.0, 40.0)
	_place(stage, "Floor", floor_mesh, Palette.light(Palette.LAVENDER), Vector3.ZERO)
	_place(stage, "Podium", _disc(1.45, 0.12), Palette.CREAM, Vector3(-0.2, 0.0, 0.0))
	_place(stage, "PodiumRim", _disc(1.55, 0.06), Palette.PEACH, Vector3(-0.2, -0.03, 0.0))
	# A soft backdrop: a big pink wall well behind her, and two pastel curtain
	# columns either side, so she is framed rather than floating.
	var wall := BoxMesh.new()
	wall.size = Vector3(14.0, 6.0, 0.2)
	_place(stage, "Backdrop", wall, Palette.light(Palette.SOFT_PINK), Vector3(0.0, 3.0, -4.0))
	for side: float in [-1.0, 1.0]:
		var curtain := _place(stage, "Curtain", _cylinder(0.32, 4.2), Palette.SOFT_PINK,
				Vector3(side * 2.7 - 0.2, 2.1, -1.4))
		curtain.name = "CurtainLeft" if side < 0.0 else "CurtainRight"
		_place(curtain, "Tie", _disc(0.36, 0.14), Palette.STAR_EARNED, Vector3(0.0, -0.8, 0.0))
	# Bunting: a row of little pastel pennants across the top of the backdrop.
	var colours: Array = [Palette.MINT, Palette.STAR_NEXT, Palette.LAVENDER, Palette.SOFT_PINK]
	for i: int in range(9):
		var x: float = -3.2 + 0.8 * float(i)
		var sag: float = 0.18 * sin(float(i) / 8.0 * PI)
		var flag := PrismMesh.new()
		flag.size = Vector3(0.34, 0.4, 0.04)
		_place(stage, "Pennant", flag, colours[i % colours.size()],
				Vector3(x, 3.55 - sag, -3.85), Vector3(0.0, 0.0, 180.0))
	# A few soft stars on the floor round the podium.
	for i: int in range(6):
		var a: float = deg_to_rad(20.0 + 60.0 * float(i))
		_place(stage, "Sparkle", _disc(0.09, 0.02), Palette.STAR_NEXT,
				Vector3(-0.2 + cos(a) * 1.95, 0.005, sin(a) * 1.2 - 0.3))


func _add_aliz() -> void:
	if not ResourceLoader.exists(BUDDY_AVATAR_SCENE_PATH):
		return
	var packed: Resource = load(BUDDY_AVATAR_SCENE_PATH)
	if not (packed is PackedScene):
		return
	var avatar: Node = (packed as PackedScene).instantiate()
	if not (avatar is Node3D):
		if avatar != null:
			avatar.free()
		return
	_aliz = avatar as Node3D
	_aliz.name = "Aliz"
	_aliz.position = ALIZ_POSITION
	_aliz.rotation = Vector3(0.0, deg_to_rad(ALIZ_YAW_DEG), 0.0)
	add_child(_aliz)
	if _aliz.has_method("build"):
		_aliz.call("build")
	# Her idle, when the wrapper has one (guarded exactly as the title screen
	# does it; nothing is faked when it is missing).
	if _aliz.has_method("can_play_action") and _aliz.has_method("play_action") \
			and bool(_aliz.call("can_play_action", "idle")):
		_aliz.call("play_action", "idle")


func get_aliz() -> Node3D:
	return _aliz


func is_model_available() -> bool:
	return _aliz != null and _aliz.has_method("is_model_available") \
			and bool(_aliz.call("is_model_available"))


## The accents: one material, three pinned primitives.
func _build_accessories() -> void:
	_accent_material = StandardMaterial3D.new()
	_accent_material.albedo_color = SWATCHES[DEFAULT_SWATCH]
	_accent_material.roughness = 0.95
	_accent_material.metallic = 0.0
	_accessories = Node3D.new()
	_accessories.name = "Accents"
	add_child(_accessories)

	_bow = _build_bow("HairBow", 0.085)
	_tutu = Node3D.new()
	_tutu.name = "Tutu"
	_accessories.add_child(_tutu)
	var skirt := TorusMesh.new()
	skirt.inner_radius = 0.21
	skirt.outer_radius = 0.37
	skirt.rings = 28
	skirt.ring_segments = 8
	var ring := _place(_tutu, "Frill", skirt, Color.WHITE, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.4, 0.92))
	ring.material_override = _accent_material
	var frill2 := _place(_tutu, "FrillUnder", skirt, Color.WHITE, Vector3(0.0, -0.045, 0.0),
			Vector3.ZERO, Vector3(1.1, 0.34, 1.0))
	frill2.material_override = _accent_material
	# Little scallops round the hem, so the frill reads as fabric, not a ring.
	for i: int in range(10):
		var a: float = deg_to_rad(36.0 * float(i))
		var scallop := _place(_tutu, "Scallop", _sphere(0.055), Color.WHITE,
				Vector3(cos(a) * 0.36, -0.06, sin(a) * 0.33), Vector3.ZERO, Vector3(1.0, 0.7, 1.0))
		scallop.material_override = _accent_material
	for side: float in [-1.0, 1.0]:
		var shoe := _build_bow("ShoeBow" + ("Left" if side < 0.0 else "Right"), 0.03)
		_shoe_bows.append([shoe, side])
	_pin_accessories()


func _build_bow(bow_name: String, size: float) -> Node3D:
	var bow := Node3D.new()
	bow.name = bow_name
	_accessories.add_child(bow)
	for side: float in [-1.0, 1.0]:
		var loop := _place(bow, "Loop", _sphere(size), Color.WHITE,
				Vector3(side * size * 1.1, 0.0, 0.0), Vector3.ZERO, Vector3(1.2, 0.8, 0.6))
		loop.material_override = _accent_material
	var knot := _place(bow, "Knot", _sphere(size * 0.5), Color.WHITE, Vector3.ZERO)
	knot.material_override = _accent_material
	return bow


## Pins each accent to its socket's position this frame. Position only; the
## accent keeps her yaw, so it never rolls with a bone.
func _pin_accessories() -> void:
	if _aliz == null or _accessories == null:
		return
	var yaw: float = _aliz.rotation.y
	var basis := Basis(Vector3.UP, yaw)
	if _bow != null:
		_bow.transform = Transform3D(basis, _socket_position("head") + basis * BOW_OFFSET)
	if _tutu != null:
		_tutu.transform = Transform3D(basis, _socket_position("hips") + basis * TUTU_OFFSET)
	for entry: Array in _shoe_bows:
		var shoe: Node3D = entry[0]
		var side: float = float(entry[1])
		var foot: Vector3 = _aliz.position + basis * Vector3(side * 0.09, SHOE_BOW_HEIGHT, -0.16)
		shoe.transform = Transform3D(basis, foot)


## The socket's position in this scene, or a plain offset from her origin when
## the wrapper has no such socket (the honest degradation).
func _socket_position(socket_name: String) -> Vector3:
	if _aliz.has_method("has_socket") and bool(_aliz.call("has_socket", socket_name)) \
			and _aliz.has_method("get_socket"):
		# In the tree the skeleton keeps its attachments current every frame;
		# out of it (the headless runner) nothing does, so ask.
		if not _aliz.is_inside_tree() and _aliz.has_method("refresh_sockets"):
			_aliz.call("refresh_sockets")
		var socket: Node3D = _aliz.call("get_socket", socket_name) as Node3D
		if socket != null and socket != _aliz:
			return _world_position(socket)
	var height: float = 1.65
	if _aliz.has_method("get_height"):
		height = float(_aliz.call("get_height"))
	match socket_name:
		"head":
			return _aliz.position + Vector3(0.0, height * 0.92, 0.0)
		"hips":
			return _aliz.position + Vector3(0.0, height * 0.52, 0.0)
		_:
			return _aliz.position


## World position in or out of the tree: `global_position` asserts on a node
## that is not in an active tree, which is the headless runner's whole tree.
static func _world_position(node: Node3D) -> Vector3:
	var transform: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent is Node3D:
		transform = (parent as Node3D).transform * transform
		parent = parent.get_parent()
	return transform.origin


# ---------------------------------------------------------------------------
# Press feedback
# ---------------------------------------------------------------------------

func _on_button_down(button: Button) -> void:
	_squish(button, PRESS_SCALE)
	var sfx: Node = _autoload("Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", TAP_SFX)


func _on_button_up(button: Button) -> void:
	_squish(button, Vector2.ONE)


func _squish(button: Button, to: Vector2) -> void:
	button.pivot_offset = button.size * 0.5
	if not is_inside_tree():
		button.scale = to
		return
	var tween: Tween = create_tween()
	tween.tween_property(button, "scale", to, PRESS_SECONDS).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _place(parent: Node, node_name: String, mesh: Mesh, colour: Color, at: Vector3,
		rot_deg: Vector3 = Vector3.ZERO, scale_by: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.95
	material.metallic = 0.0
	instance.material_override = material
	instance.position = at
	instance.rotation_degrees = rot_deg
	instance.scale = scale_by
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	return mesh


static func _disc(radius: float, thickness: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = thickness
	mesh.radial_segments = 28
	mesh.rings = 1
	return mesh


func _scene_tree() -> SceneTree:
	if is_inside_tree():
		return get_tree()
	return Engine.get_main_loop() as SceneTree


func _autoload(autoload_name: String) -> Node:
	var tree: SceneTree = _scene_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)
