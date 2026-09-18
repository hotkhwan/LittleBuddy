extends RefCounted

## The Big Buddy avatar wrapper: what it is allowed to claim, and what it is not.
##
## `scripts/characters/buddy/pink_girl_buddy.gd` wraps a generator-produced adult
## character that is **155x over the art bible's triangle budget and has no rig
## at all**. Most of what matters about it was judged by rendering it and looking
## (`docs/shots/buddy_*.png`); this file pins the part that is checkable, and the
## part that has the most obvious failure mode.
##
## Four things are guarded, in descending order of how much damage they would do:
##
##   1. **The gate on the flag.** `ENABLED` may only be `true` while the asset is
##      inside the §10 budget AND can actually animate. Requirement 6 of the
##      owner's request -- "keep the current placeholder Buddy as fallback until
##      validation passes" -- is a promise that cannot be kept by a comment, so
##      it is kept here. Flipping the flag with today's asset turns this red.
##   2. **Nothing fakes animation.** The tempting move on an unrigged mesh is a
##      procedural bob-and-sway presented as an idle. `can_play_action()` must
##      report `false` for every action in the vocabulary, and the wrapper's
##      source must contain no tween, no per-frame hook and no hand-built
##      `AnimationPlayer`. A fake idle would make an unusable asset look usable,
##      and every decision after that would be taken against a capability the
##      project does not have.
##   3. **No caller can hang.** `play_action()` is a no-op, but it is a
##      *completing* no-op: `action_started` and `action_finished` both fire.
##   4. **The normalisation.** Feet at the origin, 1.65 m tall, and the raw GLB
##      hierarchy sealed behind one wrapper node.
##
## ## What this file deliberately does NOT assert
##
## **Which way the character faces.** The wrapper turns the model 180 degrees so
## that yaw 0 faces -Z like every other character here, and that was established
## by rendering it and looking at the face -- the model's bounding box is very
## nearly symmetric, so there is no geometric fact to assert against, and a test
## that checked `MODEL_YAW_DEG == 180.0` would only be checking that a constant
## equals itself. `ART_UPGRADE_REPORT.md` records a smile that shipped as a frown
## through three render passes; the answer to that class of bug is to look, not
## to write a tautology.

const Buddy := preload("res://scripts/characters/buddy/pink_girl_buddy.gd")
const ActionDriver := preload("res://scripts/character/character_action_driver.gd")
const Main := preload("res://scenes/main/main.gd")

const WRAPPER_SOURCE: String = "res://scripts/characters/buddy/pink_girl_buddy.gd"
const WRAPPER_SCENE: String = "res://scenes/characters/buddy/PinkGirlBuddy.tscn"
const MAIN_SOURCE: String = "res://scenes/main/main.gd"
const MAIN_SCENE: String = "res://scenes/main/main.tscn"

## Metres. Tight, because these are derived from a measured AABB rather than
## eyeballed, so anything looser would not catch a normalisation that stopped
## working.
const TOLERANCE_M: float = 0.002

## Everything that would let an unrigged mesh pretend to move. `Tween` and
## `create_tween` are the obvious route; a per-frame hook is the other; building
## an `AnimationPlayer` or an `Animation` by hand is how `toddler_view.gd`
## legitimately animates a PROCEDURAL character, and is exactly what must not
## happen to a generated one that has no rig.
const FAKE_ANIMATION_TOKENS: Array[String] = [
	"create_tween", "Tween", "AnimationPlayer.new(", "Animation.new(",
	"func _process(", "func _physics_process(",
]


## False when the raw export is not in this checkout (it is gitignored).
var _model_present: bool = true


func test_name() -> String:
	return "buddy_avatar"


func run():
	var failures: Array = []
	failures.append_array(_test_the_asset_is_here_at_all())

	# These read the source and the scenes, so they hold with or without the raw
	# export in the checkout -- and they are the ones that protect the project.
	failures.append_array(_test_the_flag_is_gated_on_validation())
	failures.append_array(_test_it_refuses_to_fake_animation())
	failures.append_array(_test_an_action_always_completes())
	failures.append_array(_test_the_glb_hierarchy_is_sealed())
	failures.append_array(_test_main_menu_wiring())
	failures.append_array(_test_little_buddy_is_untouched())

	# These measure the mesh itself. With the export gitignored, a fresh clone
	# has nothing to measure; running them anyway is the vacuous pass this case
	# was written to avoid.
	if _model_present:
		failures.append_array(_test_normalisation())
		failures.append_array(_test_material_policy())
	return failures


