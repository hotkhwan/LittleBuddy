# Little Buddy — Game Bible & Story Progression v0.2

## 0. Executive Direction

Little Buddy is a **story-driven, sandbox-style life journey game for children**, focused on caring for a growing child, helping with daily routines, learning practical English through context, earning stars and passing levels, unlocking rooms/objects/outfits/stickers, and allowing the main character to walk around and interact with the home/world.

The emotional promise:

> “I get to grow up together with my Little Buddy.”

The player is a helper/caregiver — a “Big Buddy” — who supports the child character through life stages, from before birth through childhood, school, graduation, and an early-career dream ending.

The tone must always be warm, cute, safe, positive, family-friendly, non-punitive, playful, and emotionally understandable for children.

The game may take inspiration from the freedom and playfulness of child sandbox games, but must be an original product with original characters, story, art direction, UI, dialogue, mechanics, and world design.

Do not copy characters, rooms, dialogue, animations, music, UI layouts, branding, or assets from any existing commercial game.

---

# 1. Core Player Fantasy

The player is not “taking a test.”

The player is **helping Little Buddy live their life**.

English learning happens while doing real activities:
- “Let’s drink some milk.”
- “Put on your shoes.”
- “Where is the toothbrush?”
- “Let’s go to school.”
- “Open the door.”
- “Good morning!”
- “I’m hungry.”
- “Can you help me?”

The child should feel:
- “I’m helping.”
- “I’m taking care of someone.”
- “I’m making progress.”
- “I unlocked the next stage.”
- “My Buddy is growing up.”
- “I want to see what happens next.”

---

# 2. Main Character Model

## 2.1 Little Buddy

Little Buddy is the central character and grows through the story:

1. unborn baby / pregnancy chapter
2. newborn
3. baby
4. toddler
5. preschool child
6. primary-school child
7. older child
8. teen
9. university / training age
10. young adult / first career

For MVP/public beta, not every stage needs a completely unique high-detail model.

Use age-stage model families:
- newborn/baby
- toddler
- child
- older child/teen
- young adult

Each stage may share rigs when practical.

## 2.2 Player role: Big Buddy

The human player is “Big Buddy.”

Big Buddy is not necessarily shown as a full 3D person in the earliest release.

The player’s actions are expressed through:
- tap
- drag
- move Little Buddy
- pick up object
- give object
- place object
- dress character
- speak into microphone
- choose simple options

Later, Big Buddy may optionally have an avatar.

---

# 3. Family Story

The default story follows this family arc:

1. Mom and Dad meet.
2. They become friends.
3. They decide to build a life together.
4. They get married.
5. Mom is pregnant.
6. Family prepares for the baby.
7. Baby is born.
8. The player becomes the helper/caregiver.
9. Little Buddy grows through daily life.
10. Little Buddy goes to school.
11. Little Buddy develops interests.
12. Little Buddy graduates.
13. Little Buddy chooses a career.
14. Final chapter: “A New Beginning.”

Keep the presentation child-friendly.

Do NOT include sexual content, graphic childbirth, unnecessary medical detail, scary hospital imagery, or distressing pregnancy complications.

Pregnancy is communicated simply:
- family photo
- growing belly
- nursery preparation
- optional simple checkup/heartbeat moment
- “A baby is coming!”

Birth can be represented by:
- transition card
- hospital exterior / cozy room
- parents smiling
- baby wrapped in blanket

---

# 4. Game Structure

Use:

CHAPTER
  └── LEVEL
       └── 3–8 ACTIVITIES
             └── STARS + PROGRESS

The player sees a clear journey map.

Example:

Chapter 1 — Our Family Begins
- Level 1: Hello!
- Level 2: A Special Day
- Level 3: A Baby Is Coming
- Level 4: Getting Ready
- Level 5: Welcome, Little Buddy!

Chapter 2 — Baby Days
- Level 6: Milk Time
- Level 7: Bath Time
- Level 8: Bedtime
- Level 9: Toys & Smiles
- Level 10: First Words

A level should take roughly 4–10 minutes for normal play and longer if the child explores sandbox interactions.

