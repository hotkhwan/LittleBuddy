extends RefCounted

## The house, as data. Four greybox rooms, their furniture, their doors and their
## spawn points -- one source of truth shared by the room builder, the navigation
## bake tool, the camera framing and the tests.
##
## Everything here is expressed in ROOM-LOCAL coordinates (the room's floor is
## centred on its own origin) plus a per-room world `origin`. That split is what
## lets the navigation bake produce one mesh per room, in the room's own space,
## that can be baked, committed, diffed and re-used without knowing where in the
## world the room was eventually placed.
##
## ## Why the rooms are 10 m apart
##
## The house is DISCRETE: the child is in exactly one room at a time and doors
## teleport between them (see `room_transition_controller.gd`). Every room
## therefore exists simultaneously in one scene, spaced far enough apart that
## their navigation meshes can never connect into one map island. That spacing is
## the reason "walk from the bedroom to the bathroom sink" is correctly refused as
## unreachable rather than quietly walking through a wall.
##
## ## Scale (contract §3)
##
## Toddler ~0.85 m, door 1.9 m, counter 0.9 m, sofa seat 0.4 m, rooms 4 x 4 m.
## These are the numbers a reviewer should check; nothing else in the greybox
## matters.

## Room ids, camelCase, exactly as the Phase 2B contract fixes them.
const BEDROOM: String = "bedroom"
const BATHROOM: String = "bathroom"
const KITCHEN: String = "kitchen"
const LIVING_ROOM: String = "livingRoom"

## Play order round the ring: each room's right-hand (+X) door leads to the next
## and its left-hand (-X) door leads back to the previous. A ring means no dead
## ends and at most one intermediate room between any two rooms.
const ROOM_RING: Array[String] = [BEDROOM, BATHROOM, LIVING_ROOM, KITCHEN]

## The room a corrupt or unknown saved room id ultimately falls back to.
const FALLBACK_ROOM: String = BEDROOM
const DEFAULT_SPAWN: String = "default"

## Interior floor: 4 x 4 m, centred on the room origin.
const FLOOR_BOUNDS: Rect2 = Rect2(-2.0, -2.0, 4.0, 4.0)
const FLOOR_Y: float = 0.0

## Walls sit entirely OUTSIDE the interior floor, so the walkable area is bounded
## by the floor edge on all four sides equally -- including the open front, which
## has no wall at all so the camera can see in.
const WALL_THICKNESS: float = 0.15
const WALL_HEIGHT: float = 2.2
const DOOR_WIDTH: float = 0.9
const DOOR_HEIGHT: float = 1.9
const DOOR_THICKNESS: float = 0.1
## Doors are centred this far towards the camera, leaving the back half of each
## side wall free for furniture.
const DOOR_Z: float = 0.6
## Where the child stands to use a door: inside the room, in front of it.
const DOOR_STAND_X: float = 1.45

## -- The door plaque -----------------------------------------------------------
##
## `room.gd::_build_door_sign()` draws it; the numbers live here because
## `camera_framing()` has to keep it on screen, and a sign whose size is known in
## one file and framed from another drifts the first time either is touched.
##
## **Half the area it used to be.** The first plaque was 0.92 x 0.46 m -- as wide
## as the door it hung over, and about the width of the child's whole body -- with
## a 64 pt word under a chunky glyph. On an iPad it read as a placeholder label
## stuck onto the scene, which is precisely what the brief rejects. A 0.60 x 0.30 m
## plaque is a sign in a home rather than a banner over a shop, and at the room
## shot's distance the glyph is still ~40 px across, which is what a pre-reader
## actually navigates by.
const DOOR_SIGN_SIZE: Vector2 = Vector2(0.60, 0.30)
## Centre height. Clear of the door's sunk panel below and the architrave above.
const DOOR_SIGN_CENTRE_Y: float = 1.45
## How far into the room the plaque hangs from the side wall.
const DOOR_SIGN_X: float = 1.76

