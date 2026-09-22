# Google Play release-candidate checklist

Scope: Internal or Closed testing only. Do not promote this build to Open testing or Production. A checkbox means evidence must be attached to the release record; it is not satisfied merely because this document exists.

## Release gate

- [ ] Release AAB is signed with the owner's upload key, never the Android debug key.
- [ ] Record package ID, `versionName`, monotonic `versionCode`, target SDK, AAB SHA-256, merged-manifest permissions, signer certificate SHA-256, source commit, and build time.
- [ ] Confirm the release artifact is non-debuggable and contains no test endpoints, secrets, rejected/concept art, or unapproved SDKs.
- [ ] Run the full Godot suite in an environment with writable `user://`. Current 2026-09-22 run: 175 cases; the initially observed 14 failures were one expired dated cloud fixture, corrected by pinning the fixture clock; focused fixture and Android-platform reruns pass. The managed sandbox blocks new files under macOS Application Support, so its post-integration full rerun produces cascading save-test failures and is not a green canonical run.
- [ ] Install the Play-delivered split APK on a real Android phone and tablet. Physical-device status is **not tested**.
- [ ] Verify Back, background/foreground, lock/unlock, process death/restart, rotation lock, audio focus, offline startup, and unavailable API on both devices.

## Create App

1. In Play Console, select **All apps → Create app**.
2. Enter **Little Days**, default language, **Game**, and Free/Paid = **Free**.
3. Accept the declarations only after the owner confirms authority and policies.
4. Use the existing production package ID from the signed AAB. Package IDs cannot be changed after the first uploaded artifact; do not create a replacement ID casually.

## App content

### App access

1. Open **Policy and programs → App content → App access**.
2. Select that all child gameplay is available without special access if that remains true in the artifact.
3. If reviewer access to a parent-only or account area is required, provide durable review instructions and credentials in the private Play field, never in the store description.

### Ads declaration

1. Open **App content → Ads**.
2. Select **No, my app does not contain ads** only after the final dependency and merged-manifest scan confirms no advertising SDK or ad surface.

### Target audience and Families

1. Open **App content → Target audience and content**.
2. Proposed bands: **Ages 5 and under** and **Ages 6–8**, matching the preschool/early-primary design. Owner must confirm the intended audience.
3. Answer that the app appeals to children and complete the Families declaration.
4. Reconcile every response with `GOOGLE_FAMILIES_COMPLIANCE.md` and the final artifact; do not rely on a source-only audit.

### Content rating

1. Open **App content → Content rating → Start questionnaire** and choose **Game**.
2. Answer from shipped content: no violence, sexual content, profanity, drugs, gambling, user-generated content, chat, or location sharing, subject to a final human content review.
3. Treat any commerce or unrestricted-web question according to the exact RC behavior, including parent-gated surfaces.
4. Save the IARC certificate and investigate any rating above the lowest child-appropriate tier before rollout.

### Data safety

1. Open **App content → Data safety**.
2. Complete it from `GOOGLE_DATA_SAFETY.md` and final AAB behavior, not marketing intent.
3. Recheck account, child profile, audio, transcript, diagnostics, purchases, school-license, and installation-ID rows.
4. Confirm collection, sharing, optionality, purpose, encryption in transit, retention, and deletion answers with the privacy policy.
5. If Android microphone or cloud features are enabled later, reassess before uploading that build.

### Privacy policy

1. Publish the reviewed policy over HTTPS with no login requirement.
2. Candidate route found in the website source: `/privacy`. Proposed production URL: `https://littledays.joinanny.com/privacy`; **owner must deploy and verify the exact live URL before entry**.
3. Ensure the page names the responsible legal entity, child-directed practices, local and transmitted data, providers, retention/deletion, and owner contact.
4. Enter the verified URL in App content and the store listing.

## Store listing handoff

Proposed category: **Games → Educational**. Confirm the Play taxonomy available to the account.

Short description (75 characters):

> Care for Baby and learn everyday English through gentle play and listening.

Full description draft:

> Little Days is a gentle English-learning game for young children. Children care for Baby through familiar daily routines, explore rooms, listen to simple English, and learn by touching and playing at their own pace.
>
> Play feeding, bath, bedtime, tidy-up, dress-up, free-play, and classroom activities. Friendly prompts encourage children without timers, scores for pronunciation, or failure pressure. Core activities and local lessons continue to work offline.
>
> Parent settings and any grown-up information stay behind a parent gate. Little Days contains no ads. Features available in a testing build may vary while the app is in closed testing.

Do not add claims about speech, privacy, purchases, age certification, or complete offline operation unless the exact uploaded artifact and policy documents support them.

Support candidate: website source includes `/support`, but its contact block is marked `TODO(owner)`. Proposed URL `https://littledays.joinanny.com/support` is **not release-ready until the owner supplies contact details and verifies the live page**.

