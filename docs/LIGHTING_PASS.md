# Lighting pass — the house, and the menu

**Branch:** `feature/overnight-production-candidate` · **Engine:** Godot 4.7.2 · **Not committed.**

Commissioned against `docs/WORLD_POLISH_PASS.md` §8, which measured a lighting problem it did not
own the files to fix. §8's diagnosis was **wrong**, and this document says so with the evidence,
because the wrong diagnosis is written into two other files in this repository and will be
rediscovered otherwise.

Everything below was rendered from the real `scenes/house/house_world.tscn`, at both resolutions,
before and after, through one harness in one run. Every picture was looked at.

---

## 1. The finding: the sun was under the floor

`house_world.tscn` held its key light as

```
transform = Transform3D(0.7826, 0, 0.6225, 0.4769, 0.6428, -0.5995, -0.4001, 0.766, 0.5031, 0, 6, 3)
```

with the comment *"Mid-morning sun from the upper left, in front of the camera: rotation (-50 deg,
-34 deg, 0)"*.

**`Transform3D(...)` takes its nine basis values ROW-major.** Those nine were written as though
they were the x, y and z *axes* — columns. The transpose of a rotation matrix is another perfectly
valid rotation, so the engine did not warn, the scene did not look broken enough to chase, and no
test could see it. Read back live off the running light (`shots_lighting.gd` prints it), the house
was lit from:

| | authored intent (the comment) | what the file actually did |
|---|---|---|
| direction to sun | `(-0.400, 0.766, 0.503)` | **`(0.623, -0.599, 0.503)`** |
| elevation | +50° | **−36.8°** |
| azimuth | −38.5° (screen left) | **+51.1°** (screen right) |

**Elevation −36.8° is a sun 36.8 degrees below the floor, shining upwards.** The consequences,
which match the reported symptoms far better than any fill-light theory:

* every **upward-facing** surface — the floor, the worktop, the table, the bed, the window sill,
  the top of every head and every shoulder — received **zero** key light and sat at flat ambient.
  That is most of the pixels in a three-quarter view looking down.
* every **downward-facing** surface got the full key, the exact inverse of how a room looks, which
  is why nothing had weight.
* the only planes left with any modelling were the walls, and the two the light did reach came out
  at `1.18` and `1.07` in linear light — both above 1.0 — and **clipped to the same near-white**.

Measured on the kitchen at iPad resolution: **24.5% of the BEFORE frame sat at or above 0.97
luminance**. That is the "milky" complaint, as a number.

### What §8 got wrong, and where else it is written down

`WORLD_POLISH_PASS.md` §8 read the same matrix the same wrong way and concluded *"the sun's azimuth
puts its X component negative, so the -X wall never catches it at all"*. The X component was
**+0.623**: the `-X` wall was the **lit** one. `scripts/house/house_layout.gd` carries the same
error in the comment on the bathroom towel — *"it hangs on the -X wall … which the one directional
light never reaches at all"* — and the towel was sized up to compensate for a darkness it was not
in. **Neither of those comments is true and neither has been edited** (both files belong to other
workstreams); they are flagged here so the next person does not trust them.

§8's recommendation to drop ambient to 0.50 and warm it was directionally right and is part of what
follows, but on its own it would have made a badly-lit room dimmer rather than a well-lit one.

One thing no azimuth can fix, and §8 asked for it explicitly: *"a ~20° swing would light both side
walls unequally rather than one not at all."* The two side walls have exactly opposite inner
normals, so one `dot(normal, toSun)` is the negation of the other. **With one directional light,
one side wall is always at pure ambient.** That is geometry, not tuning. What the azimuth really
buys is the ratio between the lit side wall and the back wall.

---

## 2. What changed

Five numbers in `scenes/house/house_world.tscn`, two in `scenes/main/main.tscn`. The same values
live as documented constants in `scripts/house/lighting.gd::AFTER`, and
`tests/cases/test_lighting_house.gd` fails if the two copies ever drift.

