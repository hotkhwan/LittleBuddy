# Bunny is not a statue

**Brief section 7: "Bunny must not remain a rigid statue."**
Zero-Meshy, zero-credit. Everything below was built from the assets already in
the repository.

---

## 1. What was actually wrong

Bunny was not "under-animated". He was, in the shipping bedroom, **the wrong
model**, and then **the wrong model with nothing to play**. Two separate bugs,
both found by rendering the real scene and looking at it.

### Bug 1 — the bedroom was showing a 398,404-triangle statue

`child_presentation.gd::pose_for_activity()` mapped `feeding` → the `sitting`
export. `activity_for_need()` maps `hungry` → `feeding`. The child starts the
game at `hunger = 55`, which is `hungry`. So from the first frame of the game:

```
hunger 55 → need "hungry" → activity "feeding" → pose "sitting"
```

`sitting` is one of the three raw Meshy exports: **no skeleton, no skin, no
clips, 398,404 triangles, three 2048² textures.** It is physically incapable of
moving. `docs/shots/a_bunny_before_statue.png` is that model — a seated baby with
its legs stuck out, in the middle of a bedroom, for the whole opening of the
game.

That mapping was correct when it was written (three frozen exports, and seating
him was the only way to say "feeding"), and it became wrong the day the rigged
export landed. It is now: **a pose-locked export may only be chosen where it says
something the rigged model cannot.** There is exactly one such thing — lying
down — so `bedtime` is the only activity that still leaves the rig.

Side effect worth noting for the iPad budget: the bedroom no longer loads the
sitting export at all. That is 398k triangles and three 2048² textures that are
no longer paid for at runtime.

### Bug 2 — the actor animated a model it had just hidden

`child_actor.gd` cached the `AnimationPlayer` once, in `build()`. The wrapper
starts on the rigged pose, so the cache was the rigged player; the very next
line, `_refresh()`, cut the visible pose to `sitting` and hid that model. Every
clip afterwards played on an invisible baby.

`_resolve_player()` now asks the wrapper for the player of the pose that is
actually **visible**, and re-asks on every `pose_changed`. `null` is a correct
answer (a pose-locked export honestly has no player) and nothing is played.

### Bug 3 — there was no idle to play in the first place

The rigged export ships with exactly three clips: `walk`, `run`, and a 0.3 s
`Armature|clip0|baselayer` stub. Nothing to play while standing still.

---

## 2. What was added

### `baby_life_clips.gd` — five clips, hand-keyframed on the real skeleton

| clip        | length | loops | what it is                                              |
|-------------|--------|-------|---------------------------------------------------------|
| `idle`      | 5.2 s  | yes   | breath across three spine bones, hips weight shift, a slow look around the room, arms swaying a beat behind |
| `fuss`      | 1.5 s  | yes   | shoulders up, hands drawn in at the tummy, restless rock, small unhappy head shake |
| `eat`       | 2.0 s  | no    | right hand to the mouth, left half raised, head bobbing twice |
| `drink`     | 2.2 s  | no    | both hands up, head tipped **back** — the one cue that separates it from `eat` |
| `celebrate` | 1.8 s  | yes   | chin up, both arms up and forward, two bounces on the hips |

**Be precise about what these are.** They are `TYPE_ROTATION_3D` and
`TYPE_POSITION_3D` **bone** tracks on the 24-bone `LB_Rig_v1` skeleton of the
rigged export. The mesh deforms through its real skin weights and the clips
cross-fade against `walk` through the ordinary `AnimationPlayer`. They are
skeletal animation.

They are **not** DCC-authored. The keyframes were written by hand, in GDScript —
the same thing `toddler_view.gd` does for the procedural placeholder, applied to
a real rig instead of to a pile of primitives. They look like a programmer's
keyframes. `merge_into()` skips any clip name the library already has, so the day
an animator delivers `idle.glb` it is merged by `CLIP_SOURCES` first and this
file quietly stops contributing one.

They are **not** a procedural sine on the model's transform. Nothing in this pass
runs a per-frame wave, and nothing translates or tilts the whole character to
imply motion it is not making.

