# QA — Aliz Tutor Mode, integrated build `a8a2e1f` (branch `wt4/qa`)

Date: 2026-09-21. Godot 4.7.2.stable (Metal, Forward Mobile), macOS, Node 22.15.0.
Method: full headless suite, both mission smokes, audio shipping smoke, backend
`npm test`, a DEV_MODE curl transcript, the project's own harnesses
(`shots_menu`, `shots_tutor`, `aliz_tutor_shots`, `shots_tutor_settings`,
`demo_tutor_voice_session`) and three QA-owned windowed probes that drive the
real classroom scene through `TutorVoiceSession.simulate_child_audio()`
(capture-only under the scene, the real VAD / echo-gate / barge-in path) with a
timestamped state timeline. Every frame below was written from a `SubViewport`
of the stated size, the PNG size read back and asserted, and opened and looked
at. Nothing in the repo was changed; all new files are `docs/shots/qa3_*.png`
and this report. Nothing was committed.

**Verdict: NOT releasable as-is.** Two release-blocking defects in the
classroom scene's barge-in handling (B1, B2). Everything else passes; the rest
of the findings are cosmetic or tooling.

## Summary table

| # | Item | Result | Evidence (frames / lines) |
|---|---|---|---|
| 1 | Entry: "Learn with Aliz" 240×240 card top-left on the title, routes to `res://scenes/tutor/classroom.tscn`, version only on the title, no freeze | **PASS** | `qa3_title_ipad.png` 1334×750, `qa3_title_iphone.png` 2340×1080 (harness: `shot qa3_title_ipad.png 1334x750`, `MENU SHOT OK`). `main.tscn` `LearnWithAlizButton` offset 0,0→240,240; `main.gd:355 TUTOR_SCENE = "res://scenes/tutor/classroom.tscn"`; `test_menu_wow` presses the real button (PASS). Version `v0.1.0` bottom-right of the title only; no version label in any classroom frame. |
| 2 | Classroom: Aliz seated across the table, furniture/props present, four Meshy props visible, one `DirectionalLight3D`, ≤ 40k triangles, HUD = Home, Mute (obvious), Repeat, Picture card, End lesson, mic indicator; no HUD over the face at either size | **PASS** | `qa3_class_cat_question_1334x750.png`, `qa3_class_cat_praise_speaking_2340x1080.png`. Probe: `room triangles: 16221 whole scene: 20112`; `prop table_set/fruit_set/cat_dog/number_blocks source=glb`; `lights: ["DirectionalLight3D(shadows=false)"]`; `env: ssao=false ssr=false glow=false sdfgi=false fog=false vol_fog=false`; `hud buttons: ["home","end","mute","tapToTalk","repeat","card"]`. Face rect 1334×750 `P(616,324) S(102,117)`; 2340×1080 `P(1097,467) S(146,168)`; banner/subtitle sit above y=120, controls below y=540 — nothing over the face in any of the 34 classroom frames. `test_tutor_scene::_test_nothing_covers_alizs_face` PASS at both sizes. |
| 3a | Hands-free loop: welcome → subject choice → lesson; correct answer progresses | **PASS** | Probe A timeline: `Aliz: Hi! What would you like to learn today?` → child "animals" → `Great! Let's learn Animals!` → `Yay! Let's learn about animals!` → `What animal is this?` (card=cat) → child "It's a cat!" → `thinking` 0.45 s → `Great! It's a cat!` → `celebrate (banner=success)` → `Can you make a cat sound?` → "Meow!" → `Meow! You're amazing! [happy/clap/next_question]`. `qa3_class_success_banner_1334x750.png` shows "Great job!". |
| 3b | Wrong answer → encouragement → hint → third miss teaches; never "wrong" | **PASS** | Probe B, dog step, three misses: `Almost! Let's try together! What animal is this? [encouraging/tilt/retry]` → `Here is a hint. It says woof. It wags its tail. A dog! [encouraging/point/give_hint]` → `Let's say it together. It's a dog! Say dog. [encouraging/nod/next_question]` → moves on to `Can you make a dog sound?`. Frames `qa3_class_miss1_encourage_1334x750.png`, `qa3_class_miss2_hint_1334x750.png`. |
| 3c | Cough ignored (no turn, mic stays open) | **PASS** | Probe A: cough clip at 10.63 s → no `child_speaking`, no `thinking`, `capturing=true`; the only later line is the scene's own 3 s no-speech re-prompt of the same question. Suite: `cough 80 ms -> [["burst_ignored", 300.0]]`; `test_tutor_scene`: "a cough must not count as an attempt" PASS. |
| 3d | Pause mid-sentence not cut | **PASS** | Probe A: `pause_then_finish` clip (450 ms speech, 700 ms gap, 500 ms speech) → one `child said` event, one transcript "It's a cat!", one reply. Suite: `pause 700 ms mid-sentence -> [["speech_started", 220.0], ["speech_ended", 2650.0]]`. |
| 3e | Barge-in: Voice stopped, mouth 0 ≤ 120 ms, listening face ≤ 200 ms, interjection evaluated, no overlap | **PASS (timing)** / see B1 for the *result* | Probe A/B (scene): child starts 25.58 s, session `aliz_speaking -> interrupted` 25.78 s (200 ms echo-gate hold); at the `barge_in` signal `synth_speaking_at_detect:false`, `mouth_then:0.0`, `listening_face_ms:3.104`, `mouth_zero_ms:3.104` (first polled frame). Demo: `BARGE-IN { "toVoiceStopMs": 0.214, "toMouthZeroMs": 0.215 }` 170 ms after the clip started. Suite: `barge-in timing: fired 200 ms after the child started; Voice.stop after 0.003 ms; mouth 0 after 0.005 ms`; face: `barge-in proof: listening face at 0 ms, mouth 0 at 17 ms, gesture cancelled at 200 ms`. No overlapping replies in any timeline (every `Aliz:` line starts after the previous `aliz_speaking -> listening`). `qa3_class_interrupted_1334x750.png` shows "I'm listening!" / "I hear you!". |
| 3f | Owner dialogue end to end (engine, provider, hands-free session, scene) | **FAIL in the scene** (B1) | Engine (`test_tutor_lesson`) prints the full owner dialogue incl. `Child: Wait! I want a dog!` → `Aliz: Okay! Let's see the dog!` → `Aliz: What animal is this?` → `Child: Dog!`. Hands-free session (`test_tutor_voice_session`, demo): same, `Okay! Let's see the cat!` → `What animal is this?`. **Classroom scene:** `Okay! Let's see the dog! [happy/nod/jump_step]` → back to listening with the **cat** card, no dog question; see B1. |
| 4 | Aliz animation: 6 expressions, mouth follows envelope and closes ≤ 120 ms after silence, blink continues, gesture strips, tutor-state strips, locomotion unaffected | **PASS** | `qa3_aliz_expressions_sheet.png` (neutral/listening/thinking/happy/encouraging/smile, all distinct), `qa3_aliz_mouth_sheet.png`, `qa3_aliz_envelope_strip.png` (frames `[t,target,frame]`: `[0.083,0.15,1] [0.158,0.99,3] [0.243,0.08,2] [0.320,0.02,0] [0.401,0.99,3] [0.565,0.0,0]`), `qa3_aliz_gesture_{nod,tilt,point,clap,wave}_strip.png`, `qa3_aliz_state_{interrupted,explaining,celebrating}_strip.png`. Suite: silence at 0.75 s → `frame changes: … [0.8, 2], [0.85, 0]` = closed 100 ms after silence; `blink` assertions in `aliz_tutor_face` PASS; both mission smokes `SMOKE PASS -- Mission 01 played end to end in the real house.` |
| 5 | Flashcards: every allowlisted id renders; unknown id falls back; board shows the current card | **PASS** | `qa3_flashcards_all_1334x750.png` — all 13 ids drawn (apple, banana, cat, dog, one, two, three, blue, green, red, yellow, orange, grapes). Validator on `assetId:"dinosaur_green"`: `valid=false`, coerce → `{"speech":"Let's try together!","emotion":"encouraging","gesture":"tilt","visual":{"type":"none"},"lessonAction":"retry"}`; fixture `visual.assetId:not_allowed` PASS in both suites. Board: `accepted 13/13`; cat card on the wall in `qa3_class_cat_question_*`, dog card in `qa3_class_miss1_encourage_*`. |
| 6 | Quota: 300 s/UTC day, persists across reload and restart (new SaveService read), clock rollback grants nothing, near_end at 60 s, expired only at a boundary, closing copy exact, mic released after expiry, Free Play still opens, Family Club from config, settings "Used x of 5:00 today" | **PASS** | QA probe on a real on-disk profile (`user://qa3_quota_profile.json`, new `ProfileStore`+`SaveService` per "restart"): `after 120 s: used=120.0 remaining=180.0`; on disk `settings.tutorQuota = {dayUtc:"2026-09-21", usedSeconds:120.0, …}`; `after RESTART: used=120.0 remaining=180.0`; `after clock ROLLBACK 3h: used=120.0 remaining=180.0`; `near_end events=[[60.0, 240.0]] expired events=[]` until `request_end_at_boundary()` → `expired events=[320.1]`; `begin_session with nothing left -> false`. Scene (probe A/D): closing card texts `["Great job today!", "Come back tomorrow for more Little Days!", "Let's keep playing with Bunny!", "Continue Playing", "Home"]` (`qa3_class_quota_closing_1334x750.png`), `session after quota: active=false capturing=false`; Free Play/Home routing `test_tutor_scene::_test_home_and_free_play_leave` PASS. Config `familyClubDailySeconds: 1800` (`test_tutor_quota::_test_family_club_allowance_and_dev_provider` PASS). Settings: `allowance: 'Used 1:30 of 5:00 today / Resets at 07:00 today'` (`qa3_settings_aliz_1334x750.png`). |
| 7 | Privacy/security | **PASS** | `tutor_flags`, `tutor_privacy_guards`, `speech_privacy_guard`, `speech_never_mocks_on_device` PASS. `project.godot:48 ai_tutor/cloud_enabled=false`, `backend_url=""`. `export_presets.cfg`: `custom_features=""`, `command_line/extra_args=""`, no `--ai-tutor-cloud`. Network primitives only in the three allowlisted files + `cloud_quota_client.gd` (also allowlisted in the guard) and tests. No `AudioStreamMicrophone`/`AudioEffectRecord`/`enable_input` anywhere in `game/` code (the only `AudioEffectCapture` is the lip-sync tap on the *playback* bus). Key scan: `git log -p --all` → `sk-(proj-|live-|test-)?[A-Za-z0-9_-]{20,}`: **0**; AKIA/ghp_/xox/AIza/PRIVATE KEY: **0**; `-S "sk-"` → 6 lines, all the documented test placeholder `sk-test-not-real`. `backend/.env.example`: every key empty, header "No values are committed here." `.gitignore` covers `.env`, `backend/.env`. curl (DEV_MODE, port 38791/38792): `POST /sessions` 201 → turn with `lessonContext` 200 (`"speech":"Yes! Great! It's a cat! Can you make a cat sound?"`), turn without `lessonContext` 400 `invalid_turn`, turn **without `X-Parent-Approval`** → **403** `{"code":"not_approved","message":"This session belongs to another approval."}`, `POST /end` 200, `DELETE /clients/qa3-ipad` → 200 `{"deleted":{"sessions":1,"turns":0,"usage":1,"idempotency":0}}`. |
| 8 | Mobile lifecycle: PAUSED stops the session, return shows tap-to-continue without reopening the mic; permission-denied / no recogniser → tap-to-talk + answer cards; provider failure → "Let's try together!" | **PASS** | Probe A: `NOTIFICATION_APPLICATION_PAUSED` → `paused: state=background active=false capturing=false`; `RESUMED` → `resumed: state=background resume card=true active=false capturing=false` (`qa3_class_resume_card_1334x750.png`: "Welcome back! The microphone is off. Tap to keep learning.", indicator "Mic off"); mic only after `press_resume` → `active=true`. No recogniser: `fallback: tap visible=true cards=["apple_red","number_1","color_blue"]` (`qa3_class_fallback_1334x750.png`). Provider failure: `test_tutor_scene::_test_provider_failure_falls_back` PASS (log `tutor provider failed: backend unreachable` → BANNER_TOGETHER + scripted provider rebuilt). |
| 9 | Regression | **PASS** | Suite: `PASS - 157 case(s), 0 failure(s)`. Mission smokes ×2: `SMOKE PASS`. Audio shipping: `SMOKE PASS -- both delivered tracks play in the real game, one at a time`. Backend: `# tests 126 / # pass 126 / # fail 0`. |

