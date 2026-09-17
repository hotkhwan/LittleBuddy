# Little Buddy — Interaction Matrix v1.0

Design lock for Phase A (Game Bible §20). This document defines the **complete reusable
interaction vocabulary** of the game: every way a child can act on the world, for every
chapter from newborn to career.

Companion docs (written in parallel, not duplicated here): `STORY_MAP.md`,
`LEVEL_MATRIX.md`, `CHARACTER_AGE_STAGES.md`, `ART_BIBLE_DRAFT.md`,
`VERTICAL_SLICE_PLAN.md`, `VOCABULARY_ROADMAP.md`.

---

## 0. How to read this document

### 0.1 Status legend

| Status | Meaning |
| --- | --- |
| `EXISTS` | Shipping today on device. Reuse as-is; changes are additive only. |
| `EXTEND` | A working system covers part of it. Add parameters/animation, do **not** rewrite. |
| `NEW` | No runtime support at all today. Must be built. |

### 0.2 What is actually in the build today (verified, 2026-09-17)

| System | File | Role |
| --- | --- | --- |
| `DraggableObject` | `game/scripts/interaction/draggable_object.gd` | Camera-ray drag on a stable plane, latched pointer (multi-touch safe), tap fallback, spring-back tween |
| `DragPlane` | `game/scripts/interaction/drag_plane.gd` | Stable world plane for ray projection |
| `DropZone` | `game/scripts/gameplay/drop_zone.gd` | Radius zone, 6 zone ids: `mouth`, `hug`, `bath`, `dress`, `toyBox`, `hand` |
| `ObjectSpawner` | `game/scripts/gameplay/object_spawner.gd` | Builds any object node from a JSON record; enforces `MIN_GRAB_PX = 220.0` |
| `ModeHandler` + 3 modes | `game/scripts/gameplay/{find_it,say_it,follow_instruction}_mode.gd` | `findIt` / `sayIt` / `followInstruction` |
| `MissionRunner` | `game/scripts/gameplay/mission_runner.gd` | Task sequencing, stars, no-double-award, gentle skip |
| `IntentMatcher` | `game/scripts/speech/intent_matcher.gd` | Tolerant phrase matching (normalize + contains + whole-word) |
| `SpeechService` / `TtsService` | `game/scripts/speech/` | On-device STT (proven on physical iPhone) + TTS with timed fallback |

Content interaction verbs already authored in `game/content/objects.json` /
`index.json`: `dragToMouth`, `dragToHug`, `dragToBath`, `dragToDress`, `dragToToyBox`,
`tap`.

**There is no character movement of any kind today** — no `CharacterBody3D`, no
`NavigationAgent3D`, no walk state, no carry. Every movement row below is `NEW`.

### 0.3 Summary count

**27 interactions defined — 7 `EXISTS`, 9 `EXTEND`, 11 `NEW`.**

---

## 1. The three design rules this matrix obeys

### Rule 1 — Four primitives, not twenty-seven behaviours

Every interaction in this document is a **parameterisation of one of four primitives**.
If a new activity cannot be expressed as a config of these four, that is a design smell,
not a reason for a new script.

| Primitive | Script today | What it is |
| --- | --- | --- |
| **P1 `Pointable`** | `DraggableObject` (tap path) | A thing you touch once. Emits `chosen(objectId)`. |
| **P2 `Draggable`** | `DraggableObject` (drag path) | A thing you pick up with a finger and move on the drag plane. |
| **P3 `Zone`** | `DropZone` | A place a `Draggable` can be delivered to. Emits `object_delivered(objectId)`. |
| **P4 `Navigable`** | *none — `NEW`* | A place the character can walk to and face. Emits `arrived(targetId)`. |

`dragObjectToTarget` is **one** behaviour: P2 + P3. Feeding a baby, putting blocks in a
toy box, and hanging a school bag on a hook are the *same code* with three different
zone ids. The `objects.json` verbs `dragToMouth` / `dragToBath` / `dragToToyBox` are
already just rows in `DropZone.INTERACTION_TO_ZONE_ID` — keep that pattern and never add
a verb that needs a new script.

**Judgement call:** the six existing `dragToX` verbs stay as authoring sugar (content is
already written against them), but the *engine* concept is `dragObjectToTarget(zoneId)`.
New content should author `{"interaction": "dragObjectToTarget", "zoneId": "hook"}`; the
loader maps the six legacy verbs onto it. No content migration required.

