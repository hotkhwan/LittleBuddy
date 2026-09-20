#!/usr/bin/env python3
"""Contact sheet of Bunny's moods IN ENGINE, from the frames
`tools/bunny_shots.gd -- <prefix>` writes: one column per cell, the head
portrait (half size) on top, the feeding-distance frame cropped to the child
at 1:1 in the middle and at 2x underneath.

    python3 tools/bunny_face_strip.py <prefix> <out.png> [cell ...]
"""

import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from png_edit import load, save, crop, scale  # noqa: E402

CLOSE_BOX = (430, 150, 480, 450)     # head portrait, in the 1334x750 close frame
FAR_BOX = (567, 250, 200, 260)       # the child, in the far frame, 1:1
GAP = 6
BG = (40, 40, 40)
LABEL = {"content": (120, 200, 120), "hungry": (240, 150, 60), "sleepy": (170, 120, 220),
         "happy": (240, 190, 60), "hmph": (230, 100, 120), "hmph_land": (200, 80, 100),
         "blink": (90, 90, 90), "unhappy": (120, 160, 240), "asleep": (110, 90, 170)}


def half(w, h, px):
    out = bytearray()
    for y in range(0, h - h % 2, 2):
        for x in range(0, w - w % 2, 2):
            o = (y * w + x) * 3
            out += px[o:o + 3]
    return w // 2, h // 2, out


def paste(canvas, cw, img, iw, ih, x0, y0):
    for y in range(ih):
        o = ((y0 + y) * cw + x0) * 3
        canvas[o:o + iw * 3] = img[y * iw * 3:(y + 1) * iw * 3]


def main():
    prefix, out = sys.argv[1], sys.argv[2]
    cells = sys.argv[3:] or ["content", "hungry", "sleepy", "happy", "hmph", "hmph_land",
                             "blink", "unhappy", "asleep"]
    columns = []
    for cell in cells:
        W, H, C, px = load("docs/shots/%s_%s_close.png" % (prefix, cell))
        cw, ch, _, cp = crop(W, H, C, px, *CLOSE_BOX)
        cw, ch, cp = half(cw, ch, cp)
        W, H, C, px = load("docs/shots/%s_%s_far.png" % (prefix, cell))
        fw, fh, _, fp = crop(W, H, C, px, *FAR_BOX)
        zw, zh, _, zp = scale(fw, fh, C, fp, 2)
        columns.append((cell, (cw, ch, cp), (fw, fh, fp), (zw, zh, zp)))
    col_w = max(max(c[1][0], c[3][0]) for c in columns)
    row_h = [max(c[k][1] for c in columns) for k in (1, 2, 3)]
    width = GAP + len(columns) * (col_w + GAP)
    height = GAP + 8 + sum(h + GAP for h in row_h)
    canvas = bytearray(bytes(BG) * (width * height))
    for k, (cell, close, far, zoom) in enumerate(columns):
        x0 = GAP + k * (col_w + GAP)
        col = bytes(LABEL.get(cell, (200, 200, 200)))
        for y in range(GAP, GAP + 6):
            canvas[(y * width + x0) * 3:(y * width + x0 + col_w) * 3] = col * col_w
        y0 = GAP + 8
        for tile, h in zip((close, far, zoom), row_h):
            paste(canvas, width, tile[2], tile[0], tile[1], x0, y0)
            y0 += h + GAP
    save(out, width, height, 3, canvas)
    print("wrote %s (%dx%d): %s" % (out, width, height, ", ".join(cells)))


if __name__ == "__main__":
    main()
