extends RefCounted
## Game event -> recorded line id. Pure, static, deterministic.
##
## Nothing in here plays a sound. A call site says WHAT HAPPENED
## (`VoiceCues.for_event(VoiceCues.EVENT_FOOD_BITE)`) and gets back the ordered
## list of line ids the owner's line list assigns to that moment; `VoiceDirector`
## decides how to play them. Keeping the mapping here, in one table, is what
## lets `test_voice_cues.gd` pin every row and what lets the owner change a
## decision ("mistakes get the hmph") by editing one line.
##
## ## The cue table (2026-09-20, owner's line list)
##
## | event                       | detail          | line ids                                   |
## |-----------------------------|-----------------|--------------------------------------------|
## | menuReady                   |                 | aliz_001_welcome, aliz_002_lets_play       |
## | startPressed                |                 | aliz_004_lets_go_home                      |
## | freePlayPressed             |                 | aliz_004_lets_go_home                      |
## | callBunny                   |                 | aliz_003_come_on                           |
## | followMe                    |                 | aliz_010_follow_me                         |
## | whatShallWeDo               |                 | aliz_005_what_shall_we_do                  |
## | need                        | hungry          | bunny_001_hungry                           |
## | need                        | thirsty         | bunny_002_milk                             |
## | need                        | sleepy          | bunny_006_sleepy                           |
## | need                        | needsBath/dirty | bunny_008_bath                             |
## | need                        | wantsToPlay     | bunny_009_play                             |
## | need                        | needsComfort    | bunny_010_hug                              |
## | need                        | crying          | bunny_010_hug                              |
## | need                        | needsChanging   | (no line; the bubble alone)                |
## | needUrgent                  | any             | bunny_012_upset  (+ face `hmph`)           |
## | milkPrompt                  |                 | bunny_002_milk                             |
## | foodBite                    |                 | bunny_003_yummy                            |
## | mealHalfway                 |                 | bunny_004_more                             |
## | careCompleted               |                 | bunny_005_thank_you                        |
## | bedtimePlaced               |                 | bunny_007_good_night                       |
## | bath                        |                 | bunny_008_bath                             |
## | celebrate                   |                 | bunny_011_happy                            |
## | wrongItem                   |                 | bunny_012_upset  (+ face `hmph`)           |
## | task                        | apple           | aliz_011_apple                             |
## | task                        | banana          | aliz_012_banana                            |
## | task                        | water/milk/drink| aliz_013_drink                             |
## | task                        | prepareMilk     | aliz_014_milk_time                         |
## | task                        | bath/washFace   | aliz_015_bath_time                         |
## | task                        | brushTeeth      | aliz_016_brush_teeth                       |
## | task                        | bedtime/sleep   | aliz_017_bedtime                           |
## | task                        | tidy/cleanUp    | aliz_018_clean_up                          |
## | task                        | cooking/cook    | aliz_019_cooking                           |
## | taskDone                    |                 | aliz_020_all_done                          |
## | encouragement               | Great!/Nice!/…  | aliz_006_good_job                          |
## | encouragement               | You did it!/Well done! | aliz_007_well_done                  |
## | encouragement               | Try again!/Almost!     | aliz_008_try_again                  |
## | encouragement (2nd miss)    | Try again!      | aliz_008_try_again, aliz_009_its_okay      |
## | star                        |                 | aliz_021_star                              |
## | sticker                     |                 | aliz_022_sticker                           |
## | breakCard                   |                 | aliz_023_break, aliz_024_come_back         |
##
## English stays the teaching language. The HUD helper line (Thai hint) is
## untouched by any of this; the subtitle strip shows the recorded line's
## English text, which for an alias ("Nice!" -> "Great job!") is the owner's
## wording rather than the HUD's.

const VoiceManifestScript := preload("res://scripts/voice/voice_manifest.gd")

# -- Events ---------------------------------------------------------------------
const EVENT_MENU_READY: String = "menuReady"
const EVENT_START_PRESSED: String = "startPressed"
const EVENT_FREE_PLAY_PRESSED: String = "freePlayPressed"
const EVENT_CALL_BUNNY: String = "callBunny"
const EVENT_FOLLOW_ME: String = "followMe"
const EVENT_WHAT_SHALL_WE_DO: String = "whatShallWeDo"
const EVENT_NEED: String = "need"
const EVENT_NEED_URGENT: String = "needUrgent"
const EVENT_MILK_PROMPT: String = "milkPrompt"
const EVENT_FOOD_BITE: String = "foodBite"
const EVENT_MEAL_HALFWAY: String = "mealHalfway"
const EVENT_CARE_COMPLETED: String = "careCompleted"
const EVENT_BEDTIME_PLACED: String = "bedtimePlaced"
const EVENT_BATH: String = "bath"
const EVENT_CELEBRATE: String = "celebrate"
const EVENT_WRONG_ITEM: String = "wrongItem"
const EVENT_TASK: String = "task"
const EVENT_TASK_DONE: String = "taskDone"
const EVENT_ENCOURAGEMENT: String = "encouragement"
const EVENT_STAR: String = "star"
const EVENT_STICKER: String = "sticker"
const EVENT_BREAK_CARD: String = "breakCard"

