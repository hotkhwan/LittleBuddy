# Little Buddy — Overnight Production Candidate Run

You are taking over from the completed Phase 2B HouseWorld foundation.

Current verified baseline:
- Four-room HouseWorld greybox is complete and committed.
- 56/56 tests pass.
- ContentValidator = 0 problems.
- iOS export succeeds.
- arm64 Xcode build succeeds.
- Speech plugin/framework remains unchanged and bundled.
- HouseWorld is not yet wired into the actual game.
- Baby chapter remains caregiver-only; toddler+ uses locomotion.
- Product direction is defined in LITTLE_BUDDY_GAME_BIBLE.md and the design docs.
- Do not regress Chapter 2 baby gameplay.

## Mission for tonight

Work autonomously through all remaining implementation phases needed to produce a polished, child-facing, production-candidate vertical slice that can be installed and played tomorrow morning.

The target is NOT "implement all 39 life-story levels tonight."

The target IS:

**Little Buddy — A Day With Little Buddy**
A polished, coherent, visually delightful, 20–30 minute toddler-stage vertical slice with:
- four usable rooms
- Little Buddy walking
- drag/tap interactions
- breakfast
- brushing teeth
- dressing
- toys
- cleanup
- bedtime
- English prompts
- stars/level progression
- save/load
- polished UI
- polished art
- working speech integration if physically verifiable
- clean iOS export/build

This should feel like a real children's game, not a tech demo.

Do not stop at planning.
Implement, integrate, test, fix, polish, and continue.

## Hard safety rules

1. Protect the current green baseline before touching code.
2. Work on a dedicated branch: `feature/overnight-production-candidate`
3. Commit every stable phase.
4. Never force-push.
5. Never rewrite published history.
6. Never discard working systems just to simplify implementation.
7. Never remove touch fallback.
8. Never make speech required to progress.
9. Never upload child audio.
10. Never add analytics, ads, login, cloud dependency, or network gameplay.
11. Never purchase assets or spend money without human approval.
12. Never use copyrighted/ripped assets.
13. Only use assets with clearly compatible commercial licensing.
14. Update `docs/ASSET_MANIFEST.md` for every external asset.
15. Keep iPhone/iPad Universal support.
16. Keep the existing Apple Team ID/signing settings intact.
17. No raw device coordinates in domain/content data.
18. No NodePath coupling in content.
19. Do not claim "production ready" or "bug free" if any physical-device blocker remains.
20. If an external service such as Meshy requires credentials/API access that are unavailable, do not fabricate success. Continue with the best valid local/open asset path and document what remains.

---

# Phase 2C — HouseWorld Integration

Wire HouseWorld into the actual application.

## Routing

Introduce clear runtime modes:
- Story Mode
- Free Play

For now:
- Chapter 2 Baby Days continues using existing baby-care presentation.
- Chapter 3 Toddler vertical slice launches HouseWorld.
- Free Play can enter unlocked HouseWorld rooms.

Story Mode must use authored level progression.
Free Play may use randomized compatible activities.

## Save schema v4

Promote world state to top-level save data now, before Chapter 3 ships.

Add:
- `currentRoomId`
- `currentSpawnId`
- any minimal HouseWorld resume metadata actually needed

Do NOT store raw Vector3 as authoritative persistent state.

Migration:
- v1 → current
- v2 → current
- v3 → current
must all be tested and idempotent.

Invalid room/spawn:
- fall back safely to the stage default.

## Semantic target validation

ContentValidator must verify referenced activity target IDs against HouseWorld semantic target IDs.

A missing semantic target must fail loudly during validation.

## Camera activity focus

Implement:
- room frame
- focus activity
- restore room frame

No free camera rotation.

---

# Phase 2D — Vertical Slice Gameplay

Implement one complete toddler chapter slice:

## “A Day With Little Buddy”

Target:
20–30 minutes including natural exploration.

Sequence:
1. Wake Up — Bedroom
2. Walk to Bathroom
3. Brush Teeth
4. Return to Bedroom
5. Get Dressed
6. Walk to Kitchen
7. Breakfast
8. English food/drink activity
9. Walk to Living Room
10. Teddy / Toy Play
11. Clean Up
12. Return to Bedroom
13. Bedtime
14. Level/session summary

## Core interactions

Must support:
- tap floor → walk
- tap target → walk to interaction point
- drag object to Little Buddy
- drag object to target
- tap fallback
- pick up
- give
- eat
- drink
- brush teeth
- dress
- play
- put away
- sleep
- wake
- hug
- celebrate

Use semantic actions.

Mission/domain layer must never directly call animation filenames.

---

# Phase 2E — Character Action Layer

Expand the toddler character interface.

Required semantic actions:
- idle
- walk
- wave
- point
- clap
- pickUp
- hold
- give
- eat
- drink
- brushTeeth
- sit
- stand
- hug
- sleep
- wake
- celebrate

Use AnimationTree/state abstraction as appropriate.

If final animations are unavailable:
- use clean placeholders only temporarily
- keep semantic APIs stable
- prioritize at least visually understandable idle/walk/eat/drink/hug/sleep

Do not overbuild an animation framework.

