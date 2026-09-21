# QA playtest report -- head `71dd184` (independent, adversarial, headless)

Agent E, 2026-09-21. Read-only on `game/`. Every claim below comes from a run on this
Mac (`/Applications/Godot.app` 4.7.2, headless) against `feature/overnight-production-candidate`
at `71dd184`; the tutor, settings, carry and menu code is unchanged between `9fa46e6` and
`71dd184` (the later commits touch the free-play director, acts, care overlay and tests), and
the tutor/settings/carry/menu probes were re-run at `71dd184` anyway. Probe scripts and full
logs live in the session scratch dir
`/private/tmp/claude-501/-Users-hotkhwan-Projects-LittleBuddy/73706c1c-f6e4-484c-bf13-31f02dcdbe75/scratchpad/qa/`
(`probe_*.gd`, `*_71dd184.log`). Nothing here is a device claim: **no physical iPad or iPhone
was used.** A probe that could not run is marked NOT TESTED, never PASS.

## 1. The 13 owner acceptance items

| # | Owner item | Verdict | Evidence (probe -- verbatim line) |
|---|---|---|---|
| 1 | Enter Learn with Aliz | AUTOMATED PASS | `probe_menu`: `ch2-zero/LearnWithAlizButton: ... -> opened res://scenes/tutor/classroom.tscn` and `all-complete/LearnWithAlizButton: ... -> opened res://scenes/tutor/classroom.tscn`. Permission is now asked before the first lesson: `probe_tutor_mic`: `perm20s: after begin_lesson asked=1 pending=true state=idle banner=info` / `perm20s: after 20s state=idle starts=0 turns=0` / `perm20s: granted -> listening+live after 25 steps; starts=2 double=0 indicator=listening`. iOS export preset carries both privacy strings (`export_presets.cfg:38` `NSSpeechRecognitionUsageDescription`, `:44` `privacy/microphone_usage_description`). |
| 2 | Answer hands-free | NOT TESTABLE HEADLESS (mechanics AUTOMATED PASS; the device recogniser hearing a child is not) | With a device-like SpeechService (level 0 until a session opens, final with no partial): `probe_tutor_mic`: `finalNoPartial: listening+live after 25 steps (starts=2)` / `finalNoPartial: final-only 'animals' -> chosen after 0 steps; Aliz says 'Great! Let's learn Animals!'` / `finalNoPartial: first question mic reopened after 55 steps; starts=5 double=0` / `finalNoPartial: final-only 'cat' -> speaking after 5 steps: 'Great! It's a cat!' live=false`. 4 s cap five times: `caps5: 21.5 s silence: starts=6 stops=5 double=0 reopenings=5 armed=6 timeouts=5 refusedBusy=0`. **But** see BLOCKER B1: when nothing is ever heard, the lesson loops the same question forever -- the exact symptom the owner saw -- and never falls back to cards. |
| 3 | See recognition progress | AUTOMATED PASS | `probe_tutor_mic`: `partialTimeout: after partial banner=hearing indicator=hearing sessionState=child_speaking`; timeout after a partial re-arms without moving the lesson: `partialTimeout: timeout after partial -> re-armed after 0 steps; scene=listening banner=listening turns=4 double=0`; provider's own 6 s after-partial cap: `partialTimeout: 6.5 s after a partial: stops 3->4 starts 6->7 live=true scene=listening session=listening`. Indicator invariant ("Listening" only while the recogniser is open) held on every step except the two cases in B2/C1. |
| 4 | Hear Aliz respond | AUTOMATED PASS (synthesis path; audible output is a device matter) | `finalNoPartial: ... Aliz says 'Great! Let's learn Animals!'`, `... 'Great! It's a cat!'`; a late final while she speaks is dropped: `lateFinal: late final during Aliz -> turns 2->2 state=speaking`; the mic is closed while she speaks: `lateFinal: while speaking recognitionOpen=false live=false`. |
| 5 | Open and scroll Settings | AUTOMATED PASS | `input_settings_harness.gd` at 71dd184: `INPUT SETTINGS OK`, `EXIT=0`. My own cases, `probe_settings`: `dragFromClose: closeVisible=true scroll=258 closed=0 panelVisible=true closePressedDown=false sinkHits=0 unhandled=0`; `dragFromDone: scroll=0 closed=0 panelVisible=true gesture=NONE sinkHits=0 unhandled=0` (a drag on the pinned Done neither scrolls nor closes); `dragOnGateHold: holding=false progress=0.00 cardVisible=true panelVisible=false` (a vertical drag on the hold bar does not unlock); `jitterHold: holdingAfterJitter=true panelVisible=true`; nothing behind the panel got a touch in any case (`sinkHits=0`; the single `unhandled=1` was a mouse **release**, `InputEventMouseButton pressed=false`). Two-finger caveat in C3. |
| 6 | Carry Bunny 5x | AUTOMATED PASS | `probe_carry` (real house, real AffordanceLayer, events fed to its hit box): `carryFiveTimes: ["CARRY:true", "CARRY:true", "CARRY:true", "CARRY:true", "CARRY:true"]`; emulated mouse FIRST then touch: `mouseFirstTwin: verbBefore=CARRY performed=["CARRY|bedroom.littleBuddy|true"] carriedAtOnce=true carriedAfter1s=true carryState=held`; twin 130 ms apart (outside the 120 ms window): `twin130ms: performed=["CARRY|bedroom.littleBuddy|true"] carriedAtOnce=true carriedAfter1s=true`; touch index 1 while index 0 rests on the joystick: `secondFingerOnBadge: stickGrabbed=true performed=["CARRY|bedroom.littleBuddy|true"] ... carriedAfter1s=true`; a second tap 300 ms later (mid-lift): `doubleTap300ms: verbAt2nd=PLACE/bedroom.littleBuddy performed=["CARRY|...|true", "PLACE|...|false"] carryStateAt2nd=pickingUp carriedAfter1s=true` (put-down refused mid-lift, Bunny stays up); `putDownMidPickup: refusedDuring=true (state pickingUp) allowedAfter=true (state placing)`. |
| 7 | Place Bunny on bed | AUTOMATED PASS | `probe_carry`: `bedWithBunny: pickedUp=true carriedAfterBed=false activity=bedtime bunnyNodes=1 bunnyY=0.40 parent=Bedroom childAt=bed`. Bedtime routine (753e562): `probe_routes`: `bedtime: picked=true active=true activity=bedtime light 0.61->0.23 said=["There you go!", "Goodnight, Bunny! Sleep tight.", "Give me my teddy."]`; `bedtime: pick up off bed=true active=false light=0.61 activity=carried`. |
| 8 | Place at dining area | AUTOMATED PASS | `probe_house`: `seatAtTable: picked=true childAt=table activity=carried carried=false`; then a meal brought to the table opens the spoon close-up: `feed(table#1): kind=giveFood pick=HomeButton ... gestureFinished=true hunger 100->30 closed=true inputBack=true activity=carried` and `afterTable#1: childAt=table activity=carried` (he stays seated). |
| 9 | Enter feeding from Free Play | AUTOMATED PASS | `probe_house` (real house, Free Play director): `feed(bottle#1): kind=giveBottle pick=HomeButton hudIndex=6 careIndex=5 of 7 ... gestureFinished=true hunger 100->30 closed=true inputBack=true`. Fridge chooser (da1040e): `fridgeChooser: fridgeOpened=true cards=3 ids=["banana", "apple", "bottle"] cardSize=(260.0, 300.0) inputHeld=true homePick=HomeButton`; `fridgeChooser: pick apple -> ok=true held=apple open=false word='apple' said=["apple", "You have the apple!"]`. mashFood (7e91a51): `mashFood: kind=mashFood homePick=HomeButton ... finishedByGesture=true closed=true inputBack=true onCounter=mashedBanana`; `mashFood(replay): ... selfCompletedAfter=14.0s stillOpen=false`. |
| 10 | Replay feeding after completion | AUTOMATED PASS | Free Play, same session, twice at Bunny and twice at the table: `feed(bottle#2): kind=giveBottle ... hunger 100->30 closed=true`, `feed(table#2): kind=giveFood ... closed=true`; pantry refills: `after feed#1: fridge=["banana", "apple", "bottle"] counter=["spoon", "bowl"]`. Story replay via the picker: `probe_menu`: `all-complete/PlayButton/imHungry: ... pickerOpened=true ... -> opened res://scenes/house/house_world.tscn requested=imHungry freePlay=false`; `replayPays: added=0 starsByLevel[imHungry]=3 completed=true fails=[]`; `firstPlayPays: added=1`. Smoke: `7. replay re-armed 'imHungry'; lifetime stars still 10`. |
| 11 | Enter another room mini-game | AUTOMATED PASS | `probe_house`: `sinkWithBunny: picked=true opened=true kind=brushTeeth pick=HomeButton ... stillCarried=true`; `bathWithBunny: opened=true kind=washFace -> then opened=true kind=dryFace pick=HomeButton ... closedAtEnd=true bunnyActivity=bath carried=false`; `tidyLoop: start='Put the blocks away!' toys=4 allChosen->complete=true activeAfter=false restartSay='Put the circle away!' count 0->2 freshToys=4`; dressing (d6f011d): `dressing: clothes=2 picked=pajamas inHand=true carriedCategory=dressing -> outfit='pajamas' stillCarrying=false garmentBackHome=true`. Living-room toy box: see C5. |
| 12 | Open Settings from Bunny-care mode | AUTOMATED PASS | `probe_settings` (panel mounted by the real `HouseHud.open_grown_ups()`): `houseHud: panel mounted as ParentSettings index=1/2 gateCard=true panel=false standalone=false`; `houseHud: after hold panelVisible=true gateCard=false`; `houseHud: swipe on music slider -> scroll=300 slider 1.00->1.00 sinkHits=0`; `houseHud: scrolled to end: contentEnd=848 scrollEnd=848 footerTop=848` (last option not hidden by the footer); `houseHud: tap where Home is, under the panel -> pauseOpened=0`; `houseHud: Done -> closed=1 grownUpsOpen=false`. Home during the fridge chooser opens the pause card: `fridgeChooser: Home while chooser up -> pauseOpened=1 chooserStillOpen=true`. |
| 13 | Return Home safely | AUTOMATED PASS | HUD above every close-up (owner P0-6): every `feed(...)`, `sinkWithBunny`, `bathWithBunny`, `mashFood` and `fridgeChooser` line above reads `pick=HomeButton` with the HUD's index above the overlay's (`hudIndex=6 careIndex=5`); the pause card is re-raised above the close-up on open (`house_hud.gd:1028-1031`). Tutor: `background: after go_background live=false stops=2 state=background indicator=off sessionActive=false`; `background: return -> resumeCard=true live=false state=background`; `background: resume -> listening+live after 25 steps starts=4 double=0`. Menu Back keeps every button (suite `activity_picker` PASS). |

