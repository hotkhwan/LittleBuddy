extends RefCounted

## Aliz is alive at rest: her authored idle, her face moods, her blink and her
## hair sway -- the four things added 2026-09-20 on top of the rigged asset.
##
## Everything here runs on the real wrapper and the real skeleton, headless and
## out of the tree, which is the same setting `test_buddy_avatar.gd` uses. So
## the idle is judged by BONE TRANSFORM DELTAS read back off the skeleton at
## 1.5 s intervals (printed, because the brief asked for the numbers), the face
## by the texels the wrapper actually uploads, and the blink by state.
##
## What is deliberately NOT asserted: the angles' exact values. Somebody tuning
## the idle by eye must not have to edit a test to do it. What IS pinned is that
## the breath, the head bob and the weight shift EXIST and stay SMALL -- an idle
## that moves the head 20 cm is a dance, and a game for a three-year-old does
## not want its caregiver dancing.

const Buddy := preload("res://scripts/characters/buddy/pink_girl_buddy.gd")
const LifeClips := preload("res://scripts/characters/buddy/buddy_life_clips.gd")
const HairSway := preload("res://scripts/characters/buddy/buddy_hair_sway.gd")

## The head must move by at least this much between the sampled frames (the
## breath alone gives ~2 mm; the weight shift ~1 cm) and never more than this.
const HEAD_MIN_DELTA_CM: float = 0.15
const HEAD_MAX_DELTA_CM: float = 6.0
## Every keyed bone stays within this many degrees of its rest across the loop.
const MAX_BONE_DEG: float = 6.0


func test_name() -> String:
	return "aliz_life"


func run():
	var failures: Array = []
	var buddy: Node3D = Buddy.new()
	buddy.call("build")
	if not bool(buddy.call("is_model_available")):
		buddy.free()
		return ["the rigged Aliz asset is not in this build; nothing here can be measured"]
	failures.append_array(_test_idle(buddy))
	failures.append_array(_test_locomotion_returns_to_idle(buddy))
	failures.append_array(_test_faces(buddy))
	failures.append_array(_test_blink(buddy))
	failures.append_array(_test_action_faces(buddy))
	failures.append_array(_test_hair_sway(buddy))
	buddy.free()
	return failures


## -- 1. the idle: bone deltas at 1.5 s intervals -------------------------------

