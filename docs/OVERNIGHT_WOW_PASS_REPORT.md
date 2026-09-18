# Overnight WOW pass — morning report

**Date:** 2026-09-19 · **Branch:** `feature/overnight-production-candidate`
**Meshy credits spent: 10 of the 30 authorised.** Balance 3064 → **3054**.
**All gates green:** 97 tests, ContentValidator, project load, iOS export, arm64 build.

Six commits, each a green checkpoint. Nothing was left half-finished; the things
that were *not* done are listed in §9 rather than hidden.

---

## 1. What you will see when you open it

| # | Before | Now |
|---|---|---|
| App icon | a generic milk bottle | **PinkGirl + Little Buddy**, rendered from the real models |
| Main menu | 2 buttons, one procedural toddler | **PinkGirl and the baby together**, 4 actions |
| Rooms | flat beige margins at every edge | **the room fills the screen** |
| Doors | two identical arches, no clue where they go | **signed: KITCHEN, BATHROOM, BEDROOM, LIVING ROOM**, colour-coded, with a glyph |
| Cabinets | none | **a toy box whose lid actually swings open** |
| Speech | a silent button | **nine states, always visible, always with a way out** |
| Parent tools | a JSON file needing a Mac and a UDID | **an on-device speech check** |
| Caregiver | switched off, never seen | **on screen, inside budget** |

Screenshots: `docs/shots/wow_*.png`, `icon_preview_sizes.png`, `speech_state_*.png`.

## 2. Rooms fill the screen

The camera fits the 4×4 m floor and its headroom exactly, and the room *ended*
exactly there — so every aspect ratio wider or taller than the room's own showed
flat environment colour past the walls. Worst on a 4:3 iPad.

Zooming in would have cropped the room the framing was built to keep whole. So
the room stays its size and **the world got bigger**: an apron floor continues
the boards outward, and a taller surrounding wall band fills the upper corners.
Entirely visual — no collider, no navigation, no addressable target — and folded
into the shell's existing `SurfaceTool`, so it costs **no extra draw call**.

Verified at **1366×1024 (iPad)** and **1792×828 (wide iPhone)**.

## 3. Doors say where they go

Route knowledge lived only in `toRoomId`, which the player cannot read.

Each door now carries a hanging plaque: a chunky painted glyph (bed, bath, plate,
sofa) over the room name. The glyph is the load-bearing half — a four-year-old
who cannot read "KITCHEN" can still learn "the door with the plate on it".

**Three attempts, because the first two were wrong in ways only a render showed:**

1. On the wall above the architrave — the wall is 2.2 m and the door 1.9 m, so a
   0.5 m plaque did not fit and was clipped by the ceiling.
2. Flat on the door face — both doors are on *side* walls, so a flat sign is
   edge-on to this camera and unreadable.
3. Hanging into the room facing +Z. This one works.

Colours come from a sign-specific map, because `accent_color()` and
`dominant_color()` each give two rooms the same value — fine for room mood,
useless for telling two doors apart. The label is INK, not the accent: pastel on
pastel was the one part still hard to read at distance.

## 4. Speech stops being a black box

Your report was *"I cannot tell whether speech recognition is working"* — and on
a device, an invisible action is indistinguishable from a broken feature.

**Child-facing panel**, nine states, each with a face: listening (a pulsing
microphone drawn from three rounded boxes), processing, `You said: milk`,
`Great!`, `Try again!`, microphone-off, voice-unavailable, error. Two rules, both
asserted by tests:

* **Nothing reads as failure.** No red, no cross, no score, no "wrong".
* **The touch fallback is never hidden.** Every unhappy state names tapping, so a
  child who cannot be heard can always still finish.

**Parent diagnostic**, behind the parental gate, collapsed by default: 15 rows
plus a one-line verdict that names the **root cause** in the order that actually
blocks speech — setting off → plugin missing → permission → never tried → never
understood. Reporting "not understood" when iOS never granted permission would
send you looking in the wrong place.

**A privacy guard caught me.** The first version kept the last transcript in
`speech_service.gd`, and `test_speech_privacy_guard.gd` failed with *"appears to
retain a transcript"*. The guard is right: the service is a long-lived autoload
that writes JSON to disk, so anything it remembers is one bug away from being
persisted. The transcript now lives only in the parent panel — in memory, never
written, gone when the screen closes. **The guard was not touched.**

## 5. Cabinets and tidy-up

`storage_model.gd` is pure domain — no `Node3D`, no `NodePath`. A container is
`{storageId, acceptedItemTags, capacity, isOpen, storedItems}` and a new drawer
is a row in `HouseLayout.storages()`, never a new script.

The most important method is `why_refused()`, because *"nothing happened"* is the
worst possible answer for a four-year-old. A closed wardrobe, a full one and the
wrong one are three different situations, each with its own sentence — and the
reason returned is the most **useful** one, not the first found: aiming at the
wrong cabinet is reported before "it is closed", because opening it would not
have helped.

**The lid is the point.** "Open" and "closed" have to be visibly different, and a
colour change would not read at gameplay distance, so the lid is its own node on
its own hinge and opening swings it back — an unmistakable silhouette change that
needs no text. Walking up to a container toggles it and says "open" / "close".

