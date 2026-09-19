#!/usr/bin/env python3
"""Turn Aliz's permanent open-mouthed grin into a normal cheerful smile.

## Why this is geometry and not just a repaint

The grin is MODELLED. Meshy gave her an open mouth: a hole in the face with a
cavity behind it, a tongue and a strip of teeth, all real triangles. No amount of
texture painting closes a hole -- repaint the cavity skin-pink and you get an
open mouth full of skin, which is worse than the grin.

So this does two things, in the only order that works:

  1. **Closes the opening.** Every vertex of the cavity is pulled forward onto
     the lip rim -- the ring where the cavity meets the face -- so the hole
     becomes a flat patch flush with the lips. The rim itself never moves, so the
     face silhouette is untouched and no seam opens up.
  2. **Repaints that patch** as closed lips with a soft upward smile line, in the
     cavity's own tiny UV island. Nothing else on the 512x512 atlas is touched.

Skinning is safe: every vertex involved is already weighted to the head, and this
only moves positions, never `JOINTS_0`/`WEIGHTS_0`. Normals in the patch are
re-pointed forward so the flattened area lights like a face rather than like the
inside of a throat.

Zero Meshy credits: reads and rewrites local files only.

    python3 tools/close_aliz_smile.py <in.glb> <out.glb> <in.png> <out.png>
"""

import json
import math
import struct
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from png_edit import load as png_load, save as png_save  # noqa: E402


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


FMT = {5126: "f", 5123: "H", 5125: "I", 5121: "B"}
COMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def accessor(js, bin_, index):
    a = js["accessors"][index]
    bv = js["bufferViews"][a["bufferView"]]
    base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    comp, fmt = COMP[a["type"]], FMT[a["componentType"]]
    size = struct.calcsize(fmt)
    stride = bv.get("byteStride") or comp * size
    reader = [struct.unpack_from("<" + fmt * comp, bin_, base + k * stride)
              for k in range(a["count"])]
    return reader, base, stride, fmt, comp


def write_vec3(bin_, base, stride, index, value):
    struct.pack_into("<fff", bin_, base + index * stride, *value)


def main():
    in_glb, out_glb, in_png, out_png = sys.argv[1:5]
    js, bin_ = read_glb(in_glb)
    prim = js["meshes"][0]["primitives"][0]
    pos, pos_base, pos_stride, _, _ = accessor(js, bin_, prim["attributes"]["POSITION"])
    nor, nor_base, nor_stride, _, _ = accessor(js, bin_, prim["attributes"]["NORMAL"])
    uv, _, _, _, _ = accessor(js, bin_, prim["attributes"]["TEXCOORD_0"])
    idx = [v[0] for v in accessor(js, bin_, prim["indices"])[0]]

    W, H, C, tex = png_load(in_png)

    # ------------------------------------------------------------------
    # 1. The cavity, found by its own UV island.
    # ------------------------------------------------------------------
    # The inside of the mouth is unwrapped into one small island of its own,
    # located by colour: it is the only dark-red patch anywhere near the face.
    # Bounds are generous by 3 texels so the rim ring is included.
    ISLAND = (344, 300, 368, 324)  # x0, y0, x1, y1 in 512-space

    def in_island(v):
        x, y = uv[v][0] * W, uv[v][1] * H
        return ISLAND[0] <= x <= ISLAND[2] and ISLAND[1] <= y <= ISLAND[3]

    cavity = sorted({v for v in idx if in_island(v)})
    if not cavity:
        raise SystemExit("no cavity vertices found -- the island bounds are wrong")

    # The RIM is the front edge of that set: the vertices closest to the camera
    # (largest Z, since the GLB has her facing +Z). Everything behind it is the
    # throat and is what gets pulled forward.
    zs = sorted(pos[v][2] for v in cavity)
    rim_z = zs[int(len(zs) * 0.88)]
    rim = [v for v in cavity if pos[v][2] >= rim_z - 0.002]
    inner = [v for v in cavity if pos[v][2] < rim_z - 0.002]
    print("cavity verts=%d  rim=%d  inner=%d  rim_z=%.4f" % (len(cavity), len(rim), len(inner), rim_z))

    # ------------------------------------------------------------------
    # 2. Close it: every inner vertex moves out to the rim plane.
    # ------------------------------------------------------------------
    # Onto the rim's own surface, not onto a flat plane: the lips curve around
    # the face, and a flat disc there would read as a sticker. Each inner vertex
    # takes the Z of the rim vertex nearest it in X/Y, which follows that curve.
    moved = 0
    for v in inner:
        px, py = pos[v][0], pos[v][1]
        best, best_d = None, 1e9
        for r in rim:
            d = (pos[r][0] - px) ** 2 + (pos[r][1] - py) ** 2
            if d < best_d:
                best_d, best = d, r
        # Pulled almost flush, not exactly: 0.8 mm of remaining recess keeps a
        # soft shadow in the seam, which is what makes a mouth read as a mouth
        # instead of as a painted-on decal.
        target_z = pos[best][2] - 0.0008
        write_vec3(bin_, pos_base, pos_stride, v, (px, py, target_z))
        # Point the normal forward so the patch lights like a face.
        write_vec3(bin_, nor_base, nor_stride, v, (0.0, 0.0, 1.0))
        moved += 1
    for v in rim:
        write_vec3(bin_, nor_base, nor_stride, v,
                   (nor[v][0] * 0.3, nor[v][1] * 0.3 + 0.2, abs(nor[v][2]) * 0.9 + 0.3))
    print("pulled %d throat vertices onto the lip rim" % moved)

    write_glb(out_glb, js, bin_)

    # ------------------------------------------------------------------
    # 3. Repaint that island as closed, smiling lips.
    # ------------------------------------------------------------------
    x0, y0, x1, y1 = ISLAND
    cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
    half_w, half_h = (x1 - x0) * 0.5, (y1 - y0) * 0.5
    LIP = (232, 138, 146)        # soft rose, a shade deeper than the skin
    LIP_DEEP = (198, 104, 116)   # the smile line itself
    SKIN = (250, 216, 200)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            u = (x - cx) / max(half_w, 1.0)
            # The smile: a shallow arc that rises at both corners.
            arc = cy + half_h * (0.18 - 0.42 * (1.0 - u * u))
            dv = (y - arc) / max(half_h, 1.0)
            o = (y * W + x) * C
            if abs(u) > 1.0:
                continue
            if abs(dv) < 0.10:
                col = LIP_DEEP
            elif abs(dv) < 0.34:
                col = LIP
            else:
                col = SKIN
            tex[o], tex[o + 1], tex[o + 2] = col
    png_save(out_png, W, H, C, tex)
    print("repainted the mouth island at %s" % (ISLAND,))


if __name__ == "__main__":
    main()
