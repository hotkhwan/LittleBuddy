# LittleBuddySpeech — iOS native speech plugin

## Status: runtime bugs fixed this round (see "Runtime fixes" below); iOS
## export pickup was already confirmed working end-to-end (previous round)

The previous round confirmed the plugin *links and exports* correctly
end-to-end. It compiled and even bound into the exported binary, but speech
did not actually work when the app ran on a physical iPhone. This round's
job was root-causing and fixing that. See "Runtime fixes (this round)" for
the full write-up, "Simulator verification (this round)" for what was and
was not directly observed running, and "On-device only, by design, always"
for one deliberate place this round did NOT follow the literal brief.

## Runtime fixes (this round)

Five concrete bugs were found and fixed, three of them in
`game/scripts/speech/**` / `ios/speech_plugin/src/little_buddy_speech.mm`
severe enough to fully explain "speech does not work on a real device" on
their own:

1. **`SpeechService._select_backend()` picked its backend ONCE, based on a
   possibly-premature snapshot, and then never revisited that decision —
   this alone could permanently disable speech for the app's entire
   lifetime.** (`game/scripts/speech/speech_service.gd`)
   `_select_backend()` runs once, in `_ready()`, essentially on app launch.
   It used to call `IosSpeechBackend.new().is_available()` and only pick the
   native backend if that one call returned `true` *right then* — otherwise
   it permanently fell back to the inert no-op `SpeechBackend`, forever,
   even though nothing ever re-checks. But native `is_available()` depends
   on `SFSpeechRecognizer.isAvailable`, a KVO-observed property that is not
   guaranteed `true` immediately after the recognizer object is constructed,
   and no permission has even been requested yet at that point in the app's
   lifecycle. A single early `false` (plausible, not even an edge case) would
   silently and permanently disable speech for the rest of the session, even
   after the recognizer became available and the user granted permission.
   **Fix**: pick `IosSpeechBackend` whenever the native singleton is merely
   *present* (`Engine.has_singleton("LittleBuddySpeech")`), not only when a
   one-time availability snapshot happened to be `true`. `is_available()` is
   still evaluated live, on every call, straight through to the native
   object — this only stops baking in a premature permanent decision.
   Verified live (see "Verification performed" below): with the singleton
   registered, `SpeechService.get_backend_name()` now reliably returns
   `"ios"`.

2. **`listening_stopped` was only ever emitted on a manual `stop_listening()`
   call — never on a final recognition result or an error.** (`little_buddy_speech.mm`)
   `IosSpeechBackend._on_listening_stopped()` is the only thing that clears
   the cached `is_listening()` flag on the GDScript side, and
   `docs/INTEGRATION_CONTRACT.md` documents `listening_started` /
   `listening_stopped` as the pair that drives the "I'm listening..." UI.
   Since a successful or failed recognition never emitted
   `listening_stopped`, the very first use of Speak would leave
   `is_listening()` stuck `true` and any "I'm listening..." UI stuck on
   screen for the rest of the session, even though recognition itself may
   have quietly succeeded once. **Fix**: `_finishListening` is now the
   single place that emits `listening_stopped` (guarded so it only fires
   once per session), and every exit path — final result, error, the new
   ~5s timeout, and manual `stop_listening()` — funnels through it.

