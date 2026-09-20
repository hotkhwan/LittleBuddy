extends RefCounted

## Aliz's TutorFace (docs/ALIZ_TUTOR_CONTRACTS.md): expressions, the talking
## mouth, the lip sync pipeline and the upper-body gestures -- on the real
## wrapper, the real atlas and the real skeleton, headless and out of the
## tree, the way `test_aliz_life.gd` measures her.
##
## Measured, not asserted by constant: expressions are judged by the texels
## the compositor uploads, the mouth by the frame sequence a synthetic
## envelope produces (printed, because the brief asked for the numbers), the
## gestures by bone deltas read back off the skeleton mid-clip.
##
## What is deliberately NOT pinned: exact angles and exact texel counts, so
## the person tuning a nod by eye does not have to edit a test to do it. What
## IS pinned: each expression changes the face where it claims to and nowhere
## else; the blink still overlays; the mouth opens with the envelope, shuts
## within 120 ms of silence and never flickers; every gesture moves the bones
## the brief names, for the seconds it promises, and is refused while she
## walks; and nothing here disturbs the idle, the carry pose or the moods.

const Buddy := preload("res://scripts/characters/buddy/pink_girl_buddy.gd")
const LipSync := preload("res://scripts/characters/buddy/buddy_lip_sync.gd")
const Mouth := preload("res://scripts/characters/buddy/buddy_mouth.gd")
const GestureClips := preload("res://scripts/characters/buddy/buddy_gesture_clips.gd")
const GestureLayer := preload("res://scripts/characters/buddy/buddy_gesture_layer.gd")

const EXPRESSIONS: Array[String] = ["neutral", "listening", "thinking", "happy", "encouraging", "smile"]
const GESTURES: Array[String] = ["nod", "tilt", "point", "clap", "wave"]
const STEP: float = 1.0 / 60.0


func test_name() -> String:
	return "aliz_tutor_face"


func run():
	var failures: Array = []
	var buddy: Node3D = Buddy.new()
	buddy.call("build")
	if not bool(buddy.call("is_model_available")):
		buddy.free()
		return ["the rigged Aliz asset is not in this build; nothing here can be measured"]
	failures.append_array(_test_expressions(buddy))
	failures.append_array(_test_blink_overlays_expressions(buddy))
	failures.append_array(_test_mouth_follows_envelope(buddy))
	failures.append_array(_test_lip_sync_pipeline(buddy))
	failures.append_array(_test_tts_pseudo_envelope())
	failures.append_array(_test_gestures(buddy))
	failures.append_array(_test_gestures_refused_while_walking(buddy))
	failures.append_array(_test_listening_pose(buddy))
	failures.append_array(_test_nothing_else_disturbed(buddy))
	buddy.free()
	return failures


## -- 1. expressions switch the atlas regions they claim ------------------------------

func _test_expressions(buddy: Node3D):
	var failures: Array = []
	if not bool(buddy.call("has_face_moods")):
		return ["the shipped atlas has no mood patches the compositor trusts"]
	var available: Array = buddy.call("available_expressions")
	for name: String in EXPRESSIONS:
		if not available.has(name):
			failures.append("expression '%s' is missing from available_expressions() %s"
					% [name, str(available)])
	if not failures.is_empty():
		return failures
	if bool(buddy.call("set_expression", "furious")):
		failures.append("set_expression() accepted a name outside the vocabulary")
	if bool(buddy.call("set_expression", "content")):
		failures.append("set_expression() accepted a legacy mood name; that is set_face()'s job")

	var face: RefCounted = buddy.get("_face")
	var manifest: Dictionary = face.get("_manifest")
	buddy.call("set_expression", "neutral")
	var neutral: Image = (face.call("canvas") as Image).duplicate()
	# neutral IS the base: the same texels as `content`.
	buddy.call("set_face", "content")
	if not _same(neutral, face.call("canvas"), 3):
		failures.append("'neutral' and 'content' differ on the atlas; they must be one base")

	var canvases: Dictionary = {}
	for name: String in EXPRESSIONS:
		if name == "neutral":
			continue
		if not bool(buddy.call("set_expression", name)):
			failures.append("set_expression('%s') returned false" % name)
			continue
		if String(buddy.call("get_expression")) != name \
				or String(buddy.call("get_shown_face")) != name:
			failures.append("after set_expression('%s'): get_expression()='%s' get_shown_face()='%s'"
					% [name, String(buddy.call("get_expression")),
					String(buddy.call("get_shown_face"))])
		var shown: Image = face.call("canvas")
		canvases[name] = shown.duplicate()
		var rects: Array = []
		for layer: String in manifest["moods"][name]:
			for island: Rect2i in face.call("layer_rects", layer):
				rects.append(island)
		var counted: Array = _count_changes(neutral, shown, rects)
		if int(counted[0]) < 40:
			failures.append("expression '%s' changed only %d texels of the atlas; it would not read"
					% [name, int(counted[0])])
		if int(counted[1]) > 0:
			failures.append("expression '%s' wrote %d texels outside its layers' island rects"
					% [name, int(counted[1])])
	# The six are six different faces.
	var names: Array = canvases.keys()
	for i: int in range(names.size()):
		for j: int in range(i + 1, names.size()):
			if _same(canvases[names[i]], canvases[names[j]], 2):
				failures.append("expressions '%s' and '%s' are texel-identical" % [names[i], names[j]])
	# The eye expressions touch the eyes, the mouth expressions the mouth, at
	# the probe texels the manifest itself names (iris probes are eyes).
	var iris: Array = []
	for probe: Dictionary in manifest["probes"]:
		if String(probe.get("kind", "")) == "iris":
			iris.append(Vector2i(int(probe["x"]), int(probe["y"])))
	var listening_eyes: bool = false
	var smile_eyes: bool = false
	for p: Vector2i in iris:
		for dy: int in range(-6, 7):
			for dx: int in range(-6, 7):
				var q: Vector2i = p + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= neutral.get_width() or q.y >= neutral.get_height():
					continue
				if not (canvases["listening"] as Image).get_pixel(q.x, q.y).is_equal_approx(
						neutral.get_pixel(q.x, q.y)):
					listening_eyes = true
				if not (canvases["smile"] as Image).get_pixel(q.x, q.y).is_equal_approx(
						neutral.get_pixel(q.x, q.y)):
					smile_eyes = true
	if not listening_eyes:
		failures.append("'listening' left every texel within 6 of the iris probes untouched; the eyes did not widen")
	if smile_eyes:
		failures.append("'smile' changed texels at the iris probes; a smile is a mouth")
	buddy.call("set_expression", "neutral")
	if not _same(neutral, face.call("canvas"), 3):
		failures.append("set_expression('neutral') did not restore the atlas")
	return failures


