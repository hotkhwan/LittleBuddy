#!/usr/bin/env python3
"""Paint Aliz's fringe edge where the fringe GEOMETRY ends, not along an arc --
which first requires giving the forehead its own patch of atlas.

    python3 tools/aliz_fringe_repaint.py <in.glb> <in.png> <out.glb> <out.png>

## The measurement that decides the shape

The fringe is not a few millimetres of relief on the forehead, as the first
pass recorded from an unlit render. Fitting a base forehead surface to the
head-on render and rejecting everything in FRONT of it, the relief histogram is
bimodal: the forehead at 0-10 mm and a solid **32-52 mm slab** -- the bangs are
a 4 cm thick volume with a zigzag lower edge of strand tips.

The previous pass painted hair above the arc `y = 1.418 + 0.42 x^2`. Measured
per 1 cm column, that arc sits **2-9 cm BELOW the slab edge** at |x| = 3-9 cm,
so a band of flat forehead there is painted pink under a strand wall that
faces down and shades dark; in the centre the strand tips dip **15 mm below**
the arc and were painted skin. Under the house light that is what reads as a
ragged fringe at gameplay distance: a lit pink band beneath a shadowed jagged
edge, with skin-coloured teeth poking through it.

## Why a plain repaint cannot do it -- and what does

The obvious edit -- blend each hair-painted texel toward skin by how flat it
is -- was written first and produced a checkerboard of skin flecks ACROSS the
slab. Measured: **426 of the 2,176 band texels are claimed by both a forehead
triangle and a slab triangle.** The forehead island and the fringe-front
island overlap in the atlas around (347-388, 240-290). The first pass's finding
that no texels are shared between regions more than 12 cm apart is still true;
these two surfaces are 4 cm apart. One texel cannot be skin on the forehead and
pink on the slab in front of it, so the forehead has to move.

So this tool:

1. selects the **flat forehead triangles** in the band (centroid relief
   < 6 mm; 27 of them), grouped by shared UV vertices so adjacency survives;
2. finds a free rectangle in the atlas (nothing owned within a 2-texel margin)
   and gives those triangles **new vertices** there -- position, normal, joints
   and weights copied, only the UVs new -- so the mesh's triangle count does
   not change and no position moves;
3. **transfers** the old texels into the new island by barycentric lookup, so
   brows and any skin detail come with it, then turns every transferred texel
   that was hair-pink into skin;
4. repaints any **slab** texel (relief > 14 mm, every claimant on the slab)
   that the old arc had left skin-coloured back to hair, so the strand tips
   are pink to their points;
5. re-pads the gutters.

The hair/skin boundary is then the mesh edge between the forehead and the
slab's foot -- the geometric edge -- and because the two sides are on
different islands there is nothing for bilinear filtering to smear across it.

`test_aliz_face.gd` measures hair above y = 1.450 on the front of the head; the
slab edge is at 1.40-1.50 and the forehead below it is exactly what becomes
skin, so the assertion is checked by running it, not assumed.
"""

import math
import struct
import sys
from collections import defaultdict

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aliz_head_probe import read_glb, write_glb, load_mesh  # noqa: E402
from aliz_local_pass import (claim_map, tri_centroids, solve, surface,  # noqa: E402
                             replace_embedded_image, SKIN, HAIR)
from aliz_polish_pass import Mesh, pad_atlas, rebuild  # noqa: E402
from aliz_screen_probe import render, classify  # noqa: E402
from png_edit import load as png_load, save as png_save  # noqa: E402

BAND_X, BAND_Y0, BAND_Y1, BAND_Z = 0.10, 1.36, 1.50, 0.10
FIT_X, FIT_Y0, FIT_Y1 = 0.16, 1.33, 1.50
RELIEF_FLAT = 0.006      # a triangle whose centroid sits under this is forehead
RELIEF_SLAB = 0.014      # over this is fringe
FLAT_X, FLAT_Y1 = 0.08, 1.455   # the forehead that moves: under the fringe's teeth only
FIT_REJECT = 0.0025
MARGIN = 3               # texels of clear gutter round the new island

HEAD_C = (0.0, 1.400, 0.0)
HEAD_R = 0.360


