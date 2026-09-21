# Sprint report — Cloudflare dev deployment, Meshy props in play, accounts, tutor cloud (2026-09-21)

Branch `feature/ui-meshy-cloud`. Owner-test build `bb2c3e7` (tag
`owner-test-2026-09-21`) untouched. **Final commit: see §9.** Everything here
is automated or live-HTTP evidence; no physical device was used.

## 1. Cloudflare — development API is live
| Item | Value |
|---|---|
| Account | `8d67bfb5b60f8e54544e4aac74a98cc9` (owner of `joinanny.com`), pinned in `cloud/wrangler.toml`; the OAuth login's two other accounts are never used |
| Worker / env | `little-days-api-dev`, environment `dev` (`DEV_MODE=1`, mock provider) |
| Endpoint | `https://little-days-api-dev.hotkhwan.workers.dev` |
| Health | `GET /healthz` 200; `GET /healthz?db=1` 200 `"db":{"ok":true,"migrations":5}` (re-checked after the final integration) |
| D1 | `little-days-dev` `5c1b5784-be19-4125-9375-82e05b507a34` (owner-created), binding `DB`, migrations 0001–0005 applied remotely |
| Durable Objects | `TUTOR_SESSION`, `QUOTA` (SQLite classes, tag v1) — exercised by live sessions: quota `usedSeconds` grows per turn, ends at 300 s |
| Secrets | `PARENT_TOKEN_SECRET` (dev only). No OpenAI key, no store secrets |
| Domain | `api.littledays.joinanny.com/*` is an inactive Workers Route with no script; no Custom Domain exists. `[env.production]` now names `little-days-api` with that route. **Production NOT deployed.** Dev sign-in is NOT attached to the public hostname. `littledays-web` (website Worker) untouched |
| Deploy record | `docs/CLOUD_DEPLOYMENT_DEV_2026-09-21.md` (verbatim HTTPS transcript: sign-in, consent, session, turn, idempotent replay, 400, 403, quota, 503 realtime, end, 409, billing 503) |

## 2. Parent accounts (Agent B) — `aca3dca`, `dddde6f`, `313399d`
Apple / Google identity-token verifiers (JWKS, injectable, offline-tested), dev
verifier in DEV_MODE only, hashed subject/e-mail (never raw), `GET /v1/parents/me`,
`/me/subscription`, `/me/export`, `DELETE /v1/parents/me` (cascade + 30-day
tombstone, entitlements revoked-by-deletion kept for audit), child GET/PATCH/DELETE,
migration 0005, nightly tombstone sweep. Live: `POST /v1/parents {provider:"apple"}`
answers `501 not_implemented` until `APPLE_BUNDLE_ID` / `APPLE_SERVICE_ID` /
`GOOGLE_CLIENT_IDS` are set. Portal contract: `docs/PARENT_PORTAL_API.md`.

## 3. AI Tutor cloud (Agent C) — `1af02bb` … `f510be8`
The Godot client was reconciled to the deployed Worker (11 mismatches fixed
on the client, table R.1 in `docs/ALIZ_TUTOR_CLOUD_CLIENT.md`). Live classroom
smoke against the dev Worker on the final head: session
`653d076d-…`, 11 server-authored turns with flashcards and gestures, quota
`usedSeconds 86.7 / 300`, `usedTurns 11`, ended `lesson_complete`, server
acknowledged, **`mic after break: is_capturing=false is_active=false`**,
`SMOKE: PASS`. Live dev-API case: idempotent replay not charged; quota driven
to 300 s with `X-Debug-Now` → client ends at the boundary, `/end` posted once,
409 after end, 403 on a bogus approval; realtime token 503 → turns path, the
classroom never dies. Flag `little_days/ai_tutor/cloud_enabled` **stays false**;
no OpenAI key, no live audio; synthetic data only.

