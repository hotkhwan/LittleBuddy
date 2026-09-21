# Aliz Tutor Mode V1 — final report, 2026-09-21

Branch `feature/overnight-production-candidate`. **Final code commit `e569f5e`**
(builds below were made from `94e5821`; the two commits after it add a harness
frame, this report, the QA C1 fix and a settings null guard, all suite-verified), pushed to `origin`,
fast-forward, no force. Sprint base: `7110046`. 45 commits, 432 files, seven
workstream agents plus an independent QA pass, merged one wave at a time by the
lead and re-gated after every wave.

> Every PASS is a command that ran on this MacBook or a frame that was opened
> and looked at. **Nothing ran on a physical device and no live cloud provider
> was called.** The cloud tutor is OFF in every build; the local scripted,
> hands-free tutor is what ships.

## 1. Working tutor features (local, no network)

| Feature | Status | Evidence |
|---|---|---|
| "Learn with Aliz" entry card on the title screen (240×240, art-bible compliant) | PASS | `docs/shots/menu_tutor_ipad.png` |
| Original pastel 3D classroom: Aliz seated across a round table, chairs, cards, books, pencil cup, lesson board, toy shelf; the four Meshy props (table set, fruit set, cat + dog, number blocks) | PASS | `tutor_classroom_apple_{1334x750,2340x1080}.png`, 20,112 triangles, one light |
| Deterministic lesson engine: five subjects, six lessons, first full lesson English — Colours and Fruits (18 steps ≈ 304 s), `choose` menu, `sound` steps with reactions, retry → hint → teach, interjections, progress with `completedAt`, stars paid once | PASS | `test_tutor_lesson` (17 groups) prints the owner dialogue |
| Hands-free voice session: mic live only inside an active session, child-tuned VAD (start ≥120 ms, end 900/1600 ms, 3 s long pause re-prompts, coughs ignored), echo gate, barge-in (Voice stopped and mouth 0 within 1 ms of detection, listening face ≤200 ms, interjection evaluated) | PASS | `test_tutor_voice_session`, `demo_tutor_voice_session.gd` timeline, `test_tutor_scene` regression cases |
| Classroom drives the loop with the real session in capture-only mode: welcome → subject → lesson; correct / wrong / hint / teach; cough ignored; pause not cut; "Wait! I want the banana!" honoured (board and question move); an idle interruption during praise never scores and the cut correct answer still advances | PASS | `tutor_after_switch_1334x750.png`, `tutor_interrupted_*.png`, `test_tutor_scene` |
| Aliz: six expressions, four mouth frames driven by the real audio envelope (closes 100 ms after silence), blink in every state, gestures nod / tilt / point / clap / wave on an upper-body layer, composite states idle / listening / thinking / speaking / interrupted / happy / encouraging / explaining / celebrating | PASS | `aliz_tutor_*` sheets and strips, `test_aliz_tutor_face` (12 groups) |
| Flashcards for all 13 allowlisted asset ids; unknown ids fall back through the validator | PASS | `qa3_flashcards_all_1334x750.png` |
| HUD: Home, Mute, Repeat, Picture card, End lesson (confirm), live mic indicator, subtitle, banners; nothing over Aliz's face at either size | PASS | `tutor_*_{1334x750,2340x1080}.png` |
| Free quota 5 min/day: local mirror keyed by UTC day, restart-proof, clock-rollback-proof, warns at 60 s, ends only at a safe turn with "Great job today!" / "Come back tomorrow for more Little Days!" / "Let's keep playing with Bunny!", Continue Playing / Home; mic released; Free Play still opens | PASS | `test_tutor_quota` (18 groups), `tutor_quota_closing_*.png` |
| Parent controls behind the 3 s gate: AI Tutor on/off, hands-free on/off, Aliz voice selector (device voice; cloud presets disabled), daily allowance, mic status, learning language (English), privacy text, learning history, delete learning history, subscription status ("proposed THB 99/month", billing not available) | PASS | `settings_aliz_*.png`, `test_tutor_settings` |
| Mobile lifecycle: background stops capture and the session; foreground never reopens the mic; permission denied → tap-to-talk and answer cards; provider failure → "Let's try together!" and the scripted path | PASS | `test_tutor_scene`, `tutor_fallback_*.png` |
| Backend (Node 22, zero dependencies): sessions, server-side UTC quota, entitlements free / family_club, parental-approval tokens bound to sessions, idempotent turns, rate limits, timeouts, structured-output validation, retention purge, DELETE client, usage/cost accounting, monthly budget guard, mock provider, OpenAI adapter behind an env key, realtime ephemeral-token endpoint | PASS | `npm test`: 126 passing; DEV_MODE curl transcript in `backend/README.md` |

## 2. Features behind flags (not live)

