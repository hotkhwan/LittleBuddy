extends Node3D

## ============================================================================
## BIG BUDDY -- the caregiver avatar. EXPERIMENTAL, DEFAULT OFF, NOT RIGGED.
## ============================================================================
##
## The wrapper around `assets/characters/buddy/pinkGirl/pinkGirl_v01.glb`, a
## generator-produced (Meshy) adult character supplied by the owner as the
## player's "Big Buddy" -- the grown-up who looks after Little Buddy.
##
## **This is the only file in the project that knows the GLB's node layout.**
## Everything above it talks to the semantic methods below. A re-export with
## different node names, a different pivot or a different scale changes this file
## and nothing else. That is the same bargain `scripts/character/toddler_view.gd`
## already makes for Little Buddy, and it is why the 2D-to-3D move and the
## greybox-to-art move both cost the gameplay layer nothing.
##
## **This is not Little Buddy.** The child character is and remains
## `toddler_view.gd`. This model is the adult caregiver only.
##
## ---------------------------------------------------------------------------
## ## Public API added 2026-09-20 (face, blink, idle, hair) -- callers use
## ## `has_method()` guards; every method is safe without the model
## ---------------------------------------------------------------------------
##
## **Face moods** (texture patches, see `buddy_face.gd`; nothing per frame):
##   `set_face(mood) -> bool`     "content" | "happy" | "surprised" | "sleepy".
##                                 Sets the RESTING face; an action's face (below)
##                                 shows over it and hands back when it ends.
##   `get_face() -> String`        the resting mood asked for (default "content").
##   `get_shown_face() -> String`  what is on the atlas right now.
##   `available_faces() -> Array`  [] when this build's atlas has no moods.
##   `has_face_moods() -> bool`
##   Actions carry a face: `celebrate`/`clap`/`wave`/`hug`/`give` -> happy,
##   `wake` -> surprised, `sleep` (held) -> sleepy. `ACTION_FACES` is the table.
##
## **Blink** (the `eyesClosed` layer for 120 ms every 3-6 s, randomised, driven
## by a one-shot `Timer` child -- no `_process`; paused while the shown face
## already closes the eyes, i.e. `sleepy`):
##   `set_blinking(enabled)`, `is_blinking_enabled() -> bool`,
##   `are_eyes_closed() -> bool`, `blink_now()` (closes; a second call reopens --
##   for tests and cutscenes).
##
## **Idle**: `play_action("idle")` plays an authored `idle` clip
## (`buddy_life_clips.gd`: breath, +-0.6 degree head bob, a weight shift every
## 3.8 s). `set_locomotion(0)` returns to it, so she never freezes at rest.
##
## **Hair**: the rig has no hair bones, so `buddy_hair_sway.gd` -- a
## `SkeletonModifier3D` on the head bone, +-0.4 degrees on two slow sines --
## makes the long hair read as swaying over any clip. `get_hair_sway()`.
##
## **Contact hint**: `contact_shadow.gd`, a 0.22 m soft dark-peach ellipse under
## her feet at alpha 0.18, because the game runs no shadows. `get_contact_hint()`.
##
## ---------------------------------------------------------------------------
## ## TutorFace (docs/ALIZ_TUTOR_CONTRACTS.md), added 2026-09-20 for Aliz Tutor
## ## Mode -- callers use `has_method()` guards; every method is safe without
## ## the model, the rig or the mood atlas (it then records the wish and shows
## ## nothing, which is the honest degradation)
## ---------------------------------------------------------------------------
##
## **Expressions** -- more texture moods on the SAME channel as `set_face()`
## (`tools/aliz_expression_pass.py` paints them; `docs/ALIZ_TUTOR_FACE.md`):
##   `set_expression(name) -> bool`  "neutral" | "listening" | "thinking" |
##                                   "happy" | "encouraging" | "smile".
##                                   Sets the resting face, exactly as
##                                   `set_face()` does; the two vocabularies are
##                                   one manifest and `available_faces()` lists
##                                   both. An action's face still shows over it.
##   `get_expression() -> String`    (= `get_face()`), `EXPRESSIONS` the list.
##   The blink overlays every expression.
##
## **Mouth for speech** -- four texture mouth frames (closed = the expression's
## own mouth, small, mid, open) chosen from a SMOOTHED amount by
## `buddy_mouth.gd` (attack 40 ms, release 90 ms, no frame held under 40 ms
## except a close):
##   `set_speaking(active)`          false closes the mouth now and restores the
##                                   expression's own mouth; true just marks her
##                                   speaking (the amount is the driver's).
##   `set_mouth_open(amount)`        0..1, the TARGET; the smoothing is inside.
##                                   Any amount > 0 counts as speaking.
##   `is_speaking() -> bool`, `get_mouth_open() -> float` (smoothed),
##   `get_mouth_frame() -> int` (0..3), `step_mouth(seconds)` (headless: advance
##   the smoothing by hand), `get_mouth() -> Node` (the smoother).
##   `get_lip_sync() -> Node`        a `buddy_lip_sync.gd` LipSyncSource under
##                                   `Model`, made on first use, already aimed at
##                                   this character: `attach(player)`,
##                                   `attach_bus(name)`, `attach_tts()`.
##
## **Head and hands** -- authored clips (`buddy_gesture_clips.gd`) on an
## upper-body `SkeletonModifier3D` layer (`buddy_gesture_layer.gd`) that
## composes with the idle, the seated pose and the carry arms, and never with
## the walk:
##   `play_gesture(name) -> float`   "nod" (0.9 s) | "tilt" (1.2 s) | "point"
##                                   (1.4 s) | "clap" (1.1 s) | "wave" (1.3 s).
##                                   Returns the duration, or 0.0 when refused:
##                                   unknown name, no rig, locomotion above
##                                   `GESTURE_MAX_SPEED_MPS` (0.1 m/s), or an arm
##                                   gesture while the carry pose holds the arms.
##                                   Fades in over 0.12 s, out over 0.2 s.
##                                   `set_locomotion()` above the limit fades a
##                                   running gesture out.
##   `stop_gesture()`, `get_current_gesture() -> String`,
##   `available_gestures() -> Array`, `get_gesture_layer() -> SkeletonModifier3D`.
##   `set_listening_pose(active)`    a slight lean-in (spine 6 degrees over three
##                                   bones, head counter-nodded), eased 0.35 s;
##                                   the idle breath keeps running underneath.
##   `is_listening_pose() -> bool`.
##
## ---------------------------------------------------------------------------
## ## Why it is OFF by default -- measured, not an opinion
## ---------------------------------------------------------------------------
##
## Measured from the imported asset (`describe_budget()` returns these live, so
## they cannot go stale):
##
## | Property        | Measured                  | Art bible          | Verdict     |
## |-----------------|---------------------------|--------------------|-------------|
## | Triangles       | 619,890                   | 2,500-4,000 (§10)  | 155x over   |
## | Vertices        | 336,300                   | --                 | --          |
## | File size       | 21 MB                     | 40 MB whole app    | half of it  |
## | Textures        | 3 x 2048^2 JPEG           | 1 x 512^2 (§7)     | 16x pixels  |
## | Materials       | 1                         | 1                  | OK          |
## | `metallic`      | 1.0                       | 0.0 everywhere     | violates §7 |
## | `cull_mode`     | DISABLED (double-sided)   | culling on         | 2x overdraw |
## | Normal map      | present                   | banned (§7)        | violates §7 |
## | **Skin / rig**  | **none**                  | required           | cannot pose |
## | **Anim clips**  | **none**                  | idle + walk min.   | cannot move |
##
## A single one of those would be a discussion. The triangle count alone is
## 20x the entire 30,000-triangle *frame* ceiling, and the missing rig is not a
## budget problem at all -- it is a capability problem that no import setting
## fixes. So the procedural placeholder remains the character that ships, and
## `ENABLED` below stays `false` until a retopologised, rigged re-export lands.
##
## `test_buddy_avatar.gd` enforces exactly that: the flag may only be `true`
## while the asset is inside the §10 budget AND can actually animate. Turning it
## on with this asset turns the suite red on purpose. A comment asking nicely
## would not have survived the next agent.
##
## ---------------------------------------------------------------------------
## ## It does not fake animation, and it says so
## ---------------------------------------------------------------------------
##
## The temptation with an unrigged mesh is a procedural bob-and-sway: translate
## the whole body on a sine, tilt it a few degrees, call it `idle`. That would
## have looked like progress and been a lie -- the thing still cannot walk, cannot
## reach, cannot sit, and every subsequent decision would have been taken against
## a capability the project does not have.
##
## So: `can_play_action()` answers **honestly**, by asking the model what clips it
## actually has. Today that is `false` for every action in the vocabulary.
##
## `play_action()` is nonetheless a **safe, completing no-op**: it emits
## `action_started` immediately and `action_finished` after the action's semantic
## duration, exactly as `LittleBuddyCharacter` does for its own unauthored
## actions. Nothing visible happens, and no caller can hang waiting for a signal
## that never arrives. That is the graceful-degradation rule
## (`character_action_driver.gd`) applied to a character with *no* clips rather
## than *some*.
##
## ## THE RIG SEAM
##
## `_bind_action_driver()` is where a real rig attaches. It looks for an
## `AnimationPlayer` anywhere in the instantiated model and, if it finds one with
## clips, builds the project's standard `AnimationPlayerActionDriver` from it --
## at which point `can_play_action()` and `play_action()` start doing real work
## with **no change to this file or any caller**. The seam is live code, not a
## comment, so a rigged re-export is a drop-in.
##
## What a rigged re-export must deliver, in priority order:
##   1. a skin + skeleton (there is no pose without one);
##   2. clips named from `CharacterActionDriver.KNOWN_ACTIONS` -- at minimum
##      `idle` and `walk`; the semantic names ARE the contract;
##   3. <= 4,000 triangles (§10) and one 512^2 albedo atlas (§7).
##
## ---------------------------------------------------------------------------
## ## Normalisation, and why these numbers
## ---------------------------------------------------------------------------
##
## The raw GLB is pivoted through the middle of the body (feet at y = -0.952) and
## stands 1.903 m tall. Neither is usable. Both are corrected **here, in the
## wrapper** -- the GLB on disk is left exactly as the owner supplied it, so the
## editable source and the shipped normalisation never disagree.
##
## * **Height 1.65 m.** Art bible §4 gives Mom 1.65 m and Dad 1.78 m. The
##   caregiver reads as an adult woman, so Mom's figure applies. 1.65 is also the
##   kinder of the two against §4's "adults must never dominate the frame" and
##   against `room_framing.gd`, whose `CHARACTER_HEIGHT` is 1.0 m -- every room
##   camera in the house is fitted for a 0.85 m toddler, so the shortest
##   defensible adult is the right one. Scale is DERIVED from the measured AABB
##   rather than hard-coded, so a re-export at a different size still lands at
##   1.65 m.
##
##   Honest caveat, from looking at the render rather than the numbers
##   (`docs/shots/buddy_scale_vs_littlebuddy_1334x616.png`): the model's own
##   proportions are roughly **1 : 4.5** head-to-height, against §4's 1 : 6.5 for
##   an adult. Scaled to 1.65 m it therefore reads as a very tall child rather
##   than as a grown-up. That is a property of the asset, not of this
##   normalisation -- no scale factor fixes proportions -- and it is one more
##   thing a re-export has to address.
##
## * **Feet at the wrapper's origin.** §6: "pivot at base centre for anything
##   standing". The whole house is dimensioned against floor-standing pivots;
##   a mid-body pivot would bury the character to the waist in every room.
##   Also derived from the AABB, not hard-coded.
##
## * **Yaw.** Little Buddy faces -Z at yaw 0 and the camera sits on the +Z side
##   (`room_framing.gd`: "the camera always sits on the +Z side, looking towards
##   -Z"). glTF's own convention is that an asset faces +Z, and this asset does.
##   So the model is turned 180 degrees inside the wrapper, and after that the
##   wrapper obeys the same rule as every other character in the project: **yaw 0
##   faces -Z**. Verified by rendering and looking at the face, per §12 -- a
##   facing error is invisible to every assertion and obvious in one frame.
##
## ---------------------------------------------------------------------------
## ## The material decision (§7 is a gate, not advice)
## ---------------------------------------------------------------------------
##
## Surfacing the model at all means deciding what to do about three §7
## violations. The wrapper fixes them on the instantiated material, which is a
## duplicate -- the imported resource on disk is untouched:
##
## * **`metallic = 1.0` -> `0.0`.** §7 is absolute ("0.0 everywhere"), and this is
##   not even a style call: a fully metallic surface has no diffuse response, so
##   under this game's single directional light and warm ambient the character
##   renders as a dark, oily silhouette. Setting it to 0 is the difference
##   between a caregiver and a statue.
## * **Normal map -> removed.** §7 bans them outright. It also costs a whole
##   2048^2 texture, and on a flat-albedo pastel character it buys surface detail
##   the rest of the game does not have -- §9's coherence rule says that makes the
##   *furniture* look broken.
## * **`cull_mode = DISABLED` -> `BACK`.** Double-sided doubles overdraw on a
##   619k-triangle mesh for no gain; the mesh is closed.
## * The metallic/roughness texture goes with the metallic value -- one more
##   2048^2 map dropped. Three 2048^2 textures become one.
## * Roughness is pinned into §7's 0.85-1.0 band.
##
## What the wrapper **cannot** fix and does not pretend to: the albedo atlas is
## still 2048^2 against a 512^2 budget, and the triangle count is untouchable
## from here. Both need a retopologise-and-bake pass on the asset itself.

