# Little Buddy — Overnight Autonomous Build Plan

## Mission

Turn the current working Little Buddy iOS prototype into a polished, cute, offline-first child-facing game that feels delightful on first launch and has enough varied content/replayability for roughly 2–3 hours of play.

Do not restart the project. Preserve the validated Godot 4.7.2 / iOS / Universal iPhone+iPad foundation and the current offline-first architecture.

The physical iPhone build already works. Treat that as a protected baseline.

## Non-negotiable rules

1. Do not add Cloudflare, Fly.io, login, analytics, ads, IAP, multiplayer, or any network dependency.
2. Do not remove or break the existing offline touch fallback.
3. Do not modify signing/team settings unless required to keep the existing build working.
4. Do not claim speech is done unless it is actually included in the generated Xcode project and compiles.
5. Never record, persist, upload, or transmit child audio.
6. Keep the app playable with Airplane Mode enabled.
7. Keep the current Universal iPhone+iPad target.
8. Use the Godot Mobile renderer.
9. Prefer data-driven content over hardcoded lesson logic.
10. Never wait for me unless a step genuinely requires physical-device interaction or Apple signing confirmation.
11. Do not stop at planning. Implement, integrate, test, fix, and continue.
12. Commit after each stable milestone. If a milestone breaks the build, fix it or revert only that milestone.
13. Never destroy the last known-good iOS build.
14. Do not use copyrighted/restricted third-party assets unless their license is explicitly permissive for commercial use. For tonight, prefer original procedural geometry, generated SVGs, and generated sound effects.

## Reality check

"Zero bugs" cannot be guaranteed. The target is:
- no known blocker bugs
- no known crash paths in the tested flow
- all automated tests passing
- Godot project loads with zero parse errors
- Xcode project builds successfully
- all interaction paths have graceful fallbacks
- no dead-end state where a child gets stuck

## Protected baseline

Before changing anything:

1. Verify current tests pass.
2. Verify current Godot project loads.
3. Verify current Xcode project still builds.
4. Create a git commit/tag for the current working state:

```bash
git add -A
git commit -m "checkpoint: physical iPhone MVP working"
git tag -f little-buddy-mvp-working
```

If the working tree is already clean and committed, just tag the current commit.

---

# Product direction

Little Buddy should feel like a soft, playful 3D nursery game rather than a technical demo.

The emotional target:
- cute
- warm
- safe
- playful
- understandable without reading much
- satisfying animations
- simple English learning woven into play
- lots of small rewards
- no punishment
- no scary failure state

The child should immediately understand:
- the baby needs help
- objects can be touched/dragged
- the baby reacts
- English words cause things to happen
- stars/stickers are rewards

---

# Visual direction

## Style

Create an original lightweight stylized low-poly / soft-toy aesthetic using Godot primitives and procedural materials.

Palette:
- warm cream
- pastel blue
- peach
- soft pink
- mint
- lavender
- warm wood
- avoid harsh black except pupils/outline accents

Room:
- nursery walls
- warm floor
- large soft rug
- crib/bed
- shelf
- toy box
- lamp
- framed simple shapes/stars/clouds
- window
- a few toys

Baby:
- larger head
- softer proportions
- visible hands/feet
- big expressive eyes
- eyebrows
- blush
- simple mouth that can smile/open
- pastel outfit
- slightly oversized head for cuteness

Milk bottle:
- recognizably shaped
- translucent/light body if cheap enough
- soft colored cap
- child-sized touch collider

Teddy:
- larger head
- round ears
- belly patch
- short arms/legs
- obviously huggable silhouette

## UI

Replace prototype-looking dark rectangles.

Create:
- rounded speech bubble/panel
- large friendly mic button with icon
- star counter with icon
- sticker/progress button
- subtle bounce/pulse feedback
- safe-area aware layout
- landscape adaptive on iPhone and iPad

Buttons must be large enough for a child.

Avoid long text paragraphs in child UI.

---

# Animation / delight layer

Implement lightweight AnimationPlayer/Tween-based reactions:

Baby:
- idle breathing/bobbing
- blink
- hungry/sad
- happy bounce
- drink
- hug teddy
- clap
- sleepy
- wave
- celebrate

Objects:
- pick-up scale pop
- hover/drag tilt
- snap-to-target
- soft return-to-origin
- sparkle/bounce on correct interaction

