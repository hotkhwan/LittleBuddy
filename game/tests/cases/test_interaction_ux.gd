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
const AffordanceLayer := preload("res://scripts/interaction/affordance_layer.gd")
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
	failures.append_array(_test_version_label_is_not_in_the_room())
	failures.append_array(_test_home_button_is_there_and_clear_of_the_caption())
	failures.append_array(_test_pause_menu_buttons_are_wired())
	failures.append_array(_test_home_asks_the_world_to_leave())
	failures.append_array(_test_home_without_a_hook_is_not_a_dead_end())
	failures.append_array(_test_pause_holds_the_world_and_gives_it_back())
	failures.append_array(_test_hud_adopts_the_world_layer_and_forwards_its_rules())
	failures.append_array(_test_gesture_hint_is_an_arrow_in_the_palette())
	failures.append_array(_test_icon_backing_is_opt_in())
	return failures


# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------

## Changed deliberately 2026-09-20: the build number moved to the title screen
## (Agent B). The room shows no version label at all, and nothing reserves a
## keep-out for one.
func _test_version_label_is_not_in_the_room():
	var failures: Array = []
	var hud: Control = HouseHud.new()
	hud.call("build")
	if bool(hud.call("has_version_label")):
		failures.append("interaction_ux: the room HUD still carries a version label; it belongs on the title screen only")
	hud.free()
	return failures


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


## The world mounts "AffordanceLayer" itself (house_world.gd). The HUD must
## then drive THAT layer -- chrome, narration cover, pause, keep-outs -- and
## not a private copy nobody can see.
func _test_hud_adopts_the_world_layer_and_forwards_its_rules():
	var failures: Array = []
	var world: FakeWorld = FakeWorld.new()
	var character: FakeCharacter = FakeCharacter.new()
	world.character = character
	world.add_child(character)
	var ui: CanvasLayer = CanvasLayer.new()
	ui.name = "UI"
	world.add_child(ui)
	var world_layer: Control = AffordanceLayer.new()
	ui.add_child(world_layer)
	world_layer.call("build")
	world_layer.call("bind", world)
	var hud: Control = HouseHud.new()
	ui.add_child(hud)
	hud.call("build")
	hud.call("refresh_presentation")

	if hud.call("get_affordance_layer") != world_layer:
		failures.append("interaction_ux: the HUD did not adopt the world's AffordanceLayer")
	var own: int = 0
	for child: Node in hud.get_children():
		if child.name == "AffordanceLayer" or child is AffordanceLayer:
			own += 1
	if own != 0:
		failures.append("interaction_ux: the HUD kept %d private affordance layer(s) beside the world's" % own)

	if not bool(world_layer.call("is_enabled")):
		failures.append("interaction_ux: precondition -- the world layer should start enabled")
	hud.call("set_narration_covered", true)
	if bool(world_layer.call("is_enabled")):
		failures.append("interaction_ux: narration cover did not reach the world's layer")
	hud.call("set_narration_covered", false)
	if not bool(world_layer.call("is_enabled")):
		failures.append("interaction_ux: the world's layer did not come back after the close-up")
	hud.call("set_play_chrome_visible", false)
	if bool(world_layer.call("is_enabled")):
		failures.append("interaction_ux: chrome-off did not reach the world's layer")
	hud.call("set_play_chrome_visible", true)
	hud.call("open_pause_menu")
	if bool(world_layer.call("is_enabled")):
		failures.append("interaction_ux: the pause card did not reach the world's layer")
	hud.call("close_pause_menu")
	if not bool(world_layer.call("is_enabled")):
		failures.append("interaction_ux: Continue did not re-enable the world's layer")

	# Keep-outs: Home and the stars always; Next only while it is up.
	var rects: Array = world_layer.call("get_keep_out_rects")
	# Home and the stars (the version keep-out went with the version label, 2026-09-20).
	if rects.size() < 2:
		failures.append("interaction_ux: the HUD pushed only %d keep-out rect(s); expected Home and stars at least" % rects.size())
	var before: int = rects.size()
	hud.call("set_skip_visible", true)
	if (world_layer.call("get_keep_out_rects") as Array).size() != before + 1:
		failures.append("interaction_ux: showing Next did not add its keep-out")
	hud.call("set_skip_visible", false)
	if (world_layer.call("get_keep_out_rects") as Array).size() != before:
		failures.append("interaction_ux: hiding Next did not remove its keep-out")
	world.free()
	return failures
