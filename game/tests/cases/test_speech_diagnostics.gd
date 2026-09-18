extends RefCounted

## The parent speech diagnostic: it must name the ROOT cause.
##
## The whole value of this screen is that it answers "is the microphone
## working?" without a Mac and a UDID. A verdict that names the first symptom
## rather than the actual blocker sends a parent looking in the wrong place --
## telling someone "not understood" when iOS never granted permission is worse
## than saying nothing, so the ordering below is the thing under test.
##
## Also pinned: every row formats, including the empty and missing cases, because
## a blank value reads as a broken panel rather than as "nothing yet".

const Diag := preload("res://scripts/ui/speech_diagnostics_panel.gd")


func test_name() -> String:
	return "speech_diagnostics"


func run():
	var failures: Array = []
	failures.append_array(_test_verdict_names_the_root_cause())
	failures.append_array(_test_values_never_render_blank())
	failures.append_array(_test_every_row_has_a_key_and_label())
	failures.append_array(_test_touch_is_never_threatened())
	return failures


func _working() -> Dictionary:
	return {
		"platform": "iOS",
		"backend": "ios",
		"nativeSingletonPresent": true,
		"isAvailable": true,
		"hasPermission": true,
		"speechEnabledSetting": true,
		"isListening": false,
		"listenCount": 4,
		"recognizedCount": 3,
		"failedCount": 1,
		"fallbackActive": false,
	}


func _test_verdict_names_the_root_cause():
	var failures: Array = []

	var empty: String = Diag.verdict_line({}).to_lower()
	if not empty.contains("not running"):
		failures.append("an absent service should say so; got '%s'" % empty)

	var off: Dictionary = _working()
	off["speechEnabledSetting"] = false
	off["hasPermission"] = false
	off["isAvailable"] = false
	var off_line: String = Diag.verdict_line(off).to_lower()
	if not off_line.contains("switched off"):
		failures.append(("speech disabled in settings must be reported FIRST -- it is the one "
				+ "cause the parent switched on themselves. Got: '%s'") % off_line)

	var no_plugin: Dictionary = _working()
	no_plugin["isAvailable"] = false
	no_plugin["nativeSingletonPresent"] = false
	no_plugin["hasPermission"] = false
	var plugin_line: String = Diag.verdict_line(no_plugin).to_lower()
	if not plugin_line.contains("plugin"):
		failures.append(("a missing iOS plugin must be named as the cause rather than reported "
				+ "as a permission problem. Got: '%s'") % plugin_line)

	var denied: Dictionary = _working()
	denied["hasPermission"] = false
	var denied_line: String = Diag.verdict_line(denied).to_lower()
	if not denied_line.contains("permission"):
		failures.append("a denied microphone must say 'permission'; got '%s'" % denied_line)

	var untried: Dictionary = _working()
	untried["listenCount"] = 0
	untried["recognizedCount"] = 0
	var untried_line: String = Diag.verdict_line(untried).to_lower()
	if not untried_line.contains("nothing has been tried"):
		failures.append(("with zero attempts the panel must say so rather than imply failure. "
				+ "Got: '%s'") % untried_line)

	var deaf: Dictionary = _working()
	deaf["recognizedCount"] = 0
	var deaf_line: String = Diag.verdict_line(deaf).to_lower()
	if not deaf_line.contains("last heard"):
		failures.append(("listening-but-never-understood should point at the transcript row, "
				+ "which is the next thing to look at. Got: '%s'") % deaf_line)

	var ok_line: String = Diag.verdict_line(_working()).to_lower()
	if not ok_line.contains("working"):
		failures.append("a healthy stack must say it is working; got '%s'" % ok_line)
	return failures


func _test_values_never_render_blank():
	var failures: Array = []
	var cases: Array = [
		["hasPermission", true, "yes"],
		["hasPermission", false, "no"],
		["lastTranscript", "", "—"],
		["lastTranscript", "  milk  ", "milk"],
		["lastFailureReason", null, "—"],
		["listenCount", 7, "7"],
	]
	for case: Array in cases:
		var got: String = Diag.format_value(String(case[0]), case[1])
		if got != String(case[2]):
			failures.append("format_value(%s, %s) gave '%s', expected '%s'"
					% [String(case[0]), str(case[1]), got, String(case[2])])
	return failures


func _test_every_row_has_a_key_and_label():
	var failures: Array = []
	if Diag.ROWS.size() < 10:
		failures.append("only %d diagnostic rows; the brief lists permission, availability, "
				% Diag.ROWS.size() + "on-device support, listening state, transcript, error, "
				+ "locale and fallback at minimum")
	var seen: Array = []
	for row: Dictionary in Diag.ROWS:
		var key: String = String(row.get("key", ""))
		if key.is_empty() or String(row.get("label", "")).is_empty():
			failures.append("a diagnostic row is missing its key or label: %s" % str(row))
		if seen.has(key):
			failures.append("duplicate diagnostic row '%s'" % key)
		seen.append(key)
	for required: String in ["hasPermission", "isAvailable", "isListening",
			"lastTranscript", "lastFailureReason", "locale", "fallbackActive"]:
		if not seen.has(required):
			failures.append("the diagnostic never shows '%s', which the brief asks for" % required)
	return failures


func _test_touch_is_never_threatened():
	var failures: Array = []
	# Every verdict that reports speech as unusable must also reassure that the
	# game is still playable, for the same reason the child-facing panel does.
	for broken: Dictionary in [{}, _broken("isAvailable"), _broken("nativeSingletonPresent")]:
		var line: String = Diag.verdict_line(broken).to_lower()
		if not line.contains("touch"):
			failures.append(("a verdict that reports speech unusable must say touch play still "
					+ "works: '%s'") % line)
	return failures


func _broken(key: String) -> Dictionary:
	var diag: Dictionary = _working()
	diag["isAvailable"] = false
	diag["hasPermission"] = false
	diag[key] = false
	return diag
