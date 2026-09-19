extends Node3D

## THE KITCHEN YOU CAN SEE.
##
## `kitchen_state.gd` knows that the banana left the fridge. This file is the
## reason a child believes it: the banana mesh is destroyed at the fridge and
## rebuilt in Aliz's hands, the fridge door really rotates, and two ingredients
## on the counter really become one bowl of food.
##
## The brief's rule is the whole specification -- *"do not implement
## inventory-only interactions while the world objects remain unchanged"* -- so
## this node holds NO state of its own. It renders `KitchenState` and nothing
## else. There is no way for the picture and the model to disagree, because there
## is only one of them.
##
## ## Why everything is rebuilt rather than moved
##
## `_refresh()` frees every item mesh and makes them again. That sounds wasteful
## and is not: the whole kitchen is at most seven items of a few dozen triangles
## each, rebuilt only when the child does something. Tweening a mesh from a
## fridge shelf into a hand would need per-item identity, interruption handling
## and a fallback for the case where the model changed twice in a frame -- three
## sources of the exact desync this design exists to make impossible. The door,
## which is the one thing a child watches move, IS animated.
##
## Draw calls: every item is its own `MeshInstance3D`, because items appear and
## disappear independently. At seven items that is seven calls against a budget
## the static room already fits inside with one.

const Kit := preload("res://scripts/house/prop_kit.gd")
const Palette := preload("res://scripts/ui/palette.gd")
const Items := preload("res://scripts/kitchen/kitchen_items.gd")
const Rules := preload("res://scripts/kitchen/kitchen_rules.gd")
const StateScript := preload("res://scripts/kitchen/kitchen_state.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")

## Where a station puts things a child can see, in ROOM-LOCAL space. Derived from
## `house_layout.gd`'s own furniture table rather than typed twice -- see
## `_anchor()`. Only the offsets above each piece live here.
##
## `surface` is the top of the furniture; `inside` is the shelf a store station
## shows its contents on when its door is open.
const SURFACE_LIFT: float = 0.03

## How much bigger an item is drawn while it is STANDING somewhere.
##
## The same argument as `HAND_SCALE` below, one step gentler. A 0.14 m banana is
## the right size for a 0.9 m worktop and is about 30 px on an iPad at the room
## shot's 4.3 m -- against a cream worktop, in front of a cream wall. The brief's
## test is "a child must be able to spot the bottle instantly", and 30 px of pale
## yellow is not that. The model is untouched; only the drawing grows.
const SURFACE_SCALE: float = 1.2

## The fridge door. Hinged on its -X edge so it swings toward the camera and to
## the left, which keeps the opening -- and the food -- facing the child.
const DOOR_OPEN_DEGREES: float = 104.0
const DOOR_SWING_SEC: float = 0.32

## How the held item sits in front of Aliz, when her hands cannot be found.
##
## These numbers were the whole of the answer before, and rendered, they were
## plainly wrong: the item hung at chest height with her arms at her sides,
## clipping into her dress, and read as stuck to her tummy rather than carried.
## They are now only the FALLBACK, for the toddler placeholder view and for any
## future character with no skeleton.
const HAND_FORWARD: float = 0.22
const HAND_HEIGHT: float = 0.46

## The bone the item is really carried in, and the bone tried if that is missing.
## Both spellings of the rig's convention, because a rig is another agent's file
## and a hard-coded bone name that has quietly stopped matching is a silent
## regression rather than a loud one.
const HAND_BONES: Array[String] = [
	"RightHand", "mixamorig:RightHand", "hand_r", "Hand_R", "RightHandIndex1",
]

## From the WRIST bone to the middle of the thing she is holding: barely inboard
## of the wrist, a little above it and a little in front, so her mitt closes
## round the item's upper third and the item hangs clear of the skirt. Tuned
## against `docs/shots/world_carry_ipad.png` -- the hand mesh reaches well below
## the wrist joint, which is why this is not simply zero.
const HAND_BONE_OFFSET: Vector3 = Vector3(-0.005, 0.035, -0.06)

## And how much BIGGER it is drawn while carried.
##
## A 0.13 m spoon is correct on a worktop and unreadable in a hand at the house
## camera's distance -- it measured a handful of pixels, against a striped dress
## of a similar value. "What am I carrying?" is the single question this system
## must always be able to answer at a glance, so the held copy is drawn bigger.
## The world copy is untouched; nothing about the model changes.
##
## It was 1.55, and once the item moved out of the middle of her body and into
## her hand that stopped being readable and started being absurd: a 0.26 m bottle
## drawn at 1.55 is 0.41 m, which on a 1 m child is a bottle reaching from her
## hand past her shoulder. 1.3 is still well clear of the "handful of pixels"
## problem and is something a child could actually be holding.
const HAND_SCALE: float = 1.3