## -- The kitchen worktop -------------------------------------------------------
##
## The counter is the one SHARED surface in the house: `room.gd` draws the sink,
## the tap, the hob and the prep board into it, and `kitchen_view.gd` stands the
## child's ingredients on it. Two files placing things on one 1.8 m plank by
## eye is how a bowl ends up half inside a hob, so the plan lives here once and
## both of them read it.
##
## ## The layout, and why it is this one
##
## Left to right: **hob, prep board, sink**. The sink is under the window
## because that is where a sink is, and "a room a four-year-old recognises as a
## kitchen at a glance" is the whole point of the fixtures -- the previous
## arrangement had the sink in the dark left-hand corner under the wall units and
## a bare stretch of worktop under the window, which is nobody's kitchen.
##
## The prep board is the middle third, and it is not decoration: `kitchen_view`
## puts a carried item down at `WORKTOP_BOARD_X`, so the board is the visible
## answer to "where does this go?" **and** the dark warm field a cream bottle or
## a pale banana needs behind it. Ingredients on a cream worktop in front of a
## cream wall were, measured on an iPad render, a few pale pixels.
const WORKTOP_Y: float = 0.90
## Under the window (which spans x -0.50 to 0.80), and as far right as the
## worktop allows: the counter runs to x = 0.10 and the basin is 0.44 wide, so
## anything past -0.13 hangs the bowl of the sink off the end of the bench.
## `test_kitchen_view_placement.gd` measures it; the first value here was -0.10
## and really did overhang by 2 cm.
const WORKTOP_SINK_X: float = -0.13
const WORKTOP_SINK_Z: float = -1.60
const WORKTOP_HOB_X: float = -1.50
const WORKTOP_HOB_Z: float = -1.68
## The prep board: the drop zone, made visible.
const WORKTOP_BOARD_X: float = -0.80
const WORKTOP_BOARD_Z: float = -1.52
const WORKTOP_BOARD_SIZE: Vector2 = Vector2(0.72, 0.34)
const WORKTOP_BOARD_THICKNESS: float = 0.035
## Two rows, and that is what stops the worktop reading as a jumble: what LIVES
## on the counter stands at the back against the splashback, and what the child
## is working on sits at the front on the board.
const WORKTOP_BACK_Z: float = -1.78
## The placemat on the kitchen table. Same argument as the prep board one line
## up: `kitchen_view.gd` serves a finished dish here, so the spot is marked, and
## a pale bowl set on bare `deep(peach)` wood needs something under it. It also
## stops the table being the one piece of furniture in the room with nothing on
## it at all.
const TABLE_MAT_SIZE: Vector2 = Vector2(0.48, 0.34)
const TABLE_MAT_THICKNESS: float = 0.018
## How far forward of the table's centre, as a fraction of its depth. The mat is
## pulled toward the camera so the table itself does not hide what is on it.
const TABLE_MAT_FORWARD: float = 0.22

## Half the gap between two things standing in the back row. Derived, not
## chosen: the free worktop between the hob's right edge (-1.31) and the sink's
## left (-0.32) is 0.99 m, and a 0.15 m bowl drawn at `SURFACE_SCALE` needs
## 0.18 m of it either side of its centre.
const WORKTOP_SPREAD: float = 0.22

## Distance between neighbouring room origins along X. Far larger than a 4 m room
## plus the navigation map's edge-connection margin, so no two rooms' meshes can
## ever be joined.
const ROOM_SPACING: float = 10.0

## Collision layer for all static house geometry (floors, walls, furniture).
## Layer 1 belongs to draggable pickups and layer 2 to `ActivityTarget`; keeping
## the house on its own layer means the navigation bake can select exactly the
## geometry it should and nothing can steal a child's tap.
const HOUSE_GEOMETRY_LAYER: int = 4