Assets:

- [ ] 512×512 Play icon, PNG, visually identical to the production launcher icon; check safe zone and legibility at small size.
- [ ] 1024×500 feature graphic, JPEG or 24-bit PNG without alpha; title/character inside safe areas; no store badges, pricing, rankings, or unsupported claims.
- [ ] At least two phone screenshots, and preferably four; use real Android captures from the uploaded build.
- [ ] At least four 7-inch and four 10-inch tablet captures if those form factors are supported.
- [ ] Capture Splash, Main Menu, Baby Room/free play, one care activity, Dress Up, and Classroom where representative. Exclude debug overlays, raw errors, personal data, editor chrome, and fabricated device frames.
- [ ] Keep screenshot ordering coherent: premise → play → learning → variety → parent reassurance.
- [ ] Confirm the store icon and feature graphic are production-approved, not files labeled concept/non-canonical.

## Internal testing

1. Open **Testing → Internal testing → Create new release**.
2. Enable Play App Signing and review which certificate is the app-signing key versus the local upload key.
3. Upload the signed release AAB and resolve every Play warning before rollout.
4. Add release notes identifying this as a private Android RC.
5. Create an email list or Google Group (up to the console's current internal-test limit), save, review, and **Start rollout to Internal testing** only.
6. Copy the tester opt-in link from the Testers tab. Testers must join with the invited Google account, accept, install from Play, and report the delivered version/build.
7. Record Play pre-launch report results. Automated reports do not replace child/family policy review or real-device QA.

### Play diagnostic files

- Deobfuscation mapping is required only when R8/ProGuard minification was
  enabled and generated a real `mapping.txt`. This release has minification and
  resource shrinking disabled, so no mapping exists and the Play warning is
  safe to ignore. Do not upload a placeholder. For a future minified build,
  select that exact version in **App Bundle Explorer → Downloads/Assets** and
  upload `build/android/release-metadata/mapping.txt` as the deobfuscation file.
- Native debug symbols improve native crash/ANR stack traces. This release uses
  stripped official Godot template libraries, so no valid symbols can be
  produced retroactively and the current warning is safe to leave unresolved.
  For a future custom symbol-bearing Godot template, confirm Build IDs match
  the shipped libraries, then upload
  `build/android/release-metadata/native-debug-symbols.zip` under that exact
  version's **App Bundle Explorer → Downloads/Assets → Native debug symbols**.
- Confirm `release-metadata/version.txt`, `sha256.txt`, and
  `signing-cert.txt` match the AAB before any optional diagnostic upload.

## Closed testing

1. After the internal device gate passes, open **Testing → Closed testing → Create track**.
2. Add managed tester lists/groups, upload the same or a newer monotonic build, add release notes, review, and start the Closed rollout.
3. Share only the track's opt-in URL. Record opt-in count, countries, start/end dates, devices, crashes/ANRs, and feedback.
4. If this is a new personal developer account subject to Google's production-access rule, confirm the currently displayed tester-count and continuous-duration requirement in that Play account and preserve evidence. Do not assume an old threshold.
5. Do not promote to Open or Production during this sprint.

## Subscriptions later — not this RC

- Leave Billing disabled and do not add Play Billing solely to prepare this test.
- Later, create subscriptions/base plans/offers in Play Console only after product IDs, entitlement behavior, price/localization, acknowledgement, restore, RTDN/service-account setup, parent gating, policy, and device tests are approved.
- A subscription must not be made available to children outside the parent gate. Re-run SDK, permission, Data safety, Families, and purchase-flow audits before enabling it.

## Required physical-device evidence

- Back closes the top overlay, returns one logical level, never bypasses the parent gate, and does not accidentally exit from gameplay.
- Parent Gate, Settings, Classroom, mini-games, Dress Up, and every room are tested for enter/play/wrong input/complete/replay/back/exit/re-enter.
- Background/foreground and screen lock stop microphone/session work appropriately; resume is safe and understandable.
- Force-stop/process eviction restores valid local progress without corrupting the profile.
- Offline, captive/slow network, API failure, and provider failure never expose raw infrastructure errors; local play remains usable.
- Landscape layout, touch targets, TTS/audio, thermal behavior, and performance pass on the oldest supported device.

## Android Back implementation

The RC now sets `application/config/quit_on_go_back=false`. A small application service translates `NOTIFICATION_WM_GO_BACK_REQUEST` into the shared `ui_cancel` path. Main Menu consumes Back (closing its picker first); Parent Settings closes its uppermost gated surface; Baby Room and Free Play close overlays before leaving; Dress Up, Classroom and house gameplay return to the title. Static regression coverage passes. Real-device Back and gesture-navigation testing remains mandatory before the RC gate can pass.