var _state: RefCounted = null
var _room: Node3D = null
var _carrier: Node3D = null

var _door_hinge: Node3D = null
var _items_root: Node3D = null
var _hand_root: Node3D = null
var _door_tween: Tween = null


## Binds the view to a kitchen room and the character who carries things.
## `carrier` may be null -- the kitchen still works, the held item just rests at
## the room's own origin, which is visible and wrong rather than invisible and
## wrong.
func setup(state: RefCounted, room: Node3D, carrier: Node3D = null) -> void:
	_state = state
	_room = room
	_carrier = carrier
	name = "KitchenView"

	if _items_root == null:
		_items_root = Node3D.new()
		_items_root.name = "KitchenItems"
		add_child(_items_root)
	if _hand_root == null:
		_hand_root = Node3D.new()
		_hand_root.name = "CarriedItem"
		# PARENTED TO ALIZ, not to this view, and that distinction is a bug fix
		# rather than a tidy-up. Rooms are shown and hidden as the child moves
		# between them, so a carried item living under the kitchen disappeared the
		# moment she walked out of the kitchen -- which is precisely the beat where
		# carrying matters. Attached to her, it goes where she goes.
		_attach_hand()

	_build_fridge_door()
	if _state != null:
		if not _state.changed.is_connected(_refresh):
			_state.changed.connect(_refresh)
		if not _state.openness_changed.is_connected(_on_openness_changed):
			_state.openness_changed.connect(_on_openness_changed)
	_refresh()


# ---------------------------------------------------------------------------
# The door -- the one thing that is animated
# ---------------------------------------------------------------------------

## A real door on a real hinge, built the same way the toy box's lid is: an empty
## `Node3D` at the hinge line with the slab parented to it, so opening is one
## rotation and the slab's own geometry never moves.
func _build_fridge_door() -> void:
	if _door_hinge != null:
		return
	var box: Dictionary = _prop_row(Rules.STATION_FRIDGE)
	if box.is_empty():
		return
	var size: Vector3 = box["size"]
	var centre: Vector3 = box["position"]
	var color: Color = box["color"]

	_door_hinge = Node3D.new()
	_door_hinge.name = "FridgeDoor"
	# The hinge line: the door's -X edge, on the face nearest the camera.
	_door_hinge.position = centre + Vector3(-size.x * 0.5, 0.0, size.z * 0.5)
	add_child(_door_hinge)

	var tool: SurfaceTool = Kit.begin()
	# The slab, drawn from the hinge outward so its pivot is the hinge.
	Kit.box(tool, Kit.at(Vector3(size.x * 0.5, 0.0, 0.022)),
			Vector3(size.x, size.y * 0.94, 0.045), Palette.light(color))
	# A handle on the far edge: a soft upright bar, ART_BIBLE section 5's
	# "handle as a soft shape" rather than a modelled catch.
	Kit.cylinder(tool, Kit.at(Vector3(size.x * 0.86, 0.0, 0.055)),
			0.022, size.y * 0.30, Palette.deep(color), 10)
	# A freezer line, so the fridge reads as a fridge and not as a cupboard.
	Kit.box(tool, Kit.at(Vector3(size.x * 0.5, size.y * 0.27, 0.047)),
			Vector3(size.x * 0.96, 0.018, 0.012), Palette.deep(color))

	var slab := MeshInstance3D.new()
	slab.name = "Slab"
	slab.mesh = Kit.commit(tool)
	slab.material_override = Kit.material()
	_door_hinge.add_child(slab)


func _on_openness_changed(station_id: String, open: bool) -> void:
	if station_id != Rules.STATION_FRIDGE or _door_hinge == null:
		return
	# NEGATIVE, and this is the bug that made the first build look inert: the
	# slab extends along +X from a hinge on the fridge's -X edge, so a POSITIVE
	# rotation about Y swings it toward -Z -- straight into the back wall, where
	# the child cannot see it. Negative swings it out toward the camera.
	var target: float = -DOOR_OPEN_DEGREES if open else 0.0
	if _door_tween != null and _door_tween.is_valid():
		_door_tween.kill()
	# Tweened, not snapped: the door swinging is the clearest "that worked" signal
	# in the room, and a snap reads as a glitch.
	_door_tween = create_tween()
	_door_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_door_tween.tween_property(_door_hinge, "rotation_degrees:y", target, DOOR_SWING_SEC)


