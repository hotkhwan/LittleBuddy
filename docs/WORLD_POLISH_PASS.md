# World polish — kitchen and nursery

**Branch:** `feature/overnight-production-candidate` · **Engine:** Godot 4.7.2 · **Not committed.**

Builds on `docs/WORLD_CAMERA_PASS.md`; nothing that pass established was undone. The camera, the
plaque size, the sink/tap/hob/wall-cupboard decision and the nursery's cloud are all still here —
this pass keeps the ideas and fixes the execution, which in four places was not a taste problem
but a bug.

Every claim below is from a render of the real `scenes/house/house_world.tscn`, with the real
`kitchen_state.gd` driven through the real verbs, at both resolutions the brief names. Every one
of them was looked at.

---

## 1. The three defects that were bugs, not taste

### a. The bowl and the spoon were floating in mid-air, in the first frame of the kitchen

`kitchen_view.gd::_anchor()` computed one `inside` position for every station: proud of the front
face, at `size.y * 0.16` above the centre. On the **fridge** that is the open doorway and it is
right. On the **counter** — which has no door, so its contents are drawn all the time — it put the
bowl and the spoon **0.59 m up and 0.30 m out in front of the cabinet doors, resting on nothing.**

This is the brief's *"no objects floating in mid-air"*, and it was in the room before the child
touched anything (`world_kitchen_ipad_BEFORE.png`, above the middle cabinet door).

A station that does not open now stands its contents **on its top**, and the counter gets an
authored two-row plan (§3).

### b. The fridge did not look open when it was open

`room_props.gd` draws the fridge with its door **already painted on it** — two pale panels and a
freezer line on the front face — and `kitchen_view.gd` then hangs a second, real, hinged door in
front of that. Swinging the real one open therefore revealed the painted one underneath. The only
difference between an open fridge and a closed one was three small items apparently stuck to its
front, at a camera distance of 4.3 m.

Opening it now builds a **lining**: a dusty-blue cavity face with two cream shelves, standing
proud of the front (the fridge body is a solid mesh, so anything modelled *behind* its front face
is simply occluded — that is the same mistake that made the food invisible in the first place).
Two things come out of one change: the fridge visibly opens, and the food stops floating, because
the shelf is really underneath it.

Compare `world_kitchen_open_ipad_BEFORE.png` with `world_kitchen_open_ipad.png`.

### c. The carried item was stuck to her tummy

A fixed `(0, 0.62, -0.26)` in her own space is chest height with both arms at her sides: the bottle
intersected her dress and read as attached to her, not carried (`world_carry_ipad_BEFORE.png`).

The shipped character is a skinned GLB with a 24-bone rig, so the hand is a bone. The item now
follows `RightHand` every frame — **position only**, never rotation, because the wrist rolls
through the walk cycle and a bottle that rolls with it reads as dropped. Two extra matrix
multiplies while something is carried; a character with no skeleton keeps the old offset.

Two further corrections fell out of doing it:

* item meshes are authored **standing on their own origin** (§6, "pivot at base centre"), so
  hanging one at a hand put the whole of it *above* her fist. It is now dropped by half its own
  height, measured off the mesh's `AABB` rather than guessed per shape;
* `HAND_SCALE` was **1.55**, which is a 0.41 m bottle on a 1 m child — fine while it floated in
  front of her, absurd once it was in her hand. It is **1.3**.

---

## 2. The kitchen now reads as a kitchen

| | Before | After |
|---|---|---|
| Sink | far-left corner, under the wall units | **under the window**, where a sink is |
| Hob | middle of the worktop, in the drop zone | far left |
| Drop zone | unmarked cream worktop | a **wooden prep board** |
| Between worktop and wall units | bare cream wall | a **tiled splashback** |
| Wall units | a flat slab with two paler rectangles and two invisible knobs | carcass with a visible **underside lip**, doors, **bar handles** |
| Table | bare | a **placemat**, laid where a dish is served |

The prep board earns its place twice and is the single biggest readability win in the room.
`kitchen_view.gd` puts a carried item down at `WORKTOP_BOARD_X`, so it is the visible answer to
*"where does this go?"* — **and** it is the one warm dark field on a cream worktop in front of a
cream wall. Measured on the iPad render, a banana on bare worktop was a pale yellow sliver; on the
board it is the first thing the eye lands on (`world_kitchen_counter_ipad_BEFORE.png` vs
`world_kitchen_counter_ipad.png`).

