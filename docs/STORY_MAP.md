# Little Buddy — Story Map

**Status:** design proposal, Phase A (Game Design Lock). Source of truth: `LITTLE_BUDDY_GAME_BIBLE.md` §3, §4, §5, §8, §20.
**Companion:** `docs/LEVEL_MATRIX.md` (per-level spec). Interaction, vocabulary, character-stage, art and architecture details are deliberately **out of scope here** — see §9.

**Proposal: 9 chapters · 39 levels · 6 reusable level templates.**

---

## 1. What already exists (verified against the build, 2026-09-17)

This map is written to *reuse* the shipped content system, not to replace it.

| Shipped today | Count | Role in this story map |
|---|---|---|
| Content categories (`feeding`, `dressing`, `bath`, `bedtime`, `play`) | 5 | Become level themes in Chapters 2–3 |
| Tasks (`game/content/*/tasks.json`) | 43 | Become **activities inside levels**, unchanged in schema |
| Vocabulary words | 46 | Covers Chapters 2–3 almost completely |
| Phrase variants | 270 | Feeds `targetPhrases` + speech acceptance |
| Missions (`missions.json`) | 7 | **Become Levels.** See §2 |
| Stickers | 16 | Stay as the global cosmetic reward ladder |
| Objects (`objects.json`) | 28 | Cover every Chapter 2–3 level; Chapters 4+ need new objects |
| Gameplay modes | 3 (`findIt`, `sayIt`, `followInstruction`) | The engine under 5 of the 6 level templates |
| Interactions | 6 (`tap`, `dragToMouth`, `dragToDress`, `dragToBath`, `dragToHug`, `dragToToyBox`) | Cover templates T1–T3 today |
| Character movement / navigation | **0** | **The single biggest new system.** See §5 |

Content is fully data-driven and engine-agnostic (`ContentLibrary`, `ContentValidator`, `TaskPicker`). Everything below is expressed as **data plus six templates**, so chapter expansion is authoring work, not engineering work.

---

## 2. Mission → Level: the big reuse opportunity

A mission today is:

```
{ missionId, title, thaiTitle, category, introPhrase, outroPhrase, unlockAtStars, taskIds }
```

That is **already a Level** in everything but name. A Level in the Bible (§4) is *a titled story beat containing 3–8 activities that awards up to 3 stars*. A mission is *a titled themed set containing 6–8 tasks*. The gap is four fields:

| Add to the mission schema | Why |
|---|---|
| `chapterId` | Group levels into the journey map (§4) |
| `storyBeat` | The one-line narrative reason this level exists |
| `template` | Which of the 6 reusable level templates runs it (§4 below) |
| `starRules: { star1, star2, star3 }` | Per-level 3-star model (Bible §5), replacing the flat `reward.stars` accumulation |
| `location` | Which room/scene to load |
| `requiredCharacterStage` | Which Little Buddy model family to instantiate |

**Decision: extend `missions.json` into `levels.json`; do not build a parallel system.** `unlockAtStars` stays valid and keeps driving cosmetics (§6). The existing `MissionRunner` becomes the level runner for template `sequenceRoutine` with almost no change — it already walks an ordered `taskIds` list with intro/outro phrases.

---

## 3. Star model change (Bible §5 vs. the build)

Today stars are a **single global integer** in the save profile, incremented per task. The Bible wants **up to 3 stars per level**.

**Decision: keep both, with different jobs.**

- `starsByLevel: { levelId: 0..3 }` — new. Drives progress, the journey map, "Great job! ★★☆", and the bonus sticker at 3/3.
- `totalStars` — *derived* (`sum(starsByLevel)`), not stored independently. Keeps the existing `unlockAtStars` thresholds on stickers/levels working unchanged, so all 16 stickers keep functioning on day one of the migration.

Hard rules, from Bible §5, that every level in `LEVEL_MATRIX.md` obeys:

