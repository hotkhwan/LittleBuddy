# Little Buddy — Level Matrix

**Status:** design proposal, Phase A. Companion to `docs/STORY_MAP.md` (chapters, emotional arc, unlock rules, contradictions found).
**Scope:** 9 chapters · **39 levels** · **6 level templates**.

---

## How to read this document

### Templates, not bespoke levels

Every level is **one of six templates plus data**. The `coreGameplay` column names the template first, then the shipped content modes it runs on.

| Template | Data it needs | Code status |
|---|---|---|
| `fetchAndGive` | object id, target, prompt, instruction | **Ships today** (`followInstruction` + `dragTo*`) |
| `chooseCorrectObject` | correct object + 2–3 distractors, spoken word | **Ships today** (`findIt`) |
| `placeIt` — variants `tidyUp` / `dressUp` / `arrangeScene` | slot set + acceptance rule | **Ships today** (`dragToToyBox`, `dragToDress`); named world slots are new data, not new code |
| `sequenceRoutine` | ordered step list + checklist labels | `MissionRunner` ships today; **checklist UI is new** |
| `walkTo` | floor nav mesh, activity anchors, stop radius | **Entirely new — the project's biggest new system** |
| `storybookBeat` | card art, hotspots, narration lines | New, but trivial: no character, no room, no navigation |

Two **modifiers** attach to any step and are never levels in themselves:
`sayAndDo` (optional "Can you say ___?", shipped `sayIt`, tap-the-word fallback always passes) and
`freePlay` (post-activity sandbox; this is how most levels earn star 3).

**43 template slots across 39 levels. No level requires bespoke gameplay code.** Four levels compose two templates; that is composition of existing runners, not new implementation.

### Column conventions

- `requiredObjects` — plain ids exist in `game/content/objects.json` **today** (28 objects). A `+` prefix means **a new asset is required**.
- `requiredAnimations` — semantic action names per Bible §13 (`character.playAction("drink")`), never animation file names. `idle` is assumed everywhere and omitted.
- `targetPhrases` — representative only; the full set lives in `docs/VOCABULARY_ROADMAP.md`. 270 phrase variants already ship.
- `star1/2/3` — Bible §5. Star 1 is always achievable by touch alone. Star 2 is always listening/recognition. Star 3 is always optional. **No star anywhere in this document requires correct pronunciation.** Stars are never subtracted. 2/3 passes; 3/3 grants a bonus sticker.
- `activityCount` — 3–5 is the design target. See §"Scope flags" for why the Bible's "3–8" is not achievable in 4–10 minutes.
- `implementationPhase` — `B1`, `B2`, `C`, `D1`, `D2`, `F` as defined in `STORY_MAP.md` §8.

---

## Master index

