extends RefCounted

## Where in the house the child is, as SEMANTIC state and nothing else.
##
##     {"currentRoomId": "bathroom", "currentSpawnId": "fromBedroom"}
##
## Never a raw `Vector3`. A coordinate that was valid when it was written drifts
## out of the navigation mesh the moment somebody moves a sofa, and a saved
## coordinate is then a way of stranding a child with no route back. A room id
## plus a spawn id can always be re-resolved against the CURRENT layout, and if
## either has gone away the fallback chain is deterministic:
##
##     unknown spawn  -> that room's "default" spawn
##     unknown room   -> the bedroom's "default" spawn
##
## Pure domain logic: no node, no `Node3D`, no scene tree. Engine-agnostic in the
## same sense as `profile_store.gd` and `star_rules.gd`.
##
## ## Where this is persisted, and why the save schema was NOT bumped
##
## `ProfileStore` is at schema v3 and was migrated twice this week; the contract
## says do not bump it unless genuinely necessary. It rebuilds the profile from
## `default_profile()` on every load, so an unknown TOP-LEVEL key is silently
## dropped -- but it deliberately preserves unknown JSON-safe keys inside
## `settings`. So world state round-trips through the existing v3 profile,
## unchanged, under `settings.worldState`, and the Chapter 2 baby save behaviour
## (`stars`, `completedActivities`, `starsByLevel`, `levelCompleted`, the sticker
## thresholds) is not touched at all.
##
## If the owner would rather this were a first-class top-level field, that IS a
## schema change and belongs to whoever owns `scripts/save/**`; only the two
## constants below and `read_from_profile()`/`write_into_profile()` would change.

const HouseLayout := preload("res://scripts/house/house_layout.gd")

const SETTINGS_KEY: String = "settings"
const WORLD_STATE_KEY: String = "worldState"
const ROOM_FIELD: String = "currentRoomId"
const SPAWN_FIELD: String = "currentSpawnId"

var _room_id: String = HouseLayout.FALLBACK_ROOM
var _spawn_id: String = HouseLayout.DEFAULT_SPAWN


static func create(
	room_id: String = HouseLayout.FALLBACK_ROOM, spawn_id: String = HouseLayout.DEFAULT_SPAWN
) -> RefCounted:
	var state: RefCounted = (load("res://scripts/house/world_state.gd") as GDScript).new()
	state.call("set_location", room_id, spawn_id)
	return state


## The only validation rule in the file, and the one the fallback tests pin down.
##
## Returns `{"roomId", "spawnId", "roomFallback": bool, "spawnFallback": bool}`.
## Never returns an id that does not exist in the current layout.
static func resolve(room_id: String, spawn_id: String) -> Dictionary:
	var resolved_room: String = room_id.strip_edges()
	var room_fallback: bool = false
	if not HouseLayout.has_room(resolved_room):
		resolved_room = HouseLayout.FALLBACK_ROOM
		room_fallback = true

	var resolved_spawn: String = spawn_id.strip_edges()
	var spawn_fallback: bool = false
	if room_fallback or not HouseLayout.spawn_points(resolved_room).has(resolved_spawn):
		resolved_spawn = HouseLayout.DEFAULT_SPAWN
		spawn_fallback = true

	return {
		"roomId": resolved_room,
		"spawnId": resolved_spawn,
		"roomFallback": room_fallback,
		"spawnFallback": spawn_fallback,
	}


## Stores a location, falling back as above. Returns true when the requested
## location was used exactly as asked for.
func set_location(room_id: String, spawn_id: String) -> bool:
	var resolved: Dictionary = resolve(room_id, spawn_id)
	_room_id = String(resolved["roomId"])
	_spawn_id = String(resolved["spawnId"])
	return not (bool(resolved["roomFallback"]) or bool(resolved["spawnFallback"]))


func get_room_id() -> String:
	return _room_id


func get_spawn_id() -> String:
	return _spawn_id


func to_dict() -> Dictionary:
	return {ROOM_FIELD: _room_id, SPAWN_FIELD: _spawn_id}


static func from_dict(raw: Variant) -> RefCounted:
	if typeof(raw) != TYPE_DICTIONARY:
		return create()
	var map: Dictionary = raw
	return create(str(map.get(ROOM_FIELD, "")), str(map.get(SPAWN_FIELD, "")))


## -- Profile round trip --------------------------------------------------------

## Reads world state out of a loaded profile Dictionary. A profile with no world
## state at all -- every profile written before today -- starts in the bedroom.
static func read_from_profile(profile: Variant) -> RefCounted:
	if typeof(profile) != TYPE_DICTIONARY:
		return create()
	var settings: Variant = (profile as Dictionary).get(SETTINGS_KEY, null)
	if typeof(settings) != TYPE_DICTIONARY:
		return create()
	return from_dict((settings as Dictionary).get(WORLD_STATE_KEY, null))


## Returns a COPY of `profile` carrying this world state. Copy rather than
## mutation so a caller can never half-write a profile it did not mean to touch.
func write_into_profile(profile: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(profile) == TYPE_DICTIONARY:
		result = (profile as Dictionary).duplicate(true)
	var settings: Variant = result.get(SETTINGS_KEY, null)
	var settings_map: Dictionary = settings if typeof(settings) == TYPE_DICTIONARY else {}
	settings_map[WORLD_STATE_KEY] = to_dict()
	result[SETTINGS_KEY] = settings_map
	return result
