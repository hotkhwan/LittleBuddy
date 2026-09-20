#!/usr/bin/env python3
"""A software z-buffer render of Aliz, so a defect seen on screen can be traced
back to the exact triangle and the exact texel that produced it.

## Why not just look at the atlas

Because the atlas lies. The remeshed unwrap has **overlapping islands**: more
than one triangle claims the same texels, so "which 3D point does this texel
paint" has no single answer, and a selection built in UV space silently picks up
a knee. That is exactly how the previous mouth pass failed.

Rendering forward has no such ambiguity. For every pixel this records:

    triangle id · barycentric UV · 3D position · depth · face normal

which answers the two questions the sprint actually asks:

  * **Is the grin a hole?** If the mouth pixels hit a triangle several
    centimetres *behind* the lip surface, it is a modelled cavity. If they hit
    the face surface itself, the grin is **painted** and closing it is a texture
    edit after all.
  * **Are the hair gaps holes?** A gap pixel that hits *nothing* is background
    through a real hole. A gap pixel that hits the forehead is hair that simply
    does not cover -- a different defect with a different fix.

`--mode` chooses the output image: `color` (atlas-lit, compare against Godot),
`depth`, `tri`, or `class` (skin / hair / ink / mouth, flat).

    python3 tools/aliz_screen_probe.py <glb> <atlas.png> <out.png> [headY] [--mode=color]
"""

import math
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aliz_head_probe import read_glb, load_mesh  # noqa: E402
from png_edit import load as png_load, save as png_save  # noqa: E402

# Matches scenes/spike/shot_harness.gd's `alizface` job, in MODEL space: the
# wrapper's 180-degree yaw and the camera's -Z offset cancel, so looking down
# -Z at the un-rotated model gives the same image, unmirrored.
MODEL_HEIGHT_M = 1.65
FOV_DEG = 34.0
CAM_DIST = 1.05


def classify(r, g, b):
    if r < 95 and g < 95 and b < 95:
        return "ink"
    if r > 215 and g > 208 and b > 195:
        return "white"
    if g > 140 and b > 140 and r < 205:
        return "teal"
    if 90 < r < 240 and g < 140 and b < 145 and abs(int(g) - int(b)) < 50:
        return "mouth"
    if r > 200 and 90 < g < 190 and 105 < b < 205:
        return "hair"
    if r > 225 and g > 170 and b > 135:
        return "skin"
    return "other"


CLASS_RGB = {
    "ink": (60, 40, 40), "white": (255, 255, 255), "teal": (60, 180, 180),
    "mouth": (220, 40, 60), "hair": (255, 120, 150), "skin": (255, 210, 185),
    "other": (160, 160, 60), None: (150, 190, 215),
}


