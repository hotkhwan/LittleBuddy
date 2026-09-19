extends RefCounted

## The HUD's four presentation modes, and the one thing they exist to guarantee:
## **during a close-up, nothing the HUD draws crosses the middle of the screen.**
##
## The defect these guard against is recorded in `docs/HUD_PRESENTATION_PASS.md`
## and, before that, in `docs/WORLD_CAMERA_PASS.md` §7.1: four lines of text down
## the top third while the beat put a character dead centre. The evidence is
## `docs/shots/hud_feed_BEFORE_ipad.png` next to `hud_feed_AFTER_ipad.png`; these
## are what stop it coming back.
##
## Everything here is either pure (`hud_presentation.gd` takes Dictionaries and
## returns Dictionaries) or built out of tree, so the whole case runs headlessly.
## What it cannot prove is that the result LOOKS right -- that is what the
## screenshots are for, and they were looked at.

const Presentation := preload("res://scripts/ui/hud_presentation.gd")
const HouseHud := preload("res://scripts/gameplay/house_hud.gd")
const RoomCameraScript := preload("res://scripts/camera/room_camera.gd")

## The two shipped landscape sizes the brief names, plus the project's own 4:3
## reference. Every geometric rule below is checked at all three, because a rule
## that only holds at one aspect is not a rule.
const VIEWPORTS: Array[Vector2] = [
	Vector2(1334.0, 750.0),    # iPad landscape
	Vector2(2340.0, 1080.0),   # wide iPhone landscape
	Vector2(1366.0, 1024.0),   # the project's reference aspect
]

## Measured from the real game, by rendering it -- see the table in
## `hud_presentation.gd`. `<taskKind, focusRadius, expected mode>`.
const OBSERVED_BEATS: Array = [
	["travel", 0.0, Presentation.MODE_EXPLORE],      # walkToBathroom
	["choose", 1.88, Presentation.MODE_PREPARE],     # wakeUpBuddy, sayGoodMorning
	["goAndDo", 0.90, Presentation.MODE_FEED],       # bananaOnCounter, mashTheBanana,
	["goAndDo", 0.90, Presentation.MODE_FEED],       # carrySnackToBunny, feedBunnySnack
]

## How much of the screen's width, either side of centre, a tight close-up's
## SUBJECT occupies. Measured off the render rather than guessed: in
## `docs/shots/hud_feed_AFTER_ipad.png` (1334x750) the two characters span
## x = 0.42 .. 0.59 of the width, and the same beat at 2340x1080 is narrower
## still. A tenth either side of centre is therefore the band the HUD may never
## enter; the rail's own right edge sits at 0.33 of the width at iPad landscape,
## so there are a further 7 points of width in hand.
const CENTRE_HALF_WIDTH: float = 0.10

## What the top text stack used to cost, in reference pixels: the Thai hint's
## bottom edge at 288 px of a 750 px screen. Quoted so the improvement is a
## number rather than an impression.
const SHIPPED_TOP_STACK: float = 288.0


func test_name() -> String:
	return "hud_presentation"


func run():
	var failures: Array = []
	failures.append_array(_test_the_table_is_not_empty())
	failures.append_array(_test_every_observed_beat_lands_in_the_right_mode())
	failures.append_array(_test_the_threshold_sits_between_the_two_measured_classes())
	failures.append_array(_test_kind_and_radius_never_disagree())
	failures.append_array(_test_feed_leaves_the_centre_of_the_screen_alone())
	failures.append_array(_test_the_top_stack_shrinks())
	failures.append_array(_test_no_text_drops_below_the_readable_floor())
	failures.append_array(_test_the_assist_band_clears_the_buttons())
	failures.append_array(_test_nothing_is_hidden_without_a_way_back())
	failures.append_array(_test_the_camera_reports_the_radius_the_hud_reads())
	failures.append_array(_test_a_hud_with_no_camera_still_works())
	return failures


## -- Anti-vacuity --------------------------------------------------------------

func _test_the_table_is_not_empty():
	var failures: Array = []
	if Presentation.MODE_NAMES.size() != 4:
		failures.append("hud_presentation: the brief specifies four modes, this has %d"
				% Presentation.MODE_NAMES.size())
	for mode: int in range(Presentation.MODE_NAMES.size()):
		var l: Dictionary = Presentation.layout(mode)
		for key: String in ["promptAnchor", "promptRect", "promptSize", "promptVisible",
				"hintRect", "hintSize", "hintVisible",
				"encouragementRect", "encouragementSize", "starSize"]:
			if not l.has(key):
				failures.append("hud_presentation: %s's layout has no '%s'; the HUD would read "
						% [Presentation.mode_name(mode), key] + "null and lay itself out at 0,0")
	if OBSERVED_BEATS.size() < 4:
		failures.append("hud_presentation: the observed-beat table is too small to be real")
	return failures


