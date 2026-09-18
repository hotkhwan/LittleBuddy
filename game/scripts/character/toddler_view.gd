extends Node3D

## ============================================================================
## TEMPORARY ENGINEERING ART. NOT THE FINAL TODDLER.
## ============================================================================
##
## A procedural stand-in for Little Buddy as a toddler: rounded primitives only,
## 0.85 m tall, built to `docs/ART_BIBLE_DRAFT.md` §4 so that it is *readable*
## rather than merely present. The real model comes from the art pipeline later;
## when it arrives this node is deleted and **nothing above it changes**, because:
##
##   * `LittleBuddyCharacter` finds an `AnimationPlayer` anywhere in its subtree
##     and drives it only through SEMANTIC action names ("walk", "drink",
##     "brushTeeth") -- never a clip name;
##   * the movement, facing, arrival and interaction-ready behaviour all live in
##     `character_movement_controller.gd`, which holds no node at all.
##
## Do not let content or missions reference this node. Do not make it clever.
##
## ## What it is allowed to be good at
##
## The brief's priority is child-visible quality, and the art bible's first test
## is *recognition*. So the six actions a child actually sees in Chapter 3 --
## idle, walk, eat, drink, hug, sleep -- are animated well enough to be
## understood without audio, and the face follows §4.2: eyes below the head
## midline, one solid ink iris, exactly one catchlight, permanent blush, no
## teeth, mitt hands, oversized feet. Everything is a rounded volume; there is
## not one flat plane or hard edge on the body.
##
## ## What it is deliberately NOT good at
##
## `wave`, `point`, `clap`, `pickUp`, `give` and `brushTeeth` have **no clip on
## purpose**. They keep the graceful-degradation path live in the shipped build
## rather than only in a test fixture: asking for one today is a short pause that
## still completes cleanly, which is what lets content authoring run ahead of
## animation authoring. `test_house_world.gd` pins `brushTeeth` specifically.
##
## ## Scale is real
##
## The whole greybox house is dimensioned against `HEIGHT` (contract §3): a
## toddler is ~0.85 m tall, which is why a door is 1.9 m and a counter is 0.9 m.
##
## ## Rotation conventions, written down because a sign error here is invisible
##
## `ART_UPGRADE_REPORT.md` records a smile that shipped as a perfect frown
## because of an inverted Z-rotation sign, and it survived three render passes.
## So, derived rather than guessed:
##
##   * Little Buddy faces **-Z**. The nose, eyes and mouth are all at negative Z.
##   * A limb pivot points **down** (local -Y). Under `rotation.x = +a` it maps to
##     `(0, -cos a, -sin a)`, so **positive X swings a limb forward** (toward -Z).
##   * Under `rotation.z = c` it maps to `(sin c, -cos c, 0)`, so a limb goes
##     toward -X for negative `c`. The left arm sits at -X, so
##     **`rotation.z = side * angle` raises both arms outward**, where
##     `side` is -1 on the left and +1 on the right.
##   * The torso and head pivots point **up** (local +Y), which inverts the first
##     rule for them: **head/torso tip FORWARD under a NEGATIVE `rotation.x`**,
##     and look up under a positive one.
##   * The mouth is not rotated at all, and is not assembled from pieces whose
##     relative heights could be flipped. It is the bottom arc of a circle, so
##     its middle is its lowest point by construction. `test_toddler_view.gd`
##     asserts that on the generated vertices.

## Overall height, metres. The house is built to this. Do not change it without
## re-checking every camera framing in the project.
const HEIGHT: float = 0.85

## -- Palette (contract §7, locked). `#000000` is banned; `ink` is the only dark.
const SKIN: Color = Color(1.0, 0.871, 0.741)          # skinLight  #FFDEBD
const SKIN_SHADE: Color = Color(1.0, 0.820, 0.678)    # nose bump  #FFD1AD
const SHIRT: Color = Color(0.659, 0.902, 0.812)       # mint       #A8E6CF
const TROUSERS: Color = Color(0.604, 0.753, 0.851)    # dustyBlue  #9AC0D9
const HAIR: Color = Color(0.722, 0.549, 0.420)        # hair base  #B88C6B
const INK: Color = Color(0.349, 0.259, 0.169)         # ink        #59422B
const CATCHLIGHT: Color = Color(0.980, 0.961, 0.929)  # warm white #FAF5ED
const BLUSH: Color = Color(1.0, 0.757, 0.800)         # softPink   #FFC1CC
const MOUTH: Color = Color(0.620, 0.310, 0.302)       # mouth      #9E4F4D

## -- Proportions. A big head on a short body, ~1:3.1 head-to-height. Wrong
## proportions are the fastest way to make a placeholder read as "small adult".
const LEG_HEIGHT: float = 0.22
const LEG_RADIUS: float = 0.048
const HIP_Y: float = LEG_HEIGHT
const TORSO_HEIGHT: float = 0.30
const TORSO_RADIUS: float = 0.118
const SHOULDER_Y: float = 0.30      # local to the torso pivot
const SHOULDER_X: float = 0.130
const ARM_LENGTH: float = 0.17
const ARM_RADIUS: float = 0.040
const HAND_RADIUS: float = 0.055    # a soft mitt; §4.1 bans separate fingers
const HEAD_RADIUS: float = 0.135
const HEAD_Y: float = 0.70          # world-space; head top lands at ~0.85
const HEAD_LOCAL_Y: float = HEAD_Y - HIP_Y