3. **`AVAudioSession` category was `.record` (input-only, exclusive)
   instead of `.playAndRecord`.** (`little_buddy_speech.mm`)
   `.record` is correct for an app whose *only* job is speech recognition
   (it's literally Apple's own sample-code pattern for that case), but
   Little Buddy is a game with its own concurrently-running Godot audio
   output (TTS prompts, sound effects) sharing the same process-wide
   `AVAudioSession`. Switching the shared session to an input-only,
   exclusive category every time Speak is tapped is a plausible way to
   silence or interrupt whatever Godot's own iOS audio driver already has
   playing through that same session — this was flagged as the single most
   likely runtime failure mode going in, and it is a real, concrete
   difference between "an app built to demonstrate `SFSpeechRecognizer`" and
   "a game that also needs to record". **Fix**: category is now
   `.playAndRecord`, mode `.measurement` (kept for on-device recognition
   accuracy), options `DefaultToSpeaker | AllowBluetoothHFP | MixWithOthers`.
   `_finishListening` also no longer force-deactivates the shared session
   (`setActive:NO`) on every stop, for the same reason — deactivating a
   session that Godot's own audio graph may still be actively rendering
   through risks interrupting/tearing down that graph. This was NOT
   independently observed against Godot's actual iOS audio driver (that
   requires a live device/simulator run with the audio driver active, which
   was not achievable this round — see "Simulator verification" below); it
   is a well-reasoned, Apple-documented, but still runtime-unverified fix.

