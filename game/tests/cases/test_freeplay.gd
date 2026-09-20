extends RefCounted

## Free Play: the house with no objective.
##
## Before this existed, "Free Play" meant four walkable rooms, no HUD, no prompt
## and nothing that answered a touch. The four things asserted here are the ones
## that turn that into something a four-year-old can actually do:
##
##   1. **Every object says a word.** Not most of them -- every single semantic
##      target the world reports, doors included. One silent prop is a child
##      tapping and learning that tapping does nothing.
##   2. **The word is spoken AND shown.** The player cannot read, so the voice is
##      the content and the card is the reinforcement; neither alone is enough.
##   3. **Thai is a long press, and only a long press** (ART_BIBLE section 9). A
##      translation permanently on screen means the child stops reaching for the
##      English.
##   4. **A fresh profile opens the whole house.** `unlockedRooms: []` is what a
##      brand new save carries, and reading it as "nothing is unlocked" would
##      shut a child out of their own home on their first Free Play.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract section 8).

const Words := preload("res://scripts/gameplay/house_freeplay_words.gd")
const DirectorScript := preload("res://scripts/gameplay/house_freeplay_director.gd")
const HouseHudScript := preload("res://scripts/gameplay/house_hud.gd")
const ActionDriverScript := preload("res://scripts/character/character_action_driver.gd")
const MainScript := preload("res://scenes/main/main.gd")

const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"
const VOCABULARY_PATH: String = "res://content/vocabulary/vocabulary.json"

## `main.gd::ProgressionMode`. The same ordinals `baby_room.gd` and
## `house_world.gd` use, deliberately.
const MODE_STORY: int = 0
const MODE_FREE_PLAY: int = 1


class FakeTts extends RefCounted:
	var lines: Array = []

	func speak(text: String, _interrupt: bool = true) -> void:
		lines.append(text)


class FakeSave extends RefCounted:
	var settings: Dictionary = {}
	var stars: int = 7

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		if settings.has(key):
			return settings[key]
		return default_value

	func get_stars() -> int:
		return stars


func test_name() -> String:
	return "freeplay"


func run():
	var failures: Array = []
	failures.append_array(_test_every_object_in_the_house_teaches_a_word())
	failures.append_array(_test_the_words_agree_with_the_taught_vocabulary())
	failures.append_array(_test_every_reaction_is_a_real_action())
	failures.append_array(_test_tapping_an_object_is_never_silent())
	failures.append_array(_test_thai_is_a_long_press_only())
	failures.append_array(_test_arriving_is_play())
	failures.append_array(_test_free_play_has_no_objective())
	failures.append_array(_test_a_fresh_profile_opens_the_whole_house())
	failures.append_array(_test_a_quiet_child_is_shown_a_hand())
	return failures


## -- The words -----------------------------------------------------------------

## Against the REAL world, not against the table's own keys: a prop added to
## `house_layout.gd` with no word here would otherwise be a silent tap that no
## test could see.
func _test_every_object_in_the_house_teaches_a_word():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]

	var ids: Array = world.call("get_semantic_target_ids")
	if ids.size() < 12:
		failures.append("the house reports only %d activity targets; this case is nearly "
				% ids.size() + "vacuous")

	for semantic_id: Variant in ids:
		var word: String = Words.word_for(semantic_id)
		if word.strip_edges().is_empty():
			failures.append(
				"'%s' has no English word, so tapping it in Free Play says nothing. Free Play "
				% String(semantic_id)
				+ "has no objective -- the WORD is the content -- and a silent prop teaches a "
				+ "child that touching the screen does nothing."
			)

	# Both halves of an address resolve, because the character echoes back
	# whichever id the target reported.
	if Words.word_for("bedroom.bed") != Words.word_for("bed"):
		failures.append("a semantic id and its local half give different words")
	# And an id this house does not have is empty rather than a crash or a guess.
	if not Words.word_for("attic.telescope").is_empty():
		failures.append("an unknown target invented a word for itself")
	if not Words.word_for("").is_empty():
		failures.append("an empty id produced a word")

	_release(world)
	return failures


