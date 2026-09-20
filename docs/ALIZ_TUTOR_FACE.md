# Aliz — tutor face: expressions, talking mouth, lip sync, gestures (2026-09-20)

**Zero Meshy credits. Mesh, base atlas (md5 `b664e98c…`), GLB and the six probe texels
untouched; walk/run/idle/carry/blink/moods unchanged.** Implements the `TutorFace`
contract in `docs/ALIZ_TUTOR_CONTRACTS.md` on `pink_girl_buddy.gd` (API documented at
the top of that file). Follows `ALIZ_FACE_PASS.md`. Branch `wt4/face`.

| Evidence | File |
|---|---|
| Six expressions at the tutor camera, 1:1 over 3x of the eyes and mouth | `docs/shots/aliz_tutor_expressions_sheet.png` (cells `aliz_tutor_expr_<name>.png`) |
| Four mouth frames over `neutral`, 1:1 over 3x | `docs/shots/aliz_tutor_mouth_sheet.png` (cells `aliz_tutor_mouth_<n>.png`) |
| Six frames of the mouth during a two-syllable synthetic envelope, 2x | `docs/shots/aliz_tutor_envelope_strip.png` (cells `aliz_tutor_env_<n>.png`) |
| Five frames per gesture on the real model, 10/30/50/70/90 % of the clip | `docs/shots/aliz_tutor_gesture_<nod,tilt,point,clap,wave>_strip.png` |
| Composite states, five frames at 0 / 0.15 / 0.4 / 0.9 / 1.6 s after entry, body over face | `docs/shots/aliz_tutor_state_<interrupted,explaining,celebrating>_strip.png` |
| Atlas-side proof the patches land on the right texels (frames over `neutral` AND over `happy`) | `tools/aliz_mouth_frames.py` → `<prefix>_expressions.png`, `_mouth_frames.png`, `_mouth_on_happy.png` |
| Headless prints: mouth amounts vs envelope, lip sync amounts vs tone, gesture bone deltas | `test_aliz_tutor_face.gd` (§5 below) |

## 1. Expressions — `tools/aliz_expression_pass.py`, `buddy_face.gd`

The TutorTurn emotions are **more moods in the same manifest** as `content/happy/
surprised/sleepy`, so `set_expression()` is `set_face()` with the contract's names on
it, one channel, and the blink still overlays. Painted from the shipping base atlas in
model metres through the same guarded claim map every Aliz repaint has used; the tool
refuses to run if the atlas md5 is not the manifest's.

| expression | layers | what it is |
|---|---|---|
| `neutral` | — | the base (texel-identical to `content`) |
| `listening` | `eyesWide` + `browsUp` | everything above the iris centre moved 5 mm up (the upper lash line rises, more sclera shows), brows lifted 8 mm |
| `thinking` | `eyesUpLeft` + `mouthSmall` | the iris **outline** moved 8 mm up and toward the viewer's left (sclera fills where it left, the rim is redrawn where it arrived; the iris paint itself stays), a 32 × 6 mm nearly flat mouth |
| `happy` | `mouthOpen` | the existing open smile |
| `encouraging` | `browsUp` + `mouthSoft` | brows lifted, an 84 × 20 mm open smile with no teeth |
| `smile` | `mouthSmile` | a 108 mm closed grin, corners up 20 mm |

Why the eyes are moved rather than drawn: the eyes are the generator's paint, and a
redrawn eye would be a different pair of eyes from the resting face. The first version
resampled the eye texels through the head-on render; on the fragmented eye islands an
8 mm shift is a non-integer texel step per island and the highlight turned into confetti
(`thinking_zoom`, discarded). The shipped version moves only the iris *outline*, feathered,
with the rim a step lighter than the darkest rim texel so a 4 mm-texel ring does not
stair-step. **Residue:** at 3x the moved outline is still visibly texel-stepped; at the
tutor distance it reads as a glance. It is the atlas' 2.5 texels/cm, not fixable by paint.

Colours: `LIP` (206, 104, 100) for lips, `MOUTH_IN` (150, 58, 64) inside. No teeth on
anything new (art bible §4).

## 2. The talking mouth — `buddy_mouth.gd`, `buddy_face.gd`

