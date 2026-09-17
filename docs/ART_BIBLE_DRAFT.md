# Art Bible — Draft v1

**Status:** draft for approval. Planning only — no code, scene, asset or `project.godot` change is
implied by this document. On approval this is promoted to `docs/ART_BIBLE.md` (the filename Bible
§15 uses) and becomes the gate every new art asset passes through.

**Purpose:** lock **one** visual direction before any further art is generated, commissioned or
purchased. Bible §14 is explicit that this must happen *before* step 7 ("create/generate models"),
precisely so we do not pay to regenerate assets when scope shifts.

**Companion documents**
- `docs/CHARACTER_AGE_STAGES.md` — model families, shared rig, sockets, animation library, the
  replacement contract. Geometry and rigging live there; **look** lives here.
- `docs/CUSTOM_BABY_SPEC.md` — the Infant commission brief (as amended by `CHARACTER_AGE_STAGES.md` §10).
- `docs/ASSET_MANIFEST.md` — every shipped asset and its licence. **Every third-party asset is CC0.**
- `docs/ART_UPGRADE_REPORT.md` — honest account of what currently looks finished and what does not.
- `docs/NURSERY_SWAP_CONTRACT.md` — how the nursery can be re-skinned without breaking tests.

---

## 1. Originality — a hard requirement

**Every character, room, prop, UI element, icon, animation, colour scheme and piece of dialogue in
this game must be original.** This is a commercial children's product intended for public
distribution (Bible §19); borrowed likeness is both a legal and a credibility problem.

**Do not copy, trace, pastiche, "make it look like", or use as a direct visual reference:**
Bluey · Avatar World · Toca Boca · Sago Mini · Pixar · Disney · Peppa Pig · Cocomelon · Animal
Crossing · The Sims · any other commercial game, film or TV property.

This applies to **prompts** as much as to hand-drawn art. Do not put a brand, studio, franchise,
character or artist name into a Meshy, Midjourney, Blender-addon or any other generation prompt.
Prompts are a form of reference. **Every prompt used to generate a shipped asset must be recorded**
in `docs/ASSET_MANIFEST.md` so this is auditable later.

**Commercial products may be referenced only for abstract qualities**, never for form:
playful sandbox freedom · readable one-tap interaction · warmth · child accessibility · calm
non-punitive feedback · generous touch targets. Those are design properties, not designs.

**If you are commissioning art, this section goes in the brief.** An artist delivering something
recognisably derivative is a rejected delivery, regardless of quality.

---

## 2. The direction, in one paragraph

> **Little Buddy looks like a warm, sunlit picture book that you can walk around inside.**
> Everything is built from soft rounded volumes with no sharp corners and no hard edges. Characters
> are cute and openly expressive — large eyes, simple mouths, real emotion — but never realistic
> and never uncanny. The family home is bright, tidy, lived-in and safe, lit as if it is always
> mid-morning. Colours are pastel but **saturated**, not washed out or greyed. Every object is
> instantly recognisable as the thing it teaches, because the game's entire job is teaching its
> name. Nothing is scary, nothing is dirty, nothing is broken, and nobody is ever sad for more
> than a moment.

**The five tests any asset must pass**

| Test | Question |
|---|---|
| **Recognition** | A 4-year-old who has never seen it names it correctly, cold, with no audio. |
| **Silhouette** | It is identifiable in pure black at 64 px. |
| **Warmth** | It looks like it belongs in a loved home, not a catalogue render. |
| **Safety** | Nothing sharp, dirty, broken, dark, or capable of reading as distress. |
| **Coherence** | Placed next to the shipped Kenney props, nothing looks foreign. |

---

## 3. Colour palette

### 3.1 The reconciliation, first

There are **two conflicting palettes in the repository right now**, and they are close enough that
nobody has noticed:

| Colour | `CUSTOM_BABY_SPEC.md` §2 says | `game/scripts/progression/sticker_art.gd` actually ships |
|---|---|---|
| Warm cream | `#FFF4E0` | `#FFF6E5` |
| Soft pink | `#F8BFD1` | `#FFC1CC` |
| Mint | `#9EDCC3` | `#A8E6CF` |

A third value, `#FFF6E0`, is the sticker-book background in `sticker_book.tscn`.

**Decision: the shipped code values win.** They are what actually renders, and the WCAG contrast
test (`test_ui_contrast.gd`) was tuned against them. `CUSTOM_BABY_SPEC.md` §2 should be corrected
to match. Nothing about the direction changes — the deltas are 1–3%.

### 3.2 Core palette — LOCKED

These six plus ink are the identity of the game. Everything else is derived.

| Token | Hex | RGB (0–1) | Role |
|---|---|---|---|
| `cream` | **`#FFF6E5`** | `1.000, 0.965, 0.898` | the base note. Backgrounds, panels, walls, page fields. |
| `dustyBlue` | **`#9AC0D9`** | `0.604, 0.753, 0.851` | the cool anchor. Sky, water, calm UI, boys'/neutral clothing. |
| `softPink` | **`#FFC1CC`** | `1.000, 0.757, 0.800` | warmth and affection. Blush, hearts, rugs, celebration. |
| `mint` | **`#A8E6CF`** | `0.659, 0.902, 0.812` | "go", success, freshness. Speak button, correct feedback, plants. |
| `peach` | **`#FFD3B6`** | `1.000, 0.827, 0.714` | skin-adjacent warmth. Wood, bread, cushions, sunlight. |
| `lavender` | **`#D6C7F0`** | `0.839, 0.780, 0.941` | the gentle accent. Bedtime, night, rest, sleep. |
| `ink` | **`#59422B`** | `0.349, 0.259, 0.169` | **the only "dark".** Outlines, text, eyes, shadow tint. A warm brown, never black. |

