# Voice asset request -- Little Days voice pack V1

Little Days, 2026-09-20. Agent V (voice pack). Supersedes the 2026-09-20 Agent F
single-voice list: the owner decided on a **character-based recorded voice pack
with two performers**. The 36 ids and texts below are the owner's list and are
**authoritative** -- `game/content/voice/voice_manifest.json` mirrors them
exactly and `test_voice_manifest.gd` fails if either drifts.

## Status

**0 of 36 recordings exist.** Nothing here has been recorded, converted or
dropped in. Every line currently plays through the device voice (`TtsService`),
and the game says so honestly: `Voice.is_recorded(lineId)` is false for all 36
and the test run prints `voice pack: 0 of 36 recordings present`.

## The two characters

**Aliz** -- bright, cheerful, warm, youthful English-speaking girl. She is the
narrator and guide; her lines are the English the child is learning. Clear
consonants, unhurried, a smile you can hear. Not a cartoon voice, not baby talk.
No disappointment anywhere: "Let's try again!" is an invitation.

**Bunny** -- soft, adorable, expressive baby. Laughs, delight, sleepy, a little
sulky. **Never shrill.** He is the one being cared for; his lines are needs and
reactions, so they are short and full of feeling. "Hmph!" is a toddler's cute
sulk drawn to be funny, never real anger.

Laughs, chewing, drinking, sighs and sleepy sounds are **SFX**, not voice
lines. They are not in this list and must not be delivered as `bunny_*` files.

## WAV master spec (what to record)

* **48 kHz, 24-bit, mono WAV**, one file per line, named exactly `<lineId>.wav`.
* Keep the masters **OUTSIDE the repo**: `~/Music/LittleDays/voice/aliz/` and
  `~/Music/LittleDays/voice/bunny/`. `*.wav` under `game/assets/audio/voice/`
  is git-ignored so a master can never ship by accident.
* Peak about **-3 dBFS**, no clipping, no noise reduction artefacts.
* **No more than 0.1 s** of silence at the head and at the tail.
* Room-quiet, close mic, consistent distance across the whole set so the lines
  match each other in tone.
* Two or three takes per line are welcome; deliver the chosen take under the
  exact filename.

## Delivery format (what the game loads)

    res://assets/audio/voice/<character>/<lineId>.ogg
    (game/assets/audio/voice/aliz/aliz_001_welcome.ogg, game/assets/audio/voice/bunny/bunny_003_yummy.ogg, ...)

OGG Vorbis, **44.1 kHz mono, about 96 kb/s**. Produced from the masters by:

    tools/voice_convert.sh ~/Music/LittleDays/voice

The script uses `oggenc` (vorbis-tools) or `ffmpeg`, whichever is installed
(`afconvert` is tried last and its failure is reported), validates each
duration (0.3 s - 6.0 s), writes the OGGs into the two drop-in folders and a
`voice_pack_report.json` beside them. A partial delivery is fine: a line with
no file keeps using the device voice.

Each drop-in folder has a README with the exact filenames.

## Set A -- Aliz, general

| # | lineId | English text | Emotion / direction | Used when |
|---|--------|--------------|---------------------|-----------|
| 1 | `aliz_001_welcome` | Welcome to Little Days! | cheerful | menuReady |
| 2 | `aliz_002_lets_play` | Let's play together! | excited | menuReady |
| 3 | `aliz_003_come_on` | Come on, Bunny! | inviting | callBunny |
| 4 | `aliz_004_lets_go_home` | Let's go home! | bright | startPressed |
| 5 | `aliz_005_what_shall_we_do` | What shall we do today? | curious | freePlayStart |
| 6 | `aliz_006_good_job` | Great job! | praise | encouragementGreat |
| 7 | `aliz_007_well_done` | You did it! | delighted | encouragementWellDone |
| 8 | `aliz_008_try_again` | Let's try again! | encouraging | encouragementTryAgain |
| 9 | `aliz_009_its_okay` | It's okay. We can do it! | warm | secondMiss |
| 10 | `aliz_010_follow_me` | Follow me! | inviting | followMe |

