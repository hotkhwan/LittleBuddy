extends RefCounted

## The house's light, as numbers with reasons — and as the only place those
## numbers are written down twice on purpose.
##
## `scenes/house/house_world.tscn` carries the LIVE values, because a scene that
## needs a script to look right is a scene that looks wrong in the editor. This
## file carries the SAME values as constants plus the set they replaced, so that
##
##   * `tests/shots_lighting.gd` can photograph the before and the after through
##     one code path, in one run, from one scene — a real controlled pair rather
##     than two screenshots taken a commit apart, and
##   * `tests/cases/test_lighting_house.gd` can assert the scene still agrees
##     with `AFTER`, so the two copies cannot drift.
##
## ## What is and is not allowed in here
##
## `ART_BIBLE.md` §7 is a gate, not advice: exactly ONE `DirectionalLight3D`, no
## GI, no SSAO/SSIL/SSR, no glow, no volumetric fog, no depth of field, no
## colour-correction post, no screen-space anything. Directional shadows are OFF
## by owner decision taken on a physical iPhone (§7 amendment, 2026-09-18) and
## nothing here turns them back on. Every value below is an `Environment`
## property or a light property: the cost of this pass at runtime is zero.
##
## ## Geometry, because it is the part that was wrong — twice
##
## A `DirectionalLight3D` lights along **-Z of its own basis**, so `+Z` of the
## basis is the direction TOWARDS the sun, and a surface is lit by
## `dot(normal, toSun)`.
##
## **The sun was under the floor.** `house_world.tscn` stored the key light as
## `Transform3D(0.7826, 0, 0.6225, 0.4769, 0.6428, -0.5995, -0.4001, 0.766,
## 0.5031, ...)`, whose *rows* are the three vectors somebody intended as
## *columns*. `Transform3D(...)` takes rows. The transpose of a rotation matrix
## is another perfectly valid rotation, so nothing warned and nothing looked
## broken enough to chase: the house was simply lit from `(0.623, -0.599, 0.503)`
## — **36.8° BELOW the horizon**, from the right, shining upwards. The scene
## comment saying "mid-morning sun from the upper left, rotation (-50, -34, 0)"
## described a light the file did not contain. Read back live from the running
## scene, the authored angles were elevation **-36.8°**, azimuth **+51.1°**.
##
## That one fact explains the symptoms better than any amount of ambient tuning:
##
##   * every UPWARD-facing surface — the floor, the worktop, the table, the bed,
##     the window sill, the top of every head and every shoulder — received
##     **zero** key light and sat at flat ambient. Those are most of the pixels.
##   * every DOWNWARD-facing surface got the full key, which is the exact
##     inverse of how a room looks and why nothing had weight.
##   * the only planes with any modelling left were the walls, and two of those
##     came out over 1.0 and clipped (below), so the frame's whole value range
##     was "ambient" and "white".
##
## `WORLD_POLISH_PASS.md` §8 and `house_layout.gd`'s towel comment both read the
## same matrix the same wrong way and concluded "the sun's X component is
## negative, so the -X wall is never lit". The X component was **positive**, and
## the -X wall was the lit one; the towel hanging on it was fine. Correcting the
## record is most of this pass.
##
## The one thing no azimuth can fix: the two side walls have exactly opposite
## inner normals, so one `dot` is the negation of the other. **With one
## directional light, one side wall is always at pure ambient**, and §8's "a ~20°
## swing so both side walls catch it unequally rather than one not at all" is
## geometrically impossible. What the azimuth really buys is the RATIO between
## the lit side wall and the back wall: three planes at three values, instead of
## two of them clipped to the same white.

const Palette := preload("res://scripts/ui/palette.gd")

