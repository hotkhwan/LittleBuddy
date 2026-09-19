extends RefCounted

## FREE STARTER: what a family gets for nothing, written down once, as DATA.
##
## The authoritative copy is `res://content/packs/free_starter.json`, which is a
## content pack manifest like any other (same nine fields, see
## `scripts/content_packs/content_pack.gd`). That is the point: the free set is
## not a special case in the code, it is a pack whose `entitlementId` happens to
## be the one id that is always active.
##
## ## What is in it, and why it is this much
##
## A free tier that is a demo is a lie to a parent, so this one is a real game:
##
## | missions   | `imHungry`, `snackTime` -- both shipped, chained, star-rated   |
## | rooms      | the whole house: bedroom, bathroom, kitchen, livingRoom       |
## | characters | the baby and the toddler                                      |
## | outfits    | none -- see below                                             |
## | audio      | every bundled sound effect                                    |
##
## `outfits` is deliberately an empty list rather than an invented id: no outfit
## system ships yet, so the free tier claims none. The field exists because the
## pack schema is fixed and a later dress-up pack will fill it. Claiming an
## outfit that does not exist would be the first lie in the file.
##
## ## Why there is a hard-coded fallback
##
## `definition()` reads the JSON and, if the file is missing, unreadable or
## corrupt, returns `FALLBACK` -- which is the same content, compiled into the
## build. The free set is the one thing that must never depend on a file being
## intact: a child who has been playing `imHungry` all week must still be able to
## play it after a bad write, a half-finished copy or a botched export. Everything
## else in this layer fails closed; this fails OPEN, on purpose.
##
## PURE DATA. No node, no 3D type, no network, no purchase. Reads one local file.

const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")

const PACK_PATH: String = "res://content/packs/free_starter.json"

## The compiled-in copy of the pack. Kept byte-for-byte in step with
## `free_starter.json` by `test_entitlement_free_starter.gd`, which compares the
## two field by field -- so this cannot quietly drift into being a different
## promise from the one the content file makes.
const FALLBACK: Dictionary = {
	"packId": "freeStarter",
	"version": 1,
	"requiredGameVersion": "0.1.0",
	"missions": ["imHungry", "snackTime"],
	"rooms": ["bedroom", "bathroom", "kitchen", "livingRoom"],
	"characters": ["littleBuddy", "buddy"],
	"outfits": [],
	"audio": [
		"success_chime", "soft_pop", "pickup", "place_soft", "drop_return",
		"room_change", "sticker_unlock", "star_earned", "bedtime_chime", "gentle_tap",
	],
	"entitlementId": "freeStarter",
}

## The two missions the free tier must always contain. Asserted separately from
## the data so that "the free tier is still a real game" is a test, not a habit:
## quietly shortening the missions list to one would otherwise pass every check.
const REQUIRED_MISSIONS: Array[String] = ["imHungry", "snackTime"]

## The house, all four rooms. A free tier that hands over one room is a demo.
const REQUIRED_ROOMS: Array[String] = ["bedroom", "bathroom", "kitchen", "livingRoom"]


## The Free Starter pack manifest, as a fresh Dictionary.
##
## Falls back to the compiled-in copy for a missing/corrupt file, and merges
## field by field so that a file which is only *partly* wrong still contributes
## the parts that are right.
static func definition() -> Dictionary:
	var out: Dictionary = FALLBACK.duplicate(true)
	var raw: Variant = _read_pack_file()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var parsed: Dictionary = raw
	for field: Variant in out.keys():
		var key: String = String(field)
		if not parsed.has(key):
			continue
		var value: Variant = parsed[key]
		if typeof(value) != typeof(out[key]):
			continue
		if typeof(value) == TYPE_ARRAY:
			out[key] = _strings_only(value)
		else:
			out[key] = value
	# Whatever the file says, the free set is the free set: its entitlement id is
	# the one that is always active, and the two missions are not negotiable.
	out["entitlementId"] = EntitlementIds.FREE_STARTER
	for mission_id: String in REQUIRED_MISSIONS:
		if not (out["missions"] as Array).has(mission_id):
			(out["missions"] as Array).append(mission_id)
	for room_id: String in REQUIRED_ROOMS:
		if not (out["rooms"] as Array).has(room_id):
			(out["rooms"] as Array).append(room_id)
	return out


static func entitlement_id() -> String:
	return EntitlementIds.FREE_STARTER


static func missions() -> PackedStringArray:
	return _list("missions")


static func rooms() -> PackedStringArray:
	return _list("rooms")


static func characters() -> PackedStringArray:
	return _list("characters")


static func outfits() -> PackedStringArray:
	return _list("outfits")


static func audio() -> PackedStringArray:
	return _list("audio")


## Is this mission part of what every family already owns?
static func includes_mission(mission_id: Variant) -> bool:
	if typeof(mission_id) != TYPE_STRING:
		return false
	return missions().has(String(mission_id))


## Is this room part of what every family already owns?
static func includes_room(room_id: Variant) -> bool:
	if typeof(room_id) != TYPE_STRING:
		return false
	return rooms().has(String(room_id))


## One line a grown-up can read in Parent Corner. Built from the data above, so
## it cannot describe a free tier different from the one the game grants.
static func summary_line() -> String:
	return "Free Starter: %d missions, %d rooms, %d characters -- yours, free, forever." % [
		missions().size(), rooms().size(), characters().size(),
	]


# -- internals ----------------------------------------------------------------

static func _list(field: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var value: Variant = definition().get(field, [])
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry: Variant in (value as Array):
		if typeof(entry) == TYPE_STRING and not String(entry).is_empty():
			out.append(String(entry))
	return out


static func _strings_only(value: Variant) -> Array:
	var out: Array = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry: Variant in (value as Array):
		if typeof(entry) == TYPE_STRING and not String(entry).is_empty():
			out.append(String(entry))
	return out


## Reads the local pack file. `FileAccess` + `JSON` only -- never `load()`, so a
## pack file can only ever be data and never something this build would execute.
static func _read_pack_file() -> Variant:
	if not FileAccess.file_exists(PACK_PATH):
		return null
	var file: FileAccess = FileAccess.open(PACK_PATH, FileAccess.READ)
	if file == null:
		return null
	var text: String = file.get_as_text()
	file.close()
	return JSON.parse_string(text)
