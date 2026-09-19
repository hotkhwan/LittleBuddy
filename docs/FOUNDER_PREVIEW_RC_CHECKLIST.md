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

**SHIP THE FOUNDER PREVIEW TO THE FAMILY, on iPad first.** Every technical gate
that can be executed on this machine passes, including two walkthroughs of the
real game. Nothing here is a simulation of the shipping path.

**Do not treat it as device-validated.** Physical iPad and Android remain BLOCKED
and only Khwan can close them. Ship it *to the testers*, not past them.

Three things the family should be told before they start, because all three look
like faults and are not:
1. **There is no music.** The rights are not recorded, the gate fails closed, and
   silence is the correct result.
2. **Aliz's face and hair are rough.** Known, blocked on a missing API key, and
   deliberately not fixed by shipping an unproven replacement.
3. **Speech on Android reports unavailable.** That is correct; the game is fully
   playable by touch.

---

## 2. Technical gates

| Gate | Status |
|---|---|
| Full test suite | **PASS** — 120 / 120, 0 failures |
| ContentValidator | **PASS** (runs inside the suite) |
| Clean Godot project load | **PASS** — no parse errors, and **no `add_child()` failures** (see §9) |
| Mission 01 walkthrough (real game) | **PASS**, exit 0 |
| Mission 02 walkthrough (real game) | **PASS**, exit 0 |
| Audio — silent build (normal) | **PASS** — no music, effects and speech alive |
| Audio — override armed (preview) | **PASS** — both tracks play, one player |
| Kitchen proof | **PASS** — 9 steps, each applied before it was photographed |
| iOS export | **PASS** |
| arm64 Xcode build | **BUILD SUCCEEDED** |
| Android debug APK | **PASS** — rebuilt at this commit, 36,560,813 bytes, signed v2+v3 |
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
| Playback in a normal build | **SILENT — verified, and correct** |

### Proven, not assumed

A dedicated run with nothing armed (`tests/smoke_audio_silent_build.gd`, using the
real `/root/Audio` autoload) shows:

- both .ogg files **present, imported, and decoding to the exact recorded
  durations** — so the silence is not hiding a broken path
- refusal reason is `commercialUseUnverified` on both, never `fileMissing` —
  a lost file could not masquerade as a licence refusal
- the whole tree is walked at every stage; **no** `AudioStreamPlayer` holds a
  music stream, in any scene, through four room transitions
- sound effects and spoken prompts **still work**, so the silence is music-only
- Mission 01 still completes end to end, silent, 3/3 stars

**Silence is a PASS on the device checklist.** No Suno rights were invented — the
producing tool is not even recorded.

To resolve: complete **`docs/MUSIC_RIGHTS_CHECKLIST.md`** with Anny. The deciding
fact is *which plan was active at the moment of generation*, and it is the one
fact that cannot be recovered later.

### A real leak route, found and closed

`has_cli_flag()` also read `OS.get_cmdline_args()`. Godot writes an Android
preset's `command_line/extra_args` into `assets/_cl_` **inside the APK** and
merges it into that list — and `export_presets.cfg` is a **committed file**. One
line there would have armed unverified music in a *distributed* build, with only
a device-side warning to say so.

Nothing had leaked: the shipped APK's `_cl_` was decoded and holds only harmless
engine arguments. The check is now narrowed to `get_cmdline_user_args()` — the
documented form `-- --allow-unverified-music` is exactly a user arg, so a
developer preview still works and the export route no longer exists.
`test_music_override_cannot_ship.gd` holds it shut, and also greps the presets.

### The .ogg files ship inside the binaries — owner's decision

Verified: ~2.37 MiB of audio, byte-identical, inside **both**
`build/ios/LittleBuddy.pck` and the APK. Gated at runtime; never sounds.

Correct engineering — but *distributing a copy* and *performing* a work are
different acts. Fine for a closed preview to invited families. **For any store
build, exclude `audio/music/*` from the presets rather than merely muting it** —
and the exclusion must catch the *imported* resource, not just the source, so
engineering should make and re-verify that change rather than hand-editing.

### One documented command was broken, and is fixed

`smoke_audio_shipping.gd` installed its own director named `Audio`. Once
`project.godot` registered the real autoload, `add_child()` found the name taken,
renamed the copy, and **two directors ran at once** — so
`-- --allow-unverified-music` armed both and every track played doubled. Without
the flag only the copy was armed and the autoload stayed silent, which is why it
went unnoticed. It now adopts the real autoload. Verified: one player, not two.

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

## 6. Lighting — the diagnosis was wrong, and so was the scene

The previous pass blamed ambient level and the sun's X sign. Both were checked
against the running light, and the real fault was worse and simpler:

`Transform3D(...)` takes its nine basis values **row-major**, and the scene's
were written as though they were the x/y/z **axes** (columns). The transpose of a
rotation is another valid rotation, so nothing errored, nothing warned, and no
test could see it.

| | the comment claimed | what it actually did |
|---|---|---|
| direction to sun | `(-0.400, 0.766, 0.503)` | `(0.623, -0.599, 0.503)` |
| elevation | +50° | **−36.8° — below the floor, shining upward** |