## -- 2. the blink overlays every expression --------------------------------------------

func _test_blink_overlays_expressions(buddy: Node3D):
	var failures: Array = []
	var face: RefCounted = buddy.get("_face")
	var blink_layer: String = String(face.call("blink_layer"))
	var blink_rects: Array = face.call("layer_rects", blink_layer)
	buddy.call("set_blinking", true)
	for name: String in ["listening", "thinking", "encouraging"]:
		buddy.call("set_expression", name)
		var open: Image = (face.call("canvas") as Image).duplicate()
		buddy.call("blink_now")
		if not bool(buddy.call("are_eyes_closed")):
			failures.append("blink_now() did not close the eyes over '%s'" % name)
		if String(buddy.call("get_shown_face")) != name:
			failures.append("a blink over '%s' changed the expression to '%s'"
					% [name, String(buddy.call("get_shown_face"))])
		var counted: Array = _count_changes(open, face.call("canvas"), blink_rects)
		if int(counted[0]) < 40:
			failures.append("the blink over '%s' changed only %d texels" % [name, int(counted[0])])
		buddy.call("blink_now")
		if bool(buddy.call("are_eyes_closed")):
			failures.append("the second blink_now() did not reopen the eyes over '%s'" % name)
		if not _same(open, face.call("canvas"), 2):
			failures.append("reopening the eyes did not restore '%s' to the texel" % name)
	buddy.call("set_expression", "neutral")
	return failures


## -- 3. the mouth follows a synthetic envelope: rising, closing, never flickering ---------

