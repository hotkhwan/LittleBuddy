extends Node3D

## THE CLASSROOM, built from primitives: a small bright room with a round
## teaching table in the middle, Aliz's chair behind it and a child's chair
## beside it, a colourful card rack, a stack of books and a pencil cup on the
## table, the lesson board on the back wall, a toy shelf, and a window. Pastel,
## warm, art bible section 7 materials (roughness 0.95, metallic 0, no normal
## maps), every sphere and cylinder at a low segment count so the whole room is
## a few thousand triangles against the 40k ceiling `test_tutor_scene.gd`
## enforces.
##
## ## Props manifest (swap-in seam)
##
## `res://content/tutor/props_manifest.json` may name a GLB per prop id. When
## it does, that GLB is instantiated at the manifest's scale IN PLACE OF the
## primitive and nothing else changes -- the Meshy agent's table, chairs,
## apple, banana, animals and number blocks drop in without touching this
## file. Accepted shape (either nesting):
##
##   {"props": {"table": {"glb": "res://assets/tutor/table.glb", "scale": 1.0,
##                        "yawDeg": 0, "offset": [0, 0, 0]}}}
##   {"table": {"path": "res://...glb", "scale": [1, 1, 1]}}
##
## Prop ids: table, chairAliz, chairChild, apple, banana, cat, dog,
## numberBlocks, books, pencilCup, cardRack, shelf. A missing file or a
## non-scene resource keeps the primitive, and `prop_source(id)` answers
## "glb" or "primitive" so a test can see which one is standing.

const Palette := preload("res://scripts/ui/palette.gd")
const FlashcardArt := preload("res://scripts/tutor/classroom/flashcard_art.gd")
const LessonBoardScript := preload("res://scripts/tutor/classroom/lesson_board.gd")

const MANIFEST_PATH: String = "res://content/tutor/props_manifest.json"

## Where Aliz sits (her feet-origin) and which way she faces (+Z, the camera).
const ALIZ_SEAT: Vector3 = Vector3(0.0, 0.0, -0.98)
const ALIZ_YAW: float = PI
## The base of her head when seated (rig-less fallback for the face keep-out).
const ALIZ_SEATED_HEAD: Vector3 = Vector3(0.0, 0.8, -0.98)

const TABLE_CENTRE: Vector3 = Vector3(0.0, 0.0, -0.1)
const TABLE_RADIUS: float = 0.58
const TABLE_TOP_Y: float = 0.54
const ROOM_HALF_WIDTH: float = 3.0
const ROOM_DEPTH_BACK: float = -2.3
const ROOM_HEIGHT: float = 2.7
const BOARD_POSITION: Vector3 = Vector3(1.08, 1.46, -2.24)

const SPHERE_RADIAL: int = 14
const SPHERE_RINGS: int = 7
const CYL_RADIAL: int = 18

var _manifest: Dictionary = {}
var _sources: Dictionary = {}
var _board: Node3D = null
var _built: bool = false


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	name = "Classroom"
	_manifest = _load_manifest()
	_build_room()
	_build_table()
	_build_chairs()
	_build_table_props()
	_build_shelf()
	_build_board()


func get_board() -> Node3D:
	build()
	return _board


func get_table_top() -> Vector3:
	return TABLE_CENTRE + Vector3(0.0, TABLE_TOP_Y, 0.0)


## "glb" when the props manifest replaced this prop, "primitive" otherwise.
func prop_source(prop_id: String) -> String:
	return String(_sources.get(prop_id, "primitive"))


func manifest_loaded() -> bool:
	return not _manifest.is_empty()


## Every triangle under this node, read off the meshes themselves.
func count_triangles() -> int:
	return count_triangles_under(self)


