# iOS Audio Crash Audit — shipped audio assets

**Date:** 2026-09-22
**Trigger:** crash on a physical iPad inside the Ogg Vorbis decoder
(`res2_inverse` → `vorbis_book_decodevv_add`).
**Engine:** Godot 4.7.2.stable.official.ed1daf0bf
**Checkout:** `/Users/hotkhwan/Projects/LittleBuddy-latest`
**Scope:** every audio asset that ships, in the source tree and in the exported
pack `build/ios/LittleBuddy.pck`.

## Verdict up front

**Every shipped audio asset is CLEAN. No asset in this build can explain the
decoder crash.**

Both Ogg Vorbis files are bit-perfect against the manifest, every one of their
561 Ogg pages passes a recomputed CRC32, their packet streams are complete and
well-formed, and both decode to their exact final frame through the real
libvorbis in Godot 4.7.2 — at 44.1 kHz, at 48 kHz through the resampler, across
a loop wrap, across 49 seeks each, and with four concurrent playbacks sharing
one stream object. Peak levels are sane, and not a single NaN or Inf frame was
produced in ~40 million decoded frames. No corrupt asset was found, so no
`.fixed.ogg` was produced and no re-encode was needed or performed.

## Follow-up: AVAudioSession candidate (2026-09-22)

The asset result above remains unchanged. Inspection after checkpoint
`5ad1165` found a separate integration risk: the speech plugin configured
`AVAudioSession` when recognition started but did not preserve or restore the
previous category/mode, while the shipped Tutor did not establish the stable
VoiceChat lifecycle its comments described.

The release-candidate change now configures `PlayAndRecord`/`VoiceChat` once
when a gated Tutor session begins, keeps it stable across turns, stops
recognition before exit, and restores the prior category/mode/options without
deactivating the process-wide session. Route changes, interruptions, media
service resets, silence hints, sample rate, buffer duration, channel counts,
route, permission state, and speech state are recorded locally as metadata;
no audio or transcript is included.

This is an evidence-based risk reduction, not a confirmed root-cause claim.
The original microphone-permission transition has not yet been reproduced in
this environment because no physical Apple device is available to CoreDevice.

All ten SFX are uncompressed 16-bit PCM WAV (`compress/mode=0`); **nothing in
this build converts a WAV to Vorbis at import time**, so the crashing code path
is reachable only through the two music tracks.

---

## Tooling

No `ffmpeg`, `ffprobe` or `oggdec` exists on this machine and none was
installed. Everything below was produced by purpose-written stdlib-only tools
committed under `tools/audio_audit/`:

| Tool | What it does |
| --- | --- |
| `tools/audio_audit/ogg_probe.py` | Standalone Ogg container + Vorbis codec validator. Walks every page, recomputes the Ogg CRC32 (poly `0x04c11db7`, init 0, no reflection, no final xor), checks version/flags/serials/sequence monotonicity, reassembles packets across page boundaries via the segment table, parses the `\x01vorbis` / `\x03vorbis` / `\x05vorbis` headers, and derives duration from the final granule position. |
| `tools/audio_audit/pck_read.py` | Godot 4 `.pck` reader, including the **pack format 4** layout new in Godot 4.7 (directory moved to the end of the pack; `file_count` lives at the directory offset stored as a `u64` at header byte `0x20`, not in the fixed header). Lists, extracts, and re-verifies every entry's stored MD5. |
| `tools/audio_audit/decode_all.gd` | Headless Godot harness that pulls every frame of every stream through the real engine decoder with `AudioStreamPlayback.mix_audio()`. |

### Parser validated in both directions

A validator that always says "clean" is worthless, so `ogg_probe.py` was checked
against deliberately damaged copies of a known-good file:

| Negative control | Result |
| --- | --- |
| One bit flipped at file offset 500000 of `hungry_bunny.ogg` | Caught: `bad CRC page seq 116 @0x498509, stored 0xd298aa37, computed 0xf9fb641a` |
| Truncated to 900000 bytes | Caught: `TRUNCATED_BODY at 0xdb143: page declares 4127 body bytes, only 2596 available` **and** `last page (sequence 207) does not have the EOS flag set -> file is truncated` |

The CRC implementation is additionally confirmed by the positive case: all 561
real pages across the two shipped files match their stored CRCs exactly, which a
wrong polynomial or wrong shift direction could not produce.

---

## 1. `game/audio/music/little_days_theme.ogg`

