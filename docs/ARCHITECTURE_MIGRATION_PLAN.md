# Architecture Migration Plan — Life Journey v2

**Branch:** `design/life-journey-v2` · **Date:** 2026-09-17
**Status:** proposal. No gameplay code has been changed.

Maps the current, working Little Buddy architecture onto the story-driven life-journey design
in `LITTLE_BUDDY_GAME_BIBLE.md`.

---

## 0. The headline finding

**The domain layer is already engine-agnostic and survives the redesign almost untouched.**

Verified by inspection, not memory:

```
mission_runner.gd          Node3D/Area3D/MeshInstance3D/Camera3D references: 0
content_library.gd         3D references: 0
content_validator.gd       3D references: 0
task_picker.gd             3D references: 0
```

The expensive parts of this project — the content pipeline, mission sequencing, reward
integrity, save/corruption handling, the speech stack, and the iOS build/signing pipeline —
are **not coupled to the baby room**. They were built behind semantic interfaces, and that
decision now pays for itself.

**The real work is not migration. It is one large genuinely-new system (character movement in
a multi-room world) plus a renaming/extension of the progression layer.**

Equally important: **there is no character movement of any kind today.** No `CharacterBody3D`,
no `NavigationAgent3D`, no navigation mesh, no walking. Tap-to-walk, room-to-room navigation
and walk-to-activity are all new. That is the single biggest risk and cost in this plan, and
nothing in the current codebase reduces it.

---

## 1. Subsystem audit