| | before | after | why |
|---|---|---|---|
| **sun elevation** | **−36.8°** | **+48°** | above the floor. The whole fix. |
| **sun azimuth** | +51.1° | **+61°** | stays on the same side, so no room's composition flips and the towel wall stays the lit one. The extra 10° widens the gap between the lit side wall and the back wall. |
| **key energy** | 1.12 | **0.61** | exposure, not mood — see below. |
| **key colour** | `#FFF5E5` | **`#FFEEDB`** | `CREAM → PEACH` at 0.22. A mid-morning sun that is a different colour from the surfaces it lands on. |
| **ambient energy** | 0.62 | **0.52** | |
| **ambient colour** | `#FFF6E5` (`cream`) | **`#FFEAD5`** | `CREAM → PEACH` at 0.35. |
| **background void** | `#EBE0CE` | **`#E4D9C7`** | `CREAM → INK` at 0.16. |
| **menu ambient** | `#F5F0E5` @ 0.55 | **`#FFEAD5` @ 0.52** | the menu's fill was a desaturated near-neutral in no part of the palette. |
| **menu key** | `#FFF9EC` @ 1.0 | **`#FFEEDB` @ 0.92** | one colour temperature across the Play button. |

**Key energy 1.12 → 0.61 is not "darker", it is exposure.** With the sun under the floor, only two
planes caught it. Lift it and roughly five times as much surface catches it, so the old energy
would have blown the whole room out. Total energy (key + fill) goes 1.74 → 1.13 and **nothing in
the frame is brighter than it was** — `test_lighting_house.gd` asserts that total never rises.

**Ambient stopped being `cream`**, which is the part §8 was right about and the part that matters
most for the "milky" look. A `cream` fill on `cream` walls is a tautology: it can only ever produce
more cream. `ART_BIBLE.md` §3's rule is *"never darken by reducing value alone — always mix toward
`ink`"*, and mixing the fill toward `peach` is that rule applied to light instead of to paint. The
shaded side of every form now goes **warm** rather than pale. Measured: mean `R−B` across the
kitchen frame goes **+46.8 → +60.0**.

### What was NOT done

* **No second light.** One `DirectionalLight3D`, as §7 requires and two tests now check.
* **Directional shadows stay off.** That was an owner decision taken on a physical iPhone (§7
  amendment, 2026-09-18) and a lighting pass does not get to overturn a device review. The shadow
  settings are still in the scene, unchanged and inert, exactly as the amendment asks.
* **No GI, no SSAO, no SSIL, no SSR, no glow, no fog of any kind, no DOF, no colour-correction, no
  screen-space anything.** `test_lighting_house.gd` greps both scenes for all of them, including
  plain `fog_enabled`, which is not on §7's list but would have been the cheap way to fake depth.
* **No sky-based ambient.** It is the textbook fix for wall separation and it is *not* forbidden by
  §7 — but `test_art_rooms.gd` pins `ambient_light_source = 2` (an explicit colour), that test is
  right, and generating a radiance cubemap is a real mobile cost for a room with no visible sky.

---

## 3. Evidence

All in `docs/shots/`. `_BEFORE` and plain are the **same scene, same rooms, same camera, same
framing, same code path, same run order** — the only difference is the light, applied on top of the
identical world by `Lighting.apply()`. Every dimension below was read back out of the PNG's own
IHDR chunk after writing, by the harness and again independently:

| File | Pixels |
|---|---|
| `light_kitchen_ipad.png` · `light_kitchen_ipad_BEFORE.png` | **1334 × 750** |
| `light_bedroom_ipad.png` · `light_bedroom_ipad_BEFORE.png` | **1334 × 750** |
| `light_focus_buddy_ipad.png` · `light_focus_buddy_ipad_BEFORE.png` | **1334 × 750** |
| `light_bathroom_ipad.png` · `light_bathroom_ipad_BEFORE.png` | **1334 × 750** |
| `light_livingRoom_ipad.png` · `light_livingRoom_ipad_BEFORE.png` | **1334 × 750** |
| `light_menu_ipad.png` · `light_menu_ipad_BEFORE.png` | **1334 × 750** |
| `light_kitchen_iphone.png` · `light_kitchen_iphone_BEFORE.png` | **2340 × 1080** |
| `light_bedroom_iphone.png` · `light_bedroom_iphone_BEFORE.png` | **2340 × 1080** |
| `light_focus_buddy_iphone.png` · `light_focus_buddy_iphone_BEFORE.png` | **2340 × 1080** |
| `light_menu_iphone.png` · `light_menu_iphone_BEFORE.png` | **2340 × 1080** |