const ActionDriverScript := preload("res://scripts/character/character_action_driver.gd")
const AnimationDriverScript := preload("res://scripts/character/animation_player_action_driver.gd")
const LocomotionScript := preload("res://scripts/character/locomotion.gd")
const CarryPoseScript := preload("res://scripts/characters/buddy/buddy_carry_pose.gd")
const LifeClipsScript := preload("res://scripts/characters/buddy/buddy_life_clips.gd")
const HairSwayScript := preload("res://scripts/characters/buddy/buddy_hair_sway.gd")
const FaceScript := preload("res://scripts/characters/buddy/buddy_face.gd")
const MouthScript := preload("res://scripts/characters/buddy/buddy_mouth.gd")
const LipSyncScript := preload("res://scripts/characters/buddy/buddy_lip_sync.gd")
const GestureClipsScript := preload("res://scripts/characters/buddy/buddy_gesture_clips.gd")
const GestureLayerScript := preload("res://scripts/characters/buddy/buddy_gesture_layer.gd")
const ContactHintScript := preload("res://scripts/characters/contact_shadow.gd")

## Where the bone-name adapter lives. The ONLY file that may name one of her
## bones; everything above `get_socket()` speaks `LB_Rig_v1` and nothing else.
## Same shape as `meshy_baby_v01.json`, same rig family.
const RIG_PROFILE_PATH: String = "res://content/rig_profiles/pink_girl_v01.json"

## Seconds the carry arms take to wrap and to let go (the modifier's `influence`
## is eased rather than switched, so picking up reads as a gesture).
const CARRY_POSE_BLEND_SEC: float = 0.35

