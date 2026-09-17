# Little Buddy — Vocabulary Roadmap v1.0

Design lock for Phase A (Game Bible §20). This document defines **what English is taught,
when, inside which activity, and at what complexity ceiling**, from newborn to first
career.

Companion docs: `INTERACTION_MATRIX.md` (how the child acts), `STORY_MAP.md` /
`LEVEL_MATRIX.md` (chapter and star structure), `CHARACTER_AGE_STAGES.md` (who is on
screen at each stage).

---

## 0. The one rule that governs this document

> **No word ships without an activity that needs it.**

Little Buddy is not a flash-card app and must never degrade into one. Concretely, three
hard gates apply to every vocabulary entry, enforceable in `content_validator.gd`:

| Gate | Rule | Validator check |
| --- | --- | --- |
| **G1 — Embodiment** | The word is an object you can touch, an action you can perform, or a state you can see on Little Buddy's face/body. | `word.objectId != "" OR word.actionId != "" OR word.stateId != ""` |
| **G2 — Consequence** | Doing the right thing with the word **changes the world**: hunger drops, a shirt goes on, a room gets tidy, a friend smiles. Never "correct → next card". | word appears in ≥1 task whose completion emits a mission event from `INTERACTION_MATRIX.md` §6 |
| **G3 — Echo** | The word is re-hearable forever in free play by tapping its object (Bible §9). | object exists in `objects.json` **or** the word is an action reachable in sandbox |

A word that passes only G1 is decoration. A word that passes G1+G3 but not G2 is a
flash card with a nice model. **All three or it does not ship.**

### 0.1 This gate already catches a real problem in today's content

Measured against the shipping data (46 words, 43 tasks):

| Class | Count | Words | Fix |
| --- | --- | --- | --- |
| Fully carried (target word or task object) | 32 | most nouns | keep |
| **Heard only** — spoken in a prompt, never practised | 9 | hungry, thirsty, wash, clean, wet, play, sleepy, bed, night | give each a task or accept as passive-only (see §6.3) |
| **Orphans** — never spoken, never a target, exist only in the word list | 5 | **eat, drink, wear, throw, moon** | either author an activity or delete the entry |

Those 5 orphans are exactly the flash-card failure mode appearing at 46 words. It scales
badly to 460. The validator rule above is the cheapest way to stop it permanently.

---

## 1. Stage model

Six learning stages, mapped onto the Bible's chapter structure and character age stages.

| # | Stage | Chapters | Levels | Character model family | Learner profile |
| --- | --- | --- | --- | --- | --- |
| S1 | **Baby** | 1–2 | 1–10 | newborn / baby (+ Mom, Dad in Ch1) | first contact with English; recognition over production |
| S2 | **Toddler** | 3 | 11–15 | toddler | can point, can repeat single words, starts 2-word chunks |
| S3 | **Preschool** | 4 | 16–20 | child | categories: colour, shape, number, politeness |
| S4 | **School** | 5 | 21–25 | child / older child | follows full instructions, sequences a routine |
| S5 | **Older Child** | 6 | 26–30 | older child | two-clause instructions, reasons, choices |
| S6 | **Teen / Career** | 7–9 | 31–40+ | teen / young adult | short conversation, plans, opinions |

**Judgement call:** the Bible's Chapter 1 (Mom & Dad, wedding, pregnancy) happens *before*
Little Buddy exists, so it has no age stage of its own. It is folded into S1 as the
"pre-birth" sub-block: same complexity ceiling (single words, warm social phrases),
different actors.

---

## 2. Complexity ceilings

The ceiling is a **hard cap on what the game may say and what it may ask the child to
say**. Content that exceeds its stage ceiling fails review.

