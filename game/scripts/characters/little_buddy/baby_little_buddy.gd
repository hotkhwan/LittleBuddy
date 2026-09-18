extends Node3D

## ============================================================================
## LITTLE BUDDY -- the baby, as three Meshy poses. EXPERIMENTAL, DEFAULT OFF.
## ============================================================================
##
## The wrapper around the three generator-produced (Meshy) baby exports in
## `assets/characters/littleBuddy/baby/`. They are not three characters: they are
## **one character in three poses**, and this file is the only thing in the
## project that knows that, knows their filenames, or knows their node layout.
## Everything above it says `set_pose("sitting")` or `set_view_state("hungry")`.
##
## **This does not replace `scripts/baby/baby_view_3d.gd`.** `BabyView3D` is and
## remains the Chapter 2 baby that ships. This is an alternative presentation
## behind a flag, built so that the day a retopologised, rigged re-export lands
## the swap is a scene reference and nothing else.
##
## ---------------------------------------------------------------------------
## ## Why three poses is a design and not a workaround
## ---------------------------------------------------------------------------
##
## None of the three has a skin, a skeleton or an animation clip, so each is
## frozen in the pose it was generated in. For a character who must walk that is
## fatal. **Chapter 2's baby deliberately does not walk** -- a locked product
## decision, restated in `docs/CHARACTER_AGE_STAGES.md` §2 ("non-ambulatory") --
## so a pose-locked mesh costs this character far less than it would cost any
## other. Used as three selectable poses the set covers the chapter:
##
## | Pose       | Reads as                        | Where it belongs            |
## |------------|---------------------------------|-----------------------------|
## | `sleeping` | supine, eyes closed, arms out   | crib, bedtime, "Good night" |
## | `sitting`  | seated, bib, legs forward       | feeding, milk, play         |
## | `standing` | upright, onesie, hair curl      | general, first words        |
##
## `sitting` is the default because feeding is Chapter 2's core loop.
##
## **The swap between poses is a cut, not a transition.** With no rig there is
## nothing to blend, and this file will not pretend otherwise -- see below.
##
## ---------------------------------------------------------------------------
## ## Why it is OFF by default -- measured, not an opinion
## ---------------------------------------------------------------------------
##
## Measured live from the imported assets (`describe_budget()` returns these, so
## they cannot go stale), against art bible §10's 2,500-4,000 for a main
## character:
##
## | Pose       | Triangles | vs 4,000 | vs 2,500 | Skin | Clips |
## |------------|-----------|----------|----------|------|-------|
## | `standing` |   255,458 |   64x    |  102x    | none | none  |
## | `sitting`  |   398,404 |  100x    |  159x    | none | none  |
## | `sleeping` |   373,090 |   93x    |  149x    | none | none  |
##
## `docs/CHARACTER_AGE_STAGES.md` is stricter still -- the Infant is capped at
## **3,000** triangles and one 512^2 map, because it is the hero and is always
## framed large. Every pose here carries three 2048^2 textures. And the missing
## rig is not a budget problem at all: it is a capability problem that no import
## setting fixes.
##
## So `ENABLED` stays `false`, `BabyView3D` stays the shipping baby, and
## `test_baby_avatar.gd` enforces exactly that: the flag may only be `true` while
## **every** available pose is inside the §10 budget AND can actually animate.
## Turning it on with today's assets turns the suite red on purpose.
##
## ---------------------------------------------------------------------------
## ## It does not fake animation, and it says so
## ---------------------------------------------------------------------------
##
## The temptation with an unrigged mesh is a procedural bob-and-sway: translate
## the body on a sine, tilt it a few degrees, call it `idle`. That would look
## like progress and be a lie -- the thing still cannot reach, cannot turn its
## head and cannot lift a bottle, and every decision taken afterwards would be
## taken against a capability the project does not have.
##
## So `can_play_action()` answers **honestly**, by asking the model what clips it
## has. Today that is `false` for every action in the vocabulary.
##
## `play_action()` is nonetheless a **safe, completing no-op**: it emits
## `action_started` immediately and `action_finished` after the action's semantic
## duration, exactly as `LittleBuddyCharacter` and `PinkGirlBuddy` do. Nothing
## visible happens and no caller can hang. That is `CHARACTER_AGE_STAGES.md`
## §9.2 guarantee 1 -- "a mission scripted against a finished model still
## completes against a stub" -- honoured by a stub that admits to being one.
##
## A pose change is *not* an animation and is not routed through the action
## vocabulary. It is a visibility swap between two static meshes, which is the
## one thing this asset set can honestly do.
##
## ## THE RIG SEAM
##
## `_bind_action_driver()` is where a real rig attaches. It looks for an
## `AnimationPlayer` in the instantiated pose and, if it finds one with clips,
## builds the project's standard `AnimationPlayerActionDriver` -- at which point
## `can_play_action()` and `play_action()` start doing real work with **no
## change to this file or any caller**. It is re-run on every pose change, so a
## rigged re-export of one pose works before the other two arrive. The seam is
## live code, not a comment.
##
## What a rigged re-export must deliver, in priority order:
##   1. a skin + skeleton (`LB_Rig_v1`, `CHARACTER_AGE_STAGES.md` §3) -- there is
##      no pose, and no socket, without one;
##   2. clips named from `CharacterActionDriver.KNOWN_ACTIONS`; at minimum
##      `idle`, and for this character `eat`/`drink`/`sleep`/`hug`;
##   3. <= 3,000 triangles and one 512^2 albedo atlas.
##
## Once (1) lands, the three pose files collapse into one rigged model and
## `POSES` becomes a single entry. That is the intended end state; this file is
## shaped so that change is a constant edit.
##
## ---------------------------------------------------------------------------
## ## Normalisation, and why these numbers
## ---------------------------------------------------------------------------
##
## Every raw GLB is pivoted through the middle of the body and normalised **by
## Meshy** to ~1.903 units tall, so height carries no information about the
## character's intended size. All of it is corrected here, in the wrapper; the
## GLBs on disk are left exactly as the owner supplied them.
##
## * **Height 0.78 m.** `CHARACTER_AGE_STAGES.md` §2 locks the Infant family at
##   0.78 m standing, and says so in bold: *"The 0.78 m infant height is
##   load-bearing -- it is what the existing nursery camera and the keep-out
##   volume were framed around. Do not change it without re-framing
##   `baby_room.tscn` and updating `test_nursery_contract.gd`."* A real newborn
##   is 0.50-0.55 m and a real one-year-old about 0.75 m, so 0.78 m with 1 : 3.5
##   head-to-height is the project's deliberate, slightly-older, slightly-chibi
##   infant rather than a literal newborn -- and it is the size the procedural
##   `BabyView3D` these models would stand next to already is. Matching the
##   locked figure beats matching an anatomy textbook: picking 0.55 m would put
##   the avatar a third below the camera it has to be framed by.
##
## * **One character size across all three poses -- the trap in this asset set.**
##   Meshy normalised each file *independently* to the same 1.903-unit bounding
##   box. A seated baby occupies less vertical extent than a standing one, so
##   normalising each pose to the same rendered height would silently scale the
##   sitting baby up until it dwarfed the standing one. `heightFraction` below is
##   that pose's bounding height as a fraction of the **character's standing
##   height**, so the scale applied is
##
##       MODEL_HEIGHT_M * heightFraction / measuredAabbHeight
##
##   and the character is the same size in every pose. The fractions were
##   measured, not guessed, by two independent methods that agree:
##
##   | Pose       | sqrt(surface area) | head width | fraction used |
##   |------------|--------------------|------------|---------------|
##   | `standing` | 2.0465 (x1.000)    | 0.72 (x1.000) | **1.000**  |
##   | `sitting`  | 2.5563 (x1.249)    | 0.91 (x1.264) | **0.796**  |
##   | `sleeping` | 2.0609 (x1.007)    | 0.67 (x0.931) | **1.000**  |
##
##   Skin surface area scales as the square of character size and is close to
##   pose-invariant; head width is a direct linear measure of the same thing.
##   For `sleeping` a third check settles the 1.007/0.931 disagreement: supine
##   body length equals standing height, and the two files agree on that to
##   0.04% (1.9023 vs 1.9030). The remaining difference is the three exports
##   genuinely differing by a few per cent in head size -- they are three
##   separate generations, not three poses of one mesh. **`describe_budget()`
##   reports `characterHeight` derived back through this chain**, so the test
##   asserts all three poses land on one character size rather than trusting the
##   table.
##
## * **`sleeping` is a supine figure authored upright.** Rendered as delivered it
##   is a baby standing with its eyes shut and its arms out -- which is what it
##   looks like, not what it is. `rotationDeg` lays it on its back: face up, head
##   toward -X, so it lies across the frame the way a baby lies along a crib
##   rather than pointing away from the camera. Verified by rendering it
##   (`docs/shots/baby_poses_*.png`), per art bible §12; no assertion could have
##   caught this, and the first attempt -- head toward -Z -- was rejected by
##   looking at it.
##
## * **Lowest point at the wrapper's origin, horizontally centred.** Art bible §6
##   puts the pivot at base centre; the whole house is dimensioned against
##   floor-standing pivots. Derived from the AABB **after** the pose rotation, so
##   it is the resting surface in every pose -- feet when standing, bottom when
##   sitting, back when sleeping.
##
## * **Yaw.** Little Buddy faces -Z at yaw 0 and the camera sits on the +Z side
##   (`room_framing.gd`). These assets face +Z as exported, which is glTF's own
##   convention, so they are turned 180 degrees inside the wrapper and after that
##   obey the project rule. Established by rendering and looking at the faces.
##
## ---------------------------------------------------------------------------
## ## The material decision (§7 is a gate, not advice)
## ---------------------------------------------------------------------------
##
## Applied per pose, on a **duplicate** of the imported material; the imported
## resources and the GLBs on disk are untouched:
##
## * **`metallic = 1.0` -> `0.0`.** §7 is absolute, and this is not a style call:
##   a fully metallic surface has no diffuse response, so under this game's one
##   directional light the baby renders as a dark oily silhouette.
## * **Normal map -> removed.** §7 bans them, and it drops a whole 2048^2 map. On
##   a flat-albedo pastel character it buys surface detail the furniture around
##   it does not have, which by §9's coherence rule makes the *furniture* look
##   broken.
## * **The metallic/roughness (ORM) map goes with the metallic value** -- three
##   2048^2 textures become one.
## * **`cull_mode = DISABLED` -> `BACK`.** Double-sided doubles overdraw on a
##   quarter-million-triangle mesh, and overdraw is the metric that actually
##   costs on a tile-based mobile GPU.
## * Roughness pinned to §7's 0.85-1.0 band.
##
## What the wrapper cannot fix and does not pretend to: the albedo is still
## 2048^2 against a 512^2 budget, and the triangle count is untouchable from
## here. Both need a retopologise-and-bake pass on the assets themselves.
##
## ---------------------------------------------------------------------------
## ## What is deliberately NOT here
## ---------------------------------------------------------------------------
##
## `BabyView3D` also exposes `get_mouth_position()` and `get_hug_position()`, and
## INTERACT places its drop zones from them. They are **not implemented here, on
## purpose.** `CHARACTER_AGE_STAGES.md` §9.1 says no script may "hardcode a
## socket position, height or offset", and §9.3 maps both calls onto
## `get_socket("MouthMarker")` / `get_socket("HugMarker")`. A socket is a node in
## a skeleton. With no skeleton there is no socket, and the only way to answer
## would be to invent a face offset from a bounding box and let the drop zone
## drift wherever the next re-export puts the head.
##
## So `get_socket()` is implemented and honours §9.2 guarantee 2 -- it never
## returns null, it returns this node -- and the two convenience accessors are
## left absent rather than approximated. **This is the reason the wrapper cannot
## be dropped into `baby_room.tscn` even if the triangles were fixed**, and it is
## the second half of the answer to "what is the next step".

