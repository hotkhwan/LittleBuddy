# Little Days — owner playtest build, 2026-09-20

Branch `feature/overnight-production-candidate`. **Integrated commit `fa650bd`**,
pushed to `origin` (fast-forward, no force). Base at the start of the day:
`840fd45`. 26 commits, 220 files, from six workstream agents merged one at a
time by the lead, each merge re-gated.

> Every PASS below is a command that ran on this MacBook against the real
> scenes, or a screenshot that was opened and looked at. **Nothing here is a
> physical-device result.** The device rows are the owner's to fill in
> (`docs/IPAD_QUICK_CHECK.md`).

## 1. What changed today (owner feedback → result)

| Owner observation | Result | Evidence |
|---|---|---|
| Feeding close-up was a flat placeholder face | **PASS** — the real rigged Bunny in a portrait, hold target follows his mouth socket, drink arc on his face | `docs/shots/feed_portrait_{ipad,iphone}.png`, `_mid_`, `_done_` |
| Aliz hair holes, dark chin smudge, crown lines | **PASS** (local, 0 credits) — 10 open hair loops capped, mouth cavity peeled, normals calmed | `docs/shots/aliz_polish_*`, `docs/ALIZ_POLISH_PASS.md` |
| Aliz mouth too pursed | **PASS** — smile repainted 1.4x wider, warmer, gentle corners; fringe edge moved onto the mesh | `docs/shots/aliz_smile_*` (1:1 strips at menu and gameplay size) |
| Bunny's line had no readable backing | **PASS** — cream SDF bubble with tail, sized from the shaped text, steps away from Aliz, hidden under care overlays | `docs/shots/bubble_backing_after_*` |
| Main menu plain green/blue | **PASS** — original storybook cottage, garden, path, flowerbeds, trees, clouds; Aliz and Bunny only; four picture buttons with press feedback | `docs/shots/menu_wow_{ipad,iphone,pressed}.png` |
| No Home/Exit path | **PASS** — round Home button → "Take a break?" card: Continue / Home / Grown-ups. Home saves first, returns to the title, never quits the app | `docs/shots/ux_{ipad,iphone}_pause.png` |
| Version not visible | **PASS** — `GameVersion.BUILD` ("0.1.0") bottom-right, safe-area aware, clear of Next and the joystick | `docs/shots/ux_*_home_version.png` |
| White hand prompt ugly | **PASS** — peach arrow onto a mint ring with sparkles | `docs/shots/ux_*_tap_hint.png` |
| Interaction mechanical, no affordances | **PASS** — proximity badges OPEN / TAKE / PLACE / ENTER / HUG / CARRY / FEED, big tap targets, keep-outs for joystick, Home, Next, stars, version; hidden under overlays and pause | `docs/shots/ux_*_fridge_open`, `_fridge_take`, `_door_enter`, `_story_hug`, `ux_*_toybox_open` |
| Run not faster than walk | **PASS** — measured: walk 1.05 m/s, full-stick run 1.55 m/s (ratio 1.48x); stop in 0.15 m; run clip trimmed in range, 0 % slip. Root cause: every mode was capped at WALK_SPEED while the run clip already played | `test_run_vs_walk.gd`, `docs/shots/move_{walk,run}_*.png` |
| Cannot carry Bunny | **PASS** — CARRY / PLACE on Bunny: pick up 0.45 s → held at hip/chest on Aliz's new `carryFront` socket with a 4-bone arm pose → put down on a navigable spot an arm's length ahead; same node, no duplicate, stats unchanged, cross-room safe | `docs/shots/carry_bunny_{front,quarter,placed}_*.png` |
| Pick up / place objects | **PASS** — TAKE / PLACE for milk, teddy, banana, bowl through the `itemHoldRight` socket; source empties, item lands on its pad; milk and snack missions unchanged | `docs/shots/carry_prop_{held,placed}_*.png` |
| Voice robotic; speech loop unresponsive | **PARTIAL** — voice preference chain (Zoe/Samantha Enhanced when installed → best natural en-US), pitch/rate lifted, queue releases the moment the platform stops speaking, partial results shown live and used to stop early, encouragement spoken. **Still limited:** only compact Samantha is installed on this Mac; no Apple device ships a child voice. Real bug fixed: in the house, recognized words never reached the mission runner | `docs/VOICE_HONESTY_PASS.md`, `docs/shots/voice_*.png` |
| English not conversational | **PASS** (small vocabulary) — "I'm hungry, Aliz!" / "Let's make some milk!" / "Time to drink!" / "Thank you, Aliz!" across bubble, prompts, overlay, outro | `docs/shots/feed_portrait_ipad.png` |
| Music | **PASS** — owner confirmed rights (Suno); menu theme and mission track play in a normal build, one player, no restart across four room changes, ducks under speech, mute works. Suno plan-at-generation recorded as unverified, not invented | `docs/licences/music/*/OWNER_CONFIRMATION_2026-09-20.md`, `smoke_audio_shipping.gd` |
| Android build on the MacBook | **PASS** — toolchain installed user-locally; signed debug APK from the integrated HEAD; AAB pipeline proven with a debug bundle | §4, `docs/GOOGLE_PLAY_RELEASE_READINESS.md` |