func _test_mouth_follows_envelope(buddy: Node3D):
	var failures: Array = []
	var face: RefCounted = buddy.get("_face")
	var mouth: Node = buddy.call("get_mouth")
	if mouth == null:
		return ["no mouth smoother under the model"]
	if int(face.call("mouth_frame_count")) != 4:
		failures.append("the atlas offers %d mouth frames; the brief asks for 4 (closed, small, mid, open)"
				% int(face.call("mouth_frame_count")))
	buddy.call("set_expression", "happy")
	var happy: Image = (face.call("canvas") as Image).duplicate()
	buddy.call("set_speaking", true)
	if not bool(buddy.call("is_speaking")):
		failures.append("set_speaking(true) did not mark her speaking")

	# A rising ramp over 0.3 s, a hold at 1.0, then silence: the frame index must
	# climb monotonically to 3, then fall to 0 within 120 ms of the silence.
	var log: Array = []      # [time, target, amount, frame]
	var changes: Array = []  # [time, frame]
	var last_frame: int = int(buddy.call("get_mouth_frame"))
	var t: float = 0.0
	var silence_at: float = -1.0
	var closed_at: float = -1.0
	var max_frame: int = 0
	var monotone_up: bool = true
	var frames_seen: Array = [last_frame]
	for k: int in range(90):
		var target: float
		if t < 0.3:
			target = t / 0.3
		elif t < 0.75:
			target = 1.0
		else:
			target = 0.0
			if silence_at < 0.0:
				silence_at = t
		buddy.call("set_mouth_open", target)
		buddy.call("step_mouth", STEP)
		t += STEP
		var frame: int = int(buddy.call("get_mouth_frame"))
		var amount: float = float(buddy.call("get_mouth_open"))
		log.append([t, target, amount, frame])
		if frame != last_frame:
			changes.append([t, frame])
			if silence_at < 0.0 and frame < last_frame:
				monotone_up = false
			if not frames_seen.has(frame):
				frames_seen.append(frame)
			last_frame = frame
		max_frame = maxi(max_frame, frame)
		if silence_at >= 0.0 and frame == 0 and closed_at < 0.0:
			closed_at = t
	print("      mouth proof -- synthetic envelope (ramp 0.3 s, hold, silence at %.2f s):" % silence_at)
	for entry: Array in log:
		var at: float = float(entry[0])
		if absf(fmod(at + 0.0001, 0.05)) < STEP * 0.99 or at < 0.1:
			print("        t=%.3fs  target %.2f  amount %.2f  frame %d"
					% [at, float(entry[1]), float(entry[2]), int(entry[3])])
	print("        frame changes: %s" % str(changes))
	if max_frame != 3:
		failures.append("a full-scale envelope reached frame %d, not the open frame 3" % max_frame)
	if not monotone_up:
		failures.append("the frame index fell while the envelope was rising; that is flicker")
	if frames_seen.size() < 4:
		failures.append("the ramp showed frames %s; all four should appear" % str(frames_seen))
	if closed_at < 0.0:
		failures.append("the mouth never closed after the silence")
	elif closed_at - silence_at > 0.12 + STEP * 0.5:
		failures.append("the mouth closed %.0f ms after the silence began; the contract allows 120"
				% ((closed_at - silence_at) * 1000.0))
	# No two changes to a NON-closed frame closer than the hold (closing is exempt).
	for i: int in range(1, changes.size()):
		var gap: float = float(changes[i][0]) - float(changes[i - 1][0])
		if int(changes[i][1]) != 0 and gap < Mouth.MIN_FRAME_HOLD_SEC - STEP * 0.5:
			failures.append("frame changed to %d only %.0f ms after the previous change"
					% [int(changes[i][1]), gap * 1000.0])
	# The frames actually reach the atlas, and the teeth of `happy` go with them.
	buddy.call("set_mouth_open", 1.0)
	for _k: int in range(12):
		buddy.call("step_mouth", STEP)
	if int(buddy.call("get_mouth_frame")) != 3:
		failures.append("holding 1.0 for 200 ms left the mouth at frame %d" % int(buddy.call("get_mouth_frame")))
	var talking: Image = face.call("canvas")
	var talk_rects: Array = face.call("layer_rects", String(face.call("mouth_frame_layer", 3)))
	var counted: Array = _count_changes(happy, talking, talk_rects)
	if int(counted[0]) < 40:
		failures.append("the open talk frame changed only %d texels over 'happy'" % int(counted[0]))
	if int(counted[1]) > 0:
		failures.append("the open talk frame wrote %d texels outside its island rects" % int(counted[1]))
	if int(face.call("current_mouth_frame")) != 3:
		failures.append("the compositor shows frame %d while the smoother is at 3"
				% int(face.call("current_mouth_frame")))
	# set_speaking(false) restores the expression's own mouth, to the texel.
	buddy.call("set_speaking", false)
	if int(buddy.call("get_mouth_frame")) != 0 or bool(buddy.call("is_speaking")):
		failures.append("set_speaking(false) did not close the mouth at once")
	if not _same(happy, face.call("canvas"), 2):
		failures.append("set_speaking(false) did not restore 'happy' to the texel")
	buddy.call("set_expression", "neutral")
	return failures


## -- 4. the lip sync source: RMS -> AGC -> amount, on a synthetic tone ----------------------

