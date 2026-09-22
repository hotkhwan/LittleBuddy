# Google Play Data safety inventory — Android RC

Status: **evidence draft for Internal/Closed testing; owner/legal approval required**  
Scope: committed Android RC configuration as of 22 September 2026. It distinguishes data handled only on the device from dormant cloud capabilities present in the repository.

## How to use this document

Play Console answers must describe the exact uploaded AAB and active production services. For this RC, cloud tutor and billing are disabled and Android microphone permission is false. Data that never leaves the device is documented below but generally is not “collected” under Google Play's Data safety definition. Confirm that interpretation against the current Play form and counsel when submitting.

Do not reuse the RC answers for a future build that enables accounts, cloud tutoring, realtime voice, billing, analytics or Android speech.

## RC data inventory

| Data type | Collected by developer? | Transmitted off device? | Stored | Encryption | Required / optional | Purpose | Retention | Deletion path / evidence |
|---|---:|---:|---|---|---|---|---|---|
| Account data | No active RC flow | No | None by Android app | N/A | Not required | No account is needed for local play | N/A | No RC account exists. Dormant cloud account capability is described below. |
| Child profile | No cloud collection | No | Local `user://profile.json`: progress/settings, not name/email/birth date | Platform app sandbox; save is plain JSON, not app-level encrypted | Required for save continuity; reset is optional | Game progress, unlocks and preferences | Until reset or app data/uninstall deletion | Parent Corner **Reset progress** replaces the profile with defaults; clearing app data/uninstall removes app-local data. `profile_store.gd`, `save_service.gd`. |
| Microphone/audio | No on Android RC | No | No microphone recording | N/A | Not requested; touch is available | None on Android RC; playback/TTS audio is not microphone data | N/A | `permissions/record_audio=false`; no Android speech backend. Re-audit if enabled. |
| Speech transcripts | No on Android RC | No | No transcript field in local profile | N/A | Not used | None | N/A | Speech unavailable on Android RC. Cloud turn code accepts transcript text only behind the disabled cloud flag; see dormant capability below. |
| Learning/progress data | No developer collection | No | Local profile: stars, completed activities, chapter/level/room IDs, per-level results, unlocks, settings, tutor progress/quota and optional vocabulary-review history | Platform app sandbox; no app-level encryption | Required for saved progress; tutor/history features optional | App functionality and personalization on that device | Until reset/app deletion; learning-history subset until parent deletes it | Parent Corner can delete tutor learning history (`tutorProgress`, `tutorQuota`) separately; Reset progress clears the profile. |
| Diagnostics | No diagnostic/analytics SDK found | No | Normal platform/runtime logs may exist outside app-defined persistence; app defines no diagnostic upload | Platform-controlled | Not required | Local debugging/runtime operation only | Platform-controlled; not represented as a Little Days server dataset | No in-app diagnostic account dataset found. Verify final AAB has no crash-reporting dependency. |
| Purchases/payment data | No; purchases disabled | No | No active store receipt or server entitlement from RC | N/A | Not available | None | N/A | `billing/purchases_enabled=false`; no purchase UI/transport intended. |
| School license | No active Android flow found | No | No local school-license record identified in game save | N/A | Not available | None | N/A | Cloud licensing exists as production-platform code but is not wired as an RC game feature. Re-audit before enabling. |
| Device installation ID | No active RC cloud use | No | No hardware identifier found; dormant network clients accept a pseudonymous `clientId` | If later transmitted, HTTPS transport is required; no active RC value | Not required for local play | Would bind a parent-approved cloud device/session | No active RC retention | No `ANDROID_ID`, ad ID, serial, IMEI or `OS.get_unique_id()` use found. Confirm runtime/package behavior in final AAB. |
| App settings | No developer collection | No | Local profile: locale, hints, audio/voice settings, session reminder and tutor toggles | Platform app sandbox; no app-level encryption | Optional | User preferences and accessibility/learning presentation | Until reset/app deletion | Reset progress/app data deletion. |

### Local profile contents confirmed in code

The canonical save includes `profileVersion`, stars, completed activity IDs, current chapter/level/room/spawn, per-level stars/completion, unlocked chapters/levels/rooms, and settings. Sanitized optional data can include vocabulary progress and tutor-related settings. It does not define account credentials, email, exact date of birth, advertising ID, location, audio, photo or transcript fields. Unknown JSON-safe settings are preserved, so every future setting added to the app must be reviewed before release.

## Dormant cloud/server capability — not active in this RC

These repository capabilities are excluded from the RC Play answers only because the committed client gates prevent their use. They are listed to avoid unsupported “never collected” claims and to define the re-review boundary.

