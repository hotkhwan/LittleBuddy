#!/usr/bin/env python3
"""Aliz's face head-on, orthographic, ONE PIXEL PER MILLIMETRE of model.

    python3 tools/aliz_ortho_face.py <in.glb> <atlas.png> <out.png> [--grid]

Every earlier instrument rendered through a camera, so reading "where is the
highlight" off the picture meant undoing a projection. This one does not: the
image plane IS model space -- x = X0 + px / 1000, y = Y1 - py / 1000 -- so a
feature measured on it can be typed straight into a painter that works in
metres (`aliz_face_pass.py`), and a mood patch can be judged against the base
face at exactly the same pixel positions.

Back faces are culled, nearest-z wins, the texture is sampled nearest-texel so
the atlas' own resolution is visible (it is ~2.5 texels per centimetre on the
face; that fact governs every stroke width in the face pass). `--grid` draws a
2 cm grid with a heavier line every 10 cm.

Importing it gives `render_ortho()` and `find_features()`.
"""

import math
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aliz_head_probe import read_glb, load_mesh  # noqa: E402
from png_edit import load as png_load, save as png_save  # noqa: E402

X0, X1, Y0, Y1 = -0.22, 0.22, 1.10, 1.50
MM = 1000


def render_ortho(pos, uv, idx, W, H, C, tex, x0=X0, x1=X1, y0=Y0, y1=Y1):
    """-> (w, h, rgb bytearray, depth list). Model metres in, millimetres out."""
    w, h = int(round((x1 - x0) * MM)), int(round((y1 - y0) * MM))
    depth = [-1e9] * (w * h)
    img = bytearray(w * h * 3)
    for t in range(0, len(idx), 3):
        a, b, c = idx[t], idx[t + 1], idx[t + 2]
        P = (pos[a], pos[b], pos[c])
        if max(p[2] for p in P) < -0.05:
            continue
        sx = [(p[0] - x0) * MM for p in P]
        sy = [(y1 - p[1]) * MM for p in P]
        minx, maxx = max(0, int(min(sx))), min(w - 1, int(max(sx)) + 1)
        miny, maxy = max(0, int(min(sy))), min(h - 1, int(max(sy)) + 1)
        if minx > maxx or miny > maxy:
            continue
        d = (sy[1] - sy[2]) * (sx[0] - sx[2]) + (sx[2] - sx[1]) * (sy[0] - sy[2])
        if abs(d) < 1e-9:
            continue
        # Geometric normal's z: a triangle facing away from +Z is culled.
        nz = ((P[1][0] - P[0][0]) * (P[2][1] - P[0][1])
              - (P[1][1] - P[0][1]) * (P[2][0] - P[0][0]))
        if nz <= 0:
            continue
        inv = 1.0 / d
        for y in range(miny, maxy + 1):
            py = y + 0.5
            for x in range(minx, maxx + 1):
                px = x + 0.5
                l1 = ((sy[1] - sy[2]) * (px - sx[2]) + (sx[2] - sx[1]) * (py - sy[2])) * inv
                l2 = ((sy[2] - sy[0]) * (px - sx[2]) + (sx[0] - sx[2]) * (py - sy[2])) * inv
                l3 = 1.0 - l1 - l2
                if l1 < 0 or l2 < 0 or l3 < 0:
                    continue
                z = l1 * P[0][2] + l2 * P[1][2] + l3 * P[2][2]
                i = y * w + x
                if z <= depth[i]:
                    continue
                depth[i] = z
                u = l1 * uv[a][0] + l2 * uv[b][0] + l3 * uv[c][0]
                v = l1 * uv[a][1] + l2 * uv[b][1] + l3 * uv[c][1]
                tx = min(W - 1, max(0, int(u * W)))
                ty = min(H - 1, max(0, int(v * H)))
                o = (ty * W + tx) * C
                img[i * 3:i * 3 + 3] = bytes((tex[o], tex[o + 1], tex[o + 2]))
    return w, h, img, depth


def to_model(px, py, x0=X0, y1=Y1):
    return x0 + (px + 0.5) / MM, y1 - (py + 0.5) / MM


def _components(mask, w, h, min_size=4):
    seen = bytearray(w * h)
    out = []
    for start in range(w * h):
        if not mask[start] or seen[start]:
            continue
        stack = [start]
        seen[start] = 1
        members = []
        while stack:
            i = stack.pop()
            members.append(i)
            x, y = i % w, i // w
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    j = ny * w + nx
                    if mask[j] and not seen[j]:
                        seen[j] = 1
                        stack.append(j)
        if len(members) >= min_size:
            out.append(members)
    out.sort(key=len, reverse=True)
    return out