func _test_lip_sync_pipeline(buddy: Node3D):
	var failures: Array = []
	var source: Node = LipSync.new()
	source.call("set_target", buddy)
	# 1.5 s at 48 kHz, speech-shaped and QUIET (peak 0.05 of full scale, as a
	# TTS voice through a mixed bus is): 0.3 s silence, five syllable bumps of
	# 120 ms with 60 ms gaps on a 220 Hz tone, then silence from 0.9 s.
	var rate: float = 48000.0
	var samples := PackedFloat32Array()
	var n: int = int(rate * 1.5)
	samples.resize(n)
	var bump_starts: Array = [0.3, 0.48, 0.66, 0.84, 1.02]
	var bump_len: float = 0.12
	var heights: Array = [0.05, 0.035, 0.05, 0.04, 0.045]
	for i: int in range(n):
		var t: float = float(i) / rate
		var env: float = 0.0
		for b: int in range(bump_starts.size()):
			var start: float = float(bump_starts[b])
			if t >= start and t < start + bump_len:
				env = float(heights[b]) * 0.5 * (1.0 - cos(TAU * (t - start) / bump_len))
		samples[i] = env * sin(TAU * 220.0 * t)
	var last_sound: float = float(bump_starts[bump_starts.size() - 1]) + bump_len
	buddy.call("set_speaking", true)
	var amounts: PackedFloat32Array = source.call("drive_from_envelope", samples, rate)
	if amounts.size() < 88:
		failures.append("drive_from_envelope returned %d chunks for 1.5 s; expected ~90" % amounts.size())
		source.free()
		return failures
	print("      lip sync proof -- amounts against five quiet syllable bumps (peak 0.05 full scale, 220 Hz):")
	var line: String = ""
	for k: int in range(0, amounts.size(), 3):
		line += "%.2f:%.2f " % [float(k) * STEP, amounts[k]]
		if (k / 3) % 10 == 9:
			print("        " + line)
			line = ""
	if not line.is_empty():
		print("        " + line)
	# Silence in, nothing out.
	var lead: float = 0.0
	for k: int in range(0, int(0.3 / STEP)):
		lead = maxf(lead, amounts[k])
	if lead > 0.0:
		failures.append("the source opened the mouth (%.2f) during the leading silence" % lead)
	# Every bump: the amount at its crest is above the amount at its foot, and
	# the gaps between bumps come back down -- the envelope's shape passes through.
	var peak: float = 0.0
	for b: int in range(bump_starts.size()):
		var start: float = float(bump_starts[b])
		var foot: float = amounts[int((start + 0.02) / STEP)]
		var crest: float = amounts[int((start + bump_len * 0.5) / STEP)]
		var gap: float = amounts[int((start + bump_len + 0.03) / STEP)]
		peak = maxf(peak, crest)
		if crest <= foot:
			failures.append("bump %d: crest %.2f is not above its foot %.2f; the envelope does not pass through" % [b, crest, foot])
		if gap >= crest:
			failures.append("bump %d: the gap after it (%.2f) is not below its crest (%.2f)" % [b, gap, crest])
	# Quiet input still opens the mouth wide: the AGC normalises 0.05 to ~1.
	if peak < 0.6:
		failures.append("a 0.05 full-scale voice only opened the mouth to %.2f; the AGC is not normalising" % peak)
	# Silence out: zero within 120 ms of the last sound.
	var zero_by: int = int((last_sound + 0.12) / STEP)
	for k: int in range(zero_by, amounts.size()):
		if amounts[k] > 0.0:
			failures.append("amount %.2f at t=%.2f s, more than 120 ms after the voice stopped"
					% [amounts[k], float(k) * STEP])
			break
	if int(buddy.call("get_mouth_frame")) != 0:
		failures.append("after the buffer ended the mouth frame is %d, not closed"
				% int(buddy.call("get_mouth_frame")))
	# Attaching a bus adds a capture effect and removes it again.
	var master_effects: int = AudioServer.get_bus_effect_count(0)
	if not bool(source.call("attach_bus", "Master")):
		failures.append("attach_bus('Master') returned false")
	elif AudioServer.get_bus_effect_count(0) != master_effects + 1 or not bool(source.call("is_capturing")):
		failures.append("attach_bus did not add one AudioEffectCapture to the bus")
	if bool(source.call("attach_bus", "NoSuchBus")):
		failures.append("attach_bus accepted a bus that does not exist")
	source.call("detach")
	if AudioServer.get_bus_effect_count(0) != master_effects:
		failures.append("detach() left the capture effect on the bus")
	# Never a fixed timer: the source has no Timer child and the mouth is only
	# ever moved through set_mouth_open.
	for child: Node in source.get_children():
		if child is Timer:
			failures.append("the lip sync source runs a Timer; the contract says never a fixed timer")
	buddy.call("set_speaking", false)
	source.free()
	return failures


## -- 5. the TtsService fallback: a text-derived pseudo-envelope that ends with the speech ---