## Where a Free Play word also exists as taught vocabulary, the two must be the
## same word -- or a child is taught "toy box" in the story and something else in
## Free Play. The table is deliberately not part of `content/**` (it is a
## property of the house, and Free Play must work with no content loaded), so
## this is what stops the duplication drifting.
func _test_the_words_agree_with_the_taught_vocabulary():
	var failures: Array = []
	if not ResourceLoader.exists(VOCABULARY_PATH):
		return ["%s is missing" % VOCABULARY_PATH]
	var file: FileAccess = FileAccess.open(VOCABULARY_PATH, FileAccess.READ)
	if file == null:
		return ["could not read %s" % VOCABULARY_PATH]
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return ["%s is not a JSON object" % VOCABULARY_PATH]

	var by_id: Dictionary = {}
	for entry: Variant in (parsed as Dictionary).get("words", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		by_id[String((entry as Dictionary).get("wordId", ""))] = entry

	var checked: int = 0
	for local_id: Variant in Words.SHARED_WITH_VOCABULARY.keys():
		var word_id: String = String(Words.SHARED_WITH_VOCABULARY[local_id])
		if not by_id.has(word_id):
			failures.append("house_freeplay_words claims to share '%s' with the vocabulary "
					% word_id + "set, which has no such word")
			continue
		checked += 1
		var taught: Dictionary = by_id[word_id]
		var expected_word: String = String(taught.get("word", ""))
		var expected_thai: String = String(taught.get("thai", ""))
		# Rooms are addressed through their doors, everything else by its id.
		var probe: String = String(local_id)
		if Words.ROOM_THAI.has(probe):
			probe = "bedroom.doorTo%s%s" % [probe.substr(0, 1).to_upper(), probe.substr(1)]
		if Words.word_for(probe) != expected_word:
			failures.append("Free Play says '%s' for %s; the vocabulary set teaches '%s'"
					% [Words.word_for(probe), probe, expected_word])
		if Words.thai_for(probe) != expected_thai:
			failures.append("Free Play's Thai hint for %s is '%s'; the vocabulary set has '%s'"
					% [probe, Words.thai_for(probe), expected_thai])

	if checked < 5:
		failures.append("only %d shared words were checked; this case has stopped guarding "
				% checked + "the overlap")
	return failures


## Every reaction must be one of the contract's sixteen semantic actions.
## `dress` and `play` read perfectly well in a table and do nothing at all in the
## character -- that is the exact bug this catches.
func _test_every_reaction_is_a_real_action():
	var failures: Array = []
	var known: Array = ActionDriverScript.KNOWN_ACTIONS
	for local_id: Variant in Words.ACTIONS.keys():
		var action: String = String(Words.ACTIONS[local_id])
		if action.is_empty() and Words.HANDLED_BY_ACTS.has(String(local_id)):
			# A real act (the doors swing, the fridge opens, she sits) rather
			# than a pantomime; `test_freeplay_acts.gd` proves it decides one.
			continue
		if action in ["pickUp", "hold"]:
			failures.append("'%s' reacts with '%s', which fills her hands in the movement machine "
					% [String(local_id), action] + "and left her 'carrying' nothing for the rest of the session")
		if not known.has(action):
			failures.append(
				"'%s' reacts with '%s', which is not one of the contract's semantic actions "
				% [String(local_id), action]
				+ "(%s). The character would simply stand there." % str(known)
			)
	if Words.ACTIONS.size() < Words.WORDS.size():
		failures.append("%d of the %d house objects have no reaction at all; touching them "
				% [Words.WORDS.size() - Words.ACTIONS.size(), Words.WORDS.size()]
				+ "would say a word and then nothing would happen")
	# A door must NOT act: the room is about to change under it.
	if not Words.action_for("bedroom.doorToBathroom").is_empty():
		failures.append("a door plays an action; it would land in the room the child just left")
	return failures


## -- The loop ------------------------------------------------------------------

func _test_tapping_an_object_is_never_silent():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]

	var tts: FakeTts = FakeTts.new()
	var director: Node = _make_director(world, tts, FakeSave.new())
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	director.call("start")
	var hud: Control = director.call("get_hud")

	var spoken: Array = []
	director.connect("word_spoken", func(id: String, word: String) -> void: spoken.append([id, word]))

	tts.lines.clear()
	if not bool(director.call("say_word", "bedroom.bed")):
		failures.append("tapping the bed produced nothing at all")

	if not tts.lines.has("bed"):
		failures.append(
			"tapping the bed did not SAY 'bed' (the voice heard %s). In Free Play the spoken "
			% str(tts.lines)
			+ "word is the entire lesson -- the player cannot read the card."
		)
	if String(hud.call("get_word_text")) != "bed":
		failures.append("tapping the bed did not show the word; the voice alone gives a child "
				+ "nothing to point at")
	if spoken.size() != 1:
		failures.append("word_spoken fired %d times for one tap" % spoken.size())

	# A door teaches the room it leads to, which is a word a child needs and
	# already meets in the story.
	tts.lines.clear()
	director.call("say_word", "bedroom.doorToBathroom")
	if not tts.lines.has("bathroom"):
		failures.append("tapping a door said %s, expected the room it leads to" % str(tts.lines))

	# An id this house does not have is quietly ignored, never a crash and never
	# a made-up word.
	if bool(director.call("say_word", "attic.telescope")):
		failures.append("an unknown target was given a word")

	_release(world)
	return failures