## Feet are ~1.15x naturalistic and rounded: "reads as stable and toy-like".
const FOOT_SIZE: Vector3 = Vector3(0.054, 0.036, 0.075)

## -- Face. §4.2: eyes LARGE (~20% of head width) and set BELOW the midline.
const EYE_RADIUS: float = 0.027
const EYE_SCALE: Vector3 = Vector3(1.0, 1.22, 0.78)   # soft vertical oval
const EYE_X: float = 0.053
const EYE_Y: float = -0.024                            # below the head centre
const EYE_Z: float = -0.114
## Exactly one catchlight per eye, upper-LEFT as the viewer sees it. This single
## detail is what makes the eyes look alive (§4.2), and getting its side wrong is
## invisible in every assertion, so: Little Buddy faces -Z, therefore a viewer
## looking at his face stands at -Z and looks along +Z. For that viewer
## `right = forward x up = (0,0,1) x (0,1,0) = (-1,0,0)`, so world **-X is the
## viewer's right** and world **+X is the viewer's left**. The offset is
## therefore POSITIVE in X. The first render pass had it negative and put the
## catchlight on the wrong side of both eyes.
const CATCHLIGHT_RADIUS: float = 0.0062
const CATCHLIGHT_OFFSET: Vector3 = Vector3(0.0102, 0.0128, -0.019)
const BLUSH_RADIUS: float = 0.030
const BLUSH_SCALE: Vector3 = Vector3(0.86, 0.58, 0.22)
const MOUTH_Y: float = -0.079
const MOUTH_Z: float = -0.108
## The smile arc. It is the BOTTOM of a circle centred above the mouth, so its
## lowest point is the middle and both corners are higher -- a smile by
## construction rather than by a sign that can be inverted. See `_smile_mesh()`.
const MOUTH_SEGMENTS: int = 8
const MOUTH_ARC_RADIUS: float = 0.050
const MOUTH_HALF_ANGLE: float = 0.663   # ~38 degrees; mouth width ~23% of the head
const MOUTH_THICKNESS: float = 0.0052
const MOUTH_LIFT: float = 0.0022        # floats just clear of the skin

## -- Mesh density. Godot's primitive defaults are ~4,000 tris for a single
## sphere, which would blow the 2,500-4,000 tri character budget on the head
## alone. These keep the whole child inside it while staying visibly round.
const SEG_LARGE: Vector2i = Vector2i(16, 8)
const SEG_MEDIUM: Vector2i = Vector2i(12, 6)
const SEG_SMALL: Vector2i = Vector2i(8, 4)
const SEG_TINY: Vector2i = Vector2i(6, 3)

const SIDES: Array[float] = [-1.0, 1.0]

var _animation_player: AnimationPlayer = null
var _body: Node3D = null
var _built: bool = false
var _materials: Dictionary = {}


func _ready() -> void:
	build()


## Idempotent and callable before `_ready()` -- the headless `--script` runner
## never fires `_ready()` for nodes added to the root.
func build() -> void:
	if _built:
		return
	_built = true
	_build_body()
	_build_animations()


func get_animation_player() -> AnimationPlayer:
	build()
	return _animation_player


## Diagnostic only: the triangle count of everything built, so the art budget can
## be asserted rather than assumed.
func count_triangles() -> int:
	build()
	return _count_triangles(self)


## -- Body ----------------------------------------------------------------------
##
## Node layout, chosen so every animation below is a rotation on a pivot rather
## than a mesh sliding through space:
##
##   Body                     whole-child bob, lean, and lying down
##     LegLeft / LegRight     pivot at the hip
##       Mesh, Foot
##     Torso                  pivot at the waist
##       Mesh
##       ArmLeft / ArmRight   pivot at the shoulder
##         Mesh, Hand
##       Head                 pivot at the neck
##         Mesh, Hair*, Ear*, EyeLeft/EyeRight (+Catchlight), Nose, Blush*, Mouth

