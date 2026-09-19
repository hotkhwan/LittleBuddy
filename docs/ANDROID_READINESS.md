# Android Readiness

## STATUS: NO APK WAS PRODUCED. ANDROID HAS NEVER BEEN BUILT OR RUN.

This document is preparation and an audit. It is **not** a claim of readiness.

Nothing here has been validated on an Android device, in an emulator, or by a
successful build, because the build machine has none of the required toolchain.
Verified by running the checks, not by assuming:

| Requirement | State on this machine |
| --- | --- |
| Android SDK | **absent** — no `~/Library/Android/sdk`, no `$ANDROID_HOME`, no `$ANDROID_SDK_ROOT` |
| `adb` | **absent** — not on `PATH` |
| `gradle` | **absent** — not on `PATH` |
| `sdkmanager` | **absent** — not on `PATH` |
| JDK | **absent** — `/usr/bin/java` is the macOS stub: *"Unable to locate a Java Runtime"* |
| Debug keystore | **absent** — neither `~/.android/debug.keystore` nor Godot's `keystores/debug.keystore` |
| Android device | **absent** — none connected, none owned |
| Godot 4.7.2 editor | present — `4.7.2.stable.official.ed1daf0bf` |
| Godot **Android export templates** | **present** — `android_debug.apk`, `android_release.apk`, `android_source.zip` already in `~/Library/Application Support/Godot/export_templates/4.7.2.stable/` |
| `keytool` | present — `/usr/bin/keytool` (but needs a JDK to be useful) |
| Android export preset | **absent** — `game/export_presets.cfg` contains only `"iOS"` |

Godot confirms the last point directly:

```
$ godot --headless --path game --export-debug "Android" /tmp/lb_test.apk
ERROR: Invalid export preset name: Android.
The following presets were detected in this project's `export_presets.cfg`:

        "iOS"
```

The one piece of good news is real and worth stating plainly: **the export
templates are already downloaded.** That is the slowest item on the blocking
list, and it is done.

Everything else in this document is either (a) a patch written to be applied by
someone else, (b) an audit finding with a file:line, or (c) a command to run.
Where I could verify a fact from a local artifact I did, and I say which artifact.
Where I could not, I say so.

---

## 1. The Android export preset, as a patch — NOT APPLIED

`game/export_presets.cfg` is owned by the Lead and has not been touched. The
existing file contains exactly one preset, `[preset.0]` / `[preset.0.options]`
(`platform="iOS"`), so **the next index is 1**.

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

### ⚠️ The app name is a decision, not a fact — read this before applying

I was asked to set the app name to **"Little Days"**. I have done so in the block
below, but flagging it loudly because **the string "Little Days" does not appear
anywhere in this repository**:

- `game/project.godot` → `config/name="Little Buddy"`
- the iOS bundle → `com.pointit.littlebuddy`
- the iOS export path → `build/ios/LittleBuddy.ipa`
- every doc, script and icon → `LittleBuddy` / `Little Buddy`

So applying this block as written ships an Android launcher labelled
**Little Days** next to an iPad app labelled **Little Buddy**, from the same
codebase. That may be an intentional rename in flight — if so, `config/name` in
`project.godot` and the iOS side need the same treatment and that is the Lead's
call, not mine. If it was a slip, change `package/name` to `"Little Buddy"` or
set it to `""` (empty = Godot uses `config/name`, which is the lowest-maintenance
option and keeps the two platforms in sync automatically).

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

### What the current feature set actually requires: nothing.

