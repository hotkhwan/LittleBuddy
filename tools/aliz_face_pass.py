#!/usr/bin/env python3
"""Aliz's face -- kinder and warmer -- and her MOODS. Texture only, zero credits.

    python3 tools/aliz_face_pass.py <in.glb> <in.png> <out.glb> <out.png>

Writes, next to `<out.png>` (stem = its basename without `_texture_0.png`):

    <stem>_face_eyesClosed.png   RGBA patch: both eyes shut (blink / sleepy)
    <stem>_face_mouthOpen.png    RGBA patch: the warm open smile (happy)
    <stem>_face_mouthO.png       RGBA patch: a small round "o" (surprised)
    <stem>_face_browsUp.png      RGBA patch: brows lifted (surprised)
    <stem>_faces.json            the manifest `buddy_face.gd` reads

## What the base pass changes (owner brief, 2026-09-20)

The design targets are `game/assets/uiGenerated/branding/appIconSource.png`
and `littleDaysLogo.png`: big teal eyes with bright highlights, soft blush, a
warm open smile, kind brows, warm peach skin. Measured against the shipping
atlas (`aliz_ortho_face.py`, 1 px = 1 mm):

* **skin** is a flat (253, 206, 182); the icon's forehead is (253, 212, 180).
  Every skin-family texel in the atlas moves +6 green / -3 blue: warmer, not
  lighter, and the body matches the face because the shift is global.
* **eye highlights** are a 19x16 mm white lens at the upper-outer quarter of
  each iris. They grow 1.3x and go to pure white, and a second small catchlight
  is added low on the opposite side -- the icon has two per eye.
* **blush** was two faint pink ovals hard against the eye sockets. The old pink
  is pulled halfway back to skin and a wider, softer oval is laid lower on the
  cheek in the icon's rose (252, 176, 166) at 50 % peak, feathered over the
  outer half of its radius.
* **brows** did not exist on the atlas -- the generator left them under the
  fringe. A soft rose-brown arch (212, 116, 128) is drawn 8 mm above each lash
  line, kind (arched, not angled), written only onto skin texels so the fringe
  above it is untouched.
* **the smile** goes from 84 mm x 6.2 mm in #B85E5C to 92 mm x 10 mm in
  (206, 104, 100), corners up 9 mm. Fuller and warmer, still closed. The mouth
  GEOMETRY is not touched: the polish pass flattened the cavity and this pass
  never reopens it.

## What the moods are

The same thing `baby_face_moods.gd` does for Bunny, done offline because her
atlas is fragmented: the mouth alone is spread over three islands and the
eyes over four, so a runtime rectangle cannot address a feature. Each mood
layer is painted here in MODEL METRES through the same 3D -> texel claim map
`aliz_smile_repaint.py` uses, the result is diffed against the new base, and
only the changed texels are written, as an RGBA patch cropped to their
bounding box. At runtime `buddy_face.gd` copies the base and `blend_rect`s the
active layers on -- a few hundred kilobytes, a handful of times a minute.

    mood        layers
    content     (none -- the base atlas)
    happy       mouthOpen
    surprised   mouthO + browsUp
    sleepy      eyesClosed
    (blink)     eyesClosed, for 120 ms

Gutters are re-padded per layer from the same wave order the base used, so the
mipmaps of a patched atlas average the patched colours at island edges.

## Guard

The manifest records six probe texels of the NEW base. `buddy_face.gd`
refuses to patch an atlas whose probes do not match -- a re-export moves the
islands, and a blink painted onto an ear is worse than no blink.
"""

import hashlib
import json
import math
import os
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aliz_head_probe import read_glb, write_glb, load_mesh  # noqa: E402
from aliz_local_pass import claim_map, tri_centroids, blend, replace_embedded_image  # noqa: E402
from aliz_ortho_face import render_ortho, find_features  # noqa: E402
from png_edit import load as png_load, save as png_save  # noqa: E402

HEAD_C = (0.0, 1.400, 0.0)
HEAD_R = 0.360
FRONT_Z = 0.02