## Bunny's face for the cute-angry moments. The owner asked for the `hmph`
## (brows down, puffed cheeks) on a mistake rather than the sad `unhappy`.
const FACE_HMPH: String = "hmph"

## Events with no detail: one row each.
const SIMPLE_EVENTS: Dictionary = {
	EVENT_MENU_READY: ["aliz_001_welcome", "aliz_002_lets_play"],
	EVENT_START_PRESSED: ["aliz_004_lets_go_home"],
	EVENT_FREE_PLAY_PRESSED: ["aliz_004_lets_go_home"],
	EVENT_CALL_BUNNY: ["aliz_003_come_on"],
	EVENT_FOLLOW_ME: ["aliz_010_follow_me"],
	EVENT_WHAT_SHALL_WE_DO: ["aliz_005_what_shall_we_do"],
	EVENT_NEED_URGENT: ["bunny_012_upset"],
	EVENT_MILK_PROMPT: ["bunny_002_milk"],
	EVENT_FOOD_BITE: ["bunny_003_yummy"],
	EVENT_MEAL_HALFWAY: ["bunny_004_more"],
	EVENT_CARE_COMPLETED: ["bunny_005_thank_you"],
	EVENT_BEDTIME_PLACED: ["bunny_007_good_night"],
	EVENT_BATH: ["bunny_008_bath"],
	EVENT_CELEBRATE: ["bunny_011_happy"],
	EVENT_WRONG_ITEM: ["bunny_012_upset"],
	EVENT_TASK_DONE: ["aliz_020_all_done"],
	EVENT_STAR: ["aliz_021_star"],
	EVENT_STICKER: ["aliz_022_sticker"],
	EVENT_BREAK_CARD: ["aliz_023_break", "aliz_024_come_back"],
}

## `need` detail -> line. Keys are `child_needs.gd` state names.
const NEED_LINES: Dictionary = {
	"hungry": "bunny_001_hungry",
	"thirsty": "bunny_002_milk",
	"sleepy": "bunny_006_sleepy",
	"needsBath": "bunny_008_bath",
	"dirty": "bunny_008_bath",
	"wantsToPlay": "bunny_009_play",
	"needsComfort": "bunny_010_hug",
	"crying": "bunny_010_hug",
	# needsChanging: no line in the owner's list. The bubble says it; nobody speaks it.
}

## `task` detail -> line. Keys are object ids, care kinds and act names, so the
## feeding table, the level director and free play can all ask with the word
## they already have.
const TASK_LINES: Dictionary = {
	"apple": "aliz_011_apple",
	"banana": "aliz_012_banana",
	"water": "aliz_013_drink",
	"milk": "aliz_013_drink",
	"drink": "aliz_013_drink",
	"giveBottle": "aliz_013_drink",
	"bottle": "aliz_013_drink",
	"prepareMilk": "aliz_014_milk_time",
	"makeMilk": "aliz_014_milk_time",
	"bath": "aliz_015_bath_time",
	"bathTime": "aliz_015_bath_time",
	"washFace": "aliz_015_bath_time",
	"wash": "aliz_015_bath_time",
	"brushTeeth": "aliz_016_brush_teeth",
	"bedtime": "aliz_017_bedtime",
	"sleep": "aliz_017_bedtime",
	"tidy": "aliz_018_clean_up",
	"tidyUp": "aliz_018_clean_up",
	"cleanUp": "aliz_018_clean_up",
	"cooking": "aliz_019_cooking",
	"cook": "aliz_019_cooking",
}

## Encouragement phrases the game already says (mode_handler.gd, feeding_rules.gd,
## house_freeplay_director.gd) -> the owner's recorded line. Normalised text.
const PRAISE_LINE: String = "aliz_006_good_job"
const DELIGHT_LINE: String = "aliz_007_well_done"
const RETRY_LINE: String = "aliz_008_try_again"
const SECOND_MISS_LINE: String = "aliz_009_its_okay"
const ENCOURAGEMENT_LINES: Dictionary = {
	"great!": PRAISE_LINE,
	"great job!": PRAISE_LINE,
	"nice!": PRAISE_LINE,
	"yes!": PRAISE_LINE,
	"good job!": PRAISE_LINE,
	"well done!": DELIGHT_LINE,
	"you did it!": DELIGHT_LINE,
	"try again!": RETRY_LINE,
	"let's try again!": RETRY_LINE,
	"almost!": RETRY_LINE,
	"have another go!": RETRY_LINE,
}