**`#000000` is banned everywhere in this game** — text, outlines, eyes, UI, shadow colour. Pure
black in a pastel scene reads as a hole. Use `ink`, or `ink` lightened.

### 3.3 Tints and shades — derived, not invented

Each core colour gets exactly three steps. Do not author intermediate values ad hoc.

| Token | Light (mix 45% `cream`) | Base | Deep (mix 22% `ink`) |
|---|---|---|---|
| dustyBlue | `#C4DBE9` | `#9AC0D9` | `#8AA6B2` |
| softPink | `#FFE1E6` | `#FFC1CC` | `#DFA4A9` |
| mint | `#CDEFE1` | `#A8E6CF` | `#94BFA9` |
| peach | `#FFE5D3` | `#FFD3B6` | `#DFB295` |
| lavender | `#E9DFF6` | `#D6C7F0` | `#B9A9C4` |
| cream | `#FFFCF5` | `#FFF6E5` | `#DFD0B8` |

"Deep" variants are for the shaded side of a form and for pressed UI states. **Never darken by
reducing value alone** — always mix toward `ink` so shadows stay warm.

### 3.4 Semantic roles — LOCKED

| Role | Colour | Note |
|---|---|---|
| Screen / panel background | `cream` `#FFF6E5` | |
| Primary text | `ink` `#59422B` | passes WCAG AA on `cream` |
| Secondary text | `#8A7358` (`ink` + 32% `cream`) | labels, captions only |
| Star — earned | **`#FFC73D`** | the shipped gold; the single most important colour in the game |
| Star — current/next | `#FFE199` | |
| Star — not yet earned | `#E8DCC8` | a *ghost*, never grey, never an "empty" or failure state |
| Success / "go" | `mint` `#A8E6CF` | |
| Speak / microphone | `mint` `#A8E6CF` | |
| Try again / retry | `peach` `#FFD3B6` | warm and inviting. **Never red.** |
| Locked sticker fill | `#D9D3E2` | shipped value |
| Locked sticker outline | `#C8C0D5` | shipped value |
| Parent-settings chrome | `lavender` `#D6C7F0` | visually marks "this area is for a grown-up" |

**Banned as UI colours:** red (`#E03` and anything near it), pure black, pure white as a large
field, neon/fluorescent anything, and any low-saturation grey. Per `CLAUDE.md` Child UX: no red X,
no failure colour, ever.

### 3.5 Environment palette — already shipped, now formalised

From `game/scenes/nursery/nursery_props.gd`. These are the retint targets applied to the CC0
Kenney furniture by material name and are the reference for all future rooms.

| Material role | Hex | Note |
|---|---|---|
| `wood` | `#DEBD94` | pale warm nursery wood — all furniture frames |
| `woodDark` | `#BA9670` | shadowed wood, box interiors |
| `carpet` | `#E6B0B5` | soft pink rug field |
| `carpetDarker` | `#CC8F99` | dusty rose rug border |
| `carpetWhite` | `#FAF5ED` | warm off-white bedding — **never pure white** |
| `metal` | `#BDD4E6` | dusty blue stands in for steel. There is no real metal in this game. |
| `metalDark` | `#94B3D1` | |
| `lamp` | `#FFF2CC` | warm cream lampshade |
| `plant` | `#99C99E` | soft sage. **Not neon green.** |
| `fur` | `#E8C799` | teddy / soft toys |

Wall and architecture colours currently in `nursery_props.tscn`, kept: wall field `#F0E0C7`,
wainscot `#ADC9E0`, trim `#FAF5ED`, floor `#D6BA96`, window sky `#B8DBED`, bunting
`#EDADB8` / `#ADCFE6` / `#FAE8C2` / `#B5D9B8`.

### 3.6 Skin tones

The Infant currently ships one tone, `#FFDEBD`. **Ship at least three from the first release**, so
the game is not implicitly about one kind of family. All three are warm-biased so they sit inside
the palette.

| Token | Hex | Cheek blush | Brow / hair base |
|---|---|---|---|
| `skinLight` | `#FFDEBD` *(shipped)* | `#FFB8B3` | `#B88C6B` |
| `skinMid` | `#E8B98C` | `#D69A82` | `#8A5F3C` |
| `skinDeep` | `#B07B52` | `#9A6247` | `#4E3323` |

Judgement call: skin tone is a **material slot swap on one mesh**, not three meshes. Zero
additional triangle or texture cost. Mom, Dad and Little Buddy must default to a consistent family
combination.

---

## 4. Little Buddy — character style

Proportions per family are in `CHARACTER_AGE_STAGES.md` §2. This section is the **look**.

### 4.1 Form language

- **Everything is a rounded volume.** Head = slightly flattened sphere. Torso = rounded barrel.
  Limbs = capsules with soft spherical ends. No flat planes on the body, no creases, no hard edges.
- **No neck on the Infant** (head sits on the shoulders); a short soft neck from Toddler up.
- **No chin definition** below the Child family. No jawline, no cheekbones, no clavicle relief.
- **No visible teeth, ever.** Not in `happy`, not in `celebrate`, not in `surprised`.
- **No individual fingers below the Teen family.** Hands are soft mitts with a suggested thumb.
  Teen and Adult may have a single grouped finger mass — still no separated digits.