# -- palette (all measured against the icon; see the module doc) -------------
SKIN_OLD = (253, 206, 182)
SKIN_SHIFT = (0, 6, -3)
SKIN = tuple(SKIN_OLD[k] + SKIN_SHIFT[k] for k in range(3))    # (253, 212, 179)
BLUSH = (252, 176, 166)
BROW = (212, 116, 128)
LIP = (206, 104, 100)
MOUTH_IN = (150, 58, 64)
TEETH = (252, 248, 244)
TONGUE = (234, 122, 130)
WHITE = (255, 255, 255)

# -- geometry, model metres -------------------------------------------------
PATCH_CX, PATCH_CY, PATCH_RX, PATCH_RY = 0.0, 1.180, 0.082, 0.050
SMILE_CY, SMILE_HALF_W, SMILE_HALF_T, SMILE_END_T, SMILE_ARC = 1.1830, 0.046, 0.0050, 0.55, 0.0090
BLUSH_X, BLUSH_Y, BLUSH_RX, BLUSH_RY, BLUSH_ALPHA = 0.150, 1.247, 0.042, 0.024, 0.50
BROW_X, BROW_Y, BROW_HALF_W, BROW_ARCH, BROW_T = 0.105, 1.394, 0.040, -0.007, 0.0065
BROW_UP_DY, BROW_UP_ARCH = 0.008, -0.009
HIGHLIGHT_GROW = 1.30
CATCHLIGHT_R = 0.0045
LID_DROP, LID_SAG, LID_T = 0.004, 0.012, 0.0065
EYE_ERASE_PAD = 0.011
OPEN_HALF_W, OPEN_TOP_Y, OPEN_ARC, OPEN_DEPTH, TEETH_H = 0.046, 1.1935, 0.008, 0.031, 0.0065
O_CX, O_CY, O_RX, O_RY = 0.0, 1.182, 0.013, 0.017
RIM = 0.0018
AA = 0.0016

LAYERS = ["eyesClosed", "mouthOpen", "mouthO", "browsUp"]
MOODS = {"content": [], "happy": ["mouthOpen"], "surprised": ["mouthO", "browsUp"],
         "sleepy": ["eyesClosed"]}
BLINK_LAYER = "eyesClosed"


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def edge(d, aa=AA):
    """1 inside (d < 0), 0 outside, feathered over +-aa."""
    return smooth((aa - d) / (2.0 * aa))


def is_skin(rgb):
    r, g, b = rgb
    return r >= 235 and 150 <= g <= 228 and 130 <= b <= 205 and g > b + 8


def is_dark(rgb):
    return rgb[0] < 120 and rgb[1] < 100 and rgb[2] < 110


def ellipse_d(x, y, cx, cy, rx, ry):
    """Approximate signed distance to an ellipse edge, metres."""
    e = math.hypot((x - cx) / rx, (y - cy) / ry)
    return (e - 1.0) * min(rx, ry)


def segment_d(x, y, x0, y0, x1, y1):
    vx, vy = x1 - x0, y1 - y0
    L2 = vx * vx + vy * vy
    t = 0.0 if L2 < 1e-12 else max(0.0, min(1.0, ((x - x0) * vx + (y - y0) * vy) / L2))
    return math.hypot(x - (x0 + t * vx), y - (y0 + t * vy))


def arc_d(x, y, cx, cy, half_w, amp, thick, taper):
    """Distance outside a tapered stroke along y = cy + amp * u^2, |u| <= 1,
    with round caps. `taper` is how much thinner the ends are (0..1)."""
    u = (x - cx) / half_w
    uc = max(-1.0, min(1.0, u))
    half_t = 0.5 * thick * (1.0 - taper * uc * uc)
    if abs(u) <= 1.0:
        return abs(y - (cy + amp * u * u)) - half_t
    ex = cx + math.copysign(half_w, u)
    return math.hypot(x - ex, y - (cy + amp)) - half_t


# ---------------------------------------------------------------------------
# ops: each is f(x, y, rgb) -> (rgb, alpha) or None
# ---------------------------------------------------------------------------

def op_fill_ellipse(cx, cy, rx, ry, col, alpha=1.0, soft=0.15, only=None):
    def f(x, y, rgb):
        if only is not None and not only(rgb):
            return None
        e = math.hypot((x - cx) / rx, (y - cy) / ry)
        if e >= 1.0:
            return None
        a = alpha if e <= 1.0 - soft else alpha * smooth((1.0 - e) / soft)
        return col, a
    return f


