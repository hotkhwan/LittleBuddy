extends SceneTree

## FREE PLAY'S ROUTES, PHOTOGRAPHED. Dev-only; nothing in the game references it.
##
##   Godot --path game --script res://tests/shots_freeplay.gd -- ipad 1334x750
##
## The REAL `house_world.tscn` in Free Play, hosted in a SubViewport of exactly
## the asked-for size (see `shots_rc.gd`), driven through the Free Play
## director's own arrival path. Each frame is asserted before it is written:
##
##   freeplay_feed_<s>.png      the giveBottle close-up open from Free Play, on Bunny
##   freeplay_chooser_<s>.png   the fridge's food chooser (>= 2 cards)
##   freeplay_tidy_<s>.png      the bedroom tidy-up: toys scattered, lid open
##   freeplay_bedtime_<s>.png   Bunny asleep, the night glow on

const OUT_DIR: String = "docs/shots/"
const Spatial := preload("res://scripts/navigation/spatial_util.gd")

var _suffix: String = "ipad"
var _frame: Vector2i = Vector2i(1334, 750)
var _viewport: SubViewport = null
var _world: Node = null
var _director: Node = null
var _aliz: Node3D = null
var _bunny: Node3D = null
var _fail: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not String(args[0]).strip_edges().is_empty():
		_suffix = String(args[0]).strip_edges()
	if args.size() > 1:
		var wide: PackedStringArray = String(args[1]).split("x")
		if wide.size() == 2:
			_frame = Vector2i(int(wide[0]), int(wide[1]))
	print("=== free play routes, %s, %dx%d ===" % [_suffix, _frame.x, _frame.y])

	await process_frame
	var save: Node = root.get_node_or_null("SaveService")
	if save != null and save.has_method("reset_profile"):
		save.call("reset_profile")
		var plan: GDScript = load("res://scripts/onboarding/onboarding_plan.gd")
		if plan != null and save.has_method("set_setting"):
			save.call("set_setting", plan.SETTING_KEY, true)

	_viewport = SubViewport.new()
	_viewport.size = _frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_world = load("res://scenes/house/house_world.tscn").instantiate()
	_world.call("set_progression_mode", 1)
	_viewport.add_child(_world)
	await _settle(0.8)

	_director = _world.call("ensure_free_play_director")
	if _director == null:
		return _die("no Free Play director")
	if not bool(_director.call("is_running")):
		_director.call("start")
	var hint: Control = _director.call("get_hint")
	if hint != null:
		hint.visible = false
		_director.connect("hint_shown", func(_id: String) -> void: hint.visible = false)
	_aliz = _world.call("get_character")
	_bunny = _world.get_node_or_null("Rooms/Bedroom/LittleBuddyChild")
	if _aliz == null or _bunny == null:
		return _die("no caregiver or no Bunny")

	# -- Feeding, from Free Play: make the milk in the kitchen, bring it to him.
	_world.call("place_in_room", "kitchen", "default")
	await _settle(0.6)
	var kitchen: RefCounted = _world.call("get_kitchen_state")
	kitchen.call("reset")
	kitchen.call("set_open", "fridge", true)
	kitchen.call("take", "fridge", "bottle")
	kitchen.call("place", "counter")
	kitchen.call("take", "counter", "bowl")
	kitchen.call("place", "counter")
	kitchen.call("take", "counter", "bottleOfMilk")
	_bunny.call("room_changed", _world.call("get_current_room"), _aliz)
	var stats: RefCounted = _bunny.call("get_stats")
	stats.call("adjust", "hunger", 80.0)
	var before: float = float(stats.call("get_stat", "hunger"))
	await _settle(0.3)
	_arrive("kitchen.littleBuddy")
	await _settle(0.9)
	if not bool(_director.call("is_care_open")):
		_fail.append("feeding: the close-up did not open from Free Play")
	else:
		var care: Control = _director.call("get_care_overlay")
		print("  care kind: %s, portrait: %s" % [care.call("get_care_kind"), _director.call("is_portrait_on")])
		if String(care.call("get_care_kind")) != "giveBottle":
			_fail.append("feeding: close-up is %s" % care.call("get_care_kind"))
		# Half-fed, so the ring shows progress on his real mouth.
		var at: Vector2 = care.call("get_mouth_target")
		care.call("_set_dragging", true, at)
		for _i: int in range(60):
			care.call("apply_hold", 1.0 / 60.0, at)
		await _settle(0.2)
		await _shot("freeplay_feed_%s" % _suffix)
		for _i: int in range(200):
			care.call("apply_hold", 1.0 / 60.0, care.call("get_mouth_target"))
			if bool(care.call("is_finished")):
				break
		await _settle(0.3)
		var after: float = float(stats.call("get_stat", "hunger"))
		print("  hunger %.0f -> %.0f" % [before, after])
		if after >= before:
			_fail.append("feeding: hunger did not drop")

	# -- The fridge chooser.
	kitchen.call("reset")
	kitchen.call("set_open", "fridge", true)
	_arrive("kitchen.fridge")
	await _settle(0.5)
	if not bool(_director.call("is_chooser_open")):
		_fail.append("chooser: did not open at the open fridge")
	else:
		print("  chooser cards: %d" % int(_director.call("get_food_chooser").call("get_card_count")))
		await _shot("freeplay_chooser_%s" % _suffix)
		_director.call("get_food_chooser").call("dismiss")

	# -- The tidy-up.
	_bunny.call("room_changed", _world.call("get_room", "bedroom"), _aliz)
	_world.call("place_in_room", "bedroom", "default")
	await _settle(0.6)
	_world.call("get_current_room").call("set_open", "toyBox", false)
	_arrive("bedroom.toyBox")
	await _settle(0.6)
	if not bool(_director.call("is_tidy_active")):
		_fail.append("tidy: no tidy started")
	else:
		print("  tidy toys: %d" % (_director.call("get_tidy_nodes") as Array).size())
		await _shot("freeplay_tidy_%s" % _suffix)

	# -- Bedtime.
	_aliz.global_position = _bunny.global_position + Vector3(0.0, 0.0, 0.62)
	_bunny.call("perform_affordance", _aliz)
	await _settle(0.9)
	_arrive("bedroom.bed")
	await _settle(1.6)
	if not bool(_director.call("is_bedtime_active")):
		_fail.append("bedtime: not active after laying him down")
	else:
		print("  bedtime dim: %.2f" % float(_director.call("get_bedtime_dim")))
		await _shot("freeplay_bedtime_%s" % _suffix)

	if _fail.is_empty():
		print("SHOTS PASS -- free play routes photographed at %dx%d" % [_frame.x, _frame.y])
		quit(0)
	else:
		for line: String in _fail:
			print("FAIL: %s" % line)
		quit(1)