func _test_idle(buddy: Node3D):
	var failures: Array = []
	if not bool(buddy.call("can_play_action", "idle")):
		return ["play_action(\"idle\") is not playable: the authored idle did not merge"]
	var player: AnimationPlayer = buddy.call("get_animation_player")
	var skeleton: Skeleton3D = buddy.call("get_skeleton")
	if player == null or skeleton == null or not player.has_animation("idle"):
		return ["no AnimationPlayer / skeleton / idle clip on the rigged asset"]
	var idle: Animation = player.get_animation("idle")
	if idle.loop_mode != Animation.LOOP_LINEAR:
		failures.append("the idle must loop")
	if idle.length < 4.0:
		failures.append("the idle is %.1f s; a loop that short reads as a tic" % idle.length)

	var head: int = skeleton.find_bone(LifeClips.HEAD)
	var hips: int = skeleton.find_bone(LifeClips.HIPS)
	var spine: int = skeleton.find_bone(LifeClips.SPINE_TOP)
	if head == -1 or hips == -1 or spine == -1:
		return ["the skeleton lacks Head / Hips / Spine; the idle has nothing to move"]

	player.play("idle")
	var samples: Array = []
	print("      idle proof -- bone deltas from rest, sampled 1.5 s apart:")
	for n: int in range(4):
		var t: float = 0.3 + 1.5 * float(n)
		player.seek(t, true)
		var head_pos: Vector3 = _global(skeleton, head).origin
		var rest_pos: Vector3 = skeleton.get_bone_global_rest(head).origin
		var d: Vector3 = head_pos - rest_pos
		var head_deg: float = rad_to_deg(_delta(skeleton, head).get_angle())
		var hips_deg: float = rad_to_deg(_delta(skeleton, hips).get_angle())
		var spine_deg: float = rad_to_deg(_delta(skeleton, spine).get_angle())
		# Bone units are centimetres on this rig.
		print("        t=%.1fs  head (%+.2f, %+.2f, %+.2f) cm  head %.2f deg  spine %.2f deg  hips %.2f deg"
				% [t, d.x, d.y, d.z, head_deg, spine_deg, hips_deg])
		samples.append({"head": head_pos, "headDeg": head_deg, "hipsDeg": hips_deg,
				"spineDeg": spine_deg})

	var moved: float = 0.0
	var max_deg: float = 0.0
	for k: int in range(1, samples.size()):
		moved = maxf(moved, (samples[k]["head"] as Vector3).distance_to(samples[k - 1]["head"]))
	for sample: Dictionary in samples:
		max_deg = maxf(max_deg, maxf(float(sample["headDeg"]),
				maxf(float(sample["hipsDeg"]), float(sample["spineDeg"]))))
	if moved < HEAD_MIN_DELTA_CM:
		failures.append("the idle moves the head only %.2f cm between samples; that is a statue"
				% moved)
	if moved > HEAD_MAX_DELTA_CM:
		failures.append("the idle moves the head %.2f cm between samples; that is a dance" % moved)
	if max_deg > MAX_BONE_DEG:
		failures.append("an idle bone is %.1f degrees off rest; the brief asks for a breath, not a sway"
				% max_deg)
	# The weight shift changes SIDE: the hips lean one way, then the other.
	var leaned_both_ways: bool = false
	var first_sign: float = 0.0
	for t: float in [1.0, 5.0]:
		player.seek(t, true)
		var q: Quaternion = _delta(skeleton, hips)
		var sign: float = signf(q.get_axis().z * q.get_angle())
		if first_sign == 0.0:
			first_sign = sign
		elif sign != 0.0 and sign != first_sign:
			leaned_both_ways = true
	if not leaned_both_ways:
		failures.append("the hips lean the same way at 1.0 s and 5.0 s; the weight never shifts")
	player.stop()
	return failures


## -- 2. locomotion hands back to the idle rather than freezing ---------------------

func _test_locomotion_returns_to_idle(buddy: Node3D):
	var failures: Array = []
	var player: AnimationPlayer = buddy.call("get_animation_player")
	buddy.call("set_locomotion", 1.0)
	if player.current_animation != "walk" and player.current_animation != "run":
		failures.append("set_locomotion(1.0) should play a locomotion clip, got '%s'"
				% player.current_animation)
	buddy.call("set_locomotion", 0.0)
	if player.current_animation != "idle" or not player.is_playing():
		failures.append("set_locomotion(0) should hand over to the idle, got '%s' (playing=%s)"
				% [player.current_animation, str(player.is_playing())])
	# ...and, standing still, it must not restart the idle every frame.
	player.seek(2.0, true)
	buddy.call("set_locomotion", 0.0)
	if absf(player.current_animation_position - 2.0) > 0.05:
		failures.append("set_locomotion(0) restarted the idle; at rest it must leave it alone")
	player.stop()
	return failures


## -- 3. the face moods change the texels they claim to -------------------------------

