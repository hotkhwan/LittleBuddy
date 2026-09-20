# Aliz — local face and hair pass

**2026-09-20 · zero Meshy credits · zero network calls · no Blender · no regeneration.**

Aliz is the player character and was the weakest thing on screen: a permanent open-mouthed
grin with modelled teeth and a tongue, and a fringe that read as torn pink ribbons over a
bald forehead. Both are fixed, in the shipped asset, from local tooling.

| | Before | After |
|---|---|---|
| Face, close | `docs/shots/aliz_before_face.png` | `docs/shots/aliz_after_face.png` |
| Whole body | `docs/shots/aliz_before_body.png` | `docs/shots/aliz_after_body.png` |
| Real bedroom, in game | `docs/shots/aliz_before_house.png` | `docs/shots/aliz_after_house.png` |

Every one of those six was rendered from the real game through
`res://scenes/spike/shot_harness.tscn` and **looked at**. The before/after house pair was
rendered from a clean worktree at `b53e01e` so the only difference between them is the
asset.

---

## 1. The diagnosis, and where the brief was wrong

The standing record (`FOUNDER_PREVIEW_RELEASE.md` §4) said *"permanent open-mouth grin
(modelled geometry) and real gaps in the hair"*. Half of that is right, and the wrong half
is why the previous attempt failed.

`tools/aliz_screen_probe.py` renders the mesh in software with a z-buffer, so every screen
pixel can be traced back to the triangle and the texel that produced it. Its output matches
the Godot render closely enough to reason from. Two measurements settled it:

**The grin IS geometry.** Down the midline the surface falls from `z = 0.215` to
`z = 0.112` in a single pixel — a **10 cm cavity** in a head 0.28 m deep, with a tongue and
a strip of teeth modelled inside it. No repaint closes that; painting the cavity skin-pink
gives an open mouth full of skin.

**The hair has no holes at all.** Flood-filling the background of that render finds
**zero enclosed background pixels**. Nothing shows through anywhere. The depth buffer shows
the fringe as a few millimetres of relief on one continuous head surface. What reads as a
torn fringe is the *atlas* painting skin over the front of the hair volume, leaving ragged
pink ribbons on a bald forehead — in the bang band, 29,082 skin pixels against 25,168 hair.

So the brief's suggested hair fix — a scalp cap or an inner shell behind the hair — was
**rejected**: it would have added triangles and changed nothing, because there is no hole
for it to sit behind. That is worth recording, because the idea is the obvious one and the
next person will have it too.

## 2. Why a 3D-driven atlas edit works where the UV box failed

`tools/close_aliz_smile.py` selected the mouth with a rectangle on the atlas, caught leg and
dress vertices, and was reverted. Its docstring concluded the atlas was unusable.

It is not. Rasterising every triangle into UV space and recording **every** claimant per
texel gives: **141,206 of 142,116 covered texels belong to exactly one triangle**, and
**zero** texels are shared between regions more than 12 cm apart. The unwrap is fragmented,
but it does not overlap. The rectangle was the mistake, not the atlas.

So the selection is made in **3D** — "the front of the head above the lashes", "the cavity
behind the lips" — and mapped forward to texels. A leg cannot be reached by construction,
and every write is additionally guarded: a texel is written only if every triangle that
strictly contains it lies inside a 0.36 m sphere around the head centre.

Three bugs were found and fixed inside that machinery, each of which left a visible ghost
of the old mouth before it was caught; all three are documented in
`tools/aliz_local_pass.py` at the line that fixes them.

1. Reusing the geometry taper as the paint opacity left the old teeth at 80% opacity.
2. Taking the *first* claimant of a texel rather than the most interior one put upper-lip
   texels at `z = -0.091`, on the back of the skull.
3. Treating a half-texel *gutter* graze from a dress island as ownership refused 600
   legitimate writes.

## 3. What was changed

Only `pinkGirlBuddy_v01.glb` and `pinkGirlBuddy_v01_texture_0.png`, by
`tools/aliz_local_pass.py`.

