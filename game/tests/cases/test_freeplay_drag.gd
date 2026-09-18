extends RefCounted

## Free Play's drag: the lesson first run teaches, made real.
##
## First run shows a child a drag. Free Play used to stage **no draggable object
## at all**, so that lesson was a hand sliding over an empty floor -- a gesture
## mimed at nothing, in the one mode a brand new child is most likely to be in.
##
## What has to be true for the gesture to be worth teaching:
##
##   1. **There is something to pick up, in every room.** Not in one room, and
##      not only where an authored task happens to put one.
##   2. **It has somewhere to go, and it is not already there.** A pickup that
##      spawns inside its own landing pad delivers itself; a pad on the far side
##      of the house is a drag no four-year-old will finish.
##   3. **Arriving is satisfying.** Free Play has no objective, so the drop is
##      worth exactly what it feels like: `place_soft`, the English word, and
##      Little Buddy doing something with the thing.
##   4. **It can be done again.** Nothing in a sandbox is ever used up.
##   5. **A child who cannot drag is not locked out.** A plain tap delivers too.
##   6. **Layers never mix.** Pickups are layer 1, activity targets are layer 2
##      (`test_architecture_guard.gd` owns the rule; this proves the new spawns
##      obey it).
##
## `run()` and every `_test_*` helper are untyped on purpose (contract section 8).

