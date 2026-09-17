extends RefCounted

## The BabyView3D public contract.
##
## `baby_room.gd` and every activity drop zone depend on exactly four methods,
## and the drop zones re-read the two position getters every frame. This case
## pins the parts that are easy to break silently while the game still runs:
##
##   1. The five view states are accepted and round-trip through
##      `get_view_state_name()`, and an unknown state degrades to idle rather
##      than crashing the baby mid-activity.
##   2. The mouth and chest are real marker NODES parented under the animated
##      `Body`/`Head`, at the offsets the room is composed around -- so the two
##      getters can keep deriving from live transforms instead of drifting into
##      hardcoded constants. Moving `Body` must move both points by the same
##      delta; a baked constant would not.
##   3. The baby stays the size and pose the nursery is built around: roughly
##      0.6-0.8 m tall, standing on y = 0, inside the play volume that
##      `nursery_props.tscn` is contractually required to keep clear.
##   4. Every AnimationPlayer track resolves to a real node. Track paths are
##      relative to the player's PARENT, so `Head:rotation:x` silently animates
##      nothing (Head is nested under Body) -- the clip still "plays", the baby
##      just stops reacting. This has shipped broken once already.
##   5. The face still has its two moving parts: the `Eyes` blink pivot closes
##      and reopens under `_process`, and the mouth swaps between the smile and
##      the open "o" so hungry/drinking do not wear a happy face.
##
## Note on the harness: under `--headless --script` the runner does everything
## in `SceneTree._initialize()`, where the root `Window` is not yet inside the
## tree. Nothing added there becomes "inside tree", `_ready()` never fires and
## `global_position` is unavailable -- so this case calls `_ready()` itself and
## works in the view's own local space. The global getters are additionally
## checked only if a live tree happens to be available.
##
## Scripts are loaded BY PATH, never by `class_name`: `--headless --script` does
## not rebuild `.godot/global_script_class_cache.cfg`.

const VIEW_PATH: String = "res://scripts/baby/baby_view_3d.gd"

const STATES: Array[String] = ["idle", "hungry", "drinking", "happy", "hugging"]

## Where the bottle and the teddy are aimed. Sourced from the values
## `baby_room.gd` documents as its fallbacks.
const EXPECTED_MOUTH: Vector3 = Vector3(0.0, 0.437, 0.18)
const EXPECTED_HUG: Vector3 = Vector3(0.0, 0.277, 0.20)
const POSITION_TOLERANCE: float = 0.04

## The volume nursery_props.tscn is required to leave empty.
const PLAY_VOLUME: AABB = AABB(Vector3(-0.8, 0.0, -0.4), Vector3(1.6, 1.0, 1.2))

const MIN_HEIGHT: float = 0.6
const MAX_HEIGHT: float = 0.8


func test_name() -> String:
	return "baby_view_3d"


func run():
	var failures: Array = []
	var script: GDScript = load(VIEW_PATH) as GDScript
	if script == null:
		return ["could not load %s" % VIEW_PATH]

	var view: Node3D = Node3D.new()
	view.set_script(script)
	view.call("_ready")

	failures.append_array(_test_api_surface(view))
	failures.append_array(_test_states(view))
	failures.append_array(_test_markers(view))
	failures.append_array(_test_markers_follow_the_body(view))
	failures.append_array(_test_fits_play_volume(view))
	failures.append_array(_test_animation_tracks_resolve(view))
	failures.append_array(_test_blink(view))
	failures.append_array(_test_mouth_changes_with_state(view))
	failures.append_array(_test_global_getters_if_tree_is_live(view))

	view.free()
	return failures


func _test_api_surface(view: Node3D) -> Array:
	var failures: Array = []
	for method: String in ["set_view_state", "get_view_state_name", "get_mouth_position", "get_hug_position"]:
		if not view.has_method(method):
			failures.append("BabyView3D no longer exposes %s()" % method)
	return failures


func _test_states(view: Node3D) -> Array:
	var failures: Array = []
	for state: String in STATES:
		view.call("set_view_state", state)
		var reported: String = String(view.call("get_view_state_name"))
		if reported != state:
			failures.append("set_view_state('%s') reports '%s'" % [state, reported])
	view.call("set_view_state", "not-a-state")
	var fallback: String = String(view.call("get_view_state_name"))
	if fallback != "idle":
		failures.append("an unknown state must fall back to idle, got '%s'" % fallback)
	view.call("set_view_state", "idle")
	return failures