## 4. Meshy (Agent D) — `4ee66c4`
| Asset | Task ids (preview / refine) | Credits | Result |
|---|---|---|---|
| teddy | `01a0c359-0d64-729f-98fe-4f3d84b4a8b6` / `01a0c359-7b16-71a1-b767-ec7be3cbce06` | 15 | ACCEPTED, `game/assets/models/meshy-props/teddy.glb`, 2,599 tris, 512² |
| toy box (body + lid, one task, split locally) | `01a0c35c-7baf-711a-a2df-d5991cf5a092` / `01a0c35f-8605-77b3-bfde-f5b08153c4a4` | 15 | ACCEPTED, `toyBoxBody.glb` 1,820 tris, `toyBoxLid.glb` 162 tris (`hingeBack` pivot) |

Balance **3174 → 3144**: 30 credits spent, 10 of the 40 authorised unspent;
sprint total 90 of 100. Auth PASS (HTTP 200), no API errors, no double spend
(verified after the stall by listing the account's recent tasks). Bottle, cup,
blocks NOT generated (would exceed the allowance); next batch proposal in
`docs/MESHY_PRODUCTION_PLAN.md` §9 (bottle + blocks + fridge = 45).
Ledger: `docs/MESHY_CREDIT_LEDGER.md`.

## 5. Gameplay integration (lead) — `ef39d9b`
- **Teddy**: `object_spawner.gd` `MODEL_UPGRADES` maps the frozen Chapter-2
  record `teddy` to `meshy-props/teddy` (content stays frozen; the guard test
  passes). The Meshy pack is built by the `PropRegistry` (own texture, pivot,
  tri gate 3,000); absent GLB → the old model as before. The teddy therefore
  appears wherever the `teddy` record spawns: the house bedroom draggables
  (TAKE → carried in hand → PLACE; tidy-up puts it in the box; bedtime hands it
  to Bunny) and the Baby Room `dragToHug`.
- **Toy box**: `room.gd::_build_storages` uses `PropRegistry.instance("toyBoxBody", size.x)`
  for the body (base on the layout floor; collider, target and stand point
  unchanged) and `PropRegistry.instance("toyBoxLid")` under the SAME
  `StorageLid_toyBox` hinge, now positioned on the generated body's real hinge
  line (manifest `attach.hingeOffsetMetres`), so `set_storage_open()`'s swing is
  untouched: OPEN badge → lid swings open (104°) → the tidy loop scatters
  toys → each toy dropped in is praised → "All tidy!" → replays. Drawn body/lid
  remain the fallback.
- Evidence: `docs/shots/freeplay_tidy_ipad.png` (Meshy box open with the Meshy
  teddy on the rug and "Put the blocks away!"), `freeplay_bedtime_ipad.png`,
  `props_toybox_closed_ipad.png` / `props_toybox_open_ipad.png`,
  `props_meshy_ipad.png`. Tests: `test_freeplay_acts` tidy loop and bedtime,
  `test_carry_props`, `test_assets_models` (manifest rows, budgets, licence).

## 6. Interaction badges and HUD (Agent F) — `cbda120`, `fa69814`
Badge picture (120 px disc, 72 px glyph, 40 px word pill at design scale) split
from the 240 px hit box; one badge language; hard keep-outs for controls and
visual keep-outs for Aliz's face, Bunny's face (standing and in her arms), the
bubble and the target silhouette; ring no longer crosses faces; star counter
is the shared star glyph; picker cards match the title cards. New
`test_badge_keepouts` runs the real house at three sizes. Before/after:
`docs/shots/badge_before_*` / `badge_after_*`, `picker_before_*` / `picker_after_*`.

## 7. Website and parent portal (Agent W) — `3eeab18`, `e30ad6b`
`web/`: static Worker project named `littledays-web` (assets only, no routes,
account pinned). Home, Privacy (only what the code guarantees; exact tutor
sentence), Support (one owner TODO for contact), `/parents` dev-only portal
(dev sign-in, children, consent switches, tutor minutes, subscription "not
available", permanent "Development data" banner, loopback-only API guard,
strict CSP). 12/12 tests. **Not deployed**: deploying overwrites the owner's
existing `littledays-web` Worker, so it is a by-hand step (`web/README.md`).
Blocker for live mode: the Worker emits no CORS headers (documented in
`docs/WEBSITE.md`).

## 8. Gates on the final head
| Gate | Result |
|---|---|
| Godot suite | **PASS - 166 case(s), 0 failure(s)** (163 at sprint start) |
| Mission 01 / Snack Time | SMOKE PASS / SMOKE PASS |
| Audio shipping smoke | SMOKE PASS |
| Settings real-input harness | INPUT SETTINGS OK |
| Classroom smoke vs LIVE dev Worker | SMOKE: PASS (11 turns, quota 86.7 s, mic closed) |
| Prototype backend | 126 pass |
| Cloudflare Worker (cloud/) | 151 passed, 10 files |
| Billing module | 36 pass |
| Website | 12 pass |
| Live health | `/healthz?db=1` 200, migrations 5 |

## 9. Builds and final status

**Final code commit `f510be8`**; the two commits after it are this report only.
Builds were made from `f510be8`.

| Build | Path | Size | Note |
|---|---|---|---|
| Android debug APK | `build/android/LittleDays-debug.apk` | 46,987,320 B | SHA-256 `33a446a15ca978a8f2bd22e78d2a633c3fbe69c3d8a4dde2f0aaa833a983bc35`, signed, **zero permissions**; contains the 3 new Meshy GLBs (+ textures), contains no `generated_v1` concept art |
| iOS export | `build/ios/LittleBuddy.xcodeproj`, `build/ios/LittleBuddy.pck` | pck 18,066,704 B | owner signs in Xcode |
| iOS arm64 compile | unsigned | `** BUILD SUCCEEDED **` |

| Status | Value |
|---|---|
| Cloudflare | dev API live and healthy (`/healthz?db=1` 200, 5 migrations); production NOT deployed; API hostname not attached to dev |
| OpenAI | no key on the Worker or the Mac; realtime token 503; cloud flag false; no call made |
| Billing | disabled on client (`purchases_enabled=false`) and server (`BILLING_ENABLED=false`, verify → 503); no store plugin, no charge path |
| Meshy | 3174 → 3144 (30 spent), 10 of 40 authorised unspent, 90 of 100 sprint total |
| Website | built and tested, NOT deployed (would overwrite the owner's `littledays-web`) |
| Physical device | NOT run; the owner's tonight build stays `bb2c3e7` |

## 10. Remaining blockers for production
1. Production deploy is manual: create `little-days-production` D1, apply 0001–0005, a new `PARENT_TOKEN_SECRET`, `deploy --dry-run --env production`, then deploy by hand (the route to `api.littledays.joinanny.com` is already in the config). Staging first is recommended.
2. Real parent sign-in: `APPLE_BUNDLE_ID`, `APPLE_SERVICE_ID`, `GOOGLE_CLIENT_IDS` per environment; the game and the portal must send identity tokens (they send nothing yet); the Worker needs a CORS allow-list for `https://littledays.joinanny.com` before the portal can talk to it.
3. Cloud tutor: privacy gates G1–G17, `OPENAI_API_KEY` as a Worker secret, the realtime path untested against any provider; the turns path is what runs today.
4. Billing: App Store Connect / Play Console products, secrets, reconciliation of `cloud/src/billing/schema.sql` with migration 0002 (`subject_id` vs `parent_id`), owner approval, device QA; the zero-turn session end charge (45 s) should be dropped server-side.
5. Meshy next batch needs fresh authorisation (bottle, blocks, fridge = 45 credits recommended first).
6. Android back key (`quit_on_go_back`) decision; support contact and developer legal name for the website.
