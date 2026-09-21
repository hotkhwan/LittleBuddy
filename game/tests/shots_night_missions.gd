extends SceneTree

## Every shipped activity-picker route, through its real house director.
## Capture initial playable state; do not synthesize completion or pathfinding.
const Picker := preload("res://scenes/activities_menu/activity_picker.gd")
const Library := preload("res://scripts/content/content_library.gd")
const Levels := preload("res://scripts/progression/level_system.gd")
const Fixtures := preload("res://tests/cases/test_activity_picker.gd")
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var phase: String = args[0] if args.size() > 0 else "after"
	if phase not in ["before", "after"]:
		push_error("Expected screenshot phase before or after")
		quit(1)
		return
	await process_frame
	var real_save := root.get_node_or_null("SaveService")
	if real_save != null:
		root.remove_child(real_save)
	var save := Fixtures.FakeSave.new()
	save.name = "SaveService"
	root.add_child(save)
	var library: RefCounted = Library.create()
	var levels: RefCounted = Levels.create(library)
	var entries: Array = Picker.entries_for(levels, library, {})
	print("NIGHT PICKER ROUTES ", entries.size())
	for entry: Dictionary in entries:
		var mission: String = entry["missionId"]
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1334, 750)
		viewport.size_2d_override = Vector2i(1821, 1024)
		viewport.size_2d_override_stretch = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var world: Node = load("res://scenes/house/house_world.tscn").instantiate()
		world.call("set_requested_mission_id", mission)
		viewport.add_child(world)
		# Transition tweens use elapsed time, not frame count; a fast Mac can
		# render90 frames before the entry fade finishes.
		var settle_until := Time.get_ticks_msec() + 1800
		while Time.get_ticks_msec() < settle_until:
			await process_frame
		var director: Node = world.call("get_level_director")
		if director == null or not bool(director.call("is_running")):
			failures.append("%s: director not running" % mission)
		elif String(director.call("get_mission_id")) != mission:
			failures.append("%s: routed to %s" % [mission, director.call("get_mission_id")])
		else:
			var runner: Node = director.call("get_runner")
			var task: Dictionary = runner.call("get_current_task")
			var plan: Dictionary = director.call("get_current_plan")
			if task.is_empty() or plan.is_empty():
				failures.append("%s: no playable task/plan" % mission)
			print("NIGHT ROUTE PASS %s room=%s task=%s plan=%s" % [mission, world.call("get_current_room_id"), task.get("taskId", ""), JSON.stringify(plan)])
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var path := "res://../docs/shots/night/mission_%s_%s.png" % [mission, phase]
		if image == null or image.get_size() != Vector2i(1334, 750) or image.save_png(ProjectSettings.globalize_path(path)) != OK:
			failures.append("%s: image invalid" % mission)
		viewport.queue_free()
		await process_frame
	for failure: String in failures:
		push_error(failure)
	print("NIGHT MISSIONS %d routes, %d failures" % [entries.size(), failures.size()])
	# Real save stayed detached throughout; the fake was the only mutable profile.
	save.queue_free()
	if real_save != null:
		real_save.free()
	quit(0 if failures.is_empty() else 1)
