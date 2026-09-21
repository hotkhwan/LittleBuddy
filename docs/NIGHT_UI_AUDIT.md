# Night UI audit — 2026-09-21

Baseline: `345339e32482c55db59dcd493d272f8e834bd26c`, branch `feature/codex-ui-polish`.
Actual Godot renders at 1334×750, using the project's 1024-high expanding UI canvas, not a raw-pixel approximation. Phone checks use 2340×1080. Evidence: `docs/shots/night/`.

## Initial visual gate

| Screen / route | Gate | Findings and production work |
|---|---|---|
| Main menu | NEEDS WORK | Core four-card layout and accepted logo are sound; live welcome subtitle covers Bunny's face. Move the subtitle, preserve cards/logo/animation. |
| Activity picker | NEEDS WORK | Flat bottle/bowl/brush pictograms clash with destination art; nine cards in four columns leave a lone last card. Stronger illustrated vocabulary, balanced grid, clearer title/scroll framing. |
| Feeding, house care close-up | NEEDS WORK | Dark full-width bands, unframed text and primitive bottle rectangle. Keep mouth target/hold behaviour; add friendly instruction/feedback surfaces and accepted bottle illustration. |
| Feeding, highchair | NEEDS WORK | Oversized visual Home/Back chrome, bespoke house and large competing type; preserve targets and real food/liquid interactions. |
| Bath / wash-face close-up | NEEDS WORK | Floating flat face and text over dark world. Frame the illustrated human baby and instructions without moving scrub targets. |
| Bedtime | NEEDS WORK | World dimming itself is appropriate; legacy mission UI and completion presentation need shared hierarchy. Do not alter sleep logic or add pressure. |
| Tidy-up | NEEDS WORK | Weak stacked-block silhouette; UI chrome varies across legacy/Free Play paths. Reuse accepted numbered blocks, keep toy-box/tidy semantics. |
| Baby Room | NEEDS WORK | Crowded chapter metadata, bulky controls, inconsistent house icon and prompt hierarchy. Preserve drop zones and effective touch bounds. |
| Free Play | NEEDS WORK | House navigation and face-clear affordances mostly sound; care overlays and pause card differ from V3's warmer panels. Preserve navigation and interaction affordances. |
| Food chooser | NEEDS WORK | V3 actual-model imagery is useful; title/header still dark/heavy and card/reward hierarchy needs refinement. Preserve model parity and 260×300 targets. |
| Dress Up | NEEDS WORK | Sound V3 split layout, but bows look like paired circles, weak selected marker and roadmap copy instead of useful child guidance. Existing four colour options only. |
| Classroom | NEEDS WORK | Teacher-safe V3 composition retained; flat flashcards, weak lesson heading, unframed question group, and bland exit/resume dialogs. Improve all visible learning states without tutor changes. |
| Settings / parent gate | PASS | Prior V3 headings, readable Thai fallbacks, scrolling content and fixed footer retained. No need for another structural redesign. |
| Shared primary navigation | PASS | Functional icon coverage exists. Preserve stable IconGlyph enum ordinals and accepted Home/Parents art. Add only missing activity pictures. |

## Routing findings

Main menu Play with Bunny routes through the activity picker into `house_world.tscn` missions; Free Play uses the same house. Legacy Baby Room / chapters 1–2 also remain playable and have a separate highchair feeding route. `scenes/activities/{feeding,bath,bedtime}.tscn` are staging/drop-zone scenes, not standalone UI owners. Polishing their geometry blindly would miss the visible HUD.

## Icon coverage

Home, Back, Close, Done, Reset, Music, Voice, Language, Mic/Speak, Next, Stars, Stickers, Parents, Play, Free Play and Dress Up already have shared assets. Weakest gaps are activity picker feeding/brush/bedtime/tidy imagery and older bespoke Home drawings. Keep quiet functional glyphs legible; use pastel shaded pictures for activity destinations. Do not introduce logo/app-icon concepts.

## 3D audit / spend decision

- Accepted numbered classroom blocks: recognizable pastel geometry, 2547 triangles and 512 texture; reuse for the weak procedural block stack at no generation cost.
- Refrigerator: plain but coherent; functioning door/shelves make speculative replacement risky. Retain.
- Classroom furniture and wardrobe: accepted models have recognizable, cohesive silhouettes. Their layout/UI, not another generation, is the current problem. Retain.
- Aliz, Bunny, bottle, teddy, toy box and fruit: retained. A transparent UI render of the accepted bottle is an adaptation, not a regeneration.
- No paid Meshy task planned unless the visual review reveals another concrete defect. Shared ledger remains the source of truth.

## Validation gates

Every changed screen requires identical-dimension before/after evidence, phone-like layout review, unchanged gameplay/node contracts and passing focused checks. Final status and test results are recorded in `HANDOFF_CODEX_TO_CLAUDE.md`; this table records the honest pre-change audit.
