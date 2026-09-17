# HouseWorld Architecture

**Status:** implemented and **reachable from the game**. Four greybox rooms, navigable, with
Chapter 3 routed into them. See §8 for exactly what is and is not done.
**Scope:** toddler-stage (Chapter 3+) spatial gameplay. Chapters 1–2 do not use this at all.

---

## 1. The decision this rests on

**The baby does not walk.**

| Chapter | Interaction model | Locomotion |
|---|---|---|
| 1 — Prologue | story / cinematic / light interaction | none |
| 2 — Baby Days | caregiver: tap, drag, give, feed, bath, dress, sleep, toys | none |
| 3+ — Toddler and older | tap-to-walk, activity targets, room navigation | **core mechanic** |

So HouseWorld is a **new world**, not a `baby_room` refactor. `baby_room` keeps its current
gameplay and never acquires navigation. `test_architecture_guard.gd` pins this: every `.gd` and
`.tscn` under `scenes/baby_room`, `scripts/baby` and `scripts/activities` is scanned for
`CharacterBody3D` / `NavigationAgent3D` / `NavigationRegion3D`, and a mutation adding one to
`teddy.gd` turns it red. The separation is an asserted invariant, not an intention.

## 2. Node structure

```
HouseWorld (Node3D, scripts/house/house_world.gd)
├── WorldEnvironment, DirectionalLight3D   one each — the mobile perf budget
├── WorldCamera                Camera3D; scripts/camera/room_camera.gd adopted at RUNTIME
├── Navigation                 4x NavigationRegion3D, one per room, built in code
├── Rooms
│   ├── Bedroom · Bathroom · LivingRoom · Kitchen      (scripts/house/room.gd)
├── LittleBuddy                CharacterBody3D + scripts/character/little_buddy_character.gd
│   ├── CollisionShape3D (capsule r0.16 h0.8) · NavigationAgent3D
│   └── ToddlerView            scripts/character/toddler_view.gd   ← TEMPORARY
├── NavigationController       the Phase 2A spike's, unchanged
├── RoomTransitionController   scripts/house/room_transition_controller.gd
└── UI (CanvasLayer)           fade + status label
```

Supporting scripts: `house_layout.gd` (all room geometry — one source of truth shared by the
scene builder, the navmesh bake and the tests), `world_state.gd`, `room_framing.gd` (fallback
camera fit used when the room camera is absent).

**No new autoload singletons.** Everything is composed and passed in, per `CLAUDE.md`.
`ActivityTargets` and `InteractiveObjects` live *inside their room*, not in a global bucket, so a
room is self-contained enough to reason about alone.

The character is the **spike's, unforked**. Everything proven in Phase 2A — the arrival latch,
path replacement, unreachable refusal, the String-only semantic API — applies unchanged.

## 3. Rooms

Rooms sit **10 m apart along X** so their navigation meshes can never merge into one island:
bedroom `x=0`, bathroom `x=10`, livingRoom `x=20`, kitchen `x=30`. A test asserts they are
genuinely disconnected.

Each room: 4×4 m floor at `y=0`, walls **outside** the floor rect so the walkable edge is
identical on all four sides, back and two side walls 2.2 m, and an **open front** for the camera.

Scale: toddler 0.85 m · door 0.9 × 1.9 m · counter 0.9 m · sofa 0.75 m · fridge 1.7 m.

| Room | Furniture targets | Doors | Spawns |
|---|---|---|---|
| `bedroom` | bed, wardrobe, toy | →kitchen, →bathroom | default, fromBathroom, fromKitchen |
| `bathroom` | sink, bath, towel | →bedroom, →livingRoom | default, fromBedroom, fromLivingRoom |
| `livingRoom` | sofa, toyBox, book | →bathroom, →kitchen | default, fromBathroom, fromKitchen |
| `kitchen` | fridge, table, counter | →livingRoom, →bedroom | default, fromLivingRoom, fromBedroom |

**Ring topology** — bedroom → bathroom → livingRoom → kitchen → bedroom. No dead ends; every
room is at most one intermediate hop from any other. Tested.

20 semantic ids, all unique, all on collision layer 2. Every stand position and spawn is asserted
to lie inside the walkable floor. The default spawn faces the open front so the camera sees a
face rather than the back of a head.

## 4. Transitions

Tappable doors, discrete rooms — **not** a seamless open house. (This supersedes
`VERTICAL_SLICE_PLAN.md` §4, which argued for one continuous space; see §9 there.)

A door is an `ActivityTarget` carrying `to_room_id` / `to_spawn_id`. The controller listens for
the character's **`interaction_ready`**, not `arrived` — standing at the door *and facing it*.

