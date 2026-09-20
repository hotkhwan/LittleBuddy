# Owner voice lines (drop-in)

Put a recording here as `<lineId>.ogg` (or `.wav` / `.mp3`) and it plays instead
of the platform voice for that exact English line. Nothing else changes: a line
without a file keeps using TTS. The ids and the list of lines to record are in
`docs/VOICE_ASSET_REQUEST.md`; the lookup is `scripts/speech/voice_lines.gd`.

Mono or stereo, 44.1 kHz, peak around -3 dBFS, no leading silence, ~0.1 s tail.
