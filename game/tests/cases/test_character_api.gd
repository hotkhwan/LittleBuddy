extends RefCounted

## The architecture rule, made into a test.
##
## `mission_runner.gd`, `content_library.gd`, `content_validator.gd` and
## `task_picker.gd` have zero 3D references, and that property is why the content
## pipeline, mission sequencing and reward integrity survived the 2D-to-3D move
## untouched. Navigation is the most likely thing to break it, because the
## obvious implementation hands a `NavigationAgent3D` straight to the caller.
##
## So this file asserts, in three independent ways:
##
##   1. The whole semantic API is **usable with nothing but Strings, floats and
##      bools** -- proven by driving a real character through a complete walk
##      using only string ids. If a signature ever demanded a 3D type, these
##      calls would stop compiling or stop working.
##   2. No public method signature and no signal on `LittleBuddyCharacter`
##      mentions a 3D type.
##   3. The existing domain layer still contains zero 3D references.
##
## Covers required behaviours 1, 2, 4, 6 and 8 at the character level.

const LittleBuddyCharacter := preload("res://scripts/character/little_buddy_character.gd")
const NavigationProvider := preload("res://scripts/navigation/navigation_provider.gd")
const MovementController := preload("res://scripts/character/character_movement_controller.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")

const DT: float = 1.0 / 60.0
const MAX_FRAMES: int = 1500

## Types a mission must never have to know about.
const FORBIDDEN_TYPES: Array[String] = [
	"Node3D", "Area3D", "Camera3D", "CharacterBody3D", "CollisionShape3D", "Marker3D",
	"MeshInstance3D", "NavigationAgent3D", "NavigationRegion3D", "NavigationMesh",
	"NavigationServer3D", "AnimationPlayer", "AnimationTree", "Vector3", "Transform3D",
	"PhysicsDirectSpaceState3D",
]

## Methods that would betray the abstraction if they ever appeared.
const FORBIDDEN_METHODS: Array[String] = [
	"set_target_position", "get_navigation_agent", "get_navigation_map",
	"play_animation", "get_animation_player", "set_path",
]

## The case that now owns the domain-layer source scan.
const ARCHITECTURE_GUARD_CASE: String = "res://tests/cases/test_architecture_guard.gd"

## The domain layer whose 3D-free status this test protects.
const DOMAIN_SCRIPTS: Array[String] = [
	"res://scripts/gameplay/mission_runner.gd",
	"res://scripts/content/content_library.gd",
	"res://scripts/content/content_validator.gd",
	"res://scripts/content/task_picker.gd",
]

const CHARACTER_SCRIPT: String = "res://scripts/character/little_buddy_character.gd"


## Emulates a walled room so the character-level unreachable path can be driven.
class RoomProvider extends NavigationProvider:
	var bounds: Rect2 = Rect2(-4.0, -4.0, 8.0, 8.0)

	func is_navigation_ready() -> bool:
		return true

	func query_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		return PackedVector3Array([from, snap_to_navigable(to)])

	func snap_to_navigable(point: Vector3) -> Vector3:
		return Vector3(
			clampf(point.x, bounds.position.x, bounds.end.x),
			point.y,
			clampf(point.z, bounds.position.y, bounds.end.y)
		)


## A duck-typed activity target. Deliberately NOT an `ActivityTarget`: the
## character's registry is duck-typed so a prop scene can wrap a target without
## inheriting anything, and this proves it.
class StubTarget extends Node3D:
	var id: String = "toyBox"
	var enabled: bool = true
	var stand: Vector3 = Vector3(1.5, 0.0, 0.0)
	# Deliberately PERPENDICULAR to the approach: walking east from the origin
	# leaves the character already facing east, so a facing point due east would
	# complete the turn in a single frame and the several-frame window where a
	# missing arrival latch would re-fire would never be exercised.
	var face: Vector3 = Vector3(1.5, 0.0, -3.0)

	func get_activity_target_id() -> String:
		return id

	func is_target_enabled() -> bool:
		return enabled

	func describe(_approach_from: Vector3) -> Dictionary:
		return {
			"targetId": id,
			"enabled": enabled,
			"standPosition": stand,
			"facePosition": face,
			"arrivalRadius": 0.22,
		}


