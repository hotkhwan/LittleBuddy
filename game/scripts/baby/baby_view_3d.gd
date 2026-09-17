extends Node3D
class_name BabyView3D

## Baby built entirely from built-in primitive meshes (SphereMesh/CapsuleMesh)
## with plain StandardMaterial3D — zero external art dependency, no textures,
## no shaders, no extra lights, no particles.
##
## Keeps the exact same public API the 2D view exposed so FeedActivity
## (presentation-agnostic; only calls `set_view_state` via duck typing on a
## plain Node) needs no behavioural change:
##   set_view_state("idle" | "hungry" | "drinking" | "happy" | "hugging")
##   get_view_state_name() -> String
##
## Also exposes get_mouth_position() / get_hug_position() (GLOBAL) for
## INTERACT to place drop zones. Both are derived from real child-node
## transforms every call, so they always track restyles/animation and are
## never hardcoded constants that could drift from the mesh.
##
## Reactions are driven by a single AnimationPlayer holding five short,
## cheap, looping animations (gentle idle bob, hungry squirm, drinking tilt,
## happy bounce-and-cheer, hugging arm-bring-in) built procedurally in code,
## plus two things the AnimationPlayer deliberately does NOT own:
##   * a `_process`-driven blink (a value track fighting for `Eyes:scale`
##     across five clips is a silent-breakage machine; a timer is not), and
##   * a per-state facial expression — mouth shape and brow tilt — swapped in
##     `set_view_state` so "happy" and "hungry" actually read differently on
##     the face and not only in the motion.

enum ViewState { IDLE, HUNGRY, DRINKING, HAPPY, HUGGING }

const STATE_NAMES: Dictionary = {
	"idle": ViewState.IDLE,
	"hungry": ViewState.HUNGRY,
	"drinking": ViewState.DRINKING,
	"happy": ViewState.HAPPY,
	"hugging": ViewState.HUGGING,
}

const SKIN_COLOR: Color = Color(1.0, 0.87, 0.74)
const CHEEK_COLOR: Color = Color(1.0, 0.72, 0.7)
const NOSE_COLOR: Color = Color(1.0, 0.82, 0.68)
const EYE_COLOR: Color = Color(0.22, 0.16, 0.14)
const EYE_HIGHLIGHT_COLOR: Color = Color(1.0, 1.0, 1.0)
const MOUTH_COLOR: Color = Color(0.62, 0.31, 0.3)
const OUTFIT_COLOR: Color = Color(0.45, 0.74, 0.9)
const NAPPY_COLOR: Color = Color(0.98, 0.97, 0.94)
const HAIR_COLOR: Color = Color(0.78, 0.6, 0.44)
const BROW_COLOR: Color = Color(0.72, 0.55, 0.42)

## Head sits this high in `Body` space; every facial offset below is relative
## to it, so nudging the whole head keeps the face assembled.
const HEAD_Y: float = 0.515

## Blink cadence. Randomised so two babies (or a restart) never tick in sync.
const BLINK_MIN_GAP: float = 2.4
const BLINK_MAX_GAP: float = 5.6
const BLINK_CLOSE: float = 0.07
const BLINK_HOLD: float = 0.03
const BLINK_OPEN: float = 0.09
const BLINK_SQUASH: float = 0.08

var _state: int = ViewState.IDLE
var _animation_player: AnimationPlayer = null
var _body: Node3D = null
var _head: Node3D = null
var _eyes: Node3D = null
var _mouth_marker: Node3D = null
var _hug_marker: Node3D = null
var _left_arm_pivot: Node3D = null
var _right_arm_pivot: Node3D = null
var _smile: Node3D = null
var _mouth_open: Node3D = null
var _left_brow: Node3D = null
var _right_brow: Node3D = null

var _materials: Dictionary = {}
var _blink_timer: float = 3.0
var _blink_phase: float = -1.0


