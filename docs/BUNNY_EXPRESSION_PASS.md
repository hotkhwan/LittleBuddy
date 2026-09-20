# Bunny has a face now

**Priority 2: "Bunny's expressions and animation."** Follows
`docs/BUNNY_LIFE_PASS.md`, which established that he is the rigged 14,406-triangle
export with a real 24-bone skeleton and five hand-keyframed clips. Nothing in that
pass was redone. Zero-Meshy, zero-credit: every pixel and every keyframe below
came out of the files already in the repository.

---

## 1. The honest summary, first

| what | is it animation? |
|------|------------------|
| `idle`, `fuss`, `eat`, `drink`, `celebrate`, **`sleep`** | **Real skeletal animation.** `TYPE_ROTATION_3D` / `TYPE_POSITION_3D` bone tracks on the real `LB_Rig_v1` skeleton, played by the ordinary `AnimationPlayer`, deforming the mesh through its real skin weights. Hand-keyframed in GDScript, not DCC-authored. |
| the attention turn towards Aliz | **Procedural.** A yaw on the model node, stepped once per frame at 115°/s. Unchanged by this pass and still labelled as procedural in `child_actor.gd`. |
| the four faces | **Neither.** A repainted TEXTURE. There are no facial bones, so nothing is animated and nothing is interpolated — the albedo's eye and mouth regions are redrawn and the material's texture is swapped. Four variants, a handful of swaps per session, nothing per frame. |

Five clips became six; the sixth removed the last pose cut in the game.

---

## 2. What was actually wrong, measured

Every claim in this section came from rendering the real `house_world.tscn`
bedroom at 1334×750 and looking at the picture. `game/tests/shots_bunny.gd` is
the harness — it is the `bunny` job `BUNNY_LIFE_PASS.md` §6 asked the Lead for,
written into a file this pass owns rather than requested again.

### 2.1 The reactions were too small to see

Bunny is 0.78 m tall and `camera_framing.gd::FOCUS_MIN_DISTANCE` will not let the
camera closer than 1.9 m, so at the framing the game actually composes he is about
230 px tall and his whole forearm is about 25 px. The previous fuss rocked the
hips ±3.5° and shook the head ±7°. At 230 px that is under two pixels.

`bunny_content_near_before.png` and `bunny_hungry_near_before.png` are those two
states, at the shipping framing, and **they are the same picture.** "Is Bunny all
right?" is the one question his body exists to answer.

### 2.2 The reaches never arrived

`bunny_eating_near_before.png` is a child with one hand out sideways at hip
height. That is a shrug, not eating. `bunny_happy_near_before.png` is the same
gesture with both arms — the celebrate raise stopped at hip height too.

### 2.3 Bedtime replaced the child with a different child

`bunny_sleepy_near_before.png` is the one that matters most. `bedtime` mapped to
the unrigged `sleeping` export — and the three Meshy exports are three separate
generations, not three poses of one model. Different hair, different nappy,
different proportions, 373,090 triangles, no skeleton, no breath.

Going to bed did not pose Bunny. **It replaced him with somebody else**, and
nothing in the code said so, because "a pose cut" sounds like a camera term.

### 2.4 The face never changed, ever

Hungry, crying, being fed, delighted, asleep — the same serene closed-mouth smile.
The bubble said "Waah!" over a contented face.

---

## 3. Expressions — the texture route

### There are no facial bones and there cannot be

The rig ends at `headfront`. No jaw, no brow, no eyelid. `BUNNY_LIFE_PASS.md`
§2 is right that there is no blink and cannot be one from the rig. So the only
honest routes are body language (§4) and **repainting the face region of the
albedo**, which is what `scripts/characters/little_buddy/baby_face_moods.gd` does.

### The four faces

| mood | eyes | mouth | when |
|------|------|-------|------|
| `content` | the shipped face, untouched | untouched | idle, walking, eating, drinking |
| `unhappy` | erased and redrawn small, low, under a heavy lash line | a small downturned curve | the `fuss` clip — a real unmet need |
| `delighted` | closed, arched UP | open, a wide smile | the happy window after being cared for |
| `asleep` | closed, curved DOWN | untouched | bedtime |

Two drawing primitives do all of it: a tapered quadratic stroke and a soft
ellipse. Both are `_blend()`ed, so nothing is aliased.

### Say plainly what this is

* It is **not** facial animation. There is no rig, no blend shape, no morph, no
  UV scroll and no interpolation between moods. A mood change is one blit and one
  texture upload.
