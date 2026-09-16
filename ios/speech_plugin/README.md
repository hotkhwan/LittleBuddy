# LittleBuddySpeech — iOS native speech plugin

## Status: iOS export pickup CONFIRMED WORKING end-to-end (this round)

This directory contains the GDExtension bridge for on-device speech
recognition (`SFSpeechRecognizer` + `AVAudioEngine`), exposed to GDScript as
the `LittleBuddySpeech` Engine singleton, **plus** the pieces that make
Godot's iOS exporter actually pick it up: a macOS build of the same
extension (editor-load only) and a small `EditorExportPlugin` addon that
links the system frameworks it needs.

**What was verified this round, with real tools, end to end:**

1. Root-caused (not guessed, see "Why a macOS build" and "Why not .gdip"
   below) why the previous round's export attempt produced zero
   `Speech.framework`/`AVFoundation.framework` references and never copied
   the `.xcframework` into the generated Xcode project.
2. Built and confirmed a fix for both root causes (macOS `.gdextension`
   library entries + an `EditorExportPlugin` addon calling
   `add_ios_framework`).
3. Copied the fix into a **throwaway** copy of the Godot project
   (`/tmp/gametest`, never `game/`) and ran a real
   `godot --headless --export-debug "iOS" ...` **and**
   `--export-release "iOS" ...`. Both exports completed with **zero**
   GDExtension-related errors in the log (previously: `No GDExtension
   library found for current OS and architecture (macos.arm64)` on every
   run).
4. Confirmed in the generated `project.pbxproj`, for both debug and
   release exports:
   - `Speech.framework` and `AVFoundation.framework` file references +
     `PBXBuildFile` entries, present in the target's
     `PBXFrameworksBuildPhase` (not just floating unused references).
   - `liblittle_buddy_speech.ios.debug.xcframework` /
     `...ios.release.xcframework` copied into
     `LittleBuddy/dylibs/ios/speech_plugin/bin/` and referenced as a
     `wrapper.xcframework` build file in the same Frameworks build phase.
   - `OTHER_LDFLAGS` containing
     `-Wl,-U,_little_buddy_speech_library_init` (forces the linker to
     treat our GDExtension entry symbol as an allowed-undefined dynamic
     lookup, since iOS GDExtensions are statically linked, not `dlopen`ed).
   - A generated `LittleBuddy/dummy.cpp` containing a static initializer
     that calls `add_apple_embedded_platform_init_callback(...)`, which
     registers `little_buddy_speech_library_init` with Godot's dynamic
     symbol table (`register_dynamic_symbol`) at app startup -- this is
     the actual mechanism by which `little_buddy_speech_library_init` gets
     invoked and the `LittleBuddySpeech` singleton gets registered on a
     real iOS device, confirmed by reading the generated file, not assumed.
5. Ran the real link line: `... -Wl,-U,_little_buddy_speech_library_init
   -lgodot -framework Speech -framework AVFoundation
   -llittle_buddy_speech_combined.ios.template_debug -o .../LittleBuddy`
   -- our combined archive and both frameworks are genuinely on the link
   line, not just declared in the project file.