static func count_triangles_under(node: Node) -> int:
	var total: int = 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			if arrays.is_empty():
				continue
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if indices != null and typeof(indices) == TYPE_PACKED_INT32_ARRAY and (indices as PackedInt32Array).size() > 0:
				total += (indices as PackedInt32Array).size() / 3
			else:
				var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
				if typeof(vertices) == TYPE_PACKED_VECTOR3_ARRAY:
					total += (vertices as PackedVector3Array).size() / 3
	for child: Node in node.get_children():
		total += count_triangles_under(child)
	return total


# ---------------------------------------------------------------------------
# Room shell
# ---------------------------------------------------------------------------

func _build_room() -> void:
	var shell: Node3D = _group("Room")
	# Floor: warm cream boards, with a big mint rug under the table.
	_box(shell, "Floor", Vector3(ROOM_HALF_WIDTH * 2.0, 0.08, 5.0), Vector3(0.0, -0.04, -0.1), Palette.PEACH.lerp(Palette.CREAM, 0.25))
	_cylinder(shell, "Rug", 1.55, 1.55, 0.02, Vector3(0.0, 0.01, -0.2), Palette.MINT)
	_cylinder(shell, "RugRim", 1.7, 1.7, 0.012, Vector3(0.0, 0.006, -0.2), Palette.deep(Palette.MINT))
	# Walls: dusty blue back, lavender sides, a cream dado rail.
	_box(shell, "BackWall", Vector3(ROOM_HALF_WIDTH * 2.0, ROOM_HEIGHT, 0.1), Vector3(0.0, ROOM_HEIGHT * 0.5, ROOM_DEPTH_BACK - 0.05), Palette.DUSTY_BLUE.lerp(Palette.CREAM, 0.2))
	_box(shell, "LeftWall", Vector3(0.1, ROOM_HEIGHT, 5.0), Vector3(-ROOM_HALF_WIDTH - 0.05, ROOM_HEIGHT * 0.5, -0.1), Palette.LAVENDER.lerp(Palette.CREAM, 0.2))
	_box(shell, "RightWall", Vector3(0.1, ROOM_HEIGHT, 5.0), Vector3(ROOM_HALF_WIDTH + 0.05, ROOM_HEIGHT * 0.5, -0.1), Palette.LAVENDER.lerp(Palette.CREAM, 0.2))
	_box(shell, "Dado", Vector3(ROOM_HALF_WIDTH * 2.0, 0.06, 0.04), Vector3(0.0, 0.95, ROOM_DEPTH_BACK + 0.02), Palette.CREAM)
	_box(shell, "Skirting", Vector3(ROOM_HALF_WIDTH * 2.0, 0.12, 0.04), Vector3(0.0, 0.06, ROOM_DEPTH_BACK + 0.02), Palette.CREAM)
	# A window on the left of the back wall: cream frame, sky pane, a curtain.
	_box(shell, "WindowFrame", Vector3(1.05, 0.95, 0.06), Vector3(-1.75, 1.7, ROOM_DEPTH_BACK + 0.03), Palette.CREAM)
	_box(shell, "WindowPane", Vector3(0.92, 0.82, 0.02), Vector3(-1.75, 1.7, ROOM_DEPTH_BACK + 0.06), FlashcardArt.SKY_BLUE.lerp(Palette.CREAM, 0.25))
	_box(shell, "WindowBarV", Vector3(0.04, 0.82, 0.03), Vector3(-1.75, 1.7, ROOM_DEPTH_BACK + 0.075), Palette.CREAM)
	_box(shell, "WindowBarH", Vector3(0.92, 0.04, 0.03), Vector3(-1.75, 1.7, ROOM_DEPTH_BACK + 0.075), Palette.CREAM)
	_box(shell, "CurtainL", Vector3(0.18, 1.1, 0.05), Vector3(-2.35, 1.66, ROOM_DEPTH_BACK + 0.08), Palette.SOFT_PINK)
	_box(shell, "CurtainR", Vector3(0.18, 1.1, 0.05), Vector3(-1.15, 1.66, ROOM_DEPTH_BACK + 0.08), Palette.SOFT_PINK)
	_sphere(shell, "Sun", 0.12, Vector3(-1.98, 1.92, ROOM_DEPTH_BACK + 0.08), Palette.STAR_EARNED)
	# Paper garland along the top of the back wall.
	var garland_colours: Array = [Palette.SOFT_PINK, Palette.MINT, Palette.STAR_NEXT, Palette.LAVENDER, Palette.PEACH]
	for i: int in range(9):
		var x: float = -2.6 + float(i) * 0.65
		var y: float = 2.42 - 0.08 * sin(float(i) * 0.9)
		_triangle_flag(shell, "Flag%d" % i, Vector3(x, y, ROOM_DEPTH_BACK + 0.04), garland_colours[i % garland_colours.size()])