## 2. Gates on `fa650bd`

| Gate | Result |
|---|---|
| Godot clean import | exit 0, no script errors |
| Full suite | **PASS - 128 case(s), 0 failure(s)** (was 122; no test weakened, three silence checks re-pointed at a pending fixture) |
| Mission 01 walkthrough | SMOKE PASS, 3/3 stars, replay re-armed |
| Mission 02 walkthrough | SMOKE PASS |
| Audio shipping smoke | SMOKE PASS (both tracks play, one player, ducking, crossfade, mute, loop) |
| Audio silent path (pending fixture) | SMOKE PASS |
| Feeding proof | `shots_rc.gd` RC SHOTS OK at 1334×750 and 2340×1080 |
| Kitchen / carry / menu / UX proofs | agents' harnesses (`shots_kitchen`, `shots_carry`, `shots_menu`, `shots_ux`, `shots_bubble`) all OK on their branches; independent QA on the integrated HEAD: see §5 |
| iOS export | `./tools/export_ios.sh debug` exit 0; `build/ios/LittleBuddy.xcodeproj`, pck 8,469,828 B, speech plugin referenced and registered |
| arm64 Xcode build | `** BUILD SUCCEEDED **`, binary arm64, rebuilt speech plugin linked (`partial_result` present) |
| Android debug APK | `build/android/LittleDays-debug.apk`, 36,802,352 B, SHA-256 `9b6b5f038ba19a26c0c0e3b163a4d881f0eae02c3a7a1d637627a0d9820f1758`, `com.pointit.littlebuddy` 0.1.0 (1), minSdk 24 / targetSdk 36, arm64-v8a, zero permissions, signed v2+v3 (debug key) |
| Release AAB | pipeline proven with a debug bundle; **no release artefact** — needs the owner's upload keystore (§4) |

## 3. Measurements

| | |
|---|---|
| Walk | 1.05 m/s (tap-to-walk and stick inside the run ring) |
| Run | 1.55 m/s at full stick (`RUN_SPEED` 1.6), 1.48× walk |
| Feeding camera | 1.40 m from Bunny's mouth, bound by the near floor corner |
| Bunny carry socket | 0.36 m up / 0.28 m ahead of Aliz's hips; dress clearance 0.16 m |
| Aliz | 3,889 triangles, one 512² atlas (budget 4,000 / 512) |
| Menu garden | ≈36k triangles, one directional light, no shadows |
| Meshy | balance 3134 → **3184** during the day (an increase; **0 credits spent**, no paid call) |

## 4. Install paths for today

**iPhone 14 Pro Max / iPad (Xcode):**
```
open ~/Projects/LittleBuddy-latest/build/ios/LittleBuddy.xcodeproj
```
Pick the device, check the Team on the LittleBuddy target (the preset carries
`JZDAUN45CF`; your identity is under `YZSLV4272S`, pick yours if Xcode shows
red), ⌘R. Trust the developer profile on first launch. Full card:
`docs/IPAD_QUICK_CHECK.md`.

**Android phone:**
```
~/Library/Android/sdk/platform-tools/adb install -r \
  ~/Projects/LittleBuddy-latest/build/android/LittleDays-debug.apk
```
(A phone that has the Mac Mini's build needs `adb uninstall com.pointit.littlebuddy`
first: different debug key.)

