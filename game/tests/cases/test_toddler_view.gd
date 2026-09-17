extends RefCounted

## The toddler placeholder, held to `docs/ART_BIBLE_DRAFT.md` §4 and contract §7.
##
## Most of what matters about a character cannot be asserted, and this file does
## not pretend otherwise -- the poses were judged by rendering them and looking.
## What it pins down is the narrow set of visual properties that are *checkable*
## and that have already gone wrong once in this project or in this session:
##
##   * **The smile is a smile.** `ART_UPGRADE_REPORT.md` records a mouth that
##     shipped as a perfect frown from an inverted rotation sign and survived
##     three render passes. The mouth is now generated as the bottom arc of a
##     circle, and this asserts that its middle really is its lowest point.
##   * **Every clip keys every animated property.** Found in the first render:
##     `eat` had no leg tracks, so it played with the legs still mid-stride from
##     `walk`, and `sit` had no `Body:rotation` track, so it played while the
##     child was still flat on his back from `sleep`. Silent in every assertion.
##   * **Track paths resolve.** A mistyped `NodePath` in an `Animation` is not an
##     error; the track simply does nothing, forever.
##   * **The art rules that are numbers**: the triangle budget, `#000000` banned,
##     eyes below the head midline, exactly one catchlight per eye and on the
##     same side of both.
##   * **The unauthored actions stay unauthored.** They are what keeps the
##     graceful-degradation path live in the shipped build.

const ToddlerView := preload("res://scripts/character/toddler_view.gd")

## Contract §7 budget for a character. Under is fine; over is not.
const MAX_TRIANGLES: int = 4000
## Anti-vacuity: a view that built almost nothing would otherwise pass.
const MIN_TRIANGLES: int = 1500

const CLIPS_THAT_MUST_EXIST: Array[String] = [
	"idle", "walk", "carryIdle", "eat", "drink", "hug", "sit", "stand",
	"sleep", "wake", "celebrate",
]

## Deliberately NOT animated -- see the view's class doc. `brushTeeth` is also
## pinned by `test_house_world.gd`.
const CLIPS_THAT_MUST_NOT_EXIST: Array[String] = [
	"brushTeeth", "wave", "point", "clap", "pickUp", "give",
]

## Postures loop, because they persist until released. Events do not, because
## a one-shot that loops never visibly ends.
const LOOPING_CLIPS: Array[String] = ["idle", "walk", "carryIdle", "sit", "sleep"]

## Every property any clip animates. Hard-coded rather than read back from the
## view, so that renaming a node there without updating every clip fails here.
const ANIMATED_PROPERTIES: Array[String] = [
	"Body:position",
	"Body:rotation",
	"Body/Torso:rotation",
	"Body/Torso:scale",
	"Body/Torso/Head:rotation",
	"Body/Torso/Head/Mouth:scale",
	"Body/Torso/ArmLeft:rotation",
	"Body/Torso/ArmRight:rotation",
	"Body/LegLeft:rotation",
	"Body/LegRight:rotation",
	"Body/Torso/Head/EyeLeft:scale",
	"Body/Torso/Head/EyeRight:scale",
]

## `#000000` is banned everywhere (contract §7). Nothing on the child may be
## darker than `ink`, which is the only "dark" the palette has.
const INK_LUMINANCE: float = 0.26


func test_name() -> String:
	return "toddler_view"


func run():
	var failures: Array = []
	var view: Node3D = ToddlerView.new()
	view.call("build")

	failures.append_array(_test_scale_and_budget(view))
	failures.append_array(_test_palette(view))
	failures.append_array(_test_face(view))
	failures.append_array(_test_the_smile_is_a_smile(view))
	failures.append_array(_test_clip_inventory(view))
	failures.append_array(_test_every_track_resolves(view))
	failures.append_array(_test_no_clip_leaves_a_pose_behind(view))
	failures.append_array(_test_form_language(view))

	view.free()
	return failures