## 2. BLOCKERS (would still fail on a device), ranked

### B1 -- P1: a child who is never heard gets the same question forever; the cards never come
`probe_tutor_mic`: `silent30: 60 s of silence on question 's02_cat': turns 4->17 states={ "listening": 405, "speaking": 195 } step now 's02_cat' cards=[] starts=18` and
`silent30: lines heard: ... "What animal is this?" x13`. The desktop run with the REAL
`SpeechService` (see B3) shows the identical loop on the welcome:
`'Hi! What would you like to learn today?'` at 5.18 s, 9.59 s, 13.96 s, 18.34 s.

This is precisely the owner's P0-1 symptom ("looped the opening prompt"). The mic fix
(d9d365b) is real -- the recogniser now opens -- but if on the device it opens and decodes
nothing (wrong audio-session category, on-device recognition unsupported for the locale,
the child too quiet), the scene never reaches "Let's try together!" or the answer cards.

Root cause: `game/scripts/tutor/tutor_scene.gd:1225-1232` -- in `STATE_LISTENING`, after
`NO_SPEECH_PROMPT_SECONDS` (3 s) `_nudged = true; repeat_prompt()`; the repeated line ends in
`_after_turn()` -> `_start_listening()` (`tutor_scene.gd:878-881`), which resets
`_nudged = false; _timer = 0.0`, so `LISTEN_SECONDS` (8 s) and the `PHASE_TIMEOUT` /
`_choose_subject("")` branch are unreachable while hands-free is live. `test_long_pause_asks_again`
only checks that she asks once.

