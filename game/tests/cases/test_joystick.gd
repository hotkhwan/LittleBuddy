extends RefCounted

## The virtual thumbstick: geometry, curve, gesture, palette.
##
## This case exists because of a sentence from a physical phone:
##
##   > *"เน้น smooth เล่นได้จริงๆ เพิ่ม การบังคับตัวละครแบบ joystick เหมือน moba rov"*
##
## -- focus on smooth, genuinely playable, and **add** joystick control like a
## MOBA / RoV. It is a deliberate reversal of `LITTLE_BUDDY_GAME_BIBLE.md` §6's
## "no complicated virtual joystick in early versions": device feedback outranks
## it, and tap-to-walk was not removed.
##
## What is under test here is the STICK. Everything about what it does to the
## character lives in `test_joystick_drive.gd`.
##
## The properties, and what each one is protecting:
##
##   1. **Floating origin.** The stick appears exactly where the thumb lands. A
##      fixed dial makes a four-year-old hunt for a target; this removes the hunt
##      entirely, and it is also why a press alone never moves anybody.
##   2. **Dead zone.** A small thumb resting on glass drifts. Without this,
##      "holding still" walks the character into a wall.
##   3. **The output is bounded.** `WALK_SPEED` is a ceiling derived from gait
##      physics, not a suggestion, and the stick multiplies into it.
##   4. **It never overlaps Next or Speak**, at any aspect ratio the game ships
##      at, and it never leaves the safe area.
##   5. **One pointer at a time.** Two thumbs must not fight.
##   6. **A tap inside the zone is still a tap.** No part of the floor may become
##      untappable just because the stick is drawn over it.
##   7. **It is quiet and it is mint.** ART_BIBLE §3 is locked.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const Joystick := preload("res://scripts/input/virtual_joystick.gd")
const HouseHud := preload("res://scripts/gameplay/house_hud.gd")
const Palette := preload("res://scripts/ui/palette.gd")

const JOYSTICK_SOURCE: String = "res://scripts/input/virtual_joystick.gd"

## Every viewport the game can actually produce. `project.godot` stretches
## `canvas_items` with `aspect = expand` from a 1366 x 1024 base and locks the
## handheld orientation to landscape, so the height is always 1024 and the width
## runs from 1366 (a 4:3 iPad) to about 2217 (a landscape iPhone).
const VIEWPORTS: Array[Vector2] = [
	Vector2(1366.0, 1024.0),   # iPad, 1024 x 768 window
	Vector2(1517.0, 1024.0),   # 3:2
	Vector2(1820.0, 1024.0),   # 16:9
	Vector2(2217.0, 1024.0),   # landscape iPhone, 1334 x 616 window
	Vector2(2400.0, 1024.0),   # wider than anything shipping, for headroom
]


func test_name() -> String:
	return "joystick"


func run():
	var failures: Array = []
	failures.append_array(_test_the_origin_floats())
	failures.append_array(_test_dead_zone_is_generous())
	failures.append_array(_test_output_is_bounded_and_monotonic())
	failures.append_array(_test_full_circle())
	failures.append_array(_test_activation_zone_is_large_and_reachable())
	failures.append_array(_test_zone_never_touches_next_or_speak())
	failures.append_array(_test_zone_stays_inside_the_safe_area())
	failures.append_array(_test_one_pointer_at_a_time())
	failures.append_array(_test_release_zeroes_the_output())
	failures.append_array(_test_a_tap_in_the_zone_is_handed_back())
	failures.append_array(_test_a_real_drag_is_not_handed_back())
	failures.append_array(_test_presses_outside_the_zone_are_refused())
	failures.append_array(_test_disabling_under_a_thumb_is_clean())
	failures.append_array(_test_event_translation())
	failures.append_array(_test_it_never_steals_from_the_hud_or_a_drag())
	failures.append_array(_test_palette_is_the_locked_mint())
	failures.append_array(_test_hud_geometry_still_agrees())
	return failures


