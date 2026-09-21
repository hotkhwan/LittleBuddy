# Visual completeness QA

Audit base: `7b42c6ec31a335992a16bd321aa0b65287b4fd2c`. Scope was every shipped route plus intermediate, feedback and exit states. The pass intentionally changed only one verified defect: classroom Thai/transcript labels now use the tested multilingual font chain instead of implicit OS fallback.

| Screen | Visual status | Missing icons | Typography issues | Layout issues | Fixed? | Remaining? | Screenshot evidence |
|---|---|---|---|---|---|---|---|
| Splash | PASS | None | None | Centred startup state is test-covered | No change | Fresh 4:3 baseline still needed | `docs/shots/brand_splash_2340x1080.png` |
| Main Menu | PASS | None | None | Balanced destination cards and large hit areas | No change | None observed | `docs/shots/night/main_menu_after*` |
| Activity Picker | PASS | None | None | Safe title/cards/back layout | No change | None observed | `docs/shots/night/activity_picker_after*` |
| Baby Room | PASS | None | Legacy size aliases | Face clear; targets meet child floor | No change | More terminal-state screenshots desirable | `docs/shots/night/baby_room_after*` |
| Feeding | PASS | None | None | Prompt, cards and Bunny remain separated | No change | Detailed wrong/guided captures are archival | `docs/shots/night/feeding_after*`, `docs/shots/feeding_wrong_item_2340x1080.png` |
| Bath | PASS | None | None | Care overlay avoids face and hands | No change | Completion frame not in night pair | `docs/shots/night/bath_care_after*`, `bath_dry_after*` |
| Bedtime | PASS | None | None | Active state balanced | No change | Replay is by picking Bunny up; no dedicated button by design | `docs/shots/night/freeplay_bedtime_after*` |
| Tidy-up | PASS | None | None | Instruction and objects are legible | No change | Refusal/completion evidence remains functional-test only | `docs/shots/night/freeplay_tidy_after*` |
| Free Play | PASS | None | None | HUD, pause and room overlays coherent | No change | Objective-free play intentionally has no summary | `docs/shots/night/freeplay_feed_after*`, `pause_after*` |
| Dress Up | PASS | None | None | Preview, tabs, cards and selected state balanced | No change | None observed | `docs/shots/night/after_dress*` |
| Classroom | PASS | None | Implicit Thai fallback | Safe-area and face keep-outs pass | **Yes** | Physical-device font rendering needs owner check | `docs/shots/night/after_classroom*`, `after_classroom_thai*` |
| Settings | PASS | None | Adult density intentional | Scroll body + fixed footer verified | No change | None observed | `docs/shots/settings_ipad.png`, `settings_iphone.png` |
| Parent Gate | PASS | None | None | One-second hold copy/ring consistent | No change | None observed | `docs/shots/settings_gate_ipad.png`, `settings_gate_iphone.png` |
| Food chooser | PASS | Exact object art used | None | 240px-class cards and pressed style | No change | Selection immediately routes, so no persistent selected state by design | `docs/shots/night/freeplay_chooser_after*` |
| Reward / completion | PASS | None | Celebratory scale intentional | 0-star kindness, almost, sticker, Next/Replay covered in tests | No change | Variant screenshot matrix remains incomplete | `docs/shots/feeding_summary_1334x750.png`, `feeding_summary_2340x1080.png` |
| Error / empty | PASS fallback | None | Kind short copy | No red-X/failure screen; missing content falls back silently | No change | Empty toy storage says `Open!`; functional wording debt | Functional tests; no synthetic error UI |
| Pause / back dialogs | PASS | None | None | Large targets, dim scrim, safe card | No change | Text-only secondary break actions are a deliberate low-clutter exception | `docs/shots/night/pause_after*`, `docs/shots/break_card_*` |

## State completeness

- Feeding has entry, active, invalid/wrong, guided help, success and summary behavior covered. Bath has no invalid state by child-UX design. Free Play has no completion screen by design.
- Bedtime replay is the physical pick-up/lay-down loop. Food selection routes immediately, so pressed feedback exists but a persistent selection screen does not.
- Summary tests cover 0/1/2/3 stars, almost stars, stickers, final-level no-Next, Replay and Close. The screenshot archive does not yet mirror every test variant.
- All nine activity-picker mission IDs have route-start coverage. No missing texture, missing icon, invalid node-path or shipped fallback asset was found.

## Validation

- Full Godot suite: **PASS — 171 cases, 0 failures** on 2026-09-22. Startup logs contain the expected missing local macOS speech-extension warning; per instructions it was not repaired.
- UI/touch coverage is included in `test_night_activity_ui`, `test_night_shared_ui`, `test_interaction_ux`, `test_tutor_scene`, `test_parent_gate`, `test_level_summary` and `input_settings_harness`.
- Touch/input harness: **PASS**, including no-dead-overlay probes at 1024×768 and 2340×1080.
- Scene/import scan: **PASS** (Godot headless editor exit 0); no UI resource reference was missing.
- Route-start count: **9 mission routes**, plus Main Menu, picker, Free Play, Dress Up, Classroom, Settings and Baby Room scene loads.
- Screenshot archive reviewed: **94 prior night PNGs** plus focused settings, speech, feeding and branding evidence. `docs/shots/night_complete/` contains **40 curated baseline/current PNGs** for ten major screens at the two available archived dimensions. Phone screens which were visually unchanged intentionally use identical baseline/current evidence. Existing captures use 1334×750 and 2340×1080; 1334×750 is widescreen, not a true 4:3 iPad capture. A new 1024×768 full-state baseline/current matrix remains outstanding and is not falsely claimed here.

## Exact remaining visual defects

1. A true 1024×768 baseline/current matrix is missing for most screens; older “iPad” captures are 1334×750.
2. Tidy refusal/completion/replay, bedtime success/daylight exit, chooser pressed/dismissed and every reward variant lack dedicated paired stills, although behavior is test-covered.
3. The generic break card’s Continue action and tutor exit confirmation are text-only; readable and accessible, but slightly less pictorial than primary navigation.
4. Legacy type sizes should eventually be converted to named semantic aliases without changing their rendered scale.
5. Physical-device rendering, especially Thai fallback and safe areas, requires owner testing; no physical-device PASS is claimed.

Files changed in this pass: `game/scripts/tutor/ui/tutor_hud.gd`, `docs/NIGHT_ICON_MATRIX.md`, `docs/NIGHT_TYPOGRAPHY_AUDIT.md`, and this report. Final commit SHA is reported by the handoff message because a commit cannot contain its own hash.
