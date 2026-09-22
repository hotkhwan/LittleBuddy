# Aliz AI Classroom — integration review

## Architecture

The classroom is offline-first. `lesson_local` remains deterministic and complete without a network. `standard_chat` and `premium_live` use the same provider-neutral session contract. The Godot-facing metadata is limited to tier, mode, capabilities, quota remaining and audio mode; provider names, credentials and provider tokens are not exposed.

The server adapter layer supports Mock, OpenAI, DeepSeek and Gemini Live. Standard defaults to the configurable `gpt-5.6-luna` model name. DeepSeek Flash is implemented but is not the default. Gemini `gemini-3.8-live` is a lifecycle abstraction for backend-mediated realtime audio, interruption, barge-in, transcription events, reconnect, metering and graceful fallback. It is not enabled for production child traffic.

Server-side secret names are documented in `backend/.env.example`. No secret value was added. No deployment was performed.

## Standard and Premium behavior

- Standard prefers local lesson answers when deterministic content can handle the turn, with short child-safe AI responses available through the Worker path.
- Premium Live falls back to Standard chat and then local lessons.
- The classroom session contract supplies child-friendly labels: Lesson Mode, Ask Aliz anything, and Live with Aliz.
- The HUD presents the active mode as classroom chrome rather than a text-chat transcript.
- Standard and Premium Live daily seconds are independently configurable. No 60-minute product assumption or final price is hardcoded.

## Expression Director, cues and lip sync

`TutorExpressionDirector` maps neutral, happy, proud, excited, encouraging, thinking, listening, surprised, gentle and confused into semantic face/eye/brow/mouth/head frames. It emits adapter signals and never accesses bones. Gestures are whitelisted, cooled down and window-rate-limited; deterministic pools prevent repetitive praise.

`TutorCueContract` accepts only `set_emotion`, `play_gesture`, `look_at`, `show_learning_card` and `award_star`, validates every argument and rejects arbitrary calls. The lip-sync driver supports smoothed amplitude, optional safe visemes, additive expression blending and immediate reset. The existing production Aliz rig, gesture layer and amplitude/TTS lip-sync implementation remain intact.

## Learning patterns

The data-driven pattern catalog covers Pre-K through Grade 4 with listen/touch/say, picture sentences, guided practice, reading/thinking and guided conversation. It covers colors, animals, numbers, vocabulary, everyday objects, simple sentences, simple maths, short comprehension and conversational English without creating a large curriculum.

## Classroom visual review and Meshy

The existing classroom already includes a premium pastel dollhouse room, layered rug, warm walls/window treatment, teaching table and chairs, board, card rack, books, pencils, shelf toys, fruit, pets, play table and number blocks. Four accepted Meshy tutor props are integrated and mobile-budgeted: table set, fruit set, cat/dog and number blocks.

No new paid Meshy operation was justified or run in this sprint. Existing tutor assets already cover the silhouettes that benefit from generated geometry; code-native additions are preferable for later letters/reward shelves. Credits spent this sprint: **0**. The historical 60-credit tutor prop spend and acceptance evidence remain in `MESHY_CREDIT_LEDGER.md`; no paid orphan was created.

Aliz remains seated in the current production classroom. Walking anchors and classroom-local locomotion are a separate integration risk because the existing scene has a fixed camera and seated pose; no unsafe graft onto house click-to-walk was made.

## Tests and evidence

- Backend: 132/132 Node contract tests pass, including provider metadata, switching/fallback, quotas, DeepSeek fake fetch, Gemini disconnect/reconnect, barge-in, interruption and metering.
- New Godot tests pass for expression mapping, invalid cues, rotation/rate limiting, lip-sync reset, learning patterns, session modes/fallback and the Baby display-name regression.
- Focused localization, activity-picker and menu-route tests pass.
- The tutor UI suite passes all new cases. Its existing `tutor_cloud_fixtures` case still reports 14 baseline failures; these reproduced before this sprint and were not hidden or weakened.
- A final 175-case Godot run was attempted after the rename fixes. The harness exhausted its writable socket/profile resources mid-run (`no free port`, failed temporary profile/log writes), causing cascading unrelated failures. The affected focused localization, UI, routing, voice, expression, session and rename cases all pass independently.
- Exact 1366×1024 iPad captures were produced for classroom idle, listening, hearing, speaking, correct-answer praise, muted, interrupted, lesson switch and exit. Existing 1334×750 and 2340×1080 sets cover fallback and reward/quota states. New files are under `docs/shots/tutor_*_1366x1024.png`.

## Credentials and production blockers

- Owner-managed provider credentials and a real Worker transport are required before Gemini Live can serve production traffic.
- Authoritative prices for GPT-5.6 Luna and Gemini 3.8 Live must be added to server pricing configuration before cost enforcement is enabled for those models; no price was invented.
- The macOS checkout lacks the compiled speech-plugin framework, so Godot logs its known extension-load warning. Device/native speech validation still requires a signed physical-device build.
- Premium billing is intentionally not activated.

## Integration SHA

Commit creation is blocked in this managed checkout: the linked-worktree Git index is outside the writable workspace, so Git cannot create its `index.lock`. The final handoff records the current base SHA and exact blocker. Nothing is merged or deployed.