func _test_thai_is_a_long_press_only():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]

	var save: FakeSave = FakeSave.new()
	var director: Node = _make_director(world, FakeTts.new(), save)
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	director.call("start")
	var hud: Control = director.call("get_hud")

	director.call("say_word", "kitchen.fridge")
	if not String(hud.call("get_word_thai_text")).is_empty():
		failures.append(
			"a plain tap showed the Thai hint. ART_BIBLE section 9 makes it a long press for a "
			+ "reason: a translation permanently on screen means the child stops reaching for "
			+ "the English word."
		)

	if not bool(director.call("reveal_thai_hint", "kitchen.fridge")):
		failures.append("a long press revealed no Thai hint")
	if String(hud.call("get_word_text")) != "fridge":
		failures.append("a long press lost the English word")
	if String(hud.call("get_word_thai_text")) != Words.thai_for("kitchen.fridge"):
		failures.append("a long press showed '%s', expected '%s'"
				% [String(hud.call("get_word_thai_text")), Words.thai_for("kitchen.fridge")])

	# The parent switch still wins.
	save.settings["thaiHints"] = false
	director.call("reveal_thai_hint", "kitchen.fridge")
	if not String(hud.call("get_word_thai_text")).is_empty():
		failures.append("the Thai hint ignores the thaiHints setting a parent turned off")

	_release(world)
	return failures


## Arriving is where a tap becomes play: Little Buddy uses the thing, and says
## something warm about it.
func _test_arriving_is_play():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]
	var character: Node = world.call("get_character")

	var tts: FakeTts = FakeTts.new()
	var director: Node = _make_director(world, tts, FakeSave.new())
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	director.call("start")

	tts.lines.clear()
	character.emit_signal("interaction_ready", "bedroom.bed")

	if int(director.call("get_arrival_count")) != 1:
		failures.append("arriving at the bed was not noticed at all")
	if String(character.call("get_held_action")) != "sleep" \
			and not bool(character.call("is_busy")):
		failures.append(
			"Little Buddy walked to the bed and did nothing. Free Play has no objective, so "
			+ "the reaction IS the reward; a character who arrives and stands there makes the "
			+ "whole loop feel broken."
		)
	if tts.lines.is_empty():
		failures.append("arriving said nothing")

	# A door arrival must not act or react -- the room is about to change.
	var before: Array = tts.lines.duplicate()
	character.emit_signal("interaction_ready", "bedroom.doorToKitchen")
	if tts.lines != before:
		failures.append("arriving at a door spoke a reaction into the room the child is leaving")
	# Little Days V1 is free (owner decision, 2026-09-20): every door, the
	# bathroom's included, is simply a door on a free-starter profile. Nothing a
	# child reaches says "ask a grown-up".
	if not bool(director.call("is_room_open", "bathroom")):
		failures.append("the bathroom is closed on the free starter; V1 opens every room")
	world.call("place_in_room", "bedroom", "")
	before = tts.lines.duplicate()
	character.emit_signal("interaction_ready", "bedroom.doorToBathroom")
	if tts.lines != before:
		failures.append("arriving at the bathroom door spoke into the room the child is leaving (got %s)" % str(tts.lines))
	if String(world.call("get_current_room_id")) != "bathroom":
		failures.append("the bathroom door did not open (the child is in %s)" % world.call("get_current_room_id"))

	_release(world)
	return failures


## -- No objective --------------------------------------------------------------

