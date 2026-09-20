extends RefCounted

## The owner's evening additions to "Learn with Aliz" (docs/ALIZ_TUTOR_CONTRACTS.md
## addendum, Settings): `handsFreeMode` (default on), `aiVoiceId` from the
## configured voice list (cloud presets disabled while the flag is off), and the
## read-only learning history built from `tutorProgress`.
##
## Pinned: defaults, persistence, corrupt-value fallbacks, that a cloud voice
## cannot be stored in a public build, that the history reads the engine's
## `save_progress()` shape (stars from the lesson content, never invented;
## "No lessons yet" when empty; skips junk entries; lesson ids validated before
## they become a path), and that every new row sits in the ScrollContainer just
## where the owner asked (history directly above "Delete learning history").

const ModelScript := preload("res://scripts/parent_settings/parent_settings_model.gd")
const VoiceOptions := preload("res://scripts/parent_settings/voice_options.gd")
const LearningHistory := preload("res://scripts/parent_settings/learning_history.gd")
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")
const LessonEngineScript := preload("res://scripts/tutor/lesson/lesson_engine.gd")

const PARENT_SCENE: String = "res://scenes/parent/parent_settings.tscn"
const VOICE_OPTIONS_PATH: String = "res://content/tutor/voice_options.json"


class FakeSaveService:
	extends RefCounted
	var settings: Dictionary = {}
	var stars: int = 4

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value

	func get_stars() -> int:
		return stars

	func add_stars(amount: int) -> int:
		stars += amount
		return stars


func test_name() -> String:
	return "tutor_settings"


func run():
	var failures: Array = []
	failures.append_array(_test_hands_free_mode())
	failures.append_array(_test_voice_options_file())
	failures.append_array(_test_voice_options_sanitise())
	failures.append_array(_test_ai_voice_id_persists_and_falls_back())
	failures.append_array(_test_learning_history_from_engine_format())
	failures.append_array(_test_learning_history_tolerates_junk())
	failures.append_array(_test_screen_rows())
	return failures


# -- handsFreeMode -----------------------------------------------------------------

func _test_hands_free_mode():
	var failures: Array = []
	var save := FakeSaveService.new()
	var model: RefCounted = ModelScript.new(save)
	if ModelScript.KEY_HANDS_FREE_MODE != "handsFreeMode":
		failures.append("the key must be handsFreeMode")
	if not model.get_hands_free_mode():
		failures.append("handsFreeMode must default to On")
	if save.settings.has("handsFreeMode"):
		failures.append("reading the default wrote the key")
	model.set_hands_free_mode(false)
	if save.settings.get("handsFreeMode", true) != false:
		failures.append("Off did not persist: %s" % str(save.settings))
	if ModelScript.new(save).get_hands_free_mode():
		failures.append("Off was not read back by a new model")
	save.settings["handsFreeMode"] = "sometimes"
	if not ModelScript.new(save).get_hands_free_mode():
		failures.append("a corrupt value must read as the default (On)")
	var detached: RefCounted = ModelScript.new(null)
	detached.set_hands_free_mode(false)
	if detached.get_hands_free_mode():
		failures.append("without a service the toggle forgot its value")
	return failures


# -- voice options -----------------------------------------------------------------

