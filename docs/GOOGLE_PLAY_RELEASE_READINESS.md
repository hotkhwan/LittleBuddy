# Google Play release readiness — Little Days (`com.joinanny.littledays`)

> **Signed release candidate 2026-09-22:** `build/android/LittleDays-release.aab`,
> SHA-256 `f3b8d8257630062406ab9556048ee1f373c134d70a9bea0ef4419b6da0acb1e7`.
> Bundletool confirms package `com.joinanny.littledays`, versionName `0.1.1`,
> versionCode `2`, compile/target SDK `36`, and no declared permissions. It is
> signed by the candidate Little Days upload certificate, has no
> `debuggable=true` declaration, and has not been uploaded. Before any upload,
> the owner must move and back up the only current keystore copy as described below.

**Prepared:** 2026-09-20, from worktree `wt/android` (base `cca0198`), on the MacBook.
**Scope:** what Play Console will ask for, answered from the **actual exported
APK and the actual code**, not from intent. Every claim below names where it was
measured. Items nobody on this machine can verify are marked **OWNER** and are
not ticked.

> **One-line status.** A real signed release AAB with zero permissions exists.
> Public release is **not** ready: the candidate upload key needs durable owner
> custody, there is no Play Console app, privacy-policy URL, completed store
> listing, or physical-device pass, and the game has never run on an
> Android device. Nothing below is a PASS from Google; it is the input sheet.

---

## 0. The artefact these answers describe

| | |
|---|---|
| File | `build/android/LittleDays-release.aab` (git-ignored release artifact) |
| Built | 2026-09-22 from the package-migration branch |
| Size | 44,106,193 bytes |
| SHA-256 | `f3b8d8257630062406ab9556048ee1f373c134d70a9bea0ef4419b6da0acb1e7` |
| Package / label | `com.joinanny.littledays` / **Little Days** |
| versionCode / versionName | `2` / `0.1.1` |
| minSdk / targetSdk / compileSdk | **29 / 36 / 36** |
| ABIs | `arm64-v8a` only (`libgodot_android.so` 76.2 MB uncompressed, `libc++_shared.so`) |
| 16 KB page size | both `.so` have `LOAD p_align = 0x4000` — **compliant** with Play's 16 KB requirement for targetSdk ≥ 35 |
| Orientation | `screenOrientation=11` (sensorLandscape), from `project.godot` `window/handheld/orientation=4` |
| Adaptive icon | `res/mipmap-anydpi-v26/icon.xml` + background/foreground/monochrome webp layers — present |
| `allowBackup` | `false` (`user_data_backup/allow=false`) |
| `isGame` / `appCategory` | `true` / `0` (game) |
| Debuggable | **no** — bundle manifest contains no `debuggable=true` declaration |
| Signature | JAR verified; signer `CN=Little Days Upload, OU=Mobile, O=Join Anny, C=TH` |

The lead will rebuild from the integrated HEAD with this toolchain; the hash
and build time above will change, nothing else in this document should.

### Declared permissions: **none**

```
$ bundletool dump manifest --bundle LittleDays-release.aab
package: com.joinanny.littledays
```

Zero `uses-permission` elements. In particular:

- **no `INTERNET`** — the app cannot open a socket. Offline-first is enforced by
  the OS, not by convention.
- **no `RECORD_AUDIO`** — the app cannot open the microphone. Correct, because
  there is no Android speech-recognition backend (see §3).
- no `AD_ID`, no location, no storage, no Bluetooth, no camera, no telephony.

The release template's baseline (`android_release.apk` in the export templates)
also declares no permissions, and the debug export added none, so the release
build's list is expected to be identical — **re-dump it on the actual release
artefact anyway**; `tools/export_android.sh` prints it after every APK build.

### Exported components (from the manifest)

| Component | Exported | Note |
|---|---|---|
| `com.godot.game.GodotAppLauncher` (activity-alias) | yes | the launcher entry — required |
| `com.godot.game.GodotApp` (activity) | no | |
| `org.godotengine.godot.utils.ProcessPhoenix` (activity) | no | Godot's restart helper |
| `androidx.core.content.FileProvider` | no | |
| `androidx.startup.InitializationProvider` | no | |
| `androidx.profileinstaller.ProfileInstallReceiver` (receiver) | yes, **guarded by `android.permission.DUMP`** | androidx boilerplate; only a caller holding DUMP (i.e. the shell) can reach it. Not an attack surface |

### Third-party SDKs: **none**