1. Star 1 = complete the core activity. Always achievable by touch alone.
2. Star 2 = an English listening/recognition task (`findIt`-shaped).
3. Star 3 = optional exploration / care / cleanup.
4. **Never** require correct pronunciation for any star. Speech is enrichment.
5. **Never** subtract a star, never show a negative score, never show a red X.
6. 2/3 passes the level. 3/3 grants a bonus sticker.
7. A level is never *lost* — only "there is still a star waiting here".

---

## 4. The six level templates

**A level matrix that implies 39 bespoke implementations is a failed design.** Every level below is one of these six templates plus data. Two *modifiers* layer on top of any template.

| # | Template | What the child does | Built from | Levels using it |
|---|---|---|---|---|
| T1 | `fetchAndGive` | Find an object and bring it to Buddy or a target | `followInstruction` + `dragTo*` (ships today) | 9 |
| T2 | `chooseCorrectObject` | Hear a word, tap the right one among distractors | `findIt` (ships today) | 8 |
| T3 | `placeIt` | Drag objects into slots. Three data variants: `tidyUp` (many → one container), `dressUp` (garment → body slot), `arrangeScene` (object → named world slot) | `followInstruction` + `dragToToyBox`/`dragToDress` (ships today) | 8 |
| T4 | `sequenceRoutine` | An **ordered playlist** of T1/T2/T3/T5 steps with a visible checklist | `MissionRunner` (ships today) + checklist UI (new) | 9 |
| T5 | `walkTo` | Tap the floor; Buddy walks there and starts an activity | **Entirely new** (§5) | 3 |
| T6 | `storybookBeat` | Tap hotspots on an illustrated story card; TTS narrates | New but trivial; no character, no navigation, no room | 6 |

Modifiers — **not levels**, attachable to any step:

| Modifier | Effect |
|---|---|
| `sayAndDo` | Appends an optional "Can you say ___?" to a step. Uses shipped `sayIt`. **Never blocks.** Tap-the-word fallback always present. |
| `freePlay` | Turns the loaded room into a sandbox after the core activity (Bible §9). This is how most levels earn **star 3** without bespoke code. |

**T3 is deliberately one code path, not three.** `tidyUp`, `dressUp` and `arrangeScene` differ only in the slot set and the acceptance rule; forking them into three implementations would triple the maintenance for no child-visible gain.

Coverage check: 9 + 9 + 8 + 8 + 6 + 3 = 43 template slots across 39 levels (four levels compose two templates). **Six templates cover 100% of the arc.**

---

## 5. The one genuinely new system: movement

There is **no character movement or navigation in the build today** — no `CharacterBody3D`, no `NavigationAgent3D`, no path-finding, no locomotion animation, no activity anchor points. The baby is a procedural view that does not move.

Bible §6 and §12 require tap-to-walk, a face-target step, a stop radius, an Idle/Walk/Interact/Carry/Eat/Drink/Sit/Sleep/Celebrate state machine, and a forgiving drag-the-character mode for very young players.

**This is the largest single piece of new engineering in the whole plan, and it is the gate on Chapter 3 onward.** Chapters 1 and 2 are specified so that they need *zero* movement — every level there is T1/T2/T3/T6 on a static scene. That is intentional: it lets story and star systems ship before navigation exists, and it keeps navigation risk off the critical path for the first playable build.

Everything from **Level 11 (First Steps)** onward assumes movement exists. Level 11 is the tutorial for it and should be built first inside Phase B2.

---

## 6. Unlock and progression rules

**Decision: progression gates on *completion*, not on star count.** Children should never be locked out for playing imperfectly.

| Gate | Rule |
|---|---|
| Next level | Unlocks at **≥1 star** on the previous level |
| Next chapter | Unlocks when **every level in the current chapter has ≥1 star** |
| Bonus sticker | Granted at **3/3** on a level |
| Cosmetics (stickers, outfits, room decor) | Driven by **derived `totalStars`** via the existing `unlockAtStars` field |
| Rooms | Unlock by story beat, then stay permanently playable in Free Play (Bible §9) |
| Free Life mode | Unlocks after Level 39; the save is never closed (Bible §8, Ch.9) |

