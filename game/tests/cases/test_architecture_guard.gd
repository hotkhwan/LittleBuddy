extends RefCounted

## The structural rules, enforced against the source itself.
##
## Two invariants live here, and both are the kind that no behavioural test can
## protect because nothing observable breaks on the day they are violated -- only
## six months later, when the next port or the next refactor runs into them.
##
## **1. The domain layer holds no 3D types.** `mission_runner.gd`,
## `content_library.gd`, `content_validator.gd` and `task_picker.gd` have zero
## references to `CharacterBody3D`, `NavigationAgent3D`, `NavigationRegion3D`,
## `Node3D`, `Area3D`, `Vector3` or `Transform3D`. That property is why the
## content pipeline, the mission sequencing and the reward integrity all survived
## the 2D-to-3D move untouched, and navigation is the single most likely thing to
## break it -- the obvious implementation hands a `NavigationAgent3D` straight to
## the caller. Contract §1 calls it binding.
##
## **2. Chapter 2 has no locomotion.** The product owner has locked the life-stage
## model: the baby does not walk. Tap, drag, give, feed -- never a navigation
## agent. So the Baby Room and the baby/activity scripts must reference no
## `CharacterBody3D`, `NavigationAgent3D` or `NavigationRegion3D`. Pinning it here
## turns a product decision into something that cannot be undone by accident.
##
## ## Why the source is stripped of comments first
##
## A doc comment that mentions `Vector3` -- and the files above are heavily
## documented -- would otherwise fail this test for saying the right thing. The
## predictable response to that is to weaken the test until it shuts up, at which
## point it protects nothing. So the scanner reads EXECUTABLE code only, and
## `_test_the_scanner_itself()` proves both halves of that: a token in a comment
## is invisible, a token in code is not.
##
## `test_star_rules.gd` set this precedent for the speech rule; this is the same
## technique applied to the architecture.

const SemanticId := preload("res://scripts/navigation/semantic_id.gd")
const ActivityTarget := preload("res://scripts/navigation/activity_target.gd")

## Contract §1. Verified at 0 references each when this test was written.
const DOMAIN_FILES: Array[String] = [
	"res://scripts/gameplay/mission_runner.gd",
	"res://scripts/content/content_library.gd",
	"res://scripts/content/content_validator.gd",
	"res://scripts/content/task_picker.gd",
]

## The seven the contract names, plus the wider set absorbed from
## `test_character_api.gd`, whose own copy of this scan read RAW source and so
## went red the moment a doc comment mentioned one of these tokens -- punishing
## accurate documentation, which is how a guard gets weakened rather than fixed.
## Verified before consolidating: adding the comment
## `## Note: this module deliberately holds no Vector3 and no Node3D.` to
## task_picker.gd turned that test red while this one correctly stayed green.
## One guard, one comment-stripped scanner, the stricter token list.
const FORBIDDEN_IN_DOMAIN: Array[String] = [
	"CharacterBody3D", "NavigationAgent3D", "NavigationRegion3D",
	"Node3D", "Area3D", "Vector3", "Transform3D",
	"Camera3D", "CollisionShape3D", "Marker3D", "MeshInstance3D",
	"NavigationMesh", "NavigationServer3D", "AnimationPlayer", "AnimationTree",
	"PhysicsDirectSpaceState3D",
]

## The domain layer must not reach into the movement layer's implementation
## either -- a String-only API is worth nothing if content imports the navigator.
const FORBIDDEN_DOMAIN_IMPORTS: Array[String] = [
	"scripts/navigation/", "scripts/character/", "scripts/house/", "scripts/camera/",
]

## Chapter 2. Scenes and scripts that must never acquire locomotion.
const CHAPTER_2_DIRS: Array[String] = [
	"res://scenes/baby_room",
	"res://scripts/baby",
	"res://scripts/activities",
]
const CHAPTER_2_EXTENSIONS: Array[String] = ["gd", "tscn"]

const FORBIDDEN_IN_CHAPTER_2: Array[String] = [
	"CharacterBody3D", "NavigationAgent3D", "NavigationRegion3D",
]

## Anti-vacuity floors. A guard that silently scans nothing is worse than no
## guard at all: it reports PASS forever. These are the smallest counts the
## project can legitimately have, so deleting or renaming a guarded file fails
## the test instead of quietly emptying it.
const MIN_DOMAIN_FILES: int = 4
const MIN_CHAPTER_2_FILES: int = 6
const MIN_SCANNED_CHARACTERS: int = 2000


func test_name() -> String:
	return "architecture_guard"


func run():
	var failures: Array = []
	failures.append_array(_test_the_scanner_itself())
	failures.append_array(_test_domain_layer_has_no_3d())
	failures.append_array(_test_chapter_2_has_no_locomotion())
	failures.append_array(_test_layer_discipline())
	failures.append_array(_test_semantic_ids_need_no_engine())
	return failures