**Release AAB, when the owner has an upload key:** create it once with `keytool`
outside the repo, export `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD`,
then `tools/export_android.sh release --aab`. The script refuses debug keys,
keys inside the repo, and unsigned bundles. Details and Play Console blockers:
`docs/GOOGLE_PLAY_RELEASE_READINESS.md`.

## 5. Independent QA on the integrated HEAD

Run by a separate QA agent in its own worktree at `841d682` (the same code as
`fa650bd` minus two doc commits), 63 frames, report `docs/QA_INTEGRATED_841d682.md`,
key frames copied as `docs/shots/qa_*.png`. Verbatim: suite **PASS - 128
case(s)**; run-vs-walk `1.05 m/s → 1.55 m/s, ratio 1.48x`; both mission smokes
PASS with stars persisting across replay; audio smoke PASS (menu theme, mission
track, one player, no restart, duck gain 0.316 while speaking, mute); speech
probe with the plugin linked `backend: ios, available: true, fallbackActive:
false` — the mock was never selected.

| State | Result |
|---|---|
| Main menu: Aliz + Bunny only, four buttons, cottage, title | PASS |
| House entry / bedroom | **FAIL → fixed in follow-up** — HUG badge covered Bunny's speech line (`qa_harness_house_bedroom_ipad.png`) |
| Walking / running | PASS (1.05 / 1.55 m/s) |
| Bunny hungry, backed bubble, gone when satisfied | PASS (all six stagings, both viewports) |
| Carry Bunny / place Bunny | PASS (one Bunny, held via socket, floor gap 0.000 m) |
| Prop take / place | PASS |
| Fridge OPEN, bottle TAKE, prepare milk, feed, Snack Time | PASS |
| Feed close-up: real Bunny, "Time to drink!", no bubble, no badge under overlay | PASS |
| Home + pause card, version label | PASS |
| Save / load | PASS (smokes and save tests) |
| Door ENTER badge when a prop lies near the door | **FAIL → fixed in follow-up** — a banana outranked the door (priority tie broken by distance) |
| Story HUG on iPhone | **FAIL → fixed in follow-up** — badge overprinted the bubble |
| carry / place / take badges | **cosmetic → fixed in follow-up** — lowercase, no glyph (verb-case mismatch between the providers and the layer) |

No crashes, no wrong character, no duplicate Bunny, no floating objects, no
wrong-size frames, no mock speech success. Cosmetic leftovers QA listed and we
did not fix today: the target ring sits on Aliz's face when she stands right in
front of a station; the version label is very small; the HUD prompt can sit over
the 3D KITCHEN sign on iPhone; `shots_kitchen.gd` runs on the live profile.

FOLLOWUP_PLACEHOLDER

## 6. Honest limits and blockers

1. **Physical device QA has not happened.** Everything above is a macOS render or a headless run.
2. **Voice:** only the device's built-in TTS voice; a true child voice needs recorded lines (about 20 for Mission 01). Recognition is real on-device (macOS in the editor, iOS on device); the Mac test will prompt for microphone and speech permissions on the first Speak.
3. **Music rights:** the owner's confirmation is recorded; the Suno account/plan-at-generation is not. `music_licence_override.gd` is now dead code and can be deleted in a follow-up.
4. **Google Play:** no upload keystore, no Play Console app, no privacy-policy URL, no store graphics or Android screenshots; a personal account created after Nov 2023 needs 12 testers for 14 days before production. The AAB built by Gradle comes back unsigned and is re-signed by the script (verify with `jarsigner` before the first upload); the AAB has minSdk 29 (Vulkan), the APK 24.
5. **Carry:** Bunny's semantic id stays `bedroom.littleBuddy` wherever he is put down; a Story beat that targets him while he is carried waits until he is put down. Aliz has no authored carry clip; the arm pose is a modifier over walk/run.
6. **Aliz:** a faint coplanar residue under the mouth may shimmer at close range; a regeneration (≈40 credits: image-to-3D + remesh + rig) is prepared but not needed for the preview.
7. `test_version.gd` pins only the iOS version keys; the Android `version/code` is unguarded.

## 7. Remaining highest-priority task

Run `docs/IPAD_QUICK_CHECK.md` on the iPhone 14 Pro Max (already connected and
signing configured) and on the iPad, and send back the PASS/FAIL sheet.
