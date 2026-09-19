# Installing the Little Days Founder Preview

**Closed Founder Preview.** Not a store build, not TestFlight. Two targets:
an iPad over USB from Xcode, and an Android phone over USB with `adb`.

Everything below was verified on this machine on 2026-09-19 against
`feature/overnight-production-candidate` @ `90afbfa`. Paths are absolute or
relative to the repo root `/Users/hotkhwan/Projects/little-buddy`.

> **`build/` is git-ignored.** Neither the APK nor the Xcode project is in the
> repository — they exist only on this Mac. A fresh clone on another machine has
> no installable artefact until you run the export scripts in
> [Rebuilding](#rebuilding).

---

## The Android artefact, as verified

| | |
|---|---|
| File | `build/android/LittleDays-debug.apk` |
| Size | 36,501,904 bytes (34.8 MiB) |
| SHA-256 | `26ff1ea29d78c5c79819705b8841b35ee8691c4932d1020507d81f7d281168d7` |
| Built | 2026-09-19 23:30:44 |
| Package | `com.pointit.littlebuddy` |
| Launcher label | **Little Days** |
| Version | `0.1.0` (versionCode 1) |
| Signature | Verified, APK Signature Scheme v2 + v3. Signer `CN=Android Debug, O=Android, C=US`, RSA 2048 |
| Cert SHA-256 | `2b63458c5cec82fe043531a0309db64b7efb1b6d18200864a2590f9da8dcd35c` |
| Declared permissions | **none — zero `uses-permission` entries** |
| Native code | `arm64-v8a` only |
| minSdk / targetSdk | 24 (Android 7.0) / 36 |
| Orientation | sensor-landscape, immersive |
| Debuggable | yes (`android:debuggable=true`) |

Two consequences of that permission list worth knowing before you test:

* The app **cannot reach the network** — no `INTERNET` permission. Offline-first
  is enforced by the manifest, not just by convention.
* The app **cannot open the microphone** — no `RECORD_AUDIO`. Android speech is
  unavailable at the OS level as well as in code. See
  [the two rows that lie](#the-two-rows-that-lie).

---

## Part 1 — iPad, from Xcode

**Do not change the signing configuration.** It is already set up: automatic
signing, team `JZDAUN45CF`, bundle id `com.pointit.littlebuddy`, deployment
target iOS 15.0, iPhone + iPad. If Xcode shows no red signing error, touch
nothing on that screen.

### Once per iPad (skip if you have run a dev build on it before)

1. Connect the iPad to the Mac with a cable. Unlock it, tap **Trust This
   Computer**, enter the passcode.
2. On the iPad: **Settings → Privacy & Security → Developer Mode → On**, then
   **Restart**. Unlock after the restart and confirm **Turn On**.
   *iOS 16 and later refuse to launch any developer-signed app until this is
   done, and the failure message from Xcode does not say so plainly.*

### Every install

3. Open the project:

   ```sh
   open /Users/hotkhwan/Projects/little-buddy/build/ios/LittleBuddy.xcodeproj
   ```

4. Wait for Xcode to finish indexing. Scheme: **LittleBuddy** (the only one).
5. In the toolbar run-destination menu, pick your iPad by name. If it is greyed
   out with "unavailable", it is still preparing — the Devices window
   (**Window → Devices and Simulators**) shows the progress.
6. Select the **LittleBuddy** target → **Signing & Capabilities** and confirm
   only this much:
   * **Automatically manage signing** is ticked.
   * **Team** is set. If it is empty or says "None", pick your Apple ID's team
     from the dropdown. Do not edit anything else, and do not edit
     `project.pbxproj` by hand.
7. Press **⌘R** (Run). First run takes a few minutes: Xcode compiles the shim,
   copies an 8 MB `.pck` and a large `.xcframework`, then installs.
8. The first launch will stop with **"Untrusted Developer"** or *"Verify the
   Developer App certificate"*. This is normal and not a build failure:

   > On the iPad: **Settings → General → VPN & Device Management → Developer
   > App → <your Apple ID> → Trust "<your Apple ID>" → Trust.**

   Then tap the **Little Days** icon on the home screen, or press ⌘R again.
9. Hold the iPad in **landscape**. Turn the volume **up** (then read the music
   row below before concluding anything about sound).

### The 7-day cliff

If you signed with a **free** Apple ID (a "Personal Team"), the provisioning
profile is valid for **7 days**. On day 8 the app refuses to launch — usually
*"Unable to verify app… An internet connection is required"* — even though the
app itself is fine and fully offline.

* **Fix:** plug the iPad in and press ⌘R again. That is the whole fix. You do
  not need to delete the app, and your save data survives.
* Free signing also caps you at 3 sideloaded apps per device and needs a
  network round-trip *at install time* (not at play time).
* If `JZDAUN45CF` is a **paid** Apple Developer Program team, profiles last a
  year and none of this applies.

### Do not switch the scheme to Release to install

The Release configuration signs with **Apple Distribution**, which a free Apple
ID does not have. Use the default **Debug** configuration that ⌘R uses.

---

## Part 2 — Android phone, over USB

`adb` is **not on `PATH`**. Use the full path every time:

```
/Users/hotkhwan/Library/Android/sdk/platform-tools/adb
```

### Once per phone

1. **Settings → About phone → Build number**, tap it 7 times → "You are now a
   developer".
2. **Settings → System → Developer options** (on some phones: Settings →
   Additional settings → Developer options) → turn on **USB debugging**.
3. Plug the phone into the Mac. A dialog appears on the phone: **Allow USB
   debugging?** → tick *Always allow from this computer* → **Allow**.
   *No dialog usually means the cable is charge-only, or the USB mode needs
   changing from "Charging" to "File transfer" in the phone's notification
   shade.*
4. Confirm the Mac can see it — this must list one device as `device`, not
   `unauthorized` and not `offline`:

   ```sh
   /Users/hotkhwan/Library/Android/sdk/platform-tools/adb devices -l
   ```

### Install

```sh
/Users/hotkhwan/Library/Android/sdk/platform-tools/adb install -r \
  /Users/hotkhwan/Projects/little-buddy/build/android/LittleDays-debug.apk
```

Expect `Performing Streamed Install` then `Success`. Launch **Little Days**
from the app drawer, or from the Mac:

```sh
/Users/hotkhwan/Library/Android/sdk/platform-tools/adb shell monkey \
  -p com.pointit.littlebuddy -c android.intent.category.LAUNCHER 1
```

One command does export + install together, if you would rather not copy paths:

```sh
/Users/hotkhwan/Projects/little-buddy/tools/export_android.sh debug --install
```

### When the phone refuses the APK

| What you see | Why | What to do |
|---|---|---|
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` / `signatures do not match` | An older Little Days is installed, signed with a different key. Android never lets a debug key overwrite another key. | `adb uninstall com.pointit.littlebuddy` then install again. **This deletes the save.** |
| "Blocked by Play Protect" / *unsafe app* | Play Protect always says this about an unknown developer. It is not a virus report. | Tap **More details → Install anyway**. Or turn off Play Protect scanning in Play Store → Profile → Play Protect → Settings for the session. |
| `INSTALL_FAILED_VERIFICATION_FAILURE` | Google's install verifier. | Developer options → turn off **Verify apps over USB**. |
| `INSTALL_FAILED_USER_RESTRICTED` (Xiaomi / Redmi / POCO / MIUI) | MIUI blocks USB installs by default. | Developer options → turn on **Install via USB** *and* **USB debugging (Security settings)**. These require being signed in to a Mi account and, on some builds, a SIM. |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | The APK is **arm64-v8a only**. A 32-bit-only phone or an x86 emulator cannot run it. | Use a 64-bit ARM device. Any phone from ~2017 on qualifies. |
| `INSTALL_FAILED_OLDER_SDK` | The phone is below Android 7.0 (API 24). | Use a newer device. |
| `adb: no devices/emulators found` | Not authorised, or charge-only cable. | Re-do step 3. `adb kill-server` then `adb devices` forces a fresh prompt. |
| Device shows as `unauthorized` | The USB-debugging prompt was dismissed. | Revoke USB debugging authorisations in Developer options, replug, accept. |
| Installs, then the app closes instantly | Godot uses Vulkan or GLES3. | Grab the log: `adb logcat -d godot:V *:S > /tmp/littledays.log` and send that file. |

### `INSTALL_FAILED_UPDATE_INCOMPATIBLE` is expected on the second build

Every fresh `tools/export_android.sh debug` reuses the same debug keystore, so
reinstall over the top works. But if an APK from a *different* machine was ever
installed, you must uninstall first. Uninstalling wipes progress, because the
preset sets `retain_data_on_uninstall=false` — that is deliberate, so a tester
can always get back to a true first run.

---

## The two rows that lie

Two test steps have a PASS that looks like a FAIL, or a FAIL that looks like a
PASS. Read these before judging either.

### 1. Silence is a PASS

**A normal build has no music, on purpose.** Both delivered tracks
(`little_days_theme.ogg`, `hungry_bunny.ogg`) sit in the build with
`commercialUse: "pending"` and `licenseEvidence: "OWNER TO CONFIRM"` in
`game/content/audio/manifest.json`. The licence gate **fails closed**: a track
plays only when the rights are recorded as verified. They are not. So the game
is quiet, and that is the gate working.

**If you hear music in a plain build, that is the finding** — report it.

Sound effects and spoken prompts are unaffected and should still be audible.

**To hear the tracks deliberately**, arm the named, off-by-default preview
override. It prints a loud banner whenever it is live and it cannot make a track
shippable.

*On the Mac (easiest, and the one to use):*

```sh
touch "/Users/hotkhwan/Library/Application Support/Godot/app_userdata/Little Days/OWNER_ACKNOWLEDGED_UNVERIFIED_MUSIC"
```

then run the game from the Godot editor. Delete that file to disarm.

*On the Android phone* — works because this build is debuggable:

```sh
ADB=/Users/hotkhwan/Library/Android/sdk/platform-tools/adb
$ADB shell run-as com.pointit.littlebuddy \
  sh -c 'echo armed > files/OWNER_ACKNOWLEDGED_UNVERIFIED_MUSIC'
```

*On the iPad:* the app has `UIFileSharingEnabled = false`, so the Files app
cannot reach it. Use **Xcode → Window → Devices and Simulators → your iPad →
Installed Apps → Little Days → the gear icon → Download Container…**, add an
empty file named `OWNER_ACKNOWLEDGED_UNVERIFIED_MUSIC` inside
`AppData/Documents/`, then **Replace Container…**. Fiddly; preview on the Mac
instead unless you specifically need to hear it on the iPad.

Nothing committed to the repo ever arms this. See
`game/scripts/audio/music_licence_override.gd` and
`docs/ORIGINAL_MUSIC_INTEGRATION.md`.

### 2. "Speech doesn't work" on Android is a PASS. Speech *working* is a FAIL.

On Android the game must report speech **unavailable** and hide the Speak
button. There is no Android speech backend, and the APK declares no
`RECORD_AUDIO` permission, so the microphone is unreachable.

**Hard FAIL: the game accepting a word you did not say.** A bug of exactly that
shape existed — `SpeechService` only special-cased iOS, so Android fell through
to the development mock, which reports itself available and returns a canned
`"milk"` about 0.6 s after any tap. Every speaking task passed without anyone
speaking. It is fixed (the check is now `OS.has_feature("mobile")`, covering
both platforms), and the fix is in this APK. It is listed here because it is the
one failure mode that looks like success, so only a silent tester can catch it.

**How to test it:** tap anything that invites speech, and say **nothing at
all**. Stay completely silent. If the task completes, mark FAIL and tell me.

---

## Evidence to send back

Small, local, no audio and no transcripts — just capability flags.

*iPad:*

```sh
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier com.pointit.littlebuddy \
  --source Documents/speech_diag.json --destination ./speech_diag.json
```

*Android:*

```sh
ADB=/Users/hotkhwan/Library/Android/sdk/platform-tools/adb
$ADB shell run-as com.pointit.littlebuddy cat files/speech_diag.json
$ADB logcat -d godot:V *:S > /tmp/littledays-logcat.txt
```

The `backend` field is the answer: `ios` (native recognizer), `unavailable`
(honest, expected on Android), or `mock` — and **`mock` on a phone or iPad is a
bug**, not a result.

---

## Is the APK still current?

The APK verified above was built at 23:30:44 and contains every game change up
to and including `2f0cea3` (the HUD, kitchen and music work); `90afbfa` is
documentation only. It is current as of `90afbfa`.

Work was still in flight when this was written, so check before you install —
this lists any game file newer than the APK:

```sh
cd /Users/hotkhwan/Projects/little-buddy
find game -type f -newer build/android/LittleDays-debug.apk -not -path '*/.godot/*'
```

Nothing, or only files under `game/tests/`, means the APK is current. Anything
under `game/scripts/`, `game/scenes/` or `game/content/` means it is stale —
rebuild. The same reasoning applies to `build/ios/`: re-run `tools/export_ios.sh`
if gameplay changed after it was generated.

## Rebuilding

Only needed if the code changed after 2026-09-19 23:30, or on a machine where
`build/` does not exist.

```sh
cd /Users/hotkhwan/Projects/little-buddy
tools/export_android.sh --check     # preflight only, exports nothing
tools/export_android.sh debug       # -> build/android/LittleDays-debug.apk
tools/export_ios.sh debug           # -> build/ios/LittleBuddy.xcodeproj
```

`--check` verifies all five prerequisites (Godot 4.7.2, export templates,
Temurin 17, Android SDK + build-tools 36.1.0 with `apksigner`, debug keystore,
and the `Android` preset) and prints copy-pasteable fixes for anything missing.
The NDK warning is not a blocker for this plain-template export. Full list in
`docs/ANDROID_READINESS.md`.

**`tools/export_ios.sh` does `rm -rf build/ios` first.** Any change you made
inside Xcode — including a different signing team — is destroyed by a
re-export. The team is regenerated from `application/app_store_team_id` in
`game/export_presets.cfg`, so change it there if you need it to stick.

The debug keystore lives outside the repository, at
`~/Library/Application Support/Godot/keystores/debug.keystore`. Never copy a
keystore into the repo.

---

## Then do the QA pass

`docs/DEVICE_QA_CHECKLIST.md`. It is **BLOCKED** until you run it — no engineer
can close a device row, and nothing in the engineering reports is device
evidence. Three minutes per platform, no coaching.
