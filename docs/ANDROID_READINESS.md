# Android Readiness

## STATUS (2026-09-20, MacBook): TOOLCHAIN REPRODUCED, APK REBUILT, AAB PIPELINE INSTALLED. STILL NEVER RUN ON A DEVICE.

```
build/android/LittleDays-debug.apk   36,647,845 bytes   signed (v2 + v3)   sha256 1a8f7f7b…54e2
```

The 2026-09-19 work below was done on the Mac Mini. On 2026-09-20 the same
sudo-free toolchain was installed on the MacBook by following section 7
verbatim, and section 7 was then corrected where the MacBook disagreed with it
(three places: a settings-file race, a hanging headless flag, and the build
template layout). What is new today:

| Item | 2026-09-20 result |
| --- | --- |
| Temurin 17.0.20.1, cmdline-tools 19.0, platform-tools 37.0.1, platforms;android-36, build-tools;36.1.0 | installed user-locally, checksums matched the published ones (JDK sha256 `196d13ba…f0e8`, cmdline-tools sha1 `c3e06a19…1d24`); 309 MB + 521 MB |
| Debug keystore | absent on this machine → generated (cert sha256 `fbdbc747…33ac`); **different key from the Mac Mini's**, so a phone that had the Mac Mini APK needs `adb uninstall` first |
| Debug APK | rebuilt from `cca0198` game content; manifest facts identical to the 09-19 build (0 permissions, arm64-v8a, minSdk 24 / targetSdk 36, sensorLandscape, adaptive icon, v2+v3) |
| 16 KB page size | both `.so` `p_align 0x4000` — Play-compliant |
| **NDK 29.0.14206865** | installed (1.05 GB download, 3.1 GB on disk, no sudo) — needed only for the Gradle/AAB build |
| **Android build template** | unpacked into `game/android/build` (git-ignored) with `game/android/.build_version` = `4.7.2.stable` |
| `tools/export_android.sh --aab` | new; see section 7 step 9 and `docs/GOOGLE_PLAY_RELEASE_READINESS.md` §8 |
| Release keystore | **not created, deliberately** — owner-held, supplied via environment variables only |
| Test suite in the worktree | `PASS - 122 case(s), 0 failure(s)` |
| Android device | **still absent** |

Play Store readiness (Families, Data Safety, content rating, listing assets,
the 12-tester closed-testing rule) is now written up separately in
`docs/GOOGLE_PLAY_RELEASE_READINESS.md`.

## STATUS (2026-09-19): AN APK EXISTS. IT HAS NEVER RUN ON A DEVICE.

```
build/android/LittleDays-debug.apk   36,422,803 bytes   signed (v2 + v3)
```

Two separate claims, and only the first one is proven:

- **The build works.** The toolchain was installed, the preset applied, and
  `tools/export_android.sh debug` ran the whole way through. The APK is real,
  signed, and its manifest has been dumped and read.
- **The game has NOT been validated on Android.** There is still no Android
  device and no emulator. Nothing below is a statement about how the game looks,
  performs, or feels on real hardware. Section 9 is the list that only a device
  can close, and it is entirely unticked.

An earlier revision of this document opened with *"NO APK WAS PRODUCED. ANDROID
HAS NEVER BEEN BUILT OR RUN."* The first half of that is now obsolete. **The
second half is not.**

### What changed, verified by running the checks rather than assuming

| Requirement | Was | Now |
| --- | --- | --- |
| JDK 17 | **absent** — `/usr/bin/java` is the macOS stub | **present** — Temurin `17.0.20.1`, user-local, **no sudo** |
| Android SDK | absent | **present** — `~/Library/Android/sdk` |
| `sdkmanager` / `adb` | absent | present — cmdline-tools `19.0`, platform-tools `37.0.1` |
| build-tools / platform | absent | `build-tools;36.1.0`, `platforms;android-36` |
| SDK licences | not accepted | accepted non-interactively |
| Debug keystore | absent | **generated** — outside the repo, git-ignored |
| Godot `java_sdk_path` | `""` | set to the Temurin home |
| Godot `android_sdk_path` | pointed at a non-existent dir | now a directory that exists |
| Android export preset | absent | `[preset.1]` appended; iOS preset byte-identical |
| Launcher icons | absent | 192 + two 432 adaptive layers, generated from existing art |
| Export templates | present | present (unchanged — the slowest item was already done) |
| Android device | **absent** | **still absent** |
| `gradle` | absent | **still absent, and not needed** — see below |

### Three corrections to the previous revision

1. **The debug APK declares ZERO permissions.** The previous revision predicted
   Godot would add `INTERNET` to a debug export for the remote debugger. For
   *this* export — template-based, `gradle_build/use_gradle_build=false` — it
   does **not**. `aapt2 dump xmltree` reports **0 `uses-permission` elements**.
   See section 2 for what this lets us conclude about the release build.
2. **`gradle` is not required and never was.** The preset uses the prebuilt
   template, so no Gradle build runs. The NDK is likewise unnecessary;
   `export_android.sh` correctly treats it as a warning, not a blocker.
3. **No sudo is needed for any of it.** The previously-recommended
   `brew install --cask temurin@17` prompts for an admin password. Unpacking the
   Temurin tarball into `~/Library/Java/JavaVirtualMachines/` does not, and
   `/usr/libexec/java_home -v 17` still discovers it there (verified). Section 7
   has been rewritten around the sudo-free route.

Everything else in this document is either an audit finding with a file:line or
a command that was actually run. Where a fact came from a local artifact I say
which artifact; where I could not verify something, I say so.

---

## 1. The Android export preset — APPLIED

`game/export_presets.cfg` now contains `[preset.1]` / `[preset.1.options]`
(`platform="Android"`) appended after the existing iOS preset.

**The iOS preset was not touched.** Verified two ways rather than asserted:
`diff` of lines 1–64 against `git show HEAD:game/export_presets.cfg` is empty,
and `git diff --numstat` reports `60  0` — sixty insertions, **zero deletions**.

Two values differ from the block originally drafted below:

- `export_path` is `../build/android/LittleDays.apk` (was `LittleBuddy.apk`),
  matching the app name. `export_android.sh` writes a mode-suffixed name
  (`LittleDays-debug.apk`) so a debug build cannot silently overwrite a release
  one.
- the `launcher_icons/*` paths are `res://assets/icons/android/…`, and those
  files now exist (section 5).

### The bundle identifier — reported, not changed

The iOS preset declares:

```
application/bundle_identifier="com.pointit.littlebuddy"
```

(`game/export_presets.cfg:26`, with `application/app_store_team_id="JZDAUN45CF"`).

The Android preset below uses **`com.pointit.littlebuddy`** for
`package/unique_name`, so the two platforms stay in one identifier family. This
is deliberate and it is the right call: a mismatched identifier makes every later
piece of store plumbing (Play Console app, Firebase project if one ever appears,
deep links, the `speech_diag.json` pull path documented in
`game/scripts/speech/speech_service.gd:79`) diverge between platforms for no
reason. Android imposes no `com.`-prefix constraint that iOS does not already
satisfy, and `littlebuddy` is a valid final segment (lowercase, starts with a
letter, no reserved Java keyword).

### The app name — RESOLVED, no longer a decision

A previous revision flagged this loudly, on the grounds that *"the string
'Little Days' does not appear anywhere in this repository"* and that an Android
launcher reading **Little Days** would sit beside an iPad app reading **Little
Buddy**. **That is no longer true and the warning is withdrawn.** The rename
landed:

- `game/project.godot:13` → `config/name="Little Days"`
- `docs/NAMING_AND_TRADEMARK.md` exists and covers the decision
- the name is used throughout content, audio and docs (`littleDaysTheme`, …)

So `package/name="Little Days"` agrees with the rest of the project rather than
contradicting it. Confirmed in the built APK:
`aapt2 dump badging` → `application-label:'Little Days'`.

Setting `package/name=""` (inherit `config/name`) would now give the identical
result and be one less place to update. Either is defensible; the explicit
string is kept because it is what the manifest assertion in this document
quotes.

**The bundle id did NOT change**, and must not: `com.pointit.littlebuddy` on
both platforms. Apple forbids changing a bundle id after submission, and the
owner has frozen all internal identifiers. The APK confirms it:
`package: name='com.pointit.littlebuddy'`. Only the *display name* is
"Little Days" — the identifier keeps the original spelling deliberately.

### Orientation is NOT in this preset — it comes from `project.godot`

There is no `screen/orientation` option on Godot's Android preset. Landscape is
taken from the project setting, which is **already correct**:

```
# game/project.godot
window/handheld/orientation=4
```

`4` is `Sensor Landscape` in Godot's enum (verified: the hint string
`"Landscape,Portrait,Reverse Landscape,Reverse Portrait,Sensor Landscape,Sensor
Portrait,Sensor"` is in the 4.7.2 binary). The exporter injects this into the
manifest as `android:screenOrientation="sensorLandscape"` — verified, the 4.7.2
binary contains the template line:

```xml
<activity android:name=".GodotApp" tools:replace="android:screenOrientation,android:excludeFromRecents,android:resizeableActivity" ... android:screenOrientation="%s" android:resizeableActivity="%s">
```

`sensorLandscape` is the right choice for a child: the tablet can be held either
way up and the game follows. **No change needed.** The stock manifest in
`android_source.zip` also sets `android:resizeableActivity="false"`, which
matters for section 4.

### SDK levels — verified from the shipped build template

Read out of `config.gradle` inside
`export_templates/4.7.2.stable/android_source.zip`, so these are this engine
version's actual numbers rather than remembered ones:

```groovy
compileSdk : 36
minSdk     : 24     // DEFAULT_MIN_SDK_VERSION
targetSdk  : 36     // DEFAULT_TARGET_SDK_VERSION
buildTools : '36.1.0'
javaVersion: JavaVersion.VERSION_17
ndkVersion : '29.0.14206865'
androidGradlePlugin: '8.6.1'
```

The preset below leaves `gradle_build/min_sdk` and `gradle_build/target_sdk`
**empty**, which means "use the template defaults" — min 24, target 36. That is
the correct choice and I recommend not overriding either:

- **min SDK 24 (Android 7.0)** is Godot 4's floor; you cannot go lower, and
  raising it only sheds devices. 24 is fine for a 2016-and-newer install base.
- **target SDK 36** is required by Google Play's annual target-API rule anyway.
  Note the consequence for section 4: **targetSdk 35+ means Android enforces
  edge-to-edge display**, so safe-area handling is not optional on Android the
  way it could be ignored on an older target.

Both options are also inert unless `gradle_build/use_gradle_build=true`.

### Architectures: `arm64-v8a` only. `armeabi-v7a` is not worth it.

Recommendation: **`arm64-v8a` alone.** Reasoning, in order of weight:

1. **Play requires 64-bit; 32-bit is optional.** Since August 2019 every APK/AAB
   must include 64-bit libraries. A 32-bit-only slice adds reach, never
   compliance.
2. **Size.** Godot's native library is the bulk of the APK. Adding `armeabi-v7a`
   roughly doubles the native payload for a game that already ships GLB
   characters and audio — a straight download cost paid by every 64-bit user.
3. **The devices it would add cannot run this game.** A 32-bit-only ARM device
   that is also on Android 7+ is a low-end 2016-era phone. This is a 3D title
   using the Mobile renderer, real-time directional shadow, skinned GLB
   characters and ETC2/ASTC textures (`project.godot` `[rendering]`). Shipping to
   hardware that will run it at single-digit FPS is worse for a four-year-old
   than not appearing in their store listing.
4. **It is a tablet-first game.** Per `CLAUDE.md` the target is a landscape
   tablet. Android tablets worth targeting are all arm64.

`x86`/`x86_64` are off too. The build machine is Apple Silicon (`uname -m` →
`arm64`), so an Android Studio emulator on it is **arm64-v8a** — the same slice
already being built. x86_64 would only be needed for an Intel-host emulator or a
ChromeOS/x86 tablet, neither of which is in play.

If reach ever becomes a real requirement, switch `gradle_build/export_format` to
AAB (`1`) and let Play split per-ABI, rather than fattening a universal APK.

### The block to append to `game/export_presets.cfg`

```ini
[preset.1]

name="Android"
platform="Android"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter="assets_source/*, assets/characters/buddy/pinkGirl/pinkGirl_v01*, assets/characters/mascot/*, assets/characters/littleBuddy/baby/baby_standing_v01*, assets/characters/littleBuddy/baby/baby_sleeping_v01*, assets/characters/littleBuddy/baby/baby_sitting_v01*"
export_path="../build/android/LittleBuddy.apk"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.1.options]

custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
gradle_build/gradle_build_directory=""
gradle_build/android_source_template=""
gradle_build/compress_native_libraries=false
gradle_build/export_format=0
gradle_build/min_sdk=""
gradle_build/target_sdk=""
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
version/code=1
version/name="0.1.0"
package/unique_name="com.pointit.littlebuddy"
package/name="Little Days"
package/signed=true
package/app_category=2
package/retain_data_on_uninstall=false
package/exclude_from_recents=false
package/show_in_android_tv=false
package/show_in_app_library=true
package/show_as_launcher_app=false
launcher_icons/main_192x192="res://assets/icon/android/icon_192.png"
launcher_icons/adaptive_background_432x432="res://assets/icon/android/icon_adaptive_background_432.png"
launcher_icons/adaptive_foreground_432x432="res://assets/icon/android/icon_adaptive_foreground_432.png"
launcher_icons/adaptive_monochrome_432x432=""
graphics/opengl_debug=false
xr_features/xr_mode=0
screen/immersive_mode=true
screen/edge_to_edge=false
screen/support_small=false
screen/support_normal=true
screen/support_large=true
screen/support_xlarge=true
user_data_backup/allow=false
command_line/extra_args=""
permissions/custom_permissions=PackedStringArray()
permissions/record_audio=false
```

`version/name="0.1.0"` matches `VERSION` and the iOS preset's
`application/short_version`. `version/code=1` is the integer Play orders builds
by; bump it on every upload.

`package/app_category=2` is `Game` (verified enum from the binary:
`Accessibility,Audio,Game,Image,Maps,News,Productivity,Social,Video,Undefined`).
`xr_features/xr_mode=0` is `Regular` (enum `Regular,OpenXR`).

`screen/support_small=false` is a small deliberate change from Godot's default:
`small` means <~3" screens, on which a 240x240-px-minimum child touch target
(`ART_BIBLE` §8, mirrored in `virtual_joystick.gd:105`) cannot physically fit.

`user_data_backup/allow=false` keeps the child's `user://profile.json` off
Google's cloud backup. That is consistent with "Local save only" in `CLAUDE.md`
and with the project's refusal to move child data anywhere, and it matches the
iOS preset's `user_data/accessible_from_files_app=false`.

`screen/immersive_mode=true` hides the status and navigation bars — correct for a
fullscreen landscape game, and it is also the single biggest mitigation for the
gesture-bar risk in section 4.

`screen/edge_to_edge=false` deserves a note: with `targetSdk 36` the *system*
draws the app edge-to-edge regardless of this flag. Leaving it `false` keeps
Godot from additionally opting in; whether the game then needs `true` is a
**device-verification question** (section 4) and I have not been able to settle it
locally.

### Two caveats on the block above, stated honestly

1. **Verified key names.** Every option key above was read out of the Godot
   4.7.2 binary's own option table (`strings` on
   `/Applications/Godot.app/Contents/MacOS/Godot`, matching the
   `package/`, `gradle_build/`, `launcher_icons/`, `screen/`, `permissions/`,
   `version/`, `keystore/`, `graphics/`, `xr_features/`, `user_data_backup/`,
   `command_line/`, `custom_template/`, `architectures/` prefixes). This is why
   there is **no `apk_expansion/*` block** — those options no longer exist in
   4.7.2, and pasting a remembered 3.x preset would have reintroduced dead keys.
   The two exceptions I could not string-match individually are
   `architectures/x86` and `architectures/x86_64`; both are set `false`, so if a
   name is off Godot silently drops it and re-adds the real key with the same
   `false` default. Harmless either way.
2. **`keystore/*` is intentionally omitted.** Godot resolves the debug keystore
   from Editor Settings when the preset leaves it blank, which is what you want:
   a keystore path baked into a committed `export_presets.cfg` is machine-specific
   and a release keystore path in a repo is a liability. Configure it per-machine
   (section 7).

**Safest way to apply:** add the preset once via *Project → Export → Add →
Android* in the editor (which writes canonical keys for this exact build), then
reconcile the **values** against the block above. Applying the block by hand also
works; the editor will normalise it on first open.

---

## 2. Permissions audit

### MEASURED: the built APK declares zero permissions.

This section used to be a prediction. It is now a measurement. From
`build/android/LittleDays-debug.apk`:

```
$ aapt2 dump xmltree --file AndroidManifest.xml LittleDays-debug.apk | grep -c "E: uses-permission"
0
```

**Zero `uses-permission` elements.** `aapt2 dump permissions` likewise prints
only the package name.

A grep for the word "permission" in the manifest returns two hits, and neither
is the app requesting anything — worth spelling out so nobody re-reads them as
permissions later:

- `android:grantUriPermissions="true"` on androidx's `FileProvider` — a flag
  about *granting* temporary URI access to others, not a permission request.
- `android:permission="android.permission.DUMP"` on androidx's
  `ProfileInstallReceiver` — this **restricts** the receiver, requiring any
  *caller* to hold DUMP. It grants this app nothing.

**What this says about the release build.** The previous revision warned that a
debug APK's permission list is not the shipping one, because Godot can add
`INTERNET` for the remote debugger. That warning is sound in general but did not
fire here: the debug list is already empty. Since the debug export is the one
that *adds* a permission, and it added none, the release export cannot have
more. The shipping permission set is **empty** — but it is cheap to re-check
with `aapt2` once a release keystore exists, and `export_android.sh` prints it
automatically, so re-check anyway.

