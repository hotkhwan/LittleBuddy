#!/usr/bin/env python3
"""Evaluate a skinned GLB: weight bleeding, foot slide, joint deformation.

Usage: python3 tools/glb_deform_check.py <rigged_or_clip.glb> [...]

Stdlib only. This does real linear-blend skinning — forward kinematics down the
joint hierarchy, then `sum(w_i * globalpose_i * inversebind_i * v)` — because the
questions worth asking cannot be answered from the bind pose alone:

  * do the feet slide while planted?   (needs the animated pose)
  * do weights bleed across limbs?     (needs per-vertex joint influence)
  * do knees/elbows pinch?             (needs cross-section area under bend)
  * does the head deform when it should be rigid?

glTF stores matrices column-major; that convention is kept throughout.
"""
import json
import struct
import sys
import os
import math
from collections import defaultdict

COMP = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
        5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


# ---------------------------------------------------------------- glb parsing
def load_glb(path):
    data = open(path, "rb").read()
    if struct.unpack_from("<I", data, 0)[0] != 0x46546C67:
        raise SystemExit(f"{path}: not a GLB")
    gltf = binc = None
    off = 12
    while off + 8 <= len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        body = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            gltf = json.loads(body.decode())
        elif ctype == 0x004E4942:
            binc = body
        off += 8 + clen
        off += (4 - (off % 4)) % 4
    return gltf, binc


def acc_read(gltf, binc, i):
    acc = gltf["accessors"][i]
    n = NCOMP[acc["type"]]
    fmt, sz = COMP[acc["componentType"]]
    if "bufferView" not in acc:
        return [tuple([0] * n)] * acc["count"]
    bv = gltf["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or (sz * n)
    return [struct.unpack_from("<" + fmt * n, binc, base + k * stride)
            for k in range(acc["count"])]


def acc_norm_scale(gltf, i):
    acc = gltf["accessors"][i]
    if not acc.get("normalized"):
        return 1.0
    return {5121: 1 / 255, 5123: 1 / 65535, 5120: 1 / 127, 5122: 1 / 32767}.get(
        acc["componentType"], 1.0)


# ------------------------------------------------------------------ mat4 math
def m_ident():
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def m_mul(a, b):
    """column-major a*b"""
    o = [0.0] * 16
    for c in range(4):
        for r in range(4):
            o[c * 4 + r] = sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4))
    return o


def m_from_trs(t, q, s):
    x, y, z, w = q
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    r = [1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy), 0,
         2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx), 0,
         2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy), 0,
         0, 0, 0, 1]
    for c in range(3):
        for k in range(3):
            r[c * 4 + k] *= s[c]
    r[12], r[13], r[14] = t
    return r


def m_xform(m, p):
    x, y, z = p
    return (m[0] * x + m[4] * y + m[8] * z + m[12],
            m[1] * x + m[5] * y + m[9] * z + m[13],
            m[2] * x + m[6] * y + m[10] * z + m[14])


def q_slerp(a, b, t):
    d = sum(a[i] * b[i] for i in range(4))
    if d < 0:
        b = tuple(-v for v in b)
        d = -d
    if d > 0.9995:
        r = tuple(a[i] + t * (b[i] - a[i]) for i in range(4))
    else:
        th = math.acos(max(-1.0, min(1.0, d)))
        st = math.sin(th)
        r = tuple((math.sin((1 - t) * th) * a[i] + math.sin(t * th) * b[i]) / st
                  for i in range(4))
    n = math.sqrt(sum(v * v for v in r)) or 1.0
    return tuple(v / n for v in r)