## Set B -- Bunny

| # | lineId | English text | Emotion / direction | Used when |
|---|--------|--------------|---------------------|-----------|
| 1 | `bunny_001_hungry` | I'm hungry, Aliz! | hungry, pleading | needHungry |
| 2 | `bunny_002_milk` | Milk, please! | asking, cute | milkPrompt |
| 3 | `bunny_003_yummy` | Yummy! | delighted | foodBite |
| 4 | `bunny_004_more` | More, please! | eager | mealHalfway |
| 5 | `bunny_005_thank_you` | Thank you, Aliz! | grateful, happy | careCompleted |
| 6 | `bunny_006_sleepy` | I'm sleepy. | sleepy, soft | needSleepy |
| 7 | `bunny_007_good_night` | Good night! | sleepy, content | bedtimePlaced |
| 8 | `bunny_008_bath` | Bath time! | excited | needBath |
| 9 | `bunny_009_play` | Play with me! | playful | needWantsToPlay |
| 10 | `bunny_010_hug` | Hug me, please! | tender, pleading | needComfort |
| 11 | `bunny_011_happy` | Yay! | delighted | celebrate |
| 12 | `bunny_012_upset` | Hmph! | cute sulk | wrongItem |

## Set C -- Aliz, learning prompts

| # | lineId | English text | Emotion / direction | Used when |
|---|--------|--------------|---------------------|-----------|
| 1 | `aliz_011_apple` | Let's give Bunny the apple! | bright, guiding | taskApple |
| 2 | `aliz_012_banana` | Let's peel the banana! | bright, guiding | taskBanana |
| 3 | `aliz_013_drink` | Time for a drink! | bright, guiding | taskDrink |
| 4 | `aliz_014_milk_time` | Let's make some milk! | bright, excited | taskPrepareMilk |
| 5 | `aliz_015_bath_time` | Let's take a bath! | bright, guiding | taskBath |
| 6 | `aliz_016_brush_teeth` | Let's brush our teeth! | bright, guiding | taskBrushTeeth |
| 7 | `aliz_017_bedtime` | Time for bed! | soft, warm | taskBedtime |
| 8 | `aliz_018_clean_up` | Let's put the toys away! | bright, guiding | taskTidy |
| 9 | `aliz_019_cooking` | Let's cook something yummy! | excited | taskCooking |
| 10 | `aliz_020_all_done` | All done! | pleased | taskDone |

## Set D -- Aliz, rewards and break

| # | lineId | English text | Emotion / direction | Used when |
|---|--------|--------------|---------------------|-----------|
| 1 | `aliz_021_star` | You earned a star! | delighted | starAwarded |
| 2 | `aliz_022_sticker` | A new sticker for you! | delighted | stickerUnlocked |
| 3 | `aliz_023_break` | Let's take a little break! | gentle, caring | breakCard |
| 4 | `aliz_024_come_back` | Come back soon for more Little Days! | warm, cheerful | breakCard |

## Where each line plays

See the cue table in `docs/VOICE_PACK_V1.md` (and `game/scripts/voice/voice_cues.gd`):
menu ready plays 1 then 2; Start / Free Play plays 4; the highchair asks with
11-13, cheers with Bunny's 3/4/5 and sulks with 12 on a wrong item (with the
`hmph` face); stars and stickers play 21/22 on the summary; the break card
plays 23 then 24.

## Legacy drop-in (still honoured, not requested)

The earlier text-keyed drop-in `res://audio/voice/<lineId>.ogg` read by
`scripts/speech/voice_lines.gd` still works for the device-voice path and is
kept so nothing regresses, but **no new recordings should go there**. New
recordings go to the per-character folders above.
