#!/usr/bin/env python3
"""Aliz's TUTOR expressions and her talking mouth -- more texture patches on
top of `aliz_face_pass.py`'s base. Zero credits, mesh untouched, base atlas
untouched, additive to the existing manifest.

    python3 tools/aliz_expression_pass.py <model.glb> <atlas.png> <faces.json>

Reads the SHIPPING base atlas (the one `buddy_face.gd`'s probes already
trust), paints each new layer in model metres through the same guarded
3D -> texel claim map every Aliz repaint has used, diffs the result against
the base, and writes next to the manifest:

    <stem>_face_eyesWide.png      eyes opened a little wider (listening)
    <stem>_face_eyesUpLeft.png    irises glance up and to the viewer's left
    <stem>_face_mouthSmall.png    a small, nearly flat mouth (thinking)
    <stem>_face_mouthSmile.png    a wider closed grin, corners well up (smile)
    <stem>_face_mouthSoft.png     a small open smile, no teeth (encouraging)
    <stem>_face_mouthTalk1..3.png the talking mouth: small / mid / open

and adds to `<stem>_faces.json` (existing layers, moods, probes and the atlas
md5 are kept exactly as they were):

    moods:       neutral, listening, thinking, encouraging, smile
                 (happy and the rest are the existing ones)
    mouthFrames: ["", "mouthTalk1", "mouthTalk2", "mouthTalk3"]
    layers[*].rects: per-island sub-rectangles, so the runtime blends a few
                 hundred texels for a mouth frame rather than the whole atlas

## Why the eyes are SAMPLED rather than drawn

The base eyes are the generator's paint, and redrawing them stroke by stroke
would make the tutor expressions a different pair of eyes from the resting
face. So the two eye layers move what is already there: `render_ortho()`
gives a head-on picture of the base at 1 px = 1 mm, and an op that wants the
eye "wider" or the iris "up-left" looks up the base colour at a scaled or
shifted model position and writes THAT. Only texels that are currently skin,
sclera, lash or iris may be written (never hair, never brow, never blush),
and only below the brow line, so the fringe cannot be smeared.

## The mouth frames overwrite whatever mouth the expression has

A talk frame is the mouth region ERASED to skin and repainted, and its patch
carries alpha 255 on every texel the erase touched -- not only the texels
that differ from the base -- so laid over `happy`'s open smile it replaces the
teeth completely rather than leaving a rim of them behind. `buddy_face.gd`
composes: base, the expression's layers, the talk frame (if speaking), the
blink. At amount 0 the frame is simply not applied and the expression's own
mouth is back, to the texel.

Colours: the same warm rose the base smile uses, `LIP` (206, 104, 100) for
the rim and `MOUTH_IN` (150, 58, 64) inside. No teeth (art bible section 4).

## Guard

Refuses to run if the atlas md5 does not match the manifest's `atlasMd5`:
these patches are painted for one base, and the runtime's six probe texels
(kept unchanged here) are what make that base recognisable on a device.
"""

import hashlib
import json
import math
import os
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aliz_face_pass import (  # noqa: E402
    Face, AA, BROW_Y, BROW_UP_DY, LIP, MOUTH_IN, RIM, SKIN,
    apply, edge, is_skin, op_arc, op_fill_ellipse,
)
from aliz_local_pass import blend  # noqa: E402
from aliz_ortho_face import render_ortho, X0, Y1, MM  # noqa: E402
from png_edit import load as png_load, save as png_save  # noqa: E402

# -- the eyes ---------------------------------------------------------------------
## "Slightly wider": everything above the iris centre moves UP by this much and
## the band it leaves is filled from the iris-centre row, so the upper lash line
## rises and a little more sclera shows. 5 mm is 1-2 texels at 2.5 texels/cm.
WIDE_UP = 0.005
## The glance: the eye opening's contents 8 mm toward the viewer's left (model
## -x) and 8 mm up; what slides out from under the lids is filled with sclera.
GLANCE_DX, GLANCE_DY = -0.008, 0.008
## Half a texel past the eye's own extents, the same margin the blink erases.
EYE_PAD = 0.011
## Keep everything under the brow line, whatever the op does.
EYE_TOP_LIMIT = BROW_Y - 0.004

