extends SceneTree

## Lighting evidence. Dev-only; nothing in the game references it.
##
##   Godot --headless=false --path game --script res://tests/shots_lighting.gd -- after ipad
##   Godot --path game --script res://tests/shots_lighting.gd -- before iphone
##
## Photographs the REAL `house_world.tscn` with one of `scripts/house/lighting.gd`'s
## named setups applied on top of it. Same scene, same rooms, same camera, same
## framing, same frame number — **only the light differs**, which is the only way
## a before/after picture is worth anything.
##
## ## The resolution trap, which this repository has already been burned by
##
## `--resolution 2340x1080` is a REQUEST. The window manager clamps it to the
## display, and every "wide iPhone" shot taken before `shots_world.gd` fixed it
## is really 1686 x 935 — a 1.80 aspect filed as evidence for a 2.17 one. That is
## not a rounding error: `camera_framing.solve()` derives its distance from the
## aspect, so the composition being judged was never the composition the device
## gets. So the world is hosted in a `SubViewport` of EXACTLY the asked-for size
## and photographed from its texture, the same technique `shots_world.gd` uses.
## Every frame this script writes is verified: `_shot()` re-reads the PNG's IHDR
## off disk and prints the dimensions it really has.
##
## ## The measurements
##
## Pictures are the deliverable, but "milky" is a measurable claim, so each shot
## also prints:
##
##   * `p05 / p50 / p95` luminance and `range` — how much value the frame uses.
##   * `clip` — the fraction of pixels at or above 0.97 luminance. This is the
##     milkiness number: a frame whose lit walls have all clipped to the same
##     near-white has no way to show a corner.
##   * `warm` — mean (R - B) in sRGB bytes. Warmth, as a number, so "warmer"
##     cannot be claimed without being true.

