# Carry and Movement Pass (Agent C, 2026-09-20)

Branch `wt/move`. Suite 122 -> 125 cases, both mission smokes PASS after every commit.

## 1. Run vs walk -- measured on the real character

`game/tests/cases/test_run_vs_walk.gd` drives `LittleBuddyCharacter.step_movement()` for 3.0 s
in each mode and compares displacement (asserts run >= 1.4x walk).

| mode | before | after |
|---|---|---|
| tap-to-walk | 1.05 m/s | 1.05 m/s (unchanged, calm pace) |
| stick at walk/run boundary (0.70) | -- | 1.03 m/s |
| stick, full deflection | **1.05 m/s** (same as walk) | **1.55 m/s** measured (RUN_SPEED 1.6) |
| ratio run / walk | 1.00x | **1.48x** |

Root cause: every mode topped out at `WALK_SPEED` while `locomotion.gd` already selected the run
clip from 0.73 m/s -- she *looked* like she was running at walking pace. Fix: `RUN_SPEED = 1.6`,
stick magnitude <= `RUN_MAGNITUDE` (0.70) maps linearly to a walk (exactly `WALK_SPEED` at the
boundary), then linearly to the run at the ring; continuous, no step under the thumb. Run clip trim
at 1.6 m/s is 1.62x (inside `Locomotion.MAX_SCALE`), slip 0 %. Stop from a run: 12 frames, 0.15 m.
The locomotion view now owns the clip rate (the action driver used to clamp it back to 1.0x).
`is_running()` + `running_changed(bool)` on the character; the joystick draws the run ring and
mirrors `RUN_MAGNITUDE` (asserted equal in `test_joystick.gd`).

## 2. Carry Bunny

`game/scripts/interaction/carry_controller.gd`: in world -> pickingUp (0.45 s) -> held -> placing
(0.40 s) -> in world, integrated per physics step (headless-testable). Bunny stays the same node in
the same room (no reparent, no duplicate; stats identical before/after, asserted); his tap target is
disabled while held; follower + attention turn stand down; he plays a new `carried` clip (knees up,
hands low, face delighted). Put-down: provider `snap_to_navigable` an arm's length ahead, 8
directions front-first, refused if the mesh moves the point > 0.12 m or it is < 0.45 m from her
axis; refused entirely when nowhere is standable (he stays in her arms). Cross-room: the controller
hands him to the current room via `room_changed()`.

Aliz: `game/content/rig_profiles/pink_girl_v01.json` (carryFront off Hips at 0.36 m up / 0.28 m in
front; itemHoldRight/Left = the kitchen's tuned hand offset, bone-local; hugTarget). Clearances
measured off the meshes: her dress front 0.16 m, his back 0.07 m -> 5 cm air. Arms wrap via a
`SkeletonModifier3D` (`buddy_carry_pose.gd`) eased over the walk/run clips, hands land at
(+-0.18, 0.68, -0.19) in her frame = his hips.

## 3. Pick up / place props

`spawned_object.gd` offers `take`; `drop_zone.gd` offers `place` (delivers through the drag funnel
`chosen` when the item LANDS, only on its own zone); kitchen hand rides `itemHoldRight` when the
rig has it. milk / teddy / banana / bowl all carry (`test_carry_props.gd`).

## Affordance contract (for Agent B)

Group `affordable`; `get_affordance(actor)` -> `{verb, anchor, radius, priority, target}` or `{}`;
`perform_affordance(actor)`. Bunny: `carry` (free), `place` (in THIS actor's arms), `hug` (needs
comfort/crying), `{}` for anyone else; props: `take`; zones: `place`. No house_world change is
required; `docs/patches/agentC_house_world.diff` is an optional convenience.

## Evidence (SubViewport, sizes asserted) -- `game/tests/shots_carry.gd`

`carry_bunny_front_{ipad,iphone}.png`, `carry_bunny_quarter_*`, `carry_bunny_placed_*`,
`carry_prop_held_*`, `carry_prop_placed_*`, `move_walk_*`, `move_run_*` at 1334x750 and
2340x1080. Opened and checked: no second Bunny, feet off the floor while held (root 0.36 m), on
the floor (gap 0.000) when placed 0.59 m from her, prop visibly in the right hand then on its pad.

## Known limits

- Bunny's semantic id stays `bedroom.littleBuddy` wherever he is put down; a Story beat targeting
  him while he is in another room (or in her arms: target disabled) waits until he is put down in
  the bedroom. Lead decision.
- Aliz has no authored carry clip; the arm pose is a 4-bone modifier over walk/run.