# -- the mouths (model metres; the base smile is 92 x 10 mm at y 1.183) ----------
MOUTH_CY = 1.181
## thinking: 32 mm wide, 6 mm thick, nearly flat, a little to the viewer's right.
SMALL_CX, SMALL_HALF_W, SMALL_T, SMALL_ARC = 0.008, 0.016, 0.0060, 0.0015
## smile: a closed grin, 108 mm wide, corners up 20 mm.
GRIN_CY, GRIN_HALF_W, GRIN_HALF_T, GRIN_ARC = 1.1760, 0.054, 0.0065, 0.020
## encouraging: a small open smile, no teeth. 84 mm wide, 20 mm deep.
SOFT_TOP_Y, SOFT_HALF_W, SOFT_ARC, SOFT_DEPTH = 1.1910, 0.042, 0.0075, 0.020
## talking: rounded open mouths, corners lifted a touch so she still looks kind.
TALK = {
    "mouthTalk1": (0.024, 0.0065, 0.003),
    "mouthTalk2": (0.031, 0.0120, 0.004),
    "mouthTalk3": (0.036, 0.0190, 0.005),
}
TALK_CY = 1.1800

NEW_LAYERS = ["eyesWide", "eyesUpLeft", "mouthSmall", "mouthSmile", "mouthSoft",
              "mouthTalk1", "mouthTalk2", "mouthTalk3"]
NEW_MOODS = {
    "neutral": [],
    "listening": ["eyesWide", "browsUp"],
    "thinking": ["eyesUpLeft", "mouthSmall"],
    "encouraging": ["browsUp", "mouthSoft"],
    "smile": ["mouthSmile"],
}
MOUTH_FRAMES = ["", "mouthTalk1", "mouthTalk2", "mouthTalk3"]
MOUTH_FRAME_NAMES = ["closed", "small", "mid", "open"]
## Every layer whose patch must carry alpha 255 over the WHOLE erased region.
FULL_COVERAGE = {"mouthSmall", "mouthSmile", "mouthSoft", "mouthTalk1", "mouthTalk2",
                 "mouthTalk3"}


# ---------------------------------------------------------------------------
# the base as a picture, so an op can look up "what is at (x, y)"
# ---------------------------------------------------------------------------

class Sampler:
    def __init__(self, face):
        self.w, self.h, self.img, _ = render_ortho(face.pos, face.uv, face.idx,
                                                   face.W, face.H, face.C, face.tex)

    def at(self, x, y):
        px = int((x - X0) * MM)
        py = int((Y1 - y) * MM)
        if px < 0 or py < 0 or px >= self.w or py >= self.h:
            return None
        o = (py * self.w + px) * 3
        return (self.img[o], self.img[o + 1], self.img[o + 2])


def is_pink(rgb):
    """Hair, brow, lip: the rose family. Never overwritten by an eye op."""
    r, g, b = rgb
    return r > 150 and b > g + 6


def is_teal(rgb):
    r, g, b = rgb
    return b > r + 20 and g > r + 20


def is_white(rgb):
    return rgb[0] > 225 and rgb[1] > 225 and rgb[2] > 225


def is_dark(rgb):
    return rgb[0] < 110 and rgb[1] < 90 and rgb[2] < 100


def superellipse(x, y, cx, cy, rx, ry, power=3.0):
    return (abs(x - cx) / rx) ** power + (abs(y - cy) / ry) ** power


# ---------------------------------------------------------------------------
# eye ops
# ---------------------------------------------------------------------------

