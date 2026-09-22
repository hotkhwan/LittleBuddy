# AI Cost Model

Status: telemetry contracts implemented; production forecasts remain provisional until live traffic is reconciled with provider billing. Prices and policies can change and must be rechecked before a launch decision.

## Cost boundaries

Little Days routes each request to the least expensive qualified path:

1. local deterministic lesson for known prompts and core gameplay;
2. standard Workers AI model for short vocabulary, explanation, or structured lesson turns;
3. complex reasoning model only when deterministic policy classifies the task as requiring it;
4. premium realtime voice only for an entitled, consented session with available quota;
5. fallback to standard text and then local lesson on failure or budget exhaustion.

Prices are configuration/operations data, never hardcoded subscription decisions. The child UI never exposes tokens, infrastructure quota, or provider errors.

## Metered dimensions

Record per turn/session:

- model/provider and route class;
- uncached and cached input tokens;
- output tokens;
- STT input audio minutes;
- TTS input characters or output audio duration, according to provider billing;
- Worker requests and CPU time;
- Durable Object requests, active duration, and storage;
- retry/fallback count;
- estimated cost at the price-table version used;
- provider-reported cost when available.

Do not attach raw audio, transcript text, child names, or unnecessary conversation content to cost records. AI Gateway can report requests, tokens, errors, cache rates, and estimated cost, but Cloudflare cautions that cost values are estimates and provider dashboards are authoritative. [AI Gateway cost observability](https://developers.cloudflare.com/ai-gateway/observability/costs/)

## Equations

Text turn:

```text
C_text = input_tokens / 1,000,000 * P_input
       + cached_input_tokens / 1,000,000 * P_cached
       + output_tokens / 1,000,000 * P_output
```

Voice turn:

```text
C_voice = input_audio_minutes * P_STT_minute
        + tts_input_characters / 1,000 * P_TTS_1k_chars
        + C_text
        + C_worker
        + C_durable_object
        + C_gateway
```

Fleet forecast:

```text
C_month = active_subscribers
        * active_days_per_month
        * average_daily_sessions
        * average_turns_per_session
        * average_cost_per_turn
        + fixed/minimum platform charges
```

Keep p50, p95, and high-use cohort forecasts. Averages alone hide voice-heavy and repeated-retry users.

## Guardrails

- Enforce daily seconds/turns, monthly tokens, and live voice minute pools server-side.
- Reserve quota atomically before provider work; settle measured usage afterward.
- Abort on client cancel and provider timeout.
- Bound retries and never retry unsafe or invalid output.
- Refuse the expensive path when its budget is exhausted, then degrade gracefully.
- Alert on spend velocity, cost/active user, fallback rate, output-token growth, and missing usage metadata.
- Do not cache personalized child conversation. Cache only approved, non-personal deterministic material where semantics and privacy allow it.
- Version the price table used for every estimate; reconcile estimates against invoices/dashboard usage.

## Voice planning scenario

Using the explicitly documented assumptions in `VOICE_PROVIDER_COST_COMPARISON.md`, Cloudflare Flux STT plus Aura 1 TTS has a projected audio-only subtotal of $0.004205 per session minute. This excludes LLM and platform costs. At 30 days/month:

| Daily voice minutes | Audio-only monthly subtotal/user |
|---:|---:|
| 5 | $0.6308 |
| 10 | $1.2615 |
| 15 | $1.8923 |
| 30 | $3.7845 |
| 60 | $7.5690 |

The source audio rates are in [Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/#audio-model-pricing). This scenario is arithmetic, not a live benchmark or invoice.

## Durable Object and Gateway treatment

Model Durable Objects from actual topology. WebSocket hibernation is preferred; a non-hibernating or outbound WebSocket can incur wall-clock duration while connected. Request billing also counts connection/message activity according to Cloudflare's documented rules. [Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/)

AI Gateway core functionality is currently offered free and provider inference is passed through without markup, but logging limits and future premium features must be checked at launch. [AI Gateway pricing](https://developers.cloudflare.com/ai-gateway/reference/pricing/)

## Evidence still required

- Live Workers AI token usage by selected standard/reasoning models.
- Synthetic/adult Cloudflare STT and TTS minutes/characters and dashboard reconciliation.
- Cloudflare Voice median/p95 stage and total-turn latency: **NR**.
- Gemini Live quality, latency, unit price, and measured cost: **NR**.
- Durable Object hibernation behavior and measured GB-s under voice load.
- Retry/fallback amplification under provider outage.
- A 100/1,000/10,000-active-subscriber sensitivity analysis using observed, not assumed, talk/listen ratios.

Until these exist, do not claim a full voice cost, premium-provider winner, or production voice readiness. `LIVE_CHILD_AUDIO_ENABLED` remains false.