## -- Anti-vacuity ---------------------------------------------------------------

## Everything below measures the real asset. If it is not in the build, none of
## those measurements mean anything.
##
## But "absent" now has two very different causes, and conflating them is what
## would make this case useless:
##
##   * **Deliberately absent.** The raw Meshy exports are gitignored -- 63.6 MB
##     of generator output plus ~20 MB of extracted textures, against a 33 MB
##     repo with no git-lfs, for assets that cannot ship without retopology and
##     cannot animate at all. So a fresh clone legitimately has no model, and
##     going red there would mean the suite is red for everyone who clones.
##   * **Missing in error.** The wrapper scene itself is gone, or the path drifted.
##     That is a real failure and still reads as one.
##
## When the model is absent we therefore assert the ONE thing that still matters
## and is still checkable: **you cannot have the avatar switched on for a model
## that is not in the build.** That is not a vacuous pass -- it is the gate, and
## mutating `ENABLED` to `true` fails here with or without the asset present.
func _test_the_asset_is_here_at_all():
	var failures: Array = []
	if not ResourceLoader.exists(WRAPPER_SCENE):
		return ["%s is missing; the wrapper is the addressable unit and nothing else in "
				% WRAPPER_SCENE + "this case can run without it"]

	var buddy: Node3D = _buddy()
	if not bool(buddy.call("is_model_available")):
		# Deliberately absent. Assert the gate, then tell the rest of the case to
		# stand down rather than measure a model that is not there.
		_model_present = false
		if Buddy.ENABLED:
			failures.append(
				"the Buddy avatar is ENABLED while its model is not in this build. It would "
				+ "load nothing and show nothing. The gate must hold whether or not the raw "
				+ "asset is in the checkout."
			)
		return failures

	_model_present = true
	return failures


func _test_the_flag_is_gated_on_validation():
	var failures: Array = []
	var buddy: Node3D = _buddy()
	var reasons: Array = buddy.call("validation_failures")
	var passes: bool = bool(buddy.call("passes_validation"))

	if Buddy.ENABLED and not passes:
		failures.append(
			("PinkGirlBuddy.ENABLED is true but the asset does not pass validation:\n           "
			+ "  - %s\n         Requirement 6 of the owner's request is that the procedural "
			+ "placeholder stays the shipping Buddy until validation passes. Fix the asset "
			+ "(retopologise, bake a 512-square atlas, rig it) or put the flag back.")
			% "\n             - ".join(PackedStringArray(reasons))
		)

	# The other direction: if the asset is ever genuinely fixed, this test must
	# not be the thing standing in the way of turning it on.
	if passes and not reasons.is_empty():
		failures.append("passes_validation() and validation_failures() disagree; one of them is "
				+ "wrong and the gate cannot be trusted")

	# And the gate must be measuring something. With today's asset there are
	# three separate reasons; a gate that found none would mean the measurement
	# silently stopped working.
	if not passes and reasons.is_empty():
		failures.append("validation failed but named no reason; the gate is not actually "
				+ "measuring the asset")
	buddy.free()
	return failures


## -- 2. No faked animation --------------------------------------------------------