Camera:
- subtle focus tween for major interaction
- never disorient the child
- no free-look camera required

Celebration:
- lightweight star/confetti burst using either very small GPUParticles3D budget or procedural UI stars
- short happy chime
- baby smile/bounce

Performance:
- target smooth performance on physical iPhone
- avoid GI, volumetric fog, SSR, SSAO-heavy setups, expensive shaders, large textures
- keep draw calls/material count reasonable

---

# Critical interaction systems

## 1. Real drag and drop

Implement a reusable `Draggable3D` interaction system.

Requirements:
- touch-down begins drag
- object follows finger using Camera3D ray projection against a stable drag plane
- no RigidBody3D dependency
- enlarged invisible touch collider
- multi-touch safe
- cannot trigger reward twice
- release outside valid zone returns object smoothly
- tap fallback remains available
- clear pickup feedback

Create reusable drop zones:
- `MouthDropZone`
- `HugDropZone`
- `HandDropZone`
- `BathDropZone`
- `DressDropZone`
- `ToyBoxDropZone`

## 2. Milk interaction

Flow:
1. Baby indicates hunger.
2. Speech bubble: "I'm hungry."
3. Child can drag milk to baby's mouth OR tap milk as fallback.
4. Prompt: "Can you say milk?"
5. If speech is available, child can say "milk" or supported phrase.
6. Baby drinks.
7. Baby reacts happily.
8. +1 star only once for the scored task.
9. Bottle returns to a sensible resting state.

## 3. Teddy interaction

Flow:
- drag teddy to baby chest/arms
- baby hugs teddy
- baby says via TTS: "Teddy!" / "I love my teddy!"
- happy animation
- no farming stars from repeated teddy taps
- tap fallback triggers short reaction

## 4. Speech

Complete native iOS speech integration correctly.

Requirements:
- Apple Speech framework
- AVFoundation microphone
- en-US
- request permissions only when the child taps Speak
- visible listening state
- visible success/fallback state
- prefer on-device recognition when supported
- if on-device recognition is unavailable, fail gracefully rather than uploading audio
- do not store audio
- do not write audio to files
- no networking path
- timeout safely
- stop after accepted phrase or timeout
- handle denied permission
- handle unavailable recognizer
- handle interruption
- do not leave mic/listening stuck active
- touch gameplay still works if speech fails

The generated Xcode project must contain the native plugin/framework references required for speech.

Do not mark this milestone complete based on a standalone library compile. It must survive Godot export and Xcode build.

---

# Content goal: 2–3 hours of replayable play

Do NOT try to hand-author 3 hours of unique animation. Build reusable systems plus enough data variation.

Target:
- 5 main activity categories
- 30–50 vocabulary words
- 80–120 phrase variants
- 25+ small missions/tasks
- randomized prompt ordering
- sticker collection
- star progression
- simple unlock pacing
- replayable routines

## Activity 1 — Feeding

Objects:
- milk
- water
- apple
- banana
- spoon
- bowl

English:
- milk
- water
- apple
- banana
- hungry
- thirsty
- spoon
- bowl

Example prompts:
- "I'm hungry."
- "Can I have some milk?"
- "Give me the milk, please."
- "Where is the apple?"
- "Can you say banana?"
- "I'm thirsty."
- "Give me some water."

Interactions:
- drag food/drink to baby
- choose correct requested item
- incorrect item gets gentle reaction, no punishment

## Activity 2 — Dress Up

Create simple swappable primitive/accessory items:
- red shirt
- blue shirt
- yellow shirt
- pants
- shoes
- hat
- pajamas

English:
- shirt
- pants
- shoes
- hat
- red
- blue
- yellow
- pajamas

Prompts:
- "Put on the red shirt."
- "Where are my shoes?"
- "Can you say blue?"
- "Put on my hat."
- "It's bedtime. Put on my pajamas."

Use data-driven outfit slots.

## Activity 3 — Bath / Clean Up

Objects:
- soap
- towel
- toothbrush
- cup
- bath toy

English:
- soap
- towel
- wash
- clean
- teeth
- toothbrush
- bath
- wet
- dry

Prompts:
- "Let's wash."
- "Give me the soap."
- "Where is the towel?"
- "Brush my teeth."
- "Can you say toothbrush?"

Keep visuals simple; no complex fluid simulation.

## Activity 4 — Play Room

