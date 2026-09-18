extends Control

## A MOBA/RoV-style floating thumbstick, for a four-year-old's left thumb.
##
## ## This is a deliberate reversal, not an oversight
##
## `LITTLE_BUDDY_GAME_BIBLE.md` §6 says "No complicated virtual joystick in early
## versions" and chose tap-to-walk instead. That line was written before anybody
## had played the game on a phone. What came back from the physical device was
## first *"ไม่สมูท"* -- it doesn't feel smooth -- and then, after a tap ripple and
## faster walk/turn speeds had already been added and helped:
##
##   > *"เน้น smooth เล่นได้จริงๆ เพิ่ม การบังคับตัวละครแบบ joystick เหมือน moba rov"*
##   > -- focus on smooth, genuinely playable; **add** joystick control like RoV.
##
## Device feedback outranks the Bible. The owner asked for direct analog control,
## which is a different and more immediate kind of input than tap-to-walk, and
## both now ship. **Tap-to-walk was not removed** -- see `coexistence` below.
##
## ## What makes an RoV stick feel like an RoV stick
##
## The **floating origin**. The stick is not a fixed dial the child has to find;
## it appears wherever the thumb first lands inside the activation zone, and the
## press point *is* the centre. That single detail is most of the feel, and it is
## also the accessibility win: a player who cannot reliably hit a 260 px target
## never has to. A press therefore always starts at zero deflection, so a stray
## tap inside the zone moves nobody (and is handed back to tap-to-walk -- see
## `tapped`).
##
## The rest is numbers, and every one of them is chosen for a small thumb:
##
##   * **Generous activation zone** -- about a third of the screen's width and
##     most of its height, bottom-left, so the thumb does not have to aim.
##   * **Generous dead zone** -- `DEAD_ZONE_RATIO` of the travel. A resting thumb
##     drifts; a four-year-old's resting thumb drifts a lot.
##   * **A floor under the output** (`MIN_OUTPUT`). Any deflection past the dead
##     zone produces a *visible* walk. A stick that can ask for 0.04 m/s reads as
##     a broken game, not as fine control.
##   * **A hard ceiling at 1.0**, which the character maps to `WALK_SPEED`
##     (1.05 m/s). The pace is deliberately calm and derived from gait physics
##     (Froude ~ 0.51 for a 0.22 m leg); the stick may not exceed it.
##
## ## Coexistence
##
## This node handles input in `_unhandled_input`, exactly as
## `navigation_controller.gd` does and for exactly the same reason: every UI
## control and every `DraggableObject` calls `set_input_as_handled()` and so wins
## outright, before the stick has seen anything. The drag path keeps winning
## everywhere it already did.
##
## Against tap-to-walk the rule is geometric and one-directional: the stick owns
## presses **inside its activation zone only**, and `claims_press()` is what the
## navigation controller asks before routing a tap. Outside the zone nothing
## changes at all. Inside it, a press that never leaves the dead zone and lets go
## quickly is re-offered to tap-to-walk through `tapped`, so no part of the floor
## becomes untappable.
##
## ## Pure where it can be
##
## `activation_rect()`, `rest_origin()`, `response()` and `resolve()` are static
## and take plain values, so the whole geometry and the whole response curve are
## testable with no viewport, no touchscreen and no renderer. The node half is a
## pointer latch and a `_draw()`.
##
## ## Budget and palette
##
## Two circles and two arcs in `mint` (ART_BIBLE §3: "go"), translucent, edged in
## §3's own Deep step of the same token (22% toward `ink`) because mint on a
## cream wall is otherwise invisible. There is not one hand-typed `Color` in the
## file. No `#000000`, no red, no texture, no shader, no tween. §8 wants
## generously rounded and soft, and it must not become the loudest thing on
## screen -- so at rest it sits at `REST_OPACITY` and only comes up to full while
## a thumb is on it.

const Palette := preload("res://scripts/ui/palette.gd")

