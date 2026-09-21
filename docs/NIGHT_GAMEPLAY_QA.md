# Night gameplay QA (Agent Q) — behaviour of every mini-game and screen

Date: 2026-09-22, 00:21–00:35 (+07). Godot 4.7.2 headless on macOS, plus one windowed
frame capture. Read-only on the main checkout; nothing under `game/` was changed
and `git status` is clean. **No physical device was used; nothing below is a
device claim.**

The head moved under the run (other agents were merging). Every step of the final
battery recorded `HEAD` before and after it:

| Step | HEAD before → after | Result |
|---|---|---|
| `tests/run_tests.gd` | `b445e1b` → `280f73b` | `PASS - 175 case(s), 0 failure(s)` |
| `probe_story.gd -- imHungry` | `280f73b` → `45d348a` | 37 PASS / 2 "FAIL" (both the summary observation, O1) |
| `probe_story.gd -- snackTime` | `45d348a` → `a6f1619` | 27 PASS / 6 FAIL (1 real: B2; 5 probe-accounting, see notes) |
| `probe_replay.gd` | `a6f1619` | 4 PASS / 2 FAIL (B2, reproduced twice) |
| `probe_freeplay.gd` | `a6f1619` | 64 PASS / 7 FAIL (B1 ×5, O2 ×2) |
| `probe_screens.gd` | `a6f1619` | 67 PASS / 0 FAIL, 1 SCRIPT ERROR (B3) |
| `tests/smoke_mission01.gd -- imHungry` | `a6f1619` | `SMOKE PASS -- Mission 01 played end to end in the real house.` |
| `tests/smoke_mission01.gd -- snackTime` | `a6f1619` | `SMOKE PASS -- Mission 01 played end to end in the real house.` |
| `tests/input_settings_harness.gd` | `a6f1619` | `INPUT SETTINGS OK` |

An earlier identical battery on `748799c` (the head I was given) found the same
bugs B1 and B3 and the same observations; B2 was found on the newer head only
because the replay probe was written after the first pass, not because the head
changed. Logs for both passes are in the scratchpad (`nightqa/head_748799c/`,
`nightqa/final/`).

## 1. Verbatim gate lines (final battery, `a6f1619`)

```
PASS - 175 case(s), 0 failure(s)
SMOKE PASS -- Mission 01 played end to end in the real house.      (imHungry: 7 beats, 2 care by gesture, stars 3/3, lifetime 10)
SMOKE PASS -- Mission 01 played end to end in the real house.      (snackTime: 8 beats, stars 3/3, lifetime 12)
INPUT SETTINGS OK
```

`SCRIPT ERROR` count: **0** in the suite, both smokes, the input harness and every
probe except `probe_screens.gd`, which produced **1** (B3, `baby_room.gd:1739`).

Engine `ERROR:` lines in the suite log: **649**, none a test failure. Attributed by
the first GDScript frame:

| Count | Line | Origin | Meaning |
|---|---|---|---|
| 540 | `Condition "!is_inside_tree()" is true. Returning: Transform3D()` | `baby_little_buddy.gd::get_mouth_position` | `global_transform` read on a node the headless runner never put in a tree |
| 18 | same | `child_actor.gd::room_changed` | same |
| 40 | `Parameter "data.tree" is null.` | `house_world.gd:182 _ready` | `get_tree()` in `_ready()` when a case calls it by hand outside a tree |
| 34 | `Can't use get_node() with absolute paths from outside the active scene tree.` | `house_level_director.gd:308 bind` | `/root/TtsService` lookup outside a tree |
| 6 | absolute path | `draggable_object.gd::_play_sfx` | same |
| 1 each | `main.gd:560 _arm_first_run`, `safe_area.gd _compute_insets`, `profile_store.gd:170` (the corrupt-JSON case, intentional) | | |
| 7 | RID / resource leak lines at exit | engine | headless dummy renderer |

22 `WARNING:` lines, all expected (cloud tutor banned-word replacement, simulated
audio refused when off, backend unreachable in the failure case, unknown focus
targets in negative tests, anchors, leaks at exit).