func _test_voice_options_file():
	var failures: Array = []
	if not FileAccess.file_exists(VOICE_OPTIONS_PATH):
		return ["%s is missing" % VOICE_OPTIONS_PATH]
	VoiceOptions.reset_cache()
	var options: Array = VoiceOptions.options(true)
	if options.size() < 3:
		failures.append("expected the bright device voice plus two cloud presets, got %d" % options.size())
	var defaults: int = 0
	var device: int = 0
	var cloud: int = 0
	for option: Dictionary in options:
		if bool(option["default"]):
			defaults += 1
		if String(option["provider"]) == "device":
			device += 1
		elif String(option["provider"]) == "cloud":
			cloud += 1
	if defaults != 1:
		failures.append("%d default voices; exactly one" % defaults)
	if device < 1 or cloud < 2:
		failures.append("expected >= 1 device and >= 2 cloud voices, got %d / %d" % [device, cloud])
	if VoiceOptions.default_id() != "aliz_bright":
		failures.append("the default voice is %s, expected aliz_bright" % VoiceOptions.default_id())
	if String(VoiceOptions.find("aliz_bright").get("provider", "")) != "device":
		failures.append("aliz_bright is not a device voice; the offline tutor needs one")
	if TutorFlags.cloud_enabled():
		return failures + ["the cloud flag is ON in a test run"]
	for option: Dictionary in options:
		var id: String = String(option["id"])
		var selectable: bool = VoiceOptions.is_selectable(id)
		if String(option["provider"]) == "cloud" and selectable:
			failures.append("cloud voice %s is selectable with the flag off" % id)
		if String(option["provider"]) == "device" and not selectable:
			failures.append("device voice %s is not selectable" % id)
		if String(option["provider"]) == "cloud" and VoiceOptions.availability_note(id) != "when the cloud tutor is available":
			failures.append("cloud voice %s lacks the availability note" % id)
	if VoiceOptions.is_selectable("not_a_voice") or VoiceOptions.is_known("../etc/passwd"):
		failures.append("an unknown or malformed id was accepted")
	return failures


func _test_voice_options_sanitise():
	var failures: Array = []
	# Junk file: the bundled device voice, and nothing else.
	var junk: Array = VoiceOptions.sanitise("nope")
	if junk.size() != 1 or String(junk[0]["id"]) != "aliz_bright" or not bool(junk[0]["default"]):
		failures.append("a junk file did not fall back to the bundled device voice: %s" % str(junk))
	# Only cloud voices configured: the device voice is added and made default.
	var cloud_only: Array = VoiceOptions.sanitise({"options": [
		{"id": "sky", "label": "Sky", "provider": "cloud", "default": true}]})
	var found_default: String = ""
	for option: Dictionary in cloud_only:
		if bool(option["default"]):
			found_default = String(option["id"])
	if found_default != "aliz_bright" or cloud_only.size() != 2:
		failures.append("a cloud-only list did not gain a default device voice: %s" % str(cloud_only))
	# Bad ids, duplicates, bad providers and empty labels are dropped, one at a time.
	var mixed: Array = VoiceOptions.sanitise({"options": [
		{"id": "Good Voice", "label": "x", "provider": "device"},
		{"id": "../escape", "label": "x", "provider": "device"},
		{"id": "ok_voice", "label": "  ", "provider": "device"},
		{"id": "ok_voice", "label": "Ok", "provider": "device"},
		{"id": "ok_voice", "label": "Dup", "provider": "device"},
		{"id": "odd", "label": "Odd", "provider": "telepathy"},
		{"id": "fine", "label": "Fine", "provider": "cloud", "default": "yes"},
	]})
	var ids: Array = []
	for option: Dictionary in mixed:
		ids.append(String(option["id"]))
	if ids != ["ok_voice", "fine"]:
		failures.append("sanitise kept %s, expected [ok_voice, fine]" % str(ids))
	if not bool(mixed[0]["default"]) or bool(mixed[1]["default"]):
		failures.append("the first device voice must become the default when none is flagged: %s" % str(mixed))
	return failures


func _test_ai_voice_id_persists_and_falls_back():
	var failures: Array = []
	if ModelScript.KEY_AI_VOICE_ID != "aiVoiceId":
		failures.append("the key must be aiVoiceId")
	var save := FakeSaveService.new()
	var model: RefCounted = ModelScript.new(save)
	if model.get_ai_voice_id() != "aliz_bright":
		failures.append("the default voice is %s" % model.get_ai_voice_id())
	if save.settings.has("aiVoiceId"):
		failures.append("reading the default wrote the key")
	model.set_ai_voice_id("aliz_bright")
	if save.settings.get("aiVoiceId", "") != "aliz_bright":
		failures.append("a device voice did not persist")
	# A cloud voice cannot be stored while the flag is off.
	model.set_ai_voice_id("aliz_warm_cloud")
	if save.settings.get("aiVoiceId", "") != "aliz_bright":
		failures.append("a cloud voice was stored with the flag off: %s" % str(save.settings))
	model.set_ai_voice_id("robot_9000")
	if save.settings.get("aiVoiceId", "") != "aliz_bright":
		failures.append("an unknown voice was stored")
	# Corrupt / stale values read as the default.
	for bad: Variant in [7, "aliz_warm_cloud", "", "../x", {"id": "aliz_bright"}]:
		save.settings["aiVoiceId"] = bad
		if ModelScript.new(save).get_ai_voice_id() != "aliz_bright":
			failures.append("a stored %s did not fall back to the default voice" % str(bad))
	return failures