# ---------------------------------------------------------------------------
# Everything else -- rebuilt from the model
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if _state == null or _items_root == null:
		return
	for child: Node in _items_root.get_children():
		child.queue_free()
	for child: Node in _hand_root.get_children():
		child.queue_free()

	for station_id: Variant in Rules.STATIONS.keys():
		var id: String = String(station_id)
		var anchor: Dictionary = _anchor(id)
		if anchor.is_empty():
			continue

		# What is sitting ON the station, in plain sight.
		var resting: String = _state.on_station(id)
		if resting != Items.NONE:
			_items_root.add_child(_make_item(resting, anchor["surface"], SURFACE_SCALE))

		# What is INSIDE it -- drawn only while the door is open, which is the
		# reason opening the fridge is worth a beat of its own.
		if Rules.opens(id) and not _state.is_open(id):
			continue
		var contents: Array = _state.inside(id)
		# Whether or not there is anything left in it: an empty fridge that looks
		# shut is the same defect as a full one that looks shut.
		if Rules.opens(id):
			_items_root.add_child(_store_interior(id, anchor["inside"]))
		var spread: float = float(anchor.get("spread", 0.19))
		for i: int in range(contents.size()):
			var spot: Vector3 = anchor["inside"] + Vector3(
					(float(i) - float(contents.size() - 1) * 0.5) * spread,
					0.0,
					0.0)
			_items_root.add_child(_make_item(String(contents[i]), spot, SURFACE_SCALE))

	# And what Aliz is carrying, in front of her rather than inside her.
	var held: String = _state.held()
	if held != Items.NONE:
		var carried: MeshInstance3D = _make_item(held, Vector3.ZERO, HAND_SCALE)
		# Every item mesh is authored STANDING on its own origin (pivot at base
		# centre, §6), which is right for a worktop and wrong for a hand: it hung
		# the whole bottle ABOVE her fist. Drop it by half its own height so the
		# hand holds the middle of it, measured off the mesh rather than guessed
		# per shape.
		var bounds: AABB = carried.mesh.get_aabb() if carried.mesh != null else AABB()
		carried.position = Vector3(
			0.0, -(bounds.position.y + bounds.size.y * 0.5) * HAND_SCALE, 0.0
		)
		_hand_root.add_child(carried)
		_hand_root.visible = true
		_place_hand()
	else:
		_hand_root.visible = false


func _process(_delta: float) -> void:
	if _hand_root == null or not _hand_root.visible:
		return
	# Re-checks the ATTACHMENT, so it self-heals if she is ever rebuilt.
	if _hand_root.get_parent() == self:
		_attach_hand()
	# And follows her hand. Her arms swing while she walks, so this cannot be a
	# fixed offset -- but it is only a position, never a rotation: the item stays
	# upright in her own frame, because a bottle that rolls with the wrist reads
	# as dropped rather than as carried.
	_follow_hand()


## Puts the carried-item node under whoever is carrying things, falling back to
## this view so it is always in SOME tree and never leaks.
func _attach_hand() -> void:
	if _hand_root == null:
		return
	# Found LATE on purpose. The kitchen is built while the world is still
	# assembling itself, and the character may not be bound yet -- in which case
	# an early capture would be null for the rest of the session.
	if _carrier == null or not is_instance_valid(_carrier):
		_carrier = _find_carrier()
	var parent: Node = _carrier if _carrier != null else self
	if _hand_root.get_parent() == parent:
		return
	if _hand_root.get_parent() != null:
		_hand_root.get_parent().remove_child(_hand_root)
	parent.add_child(_hand_root)
	_hand_root.position = Vector3(0.0, HAND_HEIGHT, -HAND_FORWARD)
	_hand_root.rotation = Vector3.ZERO
	_skeleton = null
	_hand_bone = -1
	_rig_searched = false
	_follow_hand()


func _place_hand() -> void:
	_attach_hand()


# ---------------------------------------------------------------------------
# Her hands
# ---------------------------------------------------------------------------

