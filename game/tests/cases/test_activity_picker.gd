extends RefCounted

## Play with Bunny -> the activity picker -> the house, on THAT mission.
##
## The owner's device playtest (2026-09-21) found two things: the primary
## button opened the Chapter 2 Baby Room, and there was no way back to Bunny's
## feeding mini-game once it had been played. This case pins the replacement
## end to end, with the real menu, the real picker and the real house:
##
##   1. the picker lists EVERY playable house level from content -- `imHungry`
##      and `snackTime` included, and still included once both are finished;
##   2. every card the picker lists is a mission a real director will start;
##   3. pressing Play with Bunny opens the picker (no walk home yet), tapping
##      `imHungry` walks home and opens `house_world.tscn` with `imHungry`
##      requested, and the house's first frame starts `imHungry` -- not
##      `snackTime`, which is what the journey's own picker would have chosen
##      with `imHungry` already complete;
##   4. Play with Bunny never opens the Baby Room, even for a profile whose
##      saved chapter says ch2;
##   5. a replay of a finished level pays 0 lifetime stars at the director's
##      reward seam, while its `starsByLevel` rating is kept;
##   6. first launch is untouched: a never-shown profile still walks straight
##      home to the tutorial.

const MainScript := preload("res://scenes/main/main.gd")
const PickerScript := preload("res://scenes/activities_menu/activity_picker.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")
const LevelSystemScript := preload("res://scripts/progression/level_system.gd")
const RewardLedgerScript := preload("res://scripts/progression/reward_ledger.gd")
const RewardManagerScript := preload("res://scripts/rewards/reward_manager.gd")

const MENU_SCENE: String = "res://scenes/main/main.tscn"
const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"
const BABY_ROOM_SCENE: String = "res://scenes/baby_room/baby_room.tscn"
const COVER_NAME: String = "SceneCover"
const MIN_TOUCH_SIDE: float = 240.0

## The seven authored Bunny-care levels (chapters.json, ch3 `levelIds`) by
## mission id. `imHungry` and `snackTime` are the two the owner could not get
## back to.
const EXPECTED_MISSIONS: Array = [
	"imHungry", "snackTime", "goodMorningRoutine", "morningRoutine",
	"breakfastTime", "toddlerPlayTime", "tidyAndBedtime",
]


func test_name() -> String:
	return "activity_picker"


func run():
	var failures: Array = []
	failures.append_array(_test_entries_come_from_content())
	failures.append_array(_test_every_card_is_a_mission_the_director_will_start())
	failures.append_array(_test_the_screen_is_child_sized())
	failures.append_array(_test_play_with_bunny_opens_the_picker_then_that_mission())
	failures.append_array(_test_back_returns_to_the_menu())
	failures.append_array(_test_a_replay_pays_no_lifetime_stars())
	failures.append_array(_test_first_launch_is_untouched())
	return failures


# ---------------------------------------------------------------------------
# A stand-in SaveService, so no case touches a real profile
# ---------------------------------------------------------------------------

class FakeSave extends Node:
	var stars: int = 0
	var completed: Dictionary = {}
	var stars_by_level: Dictionary = {}
	var current_level: String = ""
	var chapter: String = "ch3"
	## `onboardingDone: true` unless a case wants first launch.
	var settings: Dictionary = {"onboardingDone": true}

	func get_stars() -> int:
		return stars

	func add_stars(amount: int) -> int:
		stars += amount
		return stars

	func mark_activity_completed(_activity_id: String) -> void:
		pass

	func is_activity_completed(_activity_id: String) -> bool:
		return false

	func get_level_completed() -> Dictionary:
		return completed.duplicate()

	func mark_level_completed(level_id: String) -> void:
		completed[level_id] = true

	func is_level_completed(level_id: String) -> bool:
		return bool(completed.get(level_id, false))

	func get_stars_by_level() -> Dictionary:
		return stars_by_level.duplicate()

	func set_level_stars(level_id: String, value: int) -> void:
		stars_by_level[level_id] = value

	func get_level_stars(level_id: String) -> int:
		return int(stars_by_level.get(level_id, 0))

	func get_current_level() -> String:
		return current_level

	func set_current_level(level_id: String) -> void:
		current_level = level_id

	func get_current_chapter() -> String:
		return chapter

	func set_current_chapter(chapter_id: String) -> void:
		chapter = chapter_id

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value

	func unlock_level(_level_id: String) -> void:
		pass

	func unlock_chapter(_chapter_id: String) -> void:
		pass

	func save_profile() -> bool:
		return true

	func get_profile() -> Dictionary:
		return {
			"stars": stars, "levelCompleted": completed.duplicate(),
			"starsByLevel": stars_by_level.duplicate(), "settings": settings.duplicate(),
			"unlockedRooms": [],
		}