## -- The rule ------------------------------------------------------------------

func _test_every_observed_beat_lands_in_the_right_mode():
	var failures: Array = []
	for row: Array in OBSERVED_BEATS:
		# Deliberately WITHOUT the task kind: the whole claim is that the camera
		# alone is enough, so the director never has to learn a new call.
		var got: int = Presentation.shot_mode(float(row[1]), "")
		if got != int(row[2]):
			failures.append(
				("hud_presentation: a %s beat composes a %.2f m close-up and must present as "
				+ "%s, but the radius alone chose %s. This is measured from the shipped "
				+ "missions; if a beat's shot has genuinely changed, re-measure it rather "
				+ "than moving the threshold.") % [
					String(row[0]), float(row[1]),
					Presentation.mode_name(int(row[2])), Presentation.mode_name(got)]
			)
	return failures


func _test_the_threshold_sits_between_the_two_measured_classes():
	var failures: Array = []
	var tight: float = 0.90
	var wide: float = 1.88
	if not (Presentation.WIDE_SHOT_RADIUS > tight and Presentation.WIDE_SHOT_RADIUS < wide):
		failures.append(("hud_presentation: WIDE_SHOT_RADIUS is %.2f, which is not between the "
				+ "two classes the game actually composes (%.2f m and %.2f m)")
				% [Presentation.WIDE_SHOT_RADIUS, tight, wide])
	# And with real margin either side, so a beat whose staging shifts by a few
	# centimetres does not flip the whole HUD layout.
	if Presentation.WIDE_SHOT_RADIUS - tight < 0.25:
		failures.append("hud_presentation: only %.2f m of margin above the tight beats; a small "
				% (Presentation.WIDE_SHOT_RADIUS - tight)
				+ "change in staging would flip the layout mid-level")
	if wide - Presentation.WIDE_SHOT_RADIUS < 0.25:
		failures.append("hud_presentation: only %.2f m of margin below the choice rows"
				% (wide - Presentation.WIDE_SHOT_RADIUS))
	return failures


## The optional director hook and the automatic rule must never contradict each
## other. If they could, wiring the hook up would silently change the game's
## layout, which is exactly the kind of change nobody would think to re-render.
func _test_kind_and_radius_never_disagree():
	var failures: Array = []
	for row: Array in OBSERVED_BEATS:
		var kind: String = String(row[0])
		var by_kind: int = Presentation.kind_mode(kind)
		if by_kind < 0:
			continue  # `travel` composes no close-up and has no opinion; fine.
		var by_radius: int = Presentation.shot_mode(float(row[1]), "")
		if by_kind != by_radius:
			failures.append(
				("hud_presentation: kind '%s' asks for %s but its measured %.2f m shot chooses "
				+ "%s. Connecting the director's optional hook would then MOVE the HUD, and "
				+ "nothing would re-render to catch it.") % [
					kind, Presentation.mode_name(by_kind), float(row[1]),
					Presentation.mode_name(by_radius)]
			)
	return failures


## -- The P0 geometry -----------------------------------------------------------

## The one that matters. In a tight close-up the subject is centred, so the HUD's
## text must not occupy the middle of the screen at all.
func _test_feed_leaves_the_centre_of_the_screen_alone():
	var failures: Array = []
	var l: Dictionary = Presentation.layout(Presentation.MODE_FEED)
	if String(l["promptAnchor"]) != "topLeft":
		failures.append("hud_presentation: FEED must anchor its text to the left margin; it "
				+ "anchors '%s', which puts it back over the face" % String(l["promptAnchor"]))
		return failures
	if bool(l["hintVisible"]):
		failures.append("hud_presentation: FEED must stand the Thai hint down -- the left rail "
				+ "has room for one line, and two would reach the character")
	for viewport: Vector2 in VIEWPORTS:
		var right_edge: float = float((l["promptRect"] as Array)[2])
		var centre_starts: float = viewport.x * (0.5 - CENTRE_HALF_WIDTH)
		if right_edge > centre_starts:
			failures.append(
				("hud_presentation: at %dx%d the FEED rail reaches x=%.0f, and the close-up's "
				+ "subject starts at x=%.0f. This is the defect in "
				+ "docs/shots/hud_feed_BEFORE_ipad.png, re-introduced.")
				% [int(viewport.x), int(viewport.y), right_edge, centre_starts]
			)
	return failures