## A thumb landed and the stick is live. The world uses this to retire the
## tap-to-walk marker: the child has changed their mind about how they are
## driving, and a mint disc still promising a destination is a lie.
signal grabbed()

## Analog output, -1..1 on each axis, in SCREEN space: `+x` is right, `+y` is
## *down the screen*, which the world turns into "towards the camera". Floats
## only, so nothing downstream needs a 2D or 3D type to consume it.
signal moved(x: float, y: float)

## The thumb left. Output is zero from this moment; the character coasts to a
## stop over `CharacterMovementController.DRIVE_ACCELERATION`.
signal released()

## A press inside the zone that never became a stick gesture. Re-offered to
## tap-to-walk with its screen position, so the bottom-left of the floor stays
## as tappable as the rest of it.
signal tapped(x: float, y: float)

## -- Geometry, in viewport pixels ---------------------------------------------
##
## `project.godot` stretches `canvas_items` with `aspect = expand` from a
## 1366x1024 base, so the viewport height is ALWAYS 1024 and only the width
## moves: 1366 on a 4:3 iPad, 2217 on a landscape iPhone. Every number below is
## therefore a real, stable pixel count rather than a guess.

## How far the knob travels from the origin at full deflection. The base ring is
## 264 px across, comfortably past ART_BIBLE §8's 240 x 240 minimum for a primary
## child-facing control -- and the *activation zone* is many times larger again.
const MAX_RADIUS: float = 132.0
const KNOB_RADIUS: float = 46.0
const RING_WIDTH: float = 5.0
const KNOB_RIM_WIDTH: float = 4.0

## Dead zone as a fraction of `MAX_RADIUS` (33 px here). Generous on purpose: a
## small thumb resting on glass wanders, and drift that walks the character into
## a wall while the child thinks they are holding still is the worst possible
## failure of a control scheme they cannot articulate a complaint about.
const DEAD_ZONE_RATIO: float = 0.25

## The slowest the stick will ever ask for, as a fraction of the walk speed
## (0.47 m/s). Below roughly this the walk cycle stops reading as walking and a
## child concludes nothing happened. Full deflection is exactly 1.0 and the
## curve is monotonic in between, so this buys responsiveness without ever
## exceeding the calm pace the walk clip was authored for.
const MIN_OUTPUT: float = 0.45

## Slope of the response curve at the dead-zone edge. Below 1.0 the curve eases
## IN, so the first half of the travel is finer than the second.
const CURVE_LINEAR: float = 0.55

## Activation zone. Big, bottom-left, and clamped so it can never reach the
## centre-bottom Speak button or the bottom-right Next button.
const ZONE_WIDTH_RATIO: float = 0.34
const ZONE_MIN_WIDTH: float = 340.0
const ZONE_MAX_WIDTH: float = 620.0
const ZONE_HEIGHT_RATIO: float = 0.60
const ZONE_MIN_HEIGHT: float = 380.0
const ZONE_MAX_HEIGHT: float = 660.0

## Half-width of `house_hud.gd`'s Speak button, which is anchored centre-bottom.
## Mirrored here rather than imported: the input layer must not depend on the
## gameplay layer. `test_joystick.gd` asserts the two numbers still agree, so
## neither can be changed alone.
const HUD_SPEAK_HALF_WIDTH: float = 112.0

## Clear air left between the zone's right edge and the Speak button.
const CENTRE_CLEARANCE: float = 60.0

## Never hug the bezel, even where the platform reports no unsafe area. Same two
## numbers as `scripts/ui/safe_area.gd`, and for the same reason; the stick reads
## the safe area itself rather than living inside a `SafeArea` container because
## it has to prove, in VIEWPORT coordinates, that it clears a button anchored to
## the viewport's centre.
const MIN_MARGIN: float = 16.0
const MIN_MARGIN_HORIZONTAL: float = 24.0

## -- Feel ----------------------------------------------------------------------

## A press that never left the dead zone and let go within this is a tap, not a
## stick gesture, and is handed back to tap-to-walk.
const TAP_MAX_SEC: float = 0.4

