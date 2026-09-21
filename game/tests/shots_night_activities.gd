extends SceneTree

var frame := Vector2i(1334, 750)
var phase := "before"
var viewport: SubViewport
var room: Node

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	print("NIGHT initializing activity capture")
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		phase = args[0]
	if args.size() > 1:
		var parts := args[1].split("x")
		frame = Vector2i(int(parts[0]), int(parts[1]))
	await process_frame
	print("NIGHT building viewport")
	# No profile writes from a development screenshot run.
	var save := root.get_node_or_null("SaveService")
	if save != null:
		root.remove_child(save)
		save.queue_free()
	viewport = SubViewport.new()
	viewport.size = frame
	viewport.size_2d_override = Vector2i(roundi(float(frame.x) / frame.y * 1024.0), 1024)
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	room = load("res://scenes/baby_room/baby_room.tscn").instantiate()
	print("NIGHT room instantiated")
	viewport.add_child(room)
	await _settle()
	for entry: Array in [["baby_room", "playTime", "tidyToyBox"], ["bath_mission", "bathTime", "giveSoap"], ["bedtime_mission", "bedtimeRoutine", "bedtimeTeddy"], ["tidy_mission", "tidyAndBedtime", "tidyToysAway"], ["feeding", "feedingTime", "feedBanana"]]:
		room.call("_start_next_mission", entry[1])
		await _settle()
		var runner: Node = room.get_node("MissionRunner")
		for index: int in range(16):
			if String(runner.call("get_current_task").get("taskId", "")) == entry[2]:
				break
			runner.call("skip_current_task")
			await _settle()
		assert(String(runner.call("get_current_task").get("taskId", "")) == entry[2])
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		assert(image != null and image.get_size() == frame)
		var path := "res://../docs/shots/night/%s_%s_%dx%d.png" % [entry[0], phase, frame.x, frame.y]
		assert(image.save_png(ProjectSettings.globalize_path(path)) == OK)
		print("NIGHT ACTIVITY SHOT ", path)
	room.queue_free()
	await process_frame
	quit()

func _settle() -> void:
	for index: int in range(90):
		await process_frame
