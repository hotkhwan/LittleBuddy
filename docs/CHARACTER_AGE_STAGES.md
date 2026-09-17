# Character Age Stages — Model Families & Replacement Contract

**Status:** design lock proposal. Planning only — no code, scene, asset or `project.godot` change
is implied by this document.
**Scope:** which 3D character models the game actually needs, how they share a rig and an
animation library, and the exact contract that lets a commissioned or generated model **drop in
and replace a temporary one without touching a single line of mission logic**.

**Relationship to other docs**
- Builds on `docs/CUSTOM_BABY_SPEC.md` (the infant commission spec). Where this document
  differs, it says so explicitly under "Amendments to CUSTOM_BABY_SPEC" (§10) — it does not
  silently override it.
- Implements `LITTLE_BUDDY_GAME_BIBLE.md` §2.1 ("age-stage model families"), §12 (movement),
  §13 (animation), §16 (generation strategy), §17 (budgets).
- Visual treatment — palette, face style, materials, lighting — lives in
  `docs/ART_BIBLE_DRAFT.md`. This document is geometry, rig, sockets, animation and budget only.
- Story/level definitions, the interaction matrix and the vocabulary roadmap are being written
  in parallel; where this document names a chapter it is quoting Bible §8, not redefining it.

---

## 1. Headline decision

**Five model families. Not ten stages, not one per level.**

| # | Family | Chapters covered | Bible life stages folded in | Variants |
|---|---|---|---|---|
| 1 | **Infant** | Ch1 L5 · Ch2 L6–L10 | newborn, baby | 1 |
| 2 | **Toddler** | Ch3 L11–L15 · Ch4 L16–L20 | toddler, preschool child | 2 (`toddler`, `preschool`) |
| 3 | **Child** | Ch5 L21–L25 · Ch6 L26–L30 | primary-school child, older child | 2 (`child`, `olderChild`) |
| 4 | **Teen** | Ch7 L31–L35 · Ch8 L36–L37 | teen | 1 |
| 5 | **Adult** | Ch9 (Little Buddy) · **Ch1–Ch9 (Mom & Dad)** | university/training age, young adult, **both parents** | 3 (`mom`, `dad`, `youngAdult`) |

That is **5 base meshes, 9 shipped variants, 1 skeleton, 1 animation library**.

Chapters 1 L1–L4 contain no Little Buddy at all (Mom and Dad meet, marry, prepare the nursery),
so the Adult family is the **first** character asset the game needs chronologically, even though
the Infant is the first one we will actually build.

**A variant is not a new model.** A variant is the same mesh and the same skeleton with
(a) a different uniform root scale, (b) different **bone rest positions** baked in Blender, and
(c) a different clothing set. Because every animation clip is authored **rotation-only** (§5.2),
all variants of all families replay the identical clip data.

### Why five and not more

Children read age almost entirely from **head-to-body ratio** and **limb chubbiness**. Between
"primary-school child" and "older child" that ratio moves by about half a head — visible as a
scale-and-proportion variant, invisible as a whole new commissioned model. Between "baby" and
"toddler" it moves by a full head *and* the character changes from non-ambulatory to walking,
which changes the silhouette, the stance and the entire locomotion requirement. Families split
where the **rig usage** changes, not where the story labels change.

### Judgement calls made here

- **Preschool folded into Toddler, not Child.** A 4-year-old still has a toddler's head ratio.
  Ch4 gets the `preschool` variant (taller, slightly smaller head) plus a backpack and school
  clothes, which is what actually sells "first day of school".
- **Older child folded into Child, not Teen.** Ch6 is "Growing Skills" — cooking, helping,
  hobbies. Those are Child-family animations. Ch7 is where the silhouette must change.
- **Young-adult Little Buddy shares the Adult family with the parents.** Ch9 is ten small career
  activities. Commissioning a dedicated young-adult hero for ~30 minutes of endgame content is
  not defensible; a third Adult variant with career clothing is.
