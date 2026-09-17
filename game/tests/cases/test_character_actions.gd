extends RefCounted

## The semantic action seam, and its graceful degradation.
##
## The spike ships two animations: `idle` and `walk`. The vocabulary the game
## will eventually need -- eat, drink, sit, sleep, brushTeeth, hug, pickUp, give,
## celebrate -- is already accepted by the API today. Asking for one of those must
## be a short, harmless pause that ends in idle: **never an error, never a crash,
## and never a character frozen in front of a child.**
##
## That is the property this file pins down, because it is the one that decides
## whether content authoring can run ahead of animation authoring.

const ActionDriver := preload("res://scripts/character/character_action_driver.gd")
const AnimationDriver := preload("res://scripts/character/animation_player_action_driver.gd")
const LittleBuddyCharacter := preload("res://scripts/character/little_buddy_character.gd")
const NavigationProvider := preload("res://scripts/navigation/navigation_provider.gd")
const SpikeBuddyView := preload("res://scenes/spike/spike_buddy_view.gd")

const DT: float = 1.0 / 60.0

## Every action the game is expected to grow into, none of which is animated yet.
const UNAUTHORED_ACTIONS: Array[String] = [
	"eat", "drink", "sit", "sleep", "brushTeeth", "hug", "pickUp", "give", "celebrate",
]


func test_name() -> String:
	return "character_actions"


func run():
	var failures: Array = []
	failures.append_array(_test_null_driver())
	failures.append_array(_test_animation_driver())
	failures.append_array(_test_clip_name_aliases())
	failures.append_array(_test_carry_rest())
	failures.append_array(_test_action_vocabulary())
	failures.append_array(_test_unauthored_action_never_freezes_the_character())
	failures.append_array(_test_action_interrupts_a_walk())
	return failures


## The honest fallback for a character with no animation player at all.
func _test_null_driver() -> Array:
	var failures: Array = []
	var driver: RefCounted = ActionDriver.new()
	if bool(driver.call("can_play", "walk")):
		failures.append("the null driver should not claim it can play anything")
	if bool(driver.call("play", "walk")):
		failures.append("the null driver should report that it played nothing")
	if not String(driver.call("get_current_action")).is_empty():
		failures.append("the null driver should report no current action")
	driver.call("rest", false)  # Must not crash.

	# A driver bound to nothing at all behaves identically.
	var orphan: RefCounted = AnimationDriver.create(null)
	if bool(orphan.call("can_play", "idle")):
		failures.append("a driver with no AnimationPlayer should play nothing")
	if bool(orphan.call("play", "idle")):
		failures.append("a driver with no AnimationPlayer should report failure, not crash")
	orphan.call("rest", true)
	return failures


func _test_animation_driver() -> Array:
	var failures: Array = []
	var view: Node3D = SpikeBuddyView.new()
	view.call("build")
	var player: AnimationPlayer = view.call("get_animation_player")
	if player == null:
		view.free()
		return ["the spike character view exposes no AnimationPlayer"]

	var driver: RefCounted = AnimationDriver.create(player)

	for shipped: String in ["idle", "walk"]:
		if not bool(driver.call("can_play", shipped)):
			failures.append("'%s' should be playable -- the spike ships it" % shipped)
		if not bool(driver.call("play", shipped)):
			failures.append("play('%s') should succeed" % shipped)
		if String(driver.call("get_current_action")) != shipped:
			failures.append("the driver should report '%s' as current" % shipped)

	# The whole point: an unauthored action declines, and LEAVES THE CURRENT
	# ANIMATION ALONE rather than stopping the character dead.
	driver.call("play", "walk")
	for unauthored: String in UNAUTHORED_ACTIONS:
		if bool(driver.call("can_play", unauthored)):
			failures.append("'%s' has no clip yet and must not claim to be playable" % unauthored)
		if bool(driver.call("play", unauthored)):
			failures.append("play('%s') should report that it played nothing" % unauthored)
	if String(driver.call("get_current_action")) != "walk":
		failures.append("an unauthored action must not disturb what is already playing, got '%s'"
				% String(driver.call("get_current_action")))
	if player.current_animation != "walk":
		failures.append("the AnimationPlayer should still be walking, got '%s'"
				% player.current_animation)

	driver.call("rest", false)
	if String(driver.call("get_current_action")) != "idle":
		failures.append("rest() should return to idle")

	view.free()
	return failures


## A re-exported model that renames `walk` to `Walk` must not silently stop
## animating. The alias table is the single place that mapping lives.
func _test_clip_name_aliases() -> Array:
	var failures: Array = []
	var player: AnimationPlayer = _player_with(["Walk", "Idle"])
	var driver: RefCounted = AnimationDriver.create(player)

	if not bool(driver.call("can_play", "walk")):
		failures.append("a capitalised 'Walk' clip should still satisfy the semantic 'walk'")
	if not bool(driver.call("play", "walk")):
		failures.append("play('walk') should find the 'Walk' clip")
	if player.current_animation != "Walk":
		failures.append("expected the 'Walk' clip to be playing, got '%s'" % player.current_animation)

	# And an action whose clip is named exactly like the action still works, even
	# if it is not in the alias table at all.
	var exotic: AnimationPlayer = _player_with(["waterThePlants"])
	var exotic_driver: RefCounted = AnimationDriver.create(exotic)
	if not bool(exotic_driver.call("can_play", "waterThePlants")):
		failures.append("an action whose clip shares its name should be playable without an alias")

	player.free()
	exotic.free()
	return failures


