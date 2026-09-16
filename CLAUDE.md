# Little Buddy — Claude Code Project Instructions

## Mission
Build an offline-first iPad MVP for a child-friendly English learning game. The player cares for a baby character and learns English through listening, touch interaction, and simple voice commands.

Read `LITTLE_BUDDY_TONIGHT.md` before implementation.

## Tonight's Definition of Done
1. Godot project opens without errors.
2. Game runs locally on macOS from Godot.
3. One playable Baby Room exists.
4. Baby has a hungry state.
5. Child can tap/drag milk to feed baby.
6. At least one English prompt is spoken locally.
7. Speech layer has a clean interface and fallback.
8. If iOS speech is available, `milk` and accepted phrases map to `feedMilk`.
9. If speech is unavailable/denied, touch gameplay remains complete.
10. Stars/progress save locally in `user://`.
11. No network dependency.
12. Project is exportable to Xcode/iPad.

TestFlight is not required tonight. Direct Xcode install to the physical iPad is preferred.

## Hard Scope
Do not add backend, Cloudflare, Fly.io, authentication, ads, IAP, multiplayer, analytics, generative AI conversation, or production artwork tonight.

## Architecture
- Godot 4.x + GDScript
- Lightweight stylized **3D** presentation (superseded the original 2D-only plan on 2026-09-16)
- **Mobile** renderer
- `Node3D` scene roots; all child-facing UI on a `CanvasLayer` overlay
- Built-in primitive meshes tonight; swap for GLB/GLTF later without changing gameplay logic
- Performance budget: low-poly, simple materials, max 1 `DirectionalLight3D`, minimal
  real-time shadows, no GI/SSAO/SSR/glow/volumetric fog/post-processing, no heavy physics
- Domain logic (save, speech, intent matching, content, activity state machine, baby stats)
  stays engine-agnostic and must never reference 3D node types
- Landscape iPad first
- Offline-first
- Bundled core content
- No persisted/uploaded child microphone audio
- Data-driven lessons
- Local save only
- Large child-friendly touch targets

## Code Style
- JSON keys: camelCase
- GDScript: follow Godot snake_case conventions
- Prefer composition/signals over deep inheritance
- Keep scripts small and focused
- Avoid unnecessary autoloads/singletons
- No network calls in gameplay code

## MVP Flow
Baby hungry -> "I'm hungry." -> milk visible -> child selects milk -> "Can you say milk?" -> optional speech -> `feedMilk` -> baby drinks -> hunger decreases -> stars +1 -> "Thank you!"

Accepted phrases:
- milk
- give milk
- give baby milk
- give the baby milk
- give the baby some milk
- baby wants milk

Touch fallback must always work.

## Local Save
Minimum schema:
```json
{
  "profileVersion": 1,
  "stars": 0,
  "completedActivities": [],
  "settings": {
    "speechLocale": "en-US",
    "speechEnabled": true,
    "thaiHints": true
  }
}
```
Handle missing/corrupt files by restoring safe defaults.

## Child UX
- No red X for mistakes
- No pronunciation score/percentage
- Use short encouragement: Great!, Nice!, Try again!
- No timers/failure pressure
- No external links
- No purchase prompts

## Agent Strategy
Use project subagents when tasks are independent. Never let two agents edit the same files concurrently. The main Claude session owns integration/shared project files.

Preferred delegation:
- `foundation`: project bootstrap and main scene
- `gameplay`: baby room, baby state, feeding, stars
- `content`: feeding JSON and placeholder assets
- `speech`: speech abstraction + iOS bridge/fallback
- `save`: local persistence
- `qa`: read-only integration review

Native iOS speech must not block the MVP. A mock/fallback speech implementation is mandatory.

## Validation
Before claiming completion:
- run Godot headless/project parse checks if Godot is available
- run any project tests
- inspect broken resource paths
- verify no network/backend dependencies were introduced
- produce `docs/ipad-runbook.md`

Do not claim physical-device validation unless it was actually run on the device.