Checked two ways. (1) `apkanalyzer dex packages --defined-only`: the only
non-framework packages *defined* in the APK are `org.godotengine.*`,
`com.godot.game`, `androidx.*`, `kotlin*`/`kotlinx*` and
`com.google.common.util.concurrent` (Guava's ListenableFuture shim pulled in by
androidx). No ads, analytics, billing, crash-reporting, attribution or social
SDK. (2) `grep -ri` over `game/` for admob/firebase/analytics/crashlytics/
billing/purchase/StoreKit/gms: only comments and the tests that *forbid* them
(`test_entitlement_no_purchase_guard.gd`, `test_speech_privacy_guard.gd`,
`test_content_pack_catalog.gd`).

`android.speech.tts.TextToSpeech` is *referenced* (not bundled) by Godot's Java
layer — that is the system text-to-speech engine behind `DisplayServer.tts_*`,
which needs no permission. **No `SpeechRecognizer` class is referenced anywhere**
in the dex or in `libgodot_android.so`.

---

## 1. Target audience & Families policy

The product is a game for children of roughly 3–7 (`docs/NAMING_AND_TRADEMARK.md`,
`LITTLE_BUDDY_GAME_BIBLE.md`). In Play Console → *Policy → App content → Target
audience and content*, the honest declaration is a child age band (e.g. **Ages
5 and under** and/or **6–8**). Declaring any child band makes the **Families
policy** binding. How this build stands against each requirement (source:
Play Console Help, *Families policy requirements*, fetched 2026-09-20):

| Families requirement | This build | Evidence |
|---|---|---|
| Content appropriate for children | Nursery/kitchen care play, English words, no violence/gambling/dating/substances | `game/content/**`, mission JSON; a human still has to confirm every asset — see **OWNER** below |
| No collection/transmission of PII, AAID, IMEI, MAC, location from children | Nothing is transmitted: no `INTERNET`, no `AD_ID`, no location permission | `aapt2 dump permissions` → empty |
| Only approved APIs/SDKs; only self-certified ads SDKs | No third-party SDKs at all; no ads | §0 |
| No `TelephonyManager` phone-number, no `AD_ID` on API 33+, no location | none of those permissions exist | §0 |
| Privacy policy reflecting real practices, COPPA/GDPR-K | **does not exist yet** — §4 is the content it must state | **OWNER** |
| Target audience declared before publishing | not done — no Play Console app exists | **OWNER** |
| Not a webview; no links to policy-violating sites; no affiliate traffic | Native Godot app. The **one** external reference is a YouTube channel URL shown as **text** behind the 3-second parental hold and copied to the clipboard on a second confirming tap. The build never calls `OS.shell_open()` | `game/scenes/parent/parent_settings.gd:250-263,371-378`; `grep -rn shell_open game/` hits only comments and the test that forbids it |
| IAP clearly distinguished / no deceptive purchases | **There are no purchases.** Parent Corner shows Family Club *prices as information only* and says so in the UI; no billing library, no product id | `docs/FAMILY_CLUB.md`, `test_entitlement_no_purchase_guard.gd` |
| Social features → safety reminders | none — no accounts, no chat, no sharing | `save_service.gd` header: "no cloud sync, no analytics, no accounts" |
| AR safety warning | no AR | |

**Parental gate.** `game/scripts/parent_settings/parental_gate.gd`: press-and-hold
3.0 s (`DEFAULT_HOLD_SECONDS`), no maths, no digits; release or slide-off resets.
The gear is the only way into Parent Corner, and destructive actions have a
second 3-second hold. Pinned by `test_parent_gate.gd` and
`test_entitlement_no_purchase_guard.gd`.

**Things a reviewer may still ask about, honestly:**

- The Family Club **price display** (USD 2.99 / THB 99) is behind the gate and
  buys nothing. It is not an IAP, but it is a *mention of money* in a
  children's app. If a reviewer objects, the strings live in one place
  (`parent_settings.gd`); nothing else depends on them.
- The **YouTube link text**: it is not a link (no intent, no browser), but a
  reviewer reading the panel text will see a URL. Keep it behind the gate, or
  remove it for the first submission if you want zero questions.
- **Music is silent** in every build until `docs/MUSIC_RIGHTS_CHECKLIST.md` is
  answered (`commercialUse: "pending"`). A store build with unverified-licence
  music switched on is a rights problem, not a Play-policy one, but it would be
  a real one.

**OWNER — cannot be verified here:** Play Console account type and creation
date (§6), that every shipped asset is licensed for commercial use
(`docs/ASSET_LICENSE_REPORT.md`, `docs/THIRD_PARTY_NOTICES.md` — I did not
re-audit them), and the final display name (`docs/NAMING_AND_TRADEMARK.md`
recommends *not* shipping as "Little Days"; this is a naming decision, not a
Play requirement — Play does not check trademarks at submission, rights-holders
complain afterwards).