* It is **not** per-frame. Nothing in the face system runs in `_process`. In a
  whole mission the mood changes about four times.
* It is **not** a blink, and there still is not one. A blink needs a per-frame
  system and this is deliberately not one.

### The two things that were hard

**1. Erasing an eye without leaving a rectangle.** You cannot draw a closed lid
without first removing 76×65 px of black pupil from the middle of a cheek, and the
cheek carries a blush gradient. `_skin_fill()` interpolates per column between the
rows just above and just below the box — exact at those two edges — and then
corrects the left and right edges to *meet* the real pixels beside the box. A
neighbour that is not skin (the atlas packs a white island hard against the far
eye) is ignored rather than trusted, and a column with skin at neither end is left
alone. Without the edge correction the patch reads as a faint rectangle; without
the five-column smoothing it reads as vertical stripes, because the shipped
texture's own airbrush marks get carried the full height of the fill. All three
versions were rendered and looked at.

**2. This head is unwrapped TWICE, and half the face was still awake.**
The first render of the sleeping pose had one eye shut and one eye wide open —
and the front-on renders looked perfect, which is why it nearly shipped. Reading
the mesh's `TEXCOORD_0` against its `POSITION` explained it: the generator put the
front of the head into two overlapping UV charts, one covering the whole face
(u 261–460, v 533–701) and a second covering the LEFT half again
(u 405–518, v 860–1011). Different triangles sample different charts.

So **there are three eye boxes for two eyes**, `EYE_MAIN` / `EYE_FAR` /
`EYE_LEFT_B`, and `test_bunny_face.gd::_test_every_eye_is_repainted()` fails if a
mood leaves any of them untouched. There is no second mouth — the duplicate chart
carries cheek and nose there — so one mouth box is the whole mouth.

### It refuses rather than guesses

The feature positions are atlas fractions measured off the shipping texture by
cropping it and looking (`tools/png_edit.py`). What they cannot survive is a
re-unwrap. `can_paint()` therefore checks that the shipped face is where this file
thinks it is — both irises dark, the skin above light, the lip pinker than the
skin — and on any failure the whole mood system stands down and Bunny keeps the
one face he was exported with. A visibly smaller feature, not a smile across an
ear. `_test_it_refuses_a_face_it_does_not_know()` pins it, including the realistic
case: an atlas with the eye moved is refused.

### What it costs

One extra `ImageTexture` — a working copy of the albedo, 1024² RGB8 with mipmaps,
~4 MB — plus one ~286 KB patch per mood **painted lazily**, so a session that
never puts Bunny to bed never pays for the sleeping face. Four full mood atlases
would have been four megabytes of near-identical pixels; four PNGs on disk would
have been the same, and would have gone stale the day the character is re-exported.
Painting from whatever albedo is in the build means a re-export gets moods for free
— or gets none, loudly.

---

## 4. Animation — the same rig, legible

Every amplitude was raised, and then several were brought back down by looking at
a render. The rule that came out of it:

* a rotation under about 10° on a limb is invisible at this framing;
* a reach must **arrive**, or it reads as a shrug;
* silhouette beats detail — what survives 230 px is where the arms are against
  the background, not what the hands are doing.

**None of which means faster.** Every clip kept its original length and its
original timing. Not one gained a shake, a vibration or an extra beat. A bigger
pose at the same speed reads as unhappy; the same pose faster reads as agitated,
and this is a game for a three-year-old.

### `fuss` — roughly doubled, plus two things it never had

Hips ±3.5° → ±7°, head shake ±7° → ±14°, shoulders 7/10 → 10/14, elbows 44/50 →
62/70. And two additions, because a rotation about a hip joint barely moves the
outline:

* **the hips now translate** 2.4 bone units (~11 mm) onto the supporting foot;
* **the knees take the weight** — a small alternating bend, paid for by dropping
  the hips 1.4 units so the feet stay on the floor.

Three numbers went the other way after a render:

* **the chin now comes UP, not down.** The tuck existed to tell `fuss` from
  `celebrate`; the *face* does that now, and the bedroom camera looks down on a
  0.78 m child, so six degrees of tuck was most of the expression hidden behind a
  forehead. Rendered at +6, +2 and −5.
* **the inward arm `TILT` came back down** (19/34 → 12/23). At the larger value,
  from the three-quarter angle the attention turn puts him at, the far hand
  pushed through his own hip and the near one landed on his cheek.
* the forward spine lean stayed small, for the reason the previous pass recorded.

### `eat` and `drink` — solved, not dialled