const Words := preload("res://scripts/gameplay/house_freeplay_words.gd")
const DropZoneScript := preload("res://scripts/gameplay/drop_zone.gd")
const HouseStageScript := preload("res://scripts/gameplay/house_stage.gd")
const ActionDriverScript := preload("res://scripts/character/character_action_driver.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const ActivityTargetScript := preload("res://scripts/navigation/activity_target.gd")

const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"

const MODE_FREE_PLAY: int = 1

## `DraggableObject.collision_layer`. One, and never the activity-target layer.
const PICKUP_LAYER: int = 1

## The furthest a child should have to drag something, in metres of world space.
## Generous -- the rooms are 4 m across -- but it catches a pad that has been
## pointed at another room entirely.
const MAX_REACH_M: float = 3.2


class FakeTts extends RefCounted:
	var lines: Array = []

	func speak(text: String, _interrupt: bool = true) -> void:
		lines.append(text)


class FakeSave extends RefCounted:
	var settings: Dictionary = {}

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		if settings.has(key):
			return settings[key]
		return default_value

	func get_stars() -> int:
		return 0


## Writes down every sound it was asked for, so "the drop made no noise" is a
## visible regression rather than a silent one.
class FakeSfx extends RefCounted:
	var played: Array = []

	func play(sfx_name: String, _volume_db: float = 0.0) -> void:
		played.append(sfx_name)


func test_name() -> String:
	return "freeplay_drag"


func run():
	var failures: Array = []
	failures.append_array(_test_the_table_names_real_things())
	failures.append_array(_test_every_room_has_something_to_pick_up())
	failures.append_array(_test_a_pickup_has_somewhere_to_go_and_is_not_already_there())
	failures.append_array(_test_dragging_it_there_is_satisfying())
	failures.append_array(_test_it_can_be_done_again())
	failures.append_array(_test_a_child_who_cannot_drag_is_not_locked_out())
	failures.append_array(_test_pickups_never_mix_with_activity_targets())
	failures.append_array(_test_walking_into_another_room_changes_the_toys())
	failures.append_array(_test_first_run_can_point_at_a_real_drag())
	return failures


## -- The table -------------------------------------------------------------------

## Against the real content set and the real vocabularies, not against itself.
func _test_the_table_names_real_things():
	var failures: Array = []
	var library: RefCounted = ContentLibraryScript.create()
	var known_actions: Array = ActionDriverScript.KNOWN_ACTIONS
	var known_zones: Array = DropZoneScript.known_zone_ids()

	for room_id: Variant in Words.DRAGGABLES.keys():
		for entry: Variant in Words.draggables_for(room_id):
			var data: Dictionary = entry as Dictionary
			var object_id: String = String(data.get("objectId", ""))
			var interaction: String = String(data.get("interaction", ""))
			var action: String = String(data.get("action", ""))

			if not bool(library.call("has_object", object_id)):
				failures.append(
					"%s offers '%s', which is not a record in content/objects.json -- nothing "
					% [String(room_id), object_id] + "would spawn and the floor stays empty."
				)
			if not DropZoneScript.is_known_interaction(interaction):
				failures.append("'%s' declares interaction '%s', which maps to no landing pad"
						% [object_id, interaction])
			elif not known_zones.has(DropZoneScript.zone_id_for_interaction(interaction)):
				failures.append("'%s' delivers into zone '%s', which does not exist"
						% [object_id, DropZoneScript.zone_id_for_interaction(interaction)])
			if not known_actions.has(action):
				failures.append(
					"'%s' reacts with '%s', which is not one of the contract's semantic actions. "
					% [object_id, action] + "Little Buddy would take it and stand there."
				)

	# One furniture pad per room at most: `house_stage.gd` tracks every prop pad
	# to a single focus point, so two would end up on top of each other.
	for room_id: Variant in Words.DRAG_FOCUS.keys():
		var local: String = Words.drag_focus_for(room_id)
		if Words.word_for(local).is_empty():
			failures.append("%s's landing pad sits on '%s', which teaches no word"
					% [String(room_id), local])
		var prop_zones: Array = []
		for entry: Variant in Words.draggables_for(room_id):
			var zone_id: String = DropZoneScript.zone_id_for_interaction(
					String((entry as Dictionary).get("interaction", "")))
			if not zone_id.is_empty() and not HouseStageScript.ZONE_BODY_OFFSETS.has(zone_id) \
					and not prop_zones.has(zone_id):
				prop_zones.append(zone_id)
		if prop_zones.size() > 1:
			failures.append(
				"%s uses %s furniture pads. They all track one focus point, so they would be "
				% [String(room_id), str(prop_zones)] + "drawn in the same place."
			)

	# Both flavours must exist somewhere, or the child only ever learns one.
	var to_buddy: bool = false
	var to_furniture: bool = false
	for room_id: Variant in Words.DRAGGABLES.keys():
		for entry: Variant in Words.draggables_for(room_id):
			var zone_id: String = DropZoneScript.zone_id_for_interaction(
					String((entry as Dictionary).get("interaction", "")))
			if HouseStageScript.ZONE_BODY_OFFSETS.has(zone_id):
				to_buddy = true
			elif not zone_id.is_empty():
				to_furniture = true
	if not to_buddy:
		failures.append("nothing anywhere is dragged to Little Buddy himself")
	if not to_furniture:
		failures.append("nothing anywhere is dragged to a piece of furniture")

	return failures


## -- There is something to pick up -----------------------------------------------

func _test_every_room_has_something_to_pick_up():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]
	var director: Node = _make_director(world)
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	director.call("start")

	for room_id: Variant in world.call("get_room_ids"):
		var staged: Array = director.call("stage_draggables", String(room_id))
		if staged.is_empty():
			failures.append(
				"'%s' stages nothing a child can pick up. Free Play is where a brand new child "
				% String(room_id)
				+ "is taught the drag gesture, and a lesson with nothing to practise on is a "
				+ "hand waving over an empty floor."
			)
			continue
		for node: Variant in staged:
			if not (node is Node3D):
				failures.append("'%s' staged something that is not a 3D object" % String(room_id))
				continue
			# NOT `is_inside_tree()`: in the `--script` runner nothing under
			# `root` reports itself as in the tree, which is the same quirk that
			# makes `global_position` return the origin (contract section 8).
			if (node as Node).get_parent() == null:
				failures.append("a pickup in '%s' was never added to the scene" % String(room_id))

	_release(world)
	return failures


