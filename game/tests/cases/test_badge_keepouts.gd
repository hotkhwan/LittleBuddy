extends RefCounted

## THE BADGE NEVER COVERS A FACE -- on real frames of the real house.
##
## `test_affordance.gd` proves `place_badge()` on rectangles. This case proves
## the same thing on `house_world.tscn`, with the real camera, the real Aliz,
## the real Bunny and the real fridge, at the three frames the game ships at
## (1334x750, 2340x1080, 1366x1024), the way `test_tutor_scene.gd::
## _test_nothing_covers_alizs_face` does for the tutor HUD. Three frames each:
##
##   bunny     Aliz on Bunny's interaction point: CARRY (or HUG)
##   fridge    Aliz at the shut fridge: OPEN
##   carrying  Bunny in her arms, at the bed: PLACE
##
## and in every one the DRAWN badge (disc + pill, `layout_rects().footprint`)
## must clear Aliz's face, Bunny's face (standing or in her arms), his speech
## bubble and the target's own silhouette -- all four measured here, from the
## camera, independently of the layer's own keep-out maths -- while the HIT
## BOX must clear every control the layer was told about (the thumbstick,
## Home) and still be at least 240 px.
##
## The world is hosted in a `SubViewport` of the frame's exact size so the
## camera unprojects into that frame; nothing is rendered.

const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"
const LayerScript := preload("res://scripts/interaction/affordance_layer.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")

const SIZES: Array = [Vector2i(1334, 750), Vector2i(2340, 1080), Vector2i(1366, 1024)]
const MODE_FREE_PLAY: int = 1
const DT: float = 1.0 / 60.0

## Aliz's head band, metres above her feet, and Bunny's (0.78 m tall, head top
## at 0.72). Stated here, not read off the layer, so the layer cannot pass by
## agreeing with itself.
const ALIZ_FACE_BOTTOM: float = 1.25
const ALIZ_FACE_TOP: float = 1.72
const ALIZ_FACE_HALF_WIDTH: float = 0.2
const BUNNY_FACE_BOTTOM: float = 0.5
const BUNNY_FACE_TOP: float = 0.76
const BUNNY_FACE_HALF_WIDTH: float = 0.15


func test_name() -> String:
	return "badge_keepouts"


func run():
	var failures: Array = []
	for size: Vector2i in SIZES:
		failures.append_array(_frames_at(size))
	return failures


## -- The stage --------------------------------------------------------------------

func _open(size: Vector2i) -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or not ResourceLoader.exists(HOUSE_SCENE):
		return {}
	var packed: Resource = load(HOUSE_SCENE)
	if not (packed is PackedScene):
		return {}
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	tree.root.add_child(viewport)
	var world: Node = (packed as PackedScene).instantiate()
	world.call("set_progression_mode", MODE_FREE_PLAY)
	viewport.add_child(world)
	world.call("build_world")
	var director: Node = world.call("ensure_free_play_director")
	if director != null and director.has_method("is_running") and not bool(director.call("is_running")):
		director.call("start")
	var hud: Control = director.call("get_hud") if director != null and director.has_method("get_hud") else null
	if hud != null:
		hud.call("refresh_presentation")
	var layer: Control = world.call("get_affordance_layer")
	var aliz: Node3D = world.call("get_character")
	if layer != null:
		# Outside a live tree nothing joins the `affordable` group, the layer
		# cannot ask its viewport for a camera or a size, and anchors never
		# resolve: hand it all three, the same values the tree would.
		layer.call("set_camera", world.call("get_camera"))
		layer.size = Vector2(size)
		var affordables: Array = []
		_collect_affordables(world, affordables)
		layer.call("set_candidate_sources", affordables)
	return {"tree": tree, "viewport": viewport, "world": world, "layer": layer, "aliz": aliz,
			"hud": hud, "size": Vector2(size)}


## Every node under `node` that speaks the affordance contract -- what the
## `affordable` group would hold in a running game.
func _collect_affordables(node: Node, into: Array) -> void:
	if node.has_method("get_affordance"):
		into.append(node)
	for child: Node in node.get_children():
		_collect_affordables(child, into)