## Collects every signal the character emits, so ordering and counts can be
## asserted rather than assumed.
class SignalLog extends RefCounted:
	var events: Array = []

	func listen(character: Node) -> void:
		character.connect("arrived", _on_arrived)
		character.connect("interaction_ready", _on_interaction_ready)
		character.connect("move_failed", _on_move_failed)
		character.connect("move_started", _on_move_started)
		character.connect("action_started", _on_action_started)
		character.connect("action_finished", _on_action_finished)
		character.connect("state_changed", _on_state_changed)

	func _on_arrived(id: String) -> void:
		events.append(["arrived", id])

	func _on_interaction_ready(id: String) -> void:
		events.append(["interactionReady", id])

	func _on_move_failed(id: String, reason: String) -> void:
		events.append(["moveFailed", id, reason])

	func _on_move_started(id: String) -> void:
		events.append(["moveStarted", id])

	func _on_action_started(action_name: String) -> void:
		events.append(["actionStarted", action_name])

	func _on_action_finished(action_name: String) -> void:
		events.append(["actionFinished", action_name])

	func _on_state_changed(state_name: String) -> void:
		events.append(["stateChanged", state_name])

	func count(kind: String) -> int:
		var total: int = 0
		for event: Array in events:
			if event[0] == kind:
				total += 1
		return total

	func kinds() -> Array:
		var result: Array = []
		for event: Array in events:
			result.append(event[0])
		return result

	func first(kind: String) -> Array:
		for event: Array in events:
			if event[0] == kind:
				return event
		return []


func test_name() -> String:
	return "character_api"


func run():
	var failures: Array = []
	failures.append_array(_test_walk_to_a_named_target_using_only_strings())
	failures.append_array(_test_floor_walk_takes_only_floats())
	failures.append_array(_test_failures_are_reported_never_fatal())
	failures.append_array(_test_disabled_refuses_everything())
	failures.append_array(_test_public_signatures_are_engine_free())
	failures.append_array(_test_signals_carry_only_strings())
	failures.append_array(_test_forbidden_methods_absent())
	failures.append_array(_test_domain_layer_stays_3d_free())
	return failures


## THE headline test. Every call below uses a String and nothing else.
func _test_walk_to_a_named_target_using_only_strings():
	var failures: Array = []
	var character: CharacterBody3D = _make_character()
	var log := SignalLog.new()
	log.listen(character)

	var target := StubTarget.new()
	if not bool(character.call("register_activity_target", target)):
		failures.append("a duck-typed target should be registerable")
	if not bool(character.call("has_activity_target", "toyBox")):
		failures.append("the registry should know the target by its semantic id")
	if character.call("get_activity_target_ids") != ["toyBox"]:
		failures.append("the registry should list its ids")

	# --- The only line a mission would ever write.
	if not bool(character.call("move_to", "toyBox")):
		failures.append("move_to(\"toyBox\") should set the character walking")
	if String(character.call("get_state_name")) != "walking":
		failures.append("the character should be walking, got '%s'"
				% String(character.call("get_state_name")))
	if String(character.call("get_current_target_id")) != "toyBox":
		failures.append("the character should report the semantic target it is walking to")
	if not bool(character.call("is_busy")):
		failures.append("a walking character should report itself busy")

	_run(character)

	if log.count("arrived") != 1:
		failures.append("expected exactly one arrival, got %d" % log.count("arrived"))
	if log.count("interactionReady") != 1:
		failures.append("expected exactly one interaction-ready, got %d"
				% log.count("interactionReady"))
	if log.first("arrived") != ["arrived", "toyBox"]:
		failures.append("arrival should carry the semantic id, got %s" % str(log.first("arrived")))

	var ordering: Array = log.kinds()
	if ordering.find("arrived") > ordering.find("interactionReady"):
		failures.append("arrival must be reported before interaction-ready")
	if String(character.call("get_state_name")) != "idle":
		failures.append("the character should end idle")
	if bool(character.call("is_busy")):
		failures.append("an idle character should not report itself busy")
	if not NavMath.is_within(character.position, target.stand, 0.22):
		failures.append("expected to stand at the interaction point, at %s" % str(character.position))

	# And it faces the object, which is what interaction-ready actually means.
	var wanted: float = NavMath.yaw_towards(character.position, target.face, character.rotation.y)
	if not NavMath.yaw_reached(character.rotation.y, wanted, MovementController.FACING_TOLERANCE):
		failures.append("the character should be facing the object on interaction-ready")

	target.free()
	character.free()
	return failures