```
request_transition(to_room_id, to_spawn_id)
  → _in_transition latch  → set_control(false)  → validate
  → world.place_in_room() → restore control     → transition_completed
                          ↘ on any failure      → transition_refused(reason)
```

Refusal reasons: `unknownRoom` · `busy` · `notBound` · `placementFailed`.

Two properties worth stating because they are what makes it safe for a child:

- **Control is restored on every exit path, including failure.** A refusal leaves the child on
  the exact same coordinate, un-disabled, not busy, able to walk immediately. All four asserted.
- **The transition is synchronous; the fade is cosmetic and runs after control returns.** A tween
  that never completes (no tree, no frames) therefore cannot strand a child.

Re-entrancy — requesting a transition from inside `transition_started` — is refused `busy`, so a
door emits exactly one completion.

Only the current room is visible, has enabled targets, and has its targets registered with the
character. A target in another room fails as "never heard of it" rather than "known but switched
off", which is the clearer failure.

## 5. World state

Semantic only, per the contract:

```jsonc
"currentRoomId": "bedroom",
"currentSpawnId": "default"
```

**No raw `Vector3` as the only recovery mechanism** — a coordinate that drifts outside the
navmesh after a room edit would strand the child with no way back. An unknown room or spawn falls
back to the room default, and ultimately the bedroom default. That fallback is tested, not
assumed.

**Now stored as top-level `currentRoomId` / `currentSpawnId` in save schema v4.**
`settings.worldState` is retained for one release as a read-compatibility mirror and is no
longer the authority. It was deliberately not deleted in the same commit: `world_state.gd` was
its only reader, and removing the key while that was still true would have stranded every
HouseWorld restore in the bedroom **with the whole suite green** — the worst possible failure
shape. Flipping `ProfileStore.DROP_LEGACY_WORLD_STATE` finishes the job and is pre-tested.

> Historical note, kept because the bug was invisible: `world_state.gd` originally read *only*
> `settings.worldState`, which `ProfileStore` never creates. The house therefore saw nothing in a
> fresh v4 profile and would have woken every returning child in the bedroom — undetectably,
> because the bedroom is also the correct answer for a profile that has never been in the house.

Migrations v1→v4, v2→v4 and v3→v4 are built as a **chain** rather than three jumps, so there is
no fourth code path to drift, and idempotency is asserted over three passes because two-pass
stability can be an accident. Shape validation upstream means a persisted `Vector3`, Array or
compound id can never become a location.

Persistence is **caller-driven** (`write_into_profile()` / `restore_from_profile()`); the house
does not call `SaveService` itself.

## 6. Two navigation bugs worth remembering

Both made tests pass *for the wrong reason*, which is the dangerous kind:

1. **`NavigationRegion3D` only pushes its transform to the server while inside the tree.** In the
   headless runner, nodes added to the root are not inside the tree, so a position set after
   `add_child` was dropped and **all four rooms' meshes stacked on the origin** — every room
   looked walkable from every other. Fixed by setting position *before* `add_child` plus an
   explicit `region_set_transform()`.
2. **`NavMapProvider.get_map()` only trusts an in-tree agent**, so the character's provider
   resolved an invalid map, reported "not ready", and every path silently degraded to a straight
   line through walls. Fixed by binding the provider to the map RID via `set_navigation_provider()`.

Both now have mutants that go red.

## 7. Known contract drift

`docs/PHASE2B_CONTRACT.md` §6 specified `frame_room(room)`; the shipped camera takes
`frame_room(framing: Dictionary)`. HouseWorld adapts by passing `room.get_camera_framing()`.
Recorded here so a third consumer does not guess wrong.

## 8. Status

**HouseWorld is reachable.** `main.gd` routes ch1/ch2 to the Baby Room and ch3 to HouseWorld, with
Free Play entering the house directly. Chapter 3 content exists: five chained levels
(`goodMorning`, `gettingDressed`, `breakfast`, `playTime`, `tidyAndBed`), ~29 minutes, every level
completable to 3/3 by touch alone.

Routing had to do more than read the saved chapter: `set_current_chapter()` was called nowhere in
the project, so a fresh profile is written `"ch1"` and stays `"ch1"` forever. Reading it alone
would have left ch3 permanently unreachable however much of ch2 a child played. The chapter is now
trusted when it names an unlocked, unfinished chapter and recomputed from `levelCompleted`
otherwise.

Still outstanding: no journey map, no final art, and `toddler_view.gd` remains explicitly
temporary engineering art.

See `docs/NAVMESH_WORKFLOW.md` and `docs/ROOM_CAMERA_SYSTEM.md` for the two subsystems.
