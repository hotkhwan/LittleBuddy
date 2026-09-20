# Voice Pack V1 -- architecture, rules, cue table, and what is missing

Little Days, 2026-09-20. Agent V. Branch `wt3/voice`.

## What is honestly missing

**All 36 recordings.** Nothing has been recorded. `game/assets/audio/voice/aliz/`
and `/bunny/` hold a README each and no audio. Every line in the game today is
spoken by the device voice (`TtsService`) with the manifest's English text; the
subtitle strip shows that text; `Voice.is_recorded(id)` is false for every id;
the test run prints:

    voice pack: 0 of 36 recordings present

When a recording is dropped in (see `docs/VOICE_ASSET_REQUEST.md` for the spec
and `tools/voice_convert.sh` for the conversion) that line switches to the
recording with **no code change**. Nothing in the code fakes a recording: there
is no placeholder file, no pretend duration, no flag that says "recorded" for a
file that is not there.

## Pieces

| file | role |
|---|---|
| `game/content/voice/voice_manifest.json` | the owner's 36 lines: `lineId`, `character`, `text`, `emotion`, `usage`, `file` |
| `game/scripts/voice/voice_manifest.gd` | loads the JSON; `text_for`, `character_for`, `line_id_for_text`, `is_recorded`, `missing_line_ids`, `validate`. Engine-agnostic. |
| `game/scripts/voice/voice_cues.gd` | pure table: game event -> ordered line ids (`for_event`, `for_need`, `for_task`, `for_encouragement`, `for_text`, `face_for`) |
| `game/scripts/voice/voice_director.gd` | autoload `Voice`: `say`, `say_all`, `say_text`, `stop`, `is_speaking`, `current_line`, `is_recorded`, per-character volume, `line_started`/`line_finished` |
| `game/scripts/voice/voice_bridge.gd` | static null-guarded one-liners for call sites: `cue`, `say_lines`, `say_text`, `voice` |
| `game/scripts/voice/subtitle_strip.gd` | the cream pill; mounted by the house HUD, the feeding HUD and the menu |
| `game/scripts/audio/music_binder.gd` | `should_duck()` now also reads `Voice.is_speaking()` |
| `game/scripts/speech/tts_service.gd` | reads `alizVoiceVolume` (then the old `voiceVolume`) for its level |
| `game/assets/audio/voice/{aliz,bunny}/README.md` | drop-in folders, exact filenames, format |
| `tools/voice_convert.sh` | WAV masters (outside the repo) -> 44.1 kHz mono ~96 kb/s OGG; validates durations; writes `voice_pack_report.json` |
| `docs/patches/agentV_project_godot.diff` | the one-line `Voice` autoload for the lead |

Until the lead applies the autoload patch, every caller reaches the director
through `/root/Voice` with a null guard and falls back to what it did before
(TtsService). The game is complete either way.

## How a line plays

```
call site ──VoiceCues.for_event(...)──> line ids ──Voice.say(id, opts)──┐
                                                                        │
              ┌─────────────────────────────────────────────────────────┘
              ▼
   manifest.is_recorded(id)?
      yes ─> AudioStreamPlayer (one per character, bus "Voice")      ─┐
      no  ─> TtsService.speak(manifest text)  (same queue rules)     ─┤─> line_started(id, character, text)
                                                                      │   ... line_finished(id)
   music_binder.should_duck() == TtsService.is_speaking() or Voice.is_speaking()
   subtitle_strip listens to line_started / line_finished
```

The "Voice" bus is created at runtime by the director when absent (sends to
Master), so no bus-layout file had to be added.

## Never two voices at once

* Before a recording starts, `TtsService.stop()` is called if it is speaking.
* A fallback line is ONE `TtsService` utterance; the director waits for its
  `speech_finished` and only then moves the queue.
