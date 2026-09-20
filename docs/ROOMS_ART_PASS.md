# Room art — bedroom, kitchen, bathroom, living room

**Branch:** `feature/overnight-production-candidate` · **Engine:** Godot 4.7.2 · **Not committed.**

Builds on `docs/WORLD_CAMERA_PASS.md` and `docs/WORLD_POLISH_PASS.md`. Nothing either of those
established was undone: the sink is still under the window, the prep board, the splashback, the
wall units and the placemat are all still there and all still in the same places; the door plaques
are still 0.60 × 0.30 m; the rugs still have a border and a paler field; the nursery still has its
cloud, its charms and its three sparkles.

**Every claim below is from a render of the real `scenes/house/house_world.tscn`, at both shipped
aspects, and every one of them was looked at.** Five things in this pass were built, rendered,
judged wrong and rebuilt; each of those is written down where the code is, because the reason a
choice was rejected is the only thing that stops it being made again.

---

## 1. What changed, in one table

| | Before | After |
|---|---|---|
| **Every window** | a pale blue rectangle in a cream frame on a cream wall | **curtains** on a wooden pole, in the room's accent |
| **Every wainscot** | `deep(dominant)` in all four rooms — a cold slate grey in the bathroom, a grey-mauve in the nursery | the dominant at the step that contrasts with the **floor** (§2 below) |
| **Every rug** | border + plain field | border + field + **six cream spots** |
| Bathroom back wall | one 0.27 m cream mirror disc; nothing else | **tiled band** behind the basin, **five bubbles** over the bath, a 0.31 m mirror framed in mint |
| Bathroom floor | the smallest rug in the house, and bare boards | rug grown to 2.10 × 1.60, plus a **bath mat** where the child stands to use the tub |
| Bathroom towel | 0.88 m, grown to beat a darkness it was never in | **0.74 m**, and the comment corrected (§5) |
| Kitchen units | `light(peach)` doors on a `deep(peach)` carcass under a cream worktop | **`light(mint)` doors**, wall and base, matching the splashback |
| Kitchen splashback | `light(mint)` field behind cream tiles — invisible | `mint` field with `light(mint)` tiles |
| Kitchen hob | a blue plate with two rings on it | a **pan** standing in one of the rings |
| Living-room wall | one 0.50 × 0.40 m frame, cream on cream | a **three-frame gallery** and a **wall clock** |
| Living-room sofa | frame in `deep(peach)` — the exact colour of the wall behind it | frame in `deep(softPink)` |
| Living-room toy box | `softPink`, like the sofa, the shelf, the rug and the curtains | `mint` — which is what `house_layout.gd` always **declared** it to be |
| Both toy boxes | five slabs of flat colour with a knob | a recessed painted panel, a motif and a plinth |
| Nursery bed | a flat slab of `dustyBlue` blanket | five cream spots on the foot half |

Nothing in this pass added a collider, a touch target, a light, a material, a texture, a
transparent surface or a draw call. Nothing moved an activity target, a stand point or a spawn.
The committed navigation meshes are untouched and nothing was re-baked.

## 2. The wainscot, which was the single worst thing in the house

`_build_panelling()` painted the lower 0.70 m of all three walls of every room in
`Palette.deep(dominant)`. The argument for `deep()` is written down in `WORLD_POLISH_PASS` and it is
a good one — **but it is only true in two of the four rooms.** The kitchen and the living room are
dominant-`peach` and the floorboards are `peach`, so a full-strength wainscot is the same value as
the boards in front of it and the room loses its horizon.

In the other two it was a straight loss:

* `deep(dustyBlue)` is a cold slate grey. It was the largest single field of colour in the
  bathroom and it was the one thing in the house that read as an institution rather than as a home
  (`rooms_bathroom_ipad_BEFORE.png`).
* `deep(lavender)` is the same grey-mauve that `WORLD_POLISH_PASS` §3 already rejected for the
  nursery basket — *"cold, the least appealing object in the house"* — and it was wrapped round
  three walls of the baby's room.

The step is now chosen against the floor: a dominant that would disappear into `peach` boards is
deepened, one that already contrasts with them is used at full strength. That is what §3's
room-mood table actually asks for, and both values are §3 tokens or its documented `deep`
derivation either way, so `test_art_rooms.gd` is satisfied honestly rather than worked around.

**It is the biggest single change in the pass and it is four lines of code.**

## 3. Curtains — the one addition that changes every room

The top third of all three walls was an unbroken 1.3 m field of `cream` in every room: the largest
single area in the shot, carrying nothing, with the window sitting in the middle of it as a pale
blue rectangle in a cream frame on a cream wall. That is a hole, not a window.

