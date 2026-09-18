# Remesh result — `babyStanding_remesh_v01.glb`

**Date:** 2026-09-18 · **Credits consumed: 5** (ceiling was 10) · Balance 3079 → 3074

| | |
|---|---|
| Source task | `01a0b3a1-ca47-72da-85fb-bac548ffdae3` (baby standing, verified) |
| Remesh task | `01a0b49b-48a0-775f-8b1f-6390a68681eb` |
| Input method | `model_url` (Meshy CDN copy of the source task's GLB) |
| Parameters | `topology: quad`, `target_polycount: 8000`, `target_formats: ["glb"]` |
| Duration | 85 s (13:01:11Z → 13:02:36Z) |
| Saved to | `game/assets_source/meshy/littleBuddy/babyStanding_remesh_v01.glb` |
| Integrated? | **No.** Source-only, deliberately not referenced by any scene. |

Reproduce the measurements with `tools/glb_inspect.py` and `tools/glb_rig_readiness.py`.

---

## 1. Geometry

| | Original | Remesh | Change |
|---|---|---|---|
| Triangles | 255,458 | **14,406** | **−94.4 %** |
| Quads | n/a (tri mesh) | **7,203** | target was 8,000 → **90 % of target** |
| Vertices (as stored) | 139,290 | 9,827 | −93.0 % |
| Vertices (welded) | — | **7,205** | 2,622 duplicates are UV-seam splits |
| File size | 11,822,300 B (11.27 MiB) | **8,321,564 B (7.94 MiB)** | −29.6 % |
| Generator | `pygltflib@v1.16.5` | `Khronos glTF Blender I/O v4.3.47` | |

### The quad topology is mathematically confirmed

GLB has no quad primitive, so the file necessarily stores triangles and a "quad" request cannot be
verified by reading the primitive mode. It can be verified by Euler characteristic. On the welded
mesh, reading the 14,406 triangles as 7,203 quads:

```
V − E + F  =  7,205 − 14,406 + 7,203  =  2
```

Exactly 2 is a closed, genus-0 surface, and it only comes out integral like this if every face
really is a quad. **Confirmed: pure all-quad, closed, genus-0.** Not an approximation — the
identity is exact.

## 2. Mesh hygiene

| Check | Result |
|---|---|
| Degenerate triangles | **0** |
| Zero-area triangles | **0** |
| Duplicate faces | **0** |
| Loose/unused vertices | **0** |
| Non-manifold edges | **0** |
| Boundary edges (welded) | **0 — watertight** |

The raw index buffer shows 4,878 boundary edges, which looks alarming. It is an artifact: UV seams
split vertices, so a geometrically closed edge reads as two boundaries in index space. Welding by
position (9,827 → 7,205) gives **0 boundary edges**. The surface is genuinely closed.

## 3. Materials and textures

| | Original | Remesh |
|---|---|---|
| Materials | 1, `doubleSided` | 1 (`BakedMaterial`), `doubleSided` |
| Base colour | JPEG 2048² | **PNG 2048²** |
| Metallic-roughness | JPEG 2048² | **PNG 4096²** |
| Normal map | **JPEG 2048²** | **ABSENT** |

Two regressions worth knowing about, neither blocking:

1. **The normal map is gone.** The remesh baked base-colour and metallic-roughness but emitted no
   normal texture. This matters *more* at 14 k triangles than it did at 255 k: the normal map is
   exactly what would have carried the fine surface detail the decimation removed. Visually the
   silhouette and colour survive well, but fabric and facial micro-detail are now flat.
2. **A 4096² metallic-roughness map is oversized** for this project's mobile budget — and it is the
   least informative of the three maps for a soft matte baby character. It is also *larger* than
   the base colour, which is backwards. Downsizing it to 1024² (or replacing it with scalar
   factors) is an easy win before integration. Not done here: this file is a faithful record of
   what Meshy returned, and retexturing is outside the approved scope.

## 4. Orientation

glTF is Y-up. Bounding box of the remesh:

```
X  −0.4540 .. +0.4542   extent 0.9082
Y  −1.0000 .. +0.9988   extent 1.9988   <- tallest axis, upright
Z  −0.3977 .. +0.3918   extent 0.7895
centred on X +0.0001, Z −0.0030;  base Y −1.0000
```

**Facing: +Z.** A bounding box cannot distinguish +Z from −Z, so facing was determined from
geometry. In the bottom 8 % band (the feet), the toes protrude:

| | Z min | Z max | mean |
|---|---|---|---|
| Remesh | −0.1056 | **+0.2718** | +0.0814 |
| Original | −0.1056 | **+0.2543** | +0.0724 |

Forward reach in +Z is ~2.6× the −Z reach with a positive mean, in both meshes. The toes point +Z,
so the character faces **+Z**, and the remesh **preserves the original's facing**.

This matters: Meshy Rigging requires the face to point toward **+Z** and documents that models
facing other axes will fail. This asset satisfies that gate.

**Scale note:** the remesh is normalised into a [−1, 1] box and is ~5.0 % taller than the original
(1.9988 vs 1.9030). A uniform scale of **0.952** restores the original size. Both meshes place the
feet below the origin (base Y −1.0), so neither is origin-on-floor; whatever offset the current
scene applies will need re-checking at integration time.

## 5. Visual comparison

Meshy's own previews of the source task and the remesh task were compared side by side.
**Preserved:** the hair curl, both eyes with brown irises and highlights, eyebrows, blush on both
cheeks, the light-blue romper with its white lower panel, both white booties, and the overall
chubby upright silhouette. No visible collapse, spike, or hole.

At 512 px a thumbnail cannot resolve fingers, so the limb structure below was measured on the
geometry instead of eyeballed.

## 6. Limb structure (what auto-rig actually depends on)

Horizontal cross-sections, clustered in the XZ plane. At a fine threshold the limbs resolve as
separate islands — torso + 2 arms at chest height, 2 legs at ankle:

| Band | islands @ eps 0.010 | islands @ eps 0.020 |
|---|---|---|
| ankle | 7 | 2 |
| knee | 2 | 2 |
| thigh | 4 | 2 |
| chest | 3 | 1 |
| arms | 3 | 1 |
| shoulder | 2 | 2 |

Minimum surface-to-surface clearances (model height 2.0):

| Pair | Height | Min gap | Verdict |
|---|---|---|---|
| Arm ↔ torso (left) | y +0.359 | **0.1390** | clear |
| Arm ↔ torso (right) | y +0.359 | **0.1223** | clear |
| Leg ↔ leg (feet) | y −0.920 | 0.1140 | clear |
| Leg ↔ leg (ankle) | y −0.800 | 0.1229 | clear |
| Leg ↔ leg (**shin**) | y −0.640 | **0.0419** | close, not touching |
| Leg ↔ leg (knee) | y −0.480 | 0.0675 | clear |
| Leg ↔ leg (thigh) | y −0.280 | 0.0590 | clear |
| Leg ↔ leg (hip) | y −0.121 | 0.0662 | clear |

**Nothing is fused.** The arms stand well off the torso (~6–7 % of body height), which is the
failure mode that most often wrecks auto-rig weighting. The tightest point anywhere is 0.042
between the shins — close, but a real gap.

### Region vertex budget

| Region | Vertices | Share |
|---|---|---|
| Feet (bottom 8 %) | 1,294 | 13.2 % |
| Legs (8–45 %) | 3,961 | 40.3 % |
| Torso (45–72 %) | 3,053 | 31.1 % |
| Head (top 20 %) | 1,078 | 11.0 % |
| Hands (outboard \|X\|) | 445 | 4.5 % |

Feet and hands retained real geometry rather than being decimated to stumps.

**Hands/fingers:** the source model has mitten-style hands with no separated fingers — that is how
the character was generated, not something the remesh destroyed. 445 vertices across both hands is
ample for the rounded mitten form. **Do not expect per-finger bones from auto-rig**, and the game
does not need them.

## 7. Rigging suitability

| Meshy Rigging gate | Requirement | This asset | |
|---|---|---|---|
| Face count | ≤ 300,000 | 14,406 | **pass**, by 20× |
| Humanoid/biped | required | yes, upright biped | **pass** |
| Clearly defined limbs | required | arms and legs separate, nothing fused | **pass** |
| Textured | required | base colour + MR present | **pass** |
| **Facing +Z** | required, else fails | **+Z confirmed** | **pass** |
| Mesh integrity | implied | watertight, manifold, 0 degenerates | **pass** |

**Verdict: suitable for Meshy Rigging.** Every documented gate passes, with the orientation gate —
the one Meshy calls out as a hard failure — confirmed from geometry rather than assumed.

Residual risks, none blocking:

- Shin clearance of 0.042 is the most likely spot for minor weight bleeding between the legs.
  Visible only in a wide-stance pose; walk and run cycles are unlikely to expose it.
- Mitten hands mean no finger bones.
- The missing normal map is a *look* regression, not a rigging one. Worth solving before this
  character ships, independently of the rig.