| levelId | Chapter | Title | Template | Phase | Min |
|---|---|---|---|---|---|
| `hello` | 1 | Hello! | `storybookBeat` | D1 | 4 |
| `aSpecialDay` | 1 | A Special Day | `storybookBeat` + `placeIt` | D1 | 5 |
| `babyIsComing` | 1 | A Baby Is Coming | `storybookBeat` | D1 | 4 |
| `gettingReady` | 1 | Getting Ready | `placeIt:arrangeScene` | D1 | 6 |
| `welcomeLittleBuddy` | 1 | Welcome, Little Buddy! | `storybookBeat` | D1 | 4 |
| `milkTime` | 2 | Milk Time | `fetchAndGive` | B1 | 5 |
| `bathTime` | 2 | Bath Time | `sequenceRoutine` | B1 | 6 |
| `bedtime` | 2 | Bedtime | `sequenceRoutine` | B1 | 6 |
| `toysAndSmiles` | 2 | Toys & Smiles | `fetchAndGive` | B1 | 5 |
| `firstWords` | 2 | First Words | `chooseCorrectObject` | B1 | 5 |
| `firstSteps` | 3 | First Steps | `walkTo` | B2 | 6 |
| `breakfast` | 3 | Breakfast | `walkTo` + `chooseCorrectObject` | B2 | 6 |
| `gettingDressed` | 3 | Getting Dressed | `placeIt:dressUp` | B2 | 6 |
| `cleanUp` | 3 | Clean Up | `placeIt:tidyUp` | B2 | 5 |
| `playWithMe` | 3 | Play With Me | `fetchAndGive` | B2 | 6 |
| `myFirstDay` | 4 | My First Day | `sequenceRoutine` | D1 | 8 |
| `colors` | 4 | Colors | `chooseCorrectObject` | D1 | 5 |
| `shapes` | 4 | Shapes | `chooseCorrectObject` | D1 | 5 |
| `numbers` | 4 | Numbers | `chooseCorrectObject` | D1 | 6 |
| `sharing` | 4 | Sharing | `fetchAndGive` | D1 | 6 |
| `morningRoutine` | 5 | Morning Routine | `sequenceRoutine` | D2 | 9 |
| `goingToSchool` | 5 | Going to School | `walkTo` + `chooseCorrectObject` | D2 | 6 |
| `readingTime` | 5 | Reading Time | `chooseCorrectObject` | D2 | 6 |
| `artClass` | 5 | Art Class | `placeIt:arrangeScene` | D2 | 6 |
| `sportsDay` | 5 | Sports Day | `fetchAndGive` | D2 | 6 |
| `helpAtHome` | 6 | Help at Home | `sequenceRoutine` | D2 | 8 |
| `cookingTogether` | 6 | Cooking Together | `sequenceRoutine` | D2 | 8 |
| `myHobby` | 6 | My Hobby | `fetchAndGive` | D2 | 6 |
| `friends` | 6 | Friends | `fetchAndGive` | D2 | 6 |
| `myBigProject` | 6 | My Big Project | `sequenceRoutine` | D2 | 10 |
| `mySchedule` | 7 | My Schedule | `placeIt:arrangeScene` | F | 6 |
| `studyTime` | 7 | Study Time | `sequenceRoutine` | F | 7 |
| `teamwork` | 7 | Teamwork | `fetchAndGive` | F | 6 |
| `responsibility` | 7 | Responsibility | `placeIt:tidyUp` | F | 6 |
| `myDream` | 7 | My Dream | `chooseCorrectObject` | F | 5 |
| `finalProject` | 8 | Final Project | `sequenceRoutine` | F | 10 |
| `graduationDay` | 8 | Graduation Day | `placeIt:dressUp` + `storybookBeat` | F | 7 |
| `tryingJobs` | 9 | Trying a Job | `fetchAndGive` | F | 6 |
| `aNewBeginning` | 9 | A New Beginning | `storybookBeat` | F | 5 |

**Template usage:** `fetchAndGive` ×9 · `sequenceRoutine` ×9 · `placeIt` ×8 · `chooseCorrectObject` ×8 · `storybookBeat` ×6 · `walkTo` ×3 — 43 slots across 39 levels (four levels compose two templates).
**Total estimated first-play time: 238 min ≈ 4 h** (excluding free play and replays).

---

## Chapter 1 — Our Family Begins  ·  Phase D1

**Child-safety constraint applies to every level here (Bible §3):** no sexual content, no childbirth depiction, no medical procedure, no scary hospital imagery, no complications, no distress audio. Pregnancy = growing belly, nursery preparation, optional soft heartbeat, "A baby is coming!". Birth = transition card → parents smiling → baby in a blanket. Nothing between those frames is shown.

| chapterId | levelId | title | storyBeat | location | requiredCharacterStage | activityCount | coreGameplay | targetVocabulary | targetPhrases | requiredAnimations | requiredObjects | star1 | star2 | star3 | unlocks | estimatedPlayMinutes | implementationPhase |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ch1 | `hello` | Hello! | Mom and Dad meet in a park café and become friends | Park/café card | none | 3 | `storybookBeat` + `chooseCorrectObject`; `sayAndDo` | hello, hi, friend, name | "Hello!" / "Nice to meet you." / "My name is…" | wave, happy | `+momCard`, `+dadCard`, cup, `+flowerBench` | Tap both parents so they greet each other | Tap the object named aloud (cup / flower / book) | Tap "Hello" back **or** say it — either passes | `aSpecialDay`, `heartSticker` | 4 | D1 |
| ch1 | `aSpecialDay` | A Special Day | The family celebrates becoming a family | Celebration card | none | 4 | `storybookBeat` + `placeIt:arrangeScene` | family, happy, love, cake, flower, together | "We are a family." / "Happy day!" | clap, happy, excited | `+cake`, `+flowers`, `+photoFrame`, `+tableSetting` | Place cake + flowers on the table | Find the item named aloud | Take the family photo (optional extra) | `babyIsComing` | 5 | D1 |
| ch1 | `babyIsComing` | A Baby Is Coming | Parents share the news; a gently growing belly, nothing more | Living Room | unborn | 3 | `storybookBeat` + `chooseCorrectObject` | baby, family, small, happy, heart, home | "A baby is coming!" / "We are so happy." | happy, surprised, hug | `+babyClothes`, blanket, teddy, `+heartIcon` | Choose baby clothes and a blanket | Find the item named aloud | Place the teddy where the baby will sleep | `gettingReady` | 4 | D1 |
| ch1 | `gettingReady` | Getting Ready | The family prepares the nursery for the baby | **Nursery** (exists today) | unborn | 5 | `placeIt:arrangeScene`; `freePlay` | bed, blanket, pillow, teddy, bottle, clean | "Let's get the room ready." / "Put the blanket on the bed." | pickUp, hold, give, carry | blanket, pillow, teddy, milk, toyBox, lamp, `+crib` | Put blanket, pillow and teddy in place | Place the item named aloud in the right spot | Tidy the rest of the nursery (free play) | `welcomeLittleBuddy` | 6 | D1 |
| ch1 | `welcomeLittleBuddy` | Welcome, Little Buddy! | Transition card → parents smiling → baby in a blanket | Transition card → Nursery | **newborn** | 3 | `storybookBeat` + `chooseCorrectObject` | baby, welcome, hello, sleep, smile | "Welcome, Little Buddy!" / "Hello, baby!" | sleep, happy, hug | blanket, `+babyBlanketColours` | Choose a blanket colour and settle the baby | Find the blanket colour named aloud | Say **or** tap "Hello, baby!" | **Chapter 2**, Nursery in Free Play | 4 | D1 |

