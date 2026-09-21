# Visual Production V3 — 2026-09-21

Branch: `feature/codex-ui-polish`. Baseline: `2a702e1625a80d53989674584daee3f307222509` (completed 0.1.1). UI checkpoint: `7f3db14`. No version change in this sprint; the existing 0.1.1 version, centered splash and one-second parent gate are retained.

## Audit and changes

- **Classroom:** previously disconnected controls, weak question hierarchy and inconsistent flashcards. Added a cream learning shelf, compact listening/speaking state, consistent replay/picture controls, framed answer cards, selected picture state and gentler reward presentation. Aliz's face and hands remain unobstructed. Tutor/cloud/mock routing unchanged.
- **Dress Up:** replaced the scattered swatches with a preview-left / Colour Studio-right composition. Four named, glossy bow cards show selection and encouraging feedback. Existing accessory-colour logic preserved; no fictitious clothing categories added. Back retains its 280×160 effective target; cards remain at least 200×220.
- **Typography:** shared Display 48, Section 32, Body 28, Helper 22, Button 28, Count 32 roles in design-space units. Natural system-font/fallback metrics, four-pixel line spacing and word-smart wrapping. Applied to changed classroom, wardrobe, settings and food-card labels. English and Thai inspected; no new font dependency.
- **Shared chrome:** ten existing frame assets now use rounded silhouettes, restrained cream rims, softer bases and highlights. Existing theme paths and button behaviour retained. Settings gains four pastel section headings while keeping its scrolling content and fixed footer.
- **Icons:** replaced the weak flat learning icon with an authored pastel open-book icon (SVG source plus raster). Existing approved home/menu icons retained. Wardrobe bows, classroom picture art and microphone state use the same soft palette. No concept art added.
- **Food choices:** selection cards now photograph the actual kitchen mesh instead of unrelated flat symbols. Render-once previews, clearer label hierarchy and existing selected/pressed feedback; 260×300 targets retained.
- **Touch:** classroom visual controls remain compact but Talk has a 200-pixel effective target, Repeat/Picture 110 and Mute 120. Regression tests click the transparent target margins at desktop-like and phone-like sizes.

## Meshy audit and accounting

The procedural bottle was the clearest close-up weakness. Existing number blocks, table/chairs and refrigerator were reviewed and retained; their recognizable, coherent silhouettes did not justify replacement costs. Wardrobe's problem was layout, not a missing paid prop. Accepted characters, fruit, teddy and toy box were not regenerated.

Authenticated balance **3144 → 3129**; **15 credits spent**, two paid calls, no retries, no rejected generations, no paid remesh.

| Operation | Task ID | Credits | Result |
|---|---|---:|---|
| Bottle preview | `01a0c4b7-a4d7-7122-ae7d-df89a4193e09` | 5 | Accepted after geometry review |
| Bottle texture refinement | `01a0c4b8-729d-70c9-84b2-808fb844173c` | 10 | Accepted and integrated |

Runtime GLB: `game/assets/models/meshy-props/babyBottle.glb`: 2552 triangles, one material, 512×512 texture, 0.25 m high, base-centered. Milk uses a separate cream surface clipped to the curved bottle shell; the cached empty mesh is not mutated. Existing kitchen placement, carry anchors, collision/routing and bottle-to-milk state remain intact. The milk overlay adds geometry beyond the source GLB's triangle count.

Integrated through `kitchen_items.gd` and `kitchen_view.gd` into `game/scenes/house/house_world.tscn` kitchen gameplay, and through `food_chooser.gd` into its real fridge chooser. Not merely an unused download. The separate high-chair feeding prop and 2D care-overlay bottle remain unchanged to preserve their liquid/drain and interaction feedback.

Paid-call details: [shared ledger](MESHY_CREDIT_LEDGER.md). Existing Meshy helper used macOS temporary scratch outside the worktree during installation despite TMPDIR; this was detected and its three mktemp templates were corrected to honor explicit TMPDIR. No main-worktree files, secrets, native plugin, backend or production resources were changed.

## Screenshot quality gate

Each before/after pair is exactly 1334×750. Classroom also has paired 2340×1080 captures. These are actual Godot renders, not mockups.

