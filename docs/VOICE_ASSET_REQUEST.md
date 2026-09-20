# Voice asset request -- owner-recorded lines

Little Days, 2026-09-20. Agent F (audio/speech).


## What these are for

The game speaks English to the child through the device voice (compact Samantha
on this Mac; the best en-US voice the iPad has). A recorded human voice is warmer
and does not depend on which voices a device happens to have. This is the list
of lines to record so they can be dropped in **without any code change**.

## Drop-in path

    res://audio/voice/<lineId>.ogg        (game/audio/voice/<lineId>.ogg)

* `<lineId>` is the id in the first column below, exactly (lower case, underscores).
* `.ogg` (Vorbis, q4) preferred; `.wav` or `.mp3` also work.
* Mono or stereo, 44.1 kHz. Peak about -3 dBFS. No leading silence; about 0.1 s of tail.
* One file per line. A line with no file simply keeps using the device voice, so
  a partial delivery is fine and can be topped up later.
* `TtsService` checks `VoiceLines.stream_for(text)` before it speaks; music ducks
  under a recording exactly as it does under the device voice.
* The **Voice volume** slider in Grown-ups applies to recordings too.

## Voice direction

One performer, one voice, for every line: bright, kind, unhurried, addressed to a
3-5 year old who is learning English. Not a cartoon voice, not baby talk -- clear
consonants, natural pitch (a real child or a warm adult), a smile you can hear.
No disappointment anywhere: "Try again!" is an invitation. Speak the single words
("milk", "apple") slowly and completely, as a model to copy.

## The lines

| # | lineId | English text | Intended emotion | Target length |
|---|--------|--------------|------------------|---------------|
| 1 | `im_hungry_aliz` | I'm hungry, Aliz! | hungry, a little whiny, cute | ~1.6 s |
| 2 | `go_to_bunny` | Go to Bunny. | warm, guiding | ~1.2 s |
| 3 | `lets_make_some_milk` | Let's make some milk! | bright, excited | ~1.6 s |
| 4 | `walk_to_the_kitchen` | Walk to the kitchen. | calm, clear | ~1.5 s |
| 5 | `where_is_the_bottle` | Where is the bottle? | curious, playful | ~1.5 s |
| 6 | `find_the_baby_bottle` | Find the baby bottle. | calm, clear | ~1.5 s |
| 7 | `pour_the_water_then_mix` | Pour the water, then mix. | calm, step by step | ~2.0 s |
| 8 | `take_it_to_bunny` | Take it to Bunny! | encouraging | ~1.3 s |
| 9 | `time_to_drink` | Time to drink! | happy | ~1.2 s |
| 10 | `give_bunny_the_bottle` | Give Bunny the bottle. | warm | ~1.5 s |
| 11 | `bunny_wants_a_cuddle` | Bunny wants a cuddle. | soft, tender | ~1.6 s |
| 12 | `give_bunny_a_big_hug` | Give Bunny a big hug. | warm, smiling | ~1.6 s |
| 13 | `thank_you_aliz` | Thank you, Aliz! | grateful, happy | ~1.3 s |
| 14 | `im_hungry` | I'm hungry. | hungry, cute | ~1.0 s |
| 15 | `im_thirsty` | I'm thirsty. | thirsty, cute | ~1.0 s |
| 16 | `give_the_baby_some_milk` | Give the baby some milk. | warm, guiding | ~1.8 s |
| 17 | `give_the_baby_the_apple` | Give the baby the apple. | warm, guiding | ~1.8 s |
| 18 | `give_the_baby_the_banana` | Give the baby the banana. | warm, guiding | ~1.8 s |
| 19 | `give_me_some_water` | Give me some water. | asking, cute | ~1.5 s |
| 20 | `can_you_say_milk` | Can you say milk? | inviting, patient | ~1.4 s |
| 21 | `milk` | milk | clear, slow, single word | ~0.8 s |
| 22 | `apple` | apple | clear, slow, single word | ~0.8 s |
| 23 | `banana` | banana | clear, slow, single word | ~0.9 s |
| 24 | `water` | water | clear, slow, single word | ~0.8 s |
| 25 | `great` | Great! | delighted | ~0.7 s |
| 26 | `nice` | Nice! | pleased | ~0.6 s |
| 27 | `well_done` | Well done! | proud, warm | ~0.9 s |
| 28 | `thank_you` | Thank you! | grateful, happy | ~0.9 s |
| 29 | `try_again` | Try again! | kind, no disappointment | ~0.9 s |
| 30 | `you_can_tap_it_too` | You can tap it too! | kind, helpful | ~1.4 s |
| 31 | `lets_go` | Let's go! | bright | ~0.8 s |
| 32 | `this_way` | This way! | guiding, cheerful | ~0.8 s |
| 33 | `here_we_are` | Here we are! | arriving, pleased | ~1.0 s |
| 34 | `im_listening` | I'm listening... | attentive, gentle | ~1.2 s |
| 35 | `voice_is_not_ready_tap_it_instead` | Voice is not ready. Tap it instead! | matter-of-fact, kind | ~2.0 s |
| 36 | `take_a_break` | Take a break? | gentle, caring | ~1.0 s |

36 lines. The ids are `Localization.key_for(<English text>)`, the same keys
the helper-language tables use (`game/content/localization/keys_en.json`), so one
id names a line everywhere.

## Delivery checklist

1. Save each file as `game/audio/voice/<lineId>.ogg`.
2. Open the project once (or run `Godot --headless --path game --import`) so the
   `.import` files are generated.
3. Run the mission smoke: the prompt "I'm hungry, Aliz!" should now be the
   recording; any line without a file is still spoken by the device voice.
4. `tests/cases/test_tts_voice_lines.gd` keeps this table and the code in step.

## Not requested (and why)

* Thai / other-language helper lines: the helper is TEXT ONLY by design. The
  child hears English; the grown-up reads the helper.
* Bunny's sounds and reactions: sound effects, not speech, and already covered by
  `game/audio/sfx/`.