---

## Chapter 2 — Baby Days  ·  Phase B1  *(built from content that already ships)*

Every level below maps onto an existing mission and existing tasks. **No new gameplay code.** The only new work is the level shell, per-level stars, and the journey map.

| chapterId | levelId | title | storyBeat | location | requiredCharacterStage | activityCount | coreGameplay | targetVocabulary | targetPhrases | requiredAnimations | requiredObjects | star1 | star2 | star3 | unlocks | estimatedPlayMinutes | implementationPhase |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ch2 | `milkTime` | Milk Time | Buddy is hungry for the first time and the player answers | Nursery | newborn | 4 | `fetchAndGive` (`followInstruction`+`dragToMouth`); `sayAndDo`. **Reuses mission `feedingTime`** | milk, water, apple, banana, hungry, thirsty, eat, drink | "I'm hungry." / "Can I have some milk?" / "Thank you!" | drink, eat, hungry, happy | milk, water, apple, banana, bowl, spoon | Feed Little Buddy | Find the milk after hearing "milk" | Say "milk" **or** tap the word — either passes | `bathTime`, `milkSticker` | 5 | B1 |
| ch2 | `bathTime` | Bath Time | Buddy gets messy and the player makes it fun, not a chore | Bathroom | baby | 5 | `sequenceRoutine` over `fetchAndGive` steps. **Reuses mission `bathTime`** | soap, towel, toothbrush, cup, bath, wash, clean, wet, dry, teeth | "Splash! Let's take a bath." / "Wash your hands." / "I am clean and dry!" | washHands, brushTeeth, happy, excited | soap, towel, toothbrush, cup, bathToy | Wash and dry Little Buddy | Find the towel after hearing "towel" | Give the bath toy / say "toothbrush" | `bedtime`, `soapSticker`, `towelSticker` | 6 | B1 |
| ch2 | `bedtime` | Bedtime | The day ends softly; the first repeatable comfort ritual | Bedroom | baby | 5 | `sequenceRoutine` over `fetchAndGive` + `placeIt`. **Reuses mission `bedtimeRoutine`** | bed, blanket, pillow, pajamas, sleepy, good night, night, moon, lamp | "I am sleepy." / "Good night." / "See you tomorrow!" | sleepy, sleep, hold, hug | pajamas, blanket, pillow, teddy, lamp | Put Buddy to bed | Find the blanket after hearing "blanket" | Turn off the lamp / say "good night" | `toysAndSmiles`, `pillowSticker`, `moonSticker` | 6 | B1 |
| ch2 | `toysAndSmiles` | Toys & Smiles | Care becomes play; Buddy laughs for the first time | Nursery | baby | 4 | `fetchAndGive` + `placeIt:tidyUp`; `freePlay`. **Reuses mission `playTime`** | teddy, ball, block, star, play, toy box | "Let's play!" / "Give me the ball." / "That was fun!" | hug, pickUp, give, clap, excited | teddy, ball, blocks, starToy, toyBox | Play three toy activities | Find the ball after hearing "ball" | Tidy the toy box (free play) | `firstWords`, `teddySticker`, `ballSticker` | 5 | B1 |
| ch2 | `firstWords` | First Words | Buddy says a word back — the chapter's emotional payoff | Nursery | baby → **toddler** | 4 | `chooseCorrectObject` + `sayAndDo`. **Reuses mission `sayItChallenge`** | mama, dada, milk, teddy, hello, bye-bye | "Can you say milk?" / "Mama!" / "Bye-bye!" | wave, nod, clap, excited, celebrate | milk, teddy | Hear and match all the words by tapping | Pick the right object for each word spoken | Say any word aloud **or** tap it | **Chapter 3**, toddler model, bonus sticker | 5 | B1 |

