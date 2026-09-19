extends RefCounted

## NOTHING IN THIS BUILD CAN TAKE MONEY, AND NO CHILD CAN REACH A LINK.
##
## This is the case that has to stay red-proof, because both properties it guards
## are invisible when they break. A payment SDK that is merely *present* looks
## like nothing on screen. An external link that becomes reachable from a
## child-facing screen looks like nothing until a four-year-old is on YouTube.
##
## ## What it asserts
##
##   1. **No billing anywhere.** The whole GDScript and scene tree, plus the
##      native iOS plugin source, is scanned for StoreKit, Play Billing, product
##      ids, receipts, paywalls and purchase calls. Zero occurrences, in
##      executable code.
##   2. **No browser launch anywhere.** `OS.shell_open()` does not appear in this
##      project. The Songs for Fun link is text a parent copies; the game never
##      hands anybody to a browser, an autoplaying video or a recommendation feed.
##   3. **The link and the prices live in exactly one file** -- Parent Corner --
##      and appear in no scene file and no child-facing script.
##   4. **The link is not on screen until a grown-up asks twice.** Held behind the
##      unchanged press-and-hold gate, then behind an explicit tap to reveal, then
##      behind a confirming second tap to copy. Asserted by driving the real panel.
##   5. **The gate was not weakened** to make room for any of this: still 3.0
##      seconds, still hiding the whole panel.
##   6. **No pressure on the child.** The Family Club copy is scanned for urgency,
##      scarcity, "unlock", countdowns, and anything that makes Buddy the one
##      asking. Buddy is never sad about money.
##
## ## Why the scanner strips comments
##
## Because this file's own subject matter is a list of things that must not appear,
## and so is the documentation of the files it scans. A doc comment that says
## "there is no StoreKit here" must not fail the test for saying so -- that is how
## a guard gets weakened until it protects nothing. So only EXECUTABLE code is
## scanned for API names, string CONTENTS are scanned separately for the link and
## the prices, and `_test_the_scanner_itself()` proves both directions before
## anything else runs. (Same technique, and the same reasoning, as
## `test_architecture_guard.gd`.)

const PARENT_SCENE: String = "res://scenes/parent/parent_settings.tscn"
const PARENT_SCRIPT: String = "res://scenes/parent/parent_settings.gd"
const ParentSettingsScript := preload("res://scenes/parent/parent_settings.gd")
const GateScript := preload("res://scripts/parent_settings/parental_gate.gd")
const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")

## Every directory of this project's own source. `ios/` is outside `res://` and is
## read through a relative path, like `test_speech_privacy_guard.gd` does.
const SCANNED_DIRS: Array[String] = [
	"res://scripts", "res://scenes", "res://addons",
]
const SCANNED_EXTENSIONS: Array[String] = ["gd", "tscn", "tres", "cfg"]
const NATIVE_SOURCES: Array[String] = [
	"../ios/speech_plugin/src/little_buddy_speech.mm",
	"../ios/speech_plugin/src/little_buddy_speech.h",
]

## Payment. None of this exists in this repository, and none of it may.
const FORBIDDEN_PAYMENT: Array[String] = [
	"StoreKit", "SKPayment", "SKProduct", "SKStoreProduct", "SKReceipt",
	"InAppPurchase", "in_app_purchase", "InAppStore",
	"GodotGooglePlayBilling", "BillingClient", "SkuDetails",
	"requestReview", "transactionObserver",
	"restore_purchases", "restorePurchases", "show_paywall", "paywall",
	"stripe", "braintree", "paypal", "checkout",
]

## Launching an external application. The game does not do this.
const FORBIDDEN_LAUNCH: Array[String] = [
	"shell_open", "shell_show_in_file_manager", "OS.execute", "OS.create_process",
]

## The single external link in the product, and the prices. Both are Parent Corner
## copy and must appear in no other file.
const SONGS_URL: String = "https://www.youtube.com/@Songsforfun-1"
const PRICE_FRAGMENTS: Array[String] = ["2.99", "THB 99"]

## Child-facing source. Nothing here may contain the link, a price, or a word
## about paying.
const CHILD_FACING_DIRS: Array[String] = [
	"res://scenes/baby_room", "res://scenes/house", "res://scenes/activities",
	"res://scenes/progression", "res://scenes/nursery", "res://scenes/main",
	"res://scenes/characters",
	"res://scripts/baby", "res://scripts/activities", "res://scripts/gameplay",
	"res://scripts/house", "res://scripts/kitchen", "res://scripts/care",
	"res://scripts/progression", "res://scripts/ui", "res://scripts/rewards",
]