func _test_tts_pseudo_envelope():
	var failures: Array = []
	var env: PackedFloat32Array = LipSync.pseudo_envelope_for("Can you say milk?", 1.0)
	if env.is_empty():
		return ["pseudo_envelope_for() returned nothing for a sentence"]
	# Four words, five syllables: bumps separated by gaps; the whole thing about
	# 1.4-2.2 s at rate 1.0 (TtsService estimates 4 words at 2.5 wps = 1.6 s).
	var seconds: float = float(env.size()) / LipSync.PSEUDO_SAMPLE_RATE
	if seconds < 1.2 or seconds > 2.4:
		failures.append("the pseudo-envelope for 4 words lasts %.2f s; expected ~1.6" % seconds)
	var bumps: int = 0
	var above: bool = false
	var peak: float = 0.0
	var low: float = 1.0
	for v: float in env:
		if v > 0.05 and not above:
			bumps += 1
		above = v > 0.05
		peak = maxf(peak, v)
	if bumps < 4 or bumps > 7:
		failures.append("the pseudo-envelope has %d syllable bumps for 'Can you say milk?'; expected 4-7" % bumps)
	if peak < 0.5 or peak > 1.0:
		failures.append("pseudo-envelope peak %.2f is outside 0.5..1.0" % peak)
	# Bump heights vary (not a metronome): at least two distinct local maxima.
	var maxima: Array = []
	for i: int in range(1, env.size() - 1):
		if env[i] > env[i - 1] and env[i] >= env[i + 1] and env[i] > 0.1:
			if not maxima.has(snappedf(env[i], 0.01)):
				maxima.append(snappedf(env[i], 0.01))
	if maxima.size() < 2:
		failures.append("every pseudo-envelope bump has the same height; it would read as a metronome")
	if LipSync.pseudo_envelope_for("", 1.0).size() != 0:
		failures.append("an empty text produced an envelope")
	# A faster rate is shorter.
	var fast: PackedFloat32Array = LipSync.pseudo_envelope_for("Can you say milk?", 1.5)
	if fast.size() >= env.size():
		failures.append("rate 1.5 did not shorten the pseudo-envelope")
	# The source follows a stand-in service's signals and stops on finish.
	var stub := TtsStub.new()
	var sink := MouthSink.new()
	var source: Node = LipSync.new()
	source.call("set_target", sink)
	if not bool(source.call("attach_tts", stub)):
		failures.append("attach_tts() refused a node with speech_started/speech_finished")
	stub.speech_started.emit("Hello there, friend!")
	if not bool((source.call("describe") as Dictionary)["pseudoActive"]):
		failures.append("speech_started did not arm the pseudo-envelope")
	# Drive its frame loop by hand at a time inside the first bump.
	var moved: float = 0.0
	for _k: int in range(8):
		source.call("_process", STEP)
		moved = maxf(moved, sink.last)
	if moved <= 0.0:
		failures.append("the pseudo-envelope never moved the mouth after speech_started")
	stub.speech_finished.emit("Hello there, friend!")
	if sink.last != 0.0 or bool((source.call("describe") as Dictionary)["pseudoActive"]):
		failures.append("speech_finished did not zero the mouth (%.2f) and stop the envelope" % sink.last)
	source.free()
	stub.free()
	sink.free()
	return failures


class TtsStub extends Node:
	signal speech_started(text: String)
	signal speech_finished(text: String)
	func is_speaking() -> bool:
		return true
	func get_speech_rate() -> float:
		return 1.0
	func is_playing_recording() -> bool:
		return false


class MouthSink extends Node:
	var last: float = -1.0
	func set_mouth_open(amount: float) -> void:
		last = amount


## -- 6. gestures: durations, bone deltas, blend-out ------------------------------------------

