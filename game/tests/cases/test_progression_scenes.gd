extends RefCounted

## The two progression scenes really load, really instantiate, and really wire
## up -- a broken `ext_resource` path or a renamed unique node would otherwise
## only surface on the device.
##
## No autoloads are available here, which is the point: both screens must come
## up (silent, but complete) when `SaveService`, `TtsService` and `Sfx` are
## missing, exactly as they would in a scene preview.

const STICKER_BOOK_SCENE: String = "res://scenes/progression/sticker_book.tscn"
const SESSION_SUMMARY_SCENE: String = "res://scenes/progression/session_summary.tscn"

const ContentLibraryScript := preload("res://scripts/content/content_library.gd")


func test_name() -> String:
	return "progression_scenes"


func run():
	var failures: Array = []

	var root: Node = _root()
	if root == null:
		return ["no SceneTree root available; cannot instantiate scenes"]

	failures.append_array(_test_sticker_book(root))
	failures.append_array(_test_session_summary(root))

	return failures


func _test_sticker_book(root: Node) -> Array:
	var failures: Array = []

	var scene: PackedScene = _load_scene(STICKER_BOOK_SCENE, failures)
	if scene == null:
		return failures

	var screen: Node = scene.instantiate()
	if screen == null:
		return ["%s could not be instantiated" % STICKER_BOOK_SCENE]

	root.add_child(screen)
	# `_ready()` is deferred until the tree starts processing, which never
	# happens inside the runner -- so drive the public entry point directly.
	# It must be enough on its own to bring the whole screen up.
	screen.call("refresh")

	if not (screen is Control):
		failures.append("the sticker book root is %s, not a Control" % screen.get_class())

	# It must live inside the shared safe-area container, like baby_room.tscn.
	var safe_area: Node = screen.get_node_or_null("SafeArea")
	if safe_area == null:
		failures.append("the sticker book has no SafeArea node")
	elif safe_area.get_script() == null \
			or String(safe_area.get_script().resource_path) != "res://scripts/ui/safe_area.gd":
		failures.append("the sticker book's SafeArea does not use scripts/ui/safe_area.gd")

	# Always a visible way out for a child who cannot read.
	var back_button: Node = screen.get_node_or_null("%BackButton")
	if back_button == null:
		failures.append("the sticker book has no BackButton (dead end)")
	elif back_button is Button:
		var button: Button = back_button
		if button.disabled:
			failures.append("the sticker book back button is disabled (dead end)")
		if button.custom_minimum_size.x < 88.0 or button.custom_minimum_size.y < 88.0:
			failures.append("the back button is %s; too small for a child's finger"
					% str(button.custom_minimum_size))

	if not screen.has_signal("closed"):
		failures.append("the sticker book does not expose a 'closed' signal")

	# One cell per sticker in the library, and with no save service attached
	# nothing is unlocked -- so every card is a silhouette, none is missing.
	var grid: Node = screen.get_node_or_null("%StickerGrid")
	if grid == null:
		failures.append("the sticker book has no StickerGrid")
	else:
		var library: Object = ContentLibraryScript.new()
		library.load_all()
		var expected: int = library.get_stickers().size()
		if grid.get_child_count() != expected:
			failures.append("the grid built %d cells for %d stickers"
					% [grid.get_child_count(), expected])
		for cell: Node in grid.get_children():
			if not cell.has_method("get_sticker_id"):
				failures.append("a grid child is not a StickerCell")
				break
			if String(cell.call("get_sticker_id")).is_empty():
				failures.append("a grid cell has no sticker id")
				break
			if bool(cell.call("is_unlocked")):
				failures.append("a sticker was unlocked with no saved progress")
				break

	screen.queue_free()
	return failures


func _test_session_summary(root: Node) -> Array:
	var failures: Array = []

	var scene: PackedScene = _load_scene(SESSION_SUMMARY_SCENE, failures)
	if scene == null:
		return failures

	var summary: Node = scene.instantiate()
	if summary == null:
		return ["%s could not be instantiated" % SESSION_SUMMARY_SCENE]

	root.add_child(summary)

	for signal_name: String in ["play_again", "closed"]:
		if not summary.has_signal(signal_name):
			failures.append("the session summary does not expose a '%s' signal" % signal_name)

	for button_path: String in ["%PlayAgainButton", "%CloseButton"]:
		var button_node: Node = summary.get_node_or_null(button_path)
		if button_node == null:
			failures.append("the session summary has no %s" % button_path)
		elif button_node is Button and (button_node as Button).disabled:
			failures.append("%s is disabled (dead end)" % button_path)

	var sticker: Dictionary = {
		"stickerId": "milkSticker", "word": "milk", "displayName": "Milk",
		"color": "#FFFFFF", "primitive": "capsule",
		"celebrationPhrase": "You got the milk sticker!",
	}
	summary.call("show_summary", 3, 12, [sticker])

	var earned_label: Node = summary.get_node_or_null("%EarnedLabel")
	if earned_label is Label and (earned_label as Label).text != "+3":
		failures.append("the earned label reads '%s', expected '+3'" % (earned_label as Label).text)

	var total_label: Node = summary.get_node_or_null("%TotalLabel")
	if total_label is Label and (total_label as Label).text != "12":
		failures.append("the total label reads '%s', expected '12'" % (total_label as Label).text)

	var sticker_row: Node = summary.get_node_or_null("%StickerRow")
	if sticker_row is Control and not (sticker_row as Control).visible:
		failures.append("a newly unlocked sticker was not shown on the summary")

	# No sticker this time -> the row hides rather than showing an empty card.
	summary.call("reset")
	summary.call("show_summary", 1, 13, [])
	if sticker_row is Control and (sticker_row as Control).visible:
		failures.append("the sticker row stayed visible with no new sticker")

	summary.queue_free()
	return failures


func _load_scene(path: String, failures: Array) -> PackedScene:
	if not ResourceLoader.exists(path):
		failures.append("%s does not exist" % path)
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		failures.append("%s did not load as a PackedScene" % path)
		return null
	if not scene.can_instantiate():
		failures.append("%s cannot be instantiated (broken resource reference?)" % path)
		return null
	return scene


func _root() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null