| Capability/data | Potential transmission and storage | Protection/purpose | Retention and deletion |
|---|---|---|---|
| Parent account identity | Apple/Google identity token would be sent to Little Days. Server stores provider plus HMAC-hashed provider subject and optional HMAC-hashed lowercase email, not raw values. | HTTPS in transit; Cloudflare D1 at rest controls are provider-managed. Authentication, parent consent and family management. | Until account deletion. Deletion clears email hash and creates a 30-day anti-recreation tombstone; after that, eligible tombstones are deleted or subject hashes anonymized. `0001_accounts.sql`, `0005_account_privacy.sql`, account routes. |
| Child cloud profile | Nickname, bundled avatar ID, optional coarse birth-year bucket, locale and parent link. Code warns nickname is not a real name but cannot technically prove what a parent enters. | Family profile and lesson association; HTTPS in transit, provider-managed D1 at rest. | Until child/account deletion; cascade deletes linked progress/session/quota data. Parent API supports deleting one child. |
| Consent | Consent kind/version and grant/revoke timestamps. | Legal/privacy control for AI tutor and voice. | Until account deletion. |
| Pseudonymous installation ID | App-created `clientId`, platform, app version, created and last-seen times; no model, OS build, push token or hardware ID in schema. | Device approval, session binding and abuse/security controls. | Until account deletion; device-history endpoint can delete learning history associated with a client. |
| Text tutor input | Cloud turns can send transcript text (capped in client), lesson context and optional audio-duration number to Little Days; provider adapters may transmit text to the configured AI provider. | Deliver cloud tutoring after parent approval/consent. No cloud tutor in RC. | Schema intentionally has no transcript column. Idempotency stores a keyed request hash and validated response, not raw child input; idempotency retention is 24 hours. Provider-side retention/contracts remain **unverified owner due diligence** before enabling. |
| Realtime child audio | Realtime transport can send PCM/audio to a configured provider using an ephemeral token after AI and voice consent. | Live tutoring. Explicitly disabled for public/RC use. | D1 usage rows store audio seconds, not audio. Provider handling/retention is **unverified** and must be contractually approved before enablement. No child audio may be persisted by Little Days. |
| Tutor operational data | Session/child/device/lesson/provider IDs, timestamps, end reason, seconds, turns, daily quota; usage event token/audio-duration/cost counts. Learning progress stores lesson ID, step, completion time and stars. | Quota, functionality, fraud/security, cost control and progress sync. | Tutor sessions, daily quota and usage events: configured retention, documented default 30 days; idempotency: 24 hours. Learning progress lasts for child profile. Child/account deletion cascades; device-history deletion is exposed. Confirm the production scheduled purge is enabled before activating. |
| AI response data | Validated tutor response JSON may be stored in idempotency rows; it is provider output, not the raw child transcript, but may reflect lesson context. | Reliable retries and child-safe response delivery. | 24-hour idempotency retention. Confirm scheduled purge. |
| Purchase/subscription data | Store, transaction/notification ID, product, parent link, status, payload hash, opaque receipt reference or token hash, entitlement dates. Raw receipt payload is not intended to be stored. | Server-side entitlement verification, refund/tax/audit and fraud control. | Entitlement/audit records may outlive account deletion: entitlement is revoked for `account_deleted`, purchase event loses parent link, and retained account identifier is anonymized after tombstone period. Exact legal retention duration is not specified in code and requires owner/legal policy. Billing is disabled in RC. |
| School license data | Cloud licensing schema/service exists and may process organization/license, seats/devices and pool/concurrency identifiers. | Institutional entitlement management. Not wired as an Android RC feature. | A complete field-level retention/deletion policy was not established by this RC audit; must be completed before enabling. |

## Security and disclosure notes

- “Encrypted in transit” can be claimed for an enabled production flow only after confirming every endpoint is HTTPS and no developer command-line override can enter the distributed artifact. The committed cloud URL is empty; the development fallback is loopback HTTP but the RC cloud gate is off.
- Local save data is protected by Android's application sandbox and backup is disabled in the export preset, but the JSON file is not encrypted by application code. Do not claim app-level encryption at rest.
- Cloud database/provider encryption at rest should be confirmed from the production service terms and configuration before making a console claim.
- The app has no advertising/analytics SDK in source, but the final AAB must be scanned because export templates can add dependencies or permissions.
- No raw microphone audio or transcript persistence was found in the local save or cloud D1 schema. That does not by itself establish an AI provider's retention behavior; realtime remains disabled pending provider/legal review.

## Proposed Play Console answers for this exact RC

Subject to final AAB inspection and owner/legal confirmation:

1. Data collected: **No developer collection from the Android app**, because only local app data is used and all cloud/account/billing paths are disabled.
2. Data shared: **No**.
3. Security practices: core app works without account; users can request deletion only if a later account feature exists. For this RC, local deletion is Reset progress, clear app data or uninstall.
4. Ads/advertising ID: **No ads; no advertising ID use**.

Do not submit those answers if runtime testing observes any request to Little Days, Google APIs beyond ordinary Play delivery, or another provider. In that case, revise the form from captured network evidence before upload.

## Owner and release actions

- Approve the public privacy URL and ensure its Android statements match this AAB.
- Capture a clean-install network trace on a physical Android device through every shipped screen; expected result is no app-originated network request.
- Inspect the merged manifest/AAB and dependency inventory.
- Verify Reset progress, tutor-history deletion, clear-data and uninstall behavior.
- Decide and document whether platform backups are disabled in the final manifest as configured.
- Establish contact and request procedures for privacy questions even though the RC has no cloud account.
- Before any cloud release: approve processors and DPAs, provider retention/training terms, production HTTPS/CORS/auth, scheduled deletion jobs, account/child deletion, export, consent copy and a revised Play Data safety form.
