# Little Days website — design notes and claims policy

Owner: Agent W. Date: 2026-09-21. Code: `web/` (branch `wt7/web`).
Status: **built and tested locally; NOT DEPLOYED.** Runbook: `web/README.md`.

## What it is

Four static pages and a not-found page, served by a Cloudflare Worker with
static assets (`[assets] directory = "./public"`, no Worker script):

| Path | Page | Purpose |
| --- | --- | --- |
| `/` | Home | "Aliz, your child's playful learning companion". The game is free and offline; the AI Tutor is planned, needs internet and is off in the current build; Family Club is "coming later". |
| `/privacy` | Privacy | Only what the code guarantees today, future items marked *planned*, sources cited. |
| `/support` | Support | Contact block for the owner to fill in (`TODO(owner)`), plus the questions parents ask most. |
| `/parents` | Parent portal preview | Development shell: dev sign-in, children, consent switches, tutor minutes today, subscription "not available". |
| `/404.html` | Not found | Served by `not_found_handling = "404-page"`. |

Plain HTML/CSS/vanilla JS, mobile-first (16 px gutters, no horizontal
scroll, cards collapse to one column under 640 px), real heading order, alt
text on every image, every control at least 44 px, skip link, `aria-current`
on navigation, live regions for portal status. English first with a Thai
helper line under it (class `th`, `lang="th"`), the same pattern the game's
Thai hints use. No fonts, scripts or images from third parties.

## Branding

- Logo: `game/assets/branding/littleDaysLogo_512.png` copied to
  `web/public/assets/little-days-logo.png` (512×308, also the favicon).
- Colours: the seven locked tokens and the semantic roles from
  `game/scripts/ui/palette.gd` (source of truth `docs/ART_BIBLE.md` §3),
  copied as hex into CSS custom properties in `web/public/assets/site.css`:
  cream `#FFF6E5`, dustyBlue `#9AC0D9`, softPink `#FFC1CC`, mint `#A8E6CF`,
  peach `#FFD3B6`, lavender `#D6C7F0`, ink `#59422B`, inkSoft `#8A7358`,
  starEarned `#FFC73D`, starNext `#FFE199`, starGhost `#E8DCC8`. The light and
  deep derivations (45 % toward cream, 22 % toward ink) are precomputed for
  hover states. No black, no red, no grey, as the bible requires. Body text is
  `ink` on `cream` (about 9:1); `inkSoft` is used for helper text only.

## Claims policy: what the site says and where it comes from

Every statement on the Privacy page is traceable to a repository document
that cites files and tests:

- `docs/ALIZ_TUTOR_PRIVACY_REVIEW.md` §A1, §E: no network class under `game/`,
  on-device iOS recognition (`requiresOnDeviceRecognition = YES`), no audio or
  transcript stored, `cloud_enabled()` false in `project.godot` and presets.
- `docs/GOOGLE_PLAY_RELEASE_READINESS.md` §0, §3, §4: Android build has no
  `INTERNET` and no `RECORD_AUDIO` permission, no third-party SDKs, no ads, no
  purchases, what is stored locally.
- `docs/ALIZ_TUTOR_PARENT_INFO.md`: the in-app privacy text, reproduced word
  for word, including the guarded sentence "The online AI tutor is switched
  off in this build." (`web/test/site.test.mjs` fails if it changes.)

Claims deliberately **not** made anywhere on the site:

- No availability claim: no App Store or Google Play badge, no "download now";
  the Home page says "in testing, not yet listed in an app store"
  (`data-owner-status="release"`, for the owner to update).
- No prices. Family Club is "coming later"; the THB 99 hypothesis stays in
  `docs/FAMILY_CLUB.md` and the API's `priceHint`; the test suite rejects
  `THB`, `USD`, `$` amounts and "per month" on public pages.
- No "unlimited", no "guaranteed" (test-enforced), no "COPPA compliant" /
  "PDPA compliant" / "GDPR compliant" badges, no "certified", no "safe for
  kids" seal, no age rating.
- No "we never share your data" style absolute about the future cloud path;
  the page says what exists and marks the rest *planned*.
- No cookie banner and no cookie claim beyond the fact: the pages set none.
- No claim that Cloudflare logs nothing; only that Cloudflare delivers the
  page like any host.
- No support e-mail, phone or address: the owner supplies them.
- No developer legal name: the Privacy page points to Support for it.
- No AI Tutor feature description beyond "planned", and no statement about
  which model provider would be used.