func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	for side: float in SIDES:
		var leg := Node3D.new()
		leg.name = "LegLeft" if side < 0.0 else "LegRight"
		leg.position = Vector3(side * 0.058, HIP_Y, 0.0)
		_body.add_child(leg)
		# `_capsule()` adds one radius to the length, so the leg's TOTAL height is
		# `LEG_HEIGHT - FOOT_SIZE.y * 2` and the foot makes up the rest. Sized
		# this way the sole lands exactly on y = 0: the first version overshot and
		# put 48 mm of the child through the floor, which is invisible against an
		# opaque floor and very visible the moment he stands on anything thin.
		var shin: float = LEG_HEIGHT - FOOT_SIZE.y * 2.0
		_capsule(leg, "Mesh", LEG_RADIUS, shin - LEG_RADIUS, TROUSERS,
				Vector3(0.0, -shin * 0.5, 0.0))
		# Bare toddler feet, rounded and oversized. Nudged forward so the child
		# reads as standing rather than balancing on two dots.
		var foot: MeshInstance3D = _sphere(leg, "Foot", 1.0, SKIN,
				Vector3(0.0, -LEG_HEIGHT + FOOT_SIZE.y, -0.018), SEG_SMALL)
		foot.scale = FOOT_SIZE

	# A rounded seat joining the legs to the torso -- without it the waist is a
	# visible notch, which is exactly the hard-edged look §4.1 bans.
	_sphere(_body, "Hips", TORSO_RADIUS * 0.86, TROUSERS,
			Vector3(0.0, HIP_Y + 0.01, 0.0), SEG_MEDIUM).scale = Vector3(1.0, 0.8, 0.95)

	var torso := Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0.0, HIP_Y, 0.0)
	_body.add_child(torso)
	_capsule(torso, "Mesh", TORSO_RADIUS, TORSO_HEIGHT, SHIRT,
			Vector3(0.0, TORSO_HEIGHT * 0.52, 0.0))

	for side: float in SIDES:
		# A sleeve cap in the shirt colour. The first render had a visible cream
		# gap between each arm and the body: a capsule meeting a capsule tangent
		# to tangent reads as detached however much they overlap, and a detached
		# arm fails §4.1's silhouette test outright.
		_sphere(torso, "ShoulderLeft" if side < 0.0 else "ShoulderRight",
				ARM_RADIUS * 1.28, SHIRT,
				Vector3(side * (SHOULDER_X - 0.008), SHOULDER_Y - 0.006, 0.0), SEG_SMALL)
		var arm := Node3D.new()
		arm.name = "ArmLeft" if side < 0.0 else "ArmRight"
		arm.position = Vector3(side * SHOULDER_X, SHOULDER_Y, 0.0)
		torso.add_child(arm)
		_capsule(arm, "Mesh", ARM_RADIUS, ARM_LENGTH, SKIN,
				Vector3(0.0, -ARM_LENGTH * 0.5, 0.0))
		# A soft mitt. §4.1: no separated fingers at this age, ever.
		_sphere(arm, "Hand", HAND_RADIUS, SKIN, Vector3(0.0, -ARM_LENGTH - 0.01, 0.0), SEG_SMALL)

	# §4.1 asks for "a short soft neck from Toddler up". It is mostly swallowed by
	# the head and the shirt, which is the point -- it exists so the head does not
	# read as fused to the shoulders in profile.
	_sphere(torso, "Neck", 0.056, SKIN, Vector3(0.0, HEAD_LOCAL_Y - 0.100, 0.0), SEG_SMALL)

	_build_head(torso)


func _build_head(torso: Node3D) -> void:
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, HEAD_LOCAL_Y, 0.0)
	torso.add_child(head)

	# Slightly flattened sphere, per §4.1.
	_sphere(head, "Mesh", HEAD_RADIUS, SKIN, Vector3.ZERO, SEG_LARGE).scale = \
			Vector3(1.0, 0.94, 1.0)

	# Hair as 2-5 solid rounded masses. No cards, no alpha, no strands (§4.3).
	# The cap deliberately overlaps the forehead, which gives a toddler fringe.
	_sphere(head, "HairCap", HEAD_RADIUS * 1.022, HAIR,
			Vector3(0.0, 0.040, 0.012), SEG_MEDIUM).scale = Vector3(1.0, 0.78, 1.0)
	_sphere(head, "HairTuft", HEAD_RADIUS * 0.34, HAIR,
			Vector3(0.012, 0.128, 0.020), SEG_SMALL)
	_sphere(head, "HairCurl", HEAD_RADIUS * 0.24, HAIR,
			Vector3(-0.040, 0.118, 0.008), SEG_TINY)

	for side: float in SIDES:
		# Small, no inner detail (§4.2). Visible from the Toddler family up.
		_sphere(head, "EarLeft" if side < 0.0 else "EarRight", 0.030, SKIN,
				Vector3(side * 0.127, -0.012, 0.010), SEG_TINY).scale = \
				Vector3(0.55, 1.0, 0.85)

	for side: float in SIDES:
		# Pivot per eye so a blink can scale the iris AND its catchlight together.
		var eye := Node3D.new()
		eye.name = "EyeLeft" if side < 0.0 else "EyeRight"
		eye.position = Vector3(side * EYE_X, EYE_Y, EYE_Z)
		head.add_child(eye)
		# A single solid ink mass. No sclera ring, no eyelashes: simplicity is
		# what keeps this out of the uncanny valley (§4.2).
		_sphere(eye, "Iris", EYE_RADIUS, INK, Vector3.ZERO, SEG_MEDIUM).scale = EYE_SCALE
		_sphere(eye, "Catchlight", CATCHLIGHT_RADIUS, CATCHLIGHT, CATCHLIGHT_OFFSET, SEG_TINY)

	_sphere(head, "Nose", 0.0165, SKIN_SHADE, Vector3(0.0, -0.045, -0.126), SEG_SMALL)

	for side: float in SIDES:
		# "Always at least 0.3 weight -- it is part of the resting face."
		_sphere(head, "BlushLeft" if side < 0.0 else "BlushRight", BLUSH_RADIUS, BLUSH,
				Vector3(side * 0.062, -0.063, -0.097), SEG_SMALL).scale = BLUSH_SCALE

	# The mouth. §4.2: one filled shape, no lips, no lip line, no teeth, no
	# tongue. Built as a real curved strip rather than from spheres -- three
	# spheres in an arc rendered as three separate dashes, which read as a smirk
	# rather than a smile. Seen in the render, not in a test.
	var mouth := Node3D.new()
	mouth.name = "Mouth"
	mouth.position = Vector3(0.0, MOUTH_Y, 0.0)
	head.add_child(mouth)
	var smile := MeshInstance3D.new()
	smile.name = "Smile"
	smile.mesh = _smile_mesh()
	var material: StandardMaterial3D = _material(MOUTH)
	# 16 triangles with no back: winding is not worth reasoning about here, and
	# it keeps the mouth visible if the head is ever mirrored.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	smile.material_override = material
	mouth.add_child(smile)


