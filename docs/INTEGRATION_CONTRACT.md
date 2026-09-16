# Little Buddy — Integration Contract (orchestrator-owned)

This file is the single source of truth for cross-agent APIs. Sub-agents code against it.
Only the orchestrator edits this file and `game/project.godot`.

## Godot project root

`game/` is the Godot project root. `res://` == `game/`.

## Autoloads (declared by orchestrator in project.godot)

| Name | Script |
|---|---|
| `SaveService` | `res://scripts/save/save_service.gd` |
| `SpeechService` | `res://scripts/speech/speech_service.gd` |
| `TtsService` | `res://scripts/speech/tts_service.gd` |

No other autoloads.

## SaveService (Node)

```gdscript
signal profile_changed(profile: Dictionary)
signal stars_changed(stars: int)

func get_stars() -> int
func add_stars(amount: int) -> int          # returns new total, persists
func mark_activity_completed(activity_id: String) -> void
func is_activity_completed(activity_id: String) -> bool
func get_setting(key: String, default_value: Variant = null) -> Variant
func set_setting(key: String, value: Variant) -> void
func save_profile() -> bool
func reload_profile() -> void
func reset_profile() -> void
func get_profile() -> Dictionary             # deep copy
```

Save path: `user://profile.json`. Schema keys are camelCase.

## ProfileStore (RefCounted, `class_name ProfileStore`)

Pure, testable persistence logic used by `SaveService`.

## SpeechService (Node)

```gdscript
signal availability_changed(available: bool)
signal permission_result(granted: bool)
signal listening_started()
signal listening_stopped()
signal recognized(text: String)              # final transcript
signal recognition_failed(reason: String)

func is_available() -> bool
func has_permission() -> bool
func request_permission() -> void            # async -> permission_result
func start_listening(locale: String = "en-US") -> void
func stop_listening() -> void
func is_listening() -> bool
func get_backend_name() -> String            # "ios" | "mock" | "unavailable"
```

`recognition_failed` is never fatal. Gameplay must stay fully playable by touch.

## IntentMatcher (RefCounted, `class_name IntentMatcher`, static only)

```gdscript
static func normalize(text: String) -> String
static func matches(transcript: String, accepted_commands: Array, target_words: Array) -> bool
static func match_activity_id(transcript: String, activities: Array) -> String   # "" if none
```

## TtsService (Node)

```gdscript
signal speech_finished(text: String)
signal speech_started(text: String)

func speak(text: String, interrupt: bool = true) -> void
func stop() -> void
func is_available() -> bool
```

Must always emit `speech_finished` even when no TTS voice exists (timed fallback), so
gameplay sequencing never deadlocks.

## Content

`res://content/feeding/feed_milk.json` — schema per `LITTLE_BUDDY_TONIGHT.md` §7, camelCase keys.

## Scenes

| Path | Owner |
|---|---|
| `res://scenes/main/main.tscn` | foundation (project main scene, `Node3D` root) |
| `res://scenes/baby_room/baby_room.tscn` | gameplay (`Node3D` root) |

`main.tscn` must guard the baby-room load with `ResourceLoader.exists()`.

## Presentation: lightweight stylized 3D (supersedes the earlier 2D plan)

Domain layers stay **engine-agnostic and unchanged**: `scripts/save/**`, `scripts/speech/**`,
`scripts/activities/**`, `scripts/rewards/**`, `scripts/baby/baby_state.gd`, `content/**`, `tests/**`.
Only the *view* changes. Gameplay logic must never reference 3D node types directly.

- Renderer: **Mobile** (`rendering_method="mobile"`, `rendering_method.mobile="mobile"`).
- Scene roots are `Node3D`. All 2D/child-facing UI lives on a `CanvasLayer` overlay
  (speech bubble, star counter, mic button, fallback UI).
- Meshes: **built-in primitives only** tonight (`SphereMesh`, `BoxMesh`, `CapsuleMesh`,
  `CylinderMesh`, `PlaneMesh`, `TorusMesh`) so missing final art never blocks the build.
  Later these are swapped for GLB/GLTF **without changing gameplay logic**.
- Camera: one fixed `Camera3D`, roughly `position (0, 1.6, 3.4)`, looking at `(0, 1.0, 0)`, fov ~50.
- Lighting budget: **exactly one** `DirectionalLight3D`. Minimal real-time shadows.
  `WorldEnvironment` with flat colour/simple sky + ambient colour only.
- Explicitly forbidden: GI/SDFGI/VoxelGI/LightmapGI, SSAO, SSIL, SSR, glow, volumetric fog,
  post-processing dependencies, heavy physics (`RigidBody3D` simulation), particles.
- Interaction: `Area3D` with `input_ray_pickable = true` and the
  `input_event(camera, event, position, normal, shape_idx)` signal, which works with touch
  because `pointing/emulate_mouse_from_touch=true`. `baby_room.gd` must ALSO provide an
  explicit `Camera3D.project_ray_origin/normal` + `PhysicsDirectSpaceState3D.intersect_ray`
  fallback so a missed pick never leaves the child stuck.
- Interactive objects: `MilkBottle` (`Area3D`) and `Teddy` (`Area3D`).
- `AnimationPlayer` drives simple baby reactions (idle / hungry / drinking / happy).

### Interactive object contract

