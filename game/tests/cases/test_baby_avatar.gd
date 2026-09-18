extends RefCounted

## The Little Buddy (baby) avatar wrapper: what it is allowed to claim.
##
## `scripts/characters/little_buddy/baby_little_buddy.gd` wraps three
## generator-produced (Meshy) baby exports that are **64x to 159x over the art
## bible's triangle budget and have no rig at all**. Most of what matters about
## them was judged by rendering them and looking (`docs/shots/baby_*.png`); this
## file pins the parts that are checkable, and the parts with the most obvious
## failure modes.
##
## Six things are guarded, in descending order of how much damage they would do:
##
##   1. **The gate on the flag.** `ENABLED` may only be `true` while **every**
##      pose in the build is inside the §10 budget AND can actually animate.
##      `BabyView3D` stays the Chapter 2 baby until validation passes, and a
##      promise like that cannot be kept by a comment. Flipping the flag with
##      today's assets turns this red -- with or without the assets present.
##   2. **Nothing fakes animation.** The tempting move on an unrigged mesh is a
##      procedural bob-and-sway presented as an idle. `can_play_action()` must
##      report `false` for every action in the vocabulary, and the wrapper's
##      source must contain no tween, no per-frame hook and no hand-built
##      `AnimationPlayer`. A fake idle makes an unusable asset look usable, and
##      every decision taken afterwards is taken against a capability the project
##      does not have.
##   3. **No caller can hang.** `play_action()` is a no-op, but a *completing*
##      one: `action_started` and `action_finished` both fire.
##   4. **One character size across three poses.** This is the specific trap in
##      this asset set: Meshy normalised all three files to the same 1.903-unit
##      bounding box, so scaling each pose to the same rendered height would
##      leave a sitting baby that dwarfs the standing one. Asserted two ways --
##      `characterHeight` must agree across poses, and the poses' *rendered*
##      heights must NOT.
##   5. **The pose API and the Chapter 2 adapter.** Selection actually selects,
##      exactly one pose is ever visible, the load is lazy, and the five view
##      states are read out of `BabyView3D` itself so the adapter cannot drift
##      away from the vocabulary it adapts.
##   6. **The wrapper is a wrapper.** No Meshy filename exists anywhere in the
##      project outside it.
##
## ## What this file deliberately does NOT assert
##
## **Which way the characters face, and what the sleeping pose is.** The wrapper
## turns the models 180 degrees so yaw 0 faces -Z, and reclines the `sleeping`
## export onto its back because it is a supine figure that Meshy authored
## upright. Both were established by rendering and looking; the bounding boxes
## offer no fact to assert against, and `MODEL_YAW_DEG == 180.0` would only check
## that a constant equals itself. `ART_UPGRADE_REPORT.md` records a smile that
## shipped as a frown through three render passes -- the answer to that class of
## bug is to look, not to write a tautology.

const Baby := preload("res://scripts/characters/little_buddy/baby_little_buddy.gd")
const BabyView := preload("res://scripts/baby/baby_view_3d.gd")
const ActionDriver := preload("res://scripts/character/character_action_driver.gd")

const WRAPPER_SOURCE: String = "res://scripts/characters/little_buddy/baby_little_buddy.gd"
const WRAPPER_SCENE: String = "res://scenes/characters/little_buddy/BabyLittleBuddy.tscn"
const BABY_ROOM_SCENE: String = "res://scenes/baby_room/baby_room.tscn"
const BABY_VIEW_SOURCE: String = "res://scripts/baby/baby_view_3d.gd"

## Metres. Tight, because these are derived from a measured AABB rather than
## eyeballed, so anything looser would not catch a normalisation that stopped
## working.
const TOLERANCE_M: float = 0.002

## Directories scanned for a leaked Meshy filename. Everything the game is made
## of; the wrapper itself is excluded by path, not by being outside the scan.
const SCANNED_DIRS: Array[String] = ["res://scripts", "res://scenes", "res://tests"]

## Everything that would let an unrigged mesh pretend to move. `Tween` and
## `create_tween` are the obvious route; a per-frame hook is the other; building
## an `AnimationPlayer` or an `Animation` by hand is how `baby_view_3d.gd`
## legitimately animates a PROCEDURAL character, and is exactly what must not
## happen to a generated one that has no rig.
const FAKE_ANIMATION_TOKENS: Array[String] = [
	"create_tween", "Tween", "AnimationPlayer.new(", "Animation.new(",
	"func _process(", "func _physics_process(",
]

