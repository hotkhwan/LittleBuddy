#!/usr/bin/env python3
"""Assess whether a GLB is ready for automatic rigging. Local only, stdlib only.

Usage: python3 tools/glb_rig_readiness.py <file.glb> [...]

Auto-riggers fit a skeleton by finding limbs. The checks that actually predict
success are structural, not cosmetic:

  * horizontal cross-sections -> do the legs and arms read as SEPARATE islands,
    or has decimation fused them to the torso / to each other?
  * per-region vertex budget  -> do hands and feet still carry enough geometry
    to deform, or were they collapsed into stumps?
  * degenerate / duplicate triangles, and loose vertices -> these make weight
    painting misbehave.

A 512px turntable thumbnail cannot answer any of these, which is why this exists.
"""
import json
import struct
import sys
import os
import math
from collections import defaultdict


def load_glb(path):
    data = open(path, "rb").read()
    magic, ver, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
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


COMP = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
        5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}


def read_accessor(gltf, binc, idx, ncomp):
    acc = gltf["accessors"][idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    fmt, sz = COMP[acc["componentType"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or (sz * ncomp)
    out = []
    for i in range(acc["count"]):
        out.append(struct.unpack_from("<" + fmt * ncomp, binc, base + i * stride))
    return out


def geometry(path):
    gltf, binc = load_glb(path)
    prim = gltf["meshes"][0]["primitives"][0]
    verts = read_accessor(gltf, binc, prim["attributes"]["POSITION"], 3)
    tris = []
    if "indices" in prim:
        idx = [t[0] for t in read_accessor(gltf, binc, prim["indices"], 1)]
        tris = [tuple(idx[i:i + 3]) for i in range(0, len(idx) - 2, 3)]
    return verts, tris


class DSU:
    def __init__(self, n):
        self.p = list(range(n))

    def find(self, a):
        while self.p[a] != a:
            self.p[a] = self.p[self.p[a]]
            a = self.p[a]
        return a

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.p[rb] = ra


def cluster_xz(points, eps):
    """Grid-accelerated single-link clustering in the XZ plane."""
    n = len(points)
    dsu = DSU(n)
    grid = defaultdict(list)
    for i, (x, z) in enumerate(points):
        grid[(int(x // eps), int(z // eps))].append(i)
    for (gx, gz), members in grid.items():
        near = []
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                near.extend(grid.get((gx + dx, gz + dz), ()))
        for i in members:
            xi, zi = points[i]
            for j in near:
                if j <= i:
                    continue
                xj, zj = points[j]
                if (xi - xj) ** 2 + (zi - zj) ** 2 <= eps * eps:
                    dsu.union(i, j)
    roots = defaultdict(int)
    for i in range(n):
        roots[dsu.find(i)] += 1
    # ignore specks: a real limb holds a meaningful share of the slice
    return sorted((c for c in roots.values() if c >= max(3, n * 0.04)), reverse=True)


def analyse(path):
    verts, tris = geometry(path)
    ys = [v[1] for v in verts]
    lo, hi = min(ys), max(ys)
    H = hi - lo
    print("=" * 74)
    print(os.path.basename(path))
    print("=" * 74)
    print(f"  vertices {len(verts):,}   triangles {len(tris):,}   height {H:.4f}")

    # --- mesh hygiene -------------------------------------------------------
    degen = sum(1 for a, b, c in tris if a == b or b == c or a == c)
    seen = set()
    dup = 0
    for t in tris:
        k = tuple(sorted(t))
        if k in seen:
            dup += 1
        seen.add(k)
    used = set()
    for t in tris:
        used.update(t)
    loose = len(verts) - len(used)
    # zero-area triangles
    zero = 0
    for a, b, c in tris:
        if a == b or b == c or a == c:
            continue
        pa, pb, pc = verts[a], verts[b], verts[c]
        ux, uy, uz = pb[0]-pa[0], pb[1]-pa[1], pb[2]-pa[2]
        vx, vy, vz = pc[0]-pa[0], pc[1]-pa[1], pc[2]-pa[2]
        cx, cy, cz = uy*vz-uz*vy, uz*vx-ux*vz, ux*vy-uy*vx
        if math.sqrt(cx*cx+cy*cy+cz*cz) * 0.5 < 1e-12:
            zero += 1
    # edge manifoldness
    edges = defaultdict(int)
    for a, b, c in tris:
        for e in ((a, b), (b, c), (c, a)):
            edges[tuple(sorted(e))] += 1
    boundary = sum(1 for v in edges.values() if v == 1)
    nonmani = sum(1 for v in edges.values() if v > 2)
    print(f"\n  mesh hygiene:")
    print(f"    degenerate tris {degen}   zero-area {zero}   duplicate {dup}   loose verts {loose}")
    print(f"    boundary edges  {boundary}   non-manifold edges {nonmani}"
          f"   {'(watertight)' if boundary == 0 and nonmani == 0 else ''}")

    # --- limb separation ----------------------------------------------------
    eps = H * 0.030
    print(f"\n  horizontal cross-sections (island count, eps={eps:.4f}):")
    print(f"    {'height':>8}  {'y':>8}  {'verts':>6}  islands (sizes)")
    bands = [("feet", 0.03), ("ankle", 0.10), ("shin", 0.18), ("knee", 0.26),
             ("thigh", 0.36), ("hip", 0.45), ("waist", 0.52), ("chest", 0.62),
             ("arms", 0.68), ("shoulder", 0.74), ("neck", 0.80), ("head", 0.90)]
    results = {}
    for name, frac in bands:
        y = lo + frac * H
        band = [(v[0], v[2]) for v in verts if abs(v[1] - y) < H * 0.012]
        if len(band) < 4:
            print(f"    {name:>8}  {y:+8.3f}  {len(band):>6}  (too few verts)")
            continue
        sizes = cluster_xz(band, eps)
        results[name] = len(sizes)
        print(f"    {name:>8}  {y:+8.3f}  {len(band):>6}  {len(sizes)} -> {sizes[:6]}")

    # --- limb vertex budget -------------------------------------------------
    print(f"\n  region vertex budget:")
    regions = [("feet  (bottom 8%)", lambda v: v[1] < lo + 0.08 * H),
               ("legs  (8-45%)",     lambda v: lo + 0.08 * H <= v[1] < lo + 0.45 * H),
               ("torso (45-72%)",    lambda v: lo + 0.45 * H <= v[1] < lo + 0.72 * H),
               ("head  (top 20%)",   lambda v: v[1] >= lo + 0.80 * H)]
    for label, pred in regions:
        n = sum(1 for v in verts if pred(v))
        print(f"    {label:<20} {n:6,}  ({100*n/len(verts):5.1f}%)")

    # hands: extreme |X| below shoulder, the outboard ends of the arms
    xs = [abs(v[0]) for v in verts]
    xmax = max(xs)
    hands = [v for v in verts if abs(v[0]) > 0.80 * xmax and lo + 0.45 * H < v[1] < lo + 0.78 * H]
    print(f"    {'hands (|X|>80% max)':<20} {len(hands):6,}  ({100*len(hands)/len(verts):5.1f}%)")
    print()
    return results


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for p in sys.argv[1:]:
        analyse(p)