func _test_markers(view: Node3D) -> Array:
	var failures: Array = []
	var mouth: Node3D = _find(view, "MouthMarker")
	var hug: Node3D = _find(view, "HugMarker")
	if mouth == null:
		failures.append("no MouthMarker node; get_mouth_position() has nothing live to read")
	if hug == null:
		failures.append("no HugMarker node; get_hug_position() has nothing live to read")
	if mouth == null or hug == null:
		return failures

	var mouth_local: Vector3 = _local_position(view, mouth)
	var hug_local: Vector3 = _local_position(view, hug)
	if mouth_local.distance_to(EXPECTED_MOUTH) > POSITION_TOLERANCE:
		failures.append("the mouth moved to %s; the drop zone is aimed at %s"
				% [str(mouth_local), str(EXPECTED_MOUTH)])
	if hug_local.distance_to(EXPECTED_HUG) > POSITION_TOLERANCE:
		failures.append("the chest moved to %s; the hug zone is aimed at %s"
				% [str(hug_local), str(EXPECTED_HUG)])
	if mouth_local.y <= hug_local.y:
		failures.append("the mouth (%.3f) must sit above the chest (%.3f)"
				% [mouth_local.y, hug_local.y])
	if mouth_local.z <= 0.0 or hug_local.z <= 0.0:
		failures.append("both points must face the camera (+Z): mouth z=%.3f hug z=%.3f"
				% [mouth_local.z, hug_local.z])
	return failures


## Both markers hang off the animated `Body`, which is what lets the getters be
## derived rather than baked. Re-parent or detach them and this fails.
func _test_markers_follow_the_body(view: Node3D) -> Array:
	var failures: Array = []
	var body: Node3D = _find(view, "Body")
	var mouth: Node3D = _find(view, "MouthMarker")
	var hug: Node3D = _find(view, "HugMarker")
	if body == null or mouth == null or hug == null:
		return ["BabyView3D lost its Body/MouthMarker/HugMarker structure"]

	var mouth_before: Vector3 = _local_position(view, mouth)
	var hug_before: Vector3 = _local_position(view, hug)
	var original: Vector3 = body.position
	var delta: Vector3 = Vector3(0.13, 0.07, -0.05)
	body.position = original + delta
	var mouth_after: Vector3 = _local_position(view, mouth)
	var hug_after: Vector3 = _local_position(view, hug)
	body.position = original

	if not (mouth_after - mouth_before).is_equal_approx(delta):
		failures.append("the mouth marker does not move with Body; it is no longer live")
	if not (hug_after - hug_before).is_equal_approx(delta):
		failures.append("the hug marker does not move with Body; it is no longer live")
	return failures


func _test_fits_play_volume(view: Node3D) -> Array:
	var failures: Array = []
	var box: AABB = _visual_aabb(view)
	if box.size == Vector3.ZERO:
		failures.append("the baby built no visible mesh")
		return failures

	if box.size.y < MIN_HEIGHT or box.size.y > MAX_HEIGHT:
		failures.append("the baby is %.3f m tall; the room is composed for %.1f-%.1f m"
				% [box.size.y, MIN_HEIGHT, MAX_HEIGHT])
	if absf(box.position.y) > 0.06:
		failures.append("the baby's feet are at y=%.3f; it must stand on the floor"
				% box.position.y)
	# Footprint only: the blobby legs settle a few centimetres below y = 0, which
	# is hidden under the floor plane and blocks nothing. What the nursery has to
	# keep clear is the ground area the baby occupies.
	var far: Vector3 = box.position + box.size
	if box.position.x < PLAY_VOLUME.position.x or far.x > PLAY_VOLUME.end.x \
			or box.position.z < PLAY_VOLUME.position.z or far.z > PLAY_VOLUME.end.z \
			or far.y > PLAY_VOLUME.end.y:
		failures.append("the baby (%s .. %s) escapes the play volume the nursery keeps clear (%s .. %s)"
				% [str(box.position), str(far), str(PLAY_VOLUME.position), str(PLAY_VOLUME.end)])
	return failures


