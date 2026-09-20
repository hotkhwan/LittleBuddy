extends Area3D

## A thing in the world that Little Buddy can be told to go to, addressed by a
## **semantic id** and nothing else.
##
## This is the object on the far side of the architecture rule. Mission and
## content code says `character.move_to("milkBottle")`; it never sees this node,
## never sees a `Vector3`, and never sees a `NavigationAgent3D`. Everything
## spatial -- where to stand, which way to face, how close is close enough --
## lives here, in the scene, next to the art.
##
## ## Layers
##
## Activity targets sit alone on collision layer 2 so that tap-routing can
## raycast for them without colliding with the existing draggable pickups on
## layer 1. `input_ray_pickable` stays false: these are found by
## `NavigationController`'s explicit raycast, not by viewport physics picking, so
## a target can never swallow a press that a `DraggableObject` needed. That is
## what keeps drag-and-drop working unchanged alongside navigation.
##
## ## Semantic ids, and what a room adds
##
## A target is addressed as `"<roomId>.<targetId>"` -- `"kitchen.fridge"`. Set
## `room_id` and the target answers `"kitchen.fridge"` everywhere; leave it empty
## and it answers the bare `target_id`, exactly as the Phase 2A spike's
## `"toyBox"` always has. That is the whole backward-compatibility story: the
## room half is additive, and an unroomed target is byte-for-byte the object it
## was before.
##
## Both `get_activity_target_id()` and `describe()["targetId"]` report the
## ADDRESSABLE id, so `character.move_to(id)`, the character's registry, the tap
## raycast and every signal all agree on one string. `get_local_target_id()`
## returns the unqualified half for the rare caller that wants it.
##
## ## Lazy wiring
##
## Everything resolves on first use rather than in `_ready()`. The headless
## `--script` test runner never fires `_ready()` for nodes added to the root, so a
## target that only worked after `_ready()` would be untestable -- the same reason
## `session_summary.gd` has `_ensure_resolved()`.