| Property | Value |
| --- | --- |
| Bytes | 1 412 253 (manifest `runtimeBytes` 1 412 253 — **MATCH**) |
| SHA-256 | `de5588a77ed8591b82dc0eec5e3a40e829953440598692b839ee86796132eaf8` (manifest `runtimeSha256` — **MATCH**) |
| Codec | Vorbis I, version 0, first packet `\x01vorbis` — OK |
| Channels / rate | 2 / 44 100 Hz |
| Bitrate nom / max / min | 128 000 / 0 / 0 |
| Blocksize 0 / 1 | 256 / 2048 |
| Vendor | `Xiph.Org libVorbis I 20200704 (Reducing Environment)` |
| Comment header | `\x03vorbis`, framing bit set, 5 tags (`TRACKID=littleDaysTheme`, `MASTER=…`, `title`, `artist`, `album`) |
| Setup header | `\x05vorbis`, 4 140 bytes, framing bit set in final byte |
| Serial numbers | 1 (`0x4082f9bf`) — not chained, not multiplexed |
| Pages | 329 |
| **Bad CRC pages** | **0** |
| Sequence gaps / non-monotonic | 0 |
| BOS on first page / EOS on last page | set / set |
| Final page truncated (trailing 255 lacing) | no |
| Packets | 5 715 total (3 header + 5 712 audio); none incomplete at EOF; 0 zero-length |
| Largest packet | 4 140 bytes (index 2 — the setup header) |
| Smallest packet | 30 bytes |
| Final granule | 4 088 952 |
| **Duration parsed** | 4 088 952 ÷ 44 100 = **92.720 s** |
| Manifest `runtimeDurationSeconds` | 92.719 s (**delta 0.001 s** — a rounding/truncation in the manifest, not a stream defect) |
| Loop | `.import` `loop=true, loop_offset=0`; manifest `loopStart=0.0, loopEnd=0.0` ("to end of file"). Loop point is at 0.0 s, well inside a 92.720 s stream — **no loop point past the end** |
| Full decode | **PASS** — 4 088 948 frames, reached natural end, peak 0.760789, 0 NaN/Inf |

**Verdict: CLEAN.** Container, codec, packets, granule, hash and full decode all
pass with zero findings.

## 2. `game/audio/music/hungry_bunny.ogg`

| Property | Value |
| --- | --- |
| Bytes | 999 758 (manifest `runtimeBytes` 999 758 — **MATCH**) |
| SHA-256 | `64653da1f483c78f9f1d704322c04da01e5eef1b43463389d30bb27a25694b3d` (manifest `runtimeSha256` — **MATCH**) |
| Codec | Vorbis I, version 0, first packet `\x01vorbis` — OK |
| Channels / rate | 2 / 44 100 Hz |
| Bitrate nom / max / min | 128 000 / 0 / 0 |
| Blocksize 0 / 1 | 256 / 2048 |
| Vendor | `Xiph.Org libVorbis I 20200704 (Reducing Environment)` |
| Comment header | `\x03vorbis`, framing bit set, 5 tags (`TRACKID=hungryBunny`, `MASTER=…`, `title`, `artist`, `album`) |
| Setup header | `\x05vorbis`, 4 140 bytes, framing bit set in final byte |
| Serial numbers | 1 (`0x4087977d`) — not chained, not multiplexed |
| Pages | 232 |
| **Bad CRC pages** | **0** |
| Sequence gaps / non-monotonic | 0 |
| BOS on first page / EOS on last page | set / set |
| Final page truncated (trailing 255 lacing) | no |
| Packets | 3 705 total (3 header + 3 702 audio); none incomplete at EOF; 0 zero-length |
| Largest packet | 4 140 bytes (index 2 — the setup header) |
| Smallest packet | 30 bytes |
| Final granule | 2 840 040 |
| **Duration parsed** | 2 840 040 ÷ 44 100 = **64.400 s** |
| Manifest `runtimeDurationSeconds` | 64.400 s (**delta 0.000 s**) |
| Loop | `.import` `loop=true, loop_offset=0`; manifest `loopStart=0.0, loopEnd=0.0`. **No loop point past the end** |
| Full decode | **PASS** — 2 840 036 frames, reached natural end, peak 0.784019, 0 NaN/Inf |

**Verdict: CLEAN.** Same as above: zero findings on every check.

### Note on both files (documentation only, not a defect)

The manifest records the encoder as `oggenc -q 4 --resample 44100 (Vorbis
1.4.3, …)`, but the vendor string baked into both streams is
`Xiph.Org libVorbis I 20200704`, i.e. **libvorbis 1.3.7**. The `1.4.3` is the
`vorbis-tools` version, not the library version. Worth correcting in
`game/content/audio/manifest.json` and `docs/ASSET_MANIFEST.md` for provenance
accuracy. It has no bearing on the crash — libvorbis 1.3.7 is the current
stable release and is also what Godot itself bundles.

---

## 3. Full decode through the real decoder

Harness: `tools/audio_audit/decode_all.gd`, run as

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
    --script /Users/hotkhwan/Projects/LittleBuddy-latest/tools/audio_audit/decode_all.gd
```

It exercises the three ways the game actually obtains a music stream
(`ResourceLoader.load()` of the imported resource, which is what the exported
iOS build uses; `AudioStreamOggVorbis.load_from_file()`, the
`audio_director.gd::_decode_source_file` fallback; and
`imported.duplicate(true)` with loop applied, which is exactly what
`audio_director.gd::_apply_loop` does before every play), then adds a loop-wrap
pass, a 49-position seek sweep, and a four-way concurrent-playback pass.

### Output verbatim (exit code 0)

```
### GODOT 4.7.2-stable (official)
### AudioServer mix_rate=44100.0 driver=Dummy speaker_mode=0

