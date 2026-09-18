# Runtime Little Buddy — local production-candidate build

**Date:** 2026-09-19 · **Meshy credits spent: 0** · No Meshy endpoint was called.
**Recommendation: B — READY WITH MINOR VISUAL POLISH, but BLOCKED on the triangle budget.**
See §9; the honest short version is that the *character* is ready and the *budget* is not.

Source (never modified): `game/assets_source/meshy/littleBuddy/babyStanding_rigged_v01.glb`
Runtime target: `game/assets/characters/littleBuddy/baby/babyLittleBuddy_v01.glb`
Rebuild with: `python3 tools/build_runtime_character.py`

---

## 1. Blender is NOT installed

Checked: no `blender` on `PATH`, no `/Applications/Blender.app`. Also absent: Pillow, numpy,
`gltf-transform`, `gltfpack`, `meshlab`, `assimp`. Available and used instead: Python 3 stdlib,
`sips`, Godot 4.7.2, Xcode.

To install it:

```sh
brew install --cask blender
# or download from https://www.blender.org/download/
```

**It was not required for anything except baking a normal map**, so the rest of the work went
ahead. The skin-weight repair was done directly on the GLB buffers in Python, which for this
defect is more precise than weight painting: the fix is "remove opposite-leg influence below the
hip, off the midline", which is an exact rule rather than a brush stroke.

What Blender *would* add, if you install it: a baked normal map from the 255k-triangle original
onto the 14.4k runtime mesh. See §5.

## 2. Skin weights — fixed

| Defect | Before | After |
|---|---|---|
| Leg vertices driven by the OPPOSITE leg (`\|x\|>0.03`, below hip) | **602 verts, worst 0.411** | **0 verts** |
| Shoulder bones influencing the head (above head base) | **2,983 verts, worst 0.425** | **0 verts** |
| Weight sums | 1.0000 | 1.0000 (unchanged) |
| Max influences per vertex | 4 | 4 (only removals, never additions) |
| Vertices that would have been zeroed | — | 0 (guarded, none occurred) |

687 vertices had cross-leg weight removed and 3,161 had shoulder-in-head removed, then each was
renormalised.

**What was deliberately NOT removed:** 36 vertices within a 0.015 midline deadband, between the
knees and the hip, still blend both legs. That is the diaper/crotch, where blending both legs is
anatomically correct. Stripping it would tear the diaper open when the legs part.

The skeleton hierarchy was not touched, so walk, run and the `RigProfile` all still apply — see §4.

## 3. Normals — the biggest visual win, and an accident

The rig export splits vertex normals at UV seams: 2,046 welded positions disagreed by a mean of
28.9° and up to 164.6°. That was invisible in the source file because the rigging step had baked a
**full-brightness emissive** (`emissiveFactor [1,1,1]`) pointing at the base colour, which renders
the character unlit and flat. Removing the emissive — which had to happen anyway, it made the baby
a glowing cut-out — revealed the faceting underneath.

Normals are now recomputed area-weighted across **welded positions**, which is what closes the
seams. 4,363 of 9,846 vertices changed.

This matters more here than it would on a dense mesh: at 14.4k triangles with no normal map,
vertex normals are the only thing carrying surface curvature. Before and after are in
`docs/shots/ab_hand_source.png` / `ab_hand_runtime.png`.

## 4. Animation compatibility

Preserved. The repair touched `WEIGHTS_0` and `NORMAL` only — never the skeleton, the joint order,
or the inverse bind matrices.

Clips ship as Meshy's **armature-only** exports (65 KB and 61 KB) rather than its full walk/run
GLBs, which each carry a redundant 3.9 MB copy of the mesh *with the unrepaired weights*. Their
skeleton is bone-for-bone identical, so the imported tracks resolve against the runtime model
unchanged. `_merge_clips()` copies them onto the model's own `AnimationPlayer` as `walk` and `run`.

One skeleton, not two. Verified in Godot: 24 bones, clips `["Armature|clip0|baselayer", "run",
"walk"]`, 22/24 bones rotating during playback.

