# QA — integrated build 841d682 (Agent G, 2026-09-20)

Read-only verification of `wt/qa` at commit `841d682` ("feat(carry): measured hold point,
wrapped arms, evidence at both viewports"). Godot 4.7.2.stable, macOS, Metal / Forward Mobile.
Speech plugin binaries linked from the main checkout (`game/ios/speech_plugin/bin` symlink) so
the editor build loads `LittleBuddySpeech` exactly as the shipping editor does.

Every frame below was rendered by the project's own harnesses from the shipping scenes
(`main.tscn`, `house_world.tscn`), opened and judged by eye, and lives in `docs/shots/qa_*.png`
(63 files). iPad = 1334x750, iPhone = 2340x1080, both from a `SubViewport` with the PNG size
asserted by the harness. The kitchen, beat and spike-harness frames use the root window at
1334x750 (window honoured; those harnesses do not assert size, so no iPhone frame exists for them).

**No physical device was used. Nothing here is a device result.**

## Verdict

Ship-stopper count: **0 crashes, 0 wrong characters, 0 duplicate Bunnies, 0 floating objects,
0 wrong-size frames, suite and all three smokes green, speech backend is the real `ios` plugin.**
Three visible defects should be fixed before the child sees the build; details in the table and
in "Release-blocking vs cosmetic".

## Test and smoke results (verbatim, one line each)

| Run | Result line |
|---|---|
| `res://tests/run_tests.gd` (headless) | `PASS - 128 case(s), 0 failure(s)` (lead expected 125; three new carry/run cases are in the suite) |
| `test_run_vs_walk` (inside the suite) | `measured over 3.0 s: tap-to-walk 3.15 m (1.05 m/s), stick at the walk/run boundary 3.09 m (1.03 m/s), full stick 4.65 m (1.55 m/s), ratio 1.48x` |
| `res://tests/smoke_mission01.gd` | `SMOKE PASS -- Mission 01 played end to end in the real house.` — `6. saved: completed=true stars=3/3  lifetime stars=10` / `7. replay re-armed 'imHungry'; lifetime stars still 10` |
| `res://tests/smoke_mission01.gd -- snackTime` | `SMOKE PASS -- Mission 01 played end to end in the real house.` — `0. profile reset; 1 earlier level(s) marked played` / `6. saved: completed=true stars=3/3  lifetime stars=12` / `7. replay re-armed 'snackTime'; lifetime stars still 12` |
| `res://tests/smoke_audio_shipping.gd` | `SMOKE PASS -- both delivered tracks play in the real game, one at a time, they duck for English, and the shipping default is still silent because no licence evidence has been supplied.` — body lines: `2. shipped manifest: []` (no refused tracks), `3. main.tscn in the tree -> state 'menu', track 'littleDaysTheme' ... playing=true -17.0 dB`, `5. mission 'imHungry' running -> state 'miniGame', track 'hungryBunny' ... playing=true`, `6. AudioStreamPlayers holding a music stream, whole tree: 1`, `7. 4 room transitions later: track 'hungryBunny', position 0.93 s -> 2.23 s, track_started fired 1 time(s)`, `8. speaking -> music -26.0 dB (duck gain 0.316)`, `10. muted -> playing=false, players holding music=0` |
| Speech backend probe (headless, plugin linked) | `has_singleton LittleBuddySpeech: true` / `backend: ios` / `available: true  permission: false` / `fallbackActive: false` / `nativeSingletonPresent: true` (`ttsAvailable: false` is a headless artefact — no TTS server without a window) |
| `shots_menu.gd` x2 | `MENU SHOT OK` (1334x750, 2340x1080) |
| `shots_rc.gd` x2 | `beat reached: 'feedBunnyCare'` / `RC SHOTS OK` (aspect 1.78 and 2.17) |
| `shots_ux.gd` default x2 | `UX SHOTS FAIL: - door_enter: the layer shows 'take' on ''; expected ENTER on kitchen.doorToLivingRoom` (both sizes; every other frame in the run asserted OK) |
| `shots_ux.gd -- story` x2, `-- toybox` x2 | `UX SHOTS OK` |
| `shots_carry.gd` x2 | `CARRY SHOTS OK` — `held: Bunny root at (0.0, 0.36, -0.28) in her frame, state=held, socket=true, clip=carried`, `placed: floor gap 0.000 m, 0.59 m from her`, `toy held at (0.23, 0.52, -0.11) ... socket itemHoldRight`, `toy placed 0.000 m from its pad` |
| `shots_bubble.gd` x2 | `BUBBLE SHOTS OK (ipad)` / `BUBBLE SHOTS OK (iphone)` — every staging: bubble rect clear of both faces; `satisfied: bubbleVisible=false backingVisibleInTree=false` |
| `shots_kitchen.gd` | `SHOTS OK -- every step happened before it was photographed.` (9 verbs all `ok`) |
| `shot_harness.tscn -- beat imHungry:2` / `:3` | `ok` but `task=goToKitchen kind=travel focused=false` for both — the skip cannot pass a travel beat, so neither findBottle nor prepareMilkCare was reached by this job (see notes) |
| `shot_harness.tscn -- house bedroom`, `-- menu` | `ok` |
| `--headless --import` | exit 0 (the two `Can't open GDExtension` lines were from the import running before the plugin `bin` symlink existed; every later run loaded it) |

Note on the audio smoke's trailer: its last sentence ("shipping default is still silent") is stale
copy from before the 2026-09-20 licence clearance; the assertions in the same run (`shipped
manifest: []`, `is_silent_build()` false, menu and mission tracks `playing=true` with the
override disarmed) prove music DOES play in the shipping configuration.

## State table

| # | State | Frame(s) | Result | Notes / exact defect |
|---|---|---|---|---|
| 1 | Main menu: Aliz + Bunny only, four buttons, storybook house, title readable | `qa_menu_ipad.png`, `qa_menu_iphone.png`, `qa_harness_menu_ipad.png` | PASS | Two characters, "Little Days" legible, Start/Free Play/Dress Up/Grown-ups. The spike-harness menu reads "Continue" because the machine's `user://` profile now holds the smokes' progress (expected). |
| 2 | House entry / bedroom | `qa_harness_house_bedroom_ipad.png` | **FAIL** | Geometry, Aliz, one Bunny, Home, version all fine, but the HUG affordance badge (heart bubble + "HUG" pill) is drawn over Bunny's speech bubble: only "ngry, Aliz!" is legible. Unreadable text on the first frame the child sees when entering the mission. |
| 3 | Aliz walking | `qa_move_walk_ipad.png`, `qa_move_walk_iphone.png` | PASS (frame) / numbers see note | Mid-stride, walk pose, no clipping. Unit test: 1.05 m/s tap-to-walk, 1.03 m/s at the band boundary. The carry harness printed `move_walk: 0.53 m in 0.33 s = 1.60 m/s, running=false, speed=0.90` — identical displacement to the run frame, so that harness's on-screen m/s figure is not a valid measurement (see cosmetic list). |
| 4 | Aliz running | `qa_move_run_ipad.png`, `qa_move_run_iphone.png` | PASS | Unit test full stick 1.55 m/s, ratio 1.48x; harness `running=true, speed=1.60`. |
| 5 | Bunny hungry with backed bubble "I'm hungry, Aliz!" | `qa_bubble_front/left/right/abeam/longline_{ipad,iphone}.png`, `qa_ux_*_toybox_open.png`, `qa_ux_ipad_story_hug.png` | PASS | Backed panel, readable at both sizes, steps to the side Aliz is not on, never over either face; `satisfied` frames show it gone. |
| 6 | Carry Bunny (held in front, one Bunny, no floating, no intersection) | `qa_carry_bunny_front_{ipad,iphone}.png`, `qa_carry_bunny_quarter_{ipad,iphone}.png` | PASS (cosmetic note) | Held at chest/hip through the rig socket, one Bunny in the room, his feet ~0.35 m up, no clipping through her arms. Cosmetic: the badge over her head says lowercase "place" in a blank white bubble (no icon), unlike every other badge. |
| 7 | Place Bunny | `qa_carry_bunny_placed_{ipad,iphone}.png` | PASS | On the floor (gap 0.000 m), 0.59 m from her, "carry" badge returns to him, hunger unchanged. Same lowercase/blank-glyph badge note. |
| 8 | Prop take / place | `qa_carry_prop_held_*.png`, `qa_carry_prop_placed_*.png` | PASS (cosmetic note) | Teddy in her right hand (socket `itemHoldRight`), then on its pad. Cosmetic: while she holds the toy the "place" badge/ring is drawn at her head, not on the pad, and the verb is lowercase with the blank glyph. |
| 9 | Open fridge with OPEN badge | `qa_ux_{ipad,iphone}_fridge_open.png`, `qa_kitchen_2_fridge_open.png` | PASS | OPEN badge with door glyph on `kitchen.fridge`; the fridge visibly opens with banana, bottle and pudding inside. Cosmetic: the target ring is drawn around Aliz's face because she stands in front of the fridge. |
| 10 | Pick up bottle / TAKE | `qa_ux_{ipad,iphone}_fridge_take.png`, `qa_kitchen_3_take_banana.png`, `qa_kitchen_7_served.png` | PASS | TAKE badge on the open fridge at both sizes; kitchen harness shows the item leave the fridge into her hand. |
| 11 | Prepare milk | smoke `beat 4: prepareMilkCare kind=care room=kitchen care=prepareMilk` played by gesture; `qa_kitchen_5/6_*.png` (counter transform path) | PASS (by smoke; no dedicated frame) | The beat job could not skip past the `goToKitchen` travel beat, so `qa_beat_preparemilk_ipad.png` shows "Walk to the kitchen." with a correct ENTER badge instead. The care mini-game itself is proven by the smoke (`care mini-games finished by gesture: 2`) and the kitchen frames prove the counter transform. |
| 12 | Feed Bunny (portrait framing, "Time to drink!", no bubble overprint, no badge under overlay) | `qa_rc_{ipad,iphone}_feed.png`, `_feed_mid.png`, `_feed_done.png` | PASS | Real live Bunny in the FEED portrait framing (top/bottom bands, no scrim), title "Time to drink!", hint "Hold the bottle at Bunny's mouth.", child line "Milk, please, Aliz!", fill bar advances, no 3D bubble, no affordance badge under the overlay. Done frame: "Well done!" / "Yes!" and the HUG badge for the next beat; stars 3. |
| 13 | Snack Time | smoke `-- snackTime`, `qa_kitchen_1..9_*.png` | PASS | 8 beats played, banana -> counter -> spoon -> mashedBanana -> table -> carried to Bunny -> `Yum! Thank you!` -> fridge closed. |
| 14 | Home button + pause card (Continue / Home / Grown-ups) | `qa_ux_{ipad,iphone}_home_version.png`, `qa_ux_{ipad,iphone}_pause.png` | PASS | "Take a break?" card, three buttons, dimmed world, Home button top-right at both sizes. |
| 15 | Version "0.1.0" bottom-right, not under joystick/Next | every house frame | PASS | Bottom-right above the Next button, never under the stick or Next. It is very small (tiny label) — readable on the PNG, will be small on device. |
| 16 | Save / load | smokes above; suite `profile_store`, `save_migration`, `save_world_location` PASS | PASS | Smokes print the profile reset, the completed/stars write, lifetime stars persisting across the replay re-arm, and the second smoke opening with `1 earlier level(s) marked played`. The spike menu then shows "Continue" from that saved profile. |
| 17 | Door ENTER affordance (UX harness) | `qa_ux_{ipad,iphone}_door_enter.png` vs `qa_beat_*_ipad.png` | **FAIL** (harness-asserted) | At `kitchen.doorToLivingRoom` the layer shows a blank white bubble labelled lowercase "take" on the apple lying by the door instead of ENTER on the door, at both sizes. Cause read from source: the door offers `PRIORITY_DOOR = 1` and `spawned_object.gd` offers `AFFORD_PRIORITY = 1` with verb `"take"`, so `AffordanceRules._better()` breaks the tie by distance and the apple wins; `affordance_layer.gd` has no glyph for the lowercase carry verbs and falls through to `_: draw_circle` (the dot) and prints the label as-is. The bedroom kitchen door (no prop nearby) shows a correct ENTER badge in `qa_beat_findbottle_ipad.png`. |
| 18 | Story HUG affordance (iPhone) | `qa_ux_iphone_story_hug.png` | **FAIL** | HUG badge drawn over the speech bubble; "I'm hungry, Aliz!" reads as "I'… Aliz!". Same collision as #2. iPad `qa_ux_ipad_story_hug.png` is clean. |
| 19 | Tap hint | `qa_ux_{ipad,iphone}_tap_hint.png` | PASS | Arrow + ring on the table. On iPad the arrow's tip touches the OPEN pill above it (harness stages both at once). |
| 20 | Speech backend in the editor build | probe output above; suite `speech_never_mocks_on_device`, `speech_never_required`, `speech_privacy_guard` PASS | PASS | `backend: ios`, `fallbackActive: false`, mock not selected. No speech success was produced by a mock in any run. |
| 21 | Music | `smoke_audio_shipping` | PASS | Menu theme in `main.tscn`, `hungryBunny` in the mission, exactly one player, no restart across four room changes, ducks to 0.316 while speaking, mute stops it. |

## Release-blocking vs cosmetic

**Fix before the child plays (visible, wrong content, reproducible at shipping sizes):**

1. HUG badge overprints Bunny's speech line when Aliz stands in front of him — frames
   `qa_harness_house_bedroom_ipad.png` (iPad, house entry) and `qa_ux_iphone_story_hug.png`
   (iPhone). The one English line the beat is about becomes unreadable. The affordance layer
   already has keep-outs for stick/Home/Next; the need-bubble rectangle is not one of them.
2. Door ENTER lost to a floor prop — `qa_ux_*_door_enter.png`, asserted by `shots_ux.gd` at
   both sizes. Standing at a door beside a dropped toy/food shows "take" on the food instead of
   ENTER on the door. Priority tie (`PRIORITY_DOOR == spawned_object.AFFORD_PRIORITY == 1`).
3. Carry verbs render as blank badges — every "carry" / "place" / "take" badge from
   `child_actor.gd`, `spawned_object.gd`, `drop_zone.gd` is lowercase and gets the layer's
   fallback dot instead of an icon (`qa_carry_*`, `qa_ux_*_door_enter`). Not a functional break
   (tapping still works, `CARRY SHOTS OK`), but it is the new feature's only on-screen prompt and
   it looks broken next to OPEN/TAKE/HUG/ENTER.

**Cosmetic / follow-up (do not block today's playtest):**

- Target ring drawn around Aliz's face when she stands in front of the target (fridge in
  `qa_ux_*_fridge_open.png`, table in `qa_kitchen_7_served.png`, held toy in
  `qa_carry_prop_held_*.png`). Translucent, no text over the face.
- Version label is very small at both sizes (readable in the PNG, but tiny).
- Mission caption "Go to Bunny." overlaps the 3D "KITCHEN" door sign on iPhone
  (`qa_bubble_*_iphone.png`); star row overlaps the same sign on iPad in the `left` staging.
- iPad tap-hint arrow touches the OPEN pill when both are up (`qa_ux_ipad_tap_hint.png`).
- Aliz is half out of frame and strongly foreshortened at the left edge of the FEED portrait
  framing (`qa_rc_*_feed*.png`) — Bunny is the subject, so acceptable, but it reads as a lean.
- `shots_carry.gd` `_move_shot` prints identical `0.53 m in 0.33 s = 1.60 m/s` for the walk
  (`speed=0.90`) and run frames; its 40-frame window is dominated by the teleport/settle, so the
  printed m/s must not be quoted as a measurement. `test_run_vs_walk` (3.0 s window) is the
  number to quote.
- `shot_harness.tscn -- beat <level>:<skip>` cannot skip a `travel` task
  (`skip_current_task` leaves `goToKitchen` current), so beats 3+ of imHungry cannot be
  photographed by that job.
- `shots_kitchen.gd` does not detach `SaveService` (unlike the other harnesses), so it ran with
  the machine's live profile and photographed the "Go to Bunny." mission caption from it; harmless
  for evidence, but note that the smokes and this harness both write the real `user://` profile
  on the QA Mac.
- Six `.uid` files are missing from HEAD and were regenerated by the import
  (`buddy_carry_pose.gd.uid`, `carry_controller.gd.uid`, `test_carry_bunny.gd.uid`,
  `test_carry_props.gd.uid`, `test_run_vs_walk.gd.uid`, `shots_carry.gd.uid`) — commit them from
  the main checkout so fresh clones do not churn.
- The `smoke_audio_shipping` pass banner still says the shipping default is silent; the run's
  own assertions contradict it. Text only.

## Frames written (docs/shots/, 63 files)

qa_menu_{ipad,iphone}; qa_rc_{ipad,iphone}_feed, _feed_mid, _feed_done;
qa_ux_{ipad,iphone}_fridge_open, _fridge_take, _door_enter, _home_version, _pause, _tap_hint,
_story_hug, _toybox_open; qa_carry_bunny_front/quarter/placed_{ipad,iphone};
qa_carry_prop_held/placed_{ipad,iphone}; qa_move_walk/run_{ipad,iphone};
qa_bubble_front/left/right/abeam/longline/satisfied_{ipad,iphone}; qa_kitchen_1_arrive ..
qa_kitchen_9_fridge_closed; qa_beat_findbottle_ipad, qa_beat_preparemilk_ipad;
qa_harness_house_bedroom_ipad, qa_harness_menu_ipad.

Tracked `docs/shots/kitchen_*.png` files were overwritten by the kitchen harness and restored with
`git checkout`; the worktree diff is only the `qa_*.png` files, this report, the untracked plugin
`bin` symlink and the six regenerated `.uid` files. Nothing committed.