## Navigation bake parameters. `agent_radius` is an exact multiple of `cell_size`
## because Godot ceils it to whole voxels and warns when it has to round.
const NAV_CELL_SIZE: float = 0.05
const NAV_CELL_HEIGHT: float = 0.05
const NAV_AGENT_RADIUS: float = 0.20
const NAV_AGENT_HEIGHT: float = 0.85
const NAV_AGENT_MAX_CLIMB: float = 0.05
const NAV_AGENT_MAX_SLOPE: float = 10.0
## Smaller than the thinnest wall, so an edge connection can never bridge one.
const NAV_EDGE_CONNECTION_MARGIN: float = 0.05

const NAVMESH_DIR: String = "res://scenes/house/navmesh"

## Camera framing (contract §6). Pitch is a preference, distance is fitted per
## aspect ratio by `room_framing.gd` -- a fixed distance cannot frame a room on
## both a 1.33:1 iPad and a 2.17:1 landscape iPhone.
const CAMERA_ANGLE_DEGREES: float = 32.0
const CAMERA_MIN_DISTANCE: float = 3.5
const CAMERA_MAX_DISTANCE: float = 18.0
## What the camera looks at: a little above the floor so the toddler's head
## rather than its feet sits in the centre of the frame.
const CAMERA_FOCUS_HEIGHT: float = 0.55

## ...and NOT the middle of the room. The look-at point sits this far towards the
## open front, and that one number is worth ~13% of the room shot's scale.
##
## The fit is symmetric about the look-at point but the room is not symmetric
## about the camera: pitched down 32 degrees, the near floor edge falls a long
## way BELOW a centred focus while the far wall rises only a little above it. The
## room-centred shot was therefore bound, at every aspect ratio the game ships on,
## by the near-left floor corner needing 5.13 m while the back wall needed 2.24 m
## -- more than two metres of distance spent on a constraint that was not even
## close to being the hard one. Sliding the look-at point forward trades that
## slack for scale until the two constraints meet.
##
## It is a composition change, not a crop: `camera_framing.solve()` still fits
## every floor corner, every head-height corner and every tall prop, so nothing
## the child can walk to or tap leaves the safe area.
const CAMERA_FOCUS_Z: float = 0.42

## Above this, a prop's top corners are added to the camera's must-be-visible
## list by name rather than left to the generic `headroom`. The wardrobe (1.8 m)
## and the fridge (1.7 m) are activity targets with doors that open; a tighter
## shot that cropped their tops would be cropping an interaction.
##
## Deliberately NOT applied to the window (top at ~2.03 m): it is warmth, not
## gameplay, it is the single highest thing in the house, and keeping it inside
## the safe area on its own costs the whole of the gain above. It stays on
## screen -- it simply loses the right to sit below the status line.
const CAMERA_TALL_PROP_Y: float = 1.05

## -- Colour (ART_BIBLE.md section 3, LOCKED) ------------------------------------
##
## Nothing here invents a colour. Every value is one of the seven tokens or one
## of the two documented derivations of one (`light` = 45% toward `cream`,
## `deep` = 22% toward `ink`), taken from `palette.gd` so the house and the UI
## cannot drift apart. `Color` is a core type, not a 3D one, so this stays on the
## right side of the `test_architecture_guard.gd` line.

const Palette := preload("res://scripts/ui/palette.gd")

## Warm wood, in two steps of one token. The FLOOR is `peach` itself -- a pale
## sunlit board, because a dark floor is the fastest way to lose the "warm,
## sunlit picture book" of section 2 -- and FURNITURE is `deep(peach)`, so a bed
## or a table always reads against the boards it stands on. One is the floor, the
## other is everything made of wood; they are never the same value.
const WOOD_COLOR: Color = Color(0.857, 0.702, 0.594)       # deep(peach)
const FLOOR_COLOR: Color = Palette.PEACH
## Section 3: "Every room keeps `cream` as its base; only the accent shifts."
const WALL_COLOR: Color = Palette.CREAM
const DOOR_COLOR: Color = WOOD_COLOR