## -- The stick itself ----------------------------------------------------------

## THE RoV detail. The base appears under the thumb; it is not a dial to find.
func _test_the_origin_floats():
	var failures: Array = []
	var stick: Control = _stick()

	var first: Vector2 = Vector2(120.0, 900.0)
	if not bool(stick.call("press", 0, first)):
		failures.append("a press well inside the activation zone was refused")
	if not (stick.call("get_origin") as Vector2).is_equal_approx(first):
		failures.append("the stick must centre itself on the press, got %s"
				% str(stick.call("get_origin")))
	if bool(stick.call("is_active")):
		failures.append("a press alone must not move anybody: a floating stick starts at zero "
				+ "deflection, which is what makes a stray tap in the zone harmless")
	if not (stick.call("get_vector") as Vector2).is_zero_approx():
		failures.append("output should be zero on the frame of the press")

	# ...and somewhere completely different next time.
	stick.call("release", 0)
	var second: Vector2 = Vector2(430.0, 560.0)
	stick.call("press", 0, second)
	if not (stick.call("get_origin") as Vector2).is_equal_approx(second):
		failures.append("the origin must follow the SECOND thumb too; a stick that snaps back to "
				+ "one home position is the fixed dial this design exists to avoid")
	return _close(stick, failures)


func _test_dead_zone_is_generous():
	var failures: Array = []
	var dead: float = Joystick.MAX_RADIUS * Joystick.DEAD_ZONE_RATIO

	if Joystick.DEAD_ZONE_RATIO < 0.15:
		failures.append("a dead zone of %.0f%% is not generous enough for a four-year-old's thumb"
				% (Joystick.DEAD_ZONE_RATIO * 100.0))
	if Joystick.DEAD_ZONE_RATIO > 0.4:
		failures.append("a dead zone of %.0f%% eats most of the travel"
				% (Joystick.DEAD_ZONE_RATIO * 100.0))

	var origin: Vector2 = Vector2(200.0, 900.0)
	for fraction: float in [0.0, 0.25, 0.5, 0.9, 0.99]:
		var at: Vector2 = origin + Vector2(dead * fraction, 0.0)
		var state: Dictionary = Joystick.resolve(origin, at)
		if bool(state["live"]) or float(state["magnitude"]) > 0.0:
			failures.append("a thumb %.0f%% of the way across the dead zone produced motion; "
					% (fraction * 100.0) + "resting still has to mean standing still")

	var past: Dictionary = Joystick.resolve(origin, origin + Vector2(dead * 1.2, 0.0))
	if not bool(past["live"]):
		failures.append("past the dead zone the stick must be live")
	if float(past["magnitude"]) < Joystick.MIN_OUTPUT - 0.001:
		failures.append("the first step past the dead zone asks for %.2f of walk speed; below "
				% float(past["magnitude"]) + "MIN_OUTPUT the walk reads as nothing happening")
	return failures


