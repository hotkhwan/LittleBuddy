# Anny's two original tracks — integration report

**Date:** 2026-09-19 · **Branch:** `feature/overnight-production-candidate`

Two original tracks were delivered by Anny and are now wired into the shipping game: encoded
for mobile, catalogued with their provenance, connected to the real game states, and ducked
under spoken English. They are **silent by default**, and will stay silent until the owner
records what licence they come with. That last point is the important one — see §3.

| | |
|---|---|
| Runtime files | `game/audio/music/little_days_theme.ogg`, `game/audio/music/hungry_bunny.ogg` |
| Masters (not in git) | `~/Music/LittleDays/masters/` |
| Catalogue | `game/content/audio/manifest.json` |
| Licence gate | `game/scripts/audio/music_manifest.gd` |
| Preview override | `game/scripts/audio/music_licence_override.gd` |
| Game-state wiring | `game/scripts/audio/music_binder.gd` |
| Mixer, fades, ducking | `game/scripts/audio/audio_director.gd` |
| Proof it plays | `game/tests/smoke_audio_shipping.gd` |
| Unit tests | `game/tests/cases/test_audio_music_binder.gd`, `test_audio_director.gd`, `test_audio_music_manifest.gd` |

---

## 1. The masters, preserved

The originals in `~/Downloads/` were **not modified, renamed or moved**. Verified before and
after by checksum.

| | Little Days | I'm Hungry! |
|---|---|---|
| Original path | `~/Downloads/Little Days.wav` | `~/Downloads/I'm Hungry!.wav` |
| Format | WAV 48 000 Hz, 2 ch, 16-bit PCM | WAV 48 000 Hz, 2 ch, 16-bit PCM |
| Size | 17 816 080 bytes (17.0 MiB) | 12 378 640 bytes (11.8 MiB) |
| Duration | 92.720 s | 64.400 s |
| Peak / RMS | −2.74 dBFS / −17.42 dBFS | −2.63 dBFS / −17.29 dBFS |
| SHA-256 | `ce87963575cb6177e267cf58bd33cf0fa0fc8697d39203d69c4a08aea6565e59` | `43e62ad41955d7d5c766af6a104e65c311e423186831aa669835c900e9988739` |

A second copy of each master lives at `~/Music/LittleDays/masters/` with identical checksums.
Masters are deliberately **outside the repository**: 30.2 MiB of WAV against a 58 MiB `.git`
with no git-lfs configured, and the same reversibility argument the Meshy exports are excluded
under (`.gitignore`) — adding them later is one command, taking them back out means rewriting
published history.

Every number above is also recorded per-track in `manifest.json` (`masterSha256`,
`masterBytes`, `masterDurationSeconds`, …), so the repository itself knows what it was built
from.

---

## 2. Conversion to a mobile runtime format

**Neither `ffmpeg` nor `oggenc` was installed.** `afconvert` is present on macOS but cannot
produce an Ogg container (it offers Vorbis only inside CAF, which Godot cannot read), and
Godot has no encoder of its own. So the toolchain was installed:

```sh
brew install vorbis-tools        # libogg, libvorbis, flac, libao, vorbis-tools 1.4.3
```

That is a ~5 MiB developer-machine install, not a project dependency; nothing in the game
links against it. The alternative — committing 30 MiB of WAV — was rejected.

Both tracks were then encoded from the masters:

```sh
oggenc -q 4 --resample 44100 \
  -a "Anny" -t "Little Days (Main Theme)" -l "Little Days" \
  -c "TRACKID=littleDaysTheme" -c "MASTER=… sha256 ce879635…" \
  -o game/audio/music/little_days_theme.ogg "~/Music/LittleDays/masters/Little Days.wav"

oggenc -q 4 --resample 44100 \
  -a "Anny" -t "I'm Hungry! (Mission 01)" -l "Little Days" \
  -c "TRACKID=hungryBunny" -c "MASTER=… sha256 43e62ad4…" \
  -o game/audio/music/hungry_bunny.ogg "~/Music/LittleDays/masters/I'm Hungry!.wav"
```

| | source WAV | runtime OGG | saving |
|---|---|---|---|
| `little_days_theme` | 17 816 080 B | **1 412 253 B** (1.35 MiB, 121.5 kb/s) | 12.6× |
| `hungry_bunny` | 12 378 640 B | **999 758 B** (0.95 MiB, 123.6 kb/s) | 12.4× |
| **total** | 30 194 720 B (28.8 MiB) | **2 412 011 B (2.30 MiB)** | **12.5×** |

