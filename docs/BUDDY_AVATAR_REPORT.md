# Buddy Avatar — `pinkGirl_v01` asset assessment

**Asset:** `game/assets/characters/buddy/pinkGirl/pinkGirl_v01.glb`
**Source:** Meshy AI, exported via `pygltflib@v1.16.5`, glTF 2.0
**Role:** the player's Buddy / caregiver ("Big Buddy") — **not** Little Buddy, the child.
**Assessed:** 2026-09-18 · version 0.0.2

---

## 1. Measured properties

Read directly out of the GLB's JSON chunk and binary chunk — every number below is measured, none
is estimated.

| Property | Measured |
|---|---|
| File size | **21.99 MB** (23,057,540 bytes) |
| Triangles | **619,890** |
| Vertices | **336,300** |
| Meshes / primitives | 1 / 1 |
| Vertex attributes | `POSITION`, `NORMAL`, `TEXCOORD_0` — **no `JOINTS_0`, no `WEIGHTS_0`** |
| Node hierarchy | a single node, one mesh, no transform, no children |
| Materials | 1 |
| → `metallic` | **1.0** |
| → `roughness` | 1.0 |
| → `doubleSided` | **true** |
| → maps | baseColor + **normal** |
| Textures / images | 3 |
| → sizes | **2048 × 2048** each, JPEG |
| → bytes | 2.2 MB + 1.1 MB + 1.3 MB |
| → unused | **image[1] (1.1 MB) is embedded but referenced by no material** |
| **Skin (rig)** | **NONE** |
| **Animation clips** | **NONE** |
| Cameras | 0 |
| Bounds X | −0.410 … +0.409 → **0.818** |
| Bounds Y | −0.952 … +0.951 → **1.903** |
| Bounds Z | −0.309 … +0.315 → **0.624** |
| Pivot | **centre of the body** — feet sit at y = −0.952, not at the origin |
| Orientation | upright, Y-up; no authored rotation |

**Scale:** 1.903 units tall. Read as metres that is a 1.90 m adult — slightly taller than the art
bible's Dad (1.78 m) and well above Mom (1.65 m), but in the right *class*. It is an adult-scale
model, not a child, which is correct for the caregiver role.

## 2. Against the project's budgets

The art bible (§10) is locked, and its numbers were derived from this project's measured scene,
not imported as a rule of thumb.

| Metric | This asset | Budget | Over by |
|---|---|---|---|
| Triangles, character | 619,890 | 2,500–4,000 | **155× – 248×** |
| Triangles, whole frame | 619,890 | 30,000 hard ceiling | **20.7×** |
| Texture, per character | 3 × 2048² | 1 × 512² | **48× the pixels** |
| App size | 21.99 MB | 40 MB total | **55% of the entire app budget, for one character** |
| `metallic` | 1.0 | **0.0 everywhere** | violates §7 |
| Normal map | present | **banned** | violates §7 |
| Alpha / doubleSided | doubleSided | culling on, 0 transparent surfaces | doubles overdraw |

For scale: a **complete furnished room** in this game is 8,600–9,648 triangles. This single
character is **64× an entire room**, and 207× the combined geometry of every third-party model the
project ships.

## 3. The five questions, answered

### Is it suitable for production?

**No — not in this form.** It is a good *concept*: the silhouette, proportions and read of the
character are what a caregiver should be, and it is genuinely usable as a reference and as a
blockout. But as a shipping asset it fails on four independent counts — triangle count, texture
budget, material rules, and the complete absence of a rig. Any one of those would block it.

This is normal and expected. The art bible (§11) already says generation is **"a concepting and
blockout tool, not a delivery tool"** and that raw generator output is never shipped. This asset is
exactly that: raw output.

### Is it too heavy for iPhone?

**Yes, decisively.**

`export_presets.cfg` sets `min_ios_version = 15.0`, which admits hardware back to the **A9**
(iPhone 6s, iPad Air 2). The project targets 60 fps on A12+, 60 fps on A10–A11, and 30 fps on the
A9 floor with shadows off.

619,890 triangles in a single draw is not a 60 fps proposition on an A9, and it is a poor one even
on modern hardware given the rest of the frame. Worse, it is **doubleSided**, so every one of those
triangles is rasterised from both faces — on a tile-based mobile GPU that is paid twice in
overdraw, which is the metric that actually hurts here.

Texture memory: three 2048² maps are ~48 MB uncompressed, ~12 MB with ASTC. The art bible's texture
budget is **~8 MB target, 24 MB ceiling** for the *whole game*.