## 2. Per-mini-game matrix

Legend: PASS / FAIL / INT (intermittent) / NT (not tested). "Reward once" means the
task paid exactly once and the profile total matched the awards. Column
"anim" = leaving mid-animation / mid-close-up.

| Mini-game / screen | enter | play | cancel/back | complete | reward once | replay | exit | re-enter | offline | rapid taps | double tap | anim | → menu |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Feeding — Story "I'm Hungry!" (Play with Bunny → picker → house; bottle close-up on Bunny's face) | PASS | PASS (prepareMilk pour+shake, giveBottle hold 2.2 s, both by gesture, opened by arrival) | PASS (Home → pause card → Home mid-close-up) | PASS (`mission_completed` ×1, hunger 55→0) | PASS (7 tasks, 13 stars, profile 13) | PASS (Play again: 0 lifetime stars, rating 3 kept) | PASS | PASS | PASS | PASS (Next ×5 in one frame skips exactly one task) | PASS (picker card ×2 → one route; Play again ×2 → one restart) | PASS | PASS (old house freed, room saved) |
| Feeding — Story "Snack Time" (kitchen verbs, spoon feed) | PASS | PASS (8 beats) | PASS (Home mid-level) | PASS | PASS | **FAIL — B2** (in-session Play again: every kitchen beat refuses, nothing said) | PASS | PASS (from the picker the kitchen is fresh) | PASS | PASS | PASS | NT (no close-up in this level) | PASS |
| Feeding — Free Play bottle (fridge → counter MIX → Bunny) | PASS* | PASS (MIX gesture, hold 2.4 s, portrait camera on/off) | PASS | PASS (hunger 100→30) | n/a (Free Play pays nothing, by design) | PASS (pantry restocked; second bottle) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Feeding — Free Play table (Bunny seated, mashed banana) | PASS* | PASS (giveFood hold) | PASS | PASS (100→30, still at table) | n/a | PASS (second helping) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Feeding — Chapter 2 highchair (`baby_room.tscn`, `feedingTime`) | PASS (prompt "Give the baby the banana.", 3 items, stage camera current) | PASS (wrong item: "Try the banana!", half credit, no penalty; drag to mouth delivers; drinks need the held sip) | NT (highchair Back = skip not pressed) | PASS (6 tasks, once) | PASS (0→6, counter label 6) | PASS (Play again restarts once; task order is shuffled per run) | PASS (highchair Home → menu) | PASS | PASS | NT (rapid drags) | **B3** (Home ×2 → SCRIPT ERROR, still goes home) | NT (Home mid-drink) | PASS |
| Bath — Free Play (Bunny to bath: wash then towel) | PASS | PASS (wash by 2600 px of strokes → towel follows in the same held room → 9 patches dry; cleanliness 0→80; Bunny in tub) | PASS (Home mid-wash → menu, room saved) | PASS | n/a | PASS (out of the tub and back in reopens the wash) | PASS | PASS (lands in the bathroom, no stale close-up, input live) | PASS | PASS | PASS (double arrival opens one close-up) | PASS | PASS |
| Bath — Story levels with a bath beat (goodMorning, brushMyTeeth) | NT | NT | NT | NT | NT | NT | NT | NT | — | NT | NT | NT | NT |
| Teeth — Free Play sink with Bunny | PASS | PASS (10 reversals over the mouth) | PASS | PASS (0→40) | n/a | PASS | PASS | PASS | PASS | PASS | PASS | NT | PASS |
| Bedtime — Free Play (Bunny to bed) | PASS | PASS (energy 15→75, light 0.61→0.23, teddy "Night night" comforts) | PASS (pick up ends the night, light back to 0.61) | PASS | n/a | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Bedtime — Story `tidyAndBedtime` | NT | NT | NT | NT | NT | NT | NT | NT | — | NT | NT | NT | NT |
| Tidy-up — Meshy toy box (bedroom) | PASS (`Storage_toyBox` is the GLB `MeshInstance3D`) | PASS (4 toys scattered; pad tap + 3 carries; praise; "All tidy!") | PASS | PASS (4/4 in the model) | n/a | PASS (arriving again scatters a fresh set, box emptied) | PASS | PASS | PASS | PASS | PASS (double arrival mid-tidy keeps one tidy) | NT | PASS |
| Baby Room — Chapter 2 scene | PASS (mission mode, `feedingTime`) | PASS | PASS (gear tap → gate card → Back returns to the gear) | PASS | PASS | PASS | PASS | PASS (built twice) | PASS | NT | B3 | NT | PASS |
| Dress Up (title screen) | PASS (Aliz model, camera current) | PASS (4 swatches) | PASS (Back ×2 → one menu) | n/a | n/a | n/a | PASS | PASS (swatch remembered: mint) | PASS | PASS (6 swatch taps → last wins) | PASS | NT | PASS |
| Free Play — fridge chooser | PASS (3 cards ≥240 px, room input held) | PASS (dismiss gives the room back; pick banana) | PASS | PASS | n/a | PASS | PASS | PASS | PASS | PASS | PASS (pick ×2 → one take) | — | PASS |
| Free Play — counter mash / fruit bowl | PASS | **FAIL — B1** (by arrival alone nothing can be combined) | — | FAIL | — | FAIL | — | — | PASS | — | — | — | — |
| Free Play — wardrobe clothes | PASS (doors swing, 2 garments) | PASS (tap garment → in hand → Bunny wears pajamas) | PASS (second arrival shuts and puts clothes away) | PASS | n/a | PASS | PASS | PASS | PASS | PASS | PASS (garment tap ×2) | NT | PASS |
| Free Play — sink brush / hands / bubbles | PASS | PASS (hands up ~1 s with splash; bubbles) | — | PASS | n/a | PASS | PASS | PASS | PASS | PASS | PASS | — | PASS |
| Classroom — Learn with Aliz entry (real autoloads) | PASS (real engine, no cloud bridge, welcome speaks, camera current, 6 HUD buttons) | PASS | PASS (End → confirm → Keep going resumes; Yes → break card, mic released) | PASS (simulated lesson completes, break card 3 stars, progress saved) | n/a (tutor stars are the break card's) | PASS (Learn again restarts) | PASS (Home ×3 → one departure) | PASS | PASS (`cloud_enabled` false, no `HTTPRequest` nodes) | PASS | PASS | PASS (End mid-speech) | PASS (old scene freed) |
| Classroom — permission-ask path (stand-in service) | PASS (asked exactly once, waits idle, banner info) | granted: PASS (mic opens, "fruits" heard → English Basics) / denied: PASS (tap-to-talk + 4 answer cards, grown-up note names Settings, card tap answers) | PASS (Home works in both) | — | — | — | PASS | — | PASS | — | PASS (answer ×2 harmless; card ×2 one answer) | — | PASS |
| Classroom — quota card | PASS (`tick(100000)` exhausts) | PASS (closing then card, no Learn again) | — | PASS | — | PASS (a fresh classroom goes straight to the card) | PASS (card Home) | — | PASS | — | — | — | PASS |
| Classroom — break card "Continue Playing" → Free Play | NT (covered by `test_tutor_scene::_test_home_and_free_play_leave`) | | | | | | | | | | | | |
| Activity picker | PASS (lists all 9: imHungry, snackTime, goodMorningRoutine, morningRoutine, breakfastTime, toddlerPlayTime, tidyAndBedtime, sayItChallenge, brushMyTeeth) | PASS | PASS (`back_pressed` — suite `test_activity_picker`) | — | — | — | PASS | PASS (opens again after every return) | PASS | — | PASS (card ×2 → one `activity_chosen`) | — | — |
| Settings + parent gate (standalone) | PASS (gate card, panel hidden) | PASS (0.4 s hold does not unlock; 3 s hold unlocks; Voice Off persists `speechEnabled=false`; QA replay row = imHungry) | PASS (Done ×2 → relocks, asks for the title once) | — | — | — | PASS | — | PASS | PASS (`INPUT SETTINGS OK`: taps, scroll, sliders, two fingers) | PASS | — | PASS |
| Splash → menu | PASS (hands over at 1.54 s, min 1.2 respected, splash freed) | PASS (tap skips in 0.40 s) | — | — | — | — | — | — | PASS | — | — | — | PASS |

\* Free Play feeding is entered from the fridge/counter; see B1 for what a child
can and cannot do there without the dev-only `kitchen.take()` calls the harnesses
use.

Notes on the story probe's own "FAIL" lines that are **not** product bugs:
`walk.pause_card_opens_mid_level` (snackTime has no care beat, so my first loop had
already finished the level and the summary hides the chrome), `level.care_finished
0/0` (no care beats in snackTime), `level.stars_persisted 5 vs 17` (my counter
summed a completed first run plus a 0-star replay).

## 3. Room-by-room walkthrough

Driven on the real `house_world.tscn` in a live tree (`probe_freeplay.gd`, the
`walk.*` probes) plus one windowed capture per room
(`tests/shots_rooms.gd -- nightqa 1334x750`; PNGs kept in the scratchpad, not the
repo). "Badges" is the affordance verb offered to Aliz standing empty-handed.

| Room | Spawn (default, room-local) | Doors | Camera / zoom | Collision | Interaction prompts | Exit |
|---|---|---|---|---|---|---|
| Bedroom | (0, 0, 1.5), inside the floor; every arrival spawn present | 2 (→ kitchen, → bathroom) | room camera adopted, current, `fits=true`, dist 4.56; focus/portrait close-ups used by the bottle | 16 static bodies for 3 furniture + storage | bed:SIT, wardrobe:OPEN, toy:TAKE, toyBox:OPEN, both doors ENTER — **all present** | right door → bathroom at `fromBedroom`, child in control |
| Bathroom | (0, 0, 1.5) | 2 | current, `fits=true`, dist 4.23 | 15 | sink:WASH, bath:WASH, towel:TAKE, doors ENTER — **all present** | → livingRoom at `fromBathroom` |
| Living Room | (0, 0, 1.5) | 2 | current, `fits=true`, dist 4.23 | 16 | sofa:SIT, book:TAKE, toyShelf:OPEN, doors ENTER; **toyBox: no badge empty-handed** (O2, by design: it is a landing pad; PLACE appears with a toy in hand) | → kitchen at `fromLivingRoom` |
| Kitchen | (0, 0, 1.5) | 2 | current, `fits=true`, dist 4.30 | 15 | fridge:OPEN, counter:TAKE, doors ENTER, Bunny: carry; **table: no badge empty-handed** (O2, by design: it feeds when Bunny sits there) | → bedroom at `fromKitchen` |
| All 8 doors | — | every door opens and lands in the right room with the child in control; a double arrival at one door in the same frame is one transition | | | | |
| Classroom | fixed seat | Home / End only | camera current, Aliz face rect kept clear (suite) | n/a | 6 HUD buttons built and routed; answer cards ×4 in the fallback | Home → menu; break card Home / Learn again |
| Baby Room | fixed | none | `Camera3D` current; highchair stage takes the camera and hands it back | Area3D picking on the legacy objects | mic/next/sticker/gear present; highchair prompt + 3 items | highchair Home → menu (B3 on double tap); gear → gate card → Back |
| Dress Up | fixed | Back only | camera current, Aliz model available | n/a | 4 swatches + Back | Back → menu, swatch remembered |

Aesthetics were not judged. The captured frames show each room framed whole with
both door signs, the joystick and the subtitle strip visible.

## 4. Ranked bug list

Fix commit column left blank for the lead.

### B1 — HIGH — Free Play kitchen: the counter hands back whatever was just put down; no meal can be made by play alone
- **Repro (script):** `probe_freeplay.gd`, probes `kitchen.pure_play_can_make_a_meal` / `kitchen.pure_play_offers_counter_contents` (arrivals only, no direct `kitchen` calls).
- **Steps:** Free Play → kitchen → arrive fridge (opens) → arrive fridge (chooser) → pick banana → arrive counter → arrive counter → arrive counter …
- **Expected:** banana goes on the counter; the next empty-handed arrival offers the counter's bowl/spoon (the suite's own comment: "Put it down on the counter, take the bowl, bring the bowl back: cook"); mash close-up opens.
- **Actual (verbatim):** `pure-play kitchen trail: fridge->held=banana | counter->held= on=banana inside=["bowl", "spoon"] | counter->held=banana on= inside=["bowl", "spoon"] | counter->held= on=banana inside=["bowl", "spoon"] | counter->held=banana on= …` — forever. The MIX (bottle) route has the same loop; my earlier MIX/mash PASSes only exist because the probe (like `shots_freeplay.gd`) called `kitchen.take("counter","bowl")` directly.
- **Component:** `game/scripts/gameplay/house_freeplay_acts.gd:169-175` — `if not on_top.is_empty(): return {"act": ACT_KITCHEN_TAKE, "item": on_top}` runs before the `inside` branch that offers `choices`. Masked by `game/tests/cases/test_freeplay_acts.gd::_kitchen` whose assertion is conditional (`if held in [...] and second == "bowl" and made != "fruitBowl"`), so the case passes when the banana is picked back up.
- **Fix commit:** _______

### B2 — HIGH — Snack Time replayed in the same house session is unplayable: the kitchen is never reset or restocked, and the refusal is silent
- **Repro (script):** `probe_replay.gd` scenario A; also `probe_story.gd -- snackTime` probe `replay.completes`.
- **Steps:** Play with Bunny → Snack Time → play to the summary → **Play again** → walk to the fridge.
- **Expected:** a fresh level: fridge shut with a banana in it, spoon on the counter; or at least a kind line saying what to do.
- **Actual (verbatim):** `kitchen at replay start: fridgeOpen=true fridge=["apple", "bottle"] counter=["bowl"] on= held=` then `replay beat 'openTheFridge' at kitchen.fridge: advanced=false beatReached=false encouragement='Well done!' prompt='Tap the fridge door.'` and `stuck (had to be skipped)=["openTheFridge", "takeTheBanana", "bananaOnCounter", "takeTheSpoon", "mashTheBanana", "carrySnackToBunny", "feedBunnySnack"]`. The only way through is Next ×7; the stale "Well done!" from the summary stays on screen. imHungry → Next → snackTime is clean (`B.snackTime_after_imHungry_completes_without_skips: PASS`), and a replay from the picker is clean because the house is rebuilt.
- **Component:** `game/scripts/gameplay/house_level_director.gd::_start_level` (~433-480) never resets the kitchen; `_apply_kitchen_verb` "give" (~743-757) never calls `kitchen.restock()` (Free Play does, in `house_freeplay_director.gd::_on_care_completed`); `game/scripts/kitchen/kitchen_state.gd:114-115` `set_open` returns `_no("open", station_id, "", "")` with an empty `say`, so `_apply_kitchen_verb` shows nothing and `_beat_reached` is reset to false with no feedback.
- **Fix commit:** _______

### B3 — LOW — Baby Room highchair Home: a double tap logs a SCRIPT ERROR (unguarded `get_tree()`)
- **Repro (script):** `probe_screens.gd`, the highchair Home step (two `pressed.emit()` on `feeding_hud.get_home_button()`).
- **Expected:** the second tap is ignored, as `HouseWorld.leave_to_home()` does with its `_leaving` latch.
- **Actual (verbatim):** `SCRIPT ERROR: Cannot call method 'change_scene_to_file' on a null value.  at: _on_feeding_home (res://scenes/baby_room/baby_room.gd:1739)` preceded by `ERROR: Parameter "data.tree" is null.` The game still reaches the menu (`highchair.home_returns_to_menu: PASS`).
- **Component:** `game/scenes/baby_room/baby_room.gd:1731-1739` (`get_tree().change_scene_to_file(...)` with no null/latch guard; compare `_on_break_home` at 1310-1322 which guards the tree).
- **Fix commit:** _______

### Observations (not filed as bugs; the lead should decide)
- **O1** — While the level summary is up the HUD chrome (including Home) is hidden and the summary's own close button starts the next level (`house_level_director.gd::_on_summary_closed`, documented as "the back button leads forward too"). A parent who wants to quit at the summary has to enter the next level first, then Home. Not a dead end; one extra step. Probe lines `summary.home_available` / `summary.pause_menu_from_summary`.
- **O2** — `livingRoom.toyBox` and `kitchen.table` show no affordance badge when Aliz is empty-handed (the box is a landing pad, the table feeds only when Bunny sits there). Both are deliberate per the source comments; noted because the brief asked for a prompt on every target.
- **O3** — "Learn with Aliz" is entered from the title with no grown-ups gate, while `tutor_scene.gd:577` says "the classroom is entered after the grown-ups gate on the title path" and passes `gatePassed: true`. Product question, not a defect I can grade.
- **O4** — On this Mac the native speech GDExtension is present (`ios/speech_plugin/bin/...macos...framework`), so `SpeechService` reports `backend=ios available=true permission=true` in headless runs and the classroom's permission ask is skipped locally; the ask/deny/grant logic was exercised with a stand-in service only.

### Repo hygiene found on the way
- **H1** — `game/tests/cases/test_interaction_anchors.gd`, `test_nav_corners.gd`, `test_room_transitions.gd` (committed in `3a5f968`) have no `.uid` sidecars; every Godot run regenerates them and dirties the tree for whoever runs next. I deleted the regenerated files after each run.
- **H2** — `tests/smoke_mission01.gd` calls `reset_profile()` on the **real** `user://profile.json` (it does not detach the autoload the way `run_tests.gd` does). It wiped the owner's save on this Mac twice tonight; I restored it from the backup I took first (`md5 1b4cc991…` before and after). Anyone running that smoke on a dev machine with progress will lose it.

## 5. Not tested — needs a physical iPad (or was out of reach headless)

- Real touch: physical multi-touch on the care overlays, the highchair drag, the joystick and the picker; emulate-mouse-from-touch ordering on device (the settings harness covers it synthetically only).
- iOS speech: the real permission prompt, `SFSpeechRecognizer` availability settling, the mic opening in hands-free mode, barge-in with a real microphone, and the "denied → Settings" note on device.
- Audio: TTS/voice pack playback and volume sliders audibly; the bedtime chime.
- Backgrounding: `NOTIFICATION_APPLICATION_PAUSED/RESUMED` in the classroom and the house save-on-background.
- Performance/thermal: frame time on iPad and iPhone aspect at 1334×750 and 2340×1080 with the Meshy props.
- Story levels other than imHungry and snackTime played end to end (goodMorningRoutine, morningRoutine, breakfastTime, toddlerPlayTime, tidyAndBedtime, sayItChallenge, brushMyTeeth): the picker lists and starts them; their beats were not driven.
- Highchair Back (skip) button, rapid highchair drags, Home mid-drink animation.
- Classroom break card "Continue Playing" into Free Play by my probe (suite-covered only).
- Onboarding first-run walk in the house (the probes set `onboardingDone=true`; suite `test_onboarding` / `test_routing_first_run` cover it).
- Anything visual: I did not judge aesthetics; the four room frames were only checked for camera framing, door signs and HUD presence.

## 6. How to rerun

All probes live in the session scratchpad
`/private/tmp/claude-501/-Users-hotkhwan-Projects-LittleBuddy/73706c1c-f6e4-484c-bf13-31f02dcdbe75/scratchpad/nightqa/`
(`probe_story.gd`, `probe_replay.gd`, `probe_freeplay.gd`, `probe_screens.gd`,
`run_final.sh`). Each is a `SceneTree` script run from `game/` with
`Godot --headless --path . --script <abs path> [-- missionId]`; each swaps the
`SaveService` autoload for one on `user://nightqa_profile.json` and deletes that
file at the end, so `user://profile.json` is never written. They print one
`PROBE <name>: PASS|FAIL <detail>` line per check and exit 1 on any FAIL. They are
not in the repo on purpose (the brief was read-only); the lead can copy any of
them under `game/tests/` if a regression guard is wanted — B1 and B2 in particular
deserve a case each.