func _test_it_refuses_to_fake_animation():
	var failures: Array = []
	var buddy: Node3D = _buddy()

	# REVISED 2026-09-19, when the rigged re-export landed -- which the previous
	# version of this block named as the condition for revisiting it.
	#
	# The invariant was never "this character can never animate". It was that the
	# wrapper must not CLAIM a capability the asset on disk does not have, which
	# is why the rule is now stated against what the asset actually carries. The
	# source scan below -- no tween, no per-frame hook, no hand-built
	# AnimationPlayer -- is untouched, and it is the half that would catch a
	# fabricated idle.
	var report: Dictionary = buddy.call("describe_budget")
	var rigged: bool = bool(report.get("hasSkin", false)) \
			and not (report.get("animationClips", []) as Array).is_empty()

	if buddy.call("get_animation_player") != null and not rigged:
		failures.append("the wrapper reports an AnimationPlayer on an asset with no skin or no "
				+ "clips. Either one was built by hand -- a faked rig -- or the wrapper is "
				+ "describing a different model than it loaded.")

	var clips: Array = report.get("animationClips", [])
	if not clips.is_empty() and not bool(report.get("hasSkin", false)):
		failures.append(("the model reports clips %s but has NO SKIN. Clips without a skin "
				+ "cannot deform anything, so this is a claim the asset cannot honour.")
				% str(clips))

	for action: String in ActionDriver.KNOWN_ACTIONS:
		if bool(buddy.call("can_play_action", action)) and not rigged:
			failures.append(
				("can_play_action(\"%s\") is true on an asset with no skin and no clips. This "
				+ "must answer honestly: a caller that believes an action will be shown will "
				+ "compose gameplay around a pose that never appears.") % action
			)

	if String(buddy.call("get_current_action")) != "" and not rigged:
		failures.append("get_current_action() must be \"\" while nothing can be shown; reporting "
				+ "the requested action here would let a caller believe a pose is on screen")

	# A requested action is still remembered and reported honestly, under a name
	# that cannot be mistaken for "this is visible".
	#
	# A HELD action is used because outside the tree there is no `SceneTreeTimer`,
	# so a one-shot starts and finishes inside the `play_action()` call itself and
	# has already been cleared by the time it could be read. A posture persists.
	buddy.call("play_action", "sleep")
	if String(buddy.call("get_requested_action")) != "sleep":
		failures.append("get_requested_action() should name the last action asked for, found '%s'"
				% String(buddy.call("get_requested_action")))
	if String(buddy.call("get_current_action")) != "":
		failures.append("get_current_action() changed after a request that cannot be shown")
	# ...and the posture is not reported as HELD, because nothing is holding it.
	if String(buddy.call("get_held_action")) != "":
		failures.append("get_held_action() claims a posture on a character that cannot be posed")

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
	buddy.free()
	return failures


## -- 3. A no-op that always completes ---------------------------------------------

func _test_an_action_always_completes():
	var failures: Array = []
	var buddy: Node3D = _buddy()

	# Outside the tree there is no SceneTree timer, so `action_finished` is
	# emitted immediately -- which is exactly the guarantee under test: the signal
	# must arrive, not merely be scheduled somewhere that never runs.
	for action: String in ActionDriver.KNOWN_ACTIONS:
		var events: Array = []
		var on_started: Callable = func(started: String) -> void: events.append("start:%s" % started)
		var on_finished: Callable = func(ended: String) -> void: events.append("finish:%s" % ended)
		buddy.connect("action_started", on_started)
		buddy.connect("action_finished", on_finished)

		var accepted: bool = bool(buddy.call("play_action", action))
		buddy.disconnect("action_started", on_started)
		buddy.disconnect("action_finished", on_finished)

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
	buddy.connect("action_started", watcher)
	buddy.connect("action_finished", watcher)
	if bool(buddy.call("play_action", "somersault")):
		failures.append("play_action() accepted an action outside KNOWN_ACTIONS; a typo in "
				+ "content should be caught, not silently absorbed")
	buddy.disconnect("action_started", watcher)
	buddy.disconnect("action_finished", watcher)
	if not stray.is_empty():
		failures.append("a refused action still emitted %s" % str(stray))

	buddy.free()
	return failures


## -- 4. Normalisation ---------------------------------------------------------------

