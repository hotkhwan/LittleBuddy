# Aliz Tutor — quota, entitlement and parent controls (Agent F)

The game stays free. The AI tutor's **active minutes** are the one metered thing:
FREE = 300 s per UTC day, Family Club = 1800 s per UTC day (configurable, never
"unlimited"). Real billing is disabled; nothing child-facing mentions money.

## Files
| File | Role |
| --- | --- |
| `game/content/tutor/quota_config.json` | `freeDailySeconds` 300, `familyClubDailySeconds` 1800, `warnAtSeconds` 60, `cloudTimeoutSeconds` 10, `pricingProposed` {THB, 99, "proposed"}. The ONLY place the price lives. |
| `game/scripts/tutor/quota/quota_config.gd` | Reads and bounds the config (a 0 free allowance is a typo, not a plan). |
| `game/scripts/tutor/quota/quota_ledger.gd` | LOCAL MIRROR: UTC-day ledger under SaveService settings key `tutorQuota` `{dayUtc, usedSeconds, entitlement, lastSeenUnix}`. |
| `game/scripts/tutor/quota/tutor_quota.gd` | The contract object the tutor scene talks to (below). |
| `game/scripts/tutor/quota/backend_response.gd` | Pure parser: HTTP status + body → `{ok, state, code, quota, ...}`. |
| `game/scripts/tutor/quota/cloud_quota_client.gd` | Node with one `HTTPRequest`; sessions / turns / end / entitlement, timeouts, `Idempotency-Key`. Flag-gated. |
| `game/scripts/entitlement/dev_entitlement_provider.gd` | Grants `familyClub` in memory; only with user arg `-- --dev-entitlements` or built directly by a test. |
| `game/scripts/entitlement/store_entitlement_provider.gd` | Stub: `validate_purchase()` always answers `pending_server_validation`; documents the Google Play / Apple integration points; receipts are validated by the backend only. |
| `game/scenes/parent/parent_settings.gd` | "Learn with Aliz" section behind the 3 s gate. |
| `game/tests/cases/test_tutor_quota.gd`, `game/tests/fixtures/tutor_backend_session.json` | 18 test groups; recorded backend shapes from `docs/ALIZ_TUTOR_API.md`. |
| `game/tests/shots_tutor_settings.gd` | Evidence frames `docs/shots/settings_aliz_{ipad,iphone}.png`, `settings_aliz_privacy_*.png`. |

## TutorQuota API (per docs/ALIZ_TUTOR_CONTRACTS.md)
```gdscript
var quota := TutorQuotaScript.new(save_service)   # optional: entitlement_service, clock Callable
quota.state()   # {entitlement "free"|"family_club", dailyAllowanceSeconds, usedSeconds,
                #  remainingSeconds, resetAtUtc, resetAtLocalText, sessionActive, mode, warnAtSeconds, exhausted}
quota.refresh() # day rollover / entitlement / (cloud) GET entitlement → quota_changed
quota.begin_session() -> bool   # false = nothing left today: show the break screen from state()
quota.tick(active_delta)        # only ACTIVE seconds; ignored while held / app inactive / no session
quota.end_session(reason := "")
signals: quota_changed(state), near_end(remainingSeconds), expired(), provider_unavailable(reason), mode_changed(mode)
holds (mirror play_session.gd): pause_for(r) / resume_for(r) / set_held(r, bool) / set_app_active(bool)
```

### The boundary handshake
`expired` never fires mid-turn, and never fires unless the scene asked:

1. Scene: `if quota.begin_session(): quota.request_end_at_boundary()` (arm).
2. Meter: counts `tick()`s. At 60 s left → `near_end(remaining)` once. At 0 → `is_exhausted()`
   flips, ledger flushed, **no signal**. (Cloud: `endAtBoundary: true` or `quota_exhausted` does the same.)
3. Scene, at the end of **every** tutor turn (Aliz finished speaking, answer handled):
   `if quota.boundary_reached(): show_break_screen(); quota.end_session()`.
   `boundary_reached()` returns true when the session should end; if armed it also emits
   `expired` exactly once per session.

Unarmed, the meter only reports (`boundary_reached()` still returns true when exhausted).
`begin_session()` returning false emits nothing: nothing started.

## Local mirror rules
* Restart-proof: ledger written every 5 s of use and on end/exhaustion; a new instance over the
  same save resumes the count.
* UTC day window: resets at the next UTC midnight; shown in local time (`resetAtLocalText`, e.g.
  "Resets at 07:00 tomorrow" in Bangkok).
* Clock rollback grants nothing: `lastSeenUnix` only moves forward; a new day is recognised only
  when now ≥ the stored day's end AND now ≥ lastSeenUnix. Seconds are never un-used (negative
  ticks ignored). A clock set FORWARD is a new day — only the server can tell the difference,
  which is why the server is the authority when the cloud is on.
* The stored `entitlement` is a record for the grown-up screen, never a grant: the entitlement
  service is asked every time.
* "Delete learning history" (parent gate, two taps) zeroes today's count and `tutorProgress`;
  keeps the day and the monotonic mark; never touches stars.

## Cloud mode (flag on only)
`quota.enable_cloud(tree, client_id, approval_token)` is refused while `TutorFlags.cloud_enabled()`
is false. When on: the server's `quota` block is truth (`state()` shows it verbatim; the local
ledger mirrors in the background and is raised to the server's `usedSeconds`, never lowered).
Error code → state: `quota_exhausted`→`exhausted`, `not_approved`→`needs_parent_approval`,
`provider_unavailable`/`timeout`/no reply/5xx→`provider_unavailable` (meter drops to local, lesson
continues with the scripted tutor), `rate_limited`→`rate_limited` (+`retryAfterSeconds`),
`session_ended`/`not_found`→`session_lost`, the rest→`client_error`. A conversation provider that
already talks to the backend can feed blocks with `apply_server_quota(quota, end_at_boundary)` /
`apply_server_failure(parsed)`. The client never claims a purchase and never computes minutes.

## Parent controls ("Learn with Aliz", behind the gate, inside the ScrollContainer)
AI Tutor On/Off (`aiTutorEnabled`, default true; cloud line says "not available in this build");
Daily AI allowance (used / allowance today + local reset time, read-only); Microphone permission
(from `SpeechService.describe_diagnostics().hasPermission`, else "Not checked"); Learning language
(disabled "English", fixed for V1); a note pointing at the existing voice sliders; Privacy (collapsed,
link-free); Delete learning history (two taps); Subscription (Free / Family Club, the configured
"THB 99 / month (proposed)", "Billing is not available yet."). Close / Done / gate unchanged.

## Not done / follow-ups
* Wiring the meter into the tutor scene (Agent B) and passing quota blocks from the backend
  conversation provider (Agent E) — the APIs above are the seams.
* A per-install `clientId` and the production parent-approval consent endpoint (backend follow-up).
* Real store plugins: not started, by decision; the stub names the integration points.
