# Aliz gestures (wt8/gesture, 2026-09-22)

The complete upper-body gesture set on Aliz's existing rig, the event → gesture
pool the tutor scene draws from, and the enum that carries gesture names between
the lesson engine, the Worker and the face. Companion to `docs/ALIZ_TUTOR_FACE.md`
(expressions, mouth, lip sync) and `docs/ALIZ_TUTOR_CONTRACTS.md` (the TutorTurn
schema).

Nothing here touches the mesh, the rig or the repaired hair: every gesture is a
procedural clip (`game/scripts/characters/buddy/buddy_gesture_clips.gd`) played on
the upper-body `SkeletonModifier3D` layer (`buddy_gesture_layer.gd`) over the idle,
so the breath, the blink and the hair sway keep running underneath.

## The gestures

| name | duration | what moves | reads as |
|---|---|---|---|
| `nod` | 0.9 s | head + neck, two 12 degree dips | yes / good |
| `tilt` | 1.2 s | head 9 + neck 3 degrees of roll, held | curious |
| `point` | 1.4 s | right arm forward and across to camera-right, head follows | look at the board |
| `clap` | 1.1 s | both forearms up, hands pulse inward twice | applause |
| `wave` | 1.3 s | right arm up and out, forearm and hand swing four times | hello / goodbye |
| `thumbsUp` | 1.1 s | right forearm folds up, fist at chin height in front of the shoulder, pumps twice, head dips with it | well done |
| `celebrate` | 1.6 s | both arms up in a V beside the hair, hips hop 2.5 cm twice, spine and head pump | hooray |
| `listening` | 1.4 s | the attentive lean (spine 6 degrees over three bones), head tilted 8 degrees, hands still | I'm listening |
| `thinking` | 1.6 s | right hand up under the chin, head rolled 7 degrees toward it and lifted 4; the `thinking` tutor state adds the `eyesUpLeft` glance for the hold | hmm |
| `encourage` | 1.2 s | right forearm opens outward, palm to the child, one small nod while it is held | go on, try |

Poses were measured on the rig against the head/hair mesh (head + hair spans
x ±30, front z ≤ 23 cm at face height; the fringe front is z 15 at the chin):
the thumbs-up fist lands at (−26, 104, 21) cm, the thinking hand at (−9, 98, 23),
the encourage palm at (−29, 98, 24), the celebrate hands at (±38, 133, 8), all
outside the hair. `docs/shots/aliz_tutor_gesture_sheet.png` is the ten strips
(five frames each at 10/30/50/70/90 % of the clip) from `tools/aliz_tutor_shots.gd`.

There are no finger bones on this rig, so "thumbs up" is the raised fist's
silhouette; the gaze of `thinking` is a face overlay, not an eye bone.

### Timing and layering rules

* Every gesture has a fixed duration (`GestureClips.DURATIONS`), returned by
  `play_gesture(name)`; it fades in over 0.12 s and out over the last 0.2 s and
  hands every bone back to the pose underneath (rest + idle), measured to
  0.1 degrees / 0.1 cm in `test_aliz_tutor_face.gd`.
* Two gestures never overlap. `play_gesture()` over a running gesture moves the
  old one to a single OUTGOING slot that fades to 0 over 0.2 s (its clock still
  running) while the new one fades in: a cross-fade, never a snap to rest and
  back up. A third call inside that window drops the outgoing one on the spot.
* A state change interrupts: `idle` and `interrupted` stop the gesture (0.2 s
  fade); `listening` stops any ARM gesture so the hands are still (the head is
  free); the other states start their own entry gesture, which cross-fades.
* Arm gestures (`point`, `clap`, `wave`, `thumbsUp`, `celebrate`, `thinking`,
  `encourage`, and the micro beats) are refused while the carry pose holds the
  arms; every gesture is refused above 0.1 m/s of locomotion.
* The lip sync, the blink and the expression compositor never see a gesture;
  `set_expression()` mid-gesture leaves the gesture running (tested).

## Composite tutor states → poses

`set_tutor_state(name)` (`buddy_tutor_state.gd`):

| state | expression | gesture on entry | notes |
|---|---|---|---|
| `idle` | neutral | none (stops a running one) | |
| `listening` | listening | none; held listening posture (lean + 8 degree head tilt); arm gestures stopped | looks at the attention target |
| `thinking` | thinking | `thinking` | `eyesUpLeft` overlay from 0.2 s to 1.3 s |
| `speaking` | smile | none; beats every ~3 s | brows / glance overlays, talk head motion |
| `interrupted` | listening | stops the gesture inside 200 ms | mouth 0 inside 120 ms, turns to the child |
| `happy` | happy | half `nod` | |
| `encouraging` | encouraging | `encourage` | |
| `explaining` | smile | `point`, then half nods every ~2.5 s | |
| `celebrating` | happy | `celebrate` | `wants_sfx("laugh")` once |

