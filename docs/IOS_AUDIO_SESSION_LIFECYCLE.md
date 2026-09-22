# iOS Audio Session Lifecycle

## Ownership

Godot owns normal game playback. The native speech plugin temporarily owns the
process-wide `AVAudioSession` configuration only while a gated Tutor session is
active. It does not deactivate the shared session.

1. Enter Tutor: preserve category, mode, and options; configure
   `PlayAndRecord` + `VoiceChat` once; activate once.
2. Tutor turns: start/stop recognition without changing the category.
3. Leave/background/quota end: stop recognition, then restore the preserved
   category, mode, and options.
4. Media-services reset: record the reset and reapply the Tutor configuration
   only when the Tutor lifecycle is still active.

All configuration is marshalled to the main thread. The plugin removes every
notification observer during teardown.

## Local diagnostics

The existing debug diagnostics include Godot driver/mix rate and a native JSON
snapshot containing category, mode, sample rate, I/O buffer duration, input and
output channel counts, current/previous route, route-change reason,
interruption/media-reset events, other-audio hints, microphone permission,
recognizer state, and Tutor-session state. Diagnostics contain no raw audio and
are not uploaded.

## Invariants

- No category toggle per utterance.
- Recognition is stopped before the prior session configuration is restored.
- Foregrounding never silently reopens the microphone.
- A route/reset event is observable instead of being inferred from a decoder
  stack frame.
- Production child audio remains disabled by backend policy.
