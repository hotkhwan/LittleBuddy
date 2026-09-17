extends RefCounted

## The semantic action seam: the vocabulary, the one-shot/held distinction, the
## carry composition, and the graceful degradation that holds it all together.
##
## Contract §3 names sixteen actions and requires that content moves the
## character with `play_action("drink")` and never an animation filename. Two
## properties decide whether content authoring can run ahead of animation
## authoring, and both are pinned here:
##
##   1. **An unauthored action is a short, harmless pause that ends cleanly.**
##      Never an error, never a crash, never a character frozen in front of a
##      child.
##   2. **A posture is not an event.** `sit`, `sleep` and `hold` persist until
##      released; `wave`, `eat` and `clap` end by themselves. Both still report
##      `action_started` and `action_finished`, so a mission can await either
##      without knowing which it asked for.

const ActionDriver := preload("res://scripts/character/character_action_driver.gd")
const AnimationDriver := preload("res://scripts/character/animation_player_action_driver.gd")
const LittleBuddyCharacter := preload("res://scripts/character/little_buddy_character.gd")
const NavigationProvider := preload("res://scripts/navigation/navigation_provider.gd")
const SpikeBuddyView := preload("res://scenes/spike/spike_buddy_view.gd")

const DT: float = 1.0 / 60.0

## Contract §3, verbatim and in order. If this list and the contract ever
## disagree, the contract wins and this is the thing that is wrong.
const CONTRACT_VOCABULARY: Array[String] = [
	"idle", "walk", "wave", "point", "clap", "pickUp", "hold", "give", "eat",
	"drink", "brushTeeth", "sit", "stand", "hug", "sleep", "wake", "celebrate",
]

## Postures. Everything else is a one-shot.
const HOLD_ACTIONS: Array[String] = ["hold", "sit", "sleep"]

