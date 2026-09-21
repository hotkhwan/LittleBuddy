extends RefCounted

const Care := preload("res://scripts/care/care_overlay.gd")
const Art := preload("res://scripts/ui/activity_art.gd")
const Chrome := preload("res://scripts/ui/storybook_chrome.gd")
const Palette := preload("res://scripts/ui/palette.gd")
const HouseHud := preload("res://scripts/gameplay/house_hud.gd")

func test_name() -> String:
	return "night_shared_ui"

func run():
	var failures: Array = []
	for kind: String in Art.PATHS:
		if Art.texture_for(kind) == null:
			failures.append("activity artwork missing: " + kind)
	var bottle: Texture2D = Art.texture_for("bottle")
	if bottle != null:
		var image := bottle.get_image()
		if image == null or image.get_pixel(0, 0).a > 0.01:
			failures.append("bottle UI render needs a transparent background")
	var care := Care.new()
	care.size = Vector2(1821, 1024)
	care.begin("washFace")
	for name: String in ["InstructionCard", "CareFeedbackCard", "InstructionCard/CareActivityIcon"]:
		var control := care.get_node(name) as Control
		if control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			failures.append(name + " must not intercept scrubbing")
	var header := care.get_node("InstructionCard") as Control
	var footer := care.get_node("CareFeedbackCard") as Control
	if header.offset_bottom >= 1024.0 * 0.5 - Care.FACE_RADIUS:
		failures.append("care header overlaps the face interaction area")
	if 1024.0 + footer.offset_top <= 1024.0 * 0.5 + Care.FACE_RADIUS:
		failures.append("care footer overlaps the face interaction area")
	care.begin("giveBottle")
	if care.get("_bottle_art") == null:
		failures.append("drawn bottle must retain its texture between frames")
	care.free()
	var button := Button.new()
	button.custom_minimum_size = Vector2(240, 240)
	Chrome.button(button, Palette.MINT)
	if button.custom_minimum_size != Vector2(240, 240):
		failures.append("shared styling must not shrink touch targets")
	if button.get_theme_stylebox("pressed").shadow_size >= button.get_theme_stylebox("normal").shadow_size:
		failures.append("pressed state must visibly settle")
	button.free()
	var hud := HouseHud.new()
	hud.size = Vector2(1366, 1024)
	hud.build()
	hud.set_prompt("Put the toys in the toy box.", "เก็บของเล่นใส่กล่อง")
	hud.set_caption("A Day With Bunny\nClean Up and Good Night")
	var caption := hud.get_node("Caption") as Label
	if caption.autowrap_mode == TextServer.AUTOWRAP_OFF or caption.offset_right > HouseHud.CAPTION_RIGHT:
		failures.append("long story title must wrap before Home, never grow beneath it")
	var story_card := hud.get_node("StoryInstructionCard") as Control
	if story_card.mouse_filter != Control.MOUSE_FILTER_IGNORE or not story_card.visible:
		failures.append("story instructions need a visible, non-blocking card")
	hud.set_narration_covered(true)
	if story_card.visible:
		failures.append("story card must stand down when care narrates for itself")
	hud.free()
	return failures
