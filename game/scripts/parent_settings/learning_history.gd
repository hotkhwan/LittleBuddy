extends RefCounted
## The read-only "Learning history" a grown-up sees in Parent Corner: which of
## Aliz's lessons the child has completed, the stars each one paid, and when.
##
## Source: `settings.tutorProgress`, written by `lesson_engine.gd`
## (`save_progress()`): a map keyed by lessonId of
## `{stepIndex, stepCount, correctFirstTry, completed, rewardGranted}`. The
## lesson's title and star value come from its content file
## (`res://content/tutor/lessons/<lessonId>.json`, `title` and
## `completion.stars`), so this never invents a number the lesson did not pay.
##
## Dates: the engine's entry has no timestamp yet. When `completedAt` is present
## (ISO-8601 UTC string or unix seconds -- the field name this reader expects
## once `save_progress()` records it) it is shown in the device's local time;
## otherwise the row says "date not recorded". Nothing here writes.
##
## PURE. Corrupt entries are skipped one at a time; a corrupt map is "No lessons
## yet". Lesson ids are validated before they become a file path.

const LESSONS_DIR: String = "res://content/tutor/lessons/"
const EMPTY_TEXT: String = "No lessons yet"
const NO_DATE_TEXT: String = "date not recorded"
const MAX_ID_LENGTH: int = 48
const MONTHS: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

## `{lessonId, title, stars, completed, completedAtUnix (int, 0 = unknown),
## dateText, line}` for every lesson the map knows, completed lessons first,
## newest first, then by title.
static func entries(progress_map: Variant, lesson_lookup: Callable = Callable(), time_zone_bias_minutes: Variant = null) -> Array:
	var out: Array = []
	if typeof(progress_map) != TYPE_DICTIONARY:
		return out
	for key: Variant in (progress_map as Dictionary).keys():
		if not is_well_formed_id(key):
			continue
		var raw: Variant = (progress_map as Dictionary)[key]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		var lesson_id: String = String(key)
		var lesson: Dictionary = lesson_lookup.call(lesson_id) if lesson_lookup.is_valid() else load_lesson(lesson_id)
		var title: String = String(lesson.get("title", "")) if typeof(lesson.get("title", "")) == TYPE_STRING else ""
		if title.strip_edges().is_empty():
			title = lesson_id.replace("_", " ").capitalize()
		var raw_completed: Variant = entry.get("completed", false)
		var raw_granted: Variant = entry.get("rewardGranted", false)
		var completed: bool = typeof(raw_completed) == TYPE_BOOL and bool(raw_completed)
		var granted: bool = typeof(raw_granted) == TYPE_BOOL and bool(raw_granted)
		var stars: int = 0
		if completed or granted:
			var completion: Variant = lesson.get("completion", {})
			if typeof(completion) == TYPE_DICTIONARY:
				var raw_stars: Variant = (completion as Dictionary).get("stars", 0)
				if typeof(raw_stars) == TYPE_INT or typeof(raw_stars) == TYPE_FLOAT:
					stars = clampi(int(raw_stars), 0, 5)
		var when: int = completed_at_unix(entry.get("completedAt", null))
		var step_index: int = 0
		var step_count: int = 0
		var raw_index: Variant = entry.get("stepIndex", 0)
		var raw_count: Variant = entry.get("stepCount", 0)
		if typeof(raw_index) == TYPE_INT or typeof(raw_index) == TYPE_FLOAT:
			step_index = maxi(int(raw_index), 0)
		if typeof(raw_count) == TYPE_INT or typeof(raw_count) == TYPE_FLOAT:
			step_count = maxi(int(raw_count), 0)
		var date_text: String = date_text_for(when, time_zone_bias_minutes)
		out.append({
			"lessonId": lesson_id,
			"title": title,
			"stars": stars,
			"completed": completed or granted,
			"completedAtUnix": when,
			"dateText": date_text,
			"stepIndex": step_index,
			"stepCount": step_count,
			"line": _line(title, stars, completed or granted, date_text, step_index, step_count),
		})
	out.sort_custom(_newest_first)
	return out