# ------------------------------------------------------------------- the rig
class Rig:
    def __init__(self, path):
        self.gltf, self.binc = load_glb(path)
        g = self.gltf
        self.nodes = g.get("nodes", [])
        self.skin = (g.get("skins") or [None])[0]
        self.name = {i: n.get("name", f"node{i}") for i, n in enumerate(self.nodes)}
        self.parent = {}
        for i, n in enumerate(self.nodes):
            for c in n.get("children", []):
                self.parent[c] = i
        # animation channels
        self.tracks = defaultdict(dict)   # node -> path -> (times, values)
        self.duration = 0.0
        anims = g.get("animations", [])
        self.anim_name = anims[0].get("name") if anims else None
        if anims:
            an = anims[0]
            for ch in an["channels"]:
                smp = an["samplers"][ch["sampler"]]
                tin = [t[0] for t in acc_read(g, self.binc, smp["input"])]
                out = acc_read(g, self.binc, smp["output"])
                tgt = ch["target"]
                if tgt.get("node") is None:
                    continue
                self.tracks[tgt["node"]][tgt["path"]] = (tin, out)
                if tin:
                    self.duration = max(self.duration, tin[-1])

    def local(self, ni, t):
        nd = self.nodes[ni]
        tr = tuple(nd.get("translation", (0, 0, 0)))
        ro = tuple(nd.get("rotation", (0, 0, 0, 1)))
        sc = tuple(nd.get("scale", (1, 1, 1)))
        tk = self.tracks.get(ni)
        if tk:
            for path, (times, vals) in tk.items():
                v = sample(times, vals, t, path)
                if path == "translation":
                    tr = v
                elif path == "rotation":
                    ro = v
                elif path == "scale":
                    sc = v
        if "matrix" in nd and not tk:
            return list(nd["matrix"])
        return m_from_trs(tr, ro, sc)

    def globals(self, t):
        out = {}

        def get(ni):
            if ni in out:
                return out[ni]
            m = self.local(ni, t)
            p = self.parent.get(ni)
            out[ni] = m_mul(get(p), m) if p is not None else m
            return out[ni]
        for i in range(len(self.nodes)):
            get(i)
        return out

    def skinned(self, t):
        g = self.gltf
        joints = self.skin["joints"]
        ibm = acc_read(g, self.binc, self.skin["inverseBindMatrices"])
        G = self.globals(t)
        M = [m_mul(G[j], list(ibm[k])) for k, j in enumerate(joints)]
        prim = g["meshes"][0]["primitives"][0]
        a = prim["attributes"]
        P = acc_read(g, self.binc, a["POSITION"])
        J = acc_read(g, self.binc, a["JOINTS_0"])
        W = acc_read(g, self.binc, a["WEIGHTS_0"])
        ws = acc_norm_scale(g, a["WEIGHTS_0"])
        out = []
        for p, jj, ww in zip(P, J, W):
            x = y = z = 0.0
            for ji, wi in zip(jj, ww):
                w = wi * ws
                if w <= 0:
                    continue
                px, py, pz = m_xform(M[ji], p)
                x += w * px
                y += w * py
                z += w * pz
            out.append((x, y, z))
        return out


def sample(times, vals, t, path):
    if not times:
        return vals[0] if vals else (0, 0, 0)
    if t <= times[0]:
        return vals[0]
    if t >= times[-1]:
        return vals[-1]
    lo, hi = 0, len(times) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if times[mid] <= t:
            lo = mid
        else:
            hi = mid
    f = (t - times[lo]) / (times[hi] - times[lo] or 1)
    a, b = vals[lo], vals[hi]
    if path == "rotation":
        return q_slerp(a, b, f)
    return tuple(a[i] + f * (b[i] - a[i]) for i in range(len(a)))


LEFT_LEG = {"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase"}
RIGHT_LEG = {"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"}
HEAD_SET = {"Head", "head_end", "headfront", "neck"}