func _ready() -> void:
	_build_body()
	_animation_player = AnimationPlayer.new()
	_animation_player.name = "AnimationPlayer"
	add_child(_animation_player)
	_build_animations()
	_animation_player.play("idle")
	_apply_expression(ViewState.IDLE)
	_blink_timer = randf_range(BLINK_MIN_GAP, BLINK_MAX_GAP)
	set_process(true)


## Accepts "idle" | "hungry" | "drinking" | "happy" | "hugging". Unknown
## values fall back to idle so a scene mistake never crashes the baby.
func set_view_state(state_name: String) -> void:
	_state = STATE_NAMES.get(state_name, ViewState.IDLE)
	_apply_expression(_state)
	if _animation_player == null:
		return
	var anim_name: String = state_name if STATE_NAMES.has(state_name) else "idle"
	if _animation_player.has_animation(anim_name) and _animation_player.current_animation != anim_name:
		_animation_player.play(anim_name)


func get_view_state_name() -> String:
	for key: String in STATE_NAMES.keys():
		if STATE_NAMES[key] == _state:
			return key
	return "idle"


## GLOBAL position of the baby's mouth. Derived live from the mouth marker's
## transform (child of the animated Head node) so it always tracks head
## tilts/restyles instead of drifting from a hardcoded constant.
func get_mouth_position() -> Vector3:
	if _mouth_marker != null:
		return _mouth_marker.global_position
	return global_position


## GLOBAL position of the baby's chest/arms. Derived live from the hug
## marker's transform (child of the animated Body node).
func get_hug_position() -> Vector3:
	if _hug_marker != null:
		return _hug_marker.global_position
	return global_position


## -- Blink -----------------------------------------------------------------
##
## Both eyes (and their highlights) hang off a single `Eyes` pivot placed at
## eye height, so squashing that one node's Y closes both lids toward the same
## line. Deliberately not an animation track: the blink has to survive every
## state change, and five clips each owning `Eyes:scale` would blend-fight.

func _process(delta: float) -> void:
	if _eyes == null:
		return
	if _blink_phase >= 0.0:
		_blink_phase += delta
		_eyes.scale = Vector3(1.0, _blink_scale(_blink_phase), 1.0)
		if _blink_phase >= BLINK_CLOSE + BLINK_HOLD + BLINK_OPEN:
			_blink_phase = -1.0
			_eyes.scale = Vector3.ONE
			_blink_timer = randf_range(BLINK_MIN_GAP, BLINK_MAX_GAP)
		return
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_phase = 0.0


func _blink_scale(phase: float) -> float:
	if phase < BLINK_CLOSE:
		return lerpf(1.0, BLINK_SQUASH, phase / BLINK_CLOSE)
	if phase < BLINK_CLOSE + BLINK_HOLD:
		return BLINK_SQUASH
	var opening: float = (phase - BLINK_CLOSE - BLINK_HOLD) / BLINK_OPEN
	return lerpf(BLINK_SQUASH, 1.0, clampf(opening, 0.0, 1.0))


## -- Expression ------------------------------------------------------------
##
## The mouth is two alternative meshes rather than one morphing blob: a curved
## three-piece smile, and a small round "o". Swapping visibility is free and
## makes hungry/drinking read differently from happy at a glance.

