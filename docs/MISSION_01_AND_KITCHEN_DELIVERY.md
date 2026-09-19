# Mission 01 + Interactive Kitchen — delivery report

Branch `feature/overnight-production-candidate`. Sprint of 2026-09-19.

**Meshy credits spent this sprint: 0 of the 100 authorised.** See §6 for why, and
what is ready to go the moment it is unblocked.

---

## 1. The blocker is gone — and it was not where it was reported

The previous pass reported that beats reached `_task_done = true` but the runner
never advanced, and called it a director/runner handoff defect. That diagnosis
was wrong, and finding out how it was wrong took three separate fixes to the test
harness before the production code could even be judged:

1. **A frame-counted wait against a real-time gap.** `MissionRunner._delay()`
   uses `create_timer(1.6)` — 1.6 *real* seconds. A headless main loop runs flat
   out, so "wait 180 frames" expired in a fraction of that, and every beat looked
   stuck. Five of seven beats chained the moment this was fixed.
2. **Travel driven through the wrong signal.** Walking through a door does not
   raise `interaction_ready` — the handler returns early for travel plans on
   purpose, because the transition controller intercepts it.
3. **A deliver beat with nothing delivered.** `cuddleBunny` needs an object in a
   zone; nothing was putting one there.

No production behaviour was changed to make the milk mission pass, and no
QA-only completion path exists. Every input the harness uses is an entry point
normal gameplay already uses — `RoomTransitionController.request_transition()`,
`MissionRunner.on_object_chosen()` — and the director still decides what each
one means.

### Two real production bugs *were* found, by playing the second mission

* **A beat could hang forever.** `_awaiting_action` parks a beat until the
  character reports its action finished, and that report never arrives when an
  action is requested while a held pose (`hold`, `sit`, `sleep`) is still in
  effect. "Pick up the snack" and "tidy up" both hung, leaving the child at the
  counter with no way forward. The wait is now bounded by the action's own
  semantic duration plus a margin, read from `character_action_driver.gd`. A real
  signal still wins. This is the project's own no-dead-ends rule applied to the
  one place that could stall.
* **Feeding did not feed.** `give_to_bunny()` emptied Aliz's hands and said
  "Yum!" while Bunny's hunger sat exactly where it started — a mission about a
  need that the need never noticed. It now moves the real `ChildStats`.

---

## 2. Mission 01 — DONE, proven end to end

`tests/smoke_mission01.gd` runs the real `house_world.tscn`, lets the real
director pick a mission the way a fresh install does, and walks every beat. It
never calls a completion method; care acts finish by real gestures on the real
overlay. **It exits 0.**

```
=== proving mission 'imHungry' ===
1. fresh profile opened: imHungry
2. Bunny before: hunger 55.0, happiness 70.0
   beat 1: bunnyIsHungry      goAndDo  bedroom
   beat 2: goToKitchen        travel   bedroom
   beat 3: findBottle         goAndDo  kitchen
   beat 4: prepareMilkCare    care     kitchen   prepareMilk
   beat 5: carryMilkToBunny   travel   kitchen
   beat 6: feedBunnyCare      care     bedroom   giveBottle
   beat 7: cuddleBunny        deliver  bedroom
3. beats played: 7, care mini-games finished by gesture: 2
4. Bunny's hunger after: 0.0 (was 55.0)
   Bunny's happiness: 70.0 -> 78.0
5. mission_completed fired 1 time(s); tasks awarded: 7
6. saved: completed=true stars=3/3  lifetime stars=10
7. replay re-armed 'imHungry'; lifetime stars still 10
SMOKE PASS
```

Every line of the required journey is covered: hungry Bunny → acknowledge →
kitchen → bottle → prepare → carry → feed → Bunny happier → complete → stars and
save. The award check counts **signals**, not a final total, because a total
cannot distinguish one award from two that cancelled out.

### Replay Mission 01 — safe

In Parent Settings, behind the existing parental gate. It does *not* reset the
profile. Cleared: that level's completion, its rating, and the resume pointer.
Untouched: the lifetime star total, every other level, settings, unlocks. The
smoke run asserts this on a live profile; `test_mission_replay.gd` asserts each
protected key by name on a profile holding a fortnight of progress.

