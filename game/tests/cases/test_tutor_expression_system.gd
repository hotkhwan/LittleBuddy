extends RefCounted

const DirectorScript := preload("res://scripts/tutor/expression/tutor_expression_director.gd")
const CueContractScript := preload("res://scripts/tutor/expression/tutor_cue_contract.gd")
const LipSyncScript := preload("res://scripts/tutor/expression/tutor_lip_sync_driver.gd")


func test_name() -> String:
	return "tutor_expression_system"


func run():
	var failures: Array = []
	failures.append_array(_test_expression_mapping_and_smoothing())
	failures.append_array(_test_cue_whitelist_and_validation())
	failures.append_array(_test_gesture_rotation_and_rate_limit())
	failures.append_array(_test_lip_sync_and_reset())
	return failures


func _test_expression_mapping_and_smoothing():
	var failures: Array = []
	var director: Node = DirectorScript.new()
	if not director.set_emotion("encouraging", 0.8, 0.4):
		failures.append("a supported emotion was rejected")
	director.step(0.2)
	var frame: Dictionary = director.current_frame()
	if frame.get("face") != "encouraging" or frame.get("head") != "small_nod":
		failures.append("encouraging did not map to its semantic face/head frame")
	if not is_equal_approx(float(frame.get("intensity")), 0.4):
		failures.append("emotion intensity snapped instead of blending halfway")
	if director.set_emotion("angry", 1.0):
		failures.append("an emotion outside the child-safe whitelist was accepted")
	director.free()
	return failures


func _test_cue_whitelist_and_validation():
	var failures: Array = []
	var contract: RefCounted = CueContractScript.new()
	var valid: Dictionary = contract.validate({"action": "set_emotion", "emotion": "proud", "intensity": 2.0})
	if not valid.get("valid", false) or valid["arguments"].get("intensity") != 1.0:
		failures.append("valid emotion cue was not accepted and clamped")
	for cue: Dictionary in [
		{"action": "call_method", "method": "queue_free"},
		{"action": "set_emotion", "emotion": "furious"},
		{"action": "show_learning_card", "card_id": "../../secret"},
	]:
		if contract.validate(cue).get("valid", false):
			failures.append("unsafe cue was accepted: %s" % cue)
	return failures


func _test_gesture_rotation_and_rate_limit():
	var failures: Array = []
	var director: Node = DirectorScript.new()
	var pool: Array = ["Great!", "Nice!", "You did it!"]
	var sequence: Array = []
	for index: int in range(4):
		sequence.append(director.rotate("praise", pool))
	if sequence != ["Great!", "Nice!", "You did it!", "Great!"]:
		failures.append("praise rotation was not deterministic")
	if not director.play_gesture("wave", 0.8):
		failures.append("first valid gesture was rate-limited")
	if director.play_gesture("clap", 0.8):
		failures.append("back-to-back gesture spam was accepted")
	director.step(1.3)
	if not director.play_gesture("clap", 0.8):
		failures.append("gesture remained blocked after cooldown")
	director.free()
	return failures


func _test_lip_sync_and_reset():
	var failures: Array = []
	var lip_sync: RefCounted = LipSyncScript.new()
	var active: Dictionary = lip_sync.update_amplitude(0.6, 0.06)
	if float(active.get("openness", 0.0)) <= 0.0:
		failures.append("audible amplitude did not open the mouth")
	if not lip_sync.apply_viseme("oh", 0.7):
		failures.append("supported viseme was rejected")
	if lip_sync.apply_viseme("jaw_bone_rotate", 1.0):
		failures.append("unknown viseme was accepted")
	var reset: Dictionary = lip_sync.reset()
	if reset.get("openness") != 0.0 or reset.get("viseme") != "sil":
		failures.append("lip sync reset did not restore a closed neutral mouth")
	if reset.get("blendMode") != "additive_expression_safe":
		failures.append("lip sync did not declare expression-safe blending")
	return failures