---

## Chapter 3 — Toddler Adventures  ·  Phase B2  ·  *"A Day With Little Buddy"* — the vertical slice

**All project risk lives here.** `firstSteps` must be built before the other four: it is the tap-to-walk tutorial and the only level in the game that is entirely new engineering.

| chapterId | levelId | title | storyBeat | location | requiredCharacterStage | activityCount | coreGameplay | targetVocabulary | targetPhrases | requiredAnimations | requiredObjects | star1 | star2 | star3 | unlocks | estimatedPlayMinutes | implementationPhase |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ch3 | `firstSteps` | First Steps | Buddy walks for the first time — and walks to *you* | Living Room + Kitchen doorway | toddler | 4 | **`walkTo` (new system)**; `sayAndDo` | walk, stop, go, come here, up, down | "Come here!" / "Let's walk to the kitchen." / "You did it!" | **walk**, stand, sit, wave, excited, celebrate | teddy, ball, `+sofa`, `+kitchenDoor` | Walk to Mom, a toy, and the kitchen | Walk to the place named aloud | Walk somewhere the game did not ask (free exploration) | `breakfast`, Free Play (Living Room) | 6 | B2 |
| ch3 | `breakfast` | Breakfast | Buddy sits at the table and chooses their own food | Kitchen | toddler | 4 | `walkTo` → `chooseCorrectObject` → `fetchAndGive` | apple, banana, milk, water, spoon, bowl, eat, drink, sit | "I'm hungry." / "Sit at the table." / "Which one do you want?" | walk, sit, eat, drink, hold | apple, banana, milk, water, spoon, bowl, `+diningTable`, `+chair` | Walk to the table and eat breakfast | Choose the food named aloud | Try a second food / say a food word | `gettingDressed` | 6 | B2 |
| ch3 | `gettingDressed` | Getting Dressed | Buddy wants to dress themselves; the player helps | Bedroom | toddler | 5 | `placeIt:dressUp`. **Reuses mission `morningRoutine` tasks** | shirt, pants, shoes, hat, wear, red, blue, yellow | "Put on your shoes." / "I like the blue shirt!" | pickUp, hold, stand, happy | redShirt, blueShirt, yellowShirt, pants, shoes, hat | Dress Little Buddy completely | Put on the garment/colour named aloud | Try a different outfit combination (free play) | `cleanUp`, outfit slots, `shirtSticker`, `shoesSticker` | 6 | B2 |
| ch3 | `cleanUp` | Clean Up | Buddy learns that the fun ends tidily — no scolding, ever | Living Room | toddler | 4 | `placeIt:tidyUp` | clean up, put away, in, on, under, toy box | "Put the blocks **in** the box." / "Put the teddy **on** the shelf." | pickUp, carry, give, clap | blocks, teddy, ball, toyBox, `+shelf`, `+basket` | Put every toy away | Follow the preposition instruction spoken aloud | Find the toy hidden **under** something | `playWithMe` | 5 | B2 |
| ch3 | `playWithMe` | Play With Me | Buddy asks the player to play — the relationship becomes mutual | Living Room | toddler | 4 | `fetchAndGive` + `freePlay`. **Reuses mission `playTime`** | ball, teddy, block, star, circle, square, play, throw | "Play with me!" / "Throw the ball!" / "Again!" | throw, catch, hug, clap, excited | ball, teddy, blocks, starToy, circleToy, squareToy | Play three games with Buddy | Bring the toy named aloud | Free play in the room for a while | **Chapter 4**, Free Play (whole home) | 6 | B2 |

---

## Chapter 4 — Preschool  ·  Phase D1

The cheapest content chapter in the game: `colors`, `shapes`, `numbers` are **one template and a data table**.

