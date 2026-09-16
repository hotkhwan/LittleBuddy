## Pure, static intent matching for speech transcripts.
##
## No autoload dependency, no engine services touched — safe to unit test with
## `--script` (which does not load autoloads). Never persists or inspects raw
## audio; only ever operates on already-recognized text strings.
class_name IntentMatcher
extends RefCounted

## Lowercase, strip punctuation, collapse whitespace, trim.
## Safe against empty/whitespace-only input.
static func normalize(text: String) -> String:
	if text == "":
		return ""
	var lowered := text.to_lower()

	var punctuation_regex := RegEx.new()
	punctuation_regex.compile("[.,!?;:'\"()\\[\\]{}\\-_/\\\\]+")
	var stripped := punctuation_regex.sub(lowered, " ", true)

	var whitespace_regex := RegEx.new()
	whitespace_regex.compile("\\s+")
	var collapsed := whitespace_regex.sub(stripped, " ", true)

	return collapsed.strip_edges()


## True if the normalized transcript equals/contains any normalized accepted
## command, OR contains any target word as a whole word. Tolerant by design —
## MVP only requires the keyword (e.g. "milk") to be present somewhere.
static func matches(transcript: String, accepted_commands: Array, target_words: Array) -> bool:
	var normalized_transcript := normalize(transcript)
	if normalized_transcript == "":
		return false

	if accepted_commands != null:
		for command in accepted_commands:
			var normalized_command := normalize(String(command))
			if normalized_command == "":
				continue
			if normalized_transcript == normalized_command \
					or normalized_transcript.contains(normalized_command):
				return true

	if target_words != null:
		for word in target_words:
			var normalized_word := normalize(String(word))
			if normalized_word == "":
				continue
			if _contains_whole_word(normalized_transcript, normalized_word):
				return true

	return false


## Returns the matching activity's `activityId`, or "" if none match.
## `activities` is an Array of Dictionaries with `activityId`,
## `acceptedCommands`, and `targetWords` keys. Safe against malformed entries.
static func match_activity_id(transcript: String, activities: Array) -> String:
	if transcript == "" or activities == null:
		return ""

	for activity in activities:
		if typeof(activity) != TYPE_DICTIONARY:
			continue

		var accepted_commands: Array = activity.get("acceptedCommands", [])
		var target_words: Array = activity.get("targetWords", [])
		var activity_id: String = String(activity.get("activityId", ""))

		if activity_id == "":
			continue

		if matches(transcript, accepted_commands, target_words):
			return activity_id

	return ""


## Whole-word containment check on already-normalized (single-spaced) text.
static func _contains_whole_word(normalized_haystack: String, normalized_word: String) -> bool:
	var padded_haystack := " " + normalized_haystack + " "
	var padded_word := " " + normalized_word + " "
	return padded_haystack.find(padded_word) != -1