---

## 2. Content rating (IARC questionnaire) — expected inputs

Category: **Game**. Truthful answers from the code: no violence, no fear
content, no sexual content, no drugs/alcohol/tobacco, no gambling or simulated
gambling, no profanity, **no user interaction** (no chat, no sharing, no
user-generated content), **no location sharing**, **no digital purchases** (the
Family Club text is informational and cannot transact — if the questionnaire
asks "does the app *promote* purchases" answer per the owner's reading of that
panel), no unrestricted internet access (there is no internet access). Expected
outcome: the lowest rating in every region (ESRB *Everyone*, PEGI 3, USK 0,
etc.). The rating is issued only after the questionnaire is submitted in Play
Console — **not obtained yet**.

---

## 3. Data Safety form — inputs derived from the code

| Form question | Answer | Why |
|---|---|---|
| Does your app collect or share any of the required user data types? | **No** | Nothing leaves the device: no `INTERNET` permission; no network class is referenced from game code (`test_speech_privacy_guard.gd`, `test_content_pack_catalog.gd` fail the suite if one appears) |
| Is all user data encrypted in transit? | n/a — no transit | |
| Do you provide a way to request deletion? | n/a for the form (no collection). In-app: Parent Corner → *Reset progress* erases `user://profile.json` | `docs/PARENT_CORNER.md` |
| Audio → voice or sound recordings | **not collected** on Android — the app cannot open the microphone (no `RECORD_AUDIO`) | §0 |
| Device or other IDs | none | no `AD_ID`, no analytics |
| Files/docs, photos, contacts, location, financial, health, messages, calendar | none | no permissions, no code |
| App activity | none leaves the device | `user://profile.json` (stars, completed activities, settings) and `user://speech_diag.json` (counters only — never a transcript) are app-internal; `allowBackup=false` keeps them out of Google cloud backup |

What the app stores **locally only**, so the privacy policy can list it
truthfully: stars, completed activities, replay state, settings (Thai hints,
speech on/off, speaking speed), and speech *diagnostic counters* (listen /
recognised / failed counts, last failure reason, launch count, locale). No
audio, no transcripts, no names, no photos, no identifiers.

**Important asymmetry with iOS.** The iOS build *does* use the microphone and
on-device Apple speech recognition (`ios_speech_backend.gd`,
`NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` in
`export_presets.cfg`). The Play Data Safety form is answered for the **Android**
build, where none of that exists. If an Android speech backend is ever added,
`RECORD_AUDIO` appears and this form must declare *Audio → voice recordings,
processed ephemerally, not shared* — and on-device recognition must be provable
(`docs/ANDROID_READINESS.md` §3.4).

---

## 4. Privacy policy — what it must state (URL required in Play Console)

Play requires a **publicly reachable privacy-policy URL** for every app, and
Families apps are checked against it. **No such page exists yet (OWNER).** It
must say, truthfully for this build:

1. Who the developer is (legal name / contact email).
2. The app is for children; no account is created; no personal information is
   collected, stored off-device, or shared with anyone.
3. The Android app has **no internet access** and requests **no permissions**.
4. Progress and settings are stored only on the device; the parent can erase
   them in Parent Corner → Reset progress; uninstalling deletes them.
5. Speech (where available, i.e. iOS): processed on the device by the operating
   system's speech recogniser; **nothing is recorded, saved, or uploaded**; the
   parent can turn it off. State plainly that the Android version has no
   microphone or speech feature.
6. No ads, no analytics, no third-party SDKs, no purchases in the app; prices
   shown in Parent Corner are informational.
7. The one external reference (a YouTube channel) is shown as text behind a
   parental gate and is never opened by the app.
8. Contact and effective date; note COPPA / GDPR-K / Thailand PDPA as applicable
   (the owner decides jurisdictions; this document does not give legal advice).

Host it somewhere stable the owner controls (any static page). The same URL
goes into App Store Connect for iOS.

---

## 5. Store listing — required assets and what exists

Specs from Play Console Help, *Add preview assets*, fetched 2026-09-20.