func _apply_expression(state: int) -> void:
	if _smile == null or _mouth_open == null:
		return
	var open_mouth: bool = state == ViewState.HUNGRY or state == ViewState.DRINKING
	_smile.visible = not open_mouth
	_mouth_open.visible = open_mouth

	match state:
		ViewState.HAPPY:
			_smile.scale = Vector3(1.2, 1.3, 1.0)
			_mouth_open.scale = Vector3.ONE
		ViewState.DRINKING:
			_mouth_open.scale = Vector3(0.85, 0.85, 1.0)
		ViewState.HUNGRY:
			_mouth_open.scale = Vector3(1.0, 1.15, 1.0)
		_:
			_smile.scale = Vector3.ONE
			_mouth_open.scale = Vector3.ONE

	if _left_brow == null or _right_brow == null:
		return
	# Inner ends up = gently worried. Both ends up = delighted. Never angry:
	# a downward inner tilt is the one shape a child reads as cross.
	var inner_lift: float = 0.0
	var brow_raise: float = 0.0
	match state:
		ViewState.HUNGRY:
			inner_lift = 13.0
			brow_raise = 0.004
		ViewState.DRINKING:
			inner_lift = 5.0
			brow_raise = 0.0
		ViewState.HAPPY:
			inner_lift = 0.0
			brow_raise = 0.016
		ViewState.HUGGING:
			inner_lift = 3.0
			brow_raise = 0.008
		_:
			inner_lift = 0.0
			brow_raise = 0.0
	_left_brow.rotation_degrees = Vector3(0.0, 0.0, inner_lift)
	_right_brow.rotation_degrees = Vector3(0.0, 0.0, -inner_lift)
	_left_brow.position.y = _brow_rest_y() + brow_raise
	_right_brow.position.y = _brow_rest_y() + brow_raise


func _brow_rest_y() -> float:
	return 0.064


## -- Construction (primitives only) --------------------------------------

## Materials are cached per colour: ~30 small mesh instances all sharing seven
## resources instead of holding thirty near-identical ones.
func _make_material(color: Color) -> StandardMaterial3D:
	if _materials.has(color):
		return _materials[color]
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	_materials[color] = mat
	return mat


func _make_sphere(radius: float, color: Color, local_position: Vector3, scale: Vector3 = Vector3.ONE,
		radial: int = 12, rings: int = 8) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	# Low-poly budget: the engine default (32 radial segments / 16 rings) is
	# far more geometry than these small blobby shapes need.
	mesh.radial_segments = radial
	mesh.rings = rings
	instance.mesh = mesh
	instance.material_override = _make_material(color)
	instance.position = local_position
	instance.scale = scale
	return instance


## A short capsule used as a limb segment. `axis_rotation_deg` rotates its
## default vertical (Y) long axis about Z, so 0 leaves a leg upright and 90
## lays it out sideways as an arm.
func _make_limb(radius: float, length: float, color: Color, local_position: Vector3,
		axis_rotation_deg: float) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = length
	mesh.radial_segments = 8
	mesh.rings = 2
	instance.mesh = mesh
	instance.material_override = _make_material(color)
	instance.position = local_position
	instance.rotation_degrees = Vector3(0.0, 0.0, axis_rotation_deg)
	return instance


func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	_build_torso()
	_build_legs()
	_build_arms()

	# Hug marker: front of the chest, roughly where hugging arms would meet.
	_hug_marker = Node3D.new()
	_hug_marker.name = "HugMarker"
	_hug_marker.position = Vector3(0.0, 0.277, 0.2)
	_body.add_child(_hug_marker)

	_build_head()


func _build_torso() -> void:
	# Round, chubby onesie body — near-spherical so the silhouette is all
	# curves, with no waist a child could read as a grown-up shape.
	var torso: MeshInstance3D = MeshInstance3D.new()
	torso.name = "Torso"
	var torso_mesh: CapsuleMesh = CapsuleMesh.new()
	torso_mesh.radius = 0.165
	torso_mesh.height = 0.33
	torso_mesh.radial_segments = 14
	torso_mesh.rings = 4
	torso.mesh = torso_mesh
	torso.material_override = _make_material(OUTFIT_COLOR)
	torso.position = Vector3(0.0, 0.235, 0.0)
	_body.add_child(torso)

	# Nappy: a little wider than the onesie so it bulges past it. This is the
	# single strongest "this is a baby, not a small adult" cue in the whole
	# silhouette.
	var nappy: MeshInstance3D = _make_sphere(0.176, NAPPY_COLOR, Vector3(0.0, 0.142, 0.0),
			Vector3(1.0, 0.68, 0.97), 14, 8)
	nappy.name = "Nappy"
	_body.add_child(nappy)