| Stage | Child produces (Say It target) | Game speaks (Hear It / Do It) | Grammar allowed | Forbidden until later |
| --- | --- | --- | --- | --- |
| **S1 Baby** | 1 word (`"milk"`) | ≤5 words, one clause, imperative or simple declarative: *"I'm hungry." / "Find the milk."* | bare nouns, bare verbs, `a/the`, `my` | plurals-with-meaning, prepositions, questions other than *Where is…?* |
| **S2 Toddler** | 2–4 words (`"give milk"`, `"red shirt"`) | ≤7 words: *"Put the teddy in the box."* | `in / on / under`, `more`, `please`, adjective + noun, `let's` | tenses beyond present, *because*, multi-step |
| **S3 Preschool** | 3–6 words (`"I want the blue one"`) | ≤9 words, may contain two nouns: *"Give the red ball to your friend."* | numbers 1–10, colours, shapes, `my turn / your turn`, `thank you`, `can I…?` | past tense, conditionals |
| **S4 School** | full simple sentence (`"I brush my teeth"`) | 2-step instruction: *"First wash your face, then brush your teeth."* | present simple, `first / then / next`, Wh-questions, `can / let's / don't` | passive voice, perfect tenses |
| **S5 Older Child** | 1–2 sentence answer | 2-clause instruction with a reason: *"Put the books on the shelf because the table is messy."* | past simple (light), `should`, comparatives, `and / but / because` | idioms, phrasal-verb clusters |
| **S6 Teen/Career** | 2–4 turn exchange | short dialogue, opinion, plan: *"What do you want to be?" — "I want to be a chef."* | `going to / will`, `I think`, polite requests, simple reported speech | exam grammar, abstract debate |

Progression is therefore: **single words → short requests → simple instructions → short
conversation**, exactly as required.

---

## 3. Per-stage scope

### 3.1 Word budget

| Stage | Reused from today's 46 | New words | Stage total | Cumulative | New words / level |
| --- | --- | --- | --- | --- | --- |
| S1 Baby | **30** | 35 | 65 | 65 | ~6.5 |
| S2 Toddler | **7** | 48 | 55 | 120 | ~11 |
| S3 Preschool | **6** | 64 | 70 | 190 | ~14 |
| S4 School | **3** | 92 | 95 | 285 | ~19 |
| S5 Older Child | 0 | 85 | 85 | 370 | ~17 |
| S6 Teen/Career | 0 | 90 | 90 | 460 | ~9 (10 levels) |
| **Total** | **46** | **414** | **460** | | |

460 words is a realistic full-journey target for a child's first English game (comparable
to a well-scoped K–3 supplementary vocabulary). It is **not** a small amount of content:
see §8 for the honest scope warning.

### 3.2 Phrase / activity budget

Derived from the measured density of today's content: **43 tasks → 178 `acceptedCommands`
(4.1 per task) and 129 spoken lines (`prompt` + `instruction` + `repeatPrompt`)**.

| Stage | Tasks | Accepted phrase variants @4–5 | Spoken lines @3/task | Notes |
| --- | --- | --- | --- | --- |
| S1 | 50 | ~200 | 150 | today's 43 tasks cover most of this |
| S2 | 45 | ~200 | 135 | |
| S3 | 55 | ~250 | 165 | more variants: numbers/colours combine |
| S4 | 70 | ~350 | 210 | 2-step instructions need more variants |
| S5 | 60 | ~330 | 180 | |
| S6 | 60 | ~360 | 240 | dialogue = more lines per task |
| **Total** | **340** | **~1,690** | **~1,080** | |

**Today's build is ~11% of the final phrase corpus and ~10% of the word corpus.**

---

## 4. The three learning modes (Bible §10) mapped to the engine

These map 1:1 onto the modes that already exist — no new mode types are needed at any
stage. This is the most important reuse claim in this document.

| Bible mode | Engine mode (exists today) | Star | Definition |
| --- | --- | --- | --- |
| **Hear It** | `findIt` | Star 2 | Game speaks, child identifies the right object among distractors |
| **Say It** | `sayIt` | Star 3 (optional) | Game asks, child speaks; `IntentMatcher` is tolerant; touch always substitutes |
| **Do It** | `followInstruction` | Star 1 | Game instructs, child performs a world action from `INTERACTION_MATRIX.md` |

### 4.1 Mode mix per stage