Raising the reach by eye made it worse (the arm went sideways). So the four angles
were solved instead: forward kinematics down `Hips → … → RightHand` using this
file's own `_bone_pose()`, searched for the pose that gets the hand closest to the
`mouth` socket.

**That search turned up a fact about the model worth recording: this character
cannot reach its own mouth.** Shoulder-to-mouth is 41.7 bone units; the whole arm,
hand socket included, is 33. It is the chibi head that does it — 1:3.5
head-to-height, per `CHARACTER_AGE_STAGES.md` — and no keyframe fixes it.

So the clips aim for the mouth and stop where the arm stops: hand at chin height,
~13 units off centre, in front of the face, with the head dipping the last little
way. The elbow goes OUT while the forearm comes IN, which looks odd written down
and is exactly how a small child holds something up to its face.

`drink` keeps its one distinguishing cue and got more of it — the chin tips
**back** 20° instead of 13°, against `eat`'s dip forward.

### `celebrate` — the arms actually go up

−62° → −84° on the shoulder: a near-vertical FORWARD raise. The tearing the
previous pass hit was a *lateral* raise (`TILT`), and the lateral component here is
held at 30, well below the 64 that first folded badly. The elbow **opens** rather
than closing, because with the shoulder 22° higher there is no room before both
hands are over his own face. The two hops grew 1.6 → 2.8 units and the knees now
absorb them, so the lift reads as a bounce rather than as the whole child being
slid upward.

### `sleep` — new, and it removes the last pose cut in the game

`BUNNY_LIFE_PASS.md` §7 said lying supine is "a whole-body pose no arm animation
implies". True — and the wrong conclusion, because **a whole-body pose is exactly
what a rotation of the ROOT bone is**:

* `NOD −90°` at the hips tips the spine from +Y to −Z: flat on his back, face to
  the ceiling. Every bone below comes with it, so this is one rigid rotation of
  the whole child and the skin cannot tear on it.
* `TURN +90°` then swings him about the vertical so he lies ACROSS the frame
  rather than pointing away from a camera that is fixed at +Z — the same framing
  decision the unrigged export's own `rotationDeg` was making.
* the hips then translate down by **their own measured rest height**
  (`get_bone_global_rest(Hips).origin.y`, 50.05 units today) less a 12-unit
  clearance, so his back is on the floor. Derived from the rig, not typed in, so a
  re-rig at a different hip height still lands.

Plus knees dropped open, arms loose and turned out, head rolled onto one ear, and
a breath at 5.6 s a cycle — deliberately slower than the idle's 5.2 s, because the
one thing anybody can read across a room is that a sleeping thing breathes slowly.

Two numbers were fixed by looking: the head tilt (13° pointed the face away from a
camera that is above and in front — a sleeping face nobody can see is the feature
thrown away) and the thigh angle (16° rendered as a child doing sit-ups, because a
negative `NOD` on a leg swings it forward, which once supine means *upward*).

`child_presentation.gd::pose_for_activity()` now has **one answer for every
activity**, and `test_child_needs.gd` asserts the stronger rule — no activity
leaves the rig at all — paired with a check that the `sleep` clip exists, so the
exception cannot be dropped without the clip that replaces it.

The clip is named `sleep`, so `character_action_driver.gd` picks it up and
`can_play_action("sleep")` starts answering `true` by itself. `hug` is still
unauthored and still answers `false`.

---

## 5. The evidence

All 32 frames are rendered from the real `scenes/house/house_world.tscn`, in the
real bedroom, with the real lights, the real `ChildActor` and the real
`RoomCamera`. The only things forced are the child's own **stats** — which is what
the game itself moves — and where Aliz stands.

`docs/shots/bunny_<state>_<framing>_<before|after>.png`, 1334×750, **size read back
off the written image rather than off the `--resolution` request** — the request
is the thing that has lied before, and `shots_bunny.gd` hosts the world in an
explicit `SubViewport` for exactly that reason.

| state | framing | before → after |
|-------|---------|----------------|
| `content` | room, near | unchanged, deliberately: this is the baseline the others have to differ from |
| `hungry` | room, near | indistinguishable from `content` → knees bent, hips shifted, hands drawn up, **half-lidded eyes and a downturned mouth** |
| `crying` | room, near | same pose as `hungry`, faster (`fuss_pace` 1.55 vs 1.29) — honestly still the same still frame |
| `attention` | room, near | turned towards Aliz, now with the fuss pose that no longer pushes a hand through his own hip |
| `drinking` | room, near | hands out at hip height → both hands under the chin, head tipped back, face to camera |
| `eating` | room, near | one hand out sideways (a shrug) → hand up at the mouth |
| `happy` | room, near | arms at hip height, serene face → arms up beside the head, **closed arched eyes and an open smile** |
| `sleepy` | room, near | **a different, bald, unrigged baby** → Bunny, asleep on the rig, breathing, eyes shut |

