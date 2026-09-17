# Phase 2B Contract — HouseWorld Foundation

Shared interface for the Phase 2B agents. Written **before** implementation so three agents can
work in parallel without reading each other's files. If you need to deviate, say so in your
report rather than quietly diverging — a mismatch here costs an integration pass.

**Approved product decision that frames everything:** *the baby does not walk.*

| Chapter | Stage | Interaction model | Locomotion |
|---|---|---|---|
| 1 | Prologue | story / cinematic / light interaction | **none** |
| 2 | Baby Days | caregiver: tap, drag, give, feed, bath, dress, sleep, toys | **none** |
| 3+ | Toddler and older | tap-to-walk, activity targets, room navigation | **core mechanic** |

So `baby_room` keeps its current gameplay untouched and acquires **no** navigation. The Phase 2A
spike is the foundation of **Chapter 3+**, not Chapter 2. HouseWorld is a new, separate world.

> Supersedes `docs/VERTICAL_SLICE_PLAN.md` §4, which specified "one continuous navigable space,
> **not** separate loaded scenes". The product owner has since chosen explicit tappable doors
> with discrete rooms, prioritising reliability, camera framing and child comprehension over
> seamless streaming. That doc is stale on this point only.

---

## 1. Semantic IDs — the rule everything else depends on

Content and domain data reference targets by **semantic id**, never by `NodePath`, never by
scene hierarchy:

```
"<roomId>.<targetId>"      e.g. "kitchen.fridge", "bathroom.sink", "bedroom.bed"
```

