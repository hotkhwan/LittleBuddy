# Aliz — polish pass (menu smudge, hair chip, crown lines)

**2026-09-20 · zero Meshy credits · zero network calls · no Blender · no regeneration.**
Follows `docs/ALIZ_LOCAL_PASS.md`. Only `pinkGirlBuddy_v01.glb`, its atlas PNG and their
Godot `.import` md5 changed, all by `tools/aliz_polish_pass.py`.

| | Before | After |
|---|---|---|
| Real main menu, 1334x750 | `docs/shots/aliz_polish_before_menu.png` | `docs/shots/aliz_polish_after_menu.png` |
| Same menu at the 2940x1650 the harness gives for `--resolution 4002x2250` | `docs/shots/aliz_polish_before_menu3x.png` | `docs/shots/aliz_polish_after_menu3x.png` |
| **Menu face at 1:1** (the real size), before left / after right, 4x below | `docs/shots/aliz_polish_menu_face_1x.png` | same file |
| Face close-up, `alizface 1.24` | `docs/shots/aliz_polish_before_face.png` | `docs/shots/aliz_polish_after_face.png` |
| Crown close-up, `alizface 1.42` | `docs/shots/aliz_polish_before_crown.png` | `docs/shots/aliz_polish_after_crown.png` |
| Whole body, `alizface body` | — | `docs/shots/aliz_polish_after_body.png` |

Every shot above was rendered by `res://scenes/spike/shot_harness.tscn` from the shipping
wrapper, from a clean worktree at `840fd45` plus this change, and looked at.

---

## 1. What each defect actually was

The instrument that settled it is new: `tools/aliz_view_probe.py` renders through the **real
menu camera**, with **back-face culling** and Lambert shading from the interpolated vertex
normals. The earlier `aliz_screen_probe.py` renders head-on, unlit and never culls — which
is exactly why the previous pass recorded "the hair has no holes": without culling, a hole
in the hair shows the *inside of the far side of the head*, which is pink and looks like hair.

### Defect 2 — the "hair chip" is the sky

A ray through the chip pixels in the menu view hits **nothing but the culled inside of the
back of her head** (`tri 274/275`, model z −0.12..−0.15, back-facing). There is a real
7-vertex hole in the hair mesh on her left side, `x +0.180..+0.261, y 1.394..1.544`,
about 15 cm tall, and it is see-through. In the menu it shows the sky (pale), in the house
it shows the purple wall (lavender) — the same hole, hence the two descriptions of its
colour. The brief's "beside her RIGHT eye / screen-left" is the mirror of where it is: her
**left**, screen-right in every shot including the menu (`main.gd` yaws her 200°, the
wrapper 180°, so model +x lands on screen-right).

Counting boundary loops on the welded head mesh: **10 open loops on the head** (from a 1 cm
slit in the fringe to that 15 cm one), plus a **detached 16-triangle fragment** floating
1 cm above the crown at `(+0.141, 1.602, +0.130)`. Culled front-most pixels in the 2x menu
render: **979**.

### Defect 1 — the "goatee" is the flattened mouth cavity fighting itself

Clamping the cavity forward in the previous pass left every wall of the old pocket lying on
the same fitted surface. Measured on a 0.5 mm orthographic grid over the patch:

* **15 triangles wind backwards** (their geometric normal opposes their own vertex normals
  at dot ≈ −1.00). Godot culls them, leaving thin gaps that run **from each mouth corner
  down to the chin** — the goatee outline. The winding is consistent with the neighbours,
  so these are folds, not a flipped index buffer.
* **9.7 cm² of the patch has two or three coplanar front-facing layers** z-fighting.
* **17 rim vertices** still carried normals pointing into a cavity that no longer exists
  (worst 179° from the surface normal), so the patch shaded as facets.
* Below the patch, the chin drops away at mean normal `(+0.03, −0.76, +0.54)`: under the
  menu's overhead light that is **Lambert 0.05 against 0.23** for the patch. That shelf is
  the old lower lip's edge. With a grin it was the shadow under a lip; under a closed painted
  mouth it is a dark band that reads as a beard.
