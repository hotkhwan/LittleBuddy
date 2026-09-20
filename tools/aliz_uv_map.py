#!/usr/bin/env python3
"""Rasterise the mesh into UV space, so every atlas texel knows where it lives
in 3D -- and every point in 3D knows which texels paint it.

## Why this exists

The pass that failed tried to select the mouth with a **UV rectangle**. On this
atlas that is hopeless: the remesher fragmented the unwrap into dozens of
interleaved islands, so any rectangle over the mouth also covers a knee.

This inverts the problem. Rasterising each triangle into its own UV footprint
gives a 512x512 map of `(triangleId, position, normal)`. After that:

  * "the mouth" can be specified **in 3D** -- the front of the head, below the
    eyes, within a few centimetres of the midline -- and the texels that paint
    it fall out of the map. No rectangle, no leg vertices.
  * "is this a hole?" becomes answerable: an atlas texel that no triangle covers
    is unused atlas, not a hole; a *pixel on screen* showing background through
    the hair is a hole only if the ray misses every triangle.

Importing this module gives `build_maps()`. Running it prints a census and can
dump a debug PNG of the selection so the mask can be **looked at** before
anything is written.

    python3 tools/aliz_uv_map.py <glb> <atlas.png> [debug_out.png]
"""

import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aliz_head_probe import read_glb, load_mesh, sample  # noqa: E402
from png_edit import load as png_load, save as png_save  # noqa: E402


def build_maps(pos, nor, uv, idx, W, H):
    """-> (tri_of, pos_of, nor_of), each a W*H list indexed y*W+x.

    `tri_of[i]` is the triangle index painting that texel, or -1.
    Conservative by half a texel on each edge, so seams are covered rather than
    left as holes in the map -- an uncovered texel here would silently drop a
    piece of the mouth out of any selection built from it.
    """
    n = W * H
    tri_of = [-1] * n
    pos_of = [None] * n
    nor_of = [None] * n
    for t in range(0, len(idx), 3):
        a, b, c = idx[t], idx[t + 1], idx[t + 2]
        ax, ay = uv[a][0] * W, uv[a][1] * H
        bx, by = uv[b][0] * W, uv[b][1] * H
        cx, cy = uv[c][0] * W, uv[c][1] * H
        minx = max(0, int(min(ax, bx, cx)) - 1)
        maxx = min(W - 1, int(max(ax, bx, cx)) + 1)
        miny = max(0, int(min(ay, by, cy)) - 1)
        maxy = min(H - 1, int(max(ay, by, cy)) + 1)
        if minx > maxx or miny > maxy:
            continue
        d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(d) < 1e-12:
            continue
        inv = 1.0 / d
        for y in range(miny, maxy + 1):
            py = y + 0.5
            for x in range(minx, maxx + 1):
                px = x + 0.5
                l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) * inv
                l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) * inv
                l3 = 1.0 - l1 - l2
                # -0.04 rather than 0: covers the half-texel gutter at seams.
                if l1 < -0.04 or l2 < -0.04 or l3 < -0.04:
                    continue
                i = y * W + x
                tri_of[i] = t // 3
                pos_of[i] = (
                    l1 * pos[a][0] + l2 * pos[b][0] + l3 * pos[c][0],
                    l1 * pos[a][1] + l2 * pos[b][1] + l3 * pos[c][1],
                    l1 * pos[a][2] + l2 * pos[b][2] + l3 * pos[c][2],
                )
                nor_of[i] = (
                    l1 * nor[a][0] + l2 * nor[b][0] + l3 * nor[c][0],
                    l1 * nor[a][1] + l2 * nor[b][1] + l3 * nor[c][1],
                    l1 * nor[a][2] + l2 * nor[b][2] + l3 * nor[c][2],
                )
    return tri_of, pos_of, nor_of


def main():
    glb, png = sys.argv[1], sys.argv[2]
    js, bin_ = read_glb(glb)
    m = load_mesh(js, bin_)
    W, H, C, tex = png_load(png)
    tri_of, pos_of, nor_of = build_maps(m["pos"], m["nor"], m["uv"], m["idx"], W, H)
    covered = sum(1 for t in tri_of if t >= 0)
    print("atlas %dx%d  covered texels %d / %d (%.1f%%)"
          % (W, H, covered, W * H, 100.0 * covered / (W * H)))

    # Where does the FRONT OF THE HEAD live on the atlas?
    ys = [p[1] for p in m["pos"]]
    top = max(ys)
    front = []
    for i in range(W * H):
        p = pos_of[i]
        if p is None:
            continue
        if p[1] > top - 0.42 and p[2] > 0.10 and abs(p[0]) < 0.20:
            front.append(i)
    print("front-of-head texels: %d" % len(front))
    if front:
        xs = [i % W for i in front]
        yy = [i // W for i in front]
        print("  atlas bbox x[%d,%d] y[%d,%d]" % (min(xs), max(xs), min(yy), max(yy)))
        zz = [pos_of[i][2] for i in front]
        hy = [pos_of[i][1] for i in front]
        print("  3D y[%.3f,%.3f] z[%.3f,%.3f]" % (min(hy), max(hy), min(zz), max(zz)))

    if len(sys.argv) > 3:
        out = bytearray(tex)
        for i in front:
            o = i * C
            out[o] = min(255, out[o] // 2 + 128)
            out[o + 1] = out[o + 1] // 2
            out[o + 2] = out[o + 2] // 2
        png_save(sys.argv[3], W, H, C, out)
        print("wrote %s" % sys.argv[3])


if __name__ == "__main__":
    main()
