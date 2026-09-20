# Look pass — camera, materials, lighting

**Branch:** `feature/overnight-production-candidate` · **Engine:** Godot 4.7.2 · **Not committed.**

Priority 7 of the sprint: the layer that decides whether all the other art reads. Commissioned on
top of `docs/LIGHTING_PASS.md`, which had already found and fixed a sun that was 36.8° *below the
floor*, and `docs/WORLD_CAMERA_PASS.md` / `docs/HUD_PRESENTATION_PASS.md`, which had tightened the
room shot and made the HUD read the camera.

Everything below was rendered from the real `scenes/house/house_world.tscn` and
`scenes/main/main.tscn`, at 1334×750 and at a true 2340×1080, before and after, through one harness.
**Every image was opened and looked at.** Three other agents were editing the rooms, the props and
both characters in the same working tree while this ran; where that matters it is said so.

---

## 1. The house's light was already right. Here is the proof, and the alternative that was rejected

**No house-light value was changed by this pass.** That is a finding, not an omission, and the
brief asked for it to be judged rather than assumed.

The brief's item 1 was `LIGHTING_PASS.md` §7.3: the `+X` wall sits at screen luminance **0.372**,
"the value most likely to come back from a device review … one number (`ambientEnergy`) away from
being lifted". So it was lifted, rendered and measured, and it is now a documented constant —
`scripts/house/lighting.gd::LIFTED_FILL` — so the rejection cannot be quietly re-proposed.

The lift is `ambient 0.52 → 0.58`, `key 0.61 → 0.55`, so **total energy is unchanged at 1.13** and
the "energy may never rise" assertion still holds.

| plane (linear) | **ships** 0.52 / 0.61 | lifted 0.58 / 0.55 |
|---|---|---|
| floor, up-facing | 0.973 | **0.989** — 0.011 from clipping |
| `-X` wall, lit | 0.877 | 0.902 |
| back wall | 0.718 | 0.758 |
| `+X` wall, fill only | 0.520 | 0.580 |
| **floor : shaded wall** | **1.87** | **1.71** |

Whole-frame, kitchen, iPad: `p05` 0.501 → 0.526, `p95` 0.872 → 0.881, `range` **0.371 → 0.354**.

**Verdict: rejected.** It shrinks the frame's whole contrast range by 5% and the floor-to-shaded-wall
ratio by 9%, to lift the darkest large field by one step — and it puts the brightest large field at
0.989, which leaves nothing at all for a white prop standing on the floor in front of it. Looked at
(`alt_kitchen_ipad.png` against `look_kitchen_ipad.png`), the rooms read flatter, and the first
thing to go is the corner between the back wall and the shaded wall, which is the only corner a
single directional light can draw on that side.

The `+X` wall at 0.372 is **not grey** (saturation 0.25, `#B6A089`), is nowhere near `#000000`, and
is the frame's only deep value. If a device review in sunlight still rejects it, the right answer is
a device review, not a pre-emptive flattening taken on a Mac.

**Item 2 of the brief — one side wall always at pure ambient — is confirmed as geometry and left
alone.** The ratio 0.877 / 0.718 / 0.520 across the lit wall, the back wall and the fill wall is
three clean steps, and in every one of the eight room renders the corners read. That is what was
asked: not "can both side walls be lit" (they cannot, with one light) but "does the ratio read as
depth". It does.

### The docstring drift that was fixed

`scripts/house/lighting.gd`'s prose quoted **key 0.72 and ambient 0.44** — values from an earlier
draft of that pass — while the constants ten lines below it, the scene file and the shipped renders
all say **0.61 and 0.52**. The prose is corrected against the constants. Nothing executable changed.

---

## 2. The menu's shadows are off — the one §7 violation still shipping

`main.tscn` had `shadow_enabled = true`, `shadow_opacity = 0.45`. `ART_BIBLE.md` §7's amendment of
2026-09-18 turned the *house's* directional shadows off after an owner review on a physical iPhone:
at this camera pitch the props threw hard diagonal shapes that read as an artefact rather than as
grounding. The menu was exempted on the argument that its shadow falls on *"one large open plane
rather than across pastel walls"*.