Suggested fix: keep `_nudged` (or a per-step repeat counter) across `repeat_prompt()`;
reset it only in `_open_step()` / `_choose_subject()`. After the second repeat with nothing
heard, run the existing `_think("", PHASE_TIMEOUT)` path and `_offer_answer_cards()` so the
touch fallback carries the lesson even with a live-but-deaf recogniser.

### B2 -- P2: unmute does not reopen the microphone on a device
`probe_tutor_mic`: `mute: unmuted -> mic reopened after -1 steps (-1 = not within 3 s); starts 2->2 ...`,
`mute: unmute #2 -> reopened after -1 steps starts 3->3`, and 39 indicator violations
`[mute] indicator=listening but recogniser CLOSED (speech.live=false, recOpen=false, scene=listening, session=listening, rearm=false)`.
After the child taps Mute then Mute again, the indicator says "Listening" but no session is
open until Aliz's next 3 s nudge repeats the question (`turns=["Hi! ...", "Hi! ..."]`).

Root cause: `game/scripts/tutor/voice/tutor_voice_session.gd:500-501` `mute(false)` calls
`_arm_recognizer_if_driven()` (`:749-751`), which arms only when `is_recognizer_driven()` --
i.e. when there is NO level source. The classroom always installs one on a device
(`tutor_scene.gd:548-551`, `Callable(speech, "get_input_level")`), so the branch never arms.
Suggested fix: in `mute()`, `elif _state == STATE_LISTENING: _rearm_left = 0.0` (or call
`_arm_recognizer()`, which already handles capture-only).