## -- Placeholder animations ------------------------------------------------------
##
## Eleven clips. Six of the vocabulary are left unauthored on purpose -- see the
## class doc.

func _build_animations() -> void:
	_animation_player = AnimationPlayer.new()
	_animation_player.name = "AnimationPlayer"
	add_child(_animation_player)

	var library := AnimationLibrary.new()
	for entry: Array in [
		["idle", _make_idle()], ["walk", _make_walk()], ["carryIdle", _make_carry_idle()],
		["eat", _make_eat()], ["drink", _make_drink()], ["hug", _make_hug()],
		["sit", _make_sit()], ["stand", _make_stand()], ["sleep", _make_sleep()],
		["wake", _make_wake()], ["celebrate", _make_celebrate()],
	]:
		library.add_animation(String(entry[0]), _baseline(entry[1] as Animation))
	_animation_player.add_animation_library("", library)
	_animation_player.play("idle")


## Every clip must say something about every animated property, or it inherits
## whatever the last clip left behind.
##
## An `AnimationPlayer` only writes the properties a clip has tracks for; it does
## not restore the others. So `eat`, which has no leg tracks, was playing with
## the legs still mid-stride from `walk`, and `sit`, which has no `Body:rotation`
## track, played while the child was still rotated flat on his back from
## `sleep` -- a toddler folded into the floor. Both were invisible to every
## assertion and obvious in the first render.
##
## Rather than hand-write twelve tracks into eleven clips, each clip declares
## only what it changes and this fills in the rest at its neutral value. Adding a
## new animated property means adding one line to `NEUTRAL_POSE`, not editing
## every clip.
func _baseline(animation: Animation) -> Animation:
	var present: Dictionary = {}
	for track: int in range(animation.get_track_count()):
		present[String(animation.track_get_path(track))] = true
	for path: String in _neutral_pose():
		if present.has(path):
			continue
		var value: Variant = _neutral_pose()[path]
		_track(animation, path, [[0.0, value], [animation.length, value]])
	return animation


## The rest pose, keyed by track path. Anything any clip animates belongs here.
func _neutral_pose() -> Dictionary:
	var pose: Dictionary = {
		"Body:position": Vector3.ZERO,
		"Body:rotation": Vector3.ZERO,
		"%s:rotation" % TORSO_PATH: Vector3.ZERO,
		"%s:scale" % TORSO_PATH: Vector3.ONE,
		"%s:rotation" % HEAD_PATH: Vector3.ZERO,
		"%s:scale" % MOUTH_NODE: Vector3.ONE,
	}
	for side: float in SIDES:
		pose["%s:rotation" % _arm(side)] = Vector3(0.0, 0.0, side * 0.10)
		pose["%s:rotation" % _leg(side)] = Vector3.ZERO
		pose["%s:scale" % _eye(side)] = Vector3.ONE
	return pose


## Gentle breathing bob, plus the one idle micro-expression §4.2 permits: a
## blink. A toddler standing still is never completely still.
func _make_idle() -> Animation:
	var animation: Animation = _looping(2.6)
	_track(animation, "Body:position", [
		[0.0, Vector3.ZERO], [1.3, Vector3(0.0, 0.016, 0.0)], [2.6, Vector3.ZERO]])
	_track(animation, "%s:rotation" % HEAD_PATH, [
		[0.0, Vector3(0.0, 0.0, deg_to_rad(1.6))],
		[1.3, Vector3(0.0, deg_to_rad(3.0), deg_to_rad(-1.6))],
		[2.6, Vector3(0.0, 0.0, deg_to_rad(1.6))]])
	for side: float in SIDES:
		_track(animation, "%s:rotation" % _arm(side), [
			[0.0, Vector3(0.0, 0.0, side * 0.10)],
			[1.3, Vector3(0.0, 0.0, side * 0.16)],
			[2.6, Vector3(0.0, 0.0, side * 0.10)]])
	_blink(animation, 2.05)
	return animation


## A toddler stride: short, bouncy, slightly unsteady, with legs that swing and
## arms that counter-swing. It must read as walking rather than sliding.
##
## ## The clip and the walk speed are ONE decision
##
## Feet skate whenever the body covers more ground per step than the legs reach.
## The reach is `2 * LEG_HEIGHT * sin(WALK_SWING)`; the ground covered is
## `WALK_SPEED * WALK_CYCLE / 2`. These constants are chosen so those are equal,
## and `test_movement_controller.gd` asserts it -- because this has already been
## broken once by changing the speed alone, which took the skate from 1.14x to
## 1.67x while intending to fix it.
##
## If the walk speed changes, `WALK_CYCLE` changes with it. The swing is the part
## that cannot go much further: 45 degrees on a 0.22 m leg is already a long pace
## for a toddler, and past it the legs read as scissoring.
const WALK_SWING_DEG: float = 45.0
const WALK_CYCLE: float = 0.59