| Asset | Requirement | Exists? |
|---|---|---|
| App icon | 512 × 512, **32-bit PNG with alpha**, ≤ 1024 KB | **No 512 file.** `game/icon_1024.png` (1024², RGB, no alpha) and `game/assets/icon/ios/icon_1024.png` can be downscaled; add an alpha channel or keep it opaque (opaque is allowed) |
| Feature graphic | **1024 × 500**, JPEG or 24-bit PNG (no alpha), **mandatory** | **No.** Nothing at that size in the repo |
| Phone screenshots | ≥ 2; JPEG/24-bit PNG no alpha; each side 320–3840 px; **long side ≤ 2× short side**; recommended ≥ 4 at 16:9 ≥ 1920×1080 | **No Android screenshots.** `docs/shots/*.png` are macOS editor renders at iPad/iPhone viewports. 1334×750 and 1366×1024 frames satisfy the ratio rule but are below the recommended 1080 px height; the 2340×1080 "iphone" frames are 2.17:1 and **would be rejected** by the 2× rule |
| 7-inch tablet screenshots | ≥ 4 (needed for tablet listing quality), 1080–7680 px, 16:9 or 9:16 | **No** |
| 10-inch tablet screenshots | same | **No** |
| Short description (≤ 80 chars) / full description (≤ 4000) | text | not written |
| Promo video | optional; YouTube, public/unlisted, ads off, embeddable | none |

Screenshots taken on a real Android tablet/phone are the honest choice; if the
first submission uses editor renders, render them at exactly 1920×1080 (or
2560×1600 for tablets) so the ratio rule is met, and do not include HUD text
that lies about the platform.

---

## 6. Account, testing track and the closed-testing prerequisite

- **Personal developer accounts created after 13 Nov 2023** must run a **closed
  test with at least 12 testers opted-in continuously for 14 days** before the
  *Production* track (and pre-registration) unlocks; the count was 20 until
  11 Dec 2024. Meeting it makes the account *eligible to apply* for production
  access; Google can still ask for more. Organisation accounts are exempt.
  (Play Console Help, *App testing requirements for new personal developer
  accounts*, fetched 2026-09-20.)
- **Whether this rule applies to the owner's account cannot be determined from
  this machine.** It depends on the account type and creation date, visible
  only after signing in to Play Console. **OWNER.**
- Practical consequence if it does apply: a **2026-09-21 submission is a
  closed-testing upload, not a production release** — production would be no
  earlier than 14 days after 12 testers have joined. Plan the 12 testers (real
  people, Google accounts, who install and open the app) now.
- Internal testing (up to 100 testers, no review delay) is the fastest way to
  get the AAB onto real Android devices via Play, and does not count toward the
  14 days.

---

## 7. Target API and other Play technical gates (as of 2026-09-20)

| Gate | Requirement | This build |
|---|---|---|
| Target API level | New apps and updates must target **API 36** from 31 Aug 2026 (extension possible to 1 Nov 2026) — Play Console Help *Target API level requirements*, fetched today | **targetSdk 36** — meets it. Not raised by hand; it is the Godot 4.7.2 template default |
| Upload format | **AAB** for new apps (APKs are not accepted on Play) | pipeline installed; see §8 |
| Signing | Play App Signing: Google holds the app-signing key; you upload with an **upload key** | **no upload key exists** — §8 |
| 16 KB page size (targetSdk ≥ 35) | native libs 16 KB-aligned | **yes**, `p_align 0x4000` on both `.so` |
| 64-bit | arm64 required | arm64-v8a only. `armeabi-v7a` and `x86_64` are **absent** — Play does not require them; 32-bit-only phones will not see the app, and x86_64 matters only for emulators/Chromebooks. A 3-D game at 34 MB gains little from v7a |
| Debuggable | must be `false` | the debug APK/AAB are `true` by design; the release build will not be — confirm with `bundletool dump manifest` on the release AAB |
| Min SDK of the upload | your choice; Play shows it on the listing | **29 (Android 10)** in the AAB, from Godot's Vulkan default — Android 7–9 devices will not see the app. Override with `gradle_build/min_sdk="24"` only as a deliberate product decision |
| App category / declarations | Game; Families declarations; ads = none; Data Safety; content rating | not filled — no Console app |

---

## 8. Exactly what a Play-ready AAB needs on this machine

Installed and verified today, all **user-local, no sudo**:

| Piece | Where | Size |
|---|---|---|
| Temurin JDK 17.0.20.1 | `~/Library/Java/JavaVirtualMachines/temurin-17.jdk` | 309 MB |
| Android cmdline-tools 19.0, platform-tools 37.0.1, platforms;android-36, build-tools;36.1.0 | `~/Library/Android/sdk` | 521 MB |
| **NDK 29.0.14206865** (Gradle build only) | `~/Library/Android/sdk/ndk/29.0.14206865` | 3.1 GB (1.05 GB download) |
| Godot Android build template 4.7.2 | `game/android/build` (git-ignored) + `game/android/.build_version` | 217 MB per checkout |
| Gradle 8.11.1 + AGP 8.6.1 + Kotlin 2.1.21 deps | `~/.gradle` (downloaded by `gradlew` on the first build) | 1.2 GB; first build 3 min 08 s, warm build 56 s |
| Debug keystore | `~/Library/Application Support/Godot/keystores/debug.keystore` | generated today; **not for Play** |
| **Candidate release upload certificate** | generated outside Git; fingerprints in `GOOGLE_CREDENTIAL_MANAGER.md` | The owner must move it from temporary storage and make durable, separate backups before use. |