## Words that must not be said to a child, in any string, anywhere child-facing.
const FORBIDDEN_CHILD_COPY: Array[String] = [
	"subscribe", "subscription", "free trial", "credit card", "payment",
	"buy now", "youtube", "paywall", "unlock me", "ask a grown-up to pay",
]

## Words that must not appear even in the GROWN-UP copy, because they are the
## vocabulary of pressure rather than of information.
const FORBIDDEN_PRESSURE: Array[String] = [
	"hurry", "limited time", "today only", "don't miss", "act now",
	"buddy is sad", "buddy misses", "buddy needs", "unlock me", "expires",
	"last chance", "countdown",
]

## The gate, unchanged.
const REQUIRED_HOLD_SECONDS: float = 3.0


func test_name() -> String:
	return "entitlement_no_purchase_guard"


func run():
	var failures: Array = []
	failures.append_array(_test_the_scanner_itself())
	failures.append_array(_test_no_billing_anywhere())
	failures.append_array(_test_nothing_launches_a_browser())
	failures.append_array(_test_the_link_and_prices_live_in_one_file())
	failures.append_array(_test_the_child_facing_source_is_clean())
	failures.append_array(_test_the_copy_does_not_pressure_anybody())
	failures.append_array(_test_the_gate_was_not_weakened())
	failures.append_array(_test_the_panel_behaves())
	return failures


# -- the scanner, tested before it is trusted ----------------------------------

func _test_the_scanner_itself():
	var failures: Array = []

	if _code_of("# no StoreKit here\nvar x := 1\n").contains("StoreKit"):
		failures.append("the scanner reads '#' comments; a doc comment that correctly says "
				+ "'no StoreKit' would fail this test for being accurate")
	if _code_of("## Never StoreKit.\nfunc f(): pass\n").contains("StoreKit"):
		failures.append("the scanner reads '##' doc comments")
	if not _code_of("var store := StoreKit.new()\n").contains("StoreKit"):
		failures.append("the scanner cannot see a token in executable code; it is vacuous")
	if _code_of('var s := "StoreKit"\n').contains("StoreKit"):
		failures.append("the scanner reads string bodies when looking for API names; a message "
				+ "mentioning StoreKit is not a dependency on it")

	# The string scanner is the other half, and it must see string CONTENTS.
	if not _strings_of('var url := "https://example.com"  # a comment\n').contains("example.com"):
		failures.append("the string scanner cannot see a string literal; the link checks below "
				+ "would all pass vacuously")
	if _strings_of('var x := 1  # https://example.com\n').contains("example.com"):
		failures.append("the string scanner reads comments as strings")

	# And it reads real files.
	if _read(PARENT_SCRIPT).length() < 500:
		failures.append("cannot read %s at all" % PARENT_SCRIPT)
	if _files_to_scan().size() < 100:
		failures.append("only %d source files were found; this project has far more, so the sweep "
				% _files_to_scan().size() + "is not actually sweeping")
	return failures


# -- 1. no billing --------------------------------------------------------------

func _test_no_billing_anywhere():
	var failures: Array = []
	for path: String in _files_to_scan():
		var code: String = _executable_of(path)
		for token: String in FORBIDDEN_PAYMENT:
			if code.contains(token):
				failures.append(
					("%s references %s. THIS BUILD HAS NO BILLING: no payment SDK, no payment "
					+ "credentials, no product ids, no receipts and no purchase path of any kind. "
					+ "The Family Club prices in Parent Corner are information for a grown-up and "
					+ "cannot be acted on. See docs/FAMILY_CLUB.md.") % [path, token])

	for relative: String in NATIVE_SOURCES:
		var native: String = _read(_res_relative(relative))
		if native.is_empty():
			continue
		for token: String in FORBIDDEN_PAYMENT:
			if native.contains(token):
				failures.append("the native plugin source %s references %s" % [relative, token])

	# And the entitlement layer itself offers no such method.
	var service: Object = load("res://scripts/entitlement/entitlement_service.gd").new()
	for method: String in ["purchase", "buy", "subscribe", "restore_purchases", "get_price"]:
		if service.has_method(method):
			failures.append("EntitlementService exposes %s()" % method)
	if service.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("the default service grants familyClub; nothing in this build may")
	if not service.is_active(EntitlementIds.FREE_STARTER):
		failures.append("the default service does not grant Free Starter")
	return failures