`before` was re-rendered at the end of the pass against the same world the `after`
frames use, by temporarily restoring the pre-pass copies of the five files this
pass modified. Two other agents changed rooms and lighting while this one ran, and
a before/after taken hours apart would otherwise have been comparing bedrooms.

Every image in the table was opened and looked at. Six changes in this document
were made *because* of what a render showed and are named as such.

---

## 6. Tests

`test_bunny_face.gd` is new (auto-discovered; the suite goes 120 → 121 cases from
this pass). It pins:

1. **every eye box is repainted** by every mood that closes or lowers the eyes —
   the two-charts defect, which looked completely correct from the front;
2. **nothing is painted outside the feature boxes** — a stroke that overran would
   put a lash on a cheek on one activity only;
3. the resting face is the exported albedo **to the pixel**, so "go back to
   normal" cannot rot;
4. the mood is derived from the clip and the mapping is total;
5. the painter refuses a texture it does not recognise, including a realistically
   wrong one;
6. through the real `ChildActor`: content → `content`, hungry → `unhappy`, fed →
   `delighted`, bedtime → `asleep`;
7. the Child UX scan `test_bunny_life.gd` applies to the clips, applied to the
   face — no score, no percentage, no penalty, and nothing angry.

`test_child_needs.gd` was **tightened, not weakened**: "bedtime must use the
sleeping pose" became "no activity may leave the rig at all", plus an assertion
that the `sleep` clip exists. `test_bunny_life.gd` is unchanged and still passes —
its "every clip rests every other bone" and "every clip moves the head or an arm"
rules now cover six clips instead of five.

`test_baby_avatar.gd`'s `FAKE_ANIMATION_TOKENS` source scan is unchanged and still
covers `baby_little_buddy.gd` only. The wrapper gained no tween, no
`Animation.new(` and no `_process`. The seam `BUNNY_LIFE_PASS.md` §6.3 flagged is
untouched and still flagged.

---

## 7. What could not be achieved

* **Still no blink.** No eyelid bones, and a blink is a per-frame system; the face
  here is a swap that happens a few times a minute. Stated as a limit, not solved.
* **The arms cannot reach the mouth.** Measured, §4. The feeding clips get the
  hand to the chin and the head does the rest. Only a re-rig or longer arms fix it.
* **`crying` and `hungry` are the same still frame.** They differ in playback rate
  (1.29 vs 1.55) and that difference is real in motion and invisible in a
  screenshot. Giving `crying` its own pose was considered and rejected: the project
  has no failure state and a distinct "worse" pose is one step from one.
* **`hug` is still unauthored**, so `can_play_action("hug")` still answers `false`.
* **Bedtime still happens on the floor, not in the bed.** That was true before this
  pass and is a placement decision in `house_level_director.gd`, which this pass
  does not own. The sleeping child now clips the ring-stacker toy for the same
  reason the old export did.
* **The `sleeping`, `sitting` and `standing` exports are now dead weight at
  runtime.** Nothing selects one any more; they remain in `POSES` only as the
  graceful degradation for a build without the rigged model. Deleting them is a
  decision for the Lead.
* **Not run on the device.** Everything above is macOS editor rendering.

---

## 8. Notes for the Lead

1. **The suite is green except for `gameplay_object_spawner`**, which fails on
   `kenney-food-kit` grab colliders in `scripts/gameplay/object_spawner.gd` — a
   file another agent was editing while this pass ran, and one this pass does not
   own and did not touch.
2. **Something staged this pass's files into the git index** partway through
   (`git status` shows them as `M `/`A `). Nothing here ran `git add` or
   `git commit`.
3. `shots_bunny.gd` answers `BUNNY_LIFE_PASS.md` §6.1's request for a repeatable
   way to photograph Bunny. It takes a suffix and a frame size and drives the real
   house: `Godot --path game --script res://tests/shots_bunny.gd -- after 1334x750`.
4. §6.2 of that document — passing the care kind from
   `house_level_director.gd::_open_care()` — is **still open and now worth more**,
   because `eat` and `drink` are further apart than they were. Two one-word
   changes; everything keeps working if it is never done.