func _make_walk() -> Animation:
	var animation: Animation = _looping(WALK_CYCLE)
	var half: float = WALK_CYCLE * 0.5
	# The hips must DROP at full stride, or the feet leave the floor.
	#
	# These legs have no knee, so a leg swung to `WALK_SWING_DEG` reaches only
	# `LEG_HEIGHT * cos(swing)` below the hip instead of the full `LEG_HEIGHT`.
	# At 45 degrees that is 64 mm short, and the child visibly floats at both
	# ends of every step. Seen side-on in a render; invisible from the front, and
	# invisible from the game's own three-quarter camera, which is why it is
	# worth writing down.
	#
	# The first version of this track had the bob at its PEAK during the stride
	# extremes, which doubled the error. Now the body sits lowest exactly when
	# the legs are widest and returns to zero as the leg passes vertical and the
	# foot is genuinely planted -- which is what a real walk cycle does anyway.
	var drop: float = -LEG_HEIGHT * (1.0 - cos(deg_to_rad(WALK_SWING_DEG)))
	var low := Vector3(0.0, drop, 0.0)
	var lift := Vector3(0.0, 0.008, 0.0)
	_track(animation, "Body:position", [
		[0.0, low], [half * 0.5, lift], [half, low], [half * 1.5, lift], [WALK_CYCLE, low]])
	_track(animation, "Body:rotation", [
		[0.0, Vector3(0.0, 0.0, deg_to_rad(-5.0))],
		[half, Vector3(0.0, 0.0, deg_to_rad(5.0))],
		[WALK_CYCLE, Vector3(0.0, 0.0, deg_to_rad(-5.0))]])
	var swing: float = deg_to_rad(WALK_SWING_DEG)
	for side: float in SIDES:
		var lead: float = -side  # the left leg leads while the right arm does
		_track(animation, "%s:rotation" % _leg(side), [
			[0.0, Vector3(swing * lead, 0.0, 0.0)],
			[half, Vector3(-swing * lead, 0.0, 0.0)],
			[WALK_CYCLE, Vector3(swing * lead, 0.0, 0.0)]])
		_track(animation, "%s:rotation" % _arm(side), [
			[0.0, Vector3(-swing * 0.62 * lead, 0.0, side * 0.14)],
			[half, Vector3(swing * 0.62 * lead, 0.0, side * 0.14)],
			[WALK_CYCLE, Vector3(-swing * 0.62 * lead, 0.0, side * 0.14)]])
	return animation


## Both arms cradled forward. Also serves the `hold` posture -- cradling
## something and resting while carrying it are the same pose.
func _make_carry_idle() -> Animation:
	var animation: Animation = _looping(2.6)
	_track(animation, "Body:position", [
		[0.0, Vector3.ZERO], [1.3, Vector3(0.0, 0.013, 0.0)], [2.6, Vector3.ZERO]])
	for side: float in SIDES:
		_track(animation, "%s:rotation" % _arm(side), [
			[0.0, Vector3(1.35, 0.0, -side * 0.34)],
			[1.3, Vector3(1.42, 0.0, -side * 0.34)],
			[2.6, Vector3(1.35, 0.0, -side * 0.34)]])
	_track(animation, "%s:rotation" % HEAD_PATH, [
		[0.0, Vector3(-0.10, 0.0, 0.0)], [2.6, Vector3(-0.10, 0.0, 0.0)]])
	return animation


## Hand to mouth, two chews, hand down. The chew is a scale pulse on the mouth:
## §4.1 bans visible teeth, so eating cannot be shown by opening a jaw.
func _make_eat() -> Animation:
	var animation: Animation = _once(1.6)
	var reach := Vector3(2.15, 0.0, -0.95)   # right arm: forward and inward
	_track(animation, "%s:rotation" % _arm(1.0), [
		[0.0, Vector3(0.0, 0.0, 0.12)], [0.45, reach], [1.25, reach],
		[1.6, Vector3(0.0, 0.0, 0.12)]])
	_track(animation, "%s:rotation" % _arm(-1.0), [
		[0.0, Vector3(0.0, 0.0, -0.10)], [1.6, Vector3(0.0, 0.0, -0.10)]])
	# Head dips to meet the hand (a pivot pointing UP tips forward on -X).
	_track(animation, "%s:rotation" % HEAD_PATH, [
		[0.0, Vector3.ZERO], [0.45, Vector3(-0.22, 0.0, 0.0)],
		[1.25, Vector3(-0.22, 0.0, 0.0)], [1.6, Vector3.ZERO]])
	_track(animation, "%s:scale" % MOUTH_NODE, [
		[0.0, Vector3.ONE], [0.6, Vector3(0.82, 1.35, 1.0)], [0.8, Vector3.ONE],
		[1.0, Vector3(0.82, 1.35, 1.0)], [1.2, Vector3.ONE], [1.6, Vector3.ONE]])
	_track(animation, "Body:position", [
		[0.0, Vector3.ZERO], [0.6, Vector3(0.0, 0.010, 0.0)],
		[1.0, Vector3(0.0, 0.010, 0.0)], [1.6, Vector3.ZERO]])
	return animation