The release APK should ship with **zero** `<uses-permission>` entries. Walking
the actual feature set:

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
5. **Debug builds get `INTERNET`.** Godot's Android exporter adds
   `android.permission.INTERNET` to debug exports so the remote debugger can
   connect (the literal `android.permission.INTERNET` sits next to the
   `android.permission.` prefix in the exporter's own string table). This is
   normal and harmless for local testing, **but it means the debug APK's
   permission list is not the release APK's.** Never screenshot a debug APK's
   manifest as evidence of the shipping permission set. `tools/export_android.sh`
   dumps the real list with `aapt2 dump permissions` after every build for
   exactly this reason.

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

### 3.2 But there is one leaked iOS assumption, and it is a shipping bug

`game/scripts/speech/speech_service.gd:211-221`:

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
safe zone. A future `tools/make_android_icons.sh` needs a genuine two-layer
source — foreground artwork inset into the 264 px circle, plus a flat background
— and that is an **art task, not a scripting task**. Flagging it as a real
dependency rather than a one-liner someone can knock out at export time.

Suggested destination, matching the preset paths above:
`game/assets/icon/android/{icon_192.png, icon_adaptive_background_432.png,
icon_adaptive_foreground_432.png}`.

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

### It was run. Here is its actual output on this machine, unedited:

```
==> Little Buddy Android export preflight (debug)

  ok    Godot: /Applications/Godot.app/Contents/MacOS/Godot (4.7.2.stable.official.ed1daf0bf)
  ok    export templates: /Users/hotkhwan/Library/Application Support/Godot/export_templates/4.7.2.stable (android_debug.apk present)
  MISSING JDK (no working java on PATH; macOS ships a stub that only prints an ad)
  MISSING Android SDK (looked in /Users/hotkhwan/Library/Android/sdk)
  MISSING debug keystore
  MISSING editor setting export/android/android_sdk_path (currently "/Users/hotkhwan/Library/Android/sdk")
  MISSING editor setting export/android/java_sdk_path (currently "")
  MISSING export preset "Android"
  warn  adb not found (only needed for --install)

================================================================
  ANDROID EXPORT IS BLOCKED -- 6 thing(s) missing.
  NO APK WAS PRODUCED. Nothing below has been guessed at:
  each item is a real check that just failed on this machine.
================================================================

  1. No JDK. Install Temurin 17 and export JAVA_HOME:
         brew install --cask temurin@17
         export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
         echo 'export JAVA_HOME="$(/usr/libexec/java_home -v 17)"' >> ~/.zshrc
     Godot ALSO needs this path in its own Editor Settings (see below) -- the
     shell environment alone is not enough, because the editor is launched from
     Finder and never reads your ~/.zshrc.

  2. No Android SDK. Install the command-line tools and the packages
     Godot 4.7.2 needs:
         brew install --cask android-commandlinetools
         export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
         sdkmanager --licenses
         sdkmanager 'platform-tools' 'platforms;android-36' \
                    'build-tools;36.1.0' 'cmdline-tools;latest'
     (Android Studio also installs all of this, to ~/Library/Android/sdk.)

  3. No debug keystore. Without one Godot reports 'Could not find debug
     keystore, unable to export.' Generate the standard Android debug keystore
     (the password is literally 'android' by convention, and Godot's Editor
     Settings default to it):
         mkdir -p "/Users/hotkhwan/Library/Application Support/Godot/keystores"
         keytool -keyalg RSA -genkeypair -alias androiddebugkey \
           -keypass android -keystore \
           "/Users/hotkhwan/Library/Application Support/Godot/keystores/debug.keystore" \
           -storepass android -dname 'CN=Android Debug,O=Android,C=US' \
           -validity 9999 -deststoretype pkcs12
     A debug keystore is for local installs ONLY. It must never sign a Play
     Store build.

  4. Godot's Editor Settings > Export > Android > Android SdK Path is
     unset or points at a directory that does not exist. Godot ignores
     ANDROID_HOME entirely. Set it in the editor GUI, or edit:
         /Users/hotkhwan/Library/Application Support/Godot/editor_settings-4.7.tres
         export/android/android_sdk_path = "/Users/hotkhwan/Library/Android/sdk"

  5. Godot's Editor Settings > Export > Android > Java SdK Path is unset.
     Godot reports 'A valid Java SDK path is required in Editor Settings.' Set
     it in the editor GUI, or edit:
         /Users/hotkhwan/Library/Application Support/Godot/editor_settings-4.7.tres
         export/android/java_sdk_path = "$(/usr/libexec/java_home -v 17)"
     Resolve the $(...) to a literal path first -- the .tres file is not a shell
     script.

  6. game/export_presets.cfg has no Android preset. The exact block to add
     is written out in docs/ANDROID_READINESS.md section 1 -- paste it at the
     end of the file, or add it through Project > Export > Add > Android and
     then reconcile it against that document.

  Full runbook: docs/ANDROID_READINESS.md

EXIT CODE = 1
```

Worth noting what this output proves and what it does not. It proves the checks
fire, name the right paths, and refuse to proceed. It does **not** prove the
export branch works — that code has never executed, and cannot until the six
items above are resolved.

It also caught something a hand-written runbook would have missed: Godot's Editor
Settings already contain `export/android/android_sdk_path =
"/Users/hotkhwan/Library/Android/sdk"` and `export/android/debug_keystore =
".../keystores/debug.keystore"` — both pointing at paths that **do not exist**.
So the editor is pre-configured for an SDK and keystore that were never
installed, and an export attempted from the GUI would fail with a path error
rather than an obviously-missing-SDK error.

---

## 7. Exact commands to make an APK possible

Run in order on the build Mac (Apple Silicon, zsh). Steps 1-4 are one-time.

### Step 1 — JDK 17

Godot 4.7.2's build template pins `javaVersion JavaVersion.VERSION_17`
(`config.gradle`). Newer JDKs are not a safe substitute.

```bash
brew install --cask temurin@17
/usr/libexec/java_home -v 17                  # confirm it resolves
echo 'export JAVA_HOME="$(/usr/libexec/java_home -v 17)"' >> ~/.zshrc
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
java -version                                 # expect: openjdk version "17.x"
```

### Step 2 — Android SDK

Either the command-line tools (lighter) **or** Android Studio. Do not do both.

```bash
# Option A: command-line tools only
brew install --cask android-commandlinetools
echo 'export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools' >> ~/.zshrc
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
echo 'export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"' >> ~/.zshrc
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

sdkmanager --licenses            # accept all; the export fails silently without this
sdkmanager 'platform-tools' 'platforms;android-36' 'build-tools;36.1.0' 'cmdline-tools;latest'

# Option B: Android Studio instead (installs to ~/Library/Android/sdk,
# which is what Godot's Editor Settings on this machine ALREADY point at)
# brew install --cask android-studio
# then: Settings > Languages & Frameworks > Android SDK > SDK Tools,
# tick "Android SDK Build-Tools 36.1.0" and "Android SDK Platform 36".
# export ANDROID_HOME="$HOME/Library/Android/sdk"

which adb && adb --version       # confirm
```

**NDK — only if you need a custom build** (an Android plugin, e.g. a speech
backend; anything that sets `gradle_build/use_gradle_build=true`). A plain APK
export from the prebuilt template does **not** need it:

```bash
sdkmanager 'ndk;29.0.14206865'   # exact version pinned by Godot 4.7.2
```

### Step 3 — Godot Android export templates

**Already installed** — verified present at
`~/Library/Application Support/Godot/export_templates/4.7.2.stable/`
(`android_debug.apk`, `android_release.apk`, `android_source.zip`). **Skip this
step.** Only needed after a Godot version bump:

```bash
# Editor > Manage Export Templates > Download and Install
ls ~/Library/Application\ Support/Godot/export_templates/4.7.2.stable/android_*.apk
```

### Step 4 — Debug keystore

```bash
mkdir -p ~/Library/Application\ Support/Godot/keystores
keytool -keyalg RSA -genkeypair -alias androiddebugkey \
  -keypass android \
  -keystore ~/Library/Application\ Support/Godot/keystores/debug.keystore \
  -storepass android \
  -dname 'CN=Android Debug,O=Android,C=US' \
  -validity 9999 -deststoretype pkcs12

ls -la ~/Library/Application\ Support/Godot/keystores/debug.keystore
```

Requires step 1 — `keytool` exists at `/usr/bin/keytool` but is a stub without a
JDK. Godot can also generate this itself once `java_sdk_path` is set (its
*"Updated editor debug keystore to"* path), but doing it explicitly is one fewer
moving part. **A debug keystore is for local installs only and must never sign a
Play Store build.**

### Step 5 — Godot Editor Settings

**Godot does not read `ANDROID_HOME` or `JAVA_HOME`.** It reads its own settings,
which currently point at paths that do not exist. GUI route:

*Editor → Editor Settings → Export → Android*

| Setting | Value |
| --- | --- |
| Android Sdk Path | the `$ANDROID_HOME` from step 2 |
| Java Sdk Path | output of `/usr/libexec/java_home -v 17` |
| Debug Keystore | `~/Library/Application Support/Godot/keystores/debug.keystore` |
| Debug Keystore User | `androiddebugkey` |
| Debug Keystore Pass | `android` |

Or edit `~/Library/Application Support/Godot/editor_settings-4.7.tres` directly
(**close the editor first** — it rewrites the file on exit):

```ini
export/android/android_sdk_path = "/opt/homebrew/share/android-commandlinetools"
export/android/java_sdk_path = "/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home"
export/android/debug_keystore = "/Users/hotkhwan/Library/Application Support/Godot/keystores/debug.keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
```

Resolve every path to a literal — the `.tres` file is not a shell script. Lines 312-316
already exist in that file; the SDK path needs correcting and the Java path
filling in.

### Step 6 — Add the export preset

Apply section 1's block to `game/export_presets.cfg` (**Lead-owned**), or add it
via *Project → Export → Add → Android* and reconcile the values.

### Step 7 — Verify, then build

```bash
cd /Users/hotkhwan/Projects/little-buddy
tools/export_android.sh --check           # must print "All preflight checks passed."
tools/export_android.sh debug
```

### Step 8 — Install on a device

```bash
# On the device: Settings > About > tap Build number 7x, then
# Settings > System > Developer options > USB debugging
adb devices                               # must list the device as "device"
tools/export_android.sh debug --install
```

### Step 9 — What to actually verify on the device

Nothing in this document substitutes for these. In priority order:

1. **Speech reports unavailable, not mock.** Open the parent speech diagnostics
   panel. It must read `backend: unavailable`, **not** `backend: mock`. If it
   reads `mock`, the bug in section 3.2 is live and a child can pass speaking
   tasks without speaking. **Verify this first.**
2. **Touch-only playthrough.** Complete Mission 01 and Snack Time start to
   finish without ever pressing Speak. Stars must be awarded identically.
3. **Speak button absent.** With speech unavailable it must be hidden, not greyed
   (`house_hud.gd:452`, and the guarantee in `test_speech_never_required.gd:233`).
4. **TTS speaks.** Confirm English prompts are audible (`CLAUDE.md` DoD 6). If
   silent, check for an installed English voice — and confirm silence is a quiet
   no-op, not a stall.
5. **Safe area, both ways up.** Flip the tablet 180°. No HUD control may sit
   under a cutout or the gesture bar in either orientation (risks R3-R5).
6. **Joystick in the bottom-left corner.** Drive from the extreme corner and
   confirm no system back-gesture fires (risk R3).
7. **Release permission list.** `aapt2 dump permissions` on a **release** APK
   must show **no permissions at all** — the script prints this automatically.
   The debug APK will show `INTERNET`; that is expected and is not the shipping
   set (section 2).
8. **Performance.** Mobile renderer, one `DirectionalLight3D`, 1024 shadow map
   (`project.godot`). Verify the frame rate on the actual target hardware, which
   is weaker than an iPad.

---

## 8. Blocking list

Must be resolved before an Android APK can exist:

1. **No JDK 17** on the build machine. (step 1)
2. **No Android SDK** — no `sdkmanager`, no `build-tools`/`apksigner`, no
   `platforms/android-36`, no `adb`. (step 2)
3. **No debug keystore.** (step 4)
4. **Godot Editor Settings** `java_sdk_path` empty and `android_sdk_path`
   pointing at a non-existent directory. (step 5)
5. **No Android export preset** in `game/export_presets.cfg` — patch ready in
   section 1, unapplied, Lead-owned. (step 6)
6. **No Android launcher icons** — 192x192 plus two 432x432 adaptive layers. Needs
   real two-layer art; `make_ios_icons.sh` cannot be reused. (section 5)
7. **No Android device** to install on or verify against.

Not blocking an APK, but blocking a *correct* one:

8. **`speech_service.gd:215` selects `MockSpeechBackend` on Android**, faking a
   `"milk"` transcript on a real child's device. One-line fix in section 3.2.
   **This should land before any Android build is put in front of a child.**
9. **App name "Little Days"** appears nowhere in the repo and would disagree with
   the iPad app's name. Needs a decision. (section 1)
10. **Android speech recognition is not proven offline-capable** and should be
    treated as separate, independently-scoped work with on-device recognition as
    its acceptance criterion. Ship Android touch-only. (section 3.4)
11. **Joystick clearance risks R1/R2** — 0.6 px of margin on a square foldable,
    and a floor that can overlap Speak below ~920 px viewport width.
    (section 4)

Files created by this work: `tools/export_android.sh`,
`docs/ANDROID_READINESS.md`, `game/tests/cases/test_android_platform_guards.gd`.
`game/export_presets.cfg`, `game/project.godot` and everything under
`game/scripts/`, `game/scenes/` and `game/content/` were **not modified**.
Nothing was committed.
