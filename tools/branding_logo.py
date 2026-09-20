#!/usr/bin/env python3
"""Runtime title textures from the owner-approved logo
`game/assets/uiGenerated/branding/littleDaysLogo.png` (2172x724 RGBA).

That folder is excluded from every export, so the shipped textures live under
`res://assets/branding/`. The logo is trimmed to its alpha bounding box (the
render has ~470 px of empty air on each side) and area-resampled with
premultiplied alpha, so the bubble letters keep a clean edge on cream.

Outputs:
  game/assets/branding/littleDaysLogo_1024.png   <= 1024 wide, RGBA
  game/assets/branding/littleDaysLogo_512.png    <= 512 wide, RGBA

Usage: python3 tools/branding_logo.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import png_edit as png  # noqa: E402
from branding_icons import resample_area, save_png  # noqa: E402

REPO = os.path.dirname(HERE)
SOURCE = os.path.join(REPO, "game/assets/uiGenerated/branding/littleDaysLogo.png")
OUT_DIR = os.path.join(REPO, "game/assets/branding")
# Alpha below this is the render's own soft halo, not the logo.
ALPHA_FLOOR = 6
# The render's "opaque" is 250..254; see tidy().
ALPHA_SNAP = 248
# Breathing room around the trimmed content, so a mipmap never clips a letter.
PAD = 6


def alpha_bounds(w, h, px):
    left, top, right, bottom = w, h, -1, -1
    for y in range(h):
        row = y * w * 4
        for x in range(w):
            if px[row + x * 4 + 3] > ALPHA_FLOOR:
                if x < left:
                    left = x
                if x > right:
                    right = x
                if y < top:
                    top = y
                if y > bottom:
                    bottom = y
    return left, top, right + 1, bottom + 1


def tidy(w, h, px):
    """Three byte-level clean-ups that together take the 1024 texture from
    660 KB to under 400 KB with no visible change:

      * the render has NO fully opaque pixel -- its alpha tops out at 254 with
        noise from 250 up. Anything >= ALPHA_SNAP becomes 255;
      * anything <= ALPHA_FLOOR becomes 0, with a neutral cream RGB underneath
        so nothing dark bleeds through bilinear filtering or a mipmap;
      * RGB is held to 6 bits per channel (64 levels). The pastel gradients
        show no banding at that depth; the generator's per-pixel dither did
        not compress and bought nothing."""
    out = bytearray(px)
    for i in range(w * h):
        a = out[i * 4 + 3]
        if a >= ALPHA_SNAP:
            out[i * 4 + 3] = 255
        elif a <= ALPHA_FLOOR:
            out[i * 4 + 3] = 0
            out[i * 4:i * 4 + 3] = b"\xff\xf6\xe5"
            continue
        for k in range(3):
            v = out[i * 4 + k] & 0xFC
            out[i * 4 + k] = v | (v >> 6)
    return out


def main():
    w, h, c, px = png.load(SOURCE)
    if c != 4:
        raise SystemExit("expected an RGBA logo, got %d channels" % c)
    x0, y0, x1, y1 = alpha_bounds(w, h, px)
    x0, y0 = max(0, x0 - PAD), max(0, y0 - PAD)
    x1, y1 = min(w, x1 + PAD), min(h, y1 + PAD)
    cw, ch = x1 - x0, y1 - y0
    print("branding_logo: content %dx%d at (%d,%d) of %dx%d" % (cw, ch, x0, y0, w, h))
    _, _, _, crop = png.crop(w, h, c, px, x0, y0, cw, ch)
    os.makedirs(OUT_DIR, exist_ok=True)
    for width in (1024, 512):
        height = int(round(ch * width / float(cw)))
        _, _, _, out = resample_area(cw, ch, 4, crop, width, height)
        out = tidy(width, height, out)
        path = os.path.join(OUT_DIR, "littleDaysLogo_%d.png" % width)
        save_png(path, width, height, 4, out)
        print("  wrote %s  %dx%d  %.1f KB" % (os.path.relpath(path, REPO), width, height,
                                              os.path.getsize(path) / 1024.0))


if __name__ == "__main__":
    main()