const NavMath := preload("res://scripts/navigation/nav_math.gd")
const InteractionPointScript := preload("res://scripts/navigation/interaction_point.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const SemanticId := preload("res://scripts/navigation/semantic_id.gd")
const AffordanceRules := preload("res://scripts/interaction/affordance_rules.gd")

## The group `affordance_layer.gd` polls. Any node in it that answers
## `get_affordance(actor)` is offered to the child when they are close enough.
const AFFORDABLE_GROUP: String = "affordable"

## How far the affordance badge reaches beyond the target's own footprint, in
## metres. Generous on purpose: the badge is the BIG tap target that replaces
## a precise tap on a small mesh, so it has to be there before the child is
## pressed up against the fridge.
const AFFORDANCE_REACH: float = 1.15

## Layer 2 (bit value 2). Layer 1 belongs to `DraggableObject`.
const ACTIVITY_TARGET_LAYER: int = 2

## Used when no `InteractionPoint` child was authored: stand this far back from
## the object, on whichever side the character is approaching from.
const DEFAULT_STAND_DISTANCE: float = 0.55

## How close the character must get before this target counts as reached.
## Deliberately looser than a floor tap: arriving "at the sink" means standing
## near it, not on a specific square centimetre.
const DEFAULT_ARRIVAL_RADIUS: float = 0.22

## The semantic name mission/content code uses. Must be unique within a room.
@export var target_id: String = ""

## The room this target belongs to: `"kitchen"`. Empty is legal and means "not in
## a room" -- the id then stays unqualified, which is what every pre-Phase-2B
## target relies on.
@export var room_id: String = ""

## Shown/spoken name, if a room ever wants to label it. Not used for routing.
@export var display_name: String = ""

## What can be done here: `["open", "give"]`. SEMANTIC names only -- never an
## animation clip, never a method name. A mission asks "does this target support
## 'give'?" and the answer must not depend on how the animation was authored.
@export var supported_actions: PackedStringArray = PackedStringArray()

## Optional: the object a child must be carrying for the interaction to make
## sense, e.g. `"milk"`. A semantic object id, not a node.
@export var required_object: String = ""

## Optional authoring tags, for a level or mission to filter targets by. Never
## used for routing, so a wrong tag can never strand the character.
@export var level_tag: String = ""
@export var mission_tag: String = ""

## Optional: a node to look at on arrival, overriding everything else. Relative
## to this target. Use it for the thing you actually want looked at -- the tap
## rather than the sink's centre of mass.
@export var look_target_path: NodePath = NodePath()

## Optional: the world-space direction Little Buddy should face on arrival. Zero
## (the default) means "work it out", which is what every existing target does.
@export var facing_direction: Vector3 = Vector3.ZERO

## Door fields (contract §4). A target with `to_room_id` set is a door: walking
## to it is a request to change room. Empty on everything that is not a door, so
## `is_door()` is false by default and no ordinary target can accidentally
## teleport a child.
@export var to_room_id: String = ""
@export var to_spawn_id: String = ""

## A disabled target is still in the scene but cannot be walked to -- the
## equivalent of `DraggableObject.set_enabled(false)`, and used for the same
## reason: an object that is not part of the current task must not be tappable.
@export var target_enabled: bool = true

@export var stand_distance: float = DEFAULT_STAND_DISTANCE
@export var arrival_radius: float = DEFAULT_ARRIVAL_RADIUS

## Affordance activation radius, metres. Zero (the default) derives one from the
## tap box: half its footprint plus `AFFORDANCE_REACH`.
@export var affordance_radius: float = 0.0

var _resolved: bool = false
var _interaction_point: Marker3D = null
## Optional: `func(target: Node, actor: Node3D) -> Dictionary`, supplying the
## `context` half of `AffordanceRules.verb_for_target()` -- whether this fridge
## is open, what the actor is holding. Installed by the layer, never by content.
var _affordance_context: Callable = Callable()


func _ready() -> void:
	_ensure_resolved()


## Idempotent, and called from every public method, so this node behaves
## identically whether or not `_ready()` ever ran.
func _ensure_resolved() -> void:
	if _resolved:
		return
	_resolved = true
	collision_layer = ACTIVITY_TARGET_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = false
	input_ray_pickable = false
	if not is_in_group(AFFORDABLE_GROUP):
		add_to_group(AFFORDABLE_GROUP)
	for child: Node in get_children():
		if child is Marker3D and child.get_script() == InteractionPointScript:
			_interaction_point = child as Marker3D
			return
	# Tolerate a plain Marker3D named InteractionPoint, so a scene authored
	# before the script existed still works.
	var named: Node = get_node_or_null("InteractionPoint")
	if named is Marker3D:
		_interaction_point = named as Marker3D


## The addressable semantic id -- `"kitchen.fridge"`, or a bare `"toyBox"` for a
## target with no room.
##
## Duck-typed on purpose: `NavigationController` walks up the ancestors of
## whatever its raycast hit looking for anything that answers this, so a target
## can be wrapped in a prop scene without any type coupling.
func get_activity_target_id() -> String:
	return get_semantic_id()


## `"<roomId>.<targetId>"`. Identical to `get_activity_target_id()`; it exists
## under its own name because that is what the contract calls it and what content
## code should read at a call site.
func get_semantic_id() -> String:
	_ensure_resolved()
	return SemanticId.compose(room_id, target_id)


## The unqualified half: `"fridge"`. Unique within a room, not globally --
## `bedroom.toy` and `livingRoom.toy` are both fine.
func get_local_target_id() -> String:
	_ensure_resolved()
	return SemanticId.normalize(target_id)


func get_room_id() -> String:
	_ensure_resolved()
	return SemanticId.normalize(room_id)


## Semantic action names, trimmed and de-duplicated. A plain `Array` of `String`,
## so it drops straight into a camelCase dictionary or JSON without conversion.
func get_supported_actions() -> Array:
	_ensure_resolved()
	var actions: Array = []
	for raw: String in supported_actions:
		var action: String = raw.strip_edges()
		if not action.is_empty() and not actions.has(action):
			actions.append(action)
	return actions


func supports_action(action_name: String) -> bool:
	return get_supported_actions().has(action_name.strip_edges())


## Replaces the action list. Takes a `Variant` so an untyped `Array` literal from
## a room script assigns cleanly; a typed export assigned through `set()` is a
## known GDScript trap.
func set_supported_actions(actions: Variant) -> void:
	_ensure_resolved()
	var list: PackedStringArray = PackedStringArray()
	if actions is PackedStringArray or actions is Array:
		for entry: Variant in actions:
			var action: String = String(entry).strip_edges()
			if not action.is_empty() and not list.has(action):
				list.append(action)
	supported_actions = list


func get_required_object() -> String:
	_ensure_resolved()
	return required_object.strip_edges()


func requires_object() -> bool:
	return not get_required_object().is_empty()


func get_level_tag() -> String:
	_ensure_resolved()
	return level_tag.strip_edges()


func get_mission_tag() -> String:
	_ensure_resolved()
	return mission_tag.strip_edges()


## True when walking here means "take me to another room".
func is_door() -> bool:
	_ensure_resolved()
	return not to_room_id.strip_edges().is_empty()


## Where a door leads, as strings only. `toSpawnId` may be empty, which a
## transition controller should read as "the destination room's default spawn" --
## never as a coordinate, so a room edit can never strand a child.
func get_destination() -> Dictionary:
	_ensure_resolved()
	return {
		"toRoomId": to_room_id.strip_edges(),
		"toSpawnId": to_spawn_id.strip_edges(),
	}


func is_target_enabled() -> bool:
	_ensure_resolved()
	return target_enabled


func set_target_enabled(value: bool) -> void:
	_ensure_resolved()
	target_enabled = value


func has_interaction_point() -> bool:
	_ensure_resolved()
	return _interaction_point != null


## Where to stand. An authored `InteractionPoint` wins; otherwise it is computed
## on the approach side so the character does not walk through the object to
## reach an arbitrary fixed spot behind it.
func get_stand_position(approach_from: Vector3) -> Vector3:
	_ensure_resolved()
	if _interaction_point != null and _interaction_point.has_method("get_stand_position"):
		return _interaction_point.call("get_stand_position")
	if _interaction_point != null:
		return SpatialUtil.world_position(_interaction_point)
	return NavMath.stand_position(SpatialUtil.world_position(self), approach_from, stand_distance)


## What to turn towards on arrival. Most specific authored intent wins:
##
## 1. `look_target_path` -- an explicit node.
## 2. `facing_direction` -- an explicit direction, resolved from where the
##    character will be standing (hence the optional `stand_position`).
## 3. The `InteractionPoint`'s own facing, which already handles its
##    `face_point_path` and otherwise means "look at the object".
## 4. The object itself.
##
## `stand_position` is optional so the original no-argument call site keeps
## working unchanged; without it, a `facing_direction` is measured from the
## object instead, which points the same way.
func get_facing_position(stand_position: Variant = null) -> Vector3:
	_ensure_resolved()
	if not look_target_path.is_empty():
		var explicit: Node = get_node_or_null(look_target_path)
		if explicit is Node3D:
			return SpatialUtil.world_position(explicit as Node3D)
	var flat: Vector3 = Vector3(facing_direction.x, 0.0, facing_direction.z)
	if flat.length() > NavMath.EPSILON:
		var origin: Vector3 = SpatialUtil.world_position(self)
		if stand_position is Vector3:
			origin = stand_position
		return origin + flat.normalized()
	if _interaction_point != null and _interaction_point.has_method("get_facing_position"):
		return _interaction_point.call("get_facing_position")
	return SpatialUtil.world_position(self)


## Everything a mover needs, in one call. Keyed camelCase to match the project's
## JSON/dictionary convention.
##
## `targetId` is the ADDRESSABLE id (`"kitchen.fridge"`), because that is the
## string the character echoes back in `arrived`/`interaction_ready` and the
## string a mission asked for. `localTargetId` carries the unqualified half.
## Every key added in Phase 2B is additive; the original six are unchanged, which
## is what keeps `little_buddy_character.gd` working untouched.
func describe(approach_from: Vector3) -> Dictionary:
	_ensure_resolved()
	var stand: Vector3 = get_stand_position(approach_from)
	var destination: Dictionary = get_destination()
	return {
		"targetId": get_semantic_id(),
		"semanticId": get_semantic_id(),
		"localTargetId": get_local_target_id(),
		"roomId": get_room_id(),
		"displayName": display_name,
		"enabled": target_enabled,
		"standPosition": stand,
		"facePosition": get_facing_position(stand),
		"arrivalRadius": arrival_radius,
		"supportedActions": get_supported_actions(),
		"requiredObject": get_required_object(),
		"levelTag": get_level_tag(),
		"missionTag": get_mission_tag(),
		"isDoor": is_door(),
		"toRoomId": String(destination["toRoomId"]),
		"toSpawnId": String(destination["toSpawnId"]),
	}


## The content-facing view: strings and bools only, no `Vector3` anywhere, so a
## mission or a validator can inspect a target without acquiring a 3D type.
func describe_semantics() -> Dictionary:
	_ensure_resolved()
	var destination: Dictionary = get_destination()
	return {
		"semanticId": get_semantic_id(),
		"roomId": get_room_id(),
		"targetId": get_local_target_id(),
		"displayName": display_name,
		"enabled": target_enabled,
		"supportedActions": get_supported_actions(),
		"requiredObject": get_required_object(),
		"levelTag": get_level_tag(),
		"missionTag": get_mission_tag(),
		"isDoor": is_door(),
		"toRoomId": String(destination["toRoomId"]),
		"toSpawnId": String(destination["toSpawnId"]),
	}


## -- Affordances (the `affordable` contract) -----------------------------------
##
## `get_affordance(actor)` is the whole of what `affordance_layer.gd` asks of a
## node in the `affordable` group. It returns `{}` when there is nothing to
## offer, otherwise:
##
##   `verb`      -- one of `AffordanceRules.VERBS`
##   `anchor`    -- world position the badge points at
##   `radius`    -- metres; the badge shows while the actor is this close
##   `priority`  -- int; higher wins a tie between overlapping offers
##   `target`    -- this node
##   `targetId`  -- the semantic id, for mission relevance and for tests
##   `extent`    -- half the footprint, metres, for the highlight ring
##
## There is deliberately NO `perform_affordance()` here: a tap on the badge
## falls through to the ordinary tap routing (`NavigationController.apply_tap`),
## so the character walks over and whatever already happens on arrival -- the
## director's kitchen verb, Free Play's word and reaction -- happens unchanged.
## A node that wants a tap to do something of its own (Bunny's hug) adds
## `perform_affordance(actor) -> bool` and returns true when it handled it.

## Installs the context provider. `provider` is `func(target, actor) -> Dictionary`.
func set_affordance_context_provider(provider: Callable) -> void:
	_ensure_resolved()
	_affordance_context = provider


func clear_affordance_context_provider() -> void:
	_ensure_resolved()
	_affordance_context = Callable()


func get_affordance(actor: Node3D) -> Dictionary:
	_ensure_resolved()
	if not target_enabled:
		return {}
	# A target that belongs to something which speaks for itself -- Bunny's
	# `child_actor.gd` answers the contract directly -- says nothing, or the
	# child would see two badges argue over one person.
	var owner_node: Node = get_parent()
	if owner_node != null and owner_node.has_method("get_affordance"):
		return {}
	var context: Dictionary = {}
	if _affordance_context.is_valid():
		var supplied: Variant = _affordance_context.call(self, actor)
		if supplied is Dictionary:
			context = supplied
	var verb: String = AffordanceRules.verb_for_target(describe_semantics(), context)
	if verb.is_empty():
		return {}
	return {
		"verb": verb,
		"anchor": get_affordance_anchor(),
		"radius": get_affordance_radius(),
		"priority": AffordanceRules.PRIORITY_DOOR if is_door() else AffordanceRules.PRIORITY_FURNITURE,
		"target": self,
		"targetId": get_semantic_id(),
		"extent": get_affordance_extent(),
	}


## Where the badge points: a little above the object's centre, so on a fridge
## it hangs by the handle and on a table it sits over the top.
func get_affordance_anchor() -> Vector3:
	_ensure_resolved()
	var here: Vector3 = SpatialUtil.world_position(self)
	var box: Vector3 = _tap_box_size()
	return here + Vector3(0.0, box.y * 0.25, 0.0)


func get_affordance_radius() -> float:
	_ensure_resolved()
	if affordance_radius > 0.0:
		return affordance_radius
	return get_affordance_extent() + AFFORDANCE_REACH


## Half the tap box's footprint, metres: how far the object reaches from its
## centre on the floor plane.
func get_affordance_extent() -> float:
	_ensure_resolved()
	var box: Vector3 = _tap_box_size()
	return maxf(box.x, box.z) * 0.5


func _tap_box_size() -> Vector3:
	for child: Node in get_children():
		if child is CollisionShape3D:
			var shape: Shape3D = (child as CollisionShape3D).shape
			if shape is BoxShape3D:
				return (shape as BoxShape3D).size
	return Vector3(0.4, 0.4, 0.4)
