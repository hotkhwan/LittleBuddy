# Owner physical playtest — bugfix report, 2026-09-21

Branch `feature/overnight-production-candidate`. Integrated HEAD: **see §7**.
Base of this sprint: `fe15a62`. Every automated result below ran on this
MacBook; **nothing below is a physical-device result**. §6 lists the owner's
thirteen acceptance items with the only honest status this session can give.

## 1. Root causes found (all confirmed in code before any change)

### P0 — Learn with Aliz did not hear the player
1. **Microphone deadlock on a device.** On iOS the input level exists only
   while a recognition session is open: the plugin installs its audio tap
   with the request (`ios/speech_plugin/src/little_buddy_speech.mm`
   `installTapOnBus` inside `startListeningWithLocale`, `inputLevel = 0`
   otherwise) and `SpeechService.get_input_level()` returns 0 without a live
   session. The hands-free session opened the recogniser only when its VAD
   saw a level (`tutor_voice_session.gd` `EVENT_SPEECH_STARTED →
   begin_listening`). So the VAD waited for the microphone and the
   microphone waited for the VAD: the banner said Listening, the child spoke
   to a closed mic, and the classroom's 3 s / 8 s timers re-asked the
   question. Not caught by tests because they injected a constant level or
   simulated clips. **Fix:** the recogniser is armed the moment the session
   listens, re-armed after its own 4 s silence cap and after any refusal,
   and a decoded answer is heard with no VAD event at all; the VAD (fed by
   the now-live tap) still marks speech start/end. Regression test
   `_test_device_microphone_opens_without_a_level` fails on the old code
   (`starts=0`) and passes now.