## Opacity multiplier for the resting hint, before a thumb has arrived. Present
## enough to say "put your thumb here", quiet enough not to compete with the room
## or with Little Buddy.
const REST_OPACITY: float = 0.62

## Rendered and looked at on a 1334 px phone frame. At 0.12 / 0.40 / 0.58 the
## stick was a pale smudge against a cream wall -- mint on cream is a
## low-contrast pairing by design, the whole palette is pastel, so the control
## has to earn its visibility with opacity and with `deep(mint)` rather than with
## a colour §3 does not have. (`TapRipple` learned the same lesson at 0.60.)
const BASE_FILL_ALPHA: float = 0.17
const BASE_RING_ALPHA: float = 0.62
const KNOB_ALPHA: float = 0.80
const KNOB_RIM_ALPHA: float = 0.85

## No touch or mouse pointer owns the gesture. Same sentinel scheme as
## `draggable_object.gd`, which needs it for the same reason: with
## `emulate_mouse_from_touch` on, one finger produces BOTH an
## `InputEventScreenTouch` and a synthetic `InputEventMouseButton`, and only a
## latch stops the pair being read as two gestures.
const NO_POINTER: int = -1000000
const MOUSE_POINTER_INDEX: int = -1

var _enabled: bool = true
var _pointer: int = NO_POINTER
var _origin: Vector2 = Vector2.ZERO
var _current: Vector2 = Vector2.ZERO
var _output: Vector2 = Vector2.ZERO
var _live: bool = false
var _left_dead_zone: bool = false
var _pressed_msec: int = 0
var _built: bool = false


func _ready() -> void:
	build()


## Idempotent and called from every public method: `_ready()` does not fire for a
## node added to the root in the headless runner.
func build() -> void:
	if _built:
		return
	_built = true
	name = "VirtualJoystick"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Purely a drawing surface. Every touch reaches this node through
	# `_unhandled_input`, which is AFTER the GUI and after physics picking -- so
	# the Next and Speak buttons, and every `DraggableObject`, keep winning.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_unhandled_input(true)


## -- The pure half -------------------------------------------------------------

## Where a thumb may land and start the stick, for a viewport of `viewport_size`
## and safe-area `insets` (left, top, right, bottom).
##
## The width is clamped twice: once to a comfortable range, and once against the
## centre of the screen, because `house_hud.gd` anchors Speak to centre-bottom
## and Next to bottom-right. That second clamp is the one that matters, and it is
## expressed against the live viewport width rather than against a device, so it
## holds at 4:3 and at 2.17:1 alike.
static func activation_rect(viewport_size: Vector2, insets: Vector4) -> Rect2:
	var left: float = maxf(insets.x, 0.0)
	var bottom: float = viewport_size.y - maxf(insets.w, 0.0)

	var width: float = clampf(viewport_size.x * ZONE_WIDTH_RATIO, ZONE_MIN_WIDTH, ZONE_MAX_WIDTH)
	var centre_limit: float = viewport_size.x * 0.5 - HUD_SPEAK_HALF_WIDTH - CENTRE_CLEARANCE
	width = minf(width, maxf(centre_limit - left, MAX_RADIUS * 2.0))

	var height: float = clampf(viewport_size.y * ZONE_HEIGHT_RATIO, ZONE_MIN_HEIGHT, ZONE_MAX_HEIGHT)
	height = minf(height, maxf(bottom - maxf(insets.y, 0.0), MAX_RADIUS * 2.0))

	return Rect2(left, bottom - height, width, height)


## Where the resting hint sits: low and to the left, where a thumb already is
## when a phone is held in landscape, and a full `MAX_RADIUS` clear of both edges
## so the hint ring is never cropped.
static func rest_origin(zone: Rect2) -> Vector2:
	var inset: float = MAX_RADIUS + KNOB_RIM_WIDTH * 4.0
	return Vector2(
		zone.position.x + minf(inset, zone.size.x * 0.5),
		zone.position.y + zone.size.y - minf(inset, zone.size.y * 0.5)
	)


