# Overnight Production Candidate — Report

**Date:** 2026-09-18
**Branch:** `feature/overnight-production-candidate`
**Final commit:** `b5bbca7`
**Rollback point:** tag `phase2b-verified-baseline` (the verified state this run started from)

**Bottom line:** *A Day With Little Buddy* is playable end to end and no longer looks like a
prototype. Every automated release gate passes. **Nothing has been run on a physical device**, so
this is a production *candidate*, not a verified release.

---

## 1. Automated release gates

| # | Gate | Result |
|---|---|---|
| 1 | Godot project loads | **0 errors, 0 warnings** |
| 2 | Full test suite | **PASS — 84 cases, 0 failures** |
| 3 | ContentValidator | **0 problems**, 0 content load warnings |
| 4 | Missing/broken resources | **0** |
| 5 | Critical TODO / FIXME in shipped code | **0** |
| 6 | Accidental network dependency | **0 files** reference `HTTPRequest`/`HTTPClient` |
| 7 | Asset manifest complete | yes — 3 new assets tonight, all original |
| 8 | iOS export (`tools/export_ios.sh`) | **succeeds** |
| 9 | arm64 Xcode build | **BUILD SUCCEEDED**, `architecture: arm64` |
| 10 | `Speech.framework` linked | yes |
| 11 | `AVFoundation.framework` linked | yes |
| 12 | Native plugin entry symbol | **present in the built binary** (`nm` → 5 hits), not merely referenced |
| 13 | Universal iPhone + iPad | `targeted_device_family=2` |
| 14 | Landscape orientations | `handheld/orientation=4` (sensor landscape) |
| 15 | Privacy strings | Microphone + Speech only; Camera/PhotoLibrary correctly stripped |
| 16 | Signing settings | `app_store_team_id="JZDAUN45CF"`, min iOS 15.0 — unchanged |

**No tag was created.** The brief says to tag only if all gates pass, and not to use a release tag
while device-critical items are unverified. All *automated* gates pass, but nothing has run on
hardware — speech, touch, frame rate and safe-area insets are all unverified. Tagging is a
one-line decision for the owner once the device checklist in §9 is worked.

## 2. What was built

12 commits. 56 → **84** test cases.

| Phase | Delivered |
|---|---|
| 2C | HouseWorld wired into the game; Story/Free Play routing; save v4; semantic target validation; camera activity focus |
| 2D | The full "A Day With Little Buddy" level loop |
| 2E | All 17 semantic character actions; one-shot vs hold; readable toddler |
| 3A | `docs/ART_BIBLE.md` **locked**, its 12 open decisions resolved |
| 3B/3C | Four rooms out of greybox; lighting, materials, bevels, scene dressing |
| 3D | Child UX / UI polish |
| 3E | TTS that actually speaks; 2 new SFX; speech privacy guards |
| 3F | Vocabulary review — built **and wired** |
| 4A | Onboarding |
| 4B | Free Play |
| 4C/4D | Child-proofing and mutation testing |
| 4E/4F | Build + visual acceptance |

## 3. The vertical slice as implemented

Five chained Chapter 3 levels, ~29 minutes, in a four-room house:

| Level | Beats | Rooms |
|---|---|---|
| `goodMorning` | wake · walk to bathroom · brush teeth · dry face | bedroom → bathroom |
| `gettingDressed` | walk back · shirt, pants, shoes | bathroom → bedroom |
| `breakfast` | walk to kitchen · sit · choose food · eat + drink | bedroom → kitchen |
| `playTime` | walk to living room · teddy · ball · blocks | kitchen → livingRoom |
| `tidyAndBed` | tidy toys · walk home · pyjamas · sleep | livingRoom → kitchen → bedroom |

Content: **70 tasks, 58 words, 11 missions**. Every level is completable and reaches **3/3 by
touch alone** — proven of the content *and* of the running engine.

Interactions: tap floor → walk · tap target → walk, face, act · drag object to Little Buddy · drag
object to target · tap fallback everywhere · 17 semantic actions.

## 4. Save schema

**v4.** `currentRoomId` / `currentSpawnId` promoted to top level; `vocabularyProgress` preserved
additively. Migrations **v1→v4, v2→v4, v3→v4** are built as a chain rather than three jumps, so
there is no fourth code path to drift, and idempotency is asserted over three passes because
two-pass stability can be an accident.