## Both finished, rated 3 and 2 -- the state the owner was in.
static func _played_save() -> FakeSave:
	var save := FakeSave.new()
	save.completed = {"imHungry": true, "snackTime": true}
	save.stars_by_level = {"imHungry": 3, "snackTime": 2}
	save.stars = 5
	save.current_level = "goodMorning"
	return save


# ---------------------------------------------------------------------------
# 1. The list
# ---------------------------------------------------------------------------

func _test_entries_come_from_content():
	var failures: Array = []
	var library: Object = ContentLibraryScript.create()
	var system: RefCounted = LevelSystemScript.create(library)
	var entries: Array = PickerScript.entries_for(system, library, {"imHungry": 3, "snackTime": 2})
	var ids: Array = []
	for entry: Dictionary in entries:
		ids.append(String(entry.get("missionId", "")))
	for wanted: String in EXPECTED_MISSIONS:
		if not ids.has(wanted):
			failures.append("the picker does not list '%s' (got %s)" % [wanted, str(ids)])
	if ids.size() > 0 and String(ids[0]) != "imHungry":
		failures.append("the first card is '%s'; the day starts with I'm Hungry!" % String(ids[0]))
	for entry: Dictionary in entries:
		if String(entry.get("title", "")).strip_edges().is_empty():
			failures.append("card '%s' has no title a grown-up can read aloud" % entry.get("missionId"))
		var level_id: String = String(entry.get("levelId", ""))
		if level_id == "imHungry" and int(entry.get("stars", -1)) != 3:
			failures.append("imHungry shows %s stars, not its saved 3" % str(entry.get("stars")))
		if level_id == "snackTime" and int(entry.get("stars", -1)) != 2:
			failures.append("snackTime shows %s stars, not its saved 2" % str(entry.get("stars")))
		if level_id == "goodMorning" and int(entry.get("stars", -1)) != 0:
			failures.append("an unplayed level shows %s stars" % str(entry.get("stars")))
	# Completion is not an input at all: the same call with nothing saved lists
	# the same cards. A finished level can never fall off the grid.
	var fresh: Array = []
	for entry: Dictionary in PickerScript.entries_for(system, library, {}):
		fresh.append(String(entry.get("missionId", "")))
	if fresh != ids:
		failures.append("the card list depends on the profile (%s vs %s); it must be content only"
				% [str(fresh), str(ids)])
	# Degrades to nothing rather than crashing.
	if not PickerScript.entries_for(null, library, {}).is_empty():
		failures.append("entries_for(null system) returned cards")
	if not PickerScript.entries_for(system, null, {}).is_empty():
		failures.append("entries_for(null library) returned cards")
	return failures


# ---------------------------------------------------------------------------
# 2. Every card starts
# ---------------------------------------------------------------------------

## The picker's playable filter is a copy of the director's. Prove they agree
## by asking a real director about every card, and every house level about the
## picker.
func _test_every_card_is_a_mission_the_director_will_start():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var save := FakeSave.new()
	var house: Node = _open_house(tree, save)
	if house == null:
		_remove_save(tree, save)
		return ["the house did not open"]
	var director: Node = house.call("ensure_level_director")
	if director == null:
		_close_house(tree, house)
		_remove_save(tree, save)
		return ["the house built no level director"]
	var library: Object = director.call("get_library")
	var system: RefCounted = director.call("get_level_system")
	var entries: Array = PickerScript.entries_for(system, library, {})
	var ids: Array = []
	for entry: Dictionary in entries:
		var mission_id: String = String(entry.get("missionId", ""))
		ids.append(mission_id)
		if not bool(director.call("_is_requestable_mission", mission_id)):
			failures.append("the picker lists '%s' but the director would not start it" % mission_id)
	for level_id: String in (system.call("get_levels_in_chapter", PickerScript.HOUSE_CHAPTER_ID) as PackedStringArray):
		var mission_id: String = String(system.call("get_mission_id_for_level", level_id))
		if mission_id.is_empty():
			continue
		if int(director.call("_playable_task_count", mission_id)) > 0 and not ids.has(mission_id):
			failures.append("the director can play '%s' but the picker hides it" % mission_id)
	_close_house(tree, house)
	_remove_save(tree, save)
	return failures


