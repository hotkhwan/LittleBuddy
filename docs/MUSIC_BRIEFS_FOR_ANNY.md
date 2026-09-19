# Music briefs — Little Buddy

**For:** Anny (Content & Creative Lead)
**From:** audio integration
**Date:** 2026-09-19
**Status:** the game is built and shipping **silent**. Music is additive. Nothing is blocked
on these two tracks, and nothing breaks if they never arrive — so take the time to get them
right rather than fast.

---

## Read this page first (5 minutes, saves an hour)

Two tracks, described in full in §1 and §2. For each one you need:

1. a **prompt** to paste into Suno (given verbatim — edit freely, it is a starting point),
2. an **export** at the settings in §3,
3. a **filename** exactly as in §3,
4. **licence evidence** saved as in §4.

Then hand the files and the evidence over. Dropping them in is a two-minute job on our side
and needs no code change (`docs/AUDIO_MANIFEST.md` has that procedure).

### The three rules that matter more than the music

**1. Nothing startling.** The player is a 4-year-old holding an iPad about 30 cm from their
face, often with the volume near maximum because the English prompts are quiet. No sudden
entrances, no cymbal crashes, no stings, no risers, no drops, no gunshot snares, no sub-bass
thumps. Every one of our sound effects has a measured 5–60 ms attack ramp for this reason and
is tested for it. Music is held to the same standard by ear: if a moment makes *you* blink,
it will make a child flinch.

**2. No lyrics. At all.** Instrumental only.
  - Words fight the English we are teaching. The child is meant to hear *"Can you say
    milk?"*, and a vocal line is the one thing that competes with a spoken prompt.
  - Lyrics date a product ("hey, let's go!"), and they cannot be localised. This game is
    being built for a Thai-speaking child learning English; an English vocal in the
    background is a second, contradictory English lesson.
  - Wordless "ooh/aah" pads are acceptable **if** they read as an instrument rather than as
    someone singing to the child. Prefer no voice at all.

**3. It must loop for twenty minutes without becoming annoying.** This is not background
music for a trailer; it is background music for a small child who will replay the same room
thirty times. Ask yourself: *would I be happy hearing this in the next room for half an
hour?* Sparse beats busy. Tracks that breathe beat tracks that fill.

---

## 1. `littleDaysTheme` — the title and menu theme

**Where it plays:** the title screen and menus. It is the first thing anyone hears, and for a
parent it is the sound of handing the iPad over. Warm, unhurried, welcoming — a "come and sit
down" piece, not a "here we go!" piece.

| | |
|---|---|
| **Mood** | warm, gentle, welcoming, a little nostalgic; safe rather than exciting |
| **Tempo** | 70–85 BPM |
| **Key feel** | major, no unresolved tension; avoid anything that sounds like a question |
| **Instrumentation** | felt/upright piano or celesta lead; soft nylon guitar; glockenspiel or music box for sparkle; warm pad underneath; light shaker or brushed percussion at most — **no drum kit** |
| **Length** | 60–90 s that loops (see §3 on loopability) |
| **Dynamics** | narrow. Quietest to loudest moment within about 6 dB |
| **Arrangement** | 2–4 instruments at any one time. Leave space |
| **Avoid** | lyrics, orchestral swells, cymbals, brass, four-on-the-floor kick, EDM anything, "epic" build-ups, big final chord |

**Suno prompt — paste this:**

> Gentle instrumental children's lullaby-waltz, 78 BPM, warm major key. Soft felt piano
> melody with music box and glockenspiel sparkle, nylon string guitar, warm analogue pad
> underneath, light shaker only. Cosy, welcoming, nostalgic, unhurried. Very narrow dynamic
> range, soft attacks, no percussion hits, no cymbals, no brass, no build-up, no drop.
> Seamless loop, consistent arrangement throughout, no intro fill and no big ending.
> Instrumental only, absolutely no vocals.

**Negative prompt / exclude (if the tool offers the field):**
`vocals, singing, lyrics, choir, cymbal, crash, snare, kick drum, riser, drop, sting, sub
bass, orchestral swell, key change, tempo change, silence gaps`

**Test before you accept a take:** play it twice in a row, back to back. If you notice the
moment it restarts, it is not a loop yet — try another generation or a different section.

---

## 2. `hungryBunny` — the milk-mission theme

**Where it plays:** during the feeding mission. The baby is hungry, the child finds the milk
and is asked *"Can you say milk?"*. The music's whole job is to make the little task feel
light and fun **while staying out of the way of that sentence.** It sits about 4 dB quieter
than the menu theme in the mix for exactly that reason.

Playful and slightly comic — think a small creature padding about on a small errand. Comic in
the sense of *charming*: bouncy pizzicato and a cheeky bassoon, never slapstick, never a
cartoon "boing". Nothing may sound like a mistake or a wrong answer; this game has no failure
sound and no red X, and the music must not supply one.

| | |
|---|---|
| **Mood** | playful, light, gently comic, busy-but-calm; curious rather than urgent |
| **Tempo** | 95–110 BPM |
| **Key feel** | major, bouncy, resolved |
| **Instrumentation** | pizzicato strings; marimba or xylophone; bassoon or clarinet for the comic wink; ukulele; soft woodblock/brushed shaker |
| **Length** | 45–75 s that loops |
| **Dynamics** | narrow, and **quieter overall than the menu theme** — it plays under speech |
| **Arrangement** | a simple repeating figure with room in the middle for a voice |
| **Avoid** | lyrics, sad or "wrong answer" cadences, comedy sound effects (boings, slide whistles, sad trombone), accelerating sections, anything urgent or chase-like, anything that sounds like a timer |