## Release-blocking

**B1 — Barge-in topic switch is announced but not applied in the classroom scene (dead-end / wrong-card state).**
`tutor_scene.gd::_heard()` routes the interjection through `LessonEngine.handle_interjection()`, which *mutates the engine* (probe: `stepIndex 2 -> 3, step now: s04_dog`), then speaks the returned line with `lessonAction: jump_step`. `_after_turn()` (`tutor_scene.gd:545-583`) handles only `complete|end_session|next_question|_` → `_start_listening()`; `jump_step` and `switch_lesson` fall into `_`, so `_open_step()` is never called, `_current_step` and the board stay on the old step and `_last_question` stays stale. Observed (probe B, `qa3_class_after_dog_switch_1334x750.png`, `qa3_class_after_dog_switch_nudge_1334x750.png`):
```
21.42s  Aliz: Okay! Let's see the dog!  [happy/nod/jump_step]
23.42s  scene state -> listening            card=cat   scene step=s03_cat_sound  engine step=s04_dog
26.41s  Aliz: What animal is this?   (3 s re-prompt of the STALE question, cat still on the board)
28.57s  child: "woof"
30.77s  Aliz: Almost! Let's try together! What animal is this?   (judged against s04_dog; card only now becomes dog)
```
The child is asked "What animal is this?" while looking at a **cat** and the engine wants "dog". `switch_lesson` has the same hole: three "banana" answers during the animals lesson each produced `Okay! Let's learn about fruits and colours! [switch_lesson]` and nothing changed (probe A, 31–43 s). The owner's acceptance line ("Wait! I want a dog!" → Aliz switches to the dog) therefore does not hold in the shipped scene; it holds in the engine and in the lesson-driven `TutorVoiceSession` (demo, `test_tutor_voice_session`), which is not the mode the classroom runs. `test_tutor_scene::_test_barge_in_and_partials` does not catch it because it interrupts a *repeat* (phase OPEN), where interjections are not consulted, and only asserts the `thinking` state.