4. **No auto-stop timeout existed.** (`little_buddy_speech.mm`)
   If the recognizer never produced a final result (silence, ambient noise,
   an ambiguous utterance), listening stayed open indefinitely — combined
   with bug #2 above, that's a listening session with no way out short of
   the user manually stopping it. **Fix**: a cancellable ~5s
   `dispatch_after` timeout (required behaviour #4). Partial results are now
   enabled (`shouldReportPartialResults = YES`) purely so the timeout path
   has a best-effort transcript to fall back to; if none was captured, it
   reports `recognition_failed("timeout")` instead.

5. **Permission callbacks marshalled via `dispatch_async(main_queue)` into
   direct `emit_signal` calls, not `call_deferred`.** (`little_buddy_speech.mm`)
   Apple documents `SFSpeechRecognizer.requestAuthorization`,
   `AVAudioSession.requestRecordPermission`, and the
   `recognitionTaskWithRequest:` result handler as running on an arbitrary,
   unspecified queue. The existing code already hopped to
   `dispatch_get_main_queue()` before calling into Godot, which likely made
   this a non-issue in practice on iOS's main-thread-driven run loop — but
   `Object::call_deferred("emit_signal", ...)` is Godot's own documented,
   thread-safe mechanism for exactly this kind of external-callback
   marshalling, so all five `_emit_*` methods now use it instead of calling
   `emit_signal` directly. Belt-and-braces, not a confirmed observed crash.

Two smaller, defensive fixes rounded this out: `hasPermission`/
`requestPermission` now use the modern `AVAudioApplication` record-permission
API on iOS 17+ (falling back to the deprecated-but-functional
`AVAudioSession` API on iOS 15/16, since `export_presets.cfg` sets a 15.0
minimum), and a guard against a zero-rate/zero-channel input format that
some devices can report if queried before the audio session has fully
settled.

## On-device only, by design, always (one deliberate divergence from the brief)

The brief that prompted this round said on-device recognition should be
*preferred*, but if `supportsOnDeviceRecognition` is `false`, the plugin
should "still work rather than refusing" — i.e., fall back to Apple's
server-based (networked) recognition.

This plugin does **not** do that, deliberately. This repository's own
`CLAUDE.md` states, as a hard, non-negotiable project rule: **"No network
dependency"** and **no persisted/uploaded child microphone audio**. Enabling
server-based recognition when on-device is unsupported would mean uploading
the child's voice audio to Apple's servers over the network — that directly
contradicts both rules, and no instruction short of the project owner's own
explicit change to `CLAUDE.md` can authorize it.

`requiresOnDeviceRecognition` therefore remains hard-forced to `YES`, and
`isAvailable` still gates on `supportsOnDeviceRecognition`. In the case where
on-device recognition genuinely is not supported, `is_available()` reports
`false` and `start_listening()` reports `recognition_failed("unavailable")`
honestly — touch-only feeding was already designed to be fully complete
without speech (`docs/INTEGRATION_CONTRACT.md`: "Touch gameplay must remain
fully playable when speech is unavailable, denied, or errors"), so "the
child getting nothing" never actually happens; they just don't get the
optional speech shortcut on that specific device/locale combination. In
practice, on-device English recognition (`en-US`) is supported on
essentially every iPhone capable of running iOS 15+, so this divergence
should not matter for the family's actual physical device.

## Simulator verification (this round)

The device (`ios-arm64`) xcframework slice was rebuilt from the fixed
source and re-verified unchanged in kind (still device-only, still a plain
non-fat arm64 static archive). A NEW `ios-arm64_x86_64-simulator` slice was
added (see `build_xcframeworks.sh`, which now builds arm64 AND x86_64
Simulator archives and `lipo -create`s them into one universal simulator
`.a` before packaging), so the xcframework's `Info.plist` now declares
(and, verified with `lipo -info`, actually contains) both:

```
ios-arm64                    -> arm64 (device)
ios-arm64_x86_64-simulator   -> arm64 + x86_64 (Simulator, universal)
```

**What was verified, concretely, this round:**

- `scons platform=ios arch=arm64 ios_simulator=yes ...` (and the same for
  `x86_64`) compiles the fixed `little_buddy_speech.mm` cleanly for the
  Simulator SDK, for both debug and release.
- Exporting a throwaway copy of the project (`/tmp/sp_game` →
  `/tmp/sp_out`, never `game/` or `build/`) produced a `project.pbxproj`
  whose `PBXFrameworksBuildPhase` contains `Speech.framework`,
  `AVFoundation.framework`, and `liblittle_buddy_speech.ios.debug.xcframework`
  (same as the previous round's device-only verification), and the exported
  Xcode project directory (`LittleBuddy/dylibs/ios/speech_plugin/bin/...`)
  physically contains BOTH the `ios-arm64` and `ios-arm64_x86_64-simulator`
  directories from the xcframework.
- `xcodebuild -sdk iphonesimulator ARCHS=x86_64 ... build` (Simulator,
  unsigned) on that exported project produced **`** BUILD SUCCEEDED **`**,
  meaning the linker resolved `little_buddy_speech_library_init`,
  `Speech.framework`, and `AVFoundation.framework` for a real x86_64
  Simulator target using our plugin's x86_64 simulator archive.
- The plugin's own `ios-arm64-simulator` archive was independently confirmed
  to contain real arm64 object code for `register_dynamic_symbol`/
  `add_apple_embedded_platform_init_callback` (`nm -arch arm64`), i.e. our
  side of the arm64 Simulator story is correct.

**What could NOT be verified, and why — two stacked, external causes, not a
plugin defect:**

1. Godot 4.7.2's own official export template ships a `libgodot.a` for the
   iOS Simulator whose `Info.plist` claims `SupportedArchitectures: [arm64,
   x86_64]`, but the actual archive (confirmed with `lipo -info` on the raw,
   never-exported `ios.zip` template — not just our export output) is
   **x86_64 only**. Linking our plugin's `ios-arm64-simulator` slice against
   it for an `arm64` Simulator target fails with `_main`,
   `register_dynamic_symbol`, and `add_apple_embedded_platform_init_callback`
   all "undefined for architecture arm64" — because literally every object
   in Godot's own `libgodot.a` gets skipped as "wrong architecture" (`ld:
   warning: ignoring file ... found architecture 'x86_64', required
   architecture 'arm64'`, repeated for every single object in the archive).
   This is an upstream Godot export-template packaging defect, not anything
   under `ios/speech_plugin/**`.
2. Working around (1) by building/linking for `x86_64` instead (which DOES
   link and produce a `BUILD SUCCEEDED` `.app`, see above) still could not be
   **installed** on this host's iOS 27.0 Simulator runtime:
   `xcrun simctl install` fails with `IXUserPresentableErrorDomain code=4`:
   *"This app needs to be updated by the developer to work on this version
   of iOS... This device can run code for these platforms: iOS-simulator"*
   (x86_64 not listed). Rosetta 2 is installed and running on this host, but
   this Xcode 27 / iOS 27.0 Simulator runtime's CoreSimulator refuses the
   x86_64 binary outright — consistent with Apple having dropped
   Intel/Rosetta-translated iOS Simulator app support in this Xcode
   generation.

**Net result**: the export→link chain was verified end-to-end for the
Simulator using real tools (not just "it compiles"), including a genuine
`BUILD SUCCEEDED` on a real x86_64 Simulator target — but no `.app` could
actually be installed/launched/log-streamed in the Simulator in this
environment, for reasons entirely upstream of this plugin (a defective
official Godot template + this Xcode generation's simulator architecture
policy). **I did not observe `listening_started` firing, a permission
prompt, or any other live runtime signal in the Simulator or on a physical
device.** That remains unproven; see "What the user must do" below for how
to close that gap on the real hardware.

As an alternate, real (not simulated) sanity check on the shared
Objective-C++ logic, the macOS-loadable build of this same extension
(`liblittle_buddy_speech.macos.template_debug.framework`, loaded by a real
running Godot 4.7.2 process) was exercised directly:

```
Engine.has_singleton("LittleBuddySpeech") = true
LittleBuddySpeech.is_available()          = true   (real SFSpeechRecognizer, en-US, this Mac)
LittleBuddySpeech.has_permission()        = false  (correct: never requested)
```

and, with the fixed `SpeechService._select_backend()` running for real
inside a live Godot project boot (not `--script`, which skips autoloads):

```
SpeechService.get_backend_name() = "ios"
SpeechService.is_available()     = true
```

This confirms the GDExtension registration mechanism, the shared recognizer
construction/availability logic, and the backend-selection fix all execute
correctly in a live Godot process — but it exercises the macOS
`AVCaptureDevice` permission branch, not the iOS `AVAudioSession`/
`AVAudioApplication` branch or the audio-session-category fix (item 3
above), which are `#if TARGET_OS_IPHONE`-only and were not exercised by this
check.

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

1. **Whether the `.playAndRecord` + `MixWithOthers` audio-session fix (item 3
   in "Runtime fixes" above) actually resolves the conflict with Godot's own
   iOS audio driver.** This is the fix most likely to matter and the one
   least directly provable without a live device/simulator run with the
   audio driver active — see "Simulator verification" above for exactly why
   that run could not be completed in this environment.
2. Whether `little_buddy_speech_library_init` actually gets invoked and the
   `LittleBuddySpeech` singleton actually appears in `Engine.has_singleton(...)`
   **on a physical iOS device specifically.** It was, this round, confirmed
   to register correctly via the analogous macOS dylib-load mechanism (see
   "Simulator verification" above: `Engine.has_singleton("LittleBuddySpeech")
   == true` observed live), and the generated `dummy.cpp`'s
   `add_apple_embedded_platform_init_callback`/`register_dynamic_symbol`
   static-registration chain was read directly out of the exported project,
   not assumed — but the iOS-specific static-linking path itself was not
   observed firing on a live device or a genuinely booted Simulator this
   round either (see "Simulator verification" for why the Simulator boot
   itself was not achievable in this environment).
3. Whether the ~5s timeout, the `listening_stopped`-in-every-path fix, and
   the `call_deferred` marshalling behave correctly under real permission
   prompts and real microphone input — all confirmed by code
   inspection/compile and, for the parts of the logic shared with macOS, by
   a live (non-simulated) run, but not by a live iOS/Simulator recognition
   session.
4. Code-signed builds (a real Apple Developer certificate/provisioning
   profile) were not exercised -- only `CODE_SIGNING_ALLOWED=NO` builds.

## Build steps (verified — reproducible via the two build scripts)

1. `git clone -b 4.5 --depth 1 https://github.com/godotengine/godot-cpp ios/speech_plugin/godot-cpp`
2. `export PATH="$HOME/Library/Python/3.9/bin:$PATH"` (or wherever your
   `scons` lives)
3. `cd ios/speech_plugin && ./build_xcframeworks.sh` -- builds iOS device
   (arm64) AND iOS Simulator (arm64 + x86_64, lipo'd into one universal
   slice) archives, and packages both into the shipping xcframeworks.
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
6. Export → iOS (debug or release). Verified: the iOS xcframework (both
   platform slices) and both system frameworks land in the generated Xcode
   project, and `xcodebuild ... build` succeeds for both a device
   destination and (with `ARCHS=x86_64 -sdk iphonesimulator`, see "Simulator
   verification" above for why arm64-Simulator does not currently link with
   this Godot version) a Simulator destination.

**Gotcha for anyone re-testing locally**: deleting
`game/.godot/extension_list.cfg` forces a *rescan* the next time the
**editor** or an **export** runs (this is what `tools/export_ios.sh` and the
build verification above both do deliberately). A plain
`godot --headless --path game` **project run** (not the editor, not an
export) does **not** itself rescan or regenerate that cache file — if it's
missing, `Engine.has_singleton("LittleBuddySpeech")` will read `false` for
that run even though the extension is correctly declared, simply because
nothing repopulated the cache first. This is a desktop editor/tooling
quirk only; it has no bearing on the actual exported iOS binary, where
GDExtension registration is compiled in statically at export time (see
"Why a macOS build" above) and does not consult this cache file at all at
runtime.

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

## What to check on the physical iPhone this round (speech specifically)

Given the fixes above, on the actual iPhone the family will test on:

1. **Tap Speak once.** Expect a system microphone permission prompt, then
   (if granted) immediately after, a speech-recognition permission prompt
   (first launch only; subsequent taps just start listening). If nothing
   happens at all when tapping Speak, check `SpeechService.get_backend_name()`
   — if it says `"unavailable"`, the native singleton isn't registering on
   this specific build (see item 2 in "What is honestly still uncertain").
2. **After granting both permissions, tap Speak again and say "milk".**
   Expect: game audio does not cut out or glitch when listening starts (the
   `.playAndRecord`/`MixWithOthers` fix) — if it does, bug #3 in "Runtime
   fixes" was not fully resolved and is the next thing to investigate.
3. **Watch the "I'm listening..." indicator.** It must disappear within
   ~5 seconds no matter what — either because "milk" was recognized (baby
   should feed), or because of the new timeout. If it ever gets stuck on
   screen after the first attempt, bug #2 ("`listening_stopped` only on
   manual stop") has resurfaced or a new path was missed.
4. **Try it again a second and third time in the same app session** (not a
   fresh launch). This specifically exercises the backend-selection fix
   (bug #1) and the fact that `AVAudioSession` is no longer deactivated
   between attempts (bug #3's `_finishListening` change) — repeatable
   listening in the same session is exactly what those two fixes are for.
5. **Deny microphone/speech permission (in Settings, or by tapping Don't
   Allow) and confirm touch-only feeding still completes the activity end
   to end.** This was already true before this round and must remain true.

**What could still fail there that this round could not rule out**: the
`.playAndRecord` category fix is well-reasoned and Apple-documented but was
never observed against Godot's actual live iOS audio driver (see
"Simulator verification" — that run could not be completed in this
environment); if game audio still glitches or cuts out when Speak is
tapped, that is the most likely remaining culprit, and the next step would
be trying `AVAudioSessionModeDefault` instead of `.measurement`, or
`AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers` in place
of `MixWithOthers`, while watching for an audio-session interruption
notification arriving during Godot's own render callback.

## Never do this

- Never remove `requiresOnDeviceRecognition = YES`.
- Never add code that writes an `AVAudioPCMBuffer` to a file or forwards it
  over a socket/HTTP request.
- Never add a network dependency to satisfy a "better" recognizer — offline
  operation is a hard project requirement. (This applies equally to the
  macOS build, which exists only for editor-load/export purposes -- it must
  never be treated as an excuse to add any networked speech path.)