func _close(stage: Dictionary) -> void:
	if stage.is_empty():
		return
	var viewport: SubViewport = stage["viewport"]
	var tree: SceneTree = stage["tree"]
	if viewport.get_parent() == tree.root:
		tree.root.remove_child(viewport)
	viewport.free()


func _bunny_in(world: Node) -> Node3D:
	var room: Node = world.call("get_current_room")
	if room == null:
		return null
	for child: Node in room.get_children():
		if child.has_method("set_carried_by") and child.has_method("satisfy"):
			return child
	return null


## Teleports Aliz to the authored stand position of `semantic_id`, facing it.
func _stand_at(stage: Dictionary, semantic_id: String) -> bool:
	var world: Node = stage["world"]
	var aliz: Node3D = stage["aliz"]
	var target: Node = world.call("get_target_by_semantic_id", semantic_id)
	if target == null or aliz == null:
		return false
	var here: Vector3 = SpatialUtil.world_position(aliz)
	var stand: Vector3 = target.call("get_stand_position", here)
	SpatialUtil.set_world_position(aliz, stand)
	var face: Vector3 = target.call("get_facing_position", stand)
	aliz.rotation.y = NavMath.yaw_towards(stand, face, aliz.rotation.y)
	return true


## Runs the frame: Bunny's own step (his bubble follows her), the camera's,
## the HUD's keep-outs, then the layer, several times so the placement dwell
## has settled on a side.
func _step(stage: Dictionary, frames: int = 6) -> void:
	var world: Node = stage["world"]
	var layer: Control = stage["layer"]
	var hud: Control = stage["hud"]
	var camera: Camera3D = world.call("get_camera")
	var bunny: Node3D = _bunny_in(world)
	# Rooms respawn their props on entry: poll what exists now.
	var affordables: Array = []
	_collect_affordables(world, affordables)
	layer.call("set_candidate_sources", affordables)
	for _i: int in range(frames):
		if bunny != null and bunny.has_method("step"):
			bunny.call("step", DT)
		if camera != null and camera.has_method("step"):
			camera.call("step", DT)
		if hud != null:
			hud.call("refresh_presentation")
		layer.call("step", DT)


## -- Measuring, from the camera -------------------------------------------------------

## Projected BY HAND (`Projection.create_perspective` + the camera's transform,
## the way `tutor_scene.gd::project_point()` does it), because the headless
## runner's root is not an active tree and `Camera3D.unproject_position()`
## refuses there. This is the independent measurement the layer is held to.
func _project(camera: Camera3D, points: Array, view: Vector2) -> Rect2:
	var aspect: float = view.x / maxf(view.y, 1.0)
	var projection: Projection = Projection.create_perspective(camera.fov, aspect, camera.near, camera.far, false)
	var inverse: Transform3D = SpatialUtil.world_transform(camera).affine_inverse()
	var rect: Rect2 = Rect2()
	var first: bool = true
	for point: Vector3 in points:
		var local: Vector3 = inverse * point
		if -local.z < camera.near:
			return Rect2()
		var clip: Vector4 = projection * Vector4(local.x, local.y, local.z, 1.0)
		if is_zero_approx(clip.w):
			return Rect2()
		var ndc: Vector2 = Vector2(clip.x, clip.y) / clip.w
		var at: Vector2 = Vector2((ndc.x + 1.0) * 0.5 * view.x, (1.0 - ndc.y) * 0.5 * view.y)
		if first:
			rect = Rect2(at, Vector2.ZERO)
			first = false
		else:
			rect = rect.expand(at)
	return rect