func _test_gestures(buddy: Node3D):
	var failures: Array = []
	var layer: SkeletonModifier3D = buddy.call("get_gesture_layer")
	var skeleton: Skeleton3D = buddy.call("get_skeleton")
	if layer == null or skeleton == null:
		return ["no gesture layer under the rigged skeleton"]
	if layer.get_parent() != skeleton:
		failures.append("the gesture layer must be a modifier under the skeleton")
	var available: Array = buddy.call("available_gestures")
	for name: String in GESTURES:
		if not available.has(name):
			failures.append("gesture '%s' missing from available_gestures() %s" % [name, str(available)])
	if float(buddy.call("play_gesture", "shrug")) != 0.0:
		failures.append("play_gesture() accepted a name outside the vocabulary")
	if not failures.is_empty():
		return failures

	var head: int = skeleton.find_bone(GestureClips.HEAD)
	var head_end: int = skeleton.find_bone("head_end")
	var hand_r: int = skeleton.find_bone(GestureClips.HAND_R)
	var hand_l: int = skeleton.find_bone(GestureClips.HAND_L)
	if head_end == -1:
		return ["the skeleton has no head_end bone to measure the head's direction with"]
	buddy.call("set_locomotion", 0.0)
	print("      gesture proof -- bone deltas mid-clip on the real skeleton (cm, degrees):")
	for name: String in GESTURES:
		skeleton.reset_bone_poses()
		var hand_rest: Vector3 = _global(skeleton, hand_r).origin
		var hand_l_rest: Vector3 = _global(skeleton, hand_l).origin
		var expected: float = GestureClips.duration_of(name)
		var got: float = float(buddy.call("play_gesture", name))
		if absf(got - expected) > 0.001:
			failures.append("play_gesture('%s') returned %.2f s; the brief says %.2f" % [name, got, expected])
		if String(buddy.call("get_current_gesture")) != name:
			failures.append("get_current_gesture() is '%s' after play_gesture('%s')"
					% [String(buddy.call("get_current_gesture")), name])
		# Sample the clip at the moment it should be most visible.
		var peak_at: Dictionary = {"nod": 0.2, "tilt": 0.55, "point": 0.7, "clap": 0.35, "wave": 0.42}
		var t: float = 0.0
		var head_pitch: float = 0.0
		var head_roll: float = 0.0
		var hand_lift: float = 0.0
		var hand_l_lift: float = 0.0
		var pulse_min: float = 1e9
		var pulse_max: float = -1e9
		var swing_min: float = 1e9
		var swing_max: float = -1e9
		while t < float(peak_at[name]) - STEP * 0.5:
			skeleton.reset_bone_poses()
			layer.call("step", STEP)
			t += STEP
			if name == "clap":
				# Hands' separation across x pulses inward twice.
				var sep: float = absf(_global(skeleton, hand_r).origin.x - _global(skeleton, hand_l).origin.x)
				pulse_min = minf(pulse_min, sep)
				pulse_max = maxf(pulse_max, sep)
			if name == "wave":
				swing_min = minf(swing_min, _global(skeleton, hand_r).origin.x)
				swing_max = maxf(swing_max, _global(skeleton, hand_r).origin.x)
		var tipped: Vector2 = _head_tip(skeleton, head, head_end)
		head_pitch = tipped.x
		head_roll = tipped.y
		hand_lift = _global(skeleton, hand_r).origin.y - hand_rest.y
		hand_l_lift = _global(skeleton, hand_l).origin.y - hand_l_rest.y
		var hand_out: float = _global(skeleton, hand_r).origin.x - hand_rest.x
		print("        %-5s t=%.2fs  head pitch %+.1f roll %+.1f  right hand lift %+.1f cm out %+.1f cm  left hand lift %+.1f cm  weight %.2f"
				% [name, t, head_pitch, head_roll, hand_lift, -hand_out, hand_l_lift, float(layer.call("weight"))])
		match name:
			"nod":
				if absf(head_pitch) < 6.0 or absf(head_pitch) > 16.0:
					failures.append("nod: head pitch %.1f degrees at the first dip; expected ~12" % head_pitch)
				if absf(hand_lift) > 0.5:
					failures.append("nod moved the right hand %.1f cm; a nod is the head only" % hand_lift)
			"tilt":
				if absf(head_roll) < 8.0 or absf(head_roll) > 16.0:
					failures.append("tilt: head roll %.1f degrees while held; expected ~12" % head_roll)
			"point":
				if hand_lift < 15.0:
					failures.append("point: the right hand rose only %.1f cm; it should reach shoulder height" % hand_lift)
				if -hand_out < 15.0:
					failures.append("point: the right hand moved %.1f cm outward; it should point to her right" % -hand_out)
				if absf(hand_l_lift) > 0.5:
					failures.append("point moved the LEFT hand %.1f cm" % hand_l_lift)
			"clap":
				if hand_lift < 15.0 or hand_l_lift < 15.0:
					failures.append("clap: hands rose %.1f / %.1f cm; both should come up" % [hand_lift, hand_l_lift])
				if pulse_max - pulse_min < 4.0:
					failures.append("clap: the hands' separation only varied %.1f cm; no clap" % (pulse_max - pulse_min))
			"wave":
				if hand_lift < 25.0:
					failures.append("wave: the right hand rose only %.1f cm; it should be up" % hand_lift)
				if absf(hand_l_lift) > 0.5:
					failures.append("wave moved the LEFT hand %.1f cm" % hand_l_lift)
		# The second half of the clap and the wave: the pulse / swing keeps going.
		if name == "clap" or name == "wave":
			var lo: float = 1e9
			var hi: float = -1e9
			while t < expected - 0.25:
				skeleton.reset_bone_poses()
				layer.call("step", STEP)
				t += STEP
				var x: float = _global(skeleton, hand_r).origin.x
				lo = minf(lo, x)
				hi = maxf(hi, x)
			if hi - lo < 3.0:
				failures.append("%s: the right hand moved only %.1f cm sideways through the clip; nothing swings" % [name, hi - lo])
		# It ends on time, blended out, and hands the bones back.
		var finished: Array = []
		var on_finished: Callable = func(ended: String) -> void: finished.append(ended)
		layer.connect("gesture_finished", on_finished)
		var guard: int = 0
		while bool(layer.call("is_playing")) and guard < 400:
			skeleton.reset_bone_poses()
			layer.call("step", STEP)
			t += STEP
			guard += 1
		layer.disconnect("gesture_finished", on_finished)
		if finished != [name]:
			failures.append("gesture '%s' did not report gesture_finished exactly once: %s" % [name, str(finished)])
		if t > expected + 0.05:
			failures.append("gesture '%s' ran %.2f s for a %.2f s clip" % [name, t, expected])
		if float(layer.call("weight")) > 0.0:
			failures.append("gesture '%s' ended with blend weight %.2f; it must fade to 0" % [name, float(layer.call("weight"))])
		skeleton.reset_bone_poses()
		layer.call("step", STEP)
		var rest_pose: Quaternion = skeleton.get_bone_rest(head).basis.get_rotation_quaternion()
		# 0.1 degrees: the rest basis is not exactly orthonormal, and the
		# quaternion round trip through it leaves ~0.04 degrees of noise.
		if rad_to_deg(rest_pose.angle_to(skeleton.get_bone_pose_rotation(head))) > 0.1:
			failures.append("after '%s' the head is still %.2f degrees off rest" % [name, rad_to_deg(rest_pose.angle_to(skeleton.get_bone_pose_rotation(head)))])
	# The blend-out is 0.2 s: stop() mid-gesture and the weight is 0 within it.
	buddy.call("play_gesture", "tilt")
	for _k: int in range(30):
		skeleton.reset_bone_poses()
		layer.call("step", STEP)
	if float(layer.call("weight")) < 0.99:
		failures.append("tilt is not fully blended in after 0.5 s (weight %.2f)" % float(layer.call("weight")))
	buddy.call("stop_gesture")
	var fade: float = 0.0
	while bool(layer.call("is_playing")) and fade < 1.0:
		skeleton.reset_bone_poses()
		layer.call("step", STEP)
		fade += STEP
	if fade > GestureLayer.FADE_OUT_SEC + STEP * 1.5:
		failures.append("stop_gesture() took %.2f s to blend out; the brief says 0.2" % fade)
	skeleton.reset_bone_poses()
	return failures