---

# Phase 3A — Visual Art Lock

Read:
- docs/ART_BIBLE_DRAFT.md
- docs/CHARACTER_AGE_STAGES.md
- docs/CUSTOM_BABY_SPEC.md
- docs/ASSET_MANIFEST.md

Finalize:
`docs/ART_BIBLE.md`

The visual target is:
- premium stylized 3D children's game
- cute
- soft rounded forms
- warm
- tactile
- coherent
- readable silhouettes
- pastel but with enough contrast
- not photorealistic
- not uncanny
- not primitive engineering shapes
- original identity

Do not copy commercial game characters, rooms, UI, iconography, animations, or branding.

---

# Phase 3B — Art Replacement

The current weak point is presentation.

Replace obvious engineering placeholders in the vertical slice.

Priority order:
1. Little Buddy toddler
2. Teddy
3. Milk bottle / cup
4. Toothbrush
5. Breakfast props
6. Shirt / pants / shoes
7. Bed / pillow / blanket
8. Toy box / blocks / ball
9. Bathroom sink/bath props
10. Kitchen table/fridge/counter
11. Living-room furniture
12. Nursery/home decoration
13. UI icons and panels
14. App icon if current one no longer matches the final direction

## Asset sourcing

Preferred:
- cohesive permissively licensed asset family
- original procedural assets only when they genuinely look good
- generated assets only when usage rights are clear

If Meshy is accessible with valid credentials:
- use it only after ART_BIBLE is locked
- generate original assets aligned to the art bible
- prefer GLB
- keep source prompts/settings documented
- inspect topology, UVs, material count, and scale
- optimize before importing
- record provenance in ASSET_MANIFEST

If Meshy is NOT accessible:
- do not block the night
- use the best compatible existing assets already approved in the repo
- improve composition, materials, lighting, UI, and scene dressing
- create exact Meshy generation specs for remaining hero assets
- leave no fake placeholder presented as “final”

## Mobile budgets

Approximate targets:
- hero Little Buddy: 4k–10k tris
- secondary humanoid: 2k–6k
- hero prop: 1k–4k
- small prop: 300–2k
- most textures: 512–1024
- hero character: up to 2048 where justified
- keep materials low, ideally 1–3 per object

Measure actual scene cost instead of enforcing triangle count blindly.

---

# Phase 3C — Lighting / Materials / Scene Dressing

Make each room visually distinct and child-readable.

Bedroom:
- warm, sleepy, soft
- bed, pillow, blanket, wardrobe, teddy

Bathroom:
- clean mint/blue palette
- sink, toothbrush, towel, bath cues

Kitchen:
- warm breakfast palette
- food readable at phone size
- table/fridge/counter obvious

Living Room:
- playful
- rug
- toy box
- teddy/ball/blocks
- cozy seating

Lighting:
- mobile-safe
- soft shadows
- no expensive GI requirement
- no volumetric effects
- no aggressive post-processing

Render screenshots at:
- wide landscape iPhone
- landscape iPad

Actually inspect the images.

Fix visual problems that tests cannot catch.

---

# Phase 3D — Child UX / UI Polish

Replace any tech-demo UI.

Requirements:
- one coherent icon family
- rounded child-friendly controls
- balanced spacing
- readable safe-area layout
- large touch targets
- no debug-looking controls
- no ambiguous tiny icons
- no text-heavy tutorials

UI:
- current level/chapter
- short spoken instruction bubble
- current stars
- microphone only when relevant
- optional Thai hint
- pause/parent access unobtrusive

Level summary:
- celebrate 0–3 honest stars
- Next
- Replay
- sticker unlock where applicable

0-star completion:
- positive language
- no failure screen

---

# Phase 3E — Audio / TTS / Speech

## TTS

Ensure English prompts are actually spoken.

Use on-device iOS TTS where practical.

Examples:
- “Good morning!”
- “Let’s brush our teeth.”
- “Put on your shoes.”
- “Can you find the milk?”
- “Great job!”
- “Good night!”

## Speech recognition

Keep:
- offline/on-device only where supported
- permission on explicit child action
- no saved audio
- no upload
- touch fallback

Do not introduce server fallback.

If the machine cannot physically verify microphone behavior:
- compile/link/test what can be proven
- add device checklist
- do not claim runtime speech is proven

## SFX

Add/use gentle feedback:
- pickup
- place
- success
- star
- sticker
- bedtime

Avoid startling peaks.

---

# Phase 3F — Vocabulary Review

Implement lightweight resurfacing, not flashcards.

Track only what is useful:
- exposureCount
- successCount
- lastSeen

Use weighted selection so:
- recently introduced words can reappear
- mastered words appear less frequently
- no immediate repetitive spam

Review should appear naturally inside compatible activities.

Do not build a separate study dashboard.

---

# Phase 4A — Onboarding

First-run experience must explain the game without requiring reading.

Target:
- show Little Buddy
- gesture hint for tap-to-walk
- gesture hint for drag
- voice/TTS introduction
- complete one easy action
- then release child into play

Use animation/visual cues over paragraphs.

Do not make tutorial mandatory forever.

Persist onboarding completion.