## The mood manifest `tools/aliz_face_pass.py` writes next to the atlas. Absent
## or mismatched (a re-export), the face system stands down and every face
## method answers honestly that there are no moods.
const FACE_MANIFEST_PATH: String = "res://assets/characters/buddy/pinkGirl/pinkGirlBuddy_v01_faces.json"

const FACE_CONTENT: String = "content"
const FACE_HAPPY: String = "happy"
const FACE_SURPRISED: String = "surprised"
const FACE_SLEEPY: String = "sleepy"

## The face an action wears while it runs. Derived from the action, the way
## Bunny's face is derived from his clip, so the mouth cannot disagree with what
## she was asked to do. Anything not listed keeps the resting face.
const ACTION_FACES: Dictionary = {
	"celebrate": FACE_HAPPY, "clap": FACE_HAPPY, "wave": FACE_HAPPY,
	"hug": FACE_HAPPY, "give": FACE_HAPPY,
	"wake": FACE_SURPRISED,
	"sleep": FACE_SLEEPY,
}

## The TutorTurn emotion vocabulary (docs/ALIZ_TUTOR_CONTRACTS.md). Each is a
## mood in the face manifest; `set_expression()` is `set_face()` with this
## list's name on it.
const EXPRESSIONS: Array[String] = [
	"neutral", "listening", "thinking", "happy", "encouraging", "smile",
]

## Above this ground speed a gesture is refused and a running one fades out:
## the arms belong to the walk and run clips while she travels.
const GESTURE_MAX_SPEED_MPS: float = 0.1

## A blink: eyes shut for this long, every so often. Randomised so two Alizes
## in two menus would not blink in step, and so a child cannot count it.
const BLINK_CLOSED_SEC: float = 0.12
const BLINK_GAP_MIN_SEC: float = 3.0
const BLINK_GAP_MAX_SEC: float = 6.0

## Emitted when a requested action begins. Emitted even though nothing is shown,
## so a caller's await is symmetric with `LittleBuddyCharacter`'s.
signal action_started(action_name: String)
## Emitted when a requested action has run for its semantic duration. **Always**
## emitted for an action that started, including an action this character cannot
## show -- that guarantee is the whole reason a no-op is safe.
signal action_finished(action_name: String)


# ---------------------------------------------------------------------------
# THE SWITCH
# ---------------------------------------------------------------------------

## **The single flag that decides whether the avatar is in the game at all.**
##
## `false` -- the procedural placeholder is Big Buddy and this model is not
## instantiated, not loaded and costs nothing at runtime.
##
## `true` since 2026-09-19: the asset now PASSES the section 10 budget rather
## than having the budget bent around it. 3,900 triangles against 4,000, one
## 512-square atlas against one 512-square atlas. `test_buddy_avatar.gd` is
## unchanged and still gates this flag -- it simply stopped failing, which is the
## only acceptable way for a flag like this to flip.
##
## She still has NO RIG, so she is a high-quality STATIC presence: menu, arrival
## and one gameplay scene. The brief is explicit that this beats broken
## animation, and `can_play_action()` still answers honestly that she cannot act.
const ENABLED: bool = true

## Static so a caller can ask *without* loading the model. `main.gd` uses this.
static func is_enabled() -> bool:
	return ENABLED


# ---------------------------------------------------------------------------
# The asset, and the normalisation applied to it
# ---------------------------------------------------------------------------

## The RUNTIME derivative, not the raw Meshy export.
##
## The export is 619,890 triangles and 22 MB -- 155x the budget, unshippable, and
## the reason this avatar was switched off. `tools/meshy_remesh_modelurl.sh`
## (5 credits) brought it to 3,900 triangles and
## `tools/optimize_runtime_glb.py` did the rest locally: smooth normals, art
## bible section 7 material, one 512-square atlas. 22 MB -> 0.47 MB, and the raw
## export stays out of the bundle.
const MODEL_PATH: String = "res://assets/characters/buddy/pinkGirl/pinkGirlBuddy_v01.glb"

## The locomotion clips, as armature-only exports (~60 KB each) so the mesh is
## not duplicated. Their skeleton is bone-for-bone the model's, so the imported
## tracks resolve against it unchanged.
##
## Without this merge the model carries only its bind pose, `can_play_action`
## answers false for every action, and the character travels with its legs
## still -- which is exactly the floating that was reported from live play.
const CLIP_SOURCES: Dictionary = {
	"walk": "res://assets/characters/buddy/pinkGirl/pinkGirlBuddy_walk_v01.glb",
	"run": "res://assets/characters/buddy/pinkGirl/pinkGirlBuddy_run_v01.glb",
}

## Art bible §4: Mom 1.65 m, Dad 1.78 m. See the class doc for why the shorter.
const MODEL_HEIGHT_M: float = 1.65

## The model faces +Z as exported (glTF's own convention); the game faces -Z.
const MODEL_YAW_DEG: float = 180.0

## §7: roughness 0.85-1.0. "Nothing in this game is shiny."
const ROUGHNESS: float = 0.9

## §10, main character. The gate `test_buddy_avatar.gd` applies to `ENABLED`.
const MAX_TRIANGLES: int = 4000
## §7: one 512x512 atlas per family.
const MAX_TEXTURE_SIZE: int = 512

## The node the normalisation transform lives on. The raw GLB hierarchy hangs
## below it and is never addressed from outside this file.
const MODEL_NODE_NAME: String = "Model"

var _model_root: Node3D = null
var _mesh: MeshInstance3D = null
var _skeleton: Skeleton3D = null
var _driver: RefCounted = null
var _pending_action: String = ""
var _built: bool = false
var _measured: Dictionary = {}
## `LB_Rig_v1` socket names that resolved on this skeleton. See `_build_sockets()`.
var _sockets: Array = []
## The carry arm pose, a `SkeletonModifier3D` under the skeleton. Null without a rig.
var _carry_pose: SkeletonModifier3D = null
var _carry_pose_wanted: bool = false
## The head-bone sway modifier. Null without a rig.
var _hair_sway: SkeletonModifier3D = null
## The face compositor (`buddy_face.gd`); `null` until `_prepare_face()` binds.
var _face: RefCounted = null
## The resting mood a caller asked for, and the mood the running action wears.
var _face_mood: String = FACE_CONTENT
var _action_face: String = ""
var _blink_timer: Timer = null
var _blink_enabled: bool = true
## The mouth smoother (`buddy_mouth.gd`), under `Model`; null without a face.
var _mouth: Node = null
## The talk frame on the atlas right now (0 = the expression's own mouth).
var _mouth_frame: int = 0
## Recorded wishes for a build without the face system.
var _speaking_wanted: bool = false
## The lip sync source, made by `get_lip_sync()` on first use.
var _lip_sync: Node = null
## The upper-body gesture layer, a `SkeletonModifier3D` under the skeleton.
var _gesture_layer: SkeletonModifier3D = null
var _listening_wanted: bool = false
## The last ground speed `set_locomotion()` was given, m/s.
var _locomotion_speed: float = 0.0
## True between the shut and the reopen of one blink.
var _blink_shut: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	build()
	_rng.randomize()
	_schedule_blink()


## Idempotent, and callable before `_ready()` -- the headless `--script` runner
## never fires `_ready()` for nodes added to the root, which is the same reason
## `toddler_view.gd::build()` exists.
func build() -> void:
	if _built:
		return
	_built = true
	_build_model()
	_bind_action_driver()


## True when the GLB is present in this build and was instantiated. False is a
## normal, supported state: a build that ships without the asset still loads this
## scene, still answers every method, and simply shows nothing.
func is_model_available() -> bool:
	build()
	return _mesh != null