Runtime checksums: `de5588a77ed8591b82dc0eec5e3a40e829953440598692b839ee86796132eaf8` and
`64653da1f483c78f9f1d704322c04da01e5eef1b43463389d30bb27a25694b3d`.

**Why these settings.**
- **Ogg Vorbis** is the normal Godot choice, streams from disk rather than decompressing into
  RAM, and needs no import-time transcode on iOS.
- **`-q 4`** (~128 kb/s nominal) is generous for music that plays at −12 to −16 dB under
  speech through an iPad speaker. Doubling the bitrate would double the download for something
  no child will hear.
- **`--resample 44100`** matches Godot's default `audio/driver/mix_rate` exactly, so the mixer
  never resamples at runtime. Encoding once on a laptop is free; resampling 48 kHz → 44.1 kHz
  on every frame of an iPad's battery is not.
- **Stereo kept.** Mono would have saved ~40% and these are the only two pieces of music in
  the game; the width is worth 1 MiB.
- Durations are preserved exactly (92.719 s / 64.400 s), and provenance is written into each
  file's Vorbis comments as well as into the manifest.

---

## 3. Licensing — the decision, and its consequence

### What is recorded

**No licence evidence was supplied with the delivery.** Nothing is known about which tool
produced these tracks or what rights come with them. So the rows say exactly that, and nothing
more:

```json
"licenseEvidence": "OWNER TO CONFIRM",
"commercialUse": "pending",
"source": "Anny - original composition, delivered 2026-09-19 as 'Little Days.wav'.
           Which tool or DAW produced it is NOT recorded: OWNER TO CONFIRM.",
"createdAt": ""
```

No Suno account, plan or terms were invented. `createdAt` is empty because the creation date is
genuinely unknown; only `downloadedAt` (2026-09-19, the delivery) is a fact.

### The consequence, stated plainly

`MusicManifest` fails closed: a track plays only when `commercialUse` is exactly `"verified"`
**and** `licenseEvidence` names something real. `"pending"` therefore means **the shipping game
plays no music at all.** That is the gate working correctly, and it is asserted by
`test_audio_music_manifest.gd::_test_shipped_manifest_is_silent_today()` and by phase 1 of the
audio smoke.

### How that was resolved: an armed preview, not a softened gate

Three options existed; two are forbidden.

1. Write `"verified"` and invent paperwork — **fraud.** Not done.
2. Loosen the gate so `"pending"` plays — silently ships music we may not own. Not done.
3. Leave the gate untouched and add a separate switch the owner has to arm by hand. **Done.**

`game/scripts/audio/music_licence_override.gd` is that switch. It is:

- **off in every build.** `AudioDirector.allow_unverified_music` defaults to `false` and
  `_ready()` only ever sets it from `MusicLicenceOverride.is_armed()`. Nothing committed to
  this repository arms it — `test_audio_music_binder.gd` asserts that as a test.
- **armed per-machine, deliberately,** by either of two documented means:
  ```sh
  # one run
  … --script res://tests/smoke_audio_shipping.gd -- --allow-unverified-music
  # or, to keep the preview on while playing on a device, create the marker file:
  user://OWNER_ACKNOWLEDGED_UNVERIFIED_MUSIC
  ```
  On macOS that is `~/Library/Application Support/Godot/app_userdata/Little Days/`; on iPad it
  is the app's Documents directory. Deleting it disarms the override.
- **incapable of softening the gate.** `MusicManifest.is_playable()` still answers `false`, so
  `licence_refused_track_ids()` and every shipping check still see the truth. All the override
  changes is whether `AudioDirector` assigns a stream.
- **narrow.** It releases a *paperwork* refusal only. A track with no file on disk, an unknown
  id, or an explicit `commercialUse: "denied"` stays silent — someone checked, and the answer
  was no. (That last case was a real bug: `refusal_reason()` reports `"denied"` and `"pending"`
  identically, so `MusicManifest.is_denied()` was added and the override consults it. The test
  that caught it is `_test_the_override_needs_a_real_file()`.)
- **loud.** Playing a track under the override pushes an unmissable warning naming the track
  and how to disarm, and emits `unverified_music_allowed(trackId, reason)` once per track. A
  preview that is indistinguishable from a shipping build is how unlicensed audio reaches a
  store.

### To actually ship the music

1. Establish what rights the tracks carry and capture the evidence in
   `docs/licences/music/<trackId>/`.
2. In `manifest.json`, set `licenseEvidence` to a real reference and `commercialUse` to
   `"verified"`.