No blend shapes, so the mouth is four texture frames: **closed** (= the expression's own
mouth, no layer), **small** 48 × 13 mm, **mid** 62 × 24 mm, **open** 72 × 38 mm, rounded,
corners lifted 3–5 mm, same rose, no teeth. A frame's patch carries alpha 255 over the
**union of every mouth layer's footprint** (1,859 texels, gutter included), so laid over
`happy` it replaces the teeth completely (`_mouth_on_happy.png`); at amount 0 the frame
is simply not applied and the expression's mouth is back to the texel (asserted).

`buddy_mouth.gd` (a `Node` under `Model`, `_process` off while shut) turns the target
amount into a frame: linear slew **attack 40 ms** shut→open, **release 90 ms** open→shut;
frames open at 0.08 / 0.30 / 0.60 with 0.03 hysteresis; **no frame change within 40 ms
of the last — except a change to closed**, which is always allowed, because a mouth left
open after the voice stopped is the visible bug and a frame held a few ms long is not.
`set_speaking(false)` closes at once. Measured (headless, 60 Hz steps, full-scale ramp
over 0.3 s, hold, then silence at 0.75 s):

```
t=0.050s target 0.11 amount 0.11 frame 1      frame changes:
t=0.150s target 0.44 amount 0.44 frame 2        0.050 s -> 1
t=0.200s target 0.61 amount 0.61 frame 3        0.117 s -> 2
t=0.750s target 1.00 amount 1.00 frame 3        0.200 s -> 3
t=0.800s target 0.00 amount 0.44 frame 2        0.800 s -> 2
t=0.850s target 0.00 amount 0.00 frame 0        0.850 s -> 0   (closed 100 ms after silence)
```

Compositing cost: `buddy_face.gd` now blends each layer's **island rects** (15 for a mouth
layer, ~1.9 k texels) instead of its 503 × 496 bounding box, so a frame change is one
1 MB `copy_from`, a few thousand texel blends, mipmaps and one upload. Existing layers got
island rects too (manifest metadata only; their PNGs are unchanged).

## 3. Lip sync source — `buddy_lip_sync.gd` (`LipSyncSource`)

`attach(player)` / `attach_bus(name)` add an `AudioEffectCapture` to the bus (reusing one
already there); every frame the captured frames' RMS is normalised by a **slow AGC** (peak
decays to 45 % per second, floor 0.03 full scale) and gated at 0.10, curve 0.7 → amount.
When the attached player is not playing the amount is forced to 0 at once; the mouth's
90 ms release then shuts it inside the 120 ms the contract allows. `detach()` removes
the effect (asserted: effect count restored). **Never a fixed timer** (asserted: no
`Timer` child; the mouth is only ever moved through `set_mouth_open`).

`drive_from_envelope(samples, sample_rate)` pushes a mono buffer through the same
pipeline in 1/60 s chunks, stepping the mouth. Five quiet syllable bumps (peak **0.05**
full scale, 220 Hz, 120 ms on / 60 ms off from 0.30 s):

```
0.30:0.00 0.35:1.00 0.40:0.10 0.45:0.00 0.50:0.44 0.55:0.70 0.60:0.00
0.70:1.00 0.75:0.38 0.80:0.00 0.85:0.24 0.90:0.90 0.95:0.00 1.05:0.79 1.10:0.64 1.15:0.00 ...
```

Silence in → 0; each bump's crest above its foot and the gap after it lower; a 0.05
voice opens the mouth fully (AGC); zero within 120 ms of the last sound.