## Contract §3 dimensions the whole house against `HEIGHT`; §7 caps the budget.
func _test_scale_and_budget(view: Node3D):
	var failures: Array = []
	if not is_equal_approx(ToddlerView.HEIGHT, 0.85):
		failures.append("the toddler must stay 0.85 m -- every room, door and camera in the "
				+ "house is dimensioned against it; got %.2f" % ToddlerView.HEIGHT)

	var top: float = -INF
	var bottom: float = INF
	for mesh: MeshInstance3D in _meshes(view):
		var box: AABB = _local_aabb(mesh, view)
		top = maxf(top, box.position.y + box.size.y)
		bottom = minf(bottom, box.position.y)
	if absf(top - ToddlerView.HEIGHT) > 0.06:
		failures.append("the built body is %.3f m tall but HEIGHT says %.2f; the constant the "
				% [top, ToddlerView.HEIGHT] + "house is built against would be a lie")
	if bottom < -0.03:
		failures.append("the child extends %.3f m below the floor plane in his rest pose" % bottom)

	var triangles: int = int(view.call("count_triangles"))
	if triangles > MAX_TRIANGLES:
		failures.append("the placeholder is %d triangles, over the %d character budget; Godot's "
				% [triangles, MAX_TRIANGLES]
				+ "primitive defaults alone would be ~4,000 for one sphere")
	if triangles < MIN_TRIANGLES:
		failures.append("only %d triangles were built; the view is not building a body" % triangles)
	return failures


## Contract §7: pure black is banned everywhere, roughness 0.85-1.0, metallic 0.
## And §4.2 bans a specular highlight on skin, which is what metallic would give.
func _test_palette(view: Node3D):
	var failures: Array = []
	var materials: Dictionary = {}
	for mesh: MeshInstance3D in _meshes(view):
		var material: Material = mesh.material_override
		if material == null:
			failures.append("%s has no material" % mesh.name)
			continue
		if not (material is StandardMaterial3D):
			failures.append("%s uses an unexpected material type" % mesh.name)
			continue
		var standard := material as StandardMaterial3D
		materials[standard.get_instance_id()] = true
		var colour: Color = standard.albedo_color
		if _luminance(colour) < INK_LUMINANCE:
			failures.append("%s is %s, darker than ink #59422B. Pure black is banned everywhere "
					% [mesh.name, colour.to_html(false)]
					+ "in this game -- it reads as a hole in a pastel scene")
		if standard.roughness < 0.85 or standard.roughness > 1.0:
			failures.append("%s has roughness %.2f, outside the 0.85-1.0 band"
					% [mesh.name, standard.roughness])
		if standard.metallic > 0.0:
			failures.append("%s is metallic; there is no real metal in this game" % mesh.name)

	# Materials are shared by colour, not created per mesh.
	if materials.size() > 12:
		failures.append("the child uses %d distinct materials; they should be cached per colour"
				% materials.size())
	return failures


## §4.2, the parts of the face that are numbers.
func _test_face(view: Node3D):
	var failures: Array = []
	var head: Node3D = view.get_node_or_null("Body/Torso/Head") as Node3D
	if head == null:
		return ["the head is missing"]

	for side: String in ["Left", "Right"]:
		var eye: Node3D = head.get_node_or_null("Eye%s" % side) as Node3D
		if eye == null:
			failures.append("Eye%s is missing" % side)
			continue
		# "Set BELOW the vertical midline" -- the head pivot IS the midline.
		if eye.position.y >= 0.0:
			failures.append("Eye%s sits at y=%.3f, on or above the head's midline. Eyes set high "
					% [side, eye.position.y]
					+ "read as an adult face; §4.2 puts them below it")
		# "Large": ~20% of head width.
		var iris: MeshInstance3D = eye.get_node_or_null("Iris") as MeshInstance3D
		if iris == null:
			failures.append("Eye%s has no iris" % side)
		else:
			var width: float = ToddlerView.EYE_RADIUS * 2.0 * iris.scale.x
			var fraction: float = width / (ToddlerView.HEAD_RADIUS * 2.0)
			if fraction < 0.15 or fraction > 0.28:
				failures.append("Eye%s is %.0f%% of the head width; §4.2 wants roughly 20%%"
						% [side, fraction * 100.0])

		# "Exactly ONE white circle, upper-left of each eye."
		var lights: int = 0
		for child: Node in eye.get_children():
			if String(child.name).begins_with("Catchlight"):
				lights += 1
		if lights != 1:
			failures.append("Eye%s has %d catchlights; §4.2 says exactly one. It is the single "
					% [side, lights] + "highest-value detail on the character")

	# Both catchlights on the same side, and that side is the viewer's LEFT.
	# The child faces -Z, so a viewer looking at his face stands at -Z; for that
	# viewer world +X is on the left. A negative offset here would put the
	# highlight on the wrong side of the face, which no test would otherwise see.
	if ToddlerView.CATCHLIGHT_OFFSET.x <= 0.0:
		failures.append("the catchlight is offset to world -X, which is the viewer's RIGHT. "
				+ "§4.2 puts it upper-left; see the constant's comment for the derivation")
	if ToddlerView.CATCHLIGHT_OFFSET.y <= 0.0:
		failures.append("the catchlight is not in the UPPER half of the eye")

	# "Soft blush ... always at least 0.3 weight -- it is part of the resting face."
	for side: String in ["Left", "Right"]:
		if head.get_node_or_null("Blush%s" % side) == null:
			failures.append("Blush%s is missing; blush is part of the RESTING face, not an "
					% side + "expression that gets switched on")
	return failures