3. Update the two "the build is silent" test cases alongside it — do not delete them; they are
   the record that the silent path still works.
4. `music_licence_override.gd` then becomes dead code and can be deleted outright.

Until step 2, **do not ship a build believing it has music.**

---

## 4. Wiring: which music, where

`littleDaysTheme` → `menu`. `hungryBunny` → `miniGame`, which today means the milk mission.

`MusicBinder` (`game/scripts/audio/music_binder.gd`) is a child the director creates when it is
installed as an autoload. It watches `SceneTree.node_added`, recognises gameplay nodes by
script path, and connects to their signals. **No gameplay file was changed** — nothing in
`scripts/house/`, `scripts/gameplay/`, `scripts/ui/`, `scripts/speech/` or `scenes/` mentions
music, and deleting `music_binder.gd` removes the feature completely.

| what happens | music state |
|---|---|
| `scenes/main/main.gd` enters the tree | `menu` → `littleDaysTheme` |
| `house_world.gd` enters the tree, or `room_entered` outside a mission | `house` → silent (no house track) |
| `level_started` / `mission_started` | `miniGame` → `hungryBunny` |
| `mission_completed` / `level_finished` | unchanged — the celebration keeps its music |
| session summary `closed` / `play_again` / `next_level` | `house` |

### What is deliberately not connected

- **`task_plan_changed`** — an objective changes seven times in a mission. Re-requesting music
  on each is how a soundtrack stutters back to bar one every few seconds. There is no handler,
  and `test_audio_music_binder.gd` fails if one appears.
- **`transition_started`** — likewise for doors. `room_entered` *is* connected, because it is
  how free exploration is detected, but it is **ignored while a mission is running**, so
  mission 01's four room changes cannot interrupt the mission's own music. Proven in the smoke:
  four real transitions, `track_started` fired once, playback position moved 0.93 s → 2.32 s.
- **`reward`** — no reward track was delivered, so requesting that state would replace the
  mission's music with silence at the moment the child is being congratulated. The day a third
  track arrives this is one line in the binder plus one manifest row.

`AudioDirector.set_state()` is idempotent as well, so even a duplicated request is a no-op
rather than a restart. There are two `AudioStreamPlayer` voices — the minimum a crossfade needs
— and only one holds a stream once a fade settles; the smoke asserts that across the whole
tree, not just inside the director.

---

## 5. Ducking: music gets out of the way of English

While the game speaks, or while the microphone is open, music drops by `duck_db` (default
−10 dB) over 0.18 s and comes back over 0.55 s. Measured in the real game:
**−16.0 dB → −26.0 dB → −16.0 dB.**

The duck is a separate gain multiplied into the mix rather than a change to the trims, because
the trims are the parent's settings and a passing prompt must not rewrite them — and because a
crossfade may be running at the same time, where two writers of `volume_db` would fight. It can
only attenuate: whatever `duck_db` is set to, the gain never exceeds 1.0 and the audible level
never exceeds the −6 dB music ceiling.

**It is polled once per frame, not driven by signals.** `TtsService` emits a balanced
`speech_started`/`speech_finished` pair, but `SpeechService.listening_stopped` is **not
guaranteed**: `ios_speech_backend.gd::_on_recognition_failed()` re-emits a failure without
clearing its listening flag or emitting a stop, and `permission_result(false)` emits no stop
at all. A duck keyed on those edges would stick, and music that goes quiet and stays quiet is a
bug a parent reports as "the music is broken". Asking `is_speaking() or is_listening()` every
frame costs nothing, has no edge to miss, and makes a stuck duck structurally impossible.

`tts_service.gd` and `speech_service.gd` were **not modified** — they are only read. See §8 for
the one signal that would be worth adding on their side.

---

## 6. Looping

Both rows use `loopStart: 0.0` / `loopEnd: 0.0`, which means "loop the whole file". The
`.ogg.import` sidecars also set `loop=true`, and the director sets it on a duplicate of the
stream at load time so loop settings never leak into anything else that loads the same file.

**Godot's `AudioStreamOggVorbis` has no loop-end**, so `loopEnd` is honoured for WAV only. A
tighter loop therefore needs a re-cut *master*, not a manifest edit. What the wrap sounds like
today, measured:

- *Little Days* ends with a musical release decaying from ~−18 dBFS at 91.0 s to −38 dBFS at
  92.7 s, and the file opens with a ~0.10 s near-silent lead-in. The wrap is a decay into
  quiet, not a click.
