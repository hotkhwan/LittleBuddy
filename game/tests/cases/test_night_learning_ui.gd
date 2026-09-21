extends RefCounted

const Hud := preload("res://scripts/tutor/ui/tutor_hud.gd")
const Dress := preload("res://scenes/dress_up/dress_up.tscn")

func test_name() -> String:
	return "night_learning_ui"

func run():
	var failures: Array = []
	var hud := Hud.new()
	hud.build()
	var safe: Control = hud.get_node("SafeArea")
	safe.size = Vector2(1773, 992)
	hud.show_answer_cards(["apple_red", "banana_yellow", "orange_orange"])
	var row: HBoxContainer = safe.get_node("AnswerCards")
	if not safe.get_node("AnswerHint").visible:
		failures.append("answer group must explain the touch alternative")
	for button: Button in row.get_children():
		if button.custom_minimum_size.x < Hud.ANSWER_CARD_SIZE.x or button.custom_minimum_size.y < Hud.ANSWER_CARD_SIZE.y:
			failures.append("answer touch target was reduced")
	hud.hide_answer_cards()
	if safe.get_node("AnswerHint").visible:
		failures.append("answer hint must hide with cards")
	hud.set_banner("success")
	if not safe.get_node("StateEmblem").visible or hud.banner_text() != "Great job!":
		failures.append("success feedback must preserve session text")
	hud.set_subtitle("มาเรียนรู้ด้วยกันนะ")
	if safe.get_node("StateEmblem").visible or hud.subtitle_text() != "มาเรียนรู้ด้วยกันนะ":
		failures.append("state emblem must not cover helper subtitle")
	hud.free()
	var screen := Dress.instantiate()
	# Scene contract remains stable for routing and existing automation.
	for path: String in ["UI/SafeArea/BackButton", "UI/SafeArea/SwatchRow", "UI/SafeArea/HintLabel", "Camera3D"]:
		if screen.get_node_or_null(path) == null:
			failures.append("missing wardrobe node " + path)
	screen.free()
	return failures