* The atlas gutter was **black** (53,215 of 120,447 unowned texels), so every island edge
  averaged toward black in the mipmaps that the menu distance samples.

The painted skin itself was not the problem: the face atlas is a flat `(253, 205, 182)` in
every height band, so the repainted patch matches its surroundings exactly.

### Defect 3 — the crown lines are lit strand walls

A lit software render from the stored normals reproduces every line, so they are neither
texture nor culling. The fringe strands are ridges on the head; each ridge has a thin side
wall whose normal points sideways or down — e.g. `tri 390` at `(0.92, −0.21, 0.32)` between
neighbours at `(−0.2, 0.0, −1.0)`, `tri 585` facing `(0.35, −0.75, 0.57)`. Seen edge-on
they are one or two pixels wide, and in the harness's back-light they light up while the
strand tops do not. The stored normals are otherwise already smooth (every head vertex
within 30° of the area-weighted average, no split normals), so re-smoothing them would not
have changed anything; the wall's own geometry is what points at the light.

## 2. What was changed

`tools/aliz_polish_pass.py <in.glb> <in.png> <out.glb> <out.png>`, in this order:

1. **Debris.** The detached 16-triangle fragment is deleted.
2. **Holes.** Each of the 8 remaining boundary loops on the head is capped by ear-clipping
   (the loop's own edge direction gives the winding; two loops came out reversed against
   their neighbours' normals and were flipped). **28 cap triangles**: 8 reuse the loop's
   own UV duplicates because some choice of them lands on a footprint that is ≥97% hair and
   under 40 texels long; the other 20 sit on fresh vertices (position, normal, joints and
   weights copied from the loop vertex) whose UVs form a 0.6-texel triangle at `(56, 432)`,
   the hair texel farthest from any non-hair texel, so nothing can sweep the atlas.
3. **Mouth peel.** The 15 back-wound triangles are dropped (Godot never drew them), then
   coplanar duplicates are removed greedily while the grid proves every previously covered
   sample stays covered: **6 more go**, 0 holes opened. The patch's 124 raw vertices then
   take area-weighted normals from the surface that remains.
4. **Lower face.** 131 raw vertex normals under the mouth are blended **50%** toward a
   vertical cylinder round the head, fading out over 3 cm. No vertex moves. This lifts the
   lip shelf from Lambert 0.05 to the patch's level under the menu light.
5. **Hair normals.** The 514 welded hair vertices (1,391 raw; y > 1.05, texel classified as
   hair, mouth excluded) take normals from a capsule round the head — sphere above
   `y 1.405`, cylinder below so the long hair shades as a hanging mass — blended **70/30**
   with the smooth mesh normal. Art bible §4 asks for hair as "2–5 solid rounded masses";
   this shades it as one. Silhouettes are untouched.
6. **Atlas padding.** All 120,447 unowned texels are filled from their nearest owned
   neighbours, 8-connected, until none remain. Owned texels are not written.

The GLB's embedded atlas is replaced too (Extract Textures preset), and every bufferView
is re-laid out at its new offset. Skin weights, joints, bind matrices and the animation
are byte-for-byte the same data.

## 3. Numbers

| | Before | After | Gate |
|---|---|---|---|
| Triangles | 3,898 | **3,889** | ≤ 4,000 |
| Vertices | 4,879 | 4,939 | — |
| Atlas | 1 × 512² | **1 × 512²** | ≤ 512 |
| Materials | 1 | 1 | 1 |
| GLB | 614,264 B | 563,520 B | — |
| PNG | 310,898 B | 257,085 B | — |
| Bounding box | X ±0.364 Y 0–1.700 Z ±0.276 | **identical** | — |
| Open boundary loops on the head | 10 (+1 fragment) | **0** | — |
| Culled front-most pixels, 2x menu render | 979 | **79** | — |
| Culled front-most pixels, crown render | 6,528 | **414** | — |
| Back-wound triangles in the mouth patch | 15 | **0** | — |
| Coplanar z-fighting in the mouth patch | 9.7 cm² | 8.5 cm² (see §5) | — |
| Black texels in the atlas gutter | 53,215 | **0** | — |

The remaining 79 and 414 culled pixels are edge-on folds with a front face a few millimetres
behind them of identical colour and Lambert (ray-cast: `tri 293` over `tri 3264/3265`, both
hair, both 0.93–0.96), so nothing shows through.

**Full suite:** `PASS - 122 case(s), 0 failure(s)`, before and after, in this worktree.
No test was weakened. `test_aliz_face.gd`'s two assertions (no vertex more than 30 mm behind
the face; ≥90% hair above the lashes) still hold. Godot import: no new errors (the
pre-existing missing macOS speech-plugin binary message is unrelated).

