#!/usr/bin/env python3
"""Repaint Aliz's smile on the shipping atlas: wider, gentler, warmer.

    python3 tools/aliz_smile_repaint.py <in.glb> <in.png> <out.glb> <out.png>

Texture only. The mesh is read to map texels to 3D (`claim_map`) and to
rewrite the GLB's embedded copy of the atlas; no vertex, normal, UV or index
changes.

## The brief (owner feedback from the real build, 2026-09-20)

"Mouth looks too pursed." The shipped smile is 60 mm wide on a head 0.73 m
wide -- 8 % of the head -- with sharp horizontal ends, in the art bible's
`#9E4F4D`, which on a 512-square atlas at menu distance mip-averages to a
small dark dot. Asked for: roughly 1.3-1.5x the width, soft upturned corners,
a touch lighter and warmer, no teeth, no lip line, identity kept.

## What is drawn

One filled shape (art bible section 4), expressed as a signed distance in
model metres so it feathers identically across the three atlas islands that
reach the patch:

* a centreline `y = CY + ARC * u^2` (u = x / HALF_W) that rises toward both
  corners -- the upturn;
* half-thickness that is greatest in the middle and tapers toward the ends;
* **round caps** at both ends, so the corners are soft dots rather than the
  hard horizontal cut the old band had.

`HALF_W` 0.030 -> 0.042 m (1.4x). The ink is `#B85E5C`, one step lighter and
warmer than `#9E4F4D`; the art bible's exact hex is a resting-face spec for a
character the bible imagined at 1:6.5 proportions, and on this 1:3 head at
this texel density the darker ink reads as a hole. Recorded as a deliberate
deviation in docs/ALIZ_POLISH_PASS.md.

The whole mouth patch (the same ellipse `aliz_local_pass.py` used) is
repainted skin first, so the old smile cannot ghost through, and the write is
guarded the same way: a texel is written only if every triangle claiming it
lies inside the head sphere. Then the atlas gutters are re-padded so the
mipmaps average the new colour, not the old.
"""

import math
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aliz_head_probe import read_glb, write_glb, load_mesh  # noqa: E402
from aliz_local_pass import (claim_map, tri_centroids, blend, patch_weight,  # noqa: E402
                             replace_embedded_image, SKIN)
from aliz_polish_pass import Mesh, pad_atlas  # noqa: E402
from png_edit import load as png_load, save as png_save  # noqa: E402

SMILE_CX, SMILE_CY = 0.000, 1.1830
SMILE_HALF_W = 0.0420       # was 0.0300
SMILE_HALF_T = 0.0031       # half-thickness at the middle (was 0.0064 total depth)
SMILE_END_T = 0.55          # fraction of that thickness at the corners
SMILE_ARC = 0.0080          # corners ride up by this much (was 0.0062)
SMILE_AA = 0.0018
MOUTH_INK = (184, 94, 92)   # #B85E5C

HEAD_C = (0.0, 1.400, 0.0)
HEAD_R = 0.360


def smile_sdf(x, y):
    """Signed distance (metres) to the smile shape; negative inside."""
    u = x / SMILE_HALF_W
    if abs(u) <= 1.0:
        mid = SMILE_CY + SMILE_ARC * u * u
        half_t = SMILE_HALF_T * (SMILE_END_T + (1.0 - SMILE_END_T) * (1.0 - u * u))
        return abs(y - mid) - half_t
    # round cap: distance to the end point, minus the end half-thickness
    ex = math.copysign(SMILE_HALF_W, x)
    ey = SMILE_CY + SMILE_ARC
    return math.hypot(x - ex, y - ey) - SMILE_HALF_T * SMILE_END_T


def smile_weight(x, y):
    d = smile_sdf(x, y)
    if d <= -SMILE_AA:
        return 1.0
    if d >= SMILE_AA:
        return 0.0
    t = (SMILE_AA - d) / (2.0 * SMILE_AA)
    return t * t * (3.0 - 2.0 * t)


def main():
    in_glb, in_png, out_glb, out_png = sys.argv[1:5]
    js, bin_ = read_glb(in_glb)
    m = load_mesh(js, bin_)
    pos, uv, idx = m["pos"], m["uv"], m["idx"]
    W, H, C, tex = png_load(in_png)

    claims, where = claim_map(pos, uv, idx, W, H)
    cent = tri_centroids(pos, idx)

    def on_head(i):
        for t in (claims[i] or ()):
            if math.dist(cent[t], HEAD_C) > HEAD_R:
                return False
        return True

    painted = ink = refused = 0
    for i in range(W * H):
        p = where[i]
        if p is None or p[2] <= 0.0:
            continue
        x, y = p[0] - SMILE_CX, p[1]
        k = patch_weight(x, y)
        if k <= 0.0:
            continue
        if not on_head(i):
            refused += 1
            continue
        w = smile_weight(x, y)
        col = blend(SKIN, MOUTH_INK, w)
        o = i * C
        tex[o:o + 3] = bytes(blend((tex[o], tex[o + 1], tex[o + 2]), col, k))
        painted += 1
        if w > 0.5:
            ink += 1
    print("smile: repainted %d patch texels (%d ink); %d writes refused (claimant off the head)"
          % (painted, ink, refused))
    print("smile: %.0f mm wide, %.1f mm thick at the middle, corners up %.1f mm, ink #%02X%02X%02X"
          % (SMILE_HALF_W * 2000, SMILE_HALF_T * 2000, SMILE_ARC * 1000, *MOUTH_INK))

    # Re-pad the gutters from the (now changed) owned texels.
    mesh = Mesh(js, bin_)
    pad_atlas(mesh, W, H, C, tex)

    png_save(out_png, W, H, C, tex)
    bin_ = replace_embedded_image(js, bin_, open(out_png, "rb").read())
    write_glb(out_glb, js, bin_)
    print("wrote %s and %s (embedded atlas replaced)" % (out_png, out_glb))


if __name__ == "__main__":
    main()
