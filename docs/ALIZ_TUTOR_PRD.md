# Aliz Tutor Mode — Product Requirements (V1)

**Product line:** Little Days (free game). **Feature:** "Aliz, your child's playful
learning companion." **Owner:** Agent A (product + deterministic lesson system).
**Status:** V1 ships the local scripted tutor; the cloud tutor stays behind
`TutorFlags.cloud_enabled()` (false in every public build) until the privacy
review passes. Contracts: `docs/ALIZ_TUTOR_CONTRACTS.md`.

## 1. Concept

Aliz (the pink girl buddy) sits at a small classroom board and teaches English
in five-minute sessions. She shows a picture, asks one short question, listens,
and reacts with her face and voice. The child speaks or, when speech is
unavailable, taps the picture. There is no keyboard, no reading, no score.

Two layers, strictly separated:

- **Deterministic lesson engine** (`game/scripts/tutor/lesson/`) owns what is
  taught, in what order, what counts as a correct answer, when to hint, when to
  move on, and what is rewarded. It is bundled JSON plus pure GDScript, offline,
  and it produces a complete lesson on its own.
- **Conversation layer** (later, flag-gated) may *rephrase* Aliz's wording to feel
  personal. It may never change `expectedAnswers`, the step order, stars, or
  the retry policy. If it is off, unavailable or invalid, the scripted lines play.

The game is free. The AI tutor is the monetisable feature: **5 free minutes per
day**, more with Family Club (quota and entitlement are Agent F's; the child
never sees a price, a lock or a countdown).

## 2. Audience

Children aged 3–6 in Thai families learning English as a second language, on a
shared iPad or the parent's iPhone, usually with a grown-up nearby but not
always. The child may not read in any language. The grown-up may not speak
English confidently, so the helper line (Thai by default, other languages via
the existing helper-language setting) exists for them, not for the child.

## 3. The five-minute session

`targetDurationSeconds: 300`. Shape of a full lesson (the first one has 18 steps):

| Phase | Steps | Aliz | Time |
|---|---|---|---|
| Hello | 1 teach | "Hello! Let's learn together!" | 6 s |
| Item loop x4 | ask name → ask colour → teach recap | "What is this?" / "Great job! What colour is it?" / "Yes! It's a red apple!" | 4 x (22+22+6) = 200 s |
| Mixed review | 4 asks | "Which one is yellow?" ... | 4 x 22 = 88 s |
| Celebrate | 1 celebrate | "You did it! ... Here is your sticker!" + stars | 10 s |

Budget model (enforced by `LessonValidator`): teach 6 s, ask 12 s + 10 s retry
allowance, celebrate 10 s; the sum must land within 20% of the target. The
first lesson estimates at 304 s. Starter lessons are 4 steps and 60 s.

