#!/usr/bin/env python3
"""Contact sheet of every Aliz mood from the ATLAS side: each mood's layers
composited onto the base exactly as `buddy_face.gd` does it, rendered head-on
at 1 px = 1 mm by `aliz_ortho_face.py`, side by side with labels burnt in as
a coloured bar (no font dependency).

    python3 tools/aliz_face_sheet.py <glb> <atlas.png> <faces.json> <out.png>

This is the atlas-side proof that the patches land on the right texels. The
in-engine proof at gameplay distance is `tools/aliz_shots.gd -- <prefix> mood`.
"""

import json
import os
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aliz_head_probe import read_glb, load_mesh  # noqa: E402
from aliz_ortho_face import render_ortho  # noqa: E402
from png_edit import load as png_load, save as png_save  # noqa: E402

LABEL = {"content": (120, 200, 120), "happy": (240, 190, 60), "surprised": (120, 160, 240),
         "sleepy": (170, 120, 220), "blink": (90, 90, 90)}


def composite(base, W, H, C, layer_dir, manifest, names):
    tex = bytearray(base)
    for name in names:
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


def main():
    glb, png, faces, out = sys.argv[1:5]
    js, bin_ = read_glb(glb)
    m = load_mesh(js, bin_)
    W, H, C, base = png_load(png)
    manifest = json.load(open(faces))
    layer_dir = os.path.dirname(faces) or "."
    cells = [(mood, layers) for mood, layers in manifest["moods"].items()]
    cells.append(("blink", [manifest["blinkLayer"]]))
    tiles = []
    for mood, layers in cells:
        tex = composite(base, W, H, C, layer_dir, manifest, layers)
        w, h, img, _ = render_ortho(m["pos"], m["uv"], m["idx"], W, H, C, tex,
                                    x0=-0.20, x1=0.20, y0=1.12, y1=1.46)
        # A 6 px label bar in the mood's colour across the top.
        col = bytes(LABEL.get(mood, (200, 200, 200)))
        for y in range(6):
            img[y * w * 3:(y + 1) * w * 3] = col * w
        tiles.append((mood, w, h, img))
    gap = 6
    tw, th = tiles[0][1], tiles[0][2]
    width = gap + len(tiles) * (tw + gap)
    height = th + 2 * gap
    canvas = bytearray(bytes((40, 40, 40)) * (width * height))
    for k, (_mood, w, h, img) in enumerate(tiles):
        x0 = gap + k * (tw + gap)
        for y in range(h):
            o = ((gap + y) * width + x0) * 3
            canvas[o:o + w * 3] = img[y * w * 3:(y + 1) * w * 3]
    png_save(out, width, height, 3, canvas)
    print("wrote %s (%dx%d): %s" % (out, width, height, ", ".join(t[0] for t in tiles)))


if __name__ == "__main__":
    main()
