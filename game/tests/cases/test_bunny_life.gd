extends RefCounted

## Bunny is not a statue -- the part of that which can be asserted.
##
## The brief for this pass was one sentence: "Bunny must not remain a rigid
## statue." Most of the answer is a judgement about how a character LOOKS, which
## is settled by rendering the bedroom and looking at it (`docs/shots/a_bunny_*`,
## `docs/BUNNY_LIFE_PASS.md`), not by an assertion. What is pinned here is
## everything underneath that, in descending order of how badly it would hurt:
##
##   1. **The clips are real bone tracks on the real skeleton.** This is the
##      honesty guarantee. A "reaction" that turned out to be a sine wave on the
##      model's transform would be a lie told to every decision taken afterwards,
##      and `test_baby_avatar.gd` already defends the wrapper against exactly
##      that. So every authored clip must address bones of `LB_Rig_v1` by name,
##      with rotation tracks, and must actually move them off the rest pose.
##   2. **Every clip rests every bone it does not animate.** The trap that
##      `toddler_view.gd` records: an `AnimationPlayer` only writes the tracks a
##      clip has, so an `idle` with no leg tracks idles with the legs frozen
##      mid-stride from `walk`. Here it would be worse -- `walk` drives all 24.
##   3. **The distress is the REAL hunger axis, continuously.** Not a second
##      number, not a switch at the threshold. It is read off the same values
##      `child_needs.gd` derives `hungry` from, and it is monotonic in them.
##   4. **One Bunny.** Exactly one pose model visible, and one `ChildActor` in
##      the shipping house scene.
##   5. **The child UX rules hold.** No clip is a failure state, and nothing in
##      the life layer scores the player.
##
## ## Why so much of this is about the SHAPE of the data
##
## A test cannot see that a fuss reads as fretting. It can see that the fuss clip
## exists, touches the arms and the spine, differs from the idle, runs faster when
## the child is hungrier, and is the clip a hungry child is actually given. Each
## of those is a way the feature silently stops working, and all of them have
## been wrong at least once in this file's own history.

const Life := preload("res://scripts/care/child_life.gd")
const LifeClips := preload("res://scripts/characters/little_buddy/baby_life_clips.gd")
const Needs := preload("res://scripts/care/child_needs.gd")
const Present := preload("res://scripts/care/child_presentation.gd")
const Actor := preload("res://scripts/care/child_actor.gd")
const Baby := preload("res://scripts/characters/little_buddy/baby_little_buddy.gd")

const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"

## Bones every life clip must touch, because a "reaction" that moves nothing
## above the waist is not one.
const EXPRESSIVE_BONES: Array[String] = ["Head", "LeftArm", "RightArm"]

## Rotation tracks are quaternions; two poses this close are the same pose.
const SAME_POSE: float = 0.001


func test_name() -> String:
	return "bunny_life"


func run():
	var failures: Array = []
	failures.append_array(_test_the_clips_are_bone_tracks_on_the_real_rig())
	failures.append_array(_test_every_clip_rests_every_other_bone())
	failures.append_array(_test_the_clips_actually_differ())
	failures.append_array(_test_distress_is_the_real_hunger_axis())
	failures.append_array(_test_a_hungry_bunny_fusses())
	failures.append_array(_test_being_cared_for_shows())
	failures.append_array(_test_attention_has_hysteresis_and_a_limit())
	failures.append_array(_test_the_turn_never_overshoots())
	failures.append_array(_test_there_is_exactly_one_bunny())
	failures.append_array(_test_nothing_here_punishes_the_child())
	return failures


# ---------------------------------------------------------------------------
# 1. The clips are real skeletal animation
# ---------------------------------------------------------------------------