Objects:
- teddy
- ball
- blocks
- star
- circle
- square
- toy box

English:
- teddy
- ball
- block
- star
- circle
- square
- play
- throw
- put away

Mini-games:
- find the requested toy
- drag toy to baby
- put toys back into toy box
- color/shape identification

Prompts:
- "Find the ball."
- "Give me the teddy."
- "Put the block in the toy box."
- "Where is the star?"
- "Can you say circle?"

## Activity 5 — Bedtime

Objects:
- blanket
- pillow
- teddy
- pajamas
- lamp

English:
- sleepy
- bed
- blanket
- pillow
- good night
- lamp
- teddy

Flow:
- pajamas
- teddy
- blanket
- lights dim
- "Good night."

Use safe dimming only; never make the scene scary/dark.

---

# Mini-game system

Add 3 reusable mini-game modes driven from data.

## A. Find It

Baby asks for one object:
- "Find the teddy."
- "Where is the milk?"

Child taps/drags correct object.

## B. Say It

Show/animate an object:
- TTS says word
- child taps Speak
- says target word
- intent matcher uses tolerant phrase matching
- success reaction

No numeric pronunciation score.

## C. Follow the Instruction

Examples:
- "Give me the blue shirt."
- "Put the teddy in the toy box."
- "Give me some milk."

This combines listening + object interaction.

---

# Progression

Implement simple local progression.

## Stars

- reward completed learning tasks
- do not award repeatedly for spam taps
- persist locally
- show pleasant celebration

## Sticker book

Create 12–20 simple original stickers using SVG/procedural art:
- milk
- teddy
- apple
- banana
- star
- ball
- shirt
- shoes
- soap
- towel
- toothbrush
- pillow
- moon
- heart
- cloud
- rainbow

Unlock stickers at milestone thresholds.

Sticker book UI:
- grid
- locked silhouette
- unlocked sticker
- tap sticker → word spoken with TTS

## Mission/session structure

Generate short sessions of 5–8 tasks.

Examples:
- Morning routine
- Feeding time
- Play time
- Bath time
- Bedtime

After session:
- show stars earned
- unlock sticker when threshold reached
- button: "Play again"

Randomize task ordering while preventing immediate repetition.

---

# Content architecture

All activity/prompt content must be data-driven.

Suggested structure:

```text
game/content/
├── feeding/
├── dressing/
├── bath/
├── play/
├── bedtime/
├── vocabulary/
├── missions/
└── stickers/
```

Each lesson/task should define:
- id
- category
- target word(s)
- English prompt
- optional Thai hint
- accepted speech phrases
- required interaction
- object id
- reward
- difficulty
- cooldown/repetition control

No giant switch statement containing every lesson.

---

# Parent-friendly behavior

Tonight do not build login/accounts.

Add a tiny Parent Settings screen behind a simple parental gate such as:
- "Press and hold for 3 seconds"

Settings:
- Thai hints on/off
- voice practice on/off
- TTS speed: slow / normal
- reset progress with confirmation

Do not expose external links in child-facing UI.

---

# Audio

Use only original/generated sounds tonight.

Generate simple royalty-free procedural WAV effects if useful:
- success chime
- soft pop
- pickup
- sticker unlock
- gentle bedtime chime

Do not add loud/startling effects.

Use iOS TTS for English phrases where practical.

---

# Quality / bug prevention

## Required automated tests

Keep existing tests and add coverage for:
- no double star reward
- drag success
- drag cancel/return
- teddy never awards star
- mission completion
- save/load
- sticker unlock persistence
- random task generator does not immediately repeat same task
- speech intent matcher accepts expected phrase variants
- denied/unavailable speech leaves game playable
- content JSON/data validates
- every referenced scene/resource exists
- all activity IDs unique
- no dead mission references

## Static checks

Scan for:
- network APIs
- analytics SDKs
- file writes of microphone audio
- TODO/FIXME in critical gameplay
- missing resources
- duplicate content IDs
- empty iOS privacy strings
- debug UI accidentally visible in release scene
- accidental hardcoded iPhone resolution assumptions

## Runtime checks

Run:
- Godot headless project load
- full test suite
- repeated simulated touch tests
- rapid tapping
- drag cancel
- star persistence after restart
- multiple mission sessions
- iPhone aspect
- iPad aspect
- both landscape rotations