==========================================================
OGG res://audio/music/little_days_theme.ogg
  sourceBytes=1412253
  [imported] class=AudioStreamOggVorbis length=92.7200012207031s loop=true loop_offset=0.0 bpm=0.0 beat_count=0
  [imported] DECODE-TO-END frames=4088948 expected~4088952 ratio=1.0 reachedEnd=true lastPos=92.72s peak=0.760789 nanInf=0 nonSilentFrames=4086743
  [imported] LOOP-WRAP  decoded=4354048 frames (98.73s over a 92.72s stream) stillPlaying=true peak=0.760789 nanInf=0 loopCount=1
  [imported] SEEK-SWEEP 49 seeks, decoded=755993 frames peak=0.707631 nanInf=0 errors=0
  [imported] CONCURRENT 4 playbacks sharing one stream, decoded=2457600 frames peak=0.683837 nanInf=0
  [raw] class=AudioStreamOggVorbis length=92.7200012207031s loop=false loop_offset=0.0 bpm=0.0 beat_count=0
  [raw] DECODE-TO-END frames=4088948 expected~4088952 ratio=1.0 reachedEnd=true lastPos=92.72s peak=0.760789 nanInf=0 nonSilentFrames=4086743
  [duplicated] class=AudioStreamOggVorbis length=92.7200012207031s loop=true loop_offset=0.0 bpm=0.0 beat_count=0
  [duplicated] DECODE-TO-END frames=4088948 expected~4088952 ratio=1.0 reachedEnd=true lastPos=92.72s peak=0.760789 nanInf=0 nonSilentFrames=4086743
  packetSequence imported: pages=329 packets=5715 rate=44100.0 finalGranule=4088952
  packetSequence raw     : pages=329 packets=5715 rate=44100.0
  packetSequence: imported == raw  OK

==========================================================
OGG res://audio/music/hungry_bunny.ogg
  sourceBytes=999758
  [imported] class=AudioStreamOggVorbis length=64.4000015258789s loop=true loop_offset=0.0 bpm=0.0 beat_count=0
  [imported] DECODE-TO-END frames=2840036 expected~2840040 ratio=1.0 reachedEnd=true lastPos=64.4s peak=0.784019 nanInf=0 nonSilentFrames=2840034
  [imported] LOOP-WRAP  decoded=3104768 frames (70.4s over a 64.4s stream) stillPlaying=true peak=0.784019 nanInf=0 loopCount=1
  [imported] SEEK-SWEEP 49 seeks, decoded=755993 frames peak=0.723444 nanInf=0 errors=0
  [imported] CONCURRENT 4 playbacks sharing one stream, decoded=2457600 frames peak=0.784019 nanInf=0
  [raw] class=AudioStreamOggVorbis length=64.4000015258789s loop=false loop_offset=0.0 bpm=0.0 beat_count=0
  [raw] DECODE-TO-END frames=2840036 expected~2840040 ratio=1.0 reachedEnd=true lastPos=64.4s peak=0.784019 nanInf=0 nonSilentFrames=2840034
  [duplicated] class=AudioStreamOggVorbis length=64.4000015258789s loop=true loop_offset=0.0 bpm=0.0 beat_count=0
  [duplicated] DECODE-TO-END frames=2840036 expected~2840040 ratio=1.0 reachedEnd=true lastPos=64.4s peak=0.784019 nanInf=0 nonSilentFrames=2840034
  packetSequence imported: pages=232 packets=3705 rate=44100.0 finalGranule=2840040
  packetSequence raw     : pages=232 packets=3705 rate=44100.0
  packetSequence: imported == raw  OK