# ---------------------------------------------------------------------------
# The semantic action surface -- honest about what it cannot do
# ---------------------------------------------------------------------------

## Is `action_name` part of the game's vocabulary at all? Single-sourced from
## `character_action_driver.gd` so the caregiver and the child can never drift
## into two vocabularies.
func is_known_action(action_name: String) -> bool:
	return ActionDriverScript.is_known_action(action_name)


## **Can this character actually show `action_name` right now?**
##
## Answered by asking the model, not by returning a constant: today the asset has
## no skin and no clips, so this is `false` for every action in the vocabulary,
## and it will become `true` by itself the day a rigged re-export arrives. See
## THE RIG SEAM in the class doc.
##
## Callers that care about the difference between "will happen" and "will be
## politely skipped" ask this. Callers that just want the sequence to advance can
## ignore it -- `play_action()` completes either way.
func can_play_action(action_name: String) -> bool:
	build()
	if _driver == null:
		return false
	return bool(_driver.call("can_play", action_name))


## Requests `action_name`.
##
## Returns `false` for a name outside the vocabulary, and emits nothing -- a
## caller that got `false` must not be left waiting.
##
## Returns `true` otherwise, emits `action_started` now and `action_finished`
## after `seconds` (or the action's semantic default). When `can_play_action()`
## is false -- which is every action today -- **nothing is shown**: this is a
## timed, completing no-op, never a fake pose and never a stall.
func play_action(action_name: String, seconds: float = -1.0) -> bool:
	build()
	if not is_known_action(action_name):
		return false

	_pending_action = action_name
	if _driver != null:
		# Best effort, exactly as `LittleBuddyCharacter` does it: a `false` here is
		# the expected answer for an unauthored action and is not an error.
		_driver.call("play", action_name)
	# The face follows the action even when the body cannot: a "celebrate" she
	# has no clip for still gets the smile, which is the honest half of it.
	_action_face = String(ACTION_FACES.get(action_name, ""))
	_show_face()

	action_started.emit(action_name)
	_finish_after(action_name, _action_seconds(action_name, seconds))
	return true


## Ends a held posture. Returns the posture released, or "". Always safe.
## With no rig there is no posture to leave, so this is "" until one exists.
func release_action() -> String:
	build()
	# The face is handed back whether or not the posture could be SHOWN: a
	# `sleep` she has no clip for still wore the sleepy face while it was held.
	_action_face = ""
	_show_face()
	var held: String = get_held_action()
	if held.is_empty():
		if ActionDriverScript.is_hold_action(_pending_action):
			_pending_action = ""
		return ""
	_pending_action = ""
	if _driver != null:
		_driver.call("rest", false)
	return held


## The posture currently held ("sit", "sleep", "hold"), or "".
func get_held_action() -> String:
	if _pending_action.is_empty():
		return ""
	if not ActionDriverScript.is_hold_action(_pending_action):
		return ""
	return _pending_action if can_play_action(_pending_action) else ""


## **What is on screen right now.** Deliberately "" while nothing can be shown --
## reporting the requested action here would let a caller believe a pose is
## visible when the character is standing perfectly still. Use
## `get_requested_action()` for "what was last asked for".
func get_current_action() -> String:
	build()
	if _driver == null:
		return ""
	return String(_driver.call("get_current_action"))


## The last action requested, whether or not it could be shown. The honest
## counterpart to `get_current_action()`.
func get_requested_action() -> String:
	return _pending_action


## The animation player driving this character, or `null`. Null today: the asset
## has none. Present so the wrapper is shaped like `toddler_view.gd` and so
## `LittleBuddyCharacter`'s subtree search would find a rig the day there is one.
func get_animation_player() -> AnimationPlayer:
	build()
	if _model_root == null:
		return null
	return _find_animation_player(_model_root)


# ---------------------------------------------------------------------------
# Measurement -- so the budget can be asserted rather than remembered
# ---------------------------------------------------------------------------

## Triangles in the whole instantiated model. Diagnostic; mirrors
## `toddler_view.gd::count_triangles()` so the two can be compared directly.
func count_triangles() -> int:
	build()
	return int(describe_budget().get("triangles", 0))


## Everything `test_buddy_avatar.gd` and the art gate need, measured live from
## the imported asset so no number in this file can go stale.
##
## The `metallic` / `roughness` / `doubleSided` / `hasNormalMap` keys report the
## asset **as delivered**, read from the mesh's own material -- this dictionary is
## an audit of the source, and an audit that reported the values we just fixed
## would be worthless. The `applied*` keys report what is actually rendered,
## read back from the surface override, so the §7 fix can be asserted rather than
## assumed.
##
## Keys (camelCase, per `CLAUDE.md`): `available`, `triangles`, `vertices`,
## `surfaces`, `materials`, `textures` (array of side lengths), `maxTextureSize`,
## `metallic`, `roughness`, `doubleSided`, `hasNormalMap`, `appliedMetallic`,
## `appliedRoughness`, `appliedDoubleSided`, `appliedNormalMap`,
## `appliedTextures`, `hasSkin`, `animationClips`, `rawHeight`, `height`,
## `feetY`.
func describe_budget() -> Dictionary:
	build()
	if not _measured.is_empty():
		return _measured.duplicate(true)

	var report: Dictionary = {
		"available": false,
		"triangles": 0,
		"vertices": 0,
		"surfaces": 0,
		"materials": 0,
		"textures": [],
		"maxTextureSize": 0,
		"metallic": 0.0,
		"roughness": 0.0,
		"doubleSided": false,
		"hasNormalMap": false,
		"appliedMetallic": 0.0,
		"appliedRoughness": 0.0,
		"appliedDoubleSided": false,
		"appliedNormalMap": false,
		"appliedTextures": 0,
		"hasSkin": false,
		"animationClips": [],
		"rawHeight": 0.0,
		"height": 0.0,
		"feetY": 0.0,
	}
	if _mesh == null or _mesh.mesh == null:
		_measured = report
		return _measured.duplicate(true)

	var mesh: Mesh = _mesh.mesh
	var triangles: int = 0
	var vertices: int = 0
	var sizes: Array = []
	var seen_materials: Array = []
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		vertices += points.size()
		triangles += (indices.size() / 3) if indices.size() > 0 else (points.size() / 3)
		var material: Material = mesh.surface_get_material(surface)
		if material != null and not seen_materials.has(material):
			seen_materials.append(material)
		if material is StandardMaterial3D:
			var standard := material as StandardMaterial3D
			report["metallic"] = standard.metallic
			report["roughness"] = standard.roughness
			report["doubleSided"] = standard.cull_mode == BaseMaterial3D.CULL_DISABLED
			report["hasNormalMap"] = standard.normal_enabled and standard.normal_texture != null
			for texture: Variant in [
				standard.albedo_texture, standard.normal_texture,
				standard.metallic_texture, standard.roughness_texture,
			]:
				if texture is Texture2D:
					var side: int = int(maxf(
						(texture as Texture2D).get_size().x, (texture as Texture2D).get_size().y))
					if not sizes.has(side):
						sizes.append(side)
		var applied: Material = _mesh.get_surface_override_material(surface)
		if applied is StandardMaterial3D:
			var shown := applied as StandardMaterial3D
			report["appliedMetallic"] = shown.metallic
			report["appliedRoughness"] = shown.roughness
			report["appliedDoubleSided"] = shown.cull_mode == BaseMaterial3D.CULL_DISABLED
			report["appliedNormalMap"] = shown.normal_enabled and shown.normal_texture != null
			var live: int = 0
			for texture: Variant in [
				shown.albedo_texture, shown.normal_texture,
				shown.metallic_texture, shown.roughness_texture,
			]:
				if texture is Texture2D:
					live += 1
			report["appliedTextures"] = live

	var aabb: AABB = mesh.get_aabb()
	report["available"] = true
	report["triangles"] = triangles
	report["vertices"] = vertices
	report["surfaces"] = mesh.get_surface_count()
	report["materials"] = seen_materials.size()
	report["textures"] = sizes
	report["maxTextureSize"] = 0 if sizes.is_empty() else int(sizes.max())
	report["hasSkin"] = _mesh.skin != null
	report["animationClips"] = _clip_names()
	report["rawHeight"] = aabb.size.y
	# Measured through the real transform chain rather than recomputed from the
	# constants, so a normalisation that silently stopped working is visible.
	var placed: AABB = _mesh.get_transform() * aabb
	var node: Node = _mesh
	while node != null and node != self:
		if node is Node3D and node != _mesh:
			placed = (node as Node3D).get_transform() * placed
		node = node.get_parent()
	report["height"] = placed.size.y
	report["feetY"] = placed.position.y
	# A SKINNED mesh is not placed by that chain. Meshy's rig exports bones in
	# CENTIMETRES under an `Armature` node carrying a 0.01 unit conversion, while
	# the mesh's own vertex data is already in the post-inverse-bind metre space
	# the bones resolve to. Walking the node chain therefore applies that 0.01 a
	# SECOND time and reports a 1.65 m character as 0.0165 m -- which is exactly
	# what `test_buddy_avatar.gd` caught the moment the rigged asset landed.
	# What is actually rendered is the mesh extent times the scale this wrapper
	# applies, which is what the bone world positions agree with.
	if _mesh.skin != null and aabb.size.y > 0.0001:
		report["height"] = aabb.size.y * _model_root.scale.y
		report["feetY"] = 0.0
	_measured = report
	return _measured.duplicate(true)


