# Caregiver gameplay audit — P0

**Date:** 2026-09-19 · **Branch:** `feature/overnight-production-candidate`
**Method:** read the working tree, then *ran* the scenes and looked at the frames.
No claim here rests on a previous agent's report.

---

## 1. The screenshot is `house_world`, not the nursery

The description — procedural toddler in mint, top-down room, large tutorial
pointer, sparse interactions — matches **`scenes/house/house_world.tscn`** on
first run. Every element is accounted for:

| In the screenshot | What it actually is |
|---|---|
| procedural toddler, mint top | `scripts/character/toddler_view.gd` — `SHIRT = #A8E6CF`, "TEMPORARY ENGINEERING ART" in its own header |
| top-down room | the house room camera, fitting a 4×4 m floor |
| large tutorial pointer | `scripts/onboarding/gesture_hint.gd`, shown on first run |
| sparse interactions | 3 furniture + 2 doors per room |

**One correction to the brief's premise.** `scenes/baby_room/baby_room.tscn` —
the *story* route, "Baby Days / Milk Time" — **already shows a real Meshy baby**,
seated in a blue romper. Rendered and confirmed: `docs/shots/audit_babyroom.png`.
So "no clearly visible Meshy baby" is true of the house, not of the whole game.
There are two different gameplay scenes and they were in very different states.

---

## 2. Why the new characters were not visible

**Not a flag. Not an import. Not an exclusion filter. Not visibility.**
They were simply **never referenced by the house scene.**

Checked, each explicitly:

| Suspect | Finding |
|---|---|
| Feature flags | `PinkGirlBuddy.ENABLED = true`, `BabyLittleBuddy.ENABLED = true`. Both on. |
| GLB import | Fine. Both models render — PinkGirl in the menu, the baby in `baby_room`. |
| Asset exclusion filters | Fine since 2026-09-19. Runtime GLBs tracked and in the `.pck`. |
| Scene visibility | N/A — the nodes did not exist to be hidden. |
| Wrapper references | **`PinkGirlBuddy.tscn` was instantiated by `main.gd` only — the menu.** |
| Character ownership | **The player's visual was hardcoded to `ToddlerView` in `house_world.tscn`.** |
| Child in the house | **None existed.** |

### The naming trap that hid it

`house_world.tscn` contains a `CharacterBody3D` **named `LittleBuddy`** — and
that node is *the player*. So "Little Buddy is in the house" was true of the node
name and false of the game. Anyone grepping for the character found it and moved
on. This is the single reason the gap survived several passes.

### Verdict on "integrated"

The wrappers were complete and working. What was missing was the twelve lines of
scene wiring that put them on screen. **A wrapper existing is not integration**,
which is what the brief warned about, and the warning was justified.

---

## 3. Role inversion — the product bug underneath

Before this pass the game had the fantasy backwards:

| | Before | Product direction |
|---|---|---|
| Player controls | a toddler (the child) | **PinkGirl, the caregiver** |
| Child in the world | none | **Little Buddy, cared for** |
| `house_world` fantasy | "move a toddler around a house" | "I am Buddy, and I look after Little Buddy" |

In `baby_room` the player is not embodied at all — it is a tap-and-drag nursery
activity. So neither scene expressed the locked direction.

---

## 4. Camera and readability (P3 — measured, not fixed)

At 1366×1024 the player occupied roughly **8% of frame height**. The camera fits
the whole 4×4 m floor plus headroom, which is correct for navigation legibility
and wrong for reading a face. With the caregiver swapped in at 1.65 m the figure
is now materially larger, but the shot is still a wide establishing view.

**Not addressed in this pass.** The framing solver (`camera_framing.gd`) is
shared by every room and by the activity focus system; changing it is a separate,
testable piece of work and not something to bolt onto a character swap.

---

## 5. What was fixed, and what it cost