- **Adults are stylised to 1 : 6.5 head-to-height, not the real 1 : 7.5.** Realistic adult
  proportions next to a 1 : 3.5 infant would make the adults read as a different game. Keeping
  adults slightly chibi holds the style together. This is a deliberate art choice, restated in
  `ART_BIBLE_DRAFT.md`.

---

## 2. Proportions and scale

All heights are in **Godot units = metres**, standing, feet at `y = 0`.

| Family | Variant | Height | Head : height | Torso : legs | Silhouette note |
|---|---|---|---|---|---|
| Infant | `infant` | **0.78 m** | **1 : 3.5** | 1 : 0.9 | no neck, no waist, barrel torso, chubby stub limbs, non-ambulatory |
| Toddler | `toddler` | **0.88 m** | 1 : 4.2 | 1 : 1.1 | round belly still present, wide stable stance, hands still mitten-soft |
| Toddler | `preschool` | **1.00 m** | 1 : 4.6 | 1 : 1.2 | belly reduced, first hint of a neck |
| Child | `child` | **1.25 m** | 1 : 5.2 | 1 : 1.4 | clear neck, defined shoulders, fingers still fused into a soft mitt |
| Child | `olderChild` | **1.38 m** | 1 : 5.6 | 1 : 1.5 | leggier; same mesh, longer thigh/shin rests |
| Teen | `teen` | **1.55 m** | 1 : 6.0 | 1 : 1.6 | slimmer limbs, still soft joints, no musculature |
| Adult | `mom` | **1.65 m** | 1 : 6.5 | 1 : 1.7 | soft rounded shoulders, gentle silhouette |
| Adult | `dad` | **1.78 m** | 1 : 6.5 | 1 : 1.7 | broader shoulders, same mesh topology |
| Adult | `youngAdult` | **1.70 m** | 1 : 6.3 | 1 : 1.65 | Little Buddy grown up; reads as family resemblance, not as a parent |

**Anti-goals for every family** (extending `CUSTOM_BABY_SPEC.md` §1): no realistic anatomy, no
visible teeth, no sharp features, no thin stick limbs, no musculature, nothing that can read as
frightened, angry or distressed in any pose or any blend-shape combination.

**The 0.78 m infant height is load-bearing** — it is what the existing nursery camera
(`y = 0.95`, `z = 2.075`, pitch −18.5°, FOV 50°) and the keep-out volume
`x ∈ [−0.8, 0.8] · y ∈ [0, 1.0] · z ∈ [−0.4, 0.8]` were framed around. Do not change it without
re-framing `baby_room.tscn` and updating `game/tests/cases/test_nursery_contract.gd`.

**Camera implication (flagged, not solved here).** The current nursery camera cannot frame a
1.78 m Dad — he would be cut off at the chest. Rooms that contain adults need their own camera
rig. That belongs in the level/architecture design doc, but the character heights above are the
input it needs.

---

## 3. The shared rig — `LB_Rig_v1`

**One skeleton. Every family. No exceptions.** This is the single decision that makes the
animation library shareable and makes model replacement cheap.

### 3.1 Bone list (20 bones, hard cap 24)

```
root
└─ hips
   ├─ spine_01
   │  └─ spine_02
   │     ├─ neck
   │     │  └─ head
   │     ├─ clavicle_L ─ upperarm_L ─ lowerarm_L ─ hand_L
   │     └─ clavicle_R ─ upperarm_R ─ lowerarm_R ─ hand_R
   ├─ thigh_L ─ shin_L ─ foot_L
   └─ thigh_R ─ shin_R ─ foot_R
```

- **No finger bones, no toe bones, no facial bones, no twist bones, no IK, no constraints, no
  drivers.** Held objects attach to `HandMarker_*` (§4). Facial expression is blend shapes (§6).
- Bone names are **exact and case-sensitive**. A delivered model with `Head` instead of `head`
  is a rejected delivery.
- Max **4 skin influences per vertex**.
- The Infant uses all 20 bones even though it never walks. Carrying the four unused leg-chain
  bones costs nothing and means the Infant can be animated with any clip from the shared library
  without a retarget step.