## -- The scanner, tested before it is trusted ----------------------------------

## Proof that this file's central mechanism works in BOTH directions. Without
## these four assertions every check below could be passing for the wrong reason.
func _test_the_scanner_itself():
	var failures: Array = []

	var commented: String = "# this mentions Vector3 in a comment\nvar x: int = 1\n"
	if _code_of(commented).contains("Vector3"):
		failures.append("the scanner must ignore a token inside a '#' comment, or a doc comment "
				+ "would fail this test for describing the rule correctly")

	var documented: String = "## Returns a Vector3.\nfunc f() -> int:\n\treturn 1\n"
	if _code_of(documented).contains("Vector3"):
		failures.append("the scanner must ignore a token inside a '##' doc comment")

	var real: String = "var p: Vector3 = Vector3.ZERO\n"
	if not _code_of(real).contains("Vector3"):
		failures.append("the scanner must SEE a token in executable code; it is vacuous otherwise")

	# A '#' inside a string literal is not a comment. Truncating there would hide
	# everything after it on that line -- a silent blind spot.
	var stringy: String = 'var colour: String = "#ff00ff"  # pink\nvar p := Vector3.ZERO\n'
	var stripped: String = _code_of(stringy)
	if not stripped.contains("Vector3"):
		failures.append("a '#' inside a string literal must not blind the scanner to the rest "
				+ "of the file")
	if stripped.contains("pink"):
		failures.append("the trailing comment after a string literal should still be stripped")

	# And it must actually read files, not just strings.
	var own_source: String = _read("res://tests/cases/test_architecture_guard.gd")
	if own_source.length() < 100:
		failures.append("the scanner cannot read a file it is looking straight at")

	return failures


## -- Rule 1: the domain layer holds no 3D types --------------------------------

func _test_domain_layer_has_no_3d():
	var failures: Array = []
	var scanned: int = 0
	var characters: int = 0

	for path: String in DOMAIN_FILES:
		if not FileAccess.file_exists(path):
			failures.append("%s is missing; the architecture guard cannot check what is not there "
					% path + "(was it moved? update DOMAIN_FILES)")
			continue
		var code: String = _code_of(_read(path))
		if code.strip_edges().length() < 200:
			failures.append("%s stripped to almost nothing; the guard would pass vacuously" % path)
			continue
		scanned += 1
		characters += code.length()
		for token: String in FORBIDDEN_IN_DOMAIN:
			if code.contains(token):
				failures.append(
					("%s references %s in executable code. The domain layer must stay free of 3D "
					+ "types (contract §1): it is what let the content, mission and reward code "
					+ "survive the 2D-to-3D move untouched. Pass semantic ids -- Strings -- "
					+ "instead.") % [path, token]
				)
		var imports: String = _imports_of(_read(path))
		for leaked: String in FORBIDDEN_DOMAIN_IMPORTS:
			if imports.contains(leaked):
				failures.append(
					("%s reaches into %s. The domain layer addresses the world by semantic id "
					+ "and must not know how movement or presentation are implemented.")
					% [path, leaked]
				)

	if scanned < MIN_DOMAIN_FILES:
		failures.append("only %d of %d domain files were scanned; a guard that scans nothing "
				% [scanned, MIN_DOMAIN_FILES] + "reports PASS forever")
	if characters < MIN_SCANNED_CHARACTERS:
		failures.append("the domain scan covered %d characters, which is too little to be real"
				% characters)
	if FORBIDDEN_IN_DOMAIN.size() < 7:
		failures.append("the contract names seven forbidden types; this lists %d"
				% FORBIDDEN_IN_DOMAIN.size())
	return failures


## -- Rule 2: Chapter 2 does not walk -------------------------------------------

func _test_chapter_2_has_no_locomotion():
	var failures: Array = []
	var files: Array = []
	for directory: String in CHAPTER_2_DIRS:
		var found: Array = _files_under(directory)
		if found.is_empty():
			failures.append("%s holds no scannable file; either it moved or the guard is blind"
					% directory)
		files.append_array(found)

	var scanned: int = 0
	for path: String in files:
		var text: String = _read(path)
		if text.is_empty():
			continue
		# .tscn has no comment syntax to strip; a node type in a scene file is a
		# real dependency, which is exactly what must not appear here.
		var code: String = _code_of(text) if path.ends_with(".gd") else text
		scanned += 1
		for token: String in FORBIDDEN_IN_CHAPTER_2:
			if code.contains(token):
				failures.append(
					("%s references %s. Chapter 2 is a caregiver chapter -- tap, drag, give, feed "
					+ "-- and the baby does not walk. Locomotion belongs to Chapter 3+ and the "
					+ "HouseWorld, not to the Baby Room. This is a locked product decision, not "
					+ "an accident of the current implementation.") % [path, token]
				)

	if scanned < MIN_CHAPTER_2_FILES:
		failures.append("only %d Chapter 2 files were scanned, expected at least %d; the guard "
				% [scanned, MIN_CHAPTER_2_FILES] + "must not be able to pass by scanning nothing")
	return failures