The session ends at the celebrate step, or earlier at a safe turn boundary when
the daily quota runs out (break screen: "Great job today! Come back tomorrow for
more Little Days! Keep playing with Bunny!"). Leaving early keeps progress;
coming back resumes the same step.

## 4. Subjects and lessons (`game/content/tutor/subjects.json`)

Aliz opens with the menu lesson `welcome_choose` (one `choose` step: "Hi! What
would you like to learn today?"). What the child says routes by the subject's
`keywords` ("animals", "cat", "dog" → Animals; "fruits", "colours" → Fruits and
Colours; "numbers", "count"; "everyday", "cup"; "red and blue"); "anything",
"you choose", "I don't know" or a third unclear answer go to the default lesson.

| Subject | First lesson | Steps | Sticker |
|---|---|---|---|
| Fruits and Colours (`english_basics`) | `english_colors_fruits` (complete, default) | 18 | appleSticker, 3 stars |
| Numbers | `numbers_one_two_three` (starter) | 4 | starSticker, 1 star |
| Red and Blue (`colors`) | `colors_red_blue` (starter) | 4 | rainbowSticker, 1 star |
| Animals | `animals_cat_dog` (owner's acceptance dialogue, ≤ 90 s) | 6 | heartSticker, 1 star |
| Everyday Things | `everyday_cup_spoon` (starter) | 4 | milkSticker, 1 star |

Every subject has at least one real lesson so the selector never dead-ends.
Lessons are data (`lesson_schema.json`, camelCase, English-only answers with
synonyms, a hint, an encouragement and a success line per question, an optional
owner voice-pack `spokenLineId`). Visuals come only from
`assets_allowlist.json` (13 ids). Adding a lesson is adding a JSON file and one
id to `subjects.json`; the test suite validates it.

### The first lesson — English: Colors and Fruits

s01 hello → s02 apple? → s03 red? → s04 "Yes! It's a red apple!" → s05 banana?
→ s06 yellow? → s07 recap → s08 orange? → s09 orange? → s10 recap → s11
grapes? → s12 purple? → s13 recap → s14 "Which one is yellow?" → s15 "Which
one is red?" → s16 "Which one is purple?" → s17 "What colour is the orange?" →
s18 celebrate (3 stars, appleSticker).

### Animals — the owner's acceptance dialogue

"Yay! Let's learn about animals!" → "What animal is this?" (cat) → `sound`
"Can you make a cat sound?" (meow / miaow / mew) → Aliz claps, laughs and says
"Meow! You're amazing!" → dog → "Can you make a dog sound?" (woof / bark /
ruff / arf) → celebrate. Estimate 88 s.

### Barge-in (hands-free)

While Aliz speaks the child may interrupt. `LessonEngine.handle_interjection()`
turns the words into one of: **jump** to another item of this lesson ("Wait! I
want a dog!" → "Okay! Let's see the dog!"; the skipped question comes back
before the celebrate), **switch** to another subject ("I want numbers"),
**end** ("stop", "I'm done", "bye"), or nothing (an answer is an answer; anything
else makes Aliz repeat the question). Interjections never count as attempts.

## 5. Turn UX states

| State | Banner | Aliz | Rule |
|---|---|---|---|
| Speaking | (subtitle) | mouth from audio amplitude, gesture from turn | mic closed |
| Listening | "Listening" | expression `listening` | hard cap, then Timeout |
| Thinking | "Thinking" | `thinking`, tilt | ≤ 1.5 s locally; the scripted path is instant |
| Success | "Great!" | `happy`, clap/nod | success line, then next question |
| Incorrect | "Let's try together!" | `encouraging`, tilt | 1st miss: encouragement; 2nd: hint; 3rd: teach the answer and move on |
| Timeout / unclear | "Let's try together!" | `encouraging` | same escalation as a miss; never says "wrong" |
| Reaction (sound step) | "Great!" | gesture + sfx + Aliz's own sound ("Meow!") | from the step's `reaction`, only on a match |
| Interrupted | "Listening" | stop mouth, turn to the child | then jump / switch / end / repeat |

Every ask also has a **tap fallback**: tapping the picture card counts as the
answer, so the lesson completes with speech off, denied or unavailable.

## 6. Safety rules (binding)

1. **No fail state.** Three misses teach the answer ("It's an apple! Say
   apple.") and continue. Outcome is reported as `unclear`, never as failure.
   Stars are never subtracted. Every lesson reaches its celebrate step.
2. **No fake recognition.** A transcript is judged by `AnswerMatcher` against
   the lesson's answers, and only a real match plays a success line. The mock
   speech provider is never used on a device build (existing guard).
3. **Encouragement only.** Lines are short ("Great job!", "Nice try!", "Let's
   try together!"). The validator bans "wrong", "incorrect", "fail", "bad" and
   any purchase vocabulary from every spoken field.
4. **No child-directed purchase pressure.** The child never sees a price, a
   timer, a lock icon or a "buy more time" prompt. Quota ends at a turn boundary
   with a warm break screen; any upsell lives behind the parent gate.
5. **Cloud off until privacy clearance.** `TutorFlags.cloud_enabled()` is false
   in public builds. No child audio or transcript leaves the device; nothing is
   persisted or uploaded. The scripted tutor is complete without the network.
6. **Content is bounded.** Speech ≤ 160 chars, ASCII-printable English, from the
   lesson file or the TutorTurn validator's safe fallback ("Let's try
   together!"). Visuals only from the allowlist.
7. **Local, honest progress.** `settings.tutorProgress[lessonId]` stores step,
   first-try count, completed and rewardGranted; stars are paid once per
   lesson by the engine, into the same profile star total as the rest of the game.

## 7. Success metrics (V1, measured on device or in playtests, no analytics SDK)

- **Completion:** ≥ 70% of started first lessons reach the celebrate step.
- **Time to first answer:** median < 15 s from "What is this?".
- **First-try rate:** 40–80% on the first lesson (below: too hard; above: too easy).
- **Recovery:** ≥ 90% of asks that reach a hint are answered or taught within
  the third attempt with the child still engaged (no exit within 10 s).
- **Speech-off completion:** 100% of lessons completable by tap alone (test-enforced).
- **Return:** a child who finishes a lesson opens Aliz again the next day ≥ 40%.
- **Zero:** parent reports of "she said my child was wrong", purchase prompts
  seen by a child, or network traffic from the tutor with the flag off.

## 8. What V1 explicitly does not do

- No free conversation, no open-ended questions, no generative dialogue
  (the choose menu and interjections route by keywords, deterministically).
- No LLM in the loop (the flag is off); no rewording of lesson lines.
- No pronunciation scoring, percentages, streaks, leaderboards or timers.
- No reading or writing; no letters on screen as the task.
- No Thai transliterations as accepted answers; the helper line is for grown-ups.
- No adaptive difficulty across sessions; order is the lesson file's order.
- No new 3D props: flashcards use the 13 allowlisted ids (cup/spoon in the
  everyday starter are taught by recall without a picture until assets exist).
- No account, cloud save, analytics, ads or in-lesson purchase flow.
- No child-directed quota messaging beyond the break screen.