### 3.2 Orientation, pivot, units — non-negotiable

| Property | Value |
|---|---|
| Up axis | **+Y** |
| Forward axis | **−Z** in glTF terms; the character **faces +Z toward the camera** at identity rotation |
| Origin / pivot | **floor between the feet**, `y = 0`, `x = 0`, `z = 0` |
| Units | **1 unit = 1 metre**, scale applied, **no residual node scale anywhere** |
| Rest pose | neutral **A-pose**, arms ~40° from the body, palms facing inward, feet flat and slightly apart |
| Format | single `.glb` (binary glTF 2.0), animations and textures embedded |
| Engine acceptance | imports into **Godot 4.7.2** with **zero errors**, working `AnimationPlayer`, **arms deform correctly** |

That last line is an acceptance criterion, not a nicety. Kenney Mini Characters was rejected
precisely because its arms import broken in Godot 4.7.2 before any modification. **Test-import
before delivering.**

### 3.3 Why 20 bones and not the 8–12 in CUSTOM_BABY_SPEC

`CUSTOM_BABY_SPEC.md` §3 specifies "8–12 bones maximum, no fingers, no toes". That is correct
for an infant that only ever plays short in-place reactions, which is all the current build does.

It is **not** sufficient for the game the Bible describes. Bible §12 requires walking, sitting,
carrying and a nine-state movement controller, and **none of that exists yet** — so the rig must
support it from day one or every family gets re-rigged later. A 12-bone rig with one arm joint
cannot play a convincing `pickUp` or `carry`, and a rig without `clavicle_*` cannot lift a shoulder
for `wave` or `reachUp`.

20 bones is still trivially cheap on mobile. **This document raises the infant rig to
`LB_Rig_v1`.** See §10 for the full amendment list.

---

## 4. Interaction sockets

Sockets are how missions address the body without knowing anything about the mesh. **Every family
ships every socket**, with the same names, even where a socket is unused in that family's chapters.

| Socket node | Parent bone | Placement | Used for | Must move with animation |
|---|---|---|---|---|
| `MouthMarker` | `head` | at the mouth surface, offset forward (+Z) | food/drink delivery; `MouthDropZone` target | **yes** |
| `FaceMarker` | `head` | ~2 cm in front of the face centre | screen-space anchor for the instruction/speech bubble and for camera look-at | **yes** |
| `HeadMarker` | `head` | crown, at the top of the skull surface | hats, caps, graduation cap, hair accessories | **yes** |
| `HugMarker` | `spine_02` | centre of the chest, offset forward (+Z) | hug/teddy delivery; `HugDropZone` target | **yes** |
| `HandMarker_L` | `hand_L` | palm centre, palm normal = local +Y | held object attachment | **yes** |
| `HandMarker_R` | `hand_R` | palm centre, palm normal = local +Y | held object attachment (default carry hand) | **yes** |
| `BackMarker` | `spine_02` | mid-back, offset backward (−Z) | backpack (Ch4 L16, Ch5 L21–22) | **yes** |
| `SitMarker` | `hips` | the point the character's seat contacts a chair | sit alignment: the mission places the character so `SitMarker` lands on the furniture's `SeatAnchor` | **yes** |

**Critical, and already enforced by the test suite:** these must be **real child nodes parented
into the animated skeleton**, not baked constants.
`game/tests/cases/test_baby_view_3d.gd::_test_markers_follow_the_body` asserts that moving the
animated body moves `MouthMarker` and `HugMarker` by the same delta. A model that hardcodes them
fails the build. That test should be extended to cover all eight sockets when the rig lands.

**Current infant values for reference** (from `game/scripts/baby/baby_view_3d.gd`):
`MouthMarker ≈ (0, 0.43, 0.18)`, `HugMarker ≈ (0, 0.27, 0.20)` in character-local space.

**Socket accessor contract:** `character.get_socket("MouthMarker") -> Node3D`. Missions read
`.global_position` / `.global_transform` from the returned node. If a socket is missing the
accessor returns the `root` node rather than `null`, so a half-finished model degrades to
"object delivered to the character's feet" instead of crashing.