Replay comes from:
- different object choices
- randomized phrases
- optional exploration
- sticker collection
- outfits
- room interactions
- English voice practice
- star completion

---

# 5. Star System

Stars are important because children naturally read them as score/progress.

Use them intentionally.

## 5.1 Three-star level model

Each level can earn up to 3 stars.

Star 1:
- complete the core activity

Star 2:
- complete an English listening/recognition task

Star 3:
- complete optional exploration / care / cleanup task

Never require perfect pronunciation for a star.
Never subtract stars.
Never show negative scores.

## 5.2 Level completion

Example:

Milk Time

★ Feed Little Buddy
★ Find the milk after hearing “milk”
★ Say “milk” OR use touch fallback

2 / 3 stars is enough to pass.
3 / 3 unlocks a bonus sticker.

Speech should be a bonus/enrichment path, never a hard blocker.

---

# 6. World Navigation

Little Buddy must be able to move.

## Tap-to-walk

Player taps the floor:
- Little Buddy walks there.
- Animation changes idle → walk → idle.
- Movement uses NavigationAgent3D or a lightweight navigation system.
- No complicated virtual joystick in early versions.

## Drag character

For very young players, allow a forgiving “drag Little Buddy” mode in some scenes:
- drag character toward an activity zone
- character snaps to the activity spot
- then performs the activity

Do not literally teleport on every drag if it feels ugly; use a short walk/snap transition.

## Object interaction

Player can:
- tap object
- drag object to Little Buddy
- drag object to target
- tap furniture
- open/close simple containers
- move toys
- dress character

The interaction should feel like a child sandbox, not a menu-driven quiz.

---

# 7. Home Hub

For the first public version, the game world stays mostly in and around the family home.

Rooms:
1. Living Room
2. Kitchen
3. Bedroom
4. Bathroom
5. Nursery / Baby Room
6. Small Garden / Front Yard (later)
7. Study Corner (school chapter)

Each room has:
- free-play interactions
- story mission entry points
- English vocabulary set
- reusable objects

Example vocabulary:

Living Room:
sofa, table, lamp, book, teddy, ball, sit, stand, open, close

Kitchen:
milk, water, apple, banana, spoon, bowl, cup, plate, hungry, thirsty, eat, drink

Bathroom:
soap, towel, toothbrush, toothpaste, water, wash, clean, dry, brush

Bedroom:
bed, pillow, blanket, pajamas, shirt, pants, shoes, sleep, wake up, good night

---

# 8. Full Story Arc

## CHAPTER 1 — Our Family Begins

### Level 1 — Hello!
Story:
Mom and Dad meet in a friendly public place such as a park/cafe.

Activities:
- tap Mom
- tap Dad
- wave
- hear “Hello!”
- choose a drink/object
- simple walking

English:
hello, hi, my name is..., nice to meet you, friend

Stars:
1. help them say hello
2. find the correct object
3. repeat or tap “Hello”

### Level 2 — A Special Day
Story:
Mom and Dad celebrate becoming a family.

Use a simple wedding scene:
- flowers
- family
- cake
- rings shown symbolically

English:
family, happy, love, cake, flower, together

Activities:
- decorate table
- place flowers
- find cake
- take family photo

### Level 3 — A Baby Is Coming
Story:
Mom is pregnant.

Presentation:
- “A baby is coming!”
- parents are happy
- no medical detail

English:
baby, family, small, happy, heart, home

Activities:
- choose baby clothes
- choose blanket
- place teddy in nursery

### Level 4 — Getting Ready
Prepare nursery.

English:
bed, blanket, pillow, teddy, bottle, clean

Activities:
- move crib/bed item
- place teddy
- put blanket
- prepare bottle
- tidy room

### Level 5 — Welcome, Little Buddy!
Birth transition.

English:
baby, welcome, hello, sleep, smile

Activities:
- choose blanket color
- gently place baby in bed
- hear baby sound
- say “Hello, baby!”

Reward:
Unlock Chapter 2.

---

## CHAPTER 2 — Baby Days

