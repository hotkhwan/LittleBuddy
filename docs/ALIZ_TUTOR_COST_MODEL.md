# Aliz Tutor Mode: cost model

Every number below is either a **list price** from `backend/config/prices.json`
(source: https://developers.openai.com/api/docs/pricing, fetched 2026-09-20;
`platform.openai.com/docs/pricing` redirects there) or derived from a stated
**assumption** (labelled A1..A9). The arithmetic is the same code the server
runs per turn (`backend/src/usage.js` `estimateTurnCost`) and is covered by
`backend/test/usage_budget.test.js`. Re-run the figures with the snippet at the
bottom whenever a price or an assumption changes.

## Prices used (USD, list, 2026-09-20)

| Item | Price | Unit |
| --- | --- | --- |
| gpt-4o-mini input / cached input / output | 0.15 / 0.075 / 0.60 | per 1M tokens |
| gpt-4.1-mini input / cached / output | 0.40 / 0.10 / 1.60 | per 1M tokens |
| gpt-4.1-nano input / cached / output | 0.10 / 0.025 / 0.40 | per 1M tokens |
| gpt-5-mini input / cached / output | 0.25 / 0.025 / 2.00 | per 1M tokens |
| gpt-5-nano input / cached / output | 0.05 / 0.005 / 0.40 | per 1M tokens |
| gpt-4o-mini-transcribe (STT) | 0.003 | per minute of audio |
| whisper-1 / gpt-4o-transcribe (STT) | 0.006 | per minute |
| tts-1 (TTS) | 15.00 | per 1M characters |
| tts-1-hd (TTS) | 30.00 | per 1M characters |
| gpt-4o-mini-tts | not used | page lists it per token, no per-character rate; left `null` |

## Assumptions

