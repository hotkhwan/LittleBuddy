extends SceneTree

## FREE-SESSION EVIDENCE, at the pixel size it claims. Dev-only.
##
##   Godot --path game --script res://tests/shots_session.gd -- ipad 1334x750
##   Godot --path game --script res://tests/shots_session.gd -- iphone 2340x1080
##
## Writes, into docs/shots/:
##   door_enter_bathroom_<prefix>  Free Play, Aliz at the bathroom door: ENTER, not SOON
##   break_card_<prefix>           the break card over the running house, room held
##   settings_session_<prefix>     the Grown-ups panel scrolled to "Play Session Reminder"
##
## The house is the REAL `house_world.tscn` in Free Play, hosted in a SubViewport
## of exactly the asked-for size (see `shots_rc.gd`). Every frame is asserted
## before it is written -- the door must show ENTER, the card must be open with
## taps off, the row must be inside the frame -- and every PNG's size is
## asserted afterwards. The profile is touched only to mark first run as seen,
## and that is put back.

const OUT_DIR: String = "docs/shots/"
const DESIGN_HEIGHT: int = 1024
const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"
const PARENT_SCENE: String = "res://scenes/parent/parent_settings.tscn"
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const OnboardingPlan := preload("res://scripts/onboarding/onboarding_plan.gd")


class FakeSettings extends RefCounted:
	var values: Dictionary = {"sessionReminderMinutes": 5}
	func get_setting(key: String, fallback: Variant = null) -> Variant:
		return values.get(key, fallback)


var _prefix: String = "ipad"
var _frame: Vector2i = Vector2i(1334, 750)
var _viewport: SubViewport = null
var _world: Node = null
var _director: Node = null
var _layer: Control = null
var _fail: Array = []
var _saved_onboarding: Variant = null


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = String(args[0]).strip_edges()
	if args.size() > 1:
		var wide: PackedStringArray = String(args[1]).split("x")
		if wide.size() == 2:
			_frame = Vector2i(int(wide[0]), int(wide[1]))
	print("=== free session evidence, %dx%d -> %s*_%s.png ===" % [_frame.x, _frame.y, OUT_DIR, _prefix])
	await process_frame

	var save: Node = root.get_node_or_null("SaveService")
	if save != null and save.has_method("get_setting"):
		_saved_onboarding = save.call("get_setting", OnboardingPlan.SETTING_KEY, null)
		save.call("set_setting", OnboardingPlan.SETTING_KEY, true)

	_viewport = SubViewport.new()
	_viewport.size = _frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	await _house_frames()
	await _settings_frame()

	if save != null and save.has_method("set_setting"):
		if _saved_onboarding == null:
			save.call("set_setting", OnboardingPlan.SETTING_KEY, false)
		else:
			save.call("set_setting", OnboardingPlan.SETTING_KEY, _saved_onboarding)

	if _fail.is_empty():
		print("\nSESSION SHOTS OK")
		quit(0)
	else:
		print("\nSESSION SHOTS FAIL:")
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)


func _house_frames() -> void:
	_world = (load(HOUSE_SCENE) as PackedScene).instantiate()
	_world.call("set_progression_mode", 1)
	_viewport.add_child(_world)
	await _settle(0.8)
	_director = _world.call("get_free_play_director")
	if _director == null:
		_fail.append("house: no free play director came up")
		return
	var hud: Control = _director.call("get_hud")
	_layer = hud.call("get_affordance_layer") if hud != null else null
	if _layer == null:
		_fail.append("house: the HUD has no affordance layer")
		return

	# -- The bathroom door says ENTER on a free-starter profile ------------------
	_world.call("place_in_room", "bedroom", "")
	await _settle(0.5)
	_quiet()
	_stand_at("bedroom.doorToBathroom")
	await _settle(0.7)
	_quiet()
	var verb: String = String(_layer.call("get_current_verb"))
	var on_id: String = String(_layer.call("get_current_target_id"))
	if verb != "ENTER" or on_id != "bedroom.doorToBathroom":
		_fail.append("door_enter_bathroom: the layer shows '%s' on '%s'; expected ENTER on the bathroom door" % [verb, on_id])
	if not bool(_director.call("is_room_open", "bathroom")):
		_fail.append("door_enter_bathroom: the bathroom is not open in Free Play")
	print("  bathroom door: %s on %s" % [verb, on_id])
	await _shot("door_enter_bathroom_%s" % _prefix)

	# -- The break card over the house -------------------------------------------
	var host: Node = _director.call("get_break_host")
	var session: Node = host.call("get_session") if host != null else null
	if host == null or session == null:
		_fail.append("break_card: no break host / session")
		return
	session.call("set_settings_source", FakeSettings.new())
	session.call("reset")
	# Stand her somewhere plain, then let the clock pass the threshold; the
	# director shows the card once she has been calm for two seconds.
	_world.call("place_in_room", "bedroom", "")
	await _settle(0.4)
	_quiet()
	session.call("tick", 301.0)
	var waited: float = 0.0
	while not bool(host.call("is_open")) and waited < 6.0:
		await _settle(0.2)
		waited += 0.2
	if not bool(host.call("is_open")):
		_fail.append("break_card: the card did not come up (calm %.1f s, due %s)"
				% [float(_director.call("get_calm_seconds")), str(session.call("is_due"))])
		return
	var nav: Node = _world.get_node_or_null("NavigationController")
	if nav != null and bool(nav.get("taps_enabled")):
		_fail.append("break_card: taps are still on under the card")
	var card: Control = host.call("get_card")
	var buttons: Dictionary = card.call("get_buttons")
	for key: String in ["keep", "home"]:
		var button: Control = buttons.get(key)
		if button == null or not button.is_visible_in_tree():
			_fail.append("break_card: the %s button is not visible" % key)
	print("  break card: '%s' / %s" % [card.call("get_title_text"), str(card.call("get_body_lines"))])
	await _settle(0.4)
	await _shot("break_card_%s" % _prefix)
	host.call("keep_playing")
	if nav != null and not bool(nav.get("taps_enabled")):
		_fail.append("break_card: taps did not come back after Keep Playing")

	_viewport.remove_child(_world)
	_world.free()
	_world = null


