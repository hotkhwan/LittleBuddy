# Art Bible — v1.0 LOCKED

**Status: LOCKED, 2026-09-18.** This is the filename Bible §15 requires and it supersedes
`docs/ART_BIBLE_DRAFT.md`, which is retained as the reasoning record. Where the two disagree,
this wins.

**This is a gate.** Every new art asset — modelled, procedural, generated or commissioned — passes
the §14 acceptance checklist before it enters the repo. Bible §14 is explicit that direction locks
*before* models are generated, precisely so we never pay to regenerate when scope shifts.

**What changed on promotion:** the draft's twelve flagged decisions are resolved in §15. Six are
now closed by work that has since shipped; four are adopted as written; two remain genuinely open
and are owner decisions, both flagged inline.

---

## 1. Originality — a hard requirement

**Every character, room, prop, UI element, icon, animation, colour and line of dialogue must be
original.** This is a commercial children's product intended for distribution; borrowed likeness
is both a legal and a credibility problem.

**Do not copy, trace, pastiche, "make it look like", or use as direct visual reference:** Bluey ·
Avatar World · Toca Boca · Sago Mini · Pixar · Disney · Peppa Pig · Cocomelon · Animal Crossing ·
The Sims · any other commercial game, film or TV property.

**This applies to prompts exactly as it applies to hand-drawn art.** Never put a brand, studio,
franchise, character or artist name into a generation prompt. A prompt is a form of reference.
**Every prompt used to generate a shipped asset is recorded in `docs/ASSET_MANIFEST.md`** so this
stays auditable.

Commercial products may be referenced only for **abstract qualities** — playful sandbox freedom,
readable one-tap interaction, warmth, calm non-punitive feedback, generous touch targets. Those
are design properties, not designs.

If commissioning, this section goes in the brief. A recognisably derivative delivery is rejected
regardless of quality.

## 2. The direction, in one paragraph

> **Little Buddy looks like a warm, sunlit picture book that you can walk around inside.**
> Everything is built from soft rounded volumes with no sharp corners and no hard edges.
> Characters are cute and openly expressive — large eyes, simple mouths, real emotion — but never
> realistic and never uncanny. The family home is bright, tidy, lived-in and safe, lit as if it is
> always mid-morning. Colours are pastel but **saturated**, not washed out. Every object is
> instantly recognisable as the thing it teaches, because the game's entire job is teaching its
> name. Nothing is scary, nothing is dirty, nothing is broken, and nobody is ever sad for more
> than a moment.

**"Premium" means coherent, warm, well-lit and well-composed — not high-fidelity.** That
resolves the apparent conflict between the Bible's "premium stylized 3D" and a one-light,
flat-shaded, low-poly mobile game. This paragraph is the operative definition.

### The five tests every asset must pass

| Test | Question |
|---|---|
| **Recognition** | A 4-year-old who has never seen it names it correctly, cold, with no audio. |
| **Silhouette** | Identifiable in pure black at 64 px. |
| **Warmth** | Looks like it belongs in a loved home, not a catalogue render. |
| **Safety** | Nothing sharp, dirty, broken, dark, or capable of reading as distress. |
| **Coherence** | Next to the shipped props, nothing looks foreign. |

## 3. Colour — LOCKED

Seven tokens are the identity of the game. Everything else derives from them.

| Token | Hex | Role |
|---|---|---|
| `cream` | **`#FFF6E5`** | base note — backgrounds, panels, walls |
| `dustyBlue` | **`#9AC0D9`** | cool anchor — sky, water, calm UI |
| `softPink` | **`#FFC1CC`** | warmth and affection — blush, hearts, rugs |
| `mint` | **`#A8E6CF`** | "go", success, freshness — speak button, correct feedback |
| `peach` | **`#FFD3B6`** | skin-adjacent warmth — wood, bread, cushions |
| `lavender` | **`#D6C7F0`** | gentle accent — bedtime, night, rest |
| `ink` | **`#59422B`** | **the only "dark"** — outlines, text, eyes. A warm brown. |

**`#000000` is banned everywhere** — text, outlines, eyes, UI, shadow colour. Pure black in a
pastel scene reads as a hole. Use `ink`, or `ink` lightened.

**Never darken by reducing value alone.** Always mix toward `ink`, so shadows stay warm. Each core
colour gets exactly three steps: Light (45% `cream`), Base, Deep (22% `ink`). Do not author
intermediate values ad hoc.

### Semantic roles