## Xcode checks

After major milestones:
1. export Xcode project
2. confirm Universal iPhone+iPad
3. confirm team ID preserved
4. build arm64
5. confirm speech plugin/framework presence if speech milestone is active
6. do not generate IPA unless explicitly needed

---

# Overnight execution strategy

Use subagents only for non-overlapping scopes.

Recommended waves:

## Wave 1 — protected foundation
- interaction/drag agent
- speech integration agent
- visual nursery agent
- content schema/validation agent

Integrate and test.

## Wave 2 — activities
- feeding agent
- dress-up agent
- bath agent
- play/bedtime agent

Each agent owns separate scene/content directories.

Integrate and test.

## Wave 3 — progression/polish
- missions/progression/sticker agent
- animation/audio polish agent
- UI/parent settings agent

Integrate and test.

## Wave 4 — QA
Read-only QA agent first.
Then main agent fixes every blocker/high severity issue.
Repeat tests.

Do not let two agents edit the same file concurrently.
The main orchestrator owns shared core files and integration contracts.

---

# Git discipline

At each green milestone:

```bash
git add -A
git commit -m "<clear milestone message>"
```

Suggested milestones:
- `feat: add reusable child-friendly drag interactions`
- `feat: integrate offline iOS speech recognition`
- `feat: polish nursery visual presentation`
- `feat: add feeding and dress-up activities`
- `feat: add bath play and bedtime activities`
- `feat: add missions stickers and progression`
- `test: harden Little Buddy overnight MVP`

If a milestone introduces regressions, fix or revert only that milestone.

---

# Definition of Done for the overnight build

Do not call the overnight build complete until all achievable items below are true.

## Gameplay
- [ ] Cute nursery scene replaces tech-demo appearance
- [ ] Baby has visible idle/happy/hungry/drink/hug/sleep reactions
- [ ] Milk can be dragged to mouth
- [ ] Milk still supports tap fallback
- [ ] Teddy can be dragged/hugged
- [ ] Teddy still supports tap fallback
- [ ] At least 5 activity categories exist
- [ ] At least 25 playable tasks exist
- [ ] At least 30 vocabulary words exist
- [ ] At least 80 phrase variants exist
- [ ] 3 reusable mini-game modes exist
- [ ] Stars persist
- [ ] Sticker collection persists
- [ ] Sessions/missions provide replayability

## Speech
- [ ] Speak button has clear listening UI
- [ ] native iOS speech is actually integrated into exported Xcode project
- [ ] accepted words map to game actions
- [ ] denied/unavailable speech never blocks play
- [ ] no audio is stored/uploaded

## Visual
- [ ] No prototype black/debug controls visible
- [ ] rounded child-friendly UI
- [ ] safe area on iPhone/iPad
- [ ] both landscape rotations supported
- [ ] room looks intentionally designed
- [ ] lightweight celebration effects
- [ ] performance remains suitable for mobile

## Quality
- [ ] project loads with zero Godot parse errors
- [ ] all automated tests pass
- [ ] no known crash in tested flows
- [ ] no dead-end gameplay state
- [ ] generated Xcode project builds successfully
- [ ] existing Team ID / signing configuration preserved
- [ ] offline play remains functional
- [ ] no cloud/network dependency added

## Documentation
Update:
- `docs/ipad-runbook.md`
- `docs/OVERNIGHT_BUILD_REPORT.md`

The build report must include:
- what was implemented
- what was tested
- exact test results
- known limitations
- any item that still requires physical-device verification
- exact next manual step for the owner

---

# Final instruction

Work autonomously for as long as useful.

Do not stop merely because one feature is difficult. If a feature is blocked:
1. isolate it,
2. preserve the working fallback,
3. document the blocker,
4. continue with the remaining independent work.

Do not ask me routine implementation questions.
Choose sensible child-friendly defaults.

Prioritize in this exact order:

1. No regressions / app remains buildable
2. Child cannot get stuck
3. Core touch/drag interactions feel good
4. Speech actually works in the shipped iOS build
5. Cute visual presentation
6. Content/replayability
7. Polish

At the end, run the complete validation suite one final time and give me a concise report with:
- git commit/hash
- Godot test result
- Xcode build result
- content counts
- known issues
- exact physical iPhone/iPad checks still required

Do not claim "bug-free." Report truthfully what is verified and what is not.
