# QA — integrated build cad57ef (Agent G, 2026-09-20)

Read-only verification of `wt2/qa` at commit `cad57ef` ("chore: .uid sidecars for the character
pass" — the fully integrated HEAD of six workstreams). Godot 4.7.2.stable, macOS, Metal / Mobile
renderer. The speech plugin binaries were linked from the main checkout
(`game/ios/speech_plugin/bin` symlink, the only non-`qa2_` untracked path in the worktree) so the
editor build loads `LittleBuddySpeech` exactly as the shipping editor does.

Every frame cited below was rendered in this session by the project's own harnesses (or by a
QA-only probe script kept outside the repo in the session scratchpad) from the shipping scenes,
saved as `docs/shots/qa2_*.png` (134 files), and opened and judged by eye. iPad = 1334x750,
iPhone = 2340x1080, both from a `SubViewport` with the PNG size asserted; the two character
tools (`aliz_shots.gd`, `bunny_shots.gd`) photograph the root window at 1334x750. Every `qa2_*.png`
was re-measured afterwards: 86 x 1334x750, 46 x 2340x1080, plus the two tiled sheets
(`qa2_aliz_face_sheet.png` 1986x792, `qa2_bunny_sheet.png` 3660x1037). **No wrong-size PNG.**

Harnesses whose file names are fixed (feeding, carry, settings, branding) overwrite tracked
frames; each output was copied to its `qa2_` name and the tracked original restored with
`git checkout`, so the worktree's tracked files are unchanged. Where a re-render was byte-identical
to the committed frame (deterministic renders: `feeding_summary_*`, `settings_*`, `settings_gate_*`)
the fresh file's mtime was checked before copying.

**No physical device was used. Nothing here is a device result. Nothing was committed.**

## Verdict

**0 crashes, 0 freezes, 0 tap-through completions, 0 duplicate Bunnies, 0 floating objects,
0 tofu glyphs, 0 wrong-size frames, 0 mock-speech successes. Suite `PASS - 140 case(s)`, both
mission smokes and the audio smoke green, backend `ios`.**

Two visible defects should be looked at before the child plays (neither blocks the playtest);
the rest is cosmetic. Details per acceptance test below and in "Release-blocking vs cosmetic".

## Test and smoke results (verbatim)