## A camera-facing band `bottom`..`top` above `foot`, `half_w` either side.
func _face_rect(stage: Dictionary, foot: Vector3, bottom: float, top: float, half_w: float) -> Rect2:
	var camera: Camera3D = (stage["world"] as Node).call("get_camera")
	var right: Vector3 = SpatialUtil.world_transform(camera).basis.x
	return _project(camera, [
		foot + Vector3(0.0, bottom, 0.0) - right * half_w, foot + Vector3(0.0, bottom, 0.0) + right * half_w,
		foot + Vector3(0.0, top, 0.0) - right * half_w, foot + Vector3(0.0, top, 0.0) + right * half_w,
	], stage["size"])


## The eight corners of a target's tap box, projected.
func _silhouette(stage: Dictionary, target: Node) -> Rect2:
	if not (target is Node3D):
		return Rect2()
	var camera: Camera3D = (stage["world"] as Node).call("get_camera")
	for child: Node in target.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			var half: Vector3 = ((child as CollisionShape3D).shape as BoxShape3D).size * 0.5
			var xform: Transform3D = SpatialUtil.world_transform(child as Node3D)
			var corners: Array = []
			for sx: float in [-1.0, 1.0]:
				for sy: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						corners.append(xform * Vector3(half.x * sx, half.y * sy, half.z * sz))
			return _project(camera, corners, stage["size"])
	return Rect2()


## The common checks for one frame. `faces` is `{name: Rect2}`; empty rects are
## skipped (a face behind the camera is not on the screen to cover).
func _check_frame(stage: Dictionary, label: String, verbs: Array, faces: Dictionary, silhouette: Rect2) -> Array:
	var failures: Array = []
	var layer: Control = stage["layer"]
	var size: Vector2 = stage["size"]
	var tag: String = "%s at %dx%d" % [label, int(size.x), int(size.y)]
	var verb: String = String(layer.call("get_current_verb"))
	if not verbs.has(verb):
		return ["%s: the layer shows '%s', expected one of %s" % [tag, verb, str(verbs)]]
	if not bool(layer.call("is_laid_out")):
		return ["%s: the badge was not laid out (no camera in the frame?)" % tag]
	var rects: Dictionary = layer.call("get_layout_rects")
	var footprint: Rect2 = rects["footprint"]
	var disc: Rect2 = rects["disc"]
	var hit: Rect2 = rects["hit"]
	var screen: Rect2 = Rect2(Vector2.ZERO, size)
	if not screen.encloses(footprint):
		failures.append("%s: the badge %s leaves the screen" % [tag, str(footprint)])
	if hit.size.x < 239.5 or hit.size.y < 239.5:  # Control sizes round-trip through float32 offsets
		failures.append("%s: the hit box %s is under 240 px" % [tag, str(hit)])
	if not hit.encloses(disc):
		failures.append("%s: the hit box %s does not cover the disc %s" % [tag, str(hit), str(disc)])
	var scale: float = LayerScript.badge_scale(size.y)
	if absf(disc.size.x - (LayerScript.DISC_DIAMETER + LayerScript.OUTLINE_PX * 2.0) * scale) > 1.0:
		failures.append("%s: the disc is %.0f px; %.0f px was expected at this height"
				% [tag, disc.size.x, (LayerScript.DISC_DIAMETER + LayerScript.OUTLINE_PX * 2.0) * scale])
	for name: String in faces.keys():
		var face: Rect2 = faces[name]
		if face.size.x <= 0.0 or face.size.y <= 0.0:
			continue
		if footprint.intersects(face):
			failures.append("%s: the %s badge %s covers %s %s" % [tag, verb, str(footprint), name, str(face)])
	if silhouette.size.x > 0.0 and footprint.intersects(silhouette):
		failures.append("%s: the %s badge %s sits on the target's silhouette %s" % [tag, verb, str(footprint), str(silhouette)])
	var bubble: Rect2 = layer.call("get_bubble_keep_out")
	if bubble.size.x > 0.0 and footprint.intersects(bubble):
		failures.append("%s: the badge %s covers the speech bubble %s" % [tag, str(footprint), str(bubble)])
	for blocked: Rect2 in (layer.call("get_keep_out_rects") as Array):
		if hit.intersects(blocked):
			failures.append("%s: the hit box %s covers a control %s" % [tag, str(hit), str(blocked)])
	return failures