## The ceiling is the point. `WALK_SPEED` is the top of the walk range for a
## 0.22 m leg (Froude ~ 0.51) and the stick multiplies straight into it, so a
## magnitude over 1.0 would be a character that runs.
func _test_output_is_bounded_and_monotonic():
	var failures: Array = []

	if not is_equal_approx(Joystick.response(1.0), 1.0):
		failures.append("full deflection must ask for exactly walk speed, got %.4f"
				% Joystick.response(1.0))
	for travel: float in [1.0, 1.5, 4.0, 100.0]:
		if Joystick.response(travel) > 1.0:
			failures.append("response(%.1f) = %.3f exceeds walk speed"
					% [travel, Joystick.response(travel)])
	if Joystick.response(0.0) != 0.0:
		failures.append("no deflection must be no movement")
	if Joystick.response(-1.0) != 0.0:
		failures.append("a negative travel must clamp to nothing, not to a reverse")

	var previous: float = -1.0
	for i: int in range(41):
		var t: float = float(i) / 40.0
		var value: float = Joystick.response(t)
		if value < previous - 0.0001:
			failures.append("the response curve went backwards at t = %.2f" % t)
			break
		previous = value

	# A thumb dragged far past the ring is still exactly full deflection, and the
	# knob stays on the ring rather than flying off with it.
	var origin: Vector2 = Vector2(300.0, 800.0)
	var far: Dictionary = Joystick.resolve(origin, origin + Vector2(2000.0, 0.0))
	if not is_equal_approx(float(far["magnitude"]), 1.0):
		failures.append("a thumb dragged off the ring should saturate at 1.0, got %.3f"
				% float(far["magnitude"]))
	if (far["knob"] as Vector2).length() > Joystick.MAX_RADIUS + 0.001:
		failures.append("the knob left the ring: %.1f px" % (far["knob"] as Vector2).length())
	return failures


## Full 360 degrees, not eight directions. A child pushes where they are looking.
func _test_full_circle():
	var failures: Array = []
	var origin: Vector2 = Vector2(280.0, 820.0)
	var reach: float = Joystick.MAX_RADIUS

	for step: int in range(24):
		var angle: float = TAU * float(step) / 24.0
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * reach
		var state: Dictionary = Joystick.resolve(origin, origin + offset)
		if not bool(state["live"]):
			failures.append("full deflection at %.0f degrees produced nothing"
					% rad_to_deg(angle))
			continue
		var out: Vector2 = Vector2(float(state["x"]), float(state["y"]))
		if absf(out.length() - 1.0) > 0.002:
			failures.append("full deflection at %.0f degrees gave magnitude %.3f"
					% [rad_to_deg(angle), out.length()])
		if out.angle_to(offset) > 0.001:
			failures.append("the output must point where the thumb points; %.0f degrees was off by "
					% rad_to_deg(angle) + "%.3f rad" % out.angle_to(offset))
	return failures


## -- Layout --------------------------------------------------------------------

func _test_activation_zone_is_large_and_reachable():
	var failures: Array = []
	for viewport: Vector2 in VIEWPORTS:
		var stick: Control = _stick(viewport)
		var zone: Rect2 = stick.call("get_activation_rect")

		# ART_BIBLE §8: 240 x 240 minimum for a primary child-facing control. The
		# ZONE is many times that; the base ring alone must already clear it.
		if Joystick.MAX_RADIUS * 2.0 < 240.0:
			failures.append("the stick's base is %.0f px across, under the 240 px minimum"
					% (Joystick.MAX_RADIUS * 2.0))
		if zone.size.x < 240.0 or zone.size.y < 240.0:
			failures.append("%s: the activation zone is only %.0f x %.0f"
					% [str(viewport), zone.size.x, zone.size.y])
		if zone.size.x < Joystick.MAX_RADIUS * 2.0:
			failures.append("%s: the zone (%.0f px) is narrower than the stick it activates"
					% [str(viewport), zone.size.x])

		# Bottom-left, where a thumb already is on a phone held in landscape.
		if zone.position.x > viewport.x * 0.25:
			failures.append("%s: the zone starts at x = %.0f, which is not the left side"
					% [str(viewport), zone.position.x])
		if zone.end.y < viewport.y - 40.0:
			failures.append("%s: the zone stops %.0f px short of the bottom edge"
					% [str(viewport), viewport.y - zone.end.y])

		# The resting hint has to be drawable in full, inside the zone.
		var rest: Vector2 = Joystick.rest_origin(zone)
		if not zone.has_point(rest):
			failures.append("%s: the resting hint sits outside its own zone" % str(viewport))
		if rest.x - Joystick.MAX_RADIUS < -1.0 or rest.y + Joystick.MAX_RADIUS > viewport.y + 1.0:
			failures.append("%s: the resting hint ring is cropped by the screen edge"
					% str(viewport))
		stick.free()
	return failures