func _test_a_pickup_has_somewhere_to_go_and_is_not_already_there():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]
	var director: Node = _make_director(world)
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	director.call("start")

	for room_id: Variant in world.call("get_room_ids"):
		# Walk there first. Half the landing pads ride on Little Buddy, so a room
		# staged while he is standing somewhere else measures the distance
		# between two rooms rather than the length of a drag.
		world.call("place_in_room", String(room_id), "default")
		director.call("step", 0.1)
		var demo: Dictionary = director.call("get_drag_demo")
		if demo.is_empty():
			failures.append("'%s' has no drag anyone could demonstrate" % String(room_id))
			continue

		var from: Vector3 = demo.get("from", Vector3.ZERO)
		var to: Vector3 = demo.get("to", Vector3.ZERO)
		var span: float = from.distance_to(to)
		if span <= 0.30:
			failures.append(
				"in '%s' the %s starts %.2f m from its landing pad. A pickup that spawns inside "
				% [String(room_id), String(demo.get("objectWord", "")), span]
				+ "its own pad delivers itself the instant it is touched, which teaches nothing "
				+ "about dragging."
			)
		if span > MAX_REACH_M:
			failures.append(
				"in '%s' the %s is %.2f m from its landing pad -- further than a four-year-old "
				% [String(room_id), String(demo.get("objectWord", "")), span]
				+ "will drag anything before letting go."
			)
		if String(demo.get("objectWord", "")).strip_edges().is_empty():
			failures.append("the pickup in '%s' has no English word to teach" % String(room_id))

	_release(world)
	return failures


## -- Arriving is satisfying ------------------------------------------------------

## Two halves, because the headless runner can only honestly assert one of them:
##
##   * that the pickup really is **wired to its pad** -- the private `_drop_zone`
##     is read directly, because `DraggableObject` exposes no getter and "the
##     drag delivers nothing because nobody set a zone" is precisely the
##     regression worth catching;
##   * that a delivery **pays off**, driven through the object's own delivery
##     path rather than through the director's back door.
##
## The geometric half (is the pad far enough away to be a drag, and near enough
## to be finishable) lives in `_test_a_pickup_has_somewhere_to_go...`, which uses
## `spatial_util.gd` -- `global_position` reports the origin for everything in
## this runner, so a distance measured with it would compare 0 with 0 and pass
## for ever.
func _test_dragging_it_there_is_satisfying():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]
	var character: Node = world.call("get_character")
	var tts: FakeTts = FakeTts.new()
	var sfx: FakeSfx = FakeSfx.new()
	var director: Node = _make_director(world, tts, sfx)
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	director.call("start")
	director.call("step", 0.1)

	var pickup: Node3D = _first_pickup(director)
	if pickup == null:
		_release(world)
		return ["Free Play staged nothing to drag"]
	var zone: Node3D = _zone_for(director, pickup)
	if zone == null:
		_release(world)
		return ["the pickup has no landing pad"]

	if pickup.get("_drop_zone") != zone:
		failures.append(
			"the %s was never given a landing pad, so dragging it anywhere at all would end with "
			% String(pickup.get("word"))
			+ "it sliding quietly home. `DraggableObject` only delivers into a zone it was told "
			+ "about."
		)
	if float(pickup.get("_drop_zone_radius")) <= 0.0:
		failures.append("the landing pad has no catch radius; nothing could ever land in it")
	if pickup.get_signal_connection_list("chosen").is_empty():
		failures.append("nothing is listening for the %s being delivered"
				% String(pickup.get("word")))

	var dropped: Array = []
	director.connect("object_dropped", func(id: String, word: String) -> void: dropped.append([id, word]))

	tts.lines.clear()
	sfx.played.clear()
	# Through the object's own delivery path, the one both a drag into the pad
	# and a tap funnel into (`DraggableObject._on_dropped_in_zone`).
	pickup.call("try_deliver_from_raycast")

	if dropped.size() != 1:
		failures.append(
			"dragging the %s onto its landing pad did nothing at all (%d deliveries). The drop "
			% [String(pickup.get("word")), dropped.size()]
			+ "IS the reward in Free Play -- there is no objective for it to count towards."
		)
		_release(world)
		return failures

	var word: String = String(pickup.get("word"))
	if not tts.lines.has(word):
		failures.append("the drop did not say '%s' (the voice heard %s); the spoken word is the "
				% [word, str(tts.lines)] + "only content Free Play has")
	if not sfx.played.has("place_soft"):
		failures.append(
			"the drop made no sound (%s). `place_soft` exists for exactly this moment and was "
			% str(sfx.played) + "wired to nothing."
		)
	var hud: Control = director.call("get_hud")
	if hud != null and String(hud.call("get_word_text")) != word:
		failures.append("the word card says '%s' after dropping the %s"
				% [String(hud.call("get_word_text")), word])
	if tts.lines.size() < 2:
		failures.append("the drop said the word and then nothing; Little Buddy owes the child a "
				+ "reaction, not silence")
	if String(character.call("get_held_action")).is_empty() and not bool(character.call("is_busy")):
		failures.append(
			"Little Buddy was handed the %s and did nothing with it. A character who takes a "
			% word + "thing and stands there makes the whole gesture feel broken."
		)
	# Kindness (CLAUDE.md child UX): no report-card vocabulary, ever.
	for line: Variant in tts.lines:
		for banned: String in ["wrong", "fail", "oops", "score", "percent", "%"]:
			if String(line).to_lower().contains(banned):
				failures.append("the drop said '%s', which is not how this game talks to a "
						% String(line) + "four-year-old")

	_release(world)
	return failures