**Rendered and looked at, that argument does not survive the picture.** The shadow the menu actually
casts is Aliz's own: in `look_menu_ipad_BEFORE.png` it is a hard grey-green diagonal slab lying
across the peach rug, **her own legs** and the baby standing beside her; in
`look_menu_iphone_BEFORE.png` it is a dark band running a third of the way across the ground. It is
the same artefact the amendment removed, on **the first screen a child ever sees**, at the largest
on-screen size any character reaches in this game.

Measured, same scene, same camera, the shadow the only difference:

| | p05 | p50 | p95 | range |
|---|---|---|---|---|
| menu, iPad, shadows on | 0.532 | 0.804 | 0.960 | 0.428 |
| menu, iPad, **off** | **0.547** | 0.804 | 0.960 | **0.413** |
| menu, iPhone, shadows on | 0.687 | 0.782 | 0.960 | 0.273 |
| menu, iPhone, **off** | **0.719** | 0.786 | 0.960 | **0.241** |

The median does not move at all and the highlights do not move at all: the entire difference is the
darkest 5%, which is the shadow and nothing else. Both characters still read as standing on the rug
— the rug's own ellipse and the ground's value step do that work, and they did it in the house
already.

**This is the one measurable performance change in the pass, and it is a saving.** A directional
shadow map plus its depth-only geometry pass is removed from every frame of the menu. Nothing was
enabled anywhere, so no cost is added and none needed justifying.

The shadow settings are **kept in the scene, unchanged and inert**, exactly as the amendment asks of
the house. Re-enabling is one character.

### Materials

The only materials this workstream owns are `main.tscn`'s five `StandardMaterial3D` sub-resources
(floor, rug, cloud, and three balls). Audited against §7: roughness **0.9 – 1.0**, metallic **0.0**,
no normal maps, no alpha, no emission, one material per object. All compliant; none changed. The
room and prop materials belong to other workstreams and were not touched.

---

## 3. Camera — and the one number nobody had measured

`shots_lighting.gd` gained a `-- frame` mode that takes no pictures at all. It prints, for every room
at every shipped aspect, the solved distance, **which constraint produced it**, the world point that
did it, and `fillX` / `fillY`: the fraction of the usable (post-inset) window the fit points really
span on each axis. Judging composition from a screenshot is how 5.13 m survived as long as it did —
the eye cannot tell a camera that is 8% too far back from a room that is 8% too small.

The first run said something the previous two camera passes had not noticed:

> **Every shot in this game, in every room, at both shipped aspects, is bound by the VERTICAL
> constraint. The horizontal one is never within 6% of binding.**

The whole system is a vertical fit. And a camera pitched 32° down at the centre of a box spends its
distance asymmetrically: the near edge falls a long way below the look-at point while the far edge
rises only a little above it. `HouseLayout.CAMERA_FOCUS_Z = 0.42` already corrects that for the
**room** shot. `focus_framing()` did not correct it for the **close-up**, and the consequence was
not subtle:

| shot | before | after |
|---|---|---|
| room, kitchen | 4.30 m | 4.30 m (unchanged) |
| room, bedroom | 4.56 m | 4.56 m (unchanged) |
| room, bathroom / livingRoom | 4.23 m | 4.23 m (unchanged) |
| **close-up, `choose` beat (r = 1.88 m)** | **4.87 m** | **4.03 m** |
| close-up, `goAndDo` beat (r = 0.90 m) | 2.77 m | 2.80 m |

**A `choose` beat's "close-up" stood further out than the whole-room shot it interrupted** — 4.87 m
against 4.23–4.56 m. The camera moved *in* on the activity by moving 7 to 15% further *away*. It is
now 4.03 m, closer than every room shot, and `fillX` at 1334×750 goes 0.77 → **0.93**.

`camera_framing.FOCUS_LOOKAHEAD = 0.21` is the fix, and it is not a new taste: it is
`CAMERA_FOCUS_Z / 2.0` — the room's own bias divided by the room's own half-depth — so a close-up
and the room shot it interrupts are now composed by one rule instead of two. It is a fraction rather
than a distance because the box's size is what varies.

