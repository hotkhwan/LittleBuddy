# Meshy auto-rig validation — standing baby

**Date:** 2026-09-19 · **Credits: 5** (ceiling 5) · Balance 3074 → **3069**
**Verdict: usable as the production Little Buddy base, with one fix required first.**

| | |
|---|---|
| Rigging task | `01a0b58b-4ca4-7663-80e9-97a4001a6f71` |
| Input | `01a0b49b-…` (remesh) via `input_task_id` — accepted, no fallback needed |
| Duration | 33 s |
| Output | `babyStanding_rigged_v01.glb` + walk/run clips (+ armature-only variants) |
| Production touched? | **No.** Nothing outside `scenes/spike/` references any of it. |

Reproduce with `tools/glb_rig_report.py` and `tools/glb_deform_check.py`.

---

## 1. Skeleton

**24 joints, root `Hips`, one skin, one weighted mesh primitive (`char1`).**
Names are Mixamo-style, so the `RigProfile` indirection in `LB_RIG_V1.md` does its job unchanged.

```
Hips
  LeftUpLeg > LeftLeg > LeftFoot > LeftToeBase
  RightUpLeg > RightLeg > RightFoot > RightToeBase
  Spine02 > Spine01 > Spine
    LeftShoulder > LeftArm > LeftForeArm > LeftHand
    RightShoulder > RightArm > RightForeArm > RightHand
    neck > Head > (head_end, headfront)
```

> **Trap:** the spine chain is named backwards. `Spine02` is the **lowest** (32 % of height),
> then `Spine01` (37 %), then `Spine` (42 %) which is the **topmost**. `chest` maps to `Spine`.

**No finger bones** — expected, the hands are mitten forms.

**Weights are clean:** 9,846 vertices, every weight set sums to 1.0 (0 exceptions), max 4
influences per vertex, 23 of 24 joints used.

## 2. Skeleton fit — correct

The rig was checked against the model's **measured** silhouette, not assumed proportions. Taking a
width profile down the mesh, the narrowest point between 40 % and 72 % height is at **48–52 %** —
that is the neck. The rig places `Head` at 48 % and `neck` at 44 %.

| Joint | Rig position | Measured anatomy |
|---|---|---|
| Toes / feet | 0–7 % | bottom of mesh |
| Knees | 16 % | narrow leg band |
| Hips | 28 % | base of torso mass |
| Hands | 28 % | widest band (arms at sides) is 28–32 % |
| Shoulders | 46 % | just below the neck |
| Head | 48 % | measured neck at 48–52 % |
| Crown | 91 % | mesh top at 100 % |

**An earlier read of this data was wrong.** Seeing `neck` at 44 % of height, I first concluded the
rigger had fitted adult proportions to a baby. It had not — this character's head genuinely is
~40 % of its height, and the joints land where the geometry says they should. The proportions only
look wrong against an adult mental model.

## 3. Animation

| Clip | Duration | Godot tracks | Bones rotating | Bones translating |
|---|---|---|---|---|
| bind (`clip0`) | 0.300 s | — | static pose | — |
| **walk** (`walking_man`) | **1.067 s** | 28 | 22 / 24 | 1 / 24 |
| **run** (`running`) | **0.667 s** | 26 | 22 / 24 | 1 / 24 |

Both clips arrived with the rig at no extra cost, as documented.

**They are in-place cycles.** The hips travel 0.043 in X and 0.029 in Z over a full cycle —
essentially zero — while exactly one bone translates. The game must drive forward motion itself.

### Feet do not slide — a correction

The first automated pass flagged **SLIDING** on both feet: the grounded toe drifts 0.42–0.45 units
while planted. That verdict was wrong, and the metric that produced it was naive. In an *in-place*
locomotion clip the planted foot **must** travel backwards relative to the body — that motion is
the stride. It is only a defect when it fails to match the character's forward speed.

Measured stride ≈ **0.446 units per 1.067 s cycle** on a 1.7-unit-tall rig, so ground speed should
be ≈ **0.42 units/s** in rig-space. At the 0.5× scale used in the validation scene, drive the
character at ≈ **0.21 units/s** for walk. Mismatch here is what will read as sliding.

`tools/glb_deform_check.py` still prints the raw ratio; read it with this in mind.

## 4. Deformation

| Check | Result |
|---|---|
| Knees (`LeftLeg` / `RightLeg`) | 6.2 % / 7.4 % radius collapse — **stable** |
| Elbows (`LeftForeArm` / `RightForeArm`) | 11.9 % / 12.1 % — **acceptable**, mild |
| Head rigidity (above the true neck) | driven by head bones; blending is at the neck — **correct** |
| Facing | **+Z**, preserved from the remesh |
| Grounding | feet at Y ≈ 0, height exactly 1.700 units |

