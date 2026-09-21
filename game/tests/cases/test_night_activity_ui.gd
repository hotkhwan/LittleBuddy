extends RefCounted

func run():
	var failures: Array = []
	var hud: Node = load("res://scripts/feeding/feeding_hud.gd").new()
	hud.build()
	for button: Button in [hud.get_home_button(), hud.get_back_button()]:
		if button.custom_minimum_size.x < 200 or button.custom_minimum_size.y < 200:
			failures.append("Feeding navigation must retain a 200-square hit target")
		var style := button.get_theme_stylebox("normal")
		if float(style.get("expand_margin_left")) >= 0:
			failures.append("Feeding navigation art should be inset independently of input")
	hud.set_prompt("Give the baby some milk.", "ให้นมน้อง")
	if hud.get_prompt() != "Give the baby some milk.":
		failures.append("Prompt API changed")
	hud.set_star_count(12)
	hud.set_task_credit("half")
	hud.show_encouragement("Great!")
	if hud.get_encouragement() != "Great!":
		failures.append("Reward presentation API changed")
	hud.free()
	var scene: Node = load("res://scenes/baby_room/baby_room.tscn").instantiate()
	for name: String in ["StickerButton", "NextButton", "MicButton"]:
		var button := scene.get_node("UI/SafeArea/" + name) as Button
		var minimum: float = 240.0 if name == "MicButton" else 200.0
		if button.size.x < minimum or button.size.y < minimum:
			failures.append("Baby Room %s hit target changed" % name)
	scene.free()
	return failures