## -- Layer discipline ------------------------------------------------------------

## Activity targets are layer 2, draggables layer 1. Restated here because it is
## the invariant that keeps tap-to-walk and drag-and-drop from fighting over the
## same press, and it is now load-bearing for four rooms rather than one spike.
func _test_layer_discipline():
	var failures: Array = []
	if ActivityTarget.ACTIVITY_TARGET_LAYER != 2:
		failures.append("activity targets must stay on collision layer 2, found %d"
				% ActivityTarget.ACTIVITY_TARGET_LAYER)
	if ActivityTarget.ACTIVITY_TARGET_LAYER & 1 != 0:
		failures.append("the activity-target layer overlaps the draggable layer (1); a walk "
				+ "raycast could swallow a press a drag needed")
	var draggable: String = _code_of(_read("res://scripts/interaction/draggable_object.gd"))
	if not draggable.contains("collision_layer = 1"):
		failures.append("draggable_object.gd no longer sets collision_layer = 1; the "
				+ "activity-target layer choice needs revisiting")
	return failures


## -- The id layer needs no engine ------------------------------------------------

## `semantic_id.gd` is what content uses to reason about ids. If it ever acquired
## a `Node` or a `Vector3`, content would acquire one too, and rule 1 would fall
## over from the other side.
func _test_semantic_ids_need_no_engine():
	var failures: Array = []
	var path: String = "res://scripts/navigation/semantic_id.gd"
	var code: String = _code_of(_read(path))
	if code.strip_edges().length() < 200:
		failures.append("%s stripped to almost nothing" % path)
		return failures
	var forbidden: Array = []
	forbidden.append_array(FORBIDDEN_IN_DOMAIN)
	forbidden.append_array(["SceneTree", "NodePath", "get_node"])
	for token: String in forbidden:
		if code.contains(token):
			failures.append("%s references %s; the id layer must stay pure strings so content "
					% [path, token] + "can validate an id without loading a scene")
	# And it works at all, which is what makes the purity worth having.
	if SemanticId.compose("kitchen", "fridge") != "kitchen.fridge":
		failures.append("semantic_id.gd does not compose ids correctly")
	return failures


## -- Source scanning --------------------------------------------------------------

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## Source with every comment removed and every string literal blanked, leaving
## executable code.
##
## String literals are blanked rather than kept so that a `"Vector3"` written as
## data -- a dictionary key, an error message, a test fixture -- is not mistaken
## for a dependency, and so that a `#` inside a string cannot be read as the start
## of a comment and blind the scanner to the rest of the line.
static func _code_of(text: String) -> String:
	var code: String = ""
	for raw_line: String in text.split("\n"):
		code += _strip_line(raw_line) + "\n"
	return code


static func _strip_line(line: String) -> String:
	return _strip_line_keeping(line, false)


## Comments removed, string CONTENTS kept.
##
## `_code_of()` blanks string bodies, which is right for type tokens -- a literal
## "Vector3" in a message is not a dependency. It is wrong for *paths*, because a
## path only ever appears inside a string: `preload("res://scripts/navigation/…")`
## strips to `preload("")` and the import becomes invisible.
##
## Found the hard way -- the import rule below silently could not fire until this
## existed, and a mutation that added a navigation preload to task_picker.gd
## passed. Two questions, two strippers.
static func _imports_of(text: String) -> String:
	var code: String = ""
	for raw_line: String in text.split("\n"):
		code += _strip_line_keeping(raw_line, true) + "\n"
	return code


static func _strip_line_keeping(line: String, keep_string_contents: bool) -> String:
	var out: String = ""
	var quote: String = ""
	var index: int = 0
	while index < line.length():
		var character: String = line[index]
		if quote.is_empty():
			if character == "#":
				break
			if character == "\"" or character == "'":
				quote = character
			else:
				out += character
		else:
			if character == "\\":
				index += 1  # skip the escaped character
			elif character == quote:
				quote = ""
			elif keep_string_contents:
				out += character
		index += 1
	return out


func _files_under(directory: String) -> Array:
	var found: Array = []
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return found
	for file_name: String in dir.get_files():
		var name: String = file_name.trim_suffix(".remap")
		for extension: String in CHAPTER_2_EXTENSIONS:
			if name.ends_with("." + extension):
				found.append("%s/%s" % [directory, name])
				break
	for sub_directory: String in dir.get_directories():
		found.append_array(_files_under("%s/%s" % [directory, sub_directory]))
	found.sort()
	return found
