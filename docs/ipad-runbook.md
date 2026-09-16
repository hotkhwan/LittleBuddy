# Little Buddy — Physical Device Runbook (iPhone + iPad)

Getting `Little Buddy v0.0.1` from this repo onto a physical device tonight, via Xcode.
**TestFlight is not required.** Direct Xcode install with a Personal Team is the fastest path.

The build is **Universal** (`application/targeted_device_family=2`) — one build installs on
both iPhone and iPad. **Validate on the iPhone first tonight**; iPad support is preserved and
already verified at 4:3 aspect, just untested on hardware.

Layout is driven by `DisplayServer.get_display_safe_area()` via `res://scripts/ui/safe_area.gd`,
so there are **no per-device layout constants** — nothing is tuned for a specific iPhone.

---

## 0. Machine status (verified 2026-09-17)

| Item | Status |
|---|---|
| Mac mini, Apple M4, 16 GB RAM | OK |
| macOS 26.6.2 | OK |
| Godot 4.7.2 stable + export templates (incl. `ios.zip`) | Installed |
| Xcode 27.0, iPhoneOS SDK | Installed |
| Xcode license accepted | **Accepted** |
| Apple Team ID `JZDAUN45CF` in `export_presets.cfg` | **Set** |
| Godot → Xcode project export | **Succeeds** |
| `xcodebuild` compile of generated project | **`** BUILD SUCCEEDED **`** |

## 1. Export the Xcode project from Godot

Already done and reproducible. `application/export_project_only=true`, so this produces an
**Xcode project, not an `.ipa`** (no IPA is generated yet, by design).

```bash
cd /Users/hotkhwan/Projects/little-buddy
rm -rf build/ios && mkdir -p build/ios
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
  --export-debug "iOS" "$PWD/build/ios/LittleBuddy.ipa"
```

Generated project:

```
/Users/hotkhwan/Projects/little-buddy/build/ios/LittleBuddy.xcodeproj
```

### Two export gotchas that were hit and fixed (keep these settings)

1. **`textures/vram_compression/import_etc2_astc=true`** in `project.godot`.
   Without it the iOS export aborts with a **completely blank** error message
   ("configuration errors:" and nothing else). The real cause only surfaces via a macOS
   preset, which words it properly: *"Cannot export for universal or arm64 if ETC2 ASTC
   texture format is disabled."* If you ever see a blank iOS export error, check this first.
2. **`application/min_ios_version="15.0"`.** Xcode 27 rejects anything below 15.0
   (`the range of supported deployment target versions is 15.0 to 27.0.x`).

## 2. Verified in the generated project

| Setting | Value |
|---|---|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.pointit.littlebuddy` |
| `DEVELOPMENT_TEAM` | `JZDAUN45CF` |
| `CODE_SIGN_STYLE` | `Automatic` |
| `TARGETED_DEVICE_FAMILY` / `UIDeviceFamily` | `1,2` (iPhone + iPad) |
| `IPHONEOS_DEPLOYMENT_TARGET` / `MinimumOSVersion` | `15.0` |
| `UISupportedInterfaceOrientations` (iPhone + iPad) | LandscapeLeft **and** LandscapeRight |
| `NSMicrophoneUsageDescription` | present |
| `NSSpeechRecognitionUsageDescription` | present |
| Built binary | `arm64`, game `.pck` embedded |

Orientation note: `display/window/handheld/orientation` is `4` (Sensor Landscape), not `0`
(Landscape). `0` locked the app to a **single** rotation — LandscapeLeft on iPhone and
LandscapeRight on iPad — so a child flipping the device would have got a sideways app.

## 3. Reproduce the compile yourself (optional sanity check)

```bash
cd /Users/hotkhwan/Projects/little-buddy/build/ios
xcodebuild -project LittleBuddy.xcodeproj -scheme LittleBuddy -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/lb_dd \
  CODE_SIGNING_ALLOWED=NO build