## Output magnitude for `travel`, the dead-zone-compensated 0..1 deflection.
##
## Never greater than 1.0 -- the character multiplies this by `WALK_SPEED` and
## the walk speed is a ceiling, not a suggestion.
static func response(travel: float) -> float:
	var t: float = clampf(travel, 0.0, 1.0)
	if t <= 0.0:
		return 0.0
	var shaped: float = t * (CURVE_LINEAR + (1.0 - CURVE_LINEAR) * t)
	return clampf(MIN_OUTPUT + (1.0 - MIN_OUTPUT) * shaped, 0.0, 1.0)


## The whole stick, as a function of where the thumb landed and where it is now.
##
## Returns camelCase:
##   `live`      bool    -- past the dead zone
##   `x` / `y`   float   -- analog output, screen axes, magnitude <= 1
##   `magnitude` float
##   `knob`      Vector2 -- offset of the knob from the origin, clamped to
##                          `MAX_RADIUS` (drawing only)
static func resolve(origin: Vector2, current: Vector2) -> Dictionary:
	var offset: Vector2 = current - origin
	var distance: float = offset.length()
	var knob: Vector2 = offset
	if distance > MAX_RADIUS and distance > 0.0:
		knob = offset / distance * MAX_RADIUS

	var dead: float = MAX_RADIUS * DEAD_ZONE_RATIO
	if distance <= dead or distance <= 0.0:
		return {"live": false, "x": 0.0, "y": 0.0, "magnitude": 0.0, "knob": knob}

	var travel: float = (distance - dead) / maxf(MAX_RADIUS - dead, 0.001)
	var magnitude: float = response(travel)
	var direction: Vector2 = offset / distance
	return {
		"live": true,
		"x": direction.x * magnitude,
		"y": direction.y * magnitude,
		"magnitude": magnitude,
		"knob": knob,
	}


## -- The node half -------------------------------------------------------------

## True while this press belongs to the stick rather than to tap-to-walk. Asked
## by `navigation_controller.gd` before it routes a tap, so the two can never
## both act on one finger.
func claims_press(screen_position: Vector2) -> bool:
	build()
	if not _enabled:
		return false
	return get_activation_rect().has_point(screen_position)


## Begins a gesture. Returns true when the stick took the press.
##
## The origin is the press point EXACTLY -- not clamped, not snapped to a home
## position -- which is what makes this a floating stick and what guarantees a
## press alone never moves anybody.
func press(pointer_index: int, screen_position: Vector2) -> bool:
	build()
	if not _enabled:
		return false
	if _pointer != NO_POINTER:
		# Another finger already owns the stick. A second one is ignored outright,
		# exactly as `DraggableObject` ignores it, so two thumbs cannot fight.
		return false
	if not get_activation_rect().has_point(screen_position):
		return false

	_pointer = pointer_index
	_origin = screen_position
	_current = screen_position
	_output = Vector2.ZERO
	_live = false
	_left_dead_zone = false
	_pressed_msec = Time.get_ticks_msec()
	queue_redraw()
	grabbed.emit()
	return true


## Continues a gesture. Returns true when the event belonged to this stick.
func drag(pointer_index: int, screen_position: Vector2) -> bool:
	build()
	if _pointer == NO_POINTER or pointer_index != _pointer:
		return false
	_current = screen_position
	var state: Dictionary = resolve(_origin, _current)
	var was_live: bool = _live
	_live = bool(state["live"])
	if _live:
		_left_dead_zone = true
	_output = Vector2(float(state["x"]), float(state["y"]))
	queue_redraw()
	if _live or was_live:
		moved.emit(_output.x, _output.y)
	return true


## Ends a gesture. Returns true when the event belonged to this stick.
##
## A press that never left the dead zone and let go quickly was a tap, and is
## offered back to tap-to-walk rather than being swallowed: no part of the floor
## may become untappable just because the stick lives over it.
func release(pointer_index: int) -> bool:
	build()
	if _pointer == NO_POINTER or pointer_index != _pointer:
		return false
	var held_sec: float = float(Time.get_ticks_msec() - _pressed_msec) * 0.001
	var was_tap: bool = not _left_dead_zone and held_sec <= TAP_MAX_SEC
	var at: Vector2 = _current
	_reset()
	released.emit()
	if was_tap:
		tapped.emit(at.x, at.y)
	return true