| Run | Result line(s) |
|---|---|
| `res://tests/run_tests.gd` (headless) | `PASS - 140 case(s), 0 failure(s)` |
| `test_aliz_life` (inside the suite) | `idle proof -- bone deltas from rest, sampled 1.5 s apart:` / `t=0.3s  head (+1.03, -0.12, +0.49) cm  head 0.50 deg  spine 0.30 deg  hips 1.53 deg` / `t=1.8s  head (+1.25, +0.08, -0.70) cm  head 0.60 deg  spine 0.96 deg  hips 2.00 deg` / `t=3.3s  head (+1.27, -0.13, +0.51) cm  head 0.48 deg  spine 0.94 deg  hips 2.12 deg` / `t=4.8s  head (-1.28, +0.07, -0.29) cm  head 0.20 deg  spine 0.64 deg  hips 2.00 deg` |
| suite cases named by the ATs | `[PASS] speech_end_states`, `[PASS] speech_never_mocks_on_device`, `[PASS] speech_never_required`, `[PASS] speech_privacy_guard`, `[PASS] click_to_move_freeze`, `[PASS] parent_gate`, `[PASS] parent_settings_screen`, `[PASS] feeding_table`, `[PASS] level_summary`, `[PASS] affordance`, `[PASS] bubble_placement`, `[PASS] carry_bunny`, `[PASS] carry_props`, `[PASS] hud_helper_language`, `[PASS] localization`, `[PASS] menu_wow`, `[PASS] branding_splash`, `[PASS] version`, `[PASS] bunny_life`, `[PASS] bunny_face`, `[PASS] aliz_face` |
| `res://tests/smoke_mission01.gd` | `1. fresh profile opened: imHungry` … `3. beats played: 7, care mini-games finished by gesture: 2` / `4. Bunny's hunger after: 0.0 (was 55.0)` / `5. mission_completed fired 1 time(s); tasks awarded: 7` / `6. saved: completed=true stars=3/3  lifetime stars=10` / `7. replay re-armed 'imHungry'; lifetime stars still 10` / `SMOKE PASS -- Mission 01 played end to end in the real house.` |
| `res://tests/smoke_mission01.gd -- snackTime` | `0. profile reset; 1 earlier level(s) marked played` / `1. fresh profile opened: snackTime` … `3. beats played: 8` / `6. saved: completed=true stars=3/3  lifetime stars=12` / `7. replay re-armed 'snackTime'; lifetime stars still 12` / `SMOKE PASS -- Mission 01 played end to end in the real house.` |
| `res://tests/smoke_audio_shipping.gd` | `2. shipped manifest: []` / `3. main.tscn in the tree -> state 'menu', track 'littleDaysTheme'` / `live player: /root/Audio/MusicVoice0 ... from=little_days_theme.ogg imported=true playing=true -16.9 dB` / `4. house_world.tscn in the tree -> state 'house'` / `5. mission 'imHungry' running -> state 'miniGame', track 'hungryBunny'` / `live player: /root/Audio/MusicVoice1 ... from=hungry_bunny.ogg ... playing=true` / `6. AudioStreamPlayers holding a music stream, whole tree: 1` / `7. 4 room transitions later: track 'hungryBunny', position 1.02 s -> 2.32 s, track_started fired 1 time(s)` / `speaking -> music -26.0 dB (duck gain 0.316), still playing=true` / `9. mid-crossfade menu -> miniGame: ["littleDaysTheme @ -15.3 dB", "hungryBunny @ -26.1 dB"] (fading=true)` / `10. muted -> playing=false, players holding music=0` / `SMOKE PASS -- both delivered tracks play in the real game, one at a time,` |
| QA house-music probe (headless, real `Audio` autoload) | `menu (main.tscn): state 'menu', track 'littleDaysTheme', is_playing_music=true, silent_build=false, live music players: ["MusicVoice0 playing=true pos=1.02"]` / `house Free Play (house_world.tscn): state 'house', track 'littleDaysTheme', is_playing_music=true ... ["MusicVoice0 playing=true pos=2.79"]` / `house after room change to kitchen: state 'house', track 'littleDaysTheme' ... ["MusicVoice0 playing=true pos=3.81"]` (same player, position only moves forward) |
| QA speech-backend probe (headless, plugin linked) | `has_singleton LittleBuddySpeech: true` / `backend: ios` / `available: true  permission: false` / `fallbackActive: false` / `nativeSingletonPresent: true` / `platform: macOS` (`ttsAvailable: false` is the headless artefact; the on-disk `speech_diag.json` from windowed runs says `ttsAvailable: true`) |
| QA splash timing probe (windowed, real `run/main_scene`) | `run/main_scene = res://scenes/splash/splash.tscn` / `t=0.02 s current_scene=res://scenes/splash/splash.tscn` / `t=1.72 s current_scene=res://scenes/main/main.tscn` / `SPLASH -> MENU hand-over at 1.72 s (limit 3.0 s): OK` (then `t=3.32 s current_scene=res://scenes/house/house_world.tscn` — the first-run auto hand-off, because this Mac's `user://profile.json` has no `onboardingDone`; by design, see AT1 notes) |
| QA menu probe (windowed, 1334x750) | `garden ambient time 1.43 -> 4.57 s; Node3Ds tracked 891; translated 517; rotated 558` / `frames per second while menu ran: 60` / `press FreePlayButton: signal returned in 233 ms; 4.2 s later scenes=["house_world.tscn", ...]; departure=phase=done elapsed=2.51; fps=60; current_scene=house_world.tscn` / `press DressUpButton: ... scenes=["dress_up.tscn", ...]; fps=60; current_scene=dress_up.tscn` / `press ParentButton: ... scenes=["parent_settings.tscn", ...]; fps=60; current_scene=parent_settings.tscn` / `press PlayButton: ... scenes=["baby_room.tscn", ...]; departure=phase=done elapsed=2.52; fps=46; current_scene=baby_room.tscn` / `MENU PROBE OK` |
| QA tap-through probe (windowed, real `baby_room.tscn` + `MissionRunner`, feedingTime) | `tap_item(apple): ok -- a plain tap did NOT deliver the apple (nudges=0, tapHelp=false)` / `real tap event: ok -- press+release at (667.0, 609.7944) did NOT deliver` / `real drag event: ok -- a real drag to the mouth DID deliver the apple; clip=eat` / `cup no hold: ok -- a cup released after 0.15 s (hold needs 1.2 s) did NOT deliver` / `cup held: ok -- holding 1.2 s DID deliver` / `after 1 nudge: ok -- one nudge: a tap still does NOT deliver` / `after 2 nudges: ok -- tap help offered after nudge #2` / `after 2 nudges: ok -- the touch fallback tap DID deliver` / `version: ok -- no version label visible in baby_room/highchair (found [])` / `TAPTHROUGH PROBE OK -- the highchair is not a tap-through` |
| QA off-navmesh tap probe (windowed, real `house_world.tscn` Free Play, `NavigationController.apply_tap`) | `apron (5 m off the mesh, in front): tap at (0.4, 7.0) accepted=true; moved 1.68 m in 3.0 s; frames rendered 181 (60 fps); busy=false` / `far behind the left wall: tap at (-6.0, -2.0) accepted=true; moved 2.73 m in 3.0 s; frames rendered 183 (61 fps); busy=false` / `ordinary floor tap afterwards: ... accepted=true; moved 2.08 m ... busy=false` / `OFFMESH PROBE OK []` |
| `shots_menu.gd` x5 (ipad, iphone, pressed, dressup mint, dressup iphone) | `MENU SHOT OK` each; `play caption: 'Start'`; `Aliz model available = true`; `swatch: mint  accent colour: (0.659, 0.902, 0.812, 1.0)` |
| `tools/branding_shots.gd -- 1334 750` | `BRAND SHOTS OK` (4 frames, `aspect 1.78`) |
| `shots_feeding.gd -- 1334x750` / `-- 2340x1080` | `FEEDING SHOTS OK -- 8 frame(s) at 1334x750.` / `FEEDING SHOTS OK -- 8 frame(s) at 2340x1080.`; every `_check_state` line `ok` (apple dragged, delivered, clip `eat`; banana unpeeled -> peeled; clip `drink` + cup tipped; `one mistake counted`, `Bunny's face is unhappy`, `half star`; `guided mode is on`; `session summary is up`) |
| `shots_settings.gd -- ipad 1334x750` / `-- iphone 2340x1080` | `SETTINGS SHOTS OK` both; `th helper: 'น้องบันนี่หิวแล้ว' (rtl=false)`, `ja helper: 'バニーのところへ行こう。'`, `ar helper: 'اذهب إلى الأرنب.' (rtl=true)`; `speech success: 'Great!' / 'You said: milk'`, `speech retry: 'Try again!' / 'I heard: banana. You can tap it too!'`, `speech unavailable: 'Voice is not ready' / 'Tap it instead!'` |
| `shots_ux.gd -- qa2_ux_ipad 1334 750 free` / iphone | `UX SHOTS OK` both; `badge_bedroom: disc 96 px on a 750 px tall frame` / `badge_bedroom: disc 138 px on a 1080 px tall frame`; `sofa_sit: origin (18.92, 0.03, -1.34), pose sit`; `locked_sign: SOON on bedroom.doorToBathroom` |
| `shots_ux.gd -- qa2_ux_ipad 1334 750` / iphone (default run) | `UX SHOTS FAIL:` / `  - door_enter: the layer shows 'SOON' on 'kitchen.doorToLivingRoom'; expected ENTER on kitchen.doorToLivingRoom` (both sizes; every other frame in the run asserted ok — see AT4: the living room IS locked in Free Play on a fresh profile, so the sign is correct and the harness expectation is stale) |
| `shots_ux.gd ... story` x2 | `UX SHOTS OK` both |
| `shots_carry.gd -- ipad` / `-- iphone` | `CARRY SHOTS OK` both; `after a walk: Bunny root at (0.008567, 0.359867, -0.279995) in her frame, state=held, socket=true, clip=carried, activity=carried` / `placed: floor gap 0.000 m, 0.59 m from her, carried=false, state=idle` / `hunger before 55.0, after 55.0` / `toy held at (0.246676, 0.579834, -0.069118) in her frame, socket itemHoldRight` / `toy placed 0.000 m from its pad` |
| `shots_rc.gd` x2 | `beat reached: 'feedBunnyCare'` / `RC SHOTS OK` (aspect 1.78 and 2.17) |
| `tools/aliz_shots.gd -- qa2_aliz idle` / `mood`; `tools/bunny_shots.gd -- qa2_bunny` | all `ok`; `moods: ["content", "happy", "surprised", "sleepy"]` (+blink); Bunny `moods: ["content", "unhappy", "delighted", "asleep", "hungry", "sleepy", "hmph"]  clips: [..., "carried", "celebrate", "drink", "eat", "fuss", "idle", "run", "sleep", "stamp", "walk"]` |
| `--headless --path game --import` | exit 0, no errors (one `cannot connect to daemon at tcp:5037` line = no adb, harmless) |

## AT1 — Home screen

| Sub-test | Result | Frame(s) | Notes / exact defect |
|---|---|---|---|
| Premium, colourful, non-empty | PASS | `qa2_menu_ipad.png`, `qa2_menu_iphone.png` | Storybook garden (11 trees, 51 flowers, 6 clouds, cat, butterflies, toys, mailbox, sign), pink cottage, Aliz + one Bunny, logo, four big pastel buttons. Readable at both sizes; iPhone safe-area composition is fine. |
| Animated (two frames 3 s apart) | PASS | `qa2_menu_anim_t0.png`, `qa2_menu_anim_t3.png` | Probe counted 517 garden Node3Ds translated and 558 rotated between t=1.4 s and t=4.6 s (`garden.tick` via its own `_process`); by eye the clouds have drifted, the butterfly by the sign moved ~90 px, canopies lean. 60 fps. |
| Start responds, no freeze | PASS | probe line | Departure walk plays (`phase=done elapsed=2.52`), hand-off to `baby_room.tscn` (story route, SaveService detached = non-first-run). 46 fps during the room load, back to 60. |
| Free Play responds | PASS | probe line | Departure, hand-off to `house_world.tscn`, 60 fps. |
| Dress Up responds and opens `dress_up.tscn` | PASS | `qa2_dressup_mint_ipad.png`, `qa2_dressup_iphone.png` | Opens the dress-up stage; swatch applies (mint hem/bow/shoes); Back button. Cosmetic: the bunting at the top edge is clipped by the frame at 1334x750. |
| Grown-ups responds, full gate card in standalone mode | PASS | `qa2_settings_gate_ipad.png`, `qa2_settings_gate_iphone.png` | `parent_settings.tscn` comes up as the gate card: "For grown-ups / Press and hold the bar for 3 seconds… / Hold for 3 seconds to open (Thai line) / Back to the game". |
| Version text only on the title screen | PASS | `qa2_menu_*.png` (present, `v0.1.0` bottom-right), `qa2_ux_*_home_version.png`, every house frame, every `qa2_feeding_*` frame (absent) | Probe: `version labels on title: [".../UI/SafeArea/VersionLabel 'v0.1.0' visible=true"]`; tap-through probe: `no version label visible in baby_room/highchair (found [])`. Note: the splash also prints `v0.1.0` bottom-right (`qa2_brand_splash_1334x750.png`) — branding screen, not the HUD; flagging in case "ONLY the title" was meant literally. |
| Splash is first scene, hands over within 3 s | PASS | `qa2_brand_splash_intro_1334x750.png`, `qa2_brand_splash_1334x750.png`, `qa2_brand_curtain_1334x750.png` | `run/main_scene = res://scenes/splash/splash.tscn`; hand-over at **1.72 s**. Observation, by design: on this Mac's fresh profile (no `onboardingDone`) the menu then auto-opens the house at 3.32 s (`FIRST_RUN_DELAY_SEC` first-run tutorial). A returning profile does not do this. |

## AT2 — Guided feeding (highchair)

| Sub-test | Result | Frame(s) | Notes / exact defect |
|---|---|---|---|
| Start on a non-first-run profile -> `baby_room.tscn` | PASS | probe line | `press PlayButton ... current_scene=baby_room.tscn`. |
| Apple: drag to mouth, Bunny bites (eat clip, sparkles) | PASS | `qa2_feeding_apple_drag_1334x750.png`, `qa2_feeding_apple_bite_1334x750.png` (+ 2340x1080) | Mid-drag apple lifted toward the mouth; bite frame: apple shrunk, yellow sparkle confetti, `clip=eat`, arms up. Cosmetic: during the eat clip the apple reads as sitting on his nose/cheek rather than at the lips. |
| Banana: peel then give | PASS | `qa2_feeding_banana_unpeeled_*.png`, `qa2_feeding_banana_peeled_*.png` | Unpeeled -> peeled (skin splayed) on tap; then drag delivers. |
| Cup/bottle: hold, Bunny drinks | PASS | `qa2_feeding_cup_drink_1334x750.png`, `_2340x1080.png` | `clip=drink`, cup tilt > 0.3, hands at the mouth, fill/hold works (probe: 0.15 s release does not deliver, 1.2 s hold does). Cosmetic: the tipped cup sits a little low, rim at the chin/hands rather than the lips, with the cup body overlapping the chest. |
| Wrong item -> head turn, unhappy face, "Try the apple!", half star | PASS | `qa2_feeding_wrong_item_1334x750.png`, `_2340x1080.png` | Head turned away, brows down, "Try the apple!" pill, star counter shows the half star; `get_mistakes()==1`, `CREDIT_HALF`. |
| Second mistake -> guided glow/arrow | PASS | `qa2_feeding_guided_1334x750.png`, `_2340x1080.png` | Apple plate glows, dotted arrow from Bunny down to the apple, `is_guided()==true`. |
| Success -> celebrate | PASS | `qa2_feeding_apple_bite_*`, summary | `celebrate` clip present; summary "Great job!". |
| NOT a tap-through | **PASS** | `qa2_feeding_tap_no_complete_1334x750.png` + probe lines | Public `tap_item("apple")`, and a real press+release `InputEventMouseButton` at the apple's screen position through the viewport input path, both leave the task open (`is_delivered=false`, hop only). Only the drag (or the 1.2 s hold for the cup) delivers. The touch fallback appears only after the second idle nudge (`NUDGE_IDLE_SECONDS 7.0` x `NUDGES_BEFORE_TAP_HELP 2`), and then it does deliver. |
| Summary card | PASS | `qa2_feeding_summary_1334x750.png`, `_2340x1080.png` | "Great job! / Milk Time", 3 glossy stars, "+5", "So close!" half star, Apple sticker card, Back / Replay / Next. ("Milk Time" is the `levelTitle` of `feedingTime` by design.) |

## AT3 — UI quality

| Sub-test | Result | Frame(s) | Notes / exact defect |
|---|---|---|---|
| Buttons/icons polished and readable at both sizes | PASS | `qa2_menu_*`, `qa2_feeding_*_2340x1080`, `qa2_ux_iphone_*` | Bevelled pastel buttons with glyphs, consistent chrome; text legible at 2340x1080. |
| Stars / reward / summary upgraded | PASS | `qa2_feeding_summary_*`, `qa2_feeding_wrong_item_*`, `qa2_rc_*_feed_done.png` | Glossy star sprites in the counter and the card, "So close!" half star, sticker card, "+N" line. |
| Settings opens/closes fast, Close top-right, Done bottom, scrolls | PASS | `qa2_settings_ipad.png`, `qa2_settings_bottom_ipad.png`, `qa2_settings_iphone.png`, `qa2_settings_bottom_iphone.png` | Music/Voice sliders, Voice practice On/Off, Speaking speed, Helper language (Off/ไทย/中文/العربية/हिन्दी/日本語), Teaching language, Check speech, Replay Mission 01, Reset progress, **Done** bottom-right, **Close** top-right; scrollbar visible. Observation: the "Family Club" block lists proposed prices (USD 2.99 / THB 99) with "Nothing can be bought in this app"; behind the 3 s gate, information only. |
| Gate passes with 3 s hold, Back works, never traps | PASS | `qa2_settings_gate_*.png`; suite `parent_gate`, `parent_settings_screen` | Hold bar + "Back to the game"; pause card offers Continue/Home/Grown-ups (`qa2_ux_*_pause.png`). |

## AT4 — Free Play

| Sub-test | Result | Frame(s) | Notes / exact defect |
|---|---|---|---|
| Move by tap, off-navmesh tap walks to nearest point, no freeze | PASS | `qa2_offmesh_apron_1334x750.png`, `qa2_offmesh_wall_1334x750.png` | 5 m off the mesh in front: accepted, walked 1.68 m to the room edge, 60 fps, not busy. 6 m behind the left wall: walked 2.73 m to the kitchen door (ENTER badge with door glyph shows there). Ordinary tap afterwards still works. Suite `click_to_move_freeze` PASS. |
| Carry Bunny | PASS | `qa2_carry_bunny_front_{ipad,iphone}.png`, `qa2_carry_bunny_quarter_*.png` | Held through the rig socket, one Bunny, PLACE badge now has a glyph and steps aside from her face. |
| Place Bunny on the bed (lies down) | PASS | `qa2_ux_{ipad,iphone}_bed_bunny.png` | Activity `bedtime`, lying on the mattress, one Bunny, "There you go!". |
| Place Bunny at the table | PASS | `qa2_ux_{ipad,iphone}_table_bunny.png` | At his table spot (asserted < 0.08 m). Cosmetic: in the frame he is mostly hidden behind Aliz (harness stands her between camera and table). |
| Wardrobe opens | PASS | `qa2_ux_*_wardrobe_open.png` | Doors open (asserted). Subtle visually. |
| Fridge opens | PASS | `qa2_ux_*_fridge_open.png`, `qa2_ux_*_fridge_take.png` | OPEN then TAKE badges on `kitchen.fridge`. |
| Toy box opens | PASS | `qa2_ux_*_toybox_open.png`, `qa2_ux_*_badge_bedroom.png` | Lid up, teddy inside. |
| Sink opens the wash close-up | PASS (cosmetic note) | `qa2_ux_{ipad,iphone}_sink_wash.png` | `care_kind=washFace`, no badge under the overlay, "Wash! / ล้างหน้า / Rub the cloth all over the face." Cosmetic: the close-up shows a flat drawn placeholder face (pink disc with dot eyes), not the rigged Bunny used by the feeding portrait; a stray mint disc is clipped at the top-left corner (0,10). |
| Locked bathroom/living room shows SOON, never ejects | PASS | `qa2_ux_{ipad,iphone}_locked_sign.png` (bathroom), `qa2_ux_{ipad,iphone}_door_enter.png` (living room) | Signpost glyph + "Soon! Ask a grown-up". `room_transition_controller.gd` refuses `locked` without moving her ("never moved, never ejected"). The default UX harness expects ENTER on `kitchen.doorToLivingRoom`; on a fresh profile the living room is locked, so its `UX SHOTS FAIL` is a stale expectation, not a game defect. |
| Badges ≈ 96 px at 1334x750, never over joystick/Home/Next/bubble | PASS | `qa2_ux_ipad_badge_bedroom.png` (`disc 96 px`), `qa2_ux_iphone_badge_bedroom.png` (`138 px`), all `qa2_ux_*`, `qa2_house_helper_*`, `qa2_speech_*` | No badge over the stick, Home, Next or a speech bubble in any frame. Bubble "I'm hungry, Aliz!" fully legible in every frame at both sizes (the previous build's HUG-over-bubble collision is gone). See the face collision under "Characters" / defects. |

## AT5 — Audio / voice / settings

| Sub-test | Result | Evidence | Notes |
|---|---|---|---|
| Music in menu AND house (`littleDaysTheme`) | PASS | smoke step 3; QA house-music probe | Menu `littleDaysTheme` playing; house Free Play `state 'house', track 'littleDaysTheme'` on the same `MusicVoice0`, position only advancing through a room change. |
| `hungryBunny` in the mission | PASS | smoke step 5 | `state 'miniGame', track 'hungryBunny' ... playing=true`. |
| One player, no restart across rooms | PASS | smoke steps 6, 7 | `holding a music stream, whole tree: 1`; `4 room transitions later ... position 1.02 s -> 2.32 s, track_started fired 1 time(s)`. |
| Settings has language + audio controls | PASS | `qa2_settings_ipad.png` | Music volume, Voice volume, Voice practice, Speaking speed, Helper language, Teaching language. |
| Helper languages th/ja/ar render (no tofu) | PASS | `qa2_house_helper_{th,ja,ar}_{ipad,iphone}.png` | Thai, Japanese and Arabic (RTL) glyphs all render. Cosmetic/l10n: the Thai helper under "Go to Bunny." reads "น้องบันนี่หิวแล้ว" ("Bunny is hungry now") while ja/ar translate "Go to the bunny". The helper line is small (~16 px at 1334x750). |
| Speech flow ends in exactly one of success/retry/unavailable | PASS | `qa2_speech_listening_*`, `qa2_speech_success_*`, `qa2_speech_retry_*`, `qa2_speech_unavailable_*` (both sizes); suite `speech_end_states` | Faces are staged through the panel's `set_state` (UI presentation) — no recogniser, mock or real, produced the "Great!" frame. |
| Backend `ios` with the plugin linked; mock never selected | PASS | probe lines; suite `speech_never_mocks_on_device` | `backend: ios`, `nativeSingletonPresent: true`, `fallbackActive: false`; `_select_backend()` reaches the mock only when no singleton and not `mobile`. |

## AT6 — Build readiness (headless only; export/APK/iOS are the lead's)

| Sub-test | Result | Line |
|---|---|---|
| Headless suite | PASS | `PASS - 140 case(s), 0 failure(s)` |
| `smoke_mission01.gd` | PASS | `SMOKE PASS -- Mission 01 played end to end in the real house.` (imHungry, 7 beats, 2 care games by gesture, stars 3/3) |
| `smoke_mission01.gd -- snackTime` | PASS | `SMOKE PASS -- Mission 01 played end to end in the real house.` (snackTime, 8 beats, stars 3/3, lifetime 12) |
| `smoke_audio_shipping.gd` | PASS | `SMOKE PASS -- both delivered tracks play in the real game, one at a time,` |
| Noise in the suite log | note | 30 x `ERROR: Can't use get_node() with absolute paths from outside the active scene tree` from `house_level_director.gd:274 bind` via `test_camera_activity_focus.gd` — a test-environment artefact, every case still PASS. |

## Characters

| Check | Result | Frame(s) | Notes / exact defect |
|---|---|---|---|
| Aliz idle / blink / hair sway | PASS | `qa2_aliz_idle_{0,1,2}.png` (three distinct frames), suite bone deltas quoted above | Head ±1.3 cm, hips up to 2.1°, spine up to 1°. Blink frame `qa2_aliz_mood_blink_close.png`. |
| Aliz face moods sheet | PASS | `qa2_aliz_face_sheet.png` (+ `qa2_aliz_mood_*_{close,far}.png`) | content, happy (open smile), surprised (o-mouth), sleepy, blink — all distinct; sleepy and blink are near-identical closed-eye faces (design choice). |
| Bunny moods: hungry pout, sleepy, happy, hmph, blink | PASS (cosmetic note) | `qa2_bunny_sheet.png`, `qa2_bunny_hungry_close.png`, `qa2_bunny_sleepy_close.png`, `qa2_bunny_*_{far,close}.png` | All nine cells distinct (md5 checked). Cosmetic: the hungry/hmph left eyebrow is drawn as a kinked two-segment stroke; sleepy/unhappy/happy eyelids carry a few 1–3 px black specks at the lash line (visible in the close-up, faintly in `qa2_rc_iphone_feed_done.png`). |
| Contact hint under feet, not a blob | PASS | `qa2_rc_ipad_feed_mid.png`, `qa2_ux_*_badge_bedroom.png`, `qa2_carry_bunny_placed_*` | Soft foot-shaped contact shadow under both characters. |
| No neck seam in the feeding portrait | PASS | `qa2_rc_{ipad,iphone}_feed.png`, `_feed_mid.png` | Clean. |
| No duplicate Bunny | PASS | every house frame, carry frames | One Bunny in every frame (he is absent from `qa2_ux_*_locked_sign.png` because the previous act put him down in the bathroom). |
| Nothing floating | PASS | all frames | Milk carton, apple, banana, toys all on the floor/rug; Bunny on the mattress; `placed: floor gap 0.000 m`. |
| No HUD text over a face | **FAIL (visible, medium)** | `qa2_house_helper_{th,ja,ar}_{ipad,iphone}.png`, `qa2_speech_*_{ipad,iphone}.png` (10 frames) | When Aliz stands directly in front of Bunny facing the camera, the CARRY affordance disc (pink circle + glyph) is drawn over Aliz's face; the "CARRY" pill sits under her chin. The bubble is clear. In the other staging (`qa2_ux_*_story_hug.png`, `qa2_carry_bunny_front_*`) the disc correctly steps aside to her left, so the dodge exists but misses this pose at both sizes. |
| No wrong-size PNGs | PASS | all 134 `qa2_*.png` measured | 86 x 1334x750, 46 x 2340x1080, 2 sheets. |

## Release-blocking vs cosmetic

**Release-blocking (crash / freeze / tap-through / wrong content / missing geometry): none found.**

**Visible — fix before the child sees it if there is time (not blocking the playtest):**

1. CARRY affordance disc over Aliz's face when she stands in front of Bunny facing the camera —
   `qa2_house_helper_th_ipad.png`, `qa2_house_helper_ja_iphone.png`, `qa2_speech_retry_iphone.png`
   and the other seven frames of that staging, both sizes. The disc hides her eyes; the verb pill
   sits under her chin. (Layer: `affordance_layer.gd` face-dodge; it works in the three-quarter
   pose, `qa2_ux_iphone_story_hug.png`.)
2. Wash close-up uses a flat placeholder face instead of the rigged Bunny —
   `qa2_ux_{ipad,iphone}_sink_wash.png`. Functional (gesture completes, no badge underneath) but
   it is the one close-up that does not look like the rest of the game; a stray mint disc is
   clipped at the top-left corner of the same frame.

**Cosmetic:**

3. Feeding: during the eat clip the apple overlaps Bunny's nose/cheek (`qa2_feeding_apple_bite_*`);
   the tipped cup sits at the chin/hands with its body over the chest (`qa2_feeding_cup_drink_*`).
4. Bunny face texture: kinked left eyebrow on hungry/hmph; a few black specks at the lash line on
   sleepy/unhappy/happy (`qa2_bunny_hungry_close.png`, `qa2_bunny_sleepy_close.png`,
   `qa2_bunny_sheet.png`).
5. Thai helper for "Go to Bunny." says "Bunny is hungry now" (`qa2_house_helper_th_*`); ja/ar
   translate the prompt. Helper line is small (~16 px at 1334x750).
6. Dress Up: bunting clipped at the top edge at 1334x750 (`qa2_dressup_mint_ipad.png`).
7. Table act composition: Bunny hidden behind Aliz in `qa2_ux_*_table_bunny.png` (harness staging).
8. Splash prints `v0.1.0` (a branding screen; the title screen also prints it; HUD and highchair
   do not) — only matters if "ONLY the title" is literal.
9. Default `shots_ux.gd` run: stale `door_enter` expectation (living room is locked in Free Play on
   a fresh profile, so SOON is correct). Harness, not game.
10. Suite log noise: 30 `Can't use get_node() with absolute paths` errors from
    `test_camera_activity_focus.gd` -> `house_level_director.gd:274`; all cases PASS.

**Observations that are by design but worth knowing for the playtest:**

- On a fresh profile (no `onboardingDone`, which is this Mac's `user://` state after the smokes
  reset it) the title screen auto-opens the first-run house ~1.6 s after it appears
  (`FIRST_RUN_DELAY_SEC`); pressing Start first also opens the first-run house. A returning
  profile shows Continue and routes to the story.
- The grown-ups panel's "Family Club" block shows proposed prices as information only, behind the
  3 s gate.

## Method notes

- Windowed harnesses on this Mac stalled twice mid-run while the Godot window was occluded
  (`shots_feeding.gd -- 2340x1080` idled for 10 min after the guided frame; `bunny_shots.gd`
  returned the same stale root-window image for its last 16 frames — md5-identical). Both
  reproduced clean on an immediate re-run and the frames cited here are from the clean runs. This
  is a capture-environment artefact (Metal drawable not presenting), not a game freeze: the
  SubViewport harnesses assert their own state before each shot and every assertion passed.
- The `shots_ux.gd` default, story and free runs write `qa2_`-prefixed names directly; the
  fixed-name harnesses were collected as described in the header. `git status` shows only the
  134 `qa2_*.png` files, this report, and the plugin `bin` symlink.
- Probe scripts (menu, splash timing, tap-through, off-navmesh tap, speech backend, house music)
  live in the session scratchpad, not in the repo; their verbatim output is quoted above.