const ActionDriverScript := preload("res://scripts/character/character_action_driver.gd")
const AnimationDriverScript := preload("res://scripts/character/animation_player_action_driver.gd")

## Emitted when a requested action begins. Emitted even though nothing is shown,
## so a caller's await is symmetric with `LittleBuddyCharacter`'s.
signal action_started(action_name: String)
## Emitted when a requested action has run for its semantic duration. **Always**
## emitted for an action that started, including an action this character cannot
## show -- that guarantee is the whole reason a no-op is safe.
signal action_finished(action_name: String)
## Emitted when the visible pose changes. Named `pose`, never `action`: a pose
## swap is a cut between two static meshes and must not be mistaken for motion.
signal pose_changed(pose_name: String)


# ---------------------------------------------------------------------------
# THE SWITCH
# ---------------------------------------------------------------------------

## **The single flag that decides whether these models are in the game at all.**
##
## `false` -- `BabyView3D` is the Chapter 2 baby, and not one of the three GLBs
## is loaded, instantiated or paid for at runtime.
##
## Flip to `true` to see them. `test_baby_avatar.gd` will then fail until every
## available pose passes the §10 budget and can actually animate. The placeholder
## stays the character that ships until validation passes, and that promise is
## kept by a test rather than by this comment.
const ENABLED: bool = true