The walk through the feature set below explains *why* that is the correct
answer, rather than a lucky one:

| Feature | Android permission | Needed? |
| --- | --- | --- |
| Rendering, touch, joystick | — | no permission exists or is needed |
| Local save (`user://profile.json`) | — | **no.** Godot's `user://` is app-internal storage. Scoped storage means no `READ_/WRITE_EXTERNAL_STORAGE` |
| `user://speech_diag.json` | — | same — app-internal |
| Audio **playback** (TTS, SFX) | — | **no.** Output never needs a permission |
| Text-to-speech | — | **no.** Android TTS is an IPC call to a system engine |
| Networking | `INTERNET` | **no.** Grep for `HTTPRequest`/`HTTPClient`/`StreamPeerTCP`/`WebSocket`/`http[s]://` across `game/scripts` and `game/scenes` returns **zero** hits. `CLAUDE.md`: "No network calls in gameplay code" — the code holds the line |
| Haptics | `VIBRATE` | **no** — nothing calls `Input.vibrate_handheld()` |
| Speech **recognition** | `RECORD_AUDIO` | **not yet — see below** |

### RECORD_AUDIO, specifically

**`permissions/record_audio` is set to `false` in the preset above, and that is
the correct setting today.** The reason is not caution, it is that the
permission would buy nothing:

There is **no Android speech implementation in this project at all.** The only
recognition backend is `game/scripts/speech/ios_speech_backend.gd`, which bridges
to a native Apple singleton named `LittleBuddySpeech`, built by
`ios/speech_plugin/` and linked against `Speech.framework` /
`AVFoundation.framework` by `game/addons/little_buddy_speech_export/` — whose
`_supports_platform()` is hard-coded:

```gdscript
func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform.get_os_name() == "iOS"
```

So an Android build has no microphone consumer whatsoever. Declaring
`RECORD_AUDIO` would mean an app that asks a parent for microphone access and
then never opens the microphone. On a children's app that is worse than a missing
feature — it is a privacy declaration you cannot justify, and it is exactly the
kind of thing a Families policy reviewer asks about.

**Add `permissions/record_audio=true` only in the same change that lands a
working Android recognition backend.** Not before. Section 3 covers what that
backend would be.

Note one Android detail that has no iOS analogue: Android has **no separate
"speech recognition" permission**. iOS needs two declarations
(`NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`, both
present at `game/export_presets.cfg:38,44`). Android needs only `RECORD_AUDIO`,
and it is a **runtime** permission (dangerous class) — `targetSdk 36` means the
system dialog appears on first use, not at install. Godot exposes
`OS.request_permission("android.permission.RECORD_AUDIO")` for that. Whatever
text is shown alongside it should be written for a parent, in the spirit of the
iOS strings already in the preset.

### Google Play Families policy — what would trip, and what already doesn't

Assessed against *Designed for Families* / *Families self-certified ads*, which
this app will be subject to because its audience is a four-year-old.

**Already clean, and worth keeping clean:**