**B2 — A barge-in during the praise of a correct answer discards the answer and counts the interruption as an attempt.**
`_on_barge_in()` calls `_synth.cancel()`, which emits `finished` synchronously → `_on_speech_finished()` → `_after_turn()` runs the cancelled turn (celebrate state, `_outcome_was_correct` cleared) and is then overwritten by `_set_state(STATE_LISTENING)`; the celebrate timer that would have called `_advance_step()` never runs. Any later unhandled interjection is then evaluated as an ANSWER on the already-answered step (`_pending_phase == PHASE_ANSWER`). Observed (probe C, `qa3_class_unhandled_bargein_reply_1334x750.png`):
```
12.78s  Aliz: Great! It's a cat!  [happy/clap/next_question]        (child had answered "It's a cat!")
13.10s  child: "look a bird outside"  (barge-in)
13.31s  scene state -> celebrate (banner=success) -> listening       engine step=s02_cat  attempts=1
15.35s  Aliz: Let me help. It says meow. It has whiskers and a long tail. A cat!  [encouraging/point/give_hint]
```
A child who got the cat right hears a hint for the cat. Violates PRD §4 "Interjections never count as attempts" and §6.1/§7. Same root area as B1; fix together.

## Cosmetic / tooling (not blocking)

| Id | Finding | Where |
|---|---|---|
| C1 | `SCRIPT ERROR: Cannot call method 'call' on a null value` at `tutor_voice_session.gd:681` every time the VAD's 3000 ms long pause fires in capture-only mode (`_reprompt()` → `_request_turn()` uses `_engine`, which is null under the scene). Behaviour is unaffected because the scene has its own 3 s / 8 s timers, but it fires in the shipped scene on every 3 s of silence (seen 3× in the suite, in both shot harnesses and in every windowed probe). `_reprompt()` should return early when `_capture_only`. | `game/scripts/tutor/voice/tutor_voice_session.gd:586-594,681` |
| C2 | `game/tests/shots_tutor.gd` FAILS at this commit (`never reached state 'celebrate'`, `never reached state 'break'`): its `_ready_to_answer()` guards on `session.is_simulating()`, a method `TutorVoiceSession` does not have, so `_until_ready()` returns while a clip is in flight and the sequence drifts one step (the "classroom_apple" frame has an empty board, "success" is a listening frame). `test_tutor_scene.gd:107` has the same dead `has_method("is_simulating")` guard. | `game/tests/shots_tutor.gd:196-201`, `game/tests/cases/test_tutor_scene.gd:103-109` |
| C3 | Quota-closing break card shows three stars even when no lesson was completed that session (probe D: quota expired right after the subject choice). | `qa3_class_quota_closing_1334x750.png`, `tutor_break_card.gd` |
| C4 | No-recogniser subject choice offers three answer cards (apple / one / blue) — Fruits, Numbers, Colours; a child without speech cannot reach Animals or Everyday Things by tap. | `qa3_class_fallback_1334x750.png` |
| C5 | Parent-facing privacy copy says "When your child taps the microphone, the device's own speech recognition listens" while hands-free (default on) keeps the mic open for the whole lesson; the Hands-free row says so, the privacy paragraph does not. | `qa3_settings_aliz_1334x750.png`, `docs/ALIZ_TUTOR_PARENT_INFO.md` |
| C6 | `LessonBoard.show_card()` accepts an id that is not on the allowlist (`dinosaur_green` → `showing=true`, a placeholder disc). Unreachable through a turn (the validator strips it first) but the board has no guard of its own. | `game/scripts/tutor/classroom/lesson_board.gd:85` |
| C7 | During the 1.1 s "Great job!" celebrate beat the indicator reads "Listening" and the session is capturing, but `_on_child_speech_ended()` drops anything heard in that state. | `qa3_class_success_banner_1334x750.png`, `tutor_scene.gd:844` |
| C8 | Title card's glyph is a microphone; on the title screen no microphone is (or may be) open. Consider Aliz's face or a book glyph. | `qa3_title_ipad.png` |