| Screen | Before | After |
|---|---|---|
| Classroom | [before](shots/v3_before_classroom_1334x750.png) | [after](shots/v3_after_classroom_1334x750.png) |
| Answer cards | [before](shots/v3_before_answers_1334x750.png) | [after](shots/v3_after_answers_1334x750.png) |
| Dress Up | [before](shots/v3_before_dress.png) | [after](shots/v3_after_dress.png) |
| Settings top | [before](shots/settings_v3_before.png) | [after](shots/settings_v3_after.png) |
| Settings bottom/footer | [before](shots/settings_bottom_v3_before.png) | [after](shots/settings_bottom_v3_after.png) |
| Parent gate | [before](shots/settings_gate_v3_before.png) | [after](shots/settings_gate_v3_after.png) |
| Main menu | [before](shots/v3_before_menu.png) | [after](shots/v3_after_menu.png) |
| Object-choice activity | [before](shots/freeplay_chooser_v3_before.png) | [after](shots/freeplay_chooser_v3_after.png) |
| Bottle / milk close-up | [before](shots/v3_before_bottle.png) | [after](shots/v3_after_bottle.png) |

Additional evidence: `v3_after_dress_ipad.png` (1024×768), `v3_after_dress_iphone.png` (2340×1080), `v3_after_classroom_thai_*.png`, `v3_after_classroom_reward_*.png`, `v3_bottle_preview.png`, `v3_bottle_refined.png`. The main menu/settings changes are deliberately lighter than the two full composition improvements.

## Validation

Godot 4.7.2 on macOS; rendered checks use Metal. No physical-device validation and no iOS export.

- Full `res://tests/run_tests.gd`: **168 cases, zero failures**, rerun after final milk-surface refinement; includes UI layout, asset provenance/import budgets, kitchen placement, wardrobe, minigame and gameplay contracts. No script errors. Focused kitchen placement and bottle-cache regression also PASS.
- `res://tests/run_tutor_ui_tests.gd`: **16 cases, zero failures**.
- `res://tests/input_settings_harness.gd`: **INPUT SETTINGS OK**, including real taps, scrolling, sliders, footer and no-dead-overlay checks at 1334×750, 2340×1080 and 1024×768.
- `res://tests/shots_classroom_v3.gd -- after`: PASS; live deterministic lesson, answers, Thai, reward and effective-margin touch checks at both sizes.
- Dress Up rendered smoke / `menu_wow`: PASS; selection and actual preview updates, three aspect ratios.
- `res://tests/shots_freeplay.gd -- v3_after 1334x750`: PASS; feeding hunger 100→30, chooser, tidy toys and bedtime routes.
- `res://tests/shots_bottle_v3.gd`: PASS; original 0.1.1 procedural shape compared to live runtime factory at identical size.
- Godot editor import/scene validation: completed, no script parse errors. Asset model test validates actual triangles, textures, base pivot, bounds and provenance. `git diff --check` and Meshy helper shell syntax: PASS.

Known environmental noise: absent native speech framework warnings, editor ADB warning, existing headless out-of-tree/cleanup resource warnings. These are not claimed fixed and are not physical-device passes.

## Remaining limits / owner review

- Device safe areas, Thai tone-mark readability at actual device scale, audio/microphone permissions and sustained performance need owner testing on iPhone/iPad.
- Wardrobe still supports four accessory colour choices, not full garment categories. This pass does not invent gameplay.
- Classroom teaching pictures remain a consistent illustration system; kitchen choices use actual 3D objects. Broader cross-mode illustration unification remains future art work.
- Some legacy functional icons remain simple glyphs; wholesale icon replacement was intentionally avoided. Separate high-chair/2D-care bottle graphics still differ from the new kitchen prop.
- Room geometry/lighting and some procedural close-up objects remain less polished than the new UI. No additional credits spent without a demonstrated need.
- No push or merge. No further paid generation planned in this sprint.

## Exact file manifest

See [V3 changed files](VISUAL_PRODUCTION_V3_FILES.txt), including runtime assets, source art, tests and screenshot evidence. Commits separate UI composition from art integration/evidence.
