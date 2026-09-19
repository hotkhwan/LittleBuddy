# Visual quality — before / after

Same production scene, same shipping camera, commit `2f0cea3`.
Every image below was rendered from the real `house_world.tscn` and looked at.

## The rule I had to fix first

`--resolution 2340x1080` is a **request**, not an instruction — the window
manager clamps it to 1686×935. Every "wide iPhone" screenshot in this repo before
this sprint is a **1.80 aspect filed as evidence for a 2.17 one**. The camera
fits its distance *from* the aspect, so those are different compositions, not
rounding. Only the `world_*_iphone.png` set, captured through an explicit
`SubViewport`, is genuinely 2340×1080.

---

## 1. The HUD over Bunny — the sprint's P0

| | |
|---|---|
| Before | `docs/shots/hud_feed_BEFORE_ipad.png` |
| After | `docs/shots/hud_feed_AFTER_ipad.png` |

Three text lines — instruction, Thai hint, assist — stacked straight across
Aliz's eyes during every close-up. **Raising the camera cannot fix this**: the
look-at point is screen-centre, so more chrome inset pushes the camera back and
preserves the overlap.

The HUD now reads `RoomCamera.get_focus_radius()` and lays itself out around the
shot. The two shot classes were measured across both shipped missions and
separate cleanly — **1.88 m** for choice beats, **0.90 m** for close-ups, a full
metre apart. Threshold 1.30 m.

In FEED, text leaves the centre entirely for a left rail; the top stack goes
248 px → **0 px**. Both faces are clear at both viewports.

## 2. The kitchen

| | |
|---|---|
| Before | `docs/shots/world_kitchen_counter_ipad_BEFORE.png` |
| After | `docs/shots/world_kitchen_counter_ipad.png` |

**Three of the "polish" items turned out to be bugs**, which is the useful part:

1. **The bowl and spoon floated in mid-air.** The counter's contents were laid
   out with the *fridge's* formula — 0.59 m up and 0.30 m in front of the cabinet
   doors, resting on nothing. This is the floating-object defect the brief names.
2. **The fridge did not look open when it was open.** A door is painted onto the
   fridge body and a real hinged door hangs in front of it, so opening revealed
   the painted one. It now has a lined interior with two shelves.
3. **The carried item was stuck to Aliz's tummy.** It now follows the rig's
   `RightHand` bone.

Added: sink under the window, hob, wooden prep board (which is also the dark
field the pale ingredients needed — the banana went from an invisible sliver to
the first thing you see), splashback, wall units, placemat.

## 3. Characters

Bunny was **the wrong model** — the seated, unrigged 398,404-triangle export, on
screen from frame one and physically incapable of moving. The bedroom now renders
**14,406 triangles total** with exactly one Bunny node. Five real skeletal clips
on the 24-bone rig.

Aliz is **unchanged and still the known weak point**: modelled open-mouth grin,
real gaps in the hair. Blocked on `MESHY_API_KEY`; 0 of 100 credits spent.

## 4. Cost

| room | before | after |
|---|---|---|
| bedroom | 12,264 | 13,164 |
| bathroom | 9,704 | 9,860 |
| livingRoom | 11,244 | 11,400 |
| kitchen | 10,252 | 11,032 |
| **total** | 43,464 | **45,456 (+4.6%)** |

Ceiling is 30,000 per room; the worst room sits at 44% of it. **Draw calls
unchanged** — everything merges into the existing shell mesh. No new colliders,
no new touch targets, navmesh untouched.

## 5. What still looks wrong

1. **Lighting is milky.** Ambient `#FFF6E5` @ 0.62 against 0.96-luminance cream
   walls, and the sun's X component is negative so the **−X wall is never lit**.
   Both live in `house_world.tscn`, which no agent owned this sprint. ~0.50 and
   `#FFEBD8`, plus a ~20° azimuth swing, would fix it — still one light, no
   post-processing.
2. **Aliz's hair and mouth** dominate any close-up of her face.
3. The contact shadow is a grey ellipse; it wants a warm ink tint.
4. Choice-row objects still float during `choose` beats (a different spawner from
   the kitchen bug above).
5. **Nothing has been seen on a physical iPad.**