`tidy_plan.gd` holds 3–6 items, clamped. Past six it stops being a game and
becomes chores. Praise rotates so "Great!" six times does not stop reading as
praise.

## 6. Characters

| | Triangles | Texture | Bundle size | Status |
|---|---|---|---|---|
| PinkGirl, raw export | 619,890 | 3 × 2048² | 22 MB | was **switched off** |
| PinkGirl, runtime | **3,898** | one 512² | **0.59 MB** | **on screen** |
| Little Buddy, runtime | 14,406 | one 1024² | 1.60 MB | on screen |

PinkGirl took two Meshy operations (10 credits): a remesh, then a rig. The first
remesh at 2,000 quads returned 4,341 triangles — **341 over** `MAX_TRIANGLES`.
The brief says not to raise the budget to fit an asset, and editing the test to
pass would be the same thing by another route, so the **asset** was re-cut at
1,750 quads instead.

Rigging was chosen over relaxing the gate for the same reason: the flag requires
in-budget **and** able to animate, and loosening that guard for a static avatar
would have been weakening a test to turn it green. She now passes it untouched.

Everything after the remesh was local and free (`tools/optimize_runtime_glb.py`):
smooth normals across welded positions, emissive/specular/ior/normal/ORM
stripped, metallic 0.0, roughness 0.9, single-sided, one 512² atlas.

**Little Buddy was deliberately left at 14,406 triangles.** Re-cutting to ~3k
needs another remesh *and* another rig — 10 more credits — to improve something
that was already working and not blocking the visible experience. It remains over
the 4,000 art-bible budget; that call is yours, and 20 credits remain.

## 7. Two bugs the gates caught that would have shipped

**PinkGirl would have been invisible on the iPad.** `exclude_filter` excluded
`assets/characters/buddy/*` wholesale, so the optimised runtime asset would have
been stripped from the device build — visible in the editor, absent on the
device, and no test would have said so. Narrowed to the raw export only, then
verified by reading the `.pck`. **The pack fell from 24.0 MB to 5.0 MB.**

**A 100× unit error, twice.** Meshy rigs export bones in centimetres under an
`Armature` carrying a 0.01 unit conversion, while the mesh data is already in the
metre space the bones resolve to — so walking the node chain applies that 0.01
twice. `test_buddy_avatar` caught it as *"the normalised height is 0.0165 m, not
1.65 m"*. Same defect existed in the baby wrapper; fixed in both.

## 8. A near-miss worth your attention

`meshy_rig.sh` had its output paths hardcoded to the baby. Rigging PinkGirl
**silently overwrote the baby's rigged GLB and both of its clips** — three files
already paid for, no warning, no prompt.

Caught immediately, restored by re-downloading from the still-live Meshy task
(URLs valid until 2026-09-21). The tool now requires an output stem and refuses
to overwrite an existing file. Had it gone unnoticed for a day, those assets
would have been unrecoverable.

## 9. What was NOT done

Listed plainly rather than buried:

* **The tidy activity is not driven by a mission yet.** The domain is complete
  and tested (`storage_model`, `tidy_plan`), containers open and close in-game
  and are addressable — but nothing yet *scatters* items and walks a child
  through putting them away. That is the next session's work.
* **Kitchen, bathroom and living room got no new hero props.** The stage backdrop
  and door signs apply to all four rooms, but §5's "lived-in" pass only really
  landed in the bedroom (toy box) and living room (shelf).
* **Launch/opening sequence untouched.** The menu improved; there is still no
  animated first-5-seconds transition.
* **Little Buddy is still over the triangle budget** (§6).
* **No audio work.** Existing SFX untouched.
* **Interaction smoothness was not audited.** Joystick, tap-to-walk and drag were
  left exactly as they were — no regressions introduced, but no review either.

## 10. Speech status — read this before testing

Speech has **not** been validated on a physical device. Nothing in this pass
could do that, and the code makes no claim otherwise.

What is now true: a build installed on your iPhone will *tell you* what the
microphone is doing, and **Parent Corner → "Check speech"** names the root cause
in one line. That screen is the thing to open first tomorrow.

## 11. Gates

| Gate | Result |
|---|---|
| Godot test suite | **97 cases, 0 failures** (was 94 at the start of the night; 3 new cases) |
| ContentValidator | **pass** (exercised by 10 cases in that suite) |
| Project load (headless) | **pass**, clean |
| Runtime character validation | **pass** |
| iOS Xcode export | **pass** |
| **arm64 device build** | **pass** — `BUILD SUCCEEDED`, binary verified `arm64` |
| Bundle | **5.0 MB pck**, no raw source GLBs |

Tests were changed in two places, both recorded in their commits: `test_baby_avatar`
and `test_buddy_avatar` asserted "this character can never animate", a premise a
rigged asset made false — and whose own failure text asked for the revision. They
now assert **honesty** (capability must match what the asset carries) instead.
The anti-faking source scans and both budget gates are untouched and still
failing where they should.

## 12. Still needs a physical iPhone

* Whether speech recognition actually works end to end.
* Whether the microphone permission prompt appears and is accepted.
* Whether the icon reads well on a real home screen.
* Frame rate with the new stage geometry and two characters in the menu.
* Whether the door signs are legible at arm's length on a phone rather than a
  desktop monitor.