def fit_forehead(glb, png):
    buf = render(glb, png, head_y=1.40)
    pts = [p for p in buf["pos"]
           if p is not None and abs(p[0]) < FIT_X and FIT_Y0 < p[1] < FIT_Y1 and p[2] > 0.12]
    keep = pts
    coeff = None
    for _ in range(8):
        a = [[0.0] * 6 for _ in range(6)]
        rhs = [0.0] * 6
        for x, y, z in keep:
            t = (1.0, x, y, x * x, y * y, x * y)
            for i in range(6):
                rhs[i] += t[i] * z
                for j in range(6):
                    a[i][j] += t[i] * t[j]
        coeff = solve(a, rhs)
        nk = [(x, y, z) for x, y, z in keep if z < surface(coeff, x, y) + FIT_REJECT]
        if len(nk) == len(keep) or len(nk) < 200:
            break
        keep = nk
    print("forehead: base surface fitted from %d of %d rendered samples" % (len(keep), len(pts)))
    return coeff


def in_band(p):
    return abs(p[0]) < BAND_X and BAND_Y0 < p[1] < BAND_Y1 and p[2] > BAND_Z


def owned_mask(mesh, W, H):
    idx = [v for t in mesh.tris for v in t]
    claims, where = claim_map(mesh.pos, mesh.uv, idx, W, H)
    return claims, where


def free_rect(claims, W, H, need_w, need_h):
    """Top-left of the first all-unowned rectangle of need_w x need_h, scanning
    from the bottom of the atlas up (the gutters are largest there)."""
    occ = [1 if claims[i] else 0 for i in range(W * H)]
    # summed-area table
    sat = [0] * ((W + 1) * (H + 1))
    for y in range(H):
        row = 0
        for x in range(W):
            row += occ[y * W + x]
            sat[(y + 1) * (W + 1) + x + 1] = sat[y * (W + 1) + x + 1] + row

    def count(x0, y0, x1, y1):  # inclusive-exclusive
        return (sat[y1 * (W + 1) + x1] - sat[y0 * (W + 1) + x1]
                - sat[y1 * (W + 1) + x0] + sat[y0 * (W + 1) + x0])

    for y in range(H - need_h, -1, -1):
        for x in range(0, W - need_w + 1):
            if count(x, y, x + need_w, y + need_h) == 0:
                return x, y
    raise SystemExit("no free %dx%d rectangle in the atlas" % (need_w, need_h))


