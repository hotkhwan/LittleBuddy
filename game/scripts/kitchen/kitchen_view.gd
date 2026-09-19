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

## Where a station puts things a child can see, in ROOM-LOCAL space. Derived from
## `house_layout.gd`'s own furniture table rather than typed twice -- see
## `_anchor()`. Only the offsets above each piece live here.
##
## `surface` is the top of the furniture; `inside` is the shelf a store station
## shows its contents on when its door is open.
const SURFACE_LIFT: float = 0.03

## The fridge door. Hinged on its -X edge so it swings toward the camera and to
## the left, which keeps the opening -- and the food -- facing the child.
const DOOR_OPEN_DEGREES: float = 104.0
const DOOR_SWING_SEC: float = 0.32

## How the held item sits in front of Aliz: forward of her chest, at hand height.
const HAND_FORWARD: float = 0.26
const HAND_HEIGHT: float = 0.62

## And how much BIGGER it is drawn while carried.
##
## A 0.13 m spoon is correct on a worktop and unreadable in a hand at the house
## camera's distance -- it measured a handful of pixels, against a striped dress
## of a similar value. "What am I carrying?" is the single question this system
## must always be able to answer at a glance, so the held copy is drawn half as
## big again. The world copy is untouched; nothing about the model changes.
const HAND_SCALE: float = 1.55

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
			_items_root.add_child(_make_item(resting, anchor["surface"]))

		# What is INSIDE it -- drawn only while the door is open, which is the
		# reason opening the fridge is worth a beat of its own.
		if Rules.opens(id) and not _state.is_open(id):
			continue
		var contents: Array = _state.inside(id)
		for i: int in range(contents.size()):
			var spot: Vector3 = anchor["inside"] + Vector3(
					(float(i) - float(contents.size() - 1) * 0.5) * 0.19,
					0.0,
					0.0)
			_items_root.add_child(_make_item(String(contents[i]), spot))

	# And what Aliz is carrying, in front of her rather than inside her.
	var held: String = _state.held()
	if held != Items.NONE:
		var carried: Node3D = _make_item(held, Vector3.ZERO)
		carried.scale = Vector3.ONE * HAND_SCALE
		_hand_root.add_child(carried)
		_hand_root.visible = true
		_place_hand()
	else:
		_hand_root.visible = false


func _process(_delta: float) -> void:
	# Only re-checks the ATTACHMENT -- the offset is fixed in her own space, so
	# there is no per-frame position maths to get wrong. Cheap enough to run
	# while something is carried, and it self-heals if she is ever rebuilt.
	if _hand_root != null and _hand_root.visible and _hand_root.get_parent() == self:
		_attach_hand()


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
	# A fixed offset in HER space: forward of the chest, at hand height. No
	# per-frame maths, and it cannot drift out of sync with her.
	_hand_root.position = Vector3(0.0, HAND_HEIGHT, -HAND_FORWARD)
	_hand_root.rotation = Vector3.ZERO


func _place_hand() -> void:
	_attach_hand()


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
func _make_item(item_id: String, at: Vector3) -> MeshInstance3D:
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


## `{surface, inside}` in room-local space for a station, or `{}` if the kitchen
## has no such furniture.
func _anchor(station_id: String) -> Dictionary:
	var row: Dictionary = _prop_row(station_id)
	if row.is_empty():
		return {}
	var size: Vector3 = row["size"]
	var centre: Vector3 = row["position"]
	var top: float = centre.y + size.y * 0.5 + SURFACE_LIFT
	return {
		# On top, pulled toward the camera so the furniture does not hide it.
		"surface": Vector3(centre.x, top, centre.z + size.z * 0.22),
		# IN THE DOORWAY, not in the middle of the cupboard.
		#
		# The first version put contents at `centre.z + size.z * 0.18`, which is
		# geometrically inside the fridge and therefore inside a solid mesh: the
		# food was built, was in the right place, and was completely invisible.
		# A child cannot tap what they cannot see, so the contents sit ON the
		# threshold -- just proud of the front face, at hand height.
		"inside": Vector3(centre.x, centre.y + size.y * 0.16, centre.z + size.z * 0.5 + 0.10),
	}
