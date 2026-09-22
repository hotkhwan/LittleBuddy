# Aliz Voice Agent

Status: prototype contract implemented; live provider exercise **NR**. Cloudflare Voice is Beta. Production child audio remains disabled.

## Purpose and release boundary

Aliz voice is a provider-neutral learning interface, not an unrestricted assistant. It accepts a short spoken learning turn, returns an age-appropriate response, and emits synchronized events for text, audio, expressions, and timing. Offline lessons and touch interactions remain complete when voice is unavailable.

The release gates are intentionally independent:

- `LIVE_CHILD_AUDIO_ENABLED` must be true.
- Current-session parent voice consent must be true.
- Synthetic/adult QA can use an explicit QA mode without changing the production child-audio flag.

The committed defaults do not enable child audio. No raw audio or transcript is written by the voice protocol. Enabling production child audio requires privacy/legal approval, retention verification, consent UX review, and physical-device testing.

## Implemented contracts

Server-neutral contracts live in `cloud/src/voice/`:

- typed client/server events;
- bounded control-message parsing;
- STT and TTS adapter interfaces with abort signals;
- launch/consent gate;
- provider fallback state machine;
- numeric-only stage and total-turn metrics;
- child-safe error normalization.

The Godot client lives in `game/scripts/voice/voice_client.gd`. It uses `WebSocketPeer`, sends PCM16 as binary frames, handles partial/final transcription, assistant text/audio, metrics, interrupt/cancel, bounded reconnect, and fallback events. It does not use React and does not retain packet buffers after dispatch.

Cloudflare's Beta Voice package supplies server-side `withVoice`/`withVoiceInput`, Workers AI STT/TTS adapters, persistence, streaming TTS, interruption handling, and a framework-neutral client. Little Days keeps its own protocol boundary because the Godot client and privacy policy cannot depend on a web UI implementation. [Cloudflare Voice documentation](https://developers.cloudflare.com/agents/communication-channels/voice/)

## Protocol

Client control events:

- `session.start`
- `audio.start`
- binary PCM16 audio frames
- `audio.end`
- `turn.interrupt`
- `turn.cancel`
- `session.end`

Server events:

- `session.ready`
- `transcript.partial` / `transcript.final`
- `assistant.text`
- `assistant.audio`, followed by binary PCM16 frames
- `turn.metrics`
- `turn.cancelled`
- `fallback`
- `error` with a fixed child-safe message

Control messages are limited to 4 KiB. Identifiers and sample rates are validated. Arbitrary game/system commands are not part of this protocol; semantic learning tools are handled by the separately validated tool router.

## Provider architecture

The intended premium path is Cloudflare Voice Agent or Gemini Live. Neither is the sole production path. Cloudflare's documented built-in defaults are `@cf/deepgram/flux` for continuous STT and `@cf/deepgram/aura-1` for TTS through a Workers AI binding; the product remains free to substitute adapters. [Cloudflare Voice providers](https://developers.cloudflare.com/agents/communication-channels/voice/#providers)

Fallback is deterministic:

```text
Cloudflare Voice or Gemini Live
  -> standard STT + standard LLM + TTS
  -> standard text tutor
  -> local deterministic lesson
```

Quota exhaustion, timeout, disconnect, and provider failures trigger a transition. Children receive “Let's keep learning another way,” never an HTTP status, quota message, API key detail, or provider response body.

## Privacy and state

- Raw child audio: stream only; retention disabled by Little Days policy.
- Transcript: ephemeral turn input; no long-term full conversation history by default.
- Persisted data: minimal lesson/mastery signals and aggregate usage/timing.
- Diagnostics: numeric stage timings and outcomes only; no content fields.
- Provider persistence: must be explicitly configured or disabled before child use. Cloudflare Voice can persist conversations, but that capability is not permission to retain child conversations.
- Logs: raw audio and unnecessary conversation text are prohibited.

Cloudflare added typed turn metrics for successful and failed/aborted turns, including stage timing. The Little Days `VoiceTurnMetrics` boundary records STT, LLM, TTS, total, and audio-duration numbers without content. [Cloudflare Voice metrics changelog](https://developers.cloudflare.com/changelog/product/agents/)

## Validation status

| Area | Status | Evidence |
|---|---|---|
| Protocol parsing and bounds | PASS | focused Vitest |
| Child launch/consent gate | PASS | focused Vitest and Godot test source |
| Provider fallback | PASS | focused Vitest |
| Content-free metrics | PASS | focused Vitest |
| Godot parse/runtime | NR | Godot executable unavailable in implementation environment |
| Cloudflare Voice deployment | NR | no deployed Voice Agent evidence recorded |
| Cloudflare STT synthetic/adult benchmark | NR | no live audio run recorded |
| Cloudflare TTS synthetic/adult benchmark | NR | no live audio run recorded |
| Interruption/barge-in live behavior | NR | requires deployed provider and audio client |
| Physical Android/iOS child-audio QA | NR and gated | requires owner device; child audio must remain off |

## Exit criteria for a development voice trial

1. Deploy a Beta Voice Agent only in development with a Workers AI binding and SQLite Durable Object migration.
2. Disable or minimize conversation persistence and inspect actual stored state.
3. Exercise adult/synthetic English utterances: short speech, silence, pauses, interruption, cancel, disconnect/reconnect, STT error, TTS error, and quota exhaustion.
4. Record median/p95 STT, LLM, TTS, first-audio, and total-turn latency from typed metrics.
5. Reconcile metered STT minutes, TTS characters, LLM tokens, Worker requests, and Durable Object usage with provider dashboards.
6. Compare native device STT/TTS on the same fixed utterances.
7. Keep `LIVE_CHILD_AUDIO_ENABLED=false` in closed production until the owner approves privacy/legal and physical-device gates.