`height_meters` was left at the API default of **1.7**, so the rig is adult-scaled. This is a
one-line scale in Godot, not a defect — but it means the asset is *not* baby-sized as delivered.

### The one real defect: leg weight bleed at the knees

Vertices influenced by **both** legs, by height band:

| Band | Height | Cross-weighted verts | Worst cross-weight |
|---|---|---|---|
| Shin | 6–16 % | 152 | 0.202 |
| **Knee** | **14–20 %** | **414** | **0.487** |
| Thigh | 20–28 % | 201 | 0.375 |
| Crotch | 24–32 % | 83 | 0.291 |

728 vertices total (7.4 % of the mesh) carry weight from both legs, peaking **at knee height with
0.487** — very nearly half-weight from the opposite leg. Moving one leg will drag the other knee
roughly halfway with it. In an alternating walk cycle this shows as webbing or stretching between
the knees.

This is the materialisation of the risk flagged before rigging was approved: the remesh's tightest
limb clearance was 0.042 between the shins, and a distance-based auto-rigger blended across that
gap. The prediction was right about the cause, slightly off about the location — it landed at the
knees rather than the shins.

**A second, milder issue:** both shoulder bones influence the lower sides of the head —
`LeftShoulder` reaches 628 vertices above 65 % height at up to **0.291** weight (`RightShoulder`,
353 verts, up to 0.157). Arm swing will subtly squash the sides of the head. Less severe than the
knees, and partly hidden by the character's chubby silhouette.

## 5. Godot integration — all green

`scenes/spike/rig_validation.tscn` (temporary; bind pose, walk, run, visible socket markers).

```
profile loaded: meshyBabyV01
rigged: bones=24  animationPlayer=true  clips=["Armature|clip0|baselayer"]
  sockets: all 4 bone sockets resolved
walk:   bones=24  clips=["Armature|walking_man|baselayer"]  length 1.067s  tracks 28
  playback: 1/24 bones translate, 22/24 rotate over the cycle
  sockets: all 4 bone sockets resolved
run:    bones=24  clips=["Armature|running|baselayer"]  length 0.667s  tracks 26
  playback: 1/24 bones translate, 22/24 rotate over the cycle
  sockets: all 4 bone sockets resolved
=== PASS ===
```

The playback check asserts bone poses actually change across the cycle — an `AnimationPlayer`
whose tracks resolve to nothing still reports as "playing", so clip existence alone proves little.

| Step | Result |
|---|---|
| Godot 4.7.2 import | **pass** — skeleton, skin, clips all imported |
| Socket resolution | **pass** — 4/4 bone sockets on all three files |
| Animation playback | **pass** — 22/24 bones rotate |
| iOS Xcode export | **pass** |
| **arm64 device build** | **pass** — `** BUILD SUCCEEDED **`, binary verified `arm64` |

Not run on a physical iPad. No device validation is claimed.

## 6. RigProfile

`game/content/rig_profiles/meshy_baby_v01.json` — temporary, validation only.

| Socket | Resolution |
|---|---|
| `head` | bone `Head` |
| `chest` | bone `Spine` (topmost spine — see the naming trap) |
| `leftHand` / `rightHand` | bones `LeftHand` / `RightHand` |
| `mouth` | `Marker3D` on `head`, offset `[0, 0.136, 0.293]` |
| `hugTarget` | `Marker3D` on `chest`, offset `[0, 0.05, 0.22]` |

Offsets were derived from bind-pose geometry (`mouth` sits just below and behind the frontmost
face vertex, which is the nose) rather than hand-authored. They should still be eyeballed in the
editor before shipping.

## 7. Verdict

**Good enough to become the production Little Buddy base — after the knee weights are fixed.**

What is genuinely good: a clean 24-bone humanoid that Godot imports without complaint, correct
skeleton fit against measured anatomy, normalised weights, stable knees and elbows, a rigid head,
+Z facing preserved, every `LB_Rig_v1` socket resolving, and a passing arm64 device build. Walk and
run came free.

Required before production:

1. **Fix the knee weight bleed** (0.487 cross-weight, 414 verts). Cheapest route is a weight-paint
   pass in Blender on the inner knees — no Meshy credits. Re-rigging would cost 5 credits and would
   likely reproduce the same blend, since the cause is the 0.042 mesh clearance, not bad luck.
2. **Scale to baby size.** Delivered at 1.7 units on the API default `height_meters`.
3. **Restore a normal map** — lost in the remesh (see `MESHY_REMESH_RESULT.md`), unrelated to
   rigging but it gates the character's final look.

Optional: soften the shoulder→head weights.

Not recommended yet: buying animations. Walk and run cover locomotion, and the knee fix should
land before spending on clips that would inherit the same skinning.