| Subsystem | Current state | Verdict | Rationale |
|---|---|---|---|
| **Content system** (`ContentLibrary`, `ContentValidator`, `TaskPicker`, `content/*.json`) | 1,399 lines, 0 3D refs, 43 tasks / 46 words / 270 phrases / 28 objects, validator reports 0 problems | **KEEP + EXTEND** | Already data-driven and stage-agnostic. Extend the task schema with `chapterId`, `levelId`, `room`, `characterStage`. No rewrite. |
| **Mission system** (`MissionRunner`) | 0 3D refs; drives 5–8 task sessions; emits `task_completed(task_id, stars)` | **KEEP → rename to Level** | A "mission" already *is* a level: `{missionId, title, category, introPhrase, outroPhrase, unlockAtStars, taskIds}`. Rename concepts, add 3-star evaluation. Do not rewrite the runner. |
| **Mode handlers** (`ModeHandler` + `findIt`/`sayIt`/`followInstruction`) | Common interface: `start(task, context)`, `cancel()`, `task_completed`, `prompt_changed`, `encouragement`, `speak_button_enabled` | **KEEP + EXTEND** | This is the reusable-template mechanism the level matrix depends on. Add `sequenceRoutine` and `tidyUp` as new modes alongside, not instead. |
| **Stars / rewards** (`RewardLedger`, `RewardManager`) | Process-wide ledger, idempotent by `completion_id`, round-scoped ids, 350 ms spam guard, single writer to save | **KEEP + EXTEND** | Integrity logic is hard-won (double-pay, spam, scene reload) and must not be re-derived. Extend from a global counter to **per-level 1–3 stars**; keep the ledger as the only writer. |
| **Stickers** (`StickerBook`, `StickerArt`, 16 stickers) | Persisted in settings, idempotent unlock, 16 glyphs in one visual family | **KEEP + EXTEND** | Works. Extend thresholds to per-chapter and add the 3/3-stars bonus sticker from Bible §5.2. |
| **Save/progression** (`ProfileStore`, `SaveService`) | `{profileVersion, stars, completedActivities, settings}`; atomic write; survives 6 corruption shapes | **EXTEND (schema migration)** | Needs `currentChapter`, `currentLevel`, `starsByLevel`, `unlockedChapters`, `unlockedRooms`, `unlockedOutfits`, `selectedCareer`. `profileVersion` bump + migration. Corruption handling stays as-is. |
| **Speech abstraction** (`SpeechService`, `IntentMatcher`, backends) | Backend-agnostic; tolerant phrase matching; mock on desktop; **proven working on a physical iPhone** | **KEEP** | No change needed. It is the most expensively-validated subsystem in the project. |
| **iOS native speech plugin** | GDExtension, on-device only, no networking framework linked, device-validated 2026-09-17 | **KEEP — freeze** | Do not touch during migration. Rebuild steps in `docs/MACBOOK_HANDOFF.md`. |
| **Baby room** (`baby_room.tscn/gd`) | Single room, owns camera, UI, drop zones, activity scene loading, legacy fallback | **MODIFY → becomes one Room in `HouseWorld`** | Structure is sound but it is currently *the world*. Its responsibilities split: room content → `Room`, UI → a persistent HUD layer, camera → `HouseWorld`. |
| **Draggable objects** (`DraggableObject`, `DragPlane`) | Camera-ray drag on a stable plane, latched pointer (multi-touch safe), per-gesture delivery latch, tap fallback, 240×240 px grab area | **KEEP** | The Bible explicitly keeps dragging. This is solved, child-tested-by-design, and reusable as-is. |
| **Drop zones** (`DropZone`) | Named zones with radius; positioned live from character markers; contract-tested | **KEEP + EXTEND** | Extend to room-owned zones (`BathDropZone` in the bathroom, etc.) and character-relative zones that follow a *walking* character. |
| **Object spawner** (`ObjectSpawner`) | Builds any object from a JSON record (`model` / `proc` / primitive fallback) | **KEEP + EXTEND** | Extend from "spawn into a row" to "place into a room at an anchor". The fallback chain is a genuine asset-risk absorber — keep it. |
| **Animations** (`BabyView3D` + `AnimationPlayer`, 5 clips) | `set_view_state("idle"/"hungry"/"drinking"/"happy"/"hugging")` — **already semantic, not filename-driven** | **EXTEND → `playAction()`** | Rename to the Bible's `character.playAction("drink")` and grow to the full library (walk, sit, carry, brush, wash, wave, clap, sleep). The abstraction already exists; only the vocabulary grows. |
| **Procedural baby** | Built from primitives, 6,264 tris, explicitly temporary | **DEPRECATE (keep until replaced)** | Remains the working fallback until a commissioned model passes `docs/CUSTOM_BABY_SPEC.md`. Do not delete first. |
| **3D props** (11 Kenney CC0 + 17 procedural) | All 28 objects modelled; semantically correct | **KEEP** | Independent of story structure. Reused across every chapter. |
| **UI** (Nieobie icons, Kenney 9-slices, `SafeArea`) | One icon family, 6 pastel colourways, WCAG contrast test, safe-area enforced | **KEEP + EXTEND** | Add chapter/level indicator, journey map, 3-star display. Visual language stays. |
| **App icon** | Originally authored, opaque 1024², regenerable, no third-party licence surface | **KEEP** | Unaffected. |
| **Parent settings** | 3-second hold gate, Thai hints / voice / TTS speed / reset | **KEEP + EXTEND** | Add chapter reset and Free Play toggle. |
| **Audio** (`SfxPlayer`, 8 generated WAVs) | Original, zero third-party audio licence surface, measured child-safe levels | **KEEP + EXTEND** | Add per-action cues as the interaction set grows. Keep generating rather than sourcing. |
| **Tests** (30 cases) | Runner fails loudly on parse errors and aborted `run()`; mutation-tested contracts | **KEEP + EXTEND** | The suite is the safety net for this migration. Add level/chapter/navigation cases **before** refactoring. |
| **iOS export/build pipeline** (`tools/export_ios.sh`) | Strips Godot's hardcoded camera/photo plist keys; signing and Team ID committed; device install proven | **KEEP — freeze** | Explicitly out of scope for this migration. |
| **Legacy `FeedActivity` + `BabyState`** | Legacy single-loop fallback; `hunger/happiness/energy/cleanliness` barely used | **DEPRECATE** | Superseded by the mission/level system. Keep as the content-failure fallback until levels are proven, then remove. |

**Summary: 14 KEEP · 9 EXTEND · 2 MODIFY · 0 REPLACE · 3 DEPRECATE.** Nothing needs replacing.

---

## 2. Proposed architecture

Names from the brief, mapped onto what exists. **A new name does not mean new code.**