## False when the raw exports are not in this checkout (they are gitignored).
var _model_present: bool = true


func test_name() -> String:
	return "baby_avatar"


func run():
	var failures: Array = []
	if not ResourceLoader.exists(WRAPPER_SCENE):
		return ["%s is missing; the wrapper is the addressable unit and nothing else in this "
				% WRAPPER_SCENE + "case can run without it"]

	# One instance for the whole case. Instantiating a 400,000-triangle scene per
	# helper is minutes of test time for no extra coverage.
	var baby: Node3D = _baby()

	failures.append_array(_test_the_assets_are_here_at_all(baby))

	# These read the source, the scenes and the pure mapping tables, so they hold
	# with or without the raw exports in the checkout -- and they are the ones
	# that protect the project.
	failures.append_array(_test_the_flag_is_gated_on_validation(baby))
	failures.append_array(_test_it_refuses_to_fake_animation(baby))
	failures.append_array(_test_an_action_always_completes(baby))
	failures.append_array(_test_the_pose_vocabulary(baby))
	failures.append_array(_test_the_view_state_adapter(baby))
	failures.append_array(_test_no_meshy_filename_leaks())
	failures.append_array(_test_baby_view_3d_is_still_the_chapter_2_baby())

	# These measure the meshes themselves. With the exports gitignored, a fresh
	# clone has nothing to measure; running them anyway is the vacuous pass this
	# case was written to avoid.
	if _model_present:
		failures.append_array(_test_pose_selection_shows_one_pose(baby))
		failures.append_array(_test_the_load_is_lazy())
		failures.append_array(_test_one_character_size_across_poses(baby))
		failures.append_array(_test_normalisation(baby))
		failures.append_array(_test_material_policy(baby))
		failures.append_array(_test_the_glb_hierarchy_is_sealed(baby))

	baby.free()
	return failures


## -- Anti-vacuity -----------------------------------------------------------------

## Everything below the line measures the real assets. If they are not in the
## build, none of those measurements mean anything.
##
## But "absent" has two very different causes, and conflating them is what would
## make this case useless:
##
##   * **Deliberately absent.** The raw Meshy exports are gitignored -- ~42 MB of
##     generator output for these three alone, plus extracted textures, against a
##     33 MB repo with no git-lfs, for assets that cannot ship without retopology
##     and cannot animate at all. A fresh clone legitimately has no model, and
##     going red there would mean the suite is red for everyone who clones.
##   * **Missing in error.** The wrapper scene is gone, or a path drifted. That is
##     a real failure and still reads as one (handled in `run()`).
##
## When the models are absent we assert the ONE thing that still matters and is
## still checkable: **you cannot have the avatar switched on for models that are
## not in the build.** That is not a vacuous pass -- it is the gate, and mutating
## `ENABLED` to `true` fails here with or without the assets present.
func _test_the_assets_are_here_at_all(baby):
	var failures: Array = []
	if bool(baby.call("is_model_available")):
		_model_present = true
		return failures

	_model_present = false
	if Baby.ENABLED:
		failures.append(
			"the baby avatar is ENABLED while none of its pose models is in this build. It "
			+ "would load nothing and show nothing. The gate must hold whether or not the raw "
			+ "assets are in the checkout."
		)
	return failures


## -- 1. The gate on the flag --------------------------------------------------------

