# Parent portal API (littledays.joinanny.com/parents)

The minimal server surface the parent website needs. Base URL per
environment (`cloud/wrangler.toml`): dev `https://<worker>.workers.dev`,
production `https://api.littledays.joinanny.com`. Every path is also served
under `/api/v1` for the game; the portal uses `/v1`.

Conventions: JSON in and out; errors are `{"error":{"code","message",...}}`
with the codes in `cloud/src/errors.ts` (`bad_request` 400, `not_approved`
403, `not_found` 404, `conflict` 409, `not_implemented` 501,
`provider_unavailable` 503, `rate_limited` 429). The examples below use the
`dev` provider, which exists only where `DEV_MODE=1` (the dev Worker); the
portal itself uses `apple` / `google`. No cookies: the portal keeps the
`parentToken` in memory / session storage and sends it as a bearer. The
Worker emits no CORS headers today; the portal is served from a different
origin than the API, so the site agent should either proxy `/v1/*` through
the site's own host or ask the cloud lead to add an allow-list for
`https://littledays.joinanny.com` before going live.

Data rules the pages must respect (docs/ALIZ_TUTOR_PRIVACY_REVIEW.md): child
profiles are nickname + avatar + optional birth-year bucket, never a legal
name or birth date; no e-mail is stored or shown (only "an e-mail hash is
on file"); no purchase prompts on child-facing pages; the price shown comes
from the API `priceHint`, never from page copy.

## Flow

```
sign-in  ->  me  ->  children  ->  consent  ->  subscription  ->  export / delete
POST /v1/parents  GET /v1/parents/me  GET/POST/PATCH/DELETE /v1/children[/:id]
                                      GET/PUT /v1/consent   GET /v1/parents/me/subscription
                                      GET /v1/parents/me/export   DELETE /v1/parents/me
```

## 1. Sign in: `POST /v1/parents` (no credential)

Request (Apple, web flow with the Services ID):

```json
{ "provider": "apple", "identityToken": "<id_token from Sign in with Apple JS>", "nonce": "<the nonce the page generated>" }
```

Request (Google, web):

```json
{ "provider": "google", "identityToken": "<credential from Google Identity Services>" }
```

Request (dev Worker only):

```json
{ "provider": "dev", "subject": "portal-qa-1" }
```

Response `201`:

```json
{
  "parentId": "0dab0e60-6c1e-4d5c-9b2a-3f4e5d6c7b8a",
  "provider": "dev",
  "created": true,
  "parentToken": "pt1.eyJwaWQiOi...",
  "expiresAt": "2027-02-09T10:00:00.000Z",
  "emailVerified": false,
  "devMode": true
}
```

`created` is `false` on every later sign-in of the same store identity (same
`parentId`). Add `"clientId": "<the app's clientId>"` to also receive a
`parentApprovalToken` for that device (the parental gate); the portal does
not need it. Errors: `403 not_approved` with `reason` (`wrong_audience`,
`expired`, `wrong_issuer`, `unknown_key`, `bad_signature`, `wrong_nonce`) for
a token that does not verify, `400` for a malformed one, `501` when the
provider is not configured on that environment, `409 conflict` with
`{"reason":"account_deleted","availableAt":"..."}` when this identity deleted
its account less than 30 days ago (show "This account was deleted. A new one
can be created after <availableAt>.").

All routes below: `Authorization: Bearer <parentToken>`.

## 2. Me: `GET /v1/parents/me`

```json
{
  "parentId": "0dab0e60-...",
  "provider": "dev",
  "consentVersion": 1,
  "requiredConsentVersion": 1,
  "hasEmailHash": false,
  "createdAt": "2027-01-10T10:00:00.000Z",
  "via": "bearer",
  "childCount": 2,
  "maxChildren": 6,
  "tutorEntitlement": "free"
}
```

`403 not_approved` means the token expired or the account was deleted: go
back to sign-in.

## 3. Children

`GET /v1/children` -> `{ "children": [ ...child ] }`; `GET /v1/children/:id`
-> one child. A child is:

```json
{ "childId": "4eb51f20-...", "nickname": "Pip", "avatarId": "bear_01", "birthYearBucket": "2020-2021", "locale": "en-US", "createdAt": "2027-01-10T10:01:00.000Z" }
```

`POST /v1/children` (max 6 per family, `400` beyond):

```json
{ "nickname": "Pip", "avatarId": "bear_01", "birthYearBucket": "2020-2021", "locale": "th-TH" }
```

Rules: `nickname` 1-24 letters / digits / spaces, no `@`, no URLs
(`400`); `avatarId` one of the bundled ids; `birthYearBucket` `YYYY-YYYY`
or omitted; `locale` like `en-US`. The page should label the field
"nickname" and say "not your child's real name".

`PATCH /v1/children/:id` takes any subset of the same fields
(`"birthYearBucket": null` clears it) and returns the child.

`DELETE /v1/children/:id` -> `200`:

```json
{ "deleted": true, "childId": "4eb51f20-...", "counts": { "sessions": 3, "usageEvents": 12, "idempotency": 12, "progress": 4, "dailyQuota": 2 } }
```

Removes the profile, its progress, tutor session records and daily counters.
`404` for another family's child.

## 4. Consent: `GET /v1/consent`, `PUT /v1/consent`

`PUT` body: `{ "kind": "ai_tutor", "granted": true, "version": 1 }` with
`kind` in `privacy` | `ai_tutor` | `voice` (`version` defaults to the
server's required version). Both answer:

```json
{
  "parentId": "0dab0e60-...",
  "requiredVersion": 1,
  "consent": {
    "privacy":  { "version": 1, "grantedAt": "2027-01-10T10:02:00.000Z", "revokedAt": null, "granted": true },
    "ai_tutor": { "version": 1, "grantedAt": "2027-01-10T10:02:01.000Z", "revokedAt": null, "granted": true },
    "voice":    { "version": 0, "grantedAt": null, "revokedAt": null, "granted": false }
  }
}
```

`granted` is computed (granted, not revoked, version >= required); when the
required version rises the page must show the new text and ask again.
Revoking `ai_tutor` ends live tutor sessions.

## 5. Subscription (read-only): `GET /v1/parents/me/subscription`

```json
{
  "parentId": "0dab0e60-...",
  "entitlement": "family_club",
  "status": "active",
  "activeUntil": "2027-02-09T10:00:00.000Z",
  "managedBy": "apple",
  "productId": "little_days.family_club.monthly",
  "billing": { "enabled": false },
  "priceHint": { "currency": "THB", "monthly": 99, "status": "proposed" },
  "records": [ { "productId": "little_days.family_club.monthly", "source": "apple", "status": "active", "periodEnd": "2027-02-09T10:00:00.000Z", "updatedAt": "..." } ]
}
```

`status` is `none` (never subscribed), `active`, `grace`, or `inactive`
(rows exist but none in force). The portal never changes a subscription:
`managedBy` says which store's subscription settings to link to (Apple:
`https://apps.apple.com/account/subscriptions`, Google: Play subscriptions).
Show the price only from `priceHint`, and only while `billing.enabled` is
true or `priceHint.status` is `approved`.

## 6. Export: `GET /v1/parents/me/export`

`200`, `Content-Disposition: attachment; filename="little-days-family-export.json"`:

```json
{
  "format": "little-days-family-export/1",
  "exportedAt": "2027-01-10T10:05:00.000Z",
  "notes": ["Ids and numbers only. ..."],
  "parent": { "parentId": "0dab0e60-...", "provider": "dev", "consentVersion": 1, "hasEmailHash": false, "createdAt": "...", "updatedAt": "..." },
  "children": [
    {
      "childId": "4eb51f20-...", "nickname": "Pip", "avatarId": "bear_01", "birthYearBucket": "2020-2021", "locale": "en-US", "createdAt": "...", "updatedAt": "...",
      "progress": [ { "lessonId": "colors_red_blue", "stepIndex": 3, "completedAt": null, "stars": 2, "updatedAt": "..." } ],
      "tutorSessions": [ { "sessionId": "fd92a937-...", "deviceId": "ipad-demo", "lessonId": "colors_red_blue", "mode": "turns", "startedAt": "...", "endedAt": null, "reason": null, "secondsUsed": 12.5, "turnCount": 1 } ],
      "dailyQuota": [ { "day": "2027-01-10", "secondsUsed": 12.5, "turnsUsed": 1, "allowanceSeconds": 300 } ]
    }
  ],
  "devices": [ { "deviceId": "ipad-demo", "platform": "ios", "appVersion": "1.0.0", "createdAt": "...", "lastSeenAt": "..." } ],
  "consent": { "privacy": { "...": "as in section 4" } },
  "entitlements": [ { "productId": "little_days.family_club.monthly", "source": "dev", "status": "active", "revokedReason": null, "periodEnd": "...", "updatedAt": "..." } ],
  "purchaseEvents": [ { "store": "dev", "transactionId": "txn-1", "productId": "little_days.family_club.monthly", "status": "applied", "processedAt": "..." } ]
}
```

Offer it as a download button ("Download my family's data"). There is
nothing else to export: the service keeps no transcripts, audio, e-mail or
names.

## 7. Delete account: `DELETE /v1/parents/me`

`200`:

```json
{
  "deleted": true,
  "parentId": "0dab0e60-...",
  "deletedAt": "2027-01-10T10:06:00.000Z",
  "tombstoneUntil": "2027-02-09T10:06:00.000Z",
  "counts": { "children": 2, "devices": 1, "consent": 3, "sessions": 3, "usageEvents": 12, "idempotency": 12, "progress": 4, "dailyQuota": 2, "entitlementsRevoked": 1, "purchaseEventsUnlinked": 1 }
}
```

The page should confirm twice (type the word "delete"), then explain: all
child profiles, learning progress, devices and consents are deleted now;
the `parentToken` stops working immediately; an active store subscription
is NOT cancelled by this (link to `managedBy`'s subscription settings);
the same Apple / Google identity can create a new, empty account after
`tombstoneUntil`. Deletion is not reversible.

## Not for the portal

`POST /v1/parents/approval`, `POST/GET /v1/devices`, `/v1/progress`,
`/v1/tutor/*`, `/v1/billing/*` and `/v1/dev/*` serve the game and the
stores. `PUT /v1/consent`, export, `PATCH`/`DELETE` children and account
deletion accept the parent bearer only; a device's approval token gets
`403`.

## Local check (dev Worker)

```sh
PT=$(curl -s -X POST $API/v1/parents -H 'content-type: application/json' -d '{"provider":"dev","subject":"portal-qa-1"}' | jq -r .parentToken)
curl -s $API/v1/parents/me -H "authorization: Bearer $PT"
curl -s -X POST $API/v1/children -H "authorization: Bearer $PT" -H 'content-type: application/json' -d '{"nickname":"Pip","avatarId":"bear_01"}'
curl -s -X PUT $API/v1/consent -H "authorization: Bearer $PT" -H 'content-type: application/json' -d '{"kind":"ai_tutor","granted":true}'
curl -s $API/v1/parents/me/subscription -H "authorization: Bearer $PT"
curl -s $API/v1/parents/me/export -H "authorization: Bearer $PT" -o family.json
curl -s -X DELETE $API/v1/parents/me -H "authorization: Bearer $PT"
```

Tests covering this contract: `cloud/test/accounts_privacy.test.ts`,
`cloud/test/identity.test.ts`, `cloud/test/accounts.test.ts`.