def op_fill_rounded_box(cx, cy, rx, ry, col, alpha=1.0, soft=0.12, power=3.0, only=None):
    """A superellipse: squarer than an ellipse, so it swallows the lash curl at
    the corner of an eye box without having to grow past the brow."""
    def f(x, y, rgb):
        if only is not None and not only(rgb):
            return None
        e = (abs(x - cx) / rx) ** power + (abs(y - cy) / ry) ** power
        if e >= 1.0:
            return None
        a = alpha if e <= 1.0 - soft else alpha * smooth((1.0 - e) / soft)
        return col, a
    return f


def op_arc(cx, cy, half_w, amp, thick, col, alpha=1.0, taper=0.45, only=None):
    def f(x, y, rgb):
        if only is not None and not only(rgb):
            return None
        if abs(x - cx) > half_w + thick or abs(y - (cy + min(0.0, amp))) > abs(amp) + thick:
            return None
        a = edge(arc_d(x, y, cx, cy, half_w, amp, thick, taper))
        return (col, a * alpha) if a > 0.0 else None
    return f


def op_capsule(x0, y0, x1, y1, thick, col, alpha=1.0):
    def f(x, y, rgb):
        a = edge(segment_d(x, y, x0, y0, x1, y1) - 0.5 * thick)
        return (col, a * alpha) if a > 0.0 else None
    return f


def op_smile():
    def f(x, y, rgb):
        u = x / SMILE_HALF_W
        if abs(u) <= 1.0:
            mid = SMILE_CY + SMILE_ARC * u * u
            half_t = SMILE_HALF_T * (SMILE_END_T + (1.0 - SMILE_END_T) * (1.0 - u * u))
            d = abs(y - mid) - half_t
        else:
            d = math.hypot(x - math.copysign(SMILE_HALF_W, x), y - (SMILE_CY + SMILE_ARC)) \
                - SMILE_HALF_T * SMILE_END_T
        a = edge(d, 0.0020)
        return (LIP, a) if a > 0.0 else None
    return f


def op_open_smile():
    """The icon's smile: a nearly straight upper lip with lifted corners over a
    deep U, cream teeth along the top, a tongue low in the middle, a lip rim."""
    def bounds(u):
        top = OPEN_TOP_Y + OPEN_ARC * u * u
        bottom = top - OPEN_DEPTH * max(0.0, 1.0 - u * u) ** 0.8
        return top, bottom

    def f(x, y, rgb):
        u = x / OPEN_HALF_W
        if abs(u) > 1.0 + (RIM + AA) / OPEN_HALF_W:
            return None
        uc = max(-1.0, min(1.0, u))
        top, bottom = bounds(uc)
        # Signed distance to the mouth shape: vertical inside the span, radial
        # past the corners.
        if abs(u) <= 1.0:
            d = max(y - top, bottom - y)
        else:
            d = math.hypot(x - math.copysign(OPEN_HALF_W, x), y - (OPEN_TOP_Y + OPEN_ARC))
        inside = edge(d)
        if inside <= 0.0:
            rim = edge(d - RIM)
            return (LIP, rim * 0.9) if rim > 0.0 else None
        col = MOUTH_IN
        if y > top - TEETH_H and abs(u) < 0.82:
            col = blend(MOUTH_IN, TEETH, edge(top - TEETH_H - y, 0.0012))
        tcx, tcy = 0.0, bounds(0.0)[1] + 0.011
        td = ellipse_d(x, y, tcx, tcy, 0.020, 0.0085)
        col = blend(col, TONGUE, edge(td, 0.0012) * 0.95)
        return col, inside
    return f


def op_o_mouth():
    def f(x, y, rgb):
        d = ellipse_d(x, y, O_CX, O_CY, O_RX, O_RY)
        inside = edge(d)
        if inside > 0.0:
            return MOUTH_IN, inside
        rim = edge(d - RIM)
        return (LIP, rim * 0.9) if rim > 0.0 else None
    return f


def op_soften_blush(side):
    """Pull the generator's pink back halfway to skin on the cheek."""
    def f(x, y, rgb):
        if x * side <= 0 or not (0.085 < abs(x) < 0.215) or not (1.195 < y < 1.295):
            return None
        if not is_skin(rgb) or rgb[1] >= SKIN[1] - 6:
            return None
        return SKIN, 0.5
    return f


