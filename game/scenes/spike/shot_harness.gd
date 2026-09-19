extends Node
## Generic screenshot harness. Dev-only, never referenced by production.
##
##   Godot --path game --resolution WxH res://scenes/spike/shot_harness.tscn -- <job> <outName>
##
## Jobs are named below in `_JOBS`. Each loads a real scene, lets it settle, and
## writes docs/shots/<outName>.png. Running the actual scenes (rather than
## rebuilding an approximation) is the point: a harness that composes its own
## view proves nothing about what the child sees.

const OUT_DIR := "docs/shots/"

var _settle := 0
var _out := ""
var _scene: Node = null


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var job: String = args[0] if args.size() > 0 else "menu"
	_out = args[1] if args.size() > 1 else job
	var extra: String = args[2] if args.size() > 2 else ""
	_run(job, extra)


func _run(job: String, extra: String) -> void:
	match job:
		"menu":
			_load("res://scenes/main/main.tscn")
		"house":
			_load("res://scenes/house/house_world.tscn")
			if _scene != null and extra != "":
				await get_tree().process_frame
				await get_tree().process_frame
				# `place_in_room` is the name `HouseWorld` actually exports. Neither
				# of the two guesses that used to be here matched anything, so every
				# `-- house <outName> <roomId>` run since this harness was written
				# silently photographed the BEDROOM and filed it as evidence for
				# whichever room had been asked for. It is checked first, and a miss
				# now prints rather than passing quietly.
				if _scene.has_method("place_in_room"):
					if not bool(_scene.call("place_in_room", extra, "default")):
						print("  WARN: the house has no room '%s'" % extra)
				elif _scene.has_method("enter_room"):
					_scene.call("enter_room", extra)
				else:
					print("  WARN: the house cannot be told which room to show")
		"beat":
			# The close-up, opened by GAMEPLAY. The real house, the real level
			# director, stepped by the real engine: the harness only starts the
			# level and waits for `is_camera_focused()` to come back true, so it
			# cannot photograph a shot the game would not have composed.
			# `extra` names the level; it defaults to the first one a child plays.
			_load("res://scenes/house/house_world.tscn")
			await get_tree().process_frame
			await get_tree().process_frame
			# "<levelId>" or "<levelId>:<tasksToSkipFirst>", because the beat worth
			# photographing is rarely the first one: the opening task of a level is
			# usually a `choose`, whose box has to hold a whole row of objects and
			# is therefore the WIDEST close-up the game composes, not the tightest.
			var parts: PackedStringArray = extra.split(":")
			var level: String = parts[0] if parts.size() > 0 and parts[0] != "" \
					else "goodMorningRoutine"
			var skip: int = parts[1].to_int() if parts.size() > 1 else 0
			var beat_director: Node = null
			if _scene.has_method("ensure_level_director"):
				beat_director = _scene.call("ensure_level_director")
			if beat_director == null:
				print("  WARN: this build has no level director")
			else:
				beat_director.call("_start_level", level)
				var beat_runner: Node = beat_director.get("_runner")
				for _skipped in range(skip):
					if beat_runner != null:
						beat_runner.call("skip_current_task")
					for _settle_frame in range(20):
						await get_tree().process_frame
				for _frame in range(300):
					await get_tree().process_frame
					if bool(beat_director.call("is_camera_focused")):
						break
				if not bool(beat_director.call("is_camera_focused")):
					# A `goAndDo` or `deliver` beat only tightens ON ARRIVAL, and
					# nobody is tapping the floor in a screenshot run. Stand the
					# child where the walk would have ended and let the director
					# reach the beat -- the same call arriving makes, with the same
					# staging and the same close-up, so the picture is still of a
					# shot the game composes and not one the harness invented.
					var beat_plan_room: Dictionary = beat_director.call("get_current_plan")
					var focus_id: String = String(beat_plan_room.get("focusTargetId", ""))
					# The room FIRST. A beat in the kitchen reached while the bedroom
					# is the active room composes a perfectly correct close-up on a
					# room that is currently hidden, and photographs an empty beige
					# field -- which is exactly what this printed before the walk
					# was made to include the doors it would really have gone
					# through.
					if focus_id.contains("."):
						_scene.call("place_in_room", focus_id.split(".")[0], "default")
						await get_tree().process_frame
					var stand: Variant = beat_director.call("_beat_stand_position")
					var walker: Node = _scene.get_node_or_null("LittleBuddy")
					if stand is Vector3 and walker is Node3D:
						(walker as Node3D).global_position = stand
						await get_tree().process_frame
						beat_director.call("_reach_beat")
						for _settle in range(40):
							await get_tree().process_frame
				var beat_plan: Dictionary = beat_director.call("get_current_plan")
				print("  level=%s task=%s kind=%s focused=%s" % [
					level, String(beat_plan.get("taskId", "")),
					String(beat_plan.get("kind", "")),
					str(beat_director.call("is_camera_focused"))])
		"storage":
			# The house with the bedroom's toy box forced open or shut, so the two
			# states can be compared side by side.
			_load("res://scenes/house/house_world.tscn")
			await get_tree().process_frame
			await get_tree().process_frame
			var room: Node = null
			if _scene.has_method("get_room"):
				room = _scene.call("get_room", "bedroom")
			if room != null and room.has_method("set_storage_open"):
				room.call("set_storage_open", "toyBox", extra == "open")
				print("  toyBox open=%s" % str(room.call("is_storage_open", "toyBox")))
			else:
				print("  WARN: could not reach the bedroom storage")
		"walking":
			# The REAL house scene, with the player driven forward so the walk
			# clip is actually running -- not a posed model.
			_load("res://scenes/house/house_world.tscn")
			await get_tree().process_frame
			await get_tree().process_frame
			var ch: Node = _scene.get_node_or_null("LittleBuddy")
			var view: Node = ch.find_child("BuddyView", true, false) if ch != null else null
			if view != null and view.has_method("get_animation_player"):
				var pl: AnimationPlayer = view.call("get_animation_player")
				if pl != null and pl.has_animation("walk"):
					var loco := load("res://scripts/character/locomotion.gd")
					pl.speed_scale = loco.scale_for_speed(0.45)
					pl.play("walk")
					pl.seek(pl.get_animation("walk").length * 0.28, true)
					pl.pause()
					print("  posed clip=%s scale=%.2f" % [pl.current_animation, pl.speed_scale])
				else:
					print("  WARN: no walk clip on the player's view")
		"care":
			# The REAL house, running the REAL mission, advanced to the care beat
			# so the close-up is opened by gameplay rather than by the harness.
			_load("res://scenes/house/house_world.tscn")
			await get_tree().process_frame
			await get_tree().process_frame
			var director: Node = null
			if _scene.has_method("ensure_level_director"):
				director = _scene.call("ensure_level_director")
			if director != null and director.has_method("start"):
				director.call("start")
				await get_tree().process_frame
				var runner: Node = director.get("_runner")
				# Skip forward to the first care task without faking its completion.
				for _i in range(12):
					var task: Dictionary = runner.call("get_current_task") if runner != null else {}
					if String(task.get("interaction", "")) in ["brushTeeth", "washFace", "dryFace"]:
						break
					if runner != null:
						runner.call("skip_current_task")
					await get_tree().process_frame
				var ov: Node = director.get("_care_overlay")
				var plan: Dictionary = director.call("get_current_plan")
				print("  task=%s kind=%s overlayVisible=%s" % [
					String(plan.get("taskId","")), String(plan.get("careKind","")),
					str(ov.visible) if ov != null else "no overlay"])
				if ov != null and not ov.visible and not String(plan.get("careKind","")).is_empty():
					# Reached the task but not yet its beat (the walk is still
					# pending in a harness with no player input): open it the way
					# arrival would.
					director.call("_open_care", plan)
		"alizface":
			# A head-on close-up of Aliz, so a TEXTURE edit can be judged on the
			# face the child actually sees rather than on the atlas. Loads the
			# shipping wrapper, not the raw GLB.
			var root := Node3D.new()
			add_child(root)
			var girl: Node = load("res://scripts/characters/buddy/pink_girl_buddy.gd").new()
			root.add_child(girl)
			if girl.has_method("build"):
				girl.call("build")
			await get_tree().process_frame
			await get_tree().process_frame
			var light := DirectionalLight3D.new()
			light.rotation_degrees = Vector3(-24.0, 18.0, 0.0)
			light.light_energy = 1.25
			root.add_child(light)
			var env := WorldEnvironment.new()
			var e := Environment.new()
			e.background_mode = Environment.BG_COLOR
			e.background_color = Color(0.604, 0.753, 0.851)
			e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			e.ambient_light_color = Color(1, 1, 1)
			e.ambient_light_energy = 0.55
			env.environment = e
			root.add_child(env)
			var cam := Camera3D.new()
			# `extra` is the framing: a number frames the HEAD at that height,
			# "body" frames the whole character head-to-toe on a plain field --
			# which is the shape an image-to-3D reference has to be.
			root.add_child(cam)
			if extra == "body":
				e.background_color = Color(1, 1, 1)
				cam.position = Vector3(0.0, 0.66, -2.75)
				cam.fov = 40.0
				cam.look_at(Vector3(0.0, 0.66, 0.0), Vector3.UP)
			else:
				var head_y: float = float(extra) if extra != "" else 1.20
				cam.position = Vector3(0.0, head_y, -1.05)
				cam.fov = 34.0
				cam.look_at(Vector3(0.0, head_y, 0.0), Vector3.UP)
			cam.current = true
			_scene = root
		"nursery":
			_load("res://scenes/baby_room/baby_room.tscn")
		"speech":
			# The speech panel on its own, over a neutral field, so each state can
			# be reviewed without driving a whole mission to reach it.
			var bg := ColorRect.new()
			bg.color = Color(0.604, 0.753, 0.851)
			bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(bg)
			var panel_script: GDScript = load("res://scripts/ui/speech_feedback.gd")
			var panel: Control = panel_script.new()
			add_child(panel)
			panel.call("build")
			panel.call("set_state", int(extra.to_int()), "milk")
			_scene = panel
		_:
			_load(job)  # treat the job as a raw scene path
	_settle = 40


func _load(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("shot_harness: missing %s" % path)
		get_tree().quit(1)
		return
	var packed: PackedScene = load(path)
	_scene = packed.instantiate()
	add_child(_scene)


func _process(_d: float) -> void:
	if _settle <= 0:
		return
	_settle -= 1
	if _settle > 0:
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var abs_path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + _out + ".png")
	var err: int = img.save_png(abs_path)
	print("  %s %s" % ["ok " if err == OK else "FAIL", OUT_DIR + _out + ".png"])
	get_tree().quit(0)
