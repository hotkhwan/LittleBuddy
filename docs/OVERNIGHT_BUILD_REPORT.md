# Little Buddy — Overnight Build Report

**Date:** 2026-09-17
**Baseline protected at:** `0f223c9` / tag `little-buddy-mvp-working`
**Final commit:** see `git log -1` (latest is the docs commit containing this file)

> This report states what was **actually verified** and what was **not**.
> Nothing here claims the build is bug-free, and nothing here claims
> physical-device validation — no iPhone or iPad was attached at any point.

---

## 1. Final validation results (all re-run at the end, on the real repo)

| Check | Command | Result |
|---|---|---|
| Godot project loads | `--headless --path game --quit` | **zero errors** |
| Automated test suite | `--headless --path game --script res://tests/run_tests.gd` | **PASS — 24 cases, 0 failures** |
| iOS export | `tools/export_ios.sh debug` | **exit 0, no errors** |
| Xcode build (device arm64) | `xcodebuild -destination 'generic/platform=iOS'` | **`** BUILD SUCCEEDED **`** |

Shipped app binary, inspected directly:

| Property | Value |
|---|---|
| Architecture | `arm64` |
| `UIDeviceFamily` | `1,2` (Universal iPhone + iPad) |
| `MinimumOSVersion` | `15.0` |
| Orientations | LandscapeLeft **and** LandscapeRight |
| Privacy strings | `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` — and **only** these |
| `Speech.framework` + `AVFoundation.framework` | linked into the binary (`otool -L`) |
| Speech plugin entry symbol | bound (5 refs, `nm`) |
| `DEVELOPMENT_TEAM` | `JZDAUN45CF` (preserved) |

Remaining build warnings: 2× `#pragma once in main file` and 1× `AppIntents.framework`.
Both are upstream/benign — `dummy.h` is **byte-identical** to Godot 4.7.2's own export
template and is used as the Swift bridging header. Analysis in `docs/ipad-runbook.md` §3a.

---

## 2. Content — counts measured by running `ContentValidator`, not claimed

```
categories        = 5      (feeding, dressing, bath, play, bedtime)
tasks             = 43
vocabulary words  = 46
phrase variants   = 270
missions          = 7
stickers          = 16
objects           = 28
modes             = followInstruction 25, findIt 9, sayIt 9
validator problems= 0
content load warnings = 0
```

All targets in `CLAUDE_OVERNIGHT_BUILD.md` met or exceeded (targets were ≥25 tasks,
≥30 words, ≥80 phrases, 12–20 stickers, 3 modes).

---

## 3. What was implemented

**Interaction** — reusable `DraggableObject` / `DragPlane`: camera-ray drag against a
stable plane, no `RigidBody3D`, latched pointer index (multi-touch safe), per-gesture
delivery latch, smooth return-to-origin, tap fallback preserved everywhere. Measured
grab areas at 1366×1024: milk bottle 334×388 px, teddy 329×321 px, spawned objects
240×240 px — all above the 220 px child-usability bar.

**Speech** — see §5; two real runtime bugs fixed, plus interruption handling.

**Visual** — nursery replaces the tech-demo room: crib, rug, window, shelf, toy box,
wainscot, pastel palette; baby restyled with connected arms, 10 view states and 5
animation clips. Exactly **one** `DirectionalLight3D` live at runtime (verified in the
running scene, not just in the `.tscn`). No GI/SSAO/SSR/glow/volumetric fog/particles.

**Content** — fully data-driven (`ContentLibrary`, `ContentValidator`, `TaskPicker`).
Adding content requires no new scenes: `ObjectSpawner` builds any object from its
`objects.json` record.

**Gameplay** — three mode handlers (`findIt`, `sayIt`, `followInstruction`) behind one
interface, driven by `MissionRunner` over 5–8 task sessions, across five activity scenes.

**Progression** — `RewardLedger` (single writer to `SaveService`), `StickerBook`
(16 procedurally drawn stickers, persisted), celebration, session summary.

**Parent settings** — behind a 3-second press-and-hold gate: Thai hints, voice practice,
TTS speed, and reset-progress behind a second deliberate hold.

