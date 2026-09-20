#!/usr/bin/env python3
"""The verdict on both reported defects, from the forward render rather than
from the atlas. Read-only.

Prints, for the mouth region and the forehead region, what each screen pixel
actually hits: a surface triangle, a triangle recessed inside the head, or
nothing at all. That is the difference between "geometry" and "texture", and it
decides which fix is even possible.

    python3 tools/aliz_diagnose.py <glb> <atlas.png>
"""

import sys
from collections import defaultdict

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aliz_screen_probe import render, texel, classify  # noqa: E402


def main():
    glb, png = sys.argv[1], sys.argv[2]
    buf = render(glb, png, head_y=1.24)
    size = buf["size"]

    # A reference depth for "the face surface": the shallowest hit anywhere on
    # the front of the head. Everything is compared against the local surface,
    # not against this, but it anchors the numbers.
    print("== per-pixel classes over the whole frame ==")
    census = defaultdict(int)
    for i in range(size * size):
        c = texel(buf, i)
        census["background" if c is None else classify(*c)] += 1
    for k in sorted(census, key=lambda x: -census[x]):
        print("  %-12s %d" % (k, census[k]))

    def region(name, x0, y0, x1, y1):
        print("\n== %s  screen x[%d,%d] y[%d,%d] ==" % (name, x0, x1, y0, y1))
        cls = defaultdict(int)
        zs = []
        miss = 0
        for y in range(y0, y1):
            for x in range(x0, x1):
                i = y * size + x
                c = texel(buf, i)
                if c is None:
                    miss += 1
                    cls["background"] += 1
                    continue
                cls[classify(*c)] += 1
                zs.append((buf["depth"][i], buf["pos"][i][2], x, y))
        for k in sorted(cls, key=lambda t: -cls[t]):
            print("   %-12s %d" % (k, cls[k]))
        if zs:
            zs.sort()
            print("   depth  nearest=%.4f  farthest=%.4f  spread=%.1f mm"
                  % (zs[0][0], zs[-1][0], (zs[-1][0] - zs[0][0]) * 1000 * buf["scale"]))
            print("   model z  front=%.4f  back=%.4f" % (zs[0][1], zs[-1][1]))
        print("   background pixels: %d" % miss)

    region("MOUTH", 250, 380, 395, 485)
    region("FOREHEAD / BANGS", 150, 20, 500, 175)
    region("CROWN + upper hair", 60, 0, 580, 120)

    # Hair-gap detail: every pixel in the bang band that is NOT hair.
    print("\n== bang-band pixels that are not hair ==")
    runs = defaultdict(int)
    for y in range(20, 175):
        for x in range(150, 500):
            i = y * size + x
            c = texel(buf, i)
            k = "background" if c is None else classify(*c)
            if k not in ("hair",):
                runs[k] += 1
                if runs[k] <= 3:
                    p = buf["pos"][i]
                    print("   sample %-11s at (%d,%d) pos=%s" % (
                        k, x, y, None if p is None else "(%.3f,%.3f,%.3f)" % p))
    for k in sorted(runs, key=lambda t: -runs[t]):
        print("   %-12s %d" % (k, runs[k]))


if __name__ == "__main__":
    main()