Replay value comes from stars still outstanding, randomised phrase variants (270 already authored), different object choices, sticker completion, outfits, and free play — not from failure/retry.

---

## 7. Chapters

Legend for **Phase**: `B1`/`B2` = vertical slice work (Bible §20 Phase B), `C` = art lock, `D1`/`D2` = story expansion, `F` = post-beta. Phase E is TestFlight and gates on B2+D1.

---

### Chapter 1 — Our Family Begins

| Field | Value |
|---|---|
| Chapter number | 1 |
| Levels | 1–5 |
| Little Buddy stage | **none → unborn → newborn** |
| Why the player cares | *Someone is coming.* The chapter's entire job is to make the arrival of a person the player has never met feel like something they are personally preparing for. The player never meets Buddy here — they build Buddy's room. |
| Story purpose | Establish the family, the home, and the player's role as helper *before* the caregiving loop starts |
| Rooms required | Park/cafe card, celebration card, Living Room, **Nursery**, birth transition card |
| Key interactions | tap hotspot, choose-one-of-three, drag object to named slot, place teddy/blanket/bottle, take a photo |
| English goal | Greeting and family nouns; single words and 2-word phrases. `hello, hi, family, happy, love, cake, flower, baby, home, welcome, bed, blanket, pillow, teddy, bottle, clean` |
| Star structure | ★ complete the beat · ★ find the object named aloud · ★ optional tidy/decorate |
| Major reward | **Little Buddy exists.** Nursery becomes a permanently playable room. First sticker (`heartSticker`). Chapter 2 unlocks. |
| Reusable systems | T6 `storybookBeat` (L1–L3, L5), T3 `arrangeScene` (L4), T2 `chooseCorrectObject` |
| Implementation phase | **D1** |

**Child-safety constraints (hard, Bible §3).** No sexual content. No childbirth depiction. No medical procedure, no hospital interior beyond a warm exterior or cozy room, no complications, no distress. Pregnancy is: a family photo, a gently growing belly, a nursery being prepared, an optional soft heartbeat sound, and the line "A baby is coming!" Birth is: a transition card, then parents smiling, then a baby wrapped in a blanket. Nothing between those two frames is shown or described. No blood, no pain, no crying-in-distress audio, no darkness.

**Judgement call: Chapter 1 is built as a storybook chapter, not as 3D rooms.** It needs two adult characters, a park, a wedding scene and a hospital — the most expensive, least reusable art in the entire game — for the *first thirty minutes a child ever plays*. Delivering L1/L2/L3/L5 as illustrated tap-the-hotspot cards (T6) gets the emotional arc for a fraction of the cost, and only L4 (nursery prep) needs a real playable room — which Chapter 2 needs anyway. Revisit after art lock.

**Known risk, stated plainly:** for these five levels there is no Little Buddy to care for, so the core verb of the game is absent. Mitigation: the player is caring for the *parents* and for the *room*, and L4/L5 hand over the baby directly. Keep Chapter 1 short (≈20 min total) and make it skippable from the journey map on replay.

---

### Chapter 2 — Baby Days

| Field | Value |
|---|---|
| Chapter number | 2 |
| Levels | 6–10 |
| Little Buddy stage | **newborn → baby** |
| Why the player cares | *Buddy needs me.* This is where the emotional contract is signed: Buddy expresses a need, the child meets it, Buddy is visibly happier. Every later chapter is a variation on this. |
| Story purpose | Teach the core loop (need → give → happy) and make the child feel competent |
| Rooms required | Nursery (**exists today**), Bathroom, Bedroom |
| Key interactions | drag-to-mouth, drag-to-bath, drag-to-hug, drag-to-toybox, tap-to-find, optional speak |
| English goal | Concrete nouns + one-word actions (Bible §10). `milk, water, apple, banana, spoon, bowl, soap, towel, toothbrush, cup, teddy, ball, block, star, blanket, pillow, lamp, hungry, sleepy, eat, drink, wash, clean, dry, play, good night, mama, dada, bye-bye` |
| Star structure | ★ complete the care activity · ★ find the object after hearing its word · ★ say it **or** tap the word (fallback always passes) |
| Major reward | Buddy's **first word**, then Buddy **grows into a toddler** — the strongest hook in the game. Toddler model + Chapter 3 unlock. |
| Reusable systems | T1, T2, T3(`tidyUp`), T4, `sayAndDo`. **No new gameplay code required.** |
| Implementation phase | **B1** |

