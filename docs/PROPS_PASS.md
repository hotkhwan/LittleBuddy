# Interactive props — the things a child picks up

**Branch:** `feature/overnight-production-candidate` · **Engine:** Godot 4.7.2 · **Not committed.**

Priority 6 of the sprint. The interaction system was not rebuilt and was not touched:
`kitchen_state.gd`, `kitchen_rules.gd` and `kitchen_items.gd` are byte-identical, every verb still
works, and `game/tests/shots_kitchen.gd` still drives the real kitchen through all nine steps and
exits 0. What changed is **how a shape is drawn** and **where the drawing ends up**.

Every number below was measured on this machine; every picture was looked at.

---

## 1. The two defects from `FOUNDER_PREVIEW_RC_CHECKLIST.md`

### Open issue 5 — "choice-row objects float during `choose` beats"

**Confirmed, found, fixed — and the checklist's figure was wrong.** The issue says *~0.9 m*. The
real number, measured in the running game across **72 choice rows in all 14 shipped missions**, is
up to **17.8 cm**, and it is not one number: it depends on the object.

`ObjectSpawner.VISUAL_CENTRE_Y` (0.1) was doing two jobs. Its comment said *"so it rests on the
floor/table plane rather than being half-buried"*, and for the one primitive it was tuned against —
a 16 cm sphere — it did. But `model_transform()` normalises every model to its longest axis and
then **centres the result on that height**, so how far a pickup floated became a function of how
tall it happened to be:

| object | before | after |
|---|---|---|
| `milk` (a tall carton) | **1.0 cm under the floor** | on it |
| `blocks` | 2.6 cm up | on it |
| `bowl` | 2.4 cm up | on it |
| `ball` | 4.8 cm up | on it |
| `soap` / `towel` | 6.8 cm up | on it |
| `starToy`, `circleToy` (flat plates) | 8.6–9.9 cm up | on it |
| `spoon` | 12.6 cm up | on it |
| **`banana`, lying across the screen** | **17.8 cm up** | on it |

All figures are world-space, at the row's real presentation scale (1.80–2.31).