## Other phrases already spoken somewhere in the game whose meaning is one of
## the 36 lines. Used by `for_text()` so a `_speak(text)` call site can route
## through the pack without being rewritten. Exact manifest texts are matched
## first and need no row here.
const TEXT_ALIASES: Dictionary = {
	"i'm hungry.": "bunny_001_hungry",
	"thank you!": "bunny_005_thank_you",
	"yum! thank you!": "bunny_005_thank_you",
	"i'm sleepy...": "bunny_006_sleepy",
	"so sleepy... bed?": "bunny_006_sleepy",
	"i need a bath!": "bunny_008_bath",
	"bath time, please!": "bunny_008_bath",
	"let's play!": "bunny_009_play",
	"cuddle me?": "bunny_010_hug",
	"hug me, please?": "bunny_010_hug",
	"let's brush our teeth.": "aliz_016_brush_teeth",
	"let's tidy up!": "aliz_018_clean_up",
	"time to tidy up.": "aliz_018_clean_up",
	"time to clean up.": "aliz_018_clean_up",
	"let's go and cook!": "aliz_019_cooking",
	"time to sleep.": "aliz_017_bedtime",
	"it's bedtime.": "aliz_017_bedtime",
	"it is bedtime now.": "aliz_017_bedtime",
}

static var _manifest: RefCounted = null


# -----------------------------------------------------------------------------
# The mapping
# -----------------------------------------------------------------------------


## Ordered line ids for `event` (+ `detail`), or `[]` when the owner's list has
## nothing for that moment. Never raises; an unknown event is simply silent.
static func for_event(event: String, detail: String = "") -> Array:
	match event:
		EVENT_NEED:
			var need_line: String = String(NEED_LINES.get(detail, ""))
			return [need_line] if not need_line.is_empty() else []
		EVENT_TASK:
			var task_line: String = for_task(detail)
			return [task_line] if not task_line.is_empty() else []
		EVENT_ENCOURAGEMENT:
			return for_encouragement(detail)
	if SIMPLE_EVENTS.has(event):
		return (SIMPLE_EVENTS[event] as Array).duplicate()
	return []


## The first line for `event`, or "".
static func first_for(event: String, detail: String = "") -> String:
	var ids: Array = for_event(event, detail)
	return String(ids[0]) if not ids.is_empty() else ""


## Bunny's face that goes with `event`, or "" when the cue does not move the face.
static func face_for(event: String) -> String:
	if event == EVENT_WRONG_ITEM or event == EVENT_NEED_URGENT:
		return FACE_HMPH
	return ""


## `child_needs.gd` state -> line id, or "".
static func for_need(need: String) -> String:
	return String(NEED_LINES.get(need, ""))


## Object id / care kind / act name -> Aliz's learning line, or "".
## Tolerates a dotted semantic id ("kitchen.fridge.apple" -> "apple").
static func for_task(detail: String) -> String:
	var key: String = detail.strip_edges()
	if key.is_empty():
		return ""
	if TASK_LINES.has(key):
		return String(TASK_LINES[key])
	var local: String = key.get_slice(".", key.get_slice_count(".") - 1)
	return String(TASK_LINES.get(local, ""))


## Encouragement text -> line ids. `miss_count` >= 2 adds "It's okay. We can do
## it!" after "Let's try again!" -- the second miss gets the warmer answer.
## A phrase like "Try the apple!" (feeding_rules.gd) is a retry too.
static func for_encouragement(text: String, miss_count: int = 0) -> Array:
	var key: String = VoiceManifestScript.normalise_text(text)
	var line_id: String = String(ENCOURAGEMENT_LINES.get(key, ""))
	if line_id.is_empty() and key.begins_with("try the ") and key.ends_with("!"):
		line_id = RETRY_LINE
	if line_id.is_empty():
		return []
	if line_id == RETRY_LINE and miss_count >= 2:
		return [RETRY_LINE, SECOND_MISS_LINE]
	return [line_id]


## Any spoken English text -> the recorded line that says it, or "".
## Exact manifest text first (so every one of the 36 lines routes to itself),
## then the encouragement table, then the alias table. A text with no row
## returns "" and the caller keeps using TTS: nothing is ever invented.
static func for_text(text: String) -> String:
	var key: String = VoiceManifestScript.normalise_text(text)
	if key.is_empty():
		return ""
	var exact: String = manifest().line_id_for_text(key)
	if not exact.is_empty():
		return exact
	if ENCOURAGEMENT_LINES.has(key):
		return String(ENCOURAGEMENT_LINES[key])
	return String(TEXT_ALIASES.get(key, ""))


## Every event name this table knows, for the test that walks the whole table.
static func event_names() -> Array:
	var names: Array = SIMPLE_EVENTS.keys()
	names.append_array([EVENT_NEED, EVENT_TASK, EVENT_ENCOURAGEMENT])
	return names


## The shared manifest (loaded once per process). Tests may swap it.
static func manifest() -> RefCounted:
	if _manifest == null:
		_manifest = VoiceManifestScript.load_default()
	return _manifest


static func set_manifest(value: RefCounted) -> void:
	_manifest = value