**Ingredients are also drawn 1.2× on a surface** (`SURFACE_SCALE`). The world model is untouched;
only the drawing grows. The brief's test is "a child must be able to spot the bottle instantly",
and ~30 px of pale yellow is not that.

### The worktop is now a plan, not two files guessing

The counter is the one shared surface in the house: `room.gd` draws the fixtures, `kitchen_view.gd`
stands ingredients on it. Those numbers now live once, in `house_layout.gd` under `WORKTOP_*`, and
`test_kitchen_view_placement.gd` measures the clearances (§5). One of them was already wrong when
the test was first run: the sink at `x = -0.10` **hung 2 cm off the end of the bench**. It is
-0.13.

Two rows, and that is what stops the worktop reading as a jumble: what *lives* on the counter
stands at the back against the splashback; what the child is *working on* sits at the front on the
board.

---

## 3. Nursery

* **Three sparkles** beside the cloud, in `STAR_EARNED` — the one warm note on a wall that was
  otherwise entirely the room's own lavender and blue. They are crossed lozenges, not discs: drawn
  as discs (first attempt, looked at) they read as three yellow dots, and the kit has no
  five-point star outline.
* **The basket is soft pink.** `deep(lavender)` rendered as a grey-mauve pail and was, cold, the
  least appealing object in the house — a bin standing next to a cot. §3 gives the nursery
  `softPink` as its dominant.

## 4. All four rooms — the rug

Each rug was one flat plate of the room's accent: a 2 m field of saturated mint or dusty blue,
the largest single colour in the shot, competing with the child standing on it. It is now a
**border plus a paler field**. That buys two things for ~90 triangles: the strongest value goes
back to where the eye should go (her, and whatever she is carrying), and a rounded rectangle of
flat colour on floorboards stops reading as spilt paint.

Verified not to have regressed the two rooms this pass was not about:
`world_room_bathroom_*.png`, `world_room_livingRoom_*.png`.

---

## 5. Tests