func _test_the_flag_is_gated_on_validation(baby):
	var failures: Array = []
	var reasons: Array = baby.call("validation_failures")
	var passes: bool = bool(baby.call("passes_validation"))

	if Baby.ENABLED and not passes:
		failures.append(
			("BabyLittleBuddy.ENABLED is true but the assets do not pass validation:\n"
			+ "             - %s\n         BabyView3D stays the shipping Chapter 2 baby until "
			+ "validation passes. Fix the assets (retopologise, bake a 512-square atlas, rig "
			+ "them to LB_Rig_v1) or put the flag back.")
			% "\n             - ".join(PackedStringArray(reasons))
		)

	# The other direction: if the assets are ever genuinely fixed, this test must
	# not be the thing standing in the way of turning them on.
	if passes and not reasons.is_empty():
		failures.append("passes_validation() and validation_failures() disagree; one of them is "
				+ "wrong and the gate cannot be trusted")

	# And the gate must be measuring something. With today's assets there are
	# twelve separate reasons; a gate that found none would mean the measurement
	# silently stopped working.
	if not passes and reasons.is_empty():
		failures.append("validation failed but named no reason; the gate is not actually "
				+ "measuring the assets")

	# The gate covers every pose, not just whichever happens to be on screen --
	# `set_pose()` can reach any of them at runtime.
	if _model_present:
		for pose_name: String in Baby.known_poses():
			if not Baby.is_pose_available(pose_name):
				continue
			var named: bool = false
			for reason: String in reasons:
				if reason.begins_with("%s:" % pose_name):
					named = true
			if not named:
				failures.append(
					("the gate named no problem with the '%s' pose, which is %d triangles. A gate "
					+ "that only measured the visible pose would be one set_pose() call away from "
					+ "being wrong.") % [pose_name, int(baby.call("describe_budget", pose_name)
						.get("triangles", 0))]
				)
	return failures


## -- 2. No faked animation ----------------------------------------------------------

func _test_it_refuses_to_fake_animation(baby):
	var failures: Array = []

	if baby.call("get_animation_player") != null:
		failures.append("the wrapper reports an AnimationPlayer. The assets have none, so either "
				+ "one was built by hand -- which would be a faked rig -- or a rigged re-export "
				+ "has landed and this case needs revisiting alongside the flag")

	for pose_name: String in Baby.known_poses():
		if not Baby.is_pose_available(pose_name):
			continue
		var clips: Array = baby.call("describe_budget", pose_name).get("animationClips", [])
		if not clips.is_empty():
			failures.append("the '%s' pose now reports clips %s; see above" % [pose_name, str(clips)])

	for action: String in ActionDriver.KNOWN_ACTIONS:
		if bool(baby.call("can_play_action", action)):
			failures.append(
				("can_play_action(\"%s\") is true on assets with no skin and no clips. This must "
				+ "answer honestly: a caller that believes an action will be shown will compose "
				+ "gameplay around a pose that never appears.") % action
			)

	if String(baby.call("get_current_action")) != "":
		failures.append("get_current_action() must be \"\" while nothing can be shown; reporting "
				+ "the requested action here would let a caller believe a pose is on screen")

	# A requested action is still remembered and reported honestly, under a name
	# that cannot be mistaken for "this is visible".
	#
	# A HELD action is used because outside the tree there is no `SceneTreeTimer`,
	# so a one-shot starts and finishes inside the `play_action()` call itself and
	# has already been cleared by the time it could be read. A posture persists.
	baby.call("play_action", "sleep")
	if String(baby.call("get_requested_action")) != "sleep":
		failures.append("get_requested_action() should name the last action asked for, found '%s'"
				% String(baby.call("get_requested_action")))
	if String(baby.call("get_current_action")) != "":
		failures.append("get_current_action() changed after a request that cannot be shown")
	if String(baby.call("get_held_action")) != "":
		failures.append("get_held_action() claims a posture on a character that cannot be posed")

	# And the `sleep` ACTION must not have quietly swapped the `sleeping` POSE in.
	# They are different things: a pose is a mesh, an action is motion this asset
	# cannot perform, and letting one stand in for the other is the same lie as a
	# bob-and-sway.
	if _model_present and String(baby.call("get_pose")) != Baby.DEFAULT_POSE:
		failures.append(
			("play_action(\"sleep\") changed the visible pose to '%s'. A pose swap is not an "
			+ "animation and must not be triggered by the action vocabulary, or a caller will "
			+ "read a mesh change as the character having acted.") % String(baby.call("get_pose"))
		)

	# The source-level half: no tween, no per-frame hook, no hand-built player.
	var code: String = _code_of(_read(WRAPPER_SOURCE))
	if code.strip_edges().length() < 500:
		failures.append("%s stripped to almost nothing; this scan would pass vacuously"
				% WRAPPER_SOURCE)
	else:
		for token: String in FAKE_ANIMATION_TOKENS:
			if code.contains(token):
				failures.append(
					("%s contains `%s` in executable code. An unrigged mesh must not be given a "
					+ "procedural bob-and-sway and presented as animated -- it makes an unusable "
					+ "asset look usable, and every decision taken afterwards is taken against a "
					+ "capability the project does not have.") % [WRAPPER_SOURCE, token]
				)
	return failures