6. `xcodebuild -destination 'generic/platform=iOS' ... build` (device
   arm64, unsigned) produced **`** BUILD SUCCEEDED **`** for BOTH the
   debug and release exports, with zero linker errors (no undefined
   symbols from the plugin's Objective-C++ code or godot-cpp bindings).
7. Built and verified new macOS arm64 `template_debug`/`template_release`
   variants of the extension (see "Why a macOS build"): compile clean,
   link clean (`otool -L` confirms real linkage against
   `Speech.framework`, `AVFoundation.framework`, `Foundation.framework`;
   the ~59 undefined symbols are ordinary libobjc/libc++/libSystem runtime
   symbols, not missing Godot glue), entry symbol
   `_little_buddy_speech_library_init` present and exported (`nm -gU`).
8. Guarded every `AVAudioSession` call (iOS/tvOS/watchOS-only API) behind
   `#if TARGET_OS_IPHONE` so the shared `.mm` file compiles for macOS too,
   with an `AVCaptureDevice`-based fallback for microphone permission on
   macOS. `requiresOnDeviceRecognition` and `supportsOnDeviceRecognition`
   checks now use `@available(iOS 13.0, macOS 10.15, *)` so both platforms
   are covered by one code path.
9. The iOS `.a`/`.xcframework` artifacts from the previous round were
   **not rebuilt or touched** except for the guard changes above (which do
   not affect the iOS `#if TARGET_OS_IPHONE` branch's behavior at all --
   `TARGET_OS_IPHONE` is true for iOS device builds, so the iOS code path
   is byte-for-byte the same logic as before, just now inside an `#if`).
   The iOS static libraries were re-linked as part of producing the
   `.xcframework`s that got bundled in step 4 above, from the same source.

**What is still NOT verified** (out of reach without a live device):

- It has not run on a simulator or physical device -- no live
  `SFSpeechRecognizer` permission prompt, on-device recognition, or
  `feedMilk` mapping has been observed end-to-end. The build/link/export
  contract is now fully verified; the runtime behavior on-device is not.
- Code signing was disabled (`CODE_SIGNING_ALLOWED=NO`) for the verification
  build, since no device/profile is available in this environment. Whether
  code signing changes anything about the frameworks/xcframework linkage is
  unlikely (frameworks are system frameworks, always present, and our
  xcframework is a plain static archive) but not independently confirmed.
- Whether Godot's own iOS audio driver and this plugin's `AVAudioSession`
  configuration cooperate cleanly at runtime is still an open risk (see
  "Open risk" below) -- this can only be observed by running the exported
  app.

Gameplay does **not** depend on any of this. `game/scripts/speech/speech_service.gd`
detects the absence of the `LittleBuddySpeech` singleton and degrades to the
mock backend (desktop/editor) or an explicit "unavailable" state (real iOS
device without the plugin, or before the orchestrator wires this into
`game/`) -- touch feeding always works either way.

## Why a macOS build (root cause #1, confirmed)

Godot's iOS export flow relies on an internal, always-registered
`GDExtensionExportPlugin` (`editor/export/gdextension_export_plugin.h/.cpp`
-- confirmed present in the shipped Godot 4.7.2 binary via `nm`/`strings`)
that bundles a GDExtension's target-platform library/dependencies into the
exported Xcode project. This plugin operates on GDExtensions that
`GDExtensionManager` has **already successfully loaded** in the running
editor process.

Without a `macos.debug`/`macos.release` entry in
`littlebuddyspeech.gdextension`, `GDExtensionManager` cannot open the
extension at all on a macOS editor (there is no library for its own
OS/arch) and logs:
```
ERROR: No GDExtension library found for current OS and architecture (macos.arm64)
       in configuration file: res://ios/speech_plugin/littlebuddyspeech.gdextension
ERROR: Error loading extension: '...'
```
Because the extension never loads, it never enters `GDExtensionManager`'s
loaded-extensions list, so the built-in `GDExtensionExportPlugin` never
sees it during an iOS export and never copies its `ios.debug`/`ios.release`
xcframework or registers its entry symbol -- independent of whether the
`.gdextension` file's `ios.*` keys are perfectly correct.

**Fix**: added `macos.debug`/`macos.release` entries to
`littlebuddyspeech.gdextension`, pointing at a new macOS arm64 build of the
same extension code (`SConstruct` now has a `platform == "macos"` branch
producing a `SharedLibrary` wrapped in a minimal `.framework` directory,
linked directly against `Speech.framework`/`AVFoundation.framework`/
`Foundation.framework` since a `.dylib`, unlike the iOS static archive,
resolves its own symbols at build time). `little_buddy_speech.mm` guards
every `AVAudioSession` call (an iOS/tvOS/watchOS-only API) behind
`#if TARGET_OS_IPHONE`, with an `AVCaptureDevice`-based macOS fallback for
microphone permission, so the same source compiles for both platforms.

This macOS build is **not a shipping target** -- it exists purely so the
macOS editor can load the extension and hand its iOS artifacts to the
exporter. It is also incidentally useful for in-editor speech testing on a
Mac, since macOS genuinely has `SFSpeechRecognizer` + `AVAudioEngine`, but
that is a bonus, not the goal.

Verified fix: after adding the macOS entries and rebuilding, a real
`godot --headless --export-debug "iOS" ...` against a throwaway project
copy produced **zero** GDExtension errors, and the resulting
`project.pbxproj` contains the iOS xcframework, both system frameworks, and
a correctly generated entry-symbol registration shim (see "Status" above,
items 3-6).

## Why not `.gdip` (root cause #2, confirmed)

The previous round's `little_buddy_speech.gdip` (Godot 3.x-style iOS plugin
descriptor) was never going to work, independent of its exact
section/key wording. Confirmed by inspecting the shipped Godot 4.7.2
editor binary directly:

- The only `"Invalid plugin config file "` string anywhere in the binary
  is tied to `platform/android/export/export_plugin.cpp` (verified via
  `strings` + surrounding context: `android/plugins`, `plugins/`,
  `"Android .so file names must start with \"lib\""`, etc. all cluster
  around the exact same string offset). There is no equivalent iOS
  `.gdip`-parsing code path anywhere in this engine build.
- Godot 4.7's iOS/"apple embedded" exporter (`editor_export_platform_apple_embedded.cpp`,
  confirmed present) instead exposes framework/linker/plist injection to
  **script-level `EditorExportPlugin`s** via a documented set of methods,
  confirmed present in the binary's symbol table:
  `add_ios_framework`, `add_ios_embedded_framework`,
  `add_ios_project_static_lib`, `add_ios_plist_content`,
  `add_ios_linker_flags`, `add_ios_bundle_file`, `add_ios_cpp_code` (plus
  generic `add_apple_embedded_platform_*` equivalents shared with
  tvOS/visionOS).

**Fix**: `little_buddy_speech.gdip` is left in place only as a documented
paper trail (see the file itself) of what was tried and ruled out -- it is
not referenced by anything and must not be copied into `game/`. In its
place, `godot_project_overlay/addons/little_buddy_speech_export/` is a
minimal `EditorPlugin` + `EditorExportPlugin` pair: it calls
`add_ios_framework("Speech.framework")` and
`add_ios_framework("AVFoundation.framework")` from `_export_begin()` when
exporting for iOS, and does nothing else (no plist content -- the
project's own `export_presets.cfg` already declares
`NSMicrophoneUsageDescription`/`NSSpeechRecognitionUsageDescription`; no
bundle files; no linker flags; no injected code). This does not add a
network dependency or any third-party binary -- both frameworks ship with
every iOS SDK.

Verified fix: confirmed above (Status items 3-4) -- both frameworks are
present in the `PBXFrameworksBuildPhase` of the exported project, for both
debug and release exports.

## What is actually here

```
ios/speech_plugin/
├── src/
│   ├── little_buddy_speech.h      C++ GDExtension class declaration
│   ├── little_buddy_speech.mm     Objective-C++ implementation:
│   │                                - LBSpeechController (Obj-C):
│   │                                  SFSpeechRecognizer + AVAudioEngine,
│   │                                  with #if TARGET_OS_IPHONE guards so
│   │                                  it also compiles for macOS
│   │                                - LittleBuddySpeech (C++/GDExtension):
│   │                                  binds methods/signals, forwards to
│   │                                  the Obj-C controller
│   ├── register_types.h/.cpp      GDExtension init/singleton registration
├── littlebuddyspeech.gdextension  GDExtension descriptor: ios.* (shipping)
│                                    + macos.* (editor-load only, see above)
├── little_buddy_speech.gdip       DEAD/unused -- kept only as a documented
│                                    paper trail, see "Why not .gdip"
├── SConstruct                     Build script: iOS static lib + macOS
│                                    shared lib/framework branches
├── build_xcframeworks.sh          One-shot rebuild → bin/*.ios.*.xcframework
├── build_macos_framework.sh       One-shot rebuild → bin/*.macos.*.framework
├── godot_project_overlay/         Proposed res:// layout for the
│   └── addons/little_buddy_speech_export/
│       ├── plugin.cfg               EditorPlugin manifest
│       ├── plugin.gd                 registers the export plugin below
│       └── little_buddy_speech_export_plugin.gd
│                                    EditorExportPlugin: add_ios_framework
│                                    for Speech.framework/AVFoundation.framework
├── godot-cpp/                     Vendored dependency, branch "4.5" (gitignored;
│                                    `git clone -b 4.5 --depth 1 ... godot-cpp`)
├── bin/                           Build outputs (see .gitignore — only the
│   │                                final .xcframework/.framework matter
│   │                                long-term)
│   ├── liblittle_buddy_speech.ios.debug.xcframework      (iOS, shipping)
│   ├── liblittle_buddy_speech.ios.release.xcframework    (iOS, shipping)
│   ├── liblittle_buddy_speech.macos.template_debug.framework   (editor-load only)
│   └── liblittle_buddy_speech.macos.template_release.framework (editor-load only)
└── README.md                      This file
```