- **Feet are rounded and slightly oversized**, roughly 1.15× naturalistic. Reads as stable and
  toy-like.
- **Silhouette check:** in pure black at 64 px the head, the two arms and the two legs must be
  separately readable. Bible §16's "no fused arms/legs" is a hard acceptance criterion.

### 4.2 Face

The face carries the entire emotional load. It is **flat-ish and graphic**, not sculpted.

| Feature | Spec |
|---|---|
| **Eyes** | Large. Infant: eye width ≈ **22%** of head width, set **below** the vertical midline and wide apart. Ratio reduces to ~14% by the Adult family. Shape: soft vertical oval, never round buttons, never almond. |
| **Iris/pupil** | A single solid `#382924` mass. **No separate iris ring, no sclera colour variation, no eyelashes below the Teen family.** Simplicity is what keeps it out of the uncanny valley. |
| **Catchlight** | Exactly **one** white circle, upper-left of each eye, ~18% of eye width, mirrored on both eyes. A second small highlight is permitted lower-right at ≤ 8%. This is the single highest-value detail on the character — it is what makes the eyes look alive. |
| **Whites** | Very little visible sclera, and `#FAF5ED`, not `#FFFFFF`. |
| **Brows** | Short soft strokes, colour = hair base, sitting **well above** the eyes with a clear gap. They do 60% of the emotional work — drive them from `browsSad` / `browsSurprised`. |
| **Nose** | A tiny soft rounded bump, skin-coloured `#FFD1AD`, no nostrils, no shadow. Barely there. |
| **Mouth** | A single filled shape in `#9E4F4D`, swapped/blended between smile, open and sad. **No lips, no lip line, no teeth, no tongue.** |
| **Blush** | Two soft circles, `cheeksBlush`, ~25% of head width, low on the cheeks, heavily feathered. Always at least 0.3 weight — it is part of the resting face. |
| **Ears** | Small, simple, no inner detail. Visible from the Toddler family up; barely visible on the Infant. |

**Uncanny-valley guard rails.** The failure mode is not "too realistic", it is **detail
mismatch** — realistic eyes on a simple face, or a realistic mouth on a smooth head. Rule: the
face must be **uniformly simple**. If one feature gets more detail, all of them do, and they do
not. Additional bans: no wrinkles, no skin pores or texture, no subsurface scattering, no
specular highlight on skin, no asymmetry, no eye tracking that follows the cursor, no idle
micro-expressions beyond the blink.

**Expression range is deliberately narrow.** Content, happy, excited, sleepy, hungry, surprised.
There is no angry, no crying, no fear, no disgust. `hungry` is *gently* downturned — the existing
brief's wording is exactly right: **"sad, never distressed."**

> Historical note worth keeping: `ART_UPGRADE_REPORT.md` records that the baby's first smile
> shipped with inverted Z-rotation signs, producing a perfect **frown** on a character whose
> resting state is meant to be content — and it survived three render passes. **Always render and
> look at the face.** Bible §22 says the same thing.

### 4.3 Hair

- **Infant:** a single soft tuft, 1 curl, or nothing. Modelled as geometry, not a texture card.
- **Toddler → Adult:** hair is a **separate mesh** sharing the family atlas, modelled as 2–5
  solid rounded masses. **No hair cards, no alpha, no transparency, no strands.**
- Silhouette is the whole point — hair is the fastest way to tell Mom from Dad from Little Buddy
  at 64 px.
- Colours derive from the skin-tone table's "brow / hair base", ±1 shade.
- Ship **3 hairstyles per family** at launch; more are outfit-slot unlocks later.

### 4.4 Clothing look

Construction is in `CHARACTER_AGE_STAGES.md` §7. Visually:

- **Flat colour fields with a single darker accent.** No patterns below 2 cm of screen size, no
  logos, no text on clothing, no stripes narrower than ~4 px at reference resolution.
- Soft, slightly oversized fit. No tailoring, no belts, no buckles, no zips, no buttons smaller
  than a rounded dot.
- **Gender-neutral by default.** Ship a mixed set; do not make pink-for-girls / blue-for-boys the
  default pairing.
- Colour comes from §3.2 core tints. A garment may use one core colour plus `cream` plus one
  accent. Three colours maximum per garment.
- Infant: onesie in one core colour + `#FAF7F0` nappy, baked into the body mesh.

---

## 5. Parents and adults

Mom and Dad appear from Ch1 L1 and recur through the whole game. Detail in
`CHARACTER_AGE_STAGES.md` §1 and §2 — **they share the Adult family with the grown-up Little
Buddy**: one base mesh, one rig, one animation library, three variants.

| Property | Spec |
|---|---|
| Proportion | **1 : 6.5** head-to-height, deliberately *not* the realistic 1 : 7.5 |
| Height | Mom `1.65 m`, Dad `1.78 m` |
| Face | **Exactly the same system as Little Buddy** — same eye construction, same single catchlight, same mouth shape set, same blush. Larger heads reduced proportionally; nothing is added. |
| Differentiation | Hair silhouette, height, clothing colour, and shoulder width. **Not** by facial detail, and **not** by stereotyped markers (no moustache-for-dad, no apron-for-mom). |
| Expression | Warm, attentive, frequently looking *at* Little Buddy. Parents are never stressed, never scolding, never absent. |
| Pregnancy (Ch1 L3–L5) | `bellyRound` blend shape + a maternity dress. Nothing else changes. Consistent with Bible §3: no medical detail, no distress. |
| Budget | ≤ 4,000 tris incl. hair and clothing, 1 × 512² atlas, 1–2 materials |

