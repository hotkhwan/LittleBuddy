#!/usr/bin/env python3
"""Atlas-side contact sheets of Aliz's tutor face: the six expressions and the
four mouth frames, each composited onto the base exactly as `buddy_face.gd`
does (base, expression layers, mouth frame, blink), rendered head-on at
1 px = 1 mm by `aliz_ortho_face.py`.

    python3 tools/aliz_mouth_frames.py <glb> <atlas.png> <faces.json> <out_prefix>

Writes:
    <out_prefix>_expressions.png   neutral listening thinking happy encouraging smile
    <out_prefix>_mouth_frames.png  closed small mid open   (over `neutral`)
    <out_prefix>_mouth_on_happy.png the same four frames over `happy`: the
                                    frames must replace the teeth completely

This is the proof the patches land on the right texels. The in-engine proof at
the tutor camera distance is `tools/aliz_tutor_shots.gd`.
"""

import json
import os
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aliz_head_probe import read_glb, load_mesh  # noqa: E402
from aliz_ortho_face import render_ortho  # noqa: E402
from png_edit import load as png_load, save as png_save  # noqa: E402

EXPRESSIONS = ["neutral", "listening", "thinking", "happy", "encouraging", "smile"]
LABEL = {"neutral": (120, 200, 120), "listening": (120, 160, 240), "thinking": (170, 120, 220),
         "happy": (240, 190, 60), "encouraging": (240, 140, 90), "smile": (230, 100, 140),
         "closed": (90, 90, 90), "small": (130, 130, 130), "mid": (170, 170, 170),
         "open": (210, 210, 210)}


def composite(base, W, H, C, layer_dir, manifest, names):
    tex = bytearray(base)
    for name in names:
        if not name:
            continue
        spec = manifest["layers"][name]
        x0, y0, w, h = spec["rect"]
        pw, ph, pc, px = png_load(os.path.join(layer_dir, spec["file"]))
        assert (pw, ph, pc) == (w, h, 4), spec
        for y in range(h):
            for x in range(w):
                s = (y * w + x) * 4
                if px[s + 3] == 0:
                    continue
                d = ((y0 + y) * W + (x0 + x)) * C
                tex[d:d + 3] = px[s:s + 3]
    return tex


def sheet(m, W, H, C, cells, out):
    tiles = []
    for label, tex in cells:
        w, h, img, _ = render_ortho(m["pos"], m["uv"], m["idx"], W, H, C, tex,
                                    x0=-0.20, x1=0.20, y0=1.12, y1=1.46)
        col = bytes(LABEL.get(label, (200, 200, 200)))
        for y in range(6):
            img[y * w * 3:(y + 1) * w * 3] = col * w
        tiles.append((w, h, img))
    gap = 6
    tw, th = tiles[0][0], tiles[0][1]
    width = gap + len(tiles) * (tw + gap)
    height = th + 2 * gap
    canvas = bytearray(bytes((40, 40, 40)) * (width * height))
    for k, (w, h, img) in enumerate(tiles):
        x0 = gap + k * (tw + gap)
        for y in range(h):
            o = ((gap + y) * width + x0) * 3
            canvas[o:o + w * 3] = img[y * w * 3:(y + 1) * w * 3]
    png_save(out, width, height, 3, canvas)
    print("wrote %s (%dx%d): %s" % (out, width, height, ", ".join(c[0] for c in cells)))


def main():
    glb, png, faces, prefix = sys.argv[1:5]
    js, bin_ = read_glb(glb)
    m = load_mesh(js, bin_)
    W, H, C, base = png_load(png)
    manifest = json.load(open(faces))
    layer_dir = os.path.dirname(faces) or "."
    frames = manifest["mouthFrames"]
    names = manifest.get("mouthFrameNames", ["closed", "small", "mid", "open"])

    cells = [(e, composite(base, W, H, C, layer_dir, manifest, manifest["moods"][e]))
             for e in EXPRESSIONS]
    sheet(m, W, H, C, cells, prefix + "_expressions.png")
    for mood, suffix in (("neutral", "_mouth_frames.png"), ("happy", "_mouth_on_happy.png")):
        cells = [(names[k], composite(base, W, H, C, layer_dir, manifest,
                                      manifest["moods"][mood] + [frames[k]]))
                 for k in range(len(frames))]
        sheet(m, W, H, C, cells, prefix + suffix)


if __name__ == "__main__":
    main()
