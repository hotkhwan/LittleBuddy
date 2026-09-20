#!/usr/bin/env python3
"""Read-only anatomy probe for Aliz's head. Zero credits, zero writes.

## The thing that makes this different from the pass that failed

The previous mouth attempt selected vertices by a **UV box**. That cannot work
here: the Meshy-remeshed atlas interleaves the face with the legs and the dress,
so any box that catches the mouth also catches a knee.

It is also why naive connectivity fails. The index buffer has 4,879 vertices for
a mesh whose *welded* vertex count is far lower -- every UV seam and every normal
seam duplicates a vertex, so a union-find over raw indices reports 617 "shells"
and claims 4,516 of 4,879 vertices sit on a hole. Both numbers are artefacts.

So everything here **welds by position first** and works on the welded topology.
That makes "shell" and "boundary loop" mean what they say, and it is what lets
the mouth cavity be found as *a connected component of the interior* rather than
as a rectangle on the atlas.

    python3 tools/aliz_head_probe.py <in.glb> <atlas.png>
"""

import json
import struct
import sys
from collections import defaultdict

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from png_edit import load as png_load  # noqa: E402

FMT = {5126: "f", 5123: "H", 5125: "I", 5121: "B"}
COMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path):
    data = open(path, "rb").read()
    if data[:4] != b"glTF":
        raise ValueError("not a GLB: %s" % path)
    off, js, bin_ = 12, None, None
    while off < len(data):
        (length, kind) = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + length]
        off += length
        if kind == 0x4E4F534A:
            js = json.loads(chunk)
        elif kind == 0x004E4942:
            bin_ = bytearray(chunk)
    return js, bin_


def write_glb(path, js, bin_):
    j = json.dumps(js, separators=(",", ":")).encode()
    j += b" " * ((4 - len(j) % 4) % 4)
    b = bytes(bin_) + b"\x00" * ((4 - len(bin_) % 4) % 4)
    total = 12 + 8 + len(j) + 8 + len(b)
    out = b"glTF" + struct.pack("<II", 2, total)
    out += struct.pack("<II", len(j), 0x4E4F534A) + j
    out += struct.pack("<II", len(b), 0x004E4942) + b
    open(path, "wb").write(out)


def accessor(js, bin_, index):
    """Returns (rows, base_byte_offset, stride, fmt, components)."""
    a = js["accessors"][index]
    bv = js["bufferViews"][a["bufferView"]]
    base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    comp, fmt = COMP[a["type"]], FMT[a["componentType"]]
    size = struct.calcsize(fmt)
    stride = bv.get("byteStride") or comp * size
    rows = [struct.unpack_from("<" + fmt * comp, bin_, base + k * stride)
            for k in range(a["count"])]
    return rows, base, stride, fmt, comp


def load_mesh(js, bin_, prim=None):
    if prim is None:
        prim = js["meshes"][0]["primitives"][0]
    pos, pos_base, pos_stride, _, _ = accessor(js, bin_, prim["attributes"]["POSITION"])
    nor, nor_base, nor_stride, _, _ = accessor(js, bin_, prim["attributes"]["NORMAL"])
    uv, uv_base, uv_stride, _, _ = accessor(js, bin_, prim["attributes"]["TEXCOORD_0"])
    idx = [v[0] for v in accessor(js, bin_, prim["indices"])[0]]
    return {
        "prim": prim, "pos": pos, "nor": nor, "uv": uv, "idx": idx,
        "pos_base": pos_base, "pos_stride": pos_stride,
        "nor_base": nor_base, "nor_stride": nor_stride,
        "uv_base": uv_base, "uv_stride": uv_stride,
    }


def weld(pos, tol=1e-5):
    """Position -> welded id, and welded id -> list of raw vertex ids.

    Without this every UV seam reads as a crack. With it, "hole" means hole.
    """
    key_of = {}
    wid = [0] * len(pos)
    groups = []
    q = 1.0 / tol
    for v, p in enumerate(pos):
        k = (round(p[0] * q), round(p[1] * q), round(p[2] * q))
        if k not in key_of:
            key_of[k] = len(groups)
            groups.append([])
        wid[v] = key_of[k]
        groups[wid[v]].append(v)
    return wid, groups


def sample(tex, W, H, C, u, v):
    """Nearest-texel RGB at a UV. glTF v is top-down, same as PNG rows."""
    x = min(W - 1, max(0, int(u * W)))
    y = min(H - 1, max(0, int(v * H)))
    o = (y * W + x) * C
    return tex[o], tex[o + 1], tex[o + 2]