---

## 5. Animation library

### 5.1 Semantic actions — the only names missions may use

Missions call **`character.play_action("drink")`**. Missions never reference a clip filename,
an `AnimationPlayer` track, a state enum, or a family name. This is the whole replacement
contract in one sentence.

> **Naming note / Bible inconsistency.** Bible §13 writes `character.playAction("drink")`.
> `CLAUDE.md` mandates Godot snake_case for GDScript. The method is therefore
> **`play_action()`**; the **action id string stays camelCase** (`brushTeeth`, `shakeHead`),
> matching the camelCase JSON key convention the content files already use. The glTF clip name
> must equal the action id **exactly**.

| Action id | Loop | Length | Infant | Toddler | Child | Teen | Adult | Fallback chain |
|---|---|---|---|---|---|---|---|---|
| `idle` | yes | 2–3 s | ✅ | ✅ | ✅ | ✅ | ✅ | *(terminal)* |
| `walk` | yes | 1.0 s cycle | ➖ | ✅ | ✅ | ✅ | ✅ | → `crawl` (Infant) → `idle` |
| `run` | yes | 0.7 s cycle | ➖ | ➖ | ✅ | ✅ | ✅ | → `walk` |
| `crawl` | yes | 1.2 s cycle | ✅ | ➖ | ➖ | ➖ | ➖ | → `walk` |
| `sit` | one-shot | 1.0 s | ➖ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `sitIdle` | yes | 2–3 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `standUp` | one-shot | 1.0 s | ➖ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `wave` | one-shot | 1.5 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `happy` → `idle` |
| `point` | one-shot | 1.0 s | ➖ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `clap` | one-shot | 1.5 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `happy` → `idle` |
| `nod` | one-shot | 0.8 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `shakeHead` | one-shot | 0.8 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `pickUp` | one-shot | 1.0 s | ➖ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `hold` | yes | 2 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `carry` | yes | 1.0 s cycle | ➖ | ✅ | ✅ | ✅ | ✅ | → `walk` |
| `give` | one-shot | 1.0 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `hold` → `idle` |
| `eat` | one-shot | 1.5 s | ➖ | ✅ | ✅ | ✅ | ✅ | → `drink` → `idle` |
| `drink` | one-shot | 2 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `brushTeeth` | yes | 2 s | ➖ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `washHands` | yes | 2 s | ➖ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `sleep` | yes | 3 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `sleepy` → `idle` |
| `wake` | one-shot | 1.5 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `hug` | one-shot | 2 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `happy` | yes | 1.5 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `excited` | yes | 1.5 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `happy` |
| `sleepy` | yes | 2–3 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `hungry` | yes | 2 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `surprised` | one-shot | 1.0 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `idle` |
| `celebrate` | one-shot | 2 s | ✅ | ✅ | ✅ | ✅ | ✅ | → `excited` → `happy` → `idle` |
| `holdBaby` | yes | 2–3 s | ➖ | ➖ | ➖ | ➖ | ✅ (parents) | → `hold` |

✅ required · ➖ not authored; resolves via the fallback chain

**30 actions. 27 of them are shared by every family.** Infant-only: `crawl`. Adult-only:
`holdBaby`. Child-and-up only: `run`.

### 5.2 Why the whole library is shareable

**Rule: animation curves are rotation-only.** The only permitted translation tracks are on
`root` (root motion, which we do not use — the `CharacterBody3D` owns position) and a **vertical**
`hips` bob. No bone may carry X/Z translation or scale keys.

Because every family uses `LB_Rig_v1` with identical bone *names* and *hierarchy*, and clips carry
only rotations, a clip authored once on a canonical rig replays correctly on a body with
completely different bone **rest** positions. A 0.78 m infant and a 1.78 m dad play the exact same
`wave.glb` curve data.

**Two things do not transfer automatically and must be handled per family:**