## Deliberate, eyes-open preview of an asset that does NOT pass validation.
##
## `ENABLED` alone used to be forbidden while the model is over budget, which was
## right as an accident guard and wrong as a wall: the owner paid for these models
## and had seen nothing of them in the running game. So enabling is now allowed,
## but only *together with* this flag -- you cannot switch the avatar on by
## accident, only on purpose, and the test says which.
##
## What is still true while this is set: 398k triangles against a 4,000 budget, a
## 2048 albedo against 512, and NO RIG. This is for looking at, not for shipping.
const PREVIEW_OVER_BUDGET: bool = true

## Static so a caller can ask *without* loading anything.
static func is_enabled() -> bool:
	return ENABLED


# ---------------------------------------------------------------------------
# The poses
# ---------------------------------------------------------------------------

## The one place in the project that names these files.
##
## * `path` -- the raw export, gitignored and absent from a fresh clone.
## * `heightFraction` -- this pose's bounding height as a fraction of the
##   character's STANDING height. See the class doc; this is what keeps one
##   character size across three independently-normalised files.
## * `rotationDeg` -- the orientation correction. 180 about Y turns the exported
##   +Z facing into the project's -Z. `sleeping` is instead reclined onto its
##   back, which also leaves it facing the right way (upward).
const POSES: Dictionary = {
	# The rigged runtime derivative: one skinned, animatable model that supersedes
	# the three pose-locked exports. Built locally by
	# `tools/build_runtime_character.py` from the Meshy rig -- skin weights
	# repaired, material de-emissived, texture halved. THE RIG SEAM below binds a
	# real action driver the moment this pose is the one on screen, so `sockets`
	# and `can_play_action()` start answering truthfully with no caller change.
	"rigged": {
		"path": "res://assets/characters/littleBuddy/baby/babyLittleBuddy_v01.glb",
		"heightFraction": 1.0,
		"rotationDeg": Vector3(0.0, 180.0, 0.0),
	},
	"standing": {
		"path": "res://assets/characters/littleBuddy/baby/baby_standing_v01.glb",
		"heightFraction": 1.0,
		"rotationDeg": Vector3(0.0, 180.0, 0.0),
	},
	"sitting": {
		"path": "res://assets/characters/littleBuddy/baby/baby_sitting_v01.glb",
		"heightFraction": 0.796,
		"rotationDeg": Vector3(0.0, 180.0, 0.0),
	},
	"sleeping": {
		"path": "res://assets/characters/littleBuddy/baby/baby_sleeping_v01.glb",
		"heightFraction": 1.0,
		"rotationDeg": Vector3(-90.0, 90.0, 0.0),
	},
}

## **Read this before putting the wrapper in `baby_room.tscn`.**
##
## The project has two facing conventions and they are opposites, which is a
## fact about the project rather than a decision taken here:
##
## * `toddler_view.gd` (the house Little Buddy) and `pink_girl_buddy.gd` face
##   **-Z** at yaw 0 -- "the nose, eyes and mouth are all at negative Z".
## * `baby_view_3d.gd` (the Chapter 2 baby) faces **+Z**: its eyes sit at
##   `z = +0.16` and the nursery camera at `z = +2.075` looks straight at them.
##
## This wrapper follows the first, because it is the one every *character* in
## the project follows and the one a rigged re-export will be authored against.
## The consequence is a silent, ugly failure mode: dropped onto `baby_room.tscn`'s
## `BabyView` node at identity, this baby would show the child the back of its
## head, and no assertion anywhere would notice. So the yaw a Chapter 2 scene
## needs is named here rather than left to be rediscovered.
const CHAPTER_2_YAW_DEG: float = 180.0

## Feeding is Chapter 2's core loop, so the chapter's baby sits -- but only while
## the unrigged pose set is all there is. `resolve_pose()` prefers `rigged` when
## that model is in the build, because one animatable model beats three frozen
## ones for every state including feeding.
const DEFAULT_POSE: String = "sitting"

## The rigged model, when present, is preferred over every pose-locked export.
const PREFERRED_POSE: String = "rigged"

## Where the bone-name adapter lives. The ONLY file that may name a Meshy bone;
## everything above `get_socket()` speaks `LB_Rig_v1` and nothing else.
const RIG_PROFILE_PATH: String = "res://content/rig_profiles/meshy_baby_v01.json"