| Role | Colour |
|---|---|
| Panel background | `cream` `#FFF6E5` |
| Primary text | `ink` `#59422B` |
| Secondary text | `#8A7358` |
| **Star — earned** | **`#FFC73D`** — the single most important colour in the game |
| Star — current/next | `#FFE199`, pulsing ~0.6 Hz |
| Star — not yet earned | `#E8DCC8` — a warm **ghost**, never grey, never an "empty" slot |
| Success / speak | `mint` `#A8E6CF` |
| Try again | `peach` `#FFD3B6` — warm and inviting. **Never red.** |
| Parent-settings chrome | `lavender` `#D6C7F0` — marks "this is for a grown-up" |

**Banned as UI colours:** red and anything near it · pure black · pure white as a large field ·
neon/fluorescent · low-saturation grey. Per `CLAUDE.md`: no red X, no failure colour, ever.

### Skin tones — ship all three from first release

So the game is not implicitly about one kind of family. Skin tone is a **material slot swap on one
mesh**, not three meshes — zero additional triangle or texture cost.

| Token | Hex | Blush | Brow / hair base |
|---|---|---|---|
| `skinLight` | `#FFDEBD` | `#FFB8B3` | `#B88C6B` |
| `skinMid` | `#E8B98C` | `#D69A82` | `#8A5F3C` |
| `skinDeep` | `#B07B52` | `#9A6247` | `#4E3323` |

### Room moods

Every room keeps `cream` as its base; only the accent shifts. That is the whole system.

| Room | Dominant | Accent |
|---|---|---|
| Bedroom | `cream` + `lavender` | `dustyBlue` |
| Bathroom | `cream` + `dustyBlue` | `mint` |
| Kitchen | `cream` + `peach` | `mint` |
| Living Room | `cream` + `peach` | `softPink` |
| Nursery | `cream` + `softPink` | `dustyBlue` |

## 4. Characters

### Form language
Everything is a rounded volume. Head = slightly flattened sphere, torso = rounded barrel, limbs =
capsules with soft spherical ends. No flat planes, no creases, no hard edges. No chin definition
below the Child family. **No visible teeth, ever** — not in `happy`, not in `celebrate`. No
individual fingers below Teen; hands are soft mitts with a suggested thumb. Feet rounded and
~1.15× oversized, which reads as stable and toy-like.

**Silhouette check:** in pure black at 64 px the head, both arms and both legs must be separately
readable. No fused limbs — a hard acceptance criterion.

### Face — the uncanny-valley guard rail

The face carries the entire emotional load. It is **flat-ish and graphic**, not sculpted.

| Feature | Spec |
|---|---|
| Eyes | Large, set **below** the vertical midline, wide apart. ~22% of head width at Infant, ~14% by Adult. Soft vertical oval — never round buttons, never almond. |
| Iris | A single solid `#382924` mass. **No iris ring, no sclera variation, no eyelashes below Teen.** |
| Catchlight | Exactly **one** white circle, upper-left, ~18% of eye width, mirrored. **The single highest-value detail on the character** — it is what makes the eyes look alive. |
| Whites | Minimal, and `#FAF5ED` — never `#FFFFFF`. |
| Brows | Short soft strokes well above the eyes with a clear gap. They do **60% of the emotional work**. |
| Nose | A tiny skin-coloured bump. No nostrils, no shadow. |
| Mouth | One filled shape in `#9E4F4D`. **No lips, no lip line, no teeth, no tongue.** |
| Blush | Two heavily feathered circles, ~25% of head width, always at ≥0.3 weight — part of the resting face. |

**The failure mode is not "too realistic", it is detail mismatch** — realistic eyes on a simple
face. Rule: the face must be **uniformly simple**. If one feature gets more detail, all of them
do, and they do not. Banned: wrinkles, skin pores, subsurface scattering, specular on skin,
asymmetry, cursor-following eyes, idle micro-expressions beyond the blink.

**Expression range is deliberately narrow:** content, happy, excited, sleepy, hungry, surprised.
There is no angry, no crying, no fear, no disgust. `hungry` is gently downturned — **"sad, never
distressed."**

> **Always render and look at the face.** The baby's first smile shipped with inverted Z-rotation
> signs, producing a perfect frown on a character whose resting state is meant to be content, and
> it survived three render passes.

### Hair
Separate mesh, 2–5 solid rounded masses. **No hair cards, no alpha, no strands.** Silhouette is
the whole point — hair is the fastest way to tell Mom from Dad from Little Buddy at 64 px.