func _build_legs() -> void:
	# Chubby thighs splaying slightly outward, ending in visible feet that
	# point at the camera — the feet are what stop the body reading as a bag.
	for side: float in [-1.0, 1.0]:
		var thigh: MeshInstance3D = _make_limb(0.058, 0.10, SKIN_COLOR,
				Vector3(side * 0.088, 0.075, 0.025), side * -9.0)
		thigh.name = "LeftThigh" if side < 0.0 else "RightThigh"
		_body.add_child(thigh)

		var foot: MeshInstance3D = _make_sphere(0.062, SKIN_COLOR,
				Vector3(side * 0.098, 0.036, 0.055), Vector3(0.95, 0.72, 1.25))
		foot.name = "LeftFoot" if side < 0.0 else "RightFoot"
		_body.add_child(foot)


func _build_arms() -> void:
	# Arms hang down-and-out from shoulder pivots, so the hugging animation can
	# swing the whole arm forward without hardcoding a hand position anywhere
	# else. Hand radius is only a hair over the arm radius: make it much bigger
	# and the pair reads as two detached blobs instead of one soft limb.
	_left_arm_pivot = Node3D.new()
	_left_arm_pivot.name = "LeftArmPivot"
	_left_arm_pivot.position = Vector3(-0.152, 0.325, 0.025)
	_left_arm_pivot.rotation_degrees = Vector3(0.0, 0.0, 26.0)
	_body.add_child(_left_arm_pivot)
	_left_arm_pivot.add_child(_make_sphere(0.072, OUTFIT_COLOR, Vector3(-0.012, 0.0, 0.0),
			Vector3(1.0, 0.92, 1.0), 10, 6))
	_left_arm_pivot.add_child(_make_limb(0.05, 0.135, SKIN_COLOR, Vector3(-0.048, 0.0, 0.0), 90.0))
	_left_arm_pivot.add_child(_make_sphere(0.056, SKIN_COLOR, Vector3(-0.105, 0.0, 0.0),
			Vector3(1.0, 0.95, 1.0)))

	_right_arm_pivot = Node3D.new()
	_right_arm_pivot.name = "RightArmPivot"
	_right_arm_pivot.position = Vector3(0.152, 0.325, 0.025)
	_right_arm_pivot.rotation_degrees = Vector3(0.0, 0.0, -26.0)
	_body.add_child(_right_arm_pivot)
	_right_arm_pivot.add_child(_make_sphere(0.072, OUTFIT_COLOR, Vector3(0.012, 0.0, 0.0),
			Vector3(1.0, 0.92, 1.0), 10, 6))
	_right_arm_pivot.add_child(_make_limb(0.05, 0.135, SKIN_COLOR, Vector3(0.048, 0.0, 0.0), -90.0))
	_right_arm_pivot.add_child(_make_sphere(0.056, SKIN_COLOR, Vector3(0.105, 0.0, 0.0),
			Vector3(1.0, 0.95, 1.0)))


func _build_head() -> void:
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, HEAD_Y, 0.0)
	_body.add_child(_head)

	# Big round head, a touch wider than tall. The head overlaps the torso
	# rather than perching on it: a baby has no visible neck.
	var head_mesh_instance: MeshInstance3D = MeshInstance3D.new()
	head_mesh_instance.name = "HeadMesh"
	var head_mesh: SphereMesh = SphereMesh.new()
	head_mesh.radius = 0.19
	head_mesh.height = 0.38
	head_mesh.radial_segments = 20
	head_mesh.rings = 12
	head_mesh_instance.mesh = head_mesh
	head_mesh_instance.material_override = _make_material(SKIN_COLOR)
	# Only the MESH is scaled, never the `Head` node, so every facial offset
	# below stays in honest, unscaled metres.
	head_mesh_instance.scale = Vector3(1.03, 1.0, 0.99)
	_head.add_child(head_mesh_instance)

	_build_hair()
	_build_cheeks()
	_build_eyes()
	_build_brows()
	_build_nose()
	_build_mouth()