- *I'm Hungry!* decays to ~−32 dBFS over its last 1.0 s.

Both are acceptable for a looping bed. If Anny can supply seamless loop edits (no ending, exact
bar length), dropping them in is a file swap.

---

## 7. What is required from the caller

### `game/project.godot` — add one line under `[autoload]`

Without this, `MusicBinder` is never created and the game has no music at all. The block, with
the existing lines for context:

```ini
[autoload]

SaveService="*res://scripts/save/save_service.gd"
SpeechService="*res://scripts/speech/speech_service.gd"
TtsService="*res://scripts/speech/tts_service.gd"
Sfx="*res://scripts/audio/sfx_player.gd"
Audio="*res://scripts/audio/audio_director.gd"
```

`AudioDirector` already follows `SfxPlayer`'s autoload style exactly — `class_name` +
`extends Node`, no scene, defensive autoload lookups, tolerant of missing dependencies — so no
other change is needed. It binds `/root/Sfx` itself so one mixer owns every level, and it
creates its `MusicBinder` only when it is a direct child of `/root` and not the current scene,
i.e. only as an autoload.

### `game/tests/run_tests.gd` — add `"Audio"` to `PROJECT_AUTOLOADS`

```gdscript
const PROJECT_AUTOLOADS: Array[String] = [
	"SaveService", "SpeechService", "TtsService", "Sfx", "Audio",
]
```

The runner detaches the autoloads so no case can reach a real save file. An attached `Audio`
would leave a tree-wide `node_added` watcher live for the whole suite, reacting to every world
a case builds. Harmless — nothing is playable — but it is noise the runner exists to prevent.

**Both files are owned by the caller; neither was touched.** The suite is green at 114/114
without either change.

---

## 8. Verification

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/run_tests.gd
  → PASS - 116 case(s), 0 failure(s)
     (113 before this work; this adds one case, test_audio_music_binder, and weakens none.
      The count drifts upward while other workstreams land their own cases.)

… --script res://tests/smoke_mission01.gd                → SMOKE PASS
… --script res://tests/smoke_mission01.gd -- snackTime    → SMOKE PASS
… --script res://tests/smoke_audio_shipping.gd           → SMOKE PASS
```

The audio smoke drives the real `main.tscn` and `house_world.tscn` and asserts against the live
`AudioStreamPlayer` — its `stream`, class, length, `playing` flag, `volume_db` and
`get_playback_position()` — because a manifest can be right, a state machine can be right, and
the child can still hear nothing. Its real transcript (engine warnings about the armed override
elided; they are quoted in §3):

```
=== proving music in the real game ===
0. installed /root/Audio (Node)
1. licence override: disarmed (unverified music is silent, which is the shipping default)
WARNING: AudioDirector refused music track 'littleDaysTheme' (commercialUseUnverified), and there IS a file at res://audio/music/little_days_theme.ogg. A track plays only when commercialUse is "verified" and licenseEvidence names real evidence. See docs/AUDIO_MANIFEST.md.
WARNING: AudioDirector refused music track 'hungryBunny' (commercialUseUnverified), and there IS a file at res://audio/music/hungry_bunny.ogg. A track plays only when commercialUse is "verified" and licenseEvidence names real evidence. See docs/AUDIO_MANIFEST.md.
   shipping default: silent in every state, both .ogg files present, 0 errors
2. licence override ARMED (by this script; same effect as `-- --allow-unverified-music`).
   The manifest still says commercialUse="pending" and the gate still
   refuses: MusicManifest.is_playable() is false for both tracks.
   Overridden tracks: ["littleDaysTheme", "hungryBunny"]
WARNING: MUSIC LICENCE OVERRIDE IS ARMED. Track 'littleDaysTheme' is playing even though its manifest row says commercialUse="pending" / licenseEvidence="OWNER TO CONFIRM". This is an owner-acknowledged local PREVIEW and must never be shipped. Disarm it by removing user://OWNER_ACKNOWLEDGED_UNVERIFIED_MUSIC or dropping the --allow-unverified-music argument. See docs/ORIGINAL_MUSIC_INTEGRATION.md.
3. main.tscn in the tree -> state 'menu', track 'littleDaysTheme'
   live player: /root/Audio/MusicVoice0  class=AudioStreamOggVorbis  from=little_days_theme.ogg  imported=true  playing=true  -19.2 dB  pos=0.56 s  length=92.72 s