## -- The bed, and the pose that has to land on it --------------------------------
##
## The bed is the one piece of furniture whose exact geometry another file has to
## agree with, so its numbers are named rather than buried in the furniture
## table.
##
## `sleep` is played AT THE STAND POSITION, because that is where the child
## finishes walking -- which is why, before this, tapping the bed laid Little
## Buddy flat on his back on the floor in front of it. The clip in
## `toddler_view.gd` therefore carries an offset: forward by `BED_LIE_FORWARD`,
## up by `BED_LIE_HEIGHT`. Those two numbers and these three are the same
## contract seen from either end, and `test_art_rooms.gd` asserts they agree.
##
## The bed runs ALONG Z (headboard at the back wall) and is approached from its
## +X side, for a reason that is easy to get wrong: a lying child's head points
## along his own local +X, and a child facing -X has his local +X pointing at
## world -Z. Head to the headboard only works with the bed turned this way.
const BED_SIZE: Vector3 = Vector3(0.92, 0.45, 1.34)
const BED_POSITION: Vector3 = Vector3(-1.30, 0.225, -1.25)
## Where the child stands to use the bed: 0.9 m out along +X from its centre,
## which leaves 0.44 m of clear floor beside it -- more than the 0.20 m agent
## radius, so the navigation mesh really reaches it.
const BED_STAND_X: float = -0.40
## Stand point to the middle of the mattress, perpendicular to the bed.
const BED_LIE_FORWARD: float = 0.90
## And then along the bed, from its middle toward the FOOT, so a 0.85 m child
## lying head-first ends up with his head on the pillow rather than 18 cm through
## the headboard.
const BED_LIE_ALONG: float = 0.25
## Top of the blanket, above the floor. A child lying down rests here.
const BED_LIE_HEIGHT: float = 0.40


## -- Surfaces a character can be set down on (Free Play, 2026-09-20) ------------
##
## Where Bunny lands when Aliz carries him to a piece of furniture, and where
## SHE sits when she arrives alone. Room-local, like everything else here;
## `yaw` is the heading in the project's convention (`NavMath.yaw_towards`:
## the character faces -Z at yaw 0). `seatHeight` is the surface the pelvis
## rests on, for the seated pose to land on. An id with no entry has no
## surface, and the caller falls back to the floor.
const HIP_SEATED_HEIGHT: float = 0.42


static func child_surface(room_id: String, local_id: String) -> Dictionary:
	match [room_id, local_id]:
		[BEDROOM, "bed"]:
			# Head to the pillow: a lying child's head points along his local +X,
			# and facing -X puts that at the headboard (see the bed section).
			return {"position": Vector3(BED_POSITION.x, BED_LIE_HEIGHT, BED_POSITION.z + BED_LIE_ALONG),
					"yaw": PI * 0.5, "activity": "bedtime"}
		[LIVING_ROOM, "sofa"]:
			return {"position": Vector3(-0.32, 0.45, -1.42), "yaw": PI, "activity": "carried"}
		[KITCHEN, "table"]:
			# The table's +X side, facing it: Aliz stands at the FRONT to serve,
			# and a child set down there would sit behind her, hidden.
			return {"position": Vector3(1.12, FLOOR_Y, 0.60), "yaw": PI * 0.5, "activity": "carried"}
		[BATHROOM, "bath"]:
			return {"position": Vector3(0.95, 0.40, -1.48), "yaw": PI, "activity": "bath"}
		_:
			return {}


static func caregiver_seat(room_id: String, local_id: String) -> Dictionary:
	match [room_id, local_id]:
		[LIVING_ROOM, "sofa"]:
			return {"position": Vector3(-1.08, FLOOR_Y, -1.34), "yaw": PI, "seatHeight": 0.45}
		[BEDROOM, "bed"]:
			return {"position": Vector3(BED_POSITION.x + 0.28, FLOOR_Y, BED_POSITION.z + 0.30),
					"yaw": -PI * 0.5, "seatHeight": 0.41}
		_:
			return {}


## Every room id, in ring order.
static func room_ids() -> Array:
	var ids: Array = []
	ids.assign(ROOM_RING)
	return ids


static func has_room(room_id: String) -> bool:
	return ROOM_RING.has(room_id)