## Elevation and azimuth in degrees, the way a lighting note would state them,
## rather than as twelve decimals of a `Transform3D`.
##
##   `elevation`  degrees above the horizon. 90 is directly overhead, and a
##                NEGATIVE value is a sun below the floor, which is what the
##                house shipped with.
##   `azimuth`    degrees from the camera's `+Z` axis, i.e. from "the sun is
##                directly behind the viewer". POSITIVE puts the sun to screen
##                RIGHT, which lights the room's `-X` (screen-left) wall.
##
## `BEFORE` is not the comment in the old scene file, it is what that file
## actually did, read back live off the running light. Photograph it with
## `shots_lighting.gd -- before` and it reproduces the shipped house exactly.
const BEFORE: Dictionary = {
	"name": "before",
	"backgroundColor": Color(0.921, 0.877, 0.806),
	"ambientColor": Color(1.0, 0.965, 0.898),   # #FFF6E5, `cream` exactly
	"ambientEnergy": 0.62,
	"keyColor": Color(1.0, 0.961, 0.898),       # #FFF5E5
	"keyEnergy": 1.12,
	"elevation": -36.83,
	"azimuth": 51.06,
	"angularDistance": 1.2,
}

## The pass. **Nothing here is brighter; the sun is above the floor and the
## frame has a value range again.**
##
## Four numbers, and the reason for each:
##
## **Elevation -36.8 -> +48.** The whole fix. Up-facing surfaces go from zero key
## to `0.74` of it, so the floor, the worktop, the table and the tops of heads
## and shoulders become the brightest plane in the room — which is what a room
## lit from a window looks like, and is what gives every object its weight back.
##
## **Azimuth +51.1 -> +58.** Nearly unchanged, and deliberately so: the sun stays
## on the same side it has always appeared to be on, so the `-X` wall that the
## bathroom towel hangs on stays the lit one and no room's composition flips. The
## extra 7° widens the gap between the lit side wall (`0.57` of key) and the back
## wall (`0.35`), which is the "adjacent surfaces must read as different planes"
## requirement: three walls, three values, none of them clipped.
##
## **Key 1.12 -> 0.61.** Not a mood choice, an exposure one. With the sun under
## the floor only two planes caught it and both came out over `1.0` in linear
## light (`1.18` and `1.07`) and clipped to the same near-white: 24.5% of the
## kitchen frame sat at or above 0.97 luminance. Lift the sun and FIVE times as
## much surface catches it, so the same energy would have blown the room out
## completely. At `0.61` the brightest large field lands at `0.973` — under the
## ceiling, with headroom left for a white prop in front of it.
##
## **Ambient 0.62 -> 0.52, and no longer `cream`.** `cream` ambient on `cream`
## walls is a tautology: it can only ever produce more cream, which is the
## "milky" complaint stated as a colour identity. §3's rule is "never darken by
## reducing value alone — always mix toward `ink`", so the fill is
## `CREAM -> PEACH` at 0.35 (`#FFEAD5`), a palette mix rather than an invented
## colour. The shaded side of every form now goes WARM rather than pale.
##
## The resulting ladder on a `cream` wall, in linear light: up-facing `0.973`,
## lit side wall `0.877`, back wall `0.718`, shaded side wall `0.520` — four
## clearly separate planes, the deepest of them still a warm light beige, and
## nothing anywhere near `#000000`.
##
## (The paragraphs above previously quoted `0.72` and `0.44` — the values of an
## earlier draft of this same pass, left behind when the numbers were settled.
## They are corrected here against the constants below, which are what ships and
## what `test_lighting_house.gd` pins to the scene file.)
const AFTER: Dictionary = {
	"name": "after",
	## Deeper and warmer than before. This is §5's "soft cream void" above an
	## open-topped room; when it was nearly the brightest thing in frame the
	## room read as a cut-out held in front of a light box.
	"backgroundColor": Color(0.8958, 0.852, 0.7814),  # CREAM -> INK at 0.16
	"ambientColor": Color(1.0, 0.9167, 0.8336), # CREAM -> PEACH at 0.35, #FFEAD5
	"ambientEnergy": 0.52,
	"keyColor": Color(1.0, 0.9346, 0.8575),     # CREAM -> PEACH at 0.22, #FFEEDB
	"keyEnergy": 0.61,
	"elevation": 48.0,
	"azimuth": 61.0,
	## A wider sun disc softens the terminator across the characters' rounded
	## volumes. Free: a shader constant, and with shadows off it costs nothing.
	"angularDistance": 2.4,
}