func _test_free_play_has_no_objective():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]

	world.call("set_progression_mode", MODE_FREE_PLAY)
	world.call("begin_session")

	var director: Node = world.call("get_free_play_director")
	if director == null:
		failures.append("Free Play built no loop at all; the house would come up with no HUD "
				+ "and nothing that reacts to a touch, which is what it used to do")
		_release(world)
		return failures
	if not bool(director.call("is_running")):
		failures.append("the Free Play loop was built but never started")
	if world.call("get_level_director") != null:
		failures.append(
			"Free Play built a level director. Free Play has no objective BY DEFINITION "
			+ "(SLICE_CONTRACT section 5); an authored level here would hand a child a "
			+ "'sandbox' with a task list."
		)

	var hud: Control = director.call("get_hud")
	if hud == null:
		failures.append("Free Play has no HUD")
		_release(world)
		return failures
	if not bool(hud.call("is_free_play_mode")):
		failures.append("the HUD is not in Free Play mode")
	if int(hud.call("get_total")) != 0:
		failures.append("Free Play shows %d progress dots; there is nothing to be part-way "
				% int(hud.call("get_total")) + "through")
	if bool(hud.call("is_skip_visible")):
		failures.append("Free Play shows a Next button; there is nothing to skip")
	if bool(hud.call("is_speak_visible")):
		failures.append("Free Play shows a Speak button; there is no question to answer")
	if bool(world.call("is_status_visible")):
		failures.append("Free Play keeps the world status line as well as the word card; that "
				+ "is two pieces of text for a child who can read neither")

	# Idempotent, and a second call does not build a second HUD.
	if world.call("ensure_free_play_director") != director:
		failures.append("ensure_free_play_director() built a second loop")

	_release(world)
	return failures


## -- Unlocked rooms ------------------------------------------------------------

## Through the REAL hand-off `main.gd` performs, because that is where the empty
## list actually arrives from a fresh profile.
func _test_a_fresh_profile_opens_the_whole_house():
	var failures: Array = []
	if not ResourceLoader.exists(HOUSE_SCENE):
		return ["%s is missing" % HOUSE_SCENE]

	var world: Node = MainScript.build_scene(HOUSE_SCENE, MODE_FREE_PLAY, [], null)
	if world == null:
		return ["main.gd could not build the house for Free Play"]
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(world)
	world.call("build_world")

	if not bool(world.call("is_free_play")):
		failures.append("main.gd did not put the house into Free Play")

	var every_room: Array = world.call("get_room_ids")
	var open: Array = world.call("get_unlocked_room_ids")
	if open != every_room:
		failures.append(
			"a fresh profile (`unlockedRooms: []`) opened %s of %s. An empty unlock list means "
			% [str(open), str(every_room)]
			+ "EVERY room -- reading it as 'nothing is unlocked' locks a child out of their "
			+ "own house on their very first Free Play, with nothing on screen to tap."
		)
	for room_id: Variant in every_room:
		if not bool(world.call("is_room_unlocked", String(room_id))):
			failures.append("'%s' is shut on a fresh profile" % String(room_id))

	_release(world)
	return failures


## -- The idle nudge ------------------------------------------------------------

## A child who has stopped touching the screen gets a picture, not a sentence and
## never a timer.
func _test_a_quiet_child_is_shown_a_hand():
	var failures: Array = []
	var world: Node = _build_house()
	if world == null:
		return ["could not build the house"]

	var director: Node = _make_director(world, FakeTts.new(), FakeSave.new())
	if director == null:
		_release(world)
		return ["the house built no Free Play director"]
	director.call("start")

	var nudged: Array = []
	director.connect("hint_shown", func(id: String) -> void: nudged.append(id))

	for _tick: int in range(200):
		director.call("step", 0.1)

	if nudged.is_empty():
		failures.append(
			"a child who touched nothing for twenty seconds was never shown what to do. Free "
			+ "Play has no objective and no prompt, so the pointing hand is the only "
			+ "affordance there is."
		)
	else:
		for id: Variant in nudged:
			if String(id).contains("doorTo"):
				failures.append("the idle hand points at a door (%s); following it would move "
						% String(id) + "the child to a room they did not choose")
			if not Words.has_word(id):
				failures.append("the idle hand points at '%s', which says nothing" % String(id))

	# Touching anything at all takes the hand away immediately.
	director.call("_on_target_tapped", "bedroom.bed")
	var hint: Control = director.call("get_hint")
	if hint != null and hint.visible:
		failures.append("the pointing hand stayed on screen after the child touched something")

	_release(world)
	return failures


## -- Helpers -------------------------------------------------------------------

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


func _make_director(world, tts, save):
	var director: Node = world.call("ensure_free_play_director")
	if director == null:
		return null
	director.call("set_tts", tts)
	director.call("set_save_service", save)
	return director


func _release(world) -> void:
	if world == null:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and world.get_parent() == tree.root:
		tree.root.remove_child(world)
	world.free()