**Audio** — 8 original procedurally generated WAVs (sine partials, ADSR, peak-normalised
to −6…−14 dBFS, boundary samples forced to zero). All 8 are now actually triggered by
gameplay.

---

## 4. Bugs found and fixed during the build

These are worth recording because several were **silent** — tests passed while the
behaviour was wrong.

1. **Test runner hid red builds — twice.** A case whose script failed to parse silently
   vanished from the run (still reported PASS); and a case whose `run()` aborted returned
   `null`, which was counted as zero failures. Both are now loud failures, each verified
   by deliberately breaking a case.
2. **Camera pitch sign inverted** (earlier session) — baby, bottle and teddy rendered
   entirely off-screen while every automated check still passed. Only a rendered
   screenshot caught it.
3. **Speech never worked at runtime** — two independent causes, §5.
4. **Crescent-moon and banana sticker polygons were self-intersecting**; Godot's
   triangulator silently draws nothing, so they would have shipped as blank cards. A test
   now asserts every sticker polygon triangulates.
5. **`feedMilk` could pay twice** across the legacy feeding loop and the mission system.
6. **Landing pads drawn for every prop zone** even during `findIt` tasks, where nothing is
   dragged. Now only the zone the current task targets shows a pad.
7. **Three generated sound effects were never played** (`pickup`, `drop_return`,
   `bedtime_chime`).
8. **`ttsSpeed` was persisted but ignored** — `TtsService` hardcoded rate 1.0.

---

## 5. Speech: what is verified and what is not

**Two genuine runtime bugs were found and fixed:**

1. `SpeechService._select_backend()` chose a backend **once** at startup from a single
   `is_available()` snapshot. `SFSpeechRecognizer.isAvailable` is KVO-observed and is not
   reliably true immediately after construction, before permission is even requested — so
   one early `false` permanently locked the app into an inert no-op backend for its entire
   lifetime. Selection now keys off the native singleton's presence and evaluates
   availability live.
2. `listening_stopped` was emitted only on manual `stop_listening()` — never on a final
   result, error or timeout — so the "I'm listening…" state stuck on forever after the
   first attempt.

Also: `AVAudioSession` `.record` → `.playAndRecord` with `MixWithOthers`/`DefaultToSpeaker`
so grabbing the mic doesn't fight Godot's audio driver; all native signal emissions
marshalled via `call_deferred`; `AVAudioApplication` permission API on iOS 17+ with
fallback; ~5 s auto-stop timeout; interruption + media-services-reset observers routed
through the single teardown path; `@try/@catch` around `AVAudioEngine` start/teardown.

**Deliberate decision:** server-based recognition was **not** added as a fallback, even
though it would make speech work in more cases. It would upload a child's voice, which
`CLAUDE.md` forbids. On-device recognition is required, and when it is unavailable the
service reports unavailable rather than silently uploading. Touch remains fully playable.

**Verified:** plugin compiles and links for device `arm64` **and** `arm64_x86_64-simulator`;
the xcframework is embedded in the generated Xcode project; `Speech.framework` and
`AVFoundation.framework` are linked into the built app binary; the entry symbol is bound;
`xcodebuild` succeeds.

**NOT verified — requires your device:** that speech actually recognises "milk"
end-to-end. No permission prompt, no `listening_started`, and no live recognition has
been observed. A simulator run was attempted and could not be completed: Godot 4.7.2's
own simulator template archive is x86_64-only, and the Xcode 27 simulator runtime no
longer installs x86_64 apps. **Treat speech as unproven on device until you test it.**

---

## 6. QA results

A read-only QA pass drove all 7 shipped missions end-to-end (deliberately answering wrong
before right on every choice task), hammered the reward ledger with re-entrant and stale
signals, and fed the save layer six corruption shapes.

- **P0: none found.** No dead end, no crash path, no double-reward survived review.
- **P1 (2, both now fixed):** reward-pacing timing invariant was unenforced; native
  plugin had no audio-session interruption handling.
- **P2 (3):** three unused SFX (**fixed**); `ttsSpeed` not type-validated at the save
  layer (**accepted** — both consumers re-validate independently); a `TODO_COLOR`
  constant name that greps as a TODO marker (**not a real finding**).