func _build_hair() -> void:
	# Newborn-bald with a single soft curl. Every attempt at a hair *cap* out of
	# intersected primitives ends up a hard-rimmed brown plate sitting on the
	# crown -- it reads as a beret, not as hair. One light, tapered curl says
	# "brand new baby" and has no rim to give itself away.
	var tuft: MeshInstance3D = _make_sphere(0.044, HAIR_COLOR, Vector3(0.0, 0.166, 0.004),
			Vector3(1.15, 0.78, 1.05), 12, 7)
	tuft.name = "HairTuft"
	_head.add_child(tuft)
	var curl: MeshInstance3D = _make_sphere(0.026, HAIR_COLOR, Vector3(0.006, 0.199, 0.006),
			Vector3(0.82, 1.2, 0.85), 10, 6)
	curl.rotation_degrees = Vector3(0.0, 0.0, -16.0)
	_head.add_child(curl)
	_head.add_child(_make_sphere(0.014, HAIR_COLOR, Vector3(0.026, 0.224, 0.008),
			Vector3.ONE, 8, 5))


func _build_cheeks() -> void:
	# Real geometry first: two skin-coloured puffs that push past the head's
	# silhouette, so the lower face is genuinely chubby from every angle.
	# The blush is then a very flat disc laid on top, not a pink wart.
	for side: float in [-1.0, 1.0]:
		# Sized so the puff clears the head by only ~8 mm sideways and ~6 mm
		# forward: enough to widen the jaw, shallow enough that the crease
		# where the two spheres meet stays a soft shading break, not a ridge.
		# Set just far enough back that the puff clears the head sideways but not
		# forwards: the crease where the spheres meet then falls on the side of
		# the face, instead of drawing a "double chin" line under the mouth.
		_head.add_child(_make_sphere(0.074, SKIN_COLOR, Vector3(side * 0.122, -0.052, 0.061),
				Vector3(1.0, 0.98, 1.0), 12, 8))
		_head.add_child(_make_sphere(0.044, CHEEK_COLOR, Vector3(side * 0.124, -0.055, 0.130),
				Vector3(1.0, 0.75, 0.25), 12, 7))


func _build_eyes() -> void:
	# One pivot at eye height owning both eyes and all four highlights, so the
	# blink is a single scale on a single node.
	_eyes = Node3D.new()
	_eyes.name = "Eyes"
	_eyes.position = Vector3(0.0, -0.002, 0.0)
	_head.add_child(_eyes)

	for side: float in [-1.0, 1.0]:
		var eye: MeshInstance3D = _make_sphere(0.043, EYE_COLOR, Vector3(side * 0.085, 0.0, 0.16),
				Vector3(0.93, 1.06, 0.4), 14, 9)
		eye.name = "LeftEye" if side < 0.0 else "RightEye"
		_eyes.add_child(eye)
		# One big catchlight upper-inner plus one tiny spark lower-outer: the
		# pair is what turns a flat dot into an eye that looks back at you.
		_eyes.add_child(_make_sphere(0.0145, EYE_HIGHLIGHT_COLOR,
				Vector3(side * 0.068, 0.017, 0.174), Vector3(1.0, 1.0, 0.5), 10, 6))
		_eyes.add_child(_make_sphere(0.0065, EYE_HIGHLIGHT_COLOR,
				Vector3(side * 0.098, -0.019, 0.177), Vector3(1.0, 1.0, 0.5), 8, 5))


