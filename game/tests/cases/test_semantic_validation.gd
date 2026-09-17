extends RefCounted

## Content addresses the world by semantic id, and every one of those ids must
## be real. Contract §2.
##
## A reference to a target that does not exist is the quietest failure in the
## project: the level loads, the prompt plays, the child taps the thing they were
## asked to tap, and nothing at all happens. No error, no crash, no log line.
## `ContentValidator` therefore checks every reference against the ids the real
## `HouseWorld` reports, and this case is what proves the check can actually go
## red.
##
## ## The direction of the dependency
##
## `content_validator.gd` is domain code. `test_architecture_guard.gd` scans it
## for 3D types and for imports of `scripts/house/`, `scripts/navigation/`,
## `scripts/character/` and `scripts/camera/`, and fails the build on either. So
## the validator never loads the house: it takes the id list as plain **Strings**,
## injected by whoever has one. That is asserted below, because the obvious
## implementation -- `preload("res://scripts/house/house_world.gd")` -- is one
## line away and would take the whole architecture guard down with it.
##
## ## Vacuity
##
## Three separate ways this check could pass while checking nothing, all pinned:
## an empty id list, a content set with no references, and a `semanticTargetKeys`
## declaration that no longer matches the authored keys.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const ValidatorScript := preload("res://scripts/content/content_validator.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")

const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"
const VALIDATOR_PATH: String = "res://scripts/content/content_validator.gd"

## The house is a fixed four-room greybox. Fewer than this and either the layout
## shrank or the scan is reading the wrong thing.
const MIN_WORLD_TARGET_IDS: int = 20

## The content set authored against the house today. A floor, not an exact count,
## so adding a level does not fail this -- but removing every reference does.
const MIN_CONTENT_REFERENCES: int = 20


func test_name() -> String:
	return "semantic_validation"


func run():
	var failures: Array = []
	failures.append_array(_test_the_world_reports_real_ids())
	failures.append_array(_test_content_matches_the_world())
	failures.append_array(_test_a_bad_id_is_caught())
	failures.append_array(_test_it_cannot_pass_vacuously())
	failures.append_array(_test_the_validator_never_imports_the_house())
	return failures


## -- The id list -----------------------------------------------------------------

func _test_the_world_reports_real_ids():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not instantiate %s" % HOUSE_SCENE]

	var ids: Array = world.call("get_semantic_target_ids")
	if ids.size() < MIN_WORLD_TARGET_IDS:
		failures.append("the house reports %d semantic target ids, expected at least %d"
				% [ids.size(), MIN_WORLD_TARGET_IDS])

	var seen: Dictionary = {}
	for entry: Variant in ids:
		var semantic_id: String = String(entry)
		if seen.has(semantic_id):
			failures.append("duplicate semantic id '%s'; one target silently shadows another"
					% semantic_id)
		seen[semantic_id] = true
		var parts: PackedStringArray = semantic_id.split(".", false)
		if parts.size() != 2:
			failures.append("'%s' is not a '<roomId>.<targetId>' pair" % semantic_id)
			continue
		if not HouseLayout.has_room(parts[0]):
			failures.append("'%s' names a room the layout does not have" % semantic_id)

	# The ones the contract writes out by name must all be there.
	for required: String in [
		"bedroom.bed", "bedroom.wardrobe", "bedroom.toy",
		"bathroom.sink", "bathroom.bath", "bathroom.towel",
		"kitchen.fridge", "kitchen.table", "kitchen.counter",
		"livingRoom.sofa", "livingRoom.toyBox", "livingRoom.book",
	]:
		if not seen.has(required):
			failures.append("contract §2 names '%s'; the house does not have it" % required)

	_release(world)
	return failures


## -- The check that matters ------------------------------------------------------

func _test_content_matches_the_world():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not instantiate %s" % HOUSE_SCENE]
	var library: RefCounted = ContentLibraryScript.create()
	var ids: Array = world.call("get_semantic_target_ids")

	var references: Array = ValidatorScript.collect_semantic_target_references(library)
	if references.size() < MIN_CONTENT_REFERENCES:
		failures.append(
			("the scan found %d semantic target reference(s) in the content set, expected at "
			+ "least %d. Either content stopped addressing the world by semantic id, or "
			+ "index.json's 'semanticTargetKeys' no longer names the keys it is authored under "
			+ "-- and a validator with nothing to check reports no problems forever.")
			% [references.size(), MIN_CONTENT_REFERENCES]
		)

	for problem: Variant in ValidatorScript.validate_semantic_targets(library, ids):
		failures.append("content references a target the house does not have: %s" % String(problem))

	# And the full run, the way a build step would call it, must also be clean.
	for problem: Variant in ValidatorScript.validate_all(library, ids):
		failures.append("validate_all: %s" % String(problem))

	# The house's own convenience wrapper resolves its ids for the caller.
	for problem: Variant in world.call("validate_content", library):
		failures.append("HouseWorld.validate_content: %s" % String(problem))

	_release(world)
	return failures