# -- 2. no browser --------------------------------------------------------------

func _test_nothing_launches_a_browser():
	var failures: Array = []
	for path: String in _files_to_scan():
		var code: String = _executable_of(path)
		for token: String in FORBIDDEN_LAUNCH:
			if code.contains(token):
				failures.append(
					("%s calls %s. The game never opens an external application. The one link in "
					+ "the product is shown to a grown-up as text to copy, so there is no path -- "
					+ "accidental or otherwise -- from a child's tap to a browser, an autoplaying "
					+ "video or a recommendation feed.") % [path, token])
	return failures


# -- 3. one file --------------------------------------------------------------

func _test_the_link_and_prices_live_in_one_file():
	var failures: Array = []
	var link_files: PackedStringArray = PackedStringArray()
	var price_files: PackedStringArray = PackedStringArray()

	for path: String in _files_to_scan():
		var text: String = _read(path)
		if text.contains(SONGS_URL) or text.to_lower().contains("youtube"):
			link_files.append(path)
		for fragment: String in PRICE_FRAGMENTS:
			if text.contains(fragment):
				if not price_files.has(path):
					price_files.append(path)

	if Array(link_files) != [PARENT_SCRIPT]:
		failures.append(
			("the Songs for Fun link appears in %s. It may live in exactly one place -- Parent "
			+ "Corner, behind the parental gate -- and in no scene file, so there is no second "
			+ "copy to be surfaced somewhere a child can reach.") % str(link_files))
	if Array(price_files) != [PARENT_SCRIPT]:
		failures.append("a Family Club price appears in %s; prices belong only in Parent Corner"
				% str(price_files))

	# The scene FILE must not contain the link: it is built in code, gated, and
	# hidden, and a copy stored in the .tscn could be made visible by an editor
	# change with no code review.
	var scene_text: String = _read(PARENT_SCENE)
	if scene_text.contains(SONGS_URL) or scene_text.to_lower().contains("youtube"):
		failures.append("%s contains the link as scene data" % PARENT_SCENE)

	# The URL is exactly the channel asked for -- not a video, not a playlist, and
	# with no autoplay or embed parameters.
	var url: String = ParentSettingsScript.SONGS_FOR_FUN_URL
	if url != SONGS_URL:
		failures.append("the panel's link is '%s', expected '%s'" % [url, SONGS_URL])
	for parameter: String in ["autoplay", "?", "&", "embed", "watch?v="]:
		if url.contains(parameter):
			failures.append("the link carries '%s'; it must be the plain channel address"
					% parameter)
	return failures


# -- 4. child-facing source ------------------------------------------------------

func _test_the_child_facing_source_is_clean():
	var failures: Array = []
	var scanned: int = 0
	for directory: String in CHILD_FACING_DIRS:
		var files: PackedStringArray = _files_under(directory)
		if files.is_empty():
			failures.append("%s holds no scannable file; either it moved or this sweep is blind"
					% directory)
		for path: String in files:
			scanned += 1
			var text: String = _read(path)
			if text.contains(SONGS_URL):
				failures.append("%s contains the Songs for Fun link; it is child-facing" % path)
			var strings: String = _strings_of(text).to_lower() if path.ends_with(".gd") \
					else text.to_lower()
			for phrase: String in FORBIDDEN_CHILD_COPY:
				if strings.contains(phrase):
					failures.append(
						("%s can say '%s' to a child. Nothing child-facing may mention paying, "
						+ "subscribing or an outside service; a child must never be the one asked.")
						% [path, phrase])
			for fragment: String in PRICE_FRAGMENTS:
				if text.contains(fragment):
					failures.append("%s contains the price fragment '%s'" % [path, fragment])
	if scanned < 40:
		failures.append("only %d child-facing files were scanned; too few to be a real sweep"
				% scanned)
	return failures


# -- 5. the words ---------------------------------------------------------------