## 4. Verdict, defect by defect

* **Chip: fixed.** No hole in the hair in any view; the menu, 2.2x menu, crown and body shots
  show none. Evidence: `aliz_polish_after_menu.png`, `aliz_polish_after_menu3x.png`,
  `aliz_polish_after_crown.png`, `aliz_polish_menu_face_1x.png`.
* **Crown lines: fixed.** The crown shot is one smooth mass; the lit software render agrees.
  Evidence: `aliz_polish_before_crown.png` vs `aliz_polish_after_crown.png`.
* **Goatee: fixed as a goatee, with a residue.** At 1:1 menu size the dark smudge under the
  mouth is gone and the mouth reads as a small smile on a plain chin
  (`aliz_polish_menu_face_1x.png`). At the 2.2x menu render a **faint, soft, lighter rounded
  patch** around the mouth is still discernible if you look for it: it is the flattened
  patch meeting the receding chin, and it is now a smooth tonal transition rather than lines
  and facets. Close up (`aliz_polish_after_face.png`) the chin is clean.

## 5. What is not fixed, and what was tried and rejected

* **8.5 cm² of coplanar overlap remains under the mouth.** The survivors are *partially*
  overlapping folds — each member of a pair has exclusive area — so neither can be deleted
  without opening a hole. Their colour is identical (median texel difference 0) and their
  normals now agree to a median 4.8°, 90th percentile 14.5°, so the flicker is faint, but
  under a moving house camera it may still shimmer slightly. **Recessing the duplicates by
  1.2 mm on their own vertices was implemented, rendered and rejected**: it opened hairline
  cracks along their free edges that the sky showed through at gameplay distance
  (visible in an intermediate `aliz_polish_after_face.png` that was overwritten). The clean
  fix is a single-layer re-triangulation of the patch with the smile re-baked into a fresh
  UV island; that is a small project of its own and was not done tonight.
* **The hair now shades as one mass.** That is the point, and §4 asks for it, but it is a
  look change: the fringe's strand relief is carried by its silhouette and the painted edge,
  not by shading. If someone wants the creases back, `HAIR_PROXY_WEIGHT` is the knob.
* Two single-vertex non-manifold spots at `(−0.213..−0.218, 1.33, 0.055)` (her right
  temple) are not loops and were left alone; nothing shows through them in any render.
* The pale vertical rim on her far-left hair in the `alizface` crown shot (`tri 3649`) is a
  legitimate rim light: that harness lights her from behind and above. It does not appear
  under the menu light and was not treated as a defect.
* Head-to-height proportion, cheek UV seams and the arc of the fringe are as the previous
  pass left them.
* Nothing here has been seen on a physical device.

## 6. Tools

| Tool | Purpose |
|---|---|
| `tools/aliz_view_probe.py` | **New instrument.** Real menu camera (or the `alizface` framings), back-face culling, Lambert from interpolated normals. Writes `_tri`, `_lit` and `_cull` images; the cull mask is the map of everything Godot leaves see-through. |
| `tools/aliz_polish_pass.py` | **The fix.** Debris, hole caps, mouth peel, lower-face and hair normals, atlas padding; refuses to write if the peel opens a hole or the budget is exceeded. Its docstring carries the measurements. |
| `tools/aliz_menu_strip.py` | The 1:1 menu-face strip, so the judgement is made at the size a child sees. |

## 7. Restoring

`git checkout 840fd45 -- game/assets/characters/buddy/pinkGirl/` then
`Godot --headless --path game --import`. The reimport is required, as before.
