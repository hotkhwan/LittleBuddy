# Google Families compliance audit — Android RC

Status: **conditional release candidate; not approved for public publication**  
Audit basis: repository source and committed Android export configuration, 22 September 2026. Physical-device and final merged-AAB inspection are separate release gates.

## Release posture

The Android RC is a child-directed, offline-first game. Its shipped path uses bundled lessons, local saves, local audio and touch input. In `game/project.godot`, `little_days/ai_tutor/cloud_enabled=false`, `little_days/ai_tutor/backend_url=""`, and `little_days/billing/purchases_enabled=false`. In `game/export_presets.cfg`, Android `permissions/record_audio=false`. These settings must remain unchanged for this RC.

This audit does not treat dormant repository code as an active Android data flow. Cloud account, tutor, realtime-AI and billing implementations exist, but the committed Android client flags prevent their activation. Any later build that enables one of those paths requires a new Families, Data safety, consent, permission and SDK review before upload.

## SDK and integration inventory

| Area | RC finding | Evidence and Families consequence |
|---|---|---|
| Game engine | Godot 4.x; no app-level third-party mobile SDK found | `game/project.godot` and the GDScript tree. Final AAB dependency/manifest inspection must confirm the exported engine template adds no undeclared SDK. |
| Advertising | No advertising SDK or ad code found; no ads | No AdMob/advertising integration found; Android custom permissions are empty. Declare **No ads**. Final merged manifest must contain no `com.google.android.gms.permission.AD_ID`. |
| Analytics, attribution, crash reporting | None found in the Android game | No Firebase Analytics, Segment, Amplitude, Adjust, AppsFlyer, Facebook SDK or Sentry client integration found. Do not add Play/Firebase analytics without a new child-directed review. |
| Authentication | No sign-in reachable in this RC | Cloud supports Apple/Google parent identity in `cloud/src/routes/accounts.ts`, but the Android game has no active account flow with cloud disabled. Do not describe cloud parent accounts as an RC feature. |
| Cloud API | Disabled | Network-capable GDScript is isolated under tutor/store code. `TutorFlags.cloud_enabled()` gates creation of `HTTPRequest`; committed URL is empty and cloud flag false. Offline gameplay remains the release behavior. |
| AI providers | Disabled | Server code can use mock/OpenAI/Gemini-style providers and realtime transport, but the Android RC cannot activate the cloud tutor. Local scripted lessons and device/bundled voice remain available. |
| Speech/microphone | Disabled on Android RC | Android export sets `permissions/record_audio=false`; speech service reports unavailable without a native backend, and activities retain touch input. No Android speech SDK/plugin was found. |
| Billing | Disabled; no purchase UI should ship | `little_days/billing/purchases_enabled=false`; store verification has no configured transport. Server billing code and product proposals are dormant. Subscriptions are a later release item. |
| Device identifiers | No hardware/ad identifier use found | Dormant cloud design accepts an app-created pseudonymous `clientId`; no `ANDROID_ID`, ad ID, serial, IMEI or Godot unique-device-ID access was found. The RC must not create/transmit a cloud installation ID while cloud is disabled. |
| External links | No child-facing outbound link behavior found | Parent settings describes an external reference as copy-only and says it does not open in the app. Privacy/support URLs belong in the Play listing, not child screens. |
| Affiliate links | None found | No affiliate integration or commercial link found. |
| WebViews | None found | No WebView integration found in game code. Repository `web/` pages are a separate static site, not an embedded child UI. |

The Cloudflare Worker uses Hono and built-in Cloudflare services; the separate prototype backend has provider adapters. Neither is a mobile SDK embedded in the Android RC. Their existence still matters for future reviews because enabling cloud tutor would transmit data to Little Days infrastructure and potentially an AI provider.

## Child-facing and parent-only controls

- Core play, local lessons and local progress do not require an account, network, purchase or microphone.
- Speech failure never blocks touch gameplay. Android has no microphone permission in this RC.
- Parent settings are protected by a press-and-hold parent gate. Tests cover the gate card, back behavior and reopening.
- Commerce implementation refuses purchase/restore unless explicitly told the parent gate is open, and committed purchases are disabled. No purchase button, pricing sheet or restore control is intended to ship in this RC.
- Commercial calls to action, prices, subscriptions, affiliate links and outbound store/web links must not appear in child-facing scenes. A final visual walkthrough of the built AAB remains required.
- Back navigation must close an overlay or return one logical level and must never expose parent controls without completing the gate. Physical Android verification remains required.

## Families-policy declarations for this RC

Recommended Play Console posture, subject to owner/legal approval:

- Target audience: the actual intended young-child age bands selected by the owner; do not include older bands merely to broaden discovery.
- Child-directed: **Yes**.
- Ads: **No**.
- In-app purchases: **No for this RC**; subscriptions remain disabled and unconfigured.
- Location: not collected or requested.
- Microphone: not requested on Android and no Android voice feature is enabled.
- Social interaction, user-generated content, open chat and external browsing: none.
- Core functionality must be fully usable offline.

## Release gates and uncertainties

The following must be completed before the AAB is uploaded to Internal or Closed testing:

1. Inspect the **merged manifest and final AAB**, not only `export_presets.cfg`, and record every permission. Confirm no AD_ID, microphone, location, contacts, phone/SMS, package-query or advertising permission was introduced by the export template.
2. Inspect packaged native libraries/dependencies to confirm no undeclared SDK was added by the Godot Android template.
3. Run the child-facing UI on a physical Android device and confirm no commerce, raw infrastructure error, external link, parent portal, cloud tutor or microphone affordance is reachable.
4. Verify the parent gate cannot be bypassed with Android Back, process restart, rotation, background/foreground or deep-link/activity restoration.
5. Verify offline play from first launch, after process death, and after a failed network transition.
6. Have the owner/legal reviewer approve the target ages, privacy policy and Play declarations. This source audit is not legal certification.

Any change enabling cloud tutor, realtime audio, parent accounts, billing, analytics, advertising, notifications or a new SDK invalidates this audit and requires a fresh review.
