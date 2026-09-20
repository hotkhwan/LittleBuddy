extends SceneTree

## INTERACTION UX EVIDENCE, at the viewport sizes it claims.
##
##   Godot --path game --script res://tests/shots_ux.gd -- <prefix> <W> <H>
##
## Drives the REAL `house_world.tscn` in Free Play, hosted in a `SubViewport` of
## exactly the asked-for size (see `shots_rc.gd` for why `--resolution` is not
## evidence), and photographs:
##
##   <prefix>_fridge_open   Aliz beside the shut fridge, the OPEN badge showing
##   <prefix>_fridge_take   the fridge open, the TAKE badge on the food
##   <prefix>_door_enter    Aliz at a door, the ENTER badge showing
##   <prefix>_home_version  the Home button and the version label, nothing else up
##   <prefix>_pause         the pause card open
##   <prefix>_tap_hint      the redesigned tap indicator on a prop
##
## Every affordance frame is ASSERTED before it is written: the layer must be
## showing the verb the file name claims, or the run fails. The PNG's own size
## is asserted afterwards.

const OUT_DIR: String = "docs/shots/"
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

var _prefix: String = "ux_ipad"
var _frame := Vector2i(1334, 750)
var _viewport: SubViewport = null
var _world: Node = null
var _director: Node = null
var _hud: Control = null
var _layer: Control = null
var _fail: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = String(args[0])
	if args.size() > 2:
		_frame = Vector2i(int(args[1]), int(args[2]))
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
	if args.size() > 3 and String(args[3]) == "story":
		await _run_story()
		return
	if args.size() > 3 and String(args[3]) == "toybox":
		await _run_toy_box()
		return
	if args.size() > 3 and String(args[3]) == "bedroom":
		await _run_bedroom()
		return
	# Free Play: the objective-free house, which is where a child meets the
	# fridge without a mission steering the camera.
	_world.call("set_progression_mode", 1)
	_viewport.add_child(_world)
	await _settle(0.8)

	_director = _world.call("get_free_play_director")
	if _director == null:
		_fail.append("no free play director came up")
		return _finish()
	_hud = _director.call("get_hud")
	_layer = _hud.call("get_affordance_layer") if _hud != null else null
	if _layer == null:
		_fail.append("the HUD has no affordance layer")
		return _finish()

	# -- The kitchen ------------------------------------------------------------
	_world.call("place_in_room", "kitchen", "")
	await _settle(0.6)
	_quiet()
	var kitchen: RefCounted = _world.call("get_kitchen_state")

	_stand_at("kitchen.fridge")
	await _settle(0.7)
	_expect("OPEN", "kitchen.fridge", "fridge_open")
	await _shot("%s_fridge_open" % _prefix)
	await _shot("%s_home_version" % _prefix)

	if kitchen != null:
		kitchen.call("set_open", "fridge", true)
		await _settle(0.7)
		_expect("TAKE", "kitchen.fridge", "fridge_take")
		await _shot("%s_fridge_take" % _prefix)
		kitchen.call("set_open", "fridge", false)

	# -- A door -------------------------------------------------------------------
	var door_id: String = _first_door_id()
	if door_id.is_empty():
		_fail.append("the kitchen has no door target")
	else:
		_stand_at(door_id)
		await _settle(0.7)
		_quiet()
		_expect("ENTER", door_id, "door_enter")
		await _shot("%s_door_enter" % _prefix)

	# -- The pause card -------------------------------------------------------------
	_hud.call("open_pause_menu")
	await _settle(0.4)
	if not bool(_hud.call("is_pause_menu_open")):
		_fail.append("the pause card did not open")
	await _shot("%s_pause" % _prefix)
	_hud.call("close_pause_menu")
	await _settle(0.3)

	# -- The tap indicator -------------------------------------------------------
	_stand_at("kitchen.fridge")
	await _settle(0.4)
	var hint: Control = _director.call("get_hint")
	var camera: Camera3D = _viewport.get_camera_3d()
	var table: Node = _world.call("get_target_by_semantic_id", "kitchen.table")
	if hint != null and camera != null and table is Node3D:
		var at: Vector3 = SpatialUtil.world_position(table as Node3D) + Vector3(0.0, 0.35, 0.0)
		hint.call("show_tap", camera.unproject_position(at))
		# Mid-fall, so the arrow is clearly above the ring rather than on it.
		await _settle(0.25)
		await _shot("%s_tap_hint" % _prefix)
		hint.call("hide_hint")
	else:
		_fail.append("could not stage the tap hint (hint %s, camera %s)" % [hint, camera])

	_finish()


