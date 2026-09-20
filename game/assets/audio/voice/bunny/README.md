# Bunny voice lines (drop-in folder)

Put the converted OGG files for **Bunny** here. Nothing else. No WAV masters
(`*.wav` under `assets/audio/voice/` is git-ignored on purpose).

Bunny: soft, adorable, expressive baby -- laughs, delight, sleepy, a little
sulky. Never shrill. He is the one being cared for; his lines are needs and
reactions, so they are short and full of feeling.

Laughs, chewing, drinking, sighs and sleepy sounds are **SFX**, not voice lines.
They do not belong in this folder and are not in the manifest.

## Format

* OGG Vorbis, **44.1 kHz, mono, about 96 kb/s** (`oggenc -q 3` or `afconvert -f ogg`
  through the project's `tools/voice_convert.sh`).
* Made from **48 kHz / 24-bit WAV masters kept OUTSIDE the repo**, e.g.
  `~/Music/LittleDays/voice/bunny/bunny_001_hungry.wav`.
* Peak **-3 dBFS**. No more than **0.1 s** of silence at the head and at the tail.
* One file per line. Exact filename = `lineId` + `.ogg`, lower case.

## Exact filenames (12)

| file | text | feeling |
|---|---|---|
| `bunny_001_hungry.ogg` | I'm hungry, Aliz! | hungry, pleading |
| `bunny_002_milk.ogg` | Milk, please! | asking, cute |
| `bunny_003_yummy.ogg` | Yummy! | delighted |
| `bunny_004_more.ogg` | More, please! | eager |
| `bunny_005_thank_you.ogg` | Thank you, Aliz! | grateful, happy |
| `bunny_006_sleepy.ogg` | I'm sleepy. | sleepy, soft |
| `bunny_007_good_night.ogg` | Good night! | sleepy, content |
| `bunny_008_bath.ogg` | Bath time! | excited |
| `bunny_009_play.ogg` | Play with me! | playful |
| `bunny_010_hug.ogg` | Hug me, please! | tender, pleading |
| `bunny_011_happy.ogg` | Yay! | delighted |
| `bunny_012_upset.ogg` | Hmph! | cute sulk, never angry |

## Convert

    tools/voice_convert.sh ~/Music/LittleDays/voice

## Status

**No recordings exist yet (0 of 12 Bunny files).** Until a file is here the game
speaks the line through the device voice (`TtsService`). The manifest is
`game/content/voice/voice_manifest.json`; `test_voice_manifest.gd` reports which
files are present on every test run.