## The one that would actually break the game: a stick that ate a press meant for
## Next (the escape hatch) or Speak.
func _test_zone_never_touches_next_or_speak():
	var failures: Array = []
	for viewport: Vector2 in VIEWPORTS:
		var stick: Control = _stick(viewport)
		var zone: Rect2 = stick.call("get_activation_rect")
		var buttons: Dictionary = HouseHud.button_rects(viewport)

		for key: String in ["next", "speak"]:
			var button: Rect2 = buttons[key]
			if zone.intersects(button):
				failures.append("%s: the stick's zone %s overlaps the %s button %s"
						% [str(viewport), str(zone), key, str(button)])
			# And not merely touching, either: a thumb is wider than a pixel.
			if zone.end.x > button.position.x - 24.0 and zone.end.y > button.position.y:
				failures.append("%s: the zone ends %.0f px from the %s button, which is within a "
						% [str(viewport), button.position.x - zone.end.x, key] + "thumb's width")
		stick.free()
	return failures


func _test_zone_stays_inside_the_safe_area():
	var failures: Array = []
	for viewport: Vector2 in VIEWPORTS:
		var stick: Control = _stick(viewport)
		var zone: Rect2 = stick.call("get_activation_rect")
		var insets: Vector4 = stick.call("get_safe_insets")

		if zone.position.x < insets.x - 0.001:
			failures.append("%s: the zone starts %.1f px inside the left safe inset"
					% [str(viewport), insets.x - zone.position.x])
		if zone.end.y > viewport.y - insets.w + 0.001:
			failures.append("%s: the zone runs %.1f px into the bottom safe inset"
					% [str(viewport), zone.end.y - (viewport.y - insets.w)])
		if zone.position.y < insets.y - 0.001:
			failures.append("%s: the zone runs into the top safe inset" % str(viewport))
		stick.free()
	return failures


## -- Gesture -------------------------------------------------------------------

func _test_one_pointer_at_a_time():
	var failures: Array = []
	var stick: Control = _stick()

	stick.call("press", 0, Vector2(150.0, 900.0))
	if bool(stick.call("press", 1, Vector2(300.0, 700.0))):
		failures.append("a second finger started a second gesture; two thumbs must not fight "
				+ "over one character")
	if not (stick.call("get_origin") as Vector2).is_equal_approx(Vector2(150.0, 900.0)):
		failures.append("the second finger moved the origin")

	if bool(stick.call("drag", 1, Vector2(400.0, 900.0))):
		failures.append("a stray pointer's motion was accepted mid-gesture")
	if not (stick.call("get_vector") as Vector2).is_zero_approx():
		failures.append("a stray pointer's motion changed the output")

	if bool(stick.call("release", 1)):
		failures.append("a stray pointer's release ended somebody else's gesture")
	if not bool(stick.call("is_held")):
		failures.append("the original thumb should still own the stick")

	if not bool(stick.call("release", 0)):
		failures.append("the owning pointer's release was not honoured")
	return _close(stick, failures)


func _test_release_zeroes_the_output():
	var failures: Array = []
	var stick: Control = _stick()
	var released: Array = []
	stick.connect("released", func() -> void: released.append(true))

	stick.call("press", 0, Vector2(200.0, 880.0))
	stick.call("drag", 0, Vector2(200.0 + Joystick.MAX_RADIUS, 880.0))
	if not bool(stick.call("is_active")):
		failures.append("a full-deflection drag should be live")
	if absf((stick.call("get_vector") as Vector2).x - 1.0) > 0.002:
		failures.append("a full drag to the right should ask for +1.0 on x, got %s"
				% str(stick.call("get_vector")))

	stick.call("release", 0)
	if bool(stick.call("is_active")) or bool(stick.call("is_held")):
		failures.append("the stick is still live after the thumb left")
	if not (stick.call("get_vector") as Vector2).is_zero_approx():
		failures.append("output survived the release: %s" % str(stick.call("get_vector")))
	if released.size() != 1:
		failures.append("released should fire exactly once, got %d" % released.size())
	return _close(stick, failures)


