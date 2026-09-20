#!/usr/bin/env python3
"""Contact sheet of Aliz's moods IN ENGINE: the `_close` and `_far` frames
`tools/aliz_shots.gd -- <prefix> mood` writes, cropped to the face and tiled --
close-ups on the top row, the gameplay-distance face at 1:1 in the middle row
and at 3x underneath, one column per mood plus the blink frame.

    python3 tools/aliz_face_strip.py <prefix> <out.png> [mood ...]

Defaults to content, happy, surprised, sleepy, blink. The crop boxes are the
head's position in those two fixed framings (`_close`: 34 degree lens at
1.05 m; `_far`: the bedroom framing).
"""

import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from png_edit import load, save, crop, scale  # noqa: E402

CLOSE_BOX = (380, 120, 580, 480)      # x, y, w, h in the 1334x750 close frame
FAR_BOX = (600, 235, 130, 130)        # the face in the far frame, 1:1
GAP = 6
BG = (40, 40, 40)
LABEL = {"content": (120, 200, 120), "happy": (240, 190, 60), "surprised": (120, 160, 240),
         "sleepy": (170, 120, 220), "blink": (90, 90, 90)}


def paste(canvas, cw, img, iw, ih, x0, y0):
    for y in range(ih):
        o = ((y0 + y) * cw + x0) * 3
        canvas[o:o + iw * 3] = img[y * iw * 3:(y + 1) * iw * 3]


def main():
    prefix, out = sys.argv[1], sys.argv[2]
    moods = sys.argv[3:] or ["content", "happy", "surprised", "sleepy", "blink"]
    columns = []
    for mood in moods:
        W, H, C, px = load("docs/shots/%s_mood_%s_close.png" % (prefix, mood))
        cw, ch, _, cp = crop(W, H, C, px, *CLOSE_BOX)
        # Close-up shown at half size so a column is not 480 px tall.
        half = bytearray()
        for y in range(0, ch, 2):
            for x in range(0, cw, 2):
                o = (y * cw + x) * 3
                half += cp[o:o + 3]
        cw, ch, cp = cw // 2, ch // 2, half
        W, H, C, px = load("docs/shots/%s_mood_%s_far.png" % (prefix, mood))
        fw, fh, _, fp = crop(W, H, C, px, *FAR_BOX)
        zw, zh, _, zp = scale(fw, fh, C, fp, 3)
        columns.append((mood, (cw, ch, cp), (fw, fh, fp), (zw, zh, zp)))
    col_w = max(max(c[1][0], c[3][0]) for c in columns)
    row_h = [max(c[k][1] for c in columns) for k in (1, 2, 3)]
    width = GAP + len(columns) * (col_w + GAP)
    height = GAP + 8 + sum(h + GAP for h in row_h)
    canvas = bytearray(bytes(BG) * (width * height))
    for k, (mood, close, far, zoom) in enumerate(columns):
        x0 = GAP + k * (col_w + GAP)
        col = bytes(LABEL.get(mood, (200, 200, 200)))
        for y in range(GAP, GAP + 6):
            canvas[(y * width + x0) * 3:(y * width + x0 + col_w) * 3] = col * col_w
        y0 = GAP + 8
        for tile, h in zip((close, far, zoom), row_h):
            paste(canvas, width, tile[2], tile[0], tile[1], x0, y0)
            y0 += h + GAP
    save(out, width, height, 3, canvas)
    print("wrote %s (%dx%d): %s -- close-up (half size) / far 1:1 / far 3x"
          % (out, width, height, ", ".join(moods)))


if __name__ == "__main__":
    main()