## The one-line verdict: does the asset meet the bar the flag is gated on?
## Both halves matter -- a 4,000-triangle mesh that still cannot pose is no more
## shippable as a character than a 619,890-triangle one.
func passes_validation() -> bool:
	var report: Dictionary = describe_budget()
	if not bool(report.get("available", false)):
		return false
	if int(report.get("triangles", 0)) > MAX_TRIANGLES:
		return false
	if int(report.get("maxTextureSize", 0)) > MAX_TEXTURE_SIZE:
		return false
	if not bool(report.get("hasSkin", false)):
		return false
	return not (report.get("animationClips", []) as Array).is_empty()


## Plain sentences naming every reason the asset is not shippable as a character.
## Empty when it is. Used by the test so a failure reads as a brief rather than
## as "expected true, got false".
func validation_failures() -> Array:
	var report: Dictionary = describe_budget()
	var reasons: Array = []
	if not bool(report.get("available", false)):
		reasons.append("the model is not in this build at all (%s)" % MODEL_PATH)
		return reasons
	var triangles: int = int(report.get("triangles", 0))
	if triangles > MAX_TRIANGLES:
		reasons.append("%d triangles against the art bible §10 budget of %d -- %.0fx over"
				% [triangles, MAX_TRIANGLES, float(triangles) / float(MAX_TRIANGLES)])
	var texture_size: int = int(report.get("maxTextureSize", 0))
	if texture_size > MAX_TEXTURE_SIZE:
		reasons.append("a %d x %d texture against §7's one %d x %d atlas"
				% [texture_size, texture_size, MAX_TEXTURE_SIZE, MAX_TEXTURE_SIZE])
	if not bool(report.get("hasSkin", false)):
		reasons.append("no skin and no skeleton: it cannot be posed, so it cannot act")
	if (report.get("animationClips", []) as Array).is_empty():
		reasons.append("no animation clips: it cannot idle and it cannot walk")
	return reasons


# ---------------------------------------------------------------------------
# Building and normalising
# ---------------------------------------------------------------------------

func _build_model() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		return
	var packed: Resource = load(MODEL_PATH)
	if not (packed is PackedScene):
		return
	var instance: Node = (packed as PackedScene).instantiate()
	if not (instance is Node3D):
		if instance != null:
			instance.free()
		return

	_model_root = Node3D.new()
	_model_root.name = MODEL_NODE_NAME
	add_child(_model_root)
	_model_root.add_child(instance)

	_mesh = _find_mesh(instance)
	_apply_art_bible_material()
	_prepare_face()
	_normalise(instance as Node3D)
	_skeleton = _find_skeleton(instance)
	_merge_clips(instance)
	_sockets = _build_sockets()
	_build_carry_pose()
	_build_gesture_layer()
	_build_hair_sway()
	_build_blink_timer()
	_build_mouth()
	_build_contact_hint()


## Merges the locomotion clips onto the model's own `AnimationPlayer`.
##
## Nothing here is hand-authored: every clip is loaded from a file the rig
## produced. `can_play_action()` starts answering truthfully the moment this
## succeeds, which is the seam the class doc already describes.
func _merge_clips(instance: Node) -> void:
	var player: AnimationPlayer = _find_animation_player(instance)
	if player == null:
		return
	var library: AnimationLibrary = player.get_animation_library("")
	if library == null:
		return
	for action: String in CLIP_SOURCES.keys():
		var path: String = String(CLIP_SOURCES[action])
		if library.has_animation(action) or not ResourceLoader.exists(path):
			continue
		var packed: Resource = load(path)
		if not (packed is PackedScene):
			continue
		var clip_root: Node = (packed as PackedScene).instantiate()
		var clip_player: AnimationPlayer = _find_animation_player(clip_root)
		if clip_player != null:
			for clip_name: String in clip_player.get_animation_list():
				var anim: Animation = clip_player.get_animation(clip_name)
				if anim != null:
					var copy: Animation = anim.duplicate(true)
					copy.loop_mode = Animation.LOOP_LINEAR
					library.add_animation(action, copy)
					break
		clip_root.free()
	# The idle she does not ship with, authored on her real skeleton and addressed
	# the way the imported clips address it. A library that already has an
	# `idle` (an animator's) keeps it; see `buddy_life_clips.gd`.
	if _skeleton != null:
		var root: Node = player.get_node_or_null(player.root_node)
		if root != null:
			LifeClipsScript.merge_into(library, _skeleton, String(root.get_path_to(_skeleton)))


## Drives the legs from the actual ground speed.
##
## `locomotion.gd` holds the arithmetic and the measurements; this only applies
## the answer. Both halves come from ONE call so a clip can never end up playing
## at the previous clip's rate.
func set_locomotion(speed: float) -> void:
	build()
	_locomotion_speed = absf(speed)
	if _locomotion_speed > GESTURE_MAX_SPEED_MPS and _gesture_layer != null \
			and bool(_gesture_layer.call("is_playing")):
		_gesture_layer.call("stop")
	var player: AnimationPlayer = get_animation_player()
	if player == null:
		return
	var described: Dictionary = LocomotionScript.describe(speed)
	var clip: String = String(described["clip"])
	if clip.is_empty():
		# At rest. A locomotion clip hands over to the idle rather than freezing
		# on its last frame; anything else that is playing (an action, the idle
		# itself) is left alone -- this is called every frame she stands still.
		var current: String = player.current_animation
		var was_moving: bool = CLIP_SOURCES.has(current)
		if player.is_playing() and not was_moving:
			return
		if player.has_animation(LifeClipsScript.CLIP_IDLE):
			if current != LifeClipsScript.CLIP_IDLE or not player.is_playing():
				player.speed_scale = 1.0
				player.play(LifeClipsScript.CLIP_IDLE, AnimationDriverScript.ACTION_BLEND_SEC)
		elif player.is_playing():
			player.stop()
		return
	if not player.has_animation(clip):
		return
	player.speed_scale = float(described["scale"])
	if player.current_animation != clip or not player.is_playing():
		player.play(clip)