## The bottom-left of the floor must stay tappable. A press that never left the
## dead zone and let go quickly is a tap, and goes back to tap-to-walk.
func _test_a_tap_in_the_zone_is_handed_back():
	var failures: Array = []
	var stick: Control = _stick()
	var taps: Array = []
	stick.connect("tapped", func(x: float, y: float) -> void: taps.append(Vector2(x, y)))

	stick.call("press", 0, Vector2(180.0, 860.0))
	stick.call("release", 0)
	if taps.size() != 1:
		failures.append("a press-and-let-go inside the zone must be offered back to tap-to-walk, "
				+ "or a whole corner of the floor silently stops working; got %d" % taps.size())
	elif not (taps[0] as Vector2).is_equal_approx(Vector2(180.0, 860.0)):
		failures.append("the tap was handed back at the wrong place: %s" % str(taps[0]))
	return _close(stick, failures)


func _test_a_real_drag_is_not_handed_back():
	var failures: Array = []
	var stick: Control = _stick()
	var taps: Array = []
	stick.connect("tapped", func(x: float, y: float) -> void: taps.append(Vector2(x, y)))

	stick.call("press", 0, Vector2(200.0, 880.0))
	stick.call("drag", 0, Vector2(200.0 + Joystick.MAX_RADIUS, 880.0))
	# ...and back to the middle before letting go, which is exactly how a child
	# lets go of a stick.
	stick.call("drag", 0, Vector2(200.0, 880.0))
	stick.call("release", 0)
	if not taps.is_empty():
		failures.append("a stick gesture that happened to end near its origin was reported as a "
				+ "tap, so letting go of the stick would also order a walk")
	return _close(stick, failures)


func _test_presses_outside_the_zone_are_refused():
	var failures: Array = []
	var viewport: Vector2 = Vector2(2217.0, 1024.0)
	var stick: Control = _stick(viewport)
	var zone: Rect2 = stick.call("get_activation_rect")

	var outside: Array[Vector2] = [
		Vector2(viewport.x * 0.5, viewport.y * 0.5),      # the middle of the room
		Vector2(viewport.x - 120.0, viewport.y - 80.0),   # over Next
		Vector2(viewport.x * 0.5, viewport.y - 80.0),     # over Speak
		Vector2(zone.position.x + 20.0, 120.0),           # above the zone
		Vector2(zone.end.x + 40.0, zone.end.y - 40.0),    # just right of it
	]
	for at: Vector2 in outside:
		if bool(stick.call("claims_press", at)):
			failures.append("the stick claimed %s, which is outside its zone" % str(at))
		if bool(stick.call("press", 0, at)):
			failures.append("the stick took a press at %s, outside its zone" % str(at))
	if bool(stick.call("is_held")):
		failures.append("a refused press still latched a pointer")

	var inside: Vector2 = zone.get_center()
	if not bool(stick.call("claims_press", inside)):
		failures.append("the stick did not claim the middle of its own zone")
	return _close(stick, failures)


func _test_disabling_under_a_thumb_is_clean():
	var failures: Array = []
	var stick: Control = _stick()
	var taps: Array = []
	stick.connect("tapped", func(_x: float, _y: float) -> void: taps.append(true))

	stick.call("press", 0, Vector2(200.0, 880.0))
	stick.call("drag", 0, Vector2(300.0, 880.0))
	stick.call("set_enabled", false)

	if bool(stick.call("is_held")) or bool(stick.call("is_active")):
		failures.append("a summary screen opened and the stick kept driving")
	if not (stick.call("get_vector") as Vector2).is_zero_approx():
		failures.append("the last output survived being switched off, which would walk Little "
				+ "Buddy into a wall behind an overlay")
	if not taps.is_empty():
		failures.append("switching off must not be reported as a tap")
	if stick.visible:
		failures.append("a disabled stick should not be drawn")
	if bool(stick.call("claims_press", Vector2(200.0, 880.0))):
		failures.append("a disabled stick still claims presses, so tap-to-walk would lose a "
				+ "corner of the floor for nothing")

	stick.call("set_enabled", true)
	if not stick.visible or not bool(stick.call("is_enabled")):
		failures.append("the stick did not come back")
	return _close(stick, failures)