## The rig, found once and remembered. `-1` means "looked and there was none",
## which is a different state from "not looked yet" (`_skeleton == null`).
var _skeleton: Skeleton3D = null
var _hand_bone: int = -1
## Set once the subtree has been walked, so a character with no rig costs one
## search rather than one per frame.
var _rig_searched: bool = false


## Puts the carried item where her hand actually is.
##
## ## Why this is not a constant any more
##
## The item used to hang at a fixed (0, 0.62, -0.26) in her own space. Rendered
## at the close-up the game really uses, that is chest height with both arms
## hanging at her sides: the bottle intersected her dress and read as stuck to
## her tummy. The brief is explicit -- "carried items must sit in Aliz's hands
## rather than hovering" -- and no single constant can satisfy it, because her
## arms swing.
##
## The shipped character is a skinned GLB with a 24-bone rig, so the hand is
## simply a bone and its position is available every frame for the cost of two
## matrix multiplies. Only the POSITION is taken. Taking the rotation too would
## be more "correct" and looks worse: the wrist rolls through the walk cycle and
## a bottle that rolls with it reads as dropped.
##
## Everything here degrades quietly. A character with no skeleton (the toddler
## placeholder), or a rig whose hand bone has been renamed, keeps the old fixed
## offset -- which is not right, but is on-screen and stable rather than at the
## world origin.
func _follow_hand() -> void:
	if _hand_root == null or _carrier == null or not is_instance_valid(_carrier):
		return
	if _hand_root.get_parent() != _carrier:
		return
	if not _rig_searched:
		_rig_searched = true
		_skeleton = _find_skeleton(_carrier)
		_hand_bone = -1
		if _skeleton != null:
			for bone_name: String in HAND_BONES:
				var index: int = _skeleton.find_bone(bone_name)
				if index >= 0:
					_hand_bone = index
					break
			if _hand_bone < 0:
				push_warning("The carried item has no hand to sit in: none of %s is a bone "
						% str(HAND_BONES) + "on this rig, so it falls back to a fixed offset.")
	if _skeleton == null or _hand_bone < 0 or not _skeleton.is_inside_tree():
		return
	var wrist: Transform3D = (
		_skeleton.global_transform * _skeleton.get_bone_global_pose(_hand_bone)
	)
	# Into HER space, where the offset below is authored: +X is her right, -Z is
	# the way she is facing.
	var local: Vector3 = _carrier.global_transform.affine_inverse() * wrist.origin
	_hand_root.position = local + HAND_BONE_OFFSET
	_hand_root.rotation = Vector3.ZERO


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


## The character who carries things, asked of the world rather than remembered.
func _find_carrier() -> Node3D:
	var world: Node = _room.get_parent() if _room != null else null
	while world != null and not world.has_method("get_current_room_id"):
		world = world.get_parent()
	if world == null:
		return null
	return world.get_node_or_null("LittleBuddy") as Node3D


# ---------------------------------------------------------------------------
# Item meshes -- five shapes, because five silhouettes are five words
# ---------------------------------------------------------------------------

## ART_BIBLE section 6: an object must be recognisable by outline alone. A child who
## cannot tell the bowl from the apple cannot be asked for either by name, so the
## shapes are deliberately unalike rather than five tinted spheres.
func _make_item(item_id: String, at: Vector3, draw_scale: float = 1.0) -> MeshInstance3D:
	var size: float = Items.size_for(item_id)
	var color: Color = Items.color_for(item_id)
	var tool: SurfaceTool = Kit.begin()

	match Items.shape_for(item_id):
		"ball":
			Kit.box(tool, Kit.at(Vector3(0.0, size, 0.0)),
					Vector3(size * 2.0, size * 2.0, size * 2.0), color, size * 0.9, 3)
			# A stalk, so an apple is not a ball.
			Kit.cylinder(tool, Kit.at(Vector3(0.0, size * 2.1, 0.0)),
					size * 0.10, size * 0.42, Palette.deep(Palette.MINT), 6)
		"cup":
			# A bottle: body, shoulder, teat. Unmistakable against a bowl.
			Kit.cylinder(tool, Kit.at(Vector3(0.0, size * 0.85, 0.0)),
					size * 0.62, size * 1.7, color, 12)
			Kit.cylinder(tool, Kit.at(Vector3(0.0, size * 1.90, 0.0)),
					size * 0.34, size * 0.40, Palette.SOFT_PINK, 10)
			Kit.box(tool, Kit.at(Vector3(0.0, size * 2.24, 0.0)),
					Vector3(size * 0.44, size * 0.30, size * 0.44), Palette.SOFT_PINK, size * 0.14, 2)
		"bowl":
			Kit.vessel(tool, Kit.at(Vector3(0.0, size * 0.42, 0.0)),
					Kit.circle(size, 14), size * 0.84, size * 0.16, size * 0.16,
					Palette.CREAM, color)
		"flat":
			# A banana or a spoon: long, low and curved-ended.
			Kit.plate(tool, Kit.at(Vector3(0.0, size * 0.18, 0.0)),
					Kit.rounded_rect(Vector2(size * 1.9, size * 0.72), size * 0.34, 4),
					size * 0.34, color)
		_:
			Kit.box(tool, Kit.at(Vector3(0.0, size, 0.0)),
					Vector3(size * 1.6, size * 1.6, size * 1.6), color, size * 0.2, 2)

	var node := MeshInstance3D.new()
	node.name = "Item_%s" % item_id
	node.mesh = Kit.commit(tool)
	node.material_override = Kit.material()
	node.position = at
	node.scale = Vector3.ONE * draw_scale
	return node


