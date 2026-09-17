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