| Feature | Flag / gate | Why |
|---|---|---|
| Cloud conversation provider (backend turns), backend synthesis stub, OpenAI Realtime transport | `little_days/ai_tutor/cloud_enabled=false` in project.godot; `test_tutor_flags` and `test_tutor_privacy_guards` read the committed files | Privacy gate closed: 16 of 17 conditions FALSE (`docs/ALIZ_TUTOR_PRIVACY_REVIEW.md`), no OpenAI key on this machine |
| OpenAI provider and Realtime token minting on the backend | `OPENAI_API_KEY` env, absent | Unit-tested with a fake fetch only |
| Family Club entitlement and mock billing | DEV_MODE / `-- --dev-entitlements` | Real store validation returns 501 with TODOs; no purchase UI anywhere |

## 3. Speech implementation status

On-device recognition (iOS plugin, real recogniser in the editor on this Mac)
wrapped in a provider with hard caps and echo prevention; client VAD; barge-in;
transports abstracted with a deterministic mock and a flag-gated Realtime
client written against the official event names fetched on 2026-09-20 (cited
in `docs/ALIZ_TUTOR_REALTIME.md`). iOS voice-processing audio-session mode and
an input-level meter added to the native plugin and rebuilt. **Voice pack: 0 of
36 recordings present**; Aliz speaks through the device voice under the pack's
queue. The evaluation (`docs/ALIZ_TUTOR_REALTIME_EVALUATION.md`) recommends the
modular pipeline for V1 and Realtime as a later flag-gated experiment.

## 4. Spending

| | |
|---|---|
| OpenAI API | **$0** — no key, no call |
| Meshy | **60 credits** (4 props × 15: preview 5 + refine 10 each), balance 3184 → **3124**, task ids in `docs/MESHY_CREDIT_LEDGER.md`; 40 of the 100-credit ceiling unspent |

## 5. Gates on the final code

| Gate | Result |
|---|---|
| Godot suite | **PASS - 157 case(s), 0 failure(s)** |
| Mission 01 / Mission 02 walkthroughs | SMOKE PASS / SMOKE PASS |
| Audio shipping smoke | SMOKE PASS |
| Backend | 126 passing |
| Privacy guards, flag test | PASS |
| iOS export | exit 0, pck 14,998,884 B, tutor scene in, concept art out |
| arm64 Xcode build | `** BUILD SUCCEEDED **` (voice-processing symbol present) |
| Android debug APK | `build/android/LittleDays-debug.apk`, 43,909,805 B, SHA-256 `f3f0f53fd41199625dddec6cd890f10a933cfc839943c50c0d57100aa4574ec7`, signed v2+v3, zero permissions |

## 6. Quota test results (verbatim from QA on a8a2e1f, unchanged since)

120 s of use survives a new ProfileStore + SaveService "restart"; a 3 h clock
rollback grants nothing; `near_end [[60.0, 240.0]]` fires once; `expired` only
after `request_end_at_boundary()`; closing copy exact; session inactive after
expiry; settings read "Used 1:30 of 5:00 today".

## 7. Privacy / compliance blockers (cloud path)

From `docs/ALIZ_TUTOR_PRIVACY_REVIEW.md`: G1 OpenAI Zero Data Retention not
approved (no org, no key); G2 no written provider position on under-13
transcripts; G3 no verifiable parental consent flow recorded server-side (the
3 s hold is a gate, not consent); G4 no privacy policy URL; G5 store data-safety
labels not aligned; G7 no hosted secret management; G8 no penetration test;
G10 retention now implemented in code but not operated; G14 Thailand PDPA
consent basis; G17 server lesson authority now implemented. **Nothing may set
the cloud flag true until all are TRUE.** The local tutor is compliant to ship:
no network class under `game/`, no INTERNET permission, on-device recognition
only, only counts persisted, controls behind the gate.

## 8. Device and store status

Physical iPad / iPhone QA: **not run** (no real microphone audio, no
voice-processing session, no echo path exercised on hardware). Android: APK
built and signed, never run on a phone. iOS: project exported and arm64 build
succeeds unsigned; the owner's team signs in Xcode. No public readiness is
claimed.

## 9. Known limitations and cosmetic items

QA's cosmetic list (`docs/QA_TUTOR_a8a2e1f.md`) is closed as of the commit
after `e569f5e`: C1 a long silence makes Aliz ask again with no script error;
C3 the closing card shows only the stars earned this session (none when no
answer was given); C4 the tap fallback offers all four subjects with a
flashcard (Animals included; Everyday Things still has no cup/spoon card);
C5 the parent privacy text describes hands-free listening in English and Thai;
C6 the lesson board refuses ids off the allowlist; C7 the mic is gated and the
indicator says off during the celebrate beat; C8 the title card carries an
original book glyph, not a microphone. Each has a test or a frame. Engine:
cup/spoon have no flashcards; voice-pack ids are placeholders until recordings
exist.