def analyse(path):
    rig = Rig(path)
    g = rig.gltf
    print("=" * 76)
    print(f"{os.path.basename(path)}  clip={rig.anim_name!r}  duration={rig.duration:.3f}s")
    print("=" * 76)
    joints = rig.skin["joints"]
    jname = [rig.name[j] for j in joints]

    prim = g["meshes"][0]["primitives"][0]
    a = prim["attributes"]
    P = acc_read(g, rig.binc, a["POSITION"])
    J = acc_read(g, rig.binc, a["JOINTS_0"])
    W = acc_read(g, rig.binc, a["WEIGHTS_0"])
    ws = acc_norm_scale(g, a["WEIGHTS_0"])

    # ---------------- weight bleed across the legs -------------------------
    li = {k for k, n in enumerate(jname) if n in LEFT_LEG}
    ri = {k for k, n in enumerate(jname) if n in RIGHT_LEG}
    hi_ = {k for k, n in enumerate(jname) if n in HEAD_SET}
    bleed = 0
    worst = 0.0
    for p, jj, ww in zip(P, J, W):
        wl = sum(w * ws for j, w in zip(jj, ww) if j in li and w > 0)
        wr = sum(w * ws for j, w in zip(jj, ww) if j in ri and w > 0)
        if wl > 0.001 and wr > 0.001:
            bleed += 1
            worst = max(worst, min(wl, wr))
    print(f"\n  LEG WEIGHT BLEED (vertices influenced by BOTH legs)")
    print(f"    vertices affected : {bleed} of {len(P):,} ({100*bleed/len(P):.2f}%)")
    print(f"    worst cross-weight: {worst:.4f}   "
          f"{'(negligible)' if worst < 0.05 else '(VISIBLE - inspect)'}")

    # head rigidity: head verts should be driven by head/neck only
    head_bad = 0
    for p, jj, ww in zip(P, J, W):
        wh = sum(w * ws for j, w in zip(jj, ww) if j in hi_ and w > 0)
        if wh > 0.5:
            wother = sum(w * ws for j, w in zip(jj, ww) if j not in hi_ and w > 0)
            if wother > 0.25:
                head_bad += 1
    print(f"\n  HEAD RIGIDITY")
    print(f"    head-dominant verts with >25% non-head influence: {head_bad}"
          f"   {'(clean)' if head_bad == 0 else '(check jaw/neck blend)'}")

    if rig.duration <= 0.001:
        print("\n  (static pose - no motion analysis)\n")
        return

    # ---------------- foot slide -------------------------------------------
    steps = 24
    ts = [rig.duration * k / (steps - 1) for k in range(steps)]
    toe = {}
    for side in ("Left", "Right"):
        ni = next((i for i, n in rig.name.items() if n == f"{side}ToeBase"), None)
        if ni is None:
            continue
        pos = []
        for t in ts:
            G = rig.globals(t)
            m = G[ni]
            pos.append((m[12], m[13], m[14]))
        toe[side] = pos

    print(f"\n  FOOT SLIDE  (in-place clip: a planted foot should not drift in XZ)")
    hips = next((i for i, n in rig.name.items() if n == "Hips"), None)
    if hips is not None:
        hp = []
        for t in ts:
            G = rig.globals(t)
            hp.append((G[hips][12], G[hips][14]))
        dx = max(p[0] for p in hp) - min(p[0] for p in hp)
        dz = max(p[1] for p in hp) - min(p[1] for p in hp)
        print(f"    hips horizontal travel: X {dx:.4f}  Z {dz:.4f}  "
              f"{'(in-place)' if max(dx,dz) < 0.05 else '(HAS ROOT MOTION)'}")

    for side, pos in toe.items():
        ys = [p[1] for p in pos]
        lo, hi2 = min(ys), max(ys)
        thresh = lo + 0.25 * (hi2 - lo or 1)
        planted = [(k, p) for k, p in enumerate(pos) if p[1] <= thresh]
        if len(planted) < 2:
            print(f"    {side}: too few grounded samples")
            continue
        xs = [p[0] for _, p in planted]
        zs = [p[2] for _, p in planted]
        slide = math.hypot(max(xs) - min(xs), max(zs) - min(zs))
        lift = hi2 - lo
        ratio = slide / lift if lift > 1e-6 else float("inf")
        verdict = ("NO SLIDE" if ratio < 0.25 else
                   "mild slide" if ratio < 0.6 else "SLIDING")
        print(f"    {side}ToeBase: grounded {len(planted)}/{steps} samples  "
              f"lift={lift:.4f}  drift while grounded={slide:.4f}  "
              f"ratio={ratio:.2f}  [{verdict}]")

    # ---------------- joint deformation (knee/elbow volume) ----------------
    print(f"\n  JOINT DEFORMATION (skinned cross-section area near a bending joint)")
    for jn in ("LeftLeg", "RightLeg", "LeftForeArm", "RightForeArm"):
        ni = next((i for i, n in rig.name.items() if n == jn), None)
        if ni is None:
            continue
        k = jname.index(jn) if jn in jname else None
        if k is None:
            continue
        # vertices dominated by this joint
        idx = [vi for vi, (jj, ww) in enumerate(zip(J, W))
               if max(((w * ws, j) for j, w in zip(jj, ww)), default=(0, -1))[1] == k]
        if len(idx) < 12:
            print(f"    {jn}: only {len(idx)} dominant verts, skipped")
            continue
        spans = []
        for t in (0.0, rig.duration * 0.25, rig.duration * 0.5, rig.duration * 0.75):
            S = rig.skinned(t)
            pts = [S[i] for i in idx]
            cx = sum(p[0] for p in pts) / len(pts)
            cy = sum(p[1] for p in pts) / len(pts)
            cz = sum(p[2] for p in pts) / len(pts)
            rad = sum(math.dist(p, (cx, cy, cz)) for p in pts) / len(pts)
            spans.append(rad)
        lo2, hi3 = min(spans), max(spans)
        shrink = 100 * (1 - lo2 / hi3) if hi3 else 0
        verdict = ("stable" if shrink < 12 else
                   "some pinching" if shrink < 25 else "PINCHES")
        print(f"    {jn:<12} n={len(idx):4d}  mean radius {lo2:.4f}..{hi3:.4f}  "
              f"collapse {shrink:4.1f}%  [{verdict}]")

    # ---------------- facing -----------------------------------------------
    S = rig.skinned(0.0)
    ys = [p[1] for p in S]
    lo3, hi4 = min(ys), max(ys)
    H = hi4 - lo3
    feet = [p for p in S if p[1] < lo3 + 0.08 * H]
    fz = [p[2] for p in feet]
    print(f"\n  FACING (feet band Z): min {min(fz):+.4f}  max {max(fz):+.4f}  "
          f"mean {sum(fz)/len(fz):+.4f}  -> faces {'+Z' if sum(fz)/len(fz) > 0 else '-Z'}")
    print(f"  bounds: X {min(p[0] for p in S):+.3f}..{max(p[0] for p in S):+.3f}  "
          f"Y {lo3:+.3f}..{hi4:+.3f}  Z {min(p[2] for p in S):+.3f}..{max(p[2] for p in S):+.3f}")
    print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for p in sys.argv[1:]:
        analyse(p)