| Stage | Hear It | Say It | Do It | Rationale |
| --- | --- | --- | --- | --- |
| S1 Baby | 40% | 15% | 45% | comprehension first; production barely expected |
| S2 Toddler | 35% | 25% | 40% | first real production, single words and 2-word chunks |
| S3 Preschool | 30% | 30% | 40% | categories drill naturally through Say It |
| S4 School | 25% | 30% | 45% | multi-step Do It carries the language |
| S5 Older Child | 20% | 35% | 45% | longer utterances |
| S6 Teen/Career | 15% | 45% | 40% | conversation-led |

Say It **never exceeds 45%** and is **never required for level completion** at any stage
(Bible §5.1). A child who never turns on the microphone can complete 100% of the game and
earn 2/3 stars on every level; the 3rd star is always also reachable through the
touch/exploration path (see `LEVEL_MATRIX.md`).

### 4.2 Concrete examples per stage

| Stage | Activity (level) | Hear It | Say It | Do It |
| --- | --- | --- | --- | --- |
| **S1 Baby** | Milk Time (L6) | *"Where is the milk?"* → tap the bottle among 3 | *"Can you say milk?"* → `"milk"` | *"Give the baby some milk."* → drag bottle to `mouth` |
| **S1 Baby** | Bath Time (L7) | *"Find the soap."* | `"soap"` | *"Wash the baby."* → drag soap to `bath`, scrub |
| **S1 Baby (pre-birth)** | Hello! (L1) | *"Who says hello?"* → tap Mom | `"hello"` | *"Wave to Dad."* → tap Dad → `greet` |
| **S2 Toddler** | Breakfast (L12) | *"Where is the banana?"* | `"I want banana"` / `"banana please"` | *"Sit down and eat the banana."* → `sit` then drag to `mouth` |
| **S2 Toddler** | Clean Up (L14) | *"Which one is the block?"* | `"put it in"` | *"Put the blocks in the toy box."* → `cleanUp` set of 4 |
| **S2 Toddler** | Getting Dressed (L13) | *"Find the red shirt."* | `"red shirt"` | *"Put on your shoes."* → drag to `dress` |
| **S3 Preschool** | Numbers (L19) | *"Where are the three apples?"* | `"three apples"` | *"Put three apples in the bowl."* → 3× drag to `plate` |
| **S3 Preschool** | Sharing (L20) | *"Who wants the ball?"* | `"your turn"` / `"here you are"` | *"Give the ball to your friend."* → `give` |
| **S4 School** | Morning Routine (L21) | *"Where is your toothbrush?"* | `"I brush my teeth"` | *"First wash your face, then brush your teeth."* → `wash` then `brushTeeth` |
| **S4 School** | Reading Time (L23) | *"Find the word 'cat'."* | `"cat"` / `"I can read"` | *"Open the book and turn the page."* → `open` + tap |
| **S5 Older Child** | Help at Home (L26) | *"Which shelf is empty?"* | `"I put the books on the shelf"` | *"Put the books on the shelf, then clean the table."* → two `cleanUp` sets |
| **S5 Older Child** | Cooking (L27) | *"Where is the mixing bowl?"* | `"first we mix, then we cook"` | 4-step recipe: `open` fridge → `carry` → `plate` → `play_action("mix")` |
| **S6 Teen** | My Schedule (L31) | *"What do you do in the morning?"* | `"I study in the afternoon"` | drag activity cards onto a timetable → `dragObjectToTarget(desk)` |
| **S6 Career** | My Future (Ch9) | *"Who helps sick people?"* | `"I want to be a doctor"` | perform the career mini-activity |

Every row is an activity in a room, with an object, a character reaction and a world
change. None of them is a card.

---

## 5. Stage detail

### S1 — Baby (Chapters 1–2, Levels 1–10) · 65 words

**Carrier activities:** greeting Mom & Dad, decorating for the family day, preparing the
nursery, welcoming the baby, feeding, bathing, bedtime, toys, first words.

