extends SceneTree

## Room-art evidence. Dev-only; nothing in the game references it.
##
##   Godot --path game --resolution 1334x750 --script res://tests/shots_rooms.gd -- ipad
##   Godot --path game --resolution 1334x750 --script res://tests/shots_rooms.gd -- iphone 2340x1080
##
## Photographs the REAL `scenes/house/house_world.tscn` -- the rooms a child
## actually walks into -- once per room, from the room's own committed camera
## framing, and prints each room's triangle and draw-call count beside the
## picture it belongs to.
##
## ## Why the second argument exists
##
## `--resolution 2340x1080` is a REQUEST, not an instruction. The window manager
## clamps it to the display, and on this machine every "wide iPhone" shot taken
## by asking the window for one is really 1686 x 935 -- a 1.80 aspect filed as
## evidence for a 2.17 one. That is not a rounding error: `camera_framing.solve()`
## fits its distance FROM the aspect ratio, so the shot being judged is a
## different composition from the one the device gets.
##
## So when a frame size is given, the world is hosted in a `SubViewport` of
## exactly that size and the shot is taken from ITS texture. The camera inside
## sees that viewport's aspect and nothing else. `shots_world.gd` established
## this; it is followed here rather than re-invented.
##
## The suffix is used verbatim, so a BEFORE pass and an AFTER pass are taken by
## the same script with the same framing and differ only in the geometry:
##
##   ... --script res://tests/shots_rooms.gd -- ipad_BEFORE

const OUT_DIR: String = "docs/shots/"
const HouseLayout := preload("res://scripts/house/house_layout.gd")

var _world: Node = null
var _suffix: String = "ipad"
var _frame: Vector2i = Vector2i.ZERO
var _viewport: SubViewport = null


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_suffix = args[0] if args.size() > 0 else "ipad"
	if args.size() > 1:
		var wide: PackedStringArray = String(args[1]).split("x")
		if wide.size() == 2:
			_frame = Vector2i(int(wide[0]), int(wide[1]))

	await process_frame
	var packed: PackedScene = load("res://scenes/house/house_world.tscn")
	_world = packed.instantiate()
	var host: Node = root
	if _frame != Vector2i.ZERO:
		_viewport = SubViewport.new()
		_viewport.size = _frame
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_viewport.transparent_bg = false
		root.add_child(_viewport)
		host = _viewport
	host.add_child(_world)
	await _settle(0.6)

	for room_id: String in HouseLayout.room_ids():
		if not bool(_world.call("place_in_room", room_id, "default")):
			print("  WARN: the house has no room '%s'" % room_id)
			continue
		await _settle(0.6)
		_report(room_id)
		await _shot("rooms_%s_%s" % [room_id, _suffix])

	print("\nROOM SHOTS DONE (%s)" % _suffix)
	quit(0)


## The §10 budget, measured from the room the picture is of, so a screenshot and
## its triangle count can never be from two different builds.
func _report(room_id: String) -> void:
	var room: Node = _world.call("get_room", room_id) if _world.has_method("get_room") else null
	var triangles: int = int(room.call("count_triangles")) if room != null else -1
	var meshes: int = int(room.call("count_meshes")) if room != null else -1
	var line: String = "  room %-12s triangles=%-6d meshes=%d" % [room_id, triangles, meshes]
	var camera: Object = _world.call("get_camera")
	if camera != null and camera.has_method("get_last_solution"):
		var solution: Dictionary = camera.call("get_last_solution")
		line += "  distance=%.2f fov=%.1f fits=%s" % [
			float(solution.get("distance", 0.0)), float(solution.get("fov", 0.0)),
			str(solution.get("fits", false))]
	print(line)


func _shot(out_name: String) -> void:
	await RenderingServer.frame_post_draw
	var source: Viewport = _viewport if _viewport != null else root.get_viewport()
	var image: Image = source.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + out_name + ".png")
	var err: int = image.save_png(path)
	# The SIZE is printed, not assumed. See the class docs: a shot filed at the
	# wrong aspect is evidence for a composition nobody is shipping.
	print("  %s %s.png  %d x %d" % [
		"shot" if err == OK else "FAIL", out_name, image.get_width(), image.get_height()])


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