On the pacing invariant: I first tried scoping the ledger's spam window per completion id,
but that broke an existing test which correctly spams with **unique** ids — a caller that
mints a fresh id per tap is stopped only by the global window. The guard was therefore
left as designed and the cross-file invariant is now asserted instead
(`test_rewards_pacing_invariant`), which fails loudly if the task gap ever drops below
2× the spam window. Verified by setting `TASK_GAP_SEC` to 0.3 and watching it go red.

---

## 7. Compliance sweep (executed)

- No `HTTPRequest`/`HTTPClient`/`WebSocket`/TCP/UDP/multiplayer APIs anywhere in `game/`
- No `http(s)://` URLs outside the standard SVG `xmlns` declaration
- No analytics, ads, IAP, login, Cloudflare or Fly.io references
- No file/network I/O symbols in the native speech plugin (audio cannot reach disk or a socket)
- No `print()` left in child-facing gameplay code
- No real `TODO`/`FIXME` in gameplay-critical paths
- App is fully playable in Airplane Mode by design — nothing in the critical path touches the network

---

## 8. Known limitations (honest list)

1. **Nothing has been run on a physical device.** Every on-device claim is unproven.
2. **Speech is unproven on device** (§5). Touch-only play is unaffected either way.
3. **Interruption handling is reasoned, not observed** — no real Siri/phone-call
   interruption was triggered, and the `@try/@catch` was never seen catching a live throw.
4. **Spawned objects are coloured primitives.** A "spoon" is a white cylinder. Functional
   and data-driven, but not yet readable as the real object; this is the weakest part of
   the presentation.
5. **`sayIt` drives roughly one task per mission**, so speech contributes less than the
   content counts suggest. Touch completes every task identically.
6. The five placeholder SVGs in `game/assets/placeholders/` are unused leftovers from the
   original 2D plan (the mic icon is still used).
7. 3D-node spawn/despawn leak checking was done by code reading; only the pure-logic layer
   was measured for object growth (delta of 8 objects over 20 cycles — not meaningful).
8. Content is English + Thai hints only.

---

## 9. Exact next steps for the owner

1. Open `/Users/hotkhwan/Projects/little-buddy/build/ios/LittleBuddy.xcodeproj`.
2. **Signing & Capabilities** → confirm team `JZDAUN45CF` resolves.
3. iPhone → **Settings → Privacy & Security → Developer Mode → On**, reboot, unlock.
4. Select the iPhone, press **▶ Run**. First launch: **Settings → General → VPN & Device
   Management → Trust**, then Run again.

### Physical-device checklist

**Core loop**
- [ ] Title → Play → nursery appears in landscape
- [ ] A mission starts; prompt + Thai hint readable; progress dots advance
- [ ] Drag an object to the baby → it snaps, baby reacts, **+1 star exactly once**
- [ ] Tap instead of drag → same result (the accessibility path)
- [ ] Wrong choice → gentle encouragement, task continues, no red X
- [ ] **Next** always moves on — never stuck
- [ ] Session summary → "Play again" starts a new mission
- [ ] Sticker book opens, shows locked silhouettes, back button works
- [ ] Force-quit and relaunch → stars and stickers preserved

**Speech (the unproven part)**
- [ ] Tap Speak → mic **and** speech-recognition prompts appear with the custom wording
- [ ] Say "milk" → recognised, task completes
- [ ] Game audio does **not** glitch when the mic opens (the `.playAndRecord` fix)
- [ ] "I'm listening…" always clears within ~5 s
- [ ] Tap Speak 2–3 times in one session without relaunching
- [ ] **Deny permission → touch play still completes everything**
- [ ] Trigger Siri or a call mid-listen → no crash, listening clears

**Universal / safe area**
- [ ] Star counter clear of the Dynamic Island in **both** landscape rotations
- [ ] Speak/Next/Stickers clear of the home indicator
- [ ] Rotate 180° → all UI stays inside the safe area
- [ ] Repeat on iPad (4:3) — the same Universal build covers both

**Offline**
- [ ] Airplane Mode **before** launch → everything above still works

---

## 10. Recovery

The last known-good pre-overnight state is tagged:

```bash
git checkout little-buddy-mvp-working   # 0f223c9
```

Every milestone is a separate commit, so a single regression can be reverted without
losing the rest.
