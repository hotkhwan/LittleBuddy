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
	_settle = 18


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
