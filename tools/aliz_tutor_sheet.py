#!/usr/bin/env python3
"""Tiles the in-engine tutor shots (`tools/aliz_tutor_shots.gd`) into contact
sheets: a row of face crops at 1:1 (the tutor camera's own pixels) over a row
of the same faces' eye-and-mouth region at 3x, plus strips for the mouth
envelope and each gesture. No font dependency: a coloured bar labels each tile.

    python3 tools/aliz_tutor_sheet.py docs/shots aliz_tutor

Writes docs/shots/<prefix>_expressions_sheet.png, <prefix>_mouth_sheet.png,
<prefix>_envelope_strip.png, <prefix>_gesture_<name>_strip.png and the ten
strips stacked as <prefix>_gesture_sheet.png.
"""

import os
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from png_edit import load as png_load, save as png_save, crop, scale  # noqa: E402

## Face box at the tutor camera (1334x750): x, y, w, h.
FACE = (470, 240, 400, 290)
## The eyes-and-mouth region shown at 3x.
DETAIL = (540, 300, 260, 180)
## Full frame, halved, for the gesture strips (arms need the whole body).
GESTURE = (267, 0, 800, 750)
## The face at the gesture camera, 1:1, under each state strip.
STATE_FACE = (555, 225, 230, 180)
## Strip order on the gesture sheet: the five contract gestures, then the
## 2026-09-22 set (docs/ALIZ_GESTURES.md).
GESTURES = ["nod", "tilt", "point", "clap", "wave",
            "thumbsUp", "celebrate", "listening", "thinking", "encourage"]

LABELS = {"neutral": (120, 200, 120), "listening": (120, 160, 240), "thinking": (170, 120, 220),
          "happy": (240, 190, 60), "encouraging": (240, 140, 90), "smile": (230, 100, 140),
          "0": (90, 90, 90), "1": (130, 130, 130), "2": (170, 170, 170), "3": (210, 210, 210)}


def tile(paths, box, factor, labels, bar=8, gap=6):
    tiles = []
    for path, label in zip(paths, labels):
        W, H, C, px = png_load(path)
        x, y, w, h = box
        cw, ch, cc, cp = crop(W, H, C, px, x, y, w, h)
        if factor != 1:
            if factor > 1:
                cw, ch, cc, cp = scale(cw, ch, cc, cp, factor)
            else:
                cw, ch, cc, cp = downscale(cw, ch, cc, cp, int(round(1 / factor)))
        col = bytes(LABELS.get(label, (200, 200, 200)))
        for yy in range(bar):
            cp[yy * cw * cc:(yy + 1) * cw * cc] = (col + b"\xff" * (cc - 3)) * cw
        tiles.append((cw, ch, cc, cp))
    tw, th, tc = tiles[0][0], tiles[0][1], tiles[0][2]
    width = gap + len(tiles) * (tw + gap)
    height = th + 2 * gap
    canvas = bytearray((bytes((40, 40, 40)) + b"\xff" * (tc - 3)) * (width * height))
    for k, (w, h, c, p) in enumerate(tiles):
        x0 = gap + k * (tw + gap)
        for yy in range(h):
            o = ((gap + yy) * width + x0) * tc
            canvas[o:o + w * tc] = p[yy * w * tc:(yy + 1) * w * tc]
    return width, height, tc, canvas


def downscale(w, h, c, p, n):
    ow, oh = w // n, h // n
    out = bytearray(ow * oh * c)
    for y in range(oh):
        for x in range(ow):
            for ch in range(c):
                acc = 0
                for dy in range(n):
                    for dx in range(n):
                        acc += p[((y * n + dy) * w + (x * n + dx)) * c + ch]
                out[(y * ow + x) * c + ch] = acc // (n * n)
    return ow, oh, c, out


def stack(rows, gap=6):
    width = max(r[0] for r in rows)
    c = rows[0][2]
    height = sum(r[1] for r in rows) + gap * (len(rows) - 1)
    canvas = bytearray((bytes((40, 40, 40)) + b"\xff" * (c - 3)) * (width * height))
    y0 = 0
    for w, h, _c, p in rows:
        for yy in range(h):
            o = ((y0 + yy) * width) * c
            canvas[o:o + w * c] = p[yy * w * c:(yy + 1) * w * c]
        y0 += h + gap
    return width, height, c, canvas


def main():
    shots, prefix = sys.argv[1:3]
    p = lambda name: os.path.join(shots, "%s_%s.png" % (prefix, name))  # noqa: E731

    expr = ["neutral", "listening", "thinking", "happy", "encouraging", "smile"]
    rows = [tile([p("expr_" + e) for e in expr], FACE, 1, expr),
            tile([p("expr_" + e) for e in expr], DETAIL, 3, expr)]
    out = os.path.join(shots, "%s_expressions_sheet.png" % prefix)
    png_save(out, *stack(rows))
    print("wrote", out)

    frames = ["0", "1", "2", "3"]
    rows = [tile([p("mouth_" + f) for f in frames], FACE, 1, frames),
            tile([p("mouth_" + f) for f in frames], DETAIL, 3, frames)]
    out = os.path.join(shots, "%s_mouth_sheet.png" % prefix)
    png_save(out, *stack(rows))
    print("wrote", out)

    env = [str(k) for k in range(6)]
    out = os.path.join(shots, "%s_envelope_strip.png" % prefix)
    png_save(out, *tile([p("env_" + k) for k in env], DETAIL, 2, env))
    print("wrote", out)

    gesture_rows = []
    for name in GESTURES:
        keys = [str(k) for k in range(5)]
        paths = [p("gesture_%s_%s" % (name, k)) for k in keys]
        if not all(os.path.exists(x) for x in paths):
            continue
        row = tile(paths, GESTURE, 0.5, keys)
        out = os.path.join(shots, "%s_gesture_%s_strip.png" % (prefix, name))
        png_save(out, *row)
        print("wrote", out)
        gesture_rows.append(row)
    if gesture_rows:
        out = os.path.join(shots, "%s_gesture_sheet.png" % prefix)
        png_save(out, *stack(gesture_rows))
        print("wrote", out)

    for name in ["interrupted", "explaining", "celebrating"]:
        keys = [str(k) for k in range(5)]
        paths = [p("state_%s_%s" % (name, k)) for k in keys]
        if not all(os.path.exists(x) for x in paths):
            continue
        out = os.path.join(shots, "%s_state_%s_strip.png" % (prefix, name))
        png_save(out, *stack([tile(paths, GESTURE, 0.5, keys),
                              tile(paths, STATE_FACE, 1, keys)]))
        print("wrote", out)


if __name__ == "__main__":
    main()