## The mutation this file exists to catch: a content reference to a target that
## is not in the house must be reported, and must name the offender.
func _test_a_bad_id_is_caught():
	var failures: Array = []
	var library: RefCounted = ContentLibraryScript.create()
	var real: Array = ValidatorScript.collect_semantic_target_references(library)
	if real.is_empty():
		return ["no references to check against; the rest of this case would be vacuous"]

	# Every real id EXCEPT one, so the content set that passed a moment ago now
	# has at least one reference that misses.
	var without_one: Array = []
	var dropped: String = String((real[0] as Dictionary)["id"])
	for entry: Variant in real:
		var semantic_id: String = String((entry as Dictionary)["id"])
		if semantic_id != dropped and not without_one.has(semantic_id):
			without_one.append(semantic_id)
	if without_one.is_empty():
		return ["the content set references only one target; this check cannot run"]

	var problems: Array = ValidatorScript.validate_semantic_targets(library, without_one)
	if problems.is_empty():
		failures.append(
			("removing '%s' from the world left the validator with nothing to say. A content "
			+ "reference to a target that does not exist is completely silent at runtime, so "
			+ "this check is the only thing that catches it.") % dropped
		)
	var named: bool = false
	for problem: Variant in problems:
		if String(problem).contains(dropped):
			named = true
	if not named:
		failures.append("the failure never names '%s'; a problem nobody can locate is not a "
				% dropped + "problem that gets fixed")

	# An id that was never anywhere near the house is caught too.
	var invented: Array = without_one.duplicate()
	invented.append("attic.telescope")
	if ValidatorScript.validate_semantic_targets(library, invented).is_empty():
		failures.append("adding an unrelated id papered over the missing one")

	return failures


## -- Vacuity ---------------------------------------------------------------------

func _test_it_cannot_pass_vacuously():
	var failures: Array = []
	var library: RefCounted = ContentLibraryScript.create()

	# An empty id list is a problem, not a pass. Without this, a caller that
	# failed to resolve the house would get a clean bill of health.
	if ValidatorScript.validate_semantic_targets(library, []).is_empty():
		failures.append("an empty world id list reported no problems; a validator handed nothing "
				+ "to check against must say so")

	# Nonsense instead of a list is reported rather than ignored.
	if ValidatorScript.validate_semantic_targets(library, "bedroom.bed").is_empty():
		failures.append("a non-array id list reported no problems")

	# `null` is the documented "I have no world" and stays silent, so the
	# content-only callers (test_chapter3_slice, test_level_progression) are
	# unaffected.
	if not ValidatorScript.validate_semantic_targets(library, null).is_empty():
		failures.append("null should skip the section, not report problems")
	if not ValidatorScript.validate_all(library).is_empty():
		failures.append("validate_all() with no world must stay clean for content-only callers")

	# Keys the index does not declare are invisible to the scan, which is why the
	# declaration itself is checked rather than assumed.
	var keys: Array = ValidatorScript.semantic_target_keys()
	for required: String in ["targetId", "requiresWalkTo"]:
		if not keys.has(required):
			failures.append("index.json no longer declares '%s' in 'semanticTargetKeys'; every "
					% required + "reference under that key would stop being checked")

	# A declaration that matches nothing must be reported, not silently pass.
	var world: Node = _build_house()
	if world != null:
		var ids: Array = world.call("get_semantic_target_ids")
		if ValidatorScript.validate_semantic_targets(
			library, ids, "res://content/does_not_exist.json"
		).is_empty():
			failures.append("an unreadable content index reported no problems; the scan would "
					+ "have had no keys to look for")
		_release(world)

	return failures


## -- The architecture rule -------------------------------------------------------

## Restated here, next to the feature that is most likely to break it. The
## architecture guard owns the general rule; this owns the specific temptation.
func _test_the_validator_never_imports_the_house():
	var failures: Array = []
	var source: String = _read(VALIDATOR_PATH)
	if source.length() < 200:
		return ["could not read %s" % VALIDATOR_PATH]

	# Comments stripped first. The file documents the rule it obeys, and a scan
	# that read prose would fail it for saying the right thing -- which is how a
	# guard gets weakened instead of fixed (test_architecture_guard.gd,
	# "Why the source is stripped of comments first").
	var code: String = ""
	for raw_line: String in source.split("\n"):
		var line: String = raw_line
		var comment: int = line.find("#")
		if comment >= 0:
			line = line.substr(0, comment)
		code += line + "\n"

	if code.strip_edges().length() < 200:
		failures.append("%s stripped to almost nothing; the scan would pass vacuously"
				% VALIDATOR_PATH)
		return failures

	for forbidden: String in [
		"scripts/house/", "scripts/navigation/", "scripts/character/", "scripts/camera/",
	]:
		if code.contains(forbidden):
			failures.append(
				("content_validator.gd reaches into %s in executable code. The id list must be "
				+ "INJECTED as plain strings: the domain layer addresses the world by semantic "
				+ "id and must not know how the world is built. test_architecture_guard.gd fails "
				+ "the build on this.") % forbidden
			)
	return failures


## -- Helpers ---------------------------------------------------------------------

func _build_house() -> Node:
	if not ResourceLoader.exists(HOUSE_SCENE):
		return null
	var packed: Resource = load(HOUSE_SCENE)
	if not (packed is PackedScene):
		return null
	var world: Node = (packed as PackedScene).instantiate()
	if world == null:
		return null
	# In the tree, because a room's targets resolve their world positions through
	# it -- and `_ready()` does not fire for a node added to the root here, so
	# `build_world()` is called by hand.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(world)
	world.call("build_world")
	return world


func _release(world: Node) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and world.get_parent() == tree.root:
		tree.root.remove_child(world)
	world.free()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
