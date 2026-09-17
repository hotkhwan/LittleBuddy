# Vocabulary Review — Design Spec

**Status:** spec only. Not implemented in Phase 1.
**Approved product decision:** add lightweight review; it must feel like normal gameplay.

---

## 1. The problem

By the end of the roadmap the game teaches ~460 words. A word met once in Level 12 and never
seen again is a word the child does not learn. There is currently **no review mechanic
anywhere** — and the failure is already visible at 46 words: five words (`eat`, `drink`,
`wear`, `throw`, `moon`) exist in `vocabulary.json` but are never a task target and never
spoken in any prompt.

## 2. The constraint that shapes everything

**No flashcards. No study screen. No quiz mode. No review popup.**

A child playing a life-sim does not want to be tested. The moment review looks like testing,
it stops being play — and the project's own quality bar says a feature is done only when the
child understands it, not when it is technically present.

So review must be **invisible**: it happens inside activities the child already wants to do.

## 3. The mechanism: weighted resurfacing

Review is delivered by **biasing object selection**, not by adding content.

Every level already spawns distractors — a `findIt` task shows the target plus 2–3 others.
Today those distractors are picked from the same category. Instead:

> **Draw distractors preferentially from words the child learned 2–5 levels ago.**

That is the whole idea. A child asked to "find the banana" while an apple, a spoon and a
toothbrush sit beside it is re-encountering three older words — reading each silhouette,
rejecting it, and reinforcing it — with **zero new content, zero new UI and zero new screens**.

Three additional carriers, all free:

| Carrier | How review happens |
|---|---|
| `findIt` distractors | as above — the primary channel |
| Free Play | tapping any object speaks its word; weight which objects are present in a room |
| `followInstruction` targets | occasionally route an instruction through an older object |

## 4. Scheduling

Deliberately simple. **Do not build an adaptive-learning engine for v1.**

Per word, track only:

```jsonc
"milk": { "lastSeenLevel": 12, "exposureCount": 7, "successCount": 5 }
```

Selection weight:

```
weight = base
       × recencyFactor(levelsSinceLastSeen)
       × strugglingFactor(successCount / exposureCount)
```

- `recencyFactor` — **zero inside a cooldown window** (immediately-repeated words feel like
  nagging), rising to a peak around 2–5 levels since last seen, then gently decaying. Words
  never seen again should not silently fall to zero; give a long tail.
- `strugglingFactor` — mild. A word the child gets wrong resurfaces somewhat more often. **Mild
  is deliberate**: aggressively drilling a word a child struggles with is exactly how a game
  starts to feel like a test.
- `base` — from `reviewWeight` in settings so it is tunable without a code change.

**Immediate repetition is forbidden.** The existing `TaskPicker` already guarantees "never the
same task twice in a row" and is pure and tested — the same guard applies here.

## 5. Data

Additive only. Existing content and saves keep working untouched.

```jsonc
// vocabulary.json — optional per-word keys
{ "stage": "toddler", "introducedAtLevel": "milkTime", "exposure": "active" }

// profile — new optional block, absent means "no review history yet"
"vocabularyProgress": {
  "milk": { "lastSeenLevel": 12, "exposureCount": 7, "successCount": 5 }
}

// settings
"reviewWeight": 1.0        // 0.0 disables review entirely
```

A missing `vocabularyProgress` must behave exactly like today's selection. Review is an
enhancement layered on working behaviour, never a prerequisite.

## 6. What this explicitly is NOT

- ❌ a review/quiz screen
- ❌ a "words you've learned" list in the child UI
- ❌ scores, percentages, accuracy readouts, streaks
- ❌ a leech/lapse algorithm (SM-2, Anki-style)
- ❌ anything that interrupts play to test
- ❌ punishment or correction for a wrong answer — the existing gentle-retry ladder stands

A **parent-facing** summary of words practised could live behind the parent gate later. That is
a different feature with a different audience, and it is out of scope here.

## 7. Thai hints interaction

Per the approved decision, Thai hints reduce with stage: freely available at Baby/Toddler,
shorter at Preschool, English-first with Thai fallback at School+. Parent Settings can force
them ON or OFF at any time, overriding the progression.

Review targets **English recognition**, so a resurfaced word should not automatically re-show
its Thai hint — otherwise the child reads Thai and never re-reads the English. Hints stay on
the long-press path.

## 8. Implementation phase

**Not Phase 1.** Phase 1 is level semantics, per-level stars and save v2.

Review needs: (a) levels to exist so "levels since last seen" is meaningful, and (b) enough
vocabulary for resurfacing to matter. Sensible landing point is **after the vertical slice**,
when there are ~120 words across Baby + Toddler.

The only Phase 1 obligation is to **not block it**: keep the profile schema open to an additive
`vocabularyProgress` block, and keep distractor selection in one place so it can later be
weighted rather than uniform.

## 9. Success criterion

> A child re-encounters an older word roughly every 2–3 levels without ever seeing a screen
> that looks like a test — and a parent watching cannot tell which objects were chosen for
> review and which for the story.

If review is visible as review, the design has failed.