### Clothing
Flat colour fields plus a single darker accent. No patterns below 2 cm of screen size, no logos,
no text, no stripes under ~4 px. Soft, slightly oversized fit. No belts, buckles or zips.
**Gender-neutral by default** — do not make pink-for-girls / blue-for-boys the default pairing.
Three colours maximum per garment.

### Parents
Share the Adult family with the grown-up Little Buddy: one base mesh, one rig, three variants.
**1 : 6.5** head-to-height, deliberately not the realistic 1 : 7.5. **Exactly the same face system
as Little Buddy** — differentiated by hair silhouette, height, clothing and shoulder width, never
by facial detail and never by stereotyped markers. Warm, attentive, frequently looking *at* Little
Buddy. Never stressed, never scolding, never absent. **Adults must never dominate the frame.**

## 5. Home architecture

| Property | Spec |
|---|---|
| Camera | Constrained **three-quarter** view, looking slightly down. Never top-down (kills faces), never first-person, never free-orbit. Per-room framing, aspect-adaptive — see `docs/ROOM_CAMERA_SYSTEM.md`. |
| Construction | **Three walls, open fourth wall** toward the camera — the doll's-house convention. |
| Ceilings | None. Open to a soft `cream` void. |
| Windows | Every room gets one. The cheapest warmth in the scene: a flat `#B8DBED` sky plane, soft rounded frame, no glass, no transparency, no reflection. |
| Doors | Rounded-top, no visible hinges, handle as a soft sphere. |
| Floors | Warm wood, plus one rug per room to define the play area. |
| **Corners** | **Every architectural edge has a visible bevel, ~2 cm in-world.** A hard 90° corner is the single strongest "this is a prototype" signal. |
| Clutter | Tidy but lived-in — a book left out, a toy on the rug, a plant. **Never messy, never dirty, never damaged.** |

## 6. Props and food

- **Rounded low-poly.** Chamfered corners, generous fillets, no thin shells.
- **Nothing thinner than ~1.5 cm in-world** — thin geometry aliases badly with MSAA off.
- **Reduce to the minimum recognisable form.** A spoon is a bowl and a handle. Detail that does
  not aid recognition is cost with no return.
- **One object teaches one word.** Two nouns must never share a shape. This rule caught a yellow
  sphere `bathToy` against a red sphere `ball`, and five identical cubes standing in for shirts,
  pants and pyjamas.
- **Pivot at base centre** for anything standing, at the **grip point** for anything held.
- **Build a prop kit, not a set of props.** A rounded cushion recoloured is a pillow, a seat pad,
  a floor cushion and a toy. Target ≤ 60 unique prop meshes for the whole home.

**Food** is the highest-frequency vocabulary category and the easiest to get wrong. Whole, clean,
undamaged, appetising — no bites taken, no bruises, no cut cross-sections. Saturated but
palette-consistent: apple `#E8737D` not fire-engine red. **Colour is a primary teaching channel**
and must match the `colorWord` in content JSON — `soap` once shipped rendering white while its
`colorWord` said "pink". Containers must read as containers: a cup has visible interior depth.

## 7. Materials and lighting — LOCKED

| Property | Spec |
|---|---|
| Shading | Flat-shaded stylised PBR via `StandardMaterial3D`. Albedo carries everything. |
| Roughness | **0.85–1.0.** Nothing in this game is shiny. |
| Metallic | **0.0 everywhere.** There is no metal; "metal" is a dusty-blue convention. |
| Normal maps · alpha · emission · SSS | **None.** Alpha is the most common mobile performance trap and we do not need it. |
| Textures | One shared **512×512** atlas per family. Flat colour and gentle gradients only — **no baked AO, no baked shadow, no noise, no grunge, no wear, no dirt.** |
| Materials per object | **1.** Two only where genuinely different (an unshaded eye catchlight). Never three. |
| Lights | **Exactly one `DirectionalLight3D` per scene.** Non-negotiable. |
| Shadows | On, soft, warm, half-strength. Shadows are what ground objects on the floor. |
| Ambient | High warm fill — this is what stops the dark side of a form going muddy with one light. |
| Time of day | **Permanently mid-morning.** A bedtime level may tint ambient toward `lavender` and reduce energy to ~0.45 — it must stay clearly readable, **never actually dark**. |

**Why no baked AO:** one directional light plus warm ambient. Baked darkening fights it and
produces the grubby look that separates an amateur mobile scene from a polished one.