### B3 -- P2 (Mac editor/dev only, not the iPad): entering the classroom on this Mac uses the NATIVE recogniser, not the mock, and a bare Godot.app aborts on the permission ask
The custom `Godot.app` bundles the `LittleBuddySpeech` GDExtension on macOS
(`probe_singleton`: `has_singleton LittleBuddySpeech = true ... is_available -> true has_permission -> false`),
so `SpeechService._select_backend()` picks `ios` (`speech_service.gd:353-356`) and the
mock is never reached. Consequences measured:
* `probe_tutor_desktop_mock -- perm`: `request_permission()` on the native backend ->
  process exit 134; the crash report says
  `"termination" : {"namespace":"TCC","details":["... The app's Info.plist must contain an NSSpeechRecognitionUsageDescription key ..."]}`
  (`~/Library/Logs/DiagnosticReports/Godot-2026-09-21-131141.ips`, `-131940.ips`).
  `Godot.app/Contents/Info.plist` has `NSMicrophoneUsageDescription` only. Once TCC had
  recorded a grant (a later run), the classroom asked and got
  `4.81s svc.permission_result true`, then armed the real macOS recogniser
  (`diag: backend=ios permission=granted handsFreeLive=true ... armed=5 finals=0 partials=0`).
* So "does entering the classroom on a Mac open the mock and hear its canned milk?" -- **No.**
  With `SpeechService` re-selected to the mock by hand the classroom still ends up on `ios`
  because the autoload's `_ready()` re-runs `_select_backend()` when the loop starts.
  The iOS export preset is fine (both usage strings present), so this does not block the
  device; it blocks a Mac playtest of Learn with Aliz unless the editor bundle gets
  `NSSpeechRecognitionUsageDescription` (or `_select_backend()` prefers the mock on
  `OS.has_feature("macos")`).

### B4 -- P3: after the recogniser dies mid-lesson the banner says "Listening..." over a closed mic for 8 s
`probe_tutor_mic`: `unavailMid: right after: scene=listening sessionActive=false banner=listening indicator=off tapVisible=true` and `bannerSaidListeningFor=7.8s`.
The indicator and the Tap-to-talk button are honest; the top banner is not until the 8 s
`LISTEN_SECONDS` timeout. `tutor_scene.gd:1051-1056` `_on_session_ended()` calls
`_refresh_input_mode()` only. Suggested fix: when the session ends with
`recognition_unavailable` while `_state == STATE_LISTENING`, also set the banner to
`BANNER_NONE` (or go straight to `_start_listening()`, which now resolves to `awaitMic`).
Recovery afterwards is honest: `unavailMid: recogniser back, 15 s later: scene=awaitMic handsFreeLive=false` (hands-free stays latched off until the next lesson).

## 3. COSMETIC / design notes (no device failure expected)

