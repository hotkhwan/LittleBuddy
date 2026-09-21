#!/usr/bin/env python3
"""Trim a GLB down to a triangle budget by collapsing its shortest same-UV
edges. LOCAL ONLY, no network, no credits, pure stdlib.

    python3 tools/meshy_trim.py <in.glb> <out.glb> --max 3000 [--force]

The generalisation of `tools/meshy_tutor_trim.py`, which only accepted one
mesh with one primitive. This one walks EVERY primitive in the file and
shares the budget between them in proportion to their triangle counts, so a
split furniture piece (body + door in one file), a Kenney multi-part model
or a plain Meshy single mesh all go through the same gate.

Method, unchanged from the tutor tool because it has been looked at and
accepted: repeatedly collapse the shortest edge whose two endpoints share
(nearly) the same UV, mapping one endpoint onto the other, and drop the
triangles that become degenerate. Skipping UV-split edges keeps texture
seams intact; on a few-thousand-triangle toy the edges chosen are
sub-millimetre and the change is invisible. Only the index buffer is
rewritten (in place, shorter); vertex buffers are untouched, so every other
attribute survives. Run BEFORE `optimize_runtime_glb.py`, which re-smooths
normals across the welded result.

Exit status is non-zero if the budget could not be reached (a mesh made
entirely of UV-split edges), so a pipeline cannot silently ship an
over-budget asset.
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from optimize_runtime_glb import load_glb, write_glb  # noqa: E402

INDEX_FORMATS = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4)}


def collapse(pos, uv, tris, budget):
    """Returns the surviving triangles (as vertex triples) at or under `budget`."""
    n = len(pos)
    before = len(tris)
    if before <= budget:
        return tris, 0

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
        count = 0
        for a, b, c in tris:
            fa, fb, fc = find(a), find(b), find(c)
            if fa != fb and fb != fc and fc != fa:
                count += 1
        return count

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

    out = []
    for a, b, c in tris:
        fa, fb, fc = find(a), find(b), find(c)
        if fa != fb and fb != fc and fc != fa:
            out.append((fa, fb, fc))
    return out, collapsed


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    budget = int(sys.argv[sys.argv.index("--max") + 1]) if "--max" in sys.argv else 3000
    if os.path.exists(dst) and "--force" not in sys.argv:
        raise SystemExit(f"refusing to overwrite {dst} (pass --force)")

    gltf, binc = load_glb(src)

    def view(acc_i):
        acc = gltf["accessors"][acc_i]
        bv = gltf["bufferViews"][acc["bufferView"]]
        return acc, bv, bv.get("byteOffset", 0) + acc.get("byteOffset", 0)

    prims = [(m, p) for m, mesh in enumerate(gltf["meshes"]) for p, prim in enumerate(mesh["primitives"])
             if "indices" in prim and prim.get("mode", 4) == 4]
    if not prims:
        raise SystemExit("no indexed TRIANGLES primitive to trim")

    counts = {}
    for m, p in prims:
        acc = gltf["accessors"][gltf["meshes"][m]["primitives"][p]["indices"]]
        counts[(m, p)] = acc["count"] // 3
    total = sum(counts.values())
    if total <= budget:
        print(f"already {total} <= {budget}; copying unchanged")
        write_glb(dst, gltf, binc)
        return

    # Proportional budgets, largest primitive absorbs the rounding remainder.
    budgets = {k: (v * budget) // total for k, v in counts.items()}
    largest = max(counts, key=counts.get)
    budgets[largest] += budget - sum(budgets.values())

    after_total = 0
    for (m, p) in prims:
        prim = gltf["meshes"][m]["primitives"][p]
        attrs = prim["attributes"]
        pa, _, poff = view(attrs["POSITION"])
        n = pa["count"]
        pos = [struct.unpack_from("<fff", binc, poff + v * 12) for v in range(n)]
        uv = None
        if "TEXCOORD_0" in attrs:
            _, _, uoff = view(attrs["TEXCOORD_0"])
            uv = [struct.unpack_from("<ff", binc, uoff + v * 8) for v in range(n)]
        ia, ibv, ioff = view(prim["indices"])
        ifmt, isz = INDEX_FORMATS[ia["componentType"]]
        idx = [struct.unpack_from("<" + ifmt, binc, ioff + k * isz)[0] for k in range(ia["count"])]
        tris = [tuple(idx[t:t + 3]) for t in range(0, len(idx) - 2, 3)]

        kept, collapsed = collapse(pos, uv, tris, budgets[(m, p)])
        flat = [v for tri in kept for v in tri]
        for k, v in enumerate(flat):
            struct.pack_into("<" + ifmt, binc, ioff + k * isz, v)
        ia["count"] = len(flat)
        ibv["byteLength"] = ia.get("byteOffset", 0) + len(flat) * isz
        after_total += len(kept)
        print(f"mesh[{m}].prim[{p}]: {len(tris)} -> {len(kept)} triangles "
              f"({collapsed} edge collapses, budget {budgets[(m, p)]})")

    write_glb(dst, gltf, binc)
    print(f"triangles: {total} -> {after_total}  (budget {budget})")
    print(f"wrote    : {dst}")
    if after_total > budget:
        raise SystemExit(f"GATE FAILED: {after_total} > {budget} after every collapsible edge; "
                         "the asset needs a remesh or a different generation")


if __name__ == "__main__":
    main()
