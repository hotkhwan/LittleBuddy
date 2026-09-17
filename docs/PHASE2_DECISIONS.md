# Phase 2 — approved decisions and their tradeoffs

Branch `feature/level-progression-v2`. Phase 1 landed as `f422555` (35/35 green, iOS arm64
build succeeded). This records the five pre-navigation decisions, the risk of each, and two
findings that changed what the decisions actually mean in code.

---

## 1. Skip semantics: completion and stars become separate concepts

**Approved rule.** ★1 = core objective genuinely completed · ★2 = + listening/English ·
★3 = + optional/free play. Skip must never trap the child, but skipping every core objective
must not look like a core success. A child may unlock the next level with 0 stars.

### What Phase 1 shipped, and why it was wrong

Phase 1 made finishing a level always worth ★1 (`maxi(rate_session(...), 1)`), so that a child
who used the skip button on every task still unlocked the next level. The reasoning was sound —
the skip button is the room's no-dead-end escape hatch, and the codebase already treats a skip
"exactly like a completion on the progress dots"; a permanent lock would turn a no-penalty
promise into a penalty.

The mistake was **fixing it in the wrong currency**. It bought no-dead-ends by corrupting the
rating: a skip-through and a genuine touch-only completion became indistinguishable at ★1. The
owner's split fixes the cause instead of the symptom.

### The model

| Concept | Key | Set when | Gates |
|---|---|---|---|
| Completion | `levelCompleted` | child reaches the end, **skips included** | unlocking |
| Rating | `starsByLevel` | earned honestly, **skips excluded** | stickers, bonus |

A level completed with 0 stars is a legitimate, expected state. Nothing in the child-facing UI
may present it as failure — `session_summary.gd` already says "Nice playing!" at 0 and that tone
stands. No red X, no score, no percentage (CLAUDE.md, binding).

### Regression risk: LOW — and the reason is worth writing down

The old rule was committed but **never installed on a device**. The product owner's real profile
is `profileVersion: 1` (captured as `game/tests/fixtures/device_profile_v1.json`: 64 stars, 33
completed activities, 11 stickers). No save anywhere was ever written under the completion==★1
rule, so there is no population of profiles to migrate *off* it and no child whose earned rating
can be retroactively reduced.

Had v2 shipped first, this change would have been genuinely expensive: every level a child
completed by skipping would have to either lose its star (visible demotion — forbidden, we never
subtract a star) or keep an unearned one (permanently corrupt ratings). Changing it now costs
nothing. **This is the cheapest moment this decision will ever be available**, which is the
argument for doing it before navigation rather than after.

What does carry risk:

| Risk | Mitigation |
|---|---|
| Unlock derivation changes source (`starsByLevel` → `levelCompleted`) | keep it DERIVED, not accumulated, so replay/double-apply stay idempotent by construction |
| Phase 1 tests assert the old rule | `test_level_summary.gd` asserts the `maxi(..., 1)` line exists; that assertion is now wrong and is replaced, not deleted |
| Two star currencies could get summed | existing assertion that they are never added stays |
| Legacy `unlockAtStars` still gates untagged missions | untouched; the assertion that one star on `milkTime` opens `bathTime` (which still carries `unlockAtStars: 10`) stays |

### Schema

v2 → v3, additive. `levelCompleted` is a Dictionary keyed by levelId, deliberately parallel in
shape to `starsByLevel` so the two currencies stay visibly separate.

- **v2 → v3:** any level with `starsByLevel[id] >= 1` becomes completed. Nothing else changes.
- **v1 → v3:** unchanged seeding — at most 1 star for a level whose every task appears in
  `completedActivities` — and those same levels marked completed. Under-crediting is safe;
  over-crediting is not.
- Migration stays idempotent; v3 and newer pass through to field sanitisation.

---

## 2. Story Mode follows authored order

**Finding that changes the shape of this work: there is no Story/Free Play split in the code.**
The modes today are `MISSION` and `LEGACY`. "Legacy random mission selection" is
`_pick_mission_id()`, used by `MISSION` mode, which picks at random among unlocked missions and
deliberately avoids an immediate repeat.

So this is not "move random selection from Story to Free Play" — Free Play does not exist. It is:

- `MISSION` mode becomes **Story Mode** and follows `LevelSystem`'s authored order.
- `_pick_mission_id()` is **preserved in place**, explicitly marked as the Free Play picker,
  and called by nobody until Free Play is built.

Keeping the picker rather than deleting it is deliberate: it is small, tested, and re-deriving
"random but never an immediate repeat" later is pure waste.

Note the two are not interchangeable. The random picker *avoids* repeating the last mission —
which is exactly wrong for a Replay button. That mismatch is why Phase 1's Replay had to pass an
explicit mission id rather than call the picker.

---

## 3. No journey/level-select map yet

Story Mode gets only: a current chapter/level label, Replay, Next Level, authored progression.
Replay and Next already exist from Phase 1.

---

## 4. `DEFAULT_LEVELS_PATH`

**Finding: it is not dead code.** `profile_store.gd` declares
`res://content/levels/levels.json`, and it is both a constructor default and a real read path in
migration. The file was never created — levels landed in `content/missions/missions.json` plus
`content/chapters/chapters.json` — so the read always falls through to the mission file. That
fallback is what actually ran in the verified v1 migration.

So it is a live path to a file that does not exist, not an unused constant. Removing it means
rerouting the read to the mission/chapter files while keeping the injectable-path seam the tests
use. Low risk, but it is a behaviour change, not a deletion.

---

## 5. Chapter 3 stays `"status": "planned"`

Only levels whose content ships today are listed. `gettingDressed` and the `sayItChallenge`
bonus remain tagged `ch3`.

---

## Still deliberately not started

Tap-to-walk integration into the room, `HouseWorld`, four rooms, new 3D art, Meshy, Free Play,
the journey map, vocabulary review (`docs/VOCABULARY_REVIEW_SPEC.md`), Chapter 3 content.