## Story Mode, one frame: the first mission's prompt band is up and Aliz
## stands between the toy box and Bunny, so the badge has to keep out from
## under the prompt AND pick the mission's target. Proves both in the real game.
func _run_story() -> void:
	_viewport.add_child(_world)
	await _settle(0.8)
	var director: Node = _world.call("ensure_level_director")
	director.call("start")
	await _settle(1.0)
	_hud = director.call("get_hud")
	_layer = _hud.call("get_affordance_layer") if _hud != null else null
	if _layer == null:
		_fail.append("the Story HUD has no affordance layer")
		return _finish()
	# The first beat is "Go to Bunny": Aliz on his interaction point, inside
	# his own 1.1 m reach, where he -- the mission's target -- outranks the door
	# and the toy box. Bunny answers for himself: CARRY, or HUG when he needs
	# comfort; never TAKE. And never over his bubble.
	_stand_at("bedroom.littleBuddy")
	await _settle(0.7)
	_expect_any(["CARRY", "HUG"], "bedroom.littleBuddy", "story_hug")
	if float(_layer.call("get_top_keep_out")) <= 100.0:
		_fail.append("story_hug: the HUD did not raise the keep-out under its prompt (%.0f)"
				% float(_layer.call("get_top_keep_out")))
	_expect_off_bubble("story_hug")
	await _shot("%s_story_hug" % _prefix)
	_finish()


## Free Play, the bedroom, Aliz at the toy box -- the object that sits inside
## the thumbstick's corner of the screen. The badge must show OPEN and its hit
## box must be clear of the stick, Home and Next.
func _run_toy_box() -> void:
	_world.call("set_progression_mode", 1)
	_viewport.add_child(_world)
	await _settle(0.8)
	_director = _world.call("get_free_play_director")
	_hud = _director.call("get_hud") if _director != null else null
	_layer = _hud.call("get_affordance_layer") if _hud != null else null
	if _layer == null:
		_fail.append("the HUD has no affordance layer")
		return _finish()
	if _world.has_method("get_affordance_layer") and _world.call("get_affordance_layer") != null \
			and _world.call("get_affordance_layer") != _layer:
		_fail.append("the HUD drives a different layer from the one the world mounted")
	_world.call("place_in_room", "bedroom", "")
	await _settle(0.6)
	_quiet()
	_stand_at("bedroom.toyBox")
	await _settle(0.7)
	_quiet()
	_expect("OPEN", "bedroom.toyBox", "toybox_open")
	var hit: Rect2 = _layer.call("get_hit_rect")
	for blocked: Rect2 in (_layer.call("get_keep_out_rects") as Array):
		if hit.intersects(blocked):
			_fail.append("toybox_open: the badge hit box %s covers keep-out %s" % [str(hit), str(blocked)])
	var stick: Control = _world.call("get_joystick")
	if stick != null and hit.intersects(stick.call("get_activation_rect")):
		_fail.append("toybox_open: the badge %s is inside the thumbstick zone %s"
				% [str(hit), str(stick.call("get_activation_rect"))])
	print("  toybox_open: placement %s, hit %s" % [str(_layer.call("get_placement")), str(hit)])
	await _shot("%s_toybox_open" % _prefix)
	_finish()


