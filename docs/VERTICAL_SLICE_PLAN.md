# Vertical Slice — "A Day With Little Buddy"

**Branch:** `design/life-journey-v2` · **Status:** proposal, not yet implemented.

The one thing to build next. **Not** the life story — one day, done beautifully.

> If this slice is not genuinely fun and genuinely pretty, no amount of additional chapters
> will save the game. If it *is*, the remaining chapters are mostly content.

**Target playtime:** 20–30 minutes including free exploration.
**Target character stage:** toddler (walks, dresses, feeds themselves with help).

---

## 1. Why a toddler, not a baby

The current game stars a baby who cannot walk. The slice must prove **tap-to-walk**, which is
the largest new system in the project. A baby that crawls-or-is-carried would let us dodge the
exact risk the slice exists to retire.

Choosing the toddler stage also means the slice maps onto **Chapter 3 — Toddler Adventures**,
so the work becomes real story content rather than a throwaway demo. Chapters 1–2 (family,
birth, baby days) can be authored later with the systems this slice proves.

**Decision to confirm with the product owner:** the slice ships as Chapter 3, and Chapters 1–2
are authored afterwards using the same templates. See §9.

**Amendment after cross-document review — Chapter 2 ships first.** The story review found that
Chapter 2 (Baby Days) maps ~1:1 onto the five missions that already ship and validate, so it
proves the level shell, per-level stars, the journey map and the save migration with **zero new
gameplay code, zero new objects and no movement system**. It lands before this slice, so
progression is stable *before* the riskiest new system (navigation) arrives. Chapter 3 remains
the real vertical slice — this only changes what is built immediately before it.

---

## 2. The flow

| # | Beat | Room | Proves | Minutes |
|---|---|---|---|---|
| 1 | **Wake up** — Buddy is asleep; tap to wake; stretch; "Good morning!" | Bedroom | TTS, semantic action, level intro | 1–2 |
| 2 | **Walk to the bathroom** — tap the floor, Buddy walks, doorway transition | Bedroom → Bathroom | **tap-to-walk, room navigation** | 2–3 |
| 3 | **Brush teeth** — drag toothbrush to mouth; "brush", "teeth" | Bathroom | dragObjectToCharacter, MouthMarker, new anim | 2–3 |
| 4 | **Wash face** — tap the tap; Buddy washes; "wash", "water" | Bathroom | tapObject → walk → act | 1–2 |
| 5 | **Walk back and get dressed** — choose shirt / pants / shoes | Bathroom → Bedroom | dressing, colours, **`findIt` with distractors** | 3–4 |
| 6 | **Walk to the kitchen** | Bedroom → Kitchen | multi-room navigation | 1 |
| 7 | **Breakfast** — sit at the table; choose banana / milk / apple; eat and drink | Kitchen | **sit**, eat, drink, `followInstruction` | 4–5 |
| 8 | **Say it** — "Can you say milk?" | Kitchen | **iOS speech + touch fallback** | 1–2 |
| 9 | **Play with teddy** — fetch, hug, free play | Living room | dragToHug, free play, sandbox | 3–4 |
| 10 | **Clean up** — put toys in the toy box | Living room | **`tidyUp`**, dragObjectToTarget, "in / on / under" | 2–3 |
| 11 | **Bedtime** — pyjamas, blanket, teddy, lights dim, "Good night" | Bedroom | sequence routine, warm close | 2–3 |
| 12 | **Summary** — ★★☆, sticker, Play Again / Next | — | 3-star progression, save | 1 |

**Total: 23–35 minutes.** Free play between beats is not counted and is expected to add more.

---

## 3. What it must prove

| Capability | How this slice proves it | Status today |
|---|---|---|
| Character walking | Beats 2, 5, 6 across three rooms | **NEW** |
| Tap-to-walk | Primary movement throughout | **NEW** |
| Drag interactions | Toothbrush, clothes, food, teddy, toys | **EXISTS** |
| Room navigation | Bedroom ↔ Bathroom ↔ Kitchen ↔ Living room | **NEW** |
| Object interaction | Every beat | **EXISTS** |
| Animation | wake, walk, brush, wash, dress, sit, eat, drink, hug, sleep | 5 exist, ~7 new |
| TTS | Every prompt | **EXISTS** |
| iOS speech recognition | Beat 8, plus optional "say it" on any object | **EXISTS, device-proven** |
| English learning | ~20 words across 4 rooms, Hear It / Say It / Do It | **EXISTS (content layer)** |
| Stars | 3 stars for the day | **EXTEND** (global → per-level) |
| Progression | Unlocks Free Play in all four rooms | **EXTEND** |
| Save | Resume mid-day; stars persist | **EXTEND** (schema v2) |
| Visual quality | Four rooms that look intentionally designed | **Art lock required first** |
| Child-friendly UX | No dead ends, no failure, forgiving targets | **EXISTS** |

---

## 4. Exact scope

### Rooms — 4
`bedroom` · `bathroom` · `kitchen` · `livingRoom`

Connected in one continuous navigable space (a small flat/apartment floorplan), **not**
separate loaded scenes — the slice must prove continuous walking, and door-to-door fades would
hide exactly the thing we are testing.

### Objects — 18
Reusing what already exists wherever possible.

