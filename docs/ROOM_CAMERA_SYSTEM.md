# Room Camera System

**Status:** implemented, Phase 2B. Used by HouseWorld (Chapter 3+).

---

## 1. The problem it exists to solve

The Phase 2A spike proved that **one fixed camera distance cannot frame a room from 1.33:1
(iPad landscape) through 2.17:1 (landscape iPhone)**.

Godot's default `KEEP_HEIGHT` aspect mode fixes the *vertical* FOV, so:

- on a **narrow** screen (iPad 4:3) the room's **width** binds;
- on a **wide** screen (landscape iPhone) the room's **depth** binds.

A distance tuned on one device crops content on the other. This is a real shipping bug class for
a Universal app, not a theoretical one.

## 2. Components

| File | Role |
|---|---|
| `scripts/camera/camera_framing.gd` | **Pure static maths.** No `Camera3D`, no tree, no viewport, no `DisplayServer`. |
| `scripts/camera/safe_area_insets.gd` | Safe-area and game-chrome insets as screen *fractions*. |
| `scripts/camera/room_camera.gd` | `extends Camera3D`. A thin applier — it solves, then assigns. |

Keeping the fitting maths pure is what makes it unit-testable headlessly, the same discipline
that made `CharacterMovementController` testable in the spike.

## 3. Public API

```gdscript
frame_room(framing: Dictionary) -> void
focus_activity(focus: Vector3, radius := DEFAULT_ACTIVITY_RADIUS) -> void
restore_room_frame() -> void
refresh() -> void
```

`focus_activity` takes a **world position**, not a `target_id`: the camera deliberately knows
nothing about rooms or semantic ids, so the caller resolves `"kitchen.fridge"` first.

> **Contract drift:** `docs/PHASE2B_CONTRACT.md` §6 specified `frame_room(room)`. The shipped
> signature takes a framing Dictionary; HouseWorld adapts by passing
> `room.get_camera_framing()`. Recorded so a future consumer does not guess wrong.

## 4. Framing metadata

A room returns plain data and imports nothing from `scripts/camera/`:

```gdscript
func get_camera_framing() -> Dictionary:
    return {
        "bounds": get_floor_bounds(),   # Rect2, world XZ
        "focus": Vector3(cx, floor_y + 0.5, cz),
        "angle": 32.0,                  # degrees above horizontal — keep identical across rooms
        "minDistance": 3.0,
        "maxDistance": 24.0,
        "floorY": get_floor_y(),
        # optional: "headroom", "yaw", "fov", "chromeInsets", "extraPoints"
    }
```

All extras are optional and defaulted, so a room supplying only the five contract keys works.

## 5. The fitting maths

Closed-form, not a scan. The key observation: with the camera at `C = focus + u·d` always looking
down `−u`, the **camera basis does not depend on `d`**. For `q = P − focus`:

```
depth = q·forward + d     (linear in d)
x     = q·right           (constant — right ⟂ u)
y     = q·up              (constant — up ⟂ u)
```

So every edge constraint becomes a plain lower bound on `d`:

```
d ≥ |x| / (half_width  · side_limit) − q·forward
d ≥ |y| / (half_height · side_limit) − q·forward
```

with `half_height = tan(fov/2)` and `half_width = half_height · aspect`. **That single line is
`KEEP_HEIGHT`, and the whole reason narrow screens need more distance.**

`required` = max over all fit points and constraints, then `distance = clamp(required, min, max)`.
"As close as it can be while still fitting" is therefore true **by construction**, not by step
size — and `required` is reported unclamped so `clamped`/`fits` stay meaningful.

Fit points: the four floor corners, the same four at head height, the focus, plus any
`extraPoints`. Floor corners plus headroom suffice because a perspective frustum is convex.

Two extra bounds: nothing may reach the camera plane, and a clearance bound keeps the camera from
sitting at head height inside the room.

### Which dimension binds (4×4 m room, with chrome insets)

| Aspect | Distance | Binding |
|---|---|---|
| 1.334 (iPad 4:3) | 5.24 m | horizontal — room **width** |
| 1.778 (16:9) | 5.21 m | vertical — room **depth** |
| 2.165 (iPhone landscape) | 5.21 m | vertical — room **depth** |
| 1.0 (extreme narrow) | 6.36 m | horizontal — room **width** |