| Group | Words | Source |
| --- | --- | --- |
| Feeding (10) | milk, water, apple, banana, spoon, bowl, hungry, thirsty, eat, drink | **existing** |
| Bath (8) | soap, towel, cup, bath, wash, clean, wet, dry | **existing** |
| Bedtime (8) | bed, blanket, pillow, lamp, sleepy, night, moon, good night | **existing** |
| Play (4) | teddy, ball, block, play | **existing** |
| Greetings & family (12) | hello, hi, bye-bye, mama, dada, baby, family, friend, name, please, thank you, yes/no | new |
| Feelings & faces (6) | happy, sad, love, smile, cry, sleepy* | new (*reuse) |
| Pre-birth objects (9) | cake, flower, photo, home, heart, small, bottle, crib, welcome | new |
| Body & basic verbs (8) | hand, foot, eye, mouth, up, down, more, hug | new |

**Ceiling:** 1-word production. All instructions ≤5 words. Every noun has a physical
object; every adjective has a visible face or state change.

**Say It list (only 12 words are ever asked for production at S1):** milk, water, apple,
banana, teddy, ball, soap, bed, hello, bye-bye, mama, dada. Everything else is
recognition-only at this stage — deliberately.

### S2 — Toddler (Chapter 3, Levels 11–15) · 55 words

**Carrier activities:** first steps (tap-to-walk), breakfast at the table, getting
dressed, cleaning up, playing.

| Group | Words | Source |
| --- | --- | --- |
| Clothing (7) | shirt, pants, shoes, hat, pajamas, wear, toy box | **existing, re-tiered** |
| Movement (10) | walk, stop, go, come here, run, jump, sit, stand, fast, slow | new |
| Prepositions (5) | in, on, under, here, there | new |
| Food & table (10) | bread, egg, rice, juice, plate, cup*, table, chair, hot, cold | new |
| Rooms (7) | kitchen, bedroom, bathroom, door, window, sofa, light | new |
| Tidy & help (8) | clean up, put away, help, mine, yours, big, small*, open | new |
| Daily phrases (8) | good morning, let's go, all done, one more, I want, no thank you, look, wait | new |

**Ceiling:** 2–4 word production. Prepositions are introduced here because
`dragObjectToTarget` finally has more than one zone per room — the grammar is taught by
the interaction, not by explanation.

### S3 — Preschool (Chapter 4, Levels 16–20) · 70 words

**Carrier activities:** first day of school, colours, shapes, counting, sharing.

| Group | Words | Source |
| --- | --- | --- |
| Colours (6) | red, blue, yellow + green, pink, orange | 3 **existing, re-tiered** + 3 new |
| Shapes (6) | circle, square, star + triangle, heart, rectangle | 3 **existing, re-tiered** + 3 new |
| Numbers (12) | one…ten, how many, count | new |
| School objects (17) | backpack, pencil, crayon, paper, book, desk, chair*, teacher, classroom, bag, glue, scissors, eraser, ruler, board, lunchbox, chalk | new |
| Sharing & manners (10) | give, take, share, my turn, your turn, please*, thank you*, sorry, excuse me, together | new |
| Size & compare (6) | big, small, long, short, same, different | new |
| Social (8) | friend*, play together, welcome*, nice to meet you, how are you, I'm fine, goodbye, see you | new |
| Question forms (5) | where, what, who, how many*, which | new |

**Ceiling:** 3–6 words. This is the first stage where two attributes combine
(*"the blue circle"*, *"three red apples"*) — that combinatorial step is the real learning
target, not the individual words.

### S4 — School (Chapter 5, Levels 21–25) · 95 words

**Carrier activities:** full morning routine, travelling to school, reading, art class,
sports day.

| Group | Words | Source |
| --- | --- | --- |
| Hygiene routine (8) | teeth, toothbrush + toothpaste, face, soap*, comb, hair, towel* | 2 **existing, re-tiered** + 6 new |
| Sport & movement (14) | throw + catch, kick, run*, jump*, ball*, team, win, play*, race, tired, fast*, strong, rest | 1 **existing, re-tiered** + 13 new |
| Time & sequence (12) | morning, afternoon, evening, today, tomorrow, first, then, next, after, now, later, o'clock | new |
| Transport & school (12) | bus, car, walk*, road, school, classroom*, lesson, bell, friend*, teacher*, playground, gate | new |
| Reading & writing (12) | read, write, book*, page, word, letter, story, name*, look at, listen, say, question | new |
| Art (10) | draw, colour, paint, paper*, pencil*, brush, picture, cut, stick, beautiful | new |
| Weather & outside (9) | sun, rain, cloud, hot*, cold*, wind, tree, flower*, sky | new |
| Full-sentence frames (18) | I can…, I like…, I want…, Let's…, Can you…?, Don't…, It's time to…, I'm ready, etc. | new |

