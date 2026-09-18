extends Node3D

## The answer a floor tap gives back, before Little Buddy has moved a centimetre.
##
## ## Why this exists
##
## Tap routing already worked: 16 of 16 synthetic floor taps across a live room
## classified as FLOOR and were accepted. What did not work was the *feel*. A tap
## on bare floor produced nothing at all -- `NavigationController.floor_tapped`
## was consumed only by the Free Play and onboarding directors, to dismiss a
## hint, and nothing drew anything. The child pressed the floor, the screen did
## not react, and a fraction of a second later a small character somewhere else
## began to walk. Tapping the bed or the wardrobe only *felt* different because
## the bed is a big obvious thing you aimed at.
##
## So this draws the acknowledgement, on the frame of the press:
##
##   * a **pulse** -- a mint disc that springs outward from the tapped point and
##     fades in under half a second. This is the "I heard you";
##   * a **hold** -- a smaller mint disc that stays on the destination while
##     Little Buddy walks to it, and fades out when he arrives. This is the
##     "and that is where you sent me".
##
## Both are the same mint `go here` language `house_stage.gd` uses for a directed
## beat, deliberately: the game should have ONE vocabulary for "this spot
## matters", whether the game chose the spot or the child did.
##
## ## No Tween, on purpose
##
## `Tween` needs a live `SceneTree`, and the headless `--script` runner has
## neither a tree for this node nor frames to run it in. The animation is
## therefore a pure function of elapsed time (`pulse_state()`, `hold_alpha()`)
## stepped by `advance(delta)`, which `_process()` does nothing but forward. A
## test drives exactly the code a device runs, and the curve itself is assertable
## with no renderer at all.
##
## ## Budget
##
## Two unshaded, transparent, shadowless discs, built once and re-used. No
## particles, no light, no post-processing -- see the performance budget in
## `CLAUDE.md`.