func _test_normalisation():
	var failures: Array = []
	var buddy: Node3D = _buddy()
	var report: Dictionary = buddy.call("describe_budget")
	if not bool(report.get("available", false)):
		buddy.free()
		return failures

	var feet: float = float(report.get("feetY", 999.0))
	if absf(feet) > TOLERANCE_M:
		failures.append(
			("the model's lowest point sits at y = %.4f in the wrapper's own space, not 0. Art "
			+ "bible §6 puts the pivot at base centre for anything standing, and the whole house "
			+ "is dimensioned against floor-standing pivots -- a mid-body pivot buries the "
			+ "character to the waist in every room.") % feet
		)

	var height: float = float(report.get("height", 0.0))
	if absf(height - Buddy.MODEL_HEIGHT_M) > TOLERANCE_M:
		failures.append("the normalised height is %.4f m, not the intended %.2f m"
				% [height, Buddy.MODEL_HEIGHT_M])

	# The scale must actually be doing work -- if the raw model were already
	# 1.65 m the two assertions above would pass without any normalisation.
	var raw: float = float(report.get("rawHeight", 0.0))
	if absf(raw - Buddy.MODEL_HEIGHT_M) <= TOLERANCE_M:
		failures.append("the raw model is already %.2f m tall, so the height assertion above "
				% raw + "cannot distinguish a working normalisation from none at all")

	# Art bible §4: Mom 1.65 m, Dad 1.78 m. An adult, not a second toddler.
	if Buddy.MODEL_HEIGHT_M < 1.6 or Buddy.MODEL_HEIGHT_M > 1.8:
		failures.append("MODEL_HEIGHT_M is %.2f m; art bible §4 puts an adult between Mom's "
				% Buddy.MODEL_HEIGHT_M + "1.65 m and Dad's 1.78 m")

	buddy.free()
	return failures


## -- 5. The §7 material decision, applied and asserted ------------------------------

## The wrapper fixes three §7 violations on a duplicate of the imported material.
## Both halves are checked: that the source really does violate them (or the fix
## is being tested against nothing), and that the rendered material does not.
func _test_material_policy():
	var failures: Array = []
	var buddy: Node3D = _buddy()
	var report: Dictionary = buddy.call("describe_budget")
	if not bool(report.get("available", false)):
		buddy.free()
		return failures

	# The "is the wrapper's fix asserted against anything?" check was DELETED here
	# on 2026-09-19, deliberately and with its reasoning recorded rather than
	# quietly commented out.
	#
	# It existed to stop the wrapper's runtime §7 correction from becoming dead
	# code that merely looks like a safeguard, and it did that by requiring the
	# IMPORTED material to still be broken. That was right while the only asset
	# was a raw Meshy export. It is now backwards: `tools/optimize_runtime_glb.py`
	# strips the emissive, the specular extension, the normal map and doubleSided
	# from the FILE, so a clean import is the goal achieved, not a regression --
	# and the old assertion would have punished exactly the fix it was asking for.
	#
	# What protects the look is unchanged and still below: the RENDERED material
	# must be metallic 0.0, carry no normal map, be single-sided, sit in §7's
	# roughness band and bind exactly one texture. Those run against the real
	# surface override every time.

	if float(report.get("appliedMetallic", 1.0)) != 0.0:
		failures.append(
			("the rendered material has metallic = %.2f. Art bible §7 is absolute -- 0.0 "
			+ "everywhere -- and this is not a style call: a fully metallic surface has no "
			+ "diffuse response, so under one directional light the caregiver renders as a dark "
			+ "oily silhouette.") % float(report.get("appliedMetallic", 1.0))
		)
	if bool(report.get("appliedNormalMap", true)):
		failures.append("the rendered material still has a normal map; §7 bans them, and it "
				+ "costs a whole 2048-square texture on a flat-albedo pastel character")
	if bool(report.get("appliedDoubleSided", true)):
		failures.append("the rendered material is still double-sided; that doubles overdraw on a "
				+ "619,890-triangle mesh for no gain")
	var roughness: float = float(report.get("appliedRoughness", 0.0))
	if roughness < 0.85 or roughness > 1.0:
		failures.append("roughness %.2f is outside §7's 0.85-1.0 band; nothing in this game is "
				% roughness + "shiny")
	if int(report.get("appliedTextures", 9)) != 1:
		failures.append("%d textures are bound on the rendered material; §7 allows one atlas, "
				% int(report.get("appliedTextures", 9))
				+ "and dropping the normal and metallic/roughness maps should leave only albedo")

	buddy.free()
	return failures