2. **No permission prompt ever appeared** (owner: "ไม่มี noti ให้ไปเปิด allow
   microphone"). iOS only shows its microphone / speech-recognition prompt
   when the app calls `requestAuthorization`; nothing on the classroom path
   did (the old feeding room did). With the deadlock the plugin never even
   tried to open the mic, so iOS was never asked. **Fix:** the classroom asks
   before its first lesson when the recogniser exists but has no permission,
   waits for the answer (nothing starts, nothing loops), then starts. A
   refusal falls back to tap + cards, the banner never says Listening over a
   closed mic, and a grown-up is told the path in words: Settings → Little
   Days. The app cannot switch the permission on by itself; no app can. iOS
   allows one system prompt, and after a refusal only the Settings app can
   change it. Test `_test_permission_is_asked_before_the_first_lesson`
   covers both answers.
3. **Recogniser became unavailable but hands-free stayed "on".**
   `hands_free_available()` re-read `is_available()` after a permission
   failure, so the scene re-entered Listening. **Fix:** an unavailable
   recogniser latches hands-free off until the next session start.
4. Android: the APK declares no `RECORD_AUDIO` and has no speech backend on
   purpose (`docs/GOOGLE_PLAY_RELEASE_READINESS.md` §0/§3). Hands-free on
   Android is **not available and is not claimed**; the classroom shows a
   one-line "Voice is not ready on this device" note and the picture cards
   carry the lesson.
5. Not the cause, checked: the tutor never used the mock provider on a
   device (`_select_backend` refuses the mock under `OS.has_feature("mobile")`);
   the opening prompt was re-queued by the scene's no-speech timers, not by
   the long-pause path; response audio did not reset the session.

### P0 — Recognition diagnostic overlay (development only)
Five quick taps on the mic indicator in a **debug build** open a dark panel:
Speech provider / Permission / Capture + level / VAD / Recognition (open,
armed, partials, finals, timeouts, refusals) / Session / Lesson / Audio.
Debug builds also write `user://tutor_diag.json` every 3 s during a lesson.
States, counts and flags only; never a transcript (test
`_test_diagnostics_overlay_is_dev_only` scans the snapshot for words). A
release build has no catcher, no node and writes nothing. Owner instructions:
`docs/IPAD_QUICK_CHECK.md` → "If Aliz does not hear you".

### P0 — Settings cannot scroll
The right 40 % of every row is `MOUSE_FILTER_STOP` (four 420 px sliders and
every option button), so a finger drag there never reached the
ScrollContainer, and a vertical drag on a slider changed a volume instead.
The stock scrollbar was 8 px. Stars / Reset / Done sat 500 px below the fold.
**Fix:** an `_input()` gesture recogniser scrolls under any finger (a press
stays a tap; a scroll that began on a slider restores the slider); a 48 px
scrollbar; the footer (stars, Reset progress, Done) is pinned outside the
scroll area; the panel now stops touches leaking to the joystick and
click-to-move behind it. Real events are pushed through a SubViewport in
`tests/input_settings_harness.gd` (`INPUT SETTINGS OK`).

### P0 — Gear / round icon does nothing
Two different screens. (a) On the Bunny-care close-up the care overlay is a
full-rect `MOUSE_FILTER_STOP` control mounted after the HUD in the same
CanvasLayer, so it won every pick: Home (and Next, the child's way out)
looked live and did nothing. **Fix:** both directors re-raise the HUD above
the close-up after mounting it (`test_hud_hit_order.gd` picks the Home
button through both orders). (b) The Baby Room corner gear was a 3 s hold
with no hint, cancelled by finger jitter. **Fix:** a tap opens the gate card
(which explains the hold and has Back); the hold tolerates a 40 px wobble.
Returning from Settings restores the held world (unchanged path).

### P0 — Bunny carry unreliable
`project.godot` emulates a mouse from touch, so one finger delivers a touch
press AND a synthetic mouse press to the badge; `affordance_layer.gd
_on_hit_input` had no twin latch (every other pointer consumer had one), and
`child_actor.perform_affordance` re-derives the verb per call: first = carry,
second (same ms) = place, and `carry_controller.put_down()` accepted a
put-down during `pickingUp`. Lift, then drop. Intermittent because the twin
exists only for the first touch index (a thumb resting on the joystick
suppresses it). Also: the carried child's own PLACE badge always outranked
the bed/table/bath (facing bonus), and the badge moved every frame so a
near-miss walked her to Bunny and did nothing. **Fix:** twin latch + 220 ms
debounce + put-down refused mid-pickup; carried child offers PLACE at prop
priority so a reachable surface wins; badge frozen while a press is live and
250 ms placement hysteresis; arriving at Bunny empty-handed carries him.
Six regression tests including rapid taps and the touch/mouse twin.

### P0 — Navigation and naming
"Continue" is gone. The card reads exactly **Play with Bunny** and opens an
activity picker built from content (nine ch3 missions today, imHungry first)
with 0–3 star ratings; every entry stays selectable after completion. A
picked card starts THAT mission in the house (`start(mission_id)`,
`set_requested_mission_id`). It never opens the Baby Room. Learn with Aliz,
Free Play, Dress Up and Grown-ups are unchanged and reachable.

### P0 — Feeding replay
Route 1: Play with Bunny → I'm Hungry! / Snack Time! at any time. A replay of
a finished level pays 0 lifetime stars at the director's award seam; the
level rating and the summary still work. Route 2: Free Play → seat Bunny at
the table (or bring him a meal): the real bottle close-up (or the spoon-fed
`giveFood` copy for mashed banana / fruit bowl) opens on his real mouth, and
the pantry restocks so it replays in the same session.

### P0 — Free Play mini-games (per route)
| Route | Status | What the child does |
|---|---|---|
| Fridge | REAL | picture-card chooser of what is inside; the word is spoken on the pick |
| Kitchen counter | REAL | banana / fruit-bowl → `mashFood` close-up (hold, then stir) |
| Toy box (bedroom) | REAL | lid opens, 3–4 toys scatter, each put away is praised by name, "All tidy!"; replays |
| Toy box (living room) | fixed | dead OPEN badge removed; a carried toy goes in |
| Wardrobe | REAL (minimal) | pajamas / red shirt come out; brought to Bunny they go on him; doors put them away |
| Dining + Bunny | REAL | feeding close-up, see above |
| Bath + Bunny | REAL | wash face, then the towel (`dryFace`) |
| Sink + Bunny | REAL | brush teeth (stroke counting); bathroom sink no longer reads PLACE |
| Bed + Bunny | REAL | night glow, "Goodnight, Bunny!", teddy request, back to day |

Known gap: while carrying a garment the badge at Bunny reads HUG though the
act dresses him (no DRESS verb in the rules yet).

## 2. What was NOT done
- No physical device run of any kind. See §6.
- Cloud tutor stays disabled (`little_days/ai_tutor/cloud_enabled=false`);
  no OpenAI call was made or is possible from the build.
- No Meshy spend (0 credits), no monetization, no Dress Up screen changes.
- Barge-in on a real device: the mic is closed while Aliz speaks (no
  self-hearing risk); the echo-cancelled keep-open path is not enabled.


## 5. Spending
Meshy 0 credits. OpenAI $0 (no key, no call).

## 6. Owner acceptance — status this session can honestly give
| # | Item | Status |
|---|---|---|
| 1 | Enter Learn with Aliz | AUTOMATED PASS (menu card → classroom; permission asked first on a device) |
| 2 | Answer a supported question hands-free | AUTOMATED PASS (device-like recogniser: mic opens with level 0, "animals" heard, subject chosen) — DEVICE: NOT TESTED |
| 3 | See recognition progress | AUTOMATED PASS (indicator / hearing banner / partials; dev overlay) — DEVICE: NOT TESTED |
| 4 | Hear Aliz respond appropriately | AUTOMATED PASS (scripted turns) — DEVICE: NOT TESTED |
| 5 | Open and scroll Settings | AUTOMATED PASS (`INPUT SETTINGS OK`, footer pinned) — DEVICE: NOT TESTED |
| 6 | Carry Bunny reliably five times | AUTOMATED PASS (twin, rapid taps, mid-pickup put-down) — DEVICE: NOT TESTED |
| 7 | Place Bunny on the bed | AUTOMATED PASS (bedtime pose, one Bunny) — DEVICE: NOT TESTED |
| 8 | Place Bunny at the dining area | AUTOMATED PASS — DEVICE: NOT TESTED |
| 9 | Enter feeding from Free Play | AUTOMATED PASS (close-up opens, hunger 100 → 30) — DEVICE: NOT TESTED |
| 10 | Replay feeding after completion | AUTOMATED PASS (picker and Free Play routes; 0 lifetime stars on replay) — DEVICE: NOT TESTED |
| 11 | Enter another room mini-game | AUTOMATED PASS (bath, sink, toy box, bed, counter, fridge, wardrobe) — DEVICE: NOT TESTED |
| 12 | Open Settings from Bunny-care mode | AUTOMATED PASS (Home above the close-up → pause → Grown-ups) — DEVICE: NOT TESTED |
| 13 | Return Home safely | AUTOMATED PASS (smokes, no-dead-end guards) — DEVICE: NOT TESTED |

## 7. Final numbers

**Final code commit: the one after `f8f2552` carrying this section** (only this
document changed after `f8f2552`). Independent QA ran on `71dd184`
(`docs/QA_PLAYTEST_71dd184.md`): 11 of 13 acceptance items AUTOMATED PASS,
item 2 (hands-free hearing on a real device) NOT TESTABLE HEADLESS, and four
blockers. B1 (a mic that opens but never decodes made Aliz repeat the same
question every 4.5 s forever — the owner's exact symptom shape), B2 (unmute
never reopened the mic on a device) and B4 (Listening banner stayed up after
the recogniser dropped) are fixed in `f8f2552` with a regression test that
fails on the old code. B3 is Mac-only: the custom Godot.app bundles the
native recogniser, so the Mac editor never uses the mock and a bare Godot.app
aborts on the permission prompt (its Info.plist lacks
`NSSpeechRecognitionUsageDescription`); the iOS export has both strings.

| Gate on `f8f2552` | Result |
|---|---|
| Godot suite | **PASS - 159 case(s), 0 failure(s)** (fe15a62 had 157) |
| Mission 01 / Snack Time walkthroughs | SMOKE PASS / SMOKE PASS |
| Audio shipping smoke | SMOKE PASS |
| Settings real-input harness | INPUT SETTINGS OK |
| Backend | 126 pass, 0 fail |
| Tutor / free-play / carry / menu shot harnesses | PASS (frames in docs/shots) |

| Build from `f8f2552` | Path | Size | Note |
|---|---|---|---|
| Android debug APK | `build/android/LittleDays-debug.apk` | 44,067,163 B | SHA-256 `6a0f2b84f8b2208d4ae093f893c5d355e711ade9cb220d7e2f75da352090127a`, signed, **zero permissions** (no microphone on Android by design) |
| iOS export | `build/ios/LittleBuddy.xcodeproj`, `build/ios/LittleBuddy.pck` | pck 15,148,824 B | mic + speech usage strings present; owner signs in Xcode |
| iOS arm64 compile | `xcodebuild … CODE_SIGNING_ALLOWED=NO` | — | `** BUILD SUCCEEDED **` |

Remaining known items: QA cosmetics (a second finger can press an option
while the first scrolls Settings; the living-room toy box has no badge when
empty-handed; tapping Bunny while holding a teddy is a silent tap; the picker
shows nine cards; the free-play feeding portrait frames wider than Mission
01's). Barge-in with the mic open during Aliz's speech is not enabled on
devices. **Everything above is automated evidence; the owner's device run is
the next step and the only thing that can turn AUTOMATED PASS into DEVICE
PASS.**