class Opening:
    """The eye OPENING (sclera + iris, lids and lashes excluded) as a 1 mm mask
    in render space, per side, so an op can ask "is this point inside the eye"
    without classifying a single anti-aliased texel."""

    def __init__(self, face, sampler):
        self.s = sampler
        w, h = sampler.w, sampler.h
        self.mask = bytearray(w * h)
        self.sclera = {}
        for side in (-1, 1):
            f = face.features[side]
            cx, cy, rx, ry = f["iris"]
            x0, y0, x1, y1 = f["box"]
            raw = bytearray(w * h)
            for py in range(h):
                y = Y1 - (py + 0.5) / MM
                if not (y0 - 0.002 <= y <= y1 + 0.002):
                    continue
                for px in range(w):
                    x = X0 + (px + 0.5) / MM
                    if not (x0 - 0.002 <= x <= x1 + 0.002):
                        continue
                    rgb = sampler.at(x, y)
                    e = math.hypot((x - cx) / rx, (y - cy) / ry)
                    # Everything inside the iris ellipse is iris (its texels
                    # blend teal, white and dark and defeat any colour test);
                    # outside it, sclera white and the iris' own dark rim.
                    if e < 1.0 or is_white(rgb) or is_teal(rgb) or (is_dark(rgb) and e < 1.05):
                        raw[py * w + px] = 1
            # Close 2 mm holes (anti-aliased iris rim, highlight edges).
            grown = self._dilate(raw, w, h, 2)
            closed = self._erode(grown, w, h, 2)
            for i in range(w * h):
                if closed[i]:
                    self.mask[i] = 1
            sc = sampler.at(cx + side * (rx + 0.005), cy)
            self.sclera[side] = sc if (sc and is_white(sc)) else (255, 255, 255)

    @staticmethod
    def _dilate(m, w, h, r):
        out = bytearray(m)
        for i in range(w * h):
            if not m[i]:
                continue
            x, y = i % w, i // w
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        out[ny * w + nx] = 1
        return out

    @staticmethod
    def _erode(m, w, h, r):
        out = bytearray(m)
        for i in range(w * h):
            if not m[i]:
                continue
            x, y = i % w, i // w
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    nx, ny = x + dx, y + dy
                    if not (0 <= nx < w and 0 <= ny < h) or not m[ny * w + nx]:
                        out[i] = 0
                        break
                else:
                    continue
                break
        return out

    def inside(self, x, y):
        px = int((x - X0) * MM)
        py = int((Y1 - y) * MM)
        if px < 0 or py < 0 or px >= self.s.w or py >= self.s.h:
            return False
        return self.mask[py * self.s.w + px] == 1


def op_eyes_wide(face, sampler):
    eyes = []
    for side in (-1, 1):
        f = face.features[side]
        x0, y0, x1, y1 = f["box"]
        cy = f["iris"][1]
        eyes.append((cy, (x0 + x1) / 2.0, (y0 + y1) / 2.0 + WIDE_UP / 2.0,
                     (x1 - x0) / 2.0 + EYE_PAD, (y1 - y0) / 2.0 + EYE_PAD + WIDE_UP / 2.0))

    def f(x, y, rgb):
        if y > EYE_TOP_LIMIT or is_pink(rgb):
            return None
        for cy, bcx, bcy, brx, bry in eyes:
            if y <= cy or superellipse(x, y, bcx, bcy, brx, bry) >= 1.0:
                continue
            src = sampler.at(x, max(y - WIDE_UP, cy))
            if src is None or is_pink(src):
                return None
            return src, 1.0
        return None
    return f


