# Little Buddy — Codex Project Instructions

## Mission
Build an offline-first iPad MVP for a child-friendly English learning game.
The player cares for a baby character and learns English through listening, touch interaction, and simple voice commands.

## Tonight's Definition of Done
The project is successful when all of the following are true:

1. The Godot project opens without errors.
2. The game runs locally on macOS from Godot.
3. One playable `Baby Room` scene exists.
4. The baby can become hungry.
5. The player can tap/drag a milk bottle to feed the baby.
6. The game speaks at least one English prompt using local device TTS.
7. The player can press a microphone button and the speech layer exposes a result callback.
8. If iOS speech recognition is available, saying `milk` or a supported phrase triggers `feedMilk`.
9. If iOS speech recognition is not yet available, touch gameplay still works completely.
10. Progress is saved locally; no network is required.
11. The project can be exported to iOS/Xcode.
12. The app can be installed directly on a physical iPad through Xcode signing.

TestFlight is NOT required for tonight. Direct Xcode installation to the iPad is acceptable and preferred for the first playable build.

## Architecture Rules

- Offline-first. Core gameplay MUST NOT depend on Cloudflare, Fly.io, APIs, authentication, or internet access.
- No backend in MVP.
- No analytics.
- No ads.
- No IAP.
- No account/profile server.
- No child voice recording persistence.
- Do not upload microphone audio anywhere.
- Keep game content data-driven.
- Use Godot 4.x and GDScript.
- Prefer the Compatibility renderer for low-end Mac development and simple 2D rendering.
- Target iPad first, landscape orientation.
- Design touch targets for children: large buttons, minimal text, no tiny controls.

## Code Style

- JSON keys MUST use camelCase.
- GDScript variables/functions MUST use snake_case, following Godot conventions.
- Keep scripts small and single-purpose.
- Avoid deep inheritance; prefer composition/signals.
- Avoid global singletons except true application services.
- Every service must have a clear interface and a fallback implementation when reasonable.
- No network calls anywhere in gameplay code.

## Repository Structure

Expected structure:

```text
game/
├── project.godot
├── scenes/
│   ├── main/
│   └── baby_room/
├── scripts/
│   ├── baby/
│   ├── activities/
│   ├── speech/
│   ├── rewards/
│   └── save/
├── content/
│   └── feeding/
├── assets/
│   └── placeholders/
└── tests/

ios/
└── speech_plugin/
docs/
```

## Game State

Minimum baby state:

```text
hunger: 0..100
happiness: 0..100
energy: 0..100
cleanliness: 0..100
```

For MVP, only `hunger` is required to affect gameplay.

## MVP Activity

Activity ID: `feedMilk`

Expected flow:

```text
Baby is hungry
→ baby says "I'm hungry."
→ milk bottle is visible
→ player taps/drags milk
→ baby says "Can you say milk?"
→ microphone button becomes available
→ recognized "milk" or accepted phrase maps to feedMilk
→ baby drinks milk
→ hunger decreases
→ star count increases by 1
→ baby says "Thank you!"
```

Touch feeding must remain available even when microphone permission is denied.

## Intent Matching

Do not compare raw speech text with a single exact string.
Normalize lowercase text and strip basic punctuation.

Supported MVP phrases:

```text
milk
give milk
give baby milk
give the baby milk
give the baby some milk
baby wants milk
```

All should resolve to:

```text
feedMilk
```

## Local Save

Save only local progress in Godot `user://`.
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

Handle missing/corrupt save files safely by recreating defaults.

## Child UX Rules

- Never show a red X for speech mistakes.
- Feedback should be encouraging and short.
- Use phrases such as `Great!`, `Nice!`, `Try again!`.
- Do not give pronunciation percentages in MVP.
- No timers or failure pressure.
- No external links in child-facing UI.
- No ads or purchase prompts.

## Placeholder Art Policy

Tonight, do NOT waste time sourcing production art.
Use simple Godot-drawn shapes, emoji-like labels, gradients, or generated placeholder SVG/PNG assets owned by the project.
Keep all placeholder assets replaceable.

## Performance Rules

The project is intentionally lightweight:

- 2D only for MVP.
- Avoid particle-heavy effects.
- Avoid large uncompressed textures.
- Use small placeholder images.
- Do not run iOS Simulator if the Mac struggles; use a physical iPad.
- Close unnecessary applications while exporting with Xcode.

## Agent Delegation Rules

The orchestrator is explicitly authorized to spawn sub-agents.
Prefer parallel agents only for independent file scopes.
Do NOT allow multiple agents to edit the same files simultaneously.

Recommended agents:

### agentFoundation
Write scope:
- `game/project.godot`
- `game/scenes/main/**`
- basic project bootstrap only

### agentGameplay
Write scope:
- `game/scenes/baby_room/**`
- `game/scripts/baby/**`
- `game/scripts/activities/**`
- `game/scripts/rewards/**`

### agentContent
Write scope:
- `game/content/**`
- `game/assets/placeholders/**`
- content validation utilities/tests if isolated

### agentSpeech
Write scope:
- `game/scripts/speech/**`
- `ios/speech_plugin/**`

Implement a service abstraction first. The game must work with a mock/fallback speech service before the iOS native bridge is complete.

### agentSave
Write scope:
- `game/scripts/save/**`
- local-save tests only

### agentQA
Read-only unless explicitly assigned a fix after orchestration.
Responsibilities:
- inspect integration
- check missing files/references
- run project validation where available
- document iOS export blockers

## Integration Rule

The orchestrator owns integration files that multiple components depend on.
Sub-agents should not casually modify shared project configuration after bootstrap.
If a change to shared files is required, report it to the orchestrator instead.

## Stop Conditions

Do NOT expand tonight's scope to:

- bath gameplay
- dress gameplay
- bedtime gameplay
- cloud save
- multiplayer
- Cloudflare
- Fly.io
- IAP
- App Store submission
- production graphics
- generative AI conversation

Those are later milestones.
