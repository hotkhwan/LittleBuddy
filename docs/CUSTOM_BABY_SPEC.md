# Custom Baby Character — Commission Spec

**Status:** the shipped baby is procedural (built from Godot primitives in
`game/scripts/baby/baby_view_3d.gd`). It is a deliberate **temporary fallback**, not the
target. This document specifies the model to commission so an artist can quote and deliver
against it without further back-and-forth.

## Why commission rather than source

No suitable baby or toddler model exists under a permissive licence. Searched exhaustively:
Poly Pizza (`baby`, `toddler`, `child`), OpenGameArt, itch.io CC0 character listings, Kenney's
~50-pack 3D catalogue, Quaternius' ~90 packs. Findings:

- Poly Pizza `toddler` → 2 results, neither usable (a nutcracker figure; an avatar blob).
- Poly Pizza `baby` → a baby *bottle*, a baby *chick*, and one unusable joke model.
- OpenGameArt → adult humanoid base meshes only.
- Kenney → no baby. **Mini Characters was tried and rejected on two independent grounds:**
  (a) its arms **import broken in Godot 4.7.2** — meshes detach and splay across all five
  animations tested, *before* any modification, and `skins/use_named_skins=false` changes
  nothing; (b) it is a chibi **adult** with clothing baked into the shared atlas, so
  reproportioning yields a bobblehead grown-up, not an infant.

A commissioned original also means we **own it outright**, which for a commercial children's
product is worth paying for — no licence surface on the character the whole game is about.

---

## 1. Proportions

The single most important requirement. Babies read as babies because of head-to-body ratio.

| Property | Target |
|---|---|
| Total height | **0.78 m** in Godot units (matches current rig and camera framing) |
| Head : total height | **≈ 1 : 3.5** (infant-like; an adult is ~1:7.5) |
| Head shape | near-spherical, slightly wider than tall, soft jaw — **no chin definition** |
| Eyes | large, set **low** on the face (below the vertical midline) and wide apart |
| Torso | short, rounded, gently barrel-shaped; no waist |
| Limbs | short and chubby, soft rounded ends; visible hands and feet |
| Neck | essentially none — head sits directly on the shoulders |
| Stance | stable, feet slightly apart, arms a little out from the body |

**Anti-goals:** no realistic anatomy, no uncanny-valley proportions, no visible teeth, no sharp
features, no thin limbs, nothing that could read as frightened or distressed.

## 2. Style

- Cute, warm, safe, playful — picture-book / soft-toy, **not** realistic.
- Soft rounded silhouettes, readable at small size on a phone.
- Pastel palette matching the nursery: warm cream `#FFF4E0`, dusty blue, soft pink `#F8BFD1`,
  mint `#9EDCC3`, peach, lavender.
- Face: large eyes with a highlight, soft eyebrows, rosy cheek blush, a simple mouth that can
  change shape. Optional hair tuft.
- Must sit visually alongside **Kenney Food Kit / Cube Pets** props (flat-shaded, rounded,
  low-poly). See `docs/ASSET_MANIFEST.md`.
- Gender-neutral.

## 3. Rig

Deliberately minimal — the game only ever plays short, gentle reactions.

- **8–12 bones maximum**: `root`, `hips`, `spine`, `head`, `arm_L/R` (1–2 joints each),
  `leg_L/R` (1 joint each). No fingers, no toes, no facial bones.
- **Y-up, −Z forward** (Godot/glTF convention). Character faces **+Z toward the camera** when
  placed at the origin with identity rotation.
- **Origin at the floor between the feet**, i.e. pivot at `y = 0`, feet resting on `y = 0`.
- Skin weights: max **4 influences per vertex**, smooth around shoulders and hips.
- **No IK, no constraints, no drivers** — baked FK animation only.
- Mouth and eye expression via **blend shapes / morph targets** (see §4) rather than bones.

## 4. Required animations

All **looping** unless noted, gentle, short, and never startling.

| Clip | Length | Description |
|---|---|---|
| `idle` | 2–3 s | soft breathing bob, occasional weight shift |
| `hungry` | 2 s | gentle side-to-side rock, slightly downturned mouth — **sad, never distressed** |
| `drinking` | 2 s | head tilts back a little, contented |
| `happy` | 1.5 s | light bounce, arms lift slightly |
| `hugging` | 2 s | both arms come forward and in toward the chest, small forward lean |
| `clap` | 1.5 s | hands meet in front |
| `wave` | 1.5 s | one arm waves |
| `sleepy` | 2–3 s | slow sway, eyes closing |
| `blink` | 0.3 s, one-shot | additive if possible, so it can play over any state |