## -- 3. A no-op that always completes -----------------------------------------------

func _test_an_action_always_completes(baby):
	var failures: Array = []

	# Outside the tree there is no SceneTree timer, so `action_finished` is
	# emitted immediately -- which is exactly the guarantee under test: the signal
	# must arrive, not merely be scheduled somewhere that never runs.
	for action: String in ActionDriver.KNOWN_ACTIONS:
		var events: Array = []
		var on_started: Callable = func(started: String) -> void: events.append("start:%s" % started)
		var on_finished: Callable = func(ended: String) -> void: events.append("finish:%s" % ended)
		baby.connect("action_started", on_started)
		baby.connect("action_finished", on_finished)

		var accepted: bool = bool(baby.call("play_action", action))
		baby.disconnect("action_started", on_started)
		baby.disconnect("action_finished", on_finished)

		if not accepted:
			failures.append("play_action(\"%s\") was refused; every action in the vocabulary must "
					% action + "be accepted so a caller's sequence still advances")
			continue
		if not events.has("start:%s" % action):
			failures.append("play_action(\"%s\") emitted no action_started" % action)
		if not events.has("finish:%s" % action):
			failures.append(
				("play_action(\"%s\") never emitted action_finished. A caller awaiting it would "
				+ "hang forever, and a child would be left looking at a screen that has stopped. "
				+ "Doing nothing is fine; not finishing is not.") % action
			)

	# An action outside the vocabulary is refused -- and then emits nothing, so a
	# caller that checked the return value is not also left waiting.
	var stray: Array = []
	var watcher: Callable = func(seen: String) -> void: stray.append(seen)
	baby.connect("action_started", watcher)
	baby.connect("action_finished", watcher)
	if bool(baby.call("play_action", "somersault")):
		failures.append("play_action() accepted an action outside KNOWN_ACTIONS; a typo in "
				+ "content should be caught, not silently absorbed")
	baby.disconnect("action_started", watcher)
	baby.disconnect("action_finished", watcher)
	if not stray.is_empty():
		failures.append("a refused action still emitted %s" % str(stray))
	return failures


## -- 4. The pose vocabulary ---------------------------------------------------------

## Pure table checks: they hold identically in a checkout with the assets and one
## without, which is why the pose API was built as data rather than as branches.
func _test_the_pose_vocabulary(baby):
	var failures: Array = []
	var poses: Array = Baby.known_poses()

	# The three poses are the product decision recorded in
	# `docs/MESHY_CHARACTER_AUDIT.md` §6. Losing one silently would remove a
	# chapter's worth of staging, so the names are pinned.
	for required: String in ["standing", "sitting", "sleeping"]:
		if not poses.has(required):
			failures.append("the '%s' pose is gone from POSES. sleeping/sitting/standing are the "
					% required + "bedtime / feeding / first-words staging for Chapter 2.")
	if poses.size() != 3:
		failures.append("POSES holds %d entries; expected exactly the three pose variants"
				% poses.size())

	# Feeding is Chapter 2's core loop, so the chapter's baby sits.
	if Baby.DEFAULT_POSE != "sitting":
		failures.append("DEFAULT_POSE is '%s'. The owner's recommendation, and the reason the "
				% Baby.DEFAULT_POSE + "sitting export exists, is that feeding is the chapter's "
				+ "core loop.")

	for pose_name: String in poses:
		var entry: Dictionary = Baby.POSES[pose_name]
		for key: String in ["path", "heightFraction", "rotationDeg"]:
			if not entry.has(key):
				failures.append("the '%s' pose has no '%s'; the wrapper cannot normalise it"
						% [pose_name, key])
		var fraction: float = float(entry.get("heightFraction", 0.0))
		if fraction <= 0.0 or fraction > 1.0:
			failures.append(
				("the '%s' pose has heightFraction %.3f. It is that pose's bounding height as a "
				+ "fraction of the character's STANDING height, so it is in (0, 1] by "
				+ "construction -- no pose is taller than the character standing up.")
				% [pose_name, fraction]
			)

	# Selection refuses nonsense and changes nothing when it does.
	var before: String = String(baby.call("get_requested_pose"))
	if bool(baby.call("set_pose", "cartwheeling")):
		failures.append("set_pose() accepted a pose outside POSES; a typo in a scene should be "
				+ "caught, not silently absorbed")
	if String(baby.call("get_requested_pose")) != before:
		failures.append("a refused set_pose() still changed the requested pose to '%s'"
				% String(baby.call("get_requested_pose")))

	# And it accepts every pose it declares, present or not.
	for pose_name: String in poses:
		if not bool(baby.call("set_pose", pose_name)):
			failures.append("set_pose(\"%s\") was refused for a pose the wrapper declares"
					% pose_name)
	baby.call("set_pose", Baby.DEFAULT_POSE)
	return failures


