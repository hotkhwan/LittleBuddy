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
const NavMath := preload("res://scripts/navigation/nav_math.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")

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
	if args.size() > 3 and String(args[3]) == "free":
		await _run_free_play_acts()
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


## FREE PLAY ACTS, photographed (2026-09-20). Every frame is asserted against
## the world's state before it is written:
##
##   <prefix>_badge_bedroom   the 96 px OPEN badge on the toy box
##   <prefix>_wardrobe_open   the wardrobe doors swung open
##   <prefix>_toybox_open     the toy box lid open
##   <prefix>_shelf_teddy     the bedroom's teddy carried to the living room shelf and put in
##   <prefix>_sofa_sit        Aliz seated on the sofa
##   <prefix>_bed_bunny       Bunny laid on the bed (bedtime)
##   <prefix>_table_bunny     Bunny set at his table spot
##   <prefix>_sink_wash       the washFace close-up open from Free Play, Bunny in her arms
##   <prefix>_locked_sign     the SOON sign on the bathroom door
func _run_free_play_acts() -> void:
	_world.call("set_progression_mode", 1)
	_viewport.add_child(_world)
	await _settle(0.8)
	_director = _world.call("get_free_play_director")
	_hud = _director.call("get_hud") if _director != null else null
	_layer = _hud.call("get_affordance_layer") if _hud != null else null
	if _layer == null:
		_fail.append("the HUD has no affordance layer")
		return _finish()
	var aliz: Node3D = _world.call("get_character")
	var bunny: Node = _world.get_node_or_null("Rooms/Bedroom/LittleBuddyChild")

	# -- Bedroom: the badge, the wardrobe, the toy box -----------------------------
	_world.call("place_in_room", "bedroom", "")
	await _settle(0.5)
	_quiet()
	_stand_at("bedroom.toyBox")
	await _settle(0.6)
	_quiet()
	_expect("OPEN", "bedroom.toyBox", "badge_bedroom")
	var disc: float = float(_layer.call("badge_diameter", float(_frame.y)))
	print("  badge_bedroom: disc %.0f px on a %d px tall frame" % [disc, _frame.y])
	if absf(disc - float(_frame.y) * 0.128) > 2.0:
		_fail.append("badge_bedroom: the disc is %.0f px; 12.8%% of %d is %.0f" % [disc, _frame.y, float(_frame.y) * 0.128])
	await _shot("%s_badge_bedroom" % _prefix)

	var bedroom: Node = _world.call("get_current_room")
	_arrive(aliz, "bedroom.wardrobe")
	await _settle(0.6)
	if not bool(bedroom.call("is_open", "wardrobe")):
		_fail.append("wardrobe_open: the wardrobe is not open")
	_stand_at("bedroom.bed")
	_quiet()
	await _settle(0.2)
	await _shot("%s_wardrobe_open" % _prefix)
	_arrive(aliz, "bedroom.wardrobe")
	await _settle(0.5)

	bedroom.call("set_open", "toyBox", false)
	_arrive(aliz, "bedroom.toyBox")
	await _settle(0.6)
	if not bool(bedroom.call("is_storage_open", "toyBox")):
		_fail.append("toybox_open: the lid is not open")
	_quiet()
	await _shot("%s_toybox_open" % _prefix)

	# -- The teddy, carried to the living room shelf --------------------------------
	var teddy: Node = null
	for node: Variant in _director.call("ensure_draggables"):
		if node is Node and String((node as Node).get("object_id")) == "teddy":
			teddy = node
	if teddy == null:
		_fail.append("shelf_teddy: no teddy staged in the bedroom")
	else:
		aliz.call("carry_node", teddy, "itemHoldRight")
		await _settle(0.6)
		_world.call("place_in_room", "livingRoom", "")
		await _settle(0.6)
		if not is_instance_valid(teddy) or aliz.call("get_carried_node") != teddy:
			_fail.append("shelf_teddy: the teddy did not travel to the living room in her hand")
		else:
			var living: Node = _world.call("get_current_room")
			living.call("set_open", "toyShelf", true)
			_arrive(aliz, "livingRoom.toyShelf")
			await _settle(0.8)
			var model: RefCounted = living.call("get_storage", "toyShelf")
			if not bool(model.call("contains", "teddy")):
				_fail.append("shelf_teddy: the shelf's model does not hold the teddy (%s)" % str(model.call("describe")))
			if bool(aliz.call("is_carrying_node")):
				_fail.append("shelf_teddy: the teddy is still in her hand")
			_quiet()
			await _shot("%s_shelf_teddy" % _prefix)

	# -- Aliz sits on the sofa -----------------------------------------------------------
	_arrive(aliz, "livingRoom.sofa")
	await _settle(0.9)
	if not bool(_director.call("is_seated")):
		_fail.append("sofa_sit: Aliz is not seated")
	var pose: Node = _find_named(aliz, "HeldPose")
	if pose == null or String(pose.call("get_pose")) != "sit" or not bool(pose.call("is_posed")):
		_fail.append("sofa_sit: the seated pose is not on her skeleton (%s)" % (pose.call("get_pose") if pose != null else "no modifier"))
	print("  sofa_sit: origin %s, pose %s" % [SpatialUtil.world_position(aliz), pose.call("get_pose") if pose != null else "-"])
	_quiet()
	await _shot("%s_sofa_sit" % _prefix)
	_director.call("_stand_up")

	# -- Bunny on the bed, then at the table --------------------------------------------
	_world.call("place_in_room", "bedroom", "")
	await _settle(0.5)
	if bunny == null:
		_fail.append("bed_bunny: no Bunny")
	else:
		SpatialUtil.set_world_position(aliz, SpatialUtil.world_position(bunny) + Vector3(0.0, 0.0, 0.62))
		bunny.call("perform_affordance", aliz)
		await _settle(0.6)
		_arrive(aliz, "bedroom.bed")
		await _settle(0.9)
		if String(bunny.call("get_activity")) != "bedtime":
			_fail.append("bed_bunny: Bunny's activity is '%s'" % bunny.call("get_activity"))
		if SpatialUtil.world_position(bunny).y < 0.3:
			_fail.append("bed_bunny: Bunny is at y %.2f, not on the mattress" % SpatialUtil.world_position(bunny).y)
		_quiet()
		await _shot("%s_bed_bunny" % _prefix)
		_expect_no_floor_discs("bed_bunny")

		# Pick him up again and carry him to the kitchen table.
		var lie: Vector3 = SpatialUtil.world_position(bunny)
		SpatialUtil.set_world_position(aliz, Vector3(lie.x + 0.62, 0.0, lie.z))
		aliz.rotation.y = PI * 0.5
		bunny.call("perform_affordance", aliz)
		await _settle(0.6)
		_world.call("place_in_room", "kitchen", "")
		await _settle(0.6)
		_arrive(aliz, "kitchen.table")
		await _settle(0.9)
		var spot: Vector3 = SpatialUtil.world_transform(_world.call("get_current_room")) \
				* (HouseLayout.child_surface("kitchen", "table")["position"] as Vector3)
		if SpatialUtil.world_position(bunny).distance_to(spot) > 0.08:
			_fail.append("table_bunny: Bunny is at %s, not at his table spot %s" % [SpatialUtil.world_position(bunny), spot])
		_quiet()
		await _shot("%s_table_bunny" % _prefix)

		# -- The sink close-up, from Free Play ----------------------------------------------
		SpatialUtil.set_world_position(aliz, spot + Vector3(0.0, 0.0, 0.62))
		aliz.rotation.y = 0.0
		bunny.call("perform_affordance", aliz)
		await _settle(0.6)
		_world.call("place_in_room", "bathroom", "")
		await _settle(0.6)
		_arrive(aliz, "bathroom.sink")
		await _settle(0.6)
		if not bool(_director.call("is_care_open")):
			_fail.append("sink_wash: the close-up did not open")
		else:
			var care: Control = _director.call("get_care_overlay")
			if String(care.call("get_care_kind")) != "washFace":
				_fail.append("sink_wash: the close-up is '%s'" % care.call("get_care_kind"))
			if bool(_layer.call("is_showing")):
				_fail.append("sink_wash: a badge shows under the close-up")
		await _shot("%s_sink_wash" % _prefix)
		if bool(_director.call("is_care_open")):
			_director.call("get_care_overlay").call("complete_by_touch")
		await _settle(0.4)
		aliz.call("put_down_carried")
		await _settle(0.6)

	# -- The locked door's sign ------------------------------------------------------------
	_world.call("place_in_room", "bedroom", "")
	await _settle(0.5)
	_quiet()
	_stand_at("bedroom.doorToBathroom")
	await _settle(0.6)
	_quiet()
	_expect("SOON", "bedroom.doorToBathroom", "locked_sign")
	await _shot("%s_locked_sign" % _prefix)
	_finish()