---

# Phase 4B — Free Play

Make unlocked HouseWorld rooms playable outside story.

Free Play:
- move Little Buddy
- touch objects
- drag toys/food
- tap objects to hear English
- dress
- eat/drink
- sleep
- brush teeth
- play
- tidy toys

No hard objective required.

---

# Phase 4C — Robustness / Child-Proofing

Stress test:
- rapid tapping
- 2+ finger touches
- drag while walking
- tap UI while walking
- change room during interaction
- cancel activity
- replay repeatedly
- save/restart during safe points
- invalid saved room
- unavailable speech
- denied microphone
- interruption
- orientation flip
- both notch sides
- small/wide aspects
- repeated Next/Replay
- corrupt save fixture

No dead-end states.

No stuck:
- Walking
- Listening
- Disabled
- Interacting
states.

---

# Phase 4D — Automated QA

Run full suite after every major integration wave.

Add tests for all new domain behavior.

Mutation-test critical rules:
- level unlock
- star integrity
- save migration
- semantic target validation
- no duplicate arrival
- no duplicate reward
- speech-independent progression
- room fallback
- review scheduling
- onboarding once-only behavior

Keep the test runner honest.
Any parse failure / aborted test must fail the suite loudly.

---

# Phase 4E — iOS Production-Candidate Build

Final overnight validation:

1. Godot project loads with zero errors
2. full tests pass
3. ContentValidator = 0
4. no missing resources
5. no critical TODO/FIXME
6. no debug UI
7. no accidental network dependency
8. asset manifest complete
9. iOS export succeeds
10. arm64 Xcode build succeeds
11. Speech.framework linked
12. AVFoundation.framework linked
13. native plugin entry symbol present
14. Universal iPhone/iPad
15. landscape orientations intact
16. privacy strings correct
17. signing settings preserved

Use the repository's approved iOS export script.

Do not publish to App Store automatically.
Do not upload to TestFlight automatically unless explicitly authorized.

---

# Phase 4F — Visual Acceptance

Render a screenshot set from the real project:
- Bedroom
- Bathroom
- Kitchen
- Living Room
- breakfast interaction
- teddy interaction
- bedtime
- level summary
- wide iPhone
- iPad

Review them yourself.

If a screenshot still looks like:
- primitive geometry
- debug prototype
- inconsistent art packs
- unreadable object
- awkward spacing
- ugly stretched UI
- poor camera framing

then keep polishing before finalizing.

Visual QA is a release gate.

---

# Phase 5 — Handoff / Morning Build

Create:
`docs/OVERNIGHT_PRODUCTION_REPORT.md`

Include:
- final branch
- final commit
- full test count
- ContentValidator result
- iOS export result
- Xcode build result
- visual screenshots produced
- what art was replaced
- asset/license summary
- save schema version
- implemented vertical-slice flow
- known bugs
- known visual limitations
- speech verification status
- exact device test checklist
- exact commands to run on the MacBook
- exact next product decision

Create a final tag only if all automated release gates pass:
`little-buddy-production-candidate-0.2`

Do NOT use a “release” tag if device-critical items remain unverified.

---

# Autonomous execution strategy

Use agents in non-overlapping scopes.

Recommended waves:

Wave 1
- HouseWorld integration/save migration
- target validation
- vertical-slice content mapping

Wave 2
- character actions/navigation integration
- room gameplay
- onboarding/free play

Wave 3
- art/UI/lighting/audio
- asset/license audit

Wave 4
- vocabulary review
- child-proofing
- regression QA

Wave 5
- final iOS export/build
- visual screenshot review
- documentation

Main orchestrator owns shared core files and integration.

Do not let multiple agents edit the same shared file concurrently.

---

# Git discipline

Before work:

```bash
git status
git checkout -b feature/overnight-production-candidate
```

After every green milestone:

```bash
git add -A
git commit -m "<clear milestone>"
```

Never commit:
- build/
- DerivedData/
- *.p12
- *.mobileprovision
- user-specific Xcode state
- generated speech plugin binaries if repository policy says they are ignored
- secrets
- API tokens

Never force-push.

---

# Priority order if time becomes limited

1. no regressions
2. HouseWorld actually reachable
3. complete “A Day With Little Buddy” flow
4. walking + interactions
5. visually coherent Little Buddy + four rooms
6. child-friendly UI
7. TTS and speech integration
8. robust save/progression
9. Free Play
10. vocabulary review polish
11. extra cosmetic polish

Do NOT sacrifice core stability to add more features.

---

# Definition of success tomorrow morning

The child should be able to launch the game and:
- see a cute, coherent home
- understand where Little Buddy is
- tap and make Little Buddy walk
- move between rooms
- brush teeth
- get dressed
- eat breakfast
- hear useful English
- play with teddy/toys
- clean up
- go to bed
- earn stars
- see a satisfying summary
- replay or continue
- explore rooms without getting stuck

It should feel like a game made for a child, not a prototype made for developers.

Do not claim perfection.
Report exactly what is verified and exactly what still requires a physical iPhone/iPad.

Continue autonomously until every achievable phase above is complete or a truly human-only blocker is reached.
