extends SceneTree

## Filesystem-only quality gate; no rendering or saved-profile access.
const ROOT := "res://../docs/shots/night/"
const PAIRS: Array[String] = [
	"main_menu_%s", "activity_picker_%s", "freeplay_feed_%s",
	"bath_care_%s", "freeplay_bedtime_%s", "freeplay_tidy_%s",
	"freeplay_chooser_%s", "blocks_%s", "fruit_%s",
	"%s_classroom_1334x750", "%s_dress_1334x750",
	"baby_room_%s_1334x750", "feeding_%s_1334x750",
	"bath_mission_%s_1334x750", "bedtime_mission_%s_1334x750", "tidy_mission_%s_1334x750",
	"mission_imHungry_%s", "mission_snackTime_%s", "mission_goodMorningRoutine_%s",
	"mission_morningRoutine_%s", "mission_breakfastTime_%s", "mission_toddlerPlayTime_%s",
	"mission_tidyAndBedtime_%s", "mission_sayItChallenge_%s", "mission_brushMyTeeth_%s",
]

func _initialize() -> void:
	var failures: Array[String] = []
	for pair: String in PAIRS:
		var before := Image.load_from_file(ROOT + pair % "before" + ".png")
		var after := Image.load_from_file(ROOT + pair % "after" + ".png")
		if before == null or after == null:
			failures.append("missing pair " + pair)
			continue
		if before.get_size() != Vector2i(1334, 750) or after.get_size() != before.get_size():
			failures.append("dimension mismatch " + pair)
		if before.get_data() == after.get_data():
			failures.append("identical before/after " + pair)
	for failure: String in failures:
		print("FAIL: ", failure)
	print("NIGHT EVIDENCE: %d pairs, %d failures" % [PAIRS.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