==========================================================
SFX (WAV)
  bedtime_chime.wav (imported)
  [  wav] class=AudioStreamWAV length=1.9s mix_rate=22050 stereo=false format=1 loop_mode=0 loop_begin=0 loop_end=0
  [  bedtime_chime.wav] DECODE-TO-END frames=83782 expected~83790 ratio=0.9999 reachedEnd=true lastPos=1.9s peak=0.354808 nanInf=0 nonSilentFrames=79906
  drop_return.wav (imported)
  [  wav] class=AudioStreamWAV length=0.32s mix_rate=22050 stereo=false format=1 loop_mode=0 loop_begin=0 loop_end=0
  [  drop_return.wav] DECODE-TO-END frames=14104 expected~14112 ratio=0.9994 reachedEnd=true lastPos=0.32s peak=0.316233 nanInf=0 nonSilentFrames=12782
  gentle_tap.wav (imported)
  [  wav] class=AudioStreamWAV length=0.08s mix_rate=22050 stereo=false format=1 loop_mode=0 loop_begin=0 loop_end=0
  [  gentle_tap.wav] DECODE-TO-END frames=3520 expected~3528 ratio=0.9977 reachedEnd=true lastPos=0.08s peak=0.201144 nanInf=0 nonSilentFrames=2923
  pickup.wav (imported)
  [  wav] class=AudioStreamWAV length=0.15002267573696s mix_rate=22050 stereo=false format=1 loop_mode=0 loop_begin=0 loop_end=0
  [  pickup.wav] DECODE-TO-END frames=6608 expected~6616 ratio=0.9988 reachedEnd=true lastPos=0.15s peak=0.316233 nanInf=0 nonSilentFrames=5923
  place_soft.wav (imported)
  [  wav] class=AudioStreamWAV length=0.3s mix_rate=22050 stereo=false format=1 loop_mode=0 loop_begin=0 loop_end=0
  [  place_soft.wav] DECODE-TO-END frames=13222 expected~13230 ratio=0.9994 reachedEnd=true lastPos=0.3s peak=0.281838 nanInf=0 nonSilentFrames=11354
  room_change.wav (imported)
  [  wav] class=AudioStreamWAV length=0.55002267573696s mix_rate=22050 stereo=false format=1 loop_mode=0 loop_begin=0 loop_end=0
  [  room_change.wav] DECODE-TO-END frames=24248 expected~24256 ratio=0.9997 reachedEnd=true lastPos=0.55s peak=0.223977 nanInf=0 nonSilentFrames=22100
  soft_pop.wav (imported)
  [  wav] class=AudioStreamWAV length=0.16s mix_rate=22050 stereo=false format=1 loop_mode=0 loop_begin=0 loop_end=0
  [  soft_pop.wav] DECODE-TO-END frames=7048 expected~7056 ratio=0.9989 reachedEnd=true lastPos=0.16s peak=0.316572 nanInf=0 nonSilentFrames=6713
  star_earned.wav (imported)
  [  wav] class=AudioStreamWAV length=0.46s mix_rate=22050 stereo=false format=1 loop_mode=0 loop_begin=0 loop_end=0
  [  star_earned.wav] DECODE-TO-END frames=20278 expected~20286 ratio=0.9996 reachedEnd=true lastPos=0.46s peak=0.503391 nanInf=0 nonSilentFrames=18685
  sticker_unlock.wav (imported)
  [  wav] class=AudioStreamWAV length=0.78s mix_rate=22050 stereo=false format=1 loop_mode=0 loop_begin=0 loop_end=0
  [  sticker_unlock.wav] DECODE-TO-END frames=34390 expected~34398 ratio=0.9998 reachedEnd=true lastPos=0.78s peak=0.501175 nanInf=0 nonSilentFrames=24837
  success_chime.wav (imported)
  [  wav] class=AudioStreamWAV length=0.62s mix_rate=22050 stereo=false format=1 loop_mode=0 loop_begin=0 loop_end=0
  [  success_chime.wav] DECODE-TO-END frames=27334 expected~27342 ratio=0.9997 reachedEnd=true lastPos=0.62s peak=0.502403 nanInf=0 nonSilentFrames=25945

### FAILURES: 0
```

**The engine printed no `ERROR` and no `WARNING` line during the entire run.**

Notes on reading the numbers:

- `frames=4088948` vs `expected~4088952` is a 4-frame shortfall on a 4.09
  million frame stream (1 part in a million). That is the resampler's
  fractional-position tail, not lost audio: `lastPos` reports the full
  92.72 s and the stream reports itself finished. The WAV rows show the same
  8-frame tail from 22 050 → 44 100 Hz upsampling.
- `LOOP-WRAP` decoded 98.73 s of a 92.72 s stream (and 70.4 s of a 64.4 s
  stream), i.e. it crossed the loop point, registered `loopCount=1`, and kept
  producing correct non-NaN audio. The loop seek is exercised.
- `packetSequence: imported == raw OK` proves the Godot importer produced a
  packet sequence identical in page count and packet count to a fresh parse of
  the source `.ogg` — the import step did not mangle anything.

### 48 kHz resampler pass (what the iPad actually runs)

The headless macOS mixer runs at 44 100 Hz, which matches the streams and
therefore bypasses most of the resampler. Because iOS commonly mixes at
48 000 Hz, the decode was repeated in a throwaway project configured with
`audio/driver/mix_rate=48000`, including deliberate pitch scaling:

```
### mix_rate=48000.0 driver=Dummy
--- little_days_theme.ogg length=92.7200012207031
    rate_scale=1.0 frames=4450571 expected~4450560 reachedEnd=true peak=0.760499 nanInf=0
    rate_scale=0.5 frames=8901289 expected~8901120 reachedEnd=true peak=0.761194 nanInf=0
    rate_scale=2.0 frames=2225286 expected~2225280 reachedEnd=true peak=0.756191 nanInf=0
--- hungry_bunny.ogg length=64.4000015258789
    rate_scale=1.0 frames=3091206 expected~3091200 reachedEnd=true peak=0.784707 nanInf=0
    rate_scale=0.5 frames=6182515 expected~6182400 reachedEnd=true peak=0.790721 nanInf=0
    rate_scale=2.0 frames=1545603 expected~1545600 reachedEnd=true peak=0.784707 nanInf=0