Reproduce:

```
Godot --path game --script res://tests/shots_lighting.gd -- before ipad
Godot --path game --script res://tests/shots_lighting.gd -- after  ipad
Godot --path game --script res://tests/shots_lighting.gd -- before iphone
Godot --path game --script res://tests/shots_lighting.gd -- after  iphone
Godot --path game --script res://tests/shots_lighting.gd -- scene  ipad   # the .tscn, untouched
```

`-- scene` applies nothing at all and photographs `house_world.tscn` exactly as authored. It
produces statistics identical to `-- after`, which is how the scene file and `lighting.gd` are
proven to be the same light rather than merely asserted to be.

**`--resolution 2340x1080` is a request, not an instruction** — the window manager clamps it, and
every wide-iPhone shot taken in this repo before `shots_world.gd` fixed it is really 1686 × 935, a
1.80 aspect filed as evidence for a 2.17 one. This harness renders through a `SubViewport` of
exactly the asked-for size, the same technique, and then verifies the file it wrote.

### The numbers

Whole-frame, kitchen, iPad. `clip` is the fraction of pixels at or above 0.97 luminance — the
milkiness number. `warm` is mean `R − B` in sRGB bytes.

| | p05 | p50 | p95 | range | **clip** | **warm** |
|---|---|---|---|---|---|---|
| kitchen BEFORE | 0.547 | 0.757 | 0.994 | 0.447 | **18.8%** | +46.8 |
| kitchen AFTER | 0.501 | 0.738 | 0.871 | 0.370 | **0.1%** | **+60.0** |
| bedroom BEFORE | 0.547 | 0.757 | 0.994 | 0.447 | **17.5%** | +39.4 |
| bedroom AFTER | 0.505 | 0.728 | 0.871 | 0.366 | **0.0%** | **+52.1** |
| bathroom BEFORE | 0.547 | 0.748 | 0.994 | 0.447 | **22.4%** | +41.3 |
| bathroom AFTER | 0.501 | 0.738 | 0.868 | 0.367 | **0.1%** | **+56.2** |
| livingRoom BEFORE | 0.547 | 0.757 | 0.994 | 0.447 | **21.6%** | +49.7 |
| livingRoom AFTER | 0.501 | 0.739 | 0.868 | 0.367 | **0.1%** | **+63.8** |

Note the BEFORE `p95` of `0.994` in **every room**: a fifth of each frame was pinned against the
ceiling, which is why `range` looks larger before than after. It was not range, it was clipping.
The median barely moves (0.757 → 0.738), which is the "do not simply increase overall brightness"
constraint, met in both directions.

### The wall ladder — "adjacent surfaces must read as different planes"

Fixed 70 × 70 px patches on the kitchen iPad frame, identical pixels in both images:

| Surface | BEFORE | AFTER |
|---|---|---|
| `-X` wall, lit | `#FBF9E4` lum **0.943** | `#F1DABB` lum **0.727** |
| back wall | `#CCCFB3` lum **0.610** | `#C4BC9E` lum **0.503** |
| `+X` wall, fill only | `#CEC0A6` lum **0.537** | `#B6A089` lum **0.372** |
| **worktop (up-facing)** | `#BAA48C` lum **0.390** | `#D4B89C` lum **0.509** |
| floor | `#C39B7B` lum **0.367** | `#ECB48D` lum **0.527** |

The single clearest proof the sun was underneath: **BEFORE, the worktop was darker than the wall
behind it (0.390 against 0.537) and darker than the floor was bright.** A horizontal surface in a
lit room cannot be. After, the worktop sits above the wall behind it and just under the floor,
which is what a bench under a window looks like.

