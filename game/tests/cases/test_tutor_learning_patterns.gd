extends RefCounted

const PATH := "res://content/tutor/learning_patterns.json"
const GRADES := ["preK", "kindergarten", "grade1", "grade2", "grade3", "grade4"]

func run():
	var failures: Array[String] = []
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return ["learning pattern catalog is missing"]
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return ["learning pattern catalog is not JSON object"]
	var patterns: Array = parsed.get("patterns", [])
	for grade: String in GRADES:
		var covered := false
		for pattern: Variant in patterns:
			if typeof(pattern) == TYPE_DICTIONARY and grade in pattern.get("grades", []): covered = true
		if not covered: failures.append("missing reusable pattern for %s" % grade)
	for pattern: Dictionary in patterns:
		var max_sentences := int(pattern.get("responseSentencesMax", 0))
		if max_sentences < 1 or max_sentences > 3:
			failures.append("%s must keep responses to 1-3 sentences" % pattern.get("patternId", "unknown"))
	return failures