## The spike view ships `idle` and `walk` only, so every other action in the
## vocabulary is unauthored against it.
const UNAUTHORED_AGAINST_SPIKE: Array[String] = [
	"wave", "point", "clap", "pickUp", "hold", "give", "eat", "drink",
	"brushTeeth", "sit", "stand", "hug", "sleep", "wake", "celebrate",
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
	failures.append_array(_test_hold_and_one_shot_are_distinct())
	failures.append_array(_test_unauthored_action_never_freezes_the_character())
	failures.append_array(_test_every_action_reports_its_own_name())
	failures.append_array(_test_held_pose_persists_until_released())
	failures.append_array(_test_a_hold_never_makes_the_character_unavailable())
	failures.append_array(_test_pick_up_hold_give_composes())
	failures.append_array(_test_clip_length_times_the_action())
	failures.append_array(_test_action_interrupts_a_walk())
	return failures


## The honest fallback for a character with no animation player at all.
func _test_null_driver():
	var failures: Array = []
	var driver: RefCounted = ActionDriver.new()
	if bool(driver.call("can_play", "walk")):
		failures.append("the null driver should not claim it can play anything")
	if bool(driver.call("play", "walk")):
		failures.append("the null driver should report that it played nothing")
	if not String(driver.call("get_current_action")).is_empty():
		failures.append("the null driver should report no current action")
	if float(driver.call("get_action_duration", "drink")) > 0.0:
		failures.append("the null driver has no clips and so should have no opinion on timing")
	driver.call("rest", false)  # Must not crash.

	# A driver bound to nothing at all behaves identically.
	var orphan: RefCounted = AnimationDriver.create(null)
	if bool(orphan.call("can_play", "idle")):
		failures.append("a driver with no AnimationPlayer should play nothing")
	if bool(orphan.call("play", "idle")):
		failures.append("a driver with no AnimationPlayer should report failure, not crash")
	orphan.call("rest", true)
	return failures


func _test_animation_driver():
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
	for unauthored: String in UNAUTHORED_AGAINST_SPIKE:
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
func _test_clip_name_aliases():
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

	# `hold` and the carry idle are the same pose; authoring it twice would
	# guarantee the two drift apart, so `hold` falls through to `carryIdle`.
	var carrier: AnimationPlayer = _player_with(["idle", "carryIdle"])
	var carry_driver: RefCounted = AnimationDriver.create(carrier)
	if not bool(carry_driver.call("can_play", "hold")):
		failures.append("'hold' should fall back to the carry idle clip")
	carry_driver.call("play", "hold")
	if carrier.current_animation != "carryIdle":
		failures.append("play('hold') should reach 'carryIdle', got '%s'" % carrier.current_animation)

	player.free()
	exotic.free()
	carrier.free()
	return failures


## CARRYING is a resting state, not a sixth animation state.
func _test_carry_rest():
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


## The whole contract vocabulary, recognised before any of it is animated.
func _test_action_vocabulary():
	var failures: Array = []
	for action: String in CONTRACT_VOCABULARY:
		if not bool(ActionDriver.is_known_action(action)):
			failures.append("'%s' is in contract §3 and should be recognised vocabulary even "
					% action + "before it is animated")
		if ActionDriver.default_duration(action) <= 0.0:
			failures.append("'%s' has no sensible default duration" % action)
	if bool(ActionDriver.is_known_action("obviouslyATypo")):
		failures.append("an unknown action name should not be recognised; a typo in content "
				+ "should be catchable")

	# The vocabulary is exactly the contract's, no more and no less. A quietly
	# added seventeenth action is content nobody agreed to author.
	var known: Array = []
	known.append_array(ActionDriver.KNOWN_ACTIONS)
	known.sort()
	var wanted: Array = []
	wanted.append_array(CONTRACT_VOCABULARY)
	wanted.sort()
	if known != wanted:
		failures.append("the vocabulary has drifted from contract §3: expected %s, got %s"
				% [str(wanted), str(known)])
	return failures


## The design decision, asserted: three postures, everything else an event, and
## every posture has a named way out.
func _test_hold_and_one_shot_are_distinct():
	var failures: Array = []
	for action: String in HOLD_ACTIONS:
		if not bool(ActionDriver.is_hold_action(action)):
			failures.append("'%s' is a posture and should be a hold action" % action)
		var release: String = ActionDriver.release_action_for(action)
		if release.is_empty():
			failures.append("'%s' has no natural release; a posture a child cannot leave is a "
					% action + "dead end")
		elif not bool(ActionDriver.is_known_action(release)):
			failures.append("'%s' releases with '%s', which is not in the vocabulary"
					% [action, release])
	for action: String in CONTRACT_VOCABULARY:
		if HOLD_ACTIONS.has(action):
			continue
		if bool(ActionDriver.is_hold_action(action)):
			failures.append("'%s' is an event, not a posture; making it hold would leave the "
					% action + "character stuck in it")
	# An unknown name defaults to the SAFE side: a one-shot always ends itself.
	if bool(ActionDriver.is_hold_action("obviouslyATypo")):
		failures.append("an unrecognised action must default to a one-shot, never to a hold")
	return failures


## The end-to-end guarantee, at the level a mission would see it: every action in
## the vocabulary starts and finishes exactly once with no clip authored at all.
func _test_unauthored_action_never_freezes_the_character():
	var failures: Array = []
	for action: String in CONTRACT_VOCABULARY:
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

		var resting: Array = ["idle", "carrying"]
		for _frame: int in range(900):
			character.call("step_movement", DT)
			if resting.has(String(character.call("get_state_name"))):
				break

		var ended_in: String = String(character.call("get_state_name"))
		if not resting.has(ended_in):
			failures.append("'%s' left the character stuck in '%s'" % [action, ended_in])
		if started != [action]:
			failures.append("'%s' should report starting exactly once, got %s" % [action, str(started)])
		if finished != [action]:
			failures.append("'%s' should report finishing exactly once, got %s" % [action, str(finished)])
		if bool(character.call("is_busy")):
			failures.append("'%s' left the character reporting itself busy forever" % action)
		character.free()
	return failures


## `action_finished("")` would be indistinguishable from "something finished, we
## do not know what", and a mission keyed on the name would silently never fire.
func _test_every_action_reports_its_own_name():
	var failures: Array = []
	for action: String in CONTRACT_VOCABULARY:
		var character: CharacterBody3D = _make_character()
		var finished: Array = []
		character.connect("action_finished", func(name: String) -> void: finished.append(name))
		character.call("play_action", action)
		for _frame: int in range(900):
			character.call("step_movement", DT)
			if not finished.is_empty():
				break
		if finished.is_empty():
			failures.append("'%s' never reported finishing" % action)
		elif String(finished[0]).is_empty():
			failures.append("'%s' finished with an EMPTY name; a mission keyed on the action "
					% action + "name would never fire")
		elif String(finished[0]) != action:
			failures.append("'%s' finished under the wrong name '%s'" % [action, String(finished[0])])
		character.free()
	return failures


## A posture persists; an event does not. This is the distinction, observed.
func _test_held_pose_persists_until_released():
	var failures: Array = []

	for action: String in HOLD_ACTIONS:
		var character: CharacterBody3D = _make_character()
		character.call("play_action", action)
		_settle(character)
		if String(character.call("get_held_action")) != action:
			failures.append("'%s' should still be held after it finishes, got '%s'"
					% [action, String(character.call("get_held_action"))])
		# A long time later, still held. A toddler who sat down is still sitting.
		for _frame: int in range(600):
			character.call("step_movement", DT)
		if String(character.call("get_held_action")) != action:
			failures.append("'%s' stopped holding itself after a while; a posture must not "
					% action + "time out")
		if String(character.call("release_action")) != action:
			failures.append("release_action() should report releasing '%s'" % action)
		if not String(character.call("get_held_action")).is_empty():
			failures.append("'%s' should be released once release_action() is called" % action)
		if not String(character.call("release_action")).is_empty():
			failures.append("releasing nothing should report nothing, not a phantom pose")
		character.free()

	# An event leaves nothing behind.
	for action: String in ["wave", "eat", "clap", "celebrate"]:
		var character: CharacterBody3D = _make_character()
		character.call("play_action", action)
		_settle(character)
		if not String(character.call("get_held_action")).is_empty():
			failures.append("'%s' is an event and must not leave a held pose behind" % action)
		character.free()

	# Every route out of a pose. A child must never be able to tap the character
	# into a posture it cannot leave.
	var routes: Array = [
		["walking away", func(c: Node) -> void: c.call("move_to_ground", 1.0, 0.0)],
		["another action", func(c: Node) -> void: c.call("play_action", "wave")],
		["stop()", func(c: Node) -> void: c.call("stop")],
		["being disabled", func(c: Node) -> void: c.call("set_disabled", true)],
		["the natural release", func(c: Node) -> void: c.call("play_action", "stand")],
	]
	for route: Array in routes:
		var character: CharacterBody3D = _make_character()
		character.call("play_action", "sit")
		_settle(character)
		(route[1] as Callable).call(character)
		if not String(character.call("get_held_action")).is_empty():
			failures.append("%s should release a held pose, but the character is still holding '%s'"
					% [String(route[0]), String(character.call("get_held_action"))])
		character.free()
	return failures


## The safety property behind the whole design: a posture is a RESTING state, so
## the character keeps accepting instructions while in it. If sitting made the
## character permanently busy, a mission that waits for `is_busy()` to clear
## would hang and the child would be stuck looking at a room that ignores taps.
func _test_a_hold_never_makes_the_character_unavailable():
	var failures: Array = []
	var character: CharacterBody3D = _make_character()
	character.call("play_action", "sleep")
	_settle(character)

	if bool(character.call("is_busy")):
		failures.append("a sleeping character reports itself busy forever; nothing would ever "
				+ "be able to wake it")
	if String(character.call("get_state_name")) != "idle":
		failures.append("a held pose should resolve to a RESTING state, not to a sixth state; "
				+ "got '%s'" % String(character.call("get_state_name")))
	if not bool(character.call("move_to_ground", 1.0, 0.0)):
		failures.append("a held pose must not refuse the next instruction")
	character.free()

	# And no new state was invented to carry it.
	var names: Array = ["idle", "walking", "interacting", "carrying", "disabled"]
	var probe: CharacterBody3D = _make_character()
	var seen: Array = []
	probe.connect("state_changed", func(name: String) -> void: seen.append(name))
	probe.call("play_action", "sit")
	_settle(probe)
	probe.call("play_action", "stand")
	_settle(probe)
	for name: String in seen:
		if not names.has(name):
			failures.append("holding a pose invented a new state '%s'; the state set is locked "
					% name + "at five")
	probe.free()
	return failures


## Contract §3's composition: `pickUp` -> carry -> `give`, driven only by
## semantic action names. Content never calls `set_carrying()` itself.
func _test_pick_up_hold_give_composes():
	var failures: Array = []
	var character: CharacterBody3D = _make_character()

	if bool(character.call("is_carrying")):
		failures.append("the character should start empty-handed")

	character.call("play_action", "pickUp")
	_settle(character)
	if not bool(character.call("is_carrying")):
		failures.append("pickUp should leave the character carrying something")
	if String(character.call("get_state_name")) != "carrying":
		failures.append("the resting state after pickUp should be 'carrying', got '%s'"
				% String(character.call("get_state_name")))
	if not String(character.call("get_held_action")).is_empty():
		failures.append("pickUp is an event; carrying is the state it leaves behind, not a pose")

	# Carrying survives a walk, so a carry-walk clip can be chosen.
	character.call("move_to_ground", 0.6, 0.0)
	for _frame: int in range(400):
		character.call("step_movement", DT)
		if String(character.call("get_state_name")) == "carrying":
			break
	if not bool(character.call("is_carrying")):
		failures.append("walking should not make the character drop what it is holding")

	character.call("play_action", "hold")
	_settle(character)
	if not bool(character.call("is_carrying")):
		failures.append("hold should keep the hands full")
	if String(character.call("get_held_action")) != "hold":
		failures.append("hold is a posture and should persist, got '%s'"
				% String(character.call("get_held_action")))
	if String(character.call("get_state_name")) != "carrying":
		failures.append("holding something while resting is the 'carrying' state, got '%s'"
				% String(character.call("get_state_name")))

	character.call("play_action", "give")
	_settle(character)
	if bool(character.call("is_carrying")):
		failures.append("give should empty the hands")
	if String(character.call("get_state_name")) != "idle":
		failures.append("after giving, the resting state should be 'idle', got '%s'"
				% String(character.call("get_state_name")))
	if not String(character.call("get_held_action")).is_empty():
		failures.append("give should release the hold pose as well as the object")

	# An action with no opinion on carrying must not put the teddy down.
	character.call("play_action", "pickUp")
	_settle(character)
	character.call("play_action", "wave")
	_settle(character)
	if not bool(character.call("is_carrying")):
		failures.append("waving put down whatever was being carried; only pickUp/hold/give "
				+ "should have an opinion on the hands")

	character.free()
	return failures


## An authored clip times its own action, so lengthening the `drink` animation
## later lengthens the drink -- with no content change and no magic number in a
## mission. A posture is NOT timed by its clip: its clip loops for as long as the
## pose lasts, so using its length would make sitting down take one loop.
func _test_clip_length_times_the_action():
	var failures: Array = []
	var player: AnimationPlayer = _player_with(["drink", "sit"], 2.5)
	var driver: RefCounted = AnimationDriver.create(player)

	if not is_equal_approx(float(driver.call("get_action_duration", "drink")), 2.5):
		failures.append("an authored one-shot should time itself from its clip, got %.2f"
				% float(driver.call("get_action_duration", "drink")))
	if float(driver.call("get_action_duration", "sit")) > 0.0:
		failures.append("a looping posture clip must not time the action; sitting down would "
				+ "take a whole loop of the sitting pose")
	if float(driver.call("get_action_duration", "brushTeeth")) > 0.0:
		failures.append("an unauthored action has no clip and so no length of its own")

	# And the character actually uses it: a 2.5 s drink outlasts the 1.8 s default.
	var character: CharacterBody3D = _make_character()
	character.call("set_action_driver", driver)
	character.call("play_action", "drink")
	var frames: int = 0
	for _frame: int in range(900):
		character.call("step_movement", DT)
		frames += 1
		if String(character.call("get_state_name")) != "interacting":
			break
	var seconds: float = frames * DT
	if seconds < 2.4 or seconds > 2.7:
		failures.append("the drink should have lasted its clip's 2.5 s, lasted %.2f s" % seconds)

	# An explicit override still wins over both.
	character.call("play_action", "drink", 0.5)
	frames = 0
	for _frame: int in range(900):
		character.call("step_movement", DT)
		frames += 1
		if String(character.call("get_state_name")) != "interacting":
			break
	if frames * DT > 0.7:
		failures.append("an explicit duration should override the clip length, took %.2f s"
				% (frames * DT))

	character.free()
	player.free()
	return failures


## Required behaviour 7, at the character level: an interaction requested while
## walking takes over cleanly and reports no arrival.
func _test_action_interrupts_a_walk():
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

func _player_with(clip_names: Array, length: float = 0.5) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for clip_name: String in clip_names:
		var animation := Animation.new()
		animation.length = length
		library.add_animation(clip_name, animation)
	player.add_animation_library("", library)
	return player


func _make_character() -> CharacterBody3D:
	var character: CharacterBody3D = LittleBuddyCharacter.new()
	character.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	character.call("set_navigation_provider", NavigationProvider.new())
	return character


## Runs until the current action is over and the character is at rest again.
func _settle(character: Node) -> void:
	var resting: Array = ["idle", "carrying"]
	for _frame: int in range(900):
		character.call("step_movement", DT)
		if resting.has(String(character.call("get_state_name"))):
			return