| chapterId | levelId | title | storyBeat | location | requiredCharacterStage | activityCount | coreGameplay | targetVocabulary | targetPhrases | requiredAnimations | requiredObjects | star1 | star2 | star3 | unlocks | estimatedPlayMinutes | implementationPhase |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ch4 | `myFirstDay` | My First Day | Buddy's first time away from home; a small, safe separation | Home → Preschool Room | preschool | 5 | `sequenceRoutine` (pack → walk → greet) | backpack, shoes, teacher, friend, hello, goodbye | "Hello, teacher!" / "Bye-bye, Mom!" / "See you later!" | walk, wave, hug, nod, happy | shoes, hat, `+backpack`, `+teacherChar`, `+friendChar`, `+classroomDesk` | Pack the bag, get to school, greet the teacher | Pack the item named aloud | Greet the new friend as well | `colors`, friend character | 8 | D1 |
| ch4 | `colors` | Colors | First lesson: the world has names for how things look | Preschool Room | preschool | 4 | `chooseCorrectObject`; `sayAndDo`. **Reuses mission `colorsAndShapes`** | red, blue, yellow, green, pink | "Find something red." / "What colour is this?" | point, nod, clap, happy | redShirt, blueShirt, yellowShirt, apple, banana, `+greenObject`, `+pinkObject` | Match every colour | Tap the colour named aloud | Say a colour **or** find one extra | `shapes`, colour stickers | 5 | D1 |
| ch4 | `shapes` | Shapes | Buddy notices shapes everywhere | Preschool Room | preschool | 4 | `chooseCorrectObject`. **Reuses mission `colorsAndShapes`** | circle, square, triangle, star | "Find the circle." / "This is a star!" | point, clap, happy | circleToy, squareToy, starToy, `+triangleToy` | Match every shape | Tap the shape named aloud | Find a shape hidden in the room | `numbers`, `starSticker` | 5 | D1 |
| ch4 | `numbers` | Numbers | Counting turns into a game with the friend character | Preschool Room | preschool | 4 | `chooseCorrectObject` (count variant) | one…ten, count, how many, more | "How many apples?" / "Let's count!" / "One, two, three…" | point, nod, clap, excited | apple, banana, blocks, ball, `+numberCards` | Count each set correctly | Tap the number named aloud | Count a set nobody asked about | `sharing` | 6 | D1 |
| ch4 | `sharing` | Sharing | Buddy gives a toy away and feels good about it | Preschool Room | preschool | 4 | `fetchAndGive` (target = friend, not Buddy) | give, take, please, thank you, my turn, your turn | "Please." / "Thank you!" / "Your turn!" | give, hold, nod, clap, happy | teddy, ball, blocks, `+friendChar` | Share three toys with the friend | Give the toy named aloud | Offer an extra toy unprompted | **Chapter 5**, school-age model | 6 | D1 |

---

## Chapter 5 — School Days  ·  Phase D2

| chapterId | levelId | title | storyBeat | location | requiredCharacterStage | activityCount | coreGameplay | targetVocabulary | targetPhrases | requiredAnimations | requiredObjects | star1 | star2 | star3 | unlocks | estimatedPlayMinutes | implementationPhase |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ch5 | `morningRoutine` | Morning Routine | Buddy gets themselves ready — the player only prompts | Bedroom → Bathroom → Kitchen | primaryChild | 5 | `sequenceRoutine` + `walkTo` steps. **Reuses mission `morningRoutine`** | wake up, wash face, brush teeth, get dressed, breakfast, backpack | "Wake up!" / "Brush your teeth." / "Don't forget your backpack." | wake, walk, washHands, brushTeeth, eat, hold | toothbrush, towel, cup, redShirt, pants, shoes, milk, `+backpack` | Finish the whole routine in order | Do the step named aloud | Make the bed / extra tidy step | `goingToSchool` | 9 | D2 |
| ch5 | `goingToSchool` | Going to School | The journey out; the world is bigger than the house | Front yard → symbolic route → School | primaryChild | 4 | `walkTo` + `chooseCorrectObject` | bus, car, walk, school, teacher, classroom, street | "Let's go to school." / "How do we get there?" | walk, wave, sit, happy | `+bus`, `+car`, `+schoolExterior`, `+classroomDesk` | Get Buddy to the classroom | Choose the transport named aloud | Greet someone on the way | `readingTime`, School in Free Play | 6 | D2 |
| ch5 | `readingTime` | Reading Time | Buddy reads a word for the first time — an echo of "First Words" | Classroom / Study Corner | primaryChild | 4 | `chooseCorrectObject` (word-matching variant) | book, page, read, letter, word | "Find the letter B." / "Can you read this word?" | sit, read, point, nod, happy | `+book`, `+letterCards`, `+wordCards` | Match every word/picture pair | Tap the letter or word spoken aloud | Read one extra page (free play) | `artClass`, Study Corner | 6 | D2 |
| ch5 | `artClass` | Art Class | Buddy makes something and shows it to you | Art corner (dressed classroom) | primaryChild | 4 | `placeIt:arrangeScene` (drop colours onto a canvas) | draw, colour, paper, pencil, paint, picture | "Let's draw!" / "Colour it blue." / "I made this for you!" | draw, hold, clap, excited | `+pencil`, `+paper`, `+paintSet`, `+easel` | Finish the picture | Use the colour/tool named aloud | Make a second picture and hang it in the bedroom | `sportsDay` | 6 | D2 |
| ch5 | `sportsDay` | Sports Day | Buddy competes, and the player cheers — nobody loses | School yard | primaryChild | 4 | `fetchAndGive` + action mini-steps | run, jump, ball, throw, catch, fast, win | "Run!" / "Throw the ball!" / "Good job!" | run, jump, throw, catch, clap, celebrate | ball, `+cone`, `+ribbon`, `+friendChar` | Complete the three events | Do the action named aloud | Cheer for the friend character | **Chapter 6**, `ballSticker` variant | 6 | D2 |

