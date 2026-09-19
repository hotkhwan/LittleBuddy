# World / Camera pass — Agent C

**Branch:** `feature/overnight-production-candidate` · **Engine:** Godot 4.7.2 · **Not committed.**

The brief's P0 complaint was that the house uses *"one wide top-down room shot for
everything"*, which *"makes characters and interactions look small"*, plus *"giant placeholder
room labels"*. All the evidence below is a render of the real `scenes/house/house_world.tscn`,
taken at the two resolutions named in the brief and at the project's own 4:3 reference, and every
one of them was looked at.

---

## 1. Why the camera looked wide — the two numbers that were doing it

Both causes turned out to be arithmetic rather than taste, so both are now measured.

### a. The close-up was clamped back out to the room's standoff

`house_layout.gd` authors `minDistance = 3.5 m` so the **whole-room** shot cannot crawl in among
its own furniture. `camera_framing.focus_framing()` copied that number onto the **activity** box
unchanged. A beat's box (radius ~0.9 m) fits from **2.77 m** and was being pushed back out to
3.50 m — so every close-up in the game stood 26% further away than the shot it had just
computed, and the pull-in from the 5.13 m room shot was a barely perceptible 1.47×.

`camera_framing.FOCUS_MIN_DISTANCE = 1.9 m` is now the floor for a close-up. It is a *ceiling on
the room's standoff*, never a new minimum: a room that authors something tighter keeps its own
number.

### b. The room shot looked at the room's centre

Pitched down 32°, the near floor edge falls a long way below a centred look-at point while the
far wall rises only a little above it. The room-centred fit was bound, at every aspect, by the
**near-left floor corner needing 5.13 m** while the back wall needed **2.24 m** — two metres of
distance spent on a constraint that was nowhere near binding.

`HouseLayout.CAMERA_FOCUS_Z = 0.42` slides the look-at point toward the open front and trades
that slack for scale until the two constraints meet. It is a composition change, not a crop:
`solve()` still fits every floor corner and every head-height corner.

### c. The safety net that had to be added first

`camera_framing.solve()` fits the floor corners and the same corners at *head* height. It has
never known anything about a 1.8 m wardrobe or a 1.7 m fridge — a gap that was invisible while
the camera paid for it out of slack. The first time the look-at point moved forward, the top of
the fridge left the frame.

So `HouseLayout.camera_fit_points()` now names the top corners of every prop above
`CAMERA_TALL_PROP_Y` (1.05 m) plus both door plaques, and they go into the framing's
`extraPoints`. The window (top ~2.03 m) is **deliberately excluded** and documented as such:
keeping it inside the safe area on its own costs the whole of the gain. It stays on screen, it
simply loses the right to sit below the status line.

### Measured result

| Shot | Before | After | |
|---|---|---|---|
| Room, 1334×750 and 2340×1080 | 5.13 m | **4.23–4.56 m** | 11–18% closer |
| Room, 1366×1024 (4:3) | 5.28 m | **4.62 m** | 12% closer |
| Counter / baby close-up, all aspects | 3.50 m | **2.77 m** | 21% closer |
| Room → close-up pull-in | 1.47× | **1.65×** | |

---

## 2. Room signage

The plaques were **0.92 × 0.46 m** — as wide as the door they hang over, wider than the child,
with a 64 pt word. Cold, they read as debug labels that had been given a frame, and "LIVING ROOM"
overran its own board (visible in `c_room_kitchen_BEFORE_ipad.png`).

They are now **0.60 × 0.30 m** (`HouseLayout.DOOR_SIGN_SIZE`): a thin accent rim round a cream
face, glyph above, word below at 48 pt. The **glyph did not shrink proportionally** — it is the
half a pre-reader actually navigates by, so it fills more of a smaller board.

One thing was tried and reverted after looking at it: setting the word in the plaque's own
deepened accent. It is calmer in isolation and vanishes in the room — `deep(peach)` on a cream
face, 40 px wide at gameplay distance, is pastel on pastel. The word is the secondary element by
**size**, not by contrast, so it is `ink` again.

The geometry numbers moved into `house_layout.gd` because the camera has to keep the plaque on
screen and a size known in one file and framed from another drifts the first time either is
touched. `test_camera_room_shot.gd` asserts both plaque corners stay in the safe area in all four
rooms at all four aspects.

---

## 3. Kitchen

A fridge, a worktop and a table is a *room with furniture in it*. Cold, the kitchen could as
easily have been read as a hallway with a cupboard in it. It now has, drawn into the room shell:

* an **open sink basin** with real interior depth (§6), standing proud of the worktop rather than
  sunk into it — the counter is a solid mesh, so a recess would simply be filled by it;
* a **tap**, in the dusty-blue "there is no metal" convention of §7;
* a **hob**: a plate and two rings. Two, not four — four merge into a texture at this distance,
  and the ring is the whole reason it is a stove and not a chopping board;
* **wall cupboards** over the worktop, to the left of the window, kept below 1.75 m so the shot
  still holds them.

**None of them has a collider or a touch target.** They all sit inside the counter's existing
1.8 × 0.6 m collider and inside its `ActivityTarget` box, so a tap anywhere on the worktop still
lands on `kitchen.counter` — one generous target, not three small ones. Nothing here stands on
the floor, because the navigation mesh is baked and committed and cannot be re-baked from this
workstream.

They are placed **around the drop zone**: `kitchen_view.gd` puts carried items down at the
counter's centre (`x = -0.8`), so the sink and the hob take the two ends. The plant that stood at
`x = -1.46` is gone — it occupied the only part of the worktop a sink could go on, and the room
already has one on the sill.

---