func _test_floor_walk_takes_only_floats():
	var failures: Array = []
	var character: CharacterBody3D = _make_character()
	var log := SignalLog.new()
	log.listen(character)

	if not bool(character.call("move_to_ground", -1.5, 2.0)):
		failures.append("move_to_ground() should accept a plain pair of floats")
	_run(character)

	if log.count("arrived") != 1:
		failures.append("a floor walk should arrive exactly once, got %d" % log.count("arrived"))
	if log.first("arrived") != ["arrived", ""]:
		failures.append("a floor walk has no semantic target, so the id should be empty")
	if log.count("interactionReady") != 0:
		failures.append("a floor walk has nothing to face, so it must not report interaction-ready")
	if not NavMath.is_within(character.position, Vector3(-1.5, 0.0, 2.0), MovementController.ARRIVAL_RADIUS):
		failures.append("expected to reach the floor point, stopped at %s" % str(character.position))

	# Movement cancel: `stop()` ends the walk and never reports an arrival.
	character.call("move_to_ground", 3.0, 0.0)
	for _frame: int in range(10):
		character.call("step_movement", DT)
	var before: int = log.count("arrived")
	character.call("stop")
	if String(character.call("get_state_name")) != "idle":
		failures.append("stop() should return the character to idle")
	for _frame: int in range(200):
		character.call("step_movement", DT)
	if log.count("arrived") != before:
		failures.append("a stopped walk must never report an arrival")

	character.free()
	return failures


## Every failure is a signal, never a crash and never a stuck state.
func _test_failures_are_reported_never_fatal():
	var failures: Array = []
	var character: CharacterBody3D = _make_character()
	var log := SignalLog.new()
	log.listen(character)

	if bool(character.call("move_to", "aTargetThatDoesNotExist")):
		failures.append("moving to an unknown id should fail")
	if log.first("moveFailed") != ["moveFailed", "aTargetThatDoesNotExist", "unknownTarget"]:
		failures.append("an unknown target should be reported as such, got %s"
				% str(log.first("moveFailed")))
	if String(character.call("get_state_name")) != "idle":
		failures.append("an unknown target must leave the character idle, not walking")

	var target := StubTarget.new()
	target.id = "sink"
	target.enabled = false
	character.call("register_activity_target", target)
	if bool(character.call("move_to", "sink")):
		failures.append("moving to a disabled target should fail")
	if log.count("moveFailed") != 2:
		failures.append("a disabled target should report a failure")

	# Unreachable: outside the room, beyond the forgiving snap radius.
	target.enabled = true
	target.stand = Vector3(40.0, 0.0, 40.0)
	log.events.clear()
	if bool(character.call("move_to", "sink")):
		failures.append("an unreachable target should fail")
	if log.first("moveFailed") != ["moveFailed", "sink", "unreachable"]:
		failures.append("an unreachable target should say 'unreachable', got %s"
				% str(log.first("moveFailed")))
	if String(character.call("get_state_name")) != "idle":
		failures.append("an unreachable tap must never leave a walk animation running")

	# A near miss, on the other hand, is forgiven rather than refused.
	target.stand = Vector3(4.3, 0.0, 0.0)  # 0.3 m past the wall at x = 4.
	if not bool(character.call("move_to", "sink")):
		failures.append("a near-miss target should be forgiven, not refused")

	target.free()
	character.free()
	return failures


func _test_disabled_refuses_everything():
	var failures: Array = []
	var character: CharacterBody3D = _make_character()
	var log := SignalLog.new()
	log.listen(character)

	character.call("set_disabled", true)
	if String(character.call("get_state_name")) != "disabled":
		failures.append("set_disabled(true) should enter the disabled state")
	if bool(character.call("move_to_ground", 1.0, 1.0)):
		failures.append("a disabled character must refuse a floor walk")
	if bool(character.call("play_action", "drink")):
		failures.append("a disabled character must refuse an action")
	if log.count("moveFailed") != 1:
		failures.append("a refused move should still be reported")

	for _frame: int in range(60):
		character.call("step_movement", DT)
	if not character.position.is_equal_approx(Vector3.ZERO):
		failures.append("a disabled character must not move")

	character.call("set_disabled", false)
	if String(character.call("get_state_name")) != "idle":
		failures.append("re-enabling should return to idle")
	if not bool(character.call("move_to_ground", 1.0, 1.0)):
		failures.append("a re-enabled character should accept a walk again")

	character.free()
	return failures