### Rule 2 — Semantic actions only, never animation filenames

Missions and modes call:

```gdscript
character.play_action("drink")        # GDScript-side API
character.play_action("carry", {"objectId": "teddy"})
```

They **never** reference `res://assets/anim/baby_drink_v3.glb` or an
`AnimationPlayer` track name. `CharacterRig` owns the semantic-action → AnimationTree
state mapping, and is the only place that knows filenames. This is Bible §13's
requirement (`character.playAction("drink")`) and it is the single most important
decoupling in the project: it lets art be regenerated per age stage (newborn → toddler →
child → teen → adult) without touching one line of mission code.

`play_action()` must be **total**: an unknown or not-yet-authored action logs once and
falls back to `idle` + the emotion tint, and still emits `action_finished`. A missing
animation must never stall a mission.

### Rule 3 — Every interaction has a forgiving fallback and no dead end

Hard project rules, applied to every row of the matrix:

| Rule | Enforcement |
| --- | --- |
| No red X, no buzzer, no shake-of-shame | Wrong choice → `task_failed_gently()` + rotated kind phrase (`ModeHandler.GENTLE_PHRASES`), task stays running |
| No score, no percentage, no pronunciation rating | Speech returns boolean match only (`IntentMatcher.matches`), never a confidence number shown to the child |
| No timer, no failure pressure | No interaction may have a time limit. Idle nudges are re-prompts, never penalties. |
| Speech always optional | `complete_by_touch()` exists on every mode handler and is always reachable |
| Large touch targets | `ObjectSpawner.MIN_GRAB_PX = 220.0` — every new interactable inherits this floor |
| Never dead-end | Every interaction declares an **auto-resolve** path: after N gentle retries the game demonstrates and completes the step itself, still awarding the star |

**Auto-resolve ladder** (applies to *all* modes, all stages):

| Attempt | Game response |
| --- | --- |
| 1st wrong / 8 s idle | Repeat the instruction, slower TTS rate (`TtsService.SLOW_SPEECH_RATE`) |
| 2nd wrong / 16 s idle | Highlight the correct target (gentle pulse + soft glow), optional Thai hint if `thaiHints` |
| 3rd wrong / 24 s idle | Non-correct choices fade back to the tray; only the right one remains grabbable |
| 4th / any tap after that | **Assist complete** — character performs the action itself, full praise, full star. Recorded as `assisted: true` in save for parent stats only; never shown to the child. |

---

## 2. Master matrix

Columns: **Input** · **Target** · **Character action** (semantic) · **Animation** ·
**Audio/TTS** · **Mission event** · **Success** · **Fallback** · **Status**.
Mobile UX notes are in §4 per interaction; the rules that apply to all rows are in §5.

### 2.1 Movement (all `NEW`)

| # | Interaction | Input | Target | Character action | Animation | Audio / TTS | Mission event | Success condition | Fallback | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `tapToWalk` | Single tap on floor / nav mesh | `NavRegion` point | `walk_to(point)` | `idle → walk → idle`, turn-in-place if angle > 60° | Footstep SFX only; optional TTS `"Let's go!"` on first use in a level | `character_arrived(targetId)` | Character within `stopRadius` (0.35 m) of point, idle resumed | Untappable floor point snaps to nearest valid nav point — a tap **never** does nothing. If nav fails, straight-line lerp + `walk` anim. | `NEW` |
| 2 | `dragCharacterToActivity` | Drag on the character body | Activity zone (`Navigable`) | `walk_to(zone.anchor)` then `face(zone.focus)` | Drag: `carried_by_player` idle-hover (no ragdoll). Release: short `walk` to snapped anchor | Soft "whoosh" on pickup, gentle land SFX | `character_arrived(zoneId)` | Character snapped to zone anchor, facing focus | Released outside any zone → walks back to nearest valid anchor, never floats/clips. Never teleports (Bible §6). | `NEW` |
| 3 | `sit` | Tap a seat (`Navigable` + `seat` tag) | Chair / stool / floor cushion | `walk_to(seat)` → `play_action("sit")` | `walk → sit_down → sit_idle`; `stand_up` to exit | TTS `"Sit down, please."` (School+) / `"Sit!"` (Toddler) | `character_state_changed("sit")` | `sit_idle` reached, character parented to seat anchor | If no seat animation yet: snap to seat anchor with `idle` + lowered root. Tap anywhere else stands up — never trapped. | `NEW` |