const OUT_DIR: String = "docs/shots/"
const Lighting := preload("res://scripts/house/lighting.gd")
const CameraFocus := preload("res://scripts/camera/camera_focus.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## `house_level_director.gd::FOCUS_MARGIN`, so the close-up is the shot the
## child really gets rather than one this file invented.
const FOCUS_MARGIN: float = 0.3

## The two frames the brief names, both rendered at their true size.
const FRAMES: Dictionary = {
	"ipad": Vector2i(1334, 750),
	"iphone": Vector2i(2340, 1080),
}

var _world: Node = null
var _values: Dictionary = {}
var _tag: String = "after"
var _device: String = "ipad"
var _frame: Vector2i = FRAMES["ipad"]
var _viewport: SubViewport = null


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_tag = String(args[0]) if args.size() > 0 else "after"
	_device = String(args[1]) if args.size() > 1 else "ipad"
	_frame = FRAMES.get(_device, FRAMES["ipad"])
	_values = Lighting.setup(_tag)

	await process_frame
	var packed: PackedScene = load("res://scenes/house/house_world.tscn")
	_world = packed.instantiate()
	_viewport = SubViewport.new()
	_viewport.size = _frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	root.add_child(_viewport)
	_viewport.add_child(_world)
	await _settle(0.5)

	_repair_rooms()
	_apply_lighting()
	_report_setup()

	# The two rooms the brief names, each with the characters in them: the
	# nursery holds Little Buddy and the baby, the kitchen holds Little Buddy
	# against the room's largest cream fields.
	for room_id: String in [HouseLayout.KITCHEN, HouseLayout.BEDROOM]:
		_world.call("place_in_room", room_id, "default")
		await _enter(room_id)
		_report_characters()
		await _shot("light_%s_%s" % [room_id, _device])

	# Character readability, close up, where a face either separates from the
	# wall behind it or does not.
	_world.call("place_in_room", HouseLayout.BEDROOM, "default")
	await _settle(0.4)
	await _focus_shot("bedroom.littleBuddy", "light_focus_buddy_%s" % _device)

	# The two rooms this pass is not about, at iPad only: one light is global, so
	# a change made for the kitchen is a change made to the bathroom, and the
	# bathroom is where the unlit -X wall has a prop hanging on it.
	if _device == "ipad":
		for room_id: String in [HouseLayout.BATHROOM, HouseLayout.LIVING_ROOM]:
			_world.call("place_in_room", room_id, "default")
			await _settle(0.6)
			await _shot("light_%s_%s" % [room_id, _device])

	await _menu_shot()

	print("\nLIGHTING SHOTS DONE (%s, %s)" % [_tag, _device])
	quit(0)


## The menu is a different scene with its own `WorldEnvironment` and its own
## light, and this pass touches it, so it is photographed too. It is NOT given
## the house's angles: it is outdoors, its sun is already above the horizon
## (elevation 51.3, azimuth +34.0 — that matrix was authored correctly), and its
## framing is its own. Only the FILL colour is brought into line, so that
## pressing Play is not a jump in colour temperature.
func _menu_shot() -> void:
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		return
	# REMOVED, not hidden. Two `WorldEnvironment` nodes in one `World3D` is one
	# too many: only one wins, and the first menu shots taken here came out with
	# the HOUSE's environment on them -- a beige sky instead of the menu's
	# dusty-blue one, and the house's fill instead of the menu's. Both the before
	# and the after were wrong in the same direction, which is exactly the kind
	# of consistent-looking nonsense a controlled pair is supposed to catch.
	_viewport.remove_child(_world)
	var menu: Node = packed.instantiate()
	_viewport.add_child(menu)
	await _settle(0.8)
	var light: DirectionalLight3D = menu.get_node_or_null(
			"DirectionalLight3D") as DirectionalLight3D
	var environment_node: WorldEnvironment = menu.get_node_or_null(
			"WorldEnvironment") as WorldEnvironment
	if _tag == "before" and light != null and environment_node != null:
		# The menu's own previous fill: `#F5F0E5` at 0.55, a desaturated
		# near-neutral that is not in the palette at all.
		environment_node.environment.ambient_light_color = Color(0.96, 0.94, 0.9)
		environment_node.environment.ambient_light_energy = 0.55
		light.light_color = Color(1.0, 0.976, 0.925)
		light.light_energy = 1.0
		await _settle(0.3)
	if light != null and environment_node != null:
		print("  live  menu ambient %s @ %.2f  key %s @ %.2f" % [
			environment_node.environment.ambient_light_color.to_html(false),
			environment_node.environment.ambient_light_energy,
			light.light_color.to_html(false), light.light_energy])
	await _shot("light_menu_%s" % _device)


## Re-attaches a room whose geometry was built but never parented.
##
## **This is a work-around for a live regression in someone else's file, not a
## fix, and it is reported in `docs/LIGHTING_PASS.md` rather than patched here.**
## As the working tree stands, `child_actor.gd::_ready()` reaches
## `get_character()`, which lazily calls `house_world.gd::build_world()` WHILE
## the bedroom node is still setting up its own children. Godot refuses
## `add_child()` on a node in that state, so `room.gd::build()` has both of its
## `add_child()` calls rejected, marks itself `_built`, and goes on to fill a
## `Geometry` node that is attached to nothing: the bedroom renders as an empty
## void with the characters floating in it. `tests/smoke_mission01.gd` prints the
## same two errors, so this is the shipping path, not a harness artefact.
##
## Re-parenting the orphan is the least invasive repair available from here: the
## geometry, the targets and the registry entries are all the real ones, built by
## the real code, so the photograph is still of the real room. Building the world
## before adding it to the tree also works and was tried first — it costs the
## baby, whose own `build()` then never runs, and a shot missing a character is
## worse evidence than one that needed a re-parent.
func _repair_rooms() -> void:
	var rooms: Node = _world.get_node_or_null("Rooms")
	if rooms == null:
		return
	for room: Node in rooms.get_children():
		for property: String in ["_geometry", "_target_root"]:
			var orphan: Node = room.get(property) as Node
			if orphan != null and orphan.get_parent() == null:
				room.add_child(orphan)
				print("  repaired %s/%s (see _repair_rooms)" % [room.name, orphan.name])


func _apply_lighting() -> void:
	var environment_node: WorldEnvironment = _world.get_node_or_null(
			"WorldEnvironment") as WorldEnvironment
	var light: DirectionalLight3D = _world.get_node_or_null(
			"DirectionalLight3D") as DirectionalLight3D
	if environment_node == null or light == null:
		print("  FAIL: the house has no WorldEnvironment/DirectionalLight3D")
		quit(1)
		return
	# `scene` applies nothing: it photographs `house_world.tscn` exactly as
	# authored. Its only job is to prove that `AFTER` in `lighting.gd` and the
	# numbers in the scene file are the same light, by producing the same
	# picture -- a control on the control.
	if _tag != "scene":
		Lighting.apply(environment_node.environment, light, _values)
	var live: Environment = environment_node.environment
	print("  live  ambient %s @ %.2f  key %s @ %.2f  basis z=(%.3f, %.3f, %.3f)" % [
		live.ambient_light_color.to_html(false), live.ambient_light_energy,
		light.light_color.to_html(false), light.light_energy,
		light.global_transform.basis.z.x, light.global_transform.basis.z.y,
		light.global_transform.basis.z.z])


## The setup, and what it does to the three planes a doll's-house room shows the
## camera. Printed so a claim about wall separation has a number behind it.
func _report_setup() -> void:
	var sun: Vector3 = Lighting.to_sun(
			float(_values["elevation"]), float(_values["azimuth"]))
	print("setup %s (%s)  ambient %s @ %.2f  key %s @ %.2f  elev %.1f  azim %.1f" % [
		_tag, _device, _values["ambientColor"].to_html(false),
		float(_values["ambientEnergy"]), _values["keyColor"].to_html(false),
		float(_values["keyEnergy"]), float(_values["elevation"]),
		float(_values["azimuth"])])
	print("  toSun (%.3f, %.3f, %.3f)" % [sun.x, sun.y, sun.z])
	for plane: Array in [
		["back wall  (+Z normal)", Vector3(0, 0, 1)],
		["-X wall    (+X normal)", Vector3(1, 0, 0)],
		["+X wall    (-X normal)", Vector3(-1, 0, 0)],
		["floor      (+Y normal)", Vector3(0, 1, 0)],
	]:
		var fraction: float = Lighting.key_fraction(plane[1], _values)
		print("  %s key=%.3f  linear=%.3f" % [plane[0], fraction,
			float(_values["ambientEnergy"]) + float(_values["keyEnergy"]) * fraction])


## The brief asks for shots "with characters present", so the harness proves it
## rather than leaving it to whoever looks at the picture. Prints every
## character-ish node under the current room plus the roaming Little Buddy, with
## its world position, whether it is visible in the tree, and how many visual
## children it actually built — a character whose `build()` was skipped is a node
## in the right place with nothing in it.
func _report_characters() -> void:
	var found: Array[String] = []
	for node: Node in [
		_world.call("get_character"),
		_world.get_node_or_null("Rooms/Bedroom/LittleBuddyChild"),
	]:
		if node == null:
			continue
		var visible_in_tree: bool = true
		var where: Vector3 = Vector3.ZERO
		if node is Node3D:
			visible_in_tree = (node as Node3D).is_visible_in_tree()
			where = (node as Node3D).global_position
		found.append("%s at (%.2f, %.2f, %.2f) visible=%s meshes=%d" % [
			node.name, where.x, where.y, where.z, str(visible_in_tree),
			_count_meshes(node)])
	print("  cast  %s" % " | ".join(found))


func _count_meshes(node: Node) -> int:
	var total: int = 1 if node is MeshInstance3D and (node as MeshInstance3D).visible else 0
	for child: Node in node.get_children():
		total += _count_meshes(child)
	return total


func _focus_shot(semantic_id: String, out_name: String) -> void:
	var target: Node = _world.call("get_target_by_semantic_id", semantic_id)
	if target == null:
		print("  WARN: no target %s" % semantic_id)
		return
	var room_id: String = semantic_id.split(".")[0]
	var station: Vector3 = SpatialUtil.world_position(target as Node3D)
	var character: Node = _world.call("get_character")
	var child: Vector3 = station
	if character is Node3D:
		child = SpatialUtil.world_position(character as Node3D)
	var camera: Object = _world.call("get_camera")
	var height: float = HouseLayout.FLOOR_Y + HouseLayout.CAMERA_FOCUS_HEIGHT
	var shot: Dictionary = CameraFocus.frame_points(
		[station, child], height, FOCUS_MARGIN,
		CameraFocus.MIN_RADIUS, CameraFocus.MAX_RADIUS,
		HouseLayout.world_floor_bounds(room_id)
	)
	camera.call("focus_activity", shot["focus"], float(shot["radius"]))
	camera.call("settle")
	await _settle(0.5)
	await _shot(out_name)


func _shot(out_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	var file_name: String = "%s%s.png" % [out_name,
			"_BEFORE" if _tag == "before" else ""]
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + file_name)
	var err: int = image.save_png(path)
	if err != OK:
		print("  FAIL %s" % file_name)
		return
	print("  shot %-34s %s  %s" % [file_name, _verify(path), _stats(image)])


## The PNG's own IHDR, read back off disk. A harness that prints the size it
## MEANT to render is the bug this guards against.
func _verify(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "unreadable"
	var head: PackedByteArray = file.get_buffer(24)
	if head.size() < 24:
		return "truncated"
	var width: int = (head[16] << 24) | (head[17] << 16) | (head[18] << 8) | head[19]
	var height: int = (head[20] << 24) | (head[21] << 16) | (head[22] << 8) | head[23]
	var ok: bool = width == _frame.x and height == _frame.y
	return "%dx%d%s" % [width, height, "" if ok else " !! ASKED FOR %s" % str(_frame)]


## Milkiness, in numbers. See the header.
func _stats(image: Image) -> String:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var step: int = maxi(1, int(round(float(height) / 240.0)))
	var luminances: Array[float] = []
	var warm: float = 0.0
	var clipped: int = 0
	var total: int = 0
	for y: int in range(0, height, step):
		for x: int in range(0, width, step):
			var pixel: Color = image.get_pixel(x, y)
			var luminance: float = pixel.get_luminance()
			luminances.append(luminance)
			warm += (pixel.r - pixel.b) * 255.0
			if luminance >= 0.97:
				clipped += 1
			total += 1
	luminances.sort()
	var p05: float = luminances[int(float(total) * 0.05)]
	var p50: float = luminances[int(float(total) * 0.50)]
	var p95: float = luminances[int(float(total) * 0.95)]
	return "p05=%.3f p50=%.3f p95=%.3f range=%.3f clip=%.1f%% warm=%+.1f" % [
		p05, p50, p95, p95 - p05, 100.0 * float(clipped) / float(total),
		warm / float(total)]


## Waits for a room change to finish, not for a stopwatch.
##
## `place_in_room()` runs a fade through `UI/Fade`, an `ink` `ColorRect` over the
## whole screen. A shot timed with `await _settle(0.6)` sometimes lands while
## that rectangle is still partly opaque, and the result is a frame that is
## uniformly darker for reasons that have nothing to do with the light — which,
## in a lighting before/after, is the one artefact that would invalidate the
## entire deliverable. It happened: one pass produced a bathroom at
## `p05 0.279 / p95 0.287`, a flat field, and it looked like a lighting result.
##
## So the fade is waited OUT, explicitly, and the frame is only taken once the
## overlay is transparent and the camera has stopped moving.
func _enter(room_id: String) -> void:
	var fade: CanvasItem = _world.get_node_or_null("UI/Fade") as CanvasItem
	var deadline: int = Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if fade == null or fade.modulate.a <= 0.01:
			break
	if fade != null and fade.modulate.a > 0.01:
		print("  WARN: %s still under a %.2f fade when photographed"
				% [room_id, fade.modulate.a])
	await _settle(0.6)


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
