# Android package ID migration

Last updated: 2026-09-22

## Decision

The final Android application ID, before the first Google Play upload, is:

```text
com.joinanny.littledays
```

This changes Android identity only. The Apple bundle identifier remains
`com.pointit.littlebuddy`. Backend account UUIDs, parent IDs, guest IDs, child
profile IDs, database primary keys, and local save keys are unchanged.

## Repository audit

| Identifier | Finding | Classification / action |
|---|---|---|
| `com.pointit.littlebuddy` | Present | The authoritative remaining uses are Apple/iOS configuration and instructions. One Android readiness note retains it only as the package of a pre-migration sideload that may need uninstalling. It is not an active Android package value. |
| `com.pointit.littledays` | Not found | No runtime, test, configuration, or documentation occurrence existed at migration time. |
| `com.joinanny.littlebuddy` | Present from the superseded intermediate Android decision | Replaced in the Godot Android preset, export guard, Google billing configuration examples, Google verifier tests, Android QA fixtures, and current Android/Play documentation. |
| `com.joinanny.littledays` | Final | Used by all active Android package, Google Play verification, and Android release contracts. |

Generated `game/android/build/**` Gradle files and merged manifests are ignored
build products. They derive the application ID from the Godot export preset and
must be regenerated; they must not be treated as authoritative or hand-edited.

## Google Play implications

- Create the first Play Console app as `com.joinanny.littledays`.
- Do not upload an AAB using either legacy PointIT ID or the superseded
  `com.joinanny.littlebuddy` ID.
- If an empty, never-published Play Console record was created under an old ID,
  discard/delete that draft record when Play Console permits it. Do not delete
  any published app record without a separate owner review. No repository
  evidence shows that an Android artifact has been uploaded.
- Existing sideloads under another package are separate apps and will not update
  in place or share their local sandbox with the final package.

## Google identity implications

Create the Android Credential Manager / Sign in with Google OAuth client for:

```text
package: com.joinanny.littledays
certificate: owner release/app-signing SHA-256 fingerprint
```

Do not invent a client ID or certificate fingerprint. Add the issued OAuth
client ID to the server-side `GOOGLE_CLIENT_IDS` list. Debug and release signing
certificates require separate Android OAuth clients when both are tested.

## Billing and RTDN implications

- Server-side Play verification expects
  `GOOGLE_PACKAGE_NAME=com.joinanny.littledays`.
- Google service-account access must be granted to the Play Console app with
  that package.
- Play product IDs, RTDN topic/subscription, and purchase-token verification
  must be configured against the final package.
- The backend verifies receipts with Google and checks the verified purchase
  account marker against the linked parent account. A client-provided package
  string alone is never trusted.
- `BILLING_ENABLED=false` remains the production gate.

## Export contract

- target SDK: 36
- minimum SDK in the Gradle AAB: 29
- architecture: ARM64 only
- label: Little Days
- orientation: sensor/user landscape
- versionName: 0.1.1
- versionCode: 2

The release AAB is `build/android/LittleDays-release.aab`, SHA-256
`f3b8d8257630062406ab9556048ee1f373c134d70a9bea0ef4419b6da0acb1e7`.
Bundletool verified the base and asset-pack manifests use the final ID, version
`0.1.1` / code `2`, min/target/compile SDK `29` / `36` / `36`, and contain no
`debuggable=true` declaration or permissions. `jarsigner` verified the upload
signature. The bundle has not been uploaded to Play.

The candidate upload key was generated outside the repository. Its public
certificate fingerprints are recorded in `GOOGLE_CREDENTIAL_MANAGER.md`. The
owner must move the only current copy out of `/private/tmp`, back up the
keystore and password separately, and retain them for every future upload.

## Files changed

The migration commit changes the Godot export preset, Android export script,
Android package assertions, Google billing verifier fixtures, server environment
contract/example, Android QA fixtures, current Play/Android release documents,
and this migration record. Apple-only instructions intentionally retain the
Apple identifier.