| Problem | Solution |
|---|---|
| Stride length scales with leg length, so a shared `walk` cycle desyncs from ground speed and the feet skate | Each family `.glb` carries a custom property `strideLength` (metres per cycle). The controller sets `playback_speed = moveSpeed / strideLength`. Measured, not eyeballed. |
| Sitting height differs per family | `SitMarker` is per-family by construction (it hangs off `hips`); the shared `sit` clip is unchanged. |
| Reach distance for `drink`/`eat` differs | The held object is parented to `HandMarker_R` and the mouth target is `MouthMarker` — both scale with the body, so reach is automatically correct. |

### 5.3 Delivery of animation

Animations ship as a **single shared `.glb` library** (`lb_actions_v1.glb`) containing the rig and
all 30 clips, **not** baked into each character file. Each character `.glb` ships mesh + skeleton
+ blend shapes only. Godot imports the library once and the `AnimationTree`/`AnimationPlayer`
retargets it onto whichever family is instanced.

Judgement call: this costs one extra import step but means adding a 31st action is one file, not
nine. If the pipeline turns out to fight this, the fallback is to embed clips per family and
accept the duplication — but only after it is actually tried.

---

## 6. Face, blend shapes and expression

Facial expression is **blend shapes, never bones**. Far cheaper, far safer against uncanny
results, and it survives a mesh replacement because the names are contractual.

| Blend shape | Range | Present on |
|---|---|---|
| `mouthSmile` | 0–1 | all families |
| `mouthOpen` | 0–1 | all families |
| `mouthSad` | 0–1 | all families |
| `eyesClosed` | 0–1 | all families |
| `browsSad` | 0–1 | all families |
| `browsSurprised` | 0–1 | all families |
| `cheeksBlush` | 0–1 | all families (blush mesh/decal opacity) |
| `bellyRound` | 0–1 | **Adult family only** — Mom's pregnancy, Ch1 L3–L5 |

Cap: **8 blend shapes**. `CUSTOM_BABY_SPEC.md` §4 lists four (`mouth_smile`, `mouth_open`,
`eyes_closed`, `brows_sad`); this list extends it and switches to camelCase for consistency with
the action ids — see §10.

**Blink stays a `_process` timer, not an animation track.** The current implementation made this
call deliberately (a value track fighting for the eye transform across five clips is a
silent-breakage machine) and it was right. A commissioned model must therefore expose
`eyesClosed` as a blend shape the controller can drive directly, independently of the
`AnimationPlayer`.

**Pregnancy presentation** is `bellyRound` on `mom` plus a maternity-dress clothing mesh. No new
model, no medical detail, consistent with Bible §3.

---

## 7. Clothing

| Family | Approach |
|---|---|
| **Infant** | Onesie and nappy are **baked into the body mesh**. Colour is a material slot (one `albedo_color` swap), not a mesh swap. Babies do not need a wardrobe and Ch2 has no dressing level. |
| **Toddler → Adult** | Clothing is **separate meshes skinned to `LB_Rig_v1`**, instanced as siblings of the body mesh and attached to the same skeleton. |

**Clothing slots** (Toddler and up): `top`, `bottom`, `shoes`, `hat`, `accessory`.
`hat` and `accessory` may alternatively attach rigidly to `HeadMarker` / `HandMarker_*` when they
do not deform.

**Rules that stop a clothing swap from looking broken:**

1. The body mesh always wears a **base layer** — a plain vest and shorts modelled into the body —
   so an unequipped `top` or `bottom` slot never exposes a bare torso.
2. Clothing shells are offset **3–5 mm** outward along the vertex normal from the body surface.
   No z-fighting, no hidden-geometry culling needed, no per-outfit body variants.
3. Clothing shares the family's single texture atlas. A new outfit is new UV space, not a new
   material and not a new draw call if it can be atlased.
4. **Shoes are skinned to `foot_L`/`foot_R`**, not socketed, so they bend with the walk cycle.

This directly serves Bible §18 `unlockedOutfits` and Ch3 L13 "Getting Dressed" / Ch4 L16
"My First Day" without a per-outfit character model.

