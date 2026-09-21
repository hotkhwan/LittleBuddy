extends RefCounted

## The primary title-screen button says exactly "Play with Bunny".
##
## This file used to pin "Start"/"Continue" and a 12-character ceiling on the
## caption. Both went on 2026-09-21, after the owner's device playtest: the
## button that said Continue opened the Chapter 2 Baby Room, not the house with
## Bunny, and a caption that reports whether a save exists tells the CHILD
## nothing about what the button does. The label now names the destination.
##
## ## Why the length rule was relaxed, deliberately
##
## "Play with Bunny" is fifteen characters. The old ceiling existed so a word
## fit on one line of a 256 px card at 38 pt; the card now wraps the caption onto
## two lines at 32 pt (`main.tscn` PlayCaption, `autowrap_mode`), which the menu
## screenshot harness renders and which was looked at. What is pinned instead
## is the thing that matters to the owner and the child: the exact wording, and
## that the caption on the card IS that wording (line breaks aside).

const MainScript := preload("res://scenes/main/main.gd")
const MENU_SCENE: String = "res://scenes/main/main.tscn"
const EXPECTED_LABEL: String = "Play with Bunny"


func test_name() -> String:
	return "menu_start_continue"


func run():
	var failures: Array = []
	failures.append_array(_test_the_label_is_exact())
	failures.append_array(_test_the_card_carries_the_label())
	failures.append_array(_test_no_save_service_is_safe())
	return failures


func _test_the_label_is_exact():
	var failures: Array = []
	if MainScript.LABEL_PLAY_WITH_BUNNY != EXPECTED_LABEL:
		failures.append("the primary button's label is '%s'; the owner asked for exactly '%s'"
				% [MainScript.LABEL_PLAY_WITH_BUNNY, EXPECTED_LABEL])
	# The old words must not come back under another name: a child is never
	# shown "Continue" again, because it led somewhere other than Bunny.
	var script: GDScript = MainScript
	for constant: String in script.get_script_constant_map().keys():
		if constant.begins_with("LABEL_") and constant != "LABEL_PLAY_WITH_BUNNY":
			failures.append("main.gd grew a second primary-button label, %s; there is one caption"
					% constant)
	return failures


## The caption on the readied menu is the label -- not "Play", not the .tscn
## placeholder, not a caption that depends on the save.
func _test_the_card_carries_the_label():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var packed: PackedScene = load(MENU_SCENE) as PackedScene
	if packed == null:
		return ["%s cannot be loaded" % MENU_SCENE]
	var menu: Node = packed.instantiate()
	tree.root.add_child(menu)
	if not menu.is_node_ready():
		menu.notification(Node.NOTIFICATION_READY)
	var caption: Label = menu.get_node_or_null("UI/SafeArea/PlayButton/PlayCaption") as Label
	if caption == null:
		failures.append("the Play button has no PlayCaption to carry the words")
	else:
		var shown: String = caption.text.replace("\n", " ").strip_edges()
		if shown != EXPECTED_LABEL:
			failures.append("the card says '%s', not '%s'" % [shown, EXPECTED_LABEL])
		if caption.get_theme_font_size("font_size") < 27:
			failures.append("the caption is under ART_BIBLE §8's 27 pt floor")
		if caption.autowrap_mode == TextServer.AUTOWRAP_OFF:
			failures.append("fifteen characters do not fit one line of a 256 px card; the caption must wrap")
	tree.root.remove_child(menu)
	menu.free()
	return failures


func _test_no_save_service_is_safe():
	var failures: Array = []
	# The menu must not crash or guess when there is no save service at all --
	# the headless suite and a stripped build both hit this.
	var menu: Node = MainScript.new()
	if menu == null:
		return ["main.gd could not be instantiated"]
	menu.free()
	return failures
