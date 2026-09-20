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

---

# Second pass — the smile, the fringe edge, and the Meshy question

**2026-09-20, after the first pass merged as `6d9d698`. Zero Meshy credits. One public
price page was read; no API endpoint was called.**

Owner feedback from playing the real build: *"hair still has visible defects"* and *"mouth
looks too pursed."* Only the two asset files, `tools/aliz_*` and this document changed.

| View | Before | After | 1:1 strip (before left, after right, 4x below) |
|---|---|---|---|
| Real main menu | `aliz_smile_before_menu.png` | `aliz_smile_after_menu.png` | `aliz_smile_menu_face_1x.png` |
| Standing, front, house light, gameplay distance | `aliz_smile_before_front.png` | `aliz_smile_after_front.png` | `aliz_smile_front_face_1x.png` |
| Three-quarter (the walking angle) | `aliz_smile_before_threeq.png` | `aliz_smile_after_threeq.png` | `aliz_smile_threeq_face_1x.png` |
| From behind | `aliz_smile_before_back.png` | `aliz_smile_after_back.png` | — |
| Real bedroom, `shot_harness -- house` | `aliz_smile_before_bedroom.png` | `aliz_smile_after_bedroom.png` | `aliz_smile_bedroom_face_1x.png` |
| Feeding portrait, `shots_rc.gd` | `aliz_smile_before_feed.png` | `aliz_smile_after_feed.png` | — (see note) |
| Head close-up, `alizface 1.24` | `aliz_smile_before_face.png` | `aliz_smile_after_face.png` | — |
| Crown, `alizface 1.42` | — | `aliz_smile_after_crown.png` | — |

All in `docs/shots/`. The front / three-quarter / back trio comes from the new
`tools/aliz_shots.gd` (run with `Godot --path game --script ../tools/aliz_shots.gd -- <prefix>`),
which loads the shipping wrapper under `main.tscn`'s light at the bedroom's head size, so
those three are deterministic. **Note on the house shots:** `-- house` and `shots_rc.gd`
play the real game against the persistent `user://` profile, which every run advances; the
bedroom pair happened to land on the same beat, but in the feeding pair she stands behind
Bunny's portrait in the "after" run, so that pair proves only that nothing broke, not the
face. The menu and the deterministic trio are the fair comparison.

## 1. Mouth — `tools/aliz_smile_repaint.py` — PASS

**What it was.** 60 mm wide (8 % of a 0.73 m head), 6.4 mm deep, hard horizontal ends, in
the art bible's `#9E4F4D`. On this face the atlas density is about 3 texels per cm — the
entire old smile was **35 texels** — so at menu distance it mip-averaged to a small dark dot.
"Pursed" is exactly what a dark dot in the middle of a chin reads as.

**What it is now.** One filled shape, 84 mm wide (1.4x), 6.2 mm thick at the middle tapering
to 55 % at the ends, corners rising 8 mm, **round caps** instead of the cut ends, feathered
over 1.8 mm, in `#B85E5C`. That colour is one step lighter and warmer than the bible's hex,
which is a deliberate and recorded deviation: the bible's ink was specified for a 1:6.5
figure and at this head's texel density it reads as a hole. Selection is 3D → texels
through the same guarded `claim_map` as before; the whole mouth ellipse is repainted skin
first so nothing of the old shape ghosts through; gutters re-padded. No mesh change.

Judged at 1:1 in `aliz_smile_menu_face_1x.png` and `aliz_smile_front_face_1x.png`: it reads
as a small smile with corners, not a dot. The three-quarter strip shows the corner lifting
the cheek. Identity unchanged.

## 2. Hair at gameplay distance — `tools/aliz_fringe_repaint.py` — PASS, with a residue

**Cut-through.** Every view above was inspected for sky or wall showing through the hair:
none in the menu, front, three-quarter, back, bedroom, crown or close-up. The first pass's
caps hold from behind and at the walking angle. Nothing to fix here.

**The fringe edge — what it actually was.** The first pass described the fringe as "a few
millimetres of relief"; it was measured unlit. Fitting a base forehead surface to the head-on
render and rejecting everything in front of it, the relief histogram is bimodal — forehead at
0–10 mm and a solid **32–52 mm slab**: the bangs are a 4 cm volume with a zigzag lower edge.
Per 1 cm column, the old paint arc `y = 1.418 + 0.42x²` sits **2–9 cm below** that slab edge
at |x| = 3–9 cm, and the central strand tips dip **15 mm below** it. So under the house light
the owner saw a lit pink band of flat forehead beneath a shadowed jagged wall, with
skin-coloured teeth in it — a ragged fringe. Painting, not geometry, and yet not fixable by
painting alone:

**Why the obvious repaint failed.** Blending each hair texel toward skin by flatness produced
a checkerboard of skin flecks across the slab. Measured: **426 of the 2,176 texels in the
band are claimed by both a forehead triangle and a slab triangle** — the two islands overlap
in the atlas around (347–388, 240–290). The first pass's "no texel is shared between regions
more than 12 cm apart" is still true; these surfaces are 4 cm apart.

**What was done.** The **10 flat forehead triangles under the fringe's teeth** (|x| < 8 cm,
y < 1.455, relief < 6 mm) were given new vertices with UVs in a free 45×40 atlas rectangle at
(313, 451) — positions, normals, joints and weights copied, so no vertex moves and the
triangle count is unchanged. Their old texels were transferred into the new island by
barycentric lookup (brows and skin detail come along), then everything that was hair-pink in
that island became skin. The hair/skin boundary is now the **mesh edge** between forehead and
the slab's foot, on two different islands, so bilinear filtering cannot smear it. Gutters
re-padded.

A first cut moved all 27 flat triangles in the band and opened two large skin wedges at the
temples where the slab edge climbs to y 1.49 — geometrically forehead, visually holes. That
is why the selection is limited to the central teeth; the flat pink outside them stays as the
side hair's foot.

**Result.** A scalloped fringe with three soft central points over a skin forehead,
consistent with its own shading (`aliz_smile_after_crown.png`, `aliz_smile_after_face.png`,
and at size in the front and menu strips). It is a more *stylised* edge than the flat arc,
and that is the residue: the zigzag is what the generated mesh actually is. It reads as a
drawn fringe rather than a torn one, but it is not the smooth curtain the art bible sketches.

## 3. Numbers and gates

| | First pass | Now | Gate |
|---|---|---|---|
| Triangles | 3,889 | **3,889** | ≤ 4,000 |
| Vertices | 4,939 | 4,951 | — |
| Atlas | 1 × 512² | **1 × 512²** | ≤ 512 |
| GLB / PNG bytes | 563,520 / 257,085 | 565,616 / 258,558 | — |
| Bounding box | identical | **identical** | — |

Full suite after the change: `PASS - 122 case(s), 0 failure(s)`. `test_aliz_face.gd`'s hair
floor (≥ 90 % above y 1.450) still holds; the skin that returned is below 1.455 by
construction. No test weakened.

## 4. Meshy decision prep — no spend

**Verdict: the defects the owner can see are now handled locally and do not, on their own,
justify a regeneration; what would justify one is the structural remainder, and that is an
owner call.** What remains is (a) 1:3 head-to-height against the bible's 1:6.5, (b) a face
painted at ~3 texels/cm so any mouth is a few dozen texels, (c) a fringe whose shape is the
remesh's zigzag rather than authored, (d) hair that now shades as one mass because its
normals were transferred from a capsule, and (e) ~8.5 cm² of faint coplanar overlap under the
mouth. None of these is fixable by another local pass; all of them go away together only with
a new model. **The asset:** image-to-3D from `docs/reference/aliz_reference_apose.png` via
`tools/meshy_aliz_apose.sh preview` — its prompt already demands an A-pose, hair as one solid
continuous piece and a closed-mouth smile, which are precisely the three things this and the
previous pass spent their time repairing — followed by Remesh to the 4,000-triangle budget,
then Rigging (which includes the walk and run clips the wrapper already binds). **Credits,
from `docs.meshy.ai/en/api/pricing` read today (no key, no endpoint):** image-to-3D with
texture 30 (Meshy-7; 35 with 8K texture, +5 for 2k/4k geometry resolution; 15 on the
Smart-Topology T2 model), Remesh 5, Auto-Rigging 5, Animation 3 per extra action. So **40
credits for the Meshy-7 route, 25 for T2**, against an account balance last recorded at 3,054
and a sprint ceiling of 30 of which 20 are unspent — a new run therefore needs a fresh
approval, per the ledger's one-approval-per-operation rule. **Acceptance gate, all before
integration:** preview image shows a closed mouth and one continuous hair mass; after Remesh
≤ 4,000 triangles and one atlas that survives `optimize_runtime_glb.py --texture 512`;
`aliz_head_probe.py` reports **zero boundary loops on the head** and one shell;
head:height between 1:5 and 1:6.5; the rig passes `test_buddy_avatar.gd` and
`glb_deform_check.py`; the full suite is green; and `aliz_shots.gd` plus the menu shot,
side by side with `aliz_smile_after_*.png`, are judged better by the owner — not by whoever
ran the job.

## 5. Tools added this pass

| Tool | Purpose |
|---|---|
| `tools/aliz_smile_repaint.py` | The mouth. Texture only; SDF smile with round caps; guarded 3D → texel writes. |
| `tools/aliz_fringe_repaint.py` | The fringe edge. Relocates the central forehead triangles to their own island, transfers texels, paints the flat part skin. Its docstring carries the overlap measurement. |
| `tools/aliz_shots.gd` | Front / three-quarter / back at gameplay size under the game's light, deterministic. |