```gdscript
# MilkBottle (Area3D)
signal delivered
func set_enabled(enabled: bool) -> void
func reset_position() -> void

# Teddy (Area3D)
signal comforted
```

`Teddy` is a tap-to-react comfort object only: it plays a happy reaction and speaks the word
"Teddy". It awards **no** stars and is **not** a new activity — `feedMilk` remains the only
scored activity tonight.

## Tests

Runner: `godot --headless --path game --script res://tests/run_tests.gd`

Each case lives in `res://tests/cases/test_*.gd`:

```gdscript
extends RefCounted

func test_name() -> String:
	return "intent_matcher"

func run() -> Array:      # array of failure strings; empty == pass
	return []
```

Cases must not depend on autoloads (runner uses `--script`, which does not load them).

---

# Child-facing MVP round (2026-09-17)

Scope split — these three write scopes MUST NOT overlap:

| Agent | Owns |
|---|---|
| SPEECH | `ios/speech_plugin/**`, `game/scripts/speech/**` |
| INTERACT | `game/scenes/baby_room/**`, `game/scripts/activities/**`, `game/scripts/rewards/**`, `game/scripts/interaction/**`, `game/tests/cases/test_drag_*.gd` |
| VISUAL | `game/scripts/baby/**`, `game/scenes/nursery/**` |

Orchestrator owns `game/project.godot`, `game/export_presets.cfg`, `tools/**`, `docs/**`, `build/**`.

## BabyView3D contract (VISUAL provides, INTERACT consumes)

`res://scripts/baby/baby_view_3d.gd`, `class_name BabyView3D extends Node3D`:

```gdscript
func set_view_state(state: String) -> void
    # "idle" | "hungry" | "drinking" | "happy" | "hugging"
func get_view_state_name() -> String

func get_mouth_position() -> Vector3   # GLOBAL position of the baby's mouth
func get_hug_position() -> Vector3     # GLOBAL position of the baby's chest/arms
```

The baby stands at the scene origin, roughly 0.6–0.8 m tall, facing +Z (toward the camera).
`get_mouth_position()` / `get_hug_position()` must stay correct if VISUAL changes proportions —
INTERACT positions its drop zones from these at runtime and must never hardcode them.

## Nursery props (VISUAL provides, INTERACT instantiates)

`res://scenes/nursery/nursery_props.tscn`, root `Node3D`. Contains ONLY set dressing:
floor, walls, crib, rug, shelf/toy box, `WorldEnvironment`, and the single `DirectionalLight3D`.

It must contain **no** camera, no UI, no `Area3D`, and nothing interactive.
It must leave the volume around the origin (x -0.8..0.8, y 0..1.0, z -0.4..0.8) clear for
the baby, bottle and teddy. INTERACT loads it guarded by `ResourceLoader.exists()`.

## Interactive objects (INTERACT owns)

```gdscript
# MilkBottle (Area3D) and Teddy (Area3D)
signal delivered          # MilkBottle: reached MouthDropZone
signal comforted          # Teddy: reached HugDropZone, or tapped
func set_enabled(enabled: bool) -> void
func reset_position() -> void
```

Drop zones `MouthDropZone` / `HugDropZone` are `Area3D`s positioned each frame (or on ready)
from `BabyView3D.get_mouth_position()` / `get_hug_position()`.

## Speech (SPEECH owns, INTERACT consumes)

`SpeechService` API is unchanged. INTERACT must drive the listening UI from the existing
signals — `listening_started` → show "I'm listening...", `listening_stopped` → clear it:

```gdscript
signal listening_started()
signal listening_stopped()
signal recognized(text: String)
signal recognition_failed(reason: String)
signal permission_result(granted: bool)
func start_listening(locale: String = "en-US") -> void
```

Touch gameplay must remain fully playable when speech is unavailable, denied, or errors.

---

# Overnight build waves (2026-09-17, authoritative for the overnight run)

This section SUPERSEDES the narrower "Child-facing MVP round" scope table above and
supersedes any narrower scope in `.claude/agents/*.md` for the duration of the overnight
build described in `CLAUDE_OVERNIGHT_BUILD.md`. Agents assigned a scope here are
explicitly authorised to write in it.

| Role | Wave | Exclusive write scope |
|---|---|---|
| SPEECH | 1 | `ios/speech_plugin/**`, `game/scripts/speech/**` |
| INTERACT | 1 | `game/scenes/baby_room/**`, `game/scripts/activities/**`, `game/scripts/rewards/**`, `game/scripts/interaction/**` |
| VISUAL | 1 | `game/scripts/baby/**`, `game/scenes/nursery/**` |
| CONTENT | 1 | `game/content/**`, `game/scripts/content/**`, `game/tests/cases/test_content_*.gd` |
| ACTIVITIES | 2 | `game/scenes/activities/**`, `game/scripts/gameplay/**` |
| PROGRESSION | 3 | `game/scripts/progression/**`, `game/scenes/progression/**` |
| AUDIO | 3 | `game/audio/**`, `game/scripts/audio/**` |
| PARENT_UI | 3 | `game/scenes/parent/**`, `game/scripts/parent_settings/**` |

Orchestrator owns `game/project.godot`, `game/export_presets.cfg`, `game/tests/run_tests.gd`,
`tools/**`, `docs/**`, `build/**`, and all git operations.

`game/content/feeding/feed_milk.json` is a live consumed contract: its existing top-level keys
may be ADDED to but never removed or renamed.
