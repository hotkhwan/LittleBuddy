# Little Days website (`web/`)

Static site for Little Days: Home, Privacy, Support and a development-only
parent-portal shell. Plain HTML, CSS and vanilla JavaScript; no framework, no
build step, no third-party resources. Design notes and the claims policy live
in `docs/WEBSITE.md`.

```
web/
  README.md            this file
  wrangler.toml        Cloudflare Worker with static assets (assets only, no script)
  package.json         `npm test` (node:test) and `npm run serve` (local preview)
  public/              everything that is served
    index.html         Home
    privacy/index.html Privacy
    support/index.html Support (owner fills in the contact block)
    parents/           Parent portal preview: index.html, config.js, portal.js, portal_lib.js
    assets/            site.css (palette from game/scripts/ui/palette.gd), little-days-logo.png
    _headers           CSP and security headers (also applied by the local server)
    404.html           not-found page
  test/site.test.mjs   link, wording, structure and portal-helper checks
  tools/serve.mjs      zero-dependency preview server on http://127.0.0.1:8788
```

## Run locally

Node 22 (`/usr/local/bin/node` on the MacBook).

```sh
cd web
npm test          # 12 checks, offline, about 100 ms
npm run serve     # http://127.0.0.1:8788/  (Ctrl-C to stop)
```

## The parent portal preview (`/parents`)

- Talks to **one** server, the constant `API_BASE_URL` in
  `public/parents/config.js`, default `http://127.0.0.1:8787`. `portal_lib.js`
  refuses any host that is not `127.0.0.1` / `localhost`, and the
  Content-Security-Policy in `public/_headers` blocks everything else a second
  time. There is no production value to put there.
- Sign-in is the development provider from `docs/ALIZ_TUTOR_API.md` 1.2:
  `POST /v1/parents {provider:"dev", subject}`; it works only against a server
  running with `DEV_MODE=1` (`cd cloud && npm run dev`). It then reads
  `/v1/children`, `/v1/consent`, `/v1/tutor/quota?childId=`, `/v1/entitlements`
  and writes `POST /v1/children`, `PUT /v1/consent`.
- "Sample data" mode uses an in-memory store with the same JSON shapes, so the
  page can be reviewed with no server at all.
- **Known limitation:** the cloud Worker emits no CORS headers
  (`cloud/src/app.ts` has no `Access-Control-*` handling and no `OPTIONS`
  route). A browser page on `http://127.0.0.1:8788` therefore cannot call
  `http://127.0.0.1:8787` until the cloud team allows that origin in dev. Until
  then use sample data. This repository's rule is that `web/` never edits
  `cloud/`, so the request is recorded in `docs/WEBSITE.md`, not fixed here.

## Deploying (owner only, by hand)

**Warning.** The owner's Cloudflare account already contains a Worker named
`littledays-web` (created 2026-09-21) that serves `littledays.joinanny.com`.
`wrangler.toml` here uses the **same name on purpose**, so that this site can
take over that Worker. Consequently `wrangler deploy` from this directory
**overwrites that Worker's current code**. Nobody but the owner runs it, and
only after reading the dry run. Agents never deploy this project.

`wrangler.toml` deliberately contains **no routes and no custom domain** and
sets `workers_dev = false`. The hostname stays attached to the Worker in the
dashboard (or the owner adds a route after the dry run). Never attach
`api.littledays.joinanny.com` to this Worker: that hostname belongs to the
separate API Worker deployed from `cloud/`.

```sh
cd web
npm test                                            # must be green
source ../tools/cf_keychain.sh                      # exports CLOUDFLARE_API_TOKEN / ACCOUNT_ID from the keychain (see cloud/README.md)
npx wrangler@4 whoami                               # confirm account 8d67bfb5b60f8e54544e4aac74a98cc9
npx wrangler@4 deploy --dry-run                     # read it: name littledays-web, assets only, no routes
npx wrangler@4 deploy                               # OVERWRITES the existing littledays-web Worker
```

Rollback: Workers keeps previous versions; `npx wrangler@4 versions list` and
`npx wrangler@4 rollback` restore the earlier deployment.

Before the site goes public the owner also fills in the support contact block
in `public/support/index.html` (search `TODO(owner)`); the test suite allows
that one TODO and nothing else.