func _test_faces(buddy: Node3D):
	var failures: Array = []
	if not bool(buddy.call("has_face_moods")):
		return ["the shipped atlas has no mood patches the compositor trusts (manifest or probes)"]
	var moods: Array = buddy.call("available_faces")
	for wanted: String in ["content", "happy", "surprised", "sleepy"]:
		if not moods.has(wanted):
			failures.append("mood '%s' is missing from available_faces() %s" % [wanted, str(moods)])
	if bool(buddy.call("set_face", "furious")):
		failures.append("set_face() accepted a mood outside the vocabulary")

	var face: RefCounted = buddy.get("_face")
	var manifest: Dictionary = face.get("_manifest")
	buddy.call("set_face", "content")
	var base: Image = (face.call("canvas") as Image).duplicate()
	for mood: String in ["happy", "surprised", "sleepy"]:
		if not bool(buddy.call("set_face", mood)):
			failures.append("set_face('%s') returned false" % mood)
			continue
		if String(buddy.call("get_shown_face")) != mood:
			failures.append("get_shown_face() is '%s' after set_face('%s')"
					% [String(buddy.call("get_shown_face")), mood])
		var shown: Image = face.call("canvas")
		var changed: int = 0
		var outside: int = 0
		var rects: Array = []
		for layer: String in manifest["moods"][mood]:
			rects.append(face.call("layer_rect", layer))
		for y: int in range(0, base.get_height(), 2):
			for x: int in range(0, base.get_width(), 2):
				if shown.get_pixel(x, y).is_equal_approx(base.get_pixel(x, y)):
					continue
				var inside: bool = false
				for rect: Rect2i in rects:
					if rect.has_point(Vector2i(x, y)):
						inside = true
						break
				if inside:
					changed += 1
				else:
					outside += 1
		if changed == 0:
			failures.append("mood '%s' changed no texel of the atlas" % mood)
		if outside > 0:
			failures.append("mood '%s' wrote %d texels outside its layers' rects" % [mood, outside])
	# Back to the resting face restores the atlas to the pixel.
	buddy.call("set_face", "content")
	var restored: Image = face.call("canvas")
	for y: int in range(0, base.get_height(), 3):
		for x: int in range(0, base.get_width(), 3):
			if not restored.get_pixel(x, y).is_equal_approx(base.get_pixel(x, y)):
				failures.append("set_face('content') did not restore the atlas at (%d, %d)" % [x, y])
				return failures
	return failures


## -- 4. the blink -------------------------------------------------------------------

func _test_blink(buddy: Node3D):
	var failures: Array = []
	buddy.call("set_face", "content")
	buddy.call("set_blinking", true)
	if bool(buddy.call("are_eyes_closed")):
		failures.append("eyes start closed")
	buddy.call("blink_now")
	if not bool(buddy.call("are_eyes_closed")):
		failures.append("blink_now() did not close the eyes")
	if String(buddy.call("get_shown_face")) != "content":
		failures.append("a blink changed the mood")
	buddy.call("blink_now")
	if bool(buddy.call("are_eyes_closed")):
		failures.append("the second blink_now() did not reopen the eyes")
	# The blink is paused while the mood itself closes the eyes.
	buddy.call("set_face", "sleepy")
	if not bool(buddy.call("are_eyes_closed")):
		failures.append("'sleepy' should report the eyes closed")
	buddy.call("blink_now")
	if not bool(buddy.call("are_eyes_closed")) or String(buddy.call("get_shown_face")) != "sleepy":
		failures.append("a blink during 'sleepy' opened the eyes or changed the mood")
	buddy.call("set_face", "content")
	if bool(buddy.call("are_eyes_closed")):
		failures.append("leaving 'sleepy' left the eyes shut")
	# Switching blinking off mid-blink reopens.
	buddy.call("blink_now")
	buddy.call("set_blinking", false)
	if bool(buddy.call("are_eyes_closed")):
		failures.append("set_blinking(false) left the eyes shut")
	buddy.call("set_blinking", true)
	# Cadence constants: shut briefly, gaps of a few seconds.
	if Buddy.BLINK_CLOSED_SEC > 0.2 or Buddy.BLINK_CLOSED_SEC < 0.05:
		failures.append("BLINK_CLOSED_SEC %.2f is not a blink" % Buddy.BLINK_CLOSED_SEC)
	if Buddy.BLINK_GAP_MIN_SEC < 2.0 or Buddy.BLINK_GAP_MAX_SEC > 8.0 \
			or Buddy.BLINK_GAP_MIN_SEC >= Buddy.BLINK_GAP_MAX_SEC:
		failures.append("blink gap %.1f..%.1f s is outside the 3-6 s brief"
				% [Buddy.BLINK_GAP_MIN_SEC, Buddy.BLINK_GAP_MAX_SEC])
	return failures