### 2.2 Object interaction (core loop)

| # | Interaction | Input | Target | Character action | Animation | Audio / TTS | Mission event | Success condition | Fallback | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4 | `tapObject` | Single tap on object | Any spawned object | `play_action("look_at", {objectId})` | Object: scale-pop 1.12 + tilt 8° (`DraggableObject._play_pickup_feedback`). Character: `nod`/`point` | **TTS says the English word** (Bible §9). Long-press → Thai hint. | `object_chosen(objectId)` | Object emitted `chosen`; in `findIt` mode, id matches `task.objectId` | Always succeeds as an interaction — in free play there is no wrong tap, only a word spoken | `EXISTS` |
| 5 | `dragObjectToCharacter` | Drag object onto character | `DropZone` ids `mouth`, `hug`, `hand` | `receive(objectId)` then the object's own semantic action | Character: `open_mouth` / `hug` / `take`. Object: snap + consume tween | Prompt before, praise after: `"Great!"` + `"Thank you!"` | `object_delivered(zoneId, objectId)` | Object centre inside zone radius on release **or** on tap-deliver | Tap-to-deliver (already in `DraggableObject._deliver_via_tap`). Drop short of the zone → object animates to the zone anyway if within 1.6× radius ("magnet"). | `EXISTS` |
| 6 | `dragObjectToTarget` | Drag object onto a world zone | Any `DropZone` (`toyBox`, `bath`, `dress`, `bed`, `shelf`, `hook`, `plate`, `basket`…) | `play_action("point")` + reaction | Object: arc-to-zone + settle. Zone: accept pulse | Instruction `"Put the teddy on the bed."` → praise | `object_delivered(zoneId, objectId)` | Same as #5 | Same magnet + tap-deliver. Zone marker becomes visible after 1st retry (`DropZone.set_marker_visible`). | `EXISTS` |
| 7 | `pickUp` | Press-and-hold ≥120 ms, or tap when a `pickUp` task is active | Any `Draggable`, or a character-reachable object | `walk_to(object)` → `play_action("pick_up")` → holds | `reach_down → hold_idle`. Object reparents to hand socket | SFX pickup; TTS names the object on first pickup | `object_picked_up(objectId)` | Object parented to `HandSocket`, `carry` state entered | Player-hand pickup (today's drag) always works even if the character-hand version is unavailable. Two-tier: **finger pickup** (`EXISTS`) vs **character pickup** (`NEW`). | `EXTEND` |
| 8 | `carry` | Implicit after `pickUp`; walk with `tapToWalk` while holding | — | `walk_to()` with `carrying = true` | `walk_carry`, `idle_carry` (upper-body override layer over locomotion) | Nothing new; ambient only | `character_state_changed("carry")` | Object stays in hand across nav, room change, and animation blends | If no carry variant exists, use base locomotion + hand socket attachment. Item can never be "lost": dropping returns it to its home spawn. | `NEW` |
| 9 | `give` | Drag object onto another **character** (Mom, Dad, teacher, friend) | `hand` zone on the recipient | `play_action("give")` on giver, `play_action("take")` on receiver | `extend_arm → release`, receiver `take → hold` | `"Here you are."` / `"Thank you!"` — the Preschool sharing pair (Level 20) | `object_given(fromId, toId, objectId)` | Object reparented to recipient's hand socket | Falls back to `dragObjectToCharacter` on the `hand` zone with a generic accept. | `EXTEND` |
| 10 | `open` | Tap a container / door | Fridge, toy box lid, door, backpack, book | `walk_to` → `play_action("open")` | Container: hinge/slide tween 0.4 s. Character: `reach` | TTS `"Open the door."` / word on tap in free play | `container_opened(containerId)` | Container `isOpen == true`, contents revealed and interactable | Tapping an open container closes it — always reversible, no state trap. If walk fails, open in place. | `NEW` |
| 11 | `close` | Tap an open container | Same set | `play_action("close")` | Reverse tween | `"Close it, please."` | `container_closed(containerId)` | `isOpen == false`; contents no longer interactable | Auto-closes on level end so no scene is left half-open | `NEW` |

### 2.3 Care & routine (the English-carrying activities)

| # | Interaction | Input | Target | Character action | Animation | Audio / TTS | Mission event | Success condition | Fallback | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 12 | `eat` | Result of `dragObjectToCharacter(mouth)` with a food object | `mouth` zone | `play_action("eat")` | `chew` ×2–3 + `happy` emote | Chew SFX + `"Yum! Apple!"` | `need_satisfied("hunger", amount)` | `eat` animation finished, hunger reduced by `hungerRelief` | Drives from existing feeding tasks. If `eat` anim missing → `idle` + happy face + word. | `EXTEND` |
| 13 | `drink` | `dragObjectToCharacter(mouth)` with a liquid | `mouth` zone | `play_action("drink")` | `tilt_cup → swallow`, object tips | Sip SFX + `"Milk!"` | `need_satisfied("thirst", amount)` | Same pattern as `eat` | Same | `EXTEND` |
| 14 | `sleep` | Drag character to bed **or** tap bed at bedtime | `bed` zone | `walk_to(bed)` → `play_action("sleep")` | `lie_down → sleep_idle` (slow breathing loop), room lights dim | `"Good night!"` + lullaby stinger | `character_state_changed("sleep")` | `sleep_idle` reached and held ≥2 s | If `lie_down` missing: fade-to-dark card, then sleeping pose. Tap anywhere wakes — never stuck asleep. | `NEW` |
| 15 | `wake` | Tap character / tap the sun / auto at level start | Character | `play_action("wake")` | `sleep_idle → sit_up → stretch → idle`, lights raise | `"Good morning!"` | `character_state_changed("idle")` | `idle` reached, controls re-enabled | Auto-wake after 6 s if the child does nothing. **This is the vertical slice's opening beat** (Bible §20 Phase B step 1). | `NEW` |
| 16 | `dress` | Drag garment onto character | `dress` zone | `play_action("dress")` | Garment: fly-on + settle; character: `arms_up` | `"Put on the red shirt."` → `"Nice!"` | `outfit_changed(slotId, objectId)` | Garment mesh swapped into the body slot, old one returned to the wardrobe | Works today as pure delivery + mesh swap; the `arms_up` animation is the only addition. Wrong garment → gentle phrase, garment returns, **never removed from the tray**. | `EXISTS` |
| 17 | `brushTeeth` | Drag toothbrush to `mouth`, then **scrub** — 3 short back-and-forth drags | `mouth` zone + gesture | `play_action("brush_teeth")` | `brush_loop` + foam particles, progress ring fills (not a timer — it only ever goes up) | `"Brush your teeth."` + brushing SFX; `"All clean!"` | `routine_step_completed("brushTeeth")` | 3 scrub strokes **or** 2.5 s held in zone | Holding still also completes it — the scrub is a delight, not a requirement. Today this is a plain `dragToBath` delivery and stays valid. | `EXTEND` |
| 18 | `wash` | Drag soap/water/towel to a body zone, or tap-and-circle | `bath`, `hands`, `face` zones | `play_action("wash")` | `scrub` + bubble particles; dirt decals fade | `"Wash your hands."` / `"Wash your face."` | `routine_step_completed("wash:<part>")` | All dirt decals in the target zone cleared, or 2 s in-zone | Single tap clears one decal — the circling gesture is optional polish. | `EXTEND` |
| 19 | `cleanUp` | Repeat `dragObjectToTarget` over a **set** of objects | `toyBox` / `shelf` / `basket` | `play_action("point")` / `celebrate` at the end | Per-object arc-to-zone; a "tidy" counter fills | `"Clean up!"` per item, `"All done!"` at the end | `set_completed(setId, count)` | Every object in `setId` delivered | This is a **loop wrapper over #6, not a new interaction**. Any remaining object can be assist-completed. The counter never counts *down*. | `EXTEND` |
| 20 | `hug` | Drag teddy (or a person) to `hug` zone | `hug` zone | `play_action("hug")` | `arms_wrap` + heart particle + `happy` | `"I love my teddy."` | `object_delivered("hug", objectId)` | Delivery into `hug` radius | Works today. Animation is the only upgrade. | `EXISTS` |
| 21 | `play` | Tap or drag a toy; ball-roll via flick | Toy objects, play zones | `play_action("play")` / `throw` / `kick` | `ball_roll` physics-lite tween, `clap`, `laugh` | Toy SFX + `"Let's play!"` / `"Throw the ball!"` | `play_beat(toyId, beatIndex)` | Any 3 play beats within the activity | Free-play safe: there is **no wrong move**. A tap alone always produces a delightful reaction. | `EXTEND` |

### 2.4 Language & social

| # | Interaction | Input | Target | Character action | Animation | Audio / TTS | Mission event | Success condition | Fallback | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 22 | `speak` | Mic button (bottom-right, ≥220 px) → on-device STT | Task `acceptedCommands` + `targetWords` | `play_action("listen")` then `happy` | Character leans in, ear-cue; mic button pulses while listening | Prompt `"Can you say milk?"`; success `"Yes! Milk!"` | `speech_matched(taskId, transcript)` | `IntentMatcher.matches()` true | **Always optional.** Mic denied/unavailable → button hidden, touch path completes the same star. Never a score, never "wrong pronunciation", 3 no-matches → assist. | `EXISTS` |
| 23 | `listenAndFind` | TTS asks, child taps the right object among 2–4 | `task.objectId` among distractors | `play_action("point")` on success | Correct object: pop + sparkle. Wrong: gentle wobble, stays on screen | `"Where is the milk?"` / `"Find the towel."` | `object_chosen(objectId)` → `task_completed` | Chosen id == `task.objectId` | Distractor count drops 4→3→2 on retries (auto-resolve ladder §1 Rule 3). Repeat-prompt button always available. | `EXISTS` |
| 24 | `greet` | Tap another character | Mom, Dad, teacher, friend | `play_action("wave")`, other replies | `wave` both sides, `happy` | `"Hello!"` / `"Good morning!"` / `"Nice to meet you."` | `social_beat(characterId, "greet")` | Wave animation finished on both | Tap always produces a reply, even with no animation — audio + face change is enough. | `NEW` |
| 25 | `chooseOption` | Tap 1 of 2–3 large cards (Bible §2 "choose simple options") | Option cards ≥220×220 px | `play_action("nod")` | Card scale-pop, unselected fade | Reads each option aloud on tap-and-hold; confirms on release | `option_chosen(promptId, optionId)` | Any option chosen | **No option is ever wrong** — used for outfit colour, breakfast, hobby, career. Always re-openable from the level menu. | `NEW` |
| 26 | `longPressHint` | Press-and-hold ≥600 ms on any object | Any object or the instruction bubble | — | Object glows, hint card slides in | Thai hint text; English word re-spoken. Thai TTS **off** by default. | `hint_requested(objectId)` | Hint shown | Only appears if `settings.thaiHints == true`. Never auto-triggers, never blocks, never affects stars. See `VOCABULARY_ROADMAP.md` §7. | `NEW` |
| 27 | `celebrate` | Automatic on task/level completion | — | `play_action("celebrate")` | `clap`/`jump` + confetti + star fly-in | `"Great job!"` + chime; sticker reveal on 3/3 | `task_completed` / `mission_completed` | — | Stars/stickers/save already work. Only the animation and the per-level 3-star summary card are new (Bible §5.1, §11). | `EXTEND` |

---

## 3. Parameterisation — how 27 rows stay ~6 scripts

### 3.1 The content schema (additive to today's task record)

Today's task record already carries `mode`, `objectId`, `targetWords`, `prompt`,
`instruction`, `repeatPrompt`, `acceptedCommands`, `thaiHint`, `interaction`, `reward`,
`difficulty`, `cooldown`. Add only these optional keys:

```json
{
  "taskId": "putTeddyOnBed",
  "mode": "followInstruction",
  "interaction": "dragObjectToTarget",
  "objectId": "teddy",
  "zoneId": "bed",
  "distractorIds": ["ball", "blocks"],
  "characterAction": "hug",
  "requiresWalkTo": "bedroomBedAnchor",
  "setId": null,
  "repeatCount": 1,
  "assistAfterAttempts": 3
}
```

| Key | Type | Default | Purpose |
| --- | --- | --- | --- |
| `zoneId` | String | derived from legacy `interaction` verb | Which `DropZone` accepts the object |
| `distractorIds` | Array | auto-picked by `TaskPicker` | Explicit control of `findIt` difficulty |
| `characterAction` | String | derived from object category | Semantic action played on success |
| `requiresWalkTo` | String | `""` | If set, character must `walk_to` before the activity arms |
| `setId` | String | `null` | Groups objects for `cleanUp`-style loops |
| `repeatCount` | int | `1` | Scrub strokes / play beats needed |
| `assistAfterAttempts` | int | `3` | Auto-resolve threshold (§1 Rule 3) |

Anything not listed keeps working unchanged — **43 existing tasks require zero edits**.

### 3.2 Zone registry (extend `DropZone.INTERACTION_TO_ZONE_ID`)

| Zone id | Status | Used by | Chapters |
| --- | --- | --- | --- |
| `mouth` | `EXISTS` | eat, drink, brushTeeth | 2, 3, 5 |
| `hug` | `EXISTS` | hug, comfort, bedtime teddy | 2, 3 |
| `bath` | `EXISTS` | wash, soap, towel | 2, 5 |
| `dress` | `EXISTS` | dress | 2, 3, 4, 5 |
| `toyBox` | `EXISTS` | cleanUp | 3, 6 |
| `hand` | `EXISTS` | give, carry handover | 4, 6 |
| `bed` | `NEW` | sleep, put teddy on bed | 1, 2, 5 |
| `shelf` | `NEW` | cleanUp variant, books | 3, 6 |
| `basket` | `NEW` | cleanUp variant, laundry | 3, 6 |
| `plate` | `NEW` | cooking, breakfast | 3, 6 |
| `hook` | `NEW` | school bag, coat | 4, 5 |
| `desk` | `NEW` | homework, art | 5, 7 |

Adding a zone is a **data + one anchor node** change. No script change.

### 3.3 The same interaction across three chapters (proof of Rule 1)

| Chapter | Level | Task | Interaction | Params |
| --- | --- | --- | --- | --- |
| 2 Baby Days | 6 Milk Time | Feed the bottle | `dragObjectToCharacter` | `objectId: milk`, `zoneId: mouth`, `characterAction: drink` |
| 3 Toddler | 14 Clean Up | Blocks in the box | `dragObjectToTarget` | `objectId: blocks`, `zoneId: toyBox`, `setId: toyRoomTidy` |
| 5 School | 21 Morning Routine | Hang the school bag | `dragObjectToTarget` | `objectId: backpack`, `zoneId: hook` |
| 6 Growing Skills | 27 Cooking | Fruit into the bowl | `dragObjectToTarget` | `objectId: banana`, `zoneId: plate`, `setId: fruitSalad` |

Four levels, four chapters, **one behaviour, four JSON records**.

---

## 4. Mobile UX considerations (per interaction family)

| Family | Requirement |
| --- | --- |
| All touch | Minimum grab target **220×220 px** (`ObjectSpawner.MIN_GRAB_PX`). Objects smaller on screen get an invisible enlarged collider, never a bigger mesh. |
| All drag | Latched pointer index — a second finger landing mid-drag must not hijack the object (already implemented; keep this invariant in every new draggable). |
| All drag | Drag resolves against a fixed `DragPlane`, not the mesh surface: no jitter when a finger crosses an object edge. |
| `tapToWalk` | 24 px move threshold distinguishes tap from drag (`TAP_MOVE_THRESHOLD_PX`). Taps inside the UI safe area never walk the character. Bottom 15% is reserved for the mic + menu, so a thumb resting there is not a walk command. |
| `tapToWalk` | Path is fully off-screen impossible: camera keeps the character framed; if a tap would send Buddy out of frame the camera pans, it does not cut. |
| `dragCharacterToActivity` | Character grab radius is larger than its silhouette (child fingers are imprecise). Drag never rotates the character mid-air. |
| `sit` / `sleep` | Both are exitable by a single tap anywhere. No modal state without an obvious exit. |
| `open` / `close` | Container contents spawn **towards the camera** so a hand does not occlude them. Contents inherit the 220 px floor. |
| `brushTeeth` / `wash` | Gesture-based, but the hold-still path always completes. Never require a rhythm or a speed. |
| `speak` | Mic button bottom-right, thumb-reachable in landscape on both iPad and iPhone; respects safe area (`game/scripts/ui/safe_area.gd`). Hidden entirely when unavailable — no disabled-grey teaser. |
| `longPressHint` | 600 ms is deliberately long so an accidental rest doesn't trigger it; a drag started within that window cancels the hint. |
| Frame budget | All interactions are tween/state-machine based. No per-frame physics simulation on iPhone; `carry` uses a socket reparent, not a joint. |
| Landscape-first | Every zone anchor must be authored to remain on-screen at 4:3 (iPad) and 19.5:9 (iPhone). |
| Interruptions | Any interaction must survive app backgrounding: state is re-entered on resume, never lost mid-drag. |

---

## 5. Semantic action registry

The animation layer must provide exactly these actions. Names are the public API used by
missions. (Bible §13 list, plus what this matrix actually calls.)

| Semantic action | Bible §13 group | Required by | Priority |
| --- | --- | --- | --- |
| `idle` | Locomotion | everything | **P0 slice** |
| `walk` | Locomotion | `tapToWalk`, `dragCharacterToActivity` | **P0 slice** |
| `walk_carry` | Locomotion | `carry` | P1 |
| `run` | Locomotion | Sports Day (L25) | P2 |
| `wave` | Body | `greet` | P1 |
| `point` | Body | `listenAndFind`, `cleanUp` | **P0 slice** |
| `clap` | Body | `celebrate` | **P0 slice** |
| `nod` | Body | `chooseOption` | P1 |
| `shake_head` | Body | gentle "not that one" (soft, never punitive) | P1 |
| `sit_down` / `sit_idle` / `stand_up` | Body | `sit` | P1 |
| `eat` | Care | `eat` | **P0 slice** |
| `drink` | Care | `drink` | **P0 slice** |
| `brush_teeth` | Care | `brushTeeth` | **P0 slice** |
| `wash` | Care | `wash` | **P0 slice** |
| `sleep` (`lie_down`, `sleep_idle`) | Care | `sleep` | **P0 slice** |
| `wake` (`sit_up`, `stretch`) | Care | `wake` | **P0 slice** |
| `hug` | Care | `hug` | P1 |
| `pick_up` | Care | `pickUp` | P1 |
| `hold` / `idle_carry` | Care | `carry` | P1 |
| `give` / `take` | Care | `give` | P1 |
| `dress` (`arms_up`) | Care | `dress` | **P0 slice** |
| `open` / `close` | Care | `open`, `close` | P1 |
| `play` / `throw` | Care | `play` | P1 |
| `celebrate` | Emotion | `celebrate` | **P0 slice** |
| `happy` | Emotion | success everywhere | **P0 slice** |
| `excited` | Emotion | sticker unlock | P1 |
| `sleepy` | Emotion | bedtime prompt | **P0 slice** |
| `hungry` | Emotion | feeding prompt | **P0 slice** |
| `surprised` | Emotion | discovery beats | P2 |
| `listen` | Emotion | `speak` | P1 |
| `look_at` | Body (procedural) | `tapObject` — head/eye aim, not a clip | P1 |

**P0 slice = 16 actions.** That is the animation order for "A Day With Little Buddy"
(Bible §20 Phase B). P1 (13) follows; P2 (2) is optional polish.

**Contract:** `CharacterRig.play_action(name: String, params: Dictionary = {}) -> void`,
signal `action_finished(name: String)`. Unknown name → `idle` + warn once + emit
`action_finished` on the next frame. Emotions are an **additive layer** over locomotion,
not a separate state, so `walk` + `happy` compose.

---

## 6. Mission event vocabulary

New events the mission layer may listen for. `MissionRunner`'s existing signals
(`task_started`, `task_completed`, `task_skipped`, `mission_completed`,
`prompt_changed`, `encouragement`, `speak_button_enabled`) stay unchanged.

| Event | Emitted by | Payload | New? |
| --- | --- | --- | --- |
| `object_chosen` | `DraggableObject` → `ModeHandler` | `objectId` | exists |
| `object_delivered` | `DropZone` | `zoneId`, `objectId` | exists (add `zoneId`) |
| `character_arrived` | `CharacterController` | `targetId` | `NEW` |
| `character_state_changed` | `CharacterController` | `state` | `NEW` |
| `object_picked_up` / `object_dropped` | `CharacterController` | `objectId` | `NEW` |
| `object_given` | `CharacterController` | `fromId`, `toId`, `objectId` | `NEW` |
| `container_opened` / `container_closed` | `Container` | `containerId` | `NEW` |
| `routine_step_completed` | `ModeHandler` | `stepId` | `NEW` |
| `set_completed` | `ModeHandler` | `setId`, `count` | `NEW` |
| `need_satisfied` | `BabyState` (extend) | `needId`, `amount` | `EXTEND` |
| `social_beat` | `CharacterController` | `characterId`, `beatId` | `NEW` |
| `option_chosen` | `OptionCards` | `promptId`, `optionId` | `NEW` |
| `hint_requested` | `HintLayer` | `objectId` | `NEW` |
| `speech_matched` | `SayItMode` | `taskId`, `transcript` | exists (rename for clarity) |

**Rule:** mission scripts subscribe to these events only. They never poll transforms,
never read animation state, never touch a `DropZone` node directly.

---

## 7. Build order

| Wave | Contents | Unblocks |
| --- | --- | --- |
| **W0 — today** | #4, #5, #6, #16, #20, #22, #23 (`EXISTS`) | 43 tasks, 5 missions, already shipping |
| **W1 — movement core** | `CharacterController` (`CharacterBody3D` + `NavigationAgent3D`) + `CharacterRig.play_action` + #1, #2, #15 | The entire vertical slice |
| **W2 — routine actions** | #12, #13, #14, #17, #18, #27 + P0 animations | "A Day With Little Buddy" end-to-end |
| **W3 — object handling** | #3, #7, #8, #10, #11, #19 | Chapters 3–4, cooking, cleanup |
| **W4 — social & choice** | #9, #21, #24, #25, #26 | Chapters 4–6, hobby/career choice |

W1 is the single biggest risk in the project: it is the only wave with **zero** existing
code to build on.

---

## 8. Open questions / Bible ambiguities

Flagged rather than silently decided.

1. **Who walks — Little Buddy or Big Buddy?** §6 says "Little Buddy must be able to move"
   and §12's flow is "Player taps fridge → Little Buddy walks to fridge", but §2.2 says
   the player's actions include "move Little Buddy". This matrix assumes **the player
   never has an avatar body; taps command Little Buddy**. If Big Buddy later gets an
   avatar, `tapToWalk` needs a `subjectId` parameter. Confirm before W1.
2. **Chapter 1 has no Little Buddy yet** (pre-birth). Mom/Dad must therefore use the same
   `CharacterController`. This matrix assumes the controller is **character-agnostic from
   day one** — do not special-case Little Buddy.
3. **`sit` vs. activity anchors.** §12 lists `Sit` as a movement state and §13 lists `sit`
   as a body animation. Treated here as one thing: a `Navigable` zone tagged `seat`.
4. **Ball physics.** §13 has no `kick`/`throw` receiver spec, and Sports Day (L25) implies
   throwing and catching. This matrix keeps `play` tween-based (no rigid-body simulation)
   for iPhone frame budget. If real ball physics is wanted, that is a separate decision.
5. **Free-play "no wrong answer" vs. mission mode.** §9 says no quiz popup in sandbox;
   §10 needs a correct answer in missions. Resolved here as a mode flag on the room:
   `freePlay = true` disables all `task_failed_gently` paths. Confirm this is the intent.
6. **Star 2 requires "an English listening/recognition task"** (§5.1) but §5.2's example
   makes star 3 the speech star. This matrix assumes: star 1 = do it, star 2 = hear it
   (`findIt`), star 3 = say it **or** the optional exploration/care task, whichever the
   level defines. `LEVEL_MATRIX.md` owns the final rule.
7. **Scope realism.** 27 interactions × 40 levels × 9 chapters is a multi-year scope at
   this fidelity. The matrix is deliberately built so Chapters 1–3 need only W0–W2.
   Recommend locking the vertical slice against W0–W2 and treating W3–W4 as post-slice.

---

## 9. Deliberately out of scope here

Owned by the parallel design docs: chapter/level sequencing and star rules
(`STORY_MAP.md`, `LEVEL_MATRIX.md`); age-stage models, rigs and proportions
(`CHARACTER_AGE_STAGES.md`, `ART_BIBLE_DRAFT.md`); node structure, autoload and save
schema changes (`ARCHITECTURE`); per-word progression (`VOCABULARY_ROADMAP.md`).
