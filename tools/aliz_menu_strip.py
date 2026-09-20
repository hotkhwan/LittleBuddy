#!/usr/bin/env python3
"""Aliz's face cut from two 1334x750 menu shots at 1:1, side by side, with a
4x nearest-neighbour copy of each underneath -- so a judgement about the mouth
at MENU distance is made at the size a child actually sees it, not on a
close-up that hides what mipmaps and 60 pixels do to a face.

    python3 tools/aliz_menu_strip.py <before.png> <after.png> <out.png> [x y w h]

The default box is where the head sits in the current menu composition.
"""

import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from png_edit import load, save, crop, scale  # noqa: E402

GAP = 6
BG = (40, 40, 40)


def paste(canvas, cw, ch, cc, img, iw, ih, ic, x0, y0):
    for y in range(ih):
        row = img[y * iw * ic:(y + 1) * iw * ic]
        o = ((y0 + y) * cw + x0) * cc
        canvas[o:o + iw * cc] = row


def main():
    before, after, out = sys.argv[1:4]
    x, y, w, h = (int(v) for v in sys.argv[4:8]) if len(sys.argv) > 7 else (515, 185, 110, 120)
    tiles = []
    for path in (before, after):
        W, H, C, px = load(path)
        cw, ch, cc, cp = crop(W, H, C, px, x, y, w, h)
        tiles.append((cw, ch, cc, cp))
        tiles.append(scale(cw, ch, cc, cp, 4))
    C = tiles[0][2]
    width = GAP + tiles[1][0] + GAP + tiles[3][0] + GAP
    height = GAP + tiles[0][1] + GAP + tiles[1][1] + GAP
    canvas = bytearray(bytes(BG[:C]) * (width * height))
    # top row: the two 1:1 crops, left-aligned over their 4x copies
    paste(canvas, width, height, C, tiles[0][3], tiles[0][0], tiles[0][1], C, GAP, GAP)
    paste(canvas, width, height, C, tiles[2][3], tiles[2][0], tiles[2][1], C, GAP + tiles[1][0] + GAP, GAP)
    yb = GAP + tiles[0][1] + GAP
    paste(canvas, width, height, C, tiles[1][3], tiles[1][0], tiles[1][1], C, GAP, yb)
    paste(canvas, width, height, C, tiles[3][3], tiles[3][0], tiles[3][1], C, GAP + tiles[1][0] + GAP, yb)
    save(out, width, height, C, canvas)
    print("wrote %s  (%dx%d): before | after, 1:1 on top, 4x below" % (out, width, height))


if __name__ == "__main__":
    main()
