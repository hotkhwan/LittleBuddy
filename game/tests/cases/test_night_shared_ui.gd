extends RefCounted

const Care := preload("res://scripts/care/care_overlay.gd")
const Art := preload("res://scripts/ui/activity_art.gd")
const Chrome := preload("res://scripts/ui/storybook_chrome.gd")
const Palette := preload("res://scripts/ui/palette.gd")

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
	return failures