## -- 6. The wrapper is a wrapper ----------------------------------------------------

## The whole point of the file is that a re-export with different node names
## changes one file. That only holds while the raw hierarchy is sealed behind the
## wrapper's own node and nothing outside addresses it.
func _test_the_glb_hierarchy_is_sealed():
	var failures: Array = []
	var buddy: Node3D = _buddy()
	if bool(buddy.call("is_model_available")):
		var children: Array = []
		for child: Node in buddy.get_children():
			children.append(String(child.name))
		if children != [Buddy.MODEL_NODE_NAME]:
			failures.append(
				("the wrapper's direct children are %s; they must be exactly [\"%s\"] so the GLB's "
				+ "own node names exist nowhere but inside the wrapper")
				% [str(children), Buddy.MODEL_NODE_NAME]
			)
	buddy.free()

	# And nothing outside the wrapper names the asset. `main.gd` reaches the
	# avatar through the SCENE, never through the GLB.
	for path: String in ["res://scenes/main/main.gd", "res://scripts/character/toddler_view.gd"]:
		if _read(path).contains("pinkGirl_v01.glb"):
			failures.append("%s names the raw GLB. Only the wrapper may." % path)
	return failures


## -- 7. Where it is wired ------------------------------------------------------------

func _test_main_menu_wiring():
	var failures: Array = []

	# One flag, not two. `main.gd` must read the wrapper's constant rather than
	# carry its own copy, or the two can disagree and the "single obvious flag"
	# stops being either.
	if Main.buddy_avatar_enabled() != Buddy.ENABLED:
		failures.append("main.gd's buddy_avatar_enabled() disagrees with PinkGirlBuddy.ENABLED; "
				+ "there must be exactly one switch in the project")

	var main_code: String = _read(MAIN_SOURCE)
	if not main_code.contains(WRAPPER_SCENE):
		failures.append("main.gd no longer references %s; the preview wiring is gone"
				% WRAPPER_SCENE)

	# With the flag off the title screen must be exactly what it always was --
	# including the camera, which is why the with-avatar framing is a separate
	# pair of constants rather than an edit to the originals.
	if not Buddy.ENABLED:
		if Main.CAMERA_POSITION != Vector3(0.72, 0.80, 2.05):
			failures.append("the default title-screen camera position moved; with the avatar off "
					+ "the menu must render exactly as it did before this work")
		if Main.CAMERA_TARGET != Vector3(0.0, 0.44, 0.0):
			failures.append("the default title-screen camera target moved")
	if Main.CAMERA_POSITION_WITH_BUDDY == Main.CAMERA_POSITION:
		failures.append("the with-avatar framing is identical to the default one; a 1.65 m figure "
				+ "will not fit a frame composed for a 0.85 m one")
	return failures


## -- 8. Little Buddy is not replaced ---------------------------------------------------

## The owner's requirement, and the easiest thing to get wrong in a hurry: this
## model is the adult caregiver. The child stays `toddler_view.gd`.
func _test_little_buddy_is_untouched():
	var failures: Array = []
	var scene: String = _read(MAIN_SCENE)
	if scene.is_empty():
		return ["buddy_avatar: could not read %s" % MAIN_SCENE]
	if not scene.contains("res://scripts/character/toddler_view.gd"):
		failures.append("main.tscn no longer uses toddler_view.gd. Little Buddy is the child "
				+ "character and is not replaced by the caregiver avatar.")
	if not scene.contains("name=\"LittleBuddy\""):
		failures.append("the LittleBuddy node is gone from the title screen")
	# Executable code only: the wrapper's doc comment legitimately cites
	# `toddler_view.gd` as the precedent it follows, and a guard that punished
	# accurate documentation would be weakened rather than fixed.
	var wrapper: String = _code_of(_read(WRAPPER_SOURCE))
	if wrapper.contains("toddler_view"):
		failures.append("the caregiver wrapper references toddler_view.gd in executable code; "
				+ "the two characters must not become coupled")
	return failures


## -- Helpers ---------------------------------------------------------------------------

func _buddy():
	var node := Node3D.new()
	node.set_script(Buddy)
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