## -- The inside of a cupboard that opens -----------------------------------------

## How far above a store station's centre its one shelf runs.
const SHELF_Y: float = 0.22
## Of the station's own width and height.
const LINING_INSET: float = 0.17


## The lining and the shelf a `store` station's contents stand on, built only
## while the door is open.
##
## ## Why the fridge looked shut when it was open
##
## `room_props.gd` draws the fridge with its door ALREADY ON IT -- two pale
## panels and a freezer line on the front face -- and this file then hangs a
## second, real, hinged door in front of that. Swinging the real one open
## therefore revealed the painted one underneath, and the only way to tell an
## open fridge from a closed one was three small items apparently stuck to its
## front. Cold, on an iPad, the fridge simply did not open.
##
## So opening it now puts a lining over that painted door: a warm-deep cavity
## face with a cream shelf across it. Two things come out of one change -- the
## fridge visibly opens, and the food stops floating, because the shelf is really
## underneath it.
##
## It cannot be a recess. The fridge body is a solid mesh and anything modelled
## behind its front face is simply occluded by it (the same mistake that made the
## food invisible in the first place), so the lining stands a few centimetres
## PROUD of the front and reads as depth because its interior is a step darker
## than everything around it. No collider, no touch target: the fridge's own
## `ActivityTarget` box already covers all of this, so a tap anywhere here still
## lands on `kitchen.fridge`.
func _store_interior(station_id: String, shelf_at: Vector3) -> MeshInstance3D:
	var row: Dictionary = _prop_row(station_id)
	var size: Vector3 = row.get("size", Vector3(0.7, 1.7, 0.65))
	var front: float = shelf_at.z

	var tool: SurfaceTool = Kit.begin()
	# The cavity face, in the house's "there is no metal" dusty blue (§7) rather
	# than in a deepened step of the fridge's own mint. Mint on mint is one shape
	# in two values and the opening did not read; a cool blue-grey interior reads
	# as cold storage and, more usefully, is the one value in the room that a
	# cream bottle, a yellow banana and a pink apple all stand out against.
	Kit.plate(
		tool,
		Kit.at_rotated(Vector3(0.0, 0.0, -0.045), Vector3(-90.0, 0.0, 0.0)),
		Kit.rounded_rect(
			Vector2(size.x - LINING_INSET, size.y * 0.68), 0.05, 3),
		0.05, Palette.DUSTY_BLUE, 0.014
	)
	# The shelf, a little proud of the lining so it catches the light and so an
	# item standing on it is not half-buried in the back wall.
	Kit.plate(
		tool,
		Kit.at(Vector3(0.0, -0.012, 0.03)),
		Kit.rounded_rect(Vector2(size.x - LINING_INSET - 0.04, 0.20), 0.03, 2),
		0.024, Palette.CREAM, 0.008
	)
	# And a second, empty shelf below it, because one shelf is a ledge and two
	# are a fridge.
	Kit.plate(
		tool,
		Kit.at(Vector3(0.0, -0.42, 0.03)),
		Kit.rounded_rect(Vector2(size.x - LINING_INSET - 0.04, 0.20), 0.03, 2),
		0.024, Palette.CREAM, 0.008
	)

	var node := MeshInstance3D.new()
	node.name = "Interior_%s" % station_id
	node.mesh = Kit.commit(tool)
	node.material_override = Kit.material()
	node.position = Vector3(shelf_at.x, shelf_at.y, front)
	return node


