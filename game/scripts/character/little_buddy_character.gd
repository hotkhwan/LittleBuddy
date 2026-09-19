extends CharacterBody3D

## Little Buddy. The one character a child drives, and the only place in the
## project that turns "go to the milk" into motion.
##
## Big Buddy -- the player -- has no body. Tapping IS Big Buddy; there is no
## second avatar to keep in sync.
##
## ## The public API, and the rule it exists to protect
##
## `mission_runner.gd`, `content_library.gd`, `content_validator.gd` and
## `task_picker.gd` have zero 3D references today. That property is worth more
## than it looks: it is why the content pipeline, the mission sequencing and the
## reward integrity all survived the move from 2D to 3D untouched. Navigation is
## the single most likely thing to break it, because the obvious implementation
## hands a `NavigationAgent3D` and a `Vector3` straight to the caller.
##
## So the semantic API below takes **String, float and bool -- nothing else**:
##
##     character.move_to("milkBottle")        # walk to a named thing
##     character.move_to_ground(1.2, -0.4)    # walk to a floor position
##     character.drive(0.0, -0.8)             # thumbstick: a direction, not a place
##     character.stop_driving()               # ...and let go
##     character.play_action("drink")         # show a semantic action
##     character.play_action("sit")           # ...or take up a posture
##     character.release_action()             # ...and leave it again
##     character.get_held_action()            # "sit" while sitting, else ""
##     character.stop()
##     character.is_busy()
##     character.get_state_name()
##
## and reports back through signals carrying only Strings. A mission never needs
## to import a 3D type, so it cannot accidentally couple to one.
##
##     character.set_target_position(...)     # FORBIDDEN
##     character.play("walk_anim_final")      # FORBIDDEN
##
## Spatial knowledge lives in `ActivityTarget` nodes registered by id. Movement
## decisions live in `CharacterMovementController`, which holds no node at all.
## Animation lives behind `CharacterActionDriver`. This script is the thin shell
## that joins them to a `CharacterBody3D` and a `NavigationAgent3D`.
##
## ## Lazy wiring
##
## `_ensure_wired()` runs from every public method, not only from `_ready()`,
## because the headless `--script` test runner never fires `_ready()` for nodes
## added to the root -- the same reason `session_summary.gd` has
## `_ensure_resolved()`. Without it, none of this would be testable.