* While the device voice is busy with a prompt that is not ours (a mode
  handler's instruction), a non-interrupting line **waits** -- a prompt the
  child has not finished hearing is never cut for a reaction.
* If the same words reach both paths (a mode handler speaks "Let's make some
  milk!" through TTS and the cue asks for `aliz_014_milk_time`), the director
  **adopts** the utterance already playing instead of saying it twice; if a
  recording of those words is already playing, the TTS duplicate is stopped.
* If someone hands TTS a *different* prompt while a recording plays: a
  **narration** recording yields at once (the prompt is what the child must
  hear); a **reaction** recording younger than 2.5 s ("Yummy!", "Hmph!") is
  protected -- the prompt (and anything queued behind it) is taken off the
  device voice and said right after the reaction. Every Bunny line is a
  reaction; Aliz's praise is one when asked (`reaction: true`).
* A fallback reaction uses `TtsService.react()`, whose own 2.5 s protection
  does the same for the device voice.
* `interrupt: true` stops the device voice first, then plays.

All of these are driven in `test_voice_director.gd`.

## Queue rules

| situation | result |
|---|---|
| `say(aliz)` while Bunny is playing | Bunny is cut, queued Bunny lines are dropped, Aliz plays now |
| `say(aliz)` while Aliz is playing | queued behind her (her older queued lines are replaced) |
| `say(bunny)` while Aliz is playing | queued behind Aliz (never interrupts) |
| `say(bunny)` while Bunny is playing | queued behind himself, replacing his queued lines |
| `say(x, {queue: true})` | never cuts, never replaces: plain FIFO |
| `say_text("Nice!")` | the alias's recorded line under the same rules |
| `say_text("Walk to the kitchen.")` | an ad-hoc Aliz line on the device voice, under the same rules, subtitled |
| `say(x, {interrupt: true})` | cuts anything (recording or TTS, ours or not), clears the queue |
| `say_all([a, b])` | a under the rules above, then b appended in order |
| `stop("bunny")` | cuts Bunny's current line, drops his queued lines, Aliz untouched |
| `stop()` | silence, including a foreign TTS prompt |
| foreign TTS prompt is playing | a default/queued line waits for it; an interrupting line stops it |

`MAX_QUEUED` is 6; the oldest queued line is dropped past that.

## Cue table

| event (`VoiceCues.EVENT_*`) | detail | line ids | who calls it |
|---|---|---|---|
| menuReady | | aliz_001_welcome, aliz_002_lets_play | main.gd, once per launch |
| startPressed | | aliz_004_lets_go_home | main.gd Start/Continue |
| freePlayPressed | | aliz_004_lets_go_home | main.gd Free Play |
| callBunny / followMe / whatShallWeDo | | aliz_003 / aliz_010 / aliz_005 | reserved (no call site yet) |
| need | hungry | bunny_001_hungry | child_actor.gd on need change (per-need cooldown) |
| need | thirsty | bunny_002_milk | child_actor.gd |
| need | sleepy | bunny_006_sleepy | child_actor.gd |
| need | needsBath / dirty | bunny_008_bath | child_actor.gd |
| need | wantsToPlay | bunny_009_play | child_actor.gd |
| need | needsComfort / crying | bunny_010_hug | child_actor.gd |
| need | needsChanging | (none) | -- |
| needUrgent | | bunny_012_upset + face `hmph` | child_actor.gd, once per ignored need |
| milkPrompt | | bunny_002_milk | feeding_table.gd when the target item is `milk` (the bottle; the current tray has water) |
| task | apple / banana / water / milk / prepareMilk / bath / brushTeeth / bedtime / tidy / cooking | aliz_011 .. aliz_019 | feeding_table.gd per item; `_speak()` text routing |
| foodBite | | bunny_003_yummy | feeding_table.gd first bite / first sip |
| mealHalfway | | bunny_004_more | feeding_table.gd half-way bite / gulp |
| careCompleted | | bunny_005_thank_you | feeding_table.gd on success |
| taskDone | | aliz_020_all_done | feeding_table.gd after thank-you |
| wrongItem | | bunny_012_upset + face `hmph` | feeding_table.gd wrong item |
| encouragement | Great!/Nice!/Yes!/Great job! | aliz_006_good_job | `_speak()` routing (freeplay, prompt_speaker, feeding) |
| encouragement | You did it!/Well done! | aliz_007_well_done | same |
| encouragement | Try again!/Almost!/Try the X! | aliz_008_try_again (+ aliz_009_its_okay on the 2nd miss) | feeding_table.gd, `_speak()` routing |
| celebrate | | bunny_011_happy | reserved for the reward moment |
| bedtimePlaced / bath | | bunny_007_good_night / bunny_008_bath | reserved for the house acts |
| star | | aliz_021_star | session_summary.gd when stars were earned |
| sticker | | aliz_022_sticker | session_summary.gd when a sticker unlocked |
| breakCard | | aliz_023_break, aliz_024_come_back | **Agent S** (session safe-point / break card) |

`for_text(text)` maps any spoken English to a line: exact manifest text first,
then the encouragement table, then a short alias table (`voice_cues.gd`
`TEXT_ALIASES`). A text with no row returns `""` and the caller keeps TTS.

Subtitles show the recording's English, which for an alias ("Nice!" ->
"Great job!") is the owner's wording. The HUD helper (Thai) line is unchanged
and never spoken.

## API for Agent S (settings screen, break card)

```gdscript
var voice: Node = get_node_or_null("/root/Voice")
if voice != null:
    voice.set_character_volume("aliz", 0.8)   # 0..1, persists alizVoiceVolume
    voice.set_character_volume("bunny", 0.7)  # 0..1, persists bunnyVoiceVolume
    voice.get_character_volume("aliz")        # -> float
    voice.character_volume_changed            # signal(character, linear)
    voice.presence_summary()                  # "0 of 36 recordings present"
    voice.say_all(VoiceCues.for_event(VoiceCues.EVENT_BREAK_CARD))   # break, then come back
```

Setting keys: `alizVoiceVolume`, `bunnyVoiceVolume` (via `SaveService`). The
old `voiceVolume` is migrated into `alizVoiceVolume` once at first boot;
`TtsService` reads `alizVoiceVolume` first, then `voiceVolume`, so a build
where S has not yet rebound the slider still behaves.

## Evidence (2026-09-20, this checkout)

* `docs/shots/voice_subtitle_house.png` -- Story HUD, 1334x750: the cream pill
  "Let's make some milk!" bottom-centre, clear of Next, Speak, Home and the
  thumbstick's rest ring (`tests/shots_voice.gd` asserts each).
* `docs/shots/voice_subtitle_feeding.png` -- the highchair after a wrong item:
  Bunny's `hmph` face and the strip.
* Test run: `PASS - 144 case(s)`; `smoke_mission01.gd`, `-- snackTime` and
  `smoke_audio_shipping.gd` all PASS with the pack code in place (the `Voice`
  autoload is not registered on this branch; the paths run through
  `/root/Voice` null guards and the tests park a director there).
* Both frames were taken with **0 of 36 recordings present**: what is heard
  is the device voice; what is seen is the pack's strip.

Run the shots with a window (the headless renderer never reaches
`frame_post_draw`):

    Godot --path game --resolution 1334x750 --script res://tests/shots_voice.gd

## Known trade-offs

* Mode handlers (`scripts/gameplay/mode_handler.gd`, not in this pass) still
  hand their instruction to `TtsService` directly. The pack adopts an
  utterance with the same words rather than repeating it, and `TtsService`
  itself no longer repeats words it is already saying, so nothing doubles --
  but a task's instruction is only a *recording* when it arrives through
  `PromptSpeaker` or one of the wired `_speak()` paths. Routing
  `mode_handler._speak()` through `VoiceBridge.say_text()` is a one-hunk
  follow-up for whoever owns that file.
* On the highchair, Aliz's learning line ("Let's give Bunny the apple!") plays
  AFTER the mission's own "I'm hungry." / "Give the baby the apple." -- three
  lines at a task start. Once recordings exist that is the warm human voice
  the owner asked for; on the device voice it is one extra line. Dropping the
  cue is one line in `feeding_table.set_task()` if it proves too chatty.
* The feeding strip sits on the bottom edge and overlaps the lower rim of the
  centre plate at 16:9. It ignores touches (drag targets are unaffected); it
  is the least-worst spot on a screen whose bottom is the tray.

## Tests

* `test_voice_manifest.gd` -- structure, the 36 owner ids/texts pinned, folders,
  `.gitignore`, docs; REPORTS presence (`0 of 36`).
* `test_voice_cues.gd` -- every row resolves to a real line, the owner rows,
  text routing, determinism, `hmph` on a mistake.
* `test_voice_director.gd` -- queue rules, interrupt/stop, sequences, the four
  no-simultaneous-playback cases, fallback, adopt-don't-repeat, volume
  persistence + migration, no-TTS build, subtitle strip, autoload shape/patch.
* `test_voice_wiring.gd` -- a director parked at `/root/Voice`: the highchair
  cues (learning line, Yummy!, More please!, Hmph! + hmph face + Let's try
  again! + It's okay, Thank you Aliz! then All done!), Bunny's need cooldown
  and single Hmph!, the summary's star/sticker lines, the menu's once-per-launch
  welcome, `PromptSpeaker` routing without double-speak, and the no-`Voice`
  path still speaking through TtsService.
