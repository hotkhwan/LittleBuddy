# Night sprint — final QA matrix (2026-09-22)

Branch `feature/ui-meshy-cloud`. Codex visual branch `feature/codex-ui-polish`
merged at its final commit `143dba5` (merge `a6f1619`; earlier tip `7b42c6e`
merged at `98fbe5f`). Functional checkpoints tagged
`functional-checkpoint-2026-09-22` (`748799c`) and `…-22b` (`45d348a`).
**Final code commit: see §3.** Nothing here is a physical-device result.

Legend: PASS = automated evidence on this Mac; the "Device?" column marks
what only the owner's iPhone/iPad can confirm.

## 1. Matrix

| Screen / feature | Test | Result | Bug | Severity | Fix commit | Device? |
|---|---|---|---|---|---|---|
| Splash → menu | probe_screens (timing, tap-skip), suite | PASS | — | — | — | yes (real timing) |
| Main menu | test_menu_wow, routing, Codex contracts, picker | PASS | — | — | — | yes (safe areas) |
| Activity picker | test_activity_picker (9 cards, replay pays 0, de-bounce) | PASS | — | — | — | no |
| Living room | room walkthrough (spawn, doors, badges, colliders) | PASS | livingRoom.toyBox / kitchen.table show no badge empty-handed (deliberate) | note | — | no |
| Bedroom | walkthrough + tidy + bedtime + carry | PASS | — | — | — | no |
| Kitchen | walkthrough, fridge chooser, counter, feeds | PASS after fix | **B1** counter handed the fruit straight back; no meal by play alone | HIGH | `843d2f8` | no |
| Bathroom | wash → towel gesture, Home mid-wash, re-entry | PASS | — | — | — | no |
| Room transitions | test_room_transitions (48 crossings ×3, story wander) | PASS after fix | Story director re-routed to the return door on arrival → bounce | HIGH | `3a5f968` | yes (feel) |
| Click-to-walk | test_nav_corners (9 taps × 7 objects + 8 doors), stall case | PASS after fix | walked into furniture and stuck; taps projected to unreachable islands; anchors off-mesh | HIGH | `2991089` | yes (feel) |
| Interaction anchors | test_interaction_anchors (every target, every spawn) | PASS after fix | toyBox/toyShelf/sofa stand points off the eroded mesh | MED | `2991089` | no |
| Feeding (Play with Bunny → I'm Hungry!) | smoke_mission01, probe_story, replay pays 0 | PASS | — | — | — | yes |
| Feeding (Free Play table / at Bunny) | test_freeplay_acts feed ×2, restock | PASS | — | — | — | no |
| Snack Time | smoke, probe_story, same-session replay | PASS after fix | **B2** replay started with a dirty kitchen; refusals silent; every beat stuck | HIGH | `843d2f8` | no |
| Bath mini-game | bath wash→dry, touch fallback, second bath | PASS | — | — | — | no |
| Bedtime | light dims/restores, teddy, replay | PASS | — | — | — | no |
| Tidy-up (Meshy toy box) | start/praise/all-tidy/take-out/replay, lid on real hinge | PASS | — | — | — | no |
| Baby Room / highchair | 6 tasks once, wrong item, Play again, gear → gate card | PASS after fix | **B3** Home double tap → SCRIPT ERROR on a freed tree | LOW | `843d2f8` | yes (touch) |
| Dress Up | swatches, rapid taps, back, remembered | PASS | — | — | — | no |
| Free Play routes | wardrobe/dressing, sink teeth, bubbles, sofa/shelf, 8 doors | PASS | — | — | — | no |
| Classroom (Learn with Aliz) | entry, permission granted/denied, full lesson, quota card, Home | PASS | no grown-ups gate on the title path (O3, design) | note | — | **yes (mic, permission prompt)** |
| Tutor repetition | test_tutor_turn_taking, turn dedupe, demo transcript | PASS after fix | stacked openers, doubled praise across the step boundary, cancel ran the boundary, welcome spoken twice | HIGH | `3b09deb`…`447314a` | **yes (ear)** |
| Tutor audio | player lead/underrun/tail tests, session counters | PASS after fix | recogniser churn under the reply, arm on the tail, dropped/truncated cloud chunks, early stop | HIGH | `8a82018`, `000691b` | **yes (ear)** |
| Turn-taking | test_tutor_turn_taking (never talks over itself, mic scope per state) | PASS | — | — | — | yes |
| Gestures | test_aliz_tutor_face (10 gestures, handover), gesture pool, enum parity 11 | PASS | — | — | `b624fdb`, `1db69c5` | yes (look) |
| Free chat (dev) | Worker chat tests, mock chat, live dev session (context + redirect) | PASS (mock provider) | live OpenAI path unexercised: no `OPENAI_API_KEY` on dev | blocker (config) | `74268ca`…`45d348a` | no |
| Settings + parent gate | input harness 21 probes, gate hold, Done relocks | PASS | — | — | — | yes (touch) |
| Audio (music/SFX) | smoke_audio_shipping | PASS | — | — | — | yes |
| Cloud dev API | `/healthz?db=1` 200, migrations 5, live classroom smoke | PASS | production NOT deployed (by design) | — | — | no |
| iOS build | export preflight, arm64, 0 undefined plugin symbols, 0.1.1 | see §3 | — | — | `8efeb58` | **yes (launch)** |
| Android build | APK, zero permissions, Meshy + UI assets packaged, no concept art | see §3 | — | — | — | yes |

## 2. Gates on the final code
| Gate | Result |
|---|---|
| Godot suite | **PASS - 177 case(s), 0 failure(s)** (168 at the start of the night) |
| Mission 01 / Snack Time | SMOKE PASS / SMOKE PASS |
| Audio shipping smoke | SMOKE PASS |
| Settings real-input harness | INPUT SETTINGS OK |
| Classroom smoke vs live dev Worker / vs mock | SMOKE: PASS / SMOKE: PASS |
| Prototype backend | 131 pass, 0 fail |
| Cloudflare Worker | 177 passed, 12 files, typecheck clean |
| Billing module / website | 36 pass / 12 pass |
| Live health | `/healthz?db=1` 200, migrations 5 |

Details: `docs/NIGHT_GAMEPLAY_QA.md` (per-probe evidence, error attribution),
`docs/ALIZ_GESTURES.md`, `docs/ALIZ_TUTOR_FREE_CHAT.md`,
`docs/NAVMESH_WORKFLOW.md` (2026-09-22 section), `docs/HANDOFF_CODEX_TO_CLAUDE.md`.

## 3. Builds and remaining device checks
(filled in below)