This is a **different fault from the kitchen one** that `WORLD_POLISH_PASS.md` fixed. There the
ANCHOR was in the wrong place (`_anchor()` used the fridge's doorway height for the counter). Here
every anchor was right and the mesh was hung off it by half of whatever it measured.

**The fix, in two files:**

* `object_spawner.gd` — `model_transform()` and `build_primitive_visual()` now **stand the visual
  on the object's own origin**, x/z centred (`base_offset()`). That is ART_BIBLE §6's "pivot at base
  centre", the same rule the kitchen props are authored to, and it makes the resting plane the
  caller's business instead of the mesh's.
* `house_stage.gd` — `SPAWN_LIFT` 0.02 → **0.001**. The 2 cm lift existed to stop the tall objects
  being half-buried by the old rule; at the anchor's 1.8–2.3× scale it was 3.6–4.6 cm of daylight
  under every toy in the room. It is now only a z-fight guard, about 2 mm on screen.

**After: 72 rows, worst float 0.2 cm** (2 mm — the guard), nothing under the floor.

**Touch targets are untouched, deliberately.** `VISUAL_CENTRE_Y` keeps its second job as the centre
of the grab collider, and `GRAB_SIZE_M` (0.34 m) and `grab_size_px()` are unchanged, so the 220 px
minimum is exactly the number it was. A visual standing on y = 0 and no taller than
`MODEL_MAX_SIZE_M` (0.26) still sits entirely inside a 0.34 box spanning −0.07 to +0.27 — asserted,
not assumed.

Evidence: `props_ground_BEFORE_*.png` vs `props_ground_*.png` — the same four real pickups, the
same camera, the same frame, 0.4 s apart.

### Open issue 4 — "the beat marker is one of the palest shapes in frame"

It was one `CylinderMesh` at `Color(0.66, 0.90, 0.81, 0.42)`: mint, at 42% alpha, unshaded. The
lighting pass had already found why it read grey — 42% of a pale mint over a floor that was
clipping to near-white leaves almost no colour behind — and fixed the floor. The shape was still
42% of a pastel on a pastel.

It is now **opaque**, and a **ring with a dot** rather than a wash:

| | before | after |
|---|---|---|
| transparency | `TRANSPARENCY_ALPHA` | **none** |
| triangles | 768 | **388** |
| draw calls | 1 | 1 |
| material | its own `StandardMaterial3D` | the shared `prop_kit` one |
| colours | mint @ 42% | `cream` field, `deep(mint)` ring and dot |

ART_BIBLE §10 targets **zero transparent surfaces** and this was one of only three in the whole
world; it is now none of them. §7's amendment asks a floor decal to be **warm `ink`-tinted**, and
`deep(mint)` is §3's own "Deep" step — mint mixed 22% toward `ink` — so the ring is warm without
inventing a colour.

**Two versions were rendered and rejected before this one, which is the only reason the third
works:**

1. **All mint** (`mint` field, `deep(mint)` ring). Fine on floorboards; **it vanished on the
   kitchen's own mint rug** — which is exactly the surface a "go here" spot has to survive, because
   the rug is where the child is being sent to stand. One §3 value step across a few pixels is
   nothing.
2. **An `ink` ring.** Unmissable, and it read as a hole punched in the floor — §3's own warning
   about a dark in a pastel scene, and it was 6 cm of it.

The shipped answer uses **value, not hue**: `cream` is lighter than warm floorboards *and* lighter
than the mint rug, so the spot separates from both by the same amount, and `mint` — §3's "go" —
rings it.

---

## 2. The props themselves

Eight items, five generic silhouettes. Three of ART_BIBLE §6's forbidden pairs were live in the
build at once:

> **One object teaches one word. Two nouns must never share a shape.**

* **`banana` and `spoon`** were the same rounded lozenge, 14 cm against 13 cm, differing only in
  colour. "Give me the spoon" had no answer a child could see — and colour cannot carry it, because
  colour is a word this game teaches separately.
* **`bowl`, `mashedBanana` and `fruitBowl`** were one vessel in three interior colours.
* **`bottle` and `bottleOfMilk`** were one cream cylinder.

`kitchen_items.gd` is read-only and it is right: `flat` and `bowl` are the correct *classes*. So the
shape stays the class, and `kitchen_view.gd` gained an `ITEM_FORM` table that names the *drawing*.
An id with no row falls back to its shape, so a new ingredient still appears the day it is added to
the data.

| item | was | is |
|---|---|---|
| `apple` | a sphere with a mint pin | squashed ball, dimple, tan stalk, **one mint leaf** |
| `banana` | a rounded lozenge | a **tapered crescent** with two `deep()` tips |
| `spoon` | the same rounded lozenge | §6's own words: **a bowl and a handle**, with a paler hollow |
| `bottle` | a cylinder + pink knob | body, **shoulder**, collar, **teat** |
| `bottleOfMilk` | the same cylinder | the same bottle **with a milk line** in its own `deep()` step |
| `bowl` | a vessel | a vessel on a **foot ring**, deeper, so it is not a disc from 32° |
| `mashedBanana` | a vessel, yellow inside | a **cream bowl with a low mound of food in it** |
| `fruitBowl` | a vessel, peach inside | a **cream bowl with three whole fruit in it** |

Nothing was invented outside the palette: every colour is the item's own `color` from
`kitchen_items.gd`, one of §3's two documented steps of it (`light()`, `deep()`), or one of the
seven tokens. No new material, no alpha, no emission — all eight still share `prop_kit`'s single
`StandardMaterial3D` and are one draw call each, exactly as before.

---

## 3. Triangles — measured

| item | before | after | Δ |
|---|---|---|---|
| `apple` | 272 | 296 | +24 |
| `banana` | 156 | 228 | +72 |
| `bottle` | 292 | 244 | **−48** |
| `bottleOfMilk` | 292 | 320 | +28 |
| `bowl` | 164 | 200 | +36 |
| `fruitBowl` | 164 | 344 | +180 |
| `mashedBanana` | 164 | 280 | +116 |
| `spoon` | 156 | 188 | +32 |
| **total** | **1,660** | **2,100** | **+440 (+26%)** |

§10's small-prop budget is **40–400** triangles. The worst item is `fruitBowl` at **344**, which is
86% of the ceiling and the only one over 300.

**What it costs in a frame:** items are per-object `MeshInstance3D`s and there are at most seven on
screen at once (three in the fridge, two on the counter, one carried, one served). Worst case
before ≈ 1,400 triangles, after ≈ 1,900 — against a 30,000 ceiling for a room that currently
measures ~11,000. **Draw calls are unchanged**: same node count, same shared material, and the beat
marker went from one mesh to one mesh while dropping 380 triangles.

---

## 4. Does anything still float or intersect?

Audited by `tests/shots_props.gd` against the real world, in centimetres.

| where | result |
|---|---|
| items resident on the worktop | on it (0.000) |
| items on the fridge shelf | on it (0.000) |
| an item on the prep board | on it (0.000) |
| a served dish on the table placemat | on it (0.000) |
| an item carried in her hand | hangs from its middle at the `RightHand` bone, clear of the dress |
| **72 choice rows, 14 missions** | **worst 0.2 cm; nothing sunk** |

### A real bug found while building the audit, and fixed

The kitchen audit kept reporting an **empty room while the render plainly showed a bowl on the
table**. It was not the harness.

`kitchen_view._refresh()` frees every item mesh with `queue_free()` and immediately rebuilds them.
`queue_free()` does not remove a node from its parent until the end of the frame, so each
replacement found its own name already taken — and Godot renames a colliding node to
**`@MeshInstance3D@25`**, not to `Item_bowl2`. The mesh still drew, which is why nobody saw it: the
kitchen looked correct and every one of its nodes had silently lost its name, so anything that
looks an item up by name — a test, a tool, a future hit test — found nothing.

`_refresh()` now `remove_child()`s before `queue_free()`, and names survive.

---

## 5. Tests

**122 cases, 0 failures.** (The suite was 120 at the start of this pass; two of the new cases belong
to another workstream running in parallel.) **No test was weakened.** Two were made stricter, two
sub-tests are new, and both new assertions were **mutation-checked** — the fix was reverted and the
test was confirmed to fail loudly:

| file | change |
|---|---|
| `test_gameplay_object_spawner.gd` | `_test_model_fits_inside_grab_area()` asserted the presented mesh was **centred** on `VISUAL_CENTRE_Y`; it now asserts the base is on y = 0, x/z centred, **and** that the box is really enclosed by the grab collider. Strictly tighter — it pins the height as well as the centre. |
| `test_gameplay_object_spawner.gd` | **new** `_test_every_pickup_stands_on_the_floor()` — spawns every record in `objects.json` for real and measures its visual, so the primitive path (where a `torus` hovered 8 cm) is covered too. |
| `test_kitchen_view_placement.gd` | **new** `_test_two_words_never_share_a_shape()` — §6 as a regression guard. Two items teaching different words must be drawn by different forms, and their meshes must not be the same triangle count at the same proportions. **Colour is deliberately excluded**: every one of the historical defects differed in colour and nothing else. |
| `test_kitchen_view_placement.gd` | rules 2 and 3 measured "the longest ingredient" as `size × 1.9` and `size × 2.0` — the factors the old generic lozenge happened to be drawn at. They now build the real item and read its `AABB`, so re-drawing a prop re-measures it here instead of silently invalidating the clearance. |

Mutation evidence:

```
# object_spawner.gd reverted to centring on VISUAL_CENTRE_Y
- model 'kenney-food-kit/banana' does not stand on its own origin: its base is
  +0.061 m, which is 12.2 cm of daylight under it once the row's 1.8-2.3x scale is applied

# ITEM_FORM rows for banana and spoon removed
- 'banana' (banana) and 'spoon' (spoon) are two words drawn by the same form 'flat';
  §6 forbids two nouns sharing a shape
```

**Also confirmed green at the end of the pass:** `tests/shots_kitchen.gd` (nine steps, each applied
before it was photographed, exit 0), `tests/smoke_mission01.gd`, and the same with `-- snackTime`.

---

## 6. Evidence

`game/tests/shots_props.gd` is new. It photographs, and it **measures** — the float numbers in §1
and §4 are its output, not an estimate.

```
Godot --path game --resolution 1334x750 --script res://tests/shots_props.gd -- ipad
Godot --path game --resolution 1334x750 --script res://tests/shots_props.gd -- iphone 2340x1080
```

Both BEFORE and AFTER come out of **one run, at one camera, in one lighting state**, because
reverting the working tree to shoot a BEFORE is not available while other agents are editing it,
and a BEFORE taken at a different camera is not a comparison. The harness rebuilds the previous
behaviour instead — `_legacy_item()` is the old `_make_item()` verbatim and `_legacy_beat_marker()`
is the old marker verbatim — so the two frames differ by exactly the thing under review.

Every wide frame is rendered through an explicit `SubViewport` of the asked-for size and **the
written PNG's dimensions are read back off disk**, so the 2.17-aspect-filed-as-1.80 trap cannot
happen quietly.

| file | what | iPad | iPhone |
|---|---|---|---|
| `props_items_BEFORE_*` / `props_items_*` | all eight items, same camera | 1334×750 | 2340×1080 |
| `props_silhouette_BEFORE_*` / `props_silhouette_*` | the same row flooded to flat `ink` — §2's silhouette test | 1334×750 | 2340×1080 |
| `props_ground_BEFORE_*` / `props_ground_*` | four real pickups + the beat marker, old rule vs new | 1334×750 | 2340×1080 |
| `props_fridge_*` | the fridge open, food on the shelf | 1334×750 | 2340×1080 |
| `props_counter_*` | a banana on the prep board, carried item in hand | 1334×750 | 2340×1080 |
| `props_served_*` | the mashed banana served on the placemat | 1334×750 | 2340×1080 |
| `props_choose_*` | a real `choose` beat, objects on the floor | 1334×750 | 2340×1080 |

All 20 dimensions verified from the PNG headers.

---

## 7. What still looks wrong, honestly

1. **`bottle` and `bottleOfMilk` are still the same silhouette.** They differ by the milk line,
   which is colour. That is accepted rather than missed: they are one object in two states, one
   becomes the other, and the kitchen cannot hold both at once — so no child is ever asked to tell
   them apart. If that ever changes, the bottle of milk needs a different form, not a different
   tint.
2. **The three bowls separate weakly in pure silhouette from a high angle.** `props_silhouette_*`
   shows it: the empty bowl is flat-topped, the mash is domed and the fruit is lumpy, which reads at
   the game's 32° but is close at 60°. They are unmistakable in colour, and the game never asks for
   a bowl from directly above.
3. **The spoon is still the weakest-reading item**, for the same reason the sourced spoon model was
   (`ASSET_SOURCING_PLAN.md` §2): a spoon's identifying detail is small and it is a flat object. It
   is now clearly *not a banana*, which was the actual defect.
4. **The clothing cut-outs stand vertically like cardboard**, visible in `props_choose_*`. They are
   genuinely on the floor now (measured), but a flat garment presented face-on has no base to read
   as resting on anything. That presentation is a deliberate, documented decision in
   `MODEL_PRESENTATION` — a t-shirt modelled as a draped solid loses its sleeves — and changing it
   is a bigger question than this pass.
5. **`shoes` is still the weakest 3D object in the game** (ART_BIBLE §13.6). Not in this
   workstream's files and not touched.
6. **Nothing here has been run on a physical iPad or Android device.** Every number and every
   picture is a Mac render at the stated resolution. The tap-target claim is the unchanged
   `grab_size_px()` arithmetic, not a finger on glass.

---

## 8. Files changed

Only these, all within this workstream's ownership:

```
game/scripts/kitchen/kitchen_view.gd              item forms, and the queue_free() rename bug
game/scripts/gameplay/house_stage.gd              beat marker, SPAWN_LIFT
game/scripts/gameplay/object_spawner.gd           props stand on their own origin
game/tests/cases/test_kitchen_view_placement.gd   §6 guard, measured clearances
game/tests/cases/test_gameplay_object_spawner.gd  grounding assertions
game/tests/shots_props.gd                         new — the evidence harness
docs/PROPS_PASS.md                                this file
docs/shots/props_*.png                            20 images
```

`kitchen_state.gd`, `kitchen_rules.gd` and `kitchen_items.gd` are unmodified. Nothing under
`scripts/house/`, `scripts/camera/`, `scripts/care/`, `scripts/characters/`, `scripts/ui/`,
`scripts/audio/`, `scenes/`, `content/`, `project.godot` or `export_presets.cfg` was touched.

**Not committed.**