The 21.99 MB file is also a distribution problem: it more than doubles the repository and consumes
over half the app-size budget for one character.

### Does it need retopology?

**Yes, and this is the single biggest piece of work.** 619,890 → 2,500–4,000 is a 99.4% reduction.
That is not a decimation slider; it is a genuine retopology pass — building clean, animation-ready
quad topology over the generated surface, with edge loops where the body will deform.

It also needs UV unwrapping onto a single atlas, and the three 2048² maps baked down to **one 512²
albedo** with the normal map dropped entirely (§7 bans them, and in a flat-shaded one-light style
a normal map buys almost nothing visible).

Worth stating plainly: in this art direction, geometry past a few thousand triangles **actively
hurts**. A character visibly smoother and more detailed than the 300–1,500-triangle furniture
around it makes the *furniture* look broken — art bible §9. Reducing this model is not only a
performance fix, it is a coherence fix.

### Does it need rigging?

**Yes — there is no rig at all.** The GLB contains zero `skins`, zero `animations`, and the mesh
has neither `JOINTS_0` nor `WEIGHTS_0` vertex attributes. It is a static, frozen mesh.

Concretely: **it cannot walk, cannot turn to face anything, cannot eat, drink, hug, sit or sleep.**
Every one of the game's 17 semantic actions is unavailable to it. The wrapper therefore reports
`can_play_action() == false` and performs no action — **nothing fakes a rig**, per requirement 7.

### What is the exact next step before it can walk or animate?

In order. Steps 1–2 are prerequisites for 3; nothing animates until 4.

1. **Retopologise to 2,500–4,000 triangles**, with deformation-friendly loops at shoulders, elbows,
   hips and knees. (Blender, or Meshy's own remesh at its lowest setting followed by a manual
   cleanup — auto-remesh alone rarely gives loops you can skin well.)
2. **Re-UV and bake to a single 512² albedo.** Drop the normal map. Set `metallic = 0`, roughness
   0.85–1.0, one material, culling **on** (not doubleSided). Remove the unused third image.
3. **Rig to a humanoid skeleton.** The project already specifies `LB_Rig_v1` in
   `docs/CHARACTER_AGE_STAGES.md`, and the adult family is meant to share one rig across Mom, Dad
   and the grown-up Little Buddy — so rig to **that**, not to a bespoke skeleton, or the shared
   animation library is lost. Meshy's auto-rig is the fastest route to a first pass and is worth
   trying before hand-rigging; verify the bone names map to the project's rig.
4. **Author the minimum clip set: `idle` and `walk`.** The existing driver
   (`character_action_driver.gd`) resolves a semantic name to a clip and degrades safely when one
   is missing, so clips can land incrementally — `idle` and `walk` first, then `wave`, `point`,
   `pickUp`, `give` as they are made.
5. **Normalise on export:** feet at the origin (currently mid-body), facing −Z to match the rest of
   the game, adult height 1.65–1.78 m.
6. **Re-measure and re-render** in a real room next to the existing props before enabling it. The
   acceptance test in art bible §9 is: if your eye goes to it because it looks *different* rather
   than because it is the subject, it fails.

**None of steps 1–4 can be done in this environment** — there is no Blender, no `gltfpack` and no
`gltf-transform` installed here, and I will not pretend otherwise. They need either a desktop DCC
tool or Meshy's own remesh/rig features.

## 4. What was integrated, and what was deliberately not

Per requirement 6, **the procedural placeholder remains the active Buddy** and the avatar is
opt-in, default **off** — because validation demonstrably does not pass. The wrapper exists so the
model can be looked at, iterated on, and swapped in the moment a rigged, retopologised version
arrives, without any gameplay code changing.

Gameplay never touches the GLB hierarchy: the wrapper scene is the only thing that knows the
model's node layout, so a re-export with different names changes exactly one file.

Speech, save, navigation, iOS export and signing are untouched.

## 5. A note on the product decision

The design has always had **Big Buddy as the invisible player role**, not a visible avatar — that
was an explicit approved decision, and it is why no caregiver character exists in the game today.
Introducing a visible Buddy is a genuine product change, not just an asset swap: it affects framing
(two characters in shot), the camera system (which currently guarantees *Little Buddy* stays
visible), and the story's point of view.

That is the owner's call and this report does not pre-empt it. Flagged only so the decision is made
deliberately rather than arrived at by having a model.