func _build_brows() -> void:
	# Soft, light, and set high above the eye. Brows carry most of the mood for
	# almost no geometry, but a dark heavy brow instantly ages the face.
	_left_brow = _make_sphere(0.026, BROW_COLOR, Vector3(-0.081, _brow_rest_y(), 0.152),
			Vector3(1.2, 0.3, 0.28), 10, 6)
	_left_brow.name = "LeftBrow"
	_head.add_child(_left_brow)
	_right_brow = _make_sphere(0.026, BROW_COLOR, Vector3(0.081, _brow_rest_y(), 0.152),
			Vector3(1.2, 0.3, 0.28), 10, 6)
	_right_brow.name = "RightBrow"
	_head.add_child(_right_brow)


func _build_nose() -> void:
	var nose: MeshInstance3D = _make_sphere(0.022, NOSE_COLOR, Vector3(0.0, -0.035, 0.176),
			Vector3(1.0, 0.85, 0.8), 10, 7)
	nose.name = "Nose"
	_head.add_child(nose)


func _build_mouth() -> void:
	# MouthMarker is a plain anchor so the drop zone keeps reading a live node
	# transform while the visible mouth underneath is free to swap shape.
	_mouth_marker = Node3D.new()
	_mouth_marker.name = "MouthMarker"
	_mouth_marker.position = Vector3(0.0, -0.09, 0.17)
	_head.add_child(_mouth_marker)

	# Smile: five flat slivers chained into one shallow upward arc. Separate
	# pieces rather than one blob so it can actually curve, but each piece
	# overlaps its neighbour by more than half its width so the result reads as
	# a single continuous line instead of a row of dots.
	_smile = Node3D.new()
	_smile.name = "Smile"
	_mouth_marker.add_child(_smile)
	# Every sliver is the same size and sits the same ~4 mm proud of the face,
	# so the arc keeps one constant line weight and no piece bulges. Uneven
	# weights and uneven depth are what turned an earlier pass into a squiggle.
	# Sign matters: the camera looks down -Z, so a positive Z rotation lifts the
	# +X end. The LEFT piece therefore needs a negative angle to raise its outer
	# corner. Getting this backwards builds a perfectly symmetrical frown.
	for piece: Array in [
		[0.000, -0.007, -0.011, 0.0],
		[-0.031, 0.004, -0.009, -26.0],
		[0.031, 0.004, -0.009, 26.0],
	]:
		var sliver: MeshInstance3D = _make_sphere(0.024, MOUTH_COLOR,
				Vector3(piece[0], piece[1], piece[2]), Vector3(1.0, 0.27, 0.3), 10, 6)
		sliver.rotation_degrees = Vector3(0.0, 0.0, piece[3])
		_smile.add_child(sliver)

	# Open "o": shown while hungry and while drinking.
	_mouth_open = Node3D.new()
	_mouth_open.name = "MouthOpen"
	_mouth_marker.add_child(_mouth_open)
	_mouth_open.add_child(_make_sphere(0.029, MOUTH_COLOR, Vector3(0.0, -0.004, -0.006),
			Vector3(0.9, 1.0, 0.45), 12, 8))
	_mouth_open.visible = false


## -- Animation (single AnimationPlayer, five cheap looping clips) --------
##
## Track paths are relative to the AnimationPlayer's PARENT, i.e. this node.
## `Head` is nested under `Body`, so anything aimed at the head must say
## "Body/Head" — a bare "Head:..." silently resolves to nothing.

func _make_animation(length: float) -> Animation:
	var anim: Animation = Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR
	return anim


func _add_track(anim: Animation, node_name: String, property: String, keys: Array) -> void:
	var track_index: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track_index, NodePath("%s:%s" % [node_name, property]))
	anim.track_set_interpolation_type(track_index, Animation.INTERPOLATION_LINEAR)
	for key: Array in keys:
		anim.track_insert_key(track_index, key[0], key[1])