The three walls now sit at **0.727 / 0.503 / 0.372**, three clearly separate steps where before the
lit wall was pinned at 0.943 and had nowhere to go. The deepest of them, the fill-only wall, is
`#B6A089` — a warm light beige. Its saturation measures **0.25**, so it is not grey by
`palette.gd::is_grey()`'s own test (threshold 0.06), and nothing anywhere in the frame is near
`#000000`.

### Character readability

`light_focus_buddy_*.png` is the close-up, composed with the director's own
`camera_focus.frame_points()` so it is the shot the child really gets. Both characters are present:
the harness prints each one's world position, `is_visible_in_tree()` and visible mesh count
alongside the two room shots, so "with characters present" is checked rather than assumed — it is
how the missing baby in an earlier pass of these renders was caught.

Before: Little Buddy was lit from below and behind, so her face, her shoulders and the top of her
head — the parts §4 says carry the entire emotional load — were the flattest surfaces on her, and
her skirt was brighter than her face. After, she has a lit side and a warm shaded side across a
rounded volume, the top of her head reads as the top of her head, and the baby beside her reads as
a separate solid object rather than a pale shape on a pale rug.

---

## 4. Performance

**The runtime cost of this pass is zero, and that is countable rather than argued:**

* no node added to any scene, in either file;
* no `MeshInstance3D`, no material, no texture, no transparent surface;
* still exactly **one** `DirectionalLight3D`, with `shadow_enabled = false` — so no shadow map, no
  second geometry pass, no `directional_shadow_max_distance` traversal;
* every changed value is an `Environment` scalar or colour, or the light's basis. They are shader
  uniforms. They do not scale with scene complexity.

`light_angular_distance` 1.2 → 2.4 widens the sun disc so the terminator across the characters'
rounded volumes is softer. With shadows off this is a lighting-model constant only and costs
nothing; it would cost something if shadows were ever re-enabled, and it is called out here so that
whoever does that knows it is there.

**Nothing in this document has been run on a physical iPad or iPhone.** Every number and every
picture is a Mac render (Metal 4.0, Forward Mobile, Apple M4) at the stated resolution.

---

## 5. Two bugs found on the way, in files this workstream does not own

### a. The bedroom builds no geometry at all — a live regression, in the shipping path

As the working tree stands, `scripts/care/child_actor.gd::_ready()` reaches `_place_bubble()` →
`_find_caregiver()` → `house_world.gd::get_character()`, which lazily calls `build_world()` **while
the bedroom node is still setting up its own children**. Godot refuses `add_child()` on a node in
that state, so `room.gd::build()` has both of its `add_child()` calls rejected, marks itself
`_built`, and then fills a `Geometry` node that is parented to nothing:

```
ERROR: Parent node is busy setting up children, `add_child()` failed.
   [0] build (res://scripts/house/room.gd:234)
   [1] _collect_rooms (res://scripts/house/house_world.gd:303)
   [2] build_world (res://scripts/house/house_world.gd:261)
   [3] get_character (res://scripts/house/house_world.gd:727)
   [4] _find_caregiver (res://scripts/care/child_actor.gd:551)
   ...
   [9] _ready (res://scripts/care/child_actor.gd:128)
```

**The bedroom renders as an empty cream void with two characters floating in it.** This is not a
harness artefact: `tests/smoke_mission01.gd` prints the same two errors, and that is the real game
path. It is *not* caught by the test suite, which builds rooms directly rather than through scene
instantiation.

`child_actor.gd` is being edited concurrently by another workstream and was not touched here. The
benchmark works around it in `shots_lighting.gd::_repair_rooms()` by re-parenting the orphaned
`Geometry`/`Targets` nodes — the real ones, built by the real code, so the photograph is still of
the real room. **The fix belongs in `child_actor.gd`** (do not call into the world from `_ready()`;
defer it) **or in `house_world.gd`** (do not build lazily from a getter).

### b. The "grey ellipse under the character" is not a contact shadow