* C1 -- One-frame indicator transient: `[finalNoPartial] indicator=listening but recogniser CLOSED (... scene=speaking, session=aliz_speaking, rearm=true)` -- `_update_indicator()` runs before the same frame's state change. Invisible at 60 fps.
* C2 -- Push-to-talk (permission denied, then granted in iOS Settings without relaunch): `deniedThenTap: after grant + tap: live=true state=listening starts=1 indicator=off`. The indicator node is hidden while Tap-to-talk is shown, so nothing wrong is visible; `_update_indicator()` (`tutor_scene.gd:1305-1322`) simply ignores `_push_to_talk_live` when the session is inactive.
* C3 -- Settings, two fingers: a second finger landing on an option while the first scrolls presses it: `twoFinger: scrollMid=120 scrollEnd=240 voiceOffPressed=1 voiceOffToggled=true`. `parent_settings.gd:361-364` / `:367-370` ignore `index != 0`, so the second touch reaches the Button. Behind a grown-ups gate; low risk. Nothing leaked behind the panel in any case.
* C4 -- Carry, second tap 0.22-0.45 s after the first (after `PRESS_SEC`, before `PICK_UP_SEC`): the badge already says PLACE, `perform_affordance` is refused mid-lift and the press is handed to the floor router (`doubleTap300ms: ... "PLACE|bedroom.littleBuddy|false"`). Bunny stays up; on a device Aliz may take a step toward the floor point under the badge while carrying him.
* C5 -- Living-room toy box: there is no badge at all, in either state (`probe_lr_badge`: `livingRoom.toyBox: actions=["play", "putAway"] verb= offer=<none>`; carrying: `verb= offer=<none>`), because `AffordanceRules.verb_for_target` has no word for `play`/`putAway` without storage. A carried prop arriving there does go in (`livingRoomToyBox(carrying ball): ... act={ "handled": true ... } stillCarrying=false drops 0->1`); empty-handed it is still decorative (`act={ "handled": false }`). So "no longer a dead badge" is literally true (no badge), but P0-4 is only half answered for this prop.
* C6 -- Tapping Bunny while holding a non-garment prop (teddy) does nothing and says nothing: `tapBunnyHoldingProp: layerVerb=/ bunnyOffer=[] act={ "handled": false, "say": "" } ... stillHoldingTeddy=true` (`child_actor.gd:1308-1310`, `house_freeplay_acts.gd` `ACT_NONE`). By design ("hands full"), but a silent dead tap for a four-year-old; a one-line "My hands are full!" would help.
* C7 -- Bedtime: leaving the bedroom ends the night (light back to 0.61) but Bunny's activity stays `bedtime` (`bedtime: left the room -> active=false light=0.61 ... bunnyActivity=bedtime`); harmless, he wakes on the next pick-up.
* C8 -- Picker lists 9 cards (`imHungry, snackTime, goodMorningRoutine, morningRoutine, breakfastTime, toddlerPlayTime, tidyAndBedtime, sayItChallenge, brushMyTeeth`); the test's expected list names 7. Fine if the last two are meant to be offered.

## 4. Diagnostic overlay (task 2), by code path

* `tutor_hud.gd:563-565` `toggle_diagnostics()` returns `false` before doing anything when `not OS.is_debug_build()`; the overlay node is created only inside that function (`:568-573`), and `DiagCatcher` is added only under `if OS.is_debug_build():` (`:336-343`). A release build therefore has neither node. (`test_diagnostics_overlay_is_dev_only` asserts the same; this Mac is a debug build so only the debug branch ran.)
* `tutor_scene.gd:1257-1259` `_tick_diagnostics()` returns before any file write unless `OS.is_debug_build()`; `user://tutor_diag.json` (`:1270`) is the only writer.
* Transcript content: `tutor_voice_session.gd:178-180` `_diag` holds counters and two reason/terminal strings (`lastRecognitionEnd`, `lastRefusal`); `diagnostics()` (`:338-357`) adds states/flags/level; the scene adds `heard = "%d times, last %d chars"` (`:1291`), never text. The overlay (`tutor_diagnostics_overlay.gd:41-57`) renders only those keys. `show_partial()` writes to the banner label only (`tutor_hud.gd:462-470`). Nothing in either dict is a transcript.

## 5. Gate lines, verbatim (head `71dd184`)

