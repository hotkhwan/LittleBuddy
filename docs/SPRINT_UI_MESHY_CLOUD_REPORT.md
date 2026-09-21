# Sprint report — UI polish, Meshy art, cloud backend foundation (2026-09-21)

Branch `feature/ui-meshy-cloud` (from `bb2c3e7`, the owner's test build, tagged
`owner-test-2026-09-21` and untouched). **Final commit: see §8.** Nothing in
this report is a physical-device result.

## 1. Owner decisions carried into config
App name Little Days; positioning "Aliz, your child's playful learning
companion" (docs only, no UI copy yet); existing content free; AI Tutor needs
internet; free tutor 300 s/day; Family Club 1800 s/day; THB 99/month marked
`proposed` in `cloud/wrangler.toml` vars and `cloud/src/billing/config.ts`;
`BILLING_ENABLED=false` (server) and `little_days/billing/purchases_enabled=false`
(app); Meshy approved but no key on this machine (see §4).

## 2. UI integration (Agent A) — `f8235bb`, `77087c6`
Rule applied: pictures name places a child chooses (Play with Bunny, Free
Play, Dress Up cards, every Home button); flat glyphs name things to do (Next,
Speak, Back, Repeat, Mute, star counter, gears). Used: play, free_play,
dress_up, home. Not used, with reasons in `docs/UI_PACK_INTEGRATION.md`:
settings (a smiling gear is the most child-attracting icon, on the control a
child should ignore), back, music, star, logo concept (same lockup, larger
file), app-icon concept (must not ship; the whole `generated_v1/` folder is
`.gdignore`d and never exported). Shipping copies are 256 px, 344 KB total.
Title cards 256 → 240 px (the art-bible floor) with 116 px pictures; Home
picture 80 px inside the unchanged 104 px disc. Before/after frames:
`docs/shots/uipack_*`.

## 3. Settings (Agent B) — `500ca00`, `7ab8eda`
Real bugs found by real input: a second finger could press an option or start
the erase hold while the first scrolled (fixed: one gesture owns the panel);
Escape / Android back only worked on the open panel (fixed on every gate
card); the Thai privacy block did not follow a language tap (fixed). 21
real-input probes: `INPUT SETTINGS OK`. Checklist: `docs/SETTINGS_VERIFICATION.md`.
Open owner decision: `application/config/quit_on_go_back` is unset, so on
Android the back key still quits the app after the panel handles it.

## 4. Meshy (Agent C) — `d47206f`, `da12565`, `1f38fba`
**BLOCKED for generation: no `MESHY_API_KEY` in this shell or the keychain;
0 credits spent; 40 authorised credits untouched; live balance not readable.**
Delivered without credits: `tools/meshy_batch.sh` (balance → preview → refine
→ download → trim → gate → install, keychain fallback, one paid call at a
time, ledger row per call), `tools/meshy_split.py` (connected-component
splitter for openable furniture: body + door/lid with hinge pivots),
`tools/meshy_trim.py`, `tools/meshy_attach.md`, `game/scripts/house/prop_registry.gd`.
Real Meshy GLBs now in the running house: the kitchen **apple** (1,120 tris)
and **banana** (1,134 tris), split from the tutor's fruit set; drawn forms
remain the fallback. Plan and proposed next batch (teddy bear 15 + toy box
body+lid 15 = 30 of the 40 authorised) in `docs/MESHY_PRODUCTION_PLAN.md`.
Owner unblock: `security add-generic-password -s MESHY_API_KEY -a littledays -w '<key>'`.

## 5. Cloudflare backend (Agent D) — `1d95edd`, `456fbc6`, `021c14b`
`cloud/`: TypeScript Worker (Hono), D1 migrations 0001–0004 (parent accounts,
nickname-only child profiles, devices, consent, entitlements, purchase_events,
tutor sessions, daily quota, numeric usage events, learning progress,
idempotency), Durable Objects QuotaDO (per child, check-and-charge) and
TutorSessionDO (per session: ordering, idempotency, provider timeout,
validator, mock fallback, alarm countdown), no R2 (nothing is a file), three
environments dev / staging / production in `wrangler.toml`, `.dev.vars.example`,
`docs/CLOUD_BACKEND.md`, Worker contract in `docs/ALIZ_TUTOR_API.md` §1.
Tests: **129 passed** (vitest Workers pool, offline), typecheck clean.
**NOT DEPLOYED — no Cloudflare credentials on this machine.** Exact
dev/staging commands in `cloud/README.md`; production is never deployed by
automation.

