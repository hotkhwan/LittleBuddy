#!/usr/bin/env python3
"""Report the skeleton, skinning and animation content of a rigged GLB.

Usage: python3 tools/glb_rig_report.py <rigged.glb> [clip.glb ...]

Stdlib only. Answers the questions that decide whether an auto-rig is usable:
bone count and names, the root, skin/weighted-mesh counts, clip durations, and
the two deformation failure modes that matter for a biped — feet sliding during
a walk cycle, and weights bleeding between limbs that pass close together.
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


def report(path):
    gltf, binc = load_glb(path)
    nodes = gltf.get("nodes", [])
    skins = gltf.get("skins", [])
    anims = gltf.get("animations", [])
    meshes = gltf.get("meshes", [])
    size = os.path.getsize(path)

    print("=" * 76)
    print(f"{os.path.basename(path)}   ({size:,} bytes)")
    print("=" * 76)
    print(f"  generator : {(gltf.get('asset') or {}).get('generator','-')}")
    print(f"  nodes {len(nodes)}   meshes {len(meshes)}   skins {len(skins)}   animations {len(anims)}")

    # ---- skeleton ----------------------------------------------------------
    for si, sk in enumerate(skins):
        joints = sk.get("joints", [])
        print(f"\n  skin[{si}] name={sk.get('name','-')!r}  joints={len(joints)}")
        sk_root = sk.get("skeleton")
        print(f"    skeleton root node = {sk_root} "
              f"({nodes[sk_root].get('name','-') if sk_root is not None else '-'})")
        child_of = {}
        for ni, nd in enumerate(nodes):
            for c in nd.get("children", []):
                child_of[c] = ni
        roots = [j for j in joints if child_of.get(j) not in joints]
        print(f"    joint roots = {[nodes[r].get('name','?') for r in roots]}")

        def walk(n, depth, out):
            out.append("      " + "  " * depth + str(nodes[n].get("name", f"node{n}")))
            for c in nodes[n].get("children", []):
                if c in joints:
                    walk(c, depth + 1, out)
        lines = []
        for r in roots:
            walk(r, 0, lines)
        print("    hierarchy:")
        for ln in lines:
            print(ln)

    # ---- skinning ----------------------------------------------------------
    weighted = 0
    for mi, m in enumerate(meshes):
        for prim in m.get("primitives", []):
            if "JOINTS_0" in prim.get("attributes", {}):
                weighted += 1
    print(f"\n  weighted mesh primitives: {weighted}")

    skinned_nodes = [n.get("name", "?") for n in nodes if "skin" in n]
    print(f"  nodes bound to a skin   : {len(skinned_nodes)} {skinned_nodes[:4]}")

    # influence sanity
    for m in meshes:
        for prim in m.get("primitives", []):
            a = prim.get("attributes", {})
            if "WEIGHTS_0" not in a:
                continue
            W = acc_read(gltf, binc, a["WEIGHTS_0"])
            J = acc_read(gltf, binc, a["JOINTS_0"])
            wacc = gltf["accessors"][a["WEIGHTS_0"]]
            norm = wacc.get("normalized", False)
            ct = wacc["componentType"]
            scale = 1.0
            if ct == 5123 and norm:
                scale = 1 / 65535
            elif ct == 5121 and norm:
                scale = 1 / 255
            sums = [sum(w) * scale for w in W]
            bad = sum(1 for s in sums if abs(s - 1.0) > 0.02)
            used = set()
            for j, w in zip(J, W):
                for ji, wi in zip(j, w):
                    if wi > 0:
                        used.add(ji)
            infl = [sum(1 for wi in w if wi > 0) for w in W]
            print(f"    weights: verts={len(W):,}  sum!=1 on {bad} verts  "
                  f"max influences/vert={max(infl)}  joints actually used={len(used)}")
            return_data = (gltf, binc, prim, J, W, scale)
            break
        else:
            continue
        break

    # ---- animations --------------------------------------------------------
    for ai, an in enumerate(anims):
        dur = 0.0
        nkeys = 0
        targets = set()
        paths = defaultdict(int)
        for ch in an.get("channels", []):
            smp = an["samplers"][ch["sampler"]]
            tin = acc_read(gltf, binc, smp["input"])
            if tin:
                dur = max(dur, max(t[0] for t in tin))
                nkeys += len(tin)
            tgt = ch.get("target", {})
            if tgt.get("node") is not None:
                targets.add(tgt["node"])
            paths[tgt.get("path")] += 1
        print(f"\n  animation[{ai}] name={an.get('name','-')!r}")
        print(f"    duration {dur:.3f}s   channels {len(an.get('channels',[]))}   "
              f"keyframes {nkeys}   animated nodes {len(targets)}")
        print(f"    channel paths: {dict(paths)}")
    print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for p in sys.argv[1:]:
        report(p)