## World origin of a room. Rooms are laid out in a line along X in ring order.
static func room_origin(room_id: String) -> Vector3:
	var index: int = ROOM_RING.find(room_id)
	if index < 0:
		index = 0
	return Vector3(float(index) * ROOM_SPACING, 0.0, 0.0)


## The room clockwise round the ring (through the right-hand door).
static func next_room(room_id: String) -> String:
	var index: int = ROOM_RING.find(room_id)
	if index < 0:
		return FALLBACK_ROOM
	return ROOM_RING[(index + 1) % ROOM_RING.size()]


## The room anticlockwise round the ring (through the left-hand door).
static func previous_room(room_id: String) -> String:
	var index: int = ROOM_RING.find(room_id)
	if index < 0:
		return FALLBACK_ROOM
	return ROOM_RING[(index - 1 + ROOM_RING.size()) % ROOM_RING.size()]


## The spawn id a child arriving from `from_room_id` lands on: "fromBedroom",
## "fromLivingRoom", ... Semantic, never a coordinate.
static func arrival_spawn_id(from_room_id: String) -> String:
	if from_room_id.is_empty():
		return DEFAULT_SPAWN
	return "from" + from_room_id.substr(0, 1).to_upper() + from_room_id.substr(1)


## -- Doors ---------------------------------------------------------------------

## The two doors of a room, as plain dictionaries:
##   `targetId`  "doorToBathroom"       -- unique within the room
##   `toRoomId`  "bathroom"
##   `toSpawnId` "fromBedroom"          -- the spawn in the DESTINATION room
##   `side`      -1 for the -X wall, +1 for the +X wall
##   `position`  room-local centre of the door slab
##   `stand`     room-local point to stand on to use it
static func doors(room_id: String) -> Array:
	if not has_room(room_id):
		return []
	var built: Array = []
	for side: int in [-1, 1]:
		var destination: String = previous_room(room_id) if side < 0 else next_room(room_id)
		built.append({
			"targetId": door_target_id(destination),
			"displayName": "door to the %s" % display_name(destination),
			"toRoomId": destination,
			"toSpawnId": arrival_spawn_id(room_id),
			"side": side,
			"position": Vector3(
				float(side) * (FLOOR_BOUNDS.end.x + WALL_THICKNESS * 0.5),
				DOOR_HEIGHT * 0.5,
				DOOR_Z
			),
			"stand": Vector3(float(side) * DOOR_STAND_X, FLOOR_Y, DOOR_Z),
		})
	return built


static func door_target_id(to_room_id: String) -> String:
	return "doorTo" + to_room_id.substr(0, 1).to_upper() + to_room_id.substr(1)


## -- Spawn points --------------------------------------------------------------

## `{spawnId: Vector3}` in room-local space. Always contains "default", plus one
## arrival spawn per door -- just inside the room, in front of the door the child
## came through.
static func spawn_points(room_id: String) -> Dictionary:
	var points: Dictionary = {DEFAULT_SPAWN: Vector3(0.0, FLOOR_Y, 1.5)}
	for door: Dictionary in doors(room_id):
		# Arriving from the room this door leads to means appearing at this door.
		points[arrival_spawn_id(String(door["toRoomId"]))] = door["stand"] as Vector3
	return points


## -- Furniture / activity targets ----------------------------------------------

## The room's 3 furniture activity targets. Each entry:
##   `targetId`   "bed"                    -- the local half of "bedroom.bed"
##   `displayName`"bed"                    -- child-facing text, never an id
##   `size`       Vector3 box size (m)
##   `position`   room-local box CENTRE
##   `stand`      room-local point to stand on to interact
##   `actions`    semantic action names only
##   `color`      temporary greybox material
## -- Storage (the tidy-up activity) ---------------------------------------------