**Adults must never dominate the frame.** They are supporting characters; Little Buddy is the
subject. Compose and light so the child is the focal point even when a parent is present.

---

## 6. Home architecture

The Bible keeps the first public version in and around the family home (§7): Living Room, Kitchen,
Bedroom, Bathroom, Nursery, Garden (later), Study Corner.

| Property | Spec |
|---|---|
| Camera | Fixed or lightly-constrained **three-quarter** view, looking slightly down. Never top-down (kills faces), never first-person, never free-orbit. Current nursery reference: `y = 0.95`, `z = 2.075`, pitch −18.5°, **FOV 50°**. |
| Room construction | **Three walls, open fourth wall** toward the camera — the doll's-house convention. Already how the nursery is built. |
| Ceilings | None. Open to a soft `cream` void. |
| Wall height | ~`2.6 m` in-world, but the visible band is only ~`1.6 m` at this camera. Detail above that line is wasted. |
| Wall treatment | Flat colour field + **wainscot and rail** around all three walls (shipped and working). Adds scale reference and stops walls reading as empty planes. |
| Windows | Every room gets one. A window is the cheapest warmth in the scene: a flat `#B8DBED` sky plane, a soft rounded frame, no glass, no transparency, no reflection. |
| Doors | Rounded-top, no visible hinges, handle as a soft sphere. Openable doors are a mechanic (Bible §6) — model them as a single mesh rotating on a `DoorPivot` at the hinge edge. |
| Floors | Warm wood `#D6BA96`, plus one rug per room for colour and to define the play area. |
| Corners | **Every architectural edge has a visible bevel/fillet, ~2 cm in-world.** A hard 90° corner is the single strongest "this is a prototype" signal. |
| Clutter | Tidy but lived-in: a book left out, a toy on the rug, a plant, bunting. **Never messy, never dirty, never damaged.** |

> **Known weakness, from `ART_UPGRADE_REPORT.md`:** the current nursery's silhouettes are still
> harder-edged than the props and the baby. Retinting fixed the palette completely; it cannot fix
> geometry. The bevel rule above is the fix, and it is why replacement furniture (e.g. the pending
> Tiny Treats "Playful Bedroom" purchase) must be checked for fillets, not just for colour.

---

## 7. Furniture, props and food

### 7.1 Form rules

- **Rounded low-poly.** Chamfered corners, generous fillets, no sharp geometry, no thin shells.
- **No object thinner than ~1.5 cm in-world.** Thin geometry aliases badly on a retina phone
  screen with MSAA off (`msaa_3d = 0` in `project.godot`).
- **Reduce to the minimum recognisable form.** A spoon is a bowl and a handle. A book is a slab
  and a spine. Detail that does not aid recognition is cost with no return.
- **One object teaches one word.** Two nouns must never share a shape. This is the rule that
  caught `bathToy` (a yellow sphere) vs `ball` (a red sphere) and the five identical cubes
  standing in for shirts, pants and pyjamas — see `ART_UPGRADE_REPORT.md`.
- **Pivot at the base centre** for anything that stands on a surface, at the **grip point** for
  anything held. Kenney furniture pivots are corners and had to be re-anchored; author ours
  correctly from the start.
- Scale reference: the shipped interactable prop size is `VISUAL_SIZE_M = 0.16` on the longest
  axis (`object_spawner.gd`), which is what makes a drag target comfortable for a small hand.

### 7.2 Food

Food is the highest-frequency vocabulary category in the game and the easiest to get wrong.

- **Whole, clean, undamaged, appetising.** No bites taken, no bruises, no cut cross-sections
  showing seeds or flesh.
- Saturated but palette-consistent: apple `#E8737D` not fire-engine red, banana `#FFD96B` not
  neon yellow.
- **Colour is a primary teaching channel** — Ch4 L17 is literally "Colors". Food colour must be
  unambiguous and must match its `colorWord` in the content JSON. (`soap` shipped with a hex that
  rendered **white** while its `colorWord` said "pink". Content data and art must be checked
  against each other.)
- Containers read as containers: a cup has visible interior depth, a bowl is not a hemisphere.
  The shipped bowl's rim is visibly hexagonal and `water` reads as "blue cup" in isolation — both
  are on the fix list.

### 7.3 Reuse over novelty

Bible §7 makes every room's objects reusable. **Build a prop kit, not a set of props.** A soft
rounded cushion mesh recoloured is a pillow, a seat pad, a floor cushion and a toy. Target:
**≤ 60 unique prop meshes** covering the whole home, with colour and scale doing the rest.

---

## 8. Materials and texture style