# ---------------------------------------------------------------------------
# the painter
# ---------------------------------------------------------------------------

class Face:
    def __init__(self, glb_in, png_in):
        self.js, self.bin = read_glb(glb_in)
        m = load_mesh(self.js, self.bin)
        self.pos, self.uv, self.idx = m["pos"], m["uv"], m["idx"]
        self.W, self.H, self.C, self.tex = png_load(png_in)
        self.claims, self.where = claim_map(self.pos, self.uv, self.idx, self.W, self.H)
        cent = tri_centroids(self.pos, self.idx)
        self.face = []       # (texel index, x, y) for every front-of-head texel
        for i in range(self.W * self.H):
            p = self.where[i]
            if p is None or p[2] < FRONT_Z:
                continue
            if not self.claims[i]:
                continue
            if any(math.dist(cent[t], HEAD_C) > HEAD_R for t in self.claims[i]):
                continue
            self.face.append((i, p[0], p[1]))
        self.waves = self._pad_waves()
        # Features, measured off the shipping paint before anything is touched.
        w, h, img, _ = render_ortho(self.pos, self.uv, self.idx, self.W, self.H, self.C, self.tex)
        self.features = find_features(w, h, img)
        if set(self.features.keys()) != {-1, 1}:
            raise SystemExit("could not find both eyes on the atlas; refusing to paint")
        print("face: %d front-of-head texels; %d gutter texels padded in %d waves"
              % (len(self.face), sum(len(wv) for wv in self.waves), len(self.waves)))
        for side in (-1, 1):
            f = self.features[side]
            print("  eye %s iris (%.3f, %.3f) r (%.3f, %.3f) box x %.3f..%.3f y %.3f..%.3f"
                  % ("R" if side < 0 else "L", *f["iris"], f["box"][0], f["box"][2],
                     f["box"][1], f["box"][3]))

    # -- gutter padding, recorded once and replayed ------------------------------
    def _pad_waves(self):
        W, H = self.W, self.H
        filled = bytearray(1 if self.claims[i] else 0 for i in range(W * H))
        waves = []
        for _ in range(96):
            wave = []
            for i in range(W * H):
                if filled[i]:
                    continue
                x, y = i % W, i // W
                nbrs = []
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and filled[ny * W + nx]:
                        nbrs.append(ny * W + nx)
                if nbrs:
                    wave.append((i, nbrs))
            if not wave:
                break
            for i, _n in wave:
                filled[i] = 1
            waves.append(wave)
        return waves

    def pad(self, tex):
        C = self.C
        for wave in self.waves:
            for i, nbrs in wave:
                acc = [0, 0, 0]
                for n in nbrs:
                    o = n * C
                    acc[0] += tex[o]; acc[1] += tex[o + 1]; acc[2] += tex[o + 2]
                k = len(nbrs)
                tex[i * C:i * C + 3] = bytes((acc[0] // k, acc[1] // k, acc[2] // k))

    # -- painting ------------------------------------------------------------------
    def paint(self, tex, op):
        C = self.C
        n = 0
        for i, x, y in self.face:
            o = i * C
            rgb = (tex[o], tex[o + 1], tex[o + 2])
            res = op(x, y, rgb)
            if res is None:
                continue
            col, a = res
            if a <= 0.0:
                continue
            tex[o:o + 3] = bytes(blend(rgb, col, a))
            n += 1
        return n

    def warm_skin(self, tex):
        C = self.C
        n = 0
        for i in range(self.W * self.H):
            o = i * C
            rgb = (tex[o], tex[o + 1], tex[o + 2])
            if not is_skin(rgb):
                continue
            tex[o:o + 3] = bytes(max(0, min(255, rgb[k] + SKIN_SHIFT[k])) for k in range(3))
            n += 1
        return n

    # -- the features, as op lists -------------------------------------------------
    def blush_ops(self):
        ops = []
        for side in (-1, 1):
            ops.append(op_soften_blush(side))
            ops.append(op_fill_ellipse(side * BLUSH_X, BLUSH_Y, BLUSH_RX, BLUSH_RY,
                                       BLUSH, BLUSH_ALPHA, soft=0.55))
        return ops

    def brow_ops(self, dy=0.0, arch=BROW_ARCH):
        return [op_arc(side * BROW_X, BROW_Y + dy, BROW_HALF_W, arch, BROW_T, BROW,
                       alpha=1.0, only=is_skin) for side in (-1, 1)]

    def mouth_erase_ops(self):
        return [op_fill_ellipse(PATCH_CX, PATCH_CY, PATCH_RX, PATCH_RY, SKIN, 1.0, soft=0.16)]

    def highlight_ops(self):
        ops = []
        for side in (-1, 1):
            f = self.features[side]
            cx, cy, rx, ry = f["iris"]
            if not f["highlights"]:
                continue
            hx, hy, hrx, hry = f["highlights"][0]
            ops.append(op_fill_ellipse(hx, hy, hrx * HIGHLIGHT_GROW, hry * HIGHLIGHT_GROW,
                                       WHITE, 1.0, soft=0.18))
            # The second catchlight, low on the far side of the pupil.
            ops.append(op_fill_ellipse(cx - (hx - cx) * 0.75, cy - (hy - cy) * 0.95,
                                       CATCHLIGHT_R, CATCHLIGHT_R, WHITE, 0.92, soft=0.3))
        return ops

    def eye_erase_ops(self):
        ops = []
        for side in (-1, 1):
            x0, y0, x1, y1 = self.features[side]["box"]
            cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
            ops.append(op_fill_rounded_box(cx, cy, (x1 - x0) / 2.0 + EYE_ERASE_PAD,
                                           (y1 - y0) / 2.0 + EYE_ERASE_PAD, SKIN, 1.0))
        return ops

    def lid_ops(self):
        ops = []
        for side in (-1, 1):
            f = self.features[side]
            x0, y0, x1, y1 = f["box"]
            cx = (x0 + x1) / 2.0
            half_w = (x1 - x0) / 2.0 * 0.82
            y = f["iris"][1] - LID_DROP
            ops.append(op_arc(cx, y, half_w, LID_SAG, LID_T, f["lash"], taper=0.5))
            # A short lash flick off the outer corner, downward and outward.
            ex = cx + side * half_w
            ey = y + LID_SAG
            ops.append(op_capsule(ex, ey, ex + side * 0.009, ey - 0.007, 0.0042, f["lash"]))
        return ops

    def brow_erase_ops(self):
        return [op_fill_ellipse(side * BROW_X, BROW_Y, BROW_HALF_W + 0.008, BROW_T + 0.0035,
                                SKIN, 1.0, soft=0.2, only=lambda rgb: not is_dark(rgb))
                for side in (-1, 1)]


def apply(face, tex, ops):
    return sum(face.paint(tex, op) for op in ops)


def diff_patch(base, tex, W, H, C):
    """-> (x, y, w, h, rgba bytes) of every texel that differs, or None."""
    xs, ys = [], []
    for i in range(W * H):
        o = i * C
        if base[o:o + 3] != tex[o:o + 3]:
            xs.append(i % W)
            ys.append(i // W)
    if not xs:
        return None
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    w, h = x1 - x0 + 1, y1 - y0 + 1
    out = bytearray(w * h * 4)
    changed = 0
    for y in range(h):
        for x in range(w):
            i = (y0 + y) * W + (x0 + x)
            o = i * C
            d = (y * w + x) * 4
            if base[o:o + 3] != tex[o:o + 3]:
                out[d:d + 3] = tex[o:o + 3]
                out[d + 3] = 255
                changed += 1
    return x0, y0, w, h, out, changed


def probe_texels(face, tex):
    """Six texels a runtime can check before trusting the patches: each eye's
    iris centre (teal), and skin at the nose bridge, the chin and each cheek."""
    C = face.C
    targets = []
    for side in (-1, 1):
        cx, cy, _, _ = face.features[side]["iris"]
        targets.append((cx, cy, "iris"))
    targets += [(0.0, 1.300, "skin"), (0.0, 1.140, "skin"),
                (-0.10, 1.230, "skin"), (0.10, 1.230, "skin")]
    probes = []
    for tx, ty, kind in targets:
        best, best_d = None, 1e9
        for i, x, y in face.face:
            d = math.hypot(x - tx, y - ty)
            if d < best_d:
                best, best_d = i, d
        o = best * C
        probes.append({"x": best % face.W, "y": best // face.W,
                       "rgb": [tex[o], tex[o + 1], tex[o + 2]], "kind": kind})
    return probes


def main():
    glb_in, png_in, glb_out, png_out = sys.argv[1:5]
    face = Face(glb_in, png_in)
    W, H, C = face.W, face.H, face.C
    tex = bytearray(face.tex)

    # ---- base -------------------------------------------------------------
    n = face.warm_skin(tex)
    print("skin: %d texels warmed by %s" % (n, SKIN_SHIFT))
    print("mouth erased: %d" % apply(face, tex, face.mouth_erase_ops()))
    print("blush: %d" % apply(face, tex, face.blush_ops()))
    print("brows: %d" % apply(face, tex, face.brow_ops()))
    print("smile: %d (%.0f x %.1f mm, corners up %.0f mm, ink %s)"
          % (apply(face, tex, [op_smile()]), SMILE_HALF_W * 2000, SMILE_HALF_T * 2000,
             SMILE_ARC * 1000, LIP))
    print("highlights: %d" % apply(face, tex, face.highlight_ops()))
    face.pad(tex)
    base = bytes(tex)
    png_save(png_out, W, H, C, tex)

    # ---- layers -----------------------------------------------------------
    out_dir = os.path.dirname(png_out) or "."
    stem = os.path.basename(png_out)
    stem = stem[:-len("_texture_0.png")] if stem.endswith("_texture_0.png") else stem[:-4]
    layers = {}
    recipes = {
        "eyesClosed": lambda t: (apply(face, t, face.eye_erase_ops())
                                 + apply(face, t, face.blush_ops())
                                 + apply(face, t, face.brow_ops())
                                 + apply(face, t, face.lid_ops())),
        "mouthOpen": lambda t: (apply(face, t, face.mouth_erase_ops())
                                + apply(face, t, face.blush_ops())
                                + apply(face, t, [op_open_smile()])),
        "mouthO": lambda t: (apply(face, t, face.mouth_erase_ops())
                             + apply(face, t, face.blush_ops())
                             + apply(face, t, [op_o_mouth()])),
        "browsUp": lambda t: (apply(face, t, face.brow_erase_ops())
                              + apply(face, t, face.brow_ops(BROW_UP_DY, BROW_UP_ARCH))),
    }
    for name in LAYERS:
        t = bytearray(base)
        painted = recipes[name](t)
        face.pad(t)
        patch = diff_patch(base, t, W, H, C)
        if patch is None:
            raise SystemExit("layer %s changed nothing" % name)
        x0, y0, w, h, rgba, changed = patch
        file_name = "%s_face_%s.png" % (stem, name)
        png_save(os.path.join(out_dir, file_name), w, h, 4, rgba)
        layers[name] = {"file": file_name, "rect": [x0, y0, w, h]}
        print("layer %-10s painted %5d, %5d texels differ, patch %dx%d at (%d, %d) -> %s"
              % (name, painted, changed, w, h, x0, y0, file_name))

    manifest = {
        "atlas": [W, H],
        "atlasMd5": hashlib.md5(open(png_out, "rb").read()).hexdigest(),
        "layers": layers,
        "moods": MOODS,
        "blinkLayer": BLINK_LAYER,
        "probes": probe_texels(face, tex),
        "notes": [
            "Generated by tools/aliz_face_pass.py; do not hand-edit. Rects are atlas "
            "texels, origin top-left. A layer PNG is RGBA with alpha 255 only where the "
            "mood differs from the base atlas, so blend_rect is an exact overwrite.",
            "probes are texels of the base atlas the runtime checks (tolerance in "
            "buddy_face.gd) before it trusts the rects; a re-export fails them and the "
            "face system stands down.",
        ],
    }
    manifest_path = os.path.join(out_dir, "%s_faces.json" % stem)
    with open(manifest_path, "w") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")
    print("manifest -> %s" % manifest_path)

    # ---- the GLB's embedded copy ----------------------------------------------
    bin_ = replace_embedded_image(face.js, face.bin, open(png_out, "rb").read())
    write_glb(glb_out, face.js, bin_)
    print("wrote %s and %s (embedded atlas replaced; mesh untouched)" % (png_out, glb_out))


if __name__ == "__main__":
    main()