4. house_world.tscn in the tree -> state 'house'
WARNING: MUSIC LICENCE OVERRIDE IS ARMED. Track 'hungryBunny' is playing even though its manifest row says commercialUse="pending" / licenseEvidence="OWNER TO CONFIRM". This is an owner-acknowledged local PREVIEW and must never be shipped. Disarm it by removing user://OWNER_ACKNOWLEDGED_UNVERIFIED_MUSIC or dropping the --allow-unverified-music argument. See docs/ORIGINAL_MUSIC_INTEGRATION.md.
5. mission 'imHungry' running -> state 'miniGame', track 'hungryBunny'
   live player: /root/Audio/MusicVoice1  class=AudioStreamOggVorbis  from=hungry_bunny.ogg  imported=true  playing=true  -26.0 dB  pos=0.93 s  length=64.40 s
6. AudioStreamPlayers holding a music stream, whole tree: 1
   /root/Audio/MusicVoice1  AudioStreamOggVorbis 64.40 s  playing=true  volume=-26.0 dB
7. 4 room transitions later: track 'hungryBunny', position 0.93 s -> 2.32 s, track_started fired 1 time(s)
8. quiet again after true: music -16.0 dB, ducked=false, duck gain 1.000
   speaking -> music -26.0 dB (duck gain 0.316), still playing=true
   speech over (true) -> music back to -16.0 dB (duck gain 1.000)
9. mid-crossfade menu -> miniGame: ["littleDaysTheme @ -15.3 dB", "hungryBunny @ -26.1 dB"] (fading=true)
   settled -> track 'hungryBunny', players holding music=1, -16.0 dB
10. muted -> playing=false, players holding music=0
   unmuted -> track 'hungryBunny', -16.0 dB
11. littleDaysTheme: AudioStreamOggVorbis, loop=true, length=92.72 s
11. hungryBunny: AudioStreamOggVorbis, loop=true, length=64.40 s
SMOKE PASS -- both delivered tracks play in the real game, one at a time,
              they duck for English, and the shipping default is still silent
              because no licence evidence has been supplied.
```

### Two tests whose premise inverted, and were rewritten rather than deleted

Both carried an explicit instruction to update them when music landed.

- `test_audio_music_manifest.gd::_test_shipped_manifest_is_silent_today()` asserted
  "every track's file is missing". It now asserts the opposite half — every file **is** present
  — while keeping and strengthening the half that matters: nothing is playable, every track is
  licence-refused, and no refusal may be `fileMissing` (which would hide the licence question
  behind a lost file).
- `test_audio_director.gd::_test_a_build_with_no_music_behaves_normally()` asserted the director
  never wants to warn. It now asserts the warning **tracks the file's presence**: silent when
  there is no file (the designed pre-delivery state), loud when a delivery has landed without
  its rights recorded.

### One latent bug fixed in passing

`MusicManifest.to_json_string()` used `JSON.stringify`'s default `sort_keys = true`, which
reorders every row alphabetically. Harmless while rows carried only the eleven schema fields;
the moment the provenance fields above were added it broke the manifest's own JSON round-trip
identity test. Now `sort_keys = false`, which also keeps `trackId` as the first thing a human
reads.

---

## 9. Known limitations

- **No music ships until the licence is recorded.** §3. This is the headline.
- **The house is silent between missions.** `littleDaysTheme` is scoped to `menu` as briefed,
  so free exploration has no bed. Adding `"house"` to its `usageScenes` is a one-word manifest
  change and would cost nothing at runtime — the menu → house transition would not even
  re-trigger, since it is the same track id. Left as the owner's call.
- **No reward track**, so the celebration keeps the mission's music. §4.
- **Every mission gets `hungryBunny`.** `usageScenes` is keyed on the BGM state, not on a
  mission id, so `snackTime` gets the milk mission's music too. There is one mission track;
  per-mission music needs a new state or a mission-aware scene key.
- **Loop wrap is a decay, not seamless.** §6.
- **Not heard on the physical iPad.** Everything above was verified headless on macOS with the
  dummy audio driver, which proves the streams are loaded, assigned, playing, mixed and ducked,
  but cannot prove how they *sound*. Levels (−12 / −16 dB) are a judgement made from the
  masters' measured RMS and should be checked by ear on the device against a spoken prompt;
  that is a one-number manifest change per track.
- **`.godot/imported/` is gitignored**, so a fresh clone has no imported Ogg resources and
  `ResourceLoader.load()` returns null for them (verified). `AudioDirector._decode_source_file()`
  decodes the source `.ogg` directly in that case, mirroring what `wav_loader.gd` already does
  for the SFX. Both paths are proven by the smoke.