func _test_the_top_stack_shrinks():
	var failures: Array = []
	var explore: float = Presentation.top_stack_height(Presentation.MODE_EXPLORE)
	var prepare: float = Presentation.top_stack_height(Presentation.MODE_PREPARE)
	var feed: float = Presentation.top_stack_height(Presentation.MODE_FEED)
	if explore > SHIPPED_TOP_STACK:
		failures.append("hud_presentation: EXPLORE's stack grew to %.0f px, past the %.0f px "
				% [explore, SHIPPED_TOP_STACK] + "that shipped")
	if prepare >= explore:
		failures.append(("hud_presentation: PREPARE is supposed to be the COMPACT layout but "
				+ "its stack (%.0f px) is no shorter than EXPLORE's (%.0f px)")
				% [prepare, explore])
	if prepare > 200.0:
		failures.append("hud_presentation: PREPARE's stack is %.0f px, which is over a quarter "
				% prepare + "of a 750 px screen and not compact")
	if feed > 0.0:
		failures.append("hud_presentation: FEED still puts %.0f px of text across the top"
				% feed)
	return failures


## ART_BIBLE §8: 27 pt at the reference size, for anything a child is meant to
## read. "Compact" is exactly where that rule gets quietly broken.
func _test_no_text_drops_below_the_readable_floor():
	var failures: Array = []
	for mode: int in range(Presentation.MODE_NAMES.size()):
		for size: int in Presentation.font_sizes(mode):
			if size < Presentation.MIN_FONT_SIZE:
				failures.append(("hud_presentation: %s authors %d pt text. ART_BIBLE §8 sets "
						+ "27 pt as the floor and the player is four years old.")
						% [Presentation.mode_name(mode), size])
	return failures


## The assist line moved to a band above the buttons. It must not land ON them --
## it is a Label with the mouse filtered out, so a collision would not eat a
## press, but it would sit across "Next", which is the child's only escape hatch.
func _test_the_assist_band_clears_the_buttons():
	var failures: Array = []
	for mode: int in range(Presentation.MODE_NAMES.size()):
		var rect: Array = Presentation.layout(mode)["encouragementRect"]
		for viewport: Vector2 in VIEWPORTS:
			var band: Rect2 = Rect2(
				float(rect[0]), viewport.y + float(rect[1]),
				viewport.x + float(rect[2]) - float(rect[0]),
				float(rect[3]) - float(rect[1])
			)
			var buttons: Dictionary = HouseHud.button_rects(viewport)
			for name: String in ["next", "speak"]:
				var button: Rect2 = buttons[name]
				if band.intersects(button):
					failures.append(("hud_presentation: %s's assist band %s overlaps the %s "
							+ "button %s at %dx%d")
							% [Presentation.mode_name(mode), str(band), name, str(button),
									int(viewport.x), int(viewport.y)])
	return failures


## -- No dead ends (CLAUDE.md) --------------------------------------------------