## The alternative the LOOK pass measured and REJECTED, kept because the
## rejection is the finding and an undocumented rejection gets re-proposed.
##
## `docs/LIGHTING_PASS.md` §7.3 flagged the shaded (`+X`) wall, at screen
## luminance 0.372, as "the value most likely to come back from a device review
## … one number (`ambientEnergy`) away from being lifted". This is that number
## lifted, with the key dropped to pay for it so total energy still does not
## rise (0.58 + 0.55 = 1.13, exactly what ships).
##
## It does lift the shaded wall. It also flattens everything else, and the four
## planes are what the whole pass was for:
##
## | plane | ships (0.52/0.61) | lifted (0.58/0.55) |
## |---|---|---|
## | floor, up-facing | 0.973 | **0.989** — 0.011 from clipping |
## | `-X` wall, lit | 0.877 | 0.902 |
## | back wall | 0.718 | 0.758 |
## | `+X` wall, fill only | 0.520 | 0.580 |
## | **floor : shaded wall** | **1.87** | **1.71** |
##
## The frame's whole contrast range shrinks by 9% to lift its darkest large
## field by one step, and the brightest one goes to 0.989, which leaves nothing
## at all for a white prop in front of it. Photographed as `alt_*.png` and
## looked at: the rooms read flatter, and the corner between the back wall and
## the shaded wall — the only corner a single directional light can draw on that
## side — is the first thing to go.
const LIFTED_FILL: Dictionary = {
	"name": "lift",
	"backgroundColor": Color(0.8958, 0.852, 0.7814),
	"ambientColor": Color(1.0, 0.9167, 0.8336),
	"ambientEnergy": 0.58,
	"keyColor": Color(1.0, 0.9346, 0.8575),
	"keyEnergy": 0.55,
	"elevation": 48.0,
	"azimuth": 61.0,
	"angularDistance": 2.4,
}


## Named setups, for a harness that takes one on the command line.
##
## `previous` is an alias for `AFTER`: the LOOK pass changed no house-light
## value, so the house's before and after are the same light on purpose, and the
## harness's `previous` tag differs from `after` only in the camera's close-up
## framing and in the menu's shadow. Saying so here is cheaper than a reader
## discovering it from two identical renders.
static func setup(setup_name: String) -> Dictionary:
	match setup_name:
		"before":
			return BEFORE
		"lift":
			return LIFTED_FILL
		_:
			return AFTER


## The unit vector pointing AT the sun, from elevation/azimuth in degrees.
static func to_sun(elevation: float, azimuth: float) -> Vector3:
	var pitch: float = deg_to_rad(elevation)
	var yaw: float = deg_to_rad(azimuth)
	var horizontal: float = cos(pitch)
	return Vector3(horizontal * sin(yaw), sin(pitch), horizontal * cos(yaw))


## The light's basis: `-Z` is where the light travels, so `+Z` is `to_sun`.
## Built from the Y/X euler pair the scene file stores, so the matrix in the
## scene and the two angles in this file are provably the same rotation.
static func key_basis(elevation: float, azimuth: float) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(-elevation), deg_to_rad(azimuth), 0.0))


## How much key light a surface with this normal receives, 0.0 to 1.0. The
## number that decides whether two adjacent planes read as two planes.
static func key_fraction(normal: Vector3, values: Dictionary) -> float:
	var sun: Vector3 = to_sun(float(values["elevation"]), float(values["azimuth"]))
	return maxf(0.0, normal.normalized().dot(sun))


## Applies a setup to a live scene. Used by the benchmark and by the tests; the
## game itself never calls this, because the scene already holds `AFTER`.
static func apply(environment: Environment, light: DirectionalLight3D,
		values: Dictionary) -> void:
	if environment != null:
		environment.background_color = values["backgroundColor"]
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = values["ambientColor"]
		environment.ambient_light_energy = float(values["ambientEnergy"])
	if light != null:
		light.light_color = values["keyColor"]
		light.light_energy = float(values["keyEnergy"])
		light.light_angular_distance = float(values["angularDistance"])
		light.shadow_enabled = false
		light.transform.basis = key_basis(
			float(values["elevation"]), float(values["azimuth"]))
