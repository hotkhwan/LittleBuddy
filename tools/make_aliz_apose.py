#!/usr/bin/env python3
"""Swings Aliz's arms out, turning the reference render into an A-pose reference.

## Why this exists

Meshy's image-to-3D copies the pose in the picture. No prompt text will spread
the arms of a reference whose arms are down, and arms-down is exactly what made
the auto-rigger guess wrong the first time -- with the arms flat against the
body, the rigger cannot tell where the arm ends and the torso begins, which is
the same root cause as the shoulder and knee weight bleed that had to be
repaired by hand.

The source model's arms are down and cannot be re-posed (that is the problem).
But in a flat render each arm is an unambiguous patch of skin-coloured pixels,
and rotating a patch about a pivot is arithmetic.

## What it does

For each arm: find the skin pixels inside its box, erase them, and redraw them
rotated outward about the shoulder. Sampling is INVERSE -- for every destination
pixel it asks which source pixel lands there -- because the forward direction
leaves holes wherever the rotation stretches the image.

This is a REFERENCE IMAGE, not an asset. It is judged by whether a generator
reads "arms away from the body", not by whether it would survive a close-up.

    python3 tools/make_aliz_apose.py <in.png> <out.png> [degrees]
"""

import math
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from png_edit import load, save  # noqa: E402

# Each arm as (x0, y0, x1, y1, pivot_x, pivot_y, direction).
# The pivot is the shoulder; direction is the sign of the INVERSE rotation that
# swings that arm outward. The signs look backwards because the sampling is
# inverse -- the first version used the intuitive signs and folded both arms
# across the dress, which is what looking at the output showed.
# Measured off the 1024-square reference.
ARMS = [
    (338, 380, 432, 560, 410, 396, +1.0),   # her right, image left
    (580, 380, 678, 560, 604, 396, -1.0),   # her left, image right
]
DEFAULT_DEGREES = 38.0
WHITE = (255, 255, 255)


def is_skin(rgb):
    """Skin, as distinct from the dress, the hair and the white field.

    The dress colours are saturated (teal, yellow, purple, pink), the hair is
    strongly red-dominant, and the background is near-white. Skin sits in a
    narrow band: bright, red-leaning, but nowhere near as red-dominant as the
    hair.
    """
    r, g, b = rgb
    if r > 242 and g > 242 and b > 242:
        return False                      # background
    if r < 150:
        return False                      # too dark for this art
    if not (0.66 * r <= g <= 0.94 * r):
        return False                      # hair is far below, teal is above
    if not (0.55 * r <= b <= 0.90 * r):
        return False
    return g >= b                         # skin is warmer than it is cool


def is_skin_edge(rgb):
    """Skin, or a pixel blended between skin and the white field."""
    if is_skin(rgb):
        return True
    r, g, b = rgb
    if r > 248 and g > 248 and b > 248:
        return False                      # clean background, leave it
    if r < 170:
        return False
    # A blend toward white keeps skin's ordering (r >= g >= b) but flattens the
    # gaps between the channels.
    return r >= g >= b and (r - b) >= 6 and (r - b) <= 95


def main():
    src, dst = sys.argv[1], sys.argv[2]
    degrees = float(sys.argv[3]) if len(sys.argv) > 3 else DEFAULT_DEGREES
    w, h, c, px = load(src)
    original = bytes(px)

    def get(buf, x, y):
        if not (0 <= x < w and 0 <= y < h):
            return WHITE
        o = (y * w + x) * c
        return buf[o], buf[o + 1], buf[o + 2]

    def put(x, y, rgb):
        if not (0 <= x < w and 0 <= y < h):
            return
        o = (y * w + x) * c
        px[o], px[o + 1], px[o + 2] = int(rgb[0]), int(rgb[1]), int(rgb[2])

    moved = 0
    for (x0, y0, x1, y1, pvx, pvy, direction) in ARMS:
        angle = math.radians(degrees) * direction
        cos_a, sin_a = math.cos(angle), math.sin(angle)

        # 1. Erase the arm where it was. Only the skin: the dress and the hair
        #    behind it must survive, or the figure loses its silhouette.
        #
        # The erase test is LOOSER than the redraw test, deliberately. The edge
        # of the old arm is anti-aliased into the white field, and those blended
        # pixels are not skin by the strict test -- leaving them behind as thin
        # ghost outlines of arms that are no longer there. What gets erased must
        # cover what was drawn; what gets re-drawn should be only confident skin.
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if is_skin_edge(get(original, x, y)):
                    put(x, y, WHITE)

        # 2. Redraw it rotated. The destination box is widened because the hand
        #    swings well outside the column the arm hung in.
        reach = int((y1 - y0) * 1.2)
        for y in range(y0 - 20, y1 + reach):
            for x in range(x0 - reach, x1 + reach):
                # Inverse rotation: where did this destination pixel come from?
                dx, dy = x - pvx, y - pvy
                sx = pvx + dx * cos_a + dy * sin_a
                sy = pvy - dx * sin_a + dy * cos_a
                if not (x0 <= sx <= x1 and y0 <= sy <= y1):
                    continue
                sample = get(original, int(round(sx)), int(round(sy)))
                if not is_skin(sample):
                    continue
                put(x, y, sample)
                moved += 1

    save(dst, w, h, c, px)
    print("wrote %s  (%d arm pixels re-posed at %.0f degrees)" % (dst, moved, degrees))


if __name__ == "__main__":
    main()
