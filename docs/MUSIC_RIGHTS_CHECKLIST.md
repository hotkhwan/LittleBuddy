# Music rights checklist — the ten minutes that turn the music on

**For:** Khwan and Anny, together. **Time:** about ten minutes. **Date completed:** `____________`

Two original tracks are already in the game, encoded, wired to the right scenes and ducked
under the spoken English. They play **no sound in any build** and will not until this sheet is
filled in, because nobody has recorded what rights they come with.

| | |
|---|---|
| `littleDaysTheme` | `game/audio/music/little_days_theme.ogg` — 92.72 s — menu |
| `hungryBunny` | `game/audio/music/hungry_bunny.ogg` — 64.40 s — the milk mission |
| Both rows today | `commercialUse: "pending"`, `licenseEvidence: "OWNER TO CONFIRM"` |
| Consequence | the licence gate refuses both. A normal build is silent. Verified 2026-09-19. |

Write the answers straight into this file and commit it. **"I'm fairly sure" is not an
answer** — either there is evidence or the field says there is not.

---

## ⚠️ Read this before you answer anything

**The single fact that decides whether this music can ever ship is which plan the account was
on at the moment each track was generated.** Not today's plan. Not the plan when the file was
downloaded. The plan that was active when the Generate button was pressed.

Why that matters so much, and why it has to be answered now:

- Most AI music services grant commercial rights **only for generations made while a paid plan
  was active**, and that grant does not arrive later if you upgrade afterwards. A track made on
  a free plan generally stays non-commercial **forever**, even on a paid account.
- **The fact is not recoverable after the fact.** A track's page does not show which tier was
  active when it was made, billing history shows when money moved rather than what any single
  generation was covered by, and the terms themselves get rewritten without notice. If nobody
  writes it down now, in six months there is no way to establish it — and an unprovable right
  is the same as no right when a store, a publisher or a parent asks.
- If the answer turns out to be "free plan" or "cannot establish it", that is not a disaster
  and it is not a reason to fudge anything. See *If the answer is no* at the end.

**Do not write `"verified"` into the manifest on the strength of a recollection.** The whole
point of the gate is that it refuses music nobody can vouch for.

---

## Part 1 — per track

Answer both columns. If the two tracks came from the same session on the same account, write
"same as Little Days" in the second column — but check, because they were delivered as two
separate files.

### 🔴 BLOCKING — the music cannot ship without these

**1. What tool made it?** (The brief in `docs/MUSIC_BRIEFS_FOR_ANNY.md` asked for Suno. If it
was something else — a different generator, a DAW, a library — say so, because everything
below changes.)

- Little Days: `________________________________________________`
- I'm Hungry!: `________________________________________________`

**2. Which account?** (The email or username the generation lives under, and whose account it
is — Anny's own, Khwan's, or a shared one.)

- Little Days: `________________________________________________`
- I'm Hungry!: `________________________________________________`

**3. Which plan was active AT THE MOMENT OF GENERATION?** (Exact plan name — e.g. Free, Basic,
Pro, Premier. Not "paid, I think". If you cannot establish it, write `CANNOT ESTABLISH` and go
to *If the answer is no*.)

- Little Days: `________________________________________________`
- I'm Hungry!: `________________________________________________`

**4. What date was it generated?** (Needed as well as the plan: it decides *which version* of
the terms governs the track, and the terms change.)

- Little Days: `____________________`
- I'm Hungry!: `____________________`

**5. Does the track contain anything that is not yours?** (Someone else's vocal, a sample, an
uploaded reference audio, lyrics you did not write, a melody quoted from an existing song. A
clear "no, everything in it was generated from my own text prompt" is a valid and important
answer.)

- Little Days: `________________________________________________`
- I'm Hungry!: `________________________________________________`

### 🟡 NICE TO HAVE — record it while you are here; not a blocker

**6. What date was it downloaded?** (The manifest currently records 2026-09-19 for both; correct
it if that is wrong.)

- Little Days: `____________________`
- I'm Hungry!: `____________________`

**7. The track's own page — URL or track ID.** (So a future question can be answered by opening
the track rather than by memory.)

- Little Days: `________________________________________________`
- I'm Hungry!: `________________________________________________`

**8. Has this track been published, licensed or uploaded anywhere else?** (YouTube, Spotify, a
sample pack, another client. Not a blocker for us, but we should know if it is non-exclusive.)

- Little Days: `________________________________________________`
- I'm Hungry!: `________________________________________________`

---

## Part 2 — the evidence

### 🔴 BLOCKING — at least one of 9a and 9b must exist

**9. Which of these do you actually have?** Tick what exists; do not tick what you could
probably get.

- [ ] **9a. Screenshot of the generation page** showing the track, its date, and that it is
      your generation on your account. `File: ____________________`
- [ ] **9b. Screenshot or PDF of the plan / billing page** showing which plan was active on the
      generation date, with the **date of capture** visible. `File: ____________________`
- [ ] **9c. Receipt or invoice** for the plan covering the generation date.
      `File: ____________________`
- [ ] **9d. A copy of the service's terms of use as they stood on the generation date** — saved
      as PDF from the live page, or from the Internet Archive if the current page has moved on.
      `File: ____________________`
- [ ] **9e. None of the above exists.** → go to *If the answer is no*.

**10. Are the original delivered files still kept, and where?**

The repository holds only the converted `.ogg`. The WAV masters are outside git, and if they are
lost there is no way to re-encode at a different quality or re-cut a seamless loop.