**This chapter is nearly free.** The five existing missions `feedingTime`, `bathTime`, `bedtimeRoutine`, `playTime`, `sayItChallenge` map almost 1:1 onto Levels 6–10 using content that already ships and is already validated. Building Chapter 2 first proves the level shell, the per-level star model, the journey map and the save migration **without touching gameplay code at all** — which is exactly what should happen before the movement system is attempted.

---

### Chapter 3 — Toddler Adventures  ·  *"A Day With Little Buddy"* (the vertical slice)

| Field | Value |
|---|---|
| Chapter number | 3 |
| Levels | 11–15 |
| Little Buddy stage | **toddler** |
| Why the player cares | *Buddy can move now.* Buddy stops being a thing you hand objects to and becomes someone who walks across a room to you. The home opens from one room to five. |
| Story purpose | Turn the caregiving loop into a **world**; prove movement, rooms, animation, speech, stars and save all work together |
| Rooms required | Bedroom, Bathroom, Kitchen, Living Room, Nursery — the full Home Hub |
| Key interactions | **tap floor to walk**, drag Buddy (forgiving mode), tap object → walk → interact, dress, tidy, choose food |
| English goal | 2–4 word phrases (Bible §10). `walk, stop, go, come here, up, down, sit, in, on, under, put away, clean up, shirt, pants, shoes, hat, red, blue, yellow, wear` |
| Star structure | ★ finish the routine · ★ follow a spoken instruction ("Put the teddy **on** the bed") · ★ free-play/cleanup in the room |
| Major reward | **Free Play unlocked for the whole home.** First outfit choices. Preschool unlocks. |
| Reusable systems | **T5 `walkTo` (new)**, T4 `sequenceRoutine`, T1, T2, T3 all three variants, `freePlay` |
| Implementation phase | **B2** |

**Decision: Chapter 3 *is* the Bible's Phase B vertical slice.** The Bible's §20 slice sequence (wake → walk to bathroom → brush teeth → walk to bedroom → dress → walk to kitchen → breakfast → hear/say words → play → clean up → bedtime → summary) is exactly Levels 11–15 played back to back. Do not build a separate throwaway slice scene; build these five levels and chain them with an optional continuous "one day" framing. Target 20–30 min of varied play, which five 5-minute levels hits.

Build order inside B2: **L11 first** (it is the movement tutorial and the riskiest level in the game), then L12–L15 which are mostly existing content re-hosted in rooms.

---

### Chapter 4 — Preschool

| Field | Value |
|---|---|
| Chapter number | 4 |
| Levels | 16–20 |
| Little Buddy stage | **preschool child** |
| Why the player cares | *Buddy leaves home for the first time.* A small, safe separation with a real emotional question — will Buddy be okay without us? — answered warmly within one level. |
| Story purpose | Widen the world past the house; introduce peers; move English from objects to attributes (colour, shape, number) |
| Rooms required | Front door / Garden, Preschool Room (new), plus Home Hub |
| Key interactions | pack backpack, walk to school, greet teacher/friend, sort by colour, match shape, count objects, give/take turns |
| English goal | Attributes and quantities. `backpack, teacher, friend, red, blue, yellow, green, pink, circle, square, triangle, star, one…ten, give, take, please, thank you, my turn, your turn` |
| Star structure | ★ complete the class activity · ★ pick the right colour/shape/number when named · ★ help a friend / tidy the classroom |
| Major reward | A recurring **friend character**, the school-age model, and a classroom that joins the Free Play world |
| Reusable systems | T2 (heavily — colour/shape/number are pure `chooseCorrectObject` data), T3, T4, T5 |
| Implementation phase | **D1** |