func _settings_frame() -> void:
	# The panel lays out in the 1024-tall design space (see shots_settings.gd).
	var design_width: int = int(round(float(_frame.x) * float(DESIGN_HEIGHT) / float(_frame.y)))
	_viewport.size_2d_override = Vector2i(design_width, DESIGN_HEIGHT)
	_viewport.size_2d_override_stretch = true
	var panel: Control = (load(PARENT_SCENE) as PackedScene).instantiate()
	_viewport.add_child(panel)
	await _settle(0.3)
	panel.call("open_settings")
	await _settle(0.4)
	var row: Control = panel.find_child("SessionRow", true, false) as Control
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	if row == null or scroll == null:
		_fail.append("settings_session: the reminder row or the scroll container is missing")
	else:
		scroll.ensure_control_visible(row)
		await _settle(0.4)
		var rect: Rect2 = row.get_global_rect()
		var visible_h: float = float(_viewport.size_2d_override.y)
		if rect.position.y < 0.0 or rect.end.y > visible_h:
			_fail.append("settings_session: the reminder row is at %s, outside the %d-tall frame" % [str(rect), int(visible_h)])
		for node_name: String in ["SessionOffButton", "Session5Button", "Session10Button", "Session15Button",
				"AlizVoiceSlider", "BunnyVoiceSlider"]:
			var node: Control = panel.find_child(node_name, true, false) as Control
			if node == null:
				_fail.append("settings_session: %s is missing" % node_name)
		var five: Button = panel.find_child("Session5Button", true, false) as Button
		print("  reminder row at %s, 5 min selected: %s" % [str(rect), str(five != null and five.button_pressed)])
	await _shot("settings_session_%s" % _prefix)
	_viewport.remove_child(panel)
	panel.free()


## Teleports Aliz to the authored stand position of `semantic_id`, facing it.
func _stand_at(semantic_id: String) -> void:
	var target: Node = _world.call("get_target_by_semantic_id", semantic_id)
	var character: Node3D = _world.call("get_character")
	if target == null or character == null:
		_fail.append("cannot stand at unknown target '%s'" % semantic_id)
		return
	var here: Vector3 = SpatialUtil.world_position(character)
	var stand: Vector3 = target.call("get_stand_position", here)
	SpatialUtil.set_world_position(character, stand)
	var face: Vector3 = target.call("get_facing_position", stand)
	character.rotation.y = NavMath.yaw_towards(stand, face, character.rotation.y)


func _quiet() -> void:
	if _director != null and _director.has_method("_quieten_nudge"):
		_director.call("_quieten_nudge")


func _shot(name: String) -> void:
	await process_frame
	RenderingServer.force_draw(true, 0.0)
	var image: Image = _viewport.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + name + ".png")
	if image.save_png(path) != OK:
		_fail.append("could not write %s.png" % name)
		return
	if image.get_width() != _frame.x or image.get_height() != _frame.y:
		_fail.append("%s.png is %dx%d but %dx%d was asked for"
				% [name, image.get_width(), image.get_height(), _frame.x, _frame.y])
		return
	print("  shot %s.png  %dx%d" % [name, image.get_width(), image.get_height()])


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