The owner's real device profile (`device_profile_v1.json`) migrates with **64 stars, 33 completed
activities and 11 stickers exactly** preserved.

`settings.worldState` is deliberately retained for one release as a read-compatibility mirror;
`ProfileStore.DROP_LEGACY_WORLD_STATE` finishes the job and is pre-tested.

## 5. Art

Every object in the four rooms is **procedural and original**: no third-party files, no repo
bytes, no licence surface, nothing downloaded or purchased.

**Meshy was not accessible — no credentials exist in this environment.** Per the brief this did
not block the night, and **no generated asset is claimed**. Exact generation specs belong in
`ASSET_MANIFEST.md` when that path opens.

12 objects, one per taught word, each shaped so no two nouns share a silhouette. 6 draw calls per
room against a ceiling of 220; worst room 7,872 triangles against an 18,000 target.

Three new assets tonight, all original: `place_soft.wav`, `room_change.wav`, `star_outline.svg`.
All recorded in `docs/ASSET_MANIFEST.md`. **Every third-party asset in the project remains CC0.**

## 6. Bugs found and fixed — the ones worth knowing

Several were invisible to a green test suite, which is the point.

1. **The test suite was overwriting the real save file.** `run_tests.gd` documented "cases must
   not depend on autoloads — `--script` does not load them". False on Godot 4.7: `/root` really
   holds SaveService. Its `_ready()` does not fire, so it starts with an empty profile, and any
   case completing a level wrote that empty profile over `user://profile.json`. **On a device that
   erases a child's stars.** Autoloads are now detached for the run; a probe case calling
   `add_stars(-999)` can no longer reach the profile.
2. **327 typed test helpers were swallowing their own aborts.** A typed `-> Array` returns an
   *empty* Array when it aborts, so `append_array()` succeeded and the case reported `[PASS]` with
   its assertions never having run. A live instance existed: `world_state.gd` called `String(7)`,
   aborting the helper that guards a child from being stranded in an unknown room.
3. **Chapter 3 looped forever on a bonus level.** `sayItChallenge` is tagged `ch3` but is not in
   the chain, so a profile parked there opened the chapter on vocabulary cards instead of waking
   up — and a bonus level has no successor, so Next handed the same level back. The day could
   never start. Every test was green.
4. **The "slow speech" setting never slowed anything.** Pitch and rate were swapped in the
   platform call, so the parent-facing setting lowered the *pitch* instead.
5. **Every queued prompt truncated the one before it** (`interrupt` hardcoded true). Every
   Chapter 3 task has two lines, so the first was cut off on all of them.
6. **Mission intro/outro were never spoken** — emitted to a Label only, i.e. invisible to a
   pre-reader, which is every player.
7. **Rooms rendered flat and dusty** because every face was wound backwards: Godot flips the
   shading normal on a back face, so a backwards quad is not invisible, it is *lit from behind*.
8. **Palette tokens rendered pale** — a material's `albedo_color` is sRGB-converted by the engine;
   a vertex colour is not.
9. **`ProfileStore` silently dropped `vocabularyProgress`** on every save.
10. **Summary buttons were unlatched** — two fast taps restarted the level just started.
11. **Tapping the bed laid the child face-up on the floor** in front of it.

~130 mutations were applied and reverted across the run. Several **survived** and that changed the
*code*, not the test — notably two places with overlapping fallbacks each silently covering for
the other, which is defence in depth that no test can distinguish from defence in nothing.

## 7. Known limitations (honest)

- **Nothing has run on a physical device.** No speech, touch, frame-rate or safe-area validation.
- **Drag is not implemented in Free Play**, so onboarding's drag hint is a demonstration over
  empty floor — the weakest of the five onboarding beats.
- **Onboarding does not run at app launch** for a brand-new profile: `currentChapter: "ch1"` routes
  Story to the Baby Room, and tap-to-walk cannot be taught in a scene with no walking. It runs on
  first entry to the house (Free Play, or Story reaching Chapter 3).
- **The foreground floor is bare** in every room — furniture sits against the back wall.
- **`book` is the weakest object** for recognition; `bath` and `towel` are next.
- **Thin geometry aliases** (glazing bar, towel rail) because `msaa_3d = 0`.
- **Six house-only Thai hints are unreviewed** by a Thai speaker (wardrobe, sink, fridge, counter,
  book, toy).
- **No camera pull-in on a beat** — `focus_activity()` exists and is wired but unused, so objects
  read smaller than they could. The obvious next visual win.