## Animation-only exports (armature, no mesh -- ~60 KB each) whose clips are
## merged onto the rigged model's own `AnimationPlayer`. Kept separate rather
## than using Meshy's full walk/run GLBs, which each carry a redundant 3.9 MB
## copy of the mesh with the UNREPAIRED weights.
const CLIP_SOURCES: Dictionary = {
	"walk": "res://assets/characters/littleBuddy/baby/babyLittleBuddy_walk_v01.glb",
	"run": "res://assets/characters/littleBuddy/baby/babyLittleBuddy_run_v01.glb",
}

## `LB_Rig_v1` socket names, plus the two aliases Chapter 2 already calls by
## (`CHARACTER_AGE_STAGES.md` §9.3 maps `get_mouth_position()` /
## `get_hug_position()` onto these). Callers use these names; no caller ever
## names a bone.
const SOCKET_ALIASES: Dictionary = {
	"MouthMarker": "mouth",
	"HugMarker": "hugTarget",
}

## **The adapter.** Chapter 2's five view states, mapped onto the nearest pose.
##
## `BabyView3D.set_view_state()` is the vocabulary every existing caller already
## uses -- `FeedActivity` talks to the baby through it by duck typing -- so this
## wrapper answers to it unchanged. What it cannot do is answer *differently*
## per state: with no rig, changing pose is an instantaneous mesh cut, and a baby
## that teleported from seated to standing between `hungry` and `happy` would
## read as a glitch rather than as a reaction. **So the whole feeding loop stays
## on one pose**, and the other two are addressed by scene context --
## `set_pose("sleeping")` for the crib, `set_pose("standing")` for first words --
## which are not view states and never were.
##
## The adapter still earns its place: it is the single line a designer changes to
## re-point a state, and it guarantees every state resolves to a pose that is
## actually in the build (see `resolve_pose()`), which matters because these
## files are gitignored and a given build may have one, two, three or none.
const VIEW_STATE_POSES: Dictionary = {
	"idle": "sitting",
	"hungry": "sitting",
	"drinking": "sitting",
	"happy": "sitting",
	"hugging": "sitting",
}

## `BabyView3D`'s fallback for an unrecognised state, matched exactly so a scene
## mistake behaves the same way against either presentation.
const FALLBACK_VIEW_STATE: String = "idle"

## Preference order when the requested pose is not in this build. Sitting first
## for the same reason it is the default.
const POSE_FALLBACK_ORDER: Array[String] = ["rigged", "sitting", "standing", "sleeping"]


# ---------------------------------------------------------------------------
# Normalisation and budget constants
# ---------------------------------------------------------------------------

## Metres. `CHARACTER_AGE_STAGES.md` §2, Infant, locked and load-bearing.
const MODEL_HEIGHT_M: float = 0.78

## §7: roughness 0.85-1.0. "Nothing in this game is shiny."
const ROUGHNESS: float = 0.9

## §10, main character, upper bound. The Infant is capped tighter still at 3,000
## by `CHARACTER_AGE_STAGES.md` §7; the looser figure is used for the gate so
## that failing it is beyond argument.
const MAX_TRIANGLES: int = 4000
## §7: one 512x512 atlas per family.
const MAX_TEXTURE_SIZE: int = 512

## Pose holders are named `Pose_standing`, `Pose_sitting`, `Pose_sleeping`. The
## raw GLB hierarchy hangs below one of these and is never addressed from
## outside this file.
const POSE_NODE_PREFIX: String = "Pose_"

## pose name -> { "root": Node3D, "mesh": MeshInstance3D }. Populated lazily:
## selecting one pose never pays for the other two.
var _loaded: Dictionary = {}
var _measured: Dictionary = {}

var _requested_pose: String = default_pose()
var _view_state: String = FALLBACK_VIEW_STATE
var _driver: RefCounted = null
var _pending_action: String = ""
var _built: bool = false


func _ready() -> void:
	build()


## Idempotent, and callable before `_ready()` -- the headless `--script` runner
## never fires `_ready()` for nodes added to the root, which is the same reason
## `toddler_view.gd::build()` and `pink_girl_buddy.gd::build()` exist.
func build() -> void:
	if _built:
		return
	_built = true
	set_pose(_requested_pose)


# ---------------------------------------------------------------------------
# The pose surface
# ---------------------------------------------------------------------------

## Every pose the wrapper knows about, whether or not its file is in this build.
static func known_poses() -> Array:
	return POSES.keys()


static func is_known_pose(pose_name: String) -> bool:
	return POSES.has(pose_name)


## Is this pose's file in this build? Answered without loading it -- the whole
## point of the lazy load is that asking is cheap.
static func is_pose_available(pose_name: String) -> bool:
	if not POSES.has(pose_name):
		return false
	return ResourceLoader.exists(String(POSES[pose_name]["path"]))


## The pose that would actually be shown for a request: the request itself when
## its file is present, else the first pose in `POSE_FALLBACK_ORDER` that is,
## else "" when this build has none of them.
static func resolve_pose(pose_name: String) -> String:
	# An EXPLICIT request always wins, including a request for a pose-locked
	# export. An earlier version of this let the rigged model override any
	# request, which quietly broke `set_pose("standing")` -- the caller asked for
	# one thing and got another, with no way to tell. The rigged model is
	# preferred by being what the defaults POINT AT (`default_pose()`,
	# `pose_for_view_state()`), not by overruling the caller.
	if is_pose_available(pose_name):
		return pose_name
	for candidate: String in POSE_FALLBACK_ORDER:
		if is_pose_available(candidate):
			return candidate
	return ""