# ---------------------------------------------------------------------------
# 3. The screen
# ---------------------------------------------------------------------------

func _test_the_screen_is_child_sized():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var library: Object = ContentLibraryScript.create()
	var system: RefCounted = LevelSystemScript.create(library)
	var entries: Array = PickerScript.entries_for(system, library, {"imHungry": 3})
	var picker: Control = PickerScript.new()
	tree.root.add_child(picker)
	picker.call("build", entries)

	if String((picker.get_node_or_null("TitleLabel") as Label).text) != "Play with Bunny":
		failures.append("the picker's title is not 'Play with Bunny'")
	var back: Button = picker.call("get_back_button")
	if back == null:
		failures.append("the picker has no Back button")
	else:
		var w: float = back.offset_right - back.offset_left
		var h: float = back.offset_bottom - back.offset_top
		if w + 0.5 < MIN_TOUCH_SIDE or h + 0.5 < 120.0:
			failures.append("Back is %.0fx%.0f; it is big" % [w, h])
		if back.pressed.get_connections().is_empty():
			failures.append("Back does nothing when pressed")

	var cards: Array = picker.call("get_cards")
	if cards.size() != entries.size():
		failures.append("%d entries but %d cards" % [entries.size(), cards.size()])
	for card: Button in cards:
		var label: String = String(card.get_meta("missionId", ""))
		if card.custom_minimum_size.x + 0.5 < MIN_TOUCH_SIDE or card.custom_minimum_size.y + 0.5 < MIN_TOUCH_SIDE:
			failures.append("card '%s' is %s; ART_BIBLE §8 sets a 240x240 floor" % [label, str(card.custom_minimum_size)])
		if card.disabled:
			failures.append("card '%s' is disabled; every activity is always selectable" % label)
		var caption: Label = card.get_node_or_null("Caption") as Label
		if caption == null or caption.text.strip_edges().is_empty():
			failures.append("card '%s' has no caption" % label)
		elif caption.get_theme_font_size("font_size") < 27:
			failures.append("card '%s' caption is under the 27 pt floor" % label)
		if card.get_node_or_null("Picture") == null:
			failures.append("card '%s' has no picture; a pre-reader cannot tell it apart" % label)
		var stars: Node = card.get_node_or_null("Stars")
		if stars == null or stars.get_child_count() != 3:
			failures.append("card '%s' does not show a 0..3 star rating" % label)
		for child: Node in card.get_children():
			if child is Control and (child as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
				failures.append("card '%s': %s eats the touch meant for the card" % [label, child.name])
		if card.pressed.get_connections().is_empty():
			failures.append("card '%s' does nothing when pressed" % label)

	# One tap is one choice, and a second fast tap is not a second one.
	var chosen: Array = []
	picker.connect("activity_chosen", func(id: String) -> void: chosen.append(id))
	if not bool(picker.call("choose", "imHungry")):
		failures.append("there is no imHungry card to tap")
	picker.call("choose", "imHungry")
	picker.call("choose", "snackTime")
	if chosen != ["imHungry"]:
		failures.append("tapping imHungry (twice) then snackTime chose %s; one tap is one choice" % str(chosen))

	tree.root.remove_child(picker)
	picker.free()
	return failures


# ---------------------------------------------------------------------------
# 4. The whole route
# ---------------------------------------------------------------------------

func _test_play_with_bunny_opens_the_picker_then_that_mission():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var save: FakeSave = _played_save()
	# The strongest case: a saved chapter that the old chapter routing would
	# have sent to the Baby Room.
	save.chapter = "ch2"
	var previous_ledger: RefCounted = RewardManagerScript.shared_ledger()
	_install_save(tree, save)
	var menu: Node = _open_menu(tree)
	var before: Array = tree.root.get_children().duplicate()
	var previous_scene: Node = tree.current_scene

	var play: Button = menu.get_node_or_null("UI/SafeArea/PlayButton") as Button
	play.pressed.emit()
	if bool(menu.call("is_departing")):
		failures.append("Play with Bunny walked home before the child chose a card")
	if _opened_scene(tree, before) != null:
		failures.append("Play with Bunny opened a scene instead of the picker")
	var picker: Control = menu.call("get_activity_picker")
	if picker == null:
		failures.append("Play with Bunny opened no activity picker")
		_cleanup(tree, menu, previous_scene, before)
		_remove_save(tree, save)
		RewardManagerScript.set_shared_ledger(previous_ledger)
		return failures
	var ids: Array = picker.call("get_mission_ids")
	for wanted: String in ["imHungry", "snackTime"]:
		if not ids.has(wanted):
			failures.append("with both finished, the picker no longer offers '%s' (%s)" % [wanted, str(ids)])
	var hungry_card: Button = picker.call("get_card", "imHungry")
	if hungry_card != null:
		var stars: Node = hungry_card.get_node_or_null("Stars")
		var lit: int = 0
		if stars != null:
			for star: Node in stars.get_children():
				if bool(star.get_script().call("is_lit", int(star.get("state")))):
					lit += 1
		if lit != 3:
			failures.append("the finished imHungry card shows %d lit stars, not its rating of 3" % lit)

	# Tap the card the owner could not get back to.
	picker.call("choose", "imHungry")
	if not bool(menu.call("is_departing")):
		failures.append("tapping a card did not start the walk home")
	if bool(menu.call("is_activity_picker_open")):
		failures.append("the picker is still open while the walk home plays")
	menu.call("skip_departure")
	var opened: Node = _opened_scene(tree, before)
	if opened == null:
		failures.append("tapping imHungry opened nothing")
	else:
		if opened.scene_file_path == BABY_ROOM_SCENE:
			failures.append("Play with Bunny opened the BABY ROOM; the owner's bug, verbatim")
		elif opened.scene_file_path != HOUSE_SCENE:
			failures.append("tapping imHungry opened %s, not the house" % opened.scene_file_path)
		if opened.has_method("is_free_play") and bool(opened.call("is_free_play")):
			failures.append("the house came up in Free Play; a chosen activity is Story")
		if String(opened.call("get_requested_mission_id")) != "imHungry":
			failures.append("the house was handed '%s', not imHungry" % String(opened.call("get_requested_mission_id")))
		# The house's first frame.
		RewardManagerScript.set_shared_ledger(RewardLedgerScript.create())
		if not opened.is_node_ready():
			opened.call("_ready")
		opened.call("begin_session")
		var director: Node = opened.call("get_level_director")
		if director == null:
			failures.append("the house started no level director for the chosen activity")
		else:
			var started: String = String(director.call("get_mission_id"))
			if started != "imHungry":
				failures.append("the house started '%s'; the child tapped imHungry (the journey's own pick "
						% started + "would have been the next unfinished level, which is the bug)")
			if not bool(director.call("is_replaying_completed_level")):
				failures.append("the director does not know this imHungry is a replay of a finished level")
		if String(opened.call("get_requested_mission_id")) != "":
			failures.append("begin_session() did not consume the request; a second call would restart it")
	_cleanup(tree, menu, previous_scene, before)
	_remove_save(tree, save)
	RewardManagerScript.set_shared_ledger(previous_ledger)
	return failures


func _test_back_returns_to_the_menu():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var save: FakeSave = _played_save()
	_install_save(tree, save)
	var menu: Node = _open_menu(tree)
	var before: Array = tree.root.get_children().duplicate()
	var previous_scene: Node = tree.current_scene
	(menu.get_node_or_null("UI/SafeArea/PlayButton") as Button).pressed.emit()
	var picker: Control = menu.call("get_activity_picker")
	if picker == null:
		failures.append("no picker opened")
	else:
		(picker.call("get_back_button") as Button).pressed.emit()
		if bool(menu.call("is_activity_picker_open")):
			failures.append("Back left the picker open")
		if bool(menu.call("is_departing")) or _opened_scene(tree, before) != null:
			failures.append("Back went somewhere; it only closes the picker")
		# The five entries are still there to press.
		for button_name: String in ["PlayButton", "FreePlayButton", "DressUpButton", "ParentButton", "LearnWithAlizButton"]:
			var button: Button = menu.get_node_or_null("UI/SafeArea/%s" % button_name) as Button
			if button == null or button.disabled:
				failures.append("after Back, %s is missing or disabled" % button_name)
		# And Play with Bunny opens it again.
		(menu.get_node_or_null("UI/SafeArea/PlayButton") as Button).pressed.emit()
		if not bool(menu.call("is_activity_picker_open")):
			failures.append("Play with Bunny did not reopen the picker after Back")
	_cleanup(tree, menu, previous_scene, before)
	_remove_save(tree, save)
	return failures


# ---------------------------------------------------------------------------
# 5. Replay pays nothing
# ---------------------------------------------------------------------------

func _test_a_replay_pays_no_lifetime_stars():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var previous_ledger: RefCounted = RewardManagerScript.shared_ledger()

	# A finished imHungry, rated 3, ten lifetime stars.
	var replay_save: FakeSave = _played_save()
	replay_save.stars = 10
	var replay: Dictionary = _stars_after_first_task(tree, replay_save, "imHungry", failures, "replay")
	var paid_on_replay: int = int(replay.get("added", -1))
	if paid_on_replay != 0:
		failures.append("replaying a finished imHungry paid %d lifetime star(s); a replay pays 0" % paid_on_replay)
	var ratings: Dictionary = replay.get("starsByLevel", {})
	if int(ratings.get("imHungry", -1)) != 3:
		failures.append("the replay changed imHungry's rating to %s; starsByLevel stays"
				% str(ratings.get("imHungry")))
	if not bool((replay.get("completed", {}) as Dictionary).get("imHungry", false)):
		failures.append("the replay un-completed imHungry")

	# The same first task on a profile that has NOT finished it pays, so the
	# seam is a policy and not a broken reward path.
	var fresh_save := FakeSave.new()
	fresh_save.stars = 10
	var fresh: Dictionary = _stars_after_first_task(tree, fresh_save, "imHungry", failures, "first play")
	if int(fresh.get("added", 0)) <= 0:
		failures.append("a first play of imHungry paid nothing; the reward seam is broken, not policed")

	RewardManagerScript.set_shared_ledger(previous_ledger)
	return failures


## Opens the house on `mission_id`, completes its first task through the
## director's own handler, and returns `{added, starsByLevel, completed}`: how
## many lifetime stars that added, and the save's maps afterwards (read before
## the fake is freed).
func _stars_after_first_task(tree: SceneTree, save: FakeSave, mission_id: String, failures: Array, label: String) -> Dictionary:
	_install_save(tree, save)
	var ledger: RefCounted = RewardLedgerScript.create()
	ledger.set("min_interval_ms", 0)
	RewardManagerScript.set_shared_ledger(ledger)
	var house: Node = _open_house(tree, save)
	if house == null:
		failures.append("%s: the house did not open" % label)
		_remove_save(tree, save)
		return {}
	var director: Node = house.call("ensure_level_director")
	# The headless runner's root is not an ACTIVE tree during `_initialize()`,
	# so the director's reward manager cannot resolve `/root/SaveService` and
	# pins an in-memory stand-in. Point it at the fake by hand -- the same
	# `set_save_service()` seam the reward tests use -- so lifetime stars land
	# where this case can read them.
	var rewards: Node = director.call("get_reward_manager")
	rewards.call("set_save_service", save)
	var before: int = save.stars
	if not bool(director.call("start", mission_id)):
		failures.append("%s: start('%s') refused" % [label, mission_id])
	if String(director.call("get_mission_id")) != mission_id:
		failures.append("%s: start('%s') started '%s'" % [label, mission_id, director.call("get_mission_id")])
	var runner: Node = director.call("get_runner")
	var task_id: String = String(runner.call("get_current_task_id"))
	if task_id.is_empty():
		failures.append("%s: no current task to complete" % label)
	# The director's own handler -- the single writer -- as the runner's
	# `task_completed` would call it.
	director.call("_on_task_completed", task_id, 1)
	if int(rewards.call("get_stars")) != save.stars:
		failures.append("%s: the reward manager reads %d stars but the save holds %d"
				% [label, int(rewards.call("get_stars")), save.stars])
	# Rating and completion still go through `apply_completion`.
	director.call("_rate_and_record_level", mission_id)
	var result: Dictionary = {
		"added": save.stars - before,
		"starsByLevel": save.stars_by_level.duplicate(),
		"completed": save.completed.duplicate(),
	}
	_close_house(tree, house)
	_remove_save(tree, save)
	return result


# ---------------------------------------------------------------------------
# 6. First launch
# ---------------------------------------------------------------------------

func _test_first_launch_is_untouched():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var save := FakeSave.new()
	save.settings = {}   # never shown the game
	_install_save(tree, save)
	var menu: Node = _open_menu(tree)
	var before: Array = tree.root.get_children().duplicate()
	var previous_scene: Node = tree.current_scene
	if not bool(menu.call("is_first_launch")):
		failures.append("a profile with no onboardingDone is not first launch; the fake is wrong")
	(menu.get_node_or_null("UI/SafeArea/PlayButton") as Button).pressed.emit()
	if bool(menu.call("is_activity_picker_open")):
		failures.append("first launch opened the picker; it walks straight home to the tutorial")
	if not bool(menu.call("is_departing")):
		failures.append("first launch did not start the walk home")
	menu.call("skip_departure")
	var opened: Node = _opened_scene(tree, before)
	if opened == null:
		failures.append("first launch opened nothing")
	elif opened.scene_file_path != HOUSE_SCENE:
		failures.append("first launch opened %s, not the house" % opened.scene_file_path)
	_cleanup(tree, menu, previous_scene, before)
	_remove_save(tree, save)
	return failures


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

## Puts `save` under the root as "SaveService". Any stray one left by an
## earlier case is removed first: a second node of that name is renamed by the
## engine, and every lookup then finds the stale one -- which is exactly how the
## first run of this file failed, and took six unrelated cases with it.
func _install_save(tree: SceneTree, save: Node) -> void:
	var stray: Node = tree.root.get_node_or_null("SaveService")
	if stray != null and stray != save:
		tree.root.remove_child(stray)
		stray.free()
	save.name = "SaveService"
	if save.get_parent() == null:
		tree.root.add_child(save)


func _remove_save(tree: SceneTree, save: Node) -> void:
	if is_instance_valid(save):
		if save.get_parent() == tree.root:
			tree.root.remove_child(save)
		save.free()


func _open_menu(tree: SceneTree) -> Node:
	var packed: PackedScene = load(MENU_SCENE) as PackedScene
	var menu: Node = packed.instantiate()
	tree.root.add_child(menu)
	if not menu.is_node_ready():
		menu.notification(Node.NOTIFICATION_READY)
	return menu


func _open_house(tree: SceneTree, save: Node) -> Node:
	_install_save(tree, save)
	var packed: PackedScene = load(HOUSE_SCENE) as PackedScene
	if packed == null:
		return null
	var house: Node = packed.instantiate()
	tree.root.add_child(house)
	house.call("_ready")
	return house


func _close_house(tree: SceneTree, house: Node) -> void:
	if is_instance_valid(house):
		if house.get_parent() == tree.root:
			tree.root.remove_child(house)
		house.free()


static func _opened_scene(tree: SceneTree, before: Array) -> Node:
	for child: Node in tree.root.get_children():
		if before.has(child):
			continue
		if child is CanvasLayer and String(child.name) in [COVER_NAME, "SceneTransition"]:
			continue
		return child
	return null


func _cleanup(tree: SceneTree, menu: Node, previous_scene: Node, before: Array) -> void:
	var opened: Node = _opened_scene(tree, before)
	while opened != null:
		tree.root.remove_child(opened)
		opened.free()
		opened = _opened_scene(tree, before)
	for cover_name: String in [COVER_NAME, "SceneTransition"]:
		var cover: Node = tree.root.get_node_or_null(cover_name)
		if cover != null:
			tree.root.remove_child(cover)
			cover.free()
	tree.current_scene = previous_scene
	if is_instance_valid(menu):
		if menu.get_parent() == tree.root:
			tree.root.remove_child(menu)
		menu.free()