**Forbidden and not negotiable:** GI/SDFGI/VoxelGI · SSAO · SSIL · SSR · glow/bloom · volumetric
fog · depth of field · colour-correction post · any screen-space effect · `RigidBody3D` physics.

## 8. UI

| Property | Spec |
|---|---|
| Corners | Generously rounded. Nothing square, nothing with a 1 px border. |
| **Touch targets** | **240 × 240 px minimum** at the 1366×1024 reference for any primary child-facing control. **Never shrink this.** |
| Safe area | Every full-screen layer respects it. `Celebration` once ignored it and drew a sticker card over the baby's face. |
| Text | Rounded, high x-height sans. Minimum **27 pt** at reference. `ink` on `cream`. |
| Text load | Minimal — the player is a pre-reader. Icons and voice first. |
| Contrast | Enforced by `test_ui_contrast.gd` using true WCAG luminance, **including hover and pressed states** — `font_hover_pressed_color` once fell through to near-white and only that test caught it. Touch on iOS synthesises hover, so those states are real. |
| Motion | Ease-out, 150–250 ms, slight overshoot on appearance. Nothing snaps, nothing flashes. |
| **Never** | red · X marks · percentages · pronunciation scores · timers · countdowns · progress bars that can go down · modal failure dialogs · external links · purchase prompts |

**Stars** are the most emotionally loaded element in the game. Five-point, rounded tips, one shared
glyph at every size. Earned `#FFC73D`; next `#FFE199` pulsing; unearned `#E8DCC8` outline only —
**a ghost, not an empty slot.** Never grey, never crossed out, **never removed once earned**.

> Implementation trap: `_draw()` only *records* commands; the renderer binds textures later in the
> frame. A glyph held in nothing but a local dropped to zero refs and every sticker painted as a
> solid coloured square. Keep glyph resources referenced.

**App icon:** one subject, centred, no text. Reads at **60 px** and at 1024 px. Opaque. Nothing
within 8% of the edge. Once a final Little Buddy model exists the subject should be the
**character** — a face is more memorable on a home screen than an object. Must be checked on a
real home screen over a busy wallpaper before release.

## 9. Mixed sources — the coherence rule

The game ships CC0 props next to procedural geometry next to (eventually) commissioned characters.
Three sources, one look:

**Flat-shaded rounded low-poly is the house style.** New art matches it — comparable polygon
density, comparable rounding radius, flat albedo, one 512² atlas. **A commissioned character that
is visibly smoother or more detailed than the furniture around it makes the *furniture* look
broken**, which is a much worse outcome than a slightly simpler character.

**Acceptance test:** render the new asset in a real room next to existing props. If your eye goes
to it because it looks *different* rather than because it is the subject, it fails.

**Licensing is part of art direction.** Every third-party asset must be **CC0**, with the licence
file read from the downloaded archive — not a website summary — and committed alongside.
**Quaternius is excluded**: its licence changed to QAL v1.0 and §3(a) forbids redistribution
"regardless of how much the Assets have been modified", while its own FAQ still says CC0. The site
contradicts itself; do not re-add on the strength of a web search. **CC-BY is excluded** too — a
perpetual attribution obligation on a shipped children's app is not worth it when a pure-CC0 path
exists.

**Procedural is a first-class answer**, not a fallback: no licence, no download, no repo bytes.

**Objects must read as the word they teach.** Never substitute a "similar" model — a chick is not
a duck, a soap dish is not soap. An honest procedural shape beats a wrong-but-similar sourced model.

## 10. Budgets — measured, not guessed

| Class | **Bible §17 says** | **LOCKED** |
|---|---|---|
| Main character | 15k–35k | **2,500–4,000** |
| Secondary character | 10k–25k | **2,000–3,000** |
| Large furniture | 2k–8k | **300–1,500** (cap 2,000) |
| Hero prop | 1k–6k | **200–1,000** |
| Small prop | 300–3k | **40–400** |
| Character texture | 1024–2048 | **1 × 512²** per family |
| Materials per object | 1–3 | **1** (2 max on characters) |

**The Bible's 15k–35k main character is 5–12× too generous for this game** and is overridden. At
35k a single character would be 2.5× the entire current world. More importantly, **spending the
budget there would actively hurt the look**: in a flat-shaded, normal-map-free, one-light style,
geometry past a few thousand triangles buys almost nothing visible while pulling the character out
of alignment with the 200–500-triangle furniture around it (§9).

### Frame budget