**The honest fallback — platform TTS.** `attach_tts()` follows `TtsService`'s
`speech_started(text)` / `speech_finished(text)`. There is no stream in the engine to
capture from the native synthesiser, so between the two signals the source plays a
**syllable-rate pseudo-envelope derived from the text**: one raised-cosine bump per vowel
group at 3.75 syllables/s (TtsService's 2.5 words/s × ~1.5) divided by the speech rate,
60 ms at each space, 220 ms at punctuation, bump heights 0.55–1.0 chosen by the letters
(not a metronome — asserted). It is timed from the text, not measured from the sound,
and this document and the file both say so. It still stops with the audio:
`speech_finished` or `is_speaking()` going false zeroes it. When the service is playing a
**recorded** line through its own player on the Voice bus, a captured bus wins over the
pseudo-envelope. `"Can you say milk?"` → 1.6 s, five bumps.

## 4. Head and hands — `buddy_gesture_clips.gd`, `buddy_gesture_layer.gd`

Five clips authored as ordinary `Animation`s on the real skeleton (rotation tracks,
absolute poses = rest ∘ turns, same arithmetic as the idle) and played by an **upper-body
layer**: a `SkeletonModifier3D` under the skeleton (order: `CarryPose`, `GestureLayer`,
`HairSway`) that samples the clip each frame and pre-multiplies each keyed bone's
delta-from-rest onto the bone's **current** pose. So the idle's breath keeps going
underneath, a seated pose keeps its arms until asked, and the clips are deliberately *not*
merged into the `AnimationPlayer` (through it a gesture would replace the idle wholesale).
Fade in 0.12 s, out 0.2 s (also from `stop()`); **refused above 0.1 m/s** and faded out
if she moves off mid-gesture; arm gestures refused while the carry pose holds the arms
(the head is free).

| gesture | s | what moves | measured mid-clip |
|---|---|---|---|
| `nod` | 0.9 | two dips, head 8.4° + neck 3.6° | head pitch +12.0° at 0.20 s, hands still |
| `tilt` | 1.2 | 9° head + 3° neck roll, held, back | head roll +12.0° at 0.55 s |
| `point` | 1.4 | right arm forward 82° and across 58° toward camera-right (she faces the child, so camera-right is *her* left, where the board sits), head turned 12° the same way | right hand +32 cm up, +36 cm across; left hand still |
| `clap` | 1.1 | both arms forward 58°, forearms up 62°, hands pulse inward at 0.35 s and 0.70 s | both hands +33 cm; separation varies > 4 cm |
| `wave` | 1.3 | right arm forward 60° and out 45°, forearm up 75°, four swings | right hand +40 cm up, 17 cm out; sweeps 9 cm |

Sign lessons, measured on the rig (a bone turned, its child's position read back):
`NOD +` chin down, `Arm NOD −` forward, `Arm TILT` out is −1 right / +1 left, turns apply
in order about **fixed skeleton axes in the parent's rest frame** — so a forward-pointing
arm turned about the forward axis only twists (the first clap pulsed 1.8 cm; TURN gives
the 21 cm inward pulse), and on the raised wave arm the axis that sweeps the hand is
`TURN`, not `TILT`. From head-on the across-body point is foreshortened; it reads better
from the classroom's three-quarter camera.

`set_listening_pose(true)` is a held posture on the same layer (spine 2.5 + 2 + 1.5°,
head −3° to keep the eyes level), eased 0.35 s: the head moves 2.3 cm forward; a nod
plays over it (asserted).

## 4b. Composite tutor states — `buddy_tutor_state.gd` (owner addendum, contracts §"Aliz states")

`set_tutor_state(name)` turns one word into a policy across the four layers — face
texture, mouth frames, gesture layer, base clip — through the public calls above only,
so no state can make two layers disagree; the blink runs in every state. Speaking-state
micro-behaviour uses texture **overlays** (`browsUp`, `eyesUpLeft` laid over the
expression, under the blink) so the expression itself never changes, and three new
micro clips (`beatRight`, `beatLeft`, `openHands`, 0.9–1.0 s) played at 0.6 scale.

| state | face | mouth | gesture layer |
|---|---|---|---|
| `idle` | neutral | closed | nothing; straight ahead |
| `listening` | listening | closed | lean-in; head toward the attention target |
| `thinking` | thinking | closed | half tilt on entry |
| `speaking` | smile | lip sync | ±1° talk nods (two periods); brow raise 250 ms every ~1.8 s; glance 400 ms every ~4.5 s; a hand beat every ~3 s |
| `interrupted` | listening, at once | `set_speaking(false)` first | running gesture stopped (0.2 s fade); head toward the target; lean-in |
| `happy` / `encouraging` | happy / encouraging | untouched | half nod on entry |
| `explaining` | smile | lip sync | `point` on entry, then a half nod every ~2.5 s while `is_speaking()`; brow raises |
| `celebrating` | happy | untouched | `clap`; emits `wants_sfx("laugh")` once |

`set_attention_target(node)` (null → the current camera, else world +Z, which is where
the classroom camera sits) feeds `attention_yaw_deg()`; the look is a held head/neck
yaw on the gesture layer, clamped ±35°, eased at 140°/s.

Measured (headless, 60 Hz): **barge-in** from mid-sentence `explaining` (frame 3, point
up) → listening face at 0 ms, mouth 0 at 17 ms, point cancelled at 200 ms, head turned
35° toward a child on her left (yaw 39.8° clamped); **speaking** over 8 s: 4 brow raises,
2 glances, 3 hand beats, talk-nod peak 1.09°, expression unchanged throughout;
**explaining** over 8 s: point then 3 nods, and no more nods once speech stops.

## 5. Tests — `test_aliz_tutor_face.gd` (suite 141 cases, 0 failures; both mission smokes PASS)

1. Six expressions listed, each changes ≥ 40 texels and none outside its layers' island
   rects; all six pairwise different; `listening` touches texels within 6 of the iris
   probes and `smile` does not; `neutral` ≡ `content` and restores the atlas to the texel.
2. Blink over `listening` / `thinking` / `encouraging`: closes, keeps the expression,
   reopens to the texel.
3. Mouth: ramp → frames 1, 2, 3 in order, all four seen, never falls while rising, closed
   within 120 ms of silence, no two changes to a non-closed frame within 40 ms; the open
   frame changes ≥ 40 texels over `happy` and none outside its rects; `set_speaking(false)`
   restores `happy` exactly.
4. Lip sync: the synthetic-bump assertions above; `attach_bus` adds exactly one capture
   effect, `detach` removes it, a missing bus is refused, no `Timer` child.
5. TTS fallback: envelope length, bump count, varied heights, rate shortens it, the source
   arms on `speech_started`, moves the mouth, zeroes on `speech_finished`.
6. Gestures: durations exact, bone deltas as in the table, `gesture_finished` once, weight
   0 at the end, head back to rest within 0.1°, `stop()` blends out within 0.2 s.
7. Refused at 1.0 m/s, allowed at 0.05 m/s, fades within 0.2 s when locomotion starts,
   `point` refused while carrying, `nod` allowed.
8. Listening lean 2–8 cm forward, nod over it, back to rest.
9. Layers never conflict: `play_gesture("wave")` leaves the expression and every texel
   alone; `set_expression()` mid-wave leaves the gesture's clock and weight alone; the
   mouth frames disturb neither.
10. All nine states accepted, an unknown one refused; each sets the expression, gesture
    and speaking flag of the table; blink enabled in every state; `celebrating` emits
    `wants_sfx("laugh")` exactly once; listening leans in, idle straightens.
11. Barge-in timing: listening face ≤ 200 ms (0), mouth 0 ≤ 120 ms (17), gesture
    cancelled ≤ 200 ms (200); head turned ≥ 5° toward a target on her left; fallback
    yaw ~0 when she faces +Z with no target; idle returns the look to 0.
12. Speaking schedule: ≥ 3 brow raises, ≥ 1 glance, ≥ 2 hand beats in 8 s, both overlays
    reach the face, talk nod 0.5–3°, expression unchanged; explaining: point then ≥ 2
    nods in 8 s, none after `set_speaking(false)`.
13. `idle/walk/run` still in the player, no gesture merged into it, legacy moods present,
    wrapper children exactly `[Model]`, modifiers `[CarryPose, GestureLayer, HairSway]`.

`test_aliz_life.gd`, `test_aliz_face.gd`, `test_buddy_avatar.gd` unchanged and green
(the wrapper still has no `_process`, no `Tween`, no hand-built player).

## 6. Tools

| Tool | Purpose |
|---|---|
| `tools/aliz_expression_pass.py <glb> <atlas> <faces.json>` | paints the eight new layers, adds moods + `mouthFrames` + island `rects` to the manifest (additive; refuses a foreign atlas) |
| `tools/aliz_mouth_frames.py <glb> <atlas> <faces.json> <prefix>` | atlas-side sheets: expressions, mouth frames over `neutral`, mouth frames over `happy` |
| `tools/aliz_tutor_shots.gd -- <prefix> expr\|mouth\|envelope\|gesture\|state` | in-engine stills at the tutor camera (1.2 m, fov 52) |
| `tools/aliz_tutor_sheet.py docs/shots <prefix>` | tiles them: 1:1 + 3x sheets, envelope strip, gesture and state strips |

Restoring: `git checkout f0f212b -- game/assets/characters/buddy/pinkGirl/` then
`Godot --headless --path game --import`; the compositor reports one mouth frame and no
tutor expressions, `set_expression()` returns false, and nothing else changes.