## Only the completed lessons, the ones the row lists.
static func completed_entries(progress_map: Variant, lesson_lookup: Callable = Callable(), time_zone_bias_minutes: Variant = null) -> Array:
	var out: Array = []
	for entry: Dictionary in entries(progress_map, lesson_lookup, time_zone_bias_minutes):
		if bool(entry["completed"]):
			out.append(entry)
	return out


## The lines the row prints: one per completed lesson, or the empty text.
static func lines(progress_map: Variant, lesson_lookup: Callable = Callable(), time_zone_bias_minutes: Variant = null) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for entry: Dictionary in completed_entries(progress_map, lesson_lookup, time_zone_bias_minutes):
		out.append(String(entry["line"]))
	if out.is_empty():
		out.append(EMPTY_TEXT)
	return out


static func total_stars(progress_map: Variant, lesson_lookup: Callable = Callable()) -> int:
	var total: int = 0
	for entry: Dictionary in completed_entries(progress_map, lesson_lookup):
		total += int(entry["stars"])
	return total


## "Cat and Dog -- 1 star -- 20 Sep 2026" / "... -- date not recorded".
static func _line(title: String, stars: int, completed: bool, date_text: String, step_index: int, step_count: int) -> String:
	if not completed:
		var progress: String = "step %d of %d" % [mini(step_index + 1, maxi(step_count, 1)), step_count] if step_count > 0 else "in progress"
		return "%s -- %s" % [title, progress]
	var star_text: String = "1 star" if stars == 1 else "%d stars" % stars
	return "%s -- %s -- %s" % [title, star_text, date_text]


## `completedAt` as unix seconds: an int/float, or an ISO-8601 string
## ("2026-09-20T15:19:21Z" / with fraction); 0 for anything else.
static func completed_at_unix(raw: Variant) -> int:
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		var number: float = float(raw)
		return int(number) if is_finite(number) and number > 0.0 else 0
	if typeof(raw) != TYPE_STRING:
		return 0
	var text: String = String(raw).strip_edges().trim_suffix("Z")
	var dot: int = text.find(".")
	if dot >= 0:
		text = text.left(dot)
	if text.length() < 19 or text[4] != "-" or text[7] != "-" or text[10] != "T":
		return 0
	var unix: int = int(Time.get_unix_time_from_datetime_string(text))
	return unix if unix > 0 else 0


## "20 Sep 2026" in the device's zone (or the injected one); the no-date text for 0.
static func date_text_for(unix: int, time_zone_bias_minutes: Variant = null) -> String:
	if unix <= 0:
		return NO_DATE_TEXT
	var bias: int = int(time_zone_bias_minutes) if (typeof(time_zone_bias_minutes) == TYPE_INT or typeof(time_zone_bias_minutes) == TYPE_FLOAT) \
			else int(Time.get_time_zone_from_system().get("bias", 0))
	var local: Dictionary = Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	var month: int = clampi(int(local.get("month", 1)), 1, 12)
	return "%d %s %04d" % [int(local.get("day", 1)), MONTHS[month - 1], int(local.get("year", 1970))]


## The lesson file as data (`title`, `completion`), or {} when missing/corrupt.
static func load_lesson(lesson_id: String) -> Dictionary:
	if not is_well_formed_id(lesson_id):
		return {}
	var path: String = LESSONS_DIR + lesson_id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## snake_case, letters/digits/underscores, starts with a letter. Checked before
## an id is ever joined onto a path.
static func is_well_formed_id(lesson_id: Variant) -> bool:
	if typeof(lesson_id) != TYPE_STRING:
		return false
	var id: String = String(lesson_id)
	if id.is_empty() or id.length() > MAX_ID_LENGTH or id[0] < "a" or id[0] > "z":
		return false
	for index: int in range(id.length()):
		var character: String = id[index]
		var ok: bool = (character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "_"
		if not ok:
			return false
	return true


static func _newest_first(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["completed"]) != bool(b["completed"]):
		return bool(a["completed"])
	if int(a["completedAtUnix"]) != int(b["completedAtUnix"]):
		return int(a["completedAtUnix"]) > int(b["completedAtUnix"])
	return String(a["title"]) < String(b["title"])