| Metric | Target | Hard ceiling |
|---|---|---|
| Triangles, typical room | ~18,000 | **30,000** |
| **Draw calls** | ~170 | **220** |
| Directional lights | 1 | **1** |
| Other lights | 0 | **0** |
| Transparent surfaces | 0 | **0** |
| Total app assets | — | **40 MB** |

**Draw calls, not triangles, are the metric to watch.** Atlas aggressively, merge static geometry,
use `MultiMesh` for repeated props.

### No LODs — argued, not assumed
At most 3–4 characters on screen, each ≤ 4k tris; the pressure here is draw calls and overdraw,
not vertex throughput, and LODs change neither. The camera range is tiny — a fixed three-quarter
view in a small room. And LOD popping on a screen a 4-year-old holds 30 cm from their face is a
visible defect. Instead: cull inactive rooms, merge static room shells, `MultiMesh` repeats, one
atlas per pack, and treat the 220 draw-call ceiling as a build check.

**Revisit only if** a device profile on the oldest supported hardware shows vertex cost above ~20%
of frame time.

## 11. Generation (Meshy or any generator)

Permitted **only after this document is locked** — which it now is. It is a **concepting and
blockout** tool, not a delivery tool.

- **Never ship raw generator output.** Every asset is retopologised or rebuilt.
- **Never put a brand, studio, franchise or artist name in a prompt** (§1). Record every prompt in
  `ASSET_MANIFEST.md`.
- Characters: neutral A-pose, visible hands, **separated limbs**, clean proportions.
- Export **GLB**; always keep the editable source.

> **Status tonight: Meshy is not accessible — no credentials are available in this environment.**
> Per the run brief this does not block the night. No generated asset is claimed, and nothing
> fabricated is presented as final. Exact generation specs for the remaining hero assets belong in
> `ASSET_MANIFEST.md` when that path opens.

## 12. Acceptance checklist — every new asset

- [ ] Passes the five tests in §2 (recognition · silhouette · warmth · safety · coherence)
- [ ] Palette **only** from §3; no invented colours; no pure black; no red
- [ ] Inside the §10 triangle, texture and material budget
- [ ] 1 material (2 max on a character); 512² atlas; no normal map, no alpha, no emission
- [ ] Metres, pivot correct, transforms applied, no residual node scale
- [ ] Imports into Godot 4.7.2 with **zero errors**
- [ ] **Rendered and looked at** at both iPhone and iPad aspect, in the actual scene, next to
      existing props
- [ ] Licence CC0 with the archive's licence file committed — or original/commissioned
- [ ] Originality: not derivative of any commercial IP; prompt (if generated) recorded

## 13. Open decisions — honest status

Six of the draft's twelve are now closed by shipped work.

| # | Issue | Status |
|---|---|---|
| 1 | Bible §17 character budget 5–12× too large | **CLOSED** — §10 overrides it |
| 2 | Two conflicting palettes in the repo | **CLOSED** — shipped code values are canonical (§3) |
| 3 | `ART_BIBLE.md` vs `ART_BIBLE_DRAFT.md` | **CLOSED** — this promotion |
| 4 | "premium stylized" vs low-poly reality | **CLOSED** — §2 defines premium as coherent, not high-fidelity |
| 5 | 5 hand-drawn stickers inconsistent with 11 glyphs | **CLOSED** — all 16 now read as one set |
| 9 | Nursery camera cannot frame a 1.78 m adult | **CLOSED** — per-room aspect-adaptive framing, `ROOM_CAMERA_SYSTEM.md` |
| 10 | Ch9's 10 career themes too large an art ask | **CLOSED** — owner reduced to 4 for v1 |
| 12 | Bible lists 7 rooms, slice needs 4 | **CLOSED** — 4 built; the rest wait |
| 6 | **`shoes` is the weakest 3D object** ("two brown pebbles" cold) | **OPEN** — best candidate for the first commission |
| 7 | Room geometry harder-edged than props | **OPEN** — the §5 bevel rule is the fix; applies to all four new rooms |
| 8 | Particles forbidden, but the celebration wants one | **OPEN** — stays forbidden; revisit only with a device measurement |
| 11 | **`min_ios_version = 15.0` keeps A9 hardware in support** | **OPEN — OWNER DECISION.** Raising to 16.0 drops A9/A10, removes the weakest hardware from testing, and costs essentially nothing in 2026 audience terms. Nothing here requires it; the budgets hold either way. |

**Measurement discipline:** every performance claim in this document is either measured from the
repository or explicitly labelled a target. **Nothing has been frame-rate tested on real hardware.
Do not claim a device number that has not been run on the device.**