| Property | Spec |
|---|---|
| Shading | **Flat-shaded stylised PBR** via `StandardMaterial3D`. Albedo carries essentially everything. |
| Roughness | **0.85–1.0.** Nothing in this game is shiny. |
| Metallic | **0.0 everywhere.** There is no metal; "metal" is the dusty-blue `#BDD4E6` convention. |
| Specular | ≤ 0.15. Current light uses `light_specular = 0.1` — keep it. |
| Normal maps | **None.** |
| Emission | **None**, except the lamp shade if a night scene needs it, and then only at low energy. |
| Transparency / alpha blend | **None.** No alpha-tested foliage, no hair cards, no glass, no soft particles. Alpha is the most common mobile performance trap and we do not need it. |
| Subsurface scattering | **None.** |
| Textures | One shared atlas per pack/family. **512×512 is the standard.** The Kenney packs already ship exactly this and it looks correct. |
| Texture content | Flat colour regions and gentle gradients only. **No painted detail, no baked AO, no baked shadow, no noise, no grunge, no wear, no dirt.** |
| Texture filtering | Linear + mipmaps. Compressed with ETC2/ASTC (`import_etc2_astc=true`, already set). |
| Vertex colour | Permitted and encouraged as a greyscale **shade** multiplier, as `object_spawner.gd` already does. Cheaper than texture space. |
| UVs | Non-overlapping, no stretching, packed into the shared atlas. |
| Materials per object | **1.** Two only where a genuinely different surface is needed (e.g. an unshaded eye catchlight). Never three. |

**Why no baked AO or baked shadow:** this scene has exactly one directional light and a soft warm
ambient. Baked darkening fights it and produces the grubby look that separates an amateur mobile
scene from a polished one. Let the real light do the shading.

---

## 9. Lighting

| Property | Spec |
|---|---|
| Lights | **Exactly one `DirectionalLight3D` per scene.** Non-negotiable — it is the current budget and the whole look is built on it. |
| Direction | High, from the front-upper-left, angled toward the camera's left. Current transform: `Basis(0.8296, -0.4356, 0.3494 / 0, 0.6248, 0.7808 / -0.5583, -0.6479, 0.5185)`, position `(0, 3, 1.5)`. |
| Energy | `0.72` |
| Specular | `0.1` |
| Shadows | **On.** `shadow_enabled = true`, `shadow_bias = 0.02`, `shadow_normal_bias = 0.8`, `shadow_opacity = 0.5`, `shadow_blur = 1.0`, `soft_shadow_filter_quality = 0`. Soft, warm, half-strength. Shadows are what ground objects on the floor — the "before" screenshots in `ART_UPGRADE_REPORT.md` show exactly how floaty the scene looks without them. |
| Shadow colour | Never neutral grey. `shadow_opacity = 0.5` over a warm ambient yields a warm shadow — keep it that way. |
| Ambient | `ambient_light_source = 2` (colour), `#F5EDE6` at energy `0.9`. This high warm fill is what prevents the dark side of a form going muddy with only one light. |
| Background | Flat colour, `#D9E6F2` (nursery) or per-room equivalent. No skybox, no HDRI, no reflection probe. |
| Time of day | **Permanently mid-morning.** No day/night cycle in the main flow. A bedtime level may tint the ambient toward `lavender` `#D6C7F0` and reduce energy to ~0.45 — it must stay clearly readable, never actually dark. |

**Forbidden, and not negotiable at any point on this roadmap:** GI/SDFGI/VoxelGI, SSAO, SSIL,
SSR, glow/bloom, volumetric fog, depth of field, colour-correction/tonemapping post, screen-space
effects of any kind, and `RigidBody3D` physics. The Mobile renderer either does not support these
or they cost more than the entire rest of the frame.

**Particles:** currently forbidden. Flagged for a future decision — the celebration moment is the
one place a small `CPUParticles3D` burst would genuinely earn its cost. It is **not** approved
here; it needs a device measurement first. The existing celebration effect is a `Control`-layer
tween and should stay that way until then.

---

## 10. UI

The UI system is largely built and working. This section locks it rather than redesigning it.

| Property | Spec |
|---|---|
| Panels & buttons | Kenney UI Pack 2.0 nine-slices (CC0), re-paletted to **six pastel colourways** at two corner scales. Already shipped. |
| Corners | Generously rounded. Nothing square, nothing with a 1 px border. |
| Elevation | A soft warm drop shadow, ~4 px offset, ~25% opacity, `ink`-tinted. No hard borders. |
| **Touch targets** | **240 × 240 px minimum** at the 1366×1024 reference resolution for any primary child-facing control. Already the shipped size. **Never shrink this.** |
| Safe area | Every full-screen layer must respect the SafeArea. `Celebration` shipped ignoring it and drew a sticker card over the baby's face — see `ART_UPGRADE_REPORT.md`. |
| Text | Rounded, friendly, high x-height sans. Minimum **27 pt** at reference for child-facing text; 25 pt for secondary labels only. `ink` on `cream`. |
| Text load | Minimal. The player is a pre-reader. Icons and voice first; text is a parent-facing affordance. |
| Contrast | Enforced by `test_ui_contrast.gd` using true WCAG relative luminance. Every new colour pairing must pass it, **including hover and pressed states** — `font_hover_pressed_color` silently fell through to near-white and was only caught by that test. Touch on iOS synthesises hover, so hover states are real and reachable. |
| Motion | Ease-out, 150–250 ms, slight overshoot on appearance. Nothing snaps. Nothing flashes. |
| Never | red · X marks · percentages · pronunciation scores · timers · countdowns · progress bars that can go down · modal failure dialogs · external links · purchase prompts |

### 10.1 Icons