- **No ads, no IAP, no analytics, no third-party SDKs.** `CLAUDE.md` Hard Scope
  forbids all of them and the code has none. This removes the single largest
  source of Families rejections (an ad SDK that is not in Play's certified list).
- **No `INTERNET`.** No network means no data transmission to disclose, which
  makes the Data Safety form close to empty and removes almost all COPPA/GDPR-K
  surface.
- **No external links, no purchase prompts** (`CLAUDE.md` Child UX) — Families
  policy prohibits leading children to external sites or unguarded purchases.
- **No persisted child audio.** `speech_service.gd` records counters only and
  `test_speech_privacy_guard.gd` forbids the autoload from even *holding* a
  transcript in a member variable. This is the strongest single thing in the
  project's favour in a policy review.
- **`user_data_backup/allow=false`** keeps child data out of Google cloud backup.

**Would trip, or needs care:**

1. **`RECORD_AUDIO` is a Data Safety disclosure, not just a manifest line.**
   The moment it is added, the Play Data Safety form must declare *Audio →
   Voice or sound recordings*, and for a Families app Google will look hard at
   it. The defensible answer — collected on-device, processed in memory, never
   stored, never transmitted — is *true here* and needs to be said in those
   words. Get it wrong and the listing is removed, not warned.
2. **On-device recognition must be provable.** Android's default
   `SpeechRecognizer` is a **cloud** service on many devices (section 3).
   Sending a child's voice to Google's servers would turn a currently-empty Data
   Safety form into a data-transmission disclosure and contradicts
   `CLAUDE.md`'s "No persisted/uploaded child microphone audio" and
   "Offline-first". **This is the single biggest Families-policy risk in an
   Android port**, and it is a design risk, not a paperwork one.
3. **Target audience & content declaration.** Selecting a child age band in Play
   Console mandates Families policy compliance, a privacy policy URL that is
   reachable, and Teacher/Expert-approved content claims if any are made. The
   privacy policy URL is an external asset this repo does not have.
4. **`package/show_in_android_tv=false`** is correct — a touch-and-voice game
   with a virtual thumbstick is not operable by a TV remote, and shipping it to
   the TV category invites a functionality rejection.
5. **Debug builds get `INTERNET` — CORRECTED: this one did not.** The claim
   above was reasoning from the exporter's string table, and the measurement
   contradicts it: the debug APK has no `INTERNET` and no permissions at all.
   The likely reason is that this preset uses the **prebuilt template** with
   `gradle_build/use_gradle_build=false`, so no manifest-merging Gradle build
   runs to inject it.

   The *habit* the original point recommends is still right — never present a
   debug APK's manifest as the shipping permission set without checking — so
   `tools/export_android.sh` still dumps the list after every build and still
   prints a reminder on debug builds. Keep the habit; drop the assumption.

---

## 3. Android speech — independent audit

Asked for an audit rather than an assumption. Here is the audit, and it found a
real bug.

### 3.1 The abstraction is well-shaped — genuinely provider-neutral

Credit where due. `game/scripts/speech/speech_backend.gd` is a clean, platform-free
interface: six signals, six methods, every one a safe no-op by default, no iOS
vocabulary anywhere in the file. `SpeechService` documents itself as a facade
whose consumers "depend only on this API — never on a concrete backend or native
plugin", and that promise is kept — every gameplay consumer I traced
(`feed_activity.gd:149`, `mode_handler.gd:476`, `house_level_director.gd:1568`,
`baby_room.gd`) reaches the service through `get_node_or_null("/root/SpeechService")`
and calls only `is_available()` / `has_permission()` / `start_listening()` /
`stop_listening()`. An `AndroidSpeechBackend extends SpeechBackend` would drop in
with **no gameplay change at all**. That is the hard part, and it is done.

### 3.2 There WAS one leaked iOS assumption, and it was a shipping bug — NOW FIXED

> **Status: fixed and under test.** `speech_service.gd` now guards with
> `OS.has_feature("mobile")`, which is true on iOS *and* Android, so an Android
> build selects the inert `SpeechBackend` and reports `unavailable`. Two tests
> pin it — `test_speech_never_mocks_on_device.gd` and
> `test_speech_privacy_guard.gd` — and both pass, alongside
> `speech_never_required` and `android_platform_guards`.
>
> Independently confirmed from the built APK: it contains **no** native speech
> library. The iOS `.gdextension` descriptor is packed as a plain asset but has
> no `arm64` Android entry, and the export log says so explicitly —
> `No "arm64" library found for GDExtension … littlebuddyspeech.gdextension`.
> So `Engine.has_singleton("LittleBuddySpeech")` is false on Android, the first
> branch cannot match, and the `mobile` branch takes it. The diagnostics panel
> will read `backend: unavailable`, **not** `mock`.
>
> The original finding is kept below, unedited, because it is the reason the
> guard is written the way it is and deleting it would invite the regression
> back.

The bug as originally found, at `game/scripts/speech/speech_service.gd:211-221`:

```gdscript
	if Engine.has_singleton(IosSpeechBackend.SINGLETON_NAME):
		_set_backend(IosSpeechBackend.new(), "ios")
		return

	if OS.has_feature("ios"):
		# Real iOS device/export without the native plugin present.
		# Never substitute the mock here — report unavailable honestly.
		_set_backend(SpeechBackend.new(), "unavailable")
		return

	_set_backend(MockSpeechBackend.new(), "mock")
```

The guard that protects a real device from the fake backend is
**`OS.has_feature("ios")`** — a test for *one specific platform*, not a test for
*"is this a real device?"*. On Android, `Engine.has_singleton("LittleBuddySpeech")`
is false and `OS.has_feature("ios")` is false, so control falls through to the
last line and **`MockSpeechBackend` is selected on a real Android device.**

The file's own comment says the intent exactly — *"Never substitute the mock
here — report unavailable honestly"* — and the header comment says *"Otherwise
(editor/macOS/desktop/etc.) → MockSpeechBackend"*. Android is neither editor nor
desktop. The intent is right; the condition is one platform too narrow.

What that produces on an Android build, concretely
(`mock_speech_backend.gd:12,36,49-63,90`):

```gdscript
var next_transcript: String = "milk"
...
func is_available() -> bool:
	return true
```

1. `SpeechService.is_available()` returns **true**, so
   `house_level_director._speech_available()` shows the **Speak button**
   (`house_hud.gd:452`) on a build with no speech support.
2. The child taps it. 0.6 s later, `MockSpeechBackend` emits the canned
   transcript **`"milk"`** — regardless of whether the child said anything, and
   regardless of whether the device even has a working microphone.
3. `IntentMatcher` matches it and the task completes. **A child "passes" every
   speaking task without speaking**, on every Android device, silently.
4. `describe_diagnostics()` would report `backend: "mock"` on an Android phone —
   so the on-device parent panel is the only place this is visible, and only to
   someone who knows what "mock" means.

This is not a cosmetic issue. It defeats the one guarantee the speech stack is
built around (never fake a recognition result on-device) and it teaches a child
that the microphone works when it does not.

**The one-line fix** (in a file I do not own, so proposed rather than applied):

```gdscript
	# Any real handheld device without a native provider must report
	# "unavailable" honestly. Testing for iOS alone let Android fall through to
	# the mock and fake a "milk" transcript on a real child's tablet.
	if OS.has_feature("mobile") or OS.has_feature("ios") or OS.has_feature("android"):
		_set_backend(SpeechBackend.new(), "unavailable")
		return
```

(`OS.has_feature("mobile")` is true on both iOS and Android exports; the two
explicit features are belt-and-braces and make the intent readable.)

A test to land in the same change — deliberately **not** added to
`game/tests/cases/` by me, because it would fail against the current code and I
will not leave a red suite in a file whose fix I am not permitted to make:

```gdscript
## MockSpeechBackend must never be reachable on a handheld platform.
func _test_mock_is_desktop_only():
	var failures: Array = []
	var file := FileAccess.open("res://scripts/speech/speech_service.gd", FileAccess.READ)
	var source: String = file.get_as_text()
	file.close()
	if not source.contains("has_feature(\"mobile\")") \
			and not source.contains("has_feature(\"android\")"):
		failures.append(
			"speech_service.gd guards the mock backend with an iOS-only test, so an "
			+ "Android build selects MockSpeechBackend and fabricates a transcript"
		)
	return failures
```

### 3.3 What is iOS-specific, and what an Android path would actually be

**iOS-specific (everything below is unusable on Android):**

| File | Why it is iOS-only |
| --- | --- |
| `game/scripts/speech/ios_speech_backend.gd` | bridges `Engine.get_singleton("LittleBuddySpeech")`, an Apple-only native singleton |
| `ios/speech_plugin/` | Objective-C/Swift against `SFSpeechRecognizer` + `AVAudioEngine` |
| `game/addons/little_buddy_speech_export/little_buddy_speech_export_plugin.gd` | `_supports_platform()` returns `platform.get_os_name() == "iOS"`; calls `add_ios_framework()` |
| `game/export_presets.cfg:38,44` | `NSSpeechRecognitionUsageDescription`, `privacy/microphone_usage_description` |

**Provider-neutral (reusable as-is):** `speech_backend.gd`,
`intent_matcher.gd`, `prompt_speaker.gd`, `speech_feedback.gd`,
`speech_feedback_binder.gd`, `speech_diagnostics_panel.gd`, and `speech_service.gd`
apart from the selection bug above. `SpeechService`'s diagnostics already write
`"platform": OS.get_name()` and would report `Android` correctly.

**What an Android backend would have to be.** There is no Godot built-in for
speech *recognition* (unlike TTS — see 3.5), so it means a **Godot Android plugin**
(Kotlin/Java `GodotPlugin`) wrapping `android.speech.SpeechRecognizer`, exposing
the same six signals so `AndroidSpeechBackend extends SpeechBackend` stays a thin
shim. Concretely that requires:

- `gradle_build/use_gradle_build=true` in the preset, the Android build template
  installed into `game/android/` (already gitignored), NDK `29.0.14206865`, and a
  Gradle build on every export — a materially heavier build than the
  template-only APK this document otherwise describes.
- `RECORD_AUDIO` in the manifest and a runtime permission request.
- A `<queries>` manifest entry for `android.speech.RecognitionService`, because
  `targetSdk 30+` package-visibility rules otherwise hide the recognizer.

### 3.4 Does it work offline? Not reliably — and this is the blocking issue

This is the finding that matters most, and I want to be precise about my
confidence. **`android.speech.SpeechRecognizer` is not guaranteed to be
on-device.** Its implementation is whatever `RecognitionService` the device
ships, typically Google's, and that has historically been a **network** service.
Android 13 (API 33) added `SpeechRecognizer.createOnDeviceSpeechRecognizer()` for
an explicitly on-device recognizer, and `EXTRA_PREFER_OFFLINE` is only a
*preference* on the standard path. On-device recognition additionally depends on
a downloaded language pack for the locale, and `en-US` availability varies by
OEM, region and device tier.

For this project that is a hard constraint, not a nuance. `CLAUDE.md` requires
"Offline-first", "No network dependency", and "No persisted/uploaded child
microphone audio". A recognizer that may stream a four-year-old's voice to a
server violates all three, and would drag `INTERNET` and a Data Safety
disclosure in with it (section 2).

So an honest Android speech path is:

1. `minSdk` would effectively need to be **33** for the speech feature (the app
   can stay at 24 and gate the feature), because only
   `createOnDeviceSpeechRecognizer()` gives a guarantee worth relying on.
2. Query `SpeechRecognizer.isOnDeviceRecognitionAvailable()` and the language
   pack, and **report `is_available() == false` whenever on-device recognition
   is not confirmed** — never silently fall back to the cloud path.
3. Which means: **on a large fraction of Android devices, speech will correctly
   be unavailable and the game will be a touch-only game.** That is the right
   outcome, and section 3.6 shows the game already handles it.

**I could not verify Godot's Android-side behaviour from local artifacts.** The
shipped `android_source.zip` is the Gradle template plus prebuilt AARs
(`libs/release/godot-lib.template_release.aar`); it contains no engine Java
sources, so claims in this section about `SpeechRecognizer` come from Android
platform knowledge and must be **confirmed on a real device** before anyone
commits to the feature.

**Recommendation: ship Android as touch-only.** Do not build an Android speech
backend for the first Android build. Fix the mock-selection bug so speech reports
`unavailable`, ship the game, and treat Android speech as a separate,
independently-scoped piece of work with the on-device constraint as its
acceptance criterion. `CLAUDE.md` already blesses this: *"Native iOS speech must
not block the MVP"* and *"Touch fallback must always work."*

### 3.5 TTS — the one piece of good news

`game/scripts/speech/tts_service.gd` uses **no native plugin at all**. It goes
through Godot's built-in `DisplayServer` TTS and gates every call on a live
capability check:

```gdscript
func _has_tts_feature() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
```

Godot implements that on Android via the platform `TextToSpeech` engine, so the
spoken English prompts — `CLAUDE.md` DoD item 6 — have a genuine chance of
working on Android with **zero new code and zero permissions**. Every call site is
guarded by `_tts_feature_supported`, so a device with no TTS engine degrades
quietly rather than crashing.

Two device-verification items, not desk-verifiable:
`DisplayServer.tts_get_voices_for_language("en")` must return a voice (a device
with no installed English voice will report the feature but offer nothing), and
Android TTS voice data may itself require a download. If TTS is silent the game
must still be playable — worth confirming on-device that a missing voice is a
quiet no-op and not a stall.

### 3.6 Does the fallback degrade correctly? Yes — this part is genuinely solid

The strongest existing guarantee in the project.
`game/tests/cases/test_speech_never_required.gd` drives **every shipped task and
every shipped mission to completion with no speech service in the context at
all**, and again against a `DeadSpeechService` that reports unavailable, denies
permission, and fails every listen attempt. It asserts:

- touch completes every task for the **same star reward** (`:122-126`),
- every mission completes start-to-finish by touch alone (`:154-196`),
- no shipped content declares `speechRequired` (`:68-83`),
- the Speak button is **not offered** when the mic is unusable (`:233-236`),
- pressing a stale Speak button does not start listening, does not hang, and
  still says something kind (`:239-245`),
- an unrelated transcript does not fail the task and the task stays playable
  (`:248-254`).

This is exactly the "no speech at all" condition an Android build lands in. I ran
the suite: this case passes. **So once the mock-selection bug is fixed, an
Android build is fully playable by touch with no speech whatsoever, and the code
path is already under test.** Until it is fixed, Android gets a *fake* speech
path instead of an honest absent one — which is worse than either.

---

## 4. Touch / safe area review

### What is already right

Three files implement the same platform-guarded inset read, and **all three
already name Android**:

- `game/scripts/ui/safe_area.gd:75-77`
- `game/scripts/camera/safe_area_insets.gd:97-99`
- `game/scripts/input/virtual_joystick.gd:439-459` (the guard itself at `:446`)

```gdscript
func _platform_reports_safe_area() -> bool:
	var platform: String = OS.get_name()
	return platform == "iOS" or platform == "Android"
```

They read `DisplayServer.get_display_safe_area()` and — importantly — convert
from physical window pixels to the stretched viewport space
(`safe_area.gd:64-70`, `virtual_joystick.gd:452-457`). That conversion is what
makes the handling device-agnostic rather than iPad-shaped, and it is the detail
most projects get wrong. There are no per-device constants anywhere.

`project.godot` stretches `canvas_items` with `aspect="expand"` from 1366x1024,
so viewport height is always 1024 and only width varies — which is why Android's
much wider aspect range costs less here than it would in a fixed-aspect layout.

I measured the joystick geometry across the Android landscape range by
re-implementing `activation_rect()` exactly and, separately, by calling the real
static function from a new test. **It holds everywhere it needs to:**

| Shape | viewport | zone right edge | Speak clearance limit | clears |
| --- | --- | --- | --- | --- |
| iPad 4:3 | 1365x1024 | 488.2 | 510.7 | yes |
| Android tablet 16:10 | 1638x1024 | 581.1 | 647.2 | yes |
| phone 18:9 | 2048x1024 | 644.0 | 852.0 | yes |
| phone 21:9 | 2389x1024 | 644.0 | 1022.7 | yes |
| phone 21:9 + 120 px left cutout | 2389x1024 | 740.0 | 1022.7 | yes |
| foldable inner 6:5 | 1229x1024 | 441.8 | 442.4 | **yes, by 0.6 px** |

### Concrete risks, with file:line

**R1 — The Speak-button clearance has ~0.6 px of margin on a square foldable.**
`virtual_joystick.gd:228-229`:

```gdscript
	var centre_limit: float = viewport_size.x * 0.5 - HUD_SPEAK_HALF_WIDTH - CENTRE_CLEARANCE
	width = minf(width, maxf(centre_limit - left, MAX_RADIUS * 2.0))
```

At a 6:5 inner foldable display the joystick's activation zone ends 0.6 px from
the Speak button's left edge. It does not overlap — but nothing in the code
*intends* 0.6 px, and any nudge to `ZONE_WIDTH_RATIO` (`:130`),
`HUD_SPEAK_HALF_WIDTH` (`:141`) or `CENTRE_CLEARANCE` (`:144`) turns it into an
overlap on a device class nobody here tests. Now covered by
`game/tests/cases/test_android_platform_guards.gd` so it cannot regress silently.

**R2 — `maxf(..., MAX_RADIUS * 2.0)` is a floor that can overlap Speak.**
Same two lines. When `centre_limit - left < 264`, the `maxf` wins and the zone is
allowed to extend **past** the Speak button. I measured the crossover at viewport
width ≈ 920 px, i.e. aspect ≈ 0.9 — portrait or a narrow split-screen. Landscape
Android never reaches it, and the stock manifest's
`android:resizeableActivity="false"` plus `screenOrientation="sensorLandscape"`
should keep the app out of that range. **But:** Android 12+ can ignore
`resizeableActivity=false` on large screens and place the app in
multi-window/letterbox compatibility mode, and OEM desktop modes (Samsung DeX,
ChromeOS) resize freely. Worst case the joystick sits under the Speak button and
a thumb press does one thing while looking like it does another — the most
confusing possible failure for a four-year-old. Mitigation: prefer the real
clamp over the floor, or explicitly suppress the joystick below a minimum
viewport width.

**R3 — Gesture navigation is a *touch* hazard, not only a layout one.**
Android's gesture-nav bar reserves a swipe region along the bottom edge — and in
landscape, along the bottom of a very wide screen — where the system consumes the
gesture before the app sees it. `virtual_joystick.gd:240-245` places the resting
thumb hint at the **bottom-left**, which is exactly where a landscape gesture
back-swipe lives on many devices:

```gdscript
static func rest_origin(zone: Rect2) -> Vector2:
	var inset: float = MAX_RADIUS + KNOB_RIM_WIDTH * 4.0
```

The safe-area read *should* push the zone clear of it, but only if Godot's
Android `get_display_safe_area()` actually reports gesture insets — which is
precisely the thing I could not verify locally (the shipped AAR has no Java
sources). `screen/immersive_mode=true` is the main mitigation. **Device
verification required:** hold the tablet both ways up, drive the stick from the
bottom-left corner, and confirm no system gesture fires.

**R4 — Display cutouts intrude on the *long* edge in landscape.** On iPad this
barely exists; on an Android phone held in landscape the cutout is on a short
edge (left or right depending on which way up), which is why the audit above
tests both `cutout left` and `cutout right`. `sensorLandscape` means a child
flips the device and the unsafe edge *moves*. The inset code recomputes on
`NOTIFICATION_RESIZED` (`safe_area.gd:34-37`) and on `viewport.size_changed`
(`:29-31`). A 180° flip may not change the viewport size at all — so whether
Godot emits a resize notification on a same-size rotation is a **device
verification item**. If it does not, the HUD keeps yesterday's insets and drifts
under the cutout until something else triggers a relayout.

**R5 — `edge_to_edge` + `targetSdk 36`.** Android 15+ enforces edge-to-edge for
apps targeting 35+, so the app is drawn under the system bars whether or not it
asks. Everything then depends on `get_display_safe_area()` being correct on
Android. This is the highest-value single thing to check on a real device.

**R6 — Desktop-vs-device divergence is by design and hides Android bugs.**
`safe_area.gd:9-13` deliberately ignores the platform safe area anywhere that is
not iOS/Android, because macOS reports it in screen rather than window
coordinates. Correct — but it means **no amount of macOS testing exercises the
Android path**, and `test_robust_session.gd:18` documents insets as
`Vector4.ZERO` on every platform but those two. The new test pins the guard and
the geometry; it cannot substitute for one run on real glass.

### What I added

`game/tests/cases/test_android_platform_guards.gd` — passes now, and pins:

1. all three safe-area guards still name `"Android"` and still branch on
   `OS.get_name()` (deleting the Android half is a silent, crash-free regression);
2. the joystick clears Speak and stays inside the safe area across 7 Android
   landscape shapes x 4 realistic inset profiles (28 combinations), including
   left/right cutouts and a tall gesture bar;
3. the rest origin stays inside its own activation zone;
4. `SpeechBackend` — what Android falls back to — answers every question "no",
   always emits `permission_result` and `recognition_failed` so no caller hangs,
   and **never invents a transcript**.

Suite result: `[PASS] android_platform_guards`, in a run of
`FAIL - 106 case(s), 1 failure(s)`. That single failure is **pre-existing and
unrelated** — `[FAIL] baby_avatar`, a GLB export-naming assertion
(*"baby_life_clips.gd names the raw export babyLittleBuddy_v01.glb"*) in another
agent's area. Note that the suite was moving underneath these runs as other
agents authored files concurrently (case count went 103 → 106 across three runs,
and one intermediate run reported transient failures that did not reproduce), so
treat the count as a snapshot rather than a baseline.

---

## 5. Icon and app name

### What exists for iOS

`tools/make_ios_icons.sh` cuts every iOS slot from `game/icon_1024.png` with
`sips`, locally and losslessly — sizes 40, 58, 76, 80, 120, 152, 167, 180, 1024
into `game/assets/icon/ios/`. All nine exist. Its comment explains the choice
well: Godot *would* synthesise the small icons at export time, but an icon's
whole job is to be legible at 40 px, so they are cut deliberately and checked by
eye. `game/export_presets.cfg:46-58` wires each slot.

### What Android needs — four PNGs, none of which exist

Verified against the 4.7.2 exporter's own option table and the resource layout
inside `godot-lib.template_release.aar` (which ships
`res/mipmap-{m,h,xh,xxh,xxxh}dpi-v4/` plus `res/mipmap-anydpi-v26/icon.xml` and
`themed_icon.xml`):

| Preset option | Size | Purpose | Exists? |
| --- | --- | --- | --- |
| `launcher_icons/main_192x192` | **192x192** | legacy square launcher icon (pre-API-26 and fallback) | **no** |
| `launcher_icons/adaptive_background_432x432` | **432x432** | adaptive icon **background** layer | **no** |
| `launcher_icons/adaptive_foreground_432x432` | **432x432** | adaptive icon **foreground** layer | **no** |
| `launcher_icons/adaptive_monochrome_432x432` | **432x432** | Android 13+ themed/monochrome icon (optional) | **no** |

Godot generates the five density buckets from these; you supply one PNG per slot,
not per density. No art has been generated (correctly out of scope).

**The adaptive-icon constraint that matters, and that a naive crop will fail:**
an adaptive icon is a 432x432 canvas of which the launcher may mask, crop and
*parallax* anything outside the central **safe zone — a circle of diameter 264 px,
centred**. Outside it, content can be clipped by a circle, squircle, rounded
square or teardrop depending on the launcher, and is also what animates during
the icon-wobble. So:

- **Foreground:** the logo mark only, transparent background, with all meaning
  inside the centred 264 px circle — roughly the middle 61%. Simply resizing
  `game/icon_1024.png` to 432x432 **will crop the artwork on most launchers**,
  because the iOS icon is designed to fill a squircle edge to edge.
- **Background:** a full-bleed 432x432 opaque layer, no transparency, no detail
  (a flat colour or a soft wash). The project already has an obvious candidate:
  `Color(1, 0.964706, 0.878431, 1)` — the cream used for
  `boot_splash/bg_color` in `project.godot` and `storyboard/custom_bg_color` in
  the iOS preset.
- **Monochrome:** the silhouette on transparency, same safe zone. Optional; the
  preset above leaves it `""`, which is fine.
- **192x192 legacy:** may be full-bleed like the iOS icon, since nothing masks it
  beyond a rounded corner.

**Therefore `tools/make_ios_icons.sh` cannot be reused.** It is a pure
`sips -Z` downscale, which produces exactly the "resized iOS icon" that fails the
safe zone.

### The icons now exist — GENERATED, from existing art

Three of the four slots are filled, in `game/assets/icons/android/`:

| File | Size | Contents |
| --- | --- | --- |
| `icon_192.png` | 192x192 | the mark on flat cream, full-bleed |
| `icon_adaptive_background_432.png` | 432x432 | flat cream `#FFF6E0`, opaque, no detail |
| `icon_adaptive_foreground_432.png` | 432x432 | the mark on transparency, centred |
| *(monochrome)* | — | deliberately left empty, see below |

**Source and method.** No new artwork was invented. The source is
`docs/reference/aliz_reference_v1.png` — Aliz on a plain white field. A
full-body render is illegible at 192 px, so the generator crops to
head-and-shoulders, which is the only part that survives the size.

The white field is removed with a **border flood-fill**, not a global white key.
That distinction is the whole trick: a global "make near-white transparent" pass
would also punch holes through the **eye whites**, because the sclera is exactly
as white as the background. Flooding inward from the border only reaches the
outside, so interior whites survive. Edge pixels get partial alpha so the cut is
not aliased, and the downscale averages **premultiplied** alpha to avoid a white
fringe. Verified by eye on the output, not just asserted.

**Safe zone.** The mark is scaled to 236 px and centred on the 432 px canvas, so
the face sits well inside the guaranteed centred **264 px circle**. The corners
of that 236 px square fall outside the circle, but they are transparent or hair
edge — nothing meaningful is clipped by a circular, squircle or teardrop mask.

The background is a flat wash of `Color(1, 0.964706, 0.878431, 1)` — the same
cream as `boot_splash/bg_color` in `project.godot` and the iOS
`storyboard/custom_bg_color`, so the launcher icon, the splash and the iPad app
agree.

**Monochrome is intentionally empty.** Android 13+ themed icons want a
silhouette, and a silhouette of a head with long hair reads as an unrecognisable
blob. When the slot is empty the launcher falls back to the full adaptive icon,
which looks considerably better. This produces one benign `aapt2` warning —
*"resource mipmap/themed_icon … no such path exists"* — which is a dangling row
in the resource table left by Godot's template. Nothing references it: the
manifest's `android:icon` points at `mipmap/icon`, whose `icon.xml` declares
only `<background>` and `<foreground>`. Verified by dumping the XML. It cannot
be resolved at runtime and so cannot fail.

**The generator was not committed to `tools/`**, because this sprint's file
ownership did not extend there. It is ~170 lines of dependency-free Python built
on the existing `tools/png_edit.py` (which gained no changes). To re-cut the
icons — after new art, or to add a monochrome layer — the logic is: load →
RGBA → border flood-fill white key → crop `(330, 0, 350, 345)` → pad to square →
premultiplied box-downscale → centre-composite. Promoting it to
`tools/make_android_icons.py` is a reasonable follow-up.

### App name

- iOS/Android bundle id: `com.pointit.littlebuddy` (unchanged, both platforms).
- `project.godot` `config/name`: `"Little Buddy"`.
- Android launcher label: the preset sets `package/name="Little Days"` **as
  instructed** — and see the warning in section 1. The string "Little Days"
  appears **nowhere else in this repository**. Setting `package/name=""` makes
  Godot use `config/name` and keeps the platforms in sync; that is the
  lower-risk option if the rename is not intentional.

The Android label lands in the manifest via
`<application android:label="@string/godot_project_name_string">` (verified in the
template manifest and in the exporter's
`res/values/godot_project_name_string.xml` handling).

---

## 6. `tools/export_android.sh`

Created. It is a preflight-then-export script that checks all eight
prerequisites, collects **every** failure rather than dying on the first, and
prints a numbered blocking list with copy-pasteable install commands. It exits
non-zero and exports nothing when anything is missing.

```
tools/export_android.sh [debug|release] [--install] [--check]
```

Checks: Godot binary · Android export templates for the exact editor version ·
JDK 17 (`JAVA_HOME`, then `/usr/libexec/java_home`, then `PATH`) · Android SDK
with `build-tools/*/apksigner` and `platforms/android-36` · NDK
`29.0.14206865` (**warning only** — a template APK export needs no NDK; only a
Gradle/custom build does) · debug keystore in either standard location · Godot's
**Editor Settings** `android_sdk_path` and `java_sdk_path` (Godot ignores
`ANDROID_HOME`, which is a common and confusing failure) · the `Android` preset
in `export_presets.cfg` · `adb` and a visible device, only when `--install` is
passed.

After a successful build it runs `aapt2 dump permissions` on the APK and prints
the real permission list, because of the debug-`INTERNET` trap in section 2.

### It was run, and it now passes. Actual output, unedited:

```
==> Little Buddy Android export preflight (debug)

  ok    Godot: /Applications/Godot.app/Contents/MacOS/Godot (4.7.2.stable.official.ed1daf0bf)
  ok    export templates: .../export_templates/4.7.2.stable (android_debug.apk present)
  ok    JDK: /Users/hotkhwan/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home/bin/java (major 17, need >= 17)
  ok    Android SDK: /Users/hotkhwan/Library/Android/sdk
  ok    apksigner: /Users/hotkhwan/Library/Android/sdk/build-tools/36.1.0/apksigner
  ok    platform: android-36 (compileSdk 36)
  warn  NDK 29.0.14206865 not installed
  ok    debug keystore: /Users/hotkhwan/Library/Application Support/Godot/keystores/debug.keystore
  ok    editor setting export/android/android_sdk_path = /Users/hotkhwan/Library/Android/sdk
  ok    editor setting export/android/java_sdk_path = /Users/hotkhwan/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
  ok    export preset "Android" present in export_presets.cfg

All preflight checks passed.
```

The single remaining `warn` is correct and is not a blocker: a template APK
export ships prebuilt native libraries and needs no NDK. It becomes a blocker
only if `gradle_build/use_gradle_build` is ever turned on.

Then the export branch — which had never executed before — ran to completion:

```
==> Built /Users/hotkhwan/Projects/little-buddy/build/android/LittleDays-debug.apk ( 35M)

==> Permissions actually declared in the APK:
    (none -- the APK declares no permissions at all)
```

### Two fixes made to the script while proving it

1. **`OUT_APK` is now mode-suffixed** — `LittleDays-$MODE.apk`. It was a single
   `LittleBuddy.apk` for both modes, so a debug build would silently overwrite a
   release one. Those two artifacts are not interchangeable: the debug APK is
   `android:debuggable=true` and signed with a throwaway key.
2. **The empty-permission case printed silence.** The old line was
   `... | grep -E ... | sed ... || echo "(none)"`. `sed` exits 0 even with no
   input, so the `||` could never fire and a clean, permission-free APK produced
   *no output at all* — indistinguishable from the check having failed to run.
   For a children's app the difference between "nothing printed" and "asks for
   nothing" is the whole point of the check, so the result is now captured and
   stated explicitly.

### What this output proves, and what it does not

It proves the checks fire, the paths resolve, the export branch works, and the
APK is signed and permission-free. It proves **nothing whatsoever** about how
the game behaves on Android hardware. Section 9 remains entirely untested.

---

## 7. Reproducing the toolchain — the commands that were actually run

These are not suggestions; this is the transcript of what produced the APK, on
Apple Silicon / zsh. **None of it needs sudo.** Steps 1-4 are one-time.

Setting `ANDROID_HOME` / `JAVA_HOME` in the shell is convenient but is NOT what
makes the export work — Godot reads its own Editor Settings (step 5).

**Reproduced on the MacBook on 2026-09-20.** The commands are unchanged; the
three corrections found while reproducing are marked **MacBook 2026-09-20**.

### Step 1 — JDK 17, user-local, no admin password

Godot 4.7.2's build template pins `javaVersion JavaVersion.VERSION_17`
(`config.gradle`). Newer JDKs are not a safe substitute.

The documented route used to be `brew install --cask temurin@17`, which invokes
a `.pkg` installer and **prompts for an administrator password**. That is a hard
stop for an unattended build. The tarball needs no such thing, and
`/usr/libexec/java_home` finds a JDK under `~/Library/...` exactly as it finds
one under `/Library/...` (verified on this machine):

```bash
mkdir -p ~/Library/Java/JavaVirtualMachines
curl -L -o /tmp/jdk17.tar.gz \
  "https://api.adoptium.net/v3/binary/latest/17/ga/mac/aarch64/jdk/hotspot/normal/eclipse?project=jdk"
tar xzf /tmp/jdk17.tar.gz -C /tmp
mv /tmp/jdk-17* ~/Library/Java/JavaVirtualMachines/temurin-17.jdk

/usr/libexec/java_home -v 17     # -> .../temurin-17.jdk/Contents/Home
java -version                    # (with JAVA_HOME set) openjdk version "17.0.20.1"
```

Use `mac/x64` instead of `mac/aarch64` on an Intel Mac.

### Step 2 — Android SDK, user-local, licences accepted non-interactively

```bash
SDK="$HOME/Library/Android/sdk"          # where Godot's settings already pointed
mkdir -p "$SDK/cmdline-tools"
curl -L -o /tmp/cmdline-tools.zip \
  https://dl.google.com/android/repository/commandlinetools-mac-13114758_latest.zip
unzip -q /tmp/cmdline-tools.zip -d /tmp/clt
mv /tmp/clt/cmdline-tools "$SDK/cmdline-tools/latest"

export JAVA_HOME="$HOME/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home"
export ANDROID_HOME="$SDK"
export PATH="$JAVA_HOME/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PATH"

yes | sdkmanager --sdk_root="$SDK" --licenses
yes | sdkmanager --sdk_root="$SDK" 'platform-tools' 'platforms;android-36' 'build-tools;36.1.0'
```

`sdkmanager` needs a JDK, so step 1 must come first. The `yes |` is the standard
unattended licence acceptance — the licences are Google's and are accepted, not
bypassed.

**The NDK is NOT needed** and was not installed. A template APK export ships
prebuilt native libraries. Install it only when turning on
`gradle_build/use_gradle_build` (a custom build, or an Android plugin such as a
speech backend):

```bash
sdkmanager 'ndk;29.0.14206865'   # exact version pinned by Godot 4.7.2
```

`gradle` is likewise not required and is not installed.

### Step 3 — Godot Android export templates

**Already installed**, and they are the slowest item, so this is a real saving.
Verify rather than re-download:

```bash
ls ~/Library/Application\ Support/Godot/export_templates/4.7.2.stable/android_*.apk
```

Only needed again after a Godot version bump — the version string must match the
editor exactly.

### Step 4 — Debug keystore

```bash
mkdir -p ~/Library/Application\ Support/Godot/keystores
keytool -keyalg RSA -genkeypair -alias androiddebugkey \
  -keypass android \
  -keystore ~/Library/Application\ Support/Godot/keystores/debug.keystore \
  -storepass android \
  -dname 'CN=Android Debug,O=Android,C=US' \
  -validity 9999 -deststoretype pkcs12
```

**Check before you run this.** If a keystore already exists at that path or at
`~/.android/debug.keystore`, do **not** overwrite it — regenerating changes the
signing identity, and Android then refuses to upgrade an already-installed app
(`INSTALL_FAILED_UPDATE_INCOMPATIBLE`); it must be uninstalled first.

It deliberately lives **outside the repository**. `.gitignore` also blocks
`*.keystore`, `*.jks`, `*.p12`, `*.pepk` and `keystore.properties` as
belt-and-braces. A committed keystore is an unrevocable credential leak, and a
committed *release* keystore means permanently losing the ability to update the
app on Play. **A debug keystore is for local installs only and must never sign a
Play Store build.**

### Step 5 — Godot Editor Settings (the step people skip)

**Godot does not read `ANDROID_HOME` or `JAVA_HOME`.** It reads
`~/Library/Application Support/Godot/editor_settings-4.7.tres`. On this machine
that file already contained an `android_sdk_path` pointing at a directory that
did not exist and an empty `java_sdk_path` — so a GUI export would have failed
with a confusing path error rather than an obvious "no SDK" one.

Set via *Editor → Editor Settings → Export → Android*, or edit the file
(**close the editor first — it rewrites the file on exit**):

```ini
export/android/android_sdk_path = "/Users/<you>/Library/Android/sdk"
export/android/java_sdk_path = "/Users/<you>/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home"
export/android/debug_keystore = "/Users/<you>/Library/Application Support/Godot/keystores/debug.keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
```

Resolve every path to a literal — the `.tres` is not a shell script. Note Godot
re-serialises this file and drops settings left at their default, so
`debug_keystore_user` may vanish after the editor next runs; that is harmless,
because the value it dropped *is* the default.

**MacBook 2026-09-20 — the settings-file race.** *Every* Godot process that
loads the editor — including `godot --headless --import` and the headless test
runner — reads this file at start and **rewrites it from memory on exit**. If
any such process was already running when you edited the file, your edit is
silently reverted the moment it exits. This happened here: `java_sdk_path` was
set, and a headless import another agent had started earlier put `""` back.
So: edit the file when no Godot process is running (`pgrep -fl MacOS/Godot`),
and always run `tools/export_android.sh --check` immediately before an export —
it reads the file, not your memory of it. Back the file up first
(`cp -p editor_settings-4.7.tres editor_settings-4.7.tres.bak`).

### Step 6 — The export preset

Already applied — `[preset.1]` in `game/export_presets.cfg` (section 1).

### Step 7 — Verify, then build

```bash
cd /Users/hotkhwan/Projects/little-buddy
tools/export_android.sh --check           # prints "All preflight checks passed."
tools/export_android.sh debug             # -> build/android/LittleDays-debug.apk
```

### Step 8 — Install on a device

**Not done — there is no device.** These commands are untested here:

```bash
# On the device: Settings > About > tap Build number 7x, then
# Settings > System > Developer options > USB debugging
adb devices                               # must list the device as "device"
tools/export_android.sh debug --install
```

### Step 9 — The Gradle build and the .aab (MacBook 2026-09-20)

Google Play only accepts an **Android App Bundle**, and Godot only produces one
through the Gradle build (`gradle_build/use_gradle_build=true`,
`gradle_build/export_format=1`). That needs two things the plain APK path does
not, both sudo-free:

```bash
# 1. the NDK Godot 4.7.2 pins (config.gradle) -- 1.05 GB download, 3.1 GB installed
yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" 'ndk;29.0.14206865'

# 2. the Android build template, unpacked INTO THE PROJECT (game/android/ is git-ignored)
GAME=/Users/hotkhwan/Projects/LittleBuddy-latest/game     # or your worktree's game/
TPL=~/Library/Application\ Support/Godot/export_templates/4.7.2.stable
mkdir -p "$GAME/android/build"
unzip -q -o "$TPL/android_source.zip" -d "$GAME/android/build"
printf '4.7.2.stable\n' > "$GAME/android/.build_version"   # NEXT TO build/, not inside it
printf '\n'             > "$GAME/android/build/.gdignore"   # stop the editor importing the template's assets
printf 'build/\n'       > "$GAME/android/.gitignore"
```

Two things learned the hard way:

- `godot --headless --install-android-build-template` **hangs** in 4.7.2 (it
  waits on an editor dialog that never appears). Kill it and unpack by hand as
  above; that is all the menu item does.
- `.build_version` must be at `android/.build_version`. Putting it inside
  `android/build/` produces *"Trying to build from a gradle built template, but
  no version info for it exists"*. And without `android/build/.gdignore` the
  editor warns *"Detected another project.godot at
  res://android/build/src/instrumented/assets"* and imports the template's
  test assets into `.godot/`.

The **committed preset stays a plain-template APK preset** on purpose — the
APK path needs neither of the above. `tools/export_android.sh --aab` patches
the two `gradle_build` keys into a *temporary copy* of `export_presets.cfg`
for the one export and restores the file on every exit path (verified: the
file's sha256 is identical before and after, including after a failed build).
Gradle itself (8.11.1, from the wrapper) and its dependency cache land in
`~/.gradle` on the first build.

```bash
tools/export_android.sh --check --aab      # NDK + build template + everything above
tools/export_android.sh debug --aab        # debug-signed .aab: proves the pipeline, NOT uploadable
tools/export_android.sh release --aab      # the Play artefact; refused without the owner's key:
#   export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=...   (outside the repo)
#   export GODOT_ANDROID_KEYSTORE_RELEASE_USER=...
#   export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=... (read -s; never on disk, never in git)
```

Godot 4.7 reads those three variables whenever the preset's
`keystore/release`, `keystore/release_user`, `keystore/release_password` are
empty — they were added to the preset as empty strings so that this fallback is
explicit and the editor GUI shows the fields. The script refuses a release
build if the variables are missing, if the path ends in `debug.keystore`, if
the keystore is inside the working tree, or if a path has been written into
the preset. See `docs/GOOGLE_PLAY_RELEASE_READINESS.md` §8 for the owner's
one-time key creation.

**Result of the debug `--aab` runs on the MacBook, measured:**

| | |
| --- | --- |
| First run (cold `~/.gradle`) | 3 min 08 s, of which almost all was Gradle 8.11.1 + AGP 8.6.1 + Kotlin 2.1.21 downloads → `~/.gradle` = **1.2 GB** |
| Warm run | **56 s** end to end |
| Output | `build/android/LittleDays-debug.aab`, 36,495,426 bytes, sha256 `bd7cc54aa1c1f47a1457f352ac3a633777e2fc6b372fe1ae490524cda25cc5c9` |
| Preset after the run | sha256 identical to before (`98a19fd9…b239`), on success and on the earlier failed run alike |
| Bundle manifest (bundletool 1.18.3, run from a scratch dir, not installed) | package `com.pointit.littlebuddy`, versionCode 1 / 0.1.0, targetSdk 36, **zero `uses-permission`**, `debuggable=true` (debug build), `allowBackup=false`, `isGame=true`, `screenOrientation=11`, `extractNativeLibs=false`, `base/lib/arm64-v8a/` only |

Two findings that are **not** in the Godot docs:

1. **The bundle comes out of Gradle unsigned.** Godot passes
   `-Pperform_signing=true` plus the debug keystore (verified in
   `export_plugin.cpp` 4.7.2-stable, and by re-running Gradle by hand with the
   same properties); Gradle runs `:signStandardDebugBundle`; and the resulting
   `.aab` has no `META-INF/*.SF` and no signing block — `jarsigner -verify`
   says *jar is unsigned*. Godot does not sign the bundle after Gradle either.
   I did not find the cause inside AGP 8.6.1 in the time available. The script
   now **verifies every bundle and, if unsigned, signs it with `jarsigner`**
   (debug key for `debug`, the `GODOT_ANDROID_KEYSTORE_RELEASE_*` key for
   `release`, password via `-storepass:env`), then re-verifies and refuses to
   finish unless `jar verified` — `jarsigner` is the tool Google's own Play App
   Signing page names for this. `bundletool validate` passes on the re-signed
   bundle. **Check the release bundle's signature yourself before uploading**
   (`jarsigner -verify -verbose:summary -certs LittleDays-release.aab`).
2. **The Gradle build sets `minSdkVersion 29`, not 24.** The prebuilt-template
   APK says 24 because its manifest is fixed. For a Gradle build Godot 4.7.2
   computes the default min SDK as `VULKAN_MIN_SDK_VERSION = 29` whenever the
   mobile renderer runs on Vulkan (`_uses_vulkan()`: `rendering_method.mobile`
   is `mobile` and `driver.android` is `vulkan` — both true for this project),
   and `gradle_build/min_sdk` is empty. So **the Play artefact will require
   Android 10+**. That is Godot's recommendation for Vulkan 1.1, not an
   accident; it is left as is. Setting `gradle_build/min_sdk="24"` would
   override it (with an editor warning unless
   `rendering/rendering_device/fallback_to_opengl3` is on), and is a product
   decision for the owner, not something to change silently.

---

## 8. Status list

### Resolved

1. ~~No JDK 17~~ — Temurin 17.0.20.1, user-local, no sudo. (step 1)
2. ~~No Android SDK~~ — cmdline-tools, platform-tools, build-tools 36.1.0,
   platforms;android-36, licences accepted. (step 2)
3. ~~No debug keystore~~ — generated outside the repo, git-ignored. (step 4)
4. ~~Godot Editor Settings wrong~~ — both paths now resolve. (step 5)
5. ~~No Android export preset~~ — `[preset.1]` applied, iOS preset untouched and
   byte-identical. (section 1)
6. ~~No Android launcher icons~~ — 192 + two 432 adaptive layers generated from
   existing art, safe-zone-correct. (section 5)
7. ~~`speech_service.gd` selects `MockSpeechBackend` on Android~~ — fixed with an
   `OS.has_feature("mobile")` guard and pinned by two tests. (section 3.2)
8. ~~App name "Little Days" appears nowhere in the repo~~ — the rename landed;
   `config/name="Little Days"` and the APK label matches. (section 1)

### Still open (2026-09-20 additions first)

- **No release keystore** — owner must create it; the script refuses to sign a
  release with anything else. (step 9)
- **No Play Console app / privacy policy / store graphics / Android
  screenshots** — `docs/GOOGLE_PLAY_RELEASE_READINESS.md` §§4-6, 10.
- **`test_version.gd` does not cover the Android preset.** It pins
  `application/short_version` and `application/version` (iOS) against
  `VERSION`; the Android `version/name` (and the `version/code` that Play needs
  bumped on every upload) is unguarded. Not fixed here — tests are outside this
  worktree's ownership.
- The **debug keystore differs per machine** (Mac Mini vs MacBook). A phone
  that has one machine's build must `adb uninstall com.pointit.littlebuddy`
  before it accepts the other's (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).

9. **No Android device.** Nothing in section 9 has been verified. This is now
   *the* blocker, and it is not a software one — it needs hardware. Everything
   above only proves a file was produced.
10. **No release build.** Only a debug APK exists. A release build needs a
    **release** keystore, which is a credential the owner must create and hold;
    it was deliberately not generated here. The permission set is expected to
    stay empty (section 2) but should be re-dumped once it exists.
11. **Android speech recognition is not proven offline-capable.** Ship Android
    touch-only and scope it separately, with on-device recognition as the
    acceptance criterion. The game is fully playable without it — that path is
    under test (`test_speech_never_required.gd`). (section 3.4)
12. **Joystick clearance risks R1/R2** — 0.6 px of margin on a square foldable,
    and a floor that can overlap Speak below ~920 px viewport width. Pinned by
    `test_android_platform_guards.gd`, but only device use will show whether it
    matters. (section 4)
13. **Play Store readiness is untouched** — no Play Console app, no privacy
    policy URL, no Data Safety form, no target-audience declaration. (section 2)

### Files this work touched

`game/export_presets.cfg` (append-only: 60 insertions, 0 deletions),
`tools/export_android.sh`, `docs/ANDROID_READINESS.md`, `.gitignore`
(append-only), and three new PNGs under `game/assets/icons/android/`.

`game/project.godot` and everything under `game/scripts/`, `game/scenes/` and
`game/content/` were **not modified** — in particular the speech files, which
were read to verify the fix and left alone. **Nothing was committed.**

Machine state changed outside the repo (deliberately, and not in git): the JDK,
the Android SDK, the debug keystore, and Godot's editor settings.

---

## 9. What must be verified on a real device — NONE OF IT DONE

There is no Android device and no emulator, so **every item below is untested**.
This list is the honest remainder of the work. Nothing earlier in this document
substitutes for it. In priority order:

1. **Speech reports `unavailable`, not `mock`.** Open the parent speech
   diagnostics panel. It must read `backend: unavailable`. Reading `mock` would
   mean a child can pass speaking tasks without speaking. The code now guards
   this with `OS.has_feature("mobile")`, two tests pin it, and the APK provably
   contains no Android speech library — but the panel on real glass is the only
   end-to-end proof. **Check this first.**
2. **Touch-only playthrough.** Complete Mission 01 and Snack Time start to
   finish without ever pressing Speak. Stars must be awarded identically.
3. **Speak button absent.** With speech unavailable it must be hidden, not
   greyed (`house_hud.gd:452`, `test_speech_never_required.gd:233`).
4. **TTS speaks.** Confirm English prompts are audible (`CLAUDE.md` DoD 6). TTS
   goes through Godot's built-in `DisplayServer`, needs no permission and no
   plugin, so it has a genuine chance of working — but it depends on an
   installed English voice. If silent, confirm that silence is a quiet no-op and
   not a stall.
5. **Safe area, both ways up.** The manifest sets `sensorLandscape`
   (`screenOrientation=11`, confirmed in the APK), so a child flipping the
   tablet moves the unsafe edge. No HUD control may sit under a cutout or the
   gesture bar in either orientation (risks R3-R5). With `targetSdk 36` Android
   enforces edge-to-edge, so this rests entirely on
   `DisplayServer.get_display_safe_area()` being correct on Android — the single
   highest-value thing to check.
6. **Joystick in the bottom-left corner.** Drive from the extreme corner and
   confirm no system back-gesture fires (risk R3).
7. **Launcher icon.** Confirm the adaptive icon is not clipped badly under a
   circular *and* a squircle mask, and that the legacy 192 icon looks right on
   an older launcher. Icons were checked by eye as flat images only.
8. **Release permission list.** Once a release keystore exists, `aapt2 dump
   permissions` on the **release** APK must show none. The debug APK already
   shows none (section 2), so this should be a formality.
9. **Performance.** Mobile renderer, one `DirectionalLight3D`, 1024 shadow map.
   Android tablets are weaker than the target iPad, and `arm64-v8a` is the only
   ABI shipped. Measure the frame rate on the real thing.

**Do not mark any of these as passed on the strength of this document.** A
signed APK on a Mac is a file, not a playtest.