### Level 6 — Milk Time
- feed milk
- bottle drag-to-mouth
- “milk”
- “I’m hungry.”
- “Can I have some milk?”

### Level 7 — Bath Time
- soap
- towel
- wash
- clean
- dry

### Level 8 — Bedtime
- pajamas
- blanket
- pillow
- teddy
- good night

### Level 9 — Toys & Smiles
- teddy
- ball
- block
- star
- play

### Level 10 — First Words
- mama
- dada
- milk
- teddy
- hello
- bye-bye

Milestone:
Little Buddy grows to toddler stage.

---

## CHAPTER 3 — Toddler Adventures

### Level 11 — First Steps
This is where player movement becomes central.

Activities:
- tap floor to walk
- walk to Mom
- walk to toy
- walk to kitchen

English:
walk, stop, come here, go, up, down

### Level 12 — Breakfast
- sit at table
- choose food
- apple/banana/milk/water
- eat/drink

### Level 13 — Getting Dressed
- shirt
- pants
- shoes
- hat
- colors

### Level 14 — Clean Up
- put blocks into box
- teddy on shelf
- ball into basket

English:
clean up, put away, in, on, under

### Level 15 — Play With Me
- ball
- teddy
- blocks
- simple pretend play

Milestone:
Preschool unlocked.

---

## CHAPTER 4 — Preschool

### Level 16 — My First Day
- backpack
- shoes
- hello teacher
- hello friend

### Level 17 — Colors
red, blue, yellow, green, pink

### Level 18 — Shapes
circle, square, triangle, star

### Level 19 — Numbers
one to ten, count toys, count fruit

### Level 20 — Sharing
give, take, please, thank you, your turn, my turn

Milestone:
School-age character model.

---

## CHAPTER 5 — School Days

### Level 21 — Morning Routine
wake up, wash face, brush teeth, dress, breakfast, backpack

### Level 22 — Going to School
bus/car/walk symbolic, school, teacher, classroom

### Level 23 — Reading Time
book, page, read, letter, word

### Level 24 — Art Class
draw, color, paper, pencil

### Level 25 — Sports Day
run, jump, ball, throw, catch

---

## CHAPTER 6 — Growing Skills

### Level 26 — Help at Home
make bed, clean table, organize toys/books

### Level 27 — Cooking Together
simple recipe, fruit, bowl, spoon, mix

### Level 28 — My Hobby
Player chooses:
- music
- drawing
- sports
- science
- building

### Level 29 — Friends
greetings, sharing, invitation, teamwork

### Level 30 — My Big Project
A multi-step activity requiring movement, object finding, and English instructions.

---

## CHAPTER 7 — Teen Journey

Keep it light and aspirational.

### Level 31 — My Schedule
morning, afternoon, evening, today, tomorrow

### Level 32 — Study Time
homework, computer, book, question, answer

### Level 33 — Teamwork
help, together, idea, good job

### Level 34 — Responsibility
clean, prepare, check, remember

### Level 35 — My Dream
Choose interests/career themes.

---

## CHAPTER 8 — Graduation

### Level 36 — Final Project
Complete a larger activity.

### Level 37 — Graduation Day
graduation cap, family, photo, proud, congratulations

English:
“I did it!”
“Congratulations!”
“Thank you.”
“I’m proud of you.”

Reward:
Graduation sticker / trophy.

---

## CHAPTER 9 — My Future

Career exploration — not a permanent irreversible choice.

Career themes:
- doctor
- teacher
- engineer
- artist
- chef
- scientist
- firefighter
- designer
- programmer
- veterinarian

Each career has one small playful activity.

Final message:
“You helped Little Buddy grow up.”

Then:
“Every ending is a new beginning.”

Do not truly end the save.

After celebration:
- unlock Free Life mode
- revisit all ages/chapters
- replay levels
- complete stickers
- try different careers

---

# 9. Sandbox Layer

Every unlocked room remains playable.

Free Play mode:
- move Little Buddy
- interact with objects
- change clothes
- eat/drink
- sleep
- brush teeth
- play
- rearrange selected toys
- repeat words by tapping objects