## Two lines stand down, and both come back. Asserted on a real HUD rather than
## on the layout table, because "comes back" is a question about the object's
## behaviour over time, not about numbers.
func _test_nothing_is_hidden_without_a_way_back():
	var failures: Array = []
	var hud: Control = HouseHud.new()
	hud.call("build")
	hud.call("set_prompt", "Give Bunny the food.", "ให้น้องกินขนม")

	# FEED hides the hint. The instruction itself must stay.
	hud.call("set_presentation_mode", Presentation.MODE_FEED)
	var prompt_label: Label = hud.find_child("Prompt", true, false) as Label
	var hint_label: Label = hud.find_child("ThaiHint", true, false) as Label
	if prompt_label == null or hint_label == null:
		failures.append("hud_presentation: the HUD no longer builds a Prompt and a ThaiHint; "
				+ "this whole case would then be guarding nothing")
		hud.free()
		return failures
	if not prompt_label.visible:
		failures.append("hud_presentation: FEED hid the instruction itself. The Thai HINT is "
				+ "secondary and may stand down; the thing to do may not.")
	if hint_label.visible:
		failures.append("hud_presentation: FEED was supposed to stand the Thai hint down")
	if hint_label.text.strip_edges().is_empty():
		failures.append("hud_presentation: FEED cleared the hint's TEXT rather than hiding it; "
				+ "it could never come back")

	# ...and it does come back the moment the close-up ends.
	hud.call("set_presentation_mode", Presentation.MODE_EXPLORE)
	if not hint_label.visible:
		failures.append("hud_presentation: the Thai hint did not return when the close-up "
				+ "ended. That is a dead end with no way out of it.")

	# Back to deriving the mode. A pinned mode is a test/harness affordance and
	# stays pinned on purpose -- which is itself worth proving, since the reward
	# check below would pass vacuously if an override could be overruled.
	hud.call("mark_current_done")
	if hud.call("get_presentation_mode") != Presentation.MODE_EXPLORE:
		failures.append("hud_presentation: a pinned presentation mode was overruled; "
				+ "set_presentation_mode() would then be useless for a screenshot")
	hud.call("clear_presentation_override")

	# COMPLETE hides the prompt -- and the next instruction must cancel it at once
	# rather than waiting out the applause.
	hud.call("configure_progress", 3)
	hud.call("set_current", 1)
	hud.call("mark_current_done")
	if hud.call("get_presentation_mode") != Presentation.MODE_COMPLETE:
		failures.append("hud_presentation: finishing a task did not open the reward "
				+ "presentation")
	if prompt_label.visible:
		failures.append("hud_presentation: COMPLETE still shows the finished task's "
				+ "instruction, which is the one thing that is certainly no longer true")
	hud.call("set_prompt", "Put the spoon away.", "")
	if hud.call("get_presentation_mode") == Presentation.MODE_COMPLETE:
		failures.append("hud_presentation: a NEW prompt did not end the reward presentation. "
				+ "The next instruction would be invisible for up to REWARD_SECONDS.")
	if not prompt_label.visible:
		failures.append("hud_presentation: the next task's instruction is still hidden")
	hud.free()
	return failures


## -- The wiring the whole thing depends on -------------------------------------

## Without this accessor the HUD reads 0.0 for ever, silently sits in EXPLORE and
## the defect is back with every test above still green. It is the single most
## load-bearing line in the change.
func _test_the_camera_reports_the_radius_the_hud_reads():
	var failures: Array = []
	var camera: Camera3D = RoomCameraScript.new()
	if not camera.has_method("get_focus_radius"):
		failures.append("hud_presentation: room_camera.gd has no get_focus_radius(); the HUD "
				+ "duck-types this call and would fall back to EXPLORE at every beat")
		camera.free()
		return failures
	camera.call("frame_room", {
		"bounds": Rect2(-2.0, -2.0, 4.0, 4.0),
		"focus": Vector3(0.0, 0.5, 0.0),
		"angle": 37.0, "minDistance": 3.5, "maxDistance": 24.0,
	})
	if not is_equal_approx(float(camera.call("get_focus_radius")), 0.0):
		failures.append("hud_presentation: the room shot reports a focus radius of %.2f; the "
				% float(camera.call("get_focus_radius"))
				+ "HUD would compact itself during ordinary exploration")
	for radius: float in [0.90, 1.88]:
		camera.call("focus_activity", Vector3(0.4, 0.55, -0.3), radius)
		var reported: float = float(camera.call("get_focus_radius"))
		if absf(reported - radius) > 0.01:
			failures.append("hud_presentation: focused at %.2f m, the camera reports %.2f m"
					% [radius, reported])
		if Presentation.shot_mode(reported, "") != Presentation.shot_mode(radius, ""):
			failures.append("hud_presentation: the radius the camera reports for a %.2f m "
					% radius + "close-up chooses a different mode from the radius asked for")
	camera.call("restore_room_frame")
	if not is_equal_approx(float(camera.call("get_focus_radius")), 0.0):
		failures.append("hud_presentation: letting go of the close-up left a focus radius "
				+ "behind; the HUD would stay compacted for the rest of the level")
	camera.free()
	return failures


func _test_a_hud_with_no_camera_still_works():
	var failures: Array = []
	var hud: Control = HouseHud.new()
	hud.call("build")
	hud.call("refresh_presentation")
	if hud.call("get_presentation_mode") != Presentation.MODE_EXPLORE:
		failures.append("hud_presentation: with no camera in sight the HUD must present as "
				+ "EXPLORE; it chose %s" % String(hud.call("get_presentation_mode_name")))
	# Free Play has no beat and no objective; it is EXPLORE whatever a camera says.
	hud.call("set_free_play_mode", true)
	hud.call("clear_presentation_override")
	if hud.call("get_presentation_mode") != Presentation.MODE_EXPLORE:
		failures.append("hud_presentation: Free Play must stay in EXPLORE")
	hud.free()
	return failures