## -- 7. gestures refuse to start while she walks, and fade if she moves off ----------------

func _test_gestures_refused_while_walking(buddy: Node3D):
	var failures: Array = []
	var layer: SkeletonModifier3D = buddy.call("get_gesture_layer")
	var skeleton: Skeleton3D = buddy.call("get_skeleton")
	buddy.call("set_locomotion", 1.0)
	if float(buddy.call("play_gesture", "wave")) != 0.0 or bool(layer.call("is_playing")):
		failures.append("play_gesture('wave') started while walking at 1.0 m/s")
	buddy.call("set_locomotion", 0.05)
	if float(buddy.call("play_gesture", "nod")) <= 0.0:
		failures.append("play_gesture('nod') was refused at 0.05 m/s; the limit is 0.1")
	# Moving off mid-gesture fades it out rather than letting it fight the walk.
	buddy.call("set_locomotion", 0.6)
	var fade: float = 0.0
	while bool(layer.call("is_playing")) and fade < 1.0:
		skeleton.reset_bone_poses()
		layer.call("step", STEP)
		fade += STEP
	if fade > GestureLayer.FADE_OUT_SEC + STEP * 1.5:
		failures.append("a gesture kept playing %.2f s after locomotion started" % fade)
	buddy.call("set_locomotion", 0.0)
	# Arm gestures are refused while the carry pose holds the arms; the head is free.
	buddy.call("set_carry_pose", true)
	if float(buddy.call("play_gesture", "point")) != 0.0:
		failures.append("play_gesture('point') started while carrying")
	if float(buddy.call("play_gesture", "nod")) <= 0.0:
		failures.append("play_gesture('nod') was refused while carrying; the head is free")
	buddy.call("stop_gesture")
	buddy.call("set_carry_pose", false)
	for _k: int in range(20):
		skeleton.reset_bone_poses()
		layer.call("step", STEP)
	skeleton.reset_bone_poses()
	return failures


## -- 8. the listening lean-in ------------------------------------------------------------

