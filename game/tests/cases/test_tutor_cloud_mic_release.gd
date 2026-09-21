extends RefCounted

## The microphone closes on every way out of Tutor Mode (Agent C). The cloud
## tutor streams child audio only while the hands-free session reports
## `is_capturing()`, so this case pins that the capture AND the recogniser
## are closed when the child leaves the scene, when the app backgrounds, when
## the day's minutes run out (closing -> break card) and when a grown-up ends
## the lesson (End lesson -> Stop). Runs on the real classroom scene with the
## flag OFF (the cloud bridge is never loaded); the cloud session's own
## "nothing streams after end" rule is pinned in test_tutor_cloud_fixtures.

const SCENE_PATH: String = "res://scenes/tutor/classroom.tscn"
const STEP: float = 0.1


class FakeSave extends RefCounted:
	var settings: Dictionary = {}
	var stars: int = 0
	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)
	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value
	func save_profile() -> bool:
		return true
	func add_stars(amount: int) -> int:
		stars += amount
		return stars
	func get_profile() -> Dictionary:
		return {"settings": settings, "unlockedRooms": [], "stars": stars}


func test_name() -> String:
	return "tutor_cloud_mic_release"


func run():
	var failures: Array = []
	failures.append_array(_case("leave", func(scene: Node) -> void: scene.leave_to_home(), "done"))
	failures.append_array(_case("background", func(scene: Node) -> void: scene.go_background(), "background"))
	failures.append_array(_case("parent_stop", func(scene: Node) -> void:
		scene.hud().request_exit()
		scene.hud().exit_confirm().press_stop(), "break"))
	failures.append_array(_case("quota_end", func(scene: Node) -> void:
		scene.quota().tick(400.0)
		scene.simulate("correct")
		_until(scene, func() -> bool: return scene.state() == "break", 1500), "break"))
	return failures


func _case(label: String, exit_action: Callable, expected_state: String) -> Array:
	var failures: Array = []
	var scene: Node = _make()
	if _until(scene, func() -> bool: return scene.state() == "listening", 600) < 0:
		_free(scene)
		return ["%s: the classroom never opened the microphone (state %s)" % [label, scene.state()]]
	var voice: Object = scene.voice_session()
	if voice == null or not bool(voice.call("is_capturing")):
		_free(scene)
		return ["%s: expected the hands-free session to be capturing before the exit" % label]
	exit_action.call(scene)
	scene.advance(STEP)
	var capturing: bool = bool(voice.call("is_capturing"))
	var active: bool = bool(voice.call("is_active"))
	var recogniser: Object = voice.call("recognition") if voice.has_method("recognition") else null
	var open_session: bool = recogniser != null and recogniser.has_method("has_active_session") and bool(recogniser.call("has_active_session"))
	print("    %s: state=%s is_capturing=%s is_active=%s recogniser_open=%s" % [label, scene.state(), str(capturing), str(active), str(open_session)])
	if capturing or active:
		failures.append("%s: the microphone must be closed (is_capturing=%s is_active=%s)" % [label, str(capturing), str(active)])
	if open_session:
		failures.append("%s: the recogniser session must be closed" % label)
	if scene.state() != expected_state:
		failures.append("%s: expected state %s, got %s" % [label, expected_state, scene.state()])
	# Nothing reopens it on its own.
	for _i: int in range(20):
		scene.advance(STEP)
	if bool(voice.call("is_capturing")):
		failures.append("%s: the microphone reopened by itself" % label)
	_free(scene)
	return failures


func _make() -> Node:
	var packed: PackedScene = load(SCENE_PATH)
	var scene: Node = packed.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(scene)
	scene.build()
	scene.set_save_service(FakeSave.new())
	scene.enable_simulation(true)
	scene.begin_lesson()
	return scene


func _free(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		if scene.get_parent() != null:
			scene.get_parent().remove_child(scene)
		scene.free()


func _until(scene: Node, predicate: Callable, max_steps: int) -> int:
	for i: int in range(max_steps):
		if predicate.call():
			return i
		scene.advance(STEP)
	return -1