```
HouseWorld  (new)                     owns rooms, camera, navigation mesh, persistent HUD
├── Room  (new, thin)                 id, anchors, drop zones, free-play objects, vocab set
│     └── ActivityZone  (extend DropZone)
├── LittleBuddyCharacter  (extend BabyView3D)
│     ├── CharacterController  (NEW)  CharacterBody3D + NavigationAgent3D + state machine
│     └── playAction(semantic)        extends set_view_state()
├── InteractionController  (extend)   DraggableObject + DragPlane + new tap-to-walk routing
│     └── InteractiveObject  (extend) SpawnedObject
├── ChapterSystem  (new, thin)        ordering + unlock gates over LevelSystem
├── LevelSystem  (rename)             = MissionRunner + 3-star evaluation
├── MissionSystem  (keep)             = ModeHandler + the mode family
├── StarSystem  (extend)              = RewardLedger, now per-level
├── EnglishLearningSystem  (keep)     = ContentLibrary + IntentMatcher + TtsService
├── SpeechSystem  (keep, frozen)      = SpeechService + iOS plugin
└── SaveSystem  (extend)              = ProfileStore + schema migration
```

### The one genuinely new subsystem: `CharacterController`

Everything else is a rename, an extension, or a thin new coordinator. This is the only piece
with no existing foundation:

- `CharacterBody3D` + `NavigationAgent3D`, baked navigation per room
- tap-to-walk: screen tap → ray → navmesh point → path → walk → arrive → face target
- walk-to-activity: an `ActivityZone` exposes a stand position and facing
- animation state machine: Idle ↔ Walk ↔ Interact ↔ Carry ↔ Sit ↔ Sleep ↔ Celebrate
- a forgiving **drag-character** mode for very young players (Bible §6) — short walk/snap, never a teleport
- stop radius, re-path on target moved, and a hard rule: **never leave the character unreachable or stuck**

This is where the schedule risk lives. Treat it as its own vertical-slice milestone with its
own tests before any story content depends on it.

### Semantic action API (hard rule, from Bible §13)

```gdscript
character.playAction("drink")          # correct
character.play_animation("drink_v3")   # forbidden
```

Mission and content logic must never reference a 3D node type, a model, or an animation
filename. This rule is already honoured — `mission_runner.gd` has zero 3D references — and the
migration must not break it. **Add a test that fails if `scripts/gameplay/**` or
`scripts/content/**` ever gains a 3D reference.**

---

## 3. Save schema migration

```jsonc
{
  "profileVersion": 2,                  // was 1
  "stars": 64,                          // KEEP: lifetime total, still shown
  "completedActivities": [...],         // KEEP
  "currentChapter": "ch3",              // new
  "currentLevel": "lvl11",              // new
  "starsByLevel": { "lvl11": 2 },       // new — the real progression signal
  "unlockedChapters": ["ch1","ch2"],    // new
  "unlockedRooms": ["bedroom"],         // new
  "unlockedOutfits": [],                // new
  "selectedCareer": "",                 // new
  "settings": { ... }                   // KEEP, incl. unlockedStickers
}
```

**Migration rule:** a v1 profile must load without data loss. Existing `stars` and
`completedActivities` are preserved; the new fields default empty; `completedActivities` can
seed `starsByLevel` where a task id maps to a known level. `ProfileStore` already handles six
corruption shapes and merges partial data over defaults — extend that, do not replace it.

**Risk:** a real device currently holds a v1 profile with 64 stars and 26 completed activities.
Migration must be tested against **that actual file**, not only synthetic fixtures. A copy is
already pulled to `/tmp/dp6/profile.json`; it should be committed as a test fixture.

---

## 4. Implementation order

Each step ends green (project loads, tests pass, iOS build succeeds) and is independently
revertable.

| # | Step | Depends on | Regression risk |
|---|---|---|---|
| 1 | Save schema v2 + migration + fixture test from the real device profile | — | **Low** — additive; existing corruption tests still apply |
| 2 | Per-level 3-star evaluation in `RewardLedger` / `LevelSystem` | 1 | **Medium** — reward integrity is subtle; the no-double-pay tests must keep passing |
| 3 | `ChapterSystem` + journey-map UI over existing missions-as-levels | 2 | Low — additive UI |
| 4 | `Room` + `HouseWorld`; baby room becomes the first Room | — | **Medium** — touches the one scene everything currently loads |
| 5 | **`CharacterController` + navigation + tap-to-walk** | 4 | **High** — entirely new, no existing foundation, mobile input subtleties |
| 6 | `playAction()` semantic layer + expanded animation set | 5 | Medium — the current 5 clips must keep working throughout |
| 7 | New modes (`sequenceRoutine`, `tidyUp`) | 2, 5 | Low — the mode interface already exists |
| 8 | Vertical slice content ("A Day With Little Buddy") | all | Low — data, not code |