- No claim that the portal shows real families: it carries a permanent
  "Development data" banner.

## Parent portal: contract and safety rails

- One constant, `API_BASE_URL` in `web/public/parents/config.js`, default
  `http://127.0.0.1:8787` (the same default as `TutorFlags.backend_url()`).
- `isLoopbackUrl()` refuses any host other than `127.0.0.1`, `localhost`,
  `::1` before `fetch`; the CSP `connect-src 'self' http://127.0.0.1:8787
  http://localhost:8787` blocks anything else in the browser. Production
  hostnames appear nowhere in `web/public/`.
- Calls, per `docs/ALIZ_TUTOR_API.md` §1.2 and `docs/CLOUD_BACKEND.md`:
  `POST /v1/parents {provider:"dev", subject}` (DEV_MODE only) →
  `Authorization: Bearer pt1.…` on `GET /v1/parents/me`, `GET|POST
  /v1/children`, `GET|PUT /v1/consent`, `GET /v1/tutor/quota?childId=`,
  `GET /v1/entitlements`. Consent `PUT` requires the bearer (`via: bearer`),
  which is what the portal sends.
- Sample-data mode (`createMockStore()` in `portal_lib.js`) mirrors those JSON
  shapes so the UI can be reviewed with no server; it is the default choice on
  the sign-in form.
- The dev token lives in `sessionStorage` (per tab) and is cleared on sign
  out or when the tab closes.
- Subscription card always reads "not available"; billing is off
  (`BILLING_ENABLED = "false"` in `cloud/wrangler.toml`).

### Ask for the cloud team (not fixed here: `web/` never edits `cloud/`)

`cloud/src/app.ts` emits no CORS headers and has no `OPTIONS` handler, and
`docs/CLOUD_BACKEND.md` records "CORS never emitted" as a control. A browser
on `http://127.0.0.1:8788` therefore cannot reach the dev API even with the
correct token. To exercise the live mode, the dev environment (only) needs:
`Access-Control-Allow-Origin: http://127.0.0.1:8788`,
`Access-Control-Allow-Headers: authorization, content-type`,
`Access-Control-Allow-Methods: GET, POST, PUT, DELETE`, and a `204` reply to
`OPTIONS`, gated on `DEV_MODE` so production keeps emitting nothing. The
prototype `backend/` already has a `CORS_ORIGINS` list (see
`docs/ALIZ_TUTOR_API.md` §2), so `CORS_ORIGINS=http://127.0.0.1:8788 DEV_MODE=1
node backend/src/server.js` may work today for the prototype routes the portal
uses (`/api/v1/...` prefix is also served by the Worker; the portal uses `/v1`).

## Deployment and hostnames (owner only)

- `web/wrangler.toml`: `name = "littledays-web"`, the owner's `account_id`,
  `workers_dev = false`, `[assets] directory = "./public"`, **no routes, no
  custom domain**.
- The owner already has a Worker called `littledays-web` serving
  `littledays.joinanny.com`; deploying this directory replaces its code, so
  the deploy is manual and preceded by `wrangler deploy --dry-run`. Exact
  commands: `web/README.md`.
- `api.littledays.joinanny.com` is the API Worker's hostname (`cloud/`). This
  site never claims it, never proxies to it and never calls it.

## Tests

`cd web && npm test` → 12 checks (Node 22 `node:test`, offline): document
structure (lang, viewport, title, single `h1`, alt text, landmarks, skip link);
every internal link, fragment, script, stylesheet and image resolves under the
Workers `auto-trailing-slash` rules; no third-party resources; no `TODO`
except the owner contact block (and no `mailto:` in live markup); no
"unlimited" / "guaranteed" / prices; the exact tutor sentence and the source
citations on the Privacy page; Home positioning and honesty markers; Thai
helpers follow English; `wrangler.toml` has no routes, domains, script or
`workers.dev`; CSP `connect-src` is loopback-only; the portal config default
and the loopback guard; the mock store's shapes, minute maths and the
subscription summary.

## Open items for the owner

1. Fill in the support contact block (`TODO(owner)` in
   `web/public/support/index.html`), then re-run `npm test`.
2. Decide the developer legal name for the Privacy page (currently deferred
   to Support).
3. Update the Home status line when the app is listed in a store.
4. Run the deploy by hand per `web/README.md`.