Room ids are exactly: `bedroom` · `bathroom` · `kitchen` · `livingRoom` (camelCase, matching the
project's JSON convention).

A JSON file must never contain a `NodePath`, a `Vector3`, or a node name. Moving a fridge across
the kitchen must not touch a single line of content data.

**Architectural guard (binding, and there will be a test):** these files must keep **zero**
direct references to `CharacterBody3D`, `NavigationAgent3D`, `NavigationRegion3D`, `Node3D`,
`Area3D`, `Vector3` or `Transform3D`:

```
game/scripts/gameplay/mission_runner.gd
game/scripts/content/content_library.gd
game/scripts/content/content_validator.gd
game/scripts/content/task_picker.gd
```

They are clean today (verified: 0 references each). Keeping them clean is the single most
valuable structural property this project has.

---

## 2. HouseWorld node structure

```
HouseWorld (Node3D)
├── WorldCamera            (Camera3D + room_camera.gd)
├── Navigation             (NavigationRegion3D per room, or one region; see §5)
├── Rooms
│   ├── Bedroom            (Node3D + room.gd)
│   ├── Bathroom
│   ├── Kitchen
│   └── LivingRoom
├── LittleBuddy            (CharacterBody3D + little_buddy_character.gd, from the spike)
└── RoomTransitionController
```

`ActivityTargets` and `InteractiveObjects` live **inside their room**, not in a global bucket —
a room must be self-contained enough to reason about on its own.

**No new autoload singletons.** Compose; pass references in. `CLAUDE.md` forbids unnecessary
autoloads and every existing system already honours that.

---

## 3. Room contract

Each room exposes (names may differ; shape may not):

```gdscript
func get_room_id() -> String                  # "bedroom"
func get_floor_bounds() -> Rect2              # walkable extent, world XZ
func get_floor_y() -> float
func get_spawn_points() -> Dictionary         # {spawnId: Transform3D-ish}, always includes "default"
func get_spawn_position(spawn_id: String) -> Vector3
func get_activity_targets() -> Array          # the room's ActivityTarget nodes
func get_camera_framing() -> Dictionary       # see §6
func get_doors() -> Array                     # see §4
```

Required per room: walkable region · collision boundaries · camera framing metadata ·
**2–4 ActivityTargets** · clear entrance/exit · a **safe default spawn point**.

Required targets (ids are the `<targetId>` half):

| Room | Targets |
|---|---|
| `bedroom` | `bed`, `wardrobe`, `toy` |
| `bathroom` | `sink`, `bath`, `towel` |
| `kitchen` | `fridge`, `table`, `counter` |
| `livingRoom` | `sofa`, `toyBox`, `book` |

Greybox means correct **scale, collision, navigation and obvious room identity**. Temporary
materials are fine. Do not make them beautiful. Scale reference: the toddler is ~0.85 m tall,
so a door is ~1.9 m, a counter ~0.9 m, a sofa seat ~0.4 m. Rooms roughly 4×4 m.

---

## 4. Room transitions

**Tappable doors, discrete rooms.** Not a seamless open house.

```
tap door → Little Buddy walks to the door's InteractionPoint → short transition
         → spawn at the destination room's entrance spawn → camera reframes → control returns
```

A door is an `ActivityTarget` with a destination:

```gdscript
to_room_id: String        # "bathroom"
to_spawn_id: String       # "fromBedroom"
```

Rules:
- A transition to an unknown room id must be **refused**, not crashed, and must leave the child
  exactly where they were and still in control.
- Control is disabled during the transition and **always** restored — including on the failure
  path. `character.set_disabled(true/false)` already does this and refuses every request while
  disabled.
- Arrival at the destination fires **once**. The spike's arrival-latch discipline applies.
- No dead ends: every room must be reachable from every other room, directly or via one hop.

---

## 5. Navmesh

Replace the spike's runtime grid generation with **baked** navigation meshes.

- **Collision geometry is authoritative.** Bake from collision shapes, not from visual meshes,
  so the wall the child collides with and the wall the navmesh knows about cannot drift.
- **Deterministic and inspectable** — the baked `NavigationMesh` is saved as a committed
  resource, reviewable in a diff and loadable without an editor.
- **No runtime baking.** Godot documents runtime baking as a frame-blocking stall and the
  project's perf budget forbids it.
- The existing **`NavigationProvider` seam stays usable** — its base class is the straight-line
  fallback, so a room whose bake is missing still lets the child walk rather than freezing.
- Tests stay headless where possible. `NavMapProvider.force_sync()` already solves the
  headless nav-map problem; reuse it rather than reinventing it. Note the trap it exists for:
  a non-zero `map_get_iteration_id()` is **not** proof the map answers — that produced a test
  which passed for the wrong reason.

Provide a **repeatable bake command** (a `tools/` script is fine, and is better than
"open the editor and click", because it can be re-run and diffed). Document: bake workflow,
when a rebake is required, obstacle conventions, transition conventions.

If editor-time baking proves impractical headlessly, say so explicitly with what you tried —
do not silently fall back to runtime generation.

---

## 6. Camera

The spike proved a **fixed camera distance cannot frame a room from 1.33:1 to 2.17:1**: Godot's
default `KEEP_HEIGHT` fixes vertical FOV, so width binds on iPad and depth binds on iPhone.

Per-room framing metadata:

```gdscript
{
  "bounds": Rect2,           # what must be visible
  "focus": Vector3,          # look-at point
  "angle": float,            # preferred pitch
  "minDistance": float,
  "maxDistance": float,
}
```

Semantic API (names may differ):

```gdscript
frame_room(room)            # fit this room at the current aspect
focus_activity(target_id)   # optional closer framing on one target
restore_room_frame()
```

Requirements: landscape iPhone **and** iPad · both notch orientations · **no important object
under the UI or outside the safe area** · the child can always see Little Buddy · **no manual
camera rotation, no free camera control**. Re-fit on `size_changed`.

`DisplayServer.get_display_safe_area()` is how this project handles notches;
`scripts/ui/safe_area.gd` covers the 2D layer only, so 3D framing must account for insets itself.

**Renders are the only real check for anything visual here.** A camera-pitch sign error once put
the baby, bottle and teddy entirely off-screen while every automated test passed. Look at images.

---

## 7. ActivityTarget contract

Extend the proven `game/scripts/navigation/activity_target.gd` (Area3D, **collision layer 2** —
draggables are layer 1 and the two must never overlap; a test enforces this):

| Field | Meaning |
|---|---|
| `target_id` | `"fridge"` — the local half |
| `room_id` | `"kitchen"` |
| `interaction_position` | where to stand (via `InteractionPoint`) |
| `facing_direction` / `look_target` | what to face on arrival |
| `supported_actions` | e.g. `["open", "give"]` — semantic names only |
| `required_object` | optional, e.g. `"milk"` |
| `level_tag` / `mission_tag` | optional |

Plus `get_semantic_id() -> String` returning `"kitchen.fridge"`, and a lookup by semantic id that
content can use without touching the tree. **Target ids must be unique** within a room, and
semantic ids unique globally — both tested.

Keep the existing `describe(approach_from)` shape working; the character already consumes it.

---

## 8. Save / world state

**Do not bump the save schema unless genuinely necessary.** It is at v3 and was migrated twice
this week; each bump is a migration to get right and a fixture to maintain.

If world position is persisted, persist **semantic state only**:

```jsonc
"currentRoomId": "bedroom",
"currentSpawnId": "default"
```

**Never a raw `Vector3` as the only recovery mechanism** — a coordinate that drifts out of the
navmesh after a room edit strands the child with no way back.

An unknown or invalid room/spawn must fall back to the room's default spawn, and ultimately to
the bedroom default. Failing that way must be tested, not assumed.

**Chapter 2 baby save behaviour must remain untouched.** `stars`, `completedActivities`,
`starsByLevel`, `levelCompleted` and the sticker thresholds keep working exactly as they do now.

---

## 9. Definition of done

Four greybox rooms, navigable, green.

1. Godot project loads clean
2. Full suite green — **45/45 is the baseline and must not regress**
3. ContentValidator reports 0 problems
4. Screenshots rendered **and looked at** at wide iPhone landscape and iPad landscape
5. iOS export succeeds
6. arm64 Xcode build succeeds
7. Speech plugin/framework **unchanged** — entry symbol registered, `Speech.framework` and
   `AVFoundation.framework` linked, zero source changes

Do **not** claim touch navigation feels good. That needs a child and a device.

---

## 10. Project conventions that have already cost time

- **Global `class_name` is unavailable in the headless `--script` test runner** (no editor
  script-class cache). Use `preload()` constants; a bare `class_name` reference parse-errors the
  entire file.
- **`_ready()` and `_enter_tree()` do not fire** for nodes added to the root in that runner.
  Anything that must be testable needs a lazy wire-on-first-use path.
- **`Node3D.global_position` silently returns (0,0,0)** when not inside the tree — "everything
  is at the origin" instead of a loud failure. `scripts/navigation/spatial_util.gd` exists for
  exactly this.
- **Test cases must declare `func run():` untyped.** A typed `-> Array` returns an *empty Array*
  when it aborts, so a crashing case reports `[PASS]`. `test_runner_fails_loud.gd` enforces this.
- **Mutation-test your own work.** Break each important rule, confirm a test goes red, revert,
  confirm green. Report the table. A test that cannot fail is worthless, and two agents this
  week found surviving mutants in their own suites.