def find_features(w, h, img, x0=X0, y1=Y1):
    """Measure the painted eyes off the ortho render, per side.

    -> {side: {"iris": (cx, cy, rx, ry), "highlights": [(cx, cy, rx, ry), ...],
               "box": (xmin, ymin, xmax, ymax), "lash": (r, g, b)}}
    `side` is -1 for x < 0 (her right) and +1 for x > 0 (her left). Everything
    in model metres. The iris is the teal component; the highlights are the
    white components inside it; the box is the union of teal, white and dark
    (lash) pixels near it -- the region a closed eye has to cover.
    """
    n = w * h
    teal = bytearray(n)
    white = bytearray(n)
    dark = bytearray(n)
    for i in range(n):
        r, g, b = img[i * 3], img[i * 3 + 1], img[i * 3 + 2]
        py = i // w
        y = y1 - (py + 0.5) / MM
        if not (1.22 < y < 1.44):
            continue
        if b > r + 20 and g > r + 20:
            teal[i] = 1
        elif r > 232 and g > 232 and b > 232:
            white[i] = 1
        elif r < 110 and g < 90 and b < 100:
            dark[i] = 1
    out = {}
    for side in (-1, 1):
        half = bytearray(1 if ((i % w) + 0.5) / MM + x0 > 0 else 0 for i in range(n))
        if side < 0:
            half = bytearray(1 - v for v in half)
        tmask = bytearray(teal[i] & half[i] for i in range(n))
        comps = _components(tmask, w, h, 40)
        if not comps:
            continue
        iris = comps[0]
        xs = [i % w for i in iris]
        ys = [i // w for i in iris]
        cx, cy = to_model(sum(xs) / len(xs), sum(ys) / len(ys), x0, y1)
        rx = (max(xs) - min(xs) + 1) / 2.0 / MM
        ry = (max(ys) - min(ys) + 1) / 2.0 / MM
        # Highlights: white components whose centroid is inside the iris ellipse.
        wmask = bytearray(white[i] & half[i] for i in range(n))
        highlights = []
        for comp in _components(wmask, w, h, 4):
            hx = [i % w for i in comp]
            hy = [i // w for i in comp]
            hcx, hcy = to_model(sum(hx) / len(hx), sum(hy) / len(hy), x0, y1)
            if math.hypot((hcx - cx) / rx, (hcy - cy) / ry) < 0.9:
                highlights.append((hcx, hcy,
                                   (max(hx) - min(hx) + 1) / 2.0 / MM,
                                   (max(hy) - min(hy) + 1) / 2.0 / MM))
        highlights.sort(key=lambda hl: -(hl[2] * hl[3]))
        # The eye box: teal + white + dark within reach of the iris.
        bx0, by0, bx1, by1 = 1e9, 1e9, -1e9, -1e9
        lash_acc = [0, 0, 0]
        lash_n = 0
        for i in range(n):
            if not half[i] or not (teal[i] or white[i] or dark[i]):
                continue
            mx, my = to_model(i % w, i // w, x0, y1)
            if abs(mx - cx) > rx + 0.05 or abs(my - cy) > ry + 0.05:
                continue
            bx0, by0 = min(bx0, mx), min(by0, my)
            bx1, by1 = max(bx1, mx), max(by1, my)
            if dark[i]:
                lash_acc[0] += img[i * 3]
                lash_acc[1] += img[i * 3 + 1]
                lash_acc[2] += img[i * 3 + 2]
                lash_n += 1
        lash = tuple(v // max(lash_n, 1) for v in lash_acc) if lash_n else (60, 40, 50)
        out[side] = {"iris": (cx, cy, rx, ry), "highlights": highlights,
                     "box": (bx0, by0, bx1, by1), "lash": lash}
    return out


def draw_grid(w, h, img):
    for gx in range(0, w, 20):
        heavy = (gx % 100 == 0)
        for y in range(h):
            i = (y * w + gx) * 3
            img[i] = img[i] // 2 if heavy else max(0, img[i] - 40)
    for gy in range(0, h, 20):
        heavy = (gy % 100 == 0)
        for x in range(w):
            i = (gy * w + x) * 3
            img[i + 1] = img[i + 1] // 2 if heavy else max(0, img[i + 1] - 40)


def main():
    glb, png, out = sys.argv[1:4]
    js, bin_ = read_glb(glb)
    m = load_mesh(js, bin_)
    W, H, C, tex = png_load(png)
    w, h, img, _ = render_ortho(m["pos"], m["uv"], m["idx"], W, H, C, tex)
    feats = find_features(w, h, img)
    for side, f in sorted(feats.items()):
        bx0, by0, bx1, by1 = f["box"]
        print("eye %s: iris c=(%.3f, %.3f) r=(%.3f, %.3f) box x %.3f..%.3f y %.3f..%.3f lash %s"
              % ("R(x<0)" if side < 0 else "L(x>0)", *f["iris"], bx0, bx1, by0, by1, f["lash"]))
        for hl in f["highlights"]:
            print("    highlight c=(%.3f, %.3f) r=(%.4f, %.4f)" % hl)
    if "--grid" in sys.argv:
        draw_grid(w, h, img)
    png_save(out, w, h, 3, img)
    print("wrote %s  %dx%d  (x = %.2f + px/1000, y = %.2f - py/1000)" % (out, w, h, X0, Y1))


if __name__ == "__main__":
    main()