func _test_it_can_be_done_again():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]
	var director: Node = _make_director(world)
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	director.call("start")
	director.call("step", 0.1)

	var pickup: Node3D = _first_pickup(director)
	var zone: Node3D = _zone_for(director, pickup) if pickup != null else null
	if pickup == null or zone == null:
		_release(world)
		return ["Free Play staged nothing to drag"]

	var home: Vector3 = pickup.call("get_home_position")
	pickup.call("try_deliver_from_raycast")

	# Long enough for the object to have been sent home again.
	for _tick: int in range(40):
		director.call("step", 0.1)

	if not bool(pickup.get("drag_enabled")):
		failures.append("the pickup was switched off after one drop; Free Play has no objective, "
				+ "so nothing in it is ever used up")
	if bool(pickup.get("_delivered_this_drag")):
		failures.append(
			"the pickup is still latched as delivered long after it landed, so the next drag "
			+ "into the pad would do nothing at all."
		)
	var dropped_twice: Array = []
	director.connect("object_dropped", func(id: String, _w: String) -> void: dropped_twice.append(id))
	pickup.call("try_deliver_from_raycast")
	if dropped_twice.is_empty():
		failures.append(
			"the same thing could not be dragged to the same place twice. A four-year-old who "
			+ "has just worked out how to do something does it eleven more times."
		)
	if not is_zero_approx(home.distance_to(pickup.call("get_home_position"))):
		failures.append("the pickup adopted the landing pad as its new home, so the next drag "
				+ "starts from where the last one finished")

	_release(world)
	return failures


func _test_a_child_who_cannot_drag_is_not_locked_out():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]
	var director: Node = _make_director(world)
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	director.call("start")
	director.call("step", 0.1)

	var pickup: Node3D = _first_pickup(director)
	if pickup == null:
		_release(world)
		return ["Free Play staged nothing to drag"]

	var dropped: Array = []
	director.connect("object_dropped", func(id: String, _w: String) -> void: dropped.append(id))
	# The tap fallback, which `DraggableObject` routes into the same latch.
	pickup.call("try_deliver_from_raycast")

	if dropped.is_empty():
		failures.append(
			"tapping the pickup delivered nothing. A drag is a hard gesture for a four-year-old "
			+ "and touch fallback is not optional (CLAUDE.md); a child who cannot drag must still "
			+ "be able to give Little Buddy the apple."
		)

	_release(world)
	return failures


## -- Layers ----------------------------------------------------------------------

func _test_pickups_never_mix_with_activity_targets():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]
	var director: Node = _make_director(world)
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	director.call("start")

	var target_layer: int = int(ActivityTargetScript.ACTIVITY_TARGET_LAYER)
	for room_id: Variant in world.call("get_room_ids"):
		for node: Variant in director.call("stage_draggables", String(room_id)):
			if not (node is Area3D):
				continue
			var layer: int = int((node as Area3D).collision_layer)
			if layer != PICKUP_LAYER:
				failures.append(
					"a pickup in '%s' is on collision layer %d, not %d. Layer %d is the activity "
					% [String(room_id), layer, PICKUP_LAYER, target_layer]
					+ "targets' -- the navigation raycast would start walking the child to a "
					+ "thing in their own hand."
				)
			if (layer & target_layer) != 0:
				failures.append("a pickup in '%s' shares the activity-target layer" % String(room_id))

	_release(world)
	return failures


