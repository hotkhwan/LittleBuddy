#!/usr/bin/env python3
"""Trim a Meshy prop GLB down to a triangle budget by collapsing its shortest
edges. LOCAL ONLY, no network, no credits.

Usage:
    python3 tools/meshy_tutor_trim.py <in.glb> <out.glb> --max 3000

Why this exists: Smart Topology takes `target_polycount` as a target, not a
ceiling, and it overshot the 3,000 prop gate by 38 triangles on the fruit set.
Paying 5 credits for a remesh to remove 1% of the triangles would be absurd,
and weakening the test to fit the asset is exactly what the owner's brief says
not to do. So the ASSET is fixed, here, for free.

Method: repeatedly collapse the shortest edge whose two endpoints also share
(nearly) the same UV, mapping one endpoint onto the other and dropping the
triangles that become degenerate. Skipping UV-split edges is what keeps the
texture seams intact; on a 3k-triangle toy the edges chosen are sub-millimetre
and the change is invisible. It only touches indices and never re-lays vertex
buffers, so every other attribute is untouched.

Meant to run BEFORE tools/optimize_runtime_glb.py, which then re-smooths the
normals across the welded result.
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from optimize_runtime_glb import load_glb, write_glb  # noqa: E402


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    budget = int(sys.argv[sys.argv.index("--max") + 1]) if "--max" in sys.argv else 3000
    if os.path.exists(dst):
        raise SystemExit(f"refusing to overwrite {dst}")

    gltf, binc = load_glb(src)
    if len(gltf["meshes"]) != 1 or len(gltf["meshes"][0]["primitives"]) != 1:
        raise SystemExit("expects exactly one mesh with one primitive")
    prim = gltf["meshes"][0]["primitives"][0]
    attrs = prim["attributes"]

    def view(acc_i):
        a = gltf["accessors"][acc_i]
        bv = gltf["bufferViews"][a["bufferView"]]
        return a, bv.get("byteOffset", 0) + a.get("byteOffset", 0)

    pa, poff = view(attrs["POSITION"])
    n = pa["count"]
    pos = [struct.unpack_from("<fff", binc, poff + v * 12) for v in range(n)]
    uv = None
    if "TEXCOORD_0" in attrs:
        ua, uoff = view(attrs["TEXCOORD_0"])
        uv = [struct.unpack_from("<ff", binc, uoff + v * 8) for v in range(n)]

    ia, ioff = view(prim["indices"])
    ifmt, isz = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4)}[ia["componentType"]]
    idx = [struct.unpack_from("<" + ifmt, binc, ioff + k * isz)[0] for k in range(ia["count"])]
    tris = [idx[t:t + 3] for t in range(0, len(idx) - 2, 3)]
    before = len(tris)
    if before <= budget:
        print(f"already {before} <= {budget}; copying unchanged")
        write_glb(dst, gltf, binc)
        return

    def d2(a, b):
        return sum((pos[a][i] - pos[b][i]) ** 2 for i in range(3))

    def uv_ok(a, b):
        if uv is None:
            return True
        return (uv[a][0] - uv[b][0]) ** 2 + (uv[a][1] - uv[b][1]) ** 2 < 1e-4

    parent = list(range(n))

    def find(v):
        while parent[v] != v:
            parent[v] = parent[parent[v]]
            v = parent[v]
        return v

    edges = set()
    for a, b, c in tris:
        for x, y in ((a, b), (b, c), (c, a)):
            if x != y:
                edges.add((min(x, y), max(x, y)))
    order = sorted(edges, key=lambda e: d2(*e))

    def live_count():
        cnt = 0
        for a, b, c in tris:
            fa, fb, fc = find(a), find(b), find(c)
            if fa != fb and fb != fc and fc != fa:
                cnt += 1
        return cnt

    collapsed, current = 0, before
    for a, b in order:
        if current <= budget:
            break
        ra, rb = find(a), find(b)
        if ra == rb or not uv_ok(ra, rb):
            continue
        parent[rb] = ra
        collapsed += 1
        if collapsed % 8 == 0:
            current = live_count()
    current = live_count()

    out = []
    for a, b, c in tris:
        fa, fb, fc = find(a), find(b), find(c)
        if fa != fb and fb != fc and fc != fa:
            out.extend((fa, fb, fc))
    for k, v in enumerate(out):
        struct.pack_into("<" + ifmt, binc, ioff + k * isz, v)
    ia["count"] = len(out)
    bv = gltf["bufferViews"][ia["bufferView"]]
    bv["byteLength"] = ia.get("byteOffset", 0) + len(out) * isz
    print(f"triangles: {before} -> {len(out) // 3}  ({collapsed} edge collapses, budget {budget})")
    write_glb(dst, gltf, binc)
    print(f"wrote    : {dst}")


if __name__ == "__main__":
    main()