# ---------------------------------------------------------------------------

## The furniture row a station is played by, from the layout itself. Nothing here
## re-types a position: a piece of furniture that moves in `house_layout.gd`
## takes its station's items with it.
func _prop_row(station_id: String) -> Dictionary:
	var layout: GDScript = load("res://scripts/house/house_layout.gd")
	if layout == null:
		return {}
	for row: Variant in layout.furniture("kitchen"):
		var data: Dictionary = row
		if String(data.get("targetId", "")) == station_id:
			return data
	return {}


## `{surface, inside, spread}` in room-local space for a station, or `{}` if the
## kitchen has no such furniture.
##
## ## The counter has TWO rows, and that was a bug before it was a composition
##
## `inside` used to be computed the same way for every station: proud of the
## front face, at `size.y * 0.16` above the centre. On the fridge that is the
## open doorway and it is correct. On the COUNTER -- which has no door, so its
## contents are drawn all the time -- it put the bowl and the spoon **0.59 m up
## and 0.30 m out in front of the cabinet doors, resting on nothing**. That is
## the brief's "objects floating in mid-air", and it was in the first frame of
## the kitchen.
##
## So a station that does not open puts its contents ON its top, at the back,
## against the splashback, with the front of the worktop left clear for the prep
## board -- the two rows `house_layout.gd` plans out under `WORKTOP_*`.
func _anchor(station_id: String) -> Dictionary:
	var row: Dictionary = _prop_row(station_id)
	if row.is_empty():
		return {}
	var size: Vector3 = row["size"]
	var centre: Vector3 = row["position"]
	var top: float = centre.y + size.y * 0.5 + SURFACE_LIFT

	if station_id == Rules.STATION_COUNTER:
		return {
			# The prep board, which `room.gd` draws at exactly these numbers.
			"surface": Vector3(
				HouseLayout.WORKTOP_BOARD_X,
				HouseLayout.WORKTOP_Y + HouseLayout.WORKTOP_BOARD_THICKNESS,
				HouseLayout.WORKTOP_BOARD_Z
			),
			# Standing on the worktop at the back, between the hob and the sink.
			"inside": Vector3(
				HouseLayout.WORKTOP_BOARD_X, HouseLayout.WORKTOP_Y, HouseLayout.WORKTOP_BACK_Z
			),
			"spread": HouseLayout.WORKTOP_SPREAD,
		}

	if Rules.opens(station_id):
		return {
			"surface": Vector3(centre.x, top, centre.z + size.z * 0.22),
			# ON THE SHELF, in the doorway -- not in the middle of the cupboard.
			#
			# The first version put contents at `centre.z + size.z * 0.18`, which
			# is geometrically inside the fridge and therefore inside a solid
			# mesh: the food was built, was in the right place, and was completely
			# invisible. A child cannot tap what they cannot see. It then sat on
			# the threshold with nothing under it, which is the same defect one
			# step out; `_store_interior()` now builds the shelf it stands on.
			"inside": Vector3(centre.x, centre.y + SHELF_Y, centre.z + size.z * 0.5 + 0.075),
			"spread": 0.17,
		}

	# `top` carries `SURFACE_LIFT`, which is a 3 cm hover. On a worktop nobody
	# could see it; on the TABLE, which is the station a finished meal is served
	# on and which the camera then flies in to look at, a bowl 3 cm off the wood
	# is exactly the "floating in mid-air" the brief asks to be rid of. So a
	# served dish sits on the placemat `room.gd` lays for it, and nothing here
	# hovers.
	var serve_z: float = centre.z + size.z * HouseLayout.TABLE_MAT_FORWARD
	if room_serves(station_id):
		return {
			"surface": Vector3(
				centre.x,
				centre.y + size.y * 0.5 + HouseLayout.TABLE_MAT_THICKNESS,
				serve_z
			),
			"inside": Vector3(centre.x, centre.y + size.y * 0.5, centre.z - size.z * 0.20),
			"spread": 0.19,
		}
	return {
		"surface": Vector3(centre.x, top, serve_z),
		"inside": Vector3(centre.x, centre.y + size.y * 0.5, centre.z - size.z * 0.20),
		"spread": 0.19,
	}


## Does this station lay a placemat? The table, and anything else that is ever
## given the `serve` role.
func room_serves(station_id: String) -> bool:
	return Rules.role_of(station_id) == "serve"
