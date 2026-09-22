# AI provider routing

Last updated: 2026-09-22

## Measured selection

The fixed live Workers AI benchmark selected these routes. This is an engineering selection for closed testing; educator review remains required before public child use.

| Role | Selected model | Evidence summary |
|---|---|---|
| Standard primary | `@cf/google/gemma-4-26b-a4b-it` | Best deterministic adherence (96.7%) and 3/3 tool plus 3/3 JSON validity; 7,542 ms median, 17,667 ms p95 |
| Standard fallback | `@cf/zai-org/glm-4.7-flash` | Strong Thai and concise responses, but tool arguments failed exact validation in 3/3 cases; 7,290 ms median, 12,667 ms p95 |
| Complex reasoning | `@cf/openai/gpt-oss-120b` | Fastest and no transport failures; 2,791 ms median, 6,446 ms p95, but too verbose/inconsistent for routine child turns |
| External fallback | OpenAI Luna or DeepSeek Flash | NR because owner-managed external credentials were unavailable |

The detailed evidence and limitations are recorded in `AI_PROVIDER_BENCHMARK.md`. A model is not promoted solely because it is cheapest or returns HTTP 200.

## Routing order

```text
1. Deterministic local lesson/action
   -> if the answer or activity is known, stop here

2. Standard AI
   -> bounded explanation, alternate example, short tutor turn
   -> standard primary, then standard fallback for retryable failure

3. Complex reasoning
   -> only for genuinely multi-step, age-appropriate questions
   -> never for routine vocabulary, praise, known curriculum facts or tool dispatch

4. External fallback
   -> only when enabled, budgeted and credentialed server-side

5. Deterministic local fallback
   -> safe lesson prompt/activity when providers fail or output is invalid
```

Routing is server-side. Godot sends a learning intent/session event, not a provider name or arbitrary model identifier.

## Request classes

| Request | Route | Reason |
|---|---|---|
| “What color is this?” with an approved card | Local deterministic | The curriculum and asset already contain the answer |
| Repeat a prompt, give a fixed hint, award a validated reward | Local semantic tool | No generative inference is needed |
| “What does apple mean?” | Standard primary | Short scoped explanation inside approved curriculum |
| Alternate Grade 2 example | Standard primary with retrieved approved context | Generative variation is useful but bounded |
| Malformed/unsafe response from primary | Standard fallback or local fallback | Never forward unvalidated output |
| “Why does the moon change shape?” within an approved future lesson | Standard first; reasoning only if the standard result fails the quality policy | Avoid expensive reasoning for simple turns |
| Arbitrary internet lookup | Reject/use local lesson | Child lessons use the controlled curriculum, not open web search |

## Eligibility gates

Before any provider call, all of these must pass:

1. The environment allows the feature. Closed production blocks tutor traffic while `PRODUCTION_ENABLED=false`.
2. Parent approval, authentication, consent and child-profile ownership are valid.
3. Entitlement, daily/monthly quota and budget are available.
4. The lesson is active, versioned, English, and in an enabled subject.
5. The request is within body, transcript, session and per-minute limits.
6. The selected route is available and configured server-side.

Voice additionally requires the live-child-audio privacy gate. Development synthetic/adult QA may exercise voice without treating it as approved child production traffic.

## Standard provider contract

The normalized Workers AI adapter exposes chat, structured output and tool calls. It records normalized input/output usage when available and classifies retryable failures:

- timeout or caller cancellation;
- HTTP 429/rate limit;
- HTTP 503/529 or capacity/overload;
- malformed structured response;
- non-retryable provider error.

Structured output and tool calls are still untrusted. Tutor turns pass through the shared turn validator. Learning-agent tools pass through the semantic allowlist, exact argument validation, lesson-asset check and rate limiter.

## Fallback rules

Retry/fallback is allowed only when it is safe and bounded:

- Retry a timeout, 429 or capacity failure at most according to the route policy and remaining latency budget.
- Do not retry malformed/unsafe output repeatedly; switch provider once or use the deterministic fallback.
- Do not retry a client cancellation.
- Do not exceed child/session quota because an upstream provider failed.
- Preserve idempotency for rewards, lesson completion and other state changes.
- Do not expose provider names or infrastructure errors to the child.

The currently wired TutorSession path calls one configured provider and then uses the deterministic mock when output fails validation or provider execution fails. Multi-model primary/fallback/reasoning orchestration is the intended routing policy but must not be reported as fully implemented until a router invokes and tests those roles.

## Model selection policy

After live benchmark artifacts are complete, choose roles in this order:

1. Eliminate any model that fails child-safety or personal-data cases.
2. Eliminate models with unreliable JSON/tool arguments for routes that require them.
3. Require adequate English pedagogy and Thai-parent-context comprehension.
4. Compare age fit, correctness and brevity.
5. Check median/p95 latency against interaction budgets.
6. Compare measured token usage and cost among the remaining qualified models.

The complex model should earn its route on quality improvement over the standard model. If it does not materially improve the gated reasoning cases, it should not be called in production.

## AI Gateway behavior

The provider registry currently sends Workers AI requests through the actual Cloudflare `default` AI Gateway. The intended dedicated gateway, `little-days-ai`, could not be created with the current token permissions and therefore is not claimed as an existing resource.

All personalized calls use `skipCache: true`. This prevents a child's conversation from being served from, or added to, a shared response cache. Gateway capabilities may support aggregate analytics, latency/error observation, rate policies and cost monitoring, but payload logging must remain minimized and raw child audio must never be logged.

When `little-days-ai` becomes available, switching gateway IDs is a server-side configuration/integration change. It does not alter the Godot protocol or provider interface.

## Provider swapping

Provider-specific details remain behind the server adapter. A provider is eligible only if it implements the normalized operations needed by its route and maps results into the common usage/error contracts. External API keys live only in Worker secrets.

Changing a provider requires:

- successful fixed-suite benchmark artifacts;
- child-safety and structured/tool validation results;
- timeout, outage, quota and malformed-response tests;
- cost/budget configuration;
- dev deployment and synthetic QA;
- explicit closed-production configuration review.

It must not require a Godot release or expose a provider credential to the client.

## Cost and quota controls

Prefer the least expensive model that passes the quality gate for the request class. Cost is recorded from normalized token usage and model rates; missing usage is not treated as zero cost. Environment policy supplies provider budgets and plan quotas. Prices are configuration/documentation data, never hard-coded commerce behavior in the client.

Routing should stop or fall back locally when:

- daily or monthly provider budget is exhausted;
- the child/session entitlement is exhausted;
- the provider has sustained capacity errors;
- the request does not require generation;
- no model passes the safety/quality gate.

## Production posture

Development may use Workers AI for synthetic and controlled test content. Closed production retains:

```text
PRODUCTION_ENABLED=false
BILLING_ENABLED=false
LIVE_CHILD_AUDIO_ENABLED=false
```

The production Worker and bindings can be deployed and health-checked while these gates remain closed. Enabling public AI learning, billing, or child audio is a separate owner decision requiring the relevant quality, legal, privacy and physical-device gates.