**Rule: do not start step 5 until steps 1–4 are green and committed.** Navigation is the piece
most likely to churn, and it should not churn on top of unstable progression code.

---

## 5. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Navigation is entirely new** and mobile tap-to-walk has many failure modes (unreachable targets, path through furniture, character stuck) | **High** | Own milestone, own tests, a "never stuck" invariant test, and a forgiving drag-character fallback |
| Per-level stars touch the reward ledger, the most integrity-critical code | Medium | Extend rather than rewrite; keep every existing no-double-pay test green |
| Multi-room + character rig raises the draw-call/triangle budget well above today's ~14k tris / 158 draw calls | Medium | Room streaming (load only the active room), budget per room in the art bible, measure on device |
| Scope: 9 chapters / ~37 levels is far beyond one vertical slice | **High** | Phase B ships **one** slice. The level matrix must reduce to ~6 reusable templates or the scope is not real |
| Commissioned character arrives incompatible with mission logic | Medium | `docs/CUSTOM_BABY_SPEC.md` contract: socket names, semantic actions, scale, pivot — with a test that markers move with animation |
| Deprecating the legacy loop too early leaves no fallback if content fails to load | Low | Keep `FeedActivity` until levels are proven on device, then remove in its own commit |
| Speech regressions during refactor | Medium | **Freeze the speech subsystem and the iOS pipeline for this migration.** Device-proven; do not touch. |

---

## 6. What explicitly does NOT change

- iOS export pipeline, signing, Team ID, `tools/export_ios.sh`
- The native speech plugin and `SpeechService`
- Offline-first: no network calls, no analytics, no cloud save
- Privacy: no child audio recorded, persisted or uploaded
- The CC0-only asset policy, and the exclusion of Quaternius
- Child-UX rules: no red X, no scores, no timers, no failure pressure, speech never blocking
- The test runner's fail-loud behaviour

---

## 7. Cross-document reconciliation

The eight design documents were written in parallel and then reviewed against each other and
against the Game Bible. This section records the contradictions found and how they are resolved.

### 7.1 Two agent-reported "repo contradictions" that are factually wrong

Both were checked against the actual files before acting. **Neither is real — do not propagate them.**

| Claim | Reality |
|---|---|
| "`CLAUDE.md` says *2D only, Compatibility renderer*, contradicting the 3D Bible" | **False.** `CLAUDE.md` was updated on 2026-09-16 and reads *"Lightweight stylized **3D** presentation"* + *"**Mobile** renderer"*. `grep -i '2D only\|Compatibility renderer'` returns nothing. |
| "The shipped code uses `#FFF6E5`/`#FFC1CC`/`#A8E6CF`, not the spec's `#FFF4E0`/`#F8BFD1`/`#9EDCC3`" | **False.** The three spec values each appear in the code; the three claimed values appear **zero** times. The spec palette is canonical and needs no correction. |

### 7.2 Genuine Game Bible contradictions — resolutions

| # | Contradiction | Resolution |
|---|---|---|
| 1 | **§5.1 makes star 3 exploration; §5.2's worked example makes star 3 speech.** | **Star 1 = complete the activity (touch alone). Star 2 = English listening (`findIt`). Star 3 = optional exploration/care.** Speech is a bonus route *within* star 2, never its own star — otherwise speech becomes a progression gate, which product decision #8 forbids. |
| 2 | **§7 "mostly in and around the home" vs §8's park, wedding, hospital, school, 10 careers.** | Non-home locations become **storybook cards** or one data-dressed set. Only the home is a navigable 3D space in v1. |
| 3 | **"3–8 activities in 4–10 minutes"** is arithmetically impossible (8 activities in 4 min = 30 s each including TTS, a speech attempt, an animation and a reward). | Target **3–5 activities** per level. |
| 4 | **§17 main character 15k–35k triangles.** | **Rejected: 2,500–4,000.** Evidence: the entire current scene is ~14k triangles and *all 18 shipped third-party models combined* total 2,996. At 35k one character would be 2.5× the whole world, and in a flat-shaded one-light style the extra geometry is invisible while breaking silhouette consistency with 200–500-tri furniture. |
| 5 | **§2.1 lists 10 life stages but also 5 model families.** | 5 families / 9 variants / **one 20-bone rig** / one rotation-only animation library. Families split where *rig usage* changes (non-ambulatory → walking), not where a story label changes. |
| 6 | **§13 writes `character.playAction()` but `CLAUDE.md` mandates snake_case.** | `character.play_action("drink")` — snake_case method, camelCase action-id strings (matching the JSON key convention). |
| 7 | **§18 `selectedCareer` (single) vs §8 "not a permanent irreversible choice".** | `triedCareers[]` plus a last-chosen value. |
| 8 | **§9 sandbox "no quiz popup" vs §4/§5 stars only from levels** — no rule for whether free play earns anything. | Free play is the **star-3 route**. Flagged as an invention requiring product sign-off (§7.4). |