- One family: **Nieobie Game Icon Pack** (CC0), ~18 of 815 shipped.
- Consistent stroke weight, rounded caps and joins, single colour, tinted via `modulate`.
- Watch the `fill="currentColor"` trap — it resolves to black and silently breaks tinting. Ours
  are rewritten to `#ffffff` so `modulate` works.
- **If no icon in the pack means the right thing, commission one — do not substitute an
  approximate.** The sticker-book button currently uses a treasure chest because no sticker-sheet
  glyph exists. That is a compromise, and it is logged as one.

### 10.2 Stars

The single most emotionally loaded element in the game (Bible §5).

| State | Colour | Treatment |
|---|---|---|
| Earned | `#FFC73D` | full opacity, soft warm glow-free halo, gentle scale-in with overshoot |
| Current / next | `#FFE199` | pulsing at ~0.6 Hz, subtle |
| Not yet earned | `#E8DCC8` | outline only, warm. **A ghost, not an empty slot.** |

Five-point star, **rounded tips**, one shared mesh/glyph at every size so they read as one family.
Never grey. Never crossed out. Never removed once earned (Bible §5.1: never subtract stars).

### 10.3 Stickers

16 shipped: **11 real Nieobie glyphs + 5 hand-drawn polygons** (banana, soap, towel, toothbrush,
pillow). The five are visibly hand-made next to the eleven and the toothbrush reads ambiguously.

**Decision: all 16 stickers must come from one visual family.** Since no matching glyph exists in
the 815-icon pack (a pear is not a banana, a paint brush is not a toothbrush), the five need
drawn or commissioned art matching the Nieobie stroke weight and corner radius. This is the
highest-value small art commission in the backlog — stickers are the reward, and a reward that
looks unfinished undercuts the whole loop.

Sticker card spec: `cream` field, 12 px `ink`-at-20% rounded border, glyph at ~70% of the card,
one core palette colour as the backing wash.

> Implementation trap worth carrying forward: `_draw()` only **records** commands; the renderer
> binds textures later in the frame. A glyph held in nothing but a local dropped to zero refs and
> every sticker painted as a solid coloured square. Keep glyph resources referenced.

### 10.4 App icon

Already authored in-house, originally, at 1024×1024, deliberately carrying zero third-party
licence surface. Rules for any future iteration:

- **One subject, centred, no text.** Reads at **60 px** and at 1024 px.
- **Opaque** — no transparency; iOS masks it anyway.
- Nothing within 8% of the edge.
- Warm background from the core palette, subject in a contrasting core colour.
- The subject should be the **character**, not an object, once a final Little Buddy model exists.
  A face is more memorable on a home screen than a bottle.
- Must be checked on a **real home screen over a busy wallpaper** before release — still an open
  item in `ART_UPGRADE_REPORT.md`.

---

## 11. Style-coherence rule for mixed sources

The game ships CC0 Kenney props next to procedural geometry next to (eventually) commissioned
characters. Three sources, one look. The rule:

**Kenney's flat-shaded rounded low-poly is the house style.** New art matches it — comparable
polygon density, comparable rounding radius, flat albedo, one 512² atlas. A commissioned character
that is visibly smoother or more detailed than the furniture around it makes the *furniture* look
broken, which is a much worse outcome than a slightly simpler character.

**Acceptance test:** render the new asset in the nursery next to the bed, the rug and the teddy.
If your eye goes to it because it looks *different* rather than because it is the subject, it
fails.

**Licensing is part of art direction here.** Every third-party asset must be **CC0** with the
licence file read from the downloaded archive, not from a website summary, and committed
alongside the asset. **Quaternius is excluded** — its licence changed to QAL v1.0 on 2026-08-28
and §3(a) forbids redistributing assets "regardless of how much the Assets have been modified".
CC-BY is excluded too: a perpetual attribution obligation on a shipped children's app is not worth
it when a pure-CC0 path exists.

---

## 12. Rooms — a per-room mood note

One line each so rooms are distinguishable without inventing five palettes.

| Room | Dominant | Accent | Feeling |
|---|---|---|---|
| Nursery | `cream` + `softPink` | `dustyBlue` | gentle, quiet, safe |
| Bedroom | `cream` + `lavender` | `dustyBlue` | restful, dim-but-readable |
| Kitchen | `cream` + `peach` | `mint` | bright, busy, warm |
| Living Room | `cream` + `peach` | `softPink` | sociable, comfortable |
| Bathroom | `cream` + `dustyBlue` | `mint` | fresh, clean, splashy |
| Study Corner | `cream` + `mint` | `lavender` | focused, tidy |
| Garden | `mint` + `dustyBlue` | `peach` | open, sunny, alive |

Every room keeps `cream` as its base. The accent shifts. That is the whole system.

---

## 13. Technical budgets

### 13.1 Measured baseline — the numbers everything else is checked against

| Metric | Current value |
|---|---|
| Whole scene | **~14,000 triangles, 158 draw calls** |
| **All 18 shipped third-party GLBs, combined** | **2,996 triangles** |
| Largest single shipped model | `ball-red.glb`, **572 tris** |
| Kenney `bedSingle` | **214 tris** |
| Kenney `bookcaseClosedWide` | **372 tris** |
| Kenney `utensil-spoon` | **46 tris** |
| Lights | exactly 1 × `DirectionalLight3D`, soft shadows on |
| Renderer | Godot **4.7.2**, **Mobile** |
| MSAA | off (`msaa_3d = 0`) |
| Shadow filter | lowest (`soft_shadow_filter_quality = 0`) |
| Reference resolution | 1366 × 1024, sensor-landscape |
| Total shipped assets | 984 KB |