func _triangle_flag(parent: Node3D, node_name: String, at: Vector3, colour: Color) -> void:
	var prism: PrismMesh = PrismMesh.new()
	prism.size = Vector3(0.22, 0.24, 0.01)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = prism
	instance.material_override = _material(colour)
	instance.position = at
	instance.rotation.z = PI
	parent.add_child(instance)


# ---------------------------------------------------------------------------
# Furniture
# ---------------------------------------------------------------------------

func _build_table() -> void:
	var table: Node3D = _group("Table")
	table.position = TABLE_CENTRE
	if _try_glb(table, "table"):
		return
	_cylinder(table, "Top", TABLE_RADIUS, TABLE_RADIUS, 0.06, Vector3(0.0, TABLE_TOP_Y - 0.03, 0.0), Palette.SOFT_PINK)
	_cylinder(table, "Apron", TABLE_RADIUS - 0.05, TABLE_RADIUS - 0.05, 0.05, Vector3(0.0, TABLE_TOP_Y - 0.085, 0.0), Palette.CREAM)
	_cylinder(table, "Leg", 0.06, 0.06, TABLE_TOP_Y - 0.1, Vector3(0.0, (TABLE_TOP_Y - 0.1) * 0.5, 0.0), Palette.CREAM)
	_cylinder(table, "Base", 0.3, 0.34, 0.05, Vector3(0.0, 0.025, 0.0), Palette.deep(Palette.SOFT_PINK))


func _build_chairs() -> void:
	# Aliz's chair, behind the table; the child's, angled at the right.
	var aliz_chair: Node3D = _chair("ChairAliz", "chairAliz", Vector3(0.0, 0.0, -1.06), 0.0, Palette.DUSTY_BLUE)
	aliz_chair.set_meta("propId", "chairAliz")
	var child_chair: Node3D = _chair("ChairChild", "chairChild", Vector3(-1.6, 0.0, -1.35), PI * 0.38, Palette.STAR_NEXT)
	child_chair.scale = Vector3.ONE * 0.85
	child_chair.set_meta("propId", "chairChild")


func _chair(node_name: String, prop_id: String, at: Vector3, yaw: float, colour: Color) -> Node3D:
	var chair: Node3D = _group(node_name)
	chair.position = at
	chair.rotation.y = yaw
	if _try_glb(chair, prop_id):
		return chair
	var seat_y: float = 0.40
	_box(chair, "Seat", Vector3(0.44, 0.06, 0.44), Vector3(0.0, seat_y, 0.0), colour)
	_box(chair, "Back", Vector3(0.44, 0.42, 0.05), Vector3(0.0, seat_y + 0.24, -0.2), colour)
	_sphere(chair, "Knob", 0.05, Vector3(0.0, seat_y + 0.48, -0.2), Palette.deep(colour))
	for corner: Vector2 in [Vector2(-0.18, -0.18), Vector2(0.18, -0.18), Vector2(-0.18, 0.18), Vector2(0.18, 0.18)]:
		_cylinder(chair, "Leg", 0.025, 0.03, seat_y - 0.03, Vector3(corner.x, (seat_y - 0.03) * 0.5, corner.y), Palette.CREAM)
	return chair