## 4. Nursery (the bedroom)

The room where the baby lives was telling the child so with the same generic framed abstract
square the living room has. It now carries a **cloud with three hanging charms** —
read instantly, one extrusion group in the shell mesh, no text for a player who cannot read.
Diamonds rather than discs for the charms, because a disc beside a round cloud is one more
bubble.

It is flat wall art rather than a real hanging mobile: anything dangling over a cot invites a tap
that does nothing.

---

## 5. Evidence — every file below was rendered and looked at

All in `docs/shots/`.

| File | What it shows |
|---|---|
| `c_room_{bedroom,bathroom,kitchen,livingRoom}_ipad.png` | 1334×750, exploration |
| `c_room_{…}_iphone.png` | 2340×1080, exploration |
| `c_room_{bedroom,kitchen}_ipad43.png` | 1366×1024, the project's reference aspect |
| `c_focus_{counter,buddy}_{ipad,iphone}.png` | the beat close-up, composed with the level director's own `camera_focus.frame_points()` |
| `c_beat_{counter,fridge}_*.png` | the close-up opened by **gameplay** — the real `snackTime` mission, the real director, `is_camera_focused()` true |
| `c_*_BEFORE_ipad.png` | the same shots before this pass |

Reproduce:

```
Godot --path game --resolution 1334x750  --script res://tests/shots_world.gd -- ipad
Godot --path game --resolution 2340x1080 --script res://tests/shots_world.gd -- iphone
Godot --path game --resolution 1334x750 res://scenes/spike/shot_harness.tscn -- beat <out> "snackTime:6"
```

### A harness bug found on the way

`shot_harness.gd`'s `house` job called `enter_room()` / `go_to_room()`. `HouseWorld` exports
neither — the method is `place_in_room()`. Every `-- house <outName> <roomId>` run since the
harness was written therefore photographed the **bedroom** and filed it as evidence for whichever
room had been asked for. Fixed, and a miss now prints instead of passing quietly.

A `beat` job was added alongside it: it starts a real level, optionally skips N tasks, and waits
for `is_camera_focused()`. A `goAndDo` beat only tightens on arrival and nobody is tapping the
floor in a screenshot run, so it puts the child in the beat's room and at the stand point the
walk would have ended on and lets the director `_reach_beat()` — the same call arriving makes,
with the same staging and the same close-up.

---

## 6. Tests

`game/tests/cases/test_camera_room_shot.gd` is new and guards the five things this pass could
quietly have broken:

1. every tall prop's top is **named** in the room's fit points (not kept on screen by luck) and
   really lands inside the safe area at all four aspects;
2. both door plaques do too;
3. the forward look-at point **gains** distance rather than costing it, and gains at least 0.25 m
   — so "tidying" `CAMERA_FOCUS_Z` back to zero fails loudly instead of silently losing 11% of
   the scale;
4. the counter close-up is genuinely closer than the room shot, *and* still contains the child;
5. a zero-radius close-up cannot get closer than `FOCUS_MIN_DISTANCE`, and `focus_framing()` may
   only ever **lower** a room's `minDistance`, never raise it.

No existing test was weakened. `test_art_rooms.gd`'s `get_name()` was renamed to `test_name()`,
which is the name `run_tests.gd` actually reads — the case was being listed by its file path.

---

## 7. What still looks wrong, honestly

These are outside this workstream's file ownership and are requests to the Lead:

1. **The HUD text stack covers the character during a close-up.** At 1334×750 the status line,
   the task line, the Thai hint and the assist line occupy the top ~35% of the screen, and the
   close-up puts the child dead centre — so his head is behind the text
   (`c_beat_counter_ipad.png`, `c_beat_counter_iphone.png`). This cannot be fixed from the
   camera: the look-at point is always at screen centre, so raising `chromeInsets.y` only pushes
   the camera back and keeps the overlap. It needs `house_hud.gd` to move the assist line to the
   bottom, or to collapse the stack to two lines. **This is the most visible remaining defect in
   the first ten minutes.**
2. **Choice-row objects float in mid-air.** During a `choose` beat the staged objects hang around
   0.9 m with nothing under them (a blue disc and a shirt beside the wardrobe in Good Morning).
   `scripts/gameplay/**` — object spawner.
3. **A grey translucent ellipse under the character.** Visible in every close-up. It reads as a
   dirty smudge rather than as grounding at this distance; if it is the contact-shadow decal it
   wants the warm `ink`-tinted treatment ART_BIBLE §7 specifies, not grey.
4. **The bathroom's towel and the bedroom plaque overlap in screen space.** Both are on the -X
   wall, 1.1 m apart in Z, and the camera compresses them. Not broken, but untidy; the towel is
   `room_props.gd`.
5. **The suite is a moving target and the total cannot be quoted honestly.** At the start of this
   pass it was 103 cases / 1 failure. Four consecutive runs during this pass reported 111 cases
   with 1, 8, 20 and 54 failures — the count changes between runs because another agent is
   editing `scripts/audio/**`, `scripts/care/**` and `scripts/characters/**` in the same working
   tree while the suite runs. The failing cases are consistently `audio_director`, `baby_avatar`
   and (intermittently) `child_needs`. **Nothing owned by this workstream fails in any run**:
   `art_rooms`,
   `camera_framing`, `camera_activity_focus`, `camera_room_shot`, `room_camera`,
   `house_camera_focus`, `room_transition`, `house_world`, `kitchen` and `house_traversal` all
   pass, and both mission smoke tests pass (`smoke_mission01.gd`, and with `-- snackTime`).
6. **Nothing here has been run on a physical iPad.** Every number and every picture above is from
   a Mac render at the stated resolution.