def render(glb, png, size=640, head_y=1.24, cam_dist=CAM_DIST, fov=FOV_DEG):
    """-> dict of per-pixel buffers, each `size*size` long."""
    js, bin_ = read_glb(glb)
    m = load_mesh(js, bin_)
    pos, nor, uv, idx = m["pos"], m["nor"], m["uv"], m["idx"]
    W, H, C, tex = png_load(png)

    ys = [p[1] for p in pos]
    scale = MODEL_HEIGHT_M / (max(ys) - min(ys))
    # Camera sits on +Z looking down -Z at (0, head_y/scale, 0) in model space.
    eye_y = head_y / scale
    eye_z = cam_dist / scale
    f = 1.0 / math.tan(math.radians(fov) * 0.5)
    half = size * 0.5

    depth = [1e30] * (size * size)
    tri_buf = [-1] * (size * size)
    pos_buf = [None] * (size * size)
    uv_buf = [None] * (size * size)
    nz_buf = [0.0] * (size * size)

    def project(p):
        # view space: x right, y up, looking down -Z
        vx, vy, vz = p[0], p[1] - eye_y, p[2] - eye_z
        if vz >= -1e-6:
            return None
        d = -vz
        sx = half + (vx * f / d) * half
        sy = half - (vy * f / d) * half
        return sx, sy, d

    for t in range(0, len(idx), 3):
        a, b, c = idx[t], idx[t + 1], idx[t + 2]
        pa, pb, pc = project(pos[a]), project(pos[b]), project(pos[c])
        if pa is None or pb is None or pc is None:
            continue
        minx = max(0, int(min(pa[0], pb[0], pc[0])))
        maxx = min(size - 1, int(max(pa[0], pb[0], pc[0])) + 1)
        miny = max(0, int(min(pa[1], pb[1], pc[1])))
        maxy = min(size - 1, int(max(pa[1], pb[1], pc[1])) + 1)
        if minx > maxx or miny > maxy:
            continue
        d = (pb[1] - pc[1]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[1] - pc[1])
        if abs(d) < 1e-9:
            continue
        inv = 1.0 / d
        for y in range(miny, maxy + 1):
            py = y + 0.5
            for x in range(minx, maxx + 1):
                px = x + 0.5
                l1 = ((pb[1] - pc[1]) * (px - pc[0]) + (pc[0] - pb[0]) * (py - pc[1])) * inv
                l2 = ((pc[1] - pa[1]) * (px - pc[0]) + (pa[0] - pc[0]) * (py - pc[1])) * inv
                l3 = 1.0 - l1 - l2
                if l1 < 0.0 or l2 < 0.0 or l3 < 0.0:
                    continue
                z = l1 * pa[2] + l2 * pb[2] + l3 * pc[2]
                i = y * size + x
                if z >= depth[i]:
                    continue
                depth[i] = z
                tri_buf[i] = t // 3
                pos_buf[i] = (
                    l1 * pos[a][0] + l2 * pos[b][0] + l3 * pos[c][0],
                    l1 * pos[a][1] + l2 * pos[b][1] + l3 * pos[c][1],
                    l1 * pos[a][2] + l2 * pos[b][2] + l3 * pos[c][2],
                )
                uv_buf[i] = (
                    l1 * uv[a][0] + l2 * uv[b][0] + l3 * uv[c][0],
                    l1 * uv[a][1] + l2 * uv[b][1] + l3 * uv[c][1],
                )
                nz_buf[i] = l1 * nor[a][2] + l2 * nor[b][2] + l3 * nor[c][2]
    return {
        "size": size, "depth": depth, "tri": tri_buf, "pos": pos_buf,
        "uv": uv_buf, "nz": nz_buf, "tex": (W, H, C, tex), "scale": scale,
        "eye_y": eye_y, "eye_z": eye_z,
    }


def texel(buf, i):
    W, H, C, tex = buf["tex"]
    if buf["uv"][i] is None:
        return None
    u, v = buf["uv"][i]
    x = min(W - 1, max(0, int(u * W)))
    y = min(H - 1, max(0, int(v * H)))
    o = (y * W + x) * C
    return tex[o], tex[o + 1], tex[o + 2]


def write_image(buf, out, mode="color"):
    size = buf["size"]
    img = bytearray(size * size * 3)
    ds = [d for d in buf["depth"] if d < 1e29]
    dmin, dmax = (min(ds), max(ds)) if ds else (0.0, 1.0)
    for i in range(size * size):
        if mode == "depth":
            d = buf["depth"][i]
            v = 255 if d > 1e29 else int(255 * (1.0 - (d - dmin) / max(dmax - dmin, 1e-9)))
            rgb = (v, v, v)
        elif mode == "tri":
            t = buf["tri"][i]
            rgb = (200, 225, 240) if t < 0 else ((t * 97) % 255, (t * 53) % 255, (t * 29) % 255)
        elif mode == "class":
            c = texel(buf, i)
            rgb = CLASS_RGB[None if c is None else classify(*c)]
        else:
            c = texel(buf, i)
            rgb = (154, 192, 217) if c is None else c
        img[i * 3:i * 3 + 3] = bytes(rgb)
    png_save(out, size, size, 3, img)


def main():
    glb, png, out = sys.argv[1], sys.argv[2], sys.argv[3]
    head_y = 1.24
    mode = "color"
    for arg in sys.argv[4:]:
        if arg.startswith("--mode="):
            mode = arg.split("=", 1)[1]
        else:
            head_y = float(arg)
    buf = render(glb, png, head_y=head_y)
    write_image(buf, out, mode)
    size = buf["size"]
    miss = sum(1 for t in buf["tri"] if t < 0)
    print("wrote %s  mode=%s  background pixels %d / %d" % (out, mode, miss, size * size))


if __name__ == "__main__":
    main()