func _build_table_props() -> void:
	var top: Vector3 = get_table_top()
	# Picture-card rack: a small angled cream tray with three coloured cards.
	var rack: Node3D = _group("CardRack")
	rack.position = top + Vector3(0.38, 0.0, -0.02)
	rack.rotation.y = -0.45
	if not _try_glb(rack, "cardRack"):
		_box(rack, "Tray", Vector3(0.26, 0.03, 0.12), Vector3(0.0, 0.015, 0.0), Palette.CREAM)
		_box(rack, "Lip", Vector3(0.26, 0.05, 0.02), Vector3(0.0, 0.04, 0.05), Palette.deep(Palette.CREAM))
		var card_colours: Array = [FlashcardArt.APPLE_RED, FlashcardArt.BANANA_YELLOW, Palette.DUSTY_BLUE]
		for i: int in range(3):
			var card: MeshInstance3D = _box(rack, "Card%d" % i, Vector3(0.14, 0.17, 0.008), Vector3(-0.06 + float(i) * 0.06, 0.1, -0.03 + float(i) * 0.012), Palette.CREAM)
			card.rotation.x = -0.28
			var face: MeshInstance3D = _box(card, "Face", Vector3(0.1, 0.1, 0.004), Vector3(0.0, 0.015, 0.006), card_colours[i])
			face.name = "Face%d" % i
	# Books, three, a little askew.
	var books: Node3D = _group("Books")
	books.position = top + Vector3(-0.4, 0.0, -0.08)
	if not _try_glb(books, "books"):
		var book_colours: Array = [Palette.DUSTY_BLUE, Palette.SOFT_PINK, Palette.MINT]
		for i: int in range(3):
			var book: MeshInstance3D = _box(books, "Book%d" % i, Vector3(0.2, 0.03, 0.15), Vector3(0.0, 0.015 + float(i) * 0.032, 0.0), book_colours[i])
			book.rotation.y = float(i - 1) * 0.22
			var pages: MeshInstance3D = _box(book, "Pages", Vector3(0.19, 0.022, 0.14), Vector3(0.004, 0.0, 0.004), Palette.CREAM)
			pages.name = "Pages%d" % i
	# Pencil cup at the back left, three pencils.
	var cup: Node3D = _group("PencilCup")
	cup.position = top + Vector3(-0.2, 0.0, -0.36)
	if not _try_glb(cup, "pencilCup"):
		_cylinder(cup, "Cup", 0.05, 0.045, 0.1, Vector3(0.0, 0.05, 0.0), Palette.LAVENDER)
		var pencil_colours: Array = [FlashcardArt.BANANA_YELLOW, FlashcardArt.LEAF_GREEN, FlashcardArt.APPLE_RED]
		for i: int in range(3):
			var pencil: MeshInstance3D = _cylinder(cup, "Pencil%d" % i, 0.008, 0.008, 0.17, Vector3(-0.02 + float(i) * 0.02, 0.12, -0.01 + float(i) * 0.012), pencil_colours[i])
			pencil.rotation.z = float(i - 1) * 0.12
	# The lesson's own fruit, on the table between them.
	var apple: Node3D = _group("Apple")
	apple.position = top + Vector3(0.04, 0.0, -0.3)
	if not _try_glb(apple, "apple"):
		_sphere(apple, "Body", 0.055, Vector3(0.0, 0.05, 0.0), FlashcardArt.APPLE_RED)
		_cylinder(apple, "Stem", 0.006, 0.006, 0.03, Vector3(0.0, 0.11, 0.0), FlashcardArt.STEM_BROWN)
		var leaf: MeshInstance3D = _sphere(apple, "Leaf", 0.02, Vector3(0.02, 0.115, 0.0), FlashcardArt.LEAF_GREEN)
		leaf.scale = Vector3(1.4, 0.4, 0.8)
	var banana: Node3D = _group("Banana")
	banana.position = top + Vector3(0.2, 0.0, -0.32)
	banana.rotation.y = 0.5
	if not _try_glb(banana, "banana"):
		var body: MeshInstance3D = _capsule(banana, "Body", 0.028, 0.2, Vector3(0.0, 0.03, 0.0), FlashcardArt.BANANA_YELLOW)
		body.rotation.z = PI * 0.5
		body.rotation.x = 0.15


