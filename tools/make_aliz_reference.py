#!/usr/bin/env python3
"""Builds the standalone Aliz reference image an image-to-3D regeneration needs.

## Why in 2D and not on the model

The open-mouthed grin is modelled geometry, and the model's UV atlas is
fragmented into dozens of interleaved islands -- an earlier attempt to edit it
kept selecting leg and dress vertices along with the face. In a flat RENDER the
mouth is an unambiguous rectangle of pixels, so the correction that is unsafe on
the mesh is trivial here.

That matters because the reference image is the thing a regeneration copies.
Fixing the smile here fixes it in the generated model, which is the only place it
was ever going to be fixable without a 3D package.

## What it does

  1. Paints out the open mouth, rebuilding the skin by interpolating between the
     rows just above and just below it -- so the chin's shading survives instead
     of becoming a flat patch.
  2. Draws a gentle closed smile: a shallow upward arc in a slightly deeper rose
     than the skin, with softened ends so it does not read as a drawn-on line.

Everything else -- the pink hair, the eyes, the striped dress, the shoes -- is
untouched, because her identity is the part that must survive.

    python3 tools/make_aliz_reference.py <in.png> <out.png>
"""

import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from png_edit import load, save  # noqa: E402

# The mouth, measured off the 1024-square render (see the crop in the delivery
# doc). Generous by a couple of pixels so no dark rim survives at the edges.
MOUTH = (476, 198, 548, 248)   # x0, y0, x1, y1
# The smile: how far below the mouth box's middle the arc sits, and how far its
# ends rise. Small numbers -- a big curve reads as a grin, which is the thing
# being removed.
SMILE_DROP = 0.30
SMILE_RISE = 0.22

## The fringe band: from the top of the modelled hair down to just above the
## eyes. Stops short of the eyes on purpose -- an eyebrow is not a gap.
FRINGE = (424, 34, 634, 118)
## Below this green-to-red ratio a pixel is hair; above it, it is skin, white or
## a highlight showing through a gap.
HAIR_GREEN_RATIO = 0.66


def main():
    src, dst = sys.argv[1], sys.argv[2]
    w, h, c, px = load(src)

    def get(x, y):
        o = (y * w + x) * c
        return px[o], px[o + 1], px[o + 2]

    def put(x, y, rgb, alpha=1.0):
        if not (0 <= x < w and 0 <= y < h):
            return
        o = (y * w + x) * c
        for i in range(3):
            px[o + i] = int(round(px[o + i] * (1.0 - alpha) + rgb[i] * alpha))

    x0, y0, x1, y1 = MOUTH
    above_y = max(0, y0 - 3)
    below_y = min(h - 1, y1 + 3)

    # 1. Rebuild the skin, column by column, between the rows that bracket the
    #    mouth. Interpolating rather than flood-filling is what keeps the chin
    #    from turning into a sticker.
    for x in range(x0, x1 + 1):
        top = get(x, above_y)
        bottom = get(x, below_y)
        span = float(below_y - above_y)
        for y in range(y0, y1 + 1):
            t = (y - above_y) / span
            put(x, y, tuple(top[i] * (1.0 - t) + bottom[i] * t for i in range(3)))

    # 2. Draw the smile.
    cx = (x0 + x1) * 0.5
    cy = (y0 + y1) * 0.5
    half_w = (x1 - x0) * 0.40
    half_h = (y1 - y0) * 0.5
    base_y = cy + half_h * SMILE_DROP
    for step in range(int(half_w * 2) + 1):
        x = int(round(cx - half_w + step))
        u = (x - cx) / max(half_w, 1.0)
        if abs(u) > 1.0:
            continue
        y = base_y - (SMILE_RISE * half_h * 2.0) * (u * u)
        skin = get(x, int(y) - 6)
        line = tuple(max(0, skin[i] - v) for i, v in enumerate((58, 78, 74)))
        # Fades out at the corners, so the arc ends rather than stopping.
        fade = 1.0 - (abs(u) ** 3)
        put(x, int(round(y)), line, 0.92 * fade)
        put(x, int(round(y)) + 1, line, 0.55 * fade)
        put(x, int(round(y)) - 1, line, 0.30 * fade)
        # A soft lower lip, which is what stops a closed mouth reading as a scar.
        lip = tuple(max(0, skin[i] - v) for i, v in enumerate((16, 30, 26)))
        for d in range(2, 6):
            put(x, int(round(y)) + d, lip, 0.30 * fade * (1.0 - d / 6.0))

    # 3. Close the fringe.
    #
    # The hair is modelled as separate strands with real gaps between them, so
    # the forehead shows through in wedges and there is a hole clean to the
    # background at the right temple. A generated model copies whatever the
    # reference shows, so a torn fringe here would be a torn fringe again.
    #
    # Each gap pixel takes the colour of the nearest HAIR pixel above it in its
    # own column, which keeps the fringe's shading instead of flattening it into
    # a pink block.
    fx0, fy0, fx1, fy1 = FRINGE

    def is_hair(rgb):
        # Pink hair is strongly red-dominant; skin and white are not.
        return rgb[0] > 90 and rgb[1] < rgb[0] * HAIR_GREEN_RATIO

    for x in range(fx0, fx1 + 1):
        for y in range(fy0, fy1 + 1):
            if is_hair(get(x, y)):
                continue
            source = None
            for up in range(y - 1, max(-1, fy0 - 26), -1):
                candidate = get(x, up)
                if is_hair(candidate):
                    source = candidate
                    break
            if source is None:
                continue
            put(x, y, source)

    save(dst, w, h, c, px)
    print("wrote %s" % dst)


if __name__ == "__main__":
    main()