---

## Chapter 6 — Growing Skills  ·  Phase D2

The chapter where the care relationship reverses: Buddy starts helping the player.

| chapterId | levelId | title | storyBeat | location | requiredCharacterStage | activityCount | coreGameplay | targetVocabulary | targetPhrases | requiredAnimations | requiredObjects | star1 | star2 | star3 | unlocks | estimatedPlayMinutes | implementationPhase |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ch6 | `helpAtHome` | Help at Home | Buddy offers to help without being asked | Bedroom + Living Room | olderChild | 5 | `sequenceRoutine` over `placeIt` steps | make the bed, clean the table, put away, tidy, help | "Can I help?" / "Let's make the bed." / "Thank you for helping!" | pickUp, carry, give, stand, happy | blanket, pillow, `+plate`, `+cloth`, toyBox, `+shelf`, `+book` | Finish all three chores | Do the chore named aloud | Tidy a room nobody asked about | `cookingTogether` | 8 | D2 |
| ch6 | `cookingTogether` | Cooking Together | The two of you make something together | Kitchen | olderChild | 5 | `sequenceRoutine` (ordered recipe steps) | mix, add, stir, cut, bowl, spoon, fruit, plate | "Add the banana." / "Now mix it!" / "It's ready!" | hold, give, eat, clap, excited | apple, banana, bowl, spoon, cup, `+plate`, `+mixingBowl` | Finish the recipe in order | Add the ingredient named aloud | Serve it to a parent / make a second bowl | `myHobby` | 8 | D2 |
| ch6 | `myHobby` | My Hobby | Buddy discovers something that is *theirs* | Data-dressed room (5 themes) | olderChild | 3 | `fetchAndGive` with 5 data variants (music/drawing/sports/science/building) — **one template, five data sets** | music, draw, sport, science, build, practise, try | "What do you like?" / "Let's try it!" / "I like this!" | hold, give, clap, excited, nod | ball, blocks, `+instrument`, `+pencil`, `+scienceKit` | Try one hobby | Pick the tool named aloud | Try a second hobby (explicitly encouraged) | `friends`, `optionalHobby` saved, hobby outfit | 6 | D2 |
| ch6 | `friends` | Friends | Buddy invites a friend over; the home fills up | Living Room | olderChild | 4 | `fetchAndGive` (target = friend) + `freePlay` | invite, together, share, help, idea, good job | "Do you want to play?" / "Let's do it together!" | wave, give, hug, clap, happy | teddy, ball, blocks, `+friendChar`, `+snackPlate` | Host the friend through three activities | Give the friend the thing named aloud | Offer a snack / extra shared activity | `myBigProject` | 6 | D2 |
| ch6 | `myBigProject` | My Big Project | Buddy takes on something too big to do alone | Bedroom → Living Room → Kitchen | olderChild | 5 | `sequenceRoutine` chaining `walkTo` + `fetchAndGive` + `placeIt` across rooms | find, bring, build, first, next, last, finished | "First, find the box." / "Now bring it here." / "We finished it!" | walk, carry, pickUp, give, clap, celebrate | blocks, toyBox, `+tape`, `+paper`, `+paintSet` | Complete the multi-room project | Follow a 2-step spoken instruction | Decorate the finished project | **Chapter 7**, older-child → teen model | 10 | D2 |

---

## Chapter 7 — Teen Journey  ·  Phase F