# -- learning history ------------------------------------------------------------------

## Drives the real engine to completion so the map is the engine's own output.
func _test_learning_history_from_engine_format():
	var failures: Array = []
	var save := FakeSaveService.new()
	if LearningHistory.lines(save.get_setting("tutorProgress", {})) != PackedStringArray(["No lessons yet"]):
		failures.append("an empty history does not read 'No lessons yet': %s" % str(LearningHistory.lines({})))

	var engine: RefCounted = LessonEngineScript.new()
	if not engine.load_lesson("animals_cat_dog"):
		return failures + ["cannot load the animals lesson"]
	var guard: int = 0
	while not engine.is_complete() and guard < 100:
		guard += 1
		var step: Dictionary = engine.current_step()
		if String(step.get("kind", "")) == "ask":
			var answers: Array = step.get("expectedAnswers", [])
			engine.evaluate(String(answers[0]) if not answers.is_empty() else "")
		engine.advance()
	if not engine.is_complete():
		return failures + ["the animals lesson never completed under the walker"]
	var granted: int = engine.save_progress(save)
	var progress: Dictionary = save.get_setting("tutorProgress", {})
	var entry: Dictionary = progress.get("animals_cat_dog", {})
	if not bool(entry.get("completed", false)):
		return failures + ["setup: the engine did not mark the lesson completed: %s" % str(entry)]

	var model: RefCounted = ModelScript.new(save)
	var entries: Array = model.learning_history_entries()
	if entries.size() != 1:
		failures.append("expected one completed lesson, got %s" % str(entries))
	else:
		var row: Dictionary = entries[0]
		if String(row["title"]) != "Cat and Dog":
			failures.append("the title was not read from the lesson content: %s" % str(row))
		if int(row["stars"]) != granted or int(row["stars"]) != 1:
			failures.append("stars %s do not match what the engine paid (%d) / the content (1)" % [str(row["stars"]), granted])
		# The engine stamps `completedAt` (ISO-8601 UTC) on completion, so the
		# row shows today's local date; an OLD entry without it says so instead.
		if String(row["dateText"]) == "date not recorded" or String(row["dateText"]).is_empty():
			failures.append("a lesson the engine just completed must show its date, got %s" % str(row["dateText"]))
	var lines: PackedStringArray = model.learning_history_lines()
	if lines.size() != 1 or not lines[0].begins_with("Cat and Dog -- 1 star -- "):
		failures.append("history lines: %s" % str(lines))

	# An in-progress lesson is not listed as completed.
	progress["colors_red_blue"] = {"stepIndex": 2, "stepCount": 6, "correctFirstTry": 1, "completed": false, "rewardGranted": false}
	save.settings["tutorProgress"] = progress
	if model.learning_history_entries().size() != 1:
		failures.append("an in-progress lesson was listed as completed")
	var all_rows: Array = LearningHistory.entries(progress)
	if all_rows.size() != 2 or bool(all_rows[1]["completed"]) or not String(all_rows[1]["line"]).contains("step 3 of 6"):
		failures.append("the full list does not describe the in-progress lesson: %s" % str(all_rows))

	# `completedAt` (ISO UTC or unix) shows as a local date, newest first; an
	# entry from before the stamp existed (no completedAt) sorts last.
	progress["colors_red_blue"] = {"stepIndex": 6, "stepCount": 6, "correctFirstTry": 3, "completed": true,
			"rewardGranted": true, "completedAt": "2026-09-19T23:30:00.000Z"}
	progress["numbers_one_two_three"] = {"stepIndex": 7, "stepCount": 7, "correctFirstTry": 3, "completed": true,
			"rewardGranted": true, "completedAt": 1789898400}
	var legacy: Dictionary = (progress["animals_cat_dog"] as Dictionary).duplicate()
	legacy.erase("completedAt")
	progress["animals_cat_dog"] = legacy
	var dated: Array = LearningHistory.completed_entries(progress, Callable(), 7 * 60)  # Bangkok
	if dated.size() != 3:
		failures.append("expected three completed lessons, got %d" % dated.size())
	else:
		if String(dated[0]["lessonId"]) != "numbers_one_two_three" or String(dated[0]["dateText"]) != "20 Sep 2026":
			failures.append("newest first / unix date: %s" % str(dated[0]))
		if String(dated[1]["lessonId"]) != "colors_red_blue" or String(dated[1]["dateText"]) != "20 Sep 2026":
			failures.append("ISO date in Bangkok (23:30Z -> 06:30 next day): %s" % str(dated[1]))
		if String(dated[2]["lessonId"]) != "animals_cat_dog":
			failures.append("undated lessons must sort last: %s" % str(dated[2]))
	if LearningHistory.total_stars(progress) != 3:
		failures.append("total stars %d, expected 3 (1+1+1 from content)" % LearningHistory.total_stars(progress))
	return failures