## An animation whose track path points at nothing plays happily and animates
## nothing at all, so this can only be caught by resolving the paths. Paths are
## relative to the AnimationPlayer's parent, i.e. the view itself.
func _test_animation_tracks_resolve(view: Node3D) -> Array:
	var failures: Array = []
	var player: AnimationPlayer = null
	for child: Node in view.get_children():
		if child is AnimationPlayer:
			player = child as AnimationPlayer
			break
	if player == null:
		return ["BabyView3D has no AnimationPlayer; no state can animate"]

	var clips: PackedStringArray = player.get_animation_list()
	for state: String in STATES:
		if not player.has_animation(state):
			failures.append("no '%s' animation; that state will freeze" % state)
	for clip_name: String in clips:
		var anim: Animation = player.get_animation(clip_name)
		if anim.get_track_count() == 0:
			failures.append("animation '%s' has no tracks; it cannot move anything" % clip_name)
		for track: int in anim.get_track_count():
			var path: NodePath = anim.track_get_path(track)
			var target: Node = view.get_node_or_null(NodePath(path.get_concatenated_names()))
			if target == null:
				failures.append("animation '%s' track '%s' resolves to no node" % [clip_name, str(path)])
	return failures


## The blink is a `_process` timer, not an animation track, precisely so it
## survives every state change. Drive it by hand: the eyes must actually shut
## and then reopen all the way.
func _test_blink(view: Node3D) -> Array:
	var failures: Array = []
	var eyes: Node3D = _find(view, "Eyes")
	if eyes == null:
		return ["no Eyes pivot; the blink has nothing to close"]
	if not view.has_method("_process"):
		return ["BabyView3D lost _process(); the blink will never fire"]

	view.set("_blink_timer", 0.0)
	var closest: float = 1.0
	for step: int in 60:
		view.call("_process", 0.02)
		closest = minf(closest, eyes.scale.y)
	if closest > 0.5:
		failures.append("the eyes never closed; narrowest scale.y was %.2f" % closest)
	if not is_equal_approx(eyes.scale.y, 1.0):
		failures.append("the eyes did not reopen; scale.y settled at %.2f" % eyes.scale.y)
	return failures


## Hungry and drinking must not wear the same face as happy.
func _test_mouth_changes_with_state(view: Node3D) -> Array:
	var failures: Array = []
	var smile: Node3D = _find(view, "Smile")
	var open_mouth: Node3D = _find(view, "MouthOpen")
	if smile == null or open_mouth == null:
		return ["the mouth lost its Smile/MouthOpen shapes; every state looks identical"]

	for state: String in ["hungry", "drinking"]:
		view.call("set_view_state", state)
		if not open_mouth.visible or smile.visible:
			failures.append("'%s' must show the open mouth, not the smile" % state)
	for state: String in ["idle", "happy", "hugging"]:
		view.call("set_view_state", state)
		if not smile.visible or open_mouth.visible:
			failures.append("'%s' must show the smile, not the open mouth" % state)
	view.call("set_view_state", "idle")
	return failures


## Opportunistic: only meaningful under a runner with a live scene tree.
func _test_global_getters_if_tree_is_live(view: Node3D) -> Array:
	var failures: Array = []
	if not view.is_inside_tree():
		return failures
	var mouth_before: Vector3 = view.call("get_mouth_position")
	var hug_before: Vector3 = view.call("get_hug_position")
	var delta: Vector3 = Vector3(0.37, 0.11, -0.23)
	var original: Vector3 = view.position
	view.position = original + delta
	var mouth_after: Vector3 = view.call("get_mouth_position")
	var hug_after: Vector3 = view.call("get_hug_position")
	view.position = original
	if not (mouth_after - mouth_before).is_equal_approx(delta):
		failures.append("get_mouth_position() did not follow the node; it looks hardcoded")
	if not (hug_after - hug_before).is_equal_approx(delta):
		failures.append("get_hug_position() did not follow the node; it looks hardcoded")
	return failures


## Position of `node` expressed in `root`'s local space, composed from the live
## transforms -- the tree-free equivalent of `global_position`.
func _local_position(root: Node3D, node: Node3D) -> Vector3:
	return _local_transform(root, node).origin


func _local_transform(root: Node3D, node: Node3D) -> Transform3D:
	var accumulated: Transform3D = Transform3D()
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			accumulated = (current as Node3D).transform * accumulated
		current = current.get_parent()
	return accumulated


func _visual_aabb(view: Node3D) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for instance: MeshInstance3D in _mesh_instances(view):
		if instance.mesh == null:
			continue
		var local: AABB = _local_transform(view, instance) * instance.mesh.get_aabb()
		if first:
			box = local
			first = false
		else:
			box = box.merge(local)
	return box


func _find(root: Node, node_name: String) -> Node3D:
	if root.name == node_name and root is Node3D:
		return root as Node3D
	for child: Node in root.get_children():
		var found: Node3D = _find(child, node_name)
		if found != null:
			return found
	return null


func _mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for child: Node in node.get_children():
		out.append_array(_mesh_instances(child))
	return out