**Mouth — geometry.** The outer face surface is recovered as a robust quadratic
`z = f(x, y)`, fitted to 44,436 rendered face samples and re-fitted four times while
discarding everything behind it — which is precisely the cavity. The cavity itself is found
by **connectivity flood fill**: 10 seed vertices more than 30 mm behind that surface near
the midline, grown through welded adjacency to any neighbour more than 5 mm behind it. The
lip rim sits *on* the surface, so the fill stops at the mouth opening by itself. 10 seeds
grew to 24 welded vertices (67 raw). Each is then clamped forward onto the surface at full
strength; the largest move is 109 mm. No taper is used and none is needed — a vertex near
the rim is already near the surface and therefore barely moves, so the patch meets the lip
smoothly. Normals in the patch are replaced by the fitted surface's own normal so it lights
like a cheek rather than like a throat.

> A first version used a box with a smoothstep taper instead. It under-moved the corners and
> left a vertex 57 mm behind the face, hidden behind the new lip but still a throat.
> `test_aliz_face.gd` caught it. The flood fill is the replacement.

**Mouth — texture.** The patch is painted skin, and one filled shape in `#9E4F4D` is drawn
as a gently up-curving smile. Art bible §4: *"One filled shape in `#9E4F4D`. No lips, no lip
line, no teeth, no tongue"* and *"**No visible teeth, ever**"*. The grin violated that rule;
the fix is the rule. The shape is a signed distance field feathered over 1.6 mm, because
this patch is reached by three different atlas islands at three different texel densities
and a hard threshold showed the island seams as steps along the lip.

**Fringe — texture.** Front-of-head texels above a gentle arc at `y = 1.418` (the lashes top
out at 1.381) are written in her own hair pink, `(254, 121, 151)`, sampled from her own
crown rather than invented. 12,182 texels. Art bible §4: hair is *"2–5 solid rounded
masses. No hair cards, no alpha, no strands."*

**Edge padding.** The painted colour is grown two texels into unowned atlas — standard bake
hygiene. Near-black texels inside a triangle are unchanged at 427 (those are her eyes and
lashes); in the gutter they fall from 1,727 to 1,514.

**The GLB's embedded copy of the atlas is replaced too.** The import preset is
`gltf/embedded_image_handling=1` (Extract Textures), so Godot pulls the image out of the GLB
into the sibling PNG. Editing only the sibling would leave the GLB still carrying the
grinning atlas, ready to come back on any re-extract.

### What did not change

| | Before | After |
|---|---|---|
| Triangles | 3,898 | **3,898** |
| Vertices | 4,879 | **4,879** |
| Materials | 1 | **1** |
| Atlas | 1 × 512² | **1 × 512²** |
| GLB size | 621,388 B | 614,264 B |
| Bounding box | X ±0.364 Y 0–1.700 Z ±0.276 | **identical** |
| Skin weights, joints, bones, clips | — | **untouched** |

`tools/glb_deform_check.py` reports byte-identical rig metrics before and after: 691
cross-weighted vertices, worst cross-weight 0.4684, 19 head-dominant vertices with non-head
influence, every joint cross-section stable. She still walks and runs.

Her identity is intact: pink hair, bangs, big teal eyes, blush, striped dress.

## 4. Validation

| Gate | Result |
|---|---|
| Full suite, isolated worktree at `b53e01e` + this change | **121 / 121, 0 failures** |
| `smoke_mission01.gd` | **PASS**, exit 0 |
| `smoke_mission01.gd -- snackTime` | **PASS**, exit 0 |
| Godot import | no errors |
| New test fails on the *broken* asset | **yes — both halves fire** |

The suite was run in a clean `git worktree` at `b53e01e` with only this change applied.
The shared checkout has four unrelated failures (`camera_framing`, `ui_palette` on
`baby_face_moods.gd`, `childproof_house`, and a JSON parse error) from other agents' in-flight
edits to files this pass does not own; none of them touch Aliz.

