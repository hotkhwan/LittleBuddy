# Voice Provider Cost Comparison

Pricing checked 2026-09-22. This is a planning model, not a bill or a completed repeated provider benchmark. Cloudflare Voice is Beta. One adult Nova-3 STT smoke and one synthetic Aura-1 TTS smoke passed; Gemini remains **NR**. Production child audio remains off.

## Published unit prices

Cloudflare's current Workers AI price table publishes:

| Component | Model | Published price |
|---|---|---:|
| Conversational STT | `@cf/deepgram/flux` WebSocket | $0.0077/input audio minute |
| Alternative STT | `@cf/deepgram/nova-3` WebSocket | $0.0092/input audio minute |
| Batch STT reference | `@cf/openai/whisper-large-v3-turbo` | $0.0005/audio minute |
| TTS | `@cf/deepgram/aura-1` | $0.015/1,000 input characters |
| Alternative TTS | `@cf/deepgram/aura-2-en` | $0.030/1,000 input characters |

Source: [Cloudflare Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/#audio-model-pricing). The Voice documentation identifies Flux and Aura 1 as its built-in continuous-STT/TTS defaults. [Cloudflare Voice providers](https://developers.cloudflare.com/agents/communication-channels/voice/#providers)

Gemini Live pricing and actual Little Days usage were not verified in this sprint, so Gemini numeric cost is **NR**. It must not be inferred from unrelated Gemini text-model pricing.

## Transparent planning assumptions

For a directional Cloudflare component subtotal only:

- 30 usage days/month;
- child/user speech occupies 40% of a session minute;
- Aliz emits 75 TTS characters per session minute;
- STT uses Flux WebSocket;
- TTS uses Aura 1;
- no free allocation or volume discount is deducted.

These are workload assumptions, not measured usage. The per-session-minute subtotal is:

```text
STT  = 0.40 * $0.0077                        = $0.003080
TTS  = (75 / 1,000) * $0.015                 = $0.001125
audio inference subtotal                     = $0.004205/session minute
monthly/subscriber = daily minutes * 30 * $0.004205
```

This subtotal excludes LLM tokens, Workers, Durable Objects, storage, egress if applicable, taxes, and any paid third-party service.

## Cloudflare audio-inference subtotal

| Minutes/day | Monthly audio subtotal/subscriber | 100 subscribers | 1,000 subscribers | 10,000 subscribers |
|---:|---:|---:|---:|---:|
| 5 | $0.6308 | $63.08 | $630.75 | $6,307.50 |
| 10 | $1.2615 | $126.15 | $1,261.50 | $12,615.00 |
| 15 | $1.8923 | $189.23 | $1,892.25 | $18,922.50 |
| 30 | $3.7845 | $378.45 | $3,784.50 | $37,845.00 |
| 60 | $7.5690 | $756.90 | $7,569.00 | $75,690.00 |

These values are arithmetic projections from published rates and stated assumptions—not measured cost.

## Platform costs to add after telemetry

Durable Objects add request, duration, and storage cost. Cloudflare documents 1 million requests/month included on the paid plan, then $0.15/million, and 400,000 GB-s/month included, then $12.50/million GB-s, subject to billing rounding and the Workers Paid minimum. Hibernatable WebSockets can materially reduce duration; active outbound WebSockets keep an object in memory. [Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/)

AI Gateway core analytics, caching, and rate limiting are currently offered free, while underlying inference is passed through without markup. Persistent-log limits depend on plan. Personalized child conversation must not be cached, and content logging should be disabled or minimized. [AI Gateway pricing](https://developers.cloudflare.com/ai-gateway/reference/pricing/)

Use this complete equation after a live trial:

```text
monthly total = STT audio minutes * STT rate
              + TTS characters / 1,000 * TTS rate
              + LLM input tokens / 1,000,000 * input rate
              + LLM output tokens / 1,000,000 * output rate
              + billable Worker requests and CPU
              + billable Durable Object requests, duration, and storage
              + gateway premium features (if any)
              + taxes/contract adjustments
```

## Provider decision status

| Dimension | Cloudflare Voice | Gemini Live |
|---|---|---|
| Product maturity | Beta | Not evaluated here |
| Godot protocol compatibility | Implemented provider-neutral protocol; live integration NR | Same protocol can adapt; live integration NR |
| STT/TTS unit pricing | Published for default Workers AI components | NR |
| Measured median/p95 latency | NR; one STT inference was 1,855 ms and one TTS generation was 587 ms | NR |
| Recognition/voice quality | Adult STT sample matched the reference at reported 0.999 confidence; TTS produced a valid 89,208-byte WAV, but listening review remains NR | NR |
| Barge-in quality | NR | NR |
| Estimated full-pipeline cost | Pending live tokens/platform telemetry | NR |

No premium provider winner is selected. Run identical synthetic/adult scripts, collect actual metrics and bills, then decide on quality, safety, latency, reliability, and total cost—not price alone.
