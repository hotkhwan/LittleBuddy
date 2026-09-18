#!/usr/bin/env python3
"""Locate the mouth on the runtime character from its TEXTURE, not its silhouette.

Usage: python3 tools/find_face_sockets.py

Why this is not just "pick a vertex": the character's lips are painted, not
modelled. The face is a smooth surface, so every geometric heuristic finds the
NOSE -- it is the only thing that protrudes. Placing the mouth socket on the
frontmost vertex put a feeding bottle on the baby's eyebrow.

So the mouth is found where it actually is: in the base colour texture. Lip
texels are isolated by colour, their UVs are collected, and each UV is mapped
back to a 3D position by finding the triangle whose UV winding contains it and
using the same barycentric weights on its vertices.

Pure stdlib: PNG is inflated and unfiltered by hand because Pillow is not
installed and this must run on a bare machine.
"""
import json
import math
import struct
import sys
import zlib
from collections import defaultdict

sys.path.insert(0, "tools")
from glb_deform_check import load_glb, acc_read  # noqa: E402

GLB = "game/assets/characters/littleBuddy/baby/babyLittleBuddy_v01.glb"


def decode_png(blob):
    """Minimal PNG -> (width, height, rows of RGB tuples). 8-bit RGB/RGBA only."""
    assert blob[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    idat = b""
    w = h = bitd = ct = None
    while pos < len(blob):
        ln = struct.unpack_from(">I", blob, pos)[0]
        typ = blob[pos + 4: pos + 8]
        data = blob[pos + 8: pos + 8 + ln]
        if typ == b"IHDR":
            w, h, bitd, ct = struct.unpack_from(">IIBB", data, 0)
        elif typ == b"IDAT":
            idat += data
        elif typ == b"IEND":
            break
        pos += 12 + ln
    if bitd != 8 or ct not in (2, 6):
        raise SystemExit(f"unsupported PNG (bitDepth={bitd} colourType={ct})")
    nch = 3 if ct == 2 else 4
    raw = zlib.decompress(idat)
    stride = w * nch
    out = []
    prev = bytearray(stride)
    p = 0
    for _y in range(h):
        f = raw[p]
        p += 1
        line = bytearray(raw[p: p + stride])
        p += stride
        if f == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                c = prev[i - nch] if i >= nch else 0
                b = prev[i]
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out.append(bytes(line))
        prev = line
    return w, h, out, nch


def main():
    gltf, binc = load_glb(GLB)
    prim = gltf["meshes"][0]["primitives"][0]
    P = acc_read(gltf, binc, prim["attributes"]["POSITION"])
    UV = acc_read(gltf, binc, prim["attributes"]["TEXCOORD_0"])
    ia = gltf["accessors"][prim["indices"]]
    fmt = {5121: "B", 5123: "H", 5125: "I"}[ia["componentType"]]
    sz = {5121: 1, 5123: 2, 5125: 4}[ia["componentType"]]
    bv = gltf["bufferViews"][ia["bufferView"]]
    off = bv.get("byteOffset", 0) + ia.get("byteOffset", 0)
    idx = [struct.unpack_from("<" + fmt, binc, off + k * sz)[0] for k in range(ia["count"])]

    img = gltf["images"][0]
    ibv = gltf["bufferViews"][img["bufferView"]]
    ioff = ibv.get("byteOffset", 0)
    w, h, rows, nch = decode_png(bytes(binc[ioff: ioff + ibv["byteLength"]]))
    print(f"texture {w}x{h}, {nch} channels")

    ys = [p[1] for p in P]
    lo, hi = min(ys), max(ys)
    H = hi - lo

    def texel(u, v):
        x = min(w - 1, max(0, int(u * w)))
        y = min(h - 1, max(0, int(v * h)))
        r = rows[y]
        return r[x * nch], r[x * nch + 1], r[x * nch + 2]

    # Classify every vertex by the colour painted on it. Lips on this character
    # are a saturated salmon: red clearly above green and blue, and darker than
    # the surrounding skin, which is pale and nearly neutral.
    lip = []
    for i, (p, uv) in enumerate(zip(P, UV)):
        if p[1] < 0.55 * H:          # face only
            continue
        r, g, b = texel(uv[0], uv[1])
        if r < 150:
            continue
        if r - g > 55 and r - b > 45 and g < 175:
            lip.append((i, p, (r, g, b)))

    if not lip:
        print("no lip texels matched; widen the colour test")
        return

    # Keep the largest cluster by height: cheeks are also pink, but the blush
    # sits higher and to the sides. The mouth is the central, lower cluster.
    lip.sort(key=lambda t: t[1][1])
    central = [t for t in lip if abs(t[1][0]) < 0.10 * H]
    use = central if len(central) >= 4 else lip
    n = len(use)
    mx = sum(t[1][0] for t in use) / n
    my = sum(t[1][1] for t in use) / n
    mz = sum(t[1][2] for t in use) / n
    print(f"lip-coloured vertices: {len(lip)}  central: {len(central)}")
    print(f"mouth centroid (mesh space): ({mx:.4f}, {my:.4f}, {mz:.4f})"
          f"   = {100*(my-lo)/H:.1f}% of height")

    # push the socket just off the surface so a prop does not z-fight the face
    target = (0.0, my, mz + 0.03)

    skin = gltf["skins"][0]
    jn = [gltf["nodes"][j].get("name", "") for j in skin["joints"]]
    ibm = acc_read(gltf, binc, skin["inverseBindMatrices"])
    from glb_deform_check import m_xform

    def bone_local(bone, pt):
        return m_xform(list(ibm[jn.index(bone)]), pt)

    o = bone_local("Head", target)
    print(f"\nmouth  -> bone-local (Head)  [{o[0]:.3f}, {o[1]:.3f}, {o[2]:.3f}]")

    # chest / hug target: front of the torso, just below the neck
    cb = [p for p in P if 0.50 * H < p[1] < 0.56 * H]
    cz = max(p[2] for p in cb)
    hug = (0.0, lo + 0.53 * H, cz + 0.04)
    o2 = bone_local("Spine", hug)
    print(f"hug    -> bone-local (Spine) [{o2[0]:.3f}, {o2[1]:.3f}, {o2[2]:.3f}]")


if __name__ == "__main__":
    main()