## Both hands up -- a toddler holds a cup with two -- and the head tipped BACK.
## The head tip is the cue that separates drinking from eating at a glance.
func _make_drink() -> Animation:
	var animation: Animation = _once(1.8)
	for side: float in SIDES:
		# Lower than `eat`'s reach: the hands hold a cup at the chin rather than
		# covering the mouth, so the tipped-back head stays visible. That head tip
		# is the only thing separating drinking from eating at a glance.
		var lift := Vector3(2.02, 0.0, -side * 0.50)
		_track(animation, "%s:rotation" % _arm(side), [
			[0.0, Vector3(0.0, 0.0, side * 0.12)], [0.5, lift], [1.45, lift],
			[1.8, Vector3(0.0, 0.0, side * 0.12)]])
	# Positive X on the head pivot looks UP; the head tips back to drink.
	_track(animation, "%s:rotation" % HEAD_PATH, [
		[0.0, Vector3.ZERO], [0.55, Vector3(0.46, 0.0, 0.0)],
		[1.4, Vector3(0.54, 0.0, 0.0)], [1.8, Vector3.ZERO]])
	_track(animation, "Body:position", [
		[0.0, Vector3.ZERO], [0.6, Vector3(0.0, 0.012, 0.0)],
		[1.45, Vector3(0.0, 0.012, 0.0)], [1.8, Vector3.ZERO]])
	_blink(animation, 1.05)
	return animation


## Arms forward and wrapped inward, the body leaning in, then a squeeze. The
## inward wrap is what makes it a hug rather than a reach.
func _make_hug() -> Animation:
	var animation: Animation = _once(2.0)
	for side: float in SIDES:
		var open := Vector3(1.25, 0.0, side * 0.55)
		var closed := Vector3(1.60, 0.0, -side * 0.70)
		var squeeze := Vector3(1.66, 0.0, -side * 0.86)
		_track(animation, "%s:rotation" % _arm(side), [
			[0.0, Vector3(0.0, 0.0, side * 0.12)], [0.45, open], [0.95, closed],
			[1.25, squeeze], [1.55, closed], [2.0, Vector3(0.0, 0.0, side * 0.12)]])
	# Negative X on the torso pivot leans forward, into the hug.
	_track(animation, "%s:rotation" % TORSO_PATH, [
		[0.0, Vector3.ZERO], [0.95, Vector3(-0.16, 0.0, 0.0)],
		[1.55, Vector3(-0.16, 0.0, 0.0)], [2.0, Vector3.ZERO]])
	_track(animation, "%s:rotation" % HEAD_PATH, [
		[0.0, Vector3.ZERO], [0.95, Vector3(-0.08, 0.0, 0.26)],
		[1.55, Vector3(-0.08, 0.0, 0.26)], [2.0, Vector3.ZERO]])
	_blink(animation, 1.15)
	return animation


## A HELD posture: sitting on the floor with the legs out in front, which is how
## toddlers actually sit. Loops, because the pose persists until released.
func _make_sit() -> Animation:
	var animation: Animation = _looping(3.0)
	_track(animation, "Body:position", [
		[0.0, SIT_BODY], [1.5, SIT_BODY + Vector3(0.0, 0.010, 0.0)], [3.0, SIT_BODY]])
	for side: float in SIDES:
		# Positive X swings a leg forward: straight out in front.
		_track(animation, "%s:rotation" % _leg(side), [
			[0.0, Vector3(1.50, 0.0, side * 0.16)], [3.0, Vector3(1.50, 0.0, side * 0.16)]])
		# Arms back and out, propping.
		_track(animation, "%s:rotation" % _arm(side), [
			[0.0, Vector3(-0.42, 0.0, side * 0.42)], [3.0, Vector3(-0.42, 0.0, side * 0.42)]])
	_blink(animation, 2.4)
	return animation


## Getting up again: the reverse, so `sit` -> `stand` does not pop.
func _make_stand() -> Animation:
	var animation: Animation = _once(0.9)
	_track(animation, "Body:position", [[0.0, SIT_BODY], [0.9, Vector3.ZERO]])
	for side: float in SIDES:
		_track(animation, "%s:rotation" % _leg(side), [
			[0.0, Vector3(1.50, 0.0, side * 0.16)], [0.9, Vector3.ZERO]])
		_track(animation, "%s:rotation" % _arm(side), [
			[0.0, Vector3(-0.42, 0.0, side * 0.42)], [0.9, Vector3(0.0, 0.0, side * 0.10)]])
	return animation


