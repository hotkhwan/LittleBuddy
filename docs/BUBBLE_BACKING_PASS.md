# The need bubble's backing

**2026-09-20. Agent C, on top of `840fd45`.**

Bunny's need line ("I'm hungry!", "I need changing.", the rest of
`child_needs.gd::LINES`) was a bare `Label3D`: ink glyphs with a cream outline
and nothing behind them. Most of the house is cream wall, so the outline and the
wall were the same colour, the outline did nothing, and the line read as loose
brown letters on beige -- `docs/shots/aliz_after_house.png`,
`docs/shots/alt_focus_buddy_ipad.png`, and every `bubble_backing_before_*.png`
below.

It is now a speech bubble: a rounded cream panel with a dusty-blue rim, a soft
warm shadow, and a small tail that leans towards Bunny's head. Nothing about
where the line goes, what it says, how big the type is, or when it appears has
changed. This document is what was built, why it is built the way it is, and the
frames that show it.

---

## 1. What was built

All in `game/scripts/care/child_actor.gd`, in the bubble section; no scene, no
asset, no other script.

### Node structure

```
ChildActor (Node3D)
└── NeedBubble (Label3D)            -- unchanged: text, font size 56, INK on CREAM outline,
    │                                  BILLBOARD_ENABLED, positioned by _place_bubble()
    └── Backing (MeshInstance3D)    -- NEW: one QuadMesh at the label's origin,
                                       ShaderMaterial (BACKING_SHADER), no shadow, no GI
```

The backing is a **child of the label, at its origin**. That is the whole design:

* `_place_bubble()` writes ONE position every frame, `_bubble.position`, and it
  has been wrong twice (`docs/BUBBLE_VERIFICATION.md`). A sibling mirroring that
  position would be a second copy of the answer that can drift from the first. A
  child has no position of its own to get wrong. `test_bubble_placement.gd::
  _test_the_backing_is_one_unit_with_the_line()` moves the caregiver about and
  asserts the panel's world position equals the label's after every placement.
* It inherits `visible`. `_refresh()` throws one switch (now via
  `_apply_bubble_visibility()`) and the panel goes with the line: no second
  switch to forget at the mission beat where the need is satisfied.
  `bubble_backing_after_satisfied_*.png` is that beat; the harness asserts
  `backing.is_visible_in_tree() == false` there rather than only photographing it.
* `Label3D` billboards in its material, not by rotating its node, so the child
  is NOT billboarded by the parent. The shader does its own billboard about the
  same origin (the stock `MAIN_CAM_INV_VIEW_MATRIX` construction), so the two
  always face the camera together.

### Sizing

From the **shaped text**, never `get_aabb()` (empty until the renderer has built
a mesh, i.e. always in the headless runner):

* width: `_bubble_half_width()` -- the existing text-server measurement the
  step rule already trusts, outline included -- plus `BUBBLE_PAD.x` (0.06 m);
* height: `font.get_height(font_size) * pixel_size / 2` plus `BUBBLE_PAD.y`
  (0.04 m), with `BUBBLE_FALLBACK_HALF_HEIGHT` if the font cannot be measured.

Measured only when the text changes (`_backing_fitted_text` guard), so the
per-frame cost is two `set_shader_parameter` calls for the tail and nothing
else. "I'm hungry!" fits a 0.327 x 0.102 m half-extent panel; "I need changing."
a wider one at the same height. `_test_the_backing_is_sized_from_the_shaped_line()`
pins: panel wider than its text on both lines, the long line's panel wider than
the short one's, one height for both, at least `BUBBLE_PAD.x` of padding.

### Why a shader rather than a texture

The panel is drawn at anything from ~190 px/m (a wide room shot) to ~600 px/m
(the iPhone close-up), and its width varies by half again between lines. A
rounded texture stretched to fit smears its corners and thins its rim; a texture
regenerated per need change is a per-pixel GDScript loop on the frame. A signed
distance field is the same quad at every size and every resolution: a rounded
box unioned with a wedge, filled, rimmed where the distance is within
`BUBBLE_RIM` of the edge, laid over the same shape offset and blurred as a
shadow. `fwidth()` gives the anti-aliasing width in screen pixels, so the rim is
one crisp line at 1334x750 and at 2340x1080.

The shader lives in `child_actor.gd` as `BACKING_SHADER` because it is this
file's, its constants are the only thing that tune it, and every uniform is
written from this file. `MAIN_CAM_INV_VIEW_MATRIX` needs Godot 4.3+; the
project is on 4.7.2.

### Colours

All from `palette.gd`, no literals in code (the `ui_palette` scan stays green):

