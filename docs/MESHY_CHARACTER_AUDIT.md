# Meshy Character Audit

**Audited:** 2026-09-18 · version 0.0.2
Every number below was read directly out of each GLB's JSON and binary chunks. Nothing is
estimated, and every identification was confirmed by **rendering the model and looking at it**,
not by reading its filename.

---

## 1. What was actually in `~/Downloads` — and what was not

You described three assets: pink-haired girl, baby, bunny mascot. There are **four** GLBs, and
three of them share the identical prefix `Meshy_AI_Create_one_original_s_…`, so the filenames
cannot tell them apart. You said not to guess, so I rendered each one.

| File | Rendered identification |
|---|---|
| `Meshy_AI_Use_only_the_pink_hai_0918081531_texture.glb` | **Pink-haired girl** ✅ |
| `Meshy_AI_Create_one_original_s_0918083052_texture.glb` | **Baby — standing**, blue onesie, hair curl |
| `Meshy_AI_Create_one_original_s_0918083143_texture.glb` | **Baby — sitting**, darker hair, bib |
| `Meshy_AI_Create_one_original_s_0918083218_texture.glb` | **Baby — sleeping**, eyes closed, arms out, white onesie |

> **Owner confirmed this mapping on 2026-09-18** (`0918083052 = ยืน`, `0918083143 = นั่ง`,
> `0918083218 = ท่านอน`). Each repo copy was then checked against its original by SHA-256 and is
> byte-identical, so the names on disk are verified rather than assumed.

> ### There is no bunny mascot
>
> All three ambiguous files are **babies**, differing only in pose. The only "bunny" anywhere in
> `~/Downloads` is a 2D PNG (`20250712_1016_Pastel Bunny Tunes….png`) — an image, not a model.
>
> So the bunny role is **not integrated and no wrapper was created for it**. Labelling one of the
> babies "bunny" to satisfy the list would have been exactly the guess you told me not to make.

**All four originals remain untouched in `~/Downloads`.** Files were copied, never moved.

## 2. Repo paths

| Role | Repo path | Status |
|---|---|---|
| Buddy / caregiver | `game/assets/characters/buddy/pinkGirl/pinkGirl_v01.glb` | copied, wrapper built |
| Little Buddy — standing | `game/assets/characters/littleBuddy/baby/baby_standing_v01.glb` | copied |
| Little Buddy — sitting | `game/assets/characters/littleBuddy/baby/baby_sitting_v01.glb` | copied |
| Little Buddy — sleeping | `game/assets/characters/littleBuddy/baby/baby_sleeping_v01.glb` | copied |
| Bunny mascot | `game/assets/characters/mascot/bunny/` | **directory created, empty — no asset supplied** |

Named by **pose** rather than `baby_v01` because an unrigged mesh is frozen in the pose it was
generated in: the sitting baby can only ever sit. Which one is "the" baby is a choice with real
consequences, and it is yours — see §6.

## 3. Measurements

| | pinkGirl | baby standing | baby sitting | baby sleeping |
|---|---|---|---|---|
| File size | 22.0 MB | 11.3 MB | 15.4 MB | 14.9 MB |
| **Triangles** | **619,890** | **255,458** | **398,404** | **373,090** |
| Vertices | 336,300 | 139,290 | 214,442 | 200,757 |
| Meshes / primitives | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 |
| Materials | 1 | 1 | 1 | 1 |
| Textures | 3 | 3 | 3 | 3 |
| Texture size | 2048² ×3 | 2048² ×3 | 2048² ×3 | 2048² ×3 |
| **Skeleton** | **none** | **none** | **none** | **none** |
| **Animation clips** | **none** | **none** | **none** | **none** |
| Node hierarchy | 1 node, no transform | same | same | same |
| Bounds W×H×D | 0.82 × 1.90 × 0.62 | 0.87 × 1.90 × 0.76 | 1.61 × 1.90 × 1.08 | 1.55 × 1.90 × 0.72 |
| Pivot | mid-body | mid-body | mid-body | mid-body |
| Orientation | upright, Y-up, no authored rotation | same | same | same |
| Limbs fused? | **no** — separated, readable silhouette | no | no | no |
| Obvious deformation | none seen | none | none | none |

Every model is normalised by Meshy to ~1.903 units tall, so **height carries no information about
the character's intended size** — the sitting baby is not 1.9 m tall, it is scaled to the same box.
Real scale has to be set in the wrapper.

Vertex attributes on all four: `POSITION`, `NORMAL`, `TEXCOORD_0`. **No `JOINTS_0`, no
`WEIGHTS_0`** — which is the technical statement of "cannot be skinned or animated".

Material on all four: `metallic = 1.0`, `roughness = 1.0`, `doubleSided = true`, with a baseColor
map, a normal map, and a metallicRoughness (ORM) map.

## 4. Against the targets you set, and the project's own budgets