| Room | Objects | Source today |
|---|---|---|
| Bedroom | bed, pillow, blanket, pyjamas, shirt, pants, shoes, lamp | ✅ all exist |
| Bathroom | toothbrush, toothpaste, soap, towel, sink/tap | ✅ 4 exist; **toothpaste + tap are new** |
| Kitchen | table, chair, milk, banana, apple, bowl, cup | ✅ all exist (table/chair from Kenney) |
| Living room | teddy, ball, blocks, toy box, sofa | ✅ all exist; **sofa new** |

**Only 4 genuinely new objects.** That is the payoff from having already modelled all 28.

### Animations — 12
| Have (5) | New (7) |
|---|---|
| idle, happy, drinking, hugging, hungry→sleepy | **walk**, wake/stretch, brushTeeth, wash, dress, sit, eat |

`walk` is the critical one and gates beats 2/5/6.

### English content — ~22 words
Mostly already authored:

- **Bedroom:** bed, pillow, blanket, pyjamas, shirt, pants, shoes, sleep, wake up, good night
- **Bathroom:** toothbrush, brush, teeth, soap, towel, wash, water
- **Kitchen:** milk, banana, apple, bowl, cup, eat, drink, hungry
- **Living room:** teddy, ball, blocks, play, clean up, in/on

Phrases: "Good morning!", "Let's brush your teeth.", "Put on your shoes.", "I'm hungry.",
"Can you say milk?", "Put the blocks in the box.", "Good night."

### Level templates used — 5 of ~6
`sequenceRoutine` (wake, bedtime) · `dragToCharacter` (brush, eat, drink) ·
`chooseCorrectObject` (dressing, breakfast) · `sayAndDo` (beat 8) · `tidyUp` (beat 10).

If the slice needs a sixth bespoke template, that is a signal the template set is wrong.

---

## 5. Stars

| Star | Condition |
|---|---|
| ★ 1 | Complete the day — all core beats done. **Achievable by touch alone.** |
| ★ 2 | Complete the listening tasks — correctly find objects when asked by name (`findIt`) |
| ★ 3 | Optional care/exploration — tidy all toys, put the teddy to bed, tap 5 objects to hear their words |

2/3 passes. 3/3 grants a bonus sticker. **Speech is never required for any star** — beat 8 can
be completed by touch and still earns its star. Never subtract a star; never show failure.

---

## 6. Free play

After the slice is completed once, all four rooms stay open in Free Play:
walk anywhere · tap any object to hear its English word · drag objects · change clothes ·
eat/drink · sleep · play · long-press for the optional Thai hint.

No quiz popups. This is where replay value lives, and it costs almost nothing once the rooms
and interactions exist.

---

## 7. What is deliberately NOT in the slice

Chapters 1–2 (family, wedding, pregnancy, birth, baby stage) · school/teen/career chapters ·
parents as playable characters · outdoor areas · outfit shop · multiple save slots ·
career mini-games · any chapter beyond the single day.

**Deliberate exclusion:** the slice does not attempt the emotional story arc. It proves the
*systems*. The story lands in Phase D on top of proven mechanics.

---

## 8. Definition of done

**Functional:** all 12 beats completable; tap-to-walk works in all four rooms with no stuck
state; every task completable **by touch alone**; speech works but is never required; 3 stars
earnable; progress saves and resumes mid-day; Free Play accessible afterwards.

**Quality:** runs on a physical iPhone and iPad at a comfortable frame rate; all four rooms
look intentionally designed (not placeholder); the character reads as a toddler and animates
convincingly for all 12 actions; **a 4-year-old can play the whole slice without adult
explanation**; no dead ends, no failure states, no debug UI.

**Technical:** project loads with zero errors; full test suite green; iOS export and arm64
build succeed; no network calls; no child audio persisted.

**The child test is the real bar.** Everything else is necessary but not sufficient.

---

## 9. Decisions needed before implementation starts

1. **Confirm the slice ships as Chapter 3 (toddler)**, with Chapters 1–2 authored afterwards.
   The alternative — build Chapter 1 first for story order — would defer the navigation risk,
   which is the wrong trade.
2. **Art lock.** `docs/ART_BIBLE_DRAFT.md` must be approved before any character or room art is
   commissioned or generated. The current baby is explicitly temporary.
3. **Character model.** Four rooms and a walking toddler need a rigged character. Either
   commission against `docs/CUSTOM_BABY_SPEC.md` (extended to toddler proportions) or continue
   procedurally for the slice and swap later. **The socket/semantic-action contract makes the
   swap safe either way** — but walking convincingly with primitives is a real risk.
4. **Room art source.** Kenney furniture retinted is serviceable but harder-edged than the
   props. Tiny Treats "Playful Bedroom" ($7.95, CC0) would cover the bedroom well; a kitchen,
   bathroom and living room still need a source.

---

## 10. Sequencing

| Phase | Work | Gate |
|---|---|---|
| **B0** | Save schema v2, per-level stars, chapter/level scaffolding | tests green, iOS build green |
| **B1** | `HouseWorld` + 4 rooms, navigation baked, **tap-to-walk**, walk animation | character walks all four rooms, never stuck |
| **B2** | `playAction()` + the 7 new animations | all 12 actions play and read correctly |
| **B3** | The 12 beats as data, using the 5 templates | slice completable by touch alone |
| **B4** | Speech, stars, summary, Free Play | 3 stars earnable, save/resume works |
| **B5** | Art pass to the locked bible; render and inspect every room | looks intentionally designed |
| **B6** | Device validation on iPhone **and** iPad; child playtest | a 4-year-old completes it unaided |

**B1 is the risk.** If tap-to-walk is not solid by the end of B1, stop and fix it — every later
phase builds on it.