## **Select a pose.** Loads its GLB the first time it is asked for and hides
## every other pose. Returns false -- and changes nothing -- for a name outside
## `POSES`, so a typo in content is caught rather than silently absorbed.
##
## This is not an action and does not go through the action vocabulary: it is a
## visibility swap between two static meshes, which is the one thing this asset
## set can honestly do. The change is a cut; there is no rig to blend with.
func set_pose(pose_name: String) -> bool:
	if not is_known_pose(pose_name):
		return false
	_built = true
	var previous: String = get_pose()
	_requested_pose = pose_name

	var shown: String = resolve_pose(pose_name)
	if not shown.is_empty():
		_ensure_pose(shown)
	for loaded_pose: String in _loaded.keys():
		var holder: Node3D = _loaded[loaded_pose]["root"]
		holder.visible = loaded_pose == shown

	_bind_action_driver()
	_measured = {}
	if shown != previous:
		pose_changed.emit(shown)
	return true


## The pose actually on screen, or "" when this build has no model for it. The
## honest counterpart to `get_requested_pose()`.
func get_pose() -> String:
	build()
	for pose_name: String in _loaded.keys():
		if (_loaded[pose_name]["root"] as Node3D).visible:
			return pose_name
	return ""


## The pose last asked for, whether or not its file is in the build.
func get_requested_pose() -> String:
	return _requested_pose


## Poses whose GLB has actually been instantiated. Used to assert the load is
## lazy: after one `set_pose()` this holds exactly one entry.
func get_loaded_poses() -> Array:
	return _loaded.keys()


func is_pose_loaded(pose_name: String) -> bool:
	return _loaded.has(pose_name)


# ---------------------------------------------------------------------------
# The Chapter 2 view-state adapter
# ---------------------------------------------------------------------------

## The pose a view state maps to, by the table alone -- no availability check, so
## this answers the same in a checkout that has the assets and one that does not.
## "" for a state outside Chapter 2's five.
static func pose_for_view_state(state_name: String) -> String:
	if not VIEW_STATE_POSES.has(state_name):
		return ""
	# Chapter 2's states all mapped to `sitting` because a pose-locked mesh could
	# not do better. When the rigged model is in the build every state points at
	# it instead: one skinned model covers all five and can actually react, which
	# is what the table was working around.
	if is_pose_available(PREFERRED_POSE):
		return PREFERRED_POSE
	return String(VIEW_STATE_POSES[state_name])


## The pose a fresh wrapper starts on: the rigged model when it is in the build,
## else Chapter 2's seated export.
static func default_pose() -> String:
	return PREFERRED_POSE if is_pose_available(PREFERRED_POSE) else DEFAULT_POSE


## `BabyView3D`'s method, unchanged in name, arguments and tolerance for
## nonsense: "idle" | "hungry" | "drinking" | "happy" | "hugging", and anything
## else falls back to idle so a scene mistake never crashes the baby.
func set_view_state(state_name: String) -> void:
	_view_state = state_name if VIEW_STATE_POSES.has(state_name) else FALLBACK_VIEW_STATE
	set_pose(pose_for_view_state(_view_state))


func get_view_state_name() -> String:
	return _view_state


# ---------------------------------------------------------------------------
# The §9.1 character contract, as far as an unrigged mesh can honour it
# ---------------------------------------------------------------------------

## `CHARACTER_AGE_STAGES.md` §2. Read, never assumed, by camera framing and UI
## anchoring -- which is why it is a method and not a caller-side constant.
func get_height() -> float:
	return MODEL_HEIGHT_M


func get_family() -> String:
	return "infant"


func get_variant() -> String:
	return "infant"


## §9.2 guarantee 2: **never returns null.** A socket is a node in a skeleton;
## these assets have no skeleton, so every socket is missing and every lookup
## returns this node, which is the specified degradation. It deliberately does
## not synthesise a position from the bounding box -- see the class doc.
func get_socket(socket_name: String) -> Node3D:
	build()
	var pose_name: String = get_pose()
	if pose_name.is_empty():
		return self
	var wanted: String = String(SOCKET_ALIASES.get(socket_name, socket_name))
	var root: Node3D = _loaded[pose_name]["root"] as Node3D
	# Sockets built by `_build_sockets()` are named `Socket_<semantic>`; an
	# unrigged pose has none and falls through to the §9.2 degradation below.
	var socket: Node = root.find_child("Socket_" + wanted, true, false)
	if socket is Node3D:
		return socket as Node3D
	var found: Node = root.find_child(socket_name, true, false)
	if found is Node3D:
		return found as Node3D
	return self


## Every `LB_Rig_v1` socket that actually resolved on the pose currently shown.
## Empty for a pose-locked mesh, which is the honest answer: a socket is a node
## in a skeleton, and those exports have no skeleton.
func available_sockets() -> Array:
	build()
	var pose_name: String = get_pose()
	if pose_name.is_empty():
		return []
	return (_loaded[pose_name].get("sockets", []) as Array).duplicate()


## True when `socket_name` resolves to a real skeleton-driven node rather than to
## the whole-character fallback. Callers that need to know whether they are
## aiming at a mouth or at an origin ask this.
func has_socket(socket_name: String) -> bool:
	var wanted: String = String(SOCKET_ALIASES.get(socket_name, socket_name))
	return available_sockets().has(wanted)


## `BabyView3D`'s accessors, now answerable because there is a skeleton to answer
## from. They were deliberately absent while the assets were pose-locked -- see
## the class doc -- and are implemented here rather than approximated from a
## bounding box, which is what §9.1 forbids.
func get_mouth_position() -> Vector3:
	return get_socket("mouth").global_position


func get_hug_position() -> Vector3:
	return get_socket("hugTarget").global_position


## True when at least one pose is in this build and was instantiated. False is a
## normal, supported state: a build that ships without the assets still loads
## this scene, still answers every method, and simply shows nothing.
func is_model_available() -> bool:
	build()
	return _current_mesh() != null


# ---------------------------------------------------------------------------
# The semantic action surface -- honest about what it cannot do
# ---------------------------------------------------------------------------