### 13.2 Recommended budgets — and where they disagree with Bible §17

| Class | **Bible §17** | **Recommended** | Measured reality |
|---|---|---|---|
| Main character | 15k–35k | **2,500–4,000** | whole scene is 14k |
| Secondary character | 10k–25k | **2,000–3,000** | — |
| Large furniture | 2k–8k | **300–1,500** (cap 2,000) | shipped bed = 214, bookcase = 372 |
| Hero prop | 1k–6k | **200–1,000** | shipped teddy = 522, ball = 572 |
| Small prop | 300–3k | **40–400** | shipped spoon = 46, glass = 44, apple = 136 |
| Character texture | 1024–2048 | **1 × 512²** per family (all variants + clothing); 1024² only for the Adult family if UV space truly demands | Kenney packs use one 512² and look right |
| Prop texture | 512–1024 | **one shared 512² atlas per pack** | already true |
| Materials per object | 1–3 | **1** (2 max on characters) | — |

**Yes — the Bible's "main character 15k–35k triangles" is far too generous for this game.**
It is **5–12× over**. At 35k a single character would be 2.5× the entire current world, and it is
more than ten times the combined geometry of every third-party model we ship. The number reads
like a general mobile-3D rule of thumb imported wholesale rather than derived from this project's
measured scene, its one-light flat-shaded style, or its iOS 15 device floor.

More importantly, **spending the budget there would actively hurt the look.** In a flat-shaded,
normal-map-free, one-light style, geometry past a few thousand triangles buys almost nothing
visible — the silhouette and the face are already resolved — while pulling the character out of
stylistic alignment with the 200–500-triangle furniture around it (§11).

Bible §17's remaining guidance — environment atlases preferred, materials kept low, no 4K
textures for ordinary props — is correct and is retained.

### 13.3 Frame budget

| Metric | Target | Hard ceiling |
|---|---|---|
| Triangles, typical room | ~18,000 | **30,000** |
| Triangles, worst case (Ch1 wedding: Little Buddy + Mom + Dad + furnished room) | ~26,000 | **30,000** |
| Draw calls | ~170 | **220** |
| Directional lights | 1 | **1** |
| Other lights | 0 | **0** |
| Unique materials in frame | ~25 | **40** |
| Texture memory | ~8 MB | **24 MB** |
| Total app assets | — | **40 MB** |
| Transparent/alpha-blended surfaces | 0 | **0** |

Draw calls, not triangles, are the metric to watch. 158 already with a sparse room. Atlas
aggressively, merge static geometry, and use `MultiMesh` for repeated props.

### 13.4 LOD decision: **no LODs**

Argued, not assumed.

**Reasons not to:**
1. At most 3–4 characters on screen, each ≤ 5,000 tris. The largest realistic frame is ~26k
   triangles — a GPU from 2015 does not care.
2. The pressure in this project is **draw calls and overdraw**, not vertex throughput. LODs reduce
   vertices and change nothing about draw calls.
3. The camera distance range is tiny. It is a fixed three-quarter view in a small room; there is
   no far plane full of distant geometry to simplify.
4. LOD popping on a screen a 4-year-old is holding 30 cm from their face is a visible defect, and
   at these triangle counts the switch distances would be short enough to be obvious.
5. Godot's automatic import LOD costs mesh memory and import time for savings we do not need.

**What we do instead:**
- **`VisibleOnScreenNotifier3D` / visibility ranges** to cull whole rooms that are not the active one.
- **Static merging** of room shells and fixed furniture into a single mesh per room.
- **`MultiMesh`** for repeated identical props (books, blocks, bunting).
- **One atlas per pack**, so the whole room shares a material.
- A **hard draw-call ceiling of 220** treated as a build check, not a guideline.

**Revisit if and only if** a device profile on the oldest supported hardware shows vertex-stage
cost above ~20% of frame time. Do not add LODs speculatively.

### 13.5 Performance target

`export_presets.cfg` sets `min_ios_version = "15.0"` and Universal iPhone + iPad
(`UIDeviceFamily = 1,2`). iOS 15 admits devices back to the **A9** generation — iPhone 6s,
iPhone SE (1st gen), iPad Air 2, iPad mini 4.

| Tier | Devices | Target |
|---|---|---|
| **Primary** | A12 and newer — iPhone XR+, iPad (8th gen)+, all iPad Air/Pro since 2018 | **60 fps locked**, shadows on |
| **Minimum** | A10–A11 — iPhone 7 / 8 / X | **60 fps**, shadows on; fall back to shadows off if measured under |
| **Floor** | A9 — iPhone 6s, SE 1, iPad Air 2, iPad mini 4 | **30 fps**, shadows off, acceptable |

**Flagged decision for the owner:** raising `min_ios_version` to **16.0** drops the A9 and A10
tiers entirely (iOS 16 requires iPhone 8 / A11+), removes the weakest hardware from the support
matrix, and costs essentially nothing in 2026 audience terms. Nothing in this art bible requires
it — the budgets above hold at 30 fps on an A9 — but it would remove a whole class of testing.
Product decision, not an art one.

**Measurement discipline:** every performance claim in this document is either measured from the
repository or explicitly labelled a target. Bible §22 and `CLAUDE.md` both require it, and
`ART_UPGRADE_REPORT.md` is honest that *nothing* has been frame-rate tested on real hardware yet.
**Do not claim a device number that has not been run on the device.**