func _build_shelf() -> void:
	var shelf: Node3D = _group("Shelf")
	shelf.position = Vector3(-2.05, 1.05, ROOM_DEPTH_BACK + 0.2)
	if _try_glb(shelf, "shelf"):
		return
	_box(shelf, "Plank", Vector3(1.3, 0.05, 0.32), Vector3.ZERO, Palette.CREAM)
	_box(shelf, "BracketL", Vector3(0.05, 0.2, 0.28), Vector3(-0.55, -0.12, 0.0), Palette.deep(Palette.CREAM))
	_box(shelf, "BracketR", Vector3(0.05, 0.2, 0.28), Vector3(0.55, -0.12, 0.0), Palette.deep(Palette.CREAM))
	# Toys: a ball, a teddy, a duck and a tower of number blocks.
	_sphere(shelf, "Ball", 0.11, Vector3(-0.48, 0.135, 0.0), FlashcardArt.SKY_BLUE)
	_sphere(shelf, "BallStripe", 0.112, Vector3(-0.48, 0.135, 0.0), Palette.SOFT_PINK).scale = Vector3(1.0, 0.3, 1.0)
	var teddy: Node3D = _group("Teddy", shelf)
	teddy.position = Vector3(-0.15, 0.025, 0.0)
	_sphere(teddy, "Body", 0.1, Vector3(0.0, 0.1, 0.0), FlashcardArt.DOG_BROWN)
	_sphere(teddy, "Head", 0.075, Vector3(0.0, 0.24, 0.02), FlashcardArt.DOG_BROWN)
	_sphere(teddy, "EarL", 0.03, Vector3(-0.06, 0.3, 0.0), FlashcardArt.DOG_BROWN)
	_sphere(teddy, "EarR", 0.03, Vector3(0.06, 0.3, 0.0), FlashcardArt.DOG_BROWN)
	_sphere(teddy, "Muzzle", 0.035, Vector3(0.0, 0.22, 0.075), Palette.CREAM)
	var duck: Node3D = _group("Duck", shelf)
	duck.position = Vector3(0.18, 0.025, 0.02)
	_sphere(duck, "Body", 0.07, Vector3(0.0, 0.07, 0.0), FlashcardArt.BANANA_YELLOW).scale = Vector3(1.3, 0.9, 1.0)
	_sphere(duck, "Head", 0.045, Vector3(0.05, 0.15, 0.0), FlashcardArt.BANANA_YELLOW)
	_sphere(duck, "Beak", 0.02, Vector3(0.09, 0.14, 0.0), FlashcardArt.ORANGE_ORANGE).scale = Vector3(1.4, 0.6, 1.0)
	var blocks: Node3D = _group("NumberBlocks", shelf)
	blocks.position = Vector3(0.48, 0.025, 0.0)
	if not _try_glb(blocks, "numberBlocks"):
		var block_colours: Array = [Palette.MINT, Palette.SOFT_PINK, Palette.LAVENDER]
		for i: int in range(3):
			var block: MeshInstance3D = _box(blocks, "Block%d" % (i + 1), Vector3(0.13, 0.13, 0.13), Vector3(0.0, 0.065 + float(i) * 0.135, 0.0), block_colours[i])
			block.rotation.y = float(i) * 0.25
			var dots: int = i + 1
			for d: int in range(dots):
				var dot: MeshInstance3D = _sphere(block, "Dot%d" % d, 0.014, Vector3((float(d) - float(dots - 1) * 0.5) * 0.035, 0.0, 0.066), Palette.INK)
				dot.scale = Vector3(1.0, 1.0, 0.3)