func _arrive(target_id: String) -> void:
	var target: Node = _world.call("get_target_by_semantic_id", target_id)
	if target != null and target.has_method("get_stand_position"):
		var here: Vector3 = Spatial.world_position(_aliz)
		var stand: Vector3 = target.call("get_stand_position", here)
		Spatial.set_world_position(_aliz, stand)
		var face: Vector3 = target.call("get_facing_position", stand)
		var d: Vector3 = face - stand
		if Vector2(d.x, d.z).length() > 0.001:
			_aliz.rotation.y = atan2(-d.x, -d.z)
	_aliz.emit_signal("interaction_ready", target_id)


func _shot(name: String) -> void:
	await _settle(0.3)
	RenderingServer.force_draw(true, 0.0)
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + name + ".png")
	if image.save_png(path) != OK:
		_fail.append("could not write %s" % path)
		return
	if image.get_width() != _frame.x or image.get_height() != _frame.y:
		_fail.append("%s is %dx%d, not %dx%d" % [name, image.get_width(), image.get_height(), _frame.x, _frame.y])
	print("  wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])


func _settle(seconds: float) -> void:
	var frames: int = maxi(1, int(ceil(seconds * 60.0)))
	for _i: int in range(frames):
		await process_frame


func _die(reason: String) -> void:
	print("FAIL: %s" % reason)
	quit(1)