## Which containers a room has, as DATA. `storage_model.gd` turns each row into a
## cabinet, and `room.gd` builds the lid that opens -- neither of them has a
## per-room branch, which is the point: a new drawer is a row here, never a new
## script.
##
## Positions are room-local. `lidPivot` is where the hinge runs, and `openDegrees`
## is how far the lid swings; a container with `openDegrees` 0 has no lid and is
## always usable (a shelf).
static func storages(room_id: String) -> Array:
	match room_id:
		BEDROOM:
			return [{
				"storageId": "toyBox",
				"displayName": "toy box",
				"acceptedItemTags": ["toy"],
				"capacity": 4,
				"size": Vector3(0.74, 0.44, 0.54),
				"position": Vector3(-1.32, 0.22, 1.12),
				"stand": Vector3(-0.78, FLOOR_Y, 1.12),
				"openDegrees": 104.0,
				"color": Palette.MINT,
			}]
		LIVING_ROOM:
			return [{
				"storageId": "toyShelf",
				"displayName": "shelf",
				"acceptedItemTags": ["toy", "book"],
				"capacity": 5,
				"size": Vector3(0.80, 0.46, 0.50),
				"position": Vector3(-1.30, 0.23, 1.10),
				"stand": Vector3(-0.76, FLOOR_Y, 1.10),
				"openDegrees": 100.0,
				"color": Palette.SOFT_PINK,
			}]
		_:
			return []


static func furniture(room_id: String) -> Array:
	match room_id:
		BEDROOM:
			return [
				_prop("bed", "bed", BED_SIZE, BED_POSITION,
						Vector3(BED_STAND_X, FLOOR_Y, BED_POSITION.z), ["sleep", "sit"],
						Palette.LAVENDER),
				_prop("wardrobe", "wardrobe", Vector3(0.9, 1.8, 0.6), Vector3(1.35, 0.9, -1.6),
						Vector3(1.35, FLOOR_Y, -0.95), ["open", "dress"], WOOD_COLOR),
				_prop("toy", "toy", Vector3(0.35, 0.35, 0.35), Vector3(0.9, 0.175, 0.9),
						Vector3(0.9, FLOOR_Y, 1.45), ["pickUp", "play"], Palette.DUSTY_BLUE),
			]
		BATHROOM:
			return [
				_prop("sink", "sink", Vector3(0.6, 0.7, 0.45), Vector3(-1.2, 0.35, -1.72),
						Vector3(-1.2, FLOOR_Y, -1.15), ["wash", "brushTeeth"], Palette.CREAM),
				# 0.68 m tall over 1.26 m long, NOT 0.5 over 1.4. Those two numbers
				# are the whole difference between "bath" and "bench": 0.5 m is
				# exactly coffee-table height, and a low cream box with a flat blue
				# top is furniture to put things on, which is what the first three
				# passes of this room actually rendered. 0.68 m clears a 0.85 m
				# toddler's waist, which is the proportion a bath really has to a
				# child, and it stands on feet, so it is the one object in the house
				# with daylight under it.
				_prop("bath", "bath", Vector3(1.26, 0.68, 0.72), Vector3(0.95, 0.34, -1.48),
						Vector3(0.95, FLOOR_Y, -0.78), ["wash", "play"], Palette.DUSTY_BLUE),
				# ## This comment used to contain a wrong diagnosis, and the towel was
				# ## sized to compensate for it
				#
				# It read: "the one directional light never reaches [the -X wall] at
				# all (its inner face points +X and the sun's X component is
				# negative)", and the towel was grown by half again to be legible in
				# a darkness it was never actually in.
				#
				# That is not what was wrong. The sun's `Transform3D` basis was
				# TRANSPOSED, which put it 36.8 degrees BELOW the floor -- so nothing
				# in the house was lit by it, not this wall in particular. With the
				# basis fixed the -X wall catches the sun like everything else and
				# the towel no longer needs to shout.
				#
				# It is back to a towel-shaped towel: 0.74 m of drop on a 2.2 m wall,
				# which is roughly what a bath towel is against a room, rather than
				# 0.88 m. It is still comfortably the largest soft object on that
				# wall and it still measures well over 40 px on a landscape iPhone.
				#
				# The collider shrinks with it and the navigation bake does not
				# notice: at x = -1.93 the whole prop lies inside the 0.20 m agent
				# radius already eroded away from the -2.0 m wall, so it has never
				# contributed a single walkable cell.
				_prop("towel", "towel", Vector3(0.17, 0.74, 0.62), Vector3(-1.93, 1.14, -0.52),
						Vector3(-1.35, FLOOR_Y, -0.5), ["pickUp", "dry"], Palette.SOFT_PINK),
			]
		KITCHEN:
			return [
				_prop("fridge", "fridge", Vector3(0.7, 1.7, 0.65), Vector3(1.4, 0.85, -1.6),
						Vector3(1.4, FLOOR_Y, -0.95), ["open", "give"], Palette.MINT),
				_prop("counter", "counter", Vector3(1.8, 0.9, 0.6), Vector3(-0.8, 0.45, -1.65),
						Vector3(-0.8, FLOOR_Y, -1.0), ["wash", "give"], WOOD_COLOR),
				_prop("table", "table", Vector3(1.0, 0.7, 0.8), Vector3(0.5, 0.35, 0.55),
						Vector3(0.5, FLOOR_Y, 1.4), ["eat", "sit"], WOOD_COLOR),
			]
		LIVING_ROOM:
			return [
				_prop("sofa", "sofa", Vector3(1.8, 0.75, 0.8), Vector3(-0.7, 0.375, -1.5),
						Vector3(-0.7, FLOOR_Y, -0.85), ["sit", "hug"], Palette.SOFT_PINK),
				# No `open`: this box has no lid and no storage model behind it
				# (the bedroom's has both). It is the room's landing pad -- toys are
				# dragged or carried INTO it -- and a badge that said OPEN on it did
				# nothing when tapped (owner playtest 2026-09-21).
				_prop("toyBox", "toy box", Vector3(0.7, 0.5, 0.5), Vector3(1.45, 0.25, -1.65),
						Vector3(1.45, FLOOR_Y, -1.05), ["play", "putAway"], Palette.MINT),
				# OPEN, and therefore wider than it is deep. A closed book on a floor
				# is a rectangular slab seen from above, and a rectangular slab seen
				# from above is a tray -- which is exactly what the owner named this
				# object as, cold, on a phone. Two cream pages either side of a spine
				# is a silhouette nothing else in this house has (ART_BIBLE.md §6).
				_prop("book", "book", Vector3(0.46, 0.16, 0.36), Vector3(0.3, 0.08, 0.8),
						Vector3(0.3, FLOOR_Y, 1.4), ["read", "pickUp"], Palette.DUSTY_BLUE),
			]
		_:
			return []