## -- 5. The Chapter 2 adapter -------------------------------------------------------

## The five view states are read out of `BabyView3D` itself rather than written
## here, so the adapter cannot drift away from the vocabulary it adapts: adding a
## state to the shipping baby fails this until the adapter answers to it.
func _test_the_view_state_adapter(baby):
	var failures: Array = []
	var states: Array = BabyView.STATE_NAMES.keys()
	if states.size() < 5:
		failures.append("BabyView3D declares only %d view states; this adapter test would be "
				% states.size() + "checking almost nothing")

	for state: String in states:
		var mapped: String = Baby.pose_for_view_state(state)
		if mapped.is_empty():
			failures.append(
				("the adapter has no pose for BabyView3D's '%s' state. Every state a Chapter 2 "
				+ "caller can set must land on a pose, or the baby silently stops changing.")
				% state
			)
			continue
		if not Baby.is_known_pose(mapped):
			failures.append("the '%s' state maps to '%s', which is not a pose" % [state, mapped])

		baby.call("set_view_state", state)
		if String(baby.call("get_view_state_name")) != state:
			failures.append("set_view_state(\"%s\") did not stick; get_view_state_name() says '%s'"
					% [state, String(baby.call("get_view_state_name"))])
		if String(baby.call("get_requested_pose")) != mapped:
			failures.append(
				("set_view_state(\"%s\") selected pose '%s' but the table says '%s'. The adapter "
				+ "is the single place a designer re-points a state and must actually be the "
				+ "thing consulted.")
				% [state, String(baby.call("get_requested_pose")), mapped]
			)

	# `BabyView3D` falls back to idle for a state it does not know, so a scene
	# mistake never crashes the baby. A drop-in replacement must do the same.
	baby.call("set_view_state", "furious")
	if String(baby.call("get_view_state_name")) != "idle":
		failures.append(
			("an unknown view state left get_view_state_name() at '%s'. BabyView3D falls back to "
			+ "idle -- \"unknown values fall back to idle so a scene mistake never crashes the "
			+ "baby\" -- and a replacement that crashed or froze instead would be worse than the "
			+ "thing it replaced.") % String(baby.call("get_view_state_name"))
		)

	# The fallback is "nearest AVAILABLE", which is what makes the wrapper usable
	# in a build that shipped one pose instead of three.
	for pose_name: String in Baby.known_poses():
		var resolved: String = Baby.resolve_pose(pose_name)
		if resolved.is_empty():
			if Baby.is_pose_available(pose_name):
				failures.append("resolve_pose(\"%s\") found nothing for a pose that is present"
						% pose_name)
			continue
		if not Baby.is_pose_available(resolved):
			failures.append("resolve_pose(\"%s\") returned '%s', which is not in this build"
					% [pose_name, resolved])

	baby.call("set_view_state", "idle")
	return failures


## -- 6. The wrapper is the only thing that knows the filenames ----------------------

## Derived from `POSES` rather than typed out, so this file is not itself the
## leak it is looking for, and so a re-export under new names stays covered.
func _test_no_meshy_filename_leaks():
	var failures: Array = []
	var names: Array = []
	for pose_name: String in Baby.known_poses():
		names.append(String(Baby.POSES[pose_name]["path"]).get_file())
	if names.is_empty():
		return ["baby_avatar: no pose paths to scan for; this guard would pass vacuously"]

	var scanned: int = 0
	for directory: String in SCANNED_DIRS:
		for path: String in _files_under(directory):
			if path == WRAPPER_SOURCE:
				continue
			scanned += 1
			var text: String = _read(path)
			for file_name: String in names:
				if text.contains(file_name):
					failures.append(
						("%s names the raw export `%s`. Only the wrapper may -- it is the one file "
						+ "a re-export with different names is allowed to cost.")
						% [path, file_name]
					)
	if scanned < 50:
		failures.append("the filename scan covered only %d files; it is not looking at the "
				% scanned + "project and would report clean forever")
	return failures