## A HELD posture: lying on his back, head to local +X, face up, eyes closed,
## breathing -- ON the bed, not on the floor in front of it. See `SLEEP_BODY`.
##
## `rotation = (PI/2, PI/2, 0)` with Godot's default YXZ Euler order maps local
## +Y (up the body) to local +X and local -Z (the face) to local +Y, so the child
## lies across the frame face-up rather than face-down. Worked out rather than
## guessed, and then rendered and looked at.
func _make_sleep() -> Animation:
	var animation: Animation = _looping(3.6)
	_track(animation, "Body:position", [[0.0, SLEEP_BODY], [3.6, SLEEP_BODY]])
	_track(animation, "Body:rotation", [[0.0, SLEEP_ROTATION], [3.6, SLEEP_ROTATION]])
	# Breathing, on the torso rather than the whole body so the head stays put.
	_track(animation, "%s:scale" % TORSO_PATH, [
		[0.0, Vector3.ONE], [1.8, Vector3(1.035, 1.0, 1.035)], [3.6, Vector3.ONE]])
	_track(animation, "%s:rotation" % HEAD_PATH, [
		[0.0, Vector3(0.0, 0.0, 0.30)], [1.8, Vector3(0.0, 0.0, 0.34)],
		[3.6, Vector3(0.0, 0.0, 0.30)]])
	for side: float in SIDES:
		_track(animation, "%s:rotation" % _arm(side), [
			[0.0, Vector3(0.30, 0.0, side * 0.30)], [3.6, Vector3(0.30, 0.0, side * 0.30)]])
		_track(animation, "%s:rotation" % _leg(side), [
			[0.0, Vector3(0.16, 0.0, side * 0.10)], [3.6, Vector3(0.16, 0.0, side * 0.10)]])
	# Eyes closed for the whole clip. This, not the pose, is what a small child
	# reads as "asleep".
	for side: float in SIDES:
		_track(animation, "%s:scale" % _eye(side), [
			[0.0, EYE_CLOSED], [3.6, EYE_CLOSED]])
	return animation


## Sitting up again: unwinds the lie-down and opens the eyes.
func _make_wake() -> Animation:
	var animation: Animation = _once(1.2)
	_track(animation, "Body:position", [[0.0, SLEEP_BODY], [1.2, Vector3.ZERO]])
	_track(animation, "Body:rotation", [[0.0, SLEEP_ROTATION], [1.2, Vector3.ZERO]])
	for side: float in SIDES:
		_track(animation, "%s:rotation" % _arm(side), [
			[0.0, Vector3(0.30, 0.0, side * 0.30)],
			[0.7, Vector3(-0.2, 0.0, side * 1.3)],
			[1.2, Vector3(0.0, 0.0, side * 0.10)]])
		_track(animation, "%s:rotation" % _leg(side), [
			[0.0, Vector3(0.16, 0.0, side * 0.10)], [1.2, Vector3.ZERO]])
		_track(animation, "%s:scale" % _eye(side), [
			[0.0, EYE_CLOSED], [0.75, EYE_CLOSED], [0.9, Vector3.ONE], [1.2, Vector3.ONE]])
	return animation


## Both arms up and two hops. Contract §6 forbids a failure state, so this is the
## only feedback shape the game has for "you did it" -- it has to be legible.
func _make_celebrate() -> Animation:
	var animation: Animation = _once(1.6)
	_track(animation, "Body:position", [
		[0.0, Vector3.ZERO], [0.30, Vector3(0.0, 0.060, 0.0)], [0.55, Vector3.ZERO],
		[0.85, Vector3(0.0, 0.060, 0.0)], [1.10, Vector3.ZERO], [1.6, Vector3.ZERO]])
	for side: float in SIDES:
		var up := Vector3(0.0, 0.0, side * 2.45)
		_track(animation, "%s:rotation" % _arm(side), [
			[0.0, Vector3(0.0, 0.0, side * 0.12)], [0.25, up], [1.15, up],
			[1.6, Vector3(0.0, 0.0, side * 0.12)]])
	_track(animation, "%s:rotation" % HEAD_PATH, [
		[0.0, Vector3.ZERO], [0.3, Vector3(0.18, 0.0, 0.0)],
		[1.15, Vector3(0.18, 0.0, 0.0)], [1.6, Vector3.ZERO]])
	# A wider smile. Still no teeth.
	_track(animation, "%s:scale" % MOUTH_NODE, [
		[0.0, Vector3.ONE], [0.3, Vector3(1.30, 1.15, 1.0)],
		[1.15, Vector3(1.30, 1.15, 1.0)], [1.6, Vector3.ONE]])
	return animation


## -- Animation helpers -----------------------------------------------------------

const SIT_BODY: Vector3 = Vector3(0.0, -0.132, 0.0)

## Lying flat lifts the body pivot by this much, so a child on the ground rests
## ON the ground rather than half through it.
const LYING_LIFT: float = 0.163

## -- Sleeping happens ON something ---------------------------------------------
##
## `sleep` plays where the child is STANDING, and he stands at the bed's
## interaction point -- which is beside the bed, not on it. Without an offset the
## clip therefore laid Little Buddy flat on his back on the floor in front of the
## bed, every single time, which is what it did until this constant existed.
##
## The three numbers below are the bed, seen from the character's side of the
## contract. They mirror `BED_LIE_FORWARD`, `BED_LIE_ALONG` and `BED_LIE_HEIGHT`
## in `house_layout.gd`, and `test_art_rooms.gd` asserts the two agree -- this
## file deliberately does NOT import the house, because a character that knows
## about furniture is a character that cannot be reused.
##
## Signs, derived rather than guessed (the same discipline as the smile):
## the child faces the bed, so his local **-Z** points at it; a lying child's
## head points along his local **+X** (see `SLEEP_ROTATION`), so moving him back
## toward the foot of the bed is a move along local **-X**.
const SLEEP_FORWARD: float = 0.90
const SLEEP_ALONG: float = 0.25
const SLEEP_LIFT: float = 0.40