**The `bounds` are untouched.** Only the aim slides. So everything `camera_focus.gd` guaranteed to
be on screen is still on screen, and `room_camera.get_focus_radius()` — which reads `bounds`, and
which the HUD reads its presentation mode from — returns exactly what it returned before.
`test_hud_presentation.gd` passes unchanged and the 1.30 m threshold has not moved.

### The bug the render found, which is the more important half

The first render at the new distance **cut the top of Aliz's head off.**

`DEFAULT_HEADROOM` is 1.0 m and its comment says *"the toddler is ~0.85 m"*. That describes the
**baby**. The character the child drives is Aliz, whose collision capsule in `house_world.tscn` is
`height = 1.5`. The solver believed it had a metre of air above her head when it had **0.12 in
normalised device coordinates**: even at the shipping 2.77 m, the top of her hair sat at ndc_y
**0.88**, past the top safe-area limit of 0.80 and a hand's breadth from the edge of the screen. It
had survived only because nothing had ever moved the camera in.

The honest repair is not to back the camera off again but to stop the solver believing a false
height. `focus_framing()` now names **one extra fit point** — the box's centre, at
`CLOSE_UP_SUBJECT_HEIGHT = 1.55 m` (the capsule's 1.5 m plus five centimetres).

Two things were tried first and are recorded so they are not retried:

* **Raising `DEFAULT_HEADROOM` 1.0 → 1.55.** It demands that much air above all **four** corners of
  the box, most of which is empty floor, and the far pair then bind: the 0.90 m close-up goes to
  **3.26 m**, wider than it has ever been, with `fillX` falling to 0.44 on a phone. Raising the
  headroom to protect a head makes the shot wider than the shot that was cropping it.
* **`CLOSE_UP_SUBJECT_HEIGHT = 1.50`** (the bare capsule). 2.66 m, and her hair lands at ndc_y 0.96
  — 15 px from the top edge at 1334×750. On screen, but not with a margin anyone should ship.

At 1.55 m the tight close-up solves to **2.80 m against the 2.77 m it ships at**: it does not move
the shot. That is the honest result — **the tight close-up cannot be tightened at all.** The 0.41 m
of standoff the near-bottom corner was wasting turns out to be exactly where the 16 cm of Aliz's
head was already going.

So the value of naming her is not scale. It is that "the player character's head is on screen during
a close-up" was true only because two unrelated numbers happened to cancel, and the next person to
move the camera in by 15 cm would have cropped her **with every test still green**. It is now a
constraint.

### The wide-aspect slack, which is geometry and was left alone

At 2.167:1 the room shots read `fillX` 0.69 – 0.78: the room sits as an island with void down both
sides. `KEEP_HEIGHT` fixes the vertical field of view, the room's depth runs out of vertical room
first, and the horizontal is then over-supplied. The only ways to spend that slack are to crop the
room's depth or to change the pitch, and both change the composition on *every* device to flatter
one. Not taken; reported.

---

## 4. Evidence

All in `docs/shots/`. Every dimension below was read back out of the PNG's own IHDR **after
writing**, by the harness, and printed — `--resolution 2340x1080` is a request the window manager
clamps to 1686×935, and since `solve()` fits the distance *from* the aspect, a 1.80 frame filed as
evidence for a 2.17 one is a different composition, not a rounding error. Everything here is
rendered through a `SubViewport` of exactly the stated size.

| File | Pixels | What differs from `_BEFORE` |
|---|---|---|
| `look_{kitchen,bedroom,bathroom,livingRoom}_ipad.png` | **1334 × 750** | nothing — the room shot is unchanged by this pass |
| `look_{kitchen,bedroom,bathroom,livingRoom}_iphone.png` | **2340 × 1080** | nothing |
| `look_focus_buddy_ipad.png` | **1334 × 750** | the close-up: 2.77 → 2.80 m, head now a named constraint |
| `look_focus_buddy_iphone.png` | **2340 × 1080** | as above |
| `look_menu_ipad.png` | **1334 × 750** | **shadows off** |
| `look_menu_iphone.png` | **2340 × 1080** | **shadows off** |
| `look_*_BEFORE.png` (same ten) | same | the state at the start of this pass |
| `alt_*_ipad.png` (six) | **1334 × 750** | the **rejected** lifted fill (§1) |

Reproduce:

```
Godot --path game --script res://tests/shots_lighting.gd -- frame                # no pictures, just the camera
Godot --path game --script res://tests/shots_lighting.gd -- previous ipad   look # the pass's BEFORE
Godot --path game --script res://tests/shots_lighting.gd -- after    ipad   look
Godot --path game --script res://tests/shots_lighting.gd -- previous iphone look
Godot --path game --script res://tests/shots_lighting.gd -- after    iphone look
Godot --path game --script res://tests/shots_lighting.gd -- lift     ipad   alt  # the rejected alternative
Godot --path game --script res://tests/shots_lighting.gd -- scene    ipad        # the .tscn, untouched
```

`previous` is a genuine controlled pair rather than two builds: it rebuilds the **old** close-up
framing (box centred, aim at its centre, no subject point) in the harness and hands it to
`frame_room()`, and it restores the menu's shadow on the live light. Same scene, same run, same
frame order.

Whole-frame numbers, `clip` = fraction at or above 0.97 luminance, `warm` = mean `R − B` in sRGB
bytes. The four room shots are **identical before and after** because nothing this pass changed
touches them — which is itself the control on the control:

| shot | p05 | p50 | p95 | range | clip | warm |
|---|---|---|---|---|---|---|
| kitchen, iPad | 0.501 | 0.737 | 0.872 | 0.371 | 0.1% | +58.5 |
| bedroom, iPad | 0.553 | 0.728 | 0.872 | 0.319 | 0.0% | +51.4 |
| bathroom, iPad | 0.501 | 0.738 | 0.868 | 0.367 | 0.1% | +54.0 |
| livingRoom, iPad | 0.501 | 0.738 | 0.871 | 0.370 | 0.1% | +63.2 |
| kitchen, iPhone | 0.550 | 0.738 | 0.871 | 0.321 | 0.0% | +59.2 |
| bedroom, iPhone | 0.561 | 0.727 | 0.867 | 0.306 | 0.0% | +52.8 |
| bathroom, iPhone | 0.550 | 0.738 | 0.868 | 0.318 | 0.1% | +55.0 |
| livingRoom, iPhone | 0.548 | 0.738 | 0.868 | 0.320 | 0.1% | +63.2 |
| close-up, iPad | 0.521 | 0.712 | 0.863 | 0.342 | 0.0% | +51.5 |
| close-up, iPhone | 0.553 | 0.708 | 0.859 | 0.307 | 0.0% | +54.6 |

Every room is warm (`+51` to `+63`), nothing clips, and the deepest 5% sits at 0.50 – 0.56 rather
than against zero. The menu is the one cool frame in the game (`warm −18` on iPhone) and is meant to
be: it is outdoors under a dusty-blue sky, and only its *fill* is matched to the house.

### A harness bug found and fixed on the way

`_menu_shot()` used to `remove_child()` the house before photographing the menu. That fixed an
earlier bug where two `WorldEnvironment` nodes in one `World3D` gave the menu the house's beige fill
— but it did **not** fix the geometry: by the time the house has been through `place_in_room()` and
a close-up, parts of it are parented outside the `HouseWorld` node, so removing the root left the
**bedroom standing in the viewport**, and the menu's own `Camera3D` — which sits at the world
origin, where the bedroom is — photographed it with the menu's buttons neatly on top. That frame
measured `clip = 18.8%` and was filed, briefly, as a menu.

It now frees every child of the viewport, waits for the frees to land, explicitly makes the menu's
camera current, and **prints a `WARN` if more than one root node remains**. The shots above were all
taken after that fix.

---

## 5. Validation

```
Godot --headless --path game --script res://tests/run_tests.gd
  121 case(s), 1 failure -- test_aliz_face.gd, another workstream's, see below

Godot --headless --path game --script res://tests/smoke_mission01.gd
  SMOKE PASS -- Mission 01 played end to end in the real house.

Godot --headless --path game --script res://tests/smoke_mission01.gd -- snackTime
  SMOKE PASS -- Mission 01 played end to end in the real house.
```

**Every case this workstream owns or can affect passes:** `art_rooms`, `camera_framing`,
`camera_activity_focus`, `camera_room_shot`, `house_camera_focus`, `room_camera`, `room_transition`,
`house_world`, `house_traversal`, `hud_presentation`, `lighting_house`.

The suite total is honest but not stable, and the number changes between consecutive runs because
three other agents are editing `scripts/house/**`, `scripts/care/**` and `scripts/characters/**`
while it runs. Over this pass it went **120 → 121 cases**, and `semantic_validation`, `child_needs`
and `ui_palette` each failed and then passed again as half-written files landed. The final run
reads **121 cases, 1 failure**, and that failure is `res://tests/cases/test_aliz_face.gd` — a case
that did not exist when this pass began, in the characters workstream's files. Both mission smokes
pass.

**No test was weakened.** One assertion in `test_camera_framing.gd` had to change, because it
asserted the old behaviour directly:

```gdscript
if Vector3(focus_solution["focus"]).distance_to(target) > 0.0001:
    failures.append("the focused camera does not look at the activity")
```

It is replaced by **three** checks, not none: the slide is exactly `radius * FOCUS_LOOKAHEAD`; it is
along the view direction's horizontal and never sideways or down; and — the part that actually
matters and was never checked at all — **the `bounds` are still centred on the activity**, which is
what `camera_focus.gd` guarantees containment against and what `get_focus_radius()` reports to the
HUD.

### Gate compliance

Re-checked by `test_lighting_house.gd` over **both** scenes, and passing: exactly one
`DirectionalLight3D` each · no `OmniLight3D` / `SpotLight3D` / `ReflectionProbe` / `VoxelGI` /
`LightmapGI` · no SDFGI, SSAO, SSIL, SSR, glow, volumetric fog, plain `fog_enabled`, DOF or
`adjustment_enabled` · `ambient_light_source = 2` (explicit colour, not sky) · total light energy
1.13, unchanged and never raised. No node, mesh, material or transparent surface was added anywhere.
Shadows are now off in **both** scenes rather than one.

---

## 6. What still looks wrong, honestly

1. **`look_focus_buddy_iphone_BEFORE.png` caught a different game state** — the baby had walked and
   a "Nice!" praise line is on screen. The harness re-runs a live level, and `child_actor.gd` is
   being edited by another workstream as this is written. The *framing* in it is the old framing and
   the comparison is valid; the character poses are not a controlled pair. Its iPad twin is clean.
2. **The wide-aspect void** (§3). Geometry, not a bug, and not free to fix.
3. **The beat marker and the joystick ring** are still the two palest, least intentional shapes in
   every frame — the pale ellipses scattered across the rug in every close-up, and the ring at
   bottom-left. `scripts/gameplay/**` and `scripts/input/**`. `LIGHTING_PASS.md` §5b already
   diagnosed the marker as authored `mint` at 42% alpha, not a contact shadow. **Now that there are
   half a dozen of them on the floor at once, this is the most visible remaining defect in a
   close-up**, and it is one constant.
4. **The `+X` wall at 0.372 is still the deepest large field** (§1). Judged and kept, but it has
   still never been seen on a device in sunlight.
5. **One side wall is always at pure ambient.** Geometry. Confirmed, not fixed, cannot be.
6. **`house_layout.gd`'s towel comment still carries the disproved sun diagnosis.** Not this
   workstream's file. `WORLD_POLISH_PASS.md` §8 now carries a correction note at its head.
7. **`DEFAULT_HEADROOM`'s comment is still wrong for the room shot.** It says the character is
   0.85 m; she is 1.5 m. The close-up now names her explicitly, but the *room* shot is still relying
   on the tall props (the 1.80 m wardrobe, the 1.70 m fridge) to bind before she does. They do, in
   all four rooms, at both aspects — but by luck, not by statement. Raising the default was measured
   and costs 0.15 m on three of the four rooms; it is a judgement for whoever owns the room framing.
8. **Nothing here has been run on a physical iPad or iPhone.** Every number and every picture is a
   Mac render (Forward Mobile, Apple M4) at the stated resolution.
