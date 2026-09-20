extends RefCounted
## `VoiceCues` is a deterministic table: the same event always yields the same
## line ids, every id it can yield exists in the manifest, and the rows the
## owner asked for are pinned one by one.

const VoiceCues := preload("res://scripts/voice/voice_cues.gd")
const VoiceManifestScript := preload("res://scripts/voice/voice_manifest.gd")


func test_name() -> String:
	return "voice_cues"


func run():
	var failures: Array = []
	failures.append_array(_test_every_row_points_at_a_real_line())
	failures.append_array(_test_the_owner_rows())
	failures.append_array(_test_text_routing())
	failures.append_array(_test_determinism_and_silence())
	return failures


func _test_every_row_points_at_a_real_line():
	var failures: Array = []
	var manifest: RefCounted = VoiceManifestScript.load_default()
	var tables: Dictionary = {
		"SIMPLE_EVENTS": VoiceCues.SIMPLE_EVENTS,
		"NEED_LINES": VoiceCues.NEED_LINES,
		"TASK_LINES": VoiceCues.TASK_LINES,
		"ENCOURAGEMENT_LINES": VoiceCues.ENCOURAGEMENT_LINES,
		"TEXT_ALIASES": VoiceCues.TEXT_ALIASES,
	}
	for table_name: String in tables.keys():
		var table: Dictionary = tables[table_name]
		for key: Variant in table.keys():
			var value: Variant = table[key]
			var ids: Array = value if value is Array else [value]
			for line_id: Variant in ids:
				if not manifest.has_line(String(line_id)):
					failures.append("%s[%s] -> %s, which is not in the manifest" % [table_name, str(key), str(line_id)])
	for line_id: String in [VoiceCues.PRAISE_LINE, VoiceCues.DELIGHT_LINE, VoiceCues.RETRY_LINE, VoiceCues.SECOND_MISS_LINE]:
		if not manifest.has_line(line_id):
			failures.append("encouragement constant %s is not in the manifest" % line_id)
	# Every one of the 36 lines is reachable from SOME cue, so no line was
	# requested that the game never uses.
	var reachable: Dictionary = {}
	for table_name: String in tables.keys():
		for value: Variant in (tables[table_name] as Dictionary).values():
			var ids: Array = value if value is Array else [value]
			for line_id: Variant in ids:
				reachable[String(line_id)] = true
	for line_id: String in manifest.line_ids():
		if not reachable.has(line_id) and not manifest.text_for(line_id).is_empty():
			# Exact text always routes to itself through `for_text`.
			if VoiceCues.for_text(manifest.text_for(line_id)) != line_id:
				failures.append("%s is reachable from no cue and not by its own text" % line_id)
	return failures