## -- 7. BabyView3D is not replaced --------------------------------------------------

## The standing instruction, and the easiest thing to get wrong in a hurry: this
## wrapper is an experiment. The Chapter 2 baby stays `baby_view_3d.gd`.
func _test_baby_view_3d_is_still_the_chapter_2_baby():
	var failures: Array = []
	var room: String = _read(BABY_ROOM_SCENE)
	if room.is_empty():
		return ["baby_avatar: could not read %s" % BABY_ROOM_SCENE]
	if not room.contains(BABY_VIEW_SOURCE):
		failures.append("baby_room.tscn no longer uses baby_view_3d.gd. The procedural baby is the "
				+ "Chapter 2 character and is not replaced by this experiment.")
	if not room.contains("name=\"BabyView\""):
		failures.append("the BabyView node is gone from the nursery")

	# While the flag is off, nothing in the shipping game may reference the
	# wrapper scene either -- an unreferenced experiment costs nothing, a
	# referenced one costs 42 MB of GLB in the export.
	if not Baby.ENABLED:
		for directory: String in ["res://scenes", "res://scripts"]:
			for path: String in _files_under(directory):
				if path.begins_with("res://scenes/characters/little_buddy"):
					continue
				if path.begins_with("res://scripts/characters/little_buddy"):
					continue
				if _read(path).contains(WRAPPER_SCENE):
					failures.append(
						("%s references %s while the avatar is disabled. Nothing in the shipping "
						+ "game may reach it until the flag is on.") % [path, WRAPPER_SCENE]
					)

	# Executable code only: the wrapper's doc comment legitimately cites
	# `baby_view_3d.gd` as the thing it is an alternative to, and a guard that
	# punished accurate documentation would be weakened rather than fixed.
	var wrapper: String = _code_of(_read(WRAPPER_SOURCE))
	if wrapper.contains("baby_view_3d") or wrapper.contains("BabyView3D"):
		failures.append("the wrapper references the procedural baby in executable code; the two "
				+ "presentations must not become coupled")
	return failures


## -- 8. Selection actually selects --------------------------------------------------

func _test_pose_selection_shows_one_pose(baby):
	var failures: Array = []
	for pose_name: String in Baby.known_poses():
		if not Baby.is_pose_available(pose_name):
			continue
		baby.call("set_pose", pose_name)
		var shown: String = String(baby.call("get_pose"))
		if shown != pose_name:
			failures.append(
				("set_pose(\"%s\") left '%s' on screen. Pose selection is the only visible thing "
				+ "this asset set can honestly do; if it does not work there is nothing left.")
				% [pose_name, shown]
			)
		var visible_count: int = 0
		for child: Node in baby.get_children():
			if (child as Node3D).visible:
				visible_count += 1
		if visible_count != 1:
			failures.append("%d poses are visible at once after set_pose(\"%s\"); exactly one "
					% [visible_count, pose_name] + "baby may be on screen")
	baby.call("set_pose", Baby.DEFAULT_POSE)
	return failures


## -- 9. The load is lazy ------------------------------------------------------------

## The point of three pose files is that you pay for the one you chose. A fresh
## instance is used because the shared one has been through every pose by now.
func _test_the_load_is_lazy():
	var failures: Array = []
	var fresh: Node3D = _baby()
	var loaded: Array = fresh.call("get_loaded_poses")
	if loaded.size() != 1:
		failures.append(
			("building the wrapper instantiated %d poses (%s). Selecting one pose must not pay "
			+ "for the other two: together they are 1,026,952 triangles and ~42 MB of GLB.")
			% [loaded.size(), str(loaded)]
		)
	if not loaded.is_empty() and String(loaded[0]) != String(fresh.call("get_pose")):
		failures.append("the pose that was loaded is not the pose that is shown")

	fresh.call("set_pose", "sleeping")
	if not bool(fresh.call("is_pose_loaded", "sleeping")):
		failures.append("set_pose(\"sleeping\") did not load the sleeping pose")
	if bool(fresh.call("is_pose_loaded", "standing")):
		failures.append("the standing pose was loaded without ever being asked for")
	fresh.free()
	return failures


## -- 10. One character, three poses -------------------------------------------------