---

## 14. Production pipeline and acceptance

### 14.1 Order of work (Bible §14)

Story lock → character-age lock → room list → interaction list → vocabulary objects → **this
document approved** → generate/model → texture → rig → animate → lighting polish. **Do not start
step 7 until this document is signed off.**

### 14.2 Generation rules (Meshy, or any generator)

Bible §16 permits generation after art direction is locked. It is a **concepting and
blockout** tool, not a delivery tool.

- Never ship raw generator output. Every asset is retopologised or rebuilt.
- **Never put a brand, studio, franchise or artist name in a prompt** (§1). Record every prompt in
  `ASSET_MANIFEST.md`.
- Per-asset checklist before it enters the repo: silhouette · topology · UVs · texture ·
  material count reduced to 1 · scale normalised to metres · pivot corrected · triangle count
  inside §13.2 · imports into Godot **4.7.2** with zero errors · tested on a physical device.
- Characters: neutral **A-pose**, visible hands, **separated limbs, no fused arms or legs**,
  clean proportions, on `LB_Rig_v1`.
- Export **GLB**, and always keep the editable source.

### 14.3 Acceptance checklist — every new asset

- [ ] Passes the five tests in §2 (recognition · silhouette · warmth · safety · coherence)
- [ ] Palette drawn **only** from §3; no invented colours; no pure black; no red
- [ ] Inside the §13.2 triangle, texture and material budget
- [ ] 1 material (2 max on a character); 512² atlas; no normal map, no alpha, no emission
- [ ] Metres, pivot correct, transforms applied, no residual node scale
- [ ] Imports into Godot 4.7.2 with **zero errors**
- [ ] **Rendered and looked at** at both iPhone and iPad aspect, in the actual scene, next to
      existing props (Bible §22)
- [ ] Licence: CC0 with the licence file read from the archive and committed — or original/commissioned
- [ ] Originality: not derivative of any commercial IP; prompt (if generated) recorded
- [ ] Characters only: satisfies the full contract in `CHARACTER_AGE_STAGES.md` §9

---

## 15. Flagged inconsistencies and open decisions

| # | Issue | Suggested resolution |
|---|---|---|
| 1 | **Bible §17 main-character budget is 5–12× too large** for this scene | adopt §13.2; see the argument in §13.2 |
| 2 | **Two conflicting palettes in the repo** — `CUSTOM_BABY_SPEC.md` §2 (`#FFF4E0`/`#F8BFD1`/`#9EDCC3`) vs shipped code (`#FFF6E5`/`#FFC1CC`/`#A8E6CF`), plus a third cream `#FFF6E0` in `sticker_book.tscn` | shipped code values are canonical (§3.1); correct `CUSTOM_BABY_SPEC.md` §2 and the sticker-book background |
| 3 | **Bible §15 names `docs/ART_BIBLE.md`; Bible §21 asks for `docs/ART_BIBLE_DRAFT.md`** | this file is the draft; promote to `ART_BIBLE.md` on approval |
| 4 | **Bible §15 asks for "premium stylized 3D" while §17's budgets and the one-light Mobile-renderer constraint describe a flat-shaded low-poly game** | not actually a conflict once stated: "premium" here means *coherent, warm, well-lit and well-composed*, not *high-fidelity*. §2 is the operative definition. |
| 5 | **5 of 16 stickers are hand-drawn and visibly inconsistent** with the other 11 | commission 5 matching glyphs — highest-value small art job in the backlog (§10.3) |
| 6 | **`shoes` is the weakest 3D object** ("two brown pebbles" cold), after 3 shape revisions and 8 angles | rebuild as a worn, rigged clothing item (`CHARACTER_AGE_STAGES.md` §7) and separately as a paired prop with a visible sole and opening |
| 7 | **Nursery geometry is harder-edged than the props** — retinting fixed colour, not form | the 2 cm bevel rule (§6); check any replacement furniture for fillets, not just palette |
| 8 | **Particles are forbidden but the celebration moment wants one** | keep forbidden; revisit only with a device measurement. Current `Control`-layer tween stays. |
| 9 | **The nursery camera cannot frame a 1.78 m adult**, and Ch1 is entirely adults | per-room camera rigs — belongs to the level/architecture doc; heights are in `CHARACTER_AGE_STAGES.md` §2 |
| 10 | **Ch9's 10 career themes** are the largest art ask in the game for the shortest content | suggest 4 careers at launch, rest in Free Life mode — story/level decision |
| 11 | **`min_ios_version = 15.0`** keeps A9 hardware in the support matrix | owner decision to raise to 16.0 (§13.5); art budgets hold either way |
| 12 | **Bible §7 lists 7 rooms; Bible §20 Phase B's vertical slice needs 4** (bedroom, bathroom, kitchen, play area) | build the 4 the slice needs first; the other 3 wait for Phase D |

**Deliberately left to the parallel design docs:** chapter/level beats, star conditions and unlock
logic (story/level doc); which object each activity uses, the interaction matrix and the English
vocabulary attached to each prop (interaction/vocabulary doc); the character controller,
`NavigationAgent3D`, `AnimationTree` state machine, scene composition and save-schema extensions
(architecture doc). Model families, rigging, sockets, animation clips and the character
replacement contract are in `docs/CHARACTER_AGE_STAGES.md`, not here.