**There is no blink, and there cannot be one.** The rig ends at `headfront`;
there are no eyelid bones, and the face is painted into the albedo. A blink would
mean animating a UV or swapping a texture — a different piece of work.
`toddler_view.gd` blinks because it has geometry for eyes; this model does not.

### `child_life.gd` — the decision, engine-free

Pure Strings, floats and Dictionaries; no node, no clip resource. Decides which
clip Bunny should be playing and how fast, so the rule is testable without
instantiating 14,000 triangles of baby.

* **`distress()`** is continuous across the same two numbers `child_needs.gd`
  already uses — `HUNGRY_AT` (40) to `CRYING_SEVERITY` (85) — so there is no
  second hunger number anywhere that could drift out of step with the first.
* **`fuss_pace()`** turns that into the fuss clip's playback rate, 0.78 → 1.55.
  The same motion, more urgent. Measured at the real start-of-game value:

  | hunger | need     | clip   | distress | pace |
  |--------|----------|--------|----------|------|
  | 10     | (none)   | idle   | 0.00     | 1.00 |
  | 40     | hungry   | fuss   | 0.00     | 0.78 |
  | 55     | hungry   | fuss   | 0.33     | 1.04 |
  | 70     | hungry   | fuss   | 0.67     | 1.29 |
  | 90     | crying   | fuss   | 1.00     | 1.55 |

  No bar, no number, no percentage, nothing a four-year-old has to read.
* **`should_attend()` / `turn_towards()`** drive the attention turn, with a
  hysteresis band (2.1 m in, 2.7 m out) so Bunny does not pivot on the spot while
  Aliz wobbles across an exact radius.

### `child_actor.gd` — applying it

* `live(delta)` is split out of `_process()` for the same reason `step()` is: a
  headless test drives exactly the code a device does.
* Being cared for opens a 3.2 s happy window (`satisfy()`), and it closes by
  itself.
* One-shot clips re-apply when they end, so feeding continues while the activity
  is feeding.
* Clips cross-fade at 0.22 s. Every clip rests every bone it does not animate —
  without that, `idle` played straight out of `walk` would idle with the legs
  frozen mid-stride, which is the trap `toddler_view.gd::_baseline()` records and
  which is worse here because `walk` drives all 24 bones.

---

## 3. The one procedural thing, named as one

**The attention turn is procedural.** `_attend_to_caregiver()` steps an angle
towards an angle, once per frame, at 115°/s. It is not a clip and it is not
described as one. It is a body turn, which is the one thing a rotation can
honestly express — it does not sway, bob or breathe.

It rotates **the model node, not the actor node**. Bunny's `ActivityTarget` and
its `InteractionPoint` are children of the actor, and the interaction point is
where Aliz is told to *stand*, 0.62 m in front of him. Yawing the actor would
swing the place she is walking to around him while she walks to it, and both
verified missions route through that point.

The turn limit is **45°**, and that number was set by rendering it twice. The
first value was 78° — about how far a real toddler turns before stepping round —
and in the bedroom it put Bunny side-on to a camera that is fixed at +Z, so the
player got the back of his ear while the mission's "I'm hungry!" came from a
child with no face. The camera does not move in this game, so how far a character
may turn is a framing decision, not an anatomy one.

---

## 4. Verified by looking

Shots are in `docs/shots/`, all rendered from the **real** `house_world.tscn`.

| shot | what it shows |
|------|---------------|
| `a_bunny_before_statue.png` | **before** — the seated, unrigged 398k export, the thing that was actually in the bedroom |
| `a_bunny_bedroom.png` | after, the shipping bedroom at the shipping camera, opening state |
| `a_bunny_bedroom_detail.png` | the same frame, enlarged: standing, turned towards Aliz, hands drawn in |
| `a_bunny_hungry.png` | `fuss` close up |
| `a_bunny_content.png` | `idle` close up — arms hanging, relaxed |
| `a_bunny_feeding.png` | `eat` close up — hand at the mouth |
| `a_bunny_happy.png` | `celebrate` close up — chin up, arms up |

The close-ups were taken with a throwaway `SceneTree` script that loaded
`house_world.tscn`, forced one stat state on the real `ChildActor`, and moved the
shipping camera in. It has been deleted (see §6 for the request that replaces
it).