```

That build deliberately skips signing. Signing happens in the Xcode GUI in the next step.

## 3a. Xcode warnings — what's cleaned and what remains (by design)

Current build is down to **two** warnings, both benign and both upstream:

```
warning: #pragma once in main file                                  (x2)
warning: Metadata extraction skipped, no AppIntents.framework dependency found
```

### `#pragma once in main file` — Godot glue, harmless, do not "fix"

Traced to `build/ios/LittleBuddy/dummy.h:31`. Verified:

- `dummy.h` is **byte-identical** to the `dummy.h` inside Godot 4.7.2's own `ios.zip`
  export template, i.e. it is engine-generated glue, regenerated on every export.
- It is wired up as `SWIFT_OBJC_BRIDGING_HEADER = "LittleBuddy/dummy.h"`. Clang compiles a
  bridging header as a *main file*, and `#pragma once` in a main file has nothing to guard
  against, hence the warning. It appears twice because Swift compiles it once for the
  bridging-header PCH and once in the driver job.
- The speech plugin contributes **zero** `#pragma once` warnings (verified by filtering the
  build log for our sources).

Editing `dummy.h` would be pointless — Godot overwrites it on the next export. Leave it.

### `AppIntents.framework` — informational

Xcode looks for App Intents metadata to extract; Little Buddy declares no App Intents
(no Siri shortcuts / widgets). Nothing to fix.

### Camera / Photo Library warnings — fixed, but they need the wrapper script

These previously appeared:

```
warning: The value for NSCameraUsageDescription must be a non-empty string.
warning: The value for NSPhotoLibraryUsageDescription must be a non-empty string.
```

Little Buddy uses neither the camera nor the photo library. **Removing the `privacy/*`
options from `export_presets.cfg` does not remove the keys** — Godot's
`godot_apple_embedded-Info.plist` template hardcodes `NSCameraUsageDescription` and
`NSPhotoLibraryUsageDescription` as `$camera_usage_description` /
`$photolibrary_usage_description` placeholders, so they are emitted on every export and just
end up empty. Filling them with dummy text would be a false privacy declaration.

So they are deleted after export by **`tools/export_ios.sh`**:

```bash
tools/export_ios.sh debug     # or: release
```

**Use that script instead of calling `--export-debug` directly, or the keys come back.**
The shipped app declares exactly two permissions: `NSMicrophoneUsageDescription` and
`NSSpeechRecognitionUsageDescription`.

## 4. Open in Xcode, sign, and run

1. Open the generated `LittleBuddy.xcodeproj` in `build/ios/`.
2. **Signing & Capabilities** → check **Automatically manage signing** → Team = your
   Personal Team. Bundle Identifier is preset to `com.pointit.littlebuddy`; if Xcode
   complains it is taken, change it (e.g. `com.pointit.littlebuddy.khwan`).
3. Connect the **iPhone** by cable. On the device: **Settings → Privacy & Security → Developer Mode → On**, then reboot and unlock.
4. Select the iPhone as the run destination. Press **▶ Run**.
5. First launch will fail to trust: on the device go to
   **Settings → General → VPN & Device Management → [your Apple ID] → Trust**, then Run again.
6. Once the iPhone is confirmed, repeat steps 3–5 with the iPad selected as the destination.
   No rebuild or preset change is needed — the same Universal build covers both.

> Personal Team provisioning expires after ~7 days. Re-run from Xcode to refresh.

## 5. Verify the Info.plist privacy strings landed

In the generated Xcode project, confirm both keys exist (they are injected by the export preset):

- `NSMicrophoneUsageDescription` — set via `privacy/microphone_usage_description`
- `NSSpeechRecognitionUsageDescription` — set via `application/additional_plist_content`

If either is missing, add it by hand in Xcode before running, or iOS will terminate the
app when the microphone is first requested.

## 6. On-device test checklist

Offline:
- [ ] Enable Airplane Mode **before** launching — the game must be fully playable
- [ ] Title screen → Play → Baby Room appears in landscape
- [ ] Baby, milk bottle and teddy are all visible on screen
- [ ] Baby says "I'm hungry." (device TTS)
- [ ] Tap the milk bottle → baby drinks → ⭐ +1 → "Thank you!"
- [ ] Tap the teddy → happy reaction, says "Teddy", **no** star
- [ ] Force-quit and relaunch → star count is preserved