## Is `action_name` part of the game's vocabulary at all? Single-sourced from
## `character_action_driver.gd` so the baby and the caregiver can never drift
## into two vocabularies.
func is_known_action(action_name: String) -> bool:
	return ActionDriverScript.is_known_action(action_name)


## **Can this character actually show `action_name` right now?**
##
## Answered by asking the model, not by returning a constant: today every pose
## has no skin and no clips, so this is `false` for every action in the
## vocabulary, and it becomes `true` by itself the day a rigged re-export
## arrives. See THE RIG SEAM in the class doc.
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

	action_started.emit(action_name)
	_finish_after(action_name, _action_seconds(action_name, seconds))
	return true


## Ends a held posture. Returns the posture released, or "". Always safe.
## With no rig there is no posture to leave, so this is "" until one exists.
func release_action() -> String:
	build()
	var held: String = get_held_action()
	if held.is_empty():
		return ""
	_pending_action = ""
	if _driver != null:
		_driver.call("rest", false)
	return held


## The posture currently held ("sit", "sleep", "hold"), or "".
##
## Note that this is about the ACTION vocabulary, not about `POSES`: the
## `sitting` mesh being on screen is not the character holding a `sit` pose, and
## conflating the two would let a caller believe the baby had sat down on cue.
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


## The animation player driving the current pose, or `null`. Null today: none of
## the assets has one. Present so the wrapper is shaped like `toddler_view.gd`
## and so a subtree search would find a rig the day there is one.
func get_animation_player() -> AnimationPlayer:
	build()
	var pose_name: String = get_pose()
	if pose_name.is_empty():
		return null
	return _find_animation_player(_loaded[pose_name]["root"])


# ---------------------------------------------------------------------------
# Measurement -- so the budget can be asserted rather than remembered
# ---------------------------------------------------------------------------

## Triangles in the pose currently on screen. Mirrors
## `baby_view_3d.gd`'s own count so the two presentations can be compared.
func count_triangles() -> int:
	return int(describe_budget().get("triangles", 0))


## Everything the gate and the art review need, measured live from the imported
## asset so no number in this file can go stale.
##
## `pose_name` defaults to the pose on screen. Naming one **loads it**, because
## auditing a pose is a deliberate act; the lazy path is `set_pose()`.
##
## The `metallic` / `roughness` / `doubleSided` / `hasNormalMap` keys report the
## asset **as delivered**, read from the mesh's own material -- this dictionary
## is an audit of the source, and an audit that reported the values we just fixed
## would be worthless. The `applied*` keys report what is actually rendered, read
## back from the surface override, so the §7 fix can be asserted rather than
## assumed.
##
## Keys (camelCase, per `CLAUDE.md`): `pose`, `available`, `triangles`,
## `vertices`, `surfaces`, `materials`, `textures`, `maxTextureSize`, `metallic`,
## `roughness`, `doubleSided`, `hasNormalMap`, `appliedMetallic`,
## `appliedRoughness`, `appliedDoubleSided`, `appliedNormalMap`,
## `appliedTextures`, `hasSkin`, `animationClips`, `rawHeight`, `appliedScale`,
## `placedHeight`, `characterHeight`, `restingY`, `centreX`, `centreZ`.
func describe_budget(pose_name: String = "") -> Dictionary:
	build()
	var wanted: String = pose_name if not pose_name.is_empty() else get_pose()
	if wanted.is_empty():
		return _empty_report("")
	if pose_name.is_empty() and not _measured.is_empty():
		return _measured.duplicate(true)

	if not _ensure_pose(wanted):
		return _empty_report(wanted)
	var report: Dictionary = _measure(wanted)
	if wanted == get_pose():
		_measured = report
	return report.duplicate(true)


## Every pose in this build, measured. **Deliberately not lazy** -- it loads all
## three, because that is what auditing means. Only the gate and the test call it.
func audit_poses() -> Dictionary:
	var audit: Dictionary = {}
	for pose_name: String in POSES.keys():
		if is_pose_available(pose_name):
			audit[pose_name] = describe_budget(pose_name)
	return audit


## The one-line verdict: does **every pose in this build** meet the bar the flag
## is gated on? Both halves matter -- a 4,000-triangle mesh that still cannot
## pose is no more shippable as a character than a 398,404-triangle one. And it
## is every pose, not the current one, because `set_pose()` can reach any of them
## at runtime: a gate that only measured whatever happened to be on screen would
## be one call away from being wrong.
func passes_validation() -> bool:
	return validation_failures().is_empty()


## Plain sentences naming every reason these assets are not shippable as a
## character. Empty when they are. Used by the test so a failure reads as a brief
## rather than as "expected true, got false".
func validation_failures() -> Array:
	var reasons: Array = []
	var audit: Dictionary = audit_poses()
	if audit.is_empty():
		reasons.append("no baby pose model is in this build at all")
		return reasons
	for pose_name: String in audit.keys():
		var report: Dictionary = audit[pose_name]
		var triangles: int = int(report.get("triangles", 0))
		if triangles > MAX_TRIANGLES:
			reasons.append("%s: %d triangles against the art bible §10 budget of %d -- %.0fx over"
					% [pose_name, triangles, MAX_TRIANGLES, float(triangles) / float(MAX_TRIANGLES)])
		var texture_size: int = int(report.get("maxTextureSize", 0))
		if texture_size > MAX_TEXTURE_SIZE:
			reasons.append("%s: a %d x %d texture against §7's one %d x %d atlas"
					% [pose_name, texture_size, texture_size, MAX_TEXTURE_SIZE, MAX_TEXTURE_SIZE])
		if not bool(report.get("hasSkin", false)):
			reasons.append("%s: no skin and no skeleton, so it cannot be posed and has no sockets"
					% pose_name)
		if (report.get("animationClips", []) as Array).is_empty():
			reasons.append("%s: no animation clips, so it cannot idle and it cannot react"
					% pose_name)
	return reasons


