# Physical device QA — Little Days Founder Preview

**Status: BLOCKED — not passed.**
No step below has been run on hardware. Everything in the engineering reports is
a macOS render. This gate can only be closed by Khwan, on a real iPad.

Build: `feature/overnight-production-candidate` · Xcode project at `build/ios/LittleBuddy.xcodeproj`

---

## How to run it

1. Open `build/ios/LittleBuddy.xcodeproj` in Xcode.
2. Select your iPad, set a signing team, Run.
3. Hold the iPad in **landscape**. Volume **up**.
4. Before starting: Parent Corner (**Grown-ups**, top right) → hold the gate →
   **Replay Mission 01**. This resets the first mission only; it does not touch
   stars or settings.
5. Work down the table. Mark each row. **Three minutes, no coaching.**

Write the actual behaviour in Notes even when a step passes — "passed but slow"
is information.

---

## The 15 steps

| # | Step | What PASS looks like | P/F | Notes |
|---|---|---|---|---|
| 1 | Launch the game | Opens landscape, no crash, no black frame, no sideways UI | ☐ | |
| 2 | Hear the **Little Days** theme | Music plays on the title screen, at a comfortable level | ☐ | |
| 3 | See Aliz and Bunny | Both visible on the title screen, clearly two different characters | ☐ | |
| 4 | Tap Start → walk Aliz to the kitchen | She walks (legs move, no sliding), goes through the door, no stall | ☐ | |
| 5 | Open the fridge / storage | The door visibly swings open; food is visible inside | ☐ | |
| 6 | Pick up the bottle | It leaves the fridge **and** appears in her hands. Not floating. | ☐ | |
| 7 | Prepare the milk by gesture | Hold the jug over the bottle, then shake. Bar fills. Liquid visibly changes. | ☐ | |
| 8 | Carry it back to Bunny | The bottle stays in her hands **through the door** into the bedroom | ☐ | |
| 9 | Feed Bunny | Bottle at his mouth; he reacts; progress is visible | ☐ | |
| 10 | Hear and see completion | Reward appears; Bunny looks happy | ☐ | |
| 11 | Verify the reward | Stars awarded **once**. Leave and re-enter — they must not increase again. | ☐ | |
| 12 | Start Snack Time | Mission 02 begins; fridge → banana → counter → spoon → mash → feed | ☐ | |
| 13 | Check HUD and camera | **Text never covers Bunny's face.** Nothing clipped at the screen edge. | ☐ | |
| 14 | Test speech on the iPad | Tap Speak, say "milk". Either it recognises, or it honestly says unavailable. | ☐ | |
| 15 | Verify touch fallback | Turn speech off in Parent Corner. Every task must still be completable. | ☐ | |

### Step 14 — read this before marking it

There are only two acceptable outcomes:

* **PASS** — it heard you, or it told you speech is unavailable and the Speak
  button is hidden.
* **FAIL** — the game accepted a word **you did not say**.

That second case is the one that matters. A bug of exactly this shape was found
and fixed this sprint: on non-iOS devices the game would accept a canned `"milk"`
whether or not the child spoke. If you ever see the game succeed while you stay
silent, mark FAIL and tell me — it is worse than speech simply not working,
because it looks like success.

---

## Stop immediately and write it down if

- [ ] The game **crashes**
- [ ] Aliz gets **stuck** with no way forward
- [ ] Anything is **unreadable** or off the edge of the screen
- [ ] The device gets **hot**, or the game becomes juddery
- [ ] A reward is granted **twice**
- [ ] Progress is **lost** between launches

---

## Already known — do not re-report

So your three minutes buy new information:

- Aliz's hair is rough and her mouth is permanently open (replacement blocked)
- Room signs, camera framing and HUD were changed this sprint — **judge them fresh**
- Bunny's motion is subtle
- There is no Android build

---

## Sign-off — Khwan only

| | |
|---|---|
| Date | |
| Device + iOS version | |
| Steps passed | ___ / 15 |
| Crashes | |
| **Ship the Founder Preview?** | ☐ Yes ☐ No ☐ Fix first |

I cannot mark this document PASS. Until it is signed here, physical-device QA
remains an **open release gate**, and the Founder Preview is not device-validated.