## Drops any gesture without emitting a tap. Used when the stick is switched off
## under a thumb -- a summary screen opening, a room change, a cutscene.
func cancel() -> void:
	build()
	if _pointer == NO_POINTER:
		return
	_reset()
	released.emit()


## Off during an overlay, a transition or anything that disables the character.
## Switching off under a thumb cancels cleanly rather than latching the last
## output, which would walk Little Buddy into a wall behind a summary screen.
func set_enabled(value: bool) -> void:
	build()
	if _enabled == value:
		return
	_enabled = value
	if not value:
		cancel()
	visible = value
	queue_redraw()


func is_enabled() -> bool:
	build()
	return _enabled


## True while a thumb is past the dead zone and the character should be driving.
func is_active() -> bool:
	build()
	return _live


## True while a thumb is down, whether or not it has left the dead zone.
func is_held() -> bool:
	build()
	return _pointer != NO_POINTER


## Analog output, screen axes, magnitude 0..1.
func get_vector() -> Vector2:
	build()
	return _output


func get_origin() -> Vector2:
	build()
	return _origin


## Knob centre in screen coordinates -- for the render checks and the tests.
func get_knob_position() -> Vector2:
	build()
	if _pointer == NO_POINTER:
		return rest_origin(get_activation_rect())
	return _origin + (resolve(_origin, _current)["knob"] as Vector2)


func get_activation_rect() -> Rect2:
	build()
	return activation_rect(_viewport_size(), get_safe_insets())


## Safe-area insets (left, top, right, bottom) in viewport pixels.
##
## Deliberately the same shape and the same platform guard as
## `scripts/ui/safe_area.gd`: on macOS the platform reports the safe area in
## SCREEN coordinates rather than window coordinates, so it is ignored there and
## only the cosmetic minimum applies.
func get_safe_insets() -> Vector4:
	var left: float = MIN_MARGIN_HORIZONTAL
	var top: float = MIN_MARGIN
	var right: float = MIN_MARGIN_HORIZONTAL
	var bottom: float = MIN_MARGIN

	var platform: String = OS.get_name()
	if platform == "iOS" or platform == "Android":
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var window: Vector2i = DisplayServer.window_get_size()
		var viewport_size: Vector2 = _viewport_size()
		if window.x > 0 and window.y > 0 and safe.size.x > 0 and safe.size.y > 0 \
				and viewport_size.x > 0.0 and viewport_size.y > 0.0:
			var scale_x: float = viewport_size.x / float(window.x)
			var scale_y: float = viewport_size.y / float(window.y)
			left = maxf(left, float(safe.position.x) * scale_x)
			top = maxf(top, float(safe.position.y) * scale_y)
			right = maxf(right, float(window.x - (safe.position.x + safe.size.x)) * scale_x)
			bottom = maxf(bottom, float(window.y - (safe.position.y + safe.size.y)) * scale_y)

	return Vector4(left, top, right, bottom)


## -- Input ---------------------------------------------------------------------

## `_unhandled_input`, never `_input` and never `_gui_input`. Everything that
## already consumed the press -- a HUD button, a `DraggableObject` -- has done so
## by the time this runs, so nothing the child could already do stops working.
func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	var phase: Dictionary = describe_event(event)
	if phase.is_empty():
		return
	var pointer: int = int(phase["pointer"])
	var at: Vector2 = phase["position"]
	var claimed: bool = false
	match String(phase["phase"]):
		"press":
			claimed = press(pointer, at)
		"drag":
			claimed = drag(pointer, at)
		"release":
			claimed = release(pointer)
	if claimed:
		# Belt and braces. `navigation_controller.gd` also asks `claims_press()`
		# before routing a tap, so the two never both act on one finger even if
		# the input groups are ever visited in the other order.
		var viewport: Viewport = get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