## The touch/mouse/emulated-mouse triple, without a touchscreen.
## `pointing/emulate_mouse_from_touch` is on, so one finger really does produce
## two events, and only the pointer latch keeps them one gesture.
func _test_event_translation():
	var failures: Array = []

	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = 2
	touch.pressed = true
	touch.position = Vector2(140.0, 900.0)
	var described: Dictionary = Joystick.describe_event(touch)
	if String(described.get("phase", "")) != "press" or int(described.get("pointer", -99)) != 2:
		failures.append("a screen touch was not read as a press: %s" % str(described))

	var slide: InputEventScreenDrag = InputEventScreenDrag.new()
	slide.index = 2
	slide.position = Vector2(220.0, 900.0)
	if String(Joystick.describe_event(slide).get("phase", "")) != "drag":
		failures.append("a screen drag was not read as motion")

	var right: InputEventMouseButton = InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	if not Joystick.describe_event(right).is_empty():
		failures.append("a right click is not a thumb")

	if not Joystick.describe_event(InputEventKey.new()).is_empty():
		failures.append("a key press is not a thumb")

	# The emulated mouse press that arrives alongside the real touch must not
	# start a second gesture.
	var stick: Control = _stick()
	stick.call("press", 2, Vector2(140.0, 900.0))
	if bool(stick.call("press", Joystick.MOUSE_POINTER_INDEX, Vector2(140.0, 900.0))):
		failures.append("the synthetic mouse press that shadows every touch started a SECOND "
				+ "gesture; with emulate_mouse_from_touch on, that is every single press")
	return _close(stick, failures)


## Structural, and the guarantee that drag-and-drop and the HUD keep winning.
##
## The stick reads `_unhandled_input`, which runs after the GUI and after physics
## picking -- the two places `house_hud.gd`'s buttons and `DraggableObject` both
## call `set_input_as_handled()`. Move it to `_input` or `_gui_input`, or give
## the control a mouse filter that swallows presses, and a child could no longer
## pick anything up in the bottom-left of the room.
func _test_it_never_steals_from_the_hud_or_a_drag():
	var failures: Array = []
	var source: String = FileAccess.get_file_as_string(JOYSTICK_SOURCE)
	if source.is_empty():
		return ["could not read %s" % JOYSTICK_SOURCE]

	if not source.contains("func _unhandled_input("):
		failures.append("the stick must read _unhandled_input, so every UI control and every "
				+ "DraggableObject wins outright before it sees anything")
	if source.contains("func _input("):
		failures.append("the stick defines _input(), which runs BEFORE the GUI and before physics "
				+ "picking: it would steal presses from the Next button and from every drag")
	if source.contains("func _gui_input("):
		failures.append("the stick defines _gui_input(), which puts it in the GUI's own dispatch "
				+ "and takes presses away from whatever is drawn under it")

	var stick: Control = _stick()
	if stick.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		failures.append("the stick's mouse filter is %d, not IGNORE; anything else marks the "
				% stick.mouse_filter + "press as handled and kills the drag path underneath it")
	return _close(stick, failures)


## -- Palette -------------------------------------------------------------------

