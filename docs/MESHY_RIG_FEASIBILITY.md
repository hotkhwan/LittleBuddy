# Meshy Auto-Rig Feasibility — Phase 1 (zero credits spent)

**Date:** 2026-09-18 · **Credits spent: 0** · **No Meshy endpoint was called.**

Everything below comes from the official API documentation and from local inspection of the four
GLBs already on disk.

---

## 1. What the API actually offers

| Operation | Endpoint | Cost | Key limits |
|---|---|---|---|
| **Remesh** | `POST /openapi/v1/remesh` | not published (response carries `consumed_credits`) | `target_polycount` **100 – 300,000**; `topology` `quad`\|`triangle`; input by `input_task_id` **or** `model_url` |
| **Rigging** | `POST /openapi/v1/rigging` | **5 credits** | **≤ 300,000 faces**; textured **humanoid/biped** with "clearly defined limbs and body structure"; **the face must point toward +Z** — "models facing other axes will fail" |
| **Animation** | `POST /openapi/v1/animations` | **3 credits per action** | requires a completed `rig_task_id`; 1–10 actions per request |
| **Animation library** | `GET /openapi/v1/animations/library` | **free** | searchable by `category`: `WalkAndRun`, `BodyMovements`, `DailyActions`, … |

### The single most useful finding

> **Rigging already includes Walking and Running clips at no extra cost.**
> The documented rigging response carries walking and running GLB/FBX outputs by default.

That changes the validation plan the owner proposed. "idle + walk" was going to be 2 animations
(6 credits); **walk arrives with the rig**, so the minimum viable test is:

**Remesh (cost TBD) → Rig (5 credits) → walk is already in hand.**

`idle` can be added for 3 credits *if* the rig validates — or skipped entirely for the first test,
since a rigged character standing still in its bind pose is enough to prove skeleton import,
skinning and socket mapping in Godot.

---

## 2. Our four models against the hard gates

Face counts measured from the GLB binary chunks; orientation confirmed by **rendering each model
with the camera on +Z and seeing its face**.

| | PinkGirl Buddy | Baby standing | Baby seated | Baby sleeping |
|---|---|---|---|---|
| Faces | 619,890 | **255,458** | 398,404 | 373,090 |
| ≤ 300,000 rigging limit | ❌ 2.07× over | ✅ **under** | ❌ 1.33× over | ❌ 1.24× over |
| Textured | ✅ | ✅ | ✅ | ✅ |
| Humanoid / biped | ✅ | ✅ | ✅ | ✅ |
| **Faces +Z** (hard gate) | ✅ | ✅ | ✅ | ✅ |
| Limb clarity | ⚠️ legs inside a skirt | ✅ **clearest** | ⚠️ legs splayed forward | ⚠️ arms wide, legs apart |
| Pose suitable for pose-estimation | ⚠️ standing, but skirt | ✅ **standing, closest to A-pose** | ❌ **seated** | ❌ **supine, authored upright** |
| **Remesh required before rigging** | **YES** (over limit) | **not for the API limit** — but yes for runtime budget | **YES** | **YES** |
| **Rig directly in this pose?** | possible after remesh | ✅ **yes — the candidate** | ❌ **no** | ❌ **no** |

### Per-model notes

**Baby standing — the candidate.** The only one already inside the 300,000-face rigging limit, and
the only one in a pose a humanoid pose-estimator is designed for: upright, arms down and slightly
away from the body, legs apart. This is the model to test the pipeline with.

**Baby seated — do not rig in this pose.** Auto-rig infers a skeleton from an assumed upright
biped. A figure with its legs extended horizontally in front of it will either fail outright or
produce a skeleton whose hips and knees are in the wrong places — and a bad skeleton is worse than
none, because the damage only shows once it animates.

**Baby sleeping — do not rig in this pose.** Meshy authored it *upright* with its eyes shut and
arms out; it is a lying baby modelled as a standing one. A pose-estimator would read it as a
T-posed standing child and build a skeleton on that reading. That might even skin plausibly, but
the result would be a rig that disagrees with what the mesh depicts.

**PinkGirl Buddy.** Humanoid and correctly oriented, but 2.07× over the face limit so remesh is
mandatory, and her legs are inside a skirt — "clearly defined limbs" is exactly what the docs say
auto-rig needs, and a skirt hides the thing being estimated. She is a *later* candidate, after the
baby proves the pipeline.

### Two heuristics I tried and threw away

Stated because a wrong method quietly reported as fact is worse than no method:

1. **Orientation by head-band centroid asymmetry** said three models face −Z. It was measuring the
   **back of the head** — hair and occiput protrude further than a baby's nose. The render is
   direct evidence and overrides it: camera on +Z, faces visible, so they face **+Z**.
2. **Limb separation by 1D X-projection, then by 2D occupancy islands** gave unusable numbers
   (11 and 16 "islands" on a single connected body) because both measure vertex sampling density,
   not solid occupancy. Limb clarity above is reported from **looking at the renders**.

---

## 3. The practical blocker before any of this can run

**`model_url` must be a publicly accessible URL or a data URI.** Our GLBs are local files.

| Route | Viability |
|---|---|
| **`input_task_id`** — reference the original generation task in the Meshy account | **Best.** It is also the route the 300,000-face note is written against. Needs the task id for the standing baby, which lives in the Meshy account and is not in the GLB (its `asset.generator` is only `pygltflib@v1.16.5`). |
| `model_url` on a public host | Works, but publishes a paid asset to a public URL. Not recommended. |
| Data URI | 15.4 MB base64-encodes to ≈ 20.5 MB of request body. Almost certainly rejected. |

**Also: `MESHY_API_KEY` is not visible to this session.** Checked in the shell, in `bash -l`, in
`zsh -l`, and for the variable *name* in the usual profile files — absent everywhere. The value was
never read or printed. Even with approval, no call can be made until it is exported where this
session can see it.

Listing tasks (to recover the `input_task_id`) is itself a zero-credit call, but the owner's
current instruction is **do not call Meshy**, so it has not been made.

---

## 4. Recommended sequence

1. **Remesh the standing baby** to a mobile-friendly source mesh. *(One approval — pending.)*
2. If it succeeds → **request approval to rig** (5 credits). Walking arrives with it.
3. If the rig succeeds → import into Godot, map the semantic sockets, **prove walk plays**.
4. Only then consider `idle` (3 credits) and, much later, `sit` / `eat` / `drink` / `hug` / `sleep`.

**One rigged baby, not three.** Once a shared skeleton exists, seated and sleeping should be
*animation poses on that skeleton*, not three unrelated meshes with three unrelated rigs. The
seated and sleeping GLBs stay as visual references and static previews until the shared rig is
proven able to reproduce them.

## 5. If the experiment fails

Do not spend more credits. The fallback is local rigging in Blender against `LB_Rig_v1`, which
costs time instead of credits and gives complete control of bone names and weights. Blender is
**not installed in this environment**, so that path needs a desktop setup — see
`docs/LB_RIG_V1.md` for the contract any rig, bought or hand-made, has to satisfy.