- **No journey/level-select map**, no parent access from the title screen.
- Baby Room Sticker/Next buttons are 200 px, below the art bible's 240 floor.

## 8. Speech status

**Unchanged and frozen.** The native plugin, `.mm` bridge and export settings were not touched.

Proven here (headless): every task and mission completes **by touch alone** with no speech service
at all and again with permission denied; no task sets `speechRequired`; no networking primitive
exists anywhere in the speech layer; the native source still forces
`requiresOnDeviceRecognition = YES`; iOS never substitutes the mock backend; diagnostics carry no
transcript.

**Not proven, and not claimed:** any runtime microphone behaviour. The earlier device validation in
`docs/SPEECH_DEVICE_VALIDATION.md` stands, but **tonight's TTS rate/pitch/volume changes are
unverified on hardware**.

## 9. Device test checklist

**Speech and audio**
1. TTS volume was raised 50 → 85. Confirm a prompt is clearly audible over SFX at ~50% device
   volume and not startling at 100%, ~30 cm from the child.
2. Confirm rate 0.85 sounds deliberate rather than sluggish, and Settings → slow (0.70) is natural.
   **This is the first build in which the slow setting changes speed at all.**
3. Start `goodMorning`: "Good morning!" then "Wake up, Buddy!" must both be heard **in full, in
   order**. This never worked before.
4. Confirm the second line starts in ~0.3 s, not after a ~2 s gap (a long gap means iOS is not
   delivering utterance-ended callbacks and the safety timer is carrying the queue).
5. Mission intro/outro spoken exactly once each, not doubled with the first task prompt.
6. Speak a prompt, then press Speak: confirm audio stays on speaker and recognition still returns.
7. Denied-microphone path; Siri/incoming call mid-listen.

**Gameplay and UX**
8. Play all five levels start to finish. Confirm no stuck Walking/Interacting/Disabled state.
9. Complete a level **without ever speaking** — confirm 3/3 is reachable.
10. Skip everything with Next — confirm the level completes at 0 stars with a kind screen.
11. Rapid-tap and two-finger-tap targets; confirm no double award and no failure state.
12. Rotate the device both ways; check both notch sides; confirm nothing important sits under the
    safe area.
13. Background the app mid-level and return — confirm progress survived.
14. First-run onboarding: does a 4-year-old know what to do with nobody reading to them?
15. Frame rate in each room (nothing has been profiled on hardware).

**Commands on the MacBook**
```bash
git checkout feature/overnight-production-candidate

/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/run_tests.gd
# expect: PASS - 84 case(s), 0 failure(s)

# a fresh clone has NO speech plugin binaries (gitignored) and will ship without speech:
export PATH="$HOME/Library/Python/3.9/bin:$PATH"
cd ios/speech_plugin
git clone -b 4.5 --depth 1 https://github.com/godotengine/godot-cpp godot-cpp
./build_xcframeworks.sh && ./build_macos_framework.sh
cp -R bin/liblittle_buddy_speech.ios.*.xcframework ../../game/ios/speech_plugin/bin/
cp -R bin/liblittle_buddy_speech.macos.*.framework ../../game/ios/speech_plugin/bin/
rm -f ../../game/.godot/extension_list.cfg
cd ../..

./tools/export_ios.sh debug          # never raw --export-debug
open build/ios/LittleBuddy.xcodeproj # confirm team JZDAUN45CF resolves, then Run
```

## 10. The next product decision

**Play it with the child, then decide between two paths.**

- **Polish this slice** — camera pull-in on each beat (the single biggest remaining visual win,
  already wired), floor-level dressing, drag in Free Play, and the `book`/`bath` objects.
- **Expand the story** — Chapters 1 and 2 already have content and systems; Chapter 4+ is now
  mostly authoring, because every system the Bible describes is built and tested.

My recommendation is **polish, not expansion**. The Bible's own quality bar says a feature is done
when a child understands it, not when it is present — and the one thing this build has never had
is a child in front of it. Everything above is verified by tests and by my own eyes on rendered
frames; none of it is verified by a 4-year-old, and that is the only test that decides which of
the two paths is right.

The second decision, smaller and independent: **`min_ios_version` is still 15.0**, which keeps A9
hardware (iPhone 6s) in the support matrix. Raising it to 16.0 removes the weakest devices from
testing and costs essentially nothing in 2026 audience terms. Art and performance budgets hold
either way.