Tone: light and aspirational (Bible §7). No moodiness, no conflict, no failure.

| chapterId | levelId | title | storyBeat | location | requiredCharacterStage | activityCount | coreGameplay | targetVocabulary | targetPhrases | requiredAnimations | requiredObjects | star1 | star2 | star3 | unlocks | estimatedPlayMinutes | implementationPhase |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ch7 | `mySchedule` | My Schedule | Buddy plans their own day for the first time | Bedroom | teen | 4 | `placeIt:arrangeScene` (drag activity cards onto a day board) | morning, afternoon, evening, today, tomorrow, first, then | "What do we do in the morning?" / "See you tomorrow." | sit, point, nod, happy | `+dayBoard`, `+activityCards`, `+clock` | Fill the day board | Place the card for the time named aloud | Plan tomorrow as well | `studyTime` | 6 | F |
| ch7 | `studyTime` | Study Time | Buddy works at something hard and finishes it | Study Corner | teen | 4 | `sequenceRoutine` (question → choose answer → next) | homework, computer, book, question, answer, try again | "What's the answer?" / "Good thinking!" / "Let's try again." | sit, read, write, nod, clap | `+desk`, `+computer`, `+book`, `+notebook` | Finish the homework set | Answer the spoken question by choosing | Do one optional extra question | `teamwork` | 7 | F |
| ch7 | `teamwork` | Teamwork | Buddy leads a group and shares credit | Shared/team space | teen | 4 | `fetchAndGive` (multi-target: friends) | help, together, idea, good job, team, plan | "Let's work together." / "Good idea!" / "Good job, team!" | give, wave, clap, nod, excited | `+friendChar`, `+teamProps`, blocks | Finish the team task | Hand the item to the person named aloud | Thank each teammate | `responsibility` | 6 | F |
| ch7 | `responsibility` | Responsibility | Buddy remembers something without being reminded | Home Hub | teen | 4 | `placeIt:tidyUp` + checklist | clean, prepare, check, remember, ready, forget | "Did you remember?" / "Everything is ready!" | pickUp, carry, nod, happy | `+backpack`, `+keys`, toothbrush, `+lunchBox` | Complete the whole checklist | Pack the item named aloud | Notice and fix one thing nobody mentioned | `myDream` | 6 | F |
| ch7 | `myDream` | My Dream | Buddy says out loud who they want to become | Bedroom | teen | 3 | `chooseCorrectObject` + `sayAndDo` | dream, want, become, doctor, teacher, artist, engineer | "I want to be a…" / "What do you want to be?" | sit, point, nod, excited | `+dreamCards`, `+careerProps` | Choose a dream theme | Pick the career named aloud | Look at every career before choosing | **Chapter 8**, Ch.9 career themes | 5 | F |

---

## Chapter 8 — Graduation  ·  Phase F

| chapterId | levelId | title | storyBeat | location | requiredCharacterStage | activityCount | coreGameplay | targetVocabulary | targetPhrases | requiredAnimations | requiredObjects | star1 | star2 | star3 | unlocks | estimatedPlayMinutes | implementationPhase |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ch8 | `finalProject` | Final Project | Buddy builds something using skills from every earlier chapter | Study Corner + Home Hub | teen → youngAdult | 5 | `sequenceRoutine` chaining all templates; props pulled from earlier chapters | plan, build, finish, proud, almost, done | "I planned it myself." / "Almost finished!" / "I did it!" | walk, carry, write, draw, clap, celebrate | blocks, `+paintSet`, `+computer`, `+notebook`, `+projectBoard` | Complete the final project | Follow the multi-step spoken instruction | Add a personal touch from the player's own hobby choice | `graduationDay` | 10 | F |
| ch8 | `graduationDay` | Graduation Day | The player's whole journey is named and celebrated back to them | Graduation Hall | youngAdult | 4 | `placeIt:dressUp` + `storybookBeat`; montage built from the player's **own** sticker/star data | graduation cap, family, photo, proud, congratulations, thank you | "Congratulations!" / "I'm proud of you." / "Thank you." / "I did it!" | dressUp, walk, wave, clap, celebrate, hug | `+cap`, `+gown`, `+certificate`, `+stage`, `+photoFrame` | Dress Buddy and walk the stage | Recognise the congratulation phrases | Collect every family-photo extra | **Chapter 9**, graduation sticker + trophy | 7 | F |

---

## Chapter 9 — My Future  ·  Phase F