## Feet on the floor at the wrapper's origin, horizontally centred, scaled to
## `MODEL_HEIGHT_M`, and turned to the project's -Z facing. Every number is
## derived from the measured AABB, so a re-export at a different size or pivot
## normalises correctly without editing this file.
func _normalise(instance: Node3D) -> void:
	if _mesh == null or _mesh.mesh == null:
		return
	var aabb: AABB = _mesh.mesh.get_aabb()
	var scale_factor: float = _model_scale()

	_model_root.scale = Vector3.ONE * scale_factor
	_model_root.rotation = Vector3(0.0, deg_to_rad(MODEL_YAW_DEG), 0.0)
	_model_root.position = Vector3.ZERO

	# The lift and the recentre go on the INNER node, in unscaled model units.
	# Putting them on `_model_root` instead would apply them outside the scale,
	# and the 0.952 m lift would leave the character floating 13 cm above every
	# floor in the house. Rotating a horizontally centred model about Y leaves it
	# centred, so the yaw above does not disturb this.
	var centre: Vector3 = aabb.position + aabb.size * 0.5
	instance.position = Vector3(-centre.x, -aabb.position.y, -centre.z)


func _model_scale() -> float:
	if _mesh == null or _mesh.mesh == null:
		return 1.0
	var height: float = _mesh.mesh.get_aabb().size.y
	if height <= 0.0001:
		return 1.0
	return MODEL_HEIGHT_M / height


## §7, applied to a DUPLICATE of the imported material. The resource on disk and
## the GLB the owner supplied are both left exactly as they were.
func _apply_art_bible_material() -> void:
	if _mesh == null or _mesh.mesh == null:
		return
	var mesh: Mesh = _mesh.mesh
	for surface: int in range(mesh.get_surface_count()):
		var material: Material = mesh.surface_get_material(surface)
		if not (material is StandardMaterial3D):
			continue
		var fixed := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
		# "Metallic 0.0 everywhere. There is no metal." A metallic surface has no
		# diffuse response and renders as a dark silhouette under this game's one
		# directional light.
		fixed.metallic = 0.0
		fixed.metallic_texture = null
		fixed.roughness = ROUGHNESS
		fixed.roughness_texture = null
		# "Normal maps: none." Also drops a 2048^2 texture.
		fixed.normal_enabled = false
		fixed.normal_texture = null
		# Culling on: double-sided doubles overdraw on a closed mesh.
		fixed.cull_mode = BaseMaterial3D.CULL_BACK
		# Nothing in this game is transparent or emissive (§7, and the frame
		# budget's zero transparent surfaces).
		fixed.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		fixed.emission_enabled = false
		_mesh.set_surface_override_material(surface, fixed)


# ---------------------------------------------------------------------------
# Sockets -- LB_Rig_v1 names, never a bone
# ---------------------------------------------------------------------------

## Where a carried child, a held bottle or a hug is aimed on HER. Same contract
## as `baby_little_buddy.gd::get_socket()`: **never returns null.** A socket is
## a node in a skeleton; without one (no model in this build) every lookup
## resolves to this node, which is the specified degradation.
func get_socket(socket_name: String) -> Node3D:
	build()
	if _model_root == null:
		return self
	if not is_inside_tree():
		# Out of the tree no frame ever runs, so a `BoneAttachment3D` would sit at
		# the skeleton's origin rather than on its bone. The headless runner is
		# exactly that case, and a socket that answers differently there than
		# on a device is a socket no test can trust.
		refresh_sockets()
	var socket: Node = _model_root.find_child("Socket_" + socket_name, true, false)
	if socket is Node3D:
		return socket as Node3D
	return self


## True when `socket_name` resolves to a real skeleton-driven node rather than
## to the whole-character fallback.
func has_socket(socket_name: String) -> bool:
	build()
	return _sockets.has(socket_name)


## Every `LB_Rig_v1` socket that actually resolved.
func available_sockets() -> Array:
	build()
	return _sockets.duplicate()


func get_skeleton() -> Skeleton3D:
	build()
	return _skeleton


## Forces every socket onto its bone's current pose now, without waiting for
## the skeleton's own deferred update. Cheap: a pose flush and one transform
## per attachment.
func refresh_sockets() -> void:
	if _skeleton == null:
		return
	if _skeleton.has_method("force_update_all_bone_transforms"):
		_skeleton.call("force_update_all_bone_transforms")
	for child: Node in _skeleton.get_children():
		if child is BoneAttachment3D and child.has_method("on_skeleton_update"):
			child.call("on_skeleton_update")


## Builds one `BoneAttachment3D` per socket from the `RigProfile` -- a bone for
## the `boneMap` entries, a `Marker3D` at a bone-local offset for
## `socketOffsets`. Identical in shape to the child's, so the two rigs are
## addressed the same way. A socket whose bone is absent is skipped and simply
## not reported, never silently placed at the origin.
func _build_sockets() -> Array:
	var built: Array = []
	if _skeleton == null:
		return built
	var profile: Dictionary = _load_rig_profile()
	if profile.is_empty():
		return built
	var bone_map: Dictionary = profile.get("boneMap", {})

	for socket_name: String in bone_map.keys():
		var bone: String = String(bone_map[socket_name])
		if _skeleton.find_bone(bone) == -1:
			push_warning("PinkGirlBuddy: socket '%s' -> bone '%s' not on this skeleton"
					% [socket_name, bone])
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "Socket_" + socket_name
		_skeleton.add_child(attachment)
		# By INDEX, after parenting: `bone_name` alone binds on entering the tree,
		# and out of the tree (the headless runner) the attachment would sit at
		# the skeleton's origin forever. Setting the index binds and poses it now.
		attachment.bone_idx = _skeleton.find_bone(bone)
		built.append(socket_name)

	for socket_name: String in (profile.get("socketOffsets", {}) as Dictionary).keys():
		var spec: Dictionary = profile["socketOffsets"][socket_name]
		var via: String = String(spec.get("bone", ""))
		var bone: String = String(bone_map.get(via, ""))
		if bone.is_empty() or _skeleton.find_bone(bone) == -1:
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "Attach_" + socket_name
		_skeleton.add_child(attachment)
		attachment.bone_idx = _skeleton.find_bone(bone)
		var marker := Marker3D.new()
		marker.name = "Socket_" + socket_name
		var offset: Array = spec.get("offset", [0.0, 0.0, 0.0])
		marker.position = Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
		attachment.add_child(marker)
		built.append(socket_name)
	return built