## Design (what the code is trying to do)

- Exposes an Engine singleton named `LittleBuddySpeech` matching exactly the
  contract `game/scripts/speech/ios_speech_backend.gd` expects:
  methods `is_available`, `has_permission`, `request_permission`,
  `start_listening(locale)`, `stop_listening`; signals `permission_result`,
  `recognized`, `recognition_failed`, `listening_started`,
  `listening_stopped`.
- Forces **on-device recognition only**:
  `SFSpeechAudioBufferRecognitionRequest.requiresOnDeviceRecognition = YES`.
  `is_available()` additionally checks
  `SFSpeechRecognizer.supportsOnDeviceRecognition` and reports `false`
  (rather than silently using server-based recognition) if on-device
  recognition isn't supported for the current locale/device. This check now
  reads `@available(iOS 13.0, macOS 10.15, *)` so the same source serves
  both platforms.
- Audio flows straight from the `AVAudioEngine` input tap buffer into the
  recognition request, in memory, and is discarded once each buffer is
  processed. **No audio is ever written to a file, cached, or sent over the
  network.** No networking code exists anywhere in this plugin, on either
  platform.
- `stop_listening` / error / final-result paths all funnel through one
  `_finishListening` teardown so the audio tap and engine are always torn
  down and (on iOS) the `AVAudioSession` is deactivated -- no dangling mic
  capture.