`Godot --headless --path . --script res://tests/run_tests.gd`
```
PASS - 159 case(s), 0 failure(s)
EXIT=0
```
`SCRIPT ERROR` lines in the suite log: **0**. Non-fatal warnings unchanged from before today (`WARNING: AffordanceLayer: bedroom_odd:<...> offered unknown verb 'juggle'; ignored.` from `test_affordance`'s deliberate bad provider; `WARNING: tutor provider failed: backend unreachable` from `test_tutor_scene`'s provider-failure case).

`res://tests/smoke_mission01.gd`
```
1. fresh profile opened: imHungry
3. beats played: 7, care mini-games finished by gesture: 2
4. Bunny's hunger after: 0.0 (was 55.0)
5. mission_completed fired 1 time(s); tasks awarded: 7
6. saved: completed=true stars=3/3  lifetime stars=10
7. replay re-armed 'imHungry'; lifetime stars still 10
SMOKE PASS -- Mission 01 played end to end in the real house.
EXIT=0
```
`res://tests/smoke_mission01.gd -- snackTime`
```
1. fresh profile opened: snackTime
3. beats played: 8, care mini-games finished by gesture: 0
5. mission_completed fired 1 time(s); tasks awarded: 8
6. saved: completed=true stars=3/3  lifetime stars=12
7. replay re-armed 'snackTime'; lifetime stars still 12
SMOKE PASS -- Mission 01 played end to end in the real house.
EXIT=0
```
`res://tests/smoke_audio_shipping.gd`
```
1. licence override: disarmed (unverified music is silent, which is the shipping default)
2. shipped manifest: []
3. main.tscn in the tree -> state 'menu', track 'littleDaysTheme'
5. mission 'imHungry' running -> state 'miniGame', track 'hungryBunny'
10. muted -> playing=false, players holding music=0
SMOKE PASS -- both delivered tracks play in the real game, one at a time,
              they duck for English, and a pending manifest stays silent
              because no licence evidence has been supplied.
EXIT=0
```
`res://tests/input_settings_harness.gd`
```
INPUT SETTINGS OK
EXIT=0
```

## 6. Probe inventory (all in the scratch `qa/` dir)

| Probe | What it drives | Result file |
|---|---|---|
| `probe_tutor_mic.gd` | real `classroom.tscn`, device-like `SpeechService` stand-in; permission after 20 s, final w/o partial, partial then timeout, unavailable mid-lesson, late final, background/foreground, mute/unmute, 4 s cap x5 (session alone), 60 s silence, denied-then-tap; per-step indicator invariant | `probe_tutor_mic_71dd184.log` |
| `probe_tutor_desktop_mock.gd -- mock/perm` | classroom with the REAL `SpeechService` autoload on this Mac, live frames | `probe_desktop_mock.log`, `probe_perm_native.log` |
| `probe_singleton.gd` | which native singletons exist headless | (stdout) |
| `probe_settings.gd` | `parent_settings.tscn` in a SubViewport with real pushed input; drags from Done/Close/gate card, two fingers, opened via `HouseHud.open_grown_ups()`; a STOP sink and an `_unhandled_input` listener behind it | `probe_settings.log` |
| `probe_carry.gd` | real house + real AffordanceLayer hit box; mouse-first twin, 130 ms twin, 300 ms double tap, index 1 with index 0 on the stick, Bunny while holding a prop, bed, put-down mid-lift, 5 carries | `probe_carry_71dd184.log` |
| `probe_menu.gd` | real `main.tscn`; ch2/zero and all-complete profiles; every button; replay pays 0 | `probe_menu_71dd184.log` |
| `probe_house.gd` | Free Play: bottle x2 at Bunny, mash x2 at table, bottle at table, sink, bath+towel, tidy loop, living-room box; HUD Home pick mirrored from `test_hud_hit_order.gd` while each close-up is open | `probe_house_71dd184.log` |
| `probe_routes.gd` | 7e91a51+ routes: fridge chooser (+Home), mashFood (+replay self-completion), bedtime (+leave room), dressing, living-room badge | `probe_routes_71dd184.log` |
| `probe_lr_badge.gd` | toy-box verb in both rooms, empty-handed and carrying | `probe_lr_badge.log` |

Not exercised (would need a device or a windowed run): the iOS plugin actually decoding a
child's voice, audible TTS/voice-pack output, real multi-touch on glass, the render of any
screen. Everything marked PASS above is the game's logic on the real scenes, driven headless.
