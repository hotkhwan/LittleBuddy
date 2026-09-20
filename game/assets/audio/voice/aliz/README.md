# Aliz voice lines (drop-in folder)

Put the converted OGG files for **Aliz** here. Nothing else. No WAV masters
(`*.wav` under `assets/audio/voice/` is git-ignored on purpose).

Aliz: bright, cheerful, warm, youthful English-speaking girl. The narrator and
guide; her lines are the English the child is learning, so consonants are clear
and the pace is unhurried.

## Format

* OGG Vorbis, **44.1 kHz, mono, about 96 kb/s** (`oggenc -q 3` or `afconvert -f ogg`
  through the project's `tools/voice_convert.sh`).
* Made from **48 kHz / 24-bit WAV masters kept OUTSIDE the repo**, e.g.
  `~/Music/LittleDays/voice/aliz/aliz_001_welcome.wav`.
* Peak **-3 dBFS**. No more than **0.1 s** of silence at the head and at the tail.
* One file per line. Exact filename = `lineId` + `.ogg`, lower case.

## Exact filenames (24)

| file | text |
|---|---|
| `aliz_001_welcome.ogg` | Welcome to Little Days! |
| `aliz_002_lets_play.ogg` | Let's play together! |
| `aliz_003_come_on.ogg` | Come on, Bunny! |
| `aliz_004_lets_go_home.ogg` | Let's go home! |
| `aliz_005_what_shall_we_do.ogg` | What shall we do today? |
| `aliz_006_good_job.ogg` | Great job! |
| `aliz_007_well_done.ogg` | You did it! |
| `aliz_008_try_again.ogg` | Let's try again! |
| `aliz_009_its_okay.ogg` | It's okay. We can do it! |
| `aliz_010_follow_me.ogg` | Follow me! |
| `aliz_011_apple.ogg` | Let's give Bunny the apple! |
| `aliz_012_banana.ogg` | Let's peel the banana! |
| `aliz_013_drink.ogg` | Time for a drink! |
| `aliz_014_milk_time.ogg` | Let's make some milk! |
| `aliz_015_bath_time.ogg` | Let's take a bath! |
| `aliz_016_brush_teeth.ogg` | Let's brush our teeth! |
| `aliz_017_bedtime.ogg` | Time for bed! |
| `aliz_018_clean_up.ogg` | Let's put the toys away! |
| `aliz_019_cooking.ogg` | Let's cook something yummy! |
| `aliz_020_all_done.ogg` | All done! |
| `aliz_021_star.ogg` | You earned a star! |
| `aliz_022_sticker.ogg` | A new sticker for you! |
| `aliz_023_break.ogg` | Let's take a little break! |
| `aliz_024_come_back.ogg` | Come back soon for more Little Days! |

## Convert

    tools/voice_convert.sh ~/Music/LittleDays/voice

The script converts every `aliz_*.wav` / `bunny_*.wav` it finds, writes the OGGs
into these folders, validates durations and writes `voice_pack_report.json`.

## Status

**No recordings exist yet (0 of 24 Aliz files).** Until a file is here the game
speaks the line through the device voice (`TtsService`). The manifest is
`game/content/voice/voice_manifest.json`; `test_voice_manifest.gd` reports which
files are present on every test run.