# ---------------------------------------------------------------------------
# Building and normalising
# ---------------------------------------------------------------------------

## Instantiates one pose, once. Returns false when its file is not in this build.
func _ensure_pose(pose_name: String) -> bool:
	if _loaded.has(pose_name):
		return true
	if not is_pose_available(pose_name):
		return false
	var packed: Resource = load(String(POSES[pose_name]["path"]))
	if not (packed is PackedScene):
		return false
	var instance: Node = (packed as PackedScene).instantiate()
	if not (instance is Node3D):
		if instance != null:
			instance.free()
		return false

	# Three nodes, and the split matters. The holder carries the placement in
	# METRES; the oriented node carries the pose rotation and the scale; the raw
	# GLB carries only a recentring in its own MODEL units. Putting the recentring
	# on the holder instead would apply it outside the scale and leave the
	# character floating above every floor in the house.
	var holder: Node3D = Node3D.new()
	holder.name = POSE_NODE_PREFIX + pose_name
	# Hidden on arrival. `set_pose()` is the only thing that reveals a pose, so
	# auditing a pose (which loads it) can never put two babies on screen.
	holder.visible = false
	add_child(holder)
	var oriented: Node3D = Node3D.new()
	oriented.name = "Oriented"
	holder.add_child(oriented)
	oriented.add_child(instance)

	var mesh_instance: MeshInstance3D = _find_mesh(instance)
	_loaded[pose_name] = {"root": holder, "mesh": mesh_instance, "sockets": []}
	_apply_art_bible_material(mesh_instance)
	_normalise(pose_name, holder, oriented, instance as Node3D, mesh_instance)
	_merge_clips(instance)
	_loaded[pose_name]["sockets"] = _build_sockets(instance)
	return true


## Merges the walk/run clips onto the pose's own `AnimationPlayer`.
##
## The clips ship as armature-only exports so the mesh is not duplicated three
## times. Their skeleton is bone-for-bone the one in the rigged model -- same
## names, same hierarchy, same order -- so the imported track paths resolve
## against this model unchanged. That identity is the whole reason animation
## compatibility survives the weight repair: the repair touched `WEIGHTS_0`
## only, never the skeleton.
##
## This is NOT a hand-built animation. Every clip here was authored by the rig
## and is loaded from a file; nothing is synthesised, tweened or driven per
## frame.
func _merge_clips(instance: Node) -> void:
	var player: AnimationPlayer = _find_animation_player(instance)
	if player == null:
		return
	var library: AnimationLibrary = player.get_animation_library("")
	if library == null:
		return
	for action: String in CLIP_SOURCES.keys():
		var path: String = String(CLIP_SOURCES[action])
		if not ResourceLoader.exists(path):
			continue
		var packed: Resource = load(path)
		if not (packed is PackedScene):
			continue
		var clip_root: Node = (packed as PackedScene).instantiate()
		var clip_player: AnimationPlayer = _find_animation_player(clip_root)
		if clip_player != null:
			for clip_name: String in clip_player.get_animation_list():
				var anim: Animation = clip_player.get_animation(clip_name)
				if anim != null and not library.has_animation(action):
					var copy: Animation = anim.duplicate(true)
					copy.loop_mode = Animation.LOOP_LINEAR
					library.add_animation(action, copy)
		clip_root.free()


## Builds one `BoneAttachment3D` per `LB_Rig_v1` socket from the `RigProfile`.
##
## Two kinds, exactly as `LB_RIG_V1.md` §3 specifies:
##   * `boneMap`        -- the socket IS that bone's transform.
##   * `socketOffsets`  -- no skeleton has a mouth bone, so the socket is a
##                         `Marker3D` parented to a mapped bone at a fixed local
##                         offset, and therefore follows the animation for free.
##
## A socket whose bone is absent is skipped and reported by `available_sockets()`
## as missing, never silently placed at the origin.
func _build_sockets(instance: Node) -> Array:
	var built: Array = []
	var skeleton: Skeleton3D = _find_skeleton(instance)
	if skeleton == null:
		return built
	var profile: Dictionary = _load_rig_profile()
	if profile.is_empty():
		return built
	var bone_map: Dictionary = profile.get("boneMap", {})

	for socket_name: String in bone_map.keys():
		var bone: String = String(bone_map[socket_name])
		if skeleton.find_bone(bone) == -1:
			push_warning("BabyLittleBuddy: socket '%s' -> bone '%s' not on this skeleton"
					% [socket_name, bone])
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "Socket_" + socket_name
		attachment.bone_name = bone
		skeleton.add_child(attachment)
		built.append(socket_name)

	for socket_name: String in (profile.get("socketOffsets", {}) as Dictionary).keys():
		var spec: Dictionary = profile["socketOffsets"][socket_name]
		var via: String = String(spec.get("bone", ""))
		var bone: String = String(bone_map.get(via, ""))
		if bone.is_empty() or skeleton.find_bone(bone) == -1:
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "Attach_" + socket_name
		attachment.bone_name = bone
		skeleton.add_child(attachment)
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


## Lowest point at the wrapper's origin, horizontally centred, turned to the
## pose's authored orientation, and scaled so that **every pose is the same
## character**. Every number is derived from the measured AABB, so a re-export at
## a different size, pivot or Meshy normalisation still lands.
func _normalise(pose_name: String, holder: Node3D, oriented: Node3D, instance: Node3D,
		mesh_instance: MeshInstance3D) -> void:
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var aabb: AABB = mesh_instance.mesh.get_aabb()

	# Centre the raw model on its own origin, in unscaled model units.
	var centre: Vector3 = aabb.position + aabb.size * 0.5
	instance.position = -centre

	oriented.rotation = _pose_rotation(pose_name)
	oriented.scale = Vector3.ONE * _pose_scale(pose_name, aabb)

	# Where that leaves the model, measured rather than predicted: rotate a box
	# and its resting face is no longer the one it started on.
	var centred: AABB = AABB(aabb.position - centre, aabb.size)
	var placed: AABB = oriented.get_transform() * centred
	holder.position = Vector3(
		-(placed.position.x + placed.size.x * 0.5),
		-placed.position.y,
		-(placed.position.z + placed.size.z * 0.5))


