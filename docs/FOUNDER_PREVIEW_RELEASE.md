# Little Days — Founder Preview v0.2

**Care, Play & Grow** · featuring Aliz and Bunny
Build date 2026-09-19 · branch `feature/overnight-production-candidate` · commit `c167fd6`

> **Closed Founder Preview. Not a store release.** Nothing here has been
> submitted to Apple or Google, no subscription can be charged, and no public
> distribution has happened or may happen without Khwan's explicit approval.

---

## 1. Release gates

| Gate | Result |
|---|---|
| Full test suite | **113 / 113**, 0 failures |
| ContentValidator | clean (runs inside the suite) |
| Clean Godot project load | no parse errors |
| Mission 01 walkthrough, real game | **PASS**, exit 0 |
| Mission 02 walkthrough, real game | **PASS**, exit 0 |
| Save / load / resume | asserted in both smoke runs |
| No duplicate rewards | `mission_completed` fires exactly once; award **signals** counted, not totals |
| Touch fallback | `test_speech_never_required` drives every task to completion with no speech |
| Bunny need transitions | hunger 55 → 0, happiness 70 → 78, on the real `ChildStats` |
| Animation validation | real skeletal clips on the 24-bone rig — see §4 for what that does and does not mean |
| Visual screenshot review | 30+ renders from the real scene, each viewed before being kept |
| iOS export | **OK** |
| arm64 Xcode build | **BUILD SUCCEEDED** |
| Android debug APK | ❌ **not produced** — no SDK on this machine (§7) |

No test was softened. One test was **broadened** — `test_speech_privacy_guard`,
explained in §3.

---

## 2. What a family can actually play

Launch → title screen reads **Start** or **Continue** depending on whether
progress exists → house → two complete missions:

**Mission 01 — "I'm Hungry!"** 7 beats. Bunny is hungry → go to him → kitchen →
find the bottle → make the milk (hold-then-shake) → carry it back → feed him
(hold at the mouth) → optional cuddle.

**Mission 02 — "Snack Time"** 8 beats. Open the fridge → take the banana → put
it on the counter → take the spoon → mash it → carry it → feed Bunny → optional
tidy up.

Both end with stars, a saved profile, and a Bunny who is measurably less hungry
and measurably happier. Parent Corner has **Replay Mission 01** behind the
parental gate, which clears one level and cannot touch the child's star total.

---

## 3. The three bugs worth knowing about

**Speech silently faked itself on every non-iOS device.** Backend selection
tested `OS.has_feature("ios")`, then fell through to the mock — which reports
itself available and emits a canned `"milk"`. On Android the Speak button would
appear on a build with no speech support and accept `"milk"` whether or not the
child made a sound. Every speaking task would pass without speech. For a product
whose purpose is a child practising English aloud, that is the worst available
failure: it looks like success. Fixed; guard now covers all mobile platforms.

The guard test that caught the fix was **broadened, not relaxed**: its function
is named `_test_mock_is_never_used_on_a_device` and its docstring says "on a
device", but its assertion looked for the literal iOS string. That gap between
stated intent and checked condition is exactly the shape of the bug.

**Bunny was the wrong model, not a stiff character.** The bedroom was rendering
the seated, *unrigged* 398,404-triangle export — no skeleton, no clips, unable
to move — from frame one of the game. Fixed, and the runtime lost 398k triangles
and three 2048² textures as a side effect.

**The screenshot harness had been lying.** Its `house` job called methods
`HouseWorld` does not export, so every per-room screenshot since it was written
photographed the *bedroom* and filed it as evidence for whichever room was
requested. Fixed, and it now reports a miss instead of silently substituting.

---

## 4. Known bugs and honest limitations

### Blocking nothing, but visible to a playtester
| # | Issue | Owner |
|---|---|---|
| 1 | **Aliz's face and hair.** Permanent open-mouth grin (modelled geometry) and real gaps in the hair. Reference and tooling ready; blocked on the Meshy key (§6). | Art |
| 2 | **HUD text overlaps the character** during close-ups — the status/task/hint stack is ~35% of screen height and sits over Bunny's head. Cannot be fixed from the camera; needs `house_hud.gd`. | Not done |
| 3 | **No audio at all.** System complete and silent-safe; awaiting Anny's tracks. | §5 |
| 4 | Choice-row objects float ~0.9 m in mid-air during `choose` beats. | Not done |
| 5 | Contact shadow reads as a grey smudge at close-up distance; wants a warm ink tint. | Not done |
| 6 | Bathroom towel and the bedroom plaque overlap in screen space. | Not done |
| 7 | `bedtime` still cuts to an unrigged sleeping export — correct today (no `sleep` clip exists) but still a statue while on screen. | Not done |
| 8 | Bunny's fuss is subtle in a still frame (±3.5° hip rock); reads better in motion. | By design, tunable |
| 9 | Joystick clears the Speak button by **0.6 px** on a 6:5 foldable, and may overlap below ~920 px viewport width (Android multi-window). | Android-only |

### What "animation validation" honestly means
Bunny's five clips (`idle`, `fuss`, `eat`, `drink`, `celebrate`) are **real
skeletal animation** — bone tracks on the real 24-bone rig, deforming through
the real skin weights. They are **not** DCC-authored: the keyframes are written
in GDScript and look like a programmer's keyframes. The attention-turn **is**
procedural and is labelled as such in the code. There is **no blink and there
cannot be one** — the rig has no eyelid bones; the face is painted into the
texture.