func _build_board() -> void:
	_board = LessonBoardScript.new()
	_board.position = BOARD_POSITION
	add_child(_board)
	_board.call("build")
	# A little tray of chalk under it and a star sticker on the frame.
	_box(_board, "Tray", Vector3(0.7, 0.04, 0.08), Vector3(0.0, -0.53, 0.06), Palette.CREAM)
	_cylinder(_board, "Chalk", 0.008, 0.008, 0.08, Vector3(-0.1, -0.5, 0.06), Palette.SOFT_PINK).rotation.z = PI * 0.5
	_sphere(_board, "Star", 0.04, Vector3(0.52, 0.42, 0.04), Palette.STAR_EARNED).scale = Vector3(1.0, 1.0, 0.4)


# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var table: Dictionary = parsed
	if typeof(table.get("props", null)) == TYPE_DICTIONARY:
		return table["props"]
	return table


## Instantiates the manifest's GLB for `prop_id` under `parent`. Returns false
## (and adds nothing) when the manifest has no usable entry, so the caller
## builds the primitive.
func _try_glb(parent: Node3D, prop_id: String) -> bool:
	var entry: Variant = _manifest.get(prop_id, null)
	if typeof(entry) == TYPE_STRING:
		entry = {"glb": entry}
	if typeof(entry) != TYPE_DICTIONARY:
		return false
	var spec: Dictionary = entry
	var path: String = String(spec.get("glb", spec.get("path", spec.get("file", "")))).strip_edges()
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	var packed: Resource = load(path)
	if not (packed is PackedScene):
		return false
	var instance: Node = (packed as PackedScene).instantiate()
	if not (instance is Node3D):
		if instance != null:
			instance.free()
		return false
	var model: Node3D = instance
	model.name = "Model"
	var scale_value: Variant = spec.get("scale", 1.0)
	if typeof(scale_value) == TYPE_ARRAY and (scale_value as Array).size() == 3:
		model.scale = Vector3(float(scale_value[0]), float(scale_value[1]), float(scale_value[2]))
	else:
		model.scale = Vector3.ONE * float(scale_value)
	model.rotation.y = deg_to_rad(float(spec.get("yawDeg", 0.0)))
	var offset: Variant = spec.get("offset", null)
	if typeof(offset) == TYPE_ARRAY and (offset as Array).size() == 3:
		model.position = Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
	parent.add_child(model)
	_sources[prop_id] = "glb"
	return true


# ---------------------------------------------------------------------------
# Primitive helpers
# ---------------------------------------------------------------------------

func _group(node_name: String, parent: Node3D = null) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = node_name
	(parent if parent != null else self).add_child(node)
	return node


func _box(parent: Node3D, node_name: String, box_size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box_size
	return _place(parent, node_name, mesh, at, colour)


func _cylinder(parent: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, at: Vector3, colour: Color) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = CYL_RADIAL
	mesh.rings = 1
	return _place(parent, node_name, mesh, at, colour)


func _sphere(parent: Node3D, node_name: String, radius: float, at: Vector3, colour: Color) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = SPHERE_RADIAL
	mesh.rings = SPHERE_RINGS
	return _place(parent, node_name, mesh, at, colour)


func _capsule(parent: Node3D, node_name: String, radius: float, height: float, at: Vector3, colour: Color) -> MeshInstance3D:
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = SPHERE_RADIAL
	mesh.rings = 4
	return _place(parent, node_name, mesh, at, colour)


func _place(parent: Node3D, node_name: String, mesh: Mesh, at: Vector3, colour: Color) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = _material(colour)
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


static func _material(colour: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.95
	material.metallic = 0.0
	return material