`stars` deliberately does not go *down*. Taking a child's stars away because a
grown-up pressed a test button is the punishment the child-UX rules exist to
prevent.

---

## 3. The interactive kitchen — DONE

Adapted from `KaganAyten/RestaurantGame3DUnity` (MIT, verified via the GitHub
API). Mechanics only — that project is Unity/C#, this is Godot/GDScript, and no
source was copied. Full analysis, including the bundled **DOTween** and
**TextMesh Pro / EmojiOne** which its MIT licence does *not* cover and which are
**not** in this project, is in `docs/THIRD_PARTY_NOTICES.md`.

| Layer | File | Holds |
|---|---|---|
| Nouns | `kitchen_items.gd` | items as DATA — each carries its English word, its Thai and its silhouette |
| Rules | `kitchen_rules.gd` | what may be taken, placed, combined; refusals as kind sentences |
| State | `kitchen_state.gd` | the verbs, and the only source of truth |
| View | `kitchen_view.gd` | renders that state and holds none of its own |

All eleven requested interactions exist, collapsed into four verbs —
`open`/`take`/`place`/`give`. To a child there is one action, *put what you are
holding onto the thing in front of you*; working out what it **means**
(place / combine / prepare / serve / put away) is the kitchen's job, not theirs.

### Three bugs the screenshots caught that the tests could not

The brief's refusal to accept unit tests as proof was correct, and here is the
evidence:

1. **The fridge door swung the wrong way** — into the back wall. It opened
   correctly, invisibly, every single time.
2. **Fridge contents were built inside a solid mesh** — right item, right place,
   completely unseeable.
3. **Carrying broke at the door.** The carried item lived under the kitchen room,
   and rooms hide when the child leaves them, so food vanished exactly at the
   beat where carrying matters. It is now parented to Aliz.

### Proof — `docs/shots/kitchen_*.png`

Produced by `tests/shots_kitchen.gd`, which drives the real house and **fails if
any verb is refused**, so a picture can never show a step that did not happen.

| Shot | Shows |
|---|---|
| `kitchen_1_arrive` | the kitchen as the child finds it |
| `kitchen_2_fridge_open` | door swung open, food visible on the shelf |
| `kitchen_3_take_banana` | banana **gone from the fridge**, apple and bottle still there |
| `kitchen_4_on_counter` | banana resting on the counter |
| `kitchen_5_take_spoon` | spoon in hand, banana still on the counter |
| `kitchen_6_transformed` | two ingredients became one bowl of food |
| `kitchen_7_served` | served on the table |
| `kitchen_8_to_bunny` | carried **into another room**, Bunny hungry |
| `kitchen_9_fridge_closed` | door closed again |

---

## 4. Snack Time — the second path — DONE and reachable

A task may now name `kitchenVerb` + `kitchenItem`. Two plain strings,
deliberately **not** a new task kind: walking to the fridge and opening it is
still `goAndDo`, and a new kind would have forced a parallel mission engine.
The kitchen decides whether a beat happened; refuse it and the beat stays open
and the child is told why.

`snackTime` is in the `ch3` chain, second, and plays through normal progression:

```
=== proving mission 'snackTime' ===
1. fresh profile opened: snackTime
   beat 1: openTheFridge     beat 5: mashTheBanana
   beat 2: takeTheBanana     beat 6: carrySnackToBunny
   beat 3: bananaOnCounter   beat 7: feedBunnySnack
   beat 4: takeTheSpoon      beat 8: tidyTheSpoon
3. beats played: 8
4. Bunny's hunger after: 0.0 (was 55.0)
5. mission_completed fired 1 time(s); tasks awarded: 8
6. saved: completed=true stars=3/3
SMOKE PASS
```

It is proven by exactly the process that proved the milk path — the same harness,
parameterised by mission — and it reaches the mission through normal progression
by marking the earlier chain level played. Nothing inside the mission under test
is skipped.

No customers, no income, no countdown, no failure punishment.

---

