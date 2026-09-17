# Navmesh Workflow

**Status:** implemented, Phase 2B. Applies to HouseWorld (Chapter 3+). Chapters 1–2 have no
navigation at all.

---

## 1. The headline

**Editor-time baking is not required.** `NavigationServer3D.parse_source_geometry_data()` and
`bake_from_source_geometry_data()` work fully headless on Godot 4.7.2, so the bake is a
**re-runnable command** rather than "open the editor and click Bake".

That matters for three reasons: a scripted bake can be diffed, repeated on another machine, and
run in CI. The output is `.tres` (text, not binary) for the same reason — the committed
navigation mesh is reviewable in a pull request rather than an opaque blob.

## 2. The command

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
    --script res://../tools/bake_navmesh.gd
```

Writes `game/scenes/house/navmesh/<roomId>_navmesh.tres`, one per room, and prints a report you
are expected to **read**: polygon counts, mesh bounds, and a live reachability probe per room.

Current output: 16–28 polygons per room, 1.2–2.1 KB each.

## 3. Two conditions that cost an hour to find

Both produce a **silent empty mesh** rather than an error, which is why they are written down:

1. **The parse root must be inside a *running* SceneTree.** Called from `_initialize()` it fails
   with *"The root node needs to be inside the SceneTree"* and yields nothing. The bake therefore
   runs from `_process()` on a later frame.
2. **`agent_radius` must be an exact multiple of `cell_size`**, or Godot ceils it to whole voxels
   and warns that it lost precision.

## 4. Collision geometry is authoritative

- `PARSED_GEOMETRY_STATIC_COLLIDERS`, `geometry_collision_mask = 4`.
- Layer discipline: **1 = draggables · 2 = activity targets · 4 = house geometry.** Visual meshes
  are never parsed.

This is the point: the wall the child collides with and the wall the navmesh knows about cannot
drift apart, because they are the same object.

**A post-filter strips non-floor polygons.** Recast will happily bake the top of a wardrobe as a
walkable island; without the filter the child could be asked to walk onto the furniture.

## 5. Room-local baking

Geometry is parsed with the **room** as the parse root, so Godot converts everything into
room-local space and the same mesh is produced whether the room sits at `x = 0` or `x = 30`. The
`NavigationRegion3D` then carries the room's world position.

The tool asserts this: all four rooms are the same 4×4 m shell and must bake to identical bounds.
That assertion is the only thing that would catch this being silently wrong.

## 6. Rebake when

- anything in `house_layout.gd` changes — a room's floor, walls, doors or furniture size/position;
- the agent radius/height, cell size or slope limits change;
- **the Godot version changes** — Recast output is not guaranteed stable across versions.

## 7. Obstacle and transition conventions

- Walls sit **outside** the floor rect, so the walkable edge is identical on all four sides.
- Rooms are **10 m apart along X** so their meshes can never merge into one island. A test asserts
  they are genuinely disconnected — without it, a bug that stacked all four regions on the origin
  would make every room appear walkable from every other, and it did exactly that once (see
  `HOUSEWORLD_ARCHITECTURE.md` §6).
- A door is an `ActivityTarget` with a **closed collision slab**: you walk to it, you do not walk
  through it. Traversal is a transition, never a path.
- Each room owns its own `NavigationRegion3D` on the house's own navigation map RID. The house
  frees that RID on `NOTIFICATION_PREDELETE` — *not* `_exit_tree`, which never fires headlessly
  and leaked.

## 8. No runtime baking, ever

Godot documents runtime baking as a frame-blocking stall, and the mobile perf budget in
`CLAUDE.md` forbids it. **A test greps the shipped house scripts for `bake_*` and
`parse_source_geometry_data`** — baking code may live in `tools/`, never in the game.

A missing bake is a `push_warning` plus the straight-line `NavigationProvider` fallback, so the
child can still walk. A missing navmesh must never be a freeze.

## 9. Headless testing

`NavMapProvider.force_sync()` solves the headless nav-map problem. Reuse it; do not reinvent it.

**The trap it exists for:** a non-zero `map_get_iteration_id()` is **not** proof the map answers.
That assumption once produced a test suite that passed while every query returned "unreachable".
`force_sync()` instead loops `map_force_update()` until `map_get_closest_point_owner()` returns a
valid RID, which is unambiguous, and reports a hard failure if the map never syncs rather than
passing vacuously.

Per-room probes in the bake tool: corner-to-corner crossing succeeds, **every** authored stand
point is reachable, and the inside of a solid object is **not** reachable. The last one is what
catches a mesh that is simply "everything".

## 10. For HouseWorld's successors

The same workflow scales to more rooms unchanged. What will need thought:

- Furniture modelled as real meshes rather than boxes still bakes from its **collision** shapes,
  so keep collision simple and deliberate — it is now load-bearing for navigation, not just
  physics.
- Cell size is currently tuned for 4×4 m rooms. A much larger space should re-check the
  polygon count before assuming it is free.