```

Clean at 48 kHz, and clean at half and double playback rate.

---

## 4. What is inside the exported pack

`build/ios/LittleBuddy.pck` — 17 238 384 bytes, **pack format version 4**,
written by Godot 4.7.2, directory at offset 17 147 648, **1 019 entries**,
unencrypted directory, no encrypted entries.

**Integrity: all 1 019 entries re-hashed against their stored MD5 — 0 bad,
0 missing, 0 short.** The pack itself is not damaged.

The complete audio payload in the pack is:

| Entry | Bytes | Kind |
| --- | --- | --- |
| `.godot/imported/little_days_theme.ogg-973cc9cc74c11adbaf4d31c744aa80ae.oggvorbisstr` | 1 454 181 | **Vorbis** |
| `.godot/imported/hungry_bunny.ogg-71669c06af296d13b93520e87ac8c769.oggvorbisstr` | 1 026 889 | **Vorbis** |
| `.godot/imported/bedtime_chime.wav-…sample` | 84 175 | PCM |
| `.godot/imported/sticker_unlock.wav-…sample` | 34 783 | PCM |
| `.godot/imported/success_chime.wav-…sample` | 27 727 | PCM |
| `.godot/imported/room_change.wav-…sample` | 24 639 | PCM |
| `.godot/imported/star_earned.wav-…sample` | 20 671 | PCM |
| `.godot/imported/drop_return.wav-…sample` | 14 495 | PCM |
| `.godot/imported/place_soft.wav-…sample` | 13 615 | PCM |
| `.godot/imported/soft_pop.wav-…sample` | 7 439 | PCM |
| `.godot/imported/pickup.wav-…sample` | 6 999 | PCM |
| `.godot/imported/gentle_tap.wav-…sample` | 3 911 | PCM |

Plus the twelve `audio/**/*.import` sidecars (150–185 bytes each) and
`content/audio/manifest.json` (3 353 bytes).

Two things follow:

1. **The source `.ogg` and `.wav` files are NOT in the pack.** Only the imported
   resources ship. So on device, `audio_director.gd::_decode_source_file` and
   `wav_loader.gd` never run — the `ResourceLoader` branch is the only live one.
2. **Every shipped imported resource is byte-identical to the one in the local
   project tree**, verified by SHA-256:

```
IDENTICAL  hungry_bunny.ogg-71669c06af296d13b93520e87ac8c769.oggvorbisstr
IDENTICAL  little_days_theme.ogg-973cc9cc74c11adbaf4d31c744aa80ae.oggvorbisstr
IDENTICAL  bedtime_chime.wav-8c3de3833545b60d5943bc51babc80fb.sample
IDENTICAL  drop_return.wav-ec4e559e0789d58984aa54938055b063.sample
IDENTICAL  gentle_tap.wav-334f24049a8af59bfa7c7d0a3d734da1.sample
IDENTICAL  pickup.wav-8f1df0dbaf980a99488429b0935e3f87.sample
IDENTICAL  place_soft.wav-4421ae6a3ac8f32b9f48ef3cbb60e783.sample
IDENTICAL  room_change.wav-9626214b4a439055e48261c2457f36f4.sample
IDENTICAL  soft_pop.wav-36483ebecafcf3aaac4505935d32ccef.sample
IDENTICAL  star_earned.wav-2f5a3e595badea5c807671d2c2cfdb71.sample
IDENTICAL  sticker_unlock.wav-e5308f27d56ff3f75a4bffa49edbe81f.sample
IDENTICAL  success_chime.wav-02bbd494b15c547b9bd658ddb3750a67.sample
```

That equality is what makes the decode results above authoritative for the
device build: the bytes decoded on this machine are the exact bytes in the
`.pck`.

---

## 5. WAV-vs-Vorbis inventory at runtime

Read from `game/audio/**/*.import`, `game/scripts/audio/**` and a repo-wide
search for runtime decode calls.

| Asset | Importer | `compress/mode` | Runtime type | Vorbis at runtime? |
| --- | --- | --- | --- | --- |
| `audio/music/little_days_theme.ogg` | `oggvorbisstr` | n/a | `AudioStreamOggVorbis` | **YES** |
| `audio/music/hungry_bunny.ogg` | `oggvorbisstr` | n/a | `AudioStreamOggVorbis` | **YES** |
| `audio/sfx/bedtime_chime.wav` | `wav` | `0` (PCM) | `AudioStreamWAV` | no |
| `audio/sfx/drop_return.wav` | `wav` | `0` (PCM) | `AudioStreamWAV` | no |
| `audio/sfx/gentle_tap.wav` | `wav` | `0` (PCM) | `AudioStreamWAV` | no |
| `audio/sfx/pickup.wav` | `wav` | `0` (PCM) | `AudioStreamWAV` | no |
| `audio/sfx/place_soft.wav` | `wav` | `0` (PCM) | `AudioStreamWAV` | no |
| `audio/sfx/room_change.wav` | `wav` | `0` (PCM) | `AudioStreamWAV` | no |
| `audio/sfx/soft_pop.wav` | `wav` | `0` (PCM) | `AudioStreamWAV` | no |
| `audio/sfx/star_earned.wav` | `wav` | `0` (PCM) | `AudioStreamWAV` | no |
| `audio/sfx/sticker_unlock.wav` | `wav` | `0` (PCM) | `AudioStreamWAV` | no |
| `audio/sfx/success_chime.wav` | `wav` | `0` (PCM) | `AudioStreamWAV` | no |

`compress/mode=0` is `MODE_PCM`. Godot's Vorbis-compressed WAV import mode is
`compress/mode=3`; **no `.wav.import` in this project uses it**. All ten SFX
also carry `edit/loop_mode=0` (disabled), `edit/loop_begin=0`,
`edit/loop_end=-1` — no loop point can run past the end.

SFX source headers, for the record (all mono 16-bit PCM at 22 050 Hz):

| File | Bytes | SHA-256 (first 16) | Ch | Rate | Format | Duration |
| --- | --- | --- | --- | --- | --- | --- |
| `bedtime_chime.wav` | 83 834 | `e1c54bf88c885249…` | 1 | 22 050 Hz | 16-bit PCM | 1.900 s |
| `drop_return.wav` | 14 156 | `c3e307422b16a45d…` | 1 | 22 050 Hz | 16-bit PCM | 0.320 s |
| `gentle_tap.wav` | 3 572 | `10ba3d3df77f643e…` | 1 | 22 050 Hz | 16-bit PCM | 0.080 s |
| `pickup.wav` | 6 660 | `eda1480c4cea1d42…` | 1 | 22 050 Hz | 16-bit PCM | 0.150 s |
| `place_soft.wav` | 13 274 | `6ab421cebf09618f…` | 1 | 22 050 Hz | 16-bit PCM | 0.300 s |
| `room_change.wav` | 24 300 | `88372d74ed0c9729…` | 1 | 22 050 Hz | 16-bit PCM | 0.550 s |
| `soft_pop.wav` | 7 100 | `a9b0ff0570e6d197…` | 1 | 22 050 Hz | 16-bit PCM | 0.160 s |
| `star_earned.wav` | 20 330 | `c9698df1553b8f55…` | 1 | 22 050 Hz | 16-bit PCM | 0.460 s |
| `sticker_unlock.wav` | 34 442 | `2a891fa86c962c7f…` | 1 | 22 050 Hz | 16-bit PCM | 0.780 s |
| `success_chime.wav` | 27 386 | `69310537a0607b76…` | 1 | 22 050 Hz | 16-bit PCM | 0.620 s |

**Verdict for all ten: CLEAN.** Every one decodes to its end with sane peaks
and zero NaN/Inf (see the harness output above), and none of them is Vorbis.

### No other Vorbis reaches the decoder

A repo-wide search for runtime audio decoding found:

- `audio_director.gd:1067` `AudioStreamOggVorbis.load_from_file(path)` — the
  source-file fallback. **Dead on device**: the `.ogg` sources are not in the
  pack, and `ResourceLoader.exists()` succeeds first anyway.
- `audio_director.gd:1072` `AudioStreamMP3.load_from_buffer(bytes)` — no `.mp3`
  ships; not a Vorbis path.
- `scripts/tutor/cloud/cloud_audio_player.gd` — cloud TTS playback uses
  **`AudioStreamGenerator` / `AudioStreamGeneratorPlayback`**, i.e. raw PCM
  frames pushed by the game. It never constructs a Vorbis stream, so cloud
  audio cannot reach `vorbis_book_decodevv_add`.
- `scripts/speech/voice_lines.gd` can load owner voice recordings as
  `res://audio/voice/<lineId>.ogg`. **`game/audio/voice/` contains only
  `README.md` today**, and a filter of the pack for `audio/voice` returns no
  audio entries — no voice Vorbis ships in this build. This is, however, the
  one place where a future untested `.ogg` could enter the decoder; re-run this
  audit when voice lines are added.
- `game/tests/**` uses `AudioStreamOggVorbis.load_from_file` and
  `AudioStreamWAV.new()` — test-only, not shipped.

---

## 6. Can any asset explain the crash?

**No.** Stated plainly, with the evidence:

- Both Vorbis files hash-match the manifest byte for byte, so the files on disk
  are the files that were encoded and vetted. Nothing was corrupted in transit,
  in git, or in the export.
- All 561 Ogg pages pass a recomputed CRC32. A single flipped bit anywhere in
  either file would have been caught — demonstrated on a deliberately damaged
  copy.
- Both streams are structurally complete: BOS set, EOS set, no sequence gaps, no
  truncated final page, no packet left open at EOF, all three Vorbis headers
  present with their framing bits.
- Both decode end to end through the actual libvorbis that Godot 4.7.2 ships,
  producing the expected frame counts with zero NaN/Inf samples and no engine
  error — at 44.1 kHz, at 48 kHz, at 0.5× and 2× rate, across a loop wrap,
  across 49 seeks each (seeks being the classic way a decoder is re-entered
  mid-stream), and with four concurrent playbacks sharing one stream object
  (the shape `audio_director.gd`'s 2-voice crossfade produces).
- The shipped `.oggvorbisstr` resources are byte-identical to the ones decoded
  here, and the `.pck`'s own per-entry MD5s all verify, so the device is reading
  the same bytes that passed.
- Loop metadata is benign everywhere: `loop_offset=0` on both Vorbis streams,
  `loopStart=0.0 / loopEnd=0.0` in the manifest, `loop_mode=0` on every WAV.
  **No loop point anywhere points past the end of its stream.**
- No WAV is Vorbis-compressed at import, and no runtime path feeds a
  Vorbis buffer to the decoder. Only two Vorbis streams exist in the whole
  build, and both are clean.

**Therefore the crash is not an asset-data defect, and re-encoding the music
will not fix it.** Look elsewhere. On the evidence gathered here, the remaining
candidates are engine/platform-side rather than content-side:

- Concurrency around the crossfade: `audio_director.gd` assigns
  `voice.stream = stream` and calls `play()` on a 2-voice pool while the other
  voice is still mixing, and `_apply_loop` mutates a freshly duplicated stream
  (`set("loop", …)`, `set("loop_offset", …)`) that a playback may already be
  reading on the audio thread. Serial and interleaved decoding were proven
  clean here, but a genuine main-thread/audio-thread race cannot be reproduced
  from a single-threaded headless script. **NOT TESTED.**
- Godot's iOS sample-playback path. `AudioStream.can_be_sampled()` returns
  **true** for both Vorbis streams, so on iOS the engine may pre-decode a stream
  into an `AudioSample` rather than stream it. Calling `generate_sample()`
  headless returned an `AudioSample` in 0 ms with no decode performed, and the
  driver-side decode lives in the iOS audio driver, which is unreachable from
  macOS. **NOT TESTED** — this is the single most plausible remaining code path
  and should be checked next, e.g. by attaching a debugger on device or by
  temporarily forcing streamed playback.
- Device-side memory pressure or an ARM-specific libvorbis codepath, neither of
  which a macOS x86/arm64 headless decode can rule in or out. **NOT TESTED.**

---

## 7. Re-encoding

**Not performed, and not needed** — no asset was proven corrupt, so the
precondition for writing a `.fixed.ogg` was never met. No file beside a shipped
asset was created.

For the record, the masters named in the manifest are **not present on this
machine**:

```
$ ls ~/Music/LittleDays/masters/
ls: /Users/hotkhwan/Music/LittleDays/masters/: No such file or directory
```

So even if a re-encode had been warranted, it could not have been done here
(`masterFile` `~/Music/LittleDays/masters/Little Days.wav` and
`~/Music/LittleDays/masters/I'm Hungry!.wav` are both missing). This is worth
resolving independently: the project currently has no local copy of the audio
masters it claims provenance from.

---

## 8. Checks that were NOT run

Listed explicitly so nothing here is mistaken for a pass:

| Check | Status |
| --- | --- |
| Decode on the physical iPad | **NOT TESTED** — no device run was performed as part of this audit |
| Godot's iOS `AudioSample` pre-decode path | **NOT TESTED** — lives in the iOS driver, unreachable headless on macOS |
| Main-thread / audio-thread race on the crossfade | **NOT TESTED** — not reproducible from a single-threaded headless script |
| Real CoreAudio output driver behaviour | **NOT TESTED** — the headless runner uses the `Dummy` driver |
| Voice-line `.ogg` assets | **N/A** — none exist in this build; re-run this audit when they are added |

---

## Reproducing this audit

```bash
cd /Users/hotkhwan/Projects/LittleBuddy-latest

# 1. Container + codec + CRC + granule + hash
python3 tools/audio_audit/ogg_probe.py \
    game/audio/music/little_days_theme.ogg \
    game/audio/music/hungry_bunny.ogg

# 2. Exported pack: list the audio payload and re-verify every entry's MD5
python3 tools/audio_audit/pck_read.py build/ios/LittleBuddy.pck --list --filter audio
python3 tools/audio_audit/pck_read.py build/ios/LittleBuddy.pck --verify

# 3. Full decode through the real engine decoder
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
    --script /Users/hotkhwan/Projects/LittleBuddy-latest/tools/audio_audit/decode_all.gd
```

All three exit `0` on a clean build.


---

# Device evidence (lead, iPad Air 4th gen, iOS 26.6.2, 2026-09-22 19:00-19:30)

The audit above exonerates the assets. This section records what the **real
device** says, with an instrumented debug build installed over USB
(`com.pointit.littlebuddy`, signed with the owner's Apple Development identity).

## What was measured
`AudioDirector` gained a debug-only diagnostic (`audio_diagnostics()` +
`_audio_diag()`, `game/scripts/audio/audio_director.gd`) that records the audio
stack at startup and at every focus/pause/resume notification into
`user://audio_diag.json`, and a debug-only soak
(`game/scripts/audio/audio_soak.gd`, armed with `-- --audio-soak`, optionally
`--audio-soak-speech`) that drives music states, cross-fades, SFX and the
native speech session without touch input. Neither runs in a release build and
neither changes audio behaviour.

## Findings
| Question | Answer from the device |
|---|---|
| Audio driver at startup | **CoreAudio** (not Dummy), mix rate **48000**, 2 buses |
| Driver after 40 recorded focus/pause/resume events | **CoreAudio throughout** — the driver never changed |
| Does the known "Dummy + CoreAudio mixing concurrently" pattern apply? | **Not as described.** That bug needs `AudioDriverCoreAudio::init()` to fail so the AudioServer falls back to Dummy while `OS_AppleEmbedded::on_focus_in()` still calls `audio_driver.start()`. Here CoreAudio initialises and is the active driver, so `start()` is a no-op (`if (!active && audio_unit != nullptr)`). |
| Music soak | 389 steps / 16 full cycles: menu → house → miniGame → reward → menu → silent with cross-fades, ducking and SFX, music confirmed playing (`musicPlaying: true`) — **no crash** |
| Music + native speech session soak | same, plus `set_voice_processing(true/false)`, `start_listening`, `cancel_listening` interleaved with music — **no crash**. Caveat: microphone permission was never granted on this fresh install, so the plugin's `AVAudioSession` category/mode switch may not have executed. |
| 22 background → foreground cycles with music playing | same process throughout (pid unchanged), `audio_driver.stop()`/`start()` exercised 22 times — **no crash** |
| Crash report for the owner's crash | **none on the device.** Only three `gpuEvent-LittleBuddy-2026-09-22-1853xx.ips` (GPU restarts) exist. The Vorbis crash was caught by the Xcode debugger, so iOS wrote no `.ips`. |

## What the engine source says (Godot 4.7.2, read at the tag)
- `drivers/apple_embedded/os_apple_embedded.mm:792` `on_focus_in()` calls
  `audio_driver.start()` unconditionally, and `:774` `on_focus_out()` calls
  `audio_driver.stop()`. Both run on every app activation.
- `drivers/coreaudio/audio_driver_coreaudio.mm:78` `init()` creates
  `audio_unit` with `AudioComponentInstanceNew` and then has **eleven**
  `ERR_FAIL_COND_V(result != noErr, FAILED)` exits that leave `audio_unit`
  allocated. `start()` only checks `!active && audio_unit != nullptr`, so after
  a failed init a focus-in WOULD start a second mixer. **That latent bug is
  real, and is worth fixing upstream, but it is not what this device is doing.**
- `output_callback()` (`:190`) writes `frames * ad->channels` samples using the
  channel count captured at `init()`, and the iOS driver reads
  `[AVAudioSession sharedInstance].sampleRate` **once** at init. Nothing in the
  driver observes `AVAudioSessionRouteChangeNotification`, an interruption, or
  a media-services reset. A session/route change made by another component
  (our speech plugin sets `.playAndRecord` + `.voiceChat` and activates the
  shared session) is therefore invisible to the driver. This remains the most
  plausible mechanism for heap corruption that surfaces inside the decoder,
  but it is **NOT PROVEN** on this device and must not be reported as the
  cause until it reproduces.

## Status
**NOT REPRODUCED by automation, before or after the fix.** The crash is real
(the owner has the disassembly), the assets are clean, and the driver is
healthy. See the verification run below.

# Verification of Codex's audio-session fix (2026-09-22 21:15-21:28)

Build: `develop` @ `4f98902` (merge of `feature/codex-ui-polish` `24a1420`,
"fix(ios): stabilize Tutor audio session lifecycle"). Signed debug build
installed over USB to the iPad Air 4th gen, iOS 26.6.2. The app binary was
checked before install: `undef=0 def=101 sessionFix=1 arch=arm64` — the new
session symbols (`get_audio_session_diagnostics_json`, `_emit_audio_session_event`)
are present, so the fix is genuinely in the installed binary.

## A false alarm that must not be repeated
An earlier attempt reported `pid: GONE` ~50 s after launch and was very nearly
written up as a reproduction. It was not. `devicectl`'s own console log for that
run says:

```
The request was denied by service delegate (SBMainWorkspace) for reason: Locked
("Unable to launch com.pointit.littlebuddy because the device was not, or could
not be, unlocked").
```

The iPad had auto-locked, so **the app never launched at all**. `pid: GONE`
meant "never started", not "crashed". Always confirm the launch succeeded
before interpreting a missing pid.

## What the run measured
| Measure | Result |
|---|---|
| Wall clock, one continuous process | **21:15:57 → 21:28:29 (12 min 32 s)**, pid **9293** start to finish |
| Foreground/background cycles | **27** (12 in round 1 + 15 in round 2), each an app→Preferences→app switch with music playing. Owner's bar was 20+. |
| Process death or pid change | **none** — 54 consecutive liveness checks, all pid 9293 |
| Audio soak | **1450 steps / 63 full loops** of menu → house → miniGame → reward → silent with cross-fades, ducking and SFX |
| Native speech interleaved | yes (`--audio-soak-speech`): `set_voice_processing`, `start_listening`, `cancel_listening` interleaved with music throughout |
| Driver across all recorded events | **CoreAudio only** — never fell back to Dummy |
| Mix rate / bus count across all events | **48000 / 2**, constant — no route or session change disturbed them |
| Music at the final event | still playing (`musicPlaying: true`, 788 s in) |
| Vorbis decoder crash | **did not occur** |
| Crash reports written for the app | **none.** The only `LittleBuddy` reports on the device are three `gpuEvent-…-1853xx.ips` from 18:53, which are GPU restarts (`restart_reason_desc: "BIF0 page fault"`) on an earlier build, not process crashes, and not audio. |

`user://audio_diag.json` keeps a rolling window of `AUDIO_DIAG_MAX_EVENTS` (40)
events, so the retained file shows the last 10 focus cycles, not all 27. The
watcher log is the authoritative cycle count.

## Honest verdict
This is the strongest negative result so far: the instrumented build with the
session fix survived 27 focus cycles and 1450 audio steps with speech, and the
audio stack never degraded. **It is still a negative result.** The original
crash has never reproduced under automation, before or after the fix, so this
run cannot prove the fix cured it — it can only show the fix did not regress
audio and that the previously suspected mechanism did not fire here.

**Calling the Vorbis crash fixed requires the owner to play the build by hand**
along the path that crashed it, ideally launched from the Home screen rather
than Xcode so a real `.ips` is written if it happens again. Two questions are
still open and only the owner can answer them: what they were doing when it
crashed, and whether it still happens on this build.