## `{"phase": "press"|"drag"|"release", "pointer": int, "position": Vector2}`,
## or `{}` for an event this node has no opinion about. Static and pure, so the
## touch/mouse/emulated-mouse triple can be asserted without a touchscreen.
static func describe_event(event: InputEvent) -> Dictionary:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		return {
			"phase": "press" if touch.pressed else "release",
			"pointer": touch.index,
			"position": touch.position,
		}
	if event is InputEventScreenDrag:
		var slide: InputEventScreenDrag = event as InputEventScreenDrag
		return {"phase": "drag", "pointer": slide.index, "position": slide.position}
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return {}
		return {
			"phase": "press" if button.pressed else "release",
			"pointer": MOUSE_POINTER_INDEX,
			"position": button.position,
		}
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		return {"phase": "drag", "pointer": MOUSE_POINTER_INDEX, "position": motion.position}
	return {}


## -- Drawing -------------------------------------------------------------------

func _draw() -> void:
	if not _enabled:
		return
	var zone: Rect2 = get_activation_rect()
	var held: bool = _pointer != NO_POINTER
	var opacity: float = 1.0 if held else REST_OPACITY
	var centre: Vector2 = _origin if held else rest_origin(zone)
	var knob: Vector2 = centre
	if held:
		knob = _origin + (resolve(_origin, _current)["knob"] as Vector2)

	# Base: a soft mint disc, ringed in `deep(mint)`. The fill stays low so the
	# room reads straight through it (ART_BIBLE §8); the ring is what makes the
	# shape legible over a cream wall, where plain mint all but disappears.
	draw_circle(centre, MAX_RADIUS, _mint(BASE_FILL_ALPHA * opacity))
	draw_arc(centre, MAX_RADIUS, 0.0, TAU, 48, _rim(BASE_RING_ALPHA * opacity),
			RING_WIDTH, true)

	# Knob: mint, brighter, rimmed in `deep(mint)` for the same reason. `#000000`
	# is banned; §3's "Deep" step (22% toward `ink`) is the palette's own way of
	# drawing an edge, and it keeps the warmth.
	draw_circle(knob, KNOB_RADIUS, _mint(KNOB_ALPHA * opacity))
	draw_arc(knob, KNOB_RADIUS, 0.0, TAU, 32, _rim(KNOB_RIM_ALPHA * opacity),
			KNOB_RIM_WIDTH, true)


## Alpha applied to a palette token, without ever constructing a colour from
## numbers. There is no `Color(` anywhere in this file, and `test_joystick.gd`
## checks that there still isn't: a hand-typed colour is how a near-red or a
## `#000000` gets into a locked palette.
func _tint(base: Color, alpha: float) -> Color:
	var tinted: Color = base
	tinted.a = clampf(alpha, 0.0, 1.0)
	return tinted


func _mint(alpha: float) -> Color:
	return _tint(Palette.MINT, alpha)


func _rim(alpha: float) -> Color:
	return _tint(Palette.deep(Palette.MINT), alpha)


## -- Internals -----------------------------------------------------------------

func _reset() -> void:
	_pointer = NO_POINTER
	_output = Vector2.ZERO
	_live = false
	_left_dead_zone = false
	_pressed_msec = 0
	queue_redraw()


## `get_viewport_rect()` asserts nothing, but a node outside the tree has no
## viewport at all -- and in the headless runner that is every node. Falling back
## to the project's own base size keeps `activation_rect()` answerable there.
func _viewport_size() -> Vector2:
	if is_inside_tree():
		var live: Vector2 = get_viewport_rect().size
		if live.x > 0.0 and live.y > 0.0:
			return live
	# Out of the tree but sized by hand: that is how a headless case asks "what
	# would this look like on a 2217 x 1024 phone?" without opening a window.
	if size.x > 0.0 and size.y > 0.0:
		return size
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1366)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 1024))
	)