## 5. Textures and the missing normal map

| | Remesh output | Rig output | Runtime |
|---|---|---|---|
| Base colour | 2048² | 2048² | **1024²** |
| Metallic-roughness | 4096² | *dropped by rigging* | none |
| Normal | *lost in remesh* | none | none |
| Materials | 1 | 1 | **1** |
| Emissive | no | **full-brightness white** | **removed** |
| `doubleSided` | true | true | **false** |

Material is now correct **at source** rather than relying on every consumer to override it:
emissive removed, `KHR_materials_specular` (2.0, non-physical) and `KHR_materials_ior` removed,
metallic 0.0, roughness 0.9 (art bible §7 band), single-sided.

**On the normal map.** It cannot be baked without Blender. The runtime model therefore uses
**smooth vertex normals and no normal texture**, which is the documented fallback. Judged by
looking (§8): the character reads cleanly and the faceting that prompted the concern is gone. A
baked normal map would still add fabric and facial micro-detail, but it is polish, not a blocker —
and art bible §7 bans normal maps on this project's characters anyway, so baking one would be
solving a problem the art direction has already ruled out of scope.

Nothing was invented that was not in the mesh. No Retexture call was made.

## 6. Scale, orientation, sockets

Normalised through the wrapper, not baked into gameplay logic:

- **0.78 m** exactly, measured; `characterHeight` and `placedHeight` both report 0.7800.
- **Feet on the floor** — `restingY` 0.00000.
- **Faces −Z at yaw 0**, the project's character convention (the GLB is authored +Z; the wrapper
  turns it). `CHAPTER_2_YAW_DEG` still names the yaw a Chapter 2 scene needs.

**A measurement bug this exposed.** `describe_budget().placedHeight` reported **0.0078 m** — 100×
too small. Meshy exports bones in centimetres under an `Armature` node carrying a 0.01 unit
conversion, and the mesh's vertex data is already in the metre space the bones resolve to. Walking
the node chain applied that 0.01 a second time. Fixed for skinned meshes, and
`runtime_character_validation` now cross-checks the reported height against a resolved socket
position, which is a source that cannot share the audit's arithmetic.

### Sockets — all six resolve

| Socket | Resolution | World position at 0.78 m |
|---|---|---|
| `head` | bone `Head` | (0.000, 0.386, −0.011) |
| `chest` | bone `Spine` (topmost — see the naming trap) | — |
| `leftHand` / `rightHand` | bones `LeftHand` / `RightHand` | (∓0.148, 0.256, −0.008) |
| `mouth` | `Marker3D` on `head` | (0.000, **0.452**, −0.161) |
| `hugTarget` | `Marker3D` on `chest` | (0.000, 0.413, −0.158) |
| `itemHoldLeft` / `itemHoldRight` | `Marker3D` on the hands | — |

Plus the legacy aliases `MouthMarker` → `mouth` and `HugMarker` → `hugTarget`, so
`CHARACTER_AGE_STAGES.md` §9.3's mapping works unchanged. `get_mouth_position()` and
`get_hug_position()` are now implemented — they were deliberately absent while there was no
skeleton to answer from.

**The units trap, twice.** Socket offsets are in **bone-local space, which is centimetres here**.
The first version expressed them in metres, so `mouth` resolved to within 1 mm of `head` — the
offset did nothing. The same trap then hid the feeding-bottle prop, which was parented into the
skeleton and rendered half a millimetre wide. Both are fixed; offsets are now computed as
`inverseBindMatrix[bone] × targetPointInMeshSpace`, and props are placed in world space.

**Finding the mouth needed the texture, not the geometry.** The lips are *painted*; the face is a
smooth surface, so every geometric heuristic finds the **nose** — the only thing that protrudes.
Deriving the socket from the frontmost vertex put the bottle on the baby's eyebrow.
`tools/find_face_sockets.py` decodes the base-colour PNG (pure stdlib — no Pillow) and profiles
face colour by height: hair is brown at 81–93%, skin is pale and near-neutral, and the lips are a
single saturated red band at 61–63% (r−g peaks at 108 against ~61 for skin). Rendering *that* put
the bottle on the nose, so it was lowered to 58% by measuring the render and confirming by eye —
the order `LB_RIG_V1.md` prescribes.