Tap object:
- object animates
- TTS says English word

Long press:
- optional Thai hint

No quiz popup required.

---

# 10. English Learning Design

Three learning modes integrated into play.

## Hear It
The game says:
“Find the milk.”

Player finds the milk.

## Say It
Game says:
“Can you say milk?”

Speech recognition is optional.
Fallback: player can tap the word/object and continue.

## Do It
Game says:
“Put the teddy on the bed.”

Player performs the instruction.

Vocabulary difficulty grows with age.

Baby:
- nouns
- one-word actions

Toddler:
- two-to-four word phrases

School:
- full simple instructions

Older:
- conversational phrases

---

# 11. Level UX

Top-left:
- chapter/level indicator

Top-center:
- current spoken instruction bubble

Top-right:
- stars earned for current level

Bottom/right:
- microphone button if voice activity available

At level finish:

Great job!

★★☆

New sticker unlocked!

[Play Again] [Next Level]

If only 1–2 stars:
- still celebrate
- never say failure
- show remaining star as optional challenge

---

# 12. Character Movement Architecture

Implement reusable character controller.

Requirements:
- CharacterBody3D
- NavigationAgent3D
- tap-to-walk
- activity target positions
- face interaction target
- stop radius
- animation state transitions
- no ragdoll
- mobile-safe

State machine:
- Idle
- Walk
- Interact
- Carry
- Eat
- Drink
- Sit
- Sleep
- Celebrate

Interaction flow:

Player taps fridge
→ Little Buddy walks to fridge
→ faces fridge
→ opens door
→ activity begins

Drag flow:

player drags banana → Little Buddy
→ character receives object
→ eat animation
→ dialogue “Banana!”

---

# 13. Animation Requirements

Minimum reusable animation library:

Locomotion:
- idle
- walk
- run optional

Body:
- wave
- point
- clap
- nod
- shake head
- sit
- stand

Care:
- eat
- drink
- brush teeth
- wash hands
- sleep
- wake
- hug
- pick up
- hold
- give

Emotion:
- happy
- excited
- sleepy
- hungry
- surprised

Use AnimationTree/state machine.

Do not hardwire missions directly to animation file names; use semantic actions.

Example:
character.playAction("drink")

---

# 14. Art Pipeline — AFTER Story/Interaction Lock

Do NOT redesign every model before this game bible is accepted.

Order:
1. lock story structure
2. lock character ages
3. lock room list
4. lock interaction list
5. lock vocabulary objects
6. create visual style bible
7. create/generate models
8. textures/materials
9. rig
10. animations
11. final lighting/polish

This avoids regenerating expensive assets because scope changed.

---

# 15. Art Bible Requirements

Before using Meshy or commissioning an artist, create:
docs/ART_BIBLE.md

It must define:
- Little Buddy face style
- age-stage proportions
- eye style
- hair style
- hand/foot proportions
- clothing style
- palette
- room style
- prop style
- material roughness
- texture resolution
- triangle budgets
- lighting
- UI style
- app icon style

Target look:
- polished stylized 3D
- soft rounded
- premium children's game
- readable silhouettes
- not photorealistic
- no uncanny realism

---

# 16. Meshy / 3D Generation Strategy

Meshy may be used after art direction is locked.

Recommended use:
- hero character concepts
- room props
- food
- toys
- furniture
- clothing accessories

Do not rely blindly on generated topology.

For every model:
- inspect silhouette
- inspect topology
- inspect UV
- inspect texture
- reduce materials
- normalize scale
- correct pivot
- optimize triangles
- test on iPhone

Character models:
- use neutral A/T pose
- visible hands
- separated limbs
- no fused arms/legs
- clean proportions

Export target:
- GLB preferred

---

# 17. Mobile Asset Budgets

Suggested budgets:

Main character:
15k–35k triangles

Secondary character:
10k–25k

Large furniture:
2k–8k

Hero prop:
1k–6k

Small prop:
300–3k

Textures:
- most props: 512–1024
- characters: 1024–2048
- environment atlases preferred

