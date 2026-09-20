class_name AnswerMatcher
extends RefCounted
## Matches a child's transcript against a lesson step's expected answers.
##
## Pure and static: no nodes, no engine types, no state. Used by `LessonEngine`
## and testable with a bare `String`.
##
## ## What counts as a match (in order)
##
## 1. **exact** -- the normalised transcript equals a normalised expected answer
##    ("Apple!" vs "apple"; "It's an apple" vs "it's an apple").
## 2. **contains** -- an expected answer appears as a whole-word run inside the
##    transcript ("um it's a red apple" contains "apple" and "red apple").
##    Short transcripts from a 3-year-old are rarely a bare word, so this is the
##    common path.
## 3. **fuzzy** -- one-letter slip (insert, delete, substitute or adjacent swap)
##    on a word of at least `FUZZY_MIN_LENGTH` letters ("aple" -> "apple",
##    "bananna" -> "banana"). Never on short words: "cat" vs "car" and "red" vs
##    "bed" stay distinct, because there the slip IS a different word.
##
## Everything else is no match. The caller decides between "incorrect" and
## "unclear"; `is_blank()` tells it whether the transcript held any words.
##
## ## Normalisation
##
## Lower-case, apostrophes removed ("it's" -> "its"), every other punctuation
## mark turned into a space, whitespace collapsed. Filler and function words at
## the edges are stripped so "the apple" / "an apple" / "it is an apple please"
## all reduce to "apple". Filler is only stripped from the OUTSIDE of the phrase
## so "orange orange" or "red apple" keep their shape.

const FUZZY_MIN_LENGTH: int = 4

## Words that carry no answer content. Stripped from both ends of a phrase.
const FILLER_WORDS: Array[String] = [
	"a", "an", "the", "it", "its", "is", "this", "that", "they", "theyre",
	"there", "here", "um", "uh", "er", "hmm", "please", "yes", "yeah", "ok", "okay",
	"i", "think", "maybe", "some", "from", "with", "of",
]


## Result: `{matched: String, kind: "exact"|"contains"|"fuzzy"|""}`. `matched`
## is the expected answer (as written in the lesson) that the transcript hit,
## or "" when nothing matched.
static func match_answer(transcript: String, expected_answers: Array) -> Dictionary:
	var spoken: String = normalize(transcript)
	if spoken.is_empty():
		return {"matched": "", "kind": ""}
	var spoken_tokens: PackedStringArray = spoken.split(" ", false)
	var stripped: String = strip_filler(spoken)
	var stripped_tokens: PackedStringArray = stripped.split(" ", false)

	# 1. exact
	for raw: Variant in expected_answers:
		var expected: String = normalize(String(raw))
		if expected.is_empty():
			continue
		if spoken == expected or stripped == strip_filler(expected):
			return {"matched": String(raw), "kind": "exact"}

	# 2. contains (whole-word run)
	for raw: Variant in expected_answers:
		var expected: String = strip_filler(normalize(String(raw)))
		if expected.is_empty():
			continue
		var expected_tokens: PackedStringArray = expected.split(" ", false)
		if _contains_run(spoken_tokens, expected_tokens):
			return {"matched": String(raw), "kind": "contains"}

	# 3. fuzzy -- one-letter slip on a long enough word
	for raw: Variant in expected_answers:
		var expected: String = strip_filler(normalize(String(raw)))
		if expected.is_empty():
			continue
		var expected_tokens: PackedStringArray = expected.split(" ", false)
		if expected_tokens.size() == 1:
			var word: String = expected_tokens[0]
			if word.length() >= FUZZY_MIN_LENGTH:
				for token: String in stripped_tokens:
					if token.length() >= FUZZY_MIN_LENGTH and is_one_slip(token, word):
						return {"matched": String(raw), "kind": "fuzzy"}
		else:
			# Multi-word answer: the whole stripped phrase within one slip.
			var joined: String = expected_tokens[0]
			for i: int in range(1, expected_tokens.size()):
				joined += expected_tokens[i]
			var spoken_joined: String = "".join(stripped_tokens)
			if joined.length() >= FUZZY_MIN_LENGTH and is_one_slip(spoken_joined, joined):
				return {"matched": String(raw), "kind": "fuzzy"}

	return {"matched": "", "kind": ""}


## True when the transcript holds no letters or digits at all -- silence, a
## timeout, or pure noise. The engine reports that as "unclear", never "incorrect".
static func is_blank(transcript: String) -> bool:
	return normalize(transcript).is_empty()


## Lower-case, no apostrophes, punctuation to spaces, single spaces, trimmed.
static func normalize(text: String) -> String:
	var lowered: String = text.strip_edges().to_lower()
	lowered = lowered.replace("'", "").replace("’", "").replace("‘", "")
	var out: String = ""
	var last_space: bool = true
	for character: String in lowered:
		var code: int = character.unicode_at(0)
		var keep: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code > 127
		if keep:
			out += character
			last_space = false
		elif not last_space:
			out += " "
			last_space = true
	return out.strip_edges()


## Removes filler words from both ends of an already-normalised phrase. Leaves
## at least one word: a transcript that is ALL filler ("um the") comes back as
## its last word so it can still be judged (and found not to match).
static func strip_filler(normalized: String) -> String:
	var tokens: PackedStringArray = normalized.split(" ", false)
	var start: int = 0
	var end: int = tokens.size()
	while start < end - 1 and FILLER_WORDS.has(tokens[start]):
		start += 1
	while end - 1 > start and FILLER_WORDS.has(tokens[end - 1]):
		end -= 1
	var kept: PackedStringArray = PackedStringArray()
	for i: int in range(start, end):
		kept.append(tokens[i])
	return " ".join(kept)


## Damerau-style: true when `a` becomes `b` with at most one insertion,
## deletion, substitution or adjacent transposition. Exact equality also counts.
static func is_one_slip(a: String, b: String) -> bool:
	if a == b:
		return true
	var la: int = a.length()
	var lb: int = b.length()
	if absi(la - lb) > 1:
		return false
	if la == lb:
		var diffs: Array[int] = []
		for i: int in range(la):
			if a[i] != b[i]:
				diffs.append(i)
				if diffs.size() > 2:
					return false
		if diffs.size() == 1:
			return true
		if diffs.size() == 2 and diffs[1] == diffs[0] + 1:
			return a[diffs[0]] == b[diffs[1]] and a[diffs[1]] == b[diffs[0]]
		return false
	# Lengths differ by one: the longer string with one character removed.
	var longer: String = a if la > lb else b
	var shorter: String = b if la > lb else a
	var i: int = 0
	var j: int = 0
	var skipped: bool = false
	while i < longer.length() and j < shorter.length():
		if longer[i] == shorter[j]:
			i += 1
			j += 1
		elif skipped:
			return false
		else:
			skipped = true
			i += 1
	return true


static func _contains_run(haystack: PackedStringArray, needle: PackedStringArray) -> bool:
	if needle.is_empty() or needle.size() > haystack.size():
		return false
	for start: int in range(haystack.size() - needle.size() + 1):
		var all_equal: bool = true
		for k: int in range(needle.size()):
			if haystack[start + k] != needle[k]:
				all_equal = false
				break
		if all_equal:
			return true
	return false