static func _prop(
	target_id: String,
	display: String,
	size: Vector3,
	position: Vector3,
	stand: Vector3,
	actions: Array,
	color: Color
) -> Dictionary:
	return {
		"targetId": target_id,
		"displayName": display,
		"size": size,
		"position": position,
		"stand": stand,
		"actions": actions,
		"color": color,
	}


## Every activity target id in a room -- furniture AND doors. Doors are activity
## targets too: the child walks to one exactly as to a fridge.
static func target_ids(room_id: String) -> Array:
	var ids: Array = []
	for prop: Dictionary in furniture(room_id):
		ids.append(String(prop["targetId"]))
	for door: Dictionary in doors(room_id):
		ids.append(String(door["targetId"]))
	return ids


## "kitchen.fridge". The only address content data is ever allowed to use.
static func semantic_id(room_id: String, target_id: String) -> String:
	return "%s.%s" % [room_id, target_id]


## -- Presentation --------------------------------------------------------------

static func display_name(room_id: String) -> String:
	match room_id:
		BEDROOM:
			return "bedroom"
		BATHROOM:
			return "bathroom"
		KITCHEN:
			return "kitchen"
		LIVING_ROOM:
			return "living room"
		_:
			return room_id


## The floor is the same warm wood in every room (section 5). A room is told
## apart by its MOOD -- its wainscot, its rug, its furniture -- not by a tinted
## floor, which is what the greybox used and which read as four different houses
## rather than as four rooms of one.
static func floor_color(_room_id: String) -> Color:
	return FLOOR_COLOR