Materials:
- keep low
- ideally 1–3 per object

No 4K textures for ordinary props.

---

# 18. Save Data

Persist:
- currentChapter
- currentLevel
- starsByLevel
- unlockedChapters
- unlockedRooms
- unlockedOutfits
- unlockedStickers
- selectedCareer
- optionalHobby
- settings

Never make story progression dependent on cloud.

---

# 19. Public/Friends Distribution Direction

The parent wants to eventually let the child tell friends:
“My dad made this game. You can download it too!”

Prepare toward a small external beta.

Do NOT publish immediately.

Before public distribution require:
1. crash-free basic flow
2. physical-device testing
3. speech permission behavior verified
4. privacy wording correct
5. asset licenses audited
6. no copyrighted borrowed models
7. app icon polished
8. no debug UI
9. parental/privacy page
10. save corruption recovery
11. first-launch onboarding
12. TestFlight beta

Recommended progression:

Dad's device
→ family devices
→ 5–10 trusted friends via TestFlight
→ fix UX/crashes
→ wider TestFlight
→ App Store consideration

---

# 20. Development Roadmap

## Phase A — Game Design Lock
Do now.

Deliver:
- story map
- chapter/level definitions
- interaction matrix
- vocabulary matrix
- progression/star rules
- movement spec
- unlock logic

NO major art regeneration yet.

## Phase B — Vertical Slice

Build only one polished slice:

“A Day With Little Buddy”

Sequence:
1. Little Buddy wakes up
2. player taps floor → Buddy walks to bathroom
3. brush teeth
4. walk to bedroom
5. get dressed
6. walk to kitchen
7. choose breakfast
8. hear/say “milk”, “banana”, etc.
9. play with teddy
10. clean up toys
11. bedtime
12. level summary

Target:
20–30 minutes of varied play.

This slice must prove:
- movement
- interaction
- room navigation
- animation
- English
- speech
- stars
- save
- art quality

Only after this slice is genuinely fun and beautiful should the full life-story chapters be produced.

## Phase C — Art Lock
Create:
- final Little Buddy model
- final home style
- final UI system
- final icon
- reusable props

## Phase D — Story Expansion
Expand chapters using proven systems.

## Phase E — TestFlight
Small beta.

---

# 21. Claude Implementation Instruction

Claude: treat this document as the product/game-design source of truth.

Do NOT immediately implement all chapters.

First produce:
1. docs/STORY_MAP.md
2. docs/LEVEL_MATRIX.md
3. docs/INTERACTION_MATRIX.md
4. docs/VOCABULARY_ROADMAP.md
5. docs/CHARACTER_AGE_STAGES.md
6. docs/ART_BIBLE_DRAFT.md
7. docs/VERTICAL_SLICE_PLAN.md

Then inspect the current codebase and map existing systems to the new design.

For each existing subsystem, mark:
- keep
- modify
- replace
- deprecate

Expected examples:
- mission system → keep/extend
- stars → keep/convert to per-level stars
- stickers → keep
- save → extend
- speech abstraction → keep/fix
- primitive baby-room flow → convert into vertical slice
- procedural placeholder models → temporary/deprecate
- current room → reuse only if compatible

Do not destroy working code until replacement is validated.

---

# 22. Quality Bar

The player is a child, not a QA engineer.

A feature is not done because:
- code compiles
- test passes
- placeholder exists

A feature is done when:
- child understands it
- object looks like what it teaches
- interaction is obvious
- animation gives feedback
- audio matches action
- no stuck state
- no scary punishment
- screen is visually coherent

For visual/UX work, always render screenshots and inspect them.

---

# 23. Immediate Next Action for Claude

Do not add more random content.
Do not generate more placeholder 3D models.
Do not expand to teen/career gameplay yet.

First:
1. read this whole document
2. audit current repo
3. create the 7 design documents listed above
4. propose the minimum architecture changes
5. identify which existing features survive
6. design the “A Day With Little Buddy” vertical slice
7. stop before destructive refactoring
8. report the proposed migration plan

Then wait for product approval before major art/model generation.