**Blend shapes** (0–1): `mouth_smile`, `mouth_open`, `eyes_closed`, `brows_sad`.
These carry most of the charm and are far cheaper than facial bones.

Clip names must be **exactly** as above — the code maps state strings to them.

## 5. Materials

- **One material** for the whole character if possible; **three maximum**.
- Flat/stylised `StandardMaterial3D`-compatible PBR: albedo-driven, `roughness ≈ 1.0`,
  `metallic = 0`.
- **A single small texture atlas (≤ 512×512), or vertex colours / plain albedo with no texture
  at all.** The Kenney packs we ship use one 512×512 colormap; matching that is ideal.
- No normal maps, no emission, no transparency, no alpha blending, no subsurface scattering.

## 6. Performance budget

Mobile (iPhone/iPad, Godot **Mobile** renderer), sharing the frame with a nursery and props.

| Metric | Budget |
|---|---|
| Triangles | **≤ 3,000** (2,000 preferred) |
| Materials | 1–3 |
| Textures | ≤ 1 × 512×512 |
| Bones | ≤ 12 |
| Blend shapes | ≤ 4 |
| File size | ≤ 500 KB |

For reference the whole current scene is ~14,000 tris / 158 draw calls.

## 7. Delivery format

- **`.glb`** (binary glTF 2.0), single file, **animations embedded**, textures embedded.
- Also deliver the **editable source** (`.blend` preferred) — we need to be able to tweak it.
- Y-up, −Z forward, **1 unit = 1 metre**, scale applied (no residual node scale).
- Transforms applied/frozen; no leftover parent transforms.
- Must import into **Godot 4.7.2** with zero errors and a working `AnimationPlayer`.
  *This is an acceptance criterion* — Kenney Mini Characters was rejected precisely because its
  arms import broken in this exact engine version, so **please test-import before delivering.**

## 8. Interaction sockets / anchors

The game positions its drop zones from the character every frame. These **must exist as named
empty nodes** parented into the skeleton so they move with the animation:

| Node name | Parent | Position | Used for |
|---|---|---|---|
| `MouthMarker` | head | at the mouth surface, slightly forward (+Z) | `MouthDropZone` — where food/drink is delivered. Currently ≈ `(0, 0.43, 0.18)` |
| `HugMarker` | spine/chest | centre of the chest, slightly forward (+Z) | `HugDropZone` — where the teddy is delivered. Currently ≈ `(0, 0.27, 0.20)` |
| `HandMarker_L` / `HandMarker_R` | each hand | palm centre | future held-object attachment |

**Critical:** these must be *real child nodes of the animated skeleton*, not static values.
Our test suite asserts the markers **move when the body animates** — a baked constant fails it.

The code contract the model must satisfy (`game/scripts/baby/baby_view_3d.gd`):

```gdscript
class_name BabyView3D extends Node3D
func set_view_state(state: String) -> void   # idle|hungry|drinking|happy|hugging
func get_view_state_name() -> String
func get_mouth_position() -> Vector3   # global, derived from MouthMarker
func get_hug_position() -> Vector3     # global, derived from HugMarker
```

The character must also stay inside the nursery play volume:
`x ∈ [−0.8, 0.8]`, `y ∈ [0, 1.0]`, `z ∈ [−0.4, 0.8]` (enforced by
`game/tests/cases/test_nursery_contract.gd` and `test_baby_view_3d.gd`).

## 9. Licence requirement for the commission

**Full assignment of copyright, or an exclusive perpetual worldwide commercial licence with
the right to modify and sublicense as part of the app.** No attribution obligation. Get it in
writing before payment. Do not accept a stock-licence delivery — the whole point is to own the
character the product is built around.

## 10. Acceptance checklist

- [ ] Imports into Godot 4.7.2 with zero errors; all 9 clips play; **arms deform correctly**
- [ ] ≤ 3,000 tris, ≤ 3 materials, ≤ 1× 512² texture, ≤ 12 bones
- [ ] 0.78 m tall, origin at the floor, faces +Z, 1 unit = 1 m
- [ ] `MouthMarker` / `HugMarker` present, parented into the skeleton, and **move with animation**
- [ ] 4 blend shapes present and named exactly
- [ ] Reads as a **baby**, not a small adult, at phone size
- [ ] Sits visually alongside the Kenney props without looking foreign
- [ ] Nothing frightening or uncanny in any state
- [ ] Copyright assigned / exclusive licence in writing