## 7. Locomotion — a real mismatch

Both clips are **in-place**; hips travel ≤0.043 over a full cycle. The movement controller owns
world translation, as required.

| Clip | Cycle | Stride @0.78 m | Ground speed at 1.0× playback |
|---|---|---|---|
| `walk` | 1.067 s | 0.216 m | **0.202 m/s** |
| `run` | 0.667 s | 0.276 m | **0.414 m/s** |

**`CharacterMovementController.WALK_SPEED` is 1.05 m/s.** Driving this character at that speed
against the walk clip at 1.0× would need **5.2× playback** to keep the feet planted — visibly
frantic. 1.05 m/s is adult walking pace and was tuned for the house character, not for a 0.78 m
infant.

Two ways to resolve, both the owner's call:
1. **Move the infant slower** — 0.20 m/s walk / 0.41 m/s run, clips at 1.0×. Correct-looking and
   the option this report recommends.
2. **Retime the clips** — e.g. walk at 1.5× with speed 0.30 m/s. Still slower than 1.05 m/s.

Not wired into the movement controller: doing so would change a shared, device-tuned constant for
every character, which is beyond a character-asset task. The numbers above are what the tuning
needs.

## 8. Evidence — rendered, then looked at

`docs/shots/runtime_baby_*.png`, 900×900, via `scenes/spike/runtime_character_shots.tscn`.

| Shot | What it shows |
|---|---|
| `standing` | Hair curl, eyes, blush, romper, diaper, booties. Clean silhouette. |
| `walk`, `run` | Natural mid-stride. Head intact, no squash during arm swing. |
| `knees_stride`, `..._front` | **Legs cleanly separated at maximum stride — no webbing.** |
| `face` | Smooth shading, clean eyes with highlights, no faceting. |
| `feeding` | Bottle on the mouth socket, nose visible above it. |
| `hug` | Teddy on the hug socket. |
| `ab_hand_source/runtime` | The normals fix, before and after. |

Checked against the brief: **no knee webbing, no head squash, no mesh tearing, no foot
penetration.** Feet do not skate *within the clip* — but see §7, which is where skating would
actually come from.

The first render pass came out as the back of the baby's head, which is exactly the silent failure
the wrapper's class doc warns about. Worth keeping: no assertion caught it; looking did.

## 9. Performance, and the blocking gate

| | Runtime rigged | Procedural `BabyView3D` | Budget |
|---|---|---|---|
| Triangles | **14,406** | 6,264 | 4,000 (§10) / **3,000** (infant) |
| Vertices | 9,846 | — | — |
| Surfaces / materials | 1 / 1 | — / 0 | — |
| Textures | 1 × 1024² | 0 (vertex colours) | one 512² |
| Texture memory | **5.33 MB** (RGBA8 + mips, uncompressed) | 0 | — |
| GLB on disk | **1.60 MB** (from 4.07 MB source, −60%) | n/a | — |
| Skin / clips | yes / walk, run | no / procedural | — |

**The character is 2.3× heavier than the procedural baby it would replace, and 3.6× over the §10
budget — 4.8× over the infant cap.** The texture is 2× per side, so 4× the pixels, against §7's
single 512² atlas.

This is the one thing local work cannot fix. The triangle count is set by the remesh
(`target_polycount 8000` → 7,203 quads → 14,406 triangles). Reaching 3,000 triangles means a new
remesh at roughly `target_polycount 1500`, which is a **Meshy credit spend and needs approval** —
or a manual retopology pass in a tool that is not installed.

The wrapper's own gate agrees, and reports it rather than hiding it:

```
- rigged: 14406 triangles against the art bible §10 budget of 4000 -- 4x over
- rigged: a 1024 x 1024 texture against §7's one 512 x 512 atlas
```