- Anny's copy: `________________________________________________`
- Khwan's copy is at `~/Music/LittleDays/masters/` — still present? `YES / NO`
- Checksums of both masters are recorded in `game/content/audio/manifest.json`
  (`masterSha256`), so a recovered file can be proven to be the same one.

**11. Signed, by the person who generated the tracks.** A plain sentence is enough, and it is
what makes the rest of this sheet evidence rather than notes:

> I generated both tracks myself on the account and plan named above, they contain no material
> belonging to anyone else, and I grant Little Days the right to use them commercially in the
> game and its marketing.

- Name: `____________________` Date: `____________________`

---

## What to do with the answers — exactly

**1. Commit this filled-in sheet.** It is the record of who said what, and when.

**2. Put the evidence files here** (create the directories):

```
docs/licences/music/littleDaysTheme/
docs/licences/music/hungryBunny/
```

Use plain, dated names so a stranger can tell what each file is:

```
generation-page-2026-XX-XX.png
plan-page-captured-2026-XX-XX.png
receipt-2026-XX-XX.pdf
terms-as-of-2026-XX-XX.pdf
```

**Redact before committing.** Crop out card numbers, home addresses and anything belonging to a
third party. A plan name and a date are what we need; a billing address is not.

*(Note for whoever tidies the docs: `docs/ASSET_LICENSE_REPORT.md` refers to the same idea as
`docs/licenses/` with an "s". Neither directory exists yet. Pick one spelling when you create
it and fix the other reference.)*

**3. Then, and only then, edit `game/content/audio/manifest.json`.** Two fields per track, and
nothing else. For each of the two rows, replace:

```json
      "licenseEvidence": "OWNER TO CONFIRM",
      "commercialUse": "pending",
```

with the real reference and the cleared state — filling in every `<...>` from the answers above:

```json
      "licenseEvidence": "<tool> <plan> plan, account <account>, generated <date>; evidence in docs/licences/music/<trackId>/",
      "commercialUse": "verified",
```

While you are in the row, set `createdAt` (question 4) — it is currently `""` — and correct
`source`, which today honestly reads *"Which tool or DAW produced it is NOT recorded: OWNER TO
CONFIRM."*

Three things the gate will not accept, so do not bother trying them: `"PENDING"`, `"TBD"`,
`"unknown"` and `""` all count as no evidence; `commercialUse` must be exactly `"verified"`,
lower case; and a typo anywhere in `commercialUse` is refused rather than guessed at.

**4. Re-run the checks.** In `/Users/hotkhwan/Projects/little-buddy`:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
    --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
    --script res://tests/smoke_audio_shipping.gd
```

**Expect some checks to start failing, and do not delete them.** Three of them assert that the
build is silent today, which is exactly the thing you have just changed:

- `game/tests/cases/test_audio_music_manifest.gd` → `_test_shipped_manifest_is_silent_today()`
- `game/tests/smoke_audio_silent_build.gd` — the whole file
- phase 1 of `game/tests/smoke_audio_shipping.gd`

They are the record that the silent path works, and the silent path still has to work for the
next unverified delivery. Point them at a fixture manifest with a pending row instead of at the
shipped one; do not remove them.

**5. Delete the override.** Once both rows say `"verified"`,
`game/scripts/audio/music_licence_override.gd` is dead code. Deleting it removes the only
mechanism in the project that can play unverified audio, which is worth doing on the day it
stops being needed.

---

## If the answer is no

If question 3 comes back as a free plan, or question 9 as "none of the above", the honest
options are these. None of them involves editing the manifest.

1. **Re-generate both tracks on a paid plan, and capture the evidence in the same session** —
   screenshot the plan page and the generation page before closing the tab. Anny has the
   prompts in `docs/MUSIC_BRIEFS_FOR_ANNY.md`; a re-generation is minutes of work and it is the
   only option that ends with rights nobody has to argue about.
2. **Replace the music** — a CC0 or explicitly commercial-licensed track, or one composed
   outright. The manifest row and the file swap; no code changes.
3. **Ship silent.** This is a real option, not a failure state: the game is complete without
   music, which is verified rather than assumed — the missions, the room transitions, the sound
   effects and the spoken English all work with the music switched off.

---

## ⚠️ One decision this sheet cannot make for you

**The `.ogg` files are inside the distributed binaries right now, even though they never play.**
Verified 2026-09-19: both tracks are present in `build/ios/LittleBuddy.pck` and in
`build/android/LittleDays-debug.apk` (about 2.37 MiB of audio). That is correct engineering —
they are game assets, and the licence gate is what keeps them quiet — but *distributing a copy
of a work* and *performing it* are not the same act, and the first one may raise a rights
question of its own even though no child ever hears a note.

Two ways to go, and it is the owner's call, not engineering's:

- **Accept it** for a closed Founder Preview to a handful of invited families, and resolve this
  sheet before any public release.
- **Exclude them from the build** — an `audio/music/*` entry in `exclude_filter` in
  `game/export_presets.cfg` keeps them out of the package. The game behaves identically: a
  missing file is a state the audio system is built to survive, and it already refuses these
  tracks on licence grounds before it ever looks at the disk. Ask engineering to make that
  change and re-verify the export rather than editing the preset by hand — the exclusion has to
  catch the imported resource as well as the source file.

Engineering has deliberately not chosen. Ask whoever advises you on rights.