## Stands Aliz at the target and fires the arrival, as a finished walk would.
func _arrive(aliz: Node3D, target_id: String) -> void:
	_stand_at(target_id)
	aliz.emit_signal("interaction_ready", target_id)


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found: Node = _find_named(child, wanted)
		if found != null:
			return found
	return null


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
	# The project's own convention (`NavMath.yaw_towards`): the character faces
	# -Z, so this is atan2(-dx, -dz). The first version had the signs the other
	# way and stood her with her back to everything she was photographed at.
	character.rotation.y = NavMath.yaw_towards(stand, face, character.rotation.y)


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


## No flat disc lies on any floor in Free Play: the landing-pad markers that
## read as fake shadows under the toy box and the bath are off for good.
func _expect_no_floor_discs(shot: String) -> void:
	for disc: MeshInstance3D in _visible_discs(_world):
		_fail.append("%s: a flat disc '%s' lies on the floor at %s" % [shot, disc.get_path(), disc.global_position])


func _visible_discs(n: Node) -> Array:
	var found: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh is CylinderMesh \
			and (n as MeshInstance3D).is_visible_in_tree() and (n as MeshInstance3D).global_position.y < 0.5 \
			and n.name != "TapRipple" and not n.name.begins_with("Ripple"):
		found.append(n)
	for c: Node in n.get_children():
		found.append_array(_visible_discs(c))
	return found