Chapters 4's four content levels (Colors, Shapes, Numbers, Sharing) are the cheapest levels in the entire game: **one template (T2) and a data table.** If the templates are right, this whole chapter is authoring.

---

### Chapter 5 — School Days

| Field | Value |
|---|---|
| Chapter number | 5 |
| Levels | 21–25 |
| Little Buddy stage | **primary-school child** |
| Why the player cares | *Buddy has a life of their own now.* The child shifts from doing things **for** Buddy to helping Buddy do things **themselves** — the first real feeling of raising someone. |
| Story purpose | Routines, competence, school life; English becomes full simple instructions |
| Rooms required | Home Hub, Study Corner (new), Classroom, School Yard, symbolic journey (bus/car/walk) |
| Key interactions | multi-step morning routine, choose transport, turn pages, draw/colour, run/throw/catch mini-actions |
| English goal | Full simple instructions. `wake up, wash face, brush teeth, get dressed, breakfast, backpack, bus, school, book, page, read, letter, word, draw, colour, paper, pencil, run, jump, throw, catch` |
| Star structure | ★ finish the routine in order · ★ follow a 2-step spoken instruction · ★ optional extra (help a classmate, tidy desk) |
| Major reward | Study Corner unlocked; reading/art props enter Free Play; school outfit set |
| Reusable systems | T4 (dominant), T1, T2, T5 |
| Implementation phase | **D2** |

---

### Chapter 6 — Growing Skills

| Field | Value |
|---|---|
| Chapter number | 6 |
| Levels | 26–30 |
| Little Buddy stage | **older child** |
| Why the player cares | *Buddy starts helping you.* The care relationship reverses for the first time — Buddy makes the bed, cooks with you, has their own hobby. That reversal is the emotional payload of the whole game. |
| Story purpose | Competence, personality and choice; Buddy becomes a specific person, not a generic child |
| Rooms required | Home Hub, Kitchen (featured), Study Corner, Garden, hobby space (data-driven dressing of an existing room) |
| Key interactions | multi-step chores, cooking sequence (add/mix/serve), choose a hobby, invite a friend, a long multi-room task |
| English goal | Conversational instructions and helping language. `make the bed, clean the table, put away, mix, add, stir, bowl, spoon, fruit, help, together, idea, good job, can you…, let's…` |
| Star structure | ★ complete the task · ★ follow a multi-step spoken instruction · ★ optional exploration or a second hobby try |
| Major reward | **Hobby choice** (persisted as `optionalHobby`), hobby props, hobby outfit |
| Reusable systems | T4, T3, T1, T5 |
| Implementation phase | **D2** |

**Flagged as ambitious:** L28 (five hobby branches) and L30 (multi-room, movement + object-finding + instruction chain). See `LEVEL_MATRIX.md` for the reduced versions.

---

### Chapter 7 — Teen Journey

| Field | Value |
|---|---|
| Chapter number | 7 |
| Levels | 31–35 |
| Little Buddy stage | **teen** |
| Why the player cares | *Buddy is deciding things alone — do I still matter?* Answer: yes, as the person who helps them plan, remember and keep going. Keep it light and aspirational (Bible §7 tone), never moody or fraught. |
| Story purpose | Planning, responsibility, teamwork, dreaming ahead |
| Rooms required | Bedroom (teen dressing), Study Corner, a shared/team space |
| Key interactions | build a daily schedule, homework sequence, team task with a friend, checklist of responsibilities, pick dream themes |
| English goal | Conversational phrases and time language. `morning, afternoon, evening, today, tomorrow, homework, computer, question, answer, help, together, idea, good job, remember, check, prepare, I want to be a…` |
| Star structure | ★ complete the task · ★ answer a spoken question by choosing · ★ optional extra help/tidy |
| Major reward | Dream/career themes unlocked for Chapter 9; teen outfits |
| Reusable systems | T4, T2, T3, T1 |
| Implementation phase | **F** |