## ART_BIBLE §3 is LOCKED and this is new on-screen colour. Mint is the game's
## "go" -- the same language `TapRipple` already speaks -- over a cream rim.
## `#000000` and red are banned everywhere.
func _test_palette_is_the_locked_mint():
	var failures: Array = []
	var stick: Control = _stick()

	var mint: Color = stick.call("_mint", 1.0)
	if absf(mint.r - Palette.MINT.r) > 0.002 or absf(mint.g - Palette.MINT.g) > 0.002 \
			or absf(mint.b - Palette.MINT.b) > 0.002:
		failures.append("the stick is not the locked mint, it is %s" % str(mint))
	# The edge is §3's own "Deep" step (22% toward `ink`), not a new colour and
	# certainly not `#000000`: over a cream wall, mint on mint disappears.
	var rim: Color = stick.call("_rim", 1.0)
	var expected: Color = Palette.deep(Palette.MINT)
	if absf(rim.r - expected.r) > 0.002 or absf(rim.g - expected.g) > 0.002 \
			or absf(rim.b - expected.b) > 0.002:
		failures.append("the rim is not deep(mint), it is %s" % str(rim))
	if Palette.is_black(rim) or Palette.is_red(rim):
		failures.append("the rim is a banned colour: %s" % str(rim))
	if Palette.is_black(mint) or Palette.is_red(mint):
		failures.append("the stick is a banned colour: %s" % str(mint))

	# Quiet: translucent enough that the room reads through it, and dimmer still
	# before a thumb arrives. It must not become the loudest thing on screen.
	for entry: Array in [
		["BASE_FILL_ALPHA", Joystick.BASE_FILL_ALPHA],
		["BASE_RING_ALPHA", Joystick.BASE_RING_ALPHA],
		["KNOB_ALPHA", Joystick.KNOB_ALPHA],
		["KNOB_RIM_ALPHA", Joystick.KNOB_RIM_ALPHA],
	]:
		if float(entry[1]) >= 1.0:
			failures.append("%s is opaque; the stick must not hide the room" % String(entry[0]))
	if Joystick.REST_OPACITY >= 1.0:
		failures.append("the resting hint is as loud as the live stick")
	if Joystick.REST_OPACITY <= 0.0:
		failures.append("the resting hint is invisible; a child needs to know where to put a thumb")

	# Not one hand-typed colour in the whole file: every tint is a palette token
	# with an alpha put on it. This is what stops a near-red or a `#000000`
	# arriving one inspector field at a time.
	var source: String = FileAccess.get_file_as_string(JOYSTICK_SOURCE)
	for line: String in source.split("\n"):
		var code: String = line.split("#")[0]
		if code.contains("Color("):
			failures.append("hand-typed colour in the stick: %s" % line.strip_edges())
	return _close(stick, failures)


## The stick's clearance is measured against numbers that live in another file.
## Mirroring them was the only way to keep the input layer from importing the
## gameplay layer, so this is what stops the two drifting apart.
func _test_hud_geometry_still_agrees():
	var failures: Array = []
	if not is_equal_approx(Joystick.HUD_SPEAK_HALF_WIDTH, HouseHud.SPEAK_HALF_WIDTH):
		failures.append("the stick thinks the Speak button is %.0f px wide either side and the "
				% Joystick.HUD_SPEAK_HALF_WIDTH + "HUD says %.0f; the clearance is now a guess"
				% HouseHud.SPEAK_HALF_WIDTH)
	if Joystick.CENTRE_CLEARANCE <= 0.0:
		failures.append("there is no clearance left between the stick and the Speak button")
	return failures


## -- Helpers -------------------------------------------------------------------

## A stick sized by hand. `_ready()` never fires for a node the headless runner
## owns, so `build()` is called explicitly and `size` stands in for a viewport.
func _stick(viewport: Vector2 = Vector2(1366.0, 1024.0)) -> Control:
	var stick: Control = Joystick.new()
	stick.size = viewport
	stick.call("build")
	return stick


func _close(stick: Control, failures: Array):
	stick.free()
	return failures