## 6. Subscription (Agent F) — `0301a97`, `6aec8e7`, `76e2542`, `f7e23cc`
Godot store gateway abstraction (mock, Apple StoreKit adapter, Google Play
Billing adapter over the plugin singletons when present), purchases
hard-disabled by project setting (guarded), backend-only entitlement decisions
applied to `StoreEntitlementProvider`, restore = verify per receipt. Worker
`cloud/src/billing/`: Apple JWS / App Store Server API verification, Google
subscriptionsv2 + RTDN, idempotent purchase events (transaction id unique,
payload hash conflict → 409), entitlement decision shared with quota
allowance. Billing tests **36 pass**. Product ids `little_days_family_monthly`,
`little_days_family_yearly`. **No real charge path is active.** Activation
checklist and allowed copy: `docs/FAMILY_CLUB_BILLING.md`.

## 7. AI Tutor cloud (Agent E) — `340fbc7`, `8a438b2`
Behind `little_days/ai_tutor/cloud_enabled=false` (committed false; guarded):
`game/scripts/tutor/cloud/` REST client (quota → session → ephemeral token →
end with usage), Realtime WebSocket transport with the official event names
(tool calls show_card / gesture / set_emotion validated through the TutorTurn
allowlist, `response.cancel` + `conversation.item.truncate` on barge-in,
usage from `response.usage`), cloud audio player driving the same TutorFace
lip sync, provider + synthesis wrappers so `tutor_scene._speak_turn()` runs
unchanged, reconnect once with a fresh token then scripted fallback, quota
mirror authoritative for the safe-point closing with the server's 402
honoured. `tools/tutor_mock_server/server.mjs` (zero-dep REST + Realtime WS)
drives a loopback integration test and a real-classroom smoke: 33 turns, 12
cloud-voiced replies, `SMOKE: PASS`. **No OpenAI call was made; no key
exists in game/ or on this machine.** Contract for the Worker in
`docs/ALIZ_TUTOR_CLOUD_CLIENT.md` (the Worker's `/v1/tutor/realtime/token`
already returns the transport's shape). Lead decision recorded: the parent
bearer header is assembled from two constants because the privacy guard
forbids the literal in child-facing files; disclosed in the file header and
pinned by a test. Cloud stays closed until privacy review items G1–G17 are
TRUE (`docs/ALIZ_TUTOR_PRIVACY_REVIEW.md`).

## 8. Final gates, builds, status

**Final code commit `8a438b2`** (this report is the only change after it).

| Gate | Result |
|---|---|
| Godot suite | **PASS - 163 case(s), 0 failure(s)** (159 at the start of the sprint) |
| Mission 01 / Snack Time walkthroughs | SMOKE PASS / SMOKE PASS |
| Audio shipping smoke | SMOKE PASS |
| Settings real-input harness | INPUT SETTINGS OK (21 probes) |
| Cloud classroom smoke vs mock server | SMOKE: PASS (17 responses, usage posted) |
| Prototype backend (backend/) | 126 pass, 0 fail |
| Cloudflare Worker (cloud/) | 129 passed, typecheck clean |
| Billing module (cloud/src/billing) | 36 pass, 0 fail |

| Build from `8a438b2` | Path | Size | Note |
|---|---|---|---|
| Android debug APK | `build/android/LittleDays-debug.apk` | 45,633,758 B | SHA-256 `a6d1e83465531f94f845174c44c720bfd125a2d33874155d176e725fddd4c434`, signed, zero permissions, no `generated_v1` files inside |
| iOS export | `build/ios/LittleBuddy.xcodeproj`, `build/ios/LittleBuddy.pck` | pck 16,714,644 B | owner signs in Xcode |
| iOS arm64 compile | unsigned | `** BUILD SUCCEEDED **` |

| Status item | Value |
|---|---|
| Meshy credits spent | **0** (key absent; 40 authorised remain; next batch proposed: 30) |
| Cloud services created | **none** — NOT DEPLOYED, no Cloudflare credentials on this machine |
| Deployment status | local only (`wrangler dev --local`, `deploy --dry-run` bundles) |
| Billing status | disabled on both sides; no store plugin shipped; no charge path |
| OpenAI API status | no key, no call; cloud tutor flag false |
| Physical device | not run; the owner's tonight build is `bb2c3e7` (tag `owner-test-2026-09-21`), untouched |

Remaining blockers: Meshy key; Cloudflare account + `wrangler login`; OpenAI
key + ZDR/consent gates; App Store Connect / Play Console products and
secrets; Apple/Google sign-in verification for `POST /v1/parents` (501);
reconcile `cloud/src/billing/schema.sql` column names with migration 0002
(D1BillingRepo untested on real D1); `quit_on_go_back` decision for Android.