**Ceiling:** full simple sentences and 2-step instructions. This is the stage where the
game starts speaking in sequences — and where `INTERACTION_MATRIX.md` W3 interactions
(`open`, `carry`, `sit`) become linguistically necessary rather than decorative.

### S5 — Older Child (Chapter 6, Levels 26–30) · 85 words

**Carrier activities:** helping at home, cooking together, choosing a hobby, friends, a
multi-step personal project.

| Group | Words |
| --- | --- |
| Housework (12) | make the bed, wash the dishes, sweep, tidy, dirty, messy, fold, laundry, rubbish, shelf, drawer, cupboard |
| Cooking (16) | mix, cut, pour, cook, boil, taste, sweet, sour, salt, sugar, flour, recipe, ingredient, hot*, careful, delicious |
| Hobbies (14) | music, guitar, drum, sing, dance, science, experiment, build, model, sport, draw*, camera, collect, practise |
| Feelings & reasons (12) | because, proud, excited, nervous, bored, kind, angry, calm, worried, glad, miss, hope |
| Teamwork (12) | help*, together*, idea, good job, plan, share*, listen*, agree, choose, try, finish, start |
| Comparison & opinion (10) | better, best, favourite, more*, less, easy, difficult, important, useful, my favourite is… |
| Past-tense frames (9) | I made…, I helped…, we went…, it was…, yesterday, last week, did you…?, I finished, I forgot |