## The frown guard, on the generated geometry rather than on three loose parts.
func _test_the_smile_is_a_smile(view: Node3D):
	var failures: Array = []
	var smile: MeshInstance3D = view.get_node_or_null("Body/Torso/Head/Mouth/Smile") as MeshInstance3D
	if smile == null or smile.mesh == null:
		return ["the mouth is missing"]

	var vertices: PackedVector3Array = smile.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if vertices.size() < 8:
		return ["the mouth mesh has only %d vertices" % vertices.size()]

	var middle_y: float = INF
	var corner_y: float = -INF
	var widest: float = 0.0
	for vertex: Vector3 in vertices:
		widest = maxf(widest, absf(vertex.x))
		if absf(vertex.x) < 0.006:
			middle_y = minf(middle_y, vertex.y)
	for vertex: Vector3 in vertices:
		if absf(vertex.x) > widest * 0.9:
			corner_y = maxf(corner_y, vertex.y)

	if not (corner_y > middle_y + 0.004):
		failures.append(("the mouth corners sit at y=%.4f and its middle at y=%.4f. A mouth whose "
				+ "corners are not clearly HIGHER than its middle is not a smile -- this is the "
				+ "frown that shipped once already and survived three render passes")
				% [corner_y, middle_y])

	var width: float = widest * 2.0
	var fraction: float = width / (ToddlerView.HEAD_RADIUS * 2.0)
	if fraction < 0.12 or fraction > 0.40:
		failures.append("the mouth is %.0f%% of the head width, which will not read" % (fraction * 100.0))

	# The mouth must sit in front of the face, not inside it.
	for vertex: Vector3 in vertices:
		if vertex.z > -0.02:
			failures.append("a mouth vertex at z=%.3f is inside the head" % vertex.z)
			break
	return failures


func _test_clip_inventory(view: Node3D):
	var failures: Array = []
	var player: AnimationPlayer = view.call("get_animation_player")
	if player == null:
		return ["the toddler view exposes no AnimationPlayer"]

	for clip: String in CLIPS_THAT_MUST_EXIST:
		if not player.has_animation(clip):
			failures.append("the '%s' clip is missing" % clip)
	for clip: String in CLIPS_THAT_MUST_NOT_EXIST:
		if player.has_animation(clip):
			failures.append(("'%s' is now animated. That is not automatically wrong, but it was "
					+ "deliberately left unauthored so the graceful-degradation path stays live "
					+ "in the SHIPPED build rather than only in a test fixture. If this is "
					+ "intentional, move it out of CLIPS_THAT_MUST_NOT_EXIST and check "
					+ "test_house_world.gd, which pins 'brushTeeth'.") % clip)

	for clip: String in CLIPS_THAT_MUST_EXIST:
		if not player.has_animation(clip):
			continue
		var animation: Animation = player.get_animation(clip)
		var loops: bool = animation.loop_mode != Animation.LOOP_NONE
		if LOOPING_CLIPS.has(clip) and not loops:
			failures.append("'%s' is a posture or a cycle and must loop" % clip)
		if not LOOPING_CLIPS.has(clip) and loops:
			failures.append("'%s' is a one-shot; looping it means it never visibly ends" % clip)
		if animation.length <= 0.1:
			failures.append("'%s' is %.2f s long, which is not an animation" % [clip, animation.length])
	return failures