---

### Chapter 8 — Graduation

| Field | Value |
|---|---|
| Chapter number | 8 |
| Levels | 36–37 |
| Little Buddy stage | **teen → young adult** |
| Why the player cares | *This is the moment the care pays off.* Everything the child did since Level 1 is named and celebrated back to them. |
| Story purpose | Climax and validation |
| Rooms required | Study Corner, Graduation Hall / stage (new), family photo spot |
| Key interactions | assemble a final project from earlier chapters' objects, dress in cap and gown, walk the stage, family photo, clap |
| English goal | `"I did it!"`, `"Congratulations!"`, `"Thank you."`, `"I'm proud of you."`, `graduation cap, family, photo, proud` |
| Star structure | ★ finish the project / the ceremony · ★ recognise the congratulation phrases · ★ collect the family photo extras |
| Major reward | **Graduation sticker + trophy**; a memory montage assembled from the player's own stickers; Chapter 9 unlocks |
| Reusable systems | T4, T3(`dressUp`), T5, T6 |
| Implementation phase | **F** |

**Deliberate design note:** the montage should be built from the *player's actual* sticker/star data, not a canned video. That is a small data query and it is the single highest-emotion, lowest-cost feature in the game.

---

### Chapter 9 — My Future

| Field | Value |
|---|---|
| Chapter number | 9 |
| Levels | 38–39 |
| Little Buddy stage | **young adult** |
| Why the player cares | *Nothing ends.* The child gets to try any future for Buddy, change their mind, and keep playing forever. |
| Story purpose | Open-ended career exploration and a non-terminal ending (Bible §8: "Do not truly end the save") |
| Rooms required | One reconfigurable **career play set** dressed by data (10 themes), plus the Home Hub for the finale |
| Key interactions | choose a career, one small playful themed activity, celebrate, unlock Free Life |
| English goal | Career nouns + `"I want to be a…"`, `"What do you want to be?"` `doctor, teacher, engineer, artist, chef, scientist, firefighter, designer, programmer, veterinarian` |
| Star structure | ★ try one career · ★ recognise career words · ★ try a second career (explicitly encouraged, never penalised) |
| Major reward | **Free Life mode** — every chapter, room, outfit and level replayable; sticker book completion; career is changeable at any time |
| Reusable systems | T1, T2, T6 |
| Implementation phase | **F** |

**Decision: two levels, not ten.** The Bible implies ten career activities. Ten bespoke mini-games is a chapter-sized project for content a child will see once. **Level 38 is one template with ten data variants** (props swap, vocabulary swaps, the verb is the same "find and use the right tool"), and Level 39 is the finale. If careers later deserve more, they expand as data.

---

## 8. Phase summary — honest scope

| Phase | Chapters | Levels | New systems needed | Notes |
|---|---|---|---|---|
| **B1** | 2 | 6–10 (5) | Level shell, per-level stars, journey map, save migration | Uses **existing content and existing gameplay code**. Cheapest, ship first. |
| **B2** | 3 | 11–15 (5) | **Tap-to-walk + navigation + animation state machine + room loading** | The vertical slice. All project risk lives here. |
| **C** | — | — | — | Art lock (Bible §20/§14) — gates on B2 being *fun*, per the Bible |
| **D1** | 1, 4 | 1–5, 16–20 (10) | Storybook card player (T6), preschool room | Story front-end + cheapest content chapter |
| **D2** | 5, 6 | 21–30 (10) | Study corner, classroom, hobby data | Mostly authoring if templates hold |
| **E** | — | — | — | TestFlight beta (gates on B1+B2+D1 complete, Bible §19) |
| **F** | 7, 8, 9 | 31–39 (9) | Graduation hall, career play set, Free Life mode | Post-beta |

**Total: 9 chapters, 39 levels, ~6 new rooms beyond the Home Hub, 6 templates.**

