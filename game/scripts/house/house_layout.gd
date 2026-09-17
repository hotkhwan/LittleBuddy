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
## What the camera looks at: the middle of the room, a little above the floor so
## the toddler's head rather than its feet sits in the centre of the frame.
const CAMERA_FOCUS_HEIGHT: float = 0.55

const FLOOR_COLOR: Color = Color(0.82, 0.76, 0.68)
const WALL_COLOR: Color = Color(0.88, 0.86, 0.82)
const DOOR_COLOR: Color = Color(0.72, 0.52, 0.34)


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
static func furniture(room_id: String) -> Array:
	match room_id:
		BEDROOM:
			return [
				_prop("bed", "bed", Vector3(1.5, 0.45, 0.95), Vector3(-1.0, 0.225, -1.4),
						Vector3(-1.0, FLOOR_Y, -0.55), ["sleep", "sit"], Color(0.62, 0.72, 0.9)),
				_prop("wardrobe", "wardrobe", Vector3(0.9, 1.8, 0.6), Vector3(1.35, 0.9, -1.6),
						Vector3(1.35, FLOOR_Y, -0.95), ["open", "dress"], Color(0.78, 0.6, 0.42)),
				_prop("toy", "toy", Vector3(0.35, 0.35, 0.35), Vector3(0.9, 0.175, 0.9),
						Vector3(0.9, FLOOR_Y, 1.45), ["pickUp", "play"], Color(0.96, 0.72, 0.4)),
			]
		BATHROOM:
			return [
				_prop("sink", "sink", Vector3(0.6, 0.7, 0.45), Vector3(-1.2, 0.35, -1.72),
						Vector3(-1.2, FLOOR_Y, -1.15), ["wash", "brushTeeth"], Color(0.86, 0.92, 0.96)),
				_prop("bath", "bath", Vector3(1.4, 0.5, 0.75), Vector3(0.95, 0.25, -1.5),
						Vector3(0.95, FLOOR_Y, -0.85), ["wash", "play"], Color(0.7, 0.88, 0.94)),
				_prop("towel", "towel", Vector3(0.3, 0.5, 0.1), Vector3(-1.9, 1.0, -0.5),
						Vector3(-1.35, FLOOR_Y, -0.5), ["pickUp", "dry"], Color(0.96, 0.78, 0.82)),
			]
		KITCHEN:
			return [
				_prop("fridge", "fridge", Vector3(0.7, 1.7, 0.65), Vector3(1.4, 0.85, -1.6),
						Vector3(1.4, FLOOR_Y, -0.95), ["open", "give"], Color(0.9, 0.92, 0.94)),
				_prop("counter", "counter", Vector3(1.8, 0.9, 0.6), Vector3(-0.8, 0.45, -1.65),
						Vector3(-0.8, FLOOR_Y, -1.0), ["wash", "give"], Color(0.84, 0.74, 0.6)),
				_prop("table", "table", Vector3(1.0, 0.7, 0.8), Vector3(0.5, 0.35, 0.55),
						Vector3(0.5, FLOOR_Y, 1.4), ["eat", "sit"], Color(0.8, 0.62, 0.44)),
			]
		LIVING_ROOM:
			return [
				_prop("sofa", "sofa", Vector3(1.8, 0.75, 0.8), Vector3(-0.7, 0.375, -1.5),
						Vector3(-0.7, FLOOR_Y, -0.85), ["sit", "hug"], Color(0.7, 0.66, 0.86)),
				_prop("toyBox", "toy box", Vector3(0.7, 0.5, 0.5), Vector3(1.45, 0.25, -1.65),
						Vector3(1.45, FLOOR_Y, -1.05), ["open", "play"], Color(0.95, 0.75, 0.82)),
				_prop("book", "book", Vector3(0.3, 0.12, 0.22), Vector3(0.3, 0.06, 0.8),
						Vector3(0.3, FLOOR_Y, 1.35), ["read", "pickUp"], Color(0.94, 0.55, 0.45)),
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


## Temporary greybox floor tint, one per room, so a reviewer can tell at a glance
## which room a screenshot is of. Replaced wholesale by the art pipeline.
static func floor_color(room_id: String) -> Color:
	match room_id:
		BEDROOM:
			return Color(0.84, 0.78, 0.7)
		BATHROOM:
			return Color(0.74, 0.84, 0.86)
		KITCHEN:
			return Color(0.86, 0.82, 0.68)
		LIVING_ROOM:
			return Color(0.8, 0.76, 0.84)
		_:
			return FLOOR_COLOR


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
		"focus": Vector3(origin.x, FLOOR_Y + CAMERA_FOCUS_HEIGHT, origin.z),
		"angle": CAMERA_ANGLE_DEGREES,
		"minDistance": CAMERA_MIN_DISTANCE,
		"maxDistance": CAMERA_MAX_DISTANCE,
		"floorY": FLOOR_Y,
	}


static func navmesh_path(room_id: String) -> String:
	return "%s/%s_navmesh.tres" % [NAVMESH_DIR, room_id]