`game/tests/cases/test_kitchen_view_placement.gd` is new. No existing test was weakened; the suite
is **116 cases, 0 failures**, up from 113 at the start of this pass (one case is mine, one is
another workstream's).

It guards the five rules whose violation is a *number* rather than a judgement, and every one of
them was a real defect in the build before it existed:

1. nothing rests on thin air — every station's drop point is on the surface it claims, and the
   counter's own contents are on the worktop rather than in front of the cupboard doors;
2. the prep board is really under what is put on it, and does not hang off the counter — the board
   and the ingredient are placed from two different files;
3. the hob, the sink and the two resident ingredients fit on one 1.8 m plank with clearance;
4. the fridge's contents are in **front** of its front face (not inside a solid mesh) and not so
   far proud that they are food floating in front of a fridge;
5. a carried item hangs from its middle, for every shape the kitchen has, and `HAND_SCALE` stays
   inside 1.0–1.45.

Mutation-checked rather than assumed: widening `WORKTOP_SPREAD` to 0.40 fails rule 3 loudly with
the overlap in metres.

**Also confirmed green:** `res://tests/smoke_mission01.gd` and the same with `-- snackTime`, and
`game/tests/shots_kitchen.gd` exits 0 with all nine steps applied before they were photographed.

---

## 6. Triangles

Measured, per room, from `room.count_triangles()`. Ceiling is 30,000 per room (§10); the target
is ~18,000.

| Room | Before | After | Δ |
|---|---|---|---|
| bedroom (nursery) | 12,264 | **13,164** | +900 |
| bathroom | 9,704 | **9,860** | +156 |
| livingRoom | 11,244 | **11,400** | +156 |
| kitchen | 10,252 | **11,032** | +780 |
| **total** | 43,464 | **45,456** | +1,992 |

+4.6%, and the worst room is at **44% of its ceiling**. Draw calls — the metric §10 says to watch —
are **unchanged**: everything added here goes into the existing shell `SurfaceTool`, so it is still
one mesh. The fridge lining is the only new `MeshInstance3D` and it exists only while the fridge is
open.

**No new colliders and no new touch targets.** Every fixture, the board, the placemat, the
splashback, the wall units, the sparkles and the fridge lining sit inside a collider that already
existed (the counter's 1.8 × 0.6 m box, the table's, the fridge's) or on a wall. A tap anywhere on
the worktop still lands on `kitchen.counter` — one generous target, not five small ones. The
committed navigation meshes are untouched and nothing was re-baked.

---

## 7. Evidence

All in `docs/shots/`, `_BEFORE` and plain being the same scene, same camera, same HUD build.

| File | What |
|---|---|
| `world_kitchen_{ipad,iphone}.png` | the kitchen as the child finds it |
| `world_kitchen_open_{ipad,iphone}.png` | fridge open, food on the shelf |
| `world_kitchen_counter_{ipad,iphone}.png` | banana on the board, bottle in hand, fridge open |
| `world_carry_{ipad,iphone}.png` | the beat close-up — where a floating held item shows |
| `world_nursery_{ipad,iphone}.png`, `world_nursery_focus_*.png` | the nursery |
| `world_room_{bathroom,livingRoom}_*.png` | the two rooms this pass was not about |

Reproduce:

```
Godot --path game --resolution 1334x750 --script res://tests/shots_world.gd -- polish ipad
Godot --path game --resolution 1334x750 --script res://tests/shots_world.gd -- polish iphone 2340x1080
```

### A harness bug found on the way, and a measurement one

* The fridge door is **tweened** (`DOOR_SWING_SEC = 0.32`). A shot taken on the frame after
  `set_open()` photographs a *closed* fridge and files it as evidence that the fridge opens. The
  first `world_kitchen_open_ipad_BEFORE.png` did exactly that. The polish set now settles first.
* `--resolution 2340x1080` is a **request**, not an instruction: the window manager clamps it to
  the display, and every "wide iPhone" shot in this repository — including `c_room_*_iphone.png`
  from the camera pass — is really **1686 × 935**, a 1.80 aspect filed as evidence for a 2.17 one.
  That is not a rounding error: `camera_framing.solve()` fits its distance from the aspect ratio,
  so the shot being judged was not the shot the device gets. The polish set now hosts the world in
  a `SubViewport` of exactly the asked-for size and photographs its texture, so
  `world_*_iphone.png` really is 2340 × 1080. **The camera pass's iPhone numbers should be re-taken
  this way before they are trusted.**

---

## 8. What still looks wrong, honestly

1. **The lighting is unchanged, and it is the biggest remaining gap.** The brief asked for warmth
   and allowed "a warmer light colour, better angle, and ambient/environment tuning". Both the one
   `DirectionalLight3D` and the `WorldEnvironment` live in `scenes/house/house_world.tscn`, which
   is **not in this workstream's file ownership** — and the `WorldCamera` is in the same file, so
   the camera workstream is very likely editing it. I did not touch it. The recommendation, for
   whoever owns it, measured against these renders:

   * `ambient_light_color` is `#FFF6E5` at energy **0.62** and `light_color` is `#FFF5E5` at
     **1.12**. Against `cream` walls (0.96 luminance) that lands the whole room in a narrow, very
     high-key band — the "milky" quality visible in every shot above. Dropping ambient to ~**0.50**
     and warming it toward `peach` (~`#FFEBD8`) while leaving the key light alone would widen the
     value range and warm the shaded sides without breaking §7 (still one light, no GI, no post).
   * The sun's azimuth puts its X component negative, so the **-X wall never catches it at all**
     (the bathroom towel comment in `house_layout.gd` already records this). A ~20° swing would
     light both side walls unequally rather than one not at all, which is most of what makes a
     one-light scene read as sunlit.

   **Everything achievable in albedo has been done** — the palette is locked by `test_art_rooms.gd`
   to the seven tokens and their two documented steps, and that test is right, so "make the wood
   richer" is not available from here.

2. **The grey translucent ellipse under the character** is still there and still grey (visible in
   every shot, bottom-left and under her feet). The camera pass reported it; it is not in this
   workstream's files either. §7's amendment specifies a **warm `ink`-tinted** contact decal.

3. **The living room's `book` lines up with her left hand** at the default spawn and reads, at a
   glance, as a second thing she is carrying (`world_room_livingRoom_ipad.png`). It is the floor
   book at `(0.3, 0.08, 0.8)` seen past her hip — present in the BEFORE shot too, so not a
   regression, but `house_layout.gd` could move it ~0.3 m and I did not, because it is an activity
   target with an authored stand point and a baked navmesh around it.

4. **The kitchen's right-hand dressing stool** sits hard against the doorway and reads as being in
   the way. It is pinned there by `DRESSING_RIGHT`, whose numbers are derived from the navigation
   bake's corner probes (`room.gd` documents the derivation) — moving it means a re-bake, which
   this workstream cannot do.

5. **The table is still the emptiest large object in the kitchen.** Chairs would fix it and cannot
   be added: visual-only chairs would be walked through, and real ones need a navmesh re-bake.

6. **Nothing here has been run on a physical iPad.** Every number and every picture is a Mac render
   at the stated resolution.