| chapterId | levelId | title | storyBeat | location | requiredCharacterStage | activityCount | coreGameplay | targetVocabulary | targetPhrases | requiredAnimations | requiredObjects | star1 | star2 | star3 | unlocks | estimatedPlayMinutes | implementationPhase |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ch9 | `tryingJobs` | Trying a Job | Buddy tries a career for a day — and can try another tomorrow | Career play set (**one set, 10 data dressings**) | youngAdult | 3 | `fetchAndGive` with 10 data variants: doctor, teacher, engineer, artist, chef, scientist, firefighter, designer, programmer, veterinarian | doctor, teacher, engineer, artist, chef, scientist, firefighter, designer, programmer, vet, tool, help | "I want to be a chef!" / "Pass me the spoon." / "I helped someone today." | hold, give, walk, clap, excited | bowl, spoon, `+careerToolSet` (10 small props), `+careerBackdrop` | Complete one career activity | Pick the tool named aloud | Try a second career — never penalised, career is always changeable | `aNewBeginning`, career sticker | 6 | F |
| ch9 | `aNewBeginning` | A New Beginning | "You helped Little Buddy grow up." Then: "Every ending is a new beginning." | Home Hub | youngAdult | 3 | `storybookBeat` + montage; **the save is never closed** | thank you, together, grow, begin, again, always | "You helped Little Buddy grow up." / "Every ending is a new beginning." | hug, wave, clap, celebrate | `+photoFrame`, `+memoryCards` | Watch the ending and hug Buddy | Recognise the closing phrases | Open the completed sticker book | **Free Life mode** — all chapters, rooms, outfits replayable | 5 | F |

---

## Scope flags

Honest assessment. Nothing here is hidden behind optimistic estimates.

### Too thin as specified in the Bible

| Level | Problem | Proposed fix (already reflected above) |
|---|---|---|
| `babyIsComing` | Three tap-choices with no character present is under 3 minutes and has no verb | Bundled with the nursery preparation beat; kept short (4 min) and framed as a storybook card rather than a room |
| `hello` | Two taps and a wave is not a level | Added an object-choice activity and a `sayAndDo` greeting; still the shortest level in the game, deliberately |
| `myDream` | "Choose interests/career themes" is a menu, not gameplay | Made it a `chooseCorrectObject` round over career words so it teaches something; still only 5 min |

### Too ambitious as specified in the Bible

| Level | Problem | Proposed fix (already reflected above) |
|---|---|---|
| `myHobby` | Five hobby branches implies five mini-games | **One template, five data sets.** The verb is identical; only props and vocabulary change. |
| `myBigProject` | "Multi-step activity requiring movement, object finding and English instructions" across rooms is the most complex level in the game | Kept, but explicitly scheduled in **D2 after** movement is proven in B2, and capped at 5 activities / 10 min |
| `tryingJobs` | Ten careers × one activity each = a chapter-sized build for content seen once | **Two levels, not ten.** One template with ten data dressings. |
| `finalProject` | "Complete a larger activity" is undefined and unbounded | Defined as a 5-step `sequenceRoutine` reusing existing props, capped at 10 min |
| `morningRoutine` | 6 ordered steps across 3 rooms is the longest routine in the game | Kept at 9 min; if playtesting shows fatigue, split at "get dressed" |

### Structural notes

1. **The Bible's "3–8 activities in 4–10 minutes" is not achievable.** Eight activities in four minutes is ~30 s each including TTS, a speech attempt, an animation and a reward beat. Every level here targets **3–5 activities**; the longest (`myBigProject`, `finalProject`) are 5 activities in 10 minutes.
2. **`firstSteps` is the highest-risk level in the entire game** and is the only one that is pure new engineering. If tap-to-walk slips, Chapters 3–9 all slip. Chapters 1 and 2 are deliberately specified to need **zero** movement so they can ship regardless.
3. **New object cost by phase:** B1 = **0 new objects** (everything ships today). B2 = 6. D1 = ~14. D2 = ~20. F = ~25. Chapter 2 is genuinely free content; Chapters 5–9 are where art cost concentrates.
4. **`bathTime` and `morningRoutine` collide with existing mission ids.** `bathTime` maps cleanly (same content). The existing `morningRoutine` mission is a *dressing* set and becomes Chapter 3 `gettingDressed`; the Chapter 5 level of the same name is a different, longer routine. **Rename one of them before authoring** or the content validator will be ambiguous.
5. **`colorsAndShapes` splits into two levels** (`colors`, `shapes`) and `feedingTime` renames to `milkTime`. Both are data edits, not code.
6. **Speech appears in 12 levels and blocks none of them.** In every case it is an alternative route to a star that a tap already earns.
