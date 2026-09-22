# Little Days Production Architecture

Status: integration candidate, closed by default. This document describes the intended production boundary; it does not assert that production is deployed.

## Runtime boundary

Godot calls the Little Days Worker and never receives a provider credential. The Worker authenticates the parent/account, derives entitlements, chooses `local`, `standard_chat`, or `premium_live`, reserves quota, and invokes an environment-selected adapter. Standard candidates are OpenAI and DeepSeek; Premium Live is Gemini. Mock remains the safe default.

The account owns child profiles. Child records contain a nickname, age band, language, and learning level; legal name, exact birth date, address, and school name are not required. Raw child audio is not retained and long transcripts are not part of the production schema.

## Components

- Worker `little-days-api`: authentication, policy, normalized errors, request IDs, routing, consent, commerce callbacks, licensing APIs, and health.
- D1 `little-days-prod` (planned): durable business records and reconstructable usage mirrors. Its ID is intentionally unset until Cloudflare inspection succeeds.
- `TutorSessionDO`: ordered tutor session lifecycle and idempotent turn processing.
- `QuotaDO`: daily Standard counters plus concurrency-safe monthly Live reservations/finalization. Live objects are keyed by account, not child, for pooled allowance.
- Provider adapters: injected, provider-neutral interfaces; secrets exist only as Worker secrets.

## Fallback

Routing is capability and policy based: Gemini Live → Standard text Tutor → deterministic local lesson. Quota/provider failures select the next mode and must not expose infrastructure language to a child.

## Environments

Development, staging, and production use separate Workers, D1 databases, Durable Object namespaces, variables, secrets, and domains. Production configuration sets `PRODUCTION_ENABLED=false`, `BILLING_ENABLED=false`, `LIVE_CHILD_AUDIO_ENABLED=false`, and mock providers. No production ID is invented.