The brief asked whether the grey translucent ellipse under Little Buddy could be given §7's warm
`ink` tint. It is **not** a contact shadow and there is no contact-shadow decal anywhere in this
project. It is the **beat marker** — the "stand here" disc the level director draws:

```
game/scripts/gameplay/house_stage.gd:217
const BEAT_MARKER_COLOR: Color = Color(0.66, 0.90, 0.81, 0.42)   # mint, 42% alpha
```

It is authored as `mint`, correctly. It *reads* grey because 42% alpha over a pale floor under a
blown-out room left almost no colour in it. Under the corrected light it reads more clearly as
mint, and it is still the weakest element in the frame. `scripts/gameplay/**` is outside this
workstream's file ownership, so it was not changed. The second, larger pale ring at bottom-left of
every shot is the virtual joystick (`scripts/input/virtual_joystick.gd`), also not ours.

**On contact shadows generally, and why none were added:** §7's amendment names contact-shadow
decals as the sanctioned mitigation for floaty objects, but §10's frame budget sets transparent
surfaces at target **0** and hard ceiling **0**, and the floor under the character already carries
two translucent discs (the beat marker and `TapRipple`). A third overlapping translucent ellipse in
exactly that spot would deepen the smudge the brief is complaining about, not fix it. The correct
order of work is: **re-tint the existing marker toward warm `ink` first** (one constant, one file,
zero new draw calls), and only then decide whether anything still floats. Lifting the sun above the
floor has already done most of that job — props now have a lit top and a shaded base, which is what
reads as weight.

---

## 6. Validation

```
Godot --headless --path game --script res://tests/run_tests.gd
  PASS - 120 case(s), 0 failure(s)

Godot --headless --path game --script res://tests/smoke_mission01.gd
  SMOKE PASS -- Mission 01 played end to end in the real house.  (7 beats, 3/3 stars)

Godot --headless --path game --script res://tests/smoke_mission01.gd -- snackTime
  SMOKE PASS -- Mission 01 played end to end in the real house.  (8 beats, 3/3 stars)
```

The suite stood at 116 cases when this pass began and is at 120 because other workstreams added
three and this one added `test_lighting_house.gd`. **No existing test was weakened, relaxed or
deleted** — in particular `test_art_rooms.gd`'s one-light, shadows-off, no-forbidden-effects and
explicit-ambient assertions all still pass unchanged, and the new case deliberately re-asserts the
same forbidden list over both scenes rather than replacing it.

The new case exists because none of the old ones could see this bug: they counted lights and
checked flags, and a transposed rotation passes every one of those. It asserts the sun's
**direction** instead — above the horizon, floor better lit than any wall, and a real value step
between the lit side wall and the back wall — plus that the scene file and `lighting.gd` still
agree, that the fill is warmer than the key, and that total energy never goes up.

---

## 7. What still looks wrong, honestly

1. **The beat marker and the joystick ring** (§5b) are now the two palest, least intentional shapes
   in every frame. Not this workstream's files.
2. **One side wall is always at pure ambient.** It is geometry (§1), not a setting. The only real
   answers are a second light (forbidden), sky-based ambient (blocked by `test_art_rooms.gd` and
   not free on mobile), or accepting it — which is what a doll's-house room lit by one window does
   anyway.
3. **The `+X` wall is now the deepest large field in the house** at luminance 0.372. It is warm and
   it is not grey, but it is the value most likely to come back from a device review: an iPad in
   sunlight will flatten it further. It is one number (`ambientEnergy`) away from being lifted.
4. **The menu is only colour-matched, not re-lit.** Its sun is correct and above the horizon
   (elevation 51.3°, azimuth +34.0° — that matrix was authored right), and its shadows are still
   on, because its shadow falls on one large open plane rather than across pastel walls and the §7
   amendment was about the latter. It was rendered before and after to prove nothing regressed; it
   was not otherwise touched.
5. **`WORLD_POLISH_PASS.md` §8 and `house_layout.gd`'s towel comment are still wrong** and still in
   the repository (§1). Whoever owns those files should correct them.
6. **Nothing here has been run on a physical device.**