| # | Assumption | Value | Why |
| --- | --- | --- | --- |
| A1 | Turns per 5-minute (300 s) session | 12 | ~25 s per beat: Aliz speaks 5-7 s, child listens/answers 3-5 s, thinking + animation the rest. Range 10-15. |
| A2 | LLM input tokens per turn | 350 | System prompt ~180 tokens + lesson context/transcript ~70 + JSON-schema response format overhead. Prompt caching does **not** apply: OpenAI caches only prefixes >= 1024 tokens, so cached-input prices are not used. |
| A3 | LLM output tokens per turn | 60 | JSON turn with a <= 160-char `speech` (~40 tokens) plus keys/enums. |
| A4 | Child audio per turn (STT, if cloud) | 4 s | Short answers; the per-request clamp is 30 s. |
| A5 | TTS characters per turn (if cloud) | 70 | Average `speech` length observed from the mock provider (43-47 chars) plus headroom; max is 160. |
| A6 | Free user: sessions per active day | 1 (the whole 300 s) | Allowance-bound. |
| A7 | Free user: active days per month | 9 | 30 % of days (typical DAU/MAU for a kids' app). |
| A8 | Family Club user: sessions per active day | 3 (15 min of the 30 min allowance) | Paying families use it more but rarely to the cap. |
| A9 | Family Club user: active days per month | 15 | 50 % of days. |

Derived: turns per free user-month = A1 x A6 x A7 = **108**; per Family Club
user-month = A1 x A8 x A9 = **540**.

Defaults today: STT and TTS run **on the device** (`STT_MODE=device`,
`TTS_MODE=device`), so only the LLM costs money. The "cloud everything" column
shows what moving STT and TTS to OpenAI would add.

## Per-turn cost breakdown (gpt-4o-mini)

| Component | Formula | USD / turn |
| --- | --- | --- |
| LLM input | 350 / 1e6 x 0.15 | 0.0000525 |
| LLM output | 60 / 1e6 x 0.60 | 0.0000360 |
| **LLM total (device STT/TTS)** | | **0.0000885** |
| STT (cloud, gpt-4o-mini-transcribe) | 4 / 60 x 0.003 | 0.0002000 |
| TTS (cloud, tts-1) | 70 / 1e6 x 15 | 0.0010500 |
| **Cloud everything** | | **0.0013385** |

Observation: with cloud speech, TTS is 78 % of the turn cost and STT 15 %; the
LLM is under 7 %. Keeping synthesis on-device (or on pre-recorded lines, which
the SpeechSynthesisProvider prefers) is the single biggest lever.

Per session (12 turns): LLM-only **$0.00106**; cloud everything **$0.01606**.
Per user-month: free LLM-only $0.0096, cloud $0.1446; Family Club LLM-only
$0.0478, cloud $0.7228.

## Monthly projections

"10 % Family Club" = 90 % of users on free (108 turns) + 10 % on Family Club (540 turns), i.e. 151.2 turns per average user-month.

| Users | Free only, LLM-only | 10 % FC, LLM-only | Free only, cloud everything | 10 % FC, cloud everything |
| --- | --- | --- | --- | --- |
| 100 | $0.96 | $1.34 | $14.46 | $20.24 |
| 1,000 | $9.56 | $13.38 | $144.56 | $202.38 |
| 10,000 | $95.58 | $133.81 | $1,445.58 | $2,023.81 |

Worst case (every user at the cap every day, cloud everything): a free user
costs 360 turns x 0.0013385 = $0.48/month, a Family Club user 2,160 turns =
$2.89/month. The server's daily allowances make these hard ceilings; nothing is
unlimited.

## Savings levers

**Response cache** (`turn_cache.js`, key = lessonId + stepId + outcome +
hasHint, TTL 24 h). The reply to "correct on step 3 of Fruits 1" is the same
teaching beat for every child, so at scale most turns are cache hits. With
~20 lessons x 8 steps x 3 outcomes x 2 hint states = 960 distinct keys, the
provider is called at most 960 times per day per instance (~$0.085/day at
gpt-4o-mini) regardless of user count; LLM cost then approaches a constant.
Cost with hit ratio h = LLM cost x (1 - h). At 1,000+ users expect h >= 0.9,
i.e. the 10,000-user LLM-only figure drops from $133.81 to about $13.
Cached turns record 0 tokens in usage, so the spend ledger reflects it.

**Small model.** Per-turn LLM cost at A2/A3:

| Model | USD / turn | vs gpt-4o-mini |
| --- | --- | --- |
| gpt-5-nano | 0.0000415 | 0.47x |
| gpt-4.1-nano | 0.0000590 | 0.67x |
| gpt-4o-mini (default) | 0.0000885 | 1.00x |
| gpt-5-mini | 0.0002075 | 2.34x |
| gpt-4.1-mini | 0.0002360 | 2.67x |

`TUTOR_MODEL` switches it; cost estimates need the model in `prices.json`.

**Short output.** `max_tokens` is 160 and the schema forbids extra fields, so
output tokens (the 4x-priced side) stay near A3.

**Fallback is free.** Timeouts, errors and invalid turns are answered by the
deterministic mock at zero provider cost.

## Budget controls

- `MONTHLY_BUDGET_USD`: the server sums the estimated cost of every turn into a
  UTC-month ledger (`spend.json`, persisted). When the total reaches the
  budget, sessions and turns return `429 quota_exhausted` with
  `reason: "monthly_budget"` and a friendly message; the game shows the same
  break screen as the daily limit and falls back to the scripted tutor.
  Suggested setting: 2x the projection for the expected user count and mix
  (e.g. $30 for 1,000 users LLM-only with cache off).
- Daily per-user caps (300 s / 1800 s) and the per-turn cap (45 s) bound the
  worst case per user; rate limits bound abuse per IP and per session.
- `GET /api/v1/dev/spend` (DEV_MODE) shows month-to-date spend, the budget and
  cache hit/miss counts. Per-turn records in `turns.json` carry
  `costBreakdown` and `priceMissing` so a null price is visible, not silent.
- Provider-side: set a hard spend limit in the OpenAI project as the last line.

## Reproduce the numbers

```sh
cd backend && node -e '
import("./src/usage.js").then(({estimateTurnCost, loadPrices}) => {
  const prices = loadPrices("config/prices.json");
  const A = {inTok:350, outTok:60, turns:12, sttSec:4, ttsChars:70, freeDays:9, fcDays:15, fcSessions:3};
  const llm = estimateTurnCost({llmInputTokens:A.inTok, llmOutputTokens:A.outTok}, {prices, model:"gpt-4o-mini", sttMode:"device", ttsMode:"device"}).costUsd;
  const cloud = estimateTurnCost({llmInputTokens:A.inTok, llmOutputTokens:A.outTok, sttSeconds:A.sttSec, ttsChars:A.ttsChars}, {prices, model:"gpt-4o-mini", sttModel:"gpt-4o-mini-transcribe", ttsModel:"tts-1", sttMode:"cloud", ttsMode:"cloud"}).costUsd;
  const freeTurns = A.turns*A.freeDays, fcTurns = A.turns*A.fcSessions*A.fcDays;
  for (const N of [100,1000,10000]) for (const [k,pt] of [["llm",llm],["cloud",cloud]])
    console.log(N, k, (N*freeTurns*pt).toFixed(2), ((0.9*N*freeTurns+0.1*N*fcTurns)*pt).toFixed(2));
});'
```