| part   | colour                          | alpha |
|--------|---------------------------------|-------|
| fill   | `Palette.CREAM`                 | 0.94  |
| rim    | `Palette.deep(Palette.DUSTY_BLUE)` (the bible's "deep" derivation) | 1.0 |
| shadow | `Palette.INK`, warm never black | 0.22  |
| text   | unchanged: `INK` on a `CREAM` outline |     |

### The tail

A wedge (`BUBBLE_TAIL_HALF_BASE` 0.038 m, `BUBBLE_TAIL_LENGTH` 0.065 m) on the
bottom edge. `_aim_bubble_tail()` takes the vector from the panel to Bunny's head
(`CHILD_HEAD_HEIGHT` 0.72 m over his origin), projects it onto the camera's right
and up (the quad's own axes once billboarded), starts the wedge where that line
crosses the bottom edge (clamped clear of the rounded corners) and runs it a
fixed short length along that line -- **never to the head**. So when the step
rule has moved the line 0.7 m sideways to clear Aliz, it still visibly belongs
to him (`bubble_backing_after_front_*.png`), and when she is clear and the line
is over his own head the tail points straight down (`..._abeam_*.png`).

---

## 2. Render ordering

Transparent geometry sorts by `render_priority` first and by depth second, and
the panel, the glyph outline and the glyphs share one origin, so depth cannot
separate them. The order is stated in three constants and asserted by
`_test_the_text_draws_over_the_backing()`:

| draw            | `render_priority` |
|-----------------|-------------------|
| backing panel   | 0 (`BUBBLE_BACKING_RENDER_PRIORITY`) |
| glyph outline   | 1 (`Label3D.outline_render_priority`, default was -1) |
| glyphs          | 2 (`Label3D.render_priority`, default was 0) |

The label's two priorities were raised ABOVE the panel rather than the panel
pushed below -1, so the bubble as a whole still sorts by depth against the
room's other transparent things (tap ripples, drop zones) instead of always
losing to them.

Depth: the panel is depth-**tested** like the label (neither sets
`no_depth_test`; the test asserts the shader has no `depth_test_disabled`) and,
like every alpha-blended material, does not write depth (`depth_draw_never`).
So a wall between the camera and the bubble hides panel and text together
rather than one showing through where the other does not.

Budget: one alpha-blended quad; `unshaded`, `shadows_disabled`,
`ambient_light_disabled`, `specular_disabled`, `fog_disabled`,
`cast_shadow = OFF`, `gi_mode = DISABLED`, no texture read.

---

## 3. `set_bubble_suppressed()` (added at the lead's request)

```gdscript
func set_bubble_suppressed(suppressed: bool) -> void
func is_bubble_suppressed() -> bool
```

While suppressed the line and its backing are hidden whatever the need is, and
`_refresh()` / `live()` / a need change during suppression do not re-show it.
Un-suppressing restores the ordinary rule (`visible = not _need.is_empty()`)
**immediately** -- `_apply_bubble_visibility()` runs in the setter, not at the
next need change -- and re-places the line the same frame so it does not
reappear where it was before the camera moved. The need itself is untouched.

Reason: the feeding close-up puts the camera on Bunny and his 3D "I'm hungry!"
was showing through the care overlay's top band, over-printing the hint text.
The director is to wrap the overlay in this; that call is in a file this pass
does not own and is **not** made here.

Asserted by `_test_it_can_be_suppressed_and_comes_straight_back()`.

---

## 4. Tests

```
Godot --headless --path game --import
Godot --headless --path game --script res://tests/run_tests.gd
```

* before this pass, on `840fd45`: `PASS - 122 case(s), 0 failure(s)`
* after: `PASS - 122 case(s), 0 failure(s)`

The count is unchanged because the four new assertions live inside the existing
`bubble_placement` case (`game/tests/cases/test_bubble_placement.gd`):
`_test_the_backing_is_one_unit_with_the_line`,
`_test_the_backing_is_sized_from_the_shaped_line`,
`_test_the_text_draws_over_the_backing`,
`_test_it_can_be_suppressed_and_comes_straight_back`. No existing assertion
was touched. The `architecture_guard` and `ui_palette` scans stay green.

---

## 5. The frames

`game/tests/shots_bubble.gd`, which drives the real `house_world.tscn`, the real
`imHungry` mission and the director's own close-up (see its header and
`docs/BUBBLE_VERIFICATION.md`). Three additions to the harness:

* a third argument, the file-name prefix, so before and after can sit side by
  side;
* `_check_faces()`: the panel's rectangle is projected into the frame and the
  run FAILS if Bunny's face (0.62 m) or Aliz's face (1.45 m) is inside it;
* a sixth staging, `satisfied`: `satisfy("hungry", 70.0)` exactly as the beat
  calls it, then assert the line and the backing are gone, then photograph.

```
Godot --path game --script res://tests/shots_bubble.gd -- ipad   1334x750  bubble_backing_before
Godot --path game --script res://tests/shots_bubble.gd -- iphone 2340x1080 bubble_backing_before
Godot --path game --script res://tests/shots_bubble.gd -- ipad   1334x750  bubble_backing_after
Godot --path game --script res://tests/shots_bubble.gd -- iphone 2340x1080 bubble_backing_after
```

All four runs: `BUBBLE SHOTS OK -- every staging measured and photographed.`
Renderer in every run: `Metal 4.0 - Forward Mobile` (the project's Mobile
renderer). Every PNG's size was read back off the written image.

| staging | iPad 1334x750 | iPhone 2340x1080 |
|---|---|---|
| front (the real beat) | `bubble_backing_before_front_ipad.png` / `..._after_front_ipad.png` | `..._before_front_iphone.png` / `..._after_front_iphone.png` |
| left | `..._before_left_ipad.png` / `..._after_left_ipad.png` | `..._before_left_iphone.png` / `..._after_left_iphone.png` |
| right | `..._before_right_ipad.png` / `..._after_right_ipad.png` | `..._before_right_iphone.png` / `..._after_right_iphone.png` |
| abeam | `..._before_abeam_ipad.png` / `..._after_abeam_ipad.png` | `..._before_abeam_iphone.png` / `..._after_abeam_iphone.png` |
| longline | `..._before_longline_ipad.png` / `..._after_longline_ipad.png` | `..._before_longline_iphone.png` / `..._after_longline_iphone.png` |
| satisfied | `..._before_satisfied_ipad.png` / `..._after_satisfied_ipad.png` | `..._before_satisfied_iphone.png` / `..._after_satisfied_iphone.png` |

All in `docs/shots/`. Every one was opened and looked at, not only measured.

### What the after frames show

* **Legibility.** In every frame the line sits on a cream panel with a visible
  blue rim against the cream wall, the wardrobe and the door -- the contrast
  problem in the before frames is gone at both viewports.
* **Faces.** Measured rectangle of the panel versus the two face points, from
  the run logs (iPad; iPhone in proportion):
  front `(780,238)-(986,302)` vs Bunny `(667,376)`, Aliz `(667,87)`;
  left `(717,238)-(923,302)` vs `(725,376)`, `(611,87)`;
  right `(411,238)-(617,302)` vs `(609,376)`, `(723,87)`;
  abeam `(783,236)-(986,299)` vs `(867,373)`, `(473,87)`;
  longline `(780,238)-(1054,302)` vs `(667,376)`, `(667,87)`.
  Neither face is inside any rectangle; the pictures agree.
* **Placement rule intact.** `bubbleWorldDX` values are identical to the before
  run to the centimetre (+0.69 front, opposite-sign to `alizDX` in left/right,
  0.00 abeam): the step maths was not touched and the panel moved with the label.
* **Text over panel.** The ink glyphs are on top of the cream in every frame
  (a wrong priority would have shown a cream rectangle with the line inside it).
* **Gone when satisfied.** `bubble_backing_after_satisfied_*.png`: need `''`,
  `bubbleVisible=false`, `backingVisibleInTree=false`, Bunny delighted, no
  panel anywhere in the frame.

---

## 6. A harness fix found on the way

The first after run sat for minutes with the scene composed and no frame
written. Instrumenting it showed `process_frame` ticking (2000+ frames) while
`RenderingServer.frame_post_draw` had stopped firing after 52 draws: macOS
stops Godot's ordinary draw loop while the window is occluded (another window
in front, the display asleep -- the machine was unattended), and the harness
awaited a signal that then never comes. `_shot()` now draws on demand with
`RenderingServer.force_draw(true, 0.0)` after one `process_frame`, which renders
the SubViewport whether or not anyone can see the window. Both after runs then
completed in ~10 s. The other `shots_*.gd` harnesses still `await
frame_post_draw` and will show the same symptom under the same conditions; not
changed here, they are not this pass's files.

---

## 7. Not verified

* **No physical device.** Everything above is the Forward Mobile renderer on
  Metal on a Mac. The shader uses nothing exotic (`fwidth`, a few dot products)
  but it has not been run on an iPad or an iPhone.
* **The director does not yet call `set_bubble_suppressed()`.** The API and its
  test exist; the wiring around the care overlay belongs to the lead.
* **A wall between camera and bubble.** The depth reasoning in §2 is by
  construction, not photographed; no staging puts geometry in front of the line.
* **Other rooms.** Only the bedroom close-up was photographed, as before. The
  panel's colours are constants, not sampled from the wall, so a differently
  coloured room changes the contrast but not the mechanism.