| Change | File |
|---|---|
| Player visual → PinkGirl; `ToddlerView` kept hidden as fallback | `house_world.tscn` |
| Collision capsule 0.8 m → 1.5 m, centre 0.4 → 0.75 | `house_world.tscn` |
| `LittleBuddyChild` added to the bedroom, parented to the room | `house_world.tscn` |
| First-run line now introduces the caregiver | `onboarding_plan.gd` |
| Nine child needs, derived | `scripts/care/child_needs.gd` |
| Need → pose/mood mapping | `scripts/care/child_presentation.gd` |
| Stats the caregiver game owns | `scripts/care/child_stats.gd` |
| The child as an inhabitant, with a visible need line | `scripts/care/child_actor.gd` |

The player node keeps the name `LittleBuddy`. It is depended on by
`house_world.gd`, `nav_spike.gd` and two test cases; renaming it is mechanical
and should be its own change rather than riding along with a visual swap.

### An architecture guard earned its keep

The first version of the needs model added `thirst` and `freshness` to Chapter
2's `BabyState` and lived in `scripts/baby/`.
`test_house_chapter2_untouched.gd` failed: *"HouseWorld is Chapter 3+ and must
not depend on Chapter 2"*.

It was right on both counts. Chapter 2 is finished and shipped, and `BabyState`
starts at `hunger = 80` specifically so the milk lesson opens with a hungry baby
— its header says "only hunger affects gameplay tonight". Bolting two axes on
would have pushed Chapter 3's concerns into a Chapter 2 file.

`BabyState` was reverted untouched and the caregiver game got its own
`scripts/care/child_stats.gd`. **The guard was not modified.**

---

## 6. Evidence

| Shot | Shows |
|---|---|
| `docs/shots/audit_babyroom.png` | the story route already had a real Meshy baby |
| `docs/shots/p1_player_pinkgirl.png` | the player is now the caregiver |
| `docs/shots/p1_caregiver_and_child.png` | both characters in the house, greeting corrected |
| `docs/shots/p2_child_responds.png` | the child says "I'm hungry!" from derived state |

All are the real `house_world` scene, not a validation harness.

---

## 7. What this audit did NOT resolve

Listed so the next session starts from fact:

* **P3 camera** — measured above, deliberately not changed.
* **P4 missions** — no caregiver mission exists yet. `MissionRunner` and the
  content pipeline are in place and are the right host; nothing was authored.
* **P5 outfits** — not started. See §8 for the blocker found while auditing.
* **P6 interactions** — `approachChild` etc. are named in `child_needs.ANSWER`
  but only as the *answer* to a need; none are implemented as an interaction.
* **P7 house** — storage/tidy domain exists and cabinets open; the tidy mission
  does not scatter anything yet.
* **P8–P9 audio / Parent Corner** — not started.
* **P10 smoothness** — not audited.

---

## 8. A blocker found for P5 (outfits), reported not worked around

The runtime child model is **one mesh, one material, one texture**: 14,406
triangles, a single primitive, one 1024² atlas. Clothing is **fused to the body
and painted into that atlas** — the blue romper is texels, not geometry.

Measured, not assumed:

```
primitives on the mesh : 1     (a separable garment would be its own primitive)
materials on the model : 1
atlas 1024x1024        : 20.3% of non-empty texels are the romper's pale blue
```

So "change outfit" cannot be a mesh swap on this asset. Honest options:

1. **Texture-atlas swap** — author 2–3 alternative 1024² albedo maps and switch
   `albedo_texture`. Real, visible, cheap, no Meshy credits. Limited to recolour
   and pattern; silhouette cannot change.
2. **Blender separation** — cut the clothing shells off and re-export as
   attachable meshes. True mesh swapping, silhouette changes possible.
   **Blender is not installed** (`brew install --cask blender`).
3. **Meshy re-generation per outfit** — costs credits; needs approval; would not
   preserve the rig.

Recommended: **(1) now, (2) when Blender is available.** Per the brief, the
limitation is documented rather than disguised — a label change presented as a
mesh swap would be exactly the false claim it forbids.

**Zero Meshy credits were spent in this pass. Balance unchanged at 3054.**