## Verbatim: the hands-free owner dialogue as the scene actually spoke it (probe B, 1334×750)

```
Aliz: Hi! What would you like to learn today?          child: "animals"
Aliz: Great! Let's learn Animals!
Aliz: Yay! Let's learn about animals!
Aliz: What animal is this?                (cat card)   child: "It's a cat!"
Aliz: Great! It's a cat!                  -> Great job!
Aliz: Can you make a cat sound?                        child: "Meow!"
Aliz: Meow! You're amazing!  [happy/clap]              child (barge-in, +200 ms detected, mouth 0 same frame): "Wait! I want a dog!"
Aliz: Okay! Let's see the dog!  [jump_step]            -> board still CAT, engine on DOG (B1)
Aliz: What animal is this?                (re-prompt)  child: "woof"
Aliz: Almost! Let's try together! What animal is this? (card now dog)
Aliz: Here is a hint. It says woof. It wags its tail. A dog!
Aliz: Let's say it together. It's a dog! Say dog.
Aliz: Can you make a dog sound?
```

## Frames produced (all under `docs/shots/`, sizes asserted by the harnesses)

Title: `qa3_title_ipad.png` (1334×750), `qa3_title_iphone.png` (2340×1080).
Classroom, both sizes (`_1334x750` and `_2340x1080`): `qa3_class_welcome_listening`, `qa3_class_cat_question`, `qa3_class_cat_praise_speaking`, `qa3_class_success_banner`, `qa3_class_interrupted`, `qa3_class_dog_question`, `qa3_class_miss_encourage`, `qa3_class_muted`, `qa3_class_picture_card`, `qa3_class_exit_confirm`, `qa3_class_break_card`, `qa3_class_resume_card`, `qa3_class_fallback`, `qa3_class_quota_closing`. 1334×750 only: `qa3_class_after_dog_switch`, `qa3_class_after_dog_switch_nudge`, `qa3_class_miss1_encourage`, `qa3_class_miss2_hint`, `qa3_class_unhandled_bargein_reply`; the project harness's own set copied as `qa3_tutor_*_1334x750.png` (sequence drifted, see C2).
Aliz: `qa3_aliz_expr_*.png` ×6, `qa3_aliz_mouth_*.png` ×4, `qa3_aliz_env_*.png` ×6, `qa3_aliz_gesture_<name>_*.png` ×25, `qa3_aliz_state_<name>_*.png` ×15, sheets `qa3_aliz_expressions_sheet.png`, `qa3_aliz_mouth_sheet.png`, `qa3_aliz_envelope_strip.png`, `qa3_aliz_gesture_*_strip.png`, `qa3_aliz_state_*_strip.png`.
Other: `qa3_flashcards_all_1334x750.png`, `qa3_settings_aliz_1334x750.png`, `qa3_settings_aliz_privacy_1334x750.png`.

## NOT tested

- No physical iPad/iPhone run: no real microphone audio, no real on-device recogniser, no AVAudioSession voice-processing mode, no real echo path. The VAD and barge-in were driven by the simulated level clips; on this Mac the plugin's `get_input_level()` was wired as the level source but no one spoke into it.
- No live OpenAI (no key on this machine): `OpenAIRealtimeTransport` / `CloudRealtimeTransport` and the backend's OpenAI adapter were exercised only by their unit tests with mock fetch/transport. Cloud flag stayed false throughout.
- No TestFlight/Xcode export; export presets were only read.
- Android: presets only.
- Actual audio quality of the device TTS voice; the recorded voice pack has 0 of 36 recordings present (`voice_manifest` reports them falling back to TTS).
- The child-facing app run through the real `main.tscn` → classroom transition in a window (the route and freeze-freedom come from `test_menu_wow` and the constant in `main.gd`, not from a windowed click).