## TutorGesturePool (`game/scripts/tutor/tutor_gesture_pool.gd`)

Pure and static. `pick(event, seed) -> String`, `expression_for(event) -> String`,
`reward_hook_for(event) -> String`, `positive_event(streak, lesson_complete) -> String`.

| event | pool (walk order) | expression | reward hook | when |
|---|---|---|---|---|
| `correct` | `thumbsUp`, `clap`, `nod` (+ the `happy` face = nod + smile) | happy | | a correct answer |
| `excellent` | `celebrate` | happy | `confetti` | `positive_event()`: three correct in a row, or the lesson complete |
| `greeting` | `wave` | smile | | the welcome |
| `listening` | `listening` | listening | | mic open |
| `thinking` | `thinking` | thinking | | waiting on the provider |
| `encourage` | `encourage` | encouraging | | wrong answer / retry |
| `farewell` | `wave` | happy | | end of the session |

Variety rule: for a pool of more than one gesture the pick is deterministic in the
seed and never equals the pick for `seed − 1`, whatever the seed sequence (the walk
is `seed × stride mod N` with a stride coprime with N and ≠ 0 mod N; for the pool
of three the stride is 2). With the step index as the seed, `correct` over steps
0, 1, 2, 3, 4, 5 gives `thumbsUp, nod, clap, thumbsUp, nod, clap`. An unknown event
gives `none` / `neutral` / `""`.

### Integration (the lead wires this into `tutor_scene.gd::_speak_turn`)

```gdscript
const TutorGesturePool := preload("res://scripts/tutor/tutor_gesture_pool.gd")
# on a correct answer, with the streak the scene already counts:
var event: String = TutorGesturePool.positive_event(_correct_streak, lesson_complete)
_face(TutorGesturePool.expression_for(event))
_gesture(TutorGesturePool.pick(event, step_index))
if TutorGesturePool.reward_hook_for(event) == "confetti":
    _play_reward()   # the scene's own hook
```

A scripted or cloud turn may still name its gesture directly (`turn.gesture`); the
pool is for the scene-driven beats (answer feedback, greeting, listening, thinking),
where the turn carries `none` or the scene wants variety.

## Enum parity

The gesture enum lives in four places and `test_tutor_gesture_pool.gd` holds them
equal (it reads the Worker files as text):

| where | list |
|---|---|
| `game/scripts/tutor/turn/tutor_turn.gd::GESTURES` | none, nod, tilt, point, clap, wave, thumbsUp, celebrate, listening, thinking, encourage |
| `game/scripts/characters/buddy/buddy_gesture_clips.gd::GESTURE_NAMES` | the same minus `none` |
| `game/content/tutor/turn_fixtures.json` | a valid case per member (five added 2026-09-22) |
| `cloud/src/tutor/turn_validator.ts::GESTURES` + `types.ts::Gesture` + `test/validator.test.ts` | the same eleven |

All additive: the five contract gestures and their fixtures are untouched; an
older Worker that only knows the first six still validates every turn the client
sends, and a client that receives an unknown gesture falls back to `none`.

## Evidence

* `game/tests/cases/test_aliz_tutor_face.gd`: every gesture resolves, moves the
  bones it names (measured mid-clip on the real skeleton), finishes inside its
  duration, fades to 0 and returns head / hands / hips to rest; the cross-fade
  handover (a clap over a wave never drops the hand below 35 % of its lift, the
  wave is gone in 200 ms); 300 interrupt combinations (10 × 10 gestures × three
  cut points, a third call inside the window, then stop or `idle`) back to rest;
  `listening` stops an arm gesture; `thinking` shows and clears the glance.
* `game/tests/cases/test_tutor_gesture_pool.gd`: the table, no consecutive repeat
  over 220 seeds, determinism, full coverage of each pool, `positive_event`, every
  pool name is a real clip and an enum member, four-way enum parity.
* `cloud/test/validator.test.ts`: 49 vitest cases green with the extended enum;
  `tsc --noEmit` clean.
* `docs/shots/aliz_tutor_gesture_sheet.png` (+ `aliz_tutor_gesture_<name>_strip.png`,
  `aliz_tutor_state_celebrating_strip.png`), rendered on the Mac with the Mobile
  renderer, checked by eye: nothing enters the hair or the face.