func _test_walking_into_another_room_changes_the_toys():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]
	var director: Node = _make_director(world)
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	director.call("start")

	var before: Array = _object_ids(director.call("get_draggables"))
	world.call("place_in_room", "kitchen", "default")
	var after: Array = _object_ids(director.call("get_draggables"))

	if String(director.call("get_staged_room_id")) != "kitchen":
		failures.append("walking into the kitchen left the bedroom's toys staged")
	if after.is_empty():
		failures.append("the kitchen came up with nothing to pick up")
	if before == after:
		failures.append("every room offers the same things (%s), so there is no reason to walk "
				% str(after) + "into another one")
	for id: Variant in after:
		if before.has(id):
			failures.append("'%s' was left behind in the room the child walked out of" % String(id))

	_release(world)
	return failures


## -- The lesson and the thing being taught are the same thing ---------------------

## Free Play's pickups exist BECAUSE first run teaches a drag. This proves the
## two still meet: the tutorial can ask Free Play for a real object without
## starting the Free Play loop underneath itself.
func _test_first_run_can_point_at_a_real_drag():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]
	var director: Node = _make_director(world)
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]

	# NOT started -- this is what first run does, before the session begins.
	var staged: Array = director.call("ensure_draggables")
	if staged.is_empty():
		failures.append(
			"first run cannot lay anything out to drag without starting the Free Play loop, so "
			+ "the tutorial would have to mime the gesture over an empty floor again."
		)
	if bool(director.call("is_running")):
		failures.append("asking for the pickups started the Free Play session underneath the "
				+ "tutorial")
	if director.call("ensure_draggables").size() != staged.size():
		failures.append("ensure_draggables() is not idempotent; a second call laid out a second "
				+ "row of toys on top of the first")

	var demo: Dictionary = director.call("get_drag_demo")
	if demo.is_empty():
		failures.append("there is no drag for first run to demonstrate")
	elif String(demo.get("objectWord", "")).strip_edges().is_empty():
		failures.append("first run would demonstrate dragging something with no name")

	_release(world)
	return failures


## -- Helpers ---------------------------------------------------------------------

func _build_house():
	if not ResourceLoader.exists(HOUSE_SCENE):
		return null
	var packed: Resource = load(HOUSE_SCENE)
	if not (packed is PackedScene):
		return null
	var world: Node = (packed as PackedScene).instantiate()
	if world == null:
		return null
	world.call("set_progression_mode", MODE_FREE_PLAY)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(world)
	# `_ready()` does not fire for a node added to the root in the `--script`
	# runner, so the world is built by hand.
	world.call("build_world")
	return world


func _make_director(world, tts = null, sfx = null):
	var director: Node = world.call("ensure_free_play_director")
	if director == null:
		return null
	director.call("set_tts", tts if tts != null else FakeTts.new())
	director.call("set_save_service", FakeSave.new())
	director.call("set_sfx", sfx if sfx != null else FakeSfx.new())
	return director


func _first_pickup(director):
	for node: Variant in director.call("get_draggables"):
		if node is Node3D and is_instance_valid(node as Node):
			return node as Node3D
	return null


func _zone_for(director, pickup):
	var entry: Dictionary = Words.draggable_entry(
		String(director.call("get_staged_room_id")), String((pickup as Node).get("object_id"))
	)
	var zone_id: String = DropZoneScript.zone_id_for_interaction(String(entry.get("interaction", "")))
	var stage: Node = director.call("get_stage")
	if stage == null:
		return null
	var zone: Node = stage.call("get_drop_zone", zone_id)
	return zone as Node3D if zone is Node3D else null


func _object_ids(nodes: Array) -> Array:
	var ids: Array = []
	for node: Variant in nodes:
		if node is Node and is_instance_valid(node as Node):
			ids.append(String((node as Node).get("object_id")))
	return ids


func _release(world) -> void:
	if world == null:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and world.get_parent() == tree.root:
		tree.root.remove_child(world)
	world.free()
