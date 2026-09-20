# Aliz Tutor backend — security findings for Agent D

Reviewer: Agent G (security / child privacy). Date: 2026-09-20.
Scope: read-only review of `.worktrees/backend` at commit `1ec9cbc`
("backend: Aliz Tutor service (Node 22, zero deps) ..."), files under
`backend/src/`, `backend/.env.example`, `backend/README.md`,
`docs/ALIZ_TUTOR_ARCHITECTURE.md`. Nothing was changed there; the lead routes
these. Line numbers are against that commit.

Severity: **H** must be fixed before any non-DEV_MODE deployment; **M** before
the cloud flag is enabled for any child; **L** hygiene / hardening.

## What is already right (so it is not undone)

- The provider key is server-only, read from `process.env`, never echoed
  (`config.js:53`, `openai_provider.js:118`), `.env.example` holds names only,
  `backend/.env`, `backend/data/` and `node_modules/` are gitignored
  (the "Aliz Tutor backend" block at the end of `.gitignore` on that branch).
- Transcripts are **not persisted and not logged**: `store.turns` holds usage
  numbers only (`usage.js:89-104`); the turn cache key excludes the transcript
  (`turn_cache.js:19`); every `log()` call carries method/path/status/latency,
  provider name or validator reasons (`app.js:48,136,146,343`, `server.js:35`).
- The prompt sends lesson context + this turn's transcript and nothing else:
  no clientId, sessionId, name, age, device (`openai_provider.js:58-71`);
  `store: false` is set (`openai_provider.js:107`); strict JSON schema plus a
  second content validator with the safe fallback turn (`app.js:133-157`).
- Body limit 32 KB, transcript 500 chars, id regex, per-IP and per-session
  fixed-window rate limits, provider timeout 6 s inside a handler timeout 10 s,
  AbortController propagation, atomic JSON writes, corrupt-file quarantine.
- Constant-time HMAC compare on the parent token (`parental_approval.js:50`);
  token bound to clientId with expiry (`:59-60`); dev literal only in DEV_MODE.
- Client-supplied `visualAssetId` is dropped unless allowlisted (`app.js:108`).
- 500s are generic (`errors.js:44`); stack traces go to the log, not the body.

## Findings

