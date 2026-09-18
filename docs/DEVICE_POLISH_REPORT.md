# Device-Feedback Polish — Report

**Branch:** `feature/overnight-production-candidate` · **Commit:** `bc36234`
**Driven by:** the owner playing the build on a physical iPhone.

All automated gates green: **89/89 tests** (three consecutive single-threaded runs) ·
ContentValidator **0** · project loads with **0** errors · iOS export ✅ · **arm64 BUILD
SUCCEEDED** ✅ · speech entry symbol present in the built binary · Universal, landscape,
privacy strings, Team ID and min-iOS all unchanged.

---

## 1. The two device complaints

### "การบังคับตัวละครยังไม่สมูท — ต้องกดที่เตียง ตู้ ประตู จึงจะเดิน"

**Diagnosed before changing anything, and the obvious conclusion was wrong.** Tap routing was
never broken: 16 of 16 synthetic floor taps across the live play area already classified as FLOOR
and were accepted. What was missing was **acknowledgement** — `floor_tapped` was emitted and
nothing drew anything. A child tapped bare floor and the game said nothing until the character
happened to start moving. Tapping furniture only *felt* different because furniture is a big thing
you aimed at.

Fixed by acknowledging the tap **on the frame of the tap**, before the walk even starts:

| | before | after |
|---|---|---|
| Floor tap feedback | none | mint ripple at the finger, full opacity immediately, + a hold disc on the destination until arrival |
| Walk speed | 0.85 m/s | **1.05 m/s** — 4 m room: 4.71 s → 3.81 s |
| Turn speed | 4.5 rad/s | **7.0 rad/s** — 90° change of mind in 0.22 s |
| Refused walk | silent | acknowledged, then fades — never failure language |

A fade-*in* was rejected: it is the exact delay the ripple exists to remove. 1.05 m/s rather than
the 1.25 first proposed, because a 0.22 m leg puts 1.25 m/s at Froude 0.72 — decisively a *run*,
which no walk cycle can be authored around. The walk clip was re-authored to a 0.311 m stride so
the feet cover exactly the ground the body does.

Drawn in `NavigationController`, the single place every floor tap passes through, so Story, Free
Play and onboarding all get it with no per-mode work.

### "item ที่ให้เราเลือก ควรไปวางตามตำแหน่งในห้อง"

You were right, and the code said so itself — `house_stage.gd`'s own comment read: *"The row goes
where the CHILD will be, never where the furniture is."*

Objects are now placed by **derivation, not a hard-coded list**: the task's focus target resolved
to the **live** `ActivityTarget`, else the object's content category, else the old row as a
fallback. No furniture coordinate is copied anywhere, which is why placement kept working while
furniture was being re-modelled underneath it. Layout is a 2×2 cluster rather than a 1×4 line,
because four objects at scale is a **3.1 m line in a 4 m room**.

Toothbrush and cup at the sink · food along the counter and fridge · clothes at the wardrobe ·
teddy, ball and blocks around the toy box.

> **Occlusion turned out to be a placement constraint, and only rendering found it.** The first
> version put the apple directly behind the kitchen table — completely invisible. "Find the apple"
> with the apple invisible is the worst kind of dead end, because the game looks fine.

## 2. The four mandatory fixes

| # | Fix | Status |
|---|---|---|
| 1 | First-launch onboarding runs automatically for a brand-new profile | **Done.** Chapter routing was deliberately *not* touched — the problem was never what a chapter means, it was that nothing ran before it. `main.gd` now intercepts first launch specifically, shows the title for 1.4 s, then opens the house in Free Play with no button pressed. Chapter 2 and the no-navigation guard are untouched. |
| 2 | Free Play drag wherever onboarding teaches drag | **Done.** Three pickups per room from real content, both flavours (drag-to-Buddy and drag-to-furniture), reusing the existing stage and drop zones rather than a parallel spawner. The onboarding drag hint now points at a real object. A drop plays `place_soft` — an SFX that had existed since Phase 2 and was wired to nothing. |
| 3 | Camera focus on key activities | **Done.** Toothbrush, dressing, breakfast, teddy/play, bedtime — **1.27×–1.51×** larger on screen. Never on `travel`, where the child needs to see where they are going. Little Buddy is in the framed set *unconditionally*, so walking away widens the shot instead of losing him. |
| 4 | Weakest objects: book, bath/bathroom, foreground floor | **Done.** See below. |

**`book`** — rebuilt as an **open** book. Why the closed one could never work, written down so
nobody pays for it a fourth time: a closed book is a rectangular slab, the camera looks *down*, and
a slab seen from above is a tray. Everything that makes a closed book a book — spine, page block,
cover boards — lives on the **edges**, which is the one part that view cannot see.

**`bath`** — the cream box with a flat blue lid is gone: ball feet (the only object in the house
with daylight under it, which is what stops a thing reading as built-in), height over length, a
rounded plan, and water recessed 9.5 cm so the inner wall is the depth cue. **`towel`** is now two
towels folded over a rail — two of a thing is what tells a child it is not a panel.