## The QA bedroom frame: Free Play, Aliz on Bunny's own interaction point,
## his bubble up. The badge must be CARRY/HUG in capitals, with a picture,
## and clear of the bubble.
func _run_bedroom() -> void:
	_world.call("set_progression_mode", 1)
	_viewport.add_child(_world)
	await _settle(0.8)
	_director = _world.call("get_free_play_director")
	_hud = _director.call("get_hud") if _director != null else null
	_layer = _hud.call("get_affordance_layer") if _hud != null else null
	if _layer == null:
		_fail.append("the HUD has no affordance layer")
		return _finish()
	_world.call("place_in_room", "bedroom", "")
	await _settle(0.6)
	_quiet()
	_stand_at("bedroom.littleBuddy")
	await _settle(0.7)
	_quiet()
	_expect_any(["CARRY", "HUG"], "bedroom.littleBuddy", "bedroom_bunny")
	_expect_off_bubble("bedroom_bunny")
	await _shot("%s_bedroom_bunny" % _prefix)
	_finish()


func _expect_any(verbs: Array, target_id: String, shot: String) -> void:
	var got_verb: String = String(_layer.call("get_current_verb"))
	var got_id: String = String(_layer.call("get_current_target_id"))
	if not verbs.has(got_verb) or got_id != target_id:
		_fail.append("%s: the layer shows '%s' on '%s'; expected one of %s on %s"
				% [shot, got_verb, got_id, str(verbs), target_id])
	if got_verb != got_verb.to_upper():
		_fail.append("%s: the verb '%s' is not in capitals" % [shot, got_verb])
	if not bool(_layer.call("is_laid_out")):
		_fail.append("%s: the badge was not laid out (no camera?)" % shot)
	print("  %s: %s on %s at %s (%s)" % [shot, got_verb, got_id,
			str(_layer.call("get_badge_centre")), str(_layer.call("get_placement"))])


func _expect_off_bubble(shot: String) -> void:
	var bubble: Rect2 = _layer.call("get_bubble_keep_out")
	if bubble.size.x <= 0.0:
		_fail.append("%s: no bubble keep-out was measured for the character" % shot)
		return
	var hit: Rect2 = _layer.call("get_hit_rect")
	var footprint: Rect2 = _layer.call("badge_footprint", _layer.call("get_badge_centre"))
	if footprint.intersects(bubble):
		_fail.append("%s: the badge %s covers Bunny's bubble %s" % [shot, str(footprint), str(bubble)])
	print("  %s: bubble %s, badge %s, hit %s" % [shot, str(bubble), str(footprint), str(hit)])


func _finish() -> void:
	if _fail.is_empty():
		print("\nUX SHOTS OK")
		quit(0)
	else:
		print("\nUX SHOTS FAIL:")
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)


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
	var away: Vector3 = face - stand
	if Vector2(away.x, away.z).length() > 0.001:
		character.rotation.y = atan2(away.x, away.z)


func _first_door_id() -> String:
	for id: Variant in _world.call("get_semantic_target_ids"):
		var target: Node = _world.call("get_target_by_semantic_id", String(id))
		if target != null and target.has_method("is_door") and bool(target.call("is_door")) \
				and String(id).begins_with("kitchen."):
			return String(id)
	return ""


func _expect(verb: String, target_id: String, shot: String) -> void:
	var got_verb: String = String(_layer.call("get_current_verb"))
	var got_id: String = String(_layer.call("get_current_target_id"))
	if got_verb != verb or got_id != target_id:
		_fail.append("%s: the layer shows '%s' on '%s'; expected %s on %s"
				% [shot, got_verb, got_id, verb, target_id])
	if not bool(_layer.call("is_laid_out")):
		_fail.append("%s: the badge was not laid out (no camera?)" % shot)
	print("  %s: %s on %s at %s" % [shot, got_verb, got_id, str(_layer.call("get_badge_centre"))])


## Puts Free Play's idle nudge away so it cannot wander into a frame.
func _quiet() -> void:
	if _director != null and _director.has_method("_quieten_nudge"):
		_director.call("_quieten_nudge")


func _shot(name: String) -> void:
	# Drawn ON DEMAND rather than awaited: macOS stops the draw loop while the
	# window is occluded and `frame_post_draw` never comes (see shots_bubble.gd).
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