> **Known open item, not solved here:** `shoes` is already flagged in
> `docs/ART_UPGRADE_REPORT.md` as the weakest 3D object in the build ("two brown pebbles" when
> seen cold). Worn shoes on a rigged foot are a different and easier problem than a standalone
> shoe prop, but the standalone prop still needs a fix.

---

## 8. Budgets

Grounded in measured numbers, not guesses. **All 18 shipped Kenney GLBs together total 2,996
triangles**; the entire current scene is ~14,000 triangles and 158 draw calls.

| Asset class | Triangles | Textures | Materials | Bones | Blend shapes | File size |
|---|---|---|---|---|---|---|
| **Infant** (hero, always framed large) | **≤ 3,000** (2,500 target) | 1 × 512² | 1–2 | 20 | ≤ 8 | ≤ 500 KB |
| **Toddler / Child / Teen** | **≤ 3,500** | 1 × 512² | 1–2 | 20 | ≤ 8 | ≤ 600 KB |
| **Adult** (Mom / Dad / youngAdult) | **≤ 4,000** | 1 × 512² *(1024² only if UV space genuinely demands it)* | 1–2 | 20 | ≤ 8 | ≤ 700 KB |
| **Clothing item** | 150–600 | shares the family atlas | shares the family material | — | — | ≤ 80 KB |
| **Hair mesh** (Toddler+) | 200–800 | shares the family atlas | shares the family material | — | — | ≤ 80 KB |
| **Animation library** `lb_actions_v1.glb` | n/a (no mesh) | none | none | 20 | — | ≤ 400 KB |

**Per-family total on screen** including clothing and hair: **≤ 5,000 triangles**.
**Worst realistic frame** (Little Buddy + Mom + Dad in the Ch1 wedding scene, plus a furnished
room): **≤ 30,000 triangles, ≤ 220 draw calls** — roughly double today's scene, still
comfortable.

Two materials per character is the intended split: one opaque body/clothing material, plus an
optional unshaded material for the eye highlight if flat catchlights are wanted. One is better.

### Disagreement with Bible §17

Bible §17 proposes **15k–35k triangles for the main character**. The whole current scene is 14k.
A single character at the top of that range would be **2.5× the entire game world**, and the
combined geometry of every third-party model we ship is **3.0k** — less than the *floor* of the
Bible's range. The number appears to have been carried in from a general mobile-3D rule of thumb
rather than derived from this game.

**Recommendation: replace Bible §17's character budgets with the table above.** Full
budget reconciliation, including props and environment, is in `docs/ART_BIBLE_DRAFT.md` §13.

### LOD

**No LODs.** At most 3–4 characters are on screen, each under 5,000 triangles. The measured
bottleneck signal in this project is draw calls (158), not vertex throughput. Godot 4.7's
automatic import LOD would add mesh memory and introduce popping on a screen a small child is
staring at from 30 cm away, in exchange for saving vertices we are not short of. Revisit only if
a device profile says otherwise — see `ART_BIBLE_DRAFT.md` §13.4 for the full argument and the
alternatives we are using instead.

---

## 9. The replacement contract

**Design goal, stated plainly: a commissioned or generated model must replace a temporary one
without changing any mission logic.** Everything below exists to make that literally true.

### 9.1 The code-facing interface

```gdscript
class_name LittleBuddyCharacter extends Node3D

# --- Actions: the ONLY way a mission animates a character ---
func play_action(action_id: String, opts: Dictionary = {}) -> bool
func has_action(action_id: String) -> bool
func get_current_action() -> String
signal action_finished(action_id: String)

# --- Sockets: the ONLY way a mission addresses a body part ---
func get_socket(socket_name: String) -> Node3D

# --- Identity / metrics ---
func get_family() -> String      # "infant"|"toddler"|"child"|"teen"|"adult"
func get_variant() -> String     # e.g. "preschool", "mom"
func get_height() -> float       # metres, for camera framing and UI anchoring

# --- Expression ---
func set_expression(name: String, weight: float) -> void   # blend shapes, §6

# --- Clothing ---
func set_clothing(slot: String, item_id: String) -> void   # "" clears the slot
```