**Every upward-facing surface — floor, worktop, table, bed, every head — received
zero key light** and sat at flat ambient, while two walls clipped to near-white.
The clearest proof: the worktop was *darker than the wall behind it*.

Fixed: elevation −36.8° → **+48°**, key energy 1.12 → **0.61**, ambient 0.62 →
**0.52**, both warmed toward peach. **Total light energy went DOWN** (1.74 →
1.13) and a test asserts it can never rise.

| room | clipped pixels before → after | warmth before → after |
|---|---|---|
| kitchen | 18.8% → **0.1%** | +46.8 → **+60.0** |
| bedroom | 17.5% → **0.0%** | +39.4 → **+52.1** |
| bathroom | 22.4% → **0.1%** | +41.3 → **+56.2** |
| livingRoom | 21.6% → **0.1%** | +49.7 → **+63.8** |

Median luminance barely moves — it is **not brighter, the light moved**.

Cost: zero. No node, mesh, material, texture or transparent surface added; still
one `DirectionalLight3D` with shadows off; every changed value is a shader
uniform. No GI/SSAO/SSR/glow/fog/post — a new test greps both scenes for all of
them, including `fog_enabled`, the cheap way to fake depth that was not taken.

Evidence: `docs/shots/light_*.png`, 20 images, iPad 1334×750 and **true** iPhone
2340×1080, each with a BEFORE twin from the same scene, camera and code path, all
dimensions read back from the PNG header.

Also corrected: the "grey ellipse under the character" is **not** a contact
shadow — there is no such decal in the project. It is the beat marker, authored
as mint at 42% alpha, which read grey only because the blown-out floor left no
colour in it. Lifting the sun above the floor restored most of the grounding.

## 7. Bunny speech bubble — the committed fix was wrong, and is now right

**Verdict on the previous change: FAIL, with evidence.** Two defects:

1. **World in, local out.** The side was chosen from world x and written into the
   bubble's *local* frame. Bunny is authored yawed 180° in the bedroom, so local
   +x **is** world −x — told the caregiver was on his left, it moved the line
   **onto her**.
2. **Never re-evaluated.** It ran only from `_refresh()`. Aliz walking over is not
   a refresh, so the side was fixed once at build and **the swap could not happen
   in gameplay at all**.

It passed my review because the one staging I photographed — Aliz directly behind
Bunny — looks fine either way, and gives no hint the rule is inverted and frozen.

Replaced: side chosen along the **live camera's** horizontal axis, converted out
of world space before writing, re-evaluated every frame, and sized as
`clearance − |her offset|` so it goes to zero exactly as she walks clear — no
threshold to flicker across.

Verified across five stagings at both viewports (15 PNGs, dimensions read back):
does not obscure Aliz (330–414 px clear) · does not obscure Bunny · readable ·
inside both viewports · no HUD collision in FEED mode · **the swap works**:
caregiver at −0.40 → bubble +0.29; at +0.40 → −0.29.

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

### Fixed this pass, worth knowing existed
1. **The bedroom rendered as an empty cream void** in the shipping path.
   `child_actor._ready()` asked for the caregiver, which called `HouseWorld`'s
   lazy `get_character()`, which began building the world **while the bedroom was
   still setting up its own children**. Godot refuses `add_child()` in that
   state, so `room.gd` had both calls rejected, marked itself built, and left its
   geometry parented to nothing. The actor's build is now deferred one frame.
   **I had seen this and dismissed it as a harness artifact.** It was not.
2. The sun was **below the floor** (§6).
3. The bubble's side-swap **could not happen in gameplay** (§7).
4. A documented preview command ran **two audio directors** and played
   everything doubled (§4).
5. The unverified-music override could have been armed from a **committed**
   preset file (§4).

### Open
| # | Issue | Severity |
|---|---|---|
| 1 | **Aliz's face and hair** — modelled grin, hair gaps. Blocked on `MESHY_API_KEY`. | Visible, accepted |
| 2 | **No in-game mute or volume control.** `AudioDirector` has the methods; no UI reaches them. Moot while music is silent. | Owner decision |
| 3 | One side wall is always at pure ambient — geometry, not a setting. One directional light cannot light opposite normals. | By design |
| 4 | The beat marker and joystick ring are now the palest shapes in frame. | Cosmetic |
| 5 | Choice-row objects float during `choose` beats (a different spawner from the kitchen bug). | Cosmetic |
| 6 | `bedtime` still cuts to an unrigged sleeping export. | Known |
| 7 | 18 older screenshots are the wrong aspect and should not be cited. | Evidence hygiene |
| 8 | `WORLD_POLISH_PASS.md` §8 and a `house_layout.gd` comment still repeat the wrong sun diagnosis. | Doc debt |

---

## 10. What only Khwan can close

`docs/DEVICE_QA_CHECKLIST.md` — iPad and Android, owner sign-off only. Neither I
nor any agent may mark a device row PASS. Two rows have a result that looks like
its opposite, and both are called out in the sheet:

- **Music**: silence is a PASS.
- **Speech on Android**: it must report *unavailable*. If the game ever accepts a
  word the tester did **not** say, that is a hard FAIL — a bug of exactly that
  shape shipped and was fixed, and it looks like success.