def main():
    in_glb, in_png, out_glb, out_png = sys.argv[1:5]
    coeff = fit_forehead(in_glb, in_png)
    js, bin_ = read_glb(in_glb)
    mesh = Mesh(js, bin_)
    W, H, C, tex = png_load(in_png)
    old_tex = bytearray(tex)

    def relief(p):
        return p[2] - surface(coeff, p[0], p[1])

    # -- 1. the flat forehead triangles, grouped by shared UV vertices ---------
    # Only the CENTRAL forehead moves. A first run relocated every flat triangle
    # in the band and, rendered, opened two large skin wedges at the temples
    # where the slab edge climbs to y 1.49: geometrically forehead, but read as
    # holes in the hair. The fringe's own teeth span |x| < 8 cm; outside that
    # and above 1.455 the flat pink stays as the side hair's foot.
    def moves(t):
        c = mesh.centroid(t)
        return (in_band(c) and relief(c) < RELIEF_FLAT
                and abs(c[0]) < FLAT_X and c[1] < FLAT_Y1)

    flat = [ti for ti, t in enumerate(mesh.tris) if moves(t)]
    parent = {ti: ti for ti in flat}

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    by_vertex = defaultdict(list)
    for ti in flat:
        for v in mesh.tris[ti]:
            by_vertex[v].append(ti)
    for tis in by_vertex.values():
        for other in tis[1:]:
            parent[find(other)] = find(tis[0])
    groups = defaultdict(list)
    for ti in flat:
        groups[find(ti)].append(ti)
    groups = list(groups.values())
    print("forehead: %d flat triangles in %d UV-connected groups" % (len(flat), len(groups)))

    # -- 2. a free rectangle, groups laid out in a row -----------------------
    boxes = []
    for g in groups:
        us = [mesh.uv[v][0] * W for ti in g for v in mesh.tris[ti]]
        vs = [mesh.uv[v][1] * H for ti in g for v in mesh.tris[ti]]
        boxes.append((min(us), min(vs), max(us) - min(us), max(vs) - min(vs)))
    need_w = int(sum(b[2] for b in boxes)) + MARGIN * (len(boxes) + 1) + len(boxes)
    need_h = int(max(b[3] for b in boxes)) + 2 * MARGIN + 1
    claims, where = owned_mask(mesh, W, H)
    rx, ry = free_rect(claims, W, H, need_w, need_h)
    print("forehead: new island %dx%d at (%d, %d)" % (need_w, need_h, rx, ry))

    # -- 3. new vertices with the new UVs; remember old->new UV per triangle ---
    moved = []   # (new_tri_index, [(old_uv, new_uv) x3])
    cursor = rx + MARGIN
    for g, (bu, bv, bw, bh) in zip(groups, boxes):
        du = (cursor - bu) / W
        dv = (ry + MARGIN - bv) / H
        remap = {}
        for ti in g:
            new_tri = []
            pairs = []
            for v in mesh.tris[ti]:
                if v not in remap:
                    ou, ov = mesh.uv[v]
                    remap[v] = mesh.add_vertex(v, (ou + du, ov + dv))
                new_tri.append(remap[v])
                pairs.append((mesh.uv[v], mesh.uv[remap[v]]))
            mesh.tris[ti] = tuple(new_tri)
            moved.append((ti, pairs))
        cursor += int(bw) + MARGIN + 1
    mesh.reweld()

    # -- 4. transfer texels into the new island, hair -> skin ----------------
    def sample_old(u, v):
        x = min(W - 1, max(0, int(u * W)))
        y = min(H - 1, max(0, int(v * H)))
        o = (y * W + x) * C
        return old_tex[o], old_tex[o + 1], old_tex[o + 2]

    written = to_skin = 0
    for ti, pairs in moved:
        (oa, na), (ob, nb), (oc, nc) = pairs
        ax, ay = na[0] * W, na[1] * H
        bx, by = nb[0] * W, nb[1] * H
        cx, cy = nc[0] * W, nc[1] * H
        d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(d) < 1e-12:
            continue
        inv = 1.0 / d
        for y in range(max(0, int(min(ay, by, cy)) - 1), min(H - 1, int(max(ay, by, cy)) + 1) + 1):
            for x in range(max(0, int(min(ax, bx, cx)) - 1), min(W - 1, int(max(ax, bx, cx)) + 1) + 1):
                px, py = x + 0.5, y + 0.5
                l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) * inv
                l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) * inv
                l3 = 1.0 - l1 - l2
                if min(l1, l2, l3) < -0.6:
                    continue
                # clamp into the triangle so the gutter samples the edge, not a neighbour
                c1, c2, c3 = max(0.0, l1), max(0.0, l2), max(0.0, l3)
                s = c1 + c2 + c3
                c1, c2, c3 = c1 / s, c2 / s, c3 / s
                u = c1 * oa[0] + c2 * ob[0] + c3 * oc[0]
                v = c1 * oa[1] + c2 * ob[1] + c3 * oc[1]
                col = sample_old(u, v)
                if classify(*col) == "hair":
                    col = SKIN
                    to_skin += 1
                o = (y * W + x) * C
                tex[o:o + 3] = bytes(col)
                written += 1
    print("forehead: %d texels transferred to the new island, %d of them hair -> skin"
          % (written, to_skin))

    # -- 5. slab texels the old arc left skin-coloured -> hair ----------------
    claims, where = owned_mask(mesh, W, H)
    cent = tri_centroids(mesh.pos, [v for t in mesh.tris for v in t])
    tips = 0
    for i in range(W * H):
        p = where[i]
        if p is None or not in_band(p):
            continue
        o = i * C
        if classify(tex[o], tex[o + 1], tex[o + 2]) != "skin":
            continue
        if relief(p) < RELIEF_SLAB:
            continue
        ok = True
        for t in (claims[i] or ()):
            if math.dist(cent[t], HEAD_C) > HEAD_R or relief(cent[t]) < RELIEF_SLAB:
                ok = False
                break
        if not ok:
            continue
        tex[o:o + 3] = bytes(HAIR)
        tips += 1
    print("fringe: %d skin-painted slab texels (strand tips) -> hair" % tips)

    pad_atlas(mesh, W, H, C, tex)
    png_save(out_png, W, H, C, tex)
    bin_ = rebuild(js, bin_, mesh, open(out_png, "rb").read())
    write_glb(out_glb, js, bin_)
    print("triangles %d, vertices %d; wrote %s and %s" % (len(mesh.tris), len(mesh.pos), out_glb, out_png))


if __name__ == "__main__":
    main()