## **The specific trap in this asset set.** Meshy normalised all three exports to
## the same ~1.903-unit bounding box, so a wrapper that scaled each pose to the
## same rendered height would produce a sitting baby around a quarter larger than
## the standing one -- and it would look deliberate, because every pose would be
## exactly 0.78 m tall.
##
## Both halves are asserted: the character size must agree across poses, and the
## rendered heights must NOT, because a seated baby is shorter than a standing
## one and a lying baby shorter still.
func _test_one_character_size_across_poses(baby):
	var failures: Array = []
	var heights: Dictionary = {}
	for pose_name: String in Baby.known_poses():
		if not Baby.is_pose_available(pose_name):
			continue
		var report: Dictionary = baby.call("describe_budget", pose_name)
		heights[pose_name] = report
		var character_height: float = float(report.get("characterHeight", 0.0))
		if absf(character_height - Baby.MODEL_HEIGHT_M) > TOLERANCE_M:
			failures.append(
				("the '%s' pose is scaled to a character %.4f m tall, not %.2f m. All three "
				+ "exports were normalised by Meshy to the same bounding box, so scaling each to "
				+ "the same height makes the sitting baby enormous; heightFraction is what stops "
				+ "that, and it has stopped working.")
				% [pose_name, character_height, Baby.MODEL_HEIGHT_M]
			)

	if heights.has("standing") and heights.has("sitting"):
		var standing: float = float(heights["standing"].get("placedHeight", 0.0))
		var sitting: float = float(heights["sitting"].get("placedHeight", 0.0))
		if sitting >= standing - 0.05:
			failures.append(
				("the sitting baby renders %.3f m tall against the standing baby's %.3f m. A "
				+ "seated baby is visibly shorter than a standing one; equal heights mean each "
				+ "pose was normalised to its own bounding box and the character changes size "
				+ "when it sits down.") % [sitting, standing]
			)

	# `CHARACTER_AGE_STAGES.md` §2 locks the Infant at 0.78 m and says the figure
	# is load-bearing for the nursery camera and the keep-out volume.
	if Baby.MODEL_HEIGHT_M < 0.70 or Baby.MODEL_HEIGHT_M > 0.90:
		failures.append(
			("MODEL_HEIGHT_M is %.2f m. CHARACTER_AGE_STAGES.md §2 locks the Infant at 0.78 m "
			+ "and calls it load-bearing -- the nursery camera and the keep-out volume were "
			+ "framed around it, and changing it means re-framing baby_room.tscn.")
			% Baby.MODEL_HEIGHT_M
		)
	return failures


## -- 11. Normalisation --------------------------------------------------------------

func _test_normalisation(baby):
	var failures: Array = []
	for pose_name: String in Baby.known_poses():
		if not Baby.is_pose_available(pose_name):
			continue
		var report: Dictionary = baby.call("describe_budget", pose_name)

		var resting: float = float(report.get("restingY", 999.0))
		if absf(resting) > TOLERANCE_M:
			failures.append(
				("the '%s' pose's lowest point sits at y = %.4f in the wrapper's own space, not 0. "
				+ "Art bible §6 puts the pivot at base centre for anything standing, and the whole "
				+ "house is dimensioned against floor-standing pivots -- a mid-body pivot buries "
				+ "the character to the waist in every room.") % [pose_name, resting]
			)
		for axis: Array in [["X", report.get("centreX", 9.0)], ["Z", report.get("centreZ", 9.0)]]:
			if absf(float(axis[1])) > TOLERANCE_M:
				failures.append("the '%s' pose is off-centre by %.4f m in %s; a scene that places "
						% [pose_name, float(axis[1]), axis[0]]
						+ "the wrapper at a spot expects the baby to be at that spot")

		# The scale must actually be doing work -- if a raw export were already
		# the right size the assertions above would pass without normalisation.
		var raw: float = float(report.get("rawHeight", 0.0))
		if absf(raw - Baby.MODEL_HEIGHT_M) <= 0.05:
			failures.append("the raw '%s' export is already %.2f m, so the scale assertions "
					% [pose_name, raw] + "cannot distinguish a working normalisation from none")
	return failures


## -- 12. The §7 material decision, applied and asserted -----------------------------

