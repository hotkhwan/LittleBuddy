# iPhone launch crash (SIGABRT in dyld) — root cause and fix, 2026-09-21

## Symptom
Xcode: `Thread 1: signal SIGABRT`, top frame `dyld\`__abort_with_payload`; the
app never reaches Godot. The arm64 build had succeeded, which is why no
automated gate caught it.

## Exact dyld error
The owner's device log was not available on this Mac. The failure is
reproduced from the built binary instead: the executable exported from
`f510be8` carries an **undefined dynamic symbol** that dyld must resolve at
launch and cannot:
```
$ nm -u LittleBuddy.app/LittleBuddy | grep little_buddy_speech
_little_buddy_speech_library_init
```
With the project's `OTHER_LDFLAGS = -Wl,-U,_little_buddy_speech_library_init`
the linker accepts the missing symbol; dyld then fails at load with
`Symbol not found: _little_buddy_speech_library_init` and aborts with payload.
(If the owner's log names a different payload, send it and this note will be
corrected; the symbol above is a launch-time failure regardless.)

## Confirmed root cause
Commit `1af02bb` (an agent's work-in-progress commit, cherry-picked into the
branch) added a **tracked symlink** `game/ios/speech_plugin/bin ->
/Users/hotkhwan/Projects/LittleBuddy-latest/game/ios/speech_plugin/bin`, i.e. a
self-loop. Checking it out replaced the real (gitignored) folder that holds
the compiled speech plugin. `.gitignore` had `game/ios/speech_plugin/bin/`,
which matches a directory but not a symlink, so `git add -A` picked it up.
Consequences during `tools/export_ios.sh`:
- the editor logged `Can't open GDExtension dynamic library:
  'res://ios/speech_plugin/littlebuddyspeech.gdextension'` (errno 62, too many
  levels of symbolic links);
- Godot's GDExtension export plugin therefore never bundled
  `liblittle_buddy_speech.ios.*.xcframework` into the Xcode project, while the
  generated `dummy.cpp` still references the entry symbol;
- the app linked (thanks to `-U`), installed, and died in dyld.
Not the cause: Meshy assets, code signing, architecture (binary is arm64,
platform iOS, minos 15.0), embedded frameworks (none; everything is static),
Info.plist keys.

## Fix applied (smallest correct)
1. `git rm --cached game/ios/speech_plugin/bin`; the symlink deleted; the real
   folder restored from the plugin build output `ios/speech_plugin/bin/`
   (`liblittle_buddy_speech.ios.debug.xcframework`, `.ios.release.xcframework`,
   the two macOS editor frameworks). Not committed (still ignored by design).
2. `.gitignore`: added `game/ios/speech_plugin/bin` (no trailing slash) so a
   symlink at that path is ignored too.
3. `tools/export_ios.sh`: preflight fails if `bin` is a symlink, is tracked, is
   missing a framework, or the iOS slice is not arm64; post-export fails if
   the Godot log shows `Can't open GDExtension` or the Xcode project lacks the
   plugin library. The export log is kept at `build/ios_export.log`.
4. Re-exported and rebuilt:
   ```
   $ tools/export_ios.sh                      # no "Can't open GDExtension"; plugin in pbxproj
   $ xcodebuild -project build/ios/LittleBuddy.xcodeproj -scheme LittleBuddy \
       -configuration Debug -destination 'generic/platform=iOS' \
       -derivedDataPath /tmp/lb_dd CODE_SIGNING_ALLOWED=NO build   # ** BUILD SUCCEEDED **
   $ nm -u .../LittleBuddy.app/LittleBuddy | grep -c little_buddy_speech   # 0
   $ nm    .../LittleBuddy.app/LittleBuddy | grep -c 'little_buddy_speech_library_init\|LBSpeechController'   # 73
   ```

## Which builds were affected
Every iOS export made after `1af02bb` was integrated (the `f510be8` artefacts
the owner installed). The owner-test build `bb2c3e7` predates it, but its
exported Xcode project in `build/ios` had since been overwritten; re-export
from any commit after this fix.

## Owner steps in Xcode (device run)
1. `tools/export_ios.sh` (or use the freshly exported `build/ios/LittleBuddy.xcodeproj`).
2. Open the project, select the `LittleBuddy` target → Signing & Capabilities →
   your Team; keep the bundle id or change it to one your team owns.
3. Select the iPhone as destination, Product → Run.
4. First launch: allow the Local Network / no prompt; on entering Learn with
   Aliz, iOS asks for Microphone and Speech Recognition — allow both.
5. If it still aborts: Window → Devices and Simulators → View Device Logs →
   copy the `Termination Reason` / `dyld` lines and send them.

## Validation status
| Check | Status |
|---|---|
| Xcode build (arm64, unsigned) | PASS |
| iOS app installation on a device | NOT TESTED (no device / signing identity on this Mac) |
| Physical-device launch | NOT TESTED |
| Godot main scene reached on device | NOT TESTED |
| Gameplay smoke on device | NOT TESTED |