**Suno prompt — paste this:**

> Playful light instrumental cartoon-cute cue, 104 BPM, bright major key. Pizzicato strings
> and marimba melody, ukulele, soft bassoon countermelody for gentle comedy, light woodblock
> and brushed shaker. Curious, bouncy, charming, never urgent. Sparse arrangement with space
> in the middle register. Very narrow dynamic range, soft attacks, no cymbals, no drum kit,
> no accelerando, no comedy sound effects. Seamless loop, consistent throughout, no intro and
> no ending. Instrumental only, absolutely no vocals.

**Negative prompt / exclude:**
`vocals, singing, lyrics, cymbal, crash, drum kit, slide whistle, sad trombone, boing,
accelerando, tension, minor key, chase music, siren, alarm, clock ticking`

**Test before you accept a take:** play it and say *"Can you say milk?"* out loud over the
top. If you had to raise your voice, the track is too busy in the middle.

---

## 3. Export settings and file names

**Export from Suno at the highest quality available to you.** In order of preference:

1. **WAV** — 44.1 kHz, 16-bit or 24-bit, stereo. Best; take it if your plan offers it.
2. **MP3** — 320 kbps CBR, 44.1 kHz, stereo. Perfectly fine.

Either works. The loader accepts `.wav`, `.mp3` and `.ogg` and finds the file by name, so
**do not convert anything** — a conversion by hand is a chance to lose quality for no gain.
We will convert to OGG Vorbis on our side if the file size needs it.

**Level.** Do not normalise, maximise, or "master for loudness". Aim for roughly **−18 LUFS
integrated** with **true peak at or below −3 dBFS**. If that means nothing to you, the
practical version is: leave Suno's output alone, and if you do touch it, make it *quieter*
rather than louder. The game attenuates music by a further 12–16 dB anyway, and a squashed,
loud master sounds worse after attenuation, not better. A track with headroom always wins.

**File names — exactly these, all lower case, no spaces, no version suffix:**

| trackId | file name (keep the extension you exported) |
|---|---|
| `littleDaysTheme` | `little_days_theme.wav` / `.mp3` |
| `hungryBunny` | `hungry_bunny.wav` / `.mp3` |

Keep your own working versions (`little_days_theme_v03.wav`, rejected takes, stems) wherever
you like, but **hand over exactly one file per track with exactly that name.** The name is
what the game looks for.

**Loopability.** The engine loops the whole file by default. Two options:

- **Preferred:** give us a file that loops when its end meets its start. Suno will usually
  fade or resolve at the end; where it does, trim the fade off and end the file on the beat
  before the phrase would repeat.
- **Alternative:** hand over the raw generation and tell us *"loop from 4.2 s to 63.8 s"*. We
  can set loop points per track in the manifest without touching the file. If you are unsure,
  choose this — an honest note beats a guessed edit.

**Length note.** A 60–90 s loop is the target. Shorter is worse (audible repetition), much
longer is fine but wastes app size. Nothing over about 3 minutes, please.

---

## 4. Licence evidence — the part that cannot be skipped

Every track in this game has to be provably ours to ship, **commercially**, and the proof has
to live in the repository rather than in anyone's memory. Until the evidence exists, the
loader refuses to play the track — that refusal is deliberate, it is tested, and it is not a
bug to be worked around.

**For each track, save all four of these:**

1. **A screenshot of the Suno generation page** showing the track, the date, and that it is
   your generation on your account.
2. **A screenshot or PDF of the plan/terms page** that grants you commercial use of your own
   generations, with the **date you captured it** visible. Suno's terms differ by plan
   (free-tier generations are typically *not* cleared for commercial use). This is the one
   piece of evidence that actually matters.
3. **The account and plan name** you generated on, in writing.
4. **The exact prompt** you used, in writing.

Put them in `docs/licences/music/<trackId>/` (create it) and tell us the path. We record it in
`game/content/audio/manifest.json` as `licenseEvidence`, set `commercialUse` to `"verified"`,
and only then will the track play.

**Three hard rules, no exceptions:**

- **Never rip audio from YouTube**, or from any site, service, game or video. Not as a
  placeholder, not "just to test the timing", not temporarily. A ripped file in a repository
  is a shipped file eventually.
- **No "free music" from a site whose licence you have not read to the end.** "Free" usually
  means free for non-commercial use with attribution, which is not what this project needs.
- **If you are not certain, say so.** A track marked `pending` is completely fine — the game
  simply stays silent there, which it already does. A track marked `verified` on a guess is
  the only outcome here that is actually a problem.

---

## 5. What happens after you hand the files over

1. We drop the files into `game/audio/music/`.
2. We fill in the manifest row: `source`, `createdAt`, `downloadedAt`, `licenseEvidence`,
   `commercialUse: "verified"`, and loop points if you gave us any.
3. The track starts playing. No code changes, no new build steps.
4. We check the mix by ear against the spoken prompts and adjust `volumeDb` in the manifest
   if music is competing with the English. That is a one-number change and needs nothing from
   you.

If a take is nearly right but not quite, say so and generate another. Silence is a perfectly
good state for this game to be in, and a track nobody enjoys hearing for the thirtieth time
is worse than no track at all.