## 5. Chapter 3 now

| # | levelId | Mission |
|---|---|---|
| L11 | `imHungry` | I'm Hungry! (milk) |
| L12 | `snackTime` | Snack Time! (cooking) |
| L13–L17 | `goodMorning` … `tidyAndBed` | unchanged, five display numbers later |

Nothing was deleted. `levelNumber` is read only by `level_definition.gd`, so the
renumbering renames no save key, mission id, scene path or resource id.

---

## 6. NOT DONE — reported separately, as required

### Aliz regeneration — BLOCKED on one thing, and it is not a decision

`MESHY_API_KEY` is **not present in this environment**, so no Meshy call of any
kind could be made. Zero credits of the 100 authorised were spent. To unblock:

```
export MESHY_API_KEY=...        # in your shell, before launching
```

(Type it with a leading `!` in the prompt, or set it and restart the session. Do
not paste the key into the conversation.)

**The zero-credit preparation §9 asks for is done.** There was no clean
standalone Aliz reference image in the repo, so one was made from the shipping
model — which preserves her identity exactly rather than approximating it — and
then corrected in 2D:

`docs/reference/aliz_reference_v1.png` (`tools/make_aliz_reference.py`)

* single character, front-facing, full body, plain white field ✅
* pink hair with bangs, large expressive eyes, striped outfit ✅ — unmodified
* **gentle closed-mouth smile** ✅ — the grin painted out and a soft arc drawn
* **continuous hair silhouette, no holes** ✅ — the torn fringe and the hole at
  the right temple filled from the nearest hair above, so the shading survives
* **A-pose** ❌ — not obtainable from a model whose arms are down. This must come
  from the generation prompt, with the image supplying identity.

Doing this in 2D rather than on the mesh was the point: the model's UV atlas is
fragmented into dozens of interleaved islands, and an earlier attempt to edit it
kept selecting leg and dress vertices along with the face. In a flat render the
mouth is an unambiguous rectangle of pixels.

A previous session also **disproved** the easy explanation for the hair: setting
the material double-sided changed nothing, so the gaps are modelled holes, not
back-face culling. That change was reverted rather than kept.

The replacement gate in §11 (front/side/back, rigging, skinning, walk, RigProfile,
mobile budget, iOS packaging, old-versus-new comparison shots at the real
gameplay camera) is **untouched** and the current model remains in production.

### Camera and mini-game framing (§12) — NOT DONE

Still the single wide room shot. Held items are drawn 1.55× while carried, which
was enough to make "what am I holding?" answerable at the house camera, but the
per-beat framing the section asks for — close on the bottle during preparation,
on Bunny during feeding — is not implemented.

### Kitchen beautification (§6 of the brief) — PARTIAL

The kitchen has a working fridge, counter and table with real food on them. The
layout, lighting and prop density were not redesigned.

### Bottle Dash — correctly not started (§13).

---

## 7. Regression gates

| Gate | Result |
|---|---|
| Full test suite | **101/101**, 0 failures |
| ContentValidator | clean (runs inside the suite) |
| Clean project load | no parse errors |
| Mission 01 smoke (`imHungry`) | **PASS**, exit 0 |
| Cooking smoke (`snackTime`) | **PASS**, exit 0 |
| Kitchen shot harness | **PASS**, 9 shots |
| iOS export | **OK** |
| arm64 Xcode build | **BUILD SUCCEEDED** |

Preserved and unchanged: existing saves, the `MissionRunner` architecture, Aliz's
locomotion, Bunny's state system, the speech plugin, touch fallback, joystick,
iOS signing, universal iPhone/iPad, landscape.

---

## 8. What I would do next, in order

1. **Unblock Meshy** and run the Aliz experiment against the prepared reference —
   one image-to-3D with an A-pose prompt, then rigging. Everything else in §9–11
   is ready.
2. **Per-beat camera framing** (§12) — the largest remaining gap between "it
   works" and "it reads".
3. **Play both missions on the physical iPad.** Everything above is verified on a
   Mac; the 3-minute acceptance walk has not been run on device, and I am not
   claiming it has.
