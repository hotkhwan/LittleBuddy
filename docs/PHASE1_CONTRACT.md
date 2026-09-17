# Phase 1 Contract — Level Progression v2

Shared interface for the Phase 1 agents. **Approved product decisions are recorded in
`docs/ARCHITECTURE_MIGRATION_PLAN.md` §7.4.**

> ## ⚠️ Superseded on two points — see `docs/PHASE2_DECISIONS.md`
>
> Phase 1 shipped as described here and is committed as `f422555`. The product owner then
> approved two changes, so the following statements below are **no longer true of the code**:
>
> | This document says | Actually true now |
> |---|---|
> | schema version **2** | schema version **3** |
> | unlocking gates on `starsByLevel` ≥ 1 | unlocking gates on `levelCompleted`, a separate key |
> | finishing a level always earns ★1 | ★1 requires the core objective to be **genuinely** completed; a skip-through completes the level with **0 stars** |
>
> Everything else here — the two-star-currency rule, the Chapter 2 mapping, the SaveService
> level-stars API, and the migration's preserve-`stars`/`completedActivities` guarantee — still
> holds exactly as written. The two-currency rule in particular is now enforced by *three*
> keys rather than two: `stars` (lifetime tasks) · `starsByLevel` (0–3 rating) ·
> `levelCompleted` (progression gate). None of them are ever summed.

## The crux: two different star currencies

Getting this wrong double-counts stars and breaks all 16 existing sticker thresholds.

| Currency | Key | Meaning | Feeds |
|---|---|---|---|
| **Task stars** (existing) | `stars` | lifetime running total, +1 per completed task | sticker `unlockAtStars` thresholds |
| **Level rating** (new) | `starsByLevel` | per level, **0–3**, best-ever | level/chapter unlocking, journey map |

They are **not** the same number and must never be summed together. A device profile today
holds `stars: 64` from 26 completed tasks; that value is preserved verbatim by the migration
and keeps driving stickers exactly as it does now.

## SaveService additions (Agent SAVE owns these)

```gdscript
# chapter / level position
func get_current_chapter() -> String
func set_current_chapter(chapter_id: String) -> void
func get_current_level() -> String
func set_current_level(level_id: String) -> void

# per-level rating, 0..3 -- MAX-WINS, never decreases
func get_level_stars(level_id: String) -> int
func set_level_stars(level_id: String, stars: int) -> void
func get_stars_by_level() -> Dictionary        # deep copy
func get_total_level_stars() -> int            # sum of starsByLevel values

# unlocks
func is_level_unlocked(level_id: String) -> bool
func unlock_level(level_id: String) -> void
func is_chapter_unlocked(chapter_id: String) -> bool
func unlock_chapter(chapter_id: String) -> void
func is_room_unlocked(room_id: String) -> bool
func unlock_room(room_id: String) -> void

signal level_stars_changed(level_id: String, stars: int)
```

**`set_level_stars` is max-wins.** Replaying a level with a worse result must never reduce the
stored rating. This is what makes "replay does not corrupt progress" true by construction
rather than by discipline, and it honours the rule that stars are never subtracted.

## Schema v2

```jsonc
{
  "profileVersion": 2,
  "stars": 64,                        // PRESERVED task-star total; still feeds stickers
  "completedActivities": [...],       // PRESERVED
  "currentChapter": "ch2",
  "currentLevel": "milkTime",
  "starsByLevel": { "milkTime": 3 },  // 0..3 per level
  "unlockedChapters": ["ch2"],
  "unlockedLevels": ["milkTime"],
  "unlockedRooms": ["nursery"],
  "settings": { ... }                 // PRESERVED, incl. unlockedStickers
}
```

## Migration v1 → v2 (Agent SAVE owns)

Additive and lossless. A v1 profile must load with **zero** data loss:
- `stars`, `completedActivities` and every `settings` key carry over untouched.
- New fields default to empty, then are seeded: any level whose tasks are all present in
  `completedActivities` is granted **1 star** (core completion) and marked unlocked. We cannot
  know retroactively whether the listening or optional star was earned, so we grant only star 1
  — under-crediting is safe, over-crediting is not.
- Chapter 2 and the first level are always unlocked so no profile can be stranded.
- An unknown/newer `profileVersion` must not crash; fall through to field-by-field sanitisation
  exactly as the existing loader does for corrupt data.

**Test against the real device profile**, not only synthetic fixtures — a copy with 64 stars
and 26 completed activities is committed as a fixture.

## Star rules (Agent LEVEL owns)

| Star | Condition |
|---|---|
| 1 | core level completion — **achievable by touch alone** |
| 2 | English listening/recognition tasks completed (`findIt` / `sayIt`) |
| 3 | optional exploration / help / cleanup / free-play challenge |

**Speech is never required for any star.** A `sayIt` task completed by touch still earns star 2.
Never subtract a star. Never show failure. 2/3 passes the level; 3/3 grants a bonus sticker.

## Chapter 2 mapping (Agent LEVEL owns)

Five existing, already-validated missions become Chapter 2 levels. **No new gameplay code, no
new objects, no movement system.**

| Level | From mission | Title |
|---|---|---|
| L6 | `feedingTime` | Milk Time |
| L7 | `bathTime` | Bath Time |
| L8 | `bedtimeRoutine` | Bedtime |
| L9 | `playTime` | Toys & Smiles |
| L10 | `colorsAndShapes` | First Words |

`morningRoutine` (a dressing set) and `sayItChallenge` stay available but belong to Chapter 3;
do not delete them.

**Unlock rule: progression gates on completion (≥1 star), not on a star count.** A child must
never be locked out for playing imperfectly.

## Hard constraints for this phase

- **No `CharacterBody3D`, no `NavigationAgent3D`, no `HouseWorld`, no new 3D art.**
- **Do not modify the speech plugin or `tools/export_ios.sh`.**
- Existing missions must keep working throughout.
- The full suite (currently 30 cases) must stay green at every commit.
