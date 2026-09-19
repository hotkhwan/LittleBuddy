# Physical device QA — Little Days Founder Preview

**Status: BLOCKED — not passed. On both platforms.**
No step below has been run on hardware. Everything in the engineering reports is
a macOS render. This gate can only be closed by Khwan, on a real iPad and a real
Android phone.

Build: `feature/overnight-production-candidate` @ `90afbfa`
· iPad: Xcode project at `build/ios/LittleBuddy.xcodeproj`
· Android: `build/android/LittleDays-debug.apk` (34.8 MB, signed, package
`com.pointit.littlebuddy`, **zero declared permissions**)

**Installation steps for both platforms: `docs/INSTALL_GUIDE.md`.** Read the
"two rows that lie" section there before judging music or speech — on both
platforms one of them has a PASS that looks like a FAIL.

---

# Part A — iPad

## How to run it

1. Open `build/ios/LittleBuddy.xcodeproj` in Xcode.
2. Select your iPad, set a signing team, Run. (Developer Mode must be on:
   Settings → Privacy & Security → Developer Mode. Then trust the profile:
   Settings → General → VPN & Device Management.)
3. Hold the iPad in **landscape**. Volume **up**.
4. Before starting: Parent Corner (**Grown-ups**, top right) → hold the gate →
   **Replay Mission 01**. This resets the first mission only; it does not touch
   stars or settings.
5. Work down the table. Mark each row. **Three minutes, no coaching.**

Write the actual behaviour in Notes even when a step passes — "passed but slow"
is information.

---

## The 19 iPad steps

| # | Step | What PASS looks like | P/F | Notes |
|---|---|---|---|---|
| 1 | Launch the game | Opens landscape, no crash, no black frame, no sideways UI | ☐ | |
| 2 | Hear the **Little Days** theme | **Silence is a PASS — read the note below before marking this.** | ☐ | |
| 3a | Look at **Aliz** | On screen, recognisably a girl, right size, not inside the floor or furniture | ☐ | |
| 3b | Look at **Bunny** | On screen, clearly a *different* character from Aliz, right size, upright | ☐ | |
| 4 | Tap Start → walk Aliz to the kitchen | She walks (legs move, no sliding), goes through the door, no stall | ☐ | |
| 5 | Open the fridge / storage | The door visibly swings open; food is visible inside | ☐ | |
| 6 | Pick up the bottle | It leaves the fridge **and** appears in her hands. Not floating. | ☐ | |
| 7 | Prepare the milk by gesture | Hold the jug over the bottle, then shake. Bar fills. Liquid visibly changes. | ☐ | |
| 8 | Carry it back to Bunny | The bottle stays in her hands **through the door** into the bedroom | ☐ | |
| 9 | Feed Bunny | Bottle at his mouth; he reacts; progress is visible | ☐ | |
| 10 | Hear and see completion | Reward appears; Bunny looks happy | ☐ | |
| 11 | Verify the reward | Stars awarded **once**. Leave and re-enter — they must not increase again. | ☐ | |
| 12 | Start Snack Time | Mission 02 begins; fridge → banana → counter → spoon → mash → feed | ☐ | |
| 13 | HUD visibility, judged fresh | **Text never covers Bunny's face.** Every word readable at arm's length. Nothing clipped by the screen edge, the rounded corners or the home indicator. | ☐ | |
| 14 | Test speech on the iPad | Tap Speak, say "milk". Either it recognises, or it honestly says unavailable. | ☐ | |
| 15 | Verify touch fallback | Turn speech off in Parent Corner. Every task must still be completable. | ☐ | |
| 16 | Mute and volume | **Read the note below — there is no in-game control.** Use the hardware buttons and the Control Centre mute. Sound must follow them, at once, with nothing stuck on. | ☐ | |
| 17 | Save / resume — soft | Force-quit (swipe up from the app switcher) and relaunch. Stars, settings and mission progress all come back. | ☐ | |
| 18 | Save / resume — cold | Reboot the iPad, relaunch. Same again. Nothing resets to a first run. | ☐ | |

### Step 2 — silence is the expected result

**A normal build has no music, deliberately.** Both of Anny's tracks are in the
build but their rights are not yet recorded (`commercialUse: "pending"`,
`licenseEvidence: "OWNER TO CONFIRM"`), and the licence gate fails closed. So:

* **PASS** — no music, while sound effects and spoken prompts still work.
* **FAIL** — music plays anyway. That means the gate leaked; report it.
* **FAIL** — *no* sound of any kind, including effects and prompts.

To hear the tracks on purpose, arm the preview override — see "Silence is a
PASS" in `docs/INSTALL_GUIDE.md`. Nothing committed to the repo turns it on.

### Step 16 — there is no mute or volume control in the game

Parent Corner has exactly three settings — Thai hints, Voice on/off, and speech
speed — and no audio controls. `AudioDirector` has working mute and per-bus
volume, but nothing in the UI reaches them, so there is **nothing to tap**. Test
the platform controls instead:

* Hardware volume buttons change the level while the game is running.
* Control Centre / the silent switch mutes it, and unmuting restores it.
* Nothing is left stuck at full volume or stuck silent after switching away to
  another app and back.

"No in-game volume slider" is a **known gap, not a FAIL** — note whether you
want one before the preview goes out.

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
- There is **no music** in a normal build, on both platforms, on purpose (step 2)
- On Android there is **no speech at all**, by design (step A9)
- An Android APK now exists, but has never been installed on a phone

---

## Sign-off — iPad — Khwan only

| | |
|---|---|
| Date | |
| Device + iOS version | |
| Steps passed | ___ / 19 |
| Crashes | |
| **Ship the Founder Preview?** | ☐ Yes ☐ No ☐ Fix first |

---

# Part B — Android

Second platform, same rule: **BLOCKED until run on a phone.** The APK exists and
is signed, and it has never been installed on a device. A green export is not a
green launch.

## How to run it

1. Install it. Full steps, including every way a phone can refuse a debug APK,
   are in `docs/INSTALL_GUIDE.md`. The short version — note `adb` is **not on
   `PATH`**:

   ```sh
   /Users/hotkhwan/Library/Android/sdk/platform-tools/adb install -r \
     /Users/hotkhwan/Projects/little-buddy/build/android/LittleDays-debug.apk
   ```

2. Enable **Developer options** (tap Build number 7 times) → **USB debugging**,
   and accept the "Allow USB debugging?" prompt on the phone.
3. Hold the phone in **landscape**. Volume **up**.
4. The phone must be **64-bit ARM** running **Android 7.0 or newer** — the APK is
   `arm64-v8a` only.
5. Parent Corner → **Replay Mission 01** before you start, same as on the iPad.

This is a **phone**, not a tablet. The game was laid out for a 4:3 iPad
(1366×1024) and a phone is far wider, so step A8 is the real one here.

## The 9 Android steps

| # | Step | What PASS looks like | P/F | Notes |
|---|---|---|---|---|
| A1 | Launch the game | Installs, opens in landscape, no crash, no black frame, no sideways UI, no permission prompt of any kind | ☐ | |
| A2 | Music | **Silence is a PASS — see step 2 above.** Effects and spoken prompts still audible. | ☐ | |
| A3 | Movement | Aliz walks where you tap; legs move, no sliding, no stalling in doorways | ☐ | |
| A4 | Mission 01 — bottle | Fridge → bottle → prepare → carry → feed Bunny → reward, end to end | ☐ | |
| A5 | Mission 02 — Snack Time | Fridge → banana → counter → spoon → mash → feed, end to end | ☐ | |
| A6 | Touch fallback | **Every** task completable by touch alone. Nothing anywhere waits on speech. | ☐ | |
| A7 | Save / resume | Force-quit and relaunch, then reboot the phone and relaunch. Stars, settings and progress survive both. | ☐ | |
| A8 | Screen layout | On a wide phone screen: nothing important off the edges, nothing under the camera cutout or gesture bar, all text readable | ☐ | |
| A9 | **No fake speech results** | The game says speech is **unavailable** and shows no Speak button | ☐ | |

### Step A9 — the one that looks like success

On Android the correct behaviour is that **speech does not work**. There is no
Android speech backend, and the APK declares **no `RECORD_AUDIO` permission** —
the microphone is unreachable at the OS level. So:

* **PASS** — the game reports speech unavailable, or simply never offers it, and
  the Speak button is absent. Nothing is blocked by this.
* **HARD FAIL** — the game accepts a word **you did not say**.

Test it by staying **completely silent**: tap whatever invites speech and make no
sound at all. If a task completes, that is the failure.

Why this row exists: `SpeechService` used to special-case iOS only, so Android
fell through to the development mock — which reports itself available and returns
a canned `"milk"` about 0.6 s after any tap. Every speaking task passed without a
child ever speaking. It is fixed (the check is now `OS.has_feature("mobile")`,
covering both platforms) and the fix is in this APK. It is on the sheet because
it is the one bug that is indistinguishable from the product working.

### Also stop and write it down if

- [ ] Android asks for **any** permission (this build declares none)
- [ ] The phone gets hot, or the frame rate visibly drops
- [ ] Anything is cut off by the notch, cutout or gesture bar
- [ ] The app closes instantly on launch — capture the log and send it:
      `/Users/hotkhwan/Library/Android/sdk/platform-tools/adb logcat -d godot:V '*:S' > /tmp/littledays.log`

---

## Sign-off — Android — Khwan only

| | |
|---|---|
| Date | |
| Phone + Android version | |
| Steps passed | ___ / 9 |
| Crashes | |
| **Is the Android build worth continuing?** | ☐ Yes ☐ No ☐ Fix first |

---

I cannot mark any row of this document PASS, and neither can any other agent —
only a run on the hardware closes one. Until both sign-off blocks above are
filled in by Khwan, physical-device QA remains an **open release gate** and the
Founder Preview is **not device-validated on either platform**.