func _test_listening_pose(buddy: Node3D):
	var failures: Array = []
	var layer: SkeletonModifier3D = buddy.call("get_gesture_layer")
	var skeleton: Skeleton3D = buddy.call("get_skeleton")
	var head: int = skeleton.find_bone(GestureClips.HEAD)
	skeleton.reset_bone_poses()
	var rest_head: Vector3 = _global(skeleton, head).origin
	buddy.call("set_listening_pose", true)
	if not bool(buddy.call("is_listening_pose")):
		failures.append("is_listening_pose() is false after set_listening_pose(true)")
	skeleton.reset_bone_poses()
	layer.call("step", STEP)
	var leaned: Vector3 = _global(skeleton, head).origin - rest_head
	print("        listening lean: head moved (%+.1f, %+.1f, %+.1f) cm" % [leaned.x, leaned.y, leaned.z])
	if leaned.z < 1.5 or leaned.z > 8.0:
		failures.append("the listening pose moved the head %.1f cm forward; expected a slight lean (2-8 cm)" % leaned.z)
	# A nod plays OVER the lean.
	var lean_pitch: float = _head_tip(skeleton, head, skeleton.find_bone("head_end")).x
	buddy.call("play_gesture", "nod")
	for _k: int in range(12):
		skeleton.reset_bone_poses()
		layer.call("step", STEP)
	var nod_pitch: float = _head_tip(skeleton, head, skeleton.find_bone("head_end")).x
	if absf(nod_pitch - lean_pitch) < 4.0:
		failures.append("a nod over the listening pose barely moved the head (%.1f degrees)"
				% (nod_pitch - lean_pitch))
	buddy.call("stop_gesture")
	buddy.call("set_listening_pose", false)
	for _k: int in range(40):
		skeleton.reset_bone_poses()
		layer.call("step", STEP)
	skeleton.reset_bone_poses()
	layer.call("step", STEP)
	var back: Vector3 = _global(skeleton, head).origin - rest_head
	if back.length() > 0.05:
		failures.append("after set_listening_pose(false) the head is still %.2f cm off rest" % back.length())
	return failures


## -- 9. nothing else moved: idle, carry pose, moods, the sealed hierarchy -----------------------

func _test_nothing_else_disturbed(buddy: Node3D):
	var failures: Array = []
	var player: AnimationPlayer = buddy.call("get_animation_player")
	for clip: String in ["idle", "walk", "run"]:
		if not player.has_animation(clip):
			failures.append("clip '%s' is gone from the player" % clip)
	for gesture: String in GESTURES:
		if player.has_animation(gesture):
			failures.append("gesture '%s' was merged into the AnimationPlayer; it must stay on the layer" % gesture)
	for mood: String in ["content", "happy", "surprised", "sleepy"]:
		if not (buddy.call("available_faces") as Array).has(mood):
			failures.append("legacy mood '%s' is gone" % mood)
	if buddy.call("get_carry_pose") == null or buddy.call("get_hair_sway") == null:
		failures.append("the carry pose or the hair sway modifier is missing")
	var children: Array = []
	for child: Node in buddy.get_children():
		children.append(String(child.name))
	if children != ["Model"]:
		failures.append("the wrapper's direct children are %s; the mouth and the lip sync must live under Model" % str(children))
	# The modifier order: carry pose, gesture layer, hair sway.
	var skeleton: Skeleton3D = buddy.call("get_skeleton")
	var order: Array = []
	for child: Node in skeleton.get_children():
		if child is SkeletonModifier3D:
			order.append(String(child.name))
	if order != ["CarryPose", "GestureLayer", "HairSway"]:
		failures.append("skeleton modifiers are %s; expected [CarryPose, GestureLayer, HairSway]" % str(order))
	return failures


## -- helpers ---------------------------------------------------------------------------------

## [inside, outside]: texels (every `stride`) that differ between `a` and `b`,
## split by whether they fall in one of `rects`.
static func _count_changes(a: Image, b: Image, rects: Array, stride: int = 1) -> Array:
	var inside: int = 0
	var outside: int = 0
	for y: int in range(0, a.get_height(), stride):
		for x: int in range(0, a.get_width(), stride):
			if a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				continue
			var hit: bool = false
			for rect: Rect2i in rects:
				if rect.has_point(Vector2i(x, y)):
					hit = true
					break
			if hit:
				inside += 1
			else:
				outside += 1
	return [inside, outside]


## (pitch, roll) of the head in degrees, from where `head_end` sits relative
## to `Head` against the rest: forward tip (chin down) is positive pitch,
## a tip toward her right (-x) is positive roll.
static func _head_tip(skeleton: Skeleton3D, head: int, head_end: int) -> Vector2:
	var rest_dir: Vector3 = (skeleton.get_bone_global_rest(head_end).origin
			- skeleton.get_bone_global_rest(head).origin).normalized()
	var now_dir: Vector3 = (_global(skeleton, head_end).origin
			- _global(skeleton, head).origin).normalized()
	var pitch: float = rad_to_deg(atan2(now_dir.z, now_dir.y) - atan2(rest_dir.z, rest_dir.y))
	var roll: float = rad_to_deg(atan2(-now_dir.x, now_dir.y) - atan2(-rest_dir.x, rest_dir.y))
	return Vector2(pitch, roll)


static func _same(a: Image, b: Image, stride: int) -> bool:
	for y: int in range(0, a.get_height(), stride):
		for x: int in range(0, a.get_width(), stride):
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				return false
	return true


static func _global(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var t := Transform3D()
	var b: int = bone
	while b != -1:
		var local := Transform3D(Basis(skeleton.get_bone_pose_rotation(b)),
				skeleton.get_bone_pose_position(b))
		t = local * t
		b = skeleton.get_bone_parent(b)
	return t