func _test_learning_history_tolerates_junk():
	var failures: Array = []
	if not LearningHistory.entries("junk").is_empty() or not LearningHistory.entries(null).is_empty():
		failures.append("a non-dictionary map produced rows")
	var progress: Dictionary = {
		"../../etc/passwd": {"completed": true, "rewardGranted": true},
		"Weird Id": {"completed": true},
		"animals_cat_dog": "not a dictionary",
		"colors_red_blue": {"completed": "yes", "rewardGranted": 1},
		"missing_lesson_file": {"completed": true, "rewardGranted": true, "completedAt": "garbage"},
		"everyday_cup_spoon": {"completed": true, "rewardGranted": true, "stepIndex": "x", "completedAt": -5},
	}
	var rows: Array = LearningHistory.completed_entries(progress)
	var ids: Array = []
	for row: Dictionary in rows:
		ids.append(String(row["lessonId"]))
	ids.sort()
	if ids != ["everyday_cup_spoon", "missing_lesson_file"]:
		failures.append("junk handling kept %s" % str(ids))
	for row: Dictionary in rows:
		if String(row["lessonId"]) == "missing_lesson_file":
			if int(row["stars"]) != 0 or String(row["title"]) != "Missing Lesson File" or String(row["dateText"]) != "date not recorded":
				failures.append("a lesson with no content file must show 0 stars, a readable title and no date: %s" % str(row))
		if String(row["lessonId"]) == "everyday_cup_spoon" and (int(row["stars"]) != 1 or String(row["title"]) != "Cup and Spoon"):
			failures.append("a real lesson's title/stars were not read: %s" % str(row))
	if not LearningHistory.load_lesson("../lesson_schema").is_empty():
		failures.append("a path-like id reached the file system")
	return failures


# -- the screen --------------------------------------------------------------------------