def op_eyes_glance(face, sampler, opening, dx, dy):
    """The iris OUTLINE moves by (dx, dy); its interior paint stays. Where the
    old iris no longer reaches, sclera; where the new one reaches over sclera,
    the iris' own rim and edge colours. No resampling, so no speckle -- the
    first version shifted the texels themselves and the fragmented eye islands
    turned the highlight into confetti."""
    eyes = []
    for side in (-1, 1):
        f = face.features[side]
        cx, cy, rx, ry = f["iris"]
        # The rim and the edge tone, measured off the base: the darkest and the
        # mean teal in the iris' outer band.
        darkest, edge_acc, edge_n = (255, 255, 255), [0, 0, 0], 0
        for py in range(sampler.h):
            y = Y1 - (py + 0.5) / MM
            if abs(y - cy) > ry:
                continue
            for px in range(sampler.w):
                x = X0 + (px + 0.5) / MM
                e = math.hypot((x - cx) / rx, (y - cy) / ry)
                if not (0.7 < e < 1.0):
                    continue
                rgb = sampler.at(x, y)
                if is_teal(rgb) or is_dark(rgb):
                    if sum(rgb) < sum(darkest):
                        darkest = rgb
                    if is_teal(rgb) and not is_dark(rgb):
                        for k in range(3):
                            edge_acc[k] += rgb[k]
                        edge_n += 1
        edge_tone = tuple(v // max(edge_n, 1) for v in edge_acc) if edge_n else darkest
        eyes.append((side, cx, cy, rx, ry, darkest, edge_tone))

    def f(x, y, rgb):
        if y > EYE_TOP_LIMIT:
            return None
        for side, cx, cy, rx, ry, rim, tone in eyes:
            if abs(x - cx) > rx + 0.03 or abs(y - cy) > ry + 0.03:
                continue
            if not opening.inside(x, y):
                return None
            old = math.hypot((x - cx) / rx, (y - cy) / ry)
            new = math.hypot((x - cx - dx) / rx, (y - cy - dy) / ry)
            band = 0.0025 / min(rx, ry)
            if new >= 1.0:
                # Outside the moved iris: sclera wherever the old iris was.
                return (opening.sclera[side], 1.0) if old < 1.0 + 0.6 * band else None
            if is_white(rgb):
                return None            # a highlight stays where it is
            if new >= 1.0 - band:
                return rim, 1.0        # the moved outline, all the way round
            if old >= 1.0 - 1.6 * band:
                return tone, 1.0       # the old outline, now interior: edge tone
            return None                # iris paint stays where it is
        return None
    return f


# ---------------------------------------------------------------------------
# mouth ops
# ---------------------------------------------------------------------------

def op_closed_smile(cx, cy, half_w, half_t, arc, end_t=0.55):
    """The base smile's shape, parameterised: a tapered stroke along a parabola
    whose corners lift by `arc`."""
    def f(x, y, rgb):
        u = (x - cx) / half_w
        if abs(u) <= 1.0:
            mid = cy + arc * u * u
            t = half_t * (end_t + (1.0 - end_t) * (1.0 - u * u))
            d = abs(y - mid) - t
        else:
            d = math.hypot(x - (cx + math.copysign(half_w, u)), y - (cy + arc)) - half_t * end_t
        a = edge(d, 0.0020)
        return (LIP, a) if a > 0.0 else None
    return f


def op_open_mouth(cx, cy, half_w, half_h, arc):
    """A rounded open mouth: dark rose inside, lip rim, corners lifted by `arc`,
    no teeth and no tongue."""
    def f(x, y, rgb):
        u = max(-1.0, min(1.0, (x - cx) / half_w))
        yy = y - arc * u * u
        e = math.hypot((x - cx) / half_w, (yy - cy) / half_h)
        d = (e - 1.0) * min(half_w, half_h)
        inside = edge(d)
        if inside > 0.0:
            return MOUTH_IN, inside
        rim = edge(d - RIM)
        return (LIP, rim * 0.9) if rim > 0.0 else None
    return f


def op_soft_smile():
    """A small open smile: nearly straight upper lip with lifted corners over a
    shallow U. `op_open_smile()`'s shape without the teeth or the tongue."""
    def f(x, y, rgb):
        u = x / SOFT_HALF_W
        if abs(u) > 1.0 + (RIM + AA) / SOFT_HALF_W:
            return None
        uc = max(-1.0, min(1.0, u))
        top = SOFT_TOP_Y + SOFT_ARC * uc * uc
        bottom = top - SOFT_DEPTH * max(0.0, 1.0 - uc * uc) ** 0.8
        if abs(u) <= 1.0:
            d = max(y - top, bottom - y)
        else:
            d = math.hypot(x - math.copysign(SOFT_HALF_W, x), y - (SOFT_TOP_Y + SOFT_ARC))
        inside = edge(d)
        if inside > 0.0:
            return MOUTH_IN, inside
        rim = edge(d - RIM)
        return (LIP, rim * 0.9) if rim > 0.0 else None
    return f


# ---------------------------------------------------------------------------
# painting with a record of every touched texel
# ---------------------------------------------------------------------------

class Tracked:
    """Wraps `Face.paint()` so the erase's footprint is known even where the
    erase wrote the colour that was already there."""

    def __init__(self, face):
        self.face = face
        self.touched = set()

    def paint(self, tex, ops):
        C = self.face.C
        n = 0
        for op in ops:
            for i, x, y in self.face.face:
                o = i * C
                rgb = (tex[o], tex[o + 1], tex[o + 2])
                res = op(x, y, rgb)
                if res is None:
                    continue
                col, a = res
                if a <= 0.0:
                    continue
                tex[o:o + 3] = bytes(blend(rgb, col, a))
                self.touched.add(i)
                n += 1
        return n


def patch_of(base, tex, W, H, C, touched):
    """-> (x, y, w, h, rgba, changed): every texel that differs from the base,
    plus every texel in `touched` (alpha 255 either way)."""
    keep = set(touched)
    for i in range(W * H):
        o = i * C
        if base[o:o + 3] != tex[o:o + 3]:
            keep.add(i)
    if not keep:
        return None
    xs = [i % W for i in keep]
    ys = [i // W for i in keep]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    w, h = x1 - x0 + 1, y1 - y0 + 1
    out = bytearray(w * h * 4)
    for i in keep:
        x, y = i % W - x0, i // W - y0
        o = i * C
        d = (y * w + x) * 4
        out[d:d + 3] = tex[o:o + 3]
        out[d + 3] = 255
    return x0, y0, w, h, out, len(keep)


def islands(rgba, w, h, x0, y0, pad=1):
    """Bounding boxes of the patch's opaque texels, clustered on a coarse grid
    (8x8 cells) so the runtime blends a handful of small rects. Returned in
    ATLAS coordinates."""
    cell = 8
    cells = set()
    for y in range(h):
        for x in range(w):
            if rgba[(y * w + x) * 4 + 3]:
                cells.add((x // cell, y // cell))
    seen = set()
    rects = []
    for start in sorted(cells):
        if start in seen:
            continue
        stack = [start]
        seen.add(start)
        members = []
        while stack:
            c = stack.pop()
            members.append(c)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (c[0] + dx, c[1] + dy)
                    if n in cells and n not in seen:
                        seen.add(n)
                        stack.append(n)
        cx0 = min(c[0] for c in members) * cell
        cy0 = min(c[1] for c in members) * cell
        cx1 = min(w, (max(c[0] for c in members) + 1) * cell)
        cy1 = min(h, (max(c[1] for c in members) + 1) * cell)
        # Tighten to the opaque texels inside the cell run.
        tx0, ty0, tx1, ty1 = w, h, -1, -1
        for y in range(cy0, cy1):
            for x in range(cx0, cx1):
                if rgba[(y * w + x) * 4 + 3]:
                    tx0, ty0 = min(tx0, x), min(ty0, y)
                    tx1, ty1 = max(tx1, x), max(ty1, y)
        if tx1 >= 0:
            rects.append([x0 + tx0, y0 + ty0, tx1 - tx0 + 1, ty1 - ty0 + 1])
    return rects


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    glb, png, manifest_path = sys.argv[1:4]
    manifest = json.load(open(manifest_path))
    md5 = hashlib.md5(open(png, "rb").read()).hexdigest()
    if manifest.get("atlasMd5") != md5:
        raise SystemExit("atlas md5 %s is not the manifest's %s; these patches are painted "
                         "for one base and this is not it" % (md5, manifest.get("atlasMd5")))
    out_dir = os.path.dirname(manifest_path) or "."
    stem = os.path.basename(manifest_path)[:-len("_faces.json")]

    face = Face(glb, png)
    W, H, C = face.W, face.H, face.C
    base = bytes(face.tex)
    sampler = Sampler(face)
    opening = Opening(face, sampler)
    print("sampler: %dx%d head-on render of the base; eye opening mask %d mm^2"
          % (sampler.w, sampler.h, sum(opening.mask)))

    erase = face.mouth_erase_ops()
    blush = face.blush_ops()
    def mouth(ops):
        return lambda t, tex: t.paint(tex, erase + blush) + t.paint(tex, ops)

    recipes = {
        "eyesWide": lambda t, tex: t.paint(tex, [op_eyes_wide(face, sampler)]),
        "eyesUpLeft": lambda t, tex: t.paint(
            tex, [op_eyes_glance(face, sampler, opening, GLANCE_DX, GLANCE_DY)]),
        "mouthSmall": mouth([op_closed_smile(SMALL_CX, MOUTH_CY, SMALL_HALF_W, SMALL_T / 2.0,
                                             SMALL_ARC, end_t=0.8)]),
        "mouthSmile": mouth([op_closed_smile(0.0, GRIN_CY, GRIN_HALF_W, GRIN_HALF_T, GRIN_ARC)]),
        "mouthSoft": mouth([op_soft_smile()]),
    }
    for name, (half_w, half_h, arc) in TALK.items():
        recipes[name] = mouth([op_open_mouth(0.0, TALK_CY, half_w, half_h, arc)])

    layers = manifest["layers"]
    # Every mouth layer -- the base pass's and this one's -- overwrites the UNION
    # of every mouth layer's footprint, gutter texels included, so no frame can
    # leave a corner of another mouth (or its padded gutter) behind.
    results = {}
    mouth_union = set()
    for name in NEW_LAYERS:
        tracked = Tracked(face)
        tex = bytearray(base)
        painted = recipes[name](tracked, tex)
        face.pad(tex)
        results[name] = (tex, painted)
        if name in FULL_COVERAGE:
            mouth_union |= tracked.touched
            for i in range(W * H):
                if base[i * C:i * C + 3] != tex[i * C:i * C + 3]:
                    mouth_union.add(i)
    for name in ("mouthOpen", "mouthO"):
        spec = layers.get(name)
        if spec is None:
            continue
        pw, ph, pc, px = png_load(os.path.join(out_dir, spec["file"]))
        for y in range(ph):
            for x in range(pw):
                if px[(y * pw + x) * 4 + 3]:
                    mouth_union.add((spec["rect"][1] + y) * W + spec["rect"][0] + x)
    print("mouth footprint union: %d texels" % len(mouth_union))
    for name in NEW_LAYERS:
        tex, painted = results[name]
        touched = mouth_union if name in FULL_COVERAGE else set()
        patch = patch_of(base, tex, W, H, C, touched)
        if patch is None:
            raise SystemExit("layer %s changed nothing" % name)
        x0, y0, w, h, rgba, kept = patch
        file_name = "%s_face_%s.png" % (stem, name)
        png_save(os.path.join(out_dir, file_name), w, h, 4, rgba)
        rects = islands(rgba, w, h, x0, y0)
        layers[name] = {"file": file_name, "rect": [x0, y0, w, h], "rects": rects}
        print("layer %-11s painted %5d, %5d texels in patch (%dx%d at %d,%d), %d island rects"
              % (name, painted, kept, w, h, x0, y0, len(rects)))

    # Island rects for the layers the base pass wrote, so every layer blends
    # small. The patches themselves are not touched.
    for name, spec in layers.items():
        if "rects" in spec:
            continue
        pw, ph, pc, px = png_load(os.path.join(out_dir, spec["file"]))
        assert (pw, ph, pc) == (spec["rect"][2], spec["rect"][3], 4), spec
        spec["rects"] = islands(px, pw, ph, spec["rect"][0], spec["rect"][1])
        print("layer %-11s (existing) %d island rects" % (name, len(spec["rects"])))

    moods = manifest["moods"]
    for mood, names in NEW_MOODS.items():
        moods[mood] = list(names)
    manifest["mouthFrames"] = list(MOUTH_FRAMES)
    manifest["mouthFrameNames"] = list(MOUTH_FRAME_NAMES)
    notes = manifest.setdefault("notes", [])
    note = ("tools/aliz_expression_pass.py added the tutor expressions (neutral, listening, "
            "thinking, encouraging, smile), the mouthFrames the talking mouth cycles through "
            "(index 0 = the expression's own mouth), and per-layer island `rects`. Mouth "
            "layers carry alpha 255 over the whole erased mouth region so a frame replaces "
            "any expression's mouth completely.")
    if note not in notes:
        notes.append(note)
    with open(manifest_path, "w") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")
    print("manifest -> %s (%d layers, %d moods, %d mouth frames)"
          % (manifest_path, len(layers), len(moods), len(MOUTH_FRAMES)))


if __name__ == "__main__":
    main()