func _test_the_copy_does_not_pressure_anybody():
	var failures: Array = []
	var lines: Array = []
	for line: String in ParentSettingsScript.FAMILY_CLUB_LINES:
		lines.append(line)
	lines.append(ParentSettingsScript.SONGS_FOR_FUN_BLURB)
	var joined: String = " ".join(PackedStringArray(lines)).to_lower()

	for phrase: String in FORBIDDEN_PRESSURE:
		if joined.contains(phrase):
			failures.append(
				("the Family Club copy says '%s'. Buddy is never sad, needy or disappointed about "
				+ "money, there is no countdown and nothing is dangled: this section is a grown-up "
				+ "reading a price list, not a sales pitch aimed at a family through their child.")
				% phrase)

	# It has to be honest about the four facts that matter.
	for required: String in ["free", "2.99", "99", "nothing can be bought"]:
		if not joined.contains(required):
			failures.append("the Family Club copy never mentions '%s'" % required)
	if not joined.contains("annual"):
		failures.append("the copy does not say anything about annual pricing; it must say there is "
				+ "none yet rather than leave a parent guessing")
	# No annual price may be invented.
	for invented: String in ["/ year", "per year", "a year", "29.99", "annually"]:
		if joined.contains(invented):
			failures.append("the copy quotes an annual price ('%s'); annual pricing is NOT FINAL "
					% invented + "and no number for it exists")
	if joined.contains("%"):
		failures.append("the copy contains a percentage")
	return failures


# -- 6. the gate ---------------------------------------------------------------

func _test_the_gate_was_not_weakened():
	var failures: Array = []
	var gate: Object = GateScript.new()
	if not is_equal_approx(float(gate.hold_duration), REQUIRED_HOLD_SECONDS):
		failures.append("the parental gate's default hold is %.2fs, not %.2fs"
				% [float(gate.hold_duration), REQUIRED_HOLD_SECONDS])
	gate.free()

	var scene_text: String = _read(PARENT_SCENE)
	var holds: int = scene_text.count("hold_duration = %.1f" % REQUIRED_HOLD_SECONDS)
	if holds < 2:
		failures.append(
			("%s sets a %.1fs hold on only %d gate(s); both the entry gate and the reset "
			+ "confirmation need one, and shortening either is how a child gets into Parent "
			+ "Corner.") % [PARENT_SCENE, REQUIRED_HOLD_SECONDS, holds])

	if not ParentSettingsScript.new().show_gate:
		failures.append("the panel no longer shows its gate by default")
	return failures


# -- 7. the real panel ---------------------------------------------------------