const MovementControllerScript := preload("res://scripts/character/character_movement_controller.gd")
const ActionDriverScript := preload("res://scripts/character/character_action_driver.gd")
const AnimationDriverScript := preload("res://scripts/character/animation_player_action_driver.gd")
const NavMapProviderScript := preload("res://scripts/navigation/nav_map_provider.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## Emitted once per move request, when the character reaches the destination.
## Exactly once -- see `CharacterMovementController`'s arrival latch.
signal arrived(target_id: String)

## Emitted after arrival AND after the turn-to-face completes, for a move that
## had something to face. This -- not `arrived` -- is the cue a mission should
## wait for before starting an interaction: it means Little Buddy is standing in
## the right place, looking at the right thing.
signal interaction_ready(target_id: String)

## The request could not be honoured. `reason` is one of:
## "disabled", "unknownTarget", "targetDisabled", "unreachable".
## Never an error, never a crash -- the character simply carries on as it was.
signal move_failed(target_id: String, reason: String)

signal move_started(target_id: String)
signal action_started(action_name: String)
signal action_finished(action_name: String)
signal state_changed(state_name: String)

## Gentle. A toddler is not a projectile.
const GRAVITY: float = 9.8

## Path taken to a `NavigationAgent3D` child. Created on the fly if absent so the
## character works in a scene that has not been updated yet.
const AGENT_NODE_NAME: String = "NavigationAgent3D"

## How many times to go looking for an `AnimationPlayer` that has not appeared
## yet before accepting that this character simply has no animations.
const DRIVER_REBIND_ATTEMPTS: int = 8

var _controller: RefCounted = null
var _driver: RefCounted = null
var _agent: NavigationAgent3D = null
var _targets: Dictionary = {}
var _wired: bool = false
var _last_state_name: String = ""
var _driver_retries: int = 0


func _ready() -> void:
	_ensure_wired()
	set_physics_process(true)


## -- Public semantic API (String / float / bool only) -------------------------

## Walks to a registered activity target, or to an `ActivityTarget` node passed
## directly (a convenience for scene code; mission code should always use the id).
## Returns true when the character actually set off.
func move_to(target: Variant) -> bool:
	_ensure_wired()
	var node: Object = target if target is Object else _targets.get(String(target), null)
	var wanted_id: String = String(target) if not (target is Object) else _describe_id(target as Object)

	if _controller.call("is_disabled"):
		move_failed.emit(wanted_id, "disabled")
		return false
	if node == null or not is_instance_valid(node):
		move_failed.emit(wanted_id, "unknownTarget")
		return false
	if node.has_method("is_target_enabled") and not bool(node.call("is_target_enabled")):
		move_failed.emit(wanted_id, "targetDisabled")
		return false

	var info: Dictionary = node.call("describe", _world_position())
	var target_id: String = String(info.get("targetId", wanted_id))
	var options: Dictionary = {
		"targetId": target_id,
		"facePoint": info.get("facePosition", null),
		"arrivalRadius": float(info.get("arrivalRadius", MovementControllerScript.ARRIVAL_RADIUS)),
	}
	return _submit_move(info.get("standPosition", _world_position()), options, target_id)


## Walks to a point on the floor. Takes plain floats rather than a `Vector3` so
## even a floor tap can be expressed without a 3D type; the character supplies
## its own ground height.
func move_to_ground(x: float, z: float) -> bool:
	_ensure_wired()
	if _controller.call("is_disabled"):
		move_failed.emit("", "disabled")
		return false
	return _submit_move(Vector3(x, _world_position().y, z), {"targetId": ""}, "")


## Walks in a DIRECTION rather than to a place: the virtual thumbstick.
##
## `(x, z)` is a horizontal vector in WORLD space with magnitude 0..1, scaled to
## `CharacterMovementController.WALK_SPEED`. Plain floats, like everything else
## here, so the input layer never needs a 3D type either.
##
## Called every physics frame while a thumb is on the stick. The first call of a
## gesture cancels any tap-to-walk path in progress (no arrival is emitted; a
## cancelled walk did not arrive) and releases a held posture; the rest are
## cheap. Refused while disabled, exactly like `move_to()`.
##
## Added after a physical-device request for MOBA/RoV-style control. See
## `scripts/input/virtual_joystick.gd` for why that overrides the game bible's
## "no virtual joystick in early versions" -- it was decided, not overlooked.
func drive(x: float, z: float) -> bool:
	_ensure_wired()
	if not bool(_controller.call("set_drive", x, z)):
		return false
	_sync_state_signal()
	return true


## The thumb left the stick. Little Buddy coasts to a stop over a fraction of a
## second and returns to idle. Safe to call when he was never driving.
func stop_driving() -> void:
	_ensure_wired()
	_controller.call("clear_drive")
	_sync_state_signal()


## True while a thumb is on the stick. Not the same question as `is_busy()`:
## `is_busy()` stays true through the coast to a stop, this does not.
func is_driving() -> bool:
	_ensure_wired()
	return bool(_controller.call("is_driving"))


## Shows a semantic action: "drink", "eat", "sit", "brushTeeth", "celebrate"...
## The full vocabulary is `character_action_driver.gd`'s `KNOWN_ACTIONS`.
##
## Returns true if the action started. It starts whether or not an animation for
## it exists yet -- an unauthored action is a short pause and then a clean return
## to rest, never a frozen character. `can_play_action()` tells you which it will
## be, for callers that care.
##
## `action_finished` is emitted for **every** action, including the held ones:
## for `sit` it means "has finished sitting down", not "has stopped sitting". A
## mission may always await it and can never dead-end. After a held action
## finishes the character rests *in* the pose and `get_held_action()` names it;
## walking, another action, `stop()`, `release_action()` or `set_disabled(true)`
## all release it.
##
## `seconds` overrides the timing. Leave it out and the action takes its clip's
## own length if a clip exists, or the semantic default if it does not -- so
## authoring a longer `drink` animation later lengthens the drink automatically,
## with no content change.
func play_action(action_name: String, seconds: float = -1.0) -> bool:
	_ensure_wired()
	_ensure_driver()
	var holds: bool = ActionDriverScript.is_hold_action(action_name)
	if not bool(_controller.call("request_action", action_name, _action_seconds(action_name, seconds), holds)):
		return false
	# Best effort. A false from the driver is expected for the actions that have
	# no clip yet, and is deliberately not an error.
	_driver.call("play", action_name)
	action_started.emit(action_name)
	_sync_state_signal()
	return true


## True when an animation for `action_name` really exists right now.
func can_play_action(action_name: String) -> bool:
	_ensure_wired()
	_ensure_driver()
	return bool(_driver.call("can_play", action_name))


## Is `action_name` a posture that persists until released, rather than a
## one-shot that ends by itself? Lets a mission decide whether it needs to stand
## the character back up afterwards, without hard-coding the list.
func is_hold_action(action_name: String) -> bool:
	return ActionDriverScript.is_hold_action(action_name)


## The posture currently held ("sit", "sleep", "hold"), or "".
func get_held_action() -> String:
	_ensure_wired()
	return String(_controller.call("get_held_action"))


## Ends a held posture and returns to the resting look. Returns the posture that
## was released, or "" if the character was not holding one. Safe to call
## always; walking or starting another action releases the pose anyway.
func release_action() -> String:
	_ensure_wired()
	_ensure_driver()
	var released: String = String(_controller.call("release_hold"))
	if released.is_empty():
		return ""
	_rest_driver()
	_sync_state_signal()
	return released


## Stops walking or acting and returns to rest. Emits no `arrived`: a cancelled
## walk did not arrive.
func stop() -> void:
	_ensure_wired()
	_controller.call("cancel")
	_driver.call("rest", bool(_controller.call("is_carrying")))
	_sync_state_signal()


func set_carrying(carrying: bool) -> void:
	_ensure_wired()
	_controller.call("set_carrying", carrying)
	if not bool(_controller.call("is_moving")):
		_rest_driver()
	_sync_state_signal()


func is_carrying() -> bool:
	_ensure_wired()
	return bool(_controller.call("is_carrying"))


## Hard stop for overlays, summaries and cutscenes. Every request is refused
## while disabled.
func set_disabled(disabled: bool) -> void:
	_ensure_wired()
	_controller.call("set_disabled", disabled)
	if not disabled:
		_rest_driver()
	_sync_state_signal()


## "idle" | "walking" | "interacting" | "carrying" | "disabled".
func get_state_name() -> String:
	_ensure_wired()
	return String(_controller.call("get_state_name"))


## True while the character should not be handed a new instruction.
func is_busy() -> bool:
	_ensure_wired()
	return bool(_controller.call("is_busy"))


## The id of the thing currently being walked to, or "" for a floor walk.
func get_current_target_id() -> String:
	_ensure_wired()
	return String(_controller.call("get_target_id"))


## -- Activity target registry -------------------------------------------------

## Duck-typed: anything answering `get_activity_target_id()` and
## `describe(approach_from)` can be registered, so a prop scene can wrap a target
## without inheriting from anything.
func register_activity_target(target: Object) -> bool:
	_ensure_wired()
	if target == null or not target.has_method("get_activity_target_id"):
		return false
	if not target.has_method("describe"):
		return false
	var id: String = String(target.call("get_activity_target_id"))
	if id.strip_edges().is_empty():
		return false
	_targets[id] = target
	return true


func unregister_activity_target(target_id: String) -> void:
	_targets.erase(target_id)


func get_activity_target_ids() -> Array:
	var ids: Array = _targets.keys()
	ids.sort()
	return ids


func has_activity_target(target_id: String) -> bool:
	return _targets.has(target_id)


## -- Test/diagnostic seams ----------------------------------------------------

## Lets the spike scene (and tests) hand in a provider instead of the default
## `NavigationAgent3D`-backed one.
func set_navigation_provider(provider: RefCounted) -> void:
	_ensure_wired()
	_controller.call("set_provider", provider)


func set_action_driver(driver: RefCounted) -> void:
	_ensure_wired()
	_driver = driver if driver != null else ActionDriverScript.new()


func get_movement_controller() -> RefCounted:
	_ensure_wired()
	return _controller


## -- Frame loop ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_ensure_wired()
	step_movement(delta)


## Extracted from `_physics_process` so it can be driven by hand. The headless
## runner has no physics frames; without this seam the integration between the
## controller and the body would be completely unobservable in a test.
func step_movement(delta: float) -> void:
	_ensure_wired()
	var step: Dictionary = _controller.call("advance", _world_position(), rotation.y, delta)

	var horizontal: Vector3 = step.get("velocity", Vector3.ZERO)
	# Gravity only in grounded mode. A room with a flat floor and no physics
	# props runs in MOTION_MODE_FLOATING and needs no floor collider, no gravity
	# integration and no `is_on_floor()` -- the cheapest thing that works, and the
	# performance budget explicitly rules out heavy physics.
	var vertical: float = 0.0
	if motion_mode == MOTION_MODE_GROUNDED and not is_on_floor():
		vertical = velocity.y - GRAVITY * delta
	velocity = Vector3(horizontal.x, vertical, horizontal.z)
	rotation.y = float(step.get("yaw", rotation.y))

	# Drive the legs from the ACTUAL ground speed, every frame.
	#
	# The view owns the arithmetic (see `locomotion.gd`); this hands it the one
	# number it cannot know. Duck-typed, so a view without locomotion -- the
	# procedural toddler -- is simply not asked, and no caller has to check.
	_sync_locomotion(Vector2(horizontal.x, horizontal.z).length())

	if is_inside_tree():
		move_and_slide()
	else:
		# Outside the tree there is no physics server to move the body. Integrate
		# by hand so the controller/body integration is still observable in the
		# headless runner, which runs no physics frames at all.
		position += velocity * delta

	# Carrying is settled BEFORE the animation sync so that a `pickUp` which has
	# just finished rests into the carry idle on the same frame, rather than
	# flashing one frame of empty-handed idle.
	if bool(step.get("actionFinished", false)):
		_apply_carry_effect(String(step.get("actionName", "")))
	# The walk cycle is authored for exactly WALK_SPEED. The thumbstick made
	# every speed between zero and that reachable, so the clip is played at the
	# rate the body is actually moving and the feet stop skating.
	_sync_locomotion_rate(horizontal.length())
	_sync_animation(step)

	if bool(step.get("arrived", false)):
		arrived.emit(String(step.get("targetId", "")))
	if bool(step.get("interactionReady", false)):
		interaction_ready.emit(String(step.get("targetId", "")))
	if bool(step.get("actionFinished", false)):
		action_finished.emit(String(step.get("actionName", "")))
	_sync_state_signal()


## -- Internals ----------------------------------------------------------------

func _submit_move(destination: Variant, options: Dictionary, target_id: String) -> bool:
	var point: Vector3 = destination if destination is Vector3 else _world_position()
	_controller.call("set_position", _world_position())
	var result: int = int(_controller.call("request_move", point, options))

	match result:
		MovementControllerScript.MoveResult.UNREACHABLE:
			# The tap landed somewhere Little Buddy genuinely cannot stand and is
			# too far off the mesh to guess at. Do nothing at all -- no walk
			# animation, no half-path, and no cancelling of a perfectly good walk
			# that was already in progress.
			move_failed.emit(target_id, "unreachable")
			return false
		MovementControllerScript.MoveResult.REFUSED:
			move_failed.emit(target_id, "disabled")
			return false
		_:
			move_started.emit(target_id)
			_ensure_driver()
			_driver.call("play", "walk")
			_sync_state_signal()
			return true


func _sync_animation(step: Dictionary) -> void:
	_ensure_driver()
	var state: int = int(step.get("state", MovementControllerScript.State.IDLE))
	var held: String = String(step.get("heldAction", ""))
	match state:
		MovementControllerScript.State.WALKING:
			if _driver.call("get_current_action") != "walk":
				_driver.call("play", "walk")
		MovementControllerScript.State.IDLE, MovementControllerScript.State.CARRYING:
			# A held posture rests *as the pose*. Without this the per-frame
			# rest-sync would drag a sitting toddler back to a standing idle one
			# frame after he sat down, which is the exact bug the CARRYING state
			# already taught us to expect.
			if not held.is_empty():
				if _driver.call("get_current_action") != held:
					_driver.call("play", held)
			elif _driver.call("get_current_action") != "idle":
				_driver.call("rest", bool(_controller.call("is_carrying")))
		_:
			pass


## How long an action should run: an explicit override wins, then the driver's
## own opinion (an authored clip times itself), then the semantic default.
func _action_seconds(action_name: String, requested: float) -> float:
	if requested > 0.0:
		return requested
	var from_clip: float = float(_driver.call("get_action_duration", action_name))
	if from_clip > 0.0:
		return from_clip
	return ActionDriverScript.default_duration(action_name)


## `pickUp` fills the hands, `give` empties them, `hold` keeps them full, and
## every other action has no opinion at all -- which is why the table answers
## `null` rather than `false` for them.
## Tells the view how fast the body is actually travelling.
##
## Kept separate from the action vocabulary on purpose: walking is not an ACTION
## a caller requests, it is a consequence of moving, and routing it through
## `play_action("walk")` would let a mission think it had asked for something.
func _sync_locomotion(speed: float) -> void:
	var view: Node = _find_locomotion_view(self)
	if view != null:
		view.call("set_locomotion", speed)


func _find_locomotion_view(node: Node) -> Node:
	for child: Node in node.get_children():
		if child.has_method("set_locomotion"):
			return child
		var deeper: Node = _find_locomotion_view(child)
		if deeper != null:
			return deeper
	return null


func _apply_carry_effect(action_name: String) -> void:
	var effect: Variant = ActionDriverScript.carry_effect(action_name)
	if effect == null:
		return
	_controller.call("set_carrying", bool(effect))


## Tells the animation driver how fast the body is really going, as a fraction
## of `WALK_SPEED`. Duck-typed: a driver without the method simply has no clips
## to scale.
func _sync_locomotion_rate(speed: float) -> void:
	if _driver == null or not _driver.has_method("set_locomotion_scale"):
		return
	_driver.call("set_locomotion_scale", speed / MovementControllerScript.WALK_SPEED)


## `rest()`, unless a posture is being held -- in which case resting IS the pose.
func _rest_driver() -> void:
	if not String(_controller.call("get_held_action")).is_empty():
		return
	_driver.call("rest", bool(_controller.call("is_carrying")))


## Re-binds the animation driver if it is still attached to nothing.
##
## The view that owns the `AnimationPlayer` may build itself later than the first
## call into the character -- a procedurally built body builds in its own
## `_ready()`, and a GLB character will stream in later still. Binding once and
## for all at wiring time would silently leave a character that never animates,
## which is invisible to every test that only checks state names.
##
## Retries are capped so this cannot become a per-frame subtree walk for a
## character that genuinely has no animations (the primitive placeholder is a
## legitimate case).
func _ensure_driver() -> void:
	if _driver_retries >= DRIVER_REBIND_ATTEMPTS:
		return
	if _driver != null and bool(_driver.call("can_play", "idle")):
		_driver_retries = DRIVER_REBIND_ATTEMPTS
		return
	_driver_retries += 1
	var player: AnimationPlayer = _find_animation_player(self)
	if player != null:
		_driver = AnimationDriverScript.create(player)


func _sync_state_signal() -> void:
	var name_now: String = String(_controller.call("get_state_name"))
	if name_now == _last_state_name:
		return
	_last_state_name = name_now
	state_changed.emit(name_now)


func _describe_id(node: Object) -> String:
	if node.has_method("get_activity_target_id"):
		return String(node.call("get_activity_target_id"))
	return ""


func _ensure_wired() -> void:
	if _wired:
		return
	_wired = true

	_agent = get_node_or_null(AGENT_NODE_NAME) as NavigationAgent3D
	if _agent == null:
		_agent = NavigationAgent3D.new()
		_agent.name = AGENT_NODE_NAME
		# Avoidance off: there is one character and no crowd. Avoidance needs a
		# synchronised map and its own server process step, and buys nothing here.
		_agent.avoidance_enabled = false
		add_child(_agent)

	_controller = MovementControllerScript.create(NavMapProviderScript.create(_agent))
	_controller.call("set_position", _world_position())
	_driver = AnimationDriverScript.create(_find_animation_player(self))
	_last_state_name = String(_controller.call("get_state_name"))


## `global_position` asserts `is_inside_tree()`; this does not, so the character
## behaves identically in a running scene and in a headless test.
func _world_position() -> Vector3:
	return SpatialUtil.world_position(self)


func _find_animation_player(node: Node) -> AnimationPlayer:
	for child: Node in node.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var deeper: AnimationPlayer = _find_animation_player(child)
		if deeper != null:
			return deeper
	return null
