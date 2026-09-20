extends SceneTree

## LEARN WITH ALIZ (parent controls) EVIDENCE, at the pixel size it claims.
## Dev-only.
##
##   Godot --path game --script res://tests/shots_tutor_settings.gd -- ipad 1334x750
##   Godot --path game --script res://tests/shots_tutor_settings.gd -- iphone 2340x1080
##
## Writes, into docs/shots/:
##   settings_aliz_<prefix>          Parent Corner scrolled to "Learn with Aliz":
##                                   AI Tutor On/Off, daily allowance, microphone,
##                                   language, privacy, delete history, subscription
##   settings_aliz_privacy_<prefix>  the same section with the privacy text open
##
## Same SubViewport / `size_2d_override` discipline as shots_settings.gd. Every
## PNG's size is asserted, and the section's rows are asserted to be inside the
## frame after the scroll. The real SaveService is left alone: the panel is
## given a throwaway settings source so nothing a child owns is touched.

const OUT_DIR: String = "docs/shots/"
const DESIGN_HEIGHT: int = 1024
const PARENT_SCENE: String = "res://scenes/parent/parent_settings.tscn"

var _prefix: String = "ipad"
var _frame: Vector2i = Vector2i(1334, 750)
var _viewport: SubViewport = null
var _fail: Array = []


## A settings source with a little tutor history, so the allowance row shows a
## real number rather than 0:00.
class ShotSaveService:
	extends RefCounted
	var settings: Dictionary = {}

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value

	func get_stars() -> int:
		return 9


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
	print("=== Learn with Aliz settings evidence, %dx%d -> %ssettings_aliz_*_%s.png ===" % [_frame.x, _frame.y, OUT_DIR, _prefix])
	await process_frame

	_viewport = SubViewport.new()
	_viewport.size = _frame
	var design_width: int = int(round(float(_frame.x) * float(DESIGN_HEIGHT) / float(_frame.y)))
	_viewport.size_2d_override = Vector2i(design_width, DESIGN_HEIGHT)
	_viewport.size_2d_override_stretch = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	await _aliz_frames()

	if _fail.is_empty():
		print("\nTUTOR SETTINGS SHOTS OK")
		quit(0)
	else:
		print("\nTUTOR SETTINGS SHOTS FAIL:")
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)


func _aliz_frames() -> void:
	var panel: Control = (load(PARENT_SCENE) as PackedScene).instantiate()
	_viewport.add_child(panel)
	await _settle(0.3)

	# A throwaway profile with 1:30 of lesson time used today.
	var save := ShotSaveService.new()
	var today: String = Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()))
	save.settings["tutorQuota"] = {"dayUtc": today, "usedSeconds": 90.0, "entitlement": "free",
			"lastSeenUnix": int(Time.get_unix_time_from_system())}
	var model: RefCounted = panel.call("model")
	model.call("set_service", save)
	var quota: RefCounted = panel.call("tutor_quota")
	if quota != null:
		quota.call("ledger").call("from_dict", save.settings["tutorQuota"])

	panel.call("open_settings")
	await _settle(0.4)
	if not bool(panel.call("is_learn_with_aliz_visible")):
		_fail.append("settings_aliz: the section is not visible after opening")
	print("  allowance: '%s'" % String(panel.call("aliz_allowance_text")).replace("\n", " / "))
	print("  subscription: '%s' -- %s" % [String(panel.call("aliz_subscription_text")), String(panel.call("aliz_pricing_text"))])
	print("  cloud: '%s'" % String(panel.call("aliz_cloud_text")))
	print("  microphone: '%s'" % String(panel.call("aliz_microphone_text")))

	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	var box: Control = panel.find_child("LearnWithAlizBox", true, false) as Control
	if scroll == null or box == null:
		_fail.append("settings_aliz: no ScrollContainer or section box")
		_viewport.remove_child(panel)
		panel.free()
		return
	_scroll_to(scroll, box)
	await _settle(0.4)
	var visible_h: float = float(_viewport.size_2d_override.y)
	for node_name: String in ["LearnWithAlizTitle", "AiTutorOnButton", "AiTutorOffButton", "AlizAllowanceValue",
			"AlizMicrophoneValue", "AlizLanguageEnButton"]:
		var node: Control = panel.find_child(node_name, true, false) as Control
		if node == null or not node.is_visible_in_tree():
			_fail.append("settings_aliz: %s is not visible" % node_name)
			continue
		var rect: Rect2 = node.get_global_rect()
		if rect.position.y < 0.0 or rect.end.y > visible_h:
			_fail.append("settings_aliz: %s is at %s, outside the %d-tall frame" % [node_name, str(rect), int(visible_h)])
	await _shot("settings_aliz_%s" % _prefix)

	# The privacy text open, scrolled so it and the rows below are in frame.
	var privacy_button: Button = panel.find_child("AlizPrivacyButton", true, false) as Button
	privacy_button.pressed.emit()
	await _settle(0.3)
	var privacy_box: Control = panel.find_child("AlizPrivacyBox", true, false) as Control
	_scroll_to(scroll, privacy_box, 140.0)
	await _settle(0.4)
	if not bool(panel.call("is_aliz_privacy_visible")):
		_fail.append("settings_aliz_privacy: the privacy text did not open")
	for node_name: String in ["AlizPrivacyLine0", "AlizDeleteHistoryButton", "AlizSubscriptionValue", "AlizPricingLabel"]:
		var node: Control = panel.find_child(node_name, true, false) as Control
		if node == null or not node.is_visible_in_tree():
			_fail.append("settings_aliz_privacy: %s is not visible" % node_name)
			continue
		var rect: Rect2 = node.get_global_rect()
		if rect.position.y < 0.0 or rect.end.y > visible_h:
			_fail.append("settings_aliz_privacy: %s is at %s, outside the %d-tall frame" % [node_name, str(rect), int(visible_h)])
	await _shot("settings_aliz_privacy_%s" % _prefix)

	_viewport.remove_child(panel)
	panel.free()


## Scrolls so `target` sits `margin` px under the top of the scroll viewport.
func _scroll_to(scroll: ScrollContainer, target: Control, margin: float = 24.0) -> void:
	var offset: float = target.get_global_rect().position.y - scroll.get_global_rect().position.y
	scroll.scroll_vertical = maxi(0, scroll.scroll_vertical + int(offset - margin))


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