func _test_the_owner_rows():
	var failures: Array = []
	var expected: Dictionary = {
		VoiceCues.EVENT_MENU_READY + "|": ["aliz_001_welcome", "aliz_002_lets_play"],
		VoiceCues.EVENT_START_PRESSED + "|": ["aliz_004_lets_go_home"],
		VoiceCues.EVENT_FREE_PLAY_PRESSED + "|": ["aliz_004_lets_go_home"],
		VoiceCues.EVENT_NEED + "|hungry": ["bunny_001_hungry"],
		VoiceCues.EVENT_MILK_PROMPT + "|": ["bunny_002_milk"],
		VoiceCues.EVENT_FOOD_BITE + "|": ["bunny_003_yummy"],
		VoiceCues.EVENT_MEAL_HALFWAY + "|": ["bunny_004_more"],
		VoiceCues.EVENT_CARE_COMPLETED + "|": ["bunny_005_thank_you"],
		VoiceCues.EVENT_NEED + "|sleepy": ["bunny_006_sleepy"],
		VoiceCues.EVENT_BEDTIME_PLACED + "|": ["bunny_007_good_night"],
		VoiceCues.EVENT_BATH + "|": ["bunny_008_bath"],
		VoiceCues.EVENT_NEED + "|needsBath": ["bunny_008_bath"],
		VoiceCues.EVENT_NEED + "|wantsToPlay": ["bunny_009_play"],
		VoiceCues.EVENT_NEED + "|needsComfort": ["bunny_010_hug"],
		VoiceCues.EVENT_CELEBRATE + "|": ["bunny_011_happy"],
		VoiceCues.EVENT_WRONG_ITEM + "|": ["bunny_012_upset"],
		VoiceCues.EVENT_NEED_URGENT + "|": ["bunny_012_upset"],
		VoiceCues.EVENT_TASK + "|apple": ["aliz_011_apple"],
		VoiceCues.EVENT_TASK + "|banana": ["aliz_012_banana"],
		VoiceCues.EVENT_TASK + "|water": ["aliz_013_drink"],
		VoiceCues.EVENT_TASK + "|milk": ["aliz_013_drink"],
		VoiceCues.EVENT_TASK + "|prepareMilk": ["aliz_014_milk_time"],
		VoiceCues.EVENT_TASK + "|bath": ["aliz_015_bath_time"],
		VoiceCues.EVENT_TASK + "|brushTeeth": ["aliz_016_brush_teeth"],
		VoiceCues.EVENT_TASK + "|bedtime": ["aliz_017_bedtime"],
		VoiceCues.EVENT_TASK + "|tidy": ["aliz_018_clean_up"],
		VoiceCues.EVENT_TASK + "|cooking": ["aliz_019_cooking"],
		VoiceCues.EVENT_TASK + "|kitchen.fridge.apple": ["aliz_011_apple"],
		VoiceCues.EVENT_TASK_DONE + "|": ["aliz_020_all_done"],
		VoiceCues.EVENT_ENCOURAGEMENT + "|Great!": ["aliz_006_good_job"],
		VoiceCues.EVENT_ENCOURAGEMENT + "|You did it!": ["aliz_007_well_done"],
		VoiceCues.EVENT_ENCOURAGEMENT + "|Well done!": ["aliz_007_well_done"],
		VoiceCues.EVENT_ENCOURAGEMENT + "|Try again!": ["aliz_008_try_again"],
		VoiceCues.EVENT_STAR + "|": ["aliz_021_star"],
		VoiceCues.EVENT_STICKER + "|": ["aliz_022_sticker"],
		VoiceCues.EVENT_BREAK_CARD + "|": ["aliz_023_break", "aliz_024_come_back"],
		VoiceCues.EVENT_NEED + "|needsChanging": [],
		"somethingNobodyMapped" + "|": [],
	}
	for key: String in expected.keys():
		var event: String = key.get_slice("|", 0)
		var detail: String = key.get_slice("|", 1)
		var got: Array = VoiceCues.for_event(event, detail)
		if got != expected[key]:
			failures.append("for_event(%s, %s) = %s, expected %s" % [event, detail, str(got), str(expected[key])])
	# The second miss gets the warmer second line.
	if VoiceCues.for_encouragement("Try again!", 2) != ["aliz_008_try_again", "aliz_009_its_okay"]:
		failures.append("a second miss should add It's okay: %s" % str(VoiceCues.for_encouragement("Try again!", 2)))
	if VoiceCues.for_encouragement("Try the apple!", 1) != ["aliz_008_try_again"]:
		failures.append("'Try the apple!' is a retry: %s" % str(VoiceCues.for_encouragement("Try the apple!", 1)))
	if VoiceCues.for_encouragement("Great!", 2) != ["aliz_006_good_job"]:
		failures.append("praise never gets the retry tail")
	# The owner asked for the cute-angry face on a mistake.
	if VoiceCues.face_for(VoiceCues.EVENT_WRONG_ITEM) != "hmph":
		failures.append("a wrong item must bring the hmph face, got '%s'" % VoiceCues.face_for(VoiceCues.EVENT_WRONG_ITEM))
	if VoiceCues.face_for(VoiceCues.EVENT_NEED_URGENT) != "hmph":
		failures.append("an ignored need must bring the hmph face")
	if not VoiceCues.face_for(VoiceCues.EVENT_FOOD_BITE).is_empty():
		failures.append("a bite does not move the face through the cue table")
	return failures


func _test_text_routing():
	var failures: Array = []
	var manifest: RefCounted = VoiceManifestScript.load_default()
	for line_id: String in manifest.line_ids():
		if VoiceCues.for_text(manifest.text_for(line_id)) != line_id:
			failures.append("for_text('%s') should be %s, got %s" % [manifest.text_for(line_id), line_id, VoiceCues.for_text(manifest.text_for(line_id))])
	var expected: Dictionary = {
		"Great!": "aliz_006_good_job",
		"Nice!": "aliz_006_good_job",
		"Try again!": "aliz_008_try_again",
		"Thank you!": "bunny_005_thank_you",
		"Let's play!": "bunny_009_play",
		"  let's MAKE some milk!  ": "aliz_014_milk_time",
		"Let's brush our teeth.": "aliz_016_brush_teeth",
		"Off you go! Tap anything you like.": "",
		"Walk to the kitchen.": "",
		"milk": "",
		"": "",
	}
	for text: String in expected.keys():
		if VoiceCues.for_text(text) != String(expected[text]):
			failures.append("for_text('%s') = '%s', expected '%s'" % [text, VoiceCues.for_text(text), expected[text]])
	return failures


func _test_determinism_and_silence():
	var failures: Array = []
	for event: String in VoiceCues.event_names():
		var first: Array = VoiceCues.for_event(event, "hungry")
		for _i: int in range(5):
			if VoiceCues.for_event(event, "hungry") != first:
				failures.append("for_event(%s) is not deterministic" % event)
				break
	if not VoiceCues.for_event("").is_empty():
		failures.append("an empty event must be silent")
	if not VoiceCues.for_task("").is_empty() or not VoiceCues.for_need("").is_empty():
		failures.append("an empty detail must be silent")
	if VoiceCues.first_for(VoiceCues.EVENT_STAR) != "aliz_021_star":
		failures.append("first_for(star) = %s" % VoiceCues.first_for(VoiceCues.EVENT_STAR))
	if not VoiceCues.first_for("nothing").is_empty():
		failures.append("first_for(unknown) must be ''")
	return failures