- On macOS, microphone permission uses `AVCaptureDevice` instead of
  `AVAudioSession` (which doesn't exist there), and there is no explicit
  audio-session category/activation step -- `AVAudioEngine` on macOS talks
  to the default input device directly.

## What is honestly still uncertain / needs on-device verification

1. Runtime behavior of the `AVAudioSession` category
   (`AVAudioSessionCategoryRecord` + `AVAudioSessionModeMeasurement`) against
   however Godot's own iOS audio driver configures the shared
   `AVAudioSession` at runtime -- there is a realistic risk of the two
   competing for the audio session category. This can only be observed by
   running the exported app on-device or in the simulator.
2. Whether `little_buddy_speech_library_init` actually gets invoked and the
   `LittleBuddySpeech` singleton actually appears in `Engine.has_singleton(...)`
   at runtime. The generated static-initializer/`register_dynamic_symbol`
   chain (see Status item 4) is Godot's own documented mechanism for this
   exact static-linking situation and was read directly out of the
   generated `dummy.cpp`, not assumed -- but it has not been observed firing
   on a live device or in the simulator.
3. Code-signed builds (a real Apple Developer certificate/provisioning
   profile) were not exercised -- only `CODE_SIGNING_ALLOWED=NO` builds.

## Build steps (verified — reproducible via the two build scripts)

1. `git clone -b 4.5 --depth 1 https://github.com/godotengine/godot-cpp ios/speech_plugin/godot-cpp`
2. `export PATH="$HOME/Library/Python/3.9/bin:$PATH"` (or wherever your
   `scons` lives)
3. `cd ios/speech_plugin && ./build_xcframeworks.sh` -- iOS device
   xcframeworks (shipping).
4. `./build_macos_framework.sh` -- macOS arm64 `.framework`s (editor-load
   only, required for the exporter to pick up step 3's output at all -- see
   "Why a macOS build").
5. (Orchestrator, in `game/`, not this directory) Copy/symlink
   `littlebuddyspeech.gdextension` and `bin/` into the Godot project under
   `res://ios/speech_plugin/`, and copy
   `godot_project_overlay/addons/little_buddy_speech_export/` into
   `res://addons/little_buddy_speech_export/`. See "Exact res:// layout to
   copy" below for the precise file list and the one `project.godot` edit
   needed to enable the addon.
6. Export → iOS (debug or release). Verified: the iOS xcframework and both
   system frameworks land in the generated Xcode project, and
   `xcodebuild ... build` succeeds (see "Status" above).

## Exact `res://` layout to copy into `game/`

```
game/ios/speech_plugin/littlebuddyspeech.gdextension
game/ios/speech_plugin/bin/liblittle_buddy_speech.ios.debug.xcframework/       (whole dir)
game/ios/speech_plugin/bin/liblittle_buddy_speech.ios.release.xcframework/    (whole dir)
game/ios/speech_plugin/bin/liblittle_buddy_speech.macos.template_debug.framework/    (whole dir)
game/ios/speech_plugin/bin/liblittle_buddy_speech.macos.template_release.framework/  (whole dir)
game/addons/little_buddy_speech_export/plugin.cfg
game/addons/little_buddy_speech_export/plugin.gd
game/addons/little_buddy_speech_export/little_buddy_speech_export_plugin.gd
```

Plus one edit to `game/project.godot` to enable the addon (without this,
`_export_begin()` never runs and the frameworks never get linked):
```
[editor_plugins]

enabled=PackedStringArray("res://addons/little_buddy_speech_export/plugin.cfg")
```

If `game/project.godot` already has an `[editor_plugins]` section, add the
path into the existing `enabled` array instead of creating a second
section.

Do **not** copy `little_buddy_speech.gdip` or `ios/plugins/` anywhere --
that mechanism is dead in Godot 4.7 (see "Why not .gdip").

After copying, delete `game/.godot/extension_list.cfg` if present (forces
Godot to rescan for GDExtensions) before the next editor open or export.

## Manual Xcode / Info.plist steps (do these regardless)

After exporting the Godot project to Xcode, open the generated `.xcodeproj`
and manually verify/add:

1. **Signing & Capabilities** → select your Apple ID / Personal Team, set a
   unique Bundle Identifier. (Verification in this round used
   `CODE_SIGNING_ALLOWED=NO` since no device/profile is available here --
   this step is unverified.)
2. **Info.plist** → confirm these two keys exist with parent-readable
   wording (they should already be present via `export_presets.cfg`'s
   `privacy/microphone_usage_description` and
   `application/additional_plist_content` -- verify, add by hand if
   missing):
   - `NSMicrophoneUsageDescription`
   - `NSSpeechRecognitionUsageDescription`
3. **Build Phases → Link Binary With Libraries** → confirmed present by this
   round's export+build verification: `Speech.framework` and
   `AVFoundation.framework`. Spot-check after any future re-export in case
   the addon above didn't run (Project Settings → Plugins must show
   "Little Buddy Speech Export" enabled).
4. **General → Deployment Info** → minimum iOS version 15.0 is already set
   in `export_presets.cfg`, which supports `supportsOnDeviceRecognition`
   (iOS 13+).
5. Connect the physical iPad, trust the developer certificate on-device if
   prompted (Settings → General → VPN & Device Management), enable Developer
   Mode on iPadOS if requested, then Run.
6. On first launch, tap the microphone/Speak button once to trigger the
   system permission prompts for microphone and speech recognition; verify
   both prompts show the wording from step 2, not generic Xcode boilerplate.
7. If the app does not show `LittleBuddySpeech` as available
   (`SpeechService.get_backend_name()` will report `"unavailable"` instead
   of `"ios"`), touch-only feeding still works -- this is expected, safe,
   degraded behavior, not a crash.

## Never do this

- Never remove `requiresOnDeviceRecognition = YES`.
- Never add code that writes an `AVAudioPCMBuffer` to a file or forwards it
  over a socket/HTTP request.
- Never add a network dependency to satisfy a "better" recognizer — offline
  operation is a hard project requirement. (This applies equally to the
  macOS build, which exists only for editor-load/export purposes -- it must
  never be treated as an excuse to add any networked speech path.)