## 10. Build gates — all green

| Gate | Result |
|---|---|
| Full Godot test suite | **PASS — 94 cases, 0 failures** |
| ContentValidator | **PASS** (exercised by 10 cases in that suite) |
| Project load (headless) | **PASS**, clean |
| iOS Xcode export | **PASS** |
| arm64 device build | **PASS** — `BUILD SUCCEEDED`, binary verified `arm64` |
| Runtime character validation | **PASS** — sockets, height, clips, playback |

Not run on a physical iPad. No device validation is claimed.

### The test suite needed changing, and that deserves your review

Baseline before this work was 94 pass / 0 fail. The changes made `test_baby_avatar` fail 11 ways.
Five were **my design mistakes** and were fixed in the code, not the test — most importantly
`resolve_pose()` originally let the rigged model override *any* explicit request, so
`set_pose("standing")` silently returned something else.

The remaining six were the test asserting a premise that is no longer true: it was written for an
asset set with **no skin and no clips**, and said so in its own failure text — *"or a rigged
re-export has landed and this case needs revisiting alongside the flag."* That case has now
arrived. `_test_it_refuses_to_fake_animation` was rewritten to assert **honesty** rather than
permanent incapacity: capability must match what the visible pose actually carries, so a rigged
pose may report clips and a pose-locked one still may not.

**The real anti-faking guard is untouched** — the source scan for `create_tween`, `Tween`,
`AnimationPlayer.new(`, `Animation.new(`, `_process`, `_physics_process` still runs, and it is the
half that would catch a fabricated idle. The budget gate is untouched and still failing (§9).

Softening a test to pass is exactly the move that should get scrutiny. These edits are in
`game/tests/cases/test_baby_avatar.gd`; please read them rather than take this paragraph for it.

## 11. Production is NOT swapped

- `baby_room.tscn` still instantiates `scripts/baby/baby_view_3d.gd`. Untouched.
- `BabyLittleBuddy.tscn` is referenced by **no production scene** — only `scenes/spike/`.
- The procedural proxy is **kept as the fallback**, as instructed. Nothing was deleted.
- `ENABLED` / `PREVIEW_OVER_BUDGET` are unchanged.

## 12. What was NOT done

- **No normal map baked** — Blender absent (§1).
- **Feeding and hug activities were not rewired** to the sockets. The seam is in place
  (`get_mouth_position()` / `get_hug_position()` now answer from the skeleton) and socket targeting
  is demonstrated in the shots, but `feed_activity.gd` and the drop zones still target
  `BabyView3D`. Rewiring them is a gameplay change on the shipping character, and the budget gate
  (§9) says this asset should not become that character yet.
- **Room navigation not validated** — it depends on the movement-speed decision in §7.
- **Movement controller not retuned** — see §7.

## 13. Recommendation: **B — ready with minor visual polish**, blocked on budget

The character itself is production quality: rigged, animatable, correctly scaled and oriented, all
six sockets resolving, weights repaired, shading clean, every build gate green, and it looks right
in every shot.

What stands between it and a swap is not quality — it is **3.6× the triangle budget and 4× the
texture pixels**, on the project's hero character, framed large, on an iPad. That is a real
constraint the project set for itself, and it is not mine to waive.

Ordered next steps:

1. **Decide the budget.** Either approve a re-remesh at ~1,500 quads (a Meshy spend — needs
   approval), or consciously raise the infant cap. Until one happens, keep `BabyView3D`.
2. **Drop the texture to 512²** — one line in `build_runtime_character.py`
   (`TARGET_TEXTURE = 512`), no credits. Worth checking by eye first; 1024 already showed no
   visible loss against 2048.
3. **Settle locomotion speed** (§7) before any navigation work.
4. *Optional:* install Blender and bake a normal map — though §7 of the art bible bans them, so
   this is likely moot.

Do not buy more Meshy animations. Walk and run are in hand and the skinning underneath them is now
correct.
