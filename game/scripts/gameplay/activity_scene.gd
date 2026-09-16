class_name ActivityScene
extends Node3D

## Per-category staging area: the drop zones and object anchor points a category
## needs, and nothing else.
##
## Explicitly contains NO `Camera3D`, NO `DirectionalLight3D` and NO
## `WorldEnvironment` -- `nursery_props.tscn` owns the single directional light
## and the environment, and `baby_room.tscn` owns the camera. Adding a second
## light here would be a regression against the lighting budget in
## INTEGRATION_CONTRACT.md.
##
## Usage from the Baby Room:
##
## ```gdscript
## var activity := load("res://scenes/activities/feeding.tscn").instantiate()
## add_child(activity)
## activity.attach_baby(%BabyView)                     # zones follow the baby
## runner.start_mission("feedingTime", library, activity.build_context())
## ```

const DROP_ZONE_SCRIPT_PATH: String = "res://scripts/gameplay/drop_zone.gd"

const OBJECT_ANCHOR_NAME: String = "ObjectAnchor"

@export var category_id: String = ""

var _baby_view: Node = null
var _zones: Dictionary = {}
var _anchor: Node3D = null
var _resolved: bool = false


func _ready() -> void:
	_ensure_resolved()


func _process(_delta: float) -> void:
	# Two Vector3 reads per baby-anchored zone. Keeps the mouth/chest/hand zones
	# glued to `BabyView3D` even if VISUAL changes the baby's proportions --
	# positions are read from the baby, never hardcoded.
	if _baby_view == null:
		return
	for zone: Variant in _zones.values():
		if zone is Node and (zone as Node).has_method("update_from_baby"):
			(zone as Node).call("update_from_baby", _baby_view)


## -- Public API ---------------------------------------------------------------

func get_category_id() -> String:
	return category_id


## The `BabyView3D` whose `get_mouth_position()`/`get_hug_position()` the
## baby-anchored zones track.
func attach_baby(baby_view: Node) -> void:
	_ensure_resolved()
	_baby_view = baby_view
	if _baby_view != null:
		for zone: Variant in _zones.values():
			if zone is Node and (zone as Node).has_method("update_from_baby"):
				(zone as Node).call("update_from_baby", _baby_view)


func get_object_anchor() -> Node3D:
	_ensure_resolved()
	return _anchor


## Positions of the `ObjectAnchor`'s `Marker3D` children, left to right, used as
## the spawn row for the current task's choices.
func get_spawn_points() -> Array:
	_ensure_resolved()
	var points: Array = []
	if _anchor == null:
		return points
	var markers: Array = []
	for child: Node in _anchor.get_children():
		if child is Marker3D:
			markers.append(child)
	markers.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.position.x < b.position.x)
	for marker: Variant in markers:
		points.append((marker as Node3D).position)
	return points


func get_drop_zones() -> Dictionary:
	_ensure_resolved()
	return _zones.duplicate()


func get_drop_zone(zone_id: String) -> Node:
	_ensure_resolved()
	var zone: Variant = _zones.get(zone_id, null)
	if zone is Node:
		return zone as Node
	return null


func has_drop_zone(zone_id: String) -> bool:
	_ensure_resolved()
	return _zones.has(zone_id)


## The context dictionary consumed by `MissionRunner` / `ModeHandler`.
func build_context(extra: Dictionary = {}) -> Dictionary:
	_ensure_resolved()
	var context: Dictionary = {
		"objectAnchor": _anchor,
		"spawnPoints": get_spawn_points(),
		"dropZones": get_drop_zones(),
	}
	for key: Variant in extra.keys():
		context[key] = extra[key]
	return context


## -- Internals ------------------------------------------------------------------

## Resolves the anchor and the zone index on first use rather than in `_ready()`.
## The Baby Room may call `build_context()` / `attach_baby()` before the scene has
## entered the tree (and the headless test runner never enters it at all), and a
## caller must never get an empty context just because of call ordering.
func _ensure_resolved() -> void:
	if _resolved:
		return
	_resolved = true
	_anchor = get_node_or_null(OBJECT_ANCHOR_NAME) as Node3D
	if _anchor == null:
		_anchor = Node3D.new()
		_anchor.name = OBJECT_ANCHOR_NAME
		add_child(_anchor)
	_index_zones()


func _index_zones() -> void:
	_zones = {}
	for child: Node in get_children():
		if not child.has_method("get_zone_id"):
			continue
		var zone_id: String = String(child.call("get_zone_id"))
		if zone_id.is_empty():
			continue
		_zones[zone_id] = child