**Three things were rejected by looking at a render and then changed:**

1. Every arm reach was authored with a positive `NOD`, which on a bone that hangs
   downward swings it *backwards*. The first fuss render was a child with both
   arms behind him like a tiny waiter. The sign table is now written into the
   class doc so the next clip does not have to rediscover it.
2. `celebrate` raised the arms 88° laterally and **tore the shoulder open** —
   this is a repaired auto-rig, and a near-horizontal lateral raise smeared the
   deltoid across the character's own face. It is now a forward reach with a bent
   elbow, which is inside the range the weights survive and is the gesture a real
   toddler makes at the person who just helped them.
3. `fuss` held its hands at the chin, which is almost exactly `celebrate`'s
   silhouette — the two states a child most needs to tell apart read the same in
   a still frame. The hands came down to the tummy, which also happens to be what
   a hungry toddler does.

---

## 5. Exactly one Bunny

* `house_world.tscn` instantiates one `ChildActor` (`Rooms/Bedroom/LittleBuddyChild`).
  Asserted as text in `test_bunny_life.gd`.
* Exactly one pose holder is visible at a time; asserted on a live actor.
* The bedroom now loads **only** the rigged pose — confirmed at runtime
  (`get_loaded_poses() == ["rigged"]`). Before this pass it loaded two.

---

## 6. Requests for the Lead — files this pass does not own

1. **`scenes/spike/shot_harness.gd`: add a `bunny` job.** There is no way to
   photograph Bunny close up from the shipping harness, so the evidence above
   needed a throwaway script that has now been deleted. A job that loads
   `house_world.tscn`, takes a stat state as `extra`, and frames the child would
   make this repeatable.
2. **`scripts/gameplay/house_level_director.gd`: pass the care kind.**
   `child_actor.gd::set_activity()` now takes an optional second argument naming
   *which* act it is. The director knows the care kind at both call sites and
   passes nothing, so a bottle and a spoon are told apart by a stats heuristic
   rather than by the fact. Two one-word changes:
   `child.call("set_activity", "feeding", "giveBottle")` in `_open_care()`, and
   `child.call("set_activity", "feeding", "giveSnack")` in the kitchen `give`
   branch. Everything keeps working unchanged if this is never done.
3. **`test_baby_avatar.gd`'s `FAKE_ANIMATION_TOKENS` scan — read this one.** It
   forbids `Animation.new(` in `baby_little_buddy.gd`. The authored clips
   therefore live in a sibling file, `baby_life_clips.gd`, which the scan does not
   cover. That is a real seam and it is flagged rather than hidden. The reasoning:
   the guard was written when every pose was an *unrigged* mesh, and its own
   comment says a hand-built `AnimationPlayer` "is how `baby_view_3d.gd`
   legitimately animates a PROCEDURAL character, and is exactly what must not
   happen to a generated one that has no rig" — the rigged export *has* a rig.
   The test was already revised on 2026-09-19 to allow a rigged pose to report
   animation capability; the source scan is the half that was not revised. The
   guard was **not** weakened by this pass. If the Lead wants the invariant made
   airtight again, the scan should be extended to `baby_life_clips.gd` with
   `Animation.new(` allowed there and everything else still banned.

---

## 7. What is still not done

* **No blink.** No eyelid bones exist. See §2.
* **No sitting, and no lying-down-awake.** There is no `sit` clip on this rig, so
  `bedtime` still cuts to the unrigged `sleeping` export — a 373,090-triangle
  statue. It is the right choice today (lying supine is a whole-body pose no arm
  animation implies) and it is still a statue while it is on screen. A `sit` and a
  `sleep` clip on the rig would remove the last pose cut in the game.
* **`hug` and `sleep` are unauthored**, so `can_play_action()` still answers
  `false` for them. Honest, and unchanged by this pass.
* **The fuss is subtle in a still frame.** It rocks ±3.5° at the hips and shakes
  the head ±7°. In motion it reads as restless; in a screenshot it mostly reads as
  the pose. If the owner wants it larger, the constants are all in one place.
* **Not run on the device.** Everything above is macOS editor rendering.