## -- The three frames -----------------------------------------------------------------

func _frames_at(size: Vector2i) -> Array:
	var failures: Array = []
	var stage: Dictionary = _open(size)
	if stage.is_empty() or stage["layer"] == null or stage["aliz"] == null:
		_close(stage)
		return ["could not open the house at %s" % str(size)]
	var world: Node = stage["world"]
	var aliz: Node3D = stage["aliz"]
	var camera: Camera3D = world.call("get_camera")
	if camera == null:
		_close(stage)
		return ["the house has no camera at %s" % str(size)]

	# 1. Bunny standing on his rug, Aliz on his interaction point.
	world.call("place_in_room", "bedroom", "")
	var bunny: Node3D = _bunny_in(world)
	if bunny == null:
		_close(stage)
		return ["no Bunny in the bedroom at %s" % str(size)]
	if _stand_at(stage, "bedroom.littleBuddy"):
		_step(stage)
		failures.append_array(_check_frame(stage, "bunny", ["CARRY", "HUG"], {
			"Aliz's face": _face_rect(stage, SpatialUtil.world_position(aliz), ALIZ_FACE_BOTTOM, ALIZ_FACE_TOP, ALIZ_FACE_HALF_WIDTH),
			"Bunny's face": _face_rect(stage, SpatialUtil.world_position(bunny), BUNNY_FACE_BOTTOM, BUNNY_FACE_TOP, BUNNY_FACE_HALF_WIDTH),
		}, Rect2()))
	else:
		failures.append("bedroom.littleBuddy has no stand position at %s" % str(size))

	# 2. The fridge, shut.
	world.call("place_in_room", "kitchen", "")
	var kitchen: RefCounted = world.call("get_kitchen_state")
	if kitchen != null:
		kitchen.call("set_open", "fridge", false)
	if _stand_at(stage, "kitchen.fridge"):
		_step(stage)
		var fridge: Node = world.call("get_target_by_semantic_id", "kitchen.fridge")
		failures.append_array(_check_frame(stage, "fridge", ["OPEN"], {
			"Aliz's face": _face_rect(stage, SpatialUtil.world_position(aliz), ALIZ_FACE_BOTTOM, ALIZ_FACE_TOP, ALIZ_FACE_HALF_WIDTH),
		}, _silhouette(stage, fridge)))
	else:
		failures.append("kitchen.fridge has no stand position at %s" % str(size))

	# 3. Bunny in her arms, at the bed: PLACE. His face now rides on her chest.
	world.call("place_in_room", "bedroom", "")
	bunny = _bunny_in(world)
	if bunny != null and _stand_at(stage, "bedroom.littleBuddy"):
		if not bool(bunny.call("perform_affordance", aliz)):
			failures.append("carrying: perform_affordance(carry) refused at %s" % str(size))
		for _i: int in range(60):
			aliz.call("step_movement", DT)
		if not bool(bunny.call("is_carried")):
			failures.append("carrying: Bunny is not in her arms at %s" % str(size))
		_stand_at(stage, "bedroom.bed")
		for _i: int in range(6):
			aliz.call("step_movement", DT)
		_step(stage)
		var bed: Node = world.call("get_target_by_semantic_id", "bedroom.bed")
		failures.append_array(_check_frame(stage, "carrying", ["PLACE"], {
			"Aliz's face": _face_rect(stage, SpatialUtil.world_position(aliz), ALIZ_FACE_BOTTOM, ALIZ_FACE_TOP, ALIZ_FACE_HALF_WIDTH),
			"Bunny's face (in her arms)": _face_rect(stage, SpatialUtil.world_position(bunny), BUNNY_FACE_BOTTOM, BUNNY_FACE_TOP, BUNNY_FACE_HALF_WIDTH),
		}, _silhouette(stage, bed)))
		aliz.call("put_down_carried")
		for _i: int in range(60):
			aliz.call("step_movement", DT)
	else:
		failures.append("could not stage the carry at %s" % str(size))

	_close(stage)
	return failures