### H1. No production path mints a parent-approval token — and the token is not consent
`app.js:318-322` is the only mint route and it exists only under
`config.devMode`. Outside DEV_MODE nothing can create a session
(`server.js:106` even warns about it). That is safe today, but it means the
"verifiable parental consent recorded server-side" gate condition is
unimplemented, not merely unwired. When a mint route is added it must be
driven by a *real* consent event (see `ALIZ_TUTOR_PRIVACY_REVIEW.md` §F), not
by the 3-second hold: the hold is a Kids-Category *parental gate*, and Apple's
own guideline 5.1.4(b) says that "is generally not the same as securing
parental consent to collect personal data". Record `{clientId, consentedAt,
method, policyVersion, revokedAt}` server-side and make `verify()` consult
that record, so revocation works (today a signed token stays valid for 30 days
after a parent withdraws; there is no revocation list and no `jti`).

### H2. Quota identity is client-chosen; a compromised or curious client can mint unlimited free days
`clientId` is any string matching `ID_RE` (`app.js:174`). Quota, entitlement
and the approval token are all keyed on it. In production a new clientId needs
a new token (good), but with H1 unimplemented the first mint route written in
a hurry will hand a token to whoever asks. Design the mint so the *consent
record* is the identity (server-issued opaque id returned to the device after
consent), not a device-invented string. Also bind the session to the token
(`app.js:185-196` stores `approvedVia` but not which token), so a stolen token
can be traced and cut off.

### H3. Session id is a bearer credential with no ownership check
`POST /sessions/{id}/turns` and `/end` (`app.js:201-205, 281-284`) accept any
caller who knows the UUID. UUIDv4 is unguessable, but the id appears in the
request path and is therefore written to the access log at info level
(`server.js:35`) and to any reverse-proxy log. Anyone with log access can
inject turns into a live child session (they get the LLM reply, not the
child's words, but they can burn the family's quota and, via `lessonContext`
text, steer what Aliz says — see M2). Require the parent token (or a
per-session secret returned at create time) on every session route, and log
only a hash prefix of ids.

### H4. Monthly budget guard is off by default
`config.js:58`: `monthlyBudgetUsd` is `null` unless `MONTHLY_BUDGET_USD` is
set, and `usage.js:127` treats null as "no limit". With `TUTOR_PROVIDER=openai`
that is an unbounded bill. Fail closed: refuse to start (or force the mock
provider) when the OpenAI provider is selected and no budget is configured.
Also add a per-clientId daily *turn* cap independent of seconds; the seconds
quota charges elapsed time, so a client that fires 30 turns/min for 45 s is
charged 45 s but costs 30 provider calls (`app.js:204, 231-232`).

### M1. Access log records `clientId` and session ids at info level
`server.js:35` logs `req.url`. `GET /api/v1/tutor/entitlement?clientId=...`
puts the persistent identifier in the line; session routes put the session id
there. The architecture doc (`ALIZ_TUTOR_ARCHITECTURE.md:125-126`) says logs
carry "method/path/status/ms only, never transcripts" — true for transcripts,
but a persistent identifier tied to a child's device is COPPA personal
information (16 CFR 312.2, "persistent identifier"). Redact query strings and
path params (log the route *pattern* from the router match, not the URL).

### M2. Client-supplied lesson text is injected into the prompt verbatim
`app.js:98-107` accepts `hint`, `nextQuestionText`, `matched`,
`expectedAnswers` from the client and `openai_provider.js:60-69` places them
in the user message. The output validator (`turn_validator.js`) limits the
damage (ASCII, length, URL pattern, banned words), but a modified client can
still make Aliz say arbitrary age-inappropriate sentences that pass a 40-word
banlist. The server has the lesson files in the repo
(`config.js:69` already reads `game/content/tutor/assets_allowlist.json`):
resolve `lessonId/stepId` server-side from `game/content/tutor/lessons/` and
ignore client-supplied hint/question text. Then the only free text from the
device is the transcript, which is what the design intends.

### M3. Idempotency store persists a SHA-256 of the full request body, forever
`app.js:161-163, 264` hashes the body (which contains the transcript) and
`store.idempotency.set` writes it to `data/idempotency.json` with no TTL.
Child transcripts are low-entropy ("apple", "red"); an unsalted hash of a
small body is dictionary-reversible. Use an HMAC with a server secret, or hash
only `lessonContext.stepId + outcome + transcript.length`, and expire entries
with the session (see M4).

### M4. No retention policy: `sessions`, `turns`, `idempotency`, `usage` grow without bound
`store.js` never deletes. `sessions.json` keeps `clientId`, `lessonId`,
timestamps and end reason for every session ever started. The 2025 COPPA
amendments require retention only "for as long as reasonably necessary to
fulfill a specific purpose" and a written retention policy (FTC release
2025-01-16, quoted in the privacy review §C1); Apple 5.1.1(i) requires the privacy policy to
state retention. Implement: sessions and idempotency purged 24 h after
`endedAt`; per-session `turns` rolled into a daily aggregate and deleted after
30 days; `usage` (quota) kept for the current UTC day + 1; and a
`DELETE /api/v1/tutor/client/{clientId}` (parent-token-authenticated) that
implements "Delete learning history" server-side.

### M5. `X-Forwarded-For` is ignored outside DEV_MODE, so behind any proxy the IP limit is global
`server.js:55`: production uses `req.socket.remoteAddress`, which behind the
TLS-terminating proxy the architecture doc prescribes is the proxy's address.
Result: 120 requests/min shared by *every* family, i.e. a trivial DoS by one
device, or (if the proxy is bypassed) a spoofable header in dev. Add a
`TRUST_PROXY_HOPS` setting and take the n-th-from-right XFF entry only when
set.

### M6. Session and turn routes are not tied to the approval that created them; approval expiry is not re-checked
Once created, a session accepts turns until quota runs out even if the parent
token expired or (after H1) was revoked. Re-verify on each turn, or at least
stamp `approvalExp` on the session and refuse turns past it.

### M7. Fixed-window limiter allows a 2x burst at the boundary and is per-process
`rate_limit.js:16-28`. Two instances or a restart reset the limits. Fine for
one box; note it in the deployment runbook and pin a single instance until a
shared store exists. Consider a sliding window for the per-session limit.

### L1. Key reuse between parent-approval HMAC and mock-billing HMAC
`entitlement.js:14` signs mock receipts with `PARENT_APPROVAL_SECRET`. Mock
billing is DEV_MODE-only (`:68`), so no live impact, but derive a separate key
(`HKDF(secret, "mock-billing")`) so the two purposes can never collide.

### L2. CORS default `*`
`config.js:38`. Irrelevant to the Godot client (no browser), harmful only if a
browser front-end is ever pointed at it. Default to no CORS headers unless
`CORS_ORIGIN` is set.

### L3. `/healthz` discloses provider model, dev mode and allowlist source
`app.js:166-169`. Low value to an attacker but free information; return
`{ok:true}` publicly and the detail only in DEV_MODE.

### L4. `audioSeconds` is client-supplied and feeds cost accounting
`app.js:221`. Only matters when `STT_MODE=cloud`; then a client can
under-report. Server-side STT would know the real duration; until then cap it
(already 30 s) and mark it `clientReported` in the usage record.

### L5. Client disconnect still charges quota
`ALIZ_TUTOR_ARCHITECTURE.md:106` says "nothing charged or recorded" on client
disconnect, but `quota.charge()` runs at `app.js:232` *before* the provider
call. Either move the charge after `produceTurn` (and charge on timeout too) or
correct the doc. Charging-before is the safer default; fix the doc.

### L6. `OPENAI_EXTRA_HEADERS` is an arbitrary header injection point from env
`config.js:55`, `openai_provider.js:118`. Env is trusted, but a typo can
override `authorization`. Reject keys `authorization`, `content-type`, `host`.

### L7. Prompt says "children aged 3 to 6" to the provider
`openai_provider.js:18`. Not personal data (no individual), but it is the
sentence that makes the under-13 nature of the traffic unambiguous to the
provider, which is correct and honest. Keep it; it is why ZDR is mandatory
(OpenAI Under-18 guidance, see privacy review §B).

### L8. No `safety_identifier` / `user` field is sent — keep it that way, but record the decision
OpenAI's safety best-practices page recommends a per-end-user identifier for
abuse tracing. Sending a hashed clientId would be disclosing a persistent
identifier of a child to a third party (COPPA PI). The current omission is the
right call; document it in the architecture doc so a later "best practices"
pass does not add it.

### L9. `git log` shows the placeholder `sk-test-not-real` in `test/openai_provider.test.js`
Harmless (it is what makes the history scan find *something*), but rename it
to `test-key-not-real` so a naive secret scanner (and the guard in
`test_tutor_privacy_guards.gd`, which flags `sk-` + 16 chars) never trips on
it if the test file is ever copied under `game/`.

## Not reviewed / out of scope

- No runtime was executed and no network call was made; the review is static.
- Real store billing (Play / App Store) is stubbed with TODOs; when written it
  needs its own review (receipt replay across clientIds is already handled for
  the mock platform at `entitlement.js:73-77`).
- TLS, deployment, secret storage on the host, and log shipping are outside
  the repository; they are gate conditions in the privacy review, not code
  findings.