## -- 5. an action wears a face and hands it back --------------------------------------

func _test_action_faces(buddy: Node3D):
	var failures: Array = []
	buddy.call("set_face", "content")
	# A HELD action keeps its face until released (a one-shot completes at once
	# out of the tree, so its face is on and off inside the call).
	buddy.call("play_action", "sleep")
	if String(buddy.call("get_shown_face")) != "sleepy":
		failures.append("play_action('sleep') should show 'sleepy', got '%s'"
				% String(buddy.call("get_shown_face")))
	if String(buddy.call("get_face")) != "content":
		failures.append("an action's face must not overwrite the RESTING face")
	buddy.call("release_action")
	if String(buddy.call("get_shown_face")) != "content":
		failures.append("release_action() should hand the resting face back, got '%s'"
				% String(buddy.call("get_shown_face")))
	for action: String in Buddy.ACTION_FACES.keys():
		if not Buddy.ACTION_FACES[action] in ["happy", "surprised", "sleepy", "content"]:
			failures.append("ACTION_FACES['%s'] names an unknown mood" % action)
	return failures


## -- 6. the hair sway: on the head bone, tiny, and two periods ------------------------

func _test_hair_sway(buddy: Node3D):
	var failures: Array = []
	var sway: SkeletonModifier3D = buddy.call("get_hair_sway")
	if sway == null:
		return ["no hair sway modifier on the rigged skeleton"]
	if sway.get_parent() != buddy.call("get_skeleton"):
		failures.append("the hair sway must be a modifier under the skeleton")
	var peak: float = 0.0
	for k: int in range(200):
		var a: Vector2 = HairSway.angles_at(float(k) * 0.05)
		peak = maxf(peak, maxf(absf(a.x), absf(a.y)))
	if peak > 0.6:
		failures.append("hair sway peaks at %.2f degrees; the face would visibly wobble" % peak)
	if peak < 0.2:
		failures.append("hair sway peaks at %.2f degrees; nothing would move" % peak)
	if is_equal_approx(HairSway.TILT_PERIOD_SEC, HairSway.TURN_PERIOD_SEC):
		failures.append("both sway sines share a period; it would read as a metronome")
	# Applying it rotates the head and nothing else.
	var skeleton: Skeleton3D = buddy.call("get_skeleton")
	var head: int = skeleton.find_bone(HairSway.HEAD_BONE)
	skeleton.reset_bone_poses()
	var before: Quaternion = skeleton.get_bone_pose_rotation(head)
	var neck_before: Quaternion = skeleton.get_bone_pose_rotation(skeleton.get_bone_parent(head))
	sway.call("step", 0.675)   # a quarter of the tilt period: the tilt's peak
	var turned: float = rad_to_deg(before.angle_to(skeleton.get_bone_pose_rotation(head)))
	if turned < 0.2 or turned > 0.8:
		failures.append("one sway step turned the head %.2f degrees; expected ~0.4" % turned)
	if not neck_before.is_equal_approx(skeleton.get_bone_pose_rotation(skeleton.get_bone_parent(head))):
		failures.append("the hair sway moved the neck; it must touch the head bone only")
	skeleton.reset_bone_poses()
	return failures


## -- helpers ------------------------------------------------------------------------------

## The bone's global pose chained by hand: out of the tree the skeleton never
## runs its own update, so `get_bone_global_pose()` would report the rest.
static func _global(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var t := Transform3D()
	var b: int = bone
	while b != -1:
		var local := Transform3D(Basis(skeleton.get_bone_pose_rotation(b)),
				skeleton.get_bone_pose_position(b))
		t = local * t
		b = skeleton.get_bone_parent(b)
	return t


static func _delta(skeleton: Skeleton3D, bone: int) -> Quaternion:
	return skeleton.get_bone_pose_rotation(bone) \
			* skeleton.get_bone_rest(bone).basis.get_rotation_quaternion().inverse()