## Drives the actual scene: locked, opened, revealed, copied, closed.
func _test_the_panel_behaves():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree; cannot drive the parent panel"]
	var packed: PackedScene = load(PARENT_SCENE) as PackedScene
	if packed == null or not packed.can_instantiate():
		return ["%s cannot be instantiated" % PARENT_SCENE]

	var panel: Node = packed.instantiate()
	tree.root.add_child(panel)
	# Made the current scene so that the panel's defensive
	# `get_node_or_null("/root/SaveService")` is a legal lookup rather than an
	# engine error about absolute paths outside the active tree. (There is no
	# SaveService during a test run -- the runner detaches the autoloads -- and the
	# panel is built to cope with that; this only keeps the log clean.)
	var previous_scene: Node = tree.current_scene
	tree.current_scene = panel
	# `_ready()` does not fire for a node added to the root in the `--script`
	# runner (see `test_onboarding.gd`), and the whole Family Club section is built
	# there, so it is invoked by hand. Everything after this point is the real
	# panel, built by the real code, driven through its real signals.
	panel.call("_ready")

	# Locked: the gear and nothing else. No prices, no link, no section.
	if panel.call("is_family_club_visible"):
		failures.append("the Family Club section is on screen while the gate is still locked")
	if panel.call("is_songs_for_fun_visible"):
		failures.append("the Songs for Fun link is on screen while the gate is still locked")

	# Unlocked (as the gate itself does it): the section is there, the link is not.
	panel.call("open_settings")
	if not panel.call("is_family_club_visible"):
		failures.append("the Family Club section is missing from the unlocked panel")
	if panel.call("is_songs_for_fun_visible"):
		failures.append(
			"the Songs for Fun link is showing as soon as Parent Corner opens. It must take a "
			+ "deliberate grown-up tap: a parent adjusting Thai hints should never have an external "
			+ "link sitting open on the screen their child is about to be handed back.")

	var songs_button: Button = panel.find_child("SongsForFunButton", true, false) as Button
	var copy_button: Button = panel.find_child("SongsForFunCopyButton", true, false) as Button
	if songs_button == null or copy_button == null:
		failures.append("the Songs for Fun controls are missing from the panel")
		panel.queue_free()
		return failures

	# Tap 1: reveal.
	songs_button.pressed.emit()
	if not panel.call("is_songs_for_fun_visible"):
		failures.append("tapping Songs for Fun did not reveal the link")
	if copy_button.text != "Copy link":
		failures.append("the copy button starts armed; it must need a confirming tap")

	# Tap 2: arm. Tap 3: copy. Nothing is opened at any point.
	copy_button.pressed.emit()
	if copy_button.text == "Copy link":
		failures.append(
			"the first tap on the copy button acted immediately. Anything that leaves the app -- "
			+ "even to a clipboard -- gets a confirm step, so a mis-tap cannot do it.")
	copy_button.pressed.emit()
	if copy_button.text != "Copy link":
		failures.append("the copy button did not disarm after copying")

	# Closing puts it all away again.
	panel.call("close_settings")
	if panel.call("is_songs_for_fun_visible"):
		failures.append("the link survived the panel closing")
	if panel.call("is_family_club_visible"):
		failures.append("the Family Club section is still on screen after the panel closed")

	# Re-opening does not remember that the link was revealed.
	panel.call("open_settings")
	if panel.call("is_songs_for_fun_visible"):
		failures.append("re-opening Parent Corner restored the revealed link")

	# The panel's own entitlement view: free tier, nothing buyable.
	var entitlements: Object = panel.call("entitlement_service")
	if entitlements == null:
		failures.append("the panel has no entitlement service")
	else:
		if not entitlements.call("is_active", EntitlementIds.FREE_STARTER):
			failures.append("the panel's entitlement service does not grant Free Starter")
		if entitlements.call("is_active", EntitlementIds.FAMILY_CLUB):
			failures.append("the panel's entitlement service grants familyClub")

	panel.call("close_settings")
	tree.current_scene = previous_scene
	tree.root.remove_child(panel)
	panel.queue_free()
	return failures


# -- source scanning -------------------------------------------------------------

var _file_cache: PackedStringArray = PackedStringArray()


func _files_to_scan() -> PackedStringArray:
	if _file_cache.is_empty():
		for directory: String in SCANNED_DIRS:
			_file_cache.append_array(_files_under(directory))
	return _file_cache


func _files_under(directory: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return found
	for file_name: String in dir.get_files():
		var name: String = file_name.trim_suffix(".remap")
		for extension: String in SCANNED_EXTENSIONS:
			if name.ends_with("." + extension):
				found.append("%s/%s" % [directory, name])
				break
	for sub_directory: String in dir.get_directories():
		found.append_array(_files_under("%s/%s" % [directory, sub_directory]))
	found.sort()
	return found


## Executable code for a script; a scene/resource file as-is, because a node type
## or a property in a .tscn is a real dependency and has no comment syntax.
func _executable_of(path: String) -> String:
	var text: String = _read(path)
	return _code_of(text) if path.ends_with(".gd") else text


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## A path relative to `res://`, for the native sources one level above it.
func _res_relative(relative: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(relative).simplify_path()


## Comments removed, string bodies blanked.
static func _code_of(text: String) -> String:
	var out: String = ""
	for line: String in text.split("\n"):
		out += _strip_line(line, false) + "\n"
	return out


## Comments removed, string bodies KEPT -- for the link and the price copy, which
## only ever exist inside a string literal.
static func _strings_of(text: String) -> String:
	var out: String = ""
	for line: String in text.split("\n"):
		out += _strip_line(line, true) + "\n"
	return out


static func _strip_line(line: String, keep_string_contents: bool) -> String:
	var out: String = ""
	var quote: String = ""
	var index: int = 0
	while index < line.length():
		var character: String = line[index]
		if quote.is_empty():
			if character == "#":
				break
			if character == "\"" or character == "'":
				quote = character
			else:
				out += character
		else:
			if character == "\\":
				index += 1
			elif character == quote:
				quote = ""
			elif keep_string_contents:
				out += character
		index += 1
	return out