func _build_animations() -> void:
	var library: AnimationLibrary = AnimationLibrary.new()

	# Idle: gentle vertical bob with a lazy head sway, so standing still still
	# looks alive.
	var idle_anim: Animation = _make_animation(3.2)
	_add_track(idle_anim, "Body", "position:y", [
		[0.0, 0.0], [0.8, 0.018], [1.6, 0.0], [2.4, 0.018], [3.2, 0.0],
	])
	_add_track(idle_anim, "Body/Head", "rotation:z", [
		[0.0, deg_to_rad(2.5)], [1.6, deg_to_rad(-2.5)], [3.2, deg_to_rad(2.5)],
	])
	library.add_animation("idle", idle_anim)

	# Hungry: a slow unhappy squirm, not a fast agitated shake.
	var hungry_anim: Animation = _make_animation(1.2)
	_add_track(hungry_anim, "Body", "rotation:z", [
		[0.0, deg_to_rad(-5.0)], [0.6, deg_to_rad(5.0)], [1.2, deg_to_rad(-5.0)],
	])
	_add_track(hungry_anim, "Body/Head", "rotation:z", [
		[0.0, deg_to_rad(3.0)], [0.6, deg_to_rad(-3.0)], [1.2, deg_to_rad(3.0)],
	])
	library.add_animation("hungry", hungry_anim)

	# Drinking: head tilts back to swallow, repeating.
	var drinking_anim: Animation = _make_animation(0.9)
	_add_track(drinking_anim, "Body/Head", "rotation:x", [
		[0.0, 0.0], [0.45, deg_to_rad(-16.0)], [0.9, 0.0],
	])
	_add_track(drinking_anim, "Body", "position:y", [
		[0.0, 0.0], [0.45, 0.008], [0.9, 0.0],
	])
	library.add_animation("drinking", drinking_anim)

	# Happy: a bounce with both arms thrown up. The arm pivots rest at +-26
	# degrees, so these keys restate that rest value rather than assuming zero.
	var happy_anim: Animation = _make_animation(0.7)
	_add_track(happy_anim, "Body", "position:y", [
		[0.0, 0.0], [0.2, 0.075], [0.45, 0.0], [0.58, 0.02], [0.7, 0.0],
	])
	_add_track(happy_anim, "Body/LeftArmPivot", "rotation:z", [
		[0.0, deg_to_rad(26.0)], [0.25, deg_to_rad(-38.0)], [0.55, deg_to_rad(-30.0)],
		[0.7, deg_to_rad(26.0)],
	])
	_add_track(happy_anim, "Body/RightArmPivot", "rotation:z", [
		[0.0, deg_to_rad(-26.0)], [0.25, deg_to_rad(38.0)], [0.55, deg_to_rad(30.0)],
		[0.7, deg_to_rad(-26.0)],
	])
	library.add_animation("happy", happy_anim)

	# Hugging: both arms swing forward/inward toward the chest and gently
	# ease back out, looping like a soft, repeated squeeze.
	var hugging_anim: Animation = _make_animation(1.4)
	_add_track(hugging_anim, "Body/LeftArmPivot", "rotation:y", [
		[0.0, 0.0], [0.4, deg_to_rad(72.0)], [1.05, deg_to_rad(72.0)], [1.4, 0.0],
	])
	_add_track(hugging_anim, "Body/RightArmPivot", "rotation:y", [
		[0.0, 0.0], [0.4, deg_to_rad(-72.0)], [1.05, deg_to_rad(-72.0)], [1.4, 0.0],
	])
	_add_track(hugging_anim, "Body", "rotation:x", [
		[0.0, 0.0], [0.4, deg_to_rad(-6.0)], [1.05, deg_to_rad(-6.0)], [1.4, 0.0],
	])
	_add_track(hugging_anim, "Body/Head", "rotation:z", [
		[0.0, 0.0], [0.4, deg_to_rad(8.0)], [1.05, deg_to_rad(8.0)], [1.4, 0.0],
	])
	library.add_animation("hugging", hugging_anim)

	_animation_player.add_animation_library("", library)