**No mission, level or activity script may:**
- name an animation clip, an `AnimationPlayer`, an `AnimationTree` state, or a `.glb` file;
- read or write a bone by name or index;
- hardcode a socket position, height or offset;
- branch on which family or variant is loaded, except for authored story reasons.

### 9.2 The guarantees that make replacement safe

1. **`play_action` never fails silently and never stalls.** Unknown or unauthored action ids walk
   the fallback chain in §5.1 and, whatever they land on, `action_finished` fires after the
   action's nominal duration — even if no clip played at all. A mission scripted against a
   finished model therefore still completes against a stub.
2. **`get_socket` never returns `null`.** A missing socket returns `root`.
3. **Metrics are read, never assumed.** Camera framing, speech-bubble anchoring and drop-zone
   placement all derive from `get_height()` and `get_socket()`, so a taller replacement reframes
   itself.
4. **Scale, orientation and pivot are fixed by §3.2**, so a replacement lands at the right size,
   facing the right way, with its feet on the floor, at identity transform.
5. **Names are contractual**: 20 bone names, 8 socket names, 8 blend-shape names, 30 action ids.
   A model that matches those names is a drop-in. A model that does not is a rejected delivery.
6. **A test enforces it.** Extend the existing `test_baby_view_3d.gd` into a family-agnostic
   `test_character_contract.gd` that loads every shipped character `.glb` and asserts: all bones
   present and correctly named; all 8 sockets present, parented into the skeleton, and **moving
   under animation**; all required actions resolve; every animation track resolves to a real node;
   height within ±2 cm of the declared value; pivot at `y = 0`; triangle count within budget.

### 9.3 Migration from today's procedural baby

The shipped `BabyView3D` exposes `set_view_state(idle|hungry|drinking|happy|hugging)`,
`get_mouth_position()`, `get_hug_position()`. The new interface is a superset, so:

| Old | New |
|---|---|
| `set_view_state("drinking")` | `play_action("drink")` |
| `set_view_state("hugging")` | `play_action("hug")` |
| `set_view_state("idle"/"hungry"/"happy")` | `play_action("idle"/"hungry"/"happy")` |
| `get_mouth_position()` | `get_socket("MouthMarker").global_position` |
| `get_hug_position()` | `get_socket("HugMarker").global_position` |

Keep a **state-name alias table** (`"drinking" → "drink"`, `"hugging" → "hug"`) inside the
character controller so the existing feeding flow keeps working unchanged during the transition.
Per Bible §21: do not delete the procedural baby until the replacement is validated on a device.

### 9.4 Build order

The Infant is family #1 to build, because it is the only family the current game needs and it is
already specced and quoted (`CUSTOM_BABY_SPEC.md`). But it must be commissioned **on
`LB_Rig_v1`** — re-rigging it later costs more than building it right once.

| Order | Family | Trigger |
|---|---|---|
| 1 | **Infant** | now — unblocks Ch2 and the vertical slice |
| 2 | **Toddler** (`toddler` variant) | when Ch3 / the "A Day With Little Buddy" slice needs walking |
| 3 | **Adult** (`mom`, `dad`) | when Ch1 is built |
| 4 | Toddler `preschool` variant | Ch4 |
| 5 | **Child** (both variants) | Ch5 |
| 6 | **Teen** | Ch7 |
| 7 | Adult `youngAdult` variant | Ch9 |

---

## 10. Amendments to `CUSTOM_BABY_SPEC.md`

`CUSTOM_BABY_SPEC.md` remains the authoritative commission brief for the Infant. This document
changes exactly five things in it. **If the spec has already been sent to an artist, send these
as a diff, not a rewrite.**

