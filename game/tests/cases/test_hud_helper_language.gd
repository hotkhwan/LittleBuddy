extends RefCounted

## The line under the English prompt follows the family's helper language:
## Thai keeps the authored hint, another language uses its table, Arabic is
## laid out right-to-left, Off hides it, and the English top line never changes.

const HouseHud := preload("res://scripts/gameplay/house_hud.gd")
const L10n := preload("res://scripts/localization/localization.gd")


class FakeSaveService:
	extends Node
	var settings: Dictionary = {}

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value


func test_name() -> String:
	return "hud_helper_language"


func run():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var save := FakeSaveService.new()
	save.name = "SaveService"
	tree.root.add_child(save)

	var hud: Control = HouseHud.new()
	hud.call("build")
	var prompt: Label = hud.find_child("Prompt", true, false) as Label
	var hint: Label = hud.find_child("ThaiHint", true, false) as Label
	if prompt == null or hint == null:
		failures.append("the HUD has no Prompt / ThaiHint labels")
	else:
		# Default profile: Thai, authored hint wins.
		hud.call("set_prompt", "Time to drink!", "ดื่มนมกันเถอะ")
		if prompt.text != "Time to drink!":
			failures.append("the English top line changed: %s" % prompt.text)
		if hint.text != "ดื่มนมกันเถอะ":
			failures.append("Thai must show the authored hint, got '%s'" % hint.text)
		if hint.text_direction == Control.TEXT_DIRECTION_RTL:
			failures.append("Thai is not right-to-left")

		# Japanese, applied by the settings model -> visible on the next prompt.
		save.settings["helperLanguage"] = "ja"
		save.settings["thaiHints"] = true
		hud.call("set_prompt", "Time to drink!", "ดื่มนมกันเถอะ")
		if hint.text != "のむ時間だよ！":
			failures.append("Japanese helper expected, got '%s'" % hint.text)
		if prompt.text != "Time to drink!":
			failures.append("the English top line changed under Japanese: %s" % prompt.text)
		if String(hud.call("get_helper_language")) != "ja":
			failures.append("the HUD reports helper language %s" % hud.call("get_helper_language"))

		# Arabic: RTL direction on the label.
		save.settings["helperLanguage"] = "ar"
		hud.call("set_prompt", "Give Baby the bottle.", "ป้อนขวดนมให้เบบี๋")
		if hint.text != "أعطِ الطفل الزجاجة.":
			failures.append("Arabic helper expected, got '%s'" % hint.text)
		if hint.text_direction != Control.TEXT_DIRECTION_RTL:
			failures.append("Arabic helper must be TEXT_DIRECTION_RTL")
		if not hint.visible:
			failures.append("the Arabic helper is hidden")

		# A language change with no new prompt: refresh_helper_language() re-derives.
		save.settings["helperLanguage"] = "hi"
		hud.call("refresh_helper_language")
		if hint.text != "बेबी को बोतल दो।":
			failures.append("refresh_helper_language() did not switch to Hindi: '%s'" % hint.text)
		if hint.text_direction == Control.TEXT_DIRECTION_RTL:
			failures.append("Hindi must not stay right-to-left after Arabic")

		# Untranslated line in a non-Thai language: no helper, never the Thai.
		save.settings["helperLanguage"] = "zh"
		hud.call("set_prompt", "A brand new sentence.", "ประโยคใหม่")
		if hint.visible or not hint.text.is_empty():
			failures.append("an untranslated helper must hide, got '%s'" % hint.text)

		# Off: nothing under the prompt, English intact.
		save.settings["helperLanguage"] = "off"
		save.settings["thaiHints"] = false
		hud.call("set_prompt", "Time to drink!", "ดื่มนมกันเถอะ")
		if hint.visible or not hint.text.is_empty():
			failures.append("helper off must hide the line, got '%s'" % hint.text)
		if prompt.text != "Time to drink!":
			failures.append("the English top line changed when the helper was off")

		# The long-press word card follows the same rule.
		save.settings["helperLanguage"] = "ja"
		save.settings["thaiHints"] = true
		hud.call("show_word", "milk", "นม")
		if String(hud.call("get_word_thai_text")) != "ミルク":
			failures.append("the word card helper should be Japanese, got '%s'" % hud.call("get_word_thai_text"))
		if String(hud.call("get_word_text")) != "milk":
			failures.append("the word card's English changed")

	hud.free()
	tree.root.remove_child(save)
	save.free()
	L10n.set_helper_language(L10n.DEFAULT_HELPER_LANGUAGE)
	return failures