## Static check 2: no public signature on the character mentions a 3D type.
func _test_public_signatures_are_engine_free():
	var failures: Array = []
	var source: String = _read(CHARACTER_SCRIPT)
	if source.is_empty():
		return ["could not read %s" % CHARACTER_SCRIPT]

	var found_public: int = 0
	for raw_line: String in source.split("\n"):
		var line: String = raw_line.strip_edges()
		if not line.begins_with("func "):
			continue
		var signature: String = line.substr(5)
		if signature.begins_with("_"):
			continue  # Private; free to speak 3D.
		found_public += 1
		for forbidden: String in FORBIDDEN_TYPES:
			if signature.contains(forbidden):
				failures.append("public API leaks an engine type: `%s` mentions %s"
						% [line, forbidden])

	if found_public < 10:
		failures.append("only found %d public methods to check; the scan is not working"
				% found_public)
	return failures


func _test_signals_carry_only_strings():
	var failures: Array = []
	var character: CharacterBody3D = _make_character()
	var allowed: Array = [TYPE_STRING, TYPE_STRING_NAME, TYPE_BOOL, TYPE_INT, TYPE_FLOAT]
	var checked: int = 0

	for info: Dictionary in character.get_signal_list():
		var signal_name: String = String(info.get("name", ""))
		# Only our own signals; CharacterBody3D brings its own inherited ones.
		if not signal_name in [
			"arrived", "interaction_ready", "move_failed", "move_started",
			"action_started", "action_finished", "state_changed",
		]:
			continue
		checked += 1
		for argument: Dictionary in info.get("args", []):
			if not allowed.has(int(argument.get("type", TYPE_NIL))):
				failures.append("signal %s(%s) carries a non-primitive argument"
						% [signal_name, String(argument.get("name", ""))])
			if not String(argument.get("class_name", "")).is_empty():
				failures.append("signal %s carries a class-typed argument (%s)"
						% [signal_name, String(argument.get("class_name", ""))])

	if checked != 7:
		failures.append("expected to check 7 character signals, checked %d" % checked)
	character.free()
	return failures


func _test_forbidden_methods_absent():
	var failures: Array = []
	var character: CharacterBody3D = _make_character()
	for method: String in FORBIDDEN_METHODS:
		if character.has_method(method):
			failures.append("LittleBuddyCharacter exposes %s(); mission code would be able to "
					% method + "drive navigation directly")
	# And the semantic ones really are there.
	for method: String in ["move_to", "move_to_ground", "play_action", "stop", "is_busy", "get_state_name"]:
		if not character.has_method(method):
			failures.append("the semantic API is missing %s()" % method)
	character.free()
	return failures


## Static check 3: the property that made this whole architecture worth keeping.
## Moved to `test_architecture_guard.gd`, which scans the same four files with
## the same (now wider) token list but strips comments first.
##
## This version read RAW source, so it failed on a doc comment that merely
## *mentioned* a forbidden type. Verified: adding
## `## Note: this module deliberately holds no Vector3 and no Node3D.`
## to task_picker.gd turned this test red while the comment-stripped guard
## correctly stayed green. A test that punishes accurate documentation gets
## weakened rather than fixed, so it is better to have one scanner that is right.
##
## What remains here is the part only this file can check: that the *character's*
## own public surface never exposes a 3D type. That is a live API boundary, not a
## file scan, and it stays.
func _test_domain_layer_stays_3d_free():
	var failures: Array = []

	# Fail loudly if the guard that took over this duty is ever removed, rather
	# than quietly losing the coverage.
	if not FileAccess.file_exists(ARCHITECTURE_GUARD_CASE):
		failures.append(
			("%s is missing. It owns the domain-layer 3D scan that used to live here; "
			+ "without it nothing checks that mission/content code stays engine-agnostic.")
			% ARCHITECTURE_GUARD_CASE
		)

	return failures


## -- Helpers -------------------------------------------------------------------

func _make_character() -> CharacterBody3D:
	var character: CharacterBody3D = LittleBuddyCharacter.new()
	character.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	character.call("set_navigation_provider", RoomProvider.new())
	return character


func _run(character: CharacterBody3D) -> void:
	for _frame: int in range(MAX_FRAMES):
		character.call("step_movement", DT)
		if String(character.call("get_state_name")) in ["idle", "carrying"]:
			return


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
