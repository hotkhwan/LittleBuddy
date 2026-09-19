# Little Days — Founder Preview Release Candidate

**Care, Play & Grow** · featuring Aliz and Bunny
Branch `feature/overnight-production-candidate`

> **Integrated commit: _pending final integration_** — this line is filled in by
> the Lead at the last green commit, and every claim below is tied to it.

> **Closed Founder Preview. Not a store release.** Nothing has been submitted to
> Apple or Google. No billing exists. No public distribution without Khwan's
> explicit approval.

---

## 1. Release recommendation

_Filled in after the final gate run. The recommendation is based only on gates
that were actually executed — a gate that could not run is BLOCKED, never PASS._

---

## 2. Technical gates

| Gate | Status |
|---|---|
| Full test suite | _pending_ |
| ContentValidator | _pending_ |
| Clean Godot project load | _pending_ |
| Mission 01 walkthrough (real game) | _pending_ |
| Mission 02 walkthrough (real game) | _pending_ |
| Audio shipping smoke | _pending_ |
| Kitchen proof | _pending_ |
| iOS export | _pending_ |
| arm64 Xcode build | _pending_ |
| Android debug APK | _pending_ |
| **Physical iPad** | **BLOCKED** — owner only |
| **Physical Android** | **BLOCKED** — owner only |

---

## 3. Installation

Full steps, including the traps, are in **`docs/INSTALL_GUIDE.md`**.

**iPad** — `build/ios/LittleBuddy.xcodeproj`, open in Xcode, select team and
device, ⌘R. Three things that will bite, all documented in the guide: iOS 16+
**Developer Mode** must be enabled on the iPad; the profile must be trusted under
Settings → General → VPN & Device Management; and free provisioning **expires
after 7 days** (replug and ⌘R — saved progress survives).

**Android** — `adb` is not on `PATH`:

```
~/Library/Android/sdk/platform-tools/adb install -r \
  /Users/hotkhwan/Projects/little-buddy/build/android/LittleDays-debug.apk
```

⚠️ **`build/` is git-ignored.** Both artefacts exist only on this Mac. A clone
elsewhere has nothing installable until the export scripts are run.

⚠️ **Re-export before installing.** The APK and the iOS project are only as fresh
as the last export. Check with:

```
find game -type f -newer build/android/LittleDays-debug.apk | head
```

---

## 4. Music licence status — the one true blocker for audio

| | |
|---|---|
| Tracks | `littleDaysTheme`, `hungryBunny` — Anny's originals, integrated |
| `commercialUse` | **`pending`** |
| `licenseEvidence` | **`OWNER TO CONFIRM`** |
| Playback in a normal build | **SILENT — and that is correct** |

The licence gate fails closed. No Suno rights evidence was invented; the
producing tool is not even recorded. **Silence is a PASS on the device
checklist**, not a failure.

To resolve it, complete **`docs/MUSIC_RIGHTS_CHECKLIST.md`** with Anny. The
question that actually decides commercial rights is *which plan was active at the
moment of generation* — and that fact is not recoverable later.

⚠️ **The unlicensed OGG files ship inside the binaries.** Verified: both
`little_days_theme` and `hungry_bunny` are present in `build/ios/LittleBuddy.pck`
(7.8 MB) and in the APK. They are gated at runtime, not excluded from the
package. For a closed preview to invited families that is defensible. **For any
store build they should be excluded, not merely muted** — one line in
`export_presets.cfg`'s `exclude_filter` (add `audio/music/*`). Not applied here,
because it would also disable the owner's preview override. Owner's call.

**The unverified-music override is a development switch and must never be the
shipping answer for rights.** Nothing committed arms it.

---

## 5. Aliz model status

**Unchanged — still the known weak point.** Modelled open-mouth grin, real gaps
in the hair, arms-down source pose that made the auto-rigger guess wrong.

**Blocked:** `MESHY_API_KEY` is not present in this environment. **0 of the 100
authorised credits spent.** No Art Agent was run, per the instruction not to
block Monday on a regeneration.

Ready the moment a key exists:
- `docs/reference/aliz_reference_v1.png` — grin painted out, fringe closed
- `docs/reference/aliz_reference_apose.png` — arms swung 38° out, because
  image-to-3D copies the pose **in the picture**
- `tools/meshy_aliz_apose.sh` — balance before/after, typed `YES` before any paid
  call, no retry, refuses to overwrite, refuses the all-zeros sentinel

The replacement gate stands: the current Aliz stays in production until a new
model passes rigging, locomotion, visual comparison, mobile budget and gameplay.
**Do not ship a beautiful broken model.**

---

## 6. Lighting

_Pending — before/after with verified viewport dimensions._

## 7. Bunny speech bubble

_Pending — deterministic capture at both viewports._

## 8. HUD

**Fixed, and re-proven at a true 2340×1080 viewport.**

The earlier fix moved the HUD's stack out of the centre during close-ups. A
capture at the *real* iPhone aspect then exposed a second collision the clamped
screenshots had hidden: the care overlay's own title ("Drink!") and the HUD's
duplicate instruction ("Give Bunny the bottle.") overprinting each other — two
systems narrating the same beat.

`set_narration_covered()` silences the HUD's copy while a full-screen close-up is
talking. **The `Next` button and the stars stay**: hiding the escape hatch with
the text would be a dead end, which `CLAUDE.md` bans outright, and that is the
assertion `test_hud_narration_cover.gd` is built around.

### Evidence quality — a correction that affects older claims

`--resolution 2340x1080` is a **request**. The window manager clamps it to
1686×935, so a **1.80 aspect gets filed as evidence for a 2.17 one**. Since the
camera fits its distance *from* the aspect, that is a different composition, not
a rounding error.

An audit of all 177 screenshots in `docs/shots/`:

| | count |
|---|---|
| iPhone-named, correct 2.17 aspect | 27 (16 of them full-res 2340×1080) |
| iPhone-named, **wrong aspect** | **18** — including 8 of the HUD evidence |

`game/tests/shots_rc.gd` renders through an explicit `SubViewport` and **asserts
the saved PNG's dimensions**, so it cannot make the same mistake quietly.

---

## 9. Known issues

_Consolidated after final integration._

---

## 10. What only Khwan can close

`docs/DEVICE_QA_CHECKLIST.md` — iPad and Android, owner sign-off only. Neither I
nor any agent may mark a device row PASS. Two rows have a result that looks like
its opposite, and both are called out in the sheet:

- **Music**: silence is a PASS.
- **Speech on Android**: it must report *unavailable*. If the game ever accepts a
  word the tester did **not** say, that is a hard FAIL — a bug of exactly that
  shape shipped and was fixed, and it looks like success.
