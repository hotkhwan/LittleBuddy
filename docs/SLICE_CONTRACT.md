# "A Day With Little Buddy" — Slice Contract

Shared interface for the overnight production-candidate run. Written before implementation so
agents work in parallel without reading each other's files. Deviate only if you must, and say so.

Baseline protected: Phase 2B, 56/56, tag `phase2b-verified-baseline`, branch
`feature/overnight-production-candidate`.

---

## 1. Chapter 3 level structure — LOCKED

The brief lists 14 beats. They ship as **5 levels** in chapter `ch3`, which is what makes the
20–30 minute target land while keeping each level to the Bible's 4–10 minutes.

| # | levelId | Title | Beats | Rooms |
|---|---|---|---|---|
| L11 | `goodMorning` | Good Morning | wake, walk to bathroom, brush teeth | bedroom → bathroom |
| L12 | `gettingDressed` | Getting Dressed | walk back, choose + wear shirt/pants/shoes | bathroom → bedroom |
| L13 | `breakfast` | Breakfast | walk to kitchen, sit, choose food, eat + drink | bedroom → kitchen |
| L14 | `playTime` | Play Time | walk to living room, teddy + ball + blocks | kitchen → livingRoom |
| L15 | `tidyAndBed` | Clean Up & Good Night | tidy toys away, walk to bedroom, pyjamas, sleep | livingRoom → bedroom |

> `gettingDressed` **already exists** as a Chapter 3 level id promoted from the old
> `morningRoutine` mission. Reuse that id; do not create a second one.

Level 16+ and chapters 4–9 are **out of scope tonight**. Do not author them.

### Star rules (unchanged engine, per level)

★1 core objective · ★2 English listening (`findIt`/`sayIt`) · ★3 optional care/exploration.
★1 must be reachable **by touch alone**. Speech is never required for any star.
Completion (`levelCompleted`) is separate from stars: a skip-through completes and rates 0.

## 2. Semantic ids — the hard rule

Content references targets as `"<roomId>.<targetId>"` — **never** a NodePath, Vector3 or node
name. Existing rooms/targets:

```
bedroom.bed      bedroom.wardrobe    bedroom.toy
bathroom.sink    bathroom.bath       bathroom.towel
kitchen.fridge   kitchen.table       kitchen.counter
livingRoom.sofa  livingRoom.toyBox   livingRoom.book
```
Plus doors: `<room>.doorTo<Room>`.

`ContentValidator` must verify every referenced target id against
`HouseWorld.get_semantic_target_ids()` and **fail loudly** on a miss.

The domain layer (`mission_runner.gd`, `content_library.gd`, `content_validator.gd`,
`task_picker.gd`) must keep **zero** 3D references. `test_architecture_guard.gd` enforces this and
will fail the build if broken.

## 3. Semantic actions — the only way content moves the character

```gdscript
character.move_to("kitchen.fridge")
character.play_action("drink")
```

**Never** an animation filename, never `set_target_position`. Required action vocabulary:

```
idle walk wave point clap pickUp hold give eat drink brushTeeth sit stand hug sleep wake celebrate
```

An action with no clip yet must still start, time out and return to idle — never crash, never
stick. That behaviour already exists; preserve it.

## 4. Save schema v4

Promote world state to top level:

```jsonc
"profileVersion": 4,
"currentRoomId": "bedroom",
"currentSpawnId": "default",
```

Migrations **v1 → v4, v2 → v4, v3 → v4** must all be tested and idempotent. v3 carries
`settings.worldState`; lift it and remove the old key. Invalid room/spawn falls back to the stage
default, ultimately `bedroom`/`default`. **Never** persist a raw `Vector3` as authoritative state.

The real device profile `game/tests/fixtures/device_profile_v1.json` (64 stars, 33 activities,
11 stickers) must survive migration with those three numbers **exactly** unchanged.

Chapter 2 baby save behaviour must not regress.

## 5. Routing

```
Main menu
├── Play (Story)  → ch2 → baby_room.tscn        (caregiver, no locomotion)
│                 → ch3 → house_world.tscn      (toddler, locomotion)
└── Free Play     → house_world.tscn, unlocked rooms, no objective
```

Story Mode uses authored level order. Free Play may randomise compatible activities.
The baby never walks: `baby_room` must acquire no navigation (guard-tested).

## 6. Child UX — binding, from CLAUDE.md

No red X · no score or percentage · no timers · no failure pressure · no dead ends ·
no external links · no purchase prompts · touch fallback always works · speech never required ·
no child audio persisted or uploaded · no network in gameplay.

0-star completion is celebrated, never a failure screen.

## 7. Art direction — from ART_BIBLE_DRAFT.md

Palette is **locked**: `cream #FFF6E5` · `dustyBlue #9AC0D9` · `softPink #FFC1CC` ·
`mint #A8E6CF` · `peach #FFD3B6` · `lavender #D6C7F0` · `ink #59422B`.

`#000000` is banned everywhere. Red is banned as a UI colour. Star gold is `#FFC73D`;
un-earned star is `#E8DCC8`, a warm ghost — never grey, never an empty slot.

Room moods: bedroom `cream+lavender` · bathroom `cream+dustyBlue`, accent mint ·
kitchen `cream+peach`, accent mint · livingRoom `cream+peach`, accent softPink.

One `DirectionalLight3D` per scene. No GI/SSAO/SSR/glow/volumetric/post/alpha/normal maps.
Roughness 0.85–1.0, metallic 0. Rounded forms only; every architectural edge bevelled.
Budgets: character 2,500–4,000 tris · furniture 300–1,500 · hero prop 200–1,000 ·
small prop 40–400. Draw calls ≤ 220.

**Originality is a hard requirement.** No copying Bluey, Toca Boca, Sago Mini, Pixar, Disney,
Peppa Pig, Cocomelon, Animal Crossing, The Sims or any commercial property — including in any
generation prompt. Third-party assets must be **CC0**; Quaternius is excluded.

## 8. Project conventions that have already cost time

- Global `class_name` is unavailable in the headless `--script` runner. Use `preload()`.
- `_ready()` / `_enter_tree()` do **not** fire for nodes added to root there.
- `Node3D.global_position` silently returns (0,0,0) outside the tree — use `spatial_util.gd`.
- Test cases must declare `func run():` **untyped**. A typed `-> Array` returns an empty Array
  when it aborts, so a crashing case reports `[PASS]`. `test_runner_fails_loud.gd` enforces it.
- Export with `./tools/export_ios.sh` — never raw `--export-debug`. It `rm -rf`s `build/ios`.
- **Render and look.** A camera-pitch sign error once put every object off-screen with the whole
  suite green. Tests are not sufficient for anything visual.
- Mutation-test your own work: break a rule, confirm red, revert, confirm green.

## 9. Commands

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import   # generates .uid
```
Baseline **56/56** must never regress.
