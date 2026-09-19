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
				if _scene.has_method("enter_room"):
					_scene.call("enter_room", extra)
				elif _scene.has_method("go_to_room"):
					_scene.call("go_to_room", extra)
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
			# Framed on the head. `extra` is the head height in metres, so the same
			# job can frame a re-scaled character without editing the harness.
			var head_y: float = float(extra) if extra != "" else 1.20
			cam.position = Vector3(0.0, head_y, -1.05)
			cam.fov = 34.0
			root.add_child(cam)
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