func _load_rig_profile() -> Dictionary:
	if not FileAccess.file_exists(RIG_PROFILE_PATH):
		return {}
	var file: FileAccess = FileAccess.open(RIG_PROFILE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# The carry pose -- arms round the child, legs still walking
# ---------------------------------------------------------------------------

func _build_carry_pose() -> void:
	if _skeleton == null:
		return
	_carry_pose = CarryPoseScript.new()
	_carry_pose.name = "CarryPose"
	_carry_pose.call("settle")
	_skeleton.add_child(_carry_pose)


## Wraps her arms round whatever she is carrying (true) or lets them swing again
## (false). The modifier eases its own `influence` over `CARRY_POSE_BLEND_SEC`
## inside the skeleton's modification pass -- this file runs no frame loop of
## its own, by rule (`test_buddy_avatar.gd`). Without a rig this is a recorded
## wish and nothing else, which is the honest degradation.
func set_carry_pose(active: bool) -> void:
	build()
	_carry_pose_wanted = active
	if _carry_pose == null:
		return
	_carry_pose.set("blend_seconds", CARRY_POSE_BLEND_SEC)
	_carry_pose.call("set_target", active)
	if not is_inside_tree():
		# No modification passes will ease this; land it, so a headless caller
		# sees the pose it asked for.
		_carry_pose.call("settle")


func is_carry_pose_active() -> bool:
	return _carry_pose_wanted


func get_carry_pose() -> SkeletonModifier3D:
	build()
	return _carry_pose


# ---------------------------------------------------------------------------
# The contact hint -- so she stands ON the floor with no shadows in the game
# ---------------------------------------------------------------------------

## A soft dark-peach ellipse under her feet (`contact_shadow.gd`), inside the
## `Model` node so the sealed-hierarchy contract holds. Sized in metres, so the
## model root's normalising scale is undone on it.
func _build_contact_hint() -> void:
	if _model_root == null:
		return
	var hint: MeshInstance3D = ContactHintScript.build(ContactHintScript.DEFAULT_RADIUS_M)
	var inverse: float = 1.0 / maxf(_model_root.scale.y, 0.0001)
	hint.scale = Vector3.ONE * inverse
	# Under the feet: the mesh is centred on its bounding box and her hair and
	# dress reach further out than her shoes, so the origin is not the stance.
	var feet: Vector3 = Vector3.ZERO
	if _mesh != null and _mesh.mesh != null:
		var instance: Node3D = _model_root.get_child(0) as Node3D
		var offset: Vector3 = instance.position if instance != null else Vector3.ZERO
		feet = ContactHintScript.feet_centre(_mesh.mesh) + offset
	hint.position = Vector3(feet.x, ContactHintScript.LIFT_M * inverse, feet.z)
	_model_root.add_child(hint)


func get_contact_hint() -> MeshInstance3D:
	build()
	if _model_root == null:
		return null
	return _model_root.get_node_or_null(ContactHintScript.NAME) as MeshInstance3D


# ---------------------------------------------------------------------------
# Hair sway -- the head bone, a fraction of a degree, so the long hair moves
# ---------------------------------------------------------------------------

func _build_hair_sway() -> void:
	if _skeleton == null:
		return
	_hair_sway = HairSwayScript.new()
	_hair_sway.name = "HairSway"
	_skeleton.add_child(_hair_sway)


## The head-bone sway modifier, or null without a rig. Its `angles_at()` is the
## envelope; `active` switches it off.
func get_hair_sway() -> SkeletonModifier3D:
	build()
	return _hair_sway


# ---------------------------------------------------------------------------
# The face -- moods and blinks as texture patches (see buddy_face.gd)
# ---------------------------------------------------------------------------

## Binds the compositor to the surface override's albedo. Silent when the
## manifest is missing or the atlas is not the one it was painted for: the
## face system stands down and `available_faces()` says so.
func _prepare_face() -> void:
	if _mesh == null:
		return
	var material: StandardMaterial3D = _mesh.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		return
	var face: RefCounted = FaceScript.new()
	if bool(face.call("setup", material, FACE_MANIFEST_PATH)):
		_face = face


## True when this build's atlas carries mood patches the compositor trusts.
func has_face_moods() -> bool:
	build()
	return _face != null


## Every mood `set_face()` accepts; empty when the feature stood down.
func available_faces() -> Array:
	build()
	return (_face.call("moods") as Array) if _face != null else []


## **Sets the resting face.** Returns false for a mood outside the vocabulary
## or when this build has no moods, and changes nothing in either case. A
## running action's face shows over it and hands back when the action ends.
func set_face(mood: String) -> bool:
	build()
	if _face == null or not (_face.call("moods") as Array).has(mood):
		return false
	_face_mood = mood
	_show_face()
	_schedule_blink()
	return true


## The resting mood asked for, whether or not it could be shown.
func get_face() -> String:
	return _face_mood


## The mood on the atlas right now: the action's face while one runs, else the
## resting one. `content` on a build without moods, which is literally true.
func get_shown_face() -> String:
	build()
	if _face == null:
		return FACE_CONTENT
	return String(_face.call("current_mood"))


func are_eyes_closed() -> bool:
	build()
	return _face != null and bool(_face.call("eyes_closed"))


## Switches the blink on or off. Off also reopens the eyes if a blink was
## mid-way, so a cutscene can freeze her face and get exactly the face it set.
func set_blinking(enabled: bool) -> void:
	build()
	_blink_enabled = enabled
	if not enabled:
		if _blink_timer != null:
			_blink_timer.stop()
		_blink_shut = false
		_show_face()
		return
	_schedule_blink()


func is_blinking_enabled() -> bool:
	return _blink_enabled


## Closes the eyes now if they are open, opens them if they are shut, and
## restarts the ordinary cadence from there. For tests and cutscenes; the
## timer does the same thing on its own schedule.
func blink_now() -> void:
	build()
	if _face == null:
		return
	_on_blink_timeout()


## The mood that should be on the atlas: the action's face wins while it runs.
func _wanted_face() -> String:
	return _action_face if not _action_face.is_empty() else _face_mood


## Does the wanted mood itself shut the eyes (`sleepy`)? Then a blink would be
## invisible and the timer is left idle.
func _mood_closes_eyes() -> bool:
	return _face != null and bool(_face.call("mood_closes_eyes", _wanted_face()))


## Composes the wanted face, keeping a blink that is mid-way shut.
func _show_face() -> void:
	if _face == null:
		return
	_face.call("show", _wanted_face(), _blink_shut and not _mood_closes_eyes(), _mouth_frame)


func _build_blink_timer() -> void:
	if _face == null or _blink_timer != null:
		return
	_blink_timer = Timer.new()
	_blink_timer.name = "BlinkTimer"
	_blink_timer.one_shot = true
	_blink_timer.timeout.connect(_on_blink_timeout)
	# Under the wrapper's own `Model` node, not beside it: the wrapper's direct
	# children are exactly [`Model`] by contract (`test_buddy_avatar.gd`).
	_model_root.add_child(_blink_timer)


## Arms the next blink. Out of the tree a `Timer` cannot run (the headless
## runner), and a mood that already shuts the eyes needs no blink; both leave
## the timer stopped rather than erroring.
func _schedule_blink() -> void:
	if _blink_timer == null or not _blink_enabled or _face == null:
		return
	if not _blink_timer.is_inside_tree():
		return
	if _mood_closes_eyes():
		_blink_timer.stop()
		return
	if _blink_shut:
		return
	if _blink_timer.is_stopped():
		_blink_timer.start(_rng.randf_range(BLINK_GAP_MIN_SEC, BLINK_GAP_MAX_SEC))


func _on_blink_timeout() -> void:
	if _face == null or not _blink_enabled:
		return
	if _blink_shut:
		# Reopen, and arm the next one.
		_blink_shut = false
		_show_face()
		_schedule_blink()
		return
	if _mood_closes_eyes():
		return
	_blink_shut = true
	_show_face()
	if _blink_timer != null and _blink_timer.is_inside_tree():
		_blink_timer.start(BLINK_CLOSED_SEC)


# ---------------------------------------------------------------------------
# TutorFace: expressions (the same channel as the moods)
# ---------------------------------------------------------------------------

## **Sets the resting expression.** The TutorTurn vocabulary is a set of moods
## in the same manifest, so this IS `set_face()`; it exists so a tutor caller
## reads as the contract does. False for a name outside `EXPRESSIONS`, or one
## this build's atlas lacks.
func set_expression(name: String) -> bool:
	if not EXPRESSIONS.has(name):
		return false
	return set_face(name)


func get_expression() -> String:
	return get_face()


## The expressions this build's atlas actually carries (a subset of
## `EXPRESSIONS`; empty when the face system stood down).
func available_expressions() -> Array:
	var out: Array = []
	var moods: Array = available_faces()
	for name: String in EXPRESSIONS:
		if moods.has(name):
			out.append(name)
	return out


# ---------------------------------------------------------------------------
# TutorFace: the mouth for speech
# ---------------------------------------------------------------------------

func _build_mouth() -> void:
	if _model_root == null or _mouth != null:
		return
	_mouth = MouthScript.new()
	_mouth.name = "Mouth"
	var frames: int = 1
	if _face != null:
		frames = int(_face.call("mouth_frame_count"))
	_mouth.call("set_frame_count", frames)
	_mouth.connect("frame_changed", _on_mouth_frame_changed)
	# Under `Model`, like the blink timer: the wrapper's direct children are
	# exactly [`Model`] by contract.
	_model_root.add_child(_mouth)


## `false` closes the mouth now and puts the expression's own mouth back;
## `true` marks her speaking (the amount comes from `set_mouth_open()`).
func set_speaking(active: bool) -> void:
	build()
	_speaking_wanted = active
	if _mouth != null:
		_mouth.call("set_speaking", active)


func is_speaking() -> bool:
	if _mouth != null:
		return bool(_mouth.call("is_speaking"))
	return _speaking_wanted


## The target openness, 0..1. Smoothed inside (`buddy_mouth.gd`); the frame
## follows the smoothed value. 0 (held) closes the mouth within the release.
func set_mouth_open(amount: float) -> void:
	build()
	if _mouth != null:
		_mouth.call("set_target", amount)


## The smoothed openness right now, 0..1 (0 without a face).
func get_mouth_open() -> float:
	return float(_mouth.call("amount")) if _mouth != null else 0.0


## The talk frame on the atlas: 0 closed (the expression's mouth), 1 small,
## 2 mid, 3 open.
func get_mouth_frame() -> int:
	return _mouth_frame


## Advances the mouth smoothing by `seconds` without a frame -- for the
## headless tests and for `buddy_lip_sync.gd`'s envelope replay.
func step_mouth(seconds: float) -> void:
	if _mouth != null:
		_mouth.call("step", seconds)


func get_mouth() -> Node:
	build()
	return _mouth


## The LipSyncSource for this character, made on first use under `Model` and
## aimed at this node. Null without the model.
func get_lip_sync() -> Node:
	build()
	if _model_root == null:
		return null
	if _lip_sync == null:
		_lip_sync = LipSyncScript.new()
		_lip_sync.name = "LipSyncSource"
		_lip_sync.call("set_target", self)
		_model_root.add_child(_lip_sync)
	return _lip_sync


func _on_mouth_frame_changed(frame: int) -> void:
	_mouth_frame = frame
	_show_face()


# ---------------------------------------------------------------------------
# TutorFace: head and hands -- the upper-body gesture layer
# ---------------------------------------------------------------------------

func _build_gesture_layer() -> void:
	if _skeleton == null:
		return
	_gesture_layer = GestureLayerScript.new()
	_gesture_layer.name = "GestureLayer"
	_gesture_layer.call("prepare", _skeleton, ".")
	# After the carry pose (whose arms it must not fight while carrying -- arm
	# gestures are refused then) and before the hair sway, which rides on top.
	_skeleton.add_child(_gesture_layer)


## Plays a gesture on the upper body and returns its length in seconds.
## Returns 0.0, and shows nothing, when refused: not a gesture, no rig,
## travelling faster than `GESTURE_MAX_SPEED_MPS`, or an arm gesture while the
## carry pose holds the arms. Nothing is emitted for a refusal, so a caller
## awaiting a duration of 0.0 is never left waiting.
func play_gesture(name: String) -> float:
	build()
	if not GestureClipsScript.is_gesture(name):
		return 0.0
	if _gesture_layer == null:
		return 0.0
	if _locomotion_speed > GESTURE_MAX_SPEED_MPS:
		return 0.0
	if _carry_pose_wanted and GestureClipsScript.ARM_GESTURES.has(name):
		return 0.0
	return float(_gesture_layer.call("play", name))


## Fades a running gesture out over 0.2 s. Safe when none is running.
func stop_gesture() -> void:
	if _gesture_layer != null:
		_gesture_layer.call("stop")


func get_current_gesture() -> String:
	if _gesture_layer == null:
		return ""
	return String(_gesture_layer.call("current_gesture"))


func available_gestures() -> Array:
	build()
	if _gesture_layer == null:
		return []
	return _gesture_layer.call("available_gestures")


func get_gesture_layer() -> SkeletonModifier3D:
	build()
	return _gesture_layer


## Leans in a little (true) or straightens (false); eased in the skeleton's
## modification pass, so out of the tree it is settled at once.
func set_listening_pose(active: bool) -> void:
	build()
	_listening_wanted = active
	if _gesture_layer == null:
		return
	_gesture_layer.call("set_listening", active)
	if not is_inside_tree():
		_gesture_layer.call("settle")


func is_listening_pose() -> bool:
	return _listening_wanted


# ---------------------------------------------------------------------------
# THE RIG SEAM
# ---------------------------------------------------------------------------

## Binds a real action driver if -- and only if -- the model can actually animate.
##
## This is the single point a rigged re-export attaches at. It is deliberately
## the project's ordinary `AnimationPlayerActionDriver`, the same one
## `LittleBuddyCharacter` builds, so a rigged Big Buddy behaves like every other
## animated character in the game the moment it exists.
##
## With today's asset `_find_animation_player()` returns null, `_driver` stays
## null, and `can_play_action()` is false for everything. Nothing here
## substitutes a procedural motion for the missing clips, and nothing should:
## a bob-and-sway would make an unusable asset look usable.
func _bind_action_driver() -> void:
	var player: AnimationPlayer = get_animation_player()
	if player == null:
		_driver = null
		return
	_driver = AnimationDriverScript.create(player)


func _clip_names() -> Array:
	var player: AnimationPlayer = get_animation_player()
	if player == null:
		return []
	var names: Array = []
	for clip: String in player.get_animation_list():
		names.append(clip)
	return names


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## An explicit override wins, then the driver's own clip length, then the
## semantic default -- the same precedence `LittleBuddyCharacter` uses, so an
## action does not change duration when a rig finally arrives.
func _action_seconds(action_name: String, requested: float) -> float:
	if requested > 0.0:
		return requested
	if _driver != null:
		var from_clip: float = float(_driver.call("get_action_duration", action_name))
		if from_clip > 0.0:
			return from_clip
	return ActionDriverScript.default_duration(action_name)


## Emits `action_finished` after `seconds`.
##
## Outside the tree -- the headless runner -- there is no `SceneTree` to make a
## timer on, so the signal is emitted immediately rather than never. "Never" is
## the one outcome this method exists to prevent.
func _finish_after(action_name: String, seconds: float) -> void:
	var tree: SceneTree = get_tree() if is_inside_tree() else null
	if tree == null or seconds <= 0.0:
		_on_action_due(action_name)
		return
	tree.create_timer(seconds).timeout.connect(_on_action_due.bind(action_name))


func _on_action_due(action_name: String) -> void:
	# A newer request supersedes an older one; only the current action reports.
	if _pending_action != action_name:
		return
	if not ActionDriverScript.is_hold_action(action_name):
		_pending_action = ""
		# A one-shot hands the face back; a held posture keeps its face until
		# `release_action()`.
		_action_face = ""
		_show_face()
	action_finished.emit(action_name)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	for child: Node in node.get_children():
		if child is AnimationPlayer and not (child as AnimationPlayer).get_animation_list().is_empty():
			return child as AnimationPlayer
		var deeper: AnimationPlayer = _find_animation_player(child)
		if deeper != null:
			return deeper
	return null