## The honesty guarantee, asserted against the skeleton the game ships.
##
## Skipped -- loudly, not silently -- when the rigged export is not in this
## checkout: it is gitignored, and a clone going red for not having a 1.6 MB GLB
## would be a suite that is red for everyone. Every other helper in this case
## runs without it.
func _test_the_clips_are_bone_tracks_on_the_real_rig():
	var failures: Array = []
	var skeleton: Skeleton3D = _skeleton()
	if skeleton == null:
		return failures

	if LifeClips.CLIP_NAMES.size() < 5:
		failures.append("only %d life clips are authored; the pass promised idle, fuss, eat, "
				% LifeClips.CLIP_NAMES.size() + "drink and celebrate")

	for clip_name: String in LifeClips.CLIP_NAMES:
		var animation: Animation = LifeClips.build(clip_name, skeleton, "Armature/Skeleton3D")
		if animation == null:
			failures.append("no '%s' clip was built at all" % clip_name)
			continue
		if animation.length < 0.5:
			failures.append("the '%s' clip is %.2f s long; that is a pop, not a motion"
					% [clip_name, animation.length])

		var moved: Dictionary = {}
		for track: int in range(animation.get_track_count()):
			var type: int = animation.track_get_type(track)
			if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D:
				failures.append(("the '%s' clip has a track of type %d. Every track must be a BONE "
						+ "track: a value track on a node property would be the model being moved "
						+ "around rather than the character being animated.") % [clip_name, type])
				continue
			var path: String = String(animation.track_get_path(track))
			var bone: String = path.get_slice(":", 1)
			if skeleton.find_bone(bone) == -1:
				failures.append(("the '%s' clip addresses '%s', which is not a bone on this "
						+ "skeleton. A track that resolves to nothing animates nothing and reports "
						+ "no error.") % [clip_name, path])
				continue
			if _track_moves(animation, track, skeleton, bone):
				moved[bone] = true

		var expressive: int = 0
		for bone: String in EXPRESSIVE_BONES:
			if moved.has(bone):
				expressive += 1
		if expressive == 0:
			failures.append(("the '%s' clip leaves the head and both arms exactly at rest. Whatever "
					+ "else it does, a reaction that moves nothing a player looks at is not one.")
					% clip_name)
	return failures


## Does this track ever leave the bone's rest pose? The whole point: a clip made
## entirely of rest keys compiles, plays, and does nothing.
func _track_moves(animation: Animation, track: int, skeleton: Skeleton3D, bone: String) -> bool:
	var index: int = skeleton.find_bone(bone)
	var rest: Transform3D = skeleton.get_bone_rest(index)
	for key: int in range(animation.track_get_key_count(track)):
		var value: Variant = animation.track_get_key_value(track, key)
		if value is Quaternion:
			if absf((value as Quaternion).dot(rest.basis.get_rotation_quaternion())) < 1.0 - SAME_POSE:
				return true
		elif value is Vector3:
			if (value as Vector3).distance_to(rest.origin) > SAME_POSE:
				return true
	return false


# ---------------------------------------------------------------------------
# 2. Every clip says something about every bone
# ---------------------------------------------------------------------------

## `walk` drives all 24 bones. A life clip that keys only the arms would play
## with the legs frozen wherever the walk left them -- the failure
## `toddler_view.gd::_baseline()` was written for, one rig larger.
func _test_every_clip_rests_every_other_bone():
	var failures: Array = []
	var skeleton: Skeleton3D = _skeleton()
	if skeleton == null:
		return failures

	for clip_name: String in LifeClips.CLIP_NAMES:
		var animation: Animation = LifeClips.build(clip_name, skeleton, "Armature/Skeleton3D")
		if animation == null:
			continue
		var covered: Dictionary = {}
		for track: int in range(animation.get_track_count()):
			covered[String(animation.track_get_path(track)).get_slice(":", 1)] = true
		var missing: Array = []
		for index: int in range(skeleton.get_bone_count()):
			if not covered.has(skeleton.get_bone_name(index)):
				missing.append(skeleton.get_bone_name(index))
		if not missing.is_empty():
			failures.append(("the '%s' clip has no track for %s. An AnimationPlayer only writes the "
					+ "tracks a clip HAS, so those bones keep whatever the previous clip left -- "
					+ "and the previous clip is usually `walk`, which drives every one of them.")
					% [clip_name, str(missing)])
	return failures