Three decisions, and each was the alternative's problem — all three found by rendering:

1. **Beside the glass, never over it.** The first pass hung a valance across the window head and
   two panels over the frame. Both rooms came back with the window looking like a *picture frame in
   the accent colour*: the cloth ringed the glass on three sides and the cream frame stopped
   reading at all. There is now no valance, the panels stop level with the glass, and a wooden pole
   above the head does the tying-together job without covering anything.
2. **Not the colour of the sky.** §3 gives the bedroom `dustyBlue` as its accent and §5 fixes the
   window sky at `#B8DBED`. Rendered, the nursery's curtains and the pane behind them were a single
   blue field. The nursery hangs its dominant instead. **The test is on hue, and that matters:**
   measured per channel `mint` is 0.117 from the sky and `dustyBlue` is 0.118, so a
   channel-distance rule hung dusty-blue curtains in the bathroom — whose accent is mint — on the
   first run. By hue they are 48° apart.
3. **Three lobes and a scalloped hem, sill length.** A flat rectangle of accent beside a window is
   a poster. The middle lobe stands 14 mm proud, is a step lighter and hangs 45 mm shorter; that
   break is what makes cloth read in a style with no textures and almost no shading.

## 4. The bathroom, which was the plainest room

`mint` is its §3 accent and the only mint anywhere in it was the paler field of the rug. Sink,
bath, towel rail, mirror glass and wainscot were all cream or dusty blue — one hue, two values.

**Tiles have to be a band, and the first version proved it.** Panels went up behind the basin *and*
the bath, each 0.42 m tall and three tiles across, and both came back reading as a grid of squares
hung on a wall. The bath's was worse: the tub stands half a metre proud of the wall it was tiled
against, so its panel floated in the air above it. The kitchen splashback is the same function and
reads correctly for one reason — it is long and low and it sits directly on the worktop. There is
now one band, behind the basin only, much wider than the basin, starting just above the chair rail.

**And the tiles are the field's own `light()` step, not `cream`.** Cream tiles on a cream wall leave
only the grout lines visible, and a panel of mint grout lines with nothing behind it reads as wire
mesh — the bathroom came back looking like it had two racks bolted to the wall.

**The bath wall gets bubbles instead**, which is the better answer for it anyway: 1.0 × 1.3 m of
wall that carried nothing, now carrying five discs on a rising diagonal, each with one cream
catchlight upper-left. They are what the room is *about*, so they reinforce the words the level
teaches; `bubble` is not a word the vocabulary owns (it has `soap`, `water`, `bath`, `clean`, `wet`,
`dry`), so §6's one-object-one-word rule is safe; and the nursery already establishes that a wall in
this house may carry a soft drawn shape.

## 5. The towel, and a wrong diagnosis that had been built into the geometry

`house_layout.gd` carried this comment:

> *the one directional light never reaches [the -X wall] at all (its inner face points +X and the
> sun's X component is negative)*

and the towel had been grown by half again to be legible in that darkness. **The diagnosis was
wrong.** The sun's `Transform3D` basis was transposed, which put it 36.8° *below the floor*, so
nothing in the house was lit by it — not that wall in particular. With the basis fixed the -X wall
catches the sun like every other surface.

The comment is corrected in place, with the real cause recorded, and the towel is back to a
towel-shaped towel: **0.74 m of drop on a 2.2 m wall** rather than 0.88 m. It is still comfortably
the largest soft object on that wall and still measures well over 40 px at 2340 × 1080.

The collider shrinks with it and the navigation bake does not notice: at x = -1.93 the whole prop
lies inside the 0.20 m agent radius already eroded away from the -2.0 m wall, so it has never
contributed a single walkable cell.

## 6. Three more things that were rendered, judged wrong and redone

* **Rug spots were four and in the accent.** A spot the same colour as the border, on that border's
  own `light()` step, has the value of a shadow and none of the shape of one — it read as a hole in
  the rug. And four at the field's corners left the kitchen and the bedroom showing exactly *one*
  visible spot, the rest behind the child, and one lone circle is a mark rather than a pattern.
  Six spots, in `cream`.
* **The gallery's two small frames were `deep()`.** At 0.30 m across, a deepened pastel has no hue
  left in it at this distance; `deep(peach)` and `deep(softPink)` came back as two brown boxes
  beside a pale one, which is not a gallery. They are `mint` and `lavender` now, and the picture
  frame generally is the other way round from before — the mount carries the colour and the subject
  is drawn on it in cream, because a cream mount on a cream wall inside a cream frame leaves
  nothing but a thin outline.
* **The nursery's middle sparkle was at x = -0.66.** With curtains hung, half of it disappeared
  behind the cloth and the rest read as something yellow caught in the hem. It moved to -0.78.

## 7. Triangles and draw calls

Measured from `room.count_triangles()` and `room.count_meshes()` in the same run that took the
screenshots, so a picture and its budget can never be from two different builds. The ceiling is
**30,000 per room** (§10) and the target is ~18,000.

| Room | Before | After | Δ | % of ceiling |
|---|---|---|---|---|
| bedroom | 13,164 | **15,592** | +2,428 | 52% |
| bathroom | 9,860 | **13,668** | +3,808 | 46% |
| livingRoom | 11,400 | **14,940** | +3,540 | 50% |
| kitchen | 11,032 | **13,500** | +2,468 | 45% |
| **total** | 45,456 | **57,700** | +12,244 | — |

+27%, and the worst room is at **52% of its ceiling**. All four rooms are still under §10's
~18,000 *target*, the worst of them by 2.4 k.

**Draw calls — the metric §10 says to watch — are unchanged:**

| Room | Before | After |
|---|---|---|
| bedroom | 10 | **10** |
| bathroom | 9 | **9** |
| livingRoom | 10 | **10** |
| kitchen | 9 | **9** |

Everything added here goes into the shell's existing `SurfaceTool`, or into the furniture mesh or
the storage body it belongs to, so the room is still one shell mesh + three furniture + two doors
(+ one storage, + one floor-dressing mesh). Still one `StandardMaterial3D` for the whole house,
still no textures, no alpha, no emission, no new light.

**No new colliders and no new touch targets.** The curtains, the pole, the tiles, the bubbles, the
gallery, the clock, the pan, the rug spots, the blanket spots and the painted toy-box fronts all
sit either on a wall, inside a collider that already existed (the counter's 1.8 × 0.6 m box, a
storage's own box) or flat on the floor at rug height. A tap anywhere on the worktop still lands on
`kitchen.counter`; a tap anywhere on the toy box still lands on the toy box. The camera's fitted
distance and field of view are **identical** before and after in all four rooms (see §8).

## 8. Evidence

All in `docs/shots/`. `_BEFORE` and plain are the same scene, the same script, the same camera and
the same HUD build, and differ only in the four files this pass owns — the BEFORE set was taken by
restoring those four files to `HEAD` and re-running, so the lighting in both halves of every pair is
the lighting as it stands tonight.

**Every dimension below was read back out of the saved PNG by the harness and printed, not
assumed.**

| File | Size | Aspect |
|---|---|---|
| `rooms_{bedroom,kitchen,bathroom,livingRoom}_ipad_BEFORE.png` | **1334 × 750** | 1.78 |
| `rooms_{bedroom,kitchen,bathroom,livingRoom}_ipad.png` | **1334 × 750** | 1.78 |
| `rooms_{bedroom,kitchen,bathroom,livingRoom}_iphone_BEFORE.png` | **2340 × 1080** | 2.17 |
| `rooms_{bedroom,kitchen,bathroom,livingRoom}_iphone.png` | **2340 × 1080** | 2.17 |

Reproduce:

```
Godot --path game --resolution 1334x750 --script res://tests/shots_rooms.gd -- ipad
Godot --path game --resolution 1334x750 --script res://tests/shots_rooms.gd -- iphone 2340x1080
```

`game/tests/shots_rooms.gd` is new and dev-only. The second argument is the reason it exists:
`--resolution 2340x1080` is a **request**, not an instruction — the window manager clamps it to the
display, and a shot taken that way is really 1686 × 935, a 1.80 aspect filed as evidence for a 2.17
one. `camera_framing.solve()` fits its distance *from* the aspect ratio, so that is a different
composition, not a rounding error. When a frame size is given the world is hosted in a `SubViewport`
of exactly that size and the shot comes from its texture. `shots_world.gd` established this; it is
followed rather than re-invented.

The camera solution is printed per room and is identical in the BEFORE and AFTER runs at both
aspects — bedroom 4.56 m, bathroom 4.23 m, livingRoom 4.23 m, kitchen 4.30 m, fov 52.0, `fits=true`
everywhere. (The distance is the same at 1.78 and at 2.17 because `KEEP_HEIGHT` fixes the vertical
field of view and every room here is bound by a vertical constraint; a wider aspect buys horizontal
field for free.)

The `-- house <out> <roomId>` job on `scenes/spike/shot_harness.tscn` photographs the same rooms and
was used throughout the pass for quick iteration; `shots_rooms.gd` is what the filed evidence came
from, because it reports the triangle count of the room it just photographed.

## 9. Tests

`run_tests.gd`: **121 cases, 0 failures.** **No test was weakened, skipped or edited by this pass**
— `game/tests/cases/` is untouched, and the only new file under `game/tests/` is the dev-only
screenshot script.

(Mid-pass the suite showed one failure, `test_aliz_face` — *"Aliz's mouth is open again"*, a vertex
on the character's face mesh. It was never this workstream's: that case preloads
`scripts/characters/buddy/pink_girl_buddy.gd` and nothing else, and `scripts/characters/**` is
explicitly outside this file ownership. It was green again by the final run, fixed by whoever owns
it.)

Green and specifically relevant: `art_rooms`, `room_camera`, `camera_room_shot`,
`kitchen_view_placement`, `house_traversal`, `house_no_dead_ends`, `childproof_house`,
`house_stage_placement`, `lighting_house`, `ui_palette`.

`art_rooms` passing is the load-bearing one. It pins every named colour in the house to §3's seven
tokens and their two documented derivations, asserts the §10 budgets, asserts that every taught
object still has its own distinct shape, and asserts the bevel and the winding. Every colour
introduced here — the wainscot's new step, the curtain cloth, the tiles, the bubbles, the clock, the
gallery mounts, the spots — is a token or one of its two steps, and the test was left exactly as it
was.

Both mission smokes pass end to end in the real house:

```
Godot --headless --path game --script res://tests/smoke_mission01.gd
Godot --headless --path game --script res://tests/smoke_mission01.gd -- snackTime
```

`imHungry`: 7 beats, 2 care mini-games finished by gesture, hunger 55 → 0, 3/3 stars.
`snackTime`: 8 beats, hunger 55 → 0, 3/3 stars.

## 10. Files changed

| File | Why |
|---|---|
| `game/scripts/house/room.gd` | curtains, wainscot step, rug spots, bathroom fixtures + bubbles, shared `_tiles()`, splashback, kitchen pan, cupboard door colour, gallery wall + clock, painted storage fronts, bathroom rug size, sparkle position |
| `game/scripts/house/room_props.gd` | blanket spots, sofa frame colour, toy-box colour, counter door colour |
| `game/scripts/house/house_layout.gd` | towel size, and the wrong shadow diagnosis corrected |
| `game/tests/shots_rooms.gd` | **new** — the evidence script |
| `docs/ROOMS_ART_PASS.md` | **new** — this |

`game/scripts/house/prop_kit.gd` was read and not changed: everything in this pass is built from
primitives it already had.

## 11. What still looks wrong, honestly

1. **The living room's wainscot is still `deep(peach)`, and it is still the dullest surface in the
   house.** The rule in §2 is right — that room's dominant *is* peach and its floor *is* peach, so
   the wainscot has to be deepened to keep the horizon — but the result is a brown band behind a
   pink sofa. The honest options are to change the living room's dominant, which contradicts §3's
   locked room-mood table, or to commission a second wood tone, which contradicts §3's seven
   tokens. Both are owner decisions, not this pass's.
2. **The bathroom's tiled band still reads as a slightly floating rectangle** rather than as a
   surface, because the basin is only 0.60 m wide and 0.45 m deep and the band has to be much wider
   than it to be a band at all. A wider basin would fix it properly.
3. **The living room's `book` still lines up with her left hand** at the default spawn and still
   reads, at a glance, as a second thing she is carrying. `WORLD_POLISH_PASS` §8.3 reported it; it
   is still true, and it is still not fixable from here — the book is an activity target with an
   authored stand point and a baked navmesh around it, and moving it means a re-bake this
   workstream cannot do.
4. **The kitchen table is still the emptiest large object in the kitchen**, for the reason
   `WORLD_POLISH_PASS` §8.5 gives: chairs would need a navmesh re-bake, and visual-only chairs would
   be walked through.
5. **The nursery's basket is still a pink pail.** It is the correct colour now, and it is still the
   least appealing object in the bedroom.
6. **The tone may move under this pass.** The lighting is another workstream's file and was being
   edited while these renders were taken. Composition, colour choice and form are what was judged
   here; if the key light or the ambient fill changes materially, the BEFORE/AFTER pairs should be
   re-shot — both halves, with the same one-command script, which is why the BEFORE set is taken by
   restoring four files rather than kept from an earlier build.
7. **Nothing here has been run on a physical iPad or iPhone.** Every number and every picture is a
   Mac render at the stated resolution.