def main():
    glb, png = sys.argv[1], sys.argv[2]
    js, bin_ = read_glb(glb)
    m = load_mesh(js, bin_)
    pos, uv, idx = m["pos"], m["uv"], m["idx"]
    W, H, C, tex = png_load(png)
    wid, groups = weld(pos)
    print("atlas %dx%d c=%d  raw verts=%d  welded=%d  tris=%d"
          % (W, H, C, len(pos), len(groups), len(idx) // 3))

    wpos = [pos[g[0]] for g in groups]

    # ---- shells on the WELDED topology ----------------------------------
    parent = list(range(len(groups)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for t in range(0, len(idx), 3):
        union(wid[idx[t]], wid[idx[t + 1]])
        union(wid[idx[t]], wid[idx[t + 2]])
    shells = defaultdict(list)
    for v in range(len(groups)):
        shells[find(v)].append(v)
    shells = sorted(shells.values(), key=len, reverse=True)
    print("\nwelded shells: %d" % len(shells))
    for s in shells[:14]:
        xs = [wpos[v][0] for v in s]
        yy = [wpos[v][1] for v in s]
        zz = [wpos[v][2] for v in s]
        cols = [sample(tex, W, H, C, uv[groups[v][0]][0], uv[groups[v][0]][1])
                for v in s[:500]]
        avg = tuple(int(sum(c[k] for c in cols) / len(cols)) for k in range(3))
        print("  n=%-5d x[%+.3f,%+.3f] y[%+.3f,%+.3f] z[%+.3f,%+.3f] avgRGB=%s"
              % (len(s), min(xs), max(xs), min(yy), max(yy), min(zz), max(zz), avg))

    # ---- boundary edges on the WELDED topology --------------------------
    edges = defaultdict(int)
    for t in range(0, len(idx), 3):
        a, b, c = wid[idx[t]], wid[idx[t + 1]], wid[idx[t + 2]]
        for e in ((a, b), (b, c), (c, a)):
            if e[0] != e[1]:
                edges[(min(e), max(e))] += 1
    boundary = [e for e, n in edges.items() if n == 1]
    print("\nwelded boundary edges: %d" % len(boundary))
    bverts = sorted({v for e in boundary for v in e})
    if bverts:
        # group the boundary into loops
        adj = defaultdict(list)
        for a, b in boundary:
            adj[a].append(b)
            adj[b].append(a)
        seen = set()
        loops = []
        for v in bverts:
            if v in seen:
                continue
            stack, comp = [v], []
            seen.add(v)
            while stack:
                u = stack.pop()
                comp.append(u)
                for w in adj[u]:
                    if w not in seen:
                        seen.add(w)
                        stack.append(w)
            loops.append(comp)
        loops.sort(key=len, reverse=True)
        print("  %d boundary loops; largest:" % len(loops))
        for lp in loops[:14]:
            xs = [wpos[v][0] for v in lp]
            yy = [wpos[v][1] for v in lp]
            zz = [wpos[v][2] for v in lp]
            cols = [sample(tex, W, H, C, uv[groups[v][0]][0], uv[groups[v][0]][1])
                    for v in lp[:200]]
            avg = tuple(int(sum(c[k] for c in cols) / len(cols)) for k in range(3))
            print("    n=%-4d x[%+.3f,%+.3f] y[%+.3f,%+.3f] z[%+.3f,%+.3f] avgRGB=%s"
                  % (len(lp), min(xs), max(xs), min(yy), max(yy),
                     min(zz), max(zz), avg))

    # ---- colour census of the face slab ---------------------------------
    print("\nface-slab colour census (y 1.38..1.62, z>0):")
    buckets = defaultdict(lambda: [0, 0.0, 0.0, 0.0, 1e9, -1e9])
    for v in range(len(pos)):
        p = pos[v]
        if not (1.38 <= p[1] <= 1.62 and p[2] > 0.0):
            continue
        r, g, b = sample(tex, W, H, C, uv[v][0], uv[v][1])
        k = (r // 32, g // 32, b // 32)
        e = buckets[k]
        e[0] += 1
        e[1] += r
        e[2] += g
        e[3] += b
        e[4] = min(e[4], p[1])
        e[5] = max(e[5], p[1])
    for k in sorted(buckets, key=lambda x: -buckets[x][0])[:16]:
        e = buckets[k]
        print("  n=%-4d avgRGB=(%3d,%3d,%3d)  y[%.3f,%.3f]"
              % (e[0], e[1] / e[0], e[2] / e[0], e[3] / e[0], e[4], e[5]))


if __name__ == "__main__":
    main()