### 7.3 Sequencing change — adopted from the story review

`VERTICAL_SLICE_PLAN.md` originally proposed going straight to the Chapter 3 toddler slice.
The story review found a better first step, and it is adopted:

**Chapter 2 (Baby Days) ships first.** Its five existing missions map ~1:1 onto Levels 6–10
using content that already ships and validates. It proves the level shell, per-level stars, the
journey map and the save migration with **zero new gameplay code, zero new objects and no
movement system**. Chapter 3 then remains the real vertical slice, where tap-to-walk is proven.

This de-risks the migration: progression is stable *before* the highest-risk new system lands.

### 7.4 Decisions requiring product-owner approval

1. **Who walks.** Bible §6/§12 command Little Buddy; §2.2 lists "move Little Buddy" as a Big
   Buddy action. Assumed: the player has **no avatar body**, and `tapToWalk` moves Little Buddy.
   Confirm before the character controller is built, or it needs a `subjectId` parameter.
2. **Chapter 1 has no playable Little Buddy** (pre-birth) — the game's core verb is absent for
   the first ~20–30 minutes, which are also the most art-expensive. The character controller
   must therefore be **character-agnostic from day one**.
3. **Free play earning star 3** — invented to resolve §7.2 #8; needs confirmation.
4. **Spaced review.** The Bible has no review mechanic; 460 words met once will be forgotten.
   Proposal: draw `findIt` distractors preferentially from words introduced 2–5 levels earlier —
   review at zero content cost and no quiz screen.
5. **Chapter 9's 10 careers** are the largest art ask in the game for the shortest content.
   Proposal: 4 at launch, the rest behind Free Life mode.
6. **Thai hints fade from Preschool onward** — without a fade, `thaiHints` silently becomes the
   primary channel by Chapter 4.

### 7.5 Amendments owed to `docs/CUSTOM_BABY_SPEC.md`

The spec was written for a non-walking baby and is now under-specified. It needs amending
(not rewriting) before it goes to an artist: **8–12 bones → 20** (the 8–12 rig cannot carry a
shared locomotion library), **9 clips → 30 semantic actions**, **4 → 8 sockets** (adding
`FaceMarker`, `HeadMarker`, `BackMarker`, `SitMarker`), and **4 → 8 blend shapes**. Height,
triangle budget, materials, texture size, export format, licence terms and the socket-must-move
rule are all unchanged. **The palette section needs no correction** (§7.1).

### 7.6 Honest scope assessment

The full roadmap is **~10× today's content**: ~460 words, ~340 tasks, ~1,690 phrase variants,
**~250 3D objects**, 39 levels across 9 chapters.

**The 250 objects are the ceiling, not the English.** Content authoring scales; art does not.

Recommended: author **Baby + Toddler only** (~120 words, ~95 tasks, ~2.5× today) before the
vertical slice proves out. Chapters 4–9 should be treated as an authoring-pipeline problem, and
not started until the slice is genuinely fun and genuinely pretty on a device.

39 levels reduce to **6 reusable templates** (`fetchAndGive`, `sequenceRoutine`, `placeIt`,
`chooseCorrectObject`, `storybookBeat`, `walkTo`), of which **five are already shipped code**.
Only `walkTo` is new engineering. That is what makes the scope defensible.