## The room's dominant accent (section 3, "Room moods"). Wainscot, rug, the large
## soft masses. Every room keeps `cream` as its base; only this shifts.
static func dominant_color(room_id: String) -> Color:
	match room_id:
		BEDROOM:
			return Palette.LAVENDER
		BATHROOM:
			return Palette.DUSTY_BLUE
		KITCHEN:
			return Palette.PEACH
		LIVING_ROOM:
			return Palette.PEACH
		_:
			return Palette.PEACH


## The room's secondary accent (section 3). The one object per room that is
## allowed to be the brightest thing in it.
static func accent_color(room_id: String) -> Color:
	match room_id:
		BEDROOM:
			return Palette.DUSTY_BLUE
		BATHROOM:
			return Palette.MINT
		KITCHEN:
			return Palette.MINT
		LIVING_ROOM:
			return Palette.SOFT_PINK
		_:
			return Palette.MINT


## World-space floor rectangle of a room, in the XZ plane.
static func world_floor_bounds(room_id: String) -> Rect2:
	var origin: Vector3 = room_origin(room_id)
	return Rect2(
		FLOOR_BOUNDS.position + Vector2(origin.x, origin.z),
		FLOOR_BOUNDS.size
	)


## The per-room camera framing metadata of contract §6.
static func camera_framing(room_id: String) -> Dictionary:
	var origin: Vector3 = room_origin(room_id)
	return {
		"bounds": world_floor_bounds(room_id),
		"focus": Vector3(
			origin.x, FLOOR_Y + CAMERA_FOCUS_HEIGHT, origin.z + CAMERA_FOCUS_Z
		),
		"angle": CAMERA_ANGLE_DEGREES,
		"minDistance": CAMERA_MIN_DISTANCE,
		"maxDistance": CAMERA_MAX_DISTANCE,
		"floorY": FLOOR_Y,
		"extraPoints": camera_fit_points(room_id),
	}


## Everything in a room that the generic `headroom` does not already cover.
##
## `camera_framing.solve()` fits the floor corners and the same corners at head
## height, which is exactly right for "a child standing anywhere is visible" and
## says nothing at all about a 1.8 m wardrobe. While the shot stood 5.1 m back
## that gap never showed; the moment the look-at point moves forward it is the
## difference between a tighter room and a decapitated fridge.
##
## Returned in WORLD space, as the framing dictionary expects. Doors get their
## plaque's top corners for the same reason: a sign whose word is cropped is
## worse than no sign.
static func camera_fit_points(room_id: String) -> Array:
	var origin: Vector3 = room_origin(room_id)
	var points: Array = []

	var boxes: Array = []
	boxes.append_array(furniture(room_id))
	boxes.append_array(storages(room_id))
	for box: Dictionary in boxes:
		var size: Vector3 = box["size"]
		var centre: Vector3 = box["position"]
		var top: float = centre.y + size.y * 0.5
		if top < CAMERA_TALL_PROP_Y:
			continue
		for sx: float in [-0.5, 0.5]:
			for sz: float in [-0.5, 0.5]:
				points.append(origin + Vector3(
					centre.x + sx * size.x, top, centre.z + sz * size.z
				))

	for door: Dictionary in doors(room_id):
		var side: float = float(door["side"])
		var sign_top: float = DOOR_SIGN_CENTRE_Y + DOOR_SIGN_SIZE.y * 0.5
		for sx: float in [-0.5, 0.5]:
			points.append(origin + Vector3(
				side * DOOR_SIGN_X + sx * DOOR_SIGN_SIZE.x,
				sign_top,
				(door["position"] as Vector3).z
			))
	return points


static func navmesh_path(room_id: String) -> String:
	return "%s/%s_navmesh.tres" % [NAVMESH_DIR, room_id]