Note the plateau: once depth binds, the depth constraint has no aspect term, so a wider screen
cannot bring the camera closer. Asserted.

## 6. Safe area

Insets are per-edge **fractions of the screen**, never pixels — the fit works in NDC and never
sees a resolution. Screen space is 2 NDC units across, so an inset covering fraction `i` leaves
`1 − 2i` of that side's half-extent.

Each of the four sides is tracked independently, which is exactly what makes **both notch
orientations** work with no special case: notch-left and notch-right produce mirrored `Vector4`s
and, being mirror images, the same fitted distance.

Two sources, combined per-edge with `max`:

- **Platform:** `DisplayServer.get_display_safe_area() ÷ window_get_size()`. Desktop is excluded
  for the same reason `scripts/ui/safe_area.gd` excludes it — macOS reports the safe area in
  screen coordinates, which would inset every Mac render by the menu bar and make screenshots lie.
- **Game chrome:** `(.04, .10, .04, .08)`, derived from the Baby Room's existing top bar and
  prompt panels. Rooms override via `chromeInsets`.

**Insets only push the camera back, never shift it laterally.** Recentring on an asymmetric window
would break "composition stays consistent, only tightness changes" and would put Little Buddy
off-centre when the phone is turned over.

## 7. No manual camera control

No free camera, no rotation gesture, no pinch. A test greps `room_camera.gd` for `_input`,
`_unhandled_input`, `_gui_input` and gesture handling and fails if any appear. A child should
never have to operate a camera.

`frame_room()` connects itself to `size_changed`, so rotation and resizes re-fit automatically.

## 8. Authoring notes that will otherwise bite

1. **`bounds` must include the half-width of anything on the boundary.** The fit guarantees the
   four corner *points*, not geometry straddling them — a render showed corner poles centred
   exactly on `bounds` spilling into the inset bands. Either inset the walls or pad `bounds`.
2. **The camera stands outside the room's near edge** (~2.2 m beyond `+Z` for a 4×4 m room). Do
   not put a solid near wall there; the rooms use an open front. Keep `yaw` identical across
   rooms so transitions do not disorient a child.
3. **`focus` controls composition**, since it is the look-at. If a room reads as sitting too high,
   nudge `focus.z`; do not change `angle` per room.
4. **Never author a `Transform3D` for `WorldCamera` in the `.tscn`.** It is overwritten on every
   fit, and a hand-written one is exactly how the baby, bottle and teddy once ended up entirely
   off-screen while every test passed.

## 9. Two bugs found by testing and looking, not by review

- **`_ensure_wired()` latched even with no viewport.** A camera framed before entering the tree
  would then be permanently deaf to `size_changed` and would crop the first time an iPad rotated
  — invisible to tests and unreproducible on a Mac. It now latches only on success and re-fits on
  `NOTIFICATION_ENTER_TREE`.
- **The projection check originally iterated the module's own fit-point list**, so a fit that
  forgot the head-height corners also forgot to check them — cropping Little Buddy at the neck
  would have stayed green. The test now declares the must-be-visible list independently. This is
  the same class of bug as the shipped camera-pitch inversion.

## 10. Verification

Tested at **1.334, 1.778, 2.167, 3.0 and 1.0**. Verification is deliberately independent of the
solver: the test rebuilds the projection with Godot's own
`Projection.create_perspective(..., flip_fov=false)` and checks NDC with its own arithmetic.

Asserted at every aspect: all corners inside the viewport · nothing under the insets · camera
above the floor and **pitched down** · focus in front of the camera · distance within
[min, max] · closest-that-fits (distance − 0.1 must fail) · identical orientation across aspects.
Plus 9 degenerate framings × 6 bad aspects (zero/negative/NaN/±INF) producing no NaN, no
divide-by-zero and no hang.

**Rendered and inspected** at landscape iPhone and iPad across all four rooms. Composition is
identical between aspects; only tightness differs.

**Not verified:** real `DisplayServer.get_display_safe_area()` values on a device — desktop is
excluded, so only chrome insets apply on macOS. The failure mode there is benign (framed slightly
too tight on one edge, never cropped), because insets can only push the camera back. And whether
a 4-year-old can read the room needs a child, not a render.
