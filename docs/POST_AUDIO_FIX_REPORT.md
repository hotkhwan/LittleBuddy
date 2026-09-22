# Post-audio Candidate Report

## Status

The decoder crash remains unreproduced and its root cause is **not confirmed**.
The Ogg/PCK integrity work at `5ad1165` remains authoritative and was not
repeated. The dual-driver theory remains a latent engine risk, not the observed
cause.

The candidate addresses the concrete AVAudioSession ownership gap: Tutor now
pins one VoiceChat session across all turns, restores the previous state at
exit, and exposes local route/interruption/sample-rate telemetry. A regression
test pins the one-enter/one-exit lifecycle.

## Release gate

Native compilation, Godot tests, iOS export guards, arm64 inspection, and
undefined-symbol inspection may pass off-device. Crash resolution must remain
open until the affected device completes the checklist in `IOS_DEVICE_QA.md`.
Cloud learning and Expression Director expansion remains secondary to this
device gate; production child audio, billing, and production enablement remain
off.
