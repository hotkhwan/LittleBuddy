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
		"nursery":
			_load("res://scenes/baby_room/baby_room.tscn")
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