| § | Was | Now | Why |
|---|---|---|---|
| §3 Rig | 8–12 bones, 1–2 arm joints, no clavicles | **`LB_Rig_v1`, 20 bones** (§3.1 above) | the shared animation library and all future walking/carrying depend on one skeleton; re-rigging later is more expensive than over-rigging now |
| §4 Animations | 9 clips, lowercase names (`drinking`, `hugging`) | **30 semantic action ids**, camelCase, of which the Infant authors 22 (§5.1); `drinking`→`drink`, `hugging`→`hug` | missions address semantic actions, not states; the fallback chain covers the 8 the Infant does not author |
| §4 Blend shapes | 4, snake_case (`mouth_smile`) | **8, camelCase** (`mouthSmile` …) (§6) | consistency with action ids and the camelCase JSON convention; `mouthSad` / `browsSurprised` / `cheeksBlush` carry most of the remaining charm |
| §8 Sockets | 4 (`MouthMarker`, `HugMarker`, `HandMarker_L/R`) | **8** — adds `FaceMarker`, `HeadMarker`, `BackMarker`, `SitMarker` (§4) | speech-bubble anchoring, hats, backpacks and chair alignment are all already in the Bible's level list |
| §6 Budget | ≤ 3,000 tris, ≤ 12 bones | ≤ 3,000 tris (unchanged), **≤ 20 bones** | only the bone cap moves |

Unchanged and still correct: 0.78 m height, 1 : 3.5 head ratio, origin at the floor, faces +Z,
1 unit = 1 m, ≤ 3,000 triangles, ≤ 3 materials, ≤ 1 × 512² texture, GLB + editable source,
Godot 4.7.2 zero-error import with working arms, full copyright assignment.

---

## 11. Flagged inconsistencies and open questions

| # | Issue | Where | Suggested resolution |
|---|---|---|---|
| 1 | **Bible §17 character budget (15k–35k tris) is 5–12× too large** — the entire scene is 14k and all 18 shipped models total 3.0k | Bible §17 | adopt §8 above; see `ART_BIBLE_DRAFT.md` §13 |
| 2 | **`playAction` vs GDScript snake_case** | Bible §13 vs `CLAUDE.md` | method `play_action()`, action id strings stay camelCase (§5.1) |
| 3 | **Bible §2.1 lists 10 life stages but also says "use age-stage model families" and lists 5** — the two lists are not reconciled | Bible §2.1 | §1 above is the reconciliation: 5 families, 9 variants, explicit chapter mapping |
| 4 | **Ch4 milestone says "School-age character model"** but Ch3's milestone already said "Preschool unlocked" — implying a model change at both boundaries | Bible §8, Ch3/Ch4 | model change happens **once**, at the Ch4→Ch5 boundary. Ch4 is a Toddler-family *variant*, not a new family. |
| 5 | **The nursery camera cannot frame an adult.** Camera is fixed at `y = 0.95`, FOV 50°, framed for a 0.78 m subject | `baby_room.tscn` vs Ch1 (Mom & Dad) | rooms containing adults need their own camera rig — belongs to the level/architecture doc; heights in §2 are its input |
| 6 | **No character movement system exists at all** — Bible §12's nine-state controller, `NavigationAgent3D`, tap-to-walk and drag-to-walk are all unwritten | Bible §12 | scoped to the architecture doc; §3 and §5 here are its prerequisite |
| 7 | **Bible §16 says "no fused arms/legs" and "visible hands" for generated models** — Meshy output routinely violates both | Bible §16 | treated as a hard acceptance criterion in `ART_BIBLE_DRAFT.md` §14, plus the automated contract test in §9.2 |
| 8 | **Ch9 has 10 career themes** each needing clothing/props. At one outfit set per career this is the largest single art ask in the game, for the shortest content | Bible §8 Ch9 | flagged as a scope risk. Suggest 4 careers at launch with the rest behind Free Life mode — a story/level decision, not an art one. |

**Deliberately left to the parallel design docs:** chapter/level beats and star conditions
(story/level doc); which object each activity uses and the English vocabulary attached to it
(interaction/vocabulary doc); the `CharacterBody3D` + `NavigationAgent3D` controller, the
`AnimationTree` state machine, scene composition and the save-schema extension for
`unlockedOutfits` (architecture doc).