func _test_screen_rows():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var save := FakeSaveService.new()
	save.settings["tutorProgress"] = {
		"animals_cat_dog": {"stepIndex": 5, "stepCount": 5, "correctFirstTry": 2, "completed": true, "rewardGranted": true},
	}
	var packed: PackedScene = load(PARENT_SCENE) as PackedScene
	var panel: Control = packed.instantiate() as Control
	tree.root.add_child(panel)
	panel.call("_ready")
	var model: RefCounted = panel.call("model")
	model.call("set_service", save)
	panel.call("open_settings")

	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	var box: Node = panel.find_child("LearnWithAlizBox", true, false)
	for node_name: String in ["HandsFreeOnButton", "HandsFreeOffButton", "AlizVoiceButtons", "AlizVoice_aliz_bright",
			"AlizVoice_aliz_warm_cloud", "AlizVoice_aliz_playful_cloud", "AlizHistoryTitle", "AlizHistoryBox",
			"AlizHistoryLine0", "AlizPrivacyBox", "AlizDeleteHistoryButton"]:
		var node: Node = panel.find_child(node_name, true, false)
		if node == null:
			failures.append("%s is missing" % node_name)
		elif scroll == null or not scroll.is_ancestor_of(node) or box == null or not box.is_ancestor_of(node):
			failures.append("%s is not inside the ScrollContainer's Learn with Aliz section" % node_name)

	# History sits directly above "Delete learning history" (help + button).
	var history_box: Node = panel.find_child("AlizHistoryBox", true, false)
	var delete_help: Node = panel.find_child("AlizDeleteHelp", true, false)
	var delete_button: Node = panel.find_child("AlizDeleteHistoryButton", true, false)
	if history_box != null and delete_help != null and delete_button != null:
		if delete_help.get_index() != history_box.get_index() + 1 or delete_button.get_index() != history_box.get_index() + 2:
			failures.append("the learning history is not directly above Delete learning history (%d / %d / %d)"
					% [history_box.get_index(), delete_help.get_index(), delete_button.get_index()])
	var history_lines: PackedStringArray = panel.call("aliz_learning_history_lines")
	if history_lines.size() != 1 or not history_lines[0].begins_with("Cat and Dog -- 1 star"):
		failures.append("the history row shows %s" % str(history_lines))
	# Empty history reads "No lessons yet".
	save.settings["tutorProgress"] = {}
	panel.call("open_settings")
	var line0: Label = panel.find_child("AlizHistoryLine0", true, false) as Label
	if line0 == null or line0.text != "No lessons yet":
		failures.append("an empty history does not show 'No lessons yet' on screen")

	# Hands-free: default On, Off persists, On again.
	var hf_on: Button = panel.find_child("HandsFreeOnButton", true, false) as Button
	var hf_off: Button = panel.find_child("HandsFreeOffButton", true, false) as Button
	if not hf_on.button_pressed or hf_off.button_pressed:
		failures.append("hands-free does not start On")
	hf_off.button_pressed = true
	hf_off.pressed.emit()
	if save.settings.get("handsFreeMode", true) != false:
		failures.append("tapping Off did not persist handsFreeMode=false")
	hf_on.button_pressed = true
	hf_on.pressed.emit()
	if save.settings.get("handsFreeMode", false) != true:
		failures.append("tapping On did not persist handsFreeMode=true")

	# Voice: device selectable, cloud disabled with the note, cloud tap refused.
	var choices: Dictionary = panel.call("aliz_voice_choices")
	if choices.get("aliz_bright", false) != true:
		failures.append("aliz_bright is not selectable: %s" % str(choices))
	for cloud_id: String in ["aliz_warm_cloud", "aliz_playful_cloud"]:
		if choices.get(cloud_id, true) != false:
			failures.append("%s is enabled with the cloud off" % cloud_id)
	var note: Label = panel.find_child("AlizVoiceNote", true, false) as Label
	if note == null or not note.visible or not note.text.contains("when the cloud tutor is available"):
		failures.append("the cloud voices are not explained as unavailable: %s" % (note.text if note != null else "no note"))
	var bright: Button = panel.find_child("AlizVoice_aliz_bright", true, false) as Button
	if not bright.button_pressed:
		failures.append("the default voice button is not selected")
	var warm: Button = panel.find_child("AlizVoice_aliz_warm_cloud", true, false) as Button
	warm.pressed.emit()  # a disabled button cannot be tapped; even a forced signal is refused
	if save.settings.has("aiVoiceId") and save.settings["aiVoiceId"] != "aliz_bright":
		failures.append("a cloud voice was stored from the screen: %s" % str(save.settings))
	if not bright.button_pressed:
		failures.append("the selection did not snap back to the kept voice")
	bright.pressed.emit()
	if save.settings.get("aiVoiceId", "") != "aliz_bright":
		failures.append("tapping the device voice did not persist it")

	# Close / Done still work with the new rows.
	var closed: Array = [0]
	panel.connect("closed", func() -> void: closed[0] += 1)
	(panel.find_child("DoneButton", true, false) as Button).pressed.emit()
	if closed[0] != 1 or bool(panel.call("is_panel_visible")):
		failures.append("Done no longer closes")
	tree.root.remove_child(panel)
	panel.free()
	return failures