const SLEEP_BODY: Vector3 = Vector3(-SLEEP_ALONG, LYING_LIFT + SLEEP_LIFT, -SLEEP_FORWARD)
const SLEEP_ROTATION: Vector3 = Vector3(PI * 0.5, PI * 0.5, 0.0)
const EYE_CLOSED: Vector3 = Vector3(1.0, 0.10, 1.0)

const TORSO_PATH: String = "Body/Torso"
const HEAD_PATH: String = "Body/Torso/Head"
const MOUTH_NODE: String = "Body/Torso/Head/Mouth"


func _arm(side: float) -> String:
	return "%s/%s" % [TORSO_PATH, "ArmLeft" if side < 0.0 else "ArmRight"]


func _leg(side: float) -> String:
	return "Body/%s" % ("LegLeft" if side < 0.0 else "LegRight")


func _eye(side: float) -> String:
	return "%s/%s" % [HEAD_PATH, "EyeLeft" if side < 0.0 else "EyeRight"]


func _looping(length: float) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR
	return animation


func _once(length: float) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_NONE
	return animation


func _track(animation: Animation, path: String, keys: Array) -> void:
	var track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, path)
	for key: Array in keys:
		animation.track_insert_key(track, float(key[0]), key[1])


## A blink at `at` seconds: both eyes shut and open again inside 0.14 s. The only
## idle micro-expression §4.2 allows, and the cheapest sign of life there is.
func _blink(animation: Animation, at: float) -> void:
	for side: float in SIDES:
		_track(animation, "%s:scale" % _eye(side), [
			[maxf(at - 0.07, 0.0), Vector3.ONE],
			[at, EYE_CLOSED],
			[minf(at + 0.07, animation.length), Vector3.ONE]])


## -- The smile ---------------------------------------------------------------------

## A continuous curved strip, generated rather than assembled from primitives,
## and wrapped onto the head's surface so the corners do not sink into the cheeks.
##
## The arc is the bottom of a circle of radius `MOUTH_ARC_RADIUS` whose centre
## sits directly above the mouth, sampled across `+/- MOUTH_HALF_ANGLE` either
## side of straight down. That construction makes "smile" a property of the
## geometry rather than of a sign: the lowest point is at x = 0 and every other
## point is higher, so this cannot silently become a frown. `test_toddler_view.gd`
## asserts exactly that on the generated vertices.
func _smile_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var head_ry: float = HEAD_RADIUS * 0.94

	for step: int in range(MOUTH_SEGMENTS + 1):
		var t: float = float(step) / float(MOUTH_SEGMENTS)
		var angle: float = -PI * 0.5 + (t * 2.0 - 1.0) * MOUTH_HALF_ANGLE
		for edge: float in [-1.0, 1.0]:
			var radius: float = MOUTH_ARC_RADIUS + edge * MOUTH_THICKNESS
			var x: float = radius * cos(angle)
			var y: float = MOUTH_ARC_RADIUS + radius * sin(angle)
			# Follow the head's own ellipsoid, floating just clear of the skin.
			var head_y: float = MOUTH_Y + y
			var inside: float = 1.0 - pow(x / HEAD_RADIUS, 2.0) - pow(head_y / head_ry, 2.0)
			var z: float = -(HEAD_RADIUS * sqrt(maxf(inside, 0.0)) + MOUTH_LIFT)
			vertices.append(Vector3(x, y, z))
			normals.append(Vector3(x / HEAD_RADIUS, head_y / head_ry, z / HEAD_RADIUS).normalized())

	for step: int in range(MOUTH_SEGMENTS):
		var base: int = step * 2
		indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## -- Mesh helpers ----------------------------------------------------------------

func _sphere(parent: Node3D, node_name: String, radius: float, color: Color,
		at: Vector3, segments: Vector2i) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments.x
	mesh.rings = segments.y
	return _instance(parent, node_name, mesh, color, at)


func _capsule(parent: Node3D, node_name: String, radius: float, length: float,
		color: Color, at: Vector3) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = length + radius
	mesh.radial_segments = SEG_MEDIUM.x
	mesh.rings = 4
	return _instance(parent, node_name, mesh, color, at)


func _instance(parent: Node3D, node_name: String, mesh: Mesh, color: Color,
		at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.position = at
	parent.add_child(instance)
	return instance


## Materials are cached per colour, so the whole child uses nine shared
## `StandardMaterial3D` resources rather than one per mesh. The art bible's "one
## material where possible" means an atlas on the final model; a primitive
## placeholder cannot reach that, but it can at least avoid twenty-five.
func _material(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html(false)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	# Roughness 0.85-1.0, metallic 0, no specular on skin (contract §7, §4.2).
	material.roughness = 0.95
	material.metallic = 0.0
	_materials[key] = material
	return material


func _count_triangles(node: Node) -> int:
	var total: int = 0
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for surface: int in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.size() > 0:
					total += indices.size() / 3
				else:
					total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for child: Node in node.get_children():
		total += _count_triangles(child)
	return total