## CARRYING is a resting state, not a sixth animation state.
func _test_carry_rest() -> Array:
	var failures: Array = []
	var with_carry: AnimationPlayer = _player_with(["idle", "carryIdle"])
	var driver: RefCounted = AnimationDriver.create(with_carry)
	driver.call("rest", true)
	if with_carry.current_animation != "carryIdle":
		failures.append("resting while carrying should prefer a carry idle, got '%s'"
				% with_carry.current_animation)
	driver.call("rest", false)
	if with_carry.current_animation != "idle":
		failures.append("resting with empty hands should use plain idle")

	# No carry clip: fall back to idle rather than to nothing.
	var without: AnimationPlayer = _player_with(["idle"])
	var fallback: RefCounted = AnimationDriver.create(without)
	fallback.call("rest", true)
	if without.current_animation != "idle":
		failures.append("without a carry clip, carrying should fall back to idle, got '%s'"
				% without.current_animation)

	with_carry.free()
	without.free()
	return failures


func _test_action_vocabulary() -> Array:
	var failures: Array = []
	for action: String in UNAUTHORED_ACTIONS:
		if not bool(ActionDriver.is_known_action(action)):
			failures.append("'%s' should be recognised vocabulary even before it is animated"
					% action)
	for action: String in ["idle", "walk"]:
		if not bool(ActionDriver.is_known_action(action)):
			failures.append("'%s' should be recognised vocabulary" % action)
	if bool(ActionDriver.is_known_action("obviouslyATypo")):
		failures.append("an unknown action name should not be recognised; a typo in content "
				+ "should be catchable")
	return failures


## The end-to-end guarantee, at the level a mission would see it.
func _test_unauthored_action_never_freezes_the_character() -> Array:
	var failures: Array = []
	for action: String in UNAUTHORED_ACTIONS:
		var character: CharacterBody3D = _make_character()
		var started: Array = []
		var finished: Array = []
		character.connect("action_started", func(name: String) -> void: started.append(name))
		character.connect("action_finished", func(name: String) -> void: finished.append(name))

		if bool(character.call("can_play_action", action)):
			failures.append("'%s' is not animated yet, so can_play_action() should say so" % action)
		if not bool(character.call("play_action", action)):
			failures.append("play_action('%s') should still start" % action)
		if String(character.call("get_state_name")) != "interacting":
			failures.append("'%s' should put the character in the interacting state" % action)

		for _frame: int in range(600):
			character.call("step_movement", DT)
			if String(character.call("get_state_name")) == "idle":
				break

		if String(character.call("get_state_name")) != "idle":
			failures.append("'%s' left the character stuck in '%s'"
					% [action, String(character.call("get_state_name"))])
		if started != [action]:
			failures.append("'%s' should report starting exactly once, got %s" % [action, str(started)])
		if finished != [action]:
			failures.append("'%s' should report finishing exactly once, got %s" % [action, str(finished)])
		character.free()
	return failures


## Required behaviour 7, at the character level: an interaction requested while
## walking takes over cleanly and reports no arrival.
func _test_action_interrupts_a_walk() -> Array:
	var failures: Array = []
	var character: CharacterBody3D = _make_character()
	var arrivals: Array = []
	character.connect("arrived", func(id: String) -> void: arrivals.append(id))

	character.call("move_to_ground", 3.0, 0.0)
	for _frame: int in range(20):
		character.call("step_movement", DT)
	if String(character.call("get_state_name")) != "walking":
		failures.append("the character should be walking before the interruption")

	character.call("play_action", "drink")
	if String(character.call("get_state_name")) != "interacting":
		failures.append("an action mid-walk should take over immediately")

	for _frame: int in range(600):
		character.call("step_movement", DT)
		if String(character.call("get_state_name")) == "idle":
			break
	if not arrivals.is_empty():
		failures.append("an interrupted walk must never report an arrival, got %s" % str(arrivals))
	if String(character.call("get_state_name")) != "idle":
		failures.append("the character should end idle after an interrupting action")

	character.free()
	return failures


## -- Helpers -------------------------------------------------------------------

func _player_with(clip_names: Array) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for clip_name: String in clip_names:
		var animation := Animation.new()
		animation.length = 0.5
		library.add_animation(clip_name, animation)
	player.add_animation_library("", library)
	return player


func _make_character() -> CharacterBody3D:
	var character: CharacterBody3D = LittleBuddyCharacter.new()
	character.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	character.call("set_navigation_provider", NavigationProvider.new())
	return character