## A mistyped NodePath in an Animation is not an error -- the track silently does
## nothing, forever. Nothing else in the project would ever notice.
func _test_every_track_resolves(view: Node3D):
	var failures: Array = []
	var player: AnimationPlayer = view.call("get_animation_player")
	if player == null:
		return []
	var checked: int = 0
	for clip: String in player.get_animation_list():
		var animation: Animation = player.get_animation(clip)
		for index: int in range(animation.get_track_count()):
			checked += 1
			var path: String = String(animation.track_get_path(index))
			var node_path: String = path.get_slice(":", 0)
			var property: String = path.get_slice(":", 1)
			var node: Node = view.get_node_or_null(NodePath(node_path))
			if node == null:
				failures.append("'%s' animates '%s', which is not a node in the toddler. The "
						% [clip, node_path] + "track would silently do nothing forever")
			elif not property.is_empty() and not (property in ["position", "rotation", "scale"]):
				failures.append("'%s' animates the unexpected property '%s'" % [clip, property])
	if checked < 50:
		failures.append("only %d tracks were checked; this guard is not seeing the clips" % checked)
	return failures


## An `AnimationPlayer` writes only the properties a clip has tracks for. It does
## NOT restore the others, so a clip that omits one inherits whatever the last
## clip left there. Both bugs this caught were invisible until rendered.
func _test_no_clip_leaves_a_pose_behind(view: Node3D):
	var failures: Array = []
	var player: AnimationPlayer = view.call("get_animation_player")
	if player == null:
		return []
	for clip: String in player.get_animation_list():
		var animation: Animation = player.get_animation(clip)
		var present: Dictionary = {}
		for index: int in range(animation.get_track_count()):
			present[String(animation.track_get_path(index))] = true
		for path: String in ANIMATED_PROPERTIES:
			if not present.has(path):
				failures.append(("'%s' has no track for '%s'. Every clip must say something "
						+ "about every animated property, or it plays with that part of the body "
						+ "still posed by whatever ran before it -- `sit` after `sleep` folded "
						+ "the child into the floor.") % [clip, path])
	return failures


## §4.1: rounded volumes, mitt hands, no separated fingers, oversized feet, and a
## silhouette in which the head, both arms and both legs are separately readable.
func _test_form_language(view: Node3D):
	var failures: Array = []
	for required: String in [
		"Body/LegLeft/Foot", "Body/LegRight/Foot",
		"Body/Torso/ArmLeft/Hand", "Body/Torso/ArmRight/Hand",
		"Body/Torso/Head/HairCap", "Body/Torso/Neck",
	]:
		if view.get_node_or_null(required) == null:
			failures.append("%s is missing" % required)

	for side: String in ["Left", "Right"]:
		var hand: Node = view.get_node_or_null("Body/Torso/Arm%s/Hand" % side)
		if hand != null and hand.get_child_count() > 0:
			failures.append("Hand%s has children; §4.1 bans separated fingers at this age -- a "
					% side + "hand is one soft mitt with at most a suggested thumb")

	# Every visible part is a rounded volume. A box anywhere on the body is the
	# single strongest "this is a prototype" signal (§4.1, §6).
	for mesh: MeshInstance3D in _meshes(view):
		if mesh.mesh is BoxMesh or mesh.mesh is PlaneMesh or mesh.mesh is PrismMesh:
			failures.append("%s is a flat-sided primitive; the form language is rounded volumes "
					% mesh.name + "only, with no hard edges anywhere on the body")

	# Feet are ~1.15x naturalistic: wider and longer than the leg they hang from.
	if ToddlerView.FOOT_SIZE.z <= ToddlerView.LEG_RADIUS * 1.2:
		failures.append("the feet are not oversized; §4.1 wants them toy-like and stable")
	return failures


## -- Helpers -------------------------------------------------------------------

func _meshes(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(_meshes(child))
	return found


## `global_transform` asserts `is_inside_tree()`, and nothing is in the tree in
## the headless runner, so the transform is accumulated by hand.
func _local_aabb(mesh: MeshInstance3D, root: Node) -> AABB:
	var transform := Transform3D.IDENTITY
	var node: Node = mesh
	while node != null and node != root:
		if node is Node3D:
			transform = (node as Node3D).transform * transform
		node = node.get_parent()
	return transform * mesh.mesh.get_aabb()


func _luminance(colour: Color) -> float:
	return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b