**How the owner supplies the release key — never in the repo:**

```sh
# one-time helper; choose a path outside the repository
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="/secure/owner/path/littledays-upload.jks"
tools/create_android_upload_keystore.sh

# in the shell that runs the export (Godot 4.7 reads these when the preset's
# keystore/release* fields are empty -- they are, deliberately)
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=littledays-upload
read -s GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD && export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD

tools/export_android.sh release --aab     # -> build/android/LittleDays-release.aab
```

**Pipeline proof:** `tools/export_android.sh release --aab` produced the signed
release candidate described in §0 and bundletool verified its package/version,
zero permissions, and arm64-v8a-only native payload. **Finding:** Gradle returned the bundle *unsigned*
although Godot asked it to sign; the script now detects that and signs with
`jarsigner` (Google's documented tool for bundles), re-verifies, and fails if
the result is not `jar verified`. Verify the release bundle yourself before
uploading: `jarsigner -verify -verbose:summary -certs LittleDays-release.aab`
must print `jar verified` and your upload-key DN.

`tools/export_android.sh release` **refuses** to run without those three
variables, refuses a path ending in `debug.keystore`, and refuses a keystore
inside the working tree. `.gitignore` blocks `*.jks`, `*.keystore`, `*.p12`,
`*.pepk`, `keystore.properties`. The three `keystore/release*` keys in
`game/export_presets.cfg` are empty strings and must stay that way.

With Play App Signing this is the *upload* key: losing it is recoverable via
Play Console support (upload-key reset); a leaked one must be reset the same
way. The *app-signing* key is Google's.

---

## 9. Remaining steps to a submission, in order

1. **OWNER:** sign in to Play Console; note account type + creation date; create
   the app (`com.joinanny.littledays`, Game, free).
2. **OWNER:** decide the public name (`docs/NAMING_AND_TRADEMARK.md`) — change
   only `config/name` in `project.godot` and `package/name` in the Android
   preset if you switch; never the package id.
3. **OWNER:** move the candidate upload keystore to durable encrypted storage
   and test its separate backups (§8).
4. Rebuild with `tools/export_android.sh release --aab` when the final owner-held
   path is in use; `aapt2`/`bundletool` check:
   permissions still empty, `debuggable=false`, versionCode bumped for every
   upload (`version/code` in the Android preset — Play rejects a repeat).
5. **OWNER:** publish the privacy-policy URL (§4).
6. Store listing: 512 icon, 1024×500 feature graphic, ≥ 4 phone + ≥ 4 tablet
   screenshots (§5), descriptions.
7. Play Console declarations: Target audience (child band) → Families; Data
   Safety (§3: "no data collected"); Content rating questionnaire (§2); Ads =
   No; News = No; Government = No; Health = No; Financial = No.
8. Upload the AAB to **internal testing** first; install from Play on a real
   Android phone and tablet; run `docs/DEVICE_QA_CHECKLIST.md` and
   `docs/ANDROID_READINESS.md` §9 (speech reads *unavailable*, touch-only
   playthrough, safe area both ways up, TTS audible).
9. Promote to **closed testing**; if the 12-tester rule applies, recruit 12
   testers and wait 14 continuous days; then apply for production.
10. Production release, staged rollout.

## 10. Blockers, plainly

- Candidate upload keystore exists, but its only current copy is in temporary
  storage and is not operationally safe until the owner moves and backs it up.
- No Play Console app / unknown account eligibility (owner login required).
- No privacy-policy URL.
- No store graphics at Play sizes; no Android screenshots.
- **The game has never run on Android hardware.** Every functional statement
  above is about the file, not the play experience.
- Music silent pending rights; Family Club price text and YouTube URL text
  are reviewer-visible design choices to confirm before submitting.
- Gradle hands back an **unsigned** bundle; the script's `jarsigner` step
  covers it, but the release bundle's signature must be eyeballed once before
  the first upload.
- The AAB's **minSdk is 29**, not the APK's 24 — decide whether Android 10+
  only is acceptable before the listing goes live.