# ---------------------------------------------------------------------------
# 3. The clips are different from each other
# ---------------------------------------------------------------------------

## Five names for one motion would pass everything above and be worth nothing.
## The two that matter most are `idle` and `fuss`: they are the two states a
## player spends the most time looking at, and the difference between them is the
## entire visible answer to "is Bunny all right?".
func _test_the_clips_actually_differ():
	var failures: Array = []
	var skeleton: Skeleton3D = _skeleton()
	if skeleton == null:
		return failures

	var idle: Animation = LifeClips.build(LifeClips.CLIP_IDLE, skeleton, "Armature/Skeleton3D")
	var fuss: Animation = LifeClips.build(LifeClips.CLIP_FUSS, skeleton, "Armature/Skeleton3D")
	if idle == null or fuss == null:
		return failures

	var differing: int = 0
	for bone: String in ["LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "Head"]:
		if _first_pose(idle, bone).dot(_first_pose(fuss, bone)) < 1.0 - 0.01:
			differing += 1
	if differing < 3:
		failures.append(("the idle and the fuss put %d of five expressive bones in different "
				+ "places. They are the two states the player sees most, and telling them apart "
				+ "IS the feature.") % differing)
	return failures


func _first_pose(animation: Animation, bone: String) -> Quaternion:
	for track: int in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		if String(animation.track_get_path(track)).get_slice(":", 1) != bone:
			continue
		if animation.track_get_key_count(track) == 0:
			continue
		return animation.track_get_key_value(track, 0) as Quaternion
	return Quaternion.IDENTITY


# ---------------------------------------------------------------------------
# 4. The distress is the real axis
# ---------------------------------------------------------------------------

## Pure, so it holds with or without the model. The rule is continuity: the cue
## must get stronger as the child gets hungrier, across the same two thresholds
## `child_needs.gd` uses, and it must not invent a third number of its own.
func _test_distress_is_the_real_hunger_axis():
	var failures: Array = []

	if Life.distress(_stats(10.0)) != 0.0:
		failures.append("a well-fed child reports distress %.2f; below the threshold it must be 0"
				% Life.distress(_stats(10.0)))
	if Life.distress(_stats(Needs.HUNGRY_AT)) != 0.0:
		failures.append("distress is already %.2f at the exact moment the child starts asking; 0 "
				% Life.distress(_stats(Needs.HUNGRY_AT)) + "is what makes the gradient start there")
	if Life.distress(_stats(Needs.CRYING_SEVERITY)) < 1.0:
		failures.append("distress is only %.2f at the severity `child_needs.gd` calls crying"
				% Life.distress(_stats(Needs.CRYING_SEVERITY)))
	if Life.distress(_stats(200.0)) > 1.0:
		failures.append("distress is unbounded above 1.0; the pace it drives would run away")

	# Monotonic. A cue that got calmer as things got worse would be worse than none.
	var previous: float = -1.0
	for hunger: float in [0.0, 20.0, 45.0, 60.0, 75.0, 90.0, 100.0]:
		var level: float = Life.distress(_stats(hunger))
		if level < previous:
			failures.append("distress fell from %.2f to %.2f as hunger rose to %.0f"
					% [previous, level, hunger])
		previous = level

	# ...and it reaches the clip, as pace, in the same direction.
	var calm: float = Life.fuss_pace(0.0)
	var urgent: float = Life.fuss_pace(1.0)
	if urgent <= calm:
		failures.append("the fuss plays at %.2f when desperate and %.2f when barely hungry; the "
				% [urgent, calm] + "pace is the whole gradient a child can see")
	if Life.pace_for(Life.LIFE_IDLE, 1.0) != 1.0:
		failures.append("the idle's pace is driven by distress; only the fuss should be, or a "
				+ "content child breathes at whatever speed the last need left behind")
	return failures


# ---------------------------------------------------------------------------
# 5. The state machine, through the real actor
# ---------------------------------------------------------------------------

func _test_a_hungry_bunny_fusses():
	var failures: Array = []

	# Pure first, so this half holds in a checkout with no model.
	var hungry: Dictionary = _stats(70.0)
	if Life.clip_for(hungry, Present.ACTIVITY_IDLE, false, 0.0) != Life.LIFE_FUSS:
		failures.append("a hungry child was given '%s'; the need must show on the body as well as "
				% Life.clip_for(hungry, Present.ACTIVITY_IDLE, false, 0.0)
				+ "in the speech bubble")
	if Life.clip_for(_stats(5.0), Present.ACTIVITY_IDLE, false, 0.0) != Life.LIFE_IDLE:
		failures.append("a content child is not idling")
	if Life.clip_for(hungry, Present.ACTIVITY_IDLE, true, 0.0) != Life.LIFE_WALK:
		failures.append("a walking child must walk; a fuss pose sliding across the floor is worse "
				+ "than no reaction at all")
	# Feeding: the bottle and the spoon are different, and an explicit care kind
	# settles it rather than the stats guessing.
	if Life.feeding_clip(hungry, "giveBottle") != Life.LIFE_DRINK:
		failures.append("a bottle must be drunk, not eaten, when the caller says it is a bottle")
	if Life.feeding_clip(hungry, "") != Life.LIFE_EAT:
		failures.append("with nothing but a hungry child's stats, feeding should read as eating")

	var bunny: Node3D = _bunny()
	if bunny == null:
		return failures
	var stats: RefCounted = bunny.call("get_stats")
	stats.call("set_stat", "hunger", 72.0)
	bunny.call("set_activity", Present.ACTIVITY_IDLE)
	if String(bunny.call("get_need")) != Needs.HUNGRY:
		failures.append("the actor does not report a hungry child as hungry")
	if String(bunny.call("get_life_clip")) != Life.LIFE_FUSS:
		failures.append("the actor left a hungry Bunny playing '%s'"
				% String(bunny.call("get_life_clip")))
	var worse: float = float(bunny.call("get_distress"))
	stats.call("set_stat", "hunger", 50.0)
	bunny.call("_refresh")
	if float(bunny.call("get_distress")) >= worse:
		failures.append("feeding the child did not reduce the distress it reports")
	bunny.free()
	return failures


func _test_being_cared_for_shows():
	var failures: Array = []
	if Life.HAPPY_SECONDS <= 0.0:
		failures.append("being cared for is visible for %.1f s; the only feedback this game has "
				% Life.HAPPY_SECONDS + "for 'you did it' cannot be zero-length")
	if Life.clip_for(_stats(70.0), Present.ACTIVITY_IDLE, false, 1.0) != Life.LIFE_HAPPY:
		failures.append("a child who has just been helped still fusses; the happy window must win "
				+ "over the need for the moment it lasts")

	var bunny: Node3D = _bunny()
	if bunny == null:
		return failures
	bunny.call("get_stats").call("set_stat", "hunger", 80.0)
	bunny.call("_refresh")
	var before: String = String(bunny.call("get_life_clip"))
	bunny.call("satisfy", Needs.HUNGRY, 70.0)
	var after: String = String(bunny.call("get_life_clip"))
	if before == after:
		failures.append("Bunny plays '%s' both before and after being fed. The whole mission ends "
				% after + "there; something has to change.")
	if after != Life.LIFE_HAPPY:
		failures.append("after being fed Bunny plays '%s', not the happy clip" % after)

	# ...and it ENDS. A child permanently celebrating a bottle from an hour ago is
	# as wrong as one who never reacted.
	bunny.call("live", Life.HAPPY_SECONDS + 0.1)
	if String(bunny.call("get_life_clip")) == Life.LIFE_HAPPY:
		failures.append("Bunny is still celebrating %.1f s later" % Life.HAPPY_SECONDS)
	bunny.free()
	return failures


# ---------------------------------------------------------------------------
# 6. Attention
# ---------------------------------------------------------------------------

func _test_attention_has_hysteresis_and_a_limit():
	var failures: Array = []
	if Life.ATTEND_FAR <= Life.ATTEND_NEAR:
		failures.append("the attention band is inverted; without a gap Bunny pivots on the spot "
				+ "every time Aliz wobbles across the exact radius")
	if Life.should_attend(Life.ATTEND_NEAR - 0.1, false) != true:
		failures.append("Bunny does not notice Aliz standing right next to him")
	if Life.should_attend(Life.ATTEND_FAR + 0.5, true) != false:
		failures.append("Bunny keeps watching Aliz from across the house")
	# The band itself: inside it, the answer is whatever it already was.
	var middle: float = (Life.ATTEND_NEAR + Life.ATTEND_FAR) * 0.5
	if Life.should_attend(middle, true) != true or Life.should_attend(middle, false) != false:
		failures.append("the hysteresis band does not hold its state at %.2f m" % middle)

	if Life.ATTEND_LIMIT_DEG <= 0.0 or Life.ATTEND_LIMIT_DEG > 90.0:
		failures.append(("Bunny will turn %.0f degrees to watch Aliz. The camera is fixed at +Z; "
				+ "past about 45 the player is looking at the back of his head and the character "
				+ "stops being one.") % Life.ATTEND_LIMIT_DEG)
	if absf(Life.attend_yaw(170.0)) > Life.ATTEND_LIMIT_DEG:
		failures.append("Aliz behind Bunny turned him %.0f degrees, past his own limit"
				% Life.attend_yaw(170.0))
	return failures


## The turn is the one procedural motion in this pass, so the two ways a
## hand-rolled turn goes wrong are pinned: it must not overshoot (which jitters
## forever), and it must take the short way round (which is the difference
## between glancing across and spinning the long way).
func _test_the_turn_never_overshoots():
	var failures: Array = []
	if Life.turn_towards(0.0, 10.0, 1.0, 1000.0) != 10.0:
		failures.append("a turn with plenty of time did not arrive exactly; got %.3f"
				% Life.turn_towards(0.0, 10.0, 1.0, 1000.0))
	if Life.shortest_turn(-170.0, 170.0) > 0.0:
		failures.append("the turn from -170 to 170 went the long way round (%.1f degrees)"
				% Life.shortest_turn(-170.0, 170.0))

	var angle: float = 0.0
	for _step: int in range(400):
		angle = Life.turn_towards(angle, 40.0, 1.0 / 60.0)
	if absf(angle - 40.0) > 0.001:
		failures.append("the turn settled at %.3f instead of 40; it is oscillating" % angle)
	if Life.TURN_RATE_DEG <= 0.0:
		failures.append("the turn rate is not positive, so Bunny never turns at all")
	return failures


# ---------------------------------------------------------------------------
# 7. One Bunny
# ---------------------------------------------------------------------------

## Two babies on screen is the failure the pose system was built to prevent, and
## it now has a second way to happen: the actor caches an `AnimationPlayer`, and
## a pose cut hides the model that player belongs to. Both halves are checked --
## one visible pose holder, and one actor in the shipping scene.
func _test_there_is_exactly_one_bunny():
	var failures: Array = []

	var bunny: Node3D = _bunny()
	if bunny != null:
		var model: Node = bunny.get_node_or_null("Model")
		var visible_poses: int = 0
		for child: Node in model.get_children():
			if (child as Node3D).visible:
				visible_poses += 1
		if visible_poses != 1:
			failures.append("%d pose models are visible at once; exactly one Bunny may be on screen"
					% visible_poses)

		# ...and the one that is visible is the one being animated.
		var shown: String = String(bunny.call("get_pose"))
		if shown != Baby.PREFERRED_POSE:
			failures.append(("a bare Bunny shows the '%s' pose. Only '%s' has a skeleton, so any "
					+ "other choice is a Bunny that cannot move.") % [shown, Baby.PREFERRED_POSE])
		bunny.free()

	# And the shipping scene holds one, not none and not two. Read as text: this
	# must hold without instantiating the whole house inside a unit test.
	var scene: String = _read(HOUSE_SCENE)
	if scene.is_empty():
		failures.append("%s is missing; the one-Bunny rule cannot be checked" % HOUSE_SCENE)
		return failures
	var actors: int = scene.count("script = ExtResource(\"8\")")
	var declared: int = scene.count("res://scripts/care/child_actor.gd")
	if declared != 1:
		failures.append("%s references child_actor.gd %d times; the house has one child"
				% [HOUSE_SCENE, declared])
	if actors != 1:
		failures.append(("%s instantiates %d ChildActors. Two Bunnies in one house is the bug this "
				+ "whole pose system exists to prevent.") % [HOUSE_SCENE, actors])
	return failures


# ---------------------------------------------------------------------------
# 8. The child UX rules
# ---------------------------------------------------------------------------

## `CLAUDE.md`: no failure pressure, no score, no red X. A reaction layer is
## exactly where those creep in -- "play the sad clip when the player is slow" is
## one line away at all times.
func _test_nothing_here_punishes_the_child():
	var failures: Array = []
	for path: String in [
		"res://scripts/care/child_life.gd",
		"res://scripts/characters/little_buddy/baby_life_clips.gd",
	]:
		# **Executable code only**, by the technique `test_architecture_guard.gd`
		# establishes and explains: comments stripped, string bodies blanked. The
		# first version of this scan read raw source and went red because those
		# files' doc comments say things like "getting a sign wrong is invisible"
		# and "the failure mode this prevents". Punishing accurate documentation is
		# how a guard gets weakened rather than fixed, so it reads code instead.
		var source: String = _code_of(_read(path)).to_lower()
		if source.strip_edges().length() < 400:
			failures.append("%s stripped to almost nothing; this scan would pass vacuously" % path)
			continue
		for banned: String in ["score", "percent", "wrong", "fail", "penalt", "countdown"]:
			if source.contains(banned):
				failures.append(("%s uses '%s' in executable code. The life layer reacts to the "
						+ "CHILD's state, never to the player's performance; a reaction that grades "
						+ "the player is how a scoreboard gets in.") % [path, banned])
	# A fuss is a need, not a punishment: it must go away when the need is met,
	# by the model alone and with no player input at all.
	if Life.clip_for(_stats(5.0), Present.ACTIVITY_IDLE, false, 0.0) == Life.LIFE_FUSS:
		failures.append("a child with nothing wrong still fusses; the cue would mean nothing")
	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _stats(hunger: float) -> Dictionary:
	return {
		"hunger": hunger, "thirst": 10.0, "happiness": 80.0,
		"energy": 90.0, "cleanliness": 90.0, "freshness": 90.0,
	}


## A built `ChildActor`, or null when the rigged export is not in this checkout.
## The caller frees it.
func _bunny():
	if not Baby.is_pose_available(Baby.PREFERRED_POSE):
		return null
	var node := Node3D.new()
	node.set_script(Actor)
	node.call("build")
	return node


## The rigged model's skeleton, or null when the export is absent. Loaded through
## the wrapper so this case never names a Meshy filename -- `test_baby_avatar.gd`
## fails the whole suite if one leaks, and rightly.
func _skeleton() -> Skeleton3D:
	var bunny: Node3D = _bunny()
	if bunny == null:
		return null
	var found: Skeleton3D = _find_skeleton(bunny)
	if found != null:
		# Detached so the 14,000-triangle baby can be freed while the skeleton it
		# owns stays measurable for the rest of the case.
		found.get_parent().remove_child(found)
	bunny.free()
	return found


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


## Source with every comment removed and every string literal blanked, leaving
## executable code. Lifted deliberately from `test_architecture_guard.gd`, which
## documents both why it is needed and why a `#` inside a string must not be read
## as the start of a comment.
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


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