---

## 9. Deliberately left to other documents

- **Gesture, hit-target, drag tolerance, failure-free feedback rules** → `docs/INTERACTION_MATRIX.md`
- **Full per-level word lists, Thai hints, phrase variants, difficulty curve** → `docs/VOCABULARY_ROADMAP.md`
- **Model families, proportions, rigs, which stages share a rig** → `docs/CHARACTER_AGE_STAGES.md`
- **Palette, silhouettes, prop style, triangle budgets** → `docs/ART_BIBLE_DRAFT.md`
- **Slice build order, task breakdown, acceptance criteria** → `docs/VERTICAL_SLICE_PLAN.md`
- **Keep/modify/replace/deprecate audit of every existing subsystem, save-schema migration** → architecture/migration doc

---

## 10. Contradictions and ambiguities found in the Game Bible

Stated rather than quietly resolved, per Phase A's purpose.

1. **2D vs 3D.** `CLAUDE.md` says "2D only, Compatibility renderer". The Bible §12/§16/§17 mandates `CharacterBody3D`, `NavigationAgent3D`, GLB models and triangle budgets. The **shipped build is 3D** (Mobile renderer, 18 GLB models, `baby_view_3d.gd`, one `DirectionalLight3D`). `CLAUDE.md` is stale from the original one-night MVP. **The Bible wins; `CLAUDE.md` needs updating by the owner.**
2. **"Mostly in and around the family home" (§7) vs the arc (§8).** §7 lists 7 rooms; §8 requires a park/cafe, a wedding venue, a hospital, a preschool, a classroom, a school yard, an art room, a graduation hall and ten career settings. These are not compatible scopes. This map resolves it by making non-home locations storybook cards or data-dressed reconfigurations of one set — but the owner should confirm.
3. **Star currency.** §5 defines 3 stars per level; the build uses one global star pool with `unlockAtStars` thresholds on stickers and missions. Resolved in §3 above (store per-level, derive the total), but it **is** a save-schema migration.
4. **Level size vs level length.** §4 says 3–8 activities and 4–10 minutes. Eight activities in four minutes is 30 s per activity including TTS, a speech attempt and an animation — not achievable. **Realistic figure: 3–5 activities per level**, which is what `LEVEL_MATRIX.md` uses. Levels with 6+ activities are marked as over-length there.
5. **Chapter length is uneven.** Chapters 1–7 have five levels each; Chapter 8 has two; Chapter 9 has none numbered. This map proposes 2 + 2 and says so, rather than padding.
6. **Chapter 1 has no playable Little Buddy.** §2 lists "unborn baby" as a character stage, but there is no character to care for, move or dress for the first five levels — the game's core verb is missing for the first ~20–30 minutes, which are also the most art-expensive. Flagged in Chapter 1 above; recommend keeping it short and skippable on replay.
7. **Sandbox vs levels.** §9 says every unlocked room stays playable and "no quiz popup required", but §4/§5 award stars only through levels. There is no stated rule for whether free play earns anything. This map's answer — free play is how **star 3** is earned — is an invention and should be confirmed.
8. **Animation requirements assume a rig that does not exist.** §13 lists 25 semantic actions; the current baby is a procedural, non-rigged, non-animated view built from primitives (`baby_view_3d.gd`), explicitly temporary. Every level from 11 onward assumes locomotion + at least 10 of those actions.
9. **Drag-to-move vs walk-to-move (§6).** Both are required, and they conflict at the level of feel ("do not literally teleport… use a short walk/snap transition"). Which one is the default for which age of player is unspecified. Recommendation for `INTERACTION_MATRIX.md`: tap-to-walk is the default; drag-Buddy is an accessibility setting in parent settings, not a per-scene choice.
10. **Career permanence.** §8 says the career choice is "not a permanent irreversible choice", while §18 persists `selectedCareer` as a single value. Needs to be a *last chosen* value plus a `triedCareers` list, or the child cannot revisit without feeling they overwrote something.
