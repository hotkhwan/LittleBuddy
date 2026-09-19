extends SceneTree

## THE VISUAL BENCHMARK: Aliz and Bunny in the kitchen, same scene, same camera.
##
##   Godot --path game --resolution 1334x750 --script res://tests/shots_benchmark.gd -- <prefix>
##
## The brief asks for a before/after comparison "using the SAME production scene
## and camera framing". That is harder than it sounds, and this file exists to
## make it honest rather than flattering:
##
##   * It drives the REAL `house_world.tscn`, not a spike scene.
##   * It puts BOTH characters in the kitchen. Bunny normally lives in the
##     bedroom, so a plain kitchen screenshot contains neither character and
##     would compare an empty room against an empty room.
##   * It opens the fridge and puts a bottle in Aliz's hands, because "carried
##     items must not float" is one of the things being judged.
##   * The camera is whatever the SHIPPING camera does. Nothing here composes a
##     flattering angle -- a benchmark that picks its own framing proves nothing
##     about what the child sees.
##
## The prefix is passed in so the same script can produce `before_*` and
## `after_*` sets that are directly comparable.
##
## DO NOT RENDER A "BEFORE" FROM A FRESH GIT WORKTREE. It looks like the clean
## way to get an uncontaminated baseline and it silently produces a lie: a new
## worktree has no `.godot/imported/` cache, so every GLB is unimported and BOTH
## CHARACTERS RENDER AS NOTHING AT ALL. The room still draws, the HUD still
## draws, and the screenshot looks plausible -- it just has no Aliz and no Bunny
## in it, and a carried bottle hanging in mid-air where she should have been.
## Cost an hour to notice. Either run `--import` in the worktree first, or take
## the baseline from committed screenshots rendered in the main tree.

const OUT_DIR: String = "docs/shots/"

var _prefix: String = "bench"
var _world: Node = null


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not String(args[0]).strip_edges().is_empty():
		_prefix = String(args[0]).strip_edges()

	var packed: PackedScene = load("res://scenes/house/house_world.tscn")
	if packed == null:
		print("FAIL: house_world.tscn will not load")
		quit(1)
		return
	_world = packed.instantiate()
	root.add_child(_world)
	await _settle(0.5)

	if not _world.call("place_in_room", "kitchen", "default"):
		print("FAIL: could not enter the kitchen")
		quit(1)
		return
	await _settle(0.5)

	# Bring Bunny to the kitchen. Without this the benchmark shot has no child in
	# it at all, which is precisely the comparison the brief is trying to avoid.
	var moved: bool = _bring_bunny()
	await _settle(0.6)
	await _shot("%s_kitchen_plain" % _prefix, "the kitchen with both characters")

	# Hands full, fridge open: the two things the brief names as defects.
	var kitchen: RefCounted = _world.call("get_kitchen_state") \
			if _world.has_method("get_kitchen_state") else null
	if kitchen != null:
		kitchen.call("set_open", "fridge", true)
		await _settle(0.5)
		await _shot("%s_kitchen_fridge" % _prefix, "fridge open, food visible")
		kitchen.call("take", "fridge", "bottle")
		await _settle(0.5)
		await _shot("%s_kitchen_carry" % _prefix, "carrying the bottle -- is it in her hands?")
	else:
		print("  note: no interactive kitchen in this build")

	print("\nbunny relocated: %s" % str(moved))
	print("done -- view every image before trusting it")
	quit(0)


## Moves the Bunny actor into the kitchen room node, if the world allows it.
## Reports whether it worked rather than assuming, so a shot with no child in it
## is recognisable as such instead of being filed as evidence.
func _bring_bunny() -> bool:
	var bedroom: Node = _world.call("get_room", "bedroom")
	var kitchen_room: Node = _world.call("get_room", "kitchen")
	if bedroom == null or kitchen_room == null:
		return false
	for child: Node in bedroom.get_children():
		if child.has_method("satisfy") and child.has_method("set_activity"):
			bedroom.remove_child(child)
			kitchen_room.add_child(child)
			# `room_changed(new_room, buddy)` -- TWO Node3D arguments, not a room
			# id string. The first version passed "kitchen" and threw, abandoning
			# the move half-done and producing a kitchen with no Bunny in it.
			if child.has_method("room_changed"):
				child.call("room_changed", kitchen_room, _find_caregiver())
			if child is Node3D:
				(child as Node3D).position = Vector3(0.55, 0.0, 0.9)
			return true
	return false


## Aliz, so Bunny can be told who to attend to after the move.
func _find_caregiver() -> Node3D:
	return _world.get_node_or_null("LittleBuddy") as Node3D


func _shot(name: String, caption: String) -> void:
	await _settle(0.4)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + name + ".png")
	var err: int = image.save_png(path)
	print("  %s %s.png  (%s)" % ["shot" if err == OK else "FAIL", name, caption])


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