`game/tests/cases/test_aliz_face.gd` is new and is the guard. Neither fix lives in code, so
nothing else in the suite protects them: a careless re-export or a revert would put the
grin back with every other test still green. It asserts two things on the imported mesh —
no vertex in the mouth region sits more than 30 mm behind the front of the face, and the
front of the head above the lashes is at least 90% hair. Both were verified to **fail** on
the original asset (106 mm and 32 offending vertices; 84% hair) and pass on the fixed one
(12 mm, 0 offenders; 99%+ hair). No existing test was weakened.

## 5. Honest verdict

**She is genuinely better, and the two named defects are gone.** Side by side at gameplay
distance the change is not subtle: a gaping mouth with teeth and a tongue becomes a small
closed smile, and a shredded fringe becomes a solid rounded mass. She now passes the art
bible §4 rules she was breaking.

**What this pass does not fix, stated plainly:**

- **Her proportions are still roughly 1 : 3 head-to-height**, against §4's 1 : 6.5 for an
  adult. No local edit changes that. She reads as a stylised child, which is defensible, but
  it is not what the art bible specifies for the caregiver.
- **The thin light lines on the crown remain.** They are specular highlights on creases in
  the generated hair geometry, not texture — the unlit software render of the same frame is
  clean. Fixing them means fixing the hair mesh, which is a regeneration or a retopology
  job.
- **Pre-existing UV seams on the cheeks** are still faintly visible; they were there before
  and are untouched.
- **The fringe edge is a smooth arc** and slightly helmet-like up close. A scalloped edge
  would read more like hair, but it is a painted boundary on geometry that does not agree
  with it, and making it more ornate makes the disagreement more visible.
- Nothing here has been seen on a physical device.

A regeneration with a closed mouth and proper proportions is still the right long-term
answer. This pass makes her presentable without one.

## 6. Tools

New, all dependency-free Python 3, all read-only unless stated:

| Tool | Purpose |
|---|---|
| `tools/aliz_head_probe.py` | GLB read/write, **welds by position** before any topology question. Without welding the index buffer reports 617 shells and claims 4,516 of 4,879 vertices sit on a hole; both are artefacts of UV seams. |
| `tools/aliz_uv_map.py` | Rasterises the mesh into UV space: which 3D point does each texel paint. |
| `tools/aliz_screen_probe.py` | Software z-buffer render. `--mode=color/depth/tri/class`. The instrument the whole diagnosis rests on. |
| `tools/aliz_diagnose.py` | The before/after verdict on both defects, printed from the render. |
| `tools/aliz_local_pass.py` | **The fix.** `python3 tools/aliz_local_pass.py <in.glb> <in.png> <out.glb> <out.png>` |

Three screenshots from the earlier, reverted attempt are **deleted**:
`docs/shots/aliz_face_after.png`, `aliz_hair_after.png` and `aliz_face_before.png`. The two
named "after" are pictures of the open-mouthed grin — they are the after of a change that
was rolled back, nothing references them, and a file called `aliz_face_after.png` showing
the defect is a trap. `aliz_reference_raw.png` is kept; it is a reference image for a
future regeneration, not a mislabelled result.

`tools/close_aliz_smile.py` is **deleted**. It was the abandoned UV-rectangle attempt, and
its docstring asserts as fact that the atlas cannot be edited safely and that the mouth
island is at UV (344, 300)–(368, 324). Both are wrong, and leaving them in the repo is a
trap for whoever reads it next. What it got right — that the grin is geometry and must be
closed before it is painted — is carried forward here and in `aliz_local_pass.py`.

## 7. Restoring

The originals are recoverable from git: `git checkout b53e01e --
game/assets/characters/buddy/pinkGirl/`, then `Godot --headless --path game --import`.
The reimport is required; Godot serves the cached `.scn` otherwise, which silently produced
an unchanged screenshot once during this pass and looked exactly like a failed edit.
