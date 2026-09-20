# Speech — Physical Device Validation

**Date:** 2026-09-17 · **Device:** iPhone 14 Pro Max (`iPhone15,3`), iOS 26.6.2
**Status: PROVEN WORKING ON DEVICE.**

This closes the item that had been the project's single blocking unknown since the speech
plugin was first written.

---

## How it was validated

There is no console on a device, so `SpeechService` writes a capability snapshot to
`user://speech_diag.json`, which is pulled off the device with:

```bash
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier com.pointit.littlebuddy \
  --source Documents/speech_diag.json --destination ./speech_diag.json
```

It records **capability flags and counts only — never a transcript.** A transcription of a
child's speech is exactly the derived personal data this project refuses to persist.

## Evidence

**First pull — the stack was alive, but every session "failed":**

```json
{ "backend": "ios", "nativeSingletonPresent": true, "isAvailable": true,
  "hasPermission": true, "ttsAvailable": true,
  "listenCount": 3, "recognizedCount": 5, "failedCount": 3,
  "lastFailureReason": "recognition_error" }
```

Owner's report: *"ขึ้นให้ Try again แล้วเสียงพูดก็เบาลง"* — the UI said **Try again**, and TTS
got **quieter**.

The decisive detail: partial results are deliberately **not** emitted as `recognized`
(`if (!result.isFinal) return;`), so `recognizedCount: 5` meant **five genuine final
transcripts already reached GDScript.** Recognition was working; the UI was misreporting it.

**After the fix:**

```json
{ "listenCount": 4, "recognizedCount": 7, "failedCount": 3, "launchCount": 2 }
```

One new listen session produced **two recognitions and zero new failures**. Stars went
**46 → 64**, and `sayPillow`, `sayBanana`, `sayTowel` completed — the child speaks and earns
the star. Owner confirmed on device.

---

## The two bugs

### 1. A trailing error masked a successful recognition

`SFSpeechRecognitionTask` commonly fires its result handler once more with an `NSError`
(`kAFAssistantErrorDomain` 216 / 1110 "no speech detected") **after** delivering the final
result, as the audio tap tears down. The code treated that as failure and showed "Try again!",
overwriting a success the child had already earned.

**Fix:** a session that emits a final transcript sets `hasReportedResult`; any error arriving
afterwards is dropped. Teardown still runs, and `listening_stopped` still fires exactly once
(guarded by the `wasListening` capture inside `_finishListening`).

### 2. TTS and SFX got quieter when the mic opened

`AVAudioSessionModeMeasurement` disables system signal processing **and routes output to the
receiver instead of the speaker**.

**Fix:** `AVAudioSessionModeDefault`, plus an explicit
`overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker` after activation —
`DefaultToSpeaker` only sets the *default* route, not the *active* one.

---

## Privacy guarantees, re-confirmed on device

- `requiresOnDeviceRecognition = YES`; **no server fallback**, ever.
- **No networking framework is linked into the app at all** — `otool -L` shows zero
  CFNetwork/Network.framework. Uploading is structurally impossible, not merely disabled.
- No audio is written to disk or transmitted; buffers go from the input tap straight into the
  recognition request in memory.
- The diagnostic file contains flags and counts only.

## A process lesson worth keeping

The first diagnostic build reset its counters in `_ready()`, so every relaunch wiped the
evidence — and separately, the agent's own `--terminate-existing` retry loop was **killing the
app while the owner was testing it**, which looked exactly like a crash ("เด้งหลุด"). No crash
report existed on the device, which is what exposed it.

Counters now persist across launches, and device testing is left entirely to the human: the
tooling installs the build and never launches or terminates it.

## Remaining speech unknowns

- Behaviour when permission is **denied** has not been re-tested since the fix (touch fallback
  is unchanged and still covered by tests).
- A real interruption (Siri / incoming call) mid-listen has not been triggered on device; the
  `AVAudioSessionInterruptionNotification` handling is code-reviewed, not observed.
- Only one device and one locale (en-US) have been exercised.


---

## 2026-09-20 — voice pass (Agent E, branch `wt/voice`). NOT device-validated.

Everything below was done on the MacBook only. **No iPhone/iPad run happened in this pass**,
so the "PROVEN WORKING ON DEVICE" status above still refers to the 2026-09-17 build, and the
changes here must be re-checked on the device before that status is claimed for them.

### What changed in the speech stack

- Native plugin (`ios/speech_plugin/src/little_buddy_speech.mm/.h`): new `partial_result(text)`
  signal for interim hypotheses; `stop_listening()` now reports the last hypothesis as
  `recognized` instead of cancelling it away (same policy as the existing 5 s timeout).
  Rebuilt on this Mac: macOS frameworks (`build_macos_framework.sh`) and iOS xcframeworks
  (`build_xcframeworks.sh`, Xcode 26.6, godot-cpp 4.5, exit 0; `partial_result` present in the
  `ios-arm64` archive). Outputs are in the worktree's `game/ios/speech_plugin/bin` (gitignored);
  the lead rebuilds in the main checkout for the export.
- `SpeechService.start_listening()` stops TTS before the microphone opens.
- `SpeechFeedbackBinder` ends listening as soon as a hypothesis matches the prompt; the
  backend's final for that hypothesis then completes the task.
- `TtsService`: voice preference chain (premium/enhanced Zoe/Nicky/Ava/Allison/Samantha before
  compact Samantha), pitch 1.15, rate 0.92, `react()` for encouragement, and completion by
  polling `tts_is_speaking()` after start.

### Facts measured on the Mac

- Voice list: the only natural en-US voice installed is `com.apple.voice.compact.en-US.Samantha`
  (full list in `docs/VOICE_HONESTY_PASS.md`). Chosen voice: Samantha (compact).
- A windowed `tts_service.gd` run: the macOS synthesiser reported itself speaking for each of
  "Great!" / "I'm hungry, Aliz!" / "Let's make some milk!" (1.28 s / 1.5 s / 1.4 s). The
  utterance ENDED callback did not arrive in that run; the poll resolved each line.
- With the plugin loaded in the editor: `Engine.has_singleton("LittleBuddySpeech") = true`,
  `is_available = true`, `has_permission = false` (macOS has not been asked yet). The Mac
  playtest therefore runs the REAL recogniser, not the mock.
- Suite: 122 cases, 0 failures. Both mission smokes (`imHungry`, `snackTime`) pass.

### To verify on the iPhone 14 Pro Max / iPad (not done)

1. Pull `user://speech_diag.json` after a session; `recognizedCount` should rise once per
   understood attempt and `lastFailureReason` should not be `timeout` for a spoken word.
2. Say "milk" at a `sayIt` prompt: the panel should show "I hear: milk" within ~0.5 s and
   "Great!" without waiting for the 5 s window. NOTE: in the house the task will only
   complete by speech once `docs/patches/agentE_house_level_director.diff` is applied —
   the transcript is not wired to the runner there today.
3. Confirm TTS is still on the loudspeaker after the first mic session (the 09-17 fix).
4. If a parent downloads Zoe (Premium) or Samantha (Enhanced) in Settings > Accessibility >
   Spoken Content > Voices, the parent diagnostic's "Voice name" row should show it within 10 s.
