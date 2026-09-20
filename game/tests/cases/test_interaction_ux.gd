extends RefCounted

## The in-game way out and the build number: the HUD's Home button, the pause
## card behind it, and the version label in the corner.
##
## Everything runs without `_ready()` and without the scene tree. The world is
## a stand-in that answers exactly what the HUD asks of it
## (`get_character()`, `leave_to_home()`), so the wiring is asserted rather than
## the lead's implementation of leaving.

const HouseHud := preload("res://scripts/gameplay/house_hud.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const GameVersion := preload("res://scripts/content_packs/game_version.gd")
const Joystick := preload("res://scripts/input/virtual_joystick.gd")
const GestureHint := preload("res://scripts/onboarding/gesture_hint.gd")
const IconGlyph := preload("res://scripts/progression/icon_glyph.gd")
const Palette := preload("res://scripts/ui/palette.gd")

## Every viewport the game ships at, plus the reference.
const VIEWPORTS: Array = [
	Vector2(1366.0, 1024.0), Vector2(1334.0, 750.0), Vector2(2340.0, 1080.0), Vector2(1180.0, 820.0),
]


class FakeCharacter extends Node3D:
	var disabled: bool = false

	func get_state_name() -> String:
		return "disabled" if disabled else "idle"

	func set_disabled(value: bool) -> void:
		disabled = value


class FakeNav extends Node:
	var taps_enabled: bool = true


class FakeWorld extends Node:
	var character: Node3D = null
	var left: int = 0

	func get_character() -> Node:
		return character

	func leave_to_home() -> bool:
		left += 1
		return true


class FakeWorldWithoutHook extends Node:
	var character: Node3D = null

	func get_character() -> Node:
		return character


func test_name() -> String:
	return "interaction_ux"


func run():
	var failures: Array = []
	failures.append_array(_test_version_label_reads_the_build())
	failures.append_array(_test_version_label_keeps_clear_of_next_and_the_stick())
	failures.append_array(_test_home_button_is_there_and_clear_of_the_caption())
	failures.append_array(_test_pause_menu_buttons_are_wired())
	failures.append_array(_test_home_asks_the_world_to_leave())
	failures.append_array(_test_home_without_a_hook_is_not_a_dead_end())
	failures.append_array(_test_pause_holds_the_world_and_gives_it_back())
	failures.append_array(_test_gesture_hint_is_an_arrow_in_the_palette())
	failures.append_array(_test_icon_backing_is_opt_in())
	return failures


# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------

func _test_version_label_reads_the_build():
	var failures: Array = []
	var hud: Control = HouseHud.new()
	hud.call("build")
	var text: String = String(hud.call("get_version_text"))
	if text != GameVersion.BUILD:
		failures.append("interaction_ux: the version label says '%s'; GameVersion.BUILD is '%s'" % [text, GameVersion.BUILD])
	if not GameVersion.is_valid(text):
		failures.append("interaction_ux: the version label '%s' is not MAJOR.MINOR.PATCH" % text)
	var label: Label = hud.call("get_version_label")
	if label == null or not label.visible:
		failures.append("interaction_ux: the version label is missing or hidden")
	elif label.get_theme_font_size("font_size") > 20:
		failures.append("interaction_ux: the version label is %d pt; it is not for the child and must stay small"
				% label.get_theme_font_size("font_size"))
	hud.free()
	return failures


func _test_version_label_keeps_clear_of_next_and_the_stick():
	var failures: Array = []
	for view: Vector2 in VIEWPORTS:
		for insets: Vector4 in [Vector4(24.0, 16.0, 24.0, 16.0), Vector4(24.0, 16.0, 24.0, 44.0), Vector4(60.0, 16.0, 60.0, 34.0)]:
			var rect: Rect2 = HouseHud.version_label_rect(view, insets)
			var next: Rect2 = HouseHud.button_rects(view)["next"]
			if rect.intersects(next):
				failures.append("interaction_ux: at %s with insets %s the version label %s sits under Next %s"
						% [str(view), str(insets), str(rect), str(next)])
			if not Rect2(Vector2.ZERO, view).encloses(rect):
				failures.append("interaction_ux: at %s the version label %s leaves the screen" % [str(view), str(rect)])
			if rect.position.x < view.x * 0.5 or rect.position.y < view.y * 0.5:
				failures.append("interaction_ux: at %s the version label %s is not bottom-right" % [str(view), str(rect)])
			if rect.end.y > view.y - insets.w + 0.01:
				failures.append("interaction_ux: at %s the version label %s ignores the bottom inset %.0f"
						% [str(view), str(rect), insets.w])
			var stick: Control = Joystick.new()
			stick.size = view
			stick.call("build")
			var zone: Rect2 = stick.call("get_activation_rect")
			if zone.size != Vector2.ZERO and rect.intersects(zone):
				failures.append("interaction_ux: at %s the version label %s sits in the thumbstick zone %s"
						% [str(view), str(rect), str(zone)])
			stick.free()
	return failures


# ---------------------------------------------------------------------------
# Home
# ---------------------------------------------------------------------------

func _test_home_button_is_there_and_clear_of_the_caption():
	var failures: Array = []
	var hud: Control = HouseHud.new()
	hud.call("build")
	var home: Button = hud.call("get_home_button")
	if home == null:
		return ["interaction_ux: the HUD has no Home button"]
	if not home.visible:
		failures.append("interaction_ux: Home starts hidden")
	for view: Vector2 in VIEWPORTS:
		var rect: Rect2 = HouseHud.home_button_rect(view)
		if rect.size.x < 96.0 or rect.size.y < 96.0:
			failures.append("interaction_ux: Home is %s; too small for a thumb" % str(rect.size))
		if not Rect2(Vector2.ZERO, view).encloses(rect):
			failures.append("interaction_ux: at %s Home %s leaves the screen" % [str(view), str(rect)])
		if rect.position.x < view.x * 0.7 or rect.end.y > view.y * 0.3:
			failures.append("interaction_ux: at %s Home %s is not top-right" % [str(view), str(rect)])
		# The level caption is anchored top-right too; it must have made room.
		var caption: Rect2 = Rect2(view.x - 400.0, 30.0, 400.0 + HouseHud.CAPTION_RIGHT, 90.0)
		if rect.intersects(caption):
			failures.append("interaction_ux: at %s Home %s overlaps the level caption %s" % [str(view), str(rect), str(caption)])
		var stars: Rect2 = Rect2(36.0, 26.0, 224.0, 60.0)
		if rect.intersects(stars):
			failures.append("interaction_ux: Home overlaps the star counter")
	# Home hides with the rest of the play chrome (the summary owns the screen).
	hud.call("set_play_chrome_visible", false)
	if home.visible:
		failures.append("interaction_ux: Home stays visible when the play chrome is off")
	hud.call("set_play_chrome_visible", true)
	if not home.visible:
		failures.append("interaction_ux: Home did not come back with the play chrome")
	var house: Node = home.get_node_or_null("HouseGlyph")
	if house == null:
		failures.append("interaction_ux: Home has no house picture; a pre-reader cannot tell it from a blank disc")
	hud.free()
	return failures


func _test_pause_menu_buttons_are_wired():
	var failures: Array = []
	var menu: Control = PauseMenu.new()
	menu.call("build")
	if menu.visible:
		failures.append("interaction_ux: the pause card starts open")
	var buttons: Dictionary = menu.call("get_buttons")
	for key: String in ["continue", "home", "settings"]:
		var button: Variant = buttons.get(key, null)
		if not (button is Button):
			failures.append("interaction_ux: the pause card has no '%s' button" % key)
			continue
		var b: Button = button
		if b.custom_minimum_size.x < 240.0 or b.custom_minimum_size.y < 72.0:
			failures.append("interaction_ux: '%s' is %s; under the child target floor" % [key, str(b.custom_minimum_size)])
		if b.text.strip_edges().is_empty():
			failures.append("interaction_ux: '%s' has no label" % key)
		for word: String in ["quit", "exit", "lose", "wrong", "fail"]:
			if b.text.to_lower().contains(word) or String(menu.call("get_title_text")).to_lower().contains(word):
				failures.append("interaction_ux: the pause card says '%s'" % word)
	var fired: Dictionary = {"continue": 0, "home": 0, "settings": 0, "closed": 0, "opened": 0}
	menu.connect("continue_pressed", func() -> void: fired["continue"] += 1)
	menu.connect("home_pressed", func() -> void: fired["home"] += 1)
	menu.connect("settings_pressed", func() -> void: fired["settings"] += 1)
	menu.connect("closed", func() -> void: fired["closed"] += 1)
	menu.connect("opened", func() -> void: fired["opened"] += 1)

	menu.call("open")
	if not bool(menu.call("is_open")) or fired["opened"] != 1:
		failures.append("interaction_ux: open() did not open the card")
	(buttons["continue"] as Button).pressed.emit()
	if fired["continue"] != 1 or fired["closed"] != 1 or bool(menu.call("is_open")):
		failures.append("interaction_ux: Continue did not close the card (continue=%d closed=%d)" % [fired["continue"], fired["closed"]])
	menu.call("open")
	(buttons["home"] as Button).pressed.emit()
	if fired["home"] != 1:
		failures.append("interaction_ux: Home did not emit home_pressed")
	(buttons["settings"] as Button).pressed.emit()
	if fired["settings"] != 1:
		failures.append("interaction_ux: Grown-ups did not emit settings_pressed")
	menu.free()
	return failures


func _mounted_hud(world: Node) -> Control:
	var ui: CanvasLayer = CanvasLayer.new()
	ui.name = "UI"
	world.add_child(ui)
	var hud: Control = HouseHud.new()
	ui.add_child(hud)
	hud.call("build")
	return hud


func _test_home_asks_the_world_to_leave():
	var failures: Array = []
	var world: FakeWorld = FakeWorld.new()
	var character: FakeCharacter = FakeCharacter.new()
	world.character = character
	world.add_child(character)
	var nav: FakeNav = FakeNav.new()
	nav.name = "NavigationController"
	world.add_child(nav)
	var hud: Control = _mounted_hud(world)
	var requested: Array = [0]
	hud.connect("home_requested", func() -> void: requested[0] += 1)

	if hud.call("get_world") != world:
		failures.append("interaction_ux: the HUD did not find its world through the UI layer")
	(hud.call("get_home_button") as Button).pressed.emit()
	if not bool(hud.call("is_pause_menu_open")):
		failures.append("interaction_ux: pressing Home did not open the pause card")
	var menu: Control = hud.call("get_pause_menu")
	var buttons: Dictionary = menu.call("get_buttons")
	(buttons["home"] as Button).pressed.emit()
	if world.left != 1:
		failures.append("interaction_ux: Home on the card called leave_to_home() %d times" % world.left)
	if requested[0] != 1:
		failures.append("interaction_ux: home_requested fired %d times" % requested[0])
	if bool(hud.call("is_pause_menu_open")):
		failures.append("interaction_ux: the card stayed open after leaving")
	world.free()
	return failures


func _test_home_without_a_hook_is_not_a_dead_end():
	var failures: Array = []
	var world: FakeWorldWithoutHook = FakeWorldWithoutHook.new()
	var character: FakeCharacter = FakeCharacter.new()
	world.character = character
	world.add_child(character)
	var hud: Control = _mounted_hud(world)
	hud.call("open_pause_menu")
	hud.call("request_home")
	if bool(hud.call("is_pause_menu_open")):
		failures.append("interaction_ux: with no leave_to_home() the card stayed open -- a dead end")
	if character.disabled:
		failures.append("interaction_ux: with no leave_to_home() the character was left disabled")
	world.free()
	return failures


func _test_pause_holds_the_world_and_gives_it_back():
	var failures: Array = []
	var world: FakeWorld = FakeWorld.new()
	var character: FakeCharacter = FakeCharacter.new()
	world.character = character
	world.add_child(character)
	var nav: FakeNav = FakeNav.new()
	nav.name = "NavigationController"
	world.add_child(nav)
	var hud: Control = _mounted_hud(world)
	var layer: Control = hud.call("get_affordance_layer")
	if layer == null:
		return ["interaction_ux: the HUD has no affordance layer"]

	hud.call("open_pause_menu")
	if nav.taps_enabled:
		failures.append("interaction_ux: taps stay enabled behind the pause card")
	if not character.disabled:
		failures.append("interaction_ux: the character can still be walked behind the pause card")
	if bool(layer.call("is_enabled")):
		failures.append("interaction_ux: affordances stay live behind the pause card")
	var menu: Control = hud.call("get_pause_menu")
	((menu.call("get_buttons") as Dictionary)["continue"] as Button).pressed.emit()
	if not nav.taps_enabled or character.disabled:
		failures.append("interaction_ux: Continue did not give the world back")
	if not bool(layer.call("is_enabled")):
		failures.append("interaction_ux: Continue did not re-enable affordances")

	# A character somebody ELSE disabled (the summary) stays disabled after Continue.
	character.disabled = true
	hud.call("open_pause_menu")
	hud.call("close_pause_menu")
	if not character.disabled:
		failures.append("interaction_ux: Continue re-enabled a character the pause card had not disabled")
	character.disabled = false

	# Home is not offered while the chrome is off (the summary owns the screen).
	hud.call("set_play_chrome_visible", false)
	hud.call("open_pause_menu")
	if bool(hud.call("is_pause_menu_open")):
		failures.append("interaction_ux: the pause card opened over the summary")
	hud.call("set_play_chrome_visible", true)

	# Grown-ups: the existing gate, as an overlay, with the world still held.
	hud.call("open_pause_menu")
	hud.call("open_grown_ups")
	if not bool(hud.call("is_grown_ups_open")):
		failures.append("interaction_ux: Grown-ups did not open the parent settings overlay")
	if bool(hud.call("is_pause_menu_open")):
		failures.append("interaction_ux: the pause card stayed up under the grown-ups gate")
	if nav.taps_enabled or not character.disabled:
		failures.append("interaction_ux: the world came back while the grown-ups gate was up")
	world.free()
	return failures


# ---------------------------------------------------------------------------
# The tap indicator and the icons
# ---------------------------------------------------------------------------

func _test_gesture_hint_is_an_arrow_in_the_palette():
	var failures: Array = []
	var hint: Control = GestureHint.new()
	hint.call("build")
	hint.call("show_tap", Vector2(300.0, 300.0))
	if String(hint.call("get_mode")) != "tap" or not hint.visible:
		failures.append("interaction_ux: show_tap() no longer shows the tap hint")
	hint.call("show_ring", Vector2(300.0, 300.0))
	if String(hint.call("get_mode")) != "ring":
		failures.append("interaction_ux: show_ring() no longer works")
	hint.call("hide_hint")
	if hint.visible:
		failures.append("interaction_ux: hide_hint() left the hint visible")
	# Coloured, not a white blob: the marker's own colours are locked tokens,
	# and none of them is red, black or grey.
	for color: Color in [GestureHint.PEACH, GestureHint.MINT, GestureHint.GOLD, GestureHint.TOKEN_COLOR]:
		if Palette.is_red(color) or Palette.is_black(color) or Palette.is_grey(color):
			failures.append("interaction_ux: the tap hint uses %s" % color)
	if GestureHint.PEACH != Palette.PEACH or GestureHint.MINT != Palette.MINT:
		failures.append("interaction_ux: the tap hint's colours drifted from the palette")
	# Narrower than the smallest prop it points at, so it never covers it.
	var width: float = GestureHint.ARROW_HEAD_HALF * 2.0 + GestureHint.OUTLINE_PX * 2.0
	if width > 120.0 or width < 60.0:
		failures.append("interaction_ux: the arrow is %.0f px wide; it must be legible yet not hide the target" % width)
	if hint.has_method("_draw_hand"):
		failures.append("interaction_ux: the cream hand is still drawn")
	hint.free()
	return failures


func _test_icon_backing_is_opt_in():
	var failures: Array = []
	var glyph: TextureRect = IconGlyph.new()
	if glyph.get("backing_color") == null:
		failures.append("interaction_ux: IconGlyph has no backing_color")
	elif (glyph.get("backing_color") as Color).a > 0.001:
		failures.append("interaction_ux: IconGlyph's backing is on by default; existing scenes would change")
	glyph.set("backing_color", Palette.MINT)
	if (glyph.get("backing_color") as Color) != Palette.MINT:
		failures.append("interaction_ux: backing_color did not take")
	glyph.free()
	return failures
