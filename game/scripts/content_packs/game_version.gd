extends RefCounted

## The build's own version, and MAJOR.MINOR.PATCH comparison.
##
## A content pack declares `requiredGameVersion`: the oldest build that can run
## it. A pack from next month's release, dropped into this month's build, must be
## REJECTED rather than half-loaded -- a pack that names a mission template this
## build does not have would otherwise fail somewhere deep in gameplay, in front
## of a child, instead of here in a validator.
##
## ## Why the version is a constant and not read from `VERSION`
##
## The repository's version of record is the `VERSION` file at the repository
## root, which is one level ABOVE `res://` and therefore not readable from a
## shipped build at all. So the number is compiled in here, and
## `test_content_pack_validator.gd` asserts it equals the root `VERSION` --
## exactly the technique `test_version.gd` already uses to keep
## `export_presets.cfg` and `CHANGELOG.md` honest. Bumping the release means
## bumping this too, and the suite says so out loud rather than letting a pack
## gate itself against a version that no longer exists.
##
## Pre-release suffixes ("0.2.0-beta1") are deliberately NOT supported. Accepting
## them would mean inventing an ordering for them, and a content pack gate is the
## wrong place to be clever.

## This build. Must equal the `VERSION` file at the repository root.
const BUILD: String = "0.1.0"

const PATTERN: String = "^([0-9]+)\\.([0-9]+)\\.([0-9]+)$"


## `[major, minor, patch]`, or an empty array when `version` is not a plain
## MAJOR.MINOR.PATCH string. An empty array means "unparseable", and every caller
## treats that as a rejection rather than as a zero.
static func parse(version: Variant) -> Array:
	if typeof(version) != TYPE_STRING:
		return []
	var regex := RegEx.new()
	regex.compile(PATTERN)
	var found: RegExMatch = regex.search(String(version).strip_edges())
	if found == null:
		return []
	return [
		int(found.get_string(1)),
		int(found.get_string(2)),
		int(found.get_string(3)),
	]


static func is_valid(version: Variant) -> bool:
	return not parse(version).is_empty()


## -1 when `left` is older, 0 when equal, 1 when `left` is newer.
## Returns 0 for a pair this function cannot order, which no caller relies on:
## they check `is_valid()` first and reject what does not parse.
static func compare(left: Variant, right: Variant) -> int:
	var a: Array = parse(left)
	var b: Array = parse(right)
	if a.is_empty() or b.is_empty():
		return 0
	for index: int in range(3):
		if int(a[index]) < int(b[index]):
			return -1
		if int(a[index]) > int(b[index]):
			return 1
	return 0


## True when `version` is strictly newer than the build it is given (the current
## build by default). This is the single question the pack gate asks.
static func is_newer_than(version: Variant, build_version: String = BUILD) -> bool:
	return compare(version, build_version) > 0