const Palette := preload("res://scripts/ui/palette.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

## How long the outward pulse lasts. Short enough to read as an instant
## acknowledgement rather than as an animation the child has to wait through.
const PULSE_SEC: float = 0.42
## The pulse springs from roughly a fingertip to roughly a footprint.
## Starts INSIDE the destination disc and finishes well outside it. Rendered at
## 0.15 -> 0.62 the two were the same size for the first third of the animation
## and the ripple read as a single disc that flickered; the expansion has to be
## visible against the thing it expands out of.
const PULSE_START_RADIUS: float = 0.10
const PULSE_END_RADIUS: float = 0.78
## Rendered and looked at: at 0.60 over the warm wood floor the pulse was a pale
## smudge on a 1334 px phone frame. Mint against peach is a low-contrast pairing
## by design -- the whole palette is pastel -- so the marker has to earn its
## visibility with opacity rather than with a colour the art bible does not have.
const PULSE_ALPHA: float = 0.78

## The destination disc. Smaller than `HouseStage.BEAT_MARKER_RADIUS` (0.42), so
## a child-chosen spot never shouts louder than the one the story is asking for.
const HOLD_RADIUS: float = 0.30
const HOLD_ALPHA: float = 0.50
## Fade-out once the walk is over (or cancelled).
const HOLD_FADE_SEC: float = 0.24
## A hold nobody ever released -- a walk cut short by a room change, a summary
## screen, a skipped task -- tidies itself away rather than sitting on the floor
## for the rest of the level.
const HOLD_MAX_SEC: float = 6.0

## Lifted clear of the floor, and of `HouseStage`'s beat marker at +0.008, so
## neither z-fights with the floorboards nor with the other.
const HOLD_LIFT: float = 0.016
const PULSE_LIFT: float = 0.022

## Unit-radius discs, scaled on X/Z at runtime -- one mesh each, never rebuilt.
const DISC_HEIGHT: float = 0.01
const DISC_SEGMENTS: int = 20

var _pulse: MeshInstance3D = null
var _pulse_material: StandardMaterial3D = null
var _hold: MeshInstance3D = null
var _hold_material: StandardMaterial3D = null
var _built: bool = false

var _floor_y: float = 0.0
var _point: Vector3 = Vector3.ZERO

var _pulse_elapsed: float = -1.0
var _hold_elapsed: float = -1.0
## Seconds since `release()`; negative while the hold is still being held.
var _release_elapsed: float = -1.0


func _ready() -> void:
	_ensure_built()
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


## -- The pure half ------------------------------------------------------------

## The pulse disc at `elapsed` seconds:
##   `active` bool, `radius` metres, `alpha` 0..1.
##
## Radius eases OUT (fast at first, settling) so the disc reads as a reaction to
## a press rather than as something inflating. Alpha falls linearly to nothing at
## `PULSE_SEC`, so the disc always leaves cleanly and never lingers at 1% opacity.
static func pulse_state(elapsed: float) -> Dictionary:
	if elapsed < 0.0 or elapsed >= PULSE_SEC:
		return {"active": false, "radius": PULSE_END_RADIUS, "alpha": 0.0}
	var t: float = clampf(elapsed / PULSE_SEC, 0.0, 1.0)
	var eased: float = 1.0 - (1.0 - t) * (1.0 - t)
	return {
		"active": true,
		"radius": lerpf(PULSE_START_RADIUS, PULSE_END_RADIUS, eased),
		"alpha": PULSE_ALPHA * (1.0 - t),
	}


## Opacity of the destination disc.
##
## `held_for` is seconds since the tap; `released_for` is seconds since the walk
## ended, or negative while it is still under way. Full opacity from the first
## frame -- this is feedback, not a fade-in -- then a short fade once the walk is
## over, and a hard stop at `HOLD_MAX_SEC` so an abandoned hold cannot outlive
## the level.
static func hold_alpha(held_for: float, released_for: float) -> float:
	if held_for < 0.0 or held_for >= HOLD_MAX_SEC:
		return 0.0
	if released_for < 0.0:
		return HOLD_ALPHA
	if released_for >= HOLD_FADE_SEC:
		return 0.0
	return HOLD_ALPHA * (1.0 - released_for / HOLD_FADE_SEC)


## -- The node half ------------------------------------------------------------

## Acknowledges a tap at world `(x, z)`. Both discs snap on in the same frame:
## there is no "appear" animation, because a delayed acknowledgement is the exact
## thing this file exists to remove.
func show_at(x: float, z: float, floor_y: float = 0.0) -> void:
	_ensure_built()
	_floor_y = floor_y
	_point = Vector3(x, floor_y, z)
	_pulse_elapsed = 0.0
	_hold_elapsed = 0.0
	_release_elapsed = -1.0
	_apply()


## The walk is over (arrived, cancelled, or refused). Fades the destination disc
## out; the pulse is unaffected and finishes on its own.
func release() -> void:
	if _hold_elapsed < 0.0 or _release_elapsed >= 0.0:
		return
	_release_elapsed = 0.0
	_apply()


## Everything off, now. Used when the world stops accepting taps at all.
func dismiss() -> void:
	_pulse_elapsed = -1.0
	_hold_elapsed = -1.0
	_release_elapsed = -1.0
	_apply()


## The whole animation step. `_process()` forwards to this and does nothing else,
## so a headless test drives exactly what a device does.
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var moved: bool = false
	if _pulse_elapsed >= 0.0:
		_pulse_elapsed += delta
		moved = true
	if _hold_elapsed >= 0.0:
		_hold_elapsed += delta
		if _release_elapsed >= 0.0:
			_release_elapsed += delta
		moved = true
	if moved:
		_apply()


## True while anything at all is on screen.
func is_showing() -> bool:
	return bool(pulse_state(_pulse_elapsed)["active"]) \
			or hold_alpha(_hold_elapsed, _release_elapsed) > 0.0


func is_holding() -> bool:
	return hold_alpha(_hold_elapsed, _release_elapsed) > 0.0


## Where the last acknowledged tap landed, in world space.
func get_point() -> Vector3:
	return _point


func get_pulse_radius() -> float:
	return float(pulse_state(_pulse_elapsed)["radius"])


## -- Internals ----------------------------------------------------------------

## Idempotent and called from every public method: `_ready()` never fires for a
## node added to the root in the headless runner.
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_hold = _make_disc("Hold", HOLD_LIFT)
	_hold_material = _hold.material_override as StandardMaterial3D
	add_child(_hold)
	_pulse = _make_disc("Pulse", PULSE_LIFT)
	_pulse_material = _pulse.material_override as StandardMaterial3D
	add_child(_pulse)
	_apply()


func _make_disc(disc_name: String, lift: float) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = DISC_HEIGHT
	mesh.radial_segments = DISC_SEGMENTS
	mesh.rings = 0

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(Palette.MINT.r, Palette.MINT.g, Palette.MINT.b, 0.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Unshaded: a floor marker must read the same under any light, and the budget
	# rules out anything that would make it interesting to light.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 1.0
	material.metallic = 0.0

	var disc: MeshInstance3D = MeshInstance3D.new()
	disc.name = disc_name
	disc.mesh = mesh
	disc.material_override = material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position = Vector3(0.0, lift, 0.0)
	disc.visible = false
	return disc


func _apply() -> void:
	if not _built:
		return
	SpatialUtil.set_world_position(self, _point)

	var pulse: Dictionary = pulse_state(_pulse_elapsed)
	var pulse_alpha: float = float(pulse["alpha"])
	_pulse.visible = pulse_alpha > 0.0
	if _pulse.visible:
		var radius: float = float(pulse["radius"])
		_pulse.scale = Vector3(radius, 1.0, radius)
		_pulse_material.albedo_color = Color(
			Palette.MINT.r, Palette.MINT.g, Palette.MINT.b, pulse_alpha)

	var held: float = hold_alpha(_hold_elapsed, _release_elapsed)
	_hold.visible = held > 0.0
	if _hold.visible:
		_hold.scale = Vector3(HOLD_RADIUS, 1.0, HOLD_RADIUS)
		_hold_material.albedo_color = Color(
			Palette.MINT.r, Palette.MINT.g, Palette.MINT.b, held)
