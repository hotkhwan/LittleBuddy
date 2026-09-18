# MESHY APPROVAL REQUEST — Rigging (baby standing)

**Status: APPROVED AND EXECUTED 2026-09-19. Result: `docs/MESHY_RIG_VALIDATION.md`. This document is now a historical record.**

Raised 2026-09-18, after Remesh operation #1b succeeded for 5 credits. One approval covers one
operation: approving this does **not** approve Animation.

---

## 1. What is being asked for

| Field | Value |
|---|---|
| Operation | **Rigging — ONE run only** |
| Endpoint | `POST /openapi/v1/rigging` |
| Asset | `babyStanding_remesh_v01.glb` (the remesh just accepted) |
| Input | the remesh task's own output, task `01a0b49b-48a0-775f-8b1f-6390a68681eb` |
| Cost | **5 credits** — published and fixed, not an estimate |
| Requested ceiling | **6 credits** (5 + margin; stop and report if exceeded) |
| Balance now | 3074 → **3069** expected after |
| Output | rigged GLB/FBX **plus Walking and Running clips at no extra cost** |

## 2. Why it is worth 5 credits

Rigging is the step that converts a static prop into a character the game can use, and Meshy
bundles **walk and run clips into the rigging price**. So this single operation delivers what would
otherwise be a rig plus two animations (5 + 3 + 3 = 11 credits) for **5**.

It is also the cheapest way to answer the questions that block the animation plan: does auto-rig
produce a usable humanoid skeleton for this character, and does that skeleton import cleanly into
Godot and map onto the `LB_Rig_v1` contract? A rigged character standing in bind pose already
proves skeleton import, skinning, and socket mapping — see `LB_RIG_V1.md`.

## 3. Evidence it will succeed

Every documented gate was verified on the actual file, not assumed
(full measurements in `MESHY_REMESH_RESULT.md`):

| Gate | Requirement | Measured | |
|---|---|---|---|
| Face count | ≤ 300,000 | 14,406 | pass, 20× margin |
| Humanoid biped | required | upright biped | pass |
| Limbs clearly defined | required | arm↔torso gap 0.12–0.14; no fusion anywhere | pass |
| Textured | required | base colour 2048² + MR 4096² | pass |
| **Faces +Z** | **fails otherwise** | **+Z, confirmed from toe geometry** | pass |
| Mesh integrity | implied | watertight, manifold, genus-0, 0 degenerates | pass |

The orientation gate is the one Meshy documents as a hard failure. It was confirmed by measuring
which way the toes protrude (+Z reach 2.6× the −Z reach), not by trusting the bounding box, which
cannot tell +Z from −Z.

## 4. Honest risks

| Risk | Likelihood | Consequence |
|---|---|---|
| Shins are 0.042 apart at the closest point | low | minor weight bleeding between legs in a wide stance; walk/run unlikely to show it |
| Mitten hands, no separated fingers | **certain** | no finger bones. The game does not need them |
| Auto-rig bone names are unknown in advance | certain | already handled: `RigProfile` maps them onto `LB_Rig_v1`, so gameplay never sees a bone name |
| Rig quality disappoints | low–moderate | 5 credits spent, no way to refund. This is the actual risk being accepted |

The remesh has **not** been integrated into any production scene, so nothing in the game breaks if
rigging is declined or the result is rejected.

## 5. Explicitly NOT being requested

- **Animation** (3 credits/action) — walk and run arrive free with the rig, so there is nothing to
  decide until the rig is validated in Godot.
- Any new **Generation**.
- Any **retry** if rigging fails. A retry needs its own approval.
- Integration into `nursery`/production scenes.

## 6. On approval

```
POST /openapi/v1/rigging
{ "input_task_id": "01a0b49b-48a0-775f-8b1f-6390a68681eb", ... }
```

Then: verify balance before/after, download the rigged GLB and the bundled walk/run clips to
`game/assets_source/meshy/littleBuddy/`, report skeleton structure, bone count, bone names, bind
pose and deformation sanity, draft the `RigProfile` mapping onto `LB_Rig_v1` — and **stop**,
without touching a production scene.

`input_task_id` may be refused here exactly as it was for the remesh
(`Invalid task mode texture`). If so I will **stop and report**, not silently fall back to
`model_url` — that substitution needed your approval last time and would need it again.

---

## Reply to approve

> **approve rigging** — one run, 5 credits, ceiling 6.