Your rough targets: Buddy hero 4k–10k · Baby 3k–8k · Bunny 3k–8k.
The art bible (§10, locked, derived from this project's measured scene) is stricter: main character
**2,500–4,000**, one **512²** texture, materials **1**, frame ceiling **30,000** triangles.

| Asset | Triangles | vs your target | vs art bible | Verdict |
|---|---|---|---|---|
| pinkGirl | 619,890 | **62× – 155×** over | 155× – 248× over | **too heavy** |
| baby standing | 255,458 | **32× – 85×** over | 64× – 102× over | **too heavy** |
| baby sitting | 398,404 | **50× – 133×** over | 100× – 159× over | **too heavy** |
| baby sleeping | 373,090 | **47× – 124×** over | 93× – 149× over | **too heavy** |

For scale: a **complete furnished room** in this game is 8,600–9,648 triangles. The lightest of
these four characters is **26× an entire room**.

Measured in the real rendered scene with the pinkGirl avatar on (all passes, incl. shadow):

| Scene | without | with | ceiling |
|---|---|---|---|
| Bedroom | 75 dc / 25,480 tris | 77 dc / **102,964** | 220 dc / 30,000 tris |
| Kitchen | 75 dc / 20,772 tris | 77 dc / **98,256** | " |
| Main menu | 62 dc / 16,961 tris | 64 dc / **171,389** | " |

**Draw calls are fine** (+2). **Triangles are 3.4× the hard ceiling in a room and 5.7× on the
menu** — and that is *after* Godot's importer silently applies auto-LOD (`generate_lods=true`),
without which the figure would be the full 619,890. Worth noting because the art bible §10
explicitly argues "no LODs"; the engine is doing it anyway, and it is still not enough.

**All four are too heavy for iPhone.** `min_ios_version = 15.0` keeps the A9 (iPhone 6s) in
support, and `doubleSided` means every triangle is rasterised twice — overdraw, which is the metric
that actually costs on a tile-based mobile GPU.

## 5. Suitability summary

| Asset | Usable now? | Needs retopology | Needs rigging | Usable as |
|---|---|---|---|---|
| pinkGirl | **no** | yes — 99.4% reduction | yes | concept / blockout / menu preview behind a flag |
| baby standing | **no** | yes — ~98.4% | yes | best general-purpose candidate |
| baby sitting | **no** | yes — ~99.0% | yes | pose-locked: feeding, play |
| baby sleeping | **no** | yes — ~98.9% | yes | pose-locked: crib, bedtime |
| bunny | — | — | — | **not supplied** |

Nothing here is rejected on looks. The **form language is right** on all of them: rounded volumes,
soft hands, big heads, separated limbs, readable silhouettes. What fails is surface (2048² maps,
metallic 1.0, normal maps), density, and the total absence of a rig.

## 6. The choice only you can make: which baby?

Chapter 2 is **caregiver gameplay and the baby deliberately does not walk** — that is a locked
product decision. So a pose-locked mesh is much less of a problem for the baby than it is for a
character who must walk. Used as three static poses, these could genuinely work *before* rigging:

- **sleeping** → crib, bedtime, "Good night"
- **sitting** → feeding, milk, play
- **standing** → general, first-words

That is a legitimate design, not a workaround. But it is a design decision with content
implications, so I have not made it. My recommendation if you want one: **sitting** as the primary
Chapter 2 baby, because feeding is the chapter's core loop.

## 7. Provenance and licence — NOT VERIFIED, and I will not invent it

You asked me to record the licence exactly as Meshy shows it, and to record CC BY 4.0 if that is
what it says. **I cannot see Meshy's export dialogue or your account's plan from here**, and a GLB
carries no licence metadata — the `asset` block says only `pygltflib@v1.16.5`. So the licence field
in `docs/ASSET_MANIFEST.md` reads **"as shown by Meshy at export — OWNER TO CONFIRM"** rather than a
value I guessed.

**This needs a real decision, because there is a standing policy conflict.** `ART_BIBLE.md` §9 and
`ASSET_MANIFEST.md` both state the project is **CC0-only, and that CC-BY is explicitly excluded** —
the reasoning on record is that a perpetual attribution obligation on a shipped children's app is
not worth it when a pure-CC0 path exists. If these exports are CC BY 4.0, they contradict that
policy and either the assets or the policy has to give.

There is a plausible resolution: Meshy's paid plans generally grant the *generating user*
commercial rights to their own generations, which is a different thing from a third-party CC-BY
asset. But I have not verified it and will not assert it. Please confirm from your Meshy account
what licence these four exports carry.

## 8. Why the raw files are not in git

They are on disk at the paths above and **gitignored**.

Four raw exports are 63.6 MB, and Godot extracts their embedded textures beside them for roughly
20 MB more — about **84 MB added permanently to a 33 MB repository**, with no git-lfs configured,
for assets that cannot ship without retopology and cannot animate at all. The app-size budget for
the entire game is 40 MB.

The deciding argument is reversibility: adding them to git later is one command, whereas taking
84 MB back out means **rewriting published history, which this project has forbidden outright**.

The whole suite is green both with and without them present, and the project loads with zero
errors either way — verified by hiding the directory and re-running. A fresh clone simply reports
the model unavailable, which the wrapper already handles, and the enable-gate still fails loudly if
anyone switches the avatar on without a model.

To include them anyway: delete the Meshy block at the end of `.gitignore` and `git add -f` the paths.

## 9. Exact next step before any of these can walk or animate

In order — nothing animates until step 4.

1. **Retopologise** to the budget (2,500–4,000), with deformation loops at shoulders, elbows, hips,
   knees. Auto-remesh alone rarely produces loops that skin well.
2. **Re-UV and bake to one 512² albedo.** Drop the normal and ORM maps. `metallic = 0`, roughness
   0.85–1.0, one material, culling **on**.
3. **Rig to `LB_Rig_v1`** — the shared adult/child skeleton already specified in
   `docs/CHARACTER_AGE_STAGES.md`. Rig to *that*, not a bespoke skeleton, or the shared animation
   library is lost. Meshy's own auto-rig is the fastest first pass; verify the bone names map.
4. **Author `idle` and `walk` first.** `character_action_driver.gd` resolves a semantic name to a
   clip and degrades safely when one is missing, so clips can land incrementally.
5. **Re-measure and re-render in a real room** next to the existing props before enabling anything.

**None of steps 1–4 is possible in this environment** — there is no Blender, no `gltfpack` and no
`gltf-transform` installed, and I have not pretended otherwise. They need a desktop DCC tool or
Meshy's own remesh/rig features.