**Ceiling:** 2-clause instructions and a stated reason. Every task in this stage has at
least **two** interaction steps (Bible L30: "a multi-step activity requiring movement,
object finding, and English instructions").

### S6 — Teen / Career (Chapters 7–9, Levels 31–40+) · 90 words

**Carrier activities:** planning a schedule, homework, teamwork, responsibility, dreams,
final project, graduation, ten career mini-activities.

| Group | Words |
| --- | --- |
| Schedule & study (14) | schedule, homework, computer, notes, exam, study, revise, subject, maths, science*, history, project, deadline, finish* |
| Responsibility (12) | remember, check, prepare, promise, on time, careful*, responsible, look after, in charge, tidy*, safe, rule |
| Conversation frames (16) | What do you think?, I think…, I agree, Maybe…, How about…?, Shall we…?, I'd like…, Could you…?, Thanks a lot, No problem, See you later, Good luck, Well done, I'm sorry, Excuse me*, Congratulations |
| Future & plans (12) | going to, will, dream, future, hope*, want to be, one day, next year, become, choose*, decide, goal |
| Careers (20) | doctor, nurse, teacher, engineer, artist, chef, scientist, firefighter, designer, programmer, vet, pilot, farmer, builder, musician, writer, police officer, dentist, photographer, astronaut |
| Graduation (10) | graduation, cap, certificate, proud*, family*, photo*, speech, celebrate, thank you*, I did it |
| Work objects (6) | computer*, tools, uniform, office, kitchen*, hospital |

**Ceiling:** 2–4 turn exchanges. The career activities are the only place multi-turn
dialogue appears, and each is short (Bible §9: "one small playful activity" per career).

---

## 6. Migration of today's 46 words

### 6.1 Verdict

| Verdict | Count | Detail |
| --- | --- | --- |
| **Reusable as-is** (word, Thai, `objectId`, `partOfSpeech` all valid) | **46 / 46** | Zero deletions, zero rewrites. Every existing record is schema-valid for this roadmap. |
| **Stay at S1 Baby** (their originally intended stage) | **30** | all feeding, bath, bedtime + teddy/ball/block/play |
| **Re-tiered to a later stage** | **16** | see §6.2 — a `stage` field change only, no content rewrite |
| **Needs an activity before it counts as taught** | **5** | eat, drink, wear, throw, moon (the orphans from §0.1) |

### 6.2 Re-tier table

| Word(s) | Today | Moves to | Why |
| --- | --- | --- | --- |
| shirt, pants, shoes, hat, pajamas, wear | dressing / S1 | **S2 Toddler** | Bible L13 "Getting Dressed" is a toddler level; dressing needs a standing, walking character |
| toy box | play / S1 | **S2 Toddler** | Bible L14 "Clean Up" is toddler |
| red, blue, yellow | dressing / S1 | **S3 Preschool** | Bible L17 is the colours level; at S1 they are decoration, at S3 they are the lesson |
| circle, square, star (shape sense) | play / S1 | **S3 Preschool** | Bible L18 is the shapes level. **`star` keeps a second S1 entry as a toy noun** — same word, two senses, two `wordId`s (`starToy`, `shapeStar`). |
| teeth, toothbrush | bath / S1 | **S4 School** | Bible L21 "Morning Routine"; `brushTeeth` needs the W2 gesture interaction |
| throw | play / S1 | **S4 School** | Bible L25 "Sports Day" |

### 6.3 The 9 "heard only" words

hungry, thirsty, wash, clean, wet, play, sleepy, bed, night are spoken by the game but
are never a task target. **Decision: keep them as deliberate passive vocabulary at S1**
(state words the child hears constantly and understands long before producing) — but add
a `exposure: "passive"` flag so the validator does not report them as orphans, and so the
progress UI never claims the child has "learned" them.

`hungry`, `sleepy`, `wet`/`dry` and `clean` also become **visible states** on the
character (`play_action("hungry")`, `play_action("sleepy")`, dirt decals), which satisfies
G1 embodiment without needing a task. That is the right fix — the word is taught by the
face, not by a card.

### 6.4 What is missing from today's 46

For S1 alone, 35 words are missing, all from Chapter 1 (which has no content yet at all):
greetings, family, pre-birth objects, feelings, body parts. **Chapter 1 is the single
largest content gap** and it is also the stage with the simplest interactions (tap, wave,
choose) — so it is the cheapest content to author once `greet` and `chooseOption`
(`INTERACTION_MATRIX.md` #24, #25) exist.

### 6.5 Schema additions (additive, backwards-compatible)

```json
{
  "wordId": "milk",
  "word": "milk",
  "category": "feeding",
  "partOfSpeech": "noun",
  "objectId": "milk",
  "thai": "นม",
  "exampleSentence": "I want some milk.",

  "stage": "baby",
  "introducedAtLevel": 6,
  "exposure": "active",
  "sayItEligible": true,
  "senseId": ""
}
```

| New key | Values | Purpose |
| --- | --- | --- |
| `stage` | `baby` \| `toddler` \| `preschool` \| `school` \| `olderChild` \| `teen` | drives review scheduling and the ceiling check |
| `introducedAtLevel` | int | first level that teaches it |
| `exposure` | `active` \| `passive` | passive = heard/understood only, never a Say It target |
| `sayItEligible` | bool | false for long/hard words at early stages |
| `senseId` | string | disambiguates `star` (toy) from `star` (shape) |

All five keys default safely if absent, so **the existing 46 records keep loading
unchanged**.

---

## 7. Thai hints — support, not crutch

`settings.thaiHints` already exists and every object and task already carries a
`thaiHint`. Policy:

| Rule | Detail |
| --- | --- |
| **On demand only** | Thai appears via long-press (`INTERACTION_MATRIX.md` #26) or after the 2nd gentle retry. It is never in the instruction bubble by default and never spoken before the English. |
| **English always first, always last** | Sequence is: English TTS → (optional Thai text) → English TTS again. The child's last input is always English. |
| **Text, not voice** | Thai is rendered as text + the object's picture. Thai TTS is **off**; a Thai voice-over would let the child ignore the English audio entirely. |
| **Never in Say It** | A `sayIt` task never shows Thai. Production is English-only or skipped. |
| **Never scored** | Using a hint does not reduce stars, is not shown to the child as a cost, and is not visible in the level summary. |
| **Fades by design** | Default `true` for S1–S2, default `false` from S3 onward (parent can re-enable any time in the existing parent settings screen). The child is not told the setting changed; the hints simply stop appearing as the stage advances. |
| **Per-word, not per-sentence** | Thai translates the *noun or action*, never the whole English sentence. Sentence-level translation teaches the child to wait for Thai. |
| **Parent-visible** | Hint usage is recorded locally for the parent screen only — as "words your child asked about", never as a failure list. |

**Judgement call:** the fade at S3 is the important part of this policy. The Bible does
not specify it; without a fade, `thaiHints` silently becomes the primary channel by
Chapter 4.

---

## 8. Honest scope assessment

| Item | Today | Full roadmap | Multiple |
| --- | --- | --- | --- |
| Words | 46 | 460 | 10× |
| Tasks | 43 | ~340 | 8× |
| Accepted phrase variants | 178 | ~1,690 | 9.5× |
| Spoken lines | 129 | ~1,080 | 8.4× |
| Objects (3D) | 28 | ~250 | 9× |
| Levels | 5 missions | 40 levels | 8× |

**Recommendation:** do not author beyond S1+S2 before the vertical slice proves out. S1
and S2 together are 120 words / ~95 tasks / ~400 phrase variants — roughly 2.5× today's
content, which is achievable. S3–S6 should be treated as a post-slice content pipeline
problem (with an authoring tool), not as hand-written JSON.

The 250-object art requirement is the real ceiling, not the English. Vocabulary should
**never** be authored ahead of the objects that embody it — that is precisely how a game
turns into flash cards.

---

## 9. Open questions / Bible ambiguities

1. **Star 2 vs Star 3.** §5.1 assigns star 2 to "an English listening/recognition task"
   and star 3 to "optional exploration/care"; §5.2's example makes star 3 the speech star.
   §4.1 above assumes Do It = star 1, Hear It = star 2, Say It **or** exploration = star 3.
   `LEVEL_MATRIX.md` must make the final call.
2. **Does the child "level up" with Little Buddy, or replay stages?** Free Life mode
   (§9) lets a child revisit Chapter 2 long after reaching S4. A 10-year-old replaying
   Milk Time should probably hear the S1 line, not an upgraded one. This roadmap assumes
   **vocabulary is bound to the level, not to the player's progress**. Confirm.
3. **No review/spaced-repetition mechanic is specified anywhere in the Bible.** Without
   one, 460 words will be met once and forgotten. Proposal (needs product sign-off): each
   level's `findIt` distractors are drawn preferentially from words introduced 2–5 levels
   earlier. This adds review with **zero** extra content and no quiz screen — it is the
   single highest-value addition to the learning design.
4. **Plurals and articles.** The ceiling table forbids meaningful plurals until S3
   (counting), yet existing content already says *"bananas"* and *"pajamas"*. Treated as
   lexical items at S1, not as grammar. Acceptable, but flagged.
5. **Locale.** `settings.speechLocale` is `en-US`. Vocabulary above is US-leaning
   (*rubbish* appears in S5 — should be *trash*). One dialect must be picked and applied
   consistently; recommend **US English** to match the STT locale.
6. **Pre-birth chapter actors.** Chapter 1's English is spoken by/about Mom and Dad, not
   Little Buddy. Confirm that S1 vocabulary may be taught by a character other than the
   one the child is caring for.

---

## 10. Deliberately out of scope here

Owned by the parallel design docs: level sequencing, star rules and unlock gating
(`STORY_MAP.md`, `LEVEL_MATRIX.md`); which interaction implements each activity
(`INTERACTION_MATRIX.md`); object models and room dressing (`ART_BIBLE_DRAFT.md`);
save-schema and content-loader changes (`ARCHITECTURE`); the vertical-slice word list
(`VERTICAL_SLICE_PLAN.md`, which should draw exclusively from S1+S2 above).