Child UX:
- [ ] Touch targets feel comfortable for a small finger
- [ ] No red X, no score, no percentage, no timer, no debug text
- [ ] Rapid mashing of the bottle cannot break the scene
- [ ] Volume is not startling

Universal / safe area (check on the iPhone specifically):
- [ ] Star counter is clear of the Dynamic Island / notch in **both** landscape rotations
- [ ] Speak button is clear of the home-indicator bar
- [ ] Nothing is clipped by the rounded screen corners
- [ ] Rotating the device 180° keeps all UI inside the safe area
- [ ] Baby, bottle and teddy all remain visible (the wide phone aspect shows *more*
      room horizontally, never less vertically — `Camera3D.keep_aspect = KEEP_HEIGHT`)
- [ ] Repeat on iPad afterwards to confirm nothing regressed at 4:3

Speech (optional tonight — see §7):
- [ ] Tapping Speak does not crash when speech is unavailable
- [ ] If permission is denied, touch feeding still completes the activity

---

## 7. Native iOS speech — status and what remains

**Status: compiled, linked and shipped in the Xcode project. NOT yet proven on a device.**
See `docs/OVERNIGHT_BUILD_REPORT.md` §5 for the two runtime bugs that were fixed and
exactly what remains unverified.

The game ships a `SpeechService` abstraction with three backends. On a real iPad without
the compiled plugin, `SpeechService` reports `"unavailable"` and **touch gameplay remains
fully complete** — it never fabricates a fake success on device. This is by design.

To actually enable voice later, per `ios/speech_plugin/README.md`:

1. Vendor `godot-cpp` at a 4.7-compatible tag under `ios/speech_plugin/godot-cpp`.
2. `scons platform=ios generate_bindings=yes`, then build debug + release `arm64`.
3. `xcodebuild -create-xcframework` into the paths named in `littlebuddyspeech.gdextension`.
4. **Copy the whole `ios/speech_plugin/` tree inside `game/`** (e.g. `game/ios/speech_plugin/`)
   and fix the relative paths — Godot only auto-loads `.gdextension`/`.gdip` files under
   `res://`, and today that directory sits *outside* the Godot project.
5. Re-export, then in Xcode confirm `Speech.framework` and `AVFoundation.framework` are linked.
6. Deployment target iOS 13+ (preset is set to 14.0) for `supportsOnDeviceRecognition`.

The plugin forces `requiresOnDeviceRecognition = YES` and never writes or uploads audio.

If `SpeechService.get_backend_name()` still reports `"unavailable"` after all this, that is a
safe degraded state, not a crash — treat it as debugging work, not a blocker.

---

## 8. If performance disappoints on the iPad

The project uses the **Mobile** renderer. If an older iPad struggles, switch to Compatibility:

```ini
# game/project.godot
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
```

Shadows are already disabled and there is exactly one directional light, so this is
unlikely to be needed on any modern iPad.

---

## 9. Known gaps (honest list)

- **Not validated on any physical device.** No iPhone or iPad was connected during this
  build; every claim above about on-device behaviour is untested. Layout was verified by
  rendering at iPhone (2.17:1) and iPad (1.44:1) aspect ratios on macOS, but the **real
  safe-area insets were never exercised** — on macOS the platform safe area is deliberately
  ignored, so only the minimum margin path has actually run. The notch/home-indicator
  branch is code-reviewed, not executed.
- Native iOS speech is uncompiled (§7).
- The placeholder SVGs in `game/assets/placeholders/` are currently **unused** — the 3D
  scene draws from primitive meshes. They are kept as a starting point for 2D UI art.
- Star counter renders as `* N` rather than a star glyph/sprite.
- Milk bottle is **tap-only**; 3D drag was deliberately not implemented (a reliable tap was
  judged safer for a child than a fragile drag).
