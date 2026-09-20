# Voice honesty pass — 2026-09-20 (Agent E, branch `wt/voice`)

Owner feedback: the voice sounds like a robot; the speak/response loop is slow;
Mission 01 should feel like a conversation. Three systems were audited separately.

## A. Text-to-speech — what this Mac actually has

`DisplayServer.tts_get_voices()` (windowed run, Godot 4.7.2, macOS 26.5, 180 voices in
total). Every `en-*` entry:

| tier | voices present |
|---|---|
| natural, en-US | **Samantha** (`com.apple.voice.compact.en-US.Samantha`) — the only one |
| natural, other English | Daniel en-GB, Karen en-AU, Moira en-IE, Rishi en-IN, Tessa en-ZA (all `super-compact`) |
| Eloquence (mechanical) | Eddy, Flo, Grandma, Grandpa, Reed, Rocko, Sandy, Shelley (en-US and en-GB) |
| novelty (MacinTalk) | Albert, Bad News, Bahh, Bells, Boing, Bubbles, Cellos, Wobble, Fred, Good News, Jester, **Junior**, Kathy, Organ, **Superstar**, Ralph, Trinoids, Whisper, Zarvox |

The old code spoke with `tts_get_voices_for_language("en")[0]`, which on every Apple
device resolves to **compact Samantha** — the lowest-quality tier Apple ships. That is the
robot the owner heard.

**Chosen voice on this Mac: Samantha (compact)** — because it is the only natural en-US voice
installed. Pitch is now 1.15 (was 1.05) and rate 0.92 (was 0.85), which makes the same
voice lighter and quicker; it does not make it a child.

**Fallback chain** (`TtsService.choose_voice()`, tested against the list above):
1. `PREFERRED_VOICE_IDS`, in order: Zoe (premium/enhanced) → Nicky → Ava → Allison →
   Samantha enhanced → Joelle → Susan → Samantha compact;
2. any natural-tier (`com.apple.voice.*`) en-US voice, female names first;
3. any natural-tier voice in any English locale, female names first;
4. any en-US voice that is not an Eloquence/novelty engine, then any English one;
5. anything English at all (so a device with only novelty voices still speaks).

**Plainly: there is no child voice on any Apple device.** "Junior" and "Superstar" are
child-*named* novelty voices from 1990s MacinTalk and sound worse than Samantha. Nothing
here fakes one, clones one, or calls a cloud service.

The immediate improvement that needs no code: on the Mac, System Settings → Accessibility →
Spoken Content → System voice → Manage Voices → download **Zoe (Premium)** or
**Samantha (Enhanced)**; on the iPhone/iPad, Settings → Accessibility → Spoken Content →
Voices → English → the same. Once downloaded the game picks it up within 10 s, fully
on-device (the app itself has no network code — `otool -L` shows none).

The real path to a bright, small, girl's voice is **recorded lines by a voice actor bundled
as OGG**: Mission 01 needs ~20 lines; `AudioDirector`/`SfxPlayer` already play bundled OGG
and the prompt text is data-driven, so a `voiceLines/<lineId>.ogg` lookup in front of
`TtsService.speak()` (TTS as the fallback for any missing line) is a contained change.

### Evidence run (windowed, this Mac)

`speak_evidence.gd` instantiated `tts_service.gd`, reacted "Great!" and spoke Mission 01's
first two lines. Output: `selected voice: com.apple.voice.compact.en-US.Samantha`,
`platform tts_is_speaking became true at 4 ms`, each line resolved when the platform went
silent (1.28 s / 1.5 s / 1.4 s). **The agent cannot hear; "spoken" here means the macOS
synthesiser reported itself speaking for the length of the line.** No device claim is made.

### Responsiveness fixes in TTS

- `TtsService` now polls the platform after an utterance starts and releases the queue the
  moment it stops speaking. Measured: the ENDED callback never arrived from
  AVSpeechSynthesizer in a plain run, so every line used to hold the queue for the full
  safety estimate (1.76 s for "Great!").
- `react()`: encouragement ("Great!", "Try again!") is spoken immediately and the next prompt
  queues behind it instead of cutting it off. `PromptSpeaker` connects the runner's
  `encouragement` signal, so those lines are voiced for the first time.
- The microphone opening stops the game's own voice (`SpeechService._hush_tts()`).

## B. Recognition — never faked, faster to answer

- Native plugin (`ios/speech_plugin/src`): new `partial_result` signal for each interim
  hypothesis; a manual `stop_listening()` now reports the last hypothesis as `recognized`
  (the same policy the 5 s timeout already used) instead of discarding it.
- `SpeechFeedbackBinder`: shows the live guess under "I'm listening…"; the moment a
  hypothesis satisfies the current prompt it ends listening, and the backend's final for
  that hypothesis completes the task — no more waiting for end-of-utterance detection. The
  words are always the recogniser's; the runner still runs its own matcher.
- Retry copy names what was heard ("Try again! I heard: banana. You can tap it too.");
  a timeout reads "Let's try again — tap Speak and say it, or just tap it."
- The mock mirrors the native contract (partial, then final; stop reports the partial) and
  is still unreachable on a device (`OS.has_feature("mobile")` guard untouched; test green).
- `test_speech_never_required` is green: every task and mission still completes by touch.

**On this Mac the native plugin loads in the editor** (`backend = ios`, `is_available =
true`, `has_permission = false` until macOS prompts). The owner's Mac playtest therefore
uses REAL on-device recognition through the Mac microphone, not the mock — the first Speak
press asks for Speech Recognition and Microphone permission.

## C. Mission 01 copy (small vocabulary, camelCase keys, ContentValidator green)

Already in place: intro "I'm hungry, Aliz!", `goToKitchen` "Let's make some milk!",
`feedBunnyCare` "Time to drink!", outro "Thank you, Aliz!". Changed here: Bunny's bubble
line `child_needs.gd` HUNGRY → "I'm hungry, Aliz!". Proposed for lead-owned files (exact
diffs in `docs/patches/`):
- `agentE_care_overlay.diff` — MIX title "Let's make some milk!", childLine "I'm hungry,
  Aliz!"; FEED title "Time to drink!", childLine "Milk, please, Aliz!", doneLine
  "Thank you, Aliz!".
- `agentE_care_tasks.diff` — `bunnyIsHungry` prompt "I'm hungry, Aliz!" (first person);
  `prepareMilkCare` prompt "Let's make some milk!".
- `agentE_house_level_director.diff` — **bug**: nothing in the house connects
  `SpeechService.recognized` to `MissionRunner.on_transcript`, so no task completes by
  speech there (the panel says "Great!" and nothing happens). Three lines fix it.

Mission 01 itself has no `sayIt` task, so the Speak button never appears in it; whether
its `followInstruction`/`findIt` beats should accept speech is a lead/design decision.

## D. Music ducking

Polled duck (`MusicBinder.should_duck()`) still works; tests green. Release lengthened
0.55 → 0.8 s because reactions now duck the music after every beat. Music remains silent by
default (licence gate) — the duck was verified by test, not by ear.