func _pose_rotation(pose_name: String) -> Vector3:
	var degrees: Vector3 = POSES[pose_name]["rotationDeg"]
	return Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))


## The scale that puts this pose at the SAME character size as every other,
## rather than at the same rendered height. See the class doc -- this is the
## single most important line in the file for how the three read together.
func _pose_scale(pose_name: String, aabb: AABB) -> float:
	if aabb.size.y <= 0.0001:
		return 1.0
	return MODEL_HEIGHT_M * float(POSES[pose_name]["heightFraction"]) / aabb.size.y


## §7, applied to a DUPLICATE of the imported material. The resource on disk and
## the GLBs the owner supplied are both left exactly as they were.
func _apply_art_bible_material(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var mesh: Mesh = mesh_instance.mesh
	for surface: int in range(mesh.get_surface_count()):
		var material: Material = mesh.surface_get_material(surface)
		if not (material is StandardMaterial3D):
			continue
		var fixed := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
		# "Metallic 0.0 everywhere. There is no metal." A metallic surface has no
		# diffuse response and renders as a dark silhouette under one light.
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
		mesh_instance.set_surface_override_material(surface, fixed)


# ---------------------------------------------------------------------------
# THE RIG SEAM
# ---------------------------------------------------------------------------

## Binds a real action driver if -- and only if -- the pose on screen can
## actually animate.
##
## This is the single point a rigged re-export attaches at, and it is
## deliberately the project's ordinary `AnimationPlayerActionDriver`, the same
## one `LittleBuddyCharacter` builds, so a rigged baby behaves like every other
## animated character the moment it exists. Re-run on every pose change, so one
## rigged pose works before the other two arrive.
##
## With today's assets `_find_animation_player()` returns null, `_driver` stays
## null, and `can_play_action()` is false for everything. Nothing here
## substitutes a procedural motion for the missing clips, and nothing should.
func _bind_action_driver() -> void:
	var player: AnimationPlayer = get_animation_player()
	if player == null:
		_driver = null
		return
	_driver = AnimationDriverScript.create(player)


## Clips on a NAMED pose, not on whatever is visible -- `validation_failures()`
## audits all three, and a pose that reported the current pose's clips would let
## one rigged re-export vouch for two unrigged ones.
func _clip_names(pose_name: String) -> Array:
	if not _loaded.has(pose_name):
		return []
	var player: AnimationPlayer = _find_animation_player(_loaded[pose_name]["root"])
	if player == null:
		return []
	var names: Array = []
	for clip: String in player.get_animation_list():
		names.append(clip)
	return names


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _current_mesh() -> MeshInstance3D:
	var pose_name: String = get_pose()
	if pose_name.is_empty():
		return null
	return _loaded[pose_name]["mesh"]


func _empty_report(pose_name: String) -> Dictionary:
	return {
		"pose": pose_name,
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
		"appliedScale": 0.0,
		"placedHeight": 0.0,
		"characterHeight": 0.0,
		"restingY": 0.0,
		"centreX": 0.0,
		"centreZ": 0.0,
	}


func _measure(pose_name: String) -> Dictionary:
	var report: Dictionary = _empty_report(pose_name)
	var mesh_instance: MeshInstance3D = _loaded[pose_name]["mesh"]
	if mesh_instance == null or mesh_instance.mesh == null:
		return report

	var mesh: Mesh = mesh_instance.mesh
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
		var applied: Material = mesh_instance.get_surface_override_material(surface)
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
	report["hasSkin"] = mesh_instance.skin != null
	report["animationClips"] = _clip_names(pose_name)
	report["rawHeight"] = aabb.size.y

	# Measured through the real transform chain rather than recomputed from the
	# constants, so a normalisation that silently stopped working is visible.
	var placed: AABB = aabb
	var node: Node = mesh_instance
	while node != null and node != self:
		if node is Node3D:
			placed = (node as Node3D).get_transform() * placed
		node = node.get_parent()
	var applied_scale: float = (_loaded[pose_name]["root"] as Node3D).get_child(0).scale.y
	report["appliedScale"] = applied_scale
	report["placedHeight"] = placed.size.y
	# A SKINNED mesh is not placed by that chain. Meshy's rig exports bones in
	# centimetres under an `Armature` node carrying a 0.01 unit conversion, and
	# the mesh's own vertex data is already in the post-inverse-bind metre space
	# the bones resolve to. Walking the node chain therefore applies that 0.01 a
	# second time and reports a character 100x too small -- 0.0078 m rather than
	# 0.78 m. What is actually rendered is the mesh extent times the scale this
	# wrapper applies, which is what the bone and socket world positions agree
	# with. Measured, not assumed: `runtime_character_validation` checks the
	# resolved socket heights against this figure.
	if mesh_instance.skin != null and aabb.size.y > 0.0001:
		report["placedHeight"] = aabb.size.y * applied_scale
		report["restingY"] = 0.0
	report["restingY"] = placed.position.y
	report["centreX"] = placed.position.x + placed.size.x * 0.5
	report["centreZ"] = placed.position.z + placed.size.z * 0.5
	# The standing height this pose has been scaled to. Equal to MODEL_HEIGHT_M
	# in every pose when the one-character-size rule is holding, and derived back
	# through the real numbers rather than restating the constant.
	var fraction: float = float(POSES[pose_name]["heightFraction"])
	if fraction > 0.0:
		report["characterHeight"] = aabb.size.y * applied_scale / fraction
	return report


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
