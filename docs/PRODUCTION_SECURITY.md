# Production Security Review

Current disposition: not approved for public traffic.

- Secrets: names only are committed; OpenAI, DeepSeek, Gemini, Apple, Google, and signing values remain Worker secrets. Godot receives none.
- Closed mode: production config denies tutor, billing, and school activation while health/readiness remain available. Billing and child Live audio have independent false gates.
- Authentication/authorization: parent credentials are server-verified; child profiles are resources under a parent account; entitlement claims are recomputed server-side.
- Validation/SQL: bounded request bodies and typed field validation are used; D1 values are bound parameters.
- Replay/idempotency: commerce lifecycle and licensing activation have replay protection; tutor finalization and turns are idempotent.
- Abuse: IP/endpoint limiting exists; Durable Objects serialize Tutor and pooled Live quota. Account/plan distributed rate limiting remains a launch gate.
- Logging: structured request IDs and status/latency are logged without request bodies. Do not log secrets, raw audio, or full conversation text.
- Webhooks: store signature/token verification credentials are not configured. No callback may be considered trusted until verification integration tests pass.
- CORS: no broad browser CORS grant is configured. A documented parent-web origin allowlist is required before browser access.
- Privacy: minimum child profile fields, versioned consent, export/deletion schema, no advertising identifiers, and no raw child-audio retention.

Required independent review: auth isolation, webhook replay/signature validation, CORS, D1/DO recovery behavior, rate limits, dependency/SBOM scan, and privacy/legal approval for child voice.

