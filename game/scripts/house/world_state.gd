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
## ## Where this is persisted
##
## Schema **v4**: `currentRoomId` / `currentSpawnId` are first-class TOP-LEVEL
## profile fields, written and validated by `ProfileStore`.
##
## They used to live under `settings.worldState`, because v3 dropped unknown
## top-level keys but preserved unknown JSON-safe keys inside `settings`. That
## mirror is still READ here -- a profile written before the v4 migration, or by
## the compatibility shim still running in `ProfileStore`, carries it -- but it is
## no longer where the truth lives, and it is not created by a fresh save.
##
## Reading the top level first matters more than it looks: `ProfileStore` never
## CREATES `settings.worldState`, it only keeps an existing one in agreement with
## the real fields. A house that read only the mirror would therefore see nothing
## at all in a fresh v4 profile and would wake every returning child in the
## bedroom, however far they had walked -- with the whole suite green, because the
## fallback it landed on is the same bedroom the test expects from a fresh
## profile.
##
## Chapter 2 baby save behaviour (`stars`, `completedActivities`, `starsByLevel`,
## `levelCompleted`, the sticker thresholds) is not touched by any of this.

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

## Reads world state out of a loaded profile Dictionary.
##
## v4 top level first, the v3 `settings.worldState` mirror second, the bedroom
## last. A profile with no world state at all -- every profile written before the
## house existed -- starts in the bedroom, which is where a child who has never
## been in the house belongs.
static func read_from_profile(profile: Variant) -> RefCounted:
	if typeof(profile) != TYPE_DICTIONARY:
		return create()
	var map: Dictionary = profile
	if map.has(ROOM_FIELD) or map.has(SPAWN_FIELD):
		return from_dict(map)
	var settings: Variant = map.get(SETTINGS_KEY, null)
	if typeof(settings) != TYPE_DICTIONARY:
		return create()
	return from_dict((settings as Dictionary).get(WORLD_STATE_KEY, null))


## Returns a COPY of `profile` carrying this world state. Copy rather than
## mutation so a caller can never half-write a profile it did not mean to touch.
##
## Writes the v4 top-level fields, and updates the legacy `settings.worldState`
## mirror only when the profile already carries one -- the same rule
## `ProfileStore` follows, so the two can never disagree and a stale mirror can
## never outlive the real location.
func write_into_profile(profile: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(profile) == TYPE_DICTIONARY:
		result = (profile as Dictionary).duplicate(true)
	result[ROOM_FIELD] = _room_id
	result[SPAWN_FIELD] = _spawn_id
	var settings: Variant = result.get(SETTINGS_KEY, null)
	if typeof(settings) == TYPE_DICTIONARY \
			and (settings as Dictionary).has(WORLD_STATE_KEY):
		var settings_map: Dictionary = settings
		settings_map[WORLD_STATE_KEY] = to_dict()
		result[SETTINGS_KEY] = settings_map
	return result