## The wrapper fixes three §7 violations on a duplicate of each imported
## material. Both halves are checked: that the source really does violate them
## (or the fix is being tested against nothing), and that the rendered material
## does not.
func _test_material_policy(baby):
	var failures: Array = []
	for pose_name: String in Baby.known_poses():
		if not Baby.is_pose_available(pose_name):
			continue
		var report: Dictionary = baby.call("describe_budget", pose_name)

		var source_is_broken: bool = (
			float(report.get("metallic", 0.0)) > 0.0
			or bool(report.get("hasNormalMap", false))
			or bool(report.get("doubleSided", false))
		)
		if not source_is_broken:
			failures.append("the imported '%s' material no longer violates §7 at all, so the fix "
					% pose_name + "is being asserted against nothing. If the asset was re-exported "
					+ "clean, simplify the wrapper rather than leaving a fix that protects nothing.")

		if float(report.get("appliedMetallic", 1.0)) != 0.0:
			failures.append(
				("the rendered '%s' material has metallic = %.2f. Art bible §7 is absolute -- 0.0 "
				+ "everywhere -- and this is not a style call: a fully metallic surface has no "
				+ "diffuse response, so under one directional light the baby renders as a dark "
				+ "oily silhouette.") % [pose_name, float(report.get("appliedMetallic", 1.0))]
			)
		if bool(report.get("appliedNormalMap", true)):
			failures.append("the rendered '%s' material still has a normal map; §7 bans them, and "
					% pose_name + "it costs a whole 2048-square texture on a flat-albedo pastel "
					+ "character")
		if bool(report.get("appliedDoubleSided", true)):
			failures.append("the rendered '%s' material is still double-sided; that doubles "
					% pose_name + "overdraw on a quarter-million-triangle mesh for no gain, and "
					+ "overdraw is what actually costs on a tile-based mobile GPU")
		var roughness: float = float(report.get("appliedRoughness", 0.0))
		if roughness < 0.85 or roughness > 1.0:
			failures.append("the '%s' pose's roughness %.2f is outside §7's 0.85-1.0 band; nothing "
					% [pose_name, roughness] + "in this game is shiny")
		if int(report.get("appliedTextures", 9)) != 1:
			failures.append("%d textures are bound on the rendered '%s' material; §7 allows one "
					% [int(report.get("appliedTextures", 9)), pose_name]
					+ "atlas, and dropping the normal and metallic/roughness maps should leave "
					+ "only albedo")
	return failures


## -- 13. The wrapper is a wrapper ---------------------------------------------------

## The whole point of the file is that a re-export with different node names
## changes one file. That only holds while the raw hierarchy is sealed behind the
## wrapper's own nodes.
func _test_the_glb_hierarchy_is_sealed(baby):
	var failures: Array = []
	for child: Node in baby.get_children():
		var name: String = String(child.name)
		if not name.begins_with(Baby.POSE_NODE_PREFIX):
			failures.append(
				("the wrapper has a direct child named '%s'. Every child must be a `%s<pose>` "
				+ "holder so the GLBs' own node names exist nowhere but inside the wrapper.")
				% [name, Baby.POSE_NODE_PREFIX]
			)
			continue
		if not Baby.is_known_pose(name.trim_prefix(Baby.POSE_NODE_PREFIX)):
			failures.append("the wrapper has a pose holder '%s' for a pose it does not declare"
					% name)
	return failures


## -- Helpers -------------------------------------------------------------------------

func _baby():
	var node := Node3D.new()
	node.set_script(Baby)
	node.call("build")
	return node


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## Every `.gd` and `.tscn` under `directory`, recursively.
func _files_under(directory: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var path: String = directory.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_files_under(path))
		elif entry.ends_with(".gd") or entry.ends_with(".tscn"):
			found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## Executable code only: comments stripped and string bodies blanked, so this
## file's own doc comment describing a banned token does not trip the scan.
## Same technique, and the same reasoning, as `test_architecture_guard.gd`.
static func _code_of(text: String) -> String:
	var code: String = ""
	for raw_line: String in text.split("\n"):
		var out: String = ""
		var quote: String = ""
		var index: int = 0
		while index < raw_line.length():
			var character: String = raw_line[index]
			if quote.is_empty():
				if character == "#":
					break
				if character == "\"" or character == "'":
					quote = character
				else:
					out += character
			else:
				if character == "\\":
					index += 1
				elif character == quote:
					quote = ""
			index += 1
		code += out + "\n"
	return code
