extends SceneTree
## Dev helper: run a single case. godot --headless --path game --script res://tests/run_one.gd -- test_feeding_table
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var case_name: String = args[0] if args.size() > 0 else "test_feeding_table"
	for auto in ["SaveService", "SpeechService", "TtsService", "Sfx", "Audio"]:
		var n := root.get_node_or_null(auto)
		if n: root.remove_child(n)
	var script: GDScript = load("res://tests/cases/%s.gd" % case_name)
	var inst = script.new()
	var result = inst.call("run")
	if result is Array and (result as Array).is_empty():
		print("[PASS] ", case_name)
	else:
		print("[FAIL] ", case_name)
		if result is Array:
			for f in result: print("   - ", f)
		else:
			print("   run() returned ", result)
	quit(0)
