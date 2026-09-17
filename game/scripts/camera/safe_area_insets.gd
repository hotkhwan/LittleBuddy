extends RefCounted

## Screen insets for 3D framing, as FRACTIONS of the screen.
##
## `scripts/ui/safe_area.gd` solves this for the 2D layer by inseting a `Control`
## in viewport pixels. That does nothing for the 3D room behind it: a bottle
## rendered under the Dynamic Island is still under the Dynamic Island. So the
## camera has to know about the same insets, in a form that survives being fed
## into a projection -- a fraction of the screen, not a pixel count, because the
## fit works in normalised device coordinates and never sees a resolution.
##
## Two separate things are combined here, and they are different in kind:
##
##   * **Platform safe area** -- notch, Dynamic Island, rounded corners, home
##     indicator. Reported by `DisplayServer.get_display_safe_area()`, per device,
##     per orientation. Asymmetric: a landscape iPhone has its notch on the left
##     or on the right depending on which way the child turned it, so left and
##     right are tracked independently and never averaged.
##   * **Game chrome** -- the star bar along the top and the prompt panel along
##     the bottom. Nothing to do with the hardware, but a bottle under the star
##     bar is exactly as unreachable as one under the notch.
##
## Both are expressed the same way and combined with a per-edge maximum, so
## whichever is worse on a given edge wins.

## Fractions of the screen the game's own HUD covers. The Baby Room's top bar is
## 86 px of a 1024 px-high viewport (~8%) and its prompt panels run to ~200 px at
## the bottom; these are rounded up a little so a room is never framed right up
## against the chrome. A room that knows better overrides them with the
## `chromeInsets` key in its framing metadata.
const CHROME_LEFT: float = 0.04
const CHROME_TOP: float = 0.10
const CHROME_RIGHT: float = 0.04
const CHROME_BOTTOM: float = 0.08

## No inset may eat this much of the screen; past it the usable window collapses
## and the fit would push the camera into the next room.
const MAX_INSET: float = 0.35


## `Vector4(left, top, right, bottom)`, the default game-chrome insets.
static func chrome_insets() -> Vector4:
	return Vector4(CHROME_LEFT, CHROME_TOP, CHROME_RIGHT, CHROME_BOTTOM)


## Converts a platform safe-area rectangle into per-edge screen fractions.
##
## Pure, so both notch orientations and both device families can be tested
## without a device: feed it the rectangle the device would report.
##
## A window of zero size, or a safe area that is not a sub-rectangle of it,
## returns no insets rather than a negative one -- the caller is about to combine
## with the chrome insets anyway, so "unknown" degrades to "the HUD margin".
static func insets_from_pixels(safe: Rect2i, window: Vector2i) -> Vector4:
	if window.x <= 0 or window.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var left: float = float(safe.position.x) / float(window.x)
	var top: float = float(safe.position.y) / float(window.y)
	var right: float = float(window.x - (safe.position.x + safe.size.x)) / float(window.x)
	var bottom: float = float(window.y - (safe.position.y + safe.size.y)) / float(window.y)
	return sanitise(Vector4(left, top, right, bottom))


## Per-edge maximum. Whichever of the two insets is worse on an edge wins there.
static func combine(a: Vector4, b: Vector4) -> Vector4:
	return sanitise(
		Vector4(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z), maxf(a.w, b.w))
	)


static func sanitise(insets: Vector4) -> Vector4:
	return Vector4(
		_clamp(insets.x), _clamp(insets.y), _clamp(insets.z), _clamp(insets.w)
	)


## The only impure function in this file: it reads the display server.
##
## Desktop is deliberately excluded, exactly as `safe_area.gd` excludes it -- on
## macOS the platform reports the safe area in SCREEN coordinates rather than
## window coordinates, which would inset a windowed run by the size of the menu
## bar and make every render taken on a Mac lie about the framing.
static func display_insets() -> Vector4:
	if not platform_reports_safe_area():
		return Vector4.ZERO
	return insets_from_pixels(
		DisplayServer.get_display_safe_area(), DisplayServer.window_get_size()
	)


## What the camera should actually use: the platform safe area and the game's
## chrome, combined.
static func current_insets(chrome: Vector4 = chrome_insets()) -> Vector4:
	return combine(display_insets(), sanitise(chrome))


static func platform_reports_safe_area() -> bool:
	var platform: String = OS.get_name()
	return platform == "iOS" or platform == "Android"


static func _clamp(value: float) -> float:
	if not is_finite(value):
		return 0.0
	return clampf(value, 0.0, MAX_INSET)