**Foreground floor** — dressing props and enlarged rugs, placed along the side walls rather than
the corners, because the navmesh bake probes corner-to-corner and a plant on a probe endpoint
broke all four rooms. None of them is a word the game teaches, so nothing competes for a noun.

## 3. Also fixed along the way

- **`sayGoodMorning` ran sixth — after the walk to the bathroom — while targeting `bedroom.bed`.**
  Its objects staged in a room the child had left. Reordered to greet on waking, which is also the
  better story.
- **The speak button was soft pink.** The locked art bible assigns **mint** to it in two separate
  places, and mint is this game's "go" colour — exactly what inviting a child to speak is. A legal
  palette token but the wrong one, so no existing scan objected; colour-*by-role* is a rule only a
  test can hold, and there is now a guard.
- **A correction to something I reported earlier.** The user-data directory is
  `app_userdata/Little Buddy/` (with a space, from `config/name`), not `LittleBuddy/`. My earlier
  verification that the test suite no longer overwrites a real save was therefore reading the wrong
  file and proved nothing. Re-run properly: a real profile of **73 stars / 16 activities / 6
  completed levels is byte-identical after a full 89-case run.** The conclusion held, but only now
  is it actually evidenced.

## 4. Before / after

`docs/shots/` holds rendered pairs at landscape-iPhone aspect. The bathroom is the clearest: a
cream box with a flat blue top and a thin pink smudge on the wall, on bare floorboards → an oval
tub on feet with visible water, two towels on a rail, and a plant and step stool carrying the
foreground.

## 5. Remaining device-only risks

These cannot be settled on a Mac. Roughly in order of how much they would cost if wrong.

| # | Risk | Why it is open | What to look for |
|---|---|---|---|
| 1 | **Grab targets are 74–89 px** | Direct cost of putting objects where you asked. Apple's 44 pt minimum ≈ 88 px in this frame; the old row-at-the-feet was 98 px. Depth compensation recovers most but not all of it — full compensation would need an apple the size of a fridge shelf. | Can a 4-year-old's finger reliably hit the toothbrush at the sink, and the milk by the fridge? |
| 2 | **Drag on glass** | `global_position` returns the origin in the headless runner, so no test can honestly exercise the real drop-zone path. The pad is 0.34 m and, for drag-to-Buddy, it **rides on a moving character**. | Ball → toy box is the longest at 2.69 m. Does a real finger land it? |
| 3 | **1.05 m/s reads calm-but-responsive** | Chosen from gait physics, not from a child. | Does he feel slow, or hurried? |
| 4 | **Tap ripple visible in real light** | Mint at alpha 0.50 on a warm wood floor, at real screen brightness and possibly in sunlight. | Is the ripple obvious enough to feel like a response? |
| 5 | **Camera ease at 0.55 s** and 60 fps with a per-frame recompose | Never profiled on hardware. Gated to re-aim only past 8 cm of drift. | Any hitch when a beat starts? Does the move read as calm or as drifting? |
| 6 | **First-launch title beat is 1.4 s** | On a cold launch the scene load may eat most of it. | Does the title sit, or flash? |
| 7 | **TTS volume 50 → 85, rate 0.85** | Changed tonight, never heard on hardware. This is the first build in which the parent's "slow" setting changes *speed* at all — previously it only deepened the pitch. | Clearly audible over SFX at ~50% volume, not startling at 100%, 30 cm from a child. |
| 8 | **Queued prompts** | The `interrupt` bug meant the first of two lines was always truncated. Now fixed, never heard. | `goodMorning`: "Good morning!" then "Wake up, Buddy!" — both in full, in order, second starting in ~0.3 s not ~2 s. |
| 9 | **Real safe-area insets** | Desktop is excluded by design, so only chrome insets applied in every render. | Rotate both ways; check both notch sides. Failure mode is benign — framed slightly wide, never cropped. |
| 10 | **Microphone runtime** | Frozen and untouched, but tonight's TTS changes are not re-validated against it. | Speak a prompt, then press Speak: audio stays on speaker and recognition still returns. |

**Speech recognition itself is unchanged.** No native plugin, `.mm`, or export setting was
touched. Touch-only completion of every task and every mission is proven headlessly, with no
speech service and again with permission denied.

## 6. Known weak points, honestly

- The floor plant's foliage is seven spheres and reads a little like balloons — the weakest new
  shape. Visible stems would fix it.
- The bedroom basket is close to a waste bin; the two hoop handles only just pull it back.
- Objects sit **beside** furniture, never **on** it (food is by the table, not on it), because
  surface heights are not exposed and anything on a surface would float the moment furniture moved.
- Decorative props are not navmesh obstacles, so an object can visually brush a plant pot.
- `shoes` is still the weakest object in the game — untouched, and still the open item from the
  art bible.
- Floor dressing is tight to the side walls rather than in the corners where composition wants it.
  That is forced by the bake's corner probes, not by taste.

## 7. Recommendation

Install and play it with the child. Every item in §5 is a question only they can answer, and **#1
is the one I would watch first** — it is the direct cost of the placement change you asked for, and
if the targets are too small for a real finger the fix is to bring the clusters forward, which
trades away some of the "items are where they belong" you wanted. That trade is yours, not mine.
