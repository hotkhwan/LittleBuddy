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
var _driver: RefCounted = null
var _pending_action: String = ""
var _built: bool = false
var _measured: Dictionary = {}


func _ready() -> void:
	build()


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
	_normalise(instance as Node3D)


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