### Not validated on any physical device
Every number and picture in this document is a macOS render. No iPad, no iPhone,
no Android device. The 3-minute acceptance walk has not been run on hardware.

---

## 5. Music readiness

**Status: system ready, zero tracks.** No audio file was created, downloaded or
synthesised — deliberately.

- `docs/MUSIC_BRIEFS_FOR_ANNY.md` — two paste-into-Suno briefs (`littleDaysTheme`,
  `hungryBunny`) with export settings, file naming and the licence evidence to save.
- `docs/AUDIO_MANIFEST.md` — field reference and drop-in procedure.
- The licence gate **fails closed**: only the exact string `"verified"` with real
  evidence will play. `"pending"`, `"Verified"`, `true`, `1` are all refused.
- Music is hard-capped at −6 dB so it can never bury the English.
- Silent-safety is a *tested property*: with zero files every state succeeds, no
  engine error, no broken resource path.

⚠️ Suno commercial rights depend on the subscription tier **at the time of
generation**. Save the receipt and the generation date with every track.

---

## 6. Credit spend report

| | |
|---|---|
| Authorised this sprint | **100 credits** |
| **Spent** | **0** |
| Reason | `MESHY_API_KEY` is not present in this environment. No request was issued. |

Prepared at zero cost so the spend is one command:
- `docs/reference/aliz_reference_v1.png` — clean standalone reference, grin
  painted out, torn fringe closed.
- `docs/reference/aliz_reference_apose.png` — arms swung 38° out. This exists
  because **image-to-3D copies the pose in the picture**; no prompt spreads the
  arms of an arms-down reference, and arms-down is what made the auto-rigger
  guess wrong the first time.
- `tools/meshy_aliz_apose.sh` — balance before/after, typed `YES` before any paid
  call, no retry on failure, refuses to overwrite, refuses the all-zeros sentinel.

To unblock: `export MESHY_API_KEY=...` then `tools/meshy_aliz_apose.sh preview`.

The **replacement gate stands**: old Aliz stays in production until a new model
passes front/side/back, rigging, skinning, walk/run, the RigProfile contract,
the mobile budget, iOS packaging, and an old-versus-new comparison at the real
gameplay camera.

---

## 7. Android

**No APK was produced and none is claimed.** Missing: JDK 17, the Android SDK,
adb, build-tools, platform-36, a debug keystore, launcher icons, and a device.
Godot's Android **export templates are already downloaded** — the slowest item
is done. `docs/ANDROID_READINESS.md` has the exact preset block (every option key
read out of the 4.7.2 binary rather than remembered), a permissions audit, the
speech audit, and nine ordered install commands.

Recommendation: **ship Android touch-only.** Android's `SpeechRecognizer` is
whatever the device provides and is historically cloud-backed — a Families-policy
risk. Text-to-speech already works via Godot's built-in `DisplayServer`.

---

## 8. Naming

Title **"Little Days"**, chosen by the owner after research (`docs/NAMING_AND_TRADEMARK.md`).
Known and accepted: two live App Store apps share the name in the baby/parenting
space, and a French class-41 registration exists. The risk is discoverability,
not legality — clear at USPTO, EUIPO and Thailand.

**Frozen and verified unchanged:** bundle identifier `com.pointit.littlebuddy`,
`user://profile.json`, `profileVersion` and all save keys, every `missionId`,
`taskId`, `levelId` and `objectId`, and the repo name. Only display strings moved.

Research note worth acting on later: **"Aliz" is clean everywhere checked and is
the strongest naming asset this project has.** "Bunny" alone is not shippable as
a title — Playboy holds a live EUIPO mark across all 45 classes.

---

## 9. Family Club — no billing exists

Provider-neutral entitlement interface only. No payment SDK, no product id, no
receipt, no buy button, **no `OS.shell_open()` anywhere in the project**. The
local provider grants Free Starter and nothing else, and a hand-edited profile
claiming `familyClub` grants nothing. Pricing displayed to a grown-up behind the
gate as PROPOSED: Free Starter; USD 2.99/month; THB 99/month. No annual price was
invented. Nothing in gameplay calls the entitlement service — the shipped game is
the free game, and no child-facing locked teaser exists.

---

## 10. Still to do, in priority order

1. **Play it on the iPad.** Nothing here is device-validated.
2. **Aliz replacement** — unblock the Meshy key; everything else is ready.
3. **HUD stack over the character** (§4 #2) — the largest remaining gap between
   "it works" and "it reads".
4. **Anny's two tracks**, with licence evidence.
5. Android SDK install → first APK.

## 11. Monday checklist

- [ ] `docs/CHILD_PLAYTEST_CHECKLIST.md` run with Aliz, adult silent
- [ ] Note the timestamp she loses interest
- [ ] Answer the only question that matters: **does she want to play again?**
- [ ] 30-second capture — *not yet attempted; no device*
- [ ] Khwan's explicit approval before anything leaves the family

*Produced by the engineering lead. Every claim above is either a command output
in this repository or is marked as not verified.*
