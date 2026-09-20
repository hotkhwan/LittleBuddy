#!/usr/bin/env python3
"""A software render of Aliz through the REAL menu camera, with back-face
culling and Lambert shading from the interpolated vertex normals.

`aliz_screen_probe.py` renders head-on, unlit, and never culls. That was the
right instrument for "is the grin a hole", and the wrong one for the three
polish defects, all of which are visible only at menu distance, only under the
menu light, or only because Godot culls back faces:

  * a culled sliver is a THIN GAP in this render and simply hair in the other;
  * a facet whose normal points at the light is a pale chip here and pink there.

So this one takes the camera and light from `scenes/main/main.gd` /
`main.tscn` (numbers copied, not imported -- this is stdlib Python), applies the
wrapper's normalisation (scale to 1.65 m, yaw 180, then the menu's yaw 200 and
position), and writes:

    <out>_tri.png    triangle ids, so a pixel can be traced to a triangle
    <out>_lit.png    Lambert-lit atlas colour, back faces culled
    <out>_cull.png   culled-only mask: pixels whose FRONT-most hit was a back
                     face -- i.e. the gaps Godot leaves

    python3 tools/aliz_view_probe.py <glb> <atlas.png> <outPrefix> [--view=menu|crown|face] [--scale=N]

`--scale` supersamples the 1334x750 frame (2 = 2668x1500), which is how the
menu shot was compared at the 2.2x the harness actually produced. `--view=crown`
and `--view=face` reproduce the `alizface` harness job (head-on, back-lit) so
the same triangle ids can be read off those shots too.
"""

import math
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aliz_head_probe import read_glb, load_mesh  # noqa: E402
from png_edit import load as png_load, save as png_save  # noqa: E402

# scenes/main/main.gd, the avatar-on framing.
MENU_CAM_POS = (0.94, 1.18, 3.05)
MENU_CAM_TARGET = (-0.22, 0.72, -0.30)
MENU_FOV = 50.0
MENU_AVATAR_POS = (-0.82, 0.0, -0.62)
MENU_AVATAR_YAW = 200.0
# main.tscn DirectionalLight3D: basis z column is (0.3494, 0.7808, 0.5185); a
# light shines down its -Z, so the to-light vector is +Z.
MENU_TO_LIGHT = (0.3494, 0.7808, 0.5185)
MENU_LIGHT_ENERGY = 0.92
MENU_AMBIENT = 0.45

# shot_harness.gd `alizface`: camera on -Z, light rotation (-24, 18, 0).
FACE_FOV = 34.0
FACE_TO_LIGHT = (0.282, 0.407, 0.869)
FACE_LIGHT_ENERGY = 1.25
FACE_AMBIENT = 0.55

# pink_girl_buddy.gd
MODEL_HEIGHT_M = 1.65
MODEL_YAW_DEG = 180.0

FRAME_W, FRAME_H = 1334, 750


def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def unit(a):
    L = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / L, a[1] / L, a[2] / L)
def rot_y(p, deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return (p[0] * c + p[2] * s, p[1], -p[0] * s + p[2] * c)


def to_world(pos, nor, yaw, offset, scale):
    """Wrapper normalisation then the scene placement, for positions and normals."""
    wp, wn = [], []
    for p, n in zip(pos, nor):
        q = rot_y((p[0] * scale, p[1] * scale, p[2] * scale), MODEL_YAW_DEG)
        q = rot_y(q, yaw)
        wp.append((q[0] + offset[0], q[1] + offset[1], q[2] + offset[2]))
        wn.append(rot_y(rot_y(n, MODEL_YAW_DEG), yaw))
    return wp, wn


def camera(eye, target, fov_deg, width, height):
    fwd = unit(sub(target, eye))
    right = unit(cross(fwd, (0.0, 1.0, 0.0)))
    up = cross(right, fwd)
    f = 1.0 / math.tan(math.radians(fov_deg) * 0.5)   # vertical fov (Godot KEEP_HEIGHT)
    halfh = height * 0.5
    halfw = width * 0.5

    def project(p):
        d = sub(p, eye)
        vx, vy, vz = dot(d, right), dot(d, up), dot(d, fwd)
        if vz <= 1e-6:
            return None
        return (halfw + vx * f / vz * halfh, halfh - vy * f / vz * halfh, vz)
    return project, fwd


def render(glb, png, view="menu", scale=1):
    js, bin_ = read_glb(glb)
    m = load_mesh(js, bin_)
    pos, nor, uv, idx = m["pos"], m["nor"], m["uv"], m["idx"]
    W, H, C, tex = png_load(png)
    ys = [p[1] for p in pos]
    s = MODEL_HEIGHT_M / (max(ys) - min(ys))

    if view == "menu":
        wpos, wnor = to_world(pos, nor, MENU_AVATAR_YAW, MENU_AVATAR_POS, s)
        eye, target, fov = MENU_CAM_POS, MENU_CAM_TARGET, MENU_FOV
        to_light, energy, ambient = MENU_TO_LIGHT, MENU_LIGHT_ENERGY, MENU_AMBIENT
    else:
        head_y = 1.42 if view == "crown" else 1.24
        wpos, wnor = to_world(pos, nor, 0.0, (0.0, 0.0, 0.0), s)
        eye, target, fov = (0.0, head_y, -1.05), (0.0, head_y, 0.0), FACE_FOV
        to_light, energy, ambient = FACE_TO_LIGHT, FACE_LIGHT_ENERGY, FACE_AMBIENT

    width, height = FRAME_W * scale, FRAME_H * scale
    project, fwd = camera(eye, target, fov, width, height)
    N = width * height
    depth = [1e30] * N
    tri = [-1] * N
    bary = [None] * N
    front = [True] * N

    for t in range(0, len(idx), 3):
        a, b, c = idx[t], idx[t + 1], idx[t + 2]
        pa, pb, pc = project(wpos[a]), project(wpos[b]), project(wpos[c])
        if pa is None or pb is None or pc is None:
            continue
        minx = max(0, int(min(pa[0], pb[0], pc[0])))
        maxx = min(width - 1, int(max(pa[0], pb[0], pc[0])) + 1)
        miny = max(0, int(min(pa[1], pb[1], pc[1])))
        maxy = min(height - 1, int(max(pa[1], pb[1], pc[1])) + 1)
        if minx > maxx or miny > maxy:
            continue
        d = (pb[1] - pc[1]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[1] - pc[1])
        if abs(d) < 1e-9:
            continue
        # Screen-space winding: y is down, so counter-clockwise in world is d < 0.
        is_front = d < 0
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
                i = y * width + x
                if z >= depth[i]:
                    continue
                depth[i] = z
                tri[i] = t // 3
                bary[i] = (l1, l2, l3)
                front[i] = is_front

    return {
        "width": width, "height": height, "tri": tri, "bary": bary, "front": front,
        "depth": depth, "mesh": (wpos, wnor, uv, idx), "tex": (W, H, C, tex),
        "to_light": to_light, "energy": energy, "ambient": ambient,
    }


def write_images(buf, prefix):
    width, height = buf["width"], buf["height"]
    wpos, wnor, uv, idx = buf["mesh"]
    W, H, C, tex = buf["tex"]
    L = unit(buf["to_light"])
    N = width * height
    img_tri = bytearray(N * 3)
    img_lit = bytearray(N * 3)
    img_cull = bytearray(N * 3)
    bg = (154, 192, 217)
    culled = 0
    for i in range(N):
        t = buf["tri"][i]
        if t < 0:
            img_tri[i * 3:i * 3 + 3] = bytes(bg)
            img_lit[i * 3:i * 3 + 3] = bytes(bg)
            img_cull[i * 3:i * 3 + 3] = bytes(bg)
            continue
        img_tri[i * 3:i * 3 + 3] = bytes(((t * 97) % 255, (t * 53) % 255, (t * 29) % 255))
        l1, l2, l3 = buf["bary"][i]
        a, b, c = idx[3 * t], idx[3 * t + 1], idx[3 * t + 2]
        u = l1 * uv[a][0] + l2 * uv[b][0] + l3 * uv[c][0]
        v = l1 * uv[a][1] + l2 * uv[b][1] + l3 * uv[c][1]
        tx = min(W - 1, max(0, int(u * W)))
        ty = min(H - 1, max(0, int(v * H)))
        o = (ty * W + tx) * C
        col = (tex[o], tex[o + 1], tex[o + 2])
        if not buf["front"][i]:
            # Godot culls this: paint it as the gap it is.
            culled += 1
            img_lit[i * 3:i * 3 + 3] = bytes((255, 0, 255))
            img_cull[i * 3:i * 3 + 3] = bytes((255, 0, 255))
            continue
        img_cull[i * 3:i * 3 + 3] = bytes((90, 90, 90))
        n = unit(tuple(l1 * wnor[a][k] + l2 * wnor[b][k] + l3 * wnor[c][k] for k in range(3)))
        lam = max(0.0, dot(n, L))
        k = buf["ambient"] + buf["energy"] * lam
        img_lit[i * 3:i * 3 + 3] = bytes(min(255, int(col[j] * k)) for j in range(3))
    png_save(prefix + "_tri.png", width, height, 3, img_tri)
    png_save(prefix + "_lit.png", width, height, 3, img_lit)
    png_save(prefix + "_cull.png", width, height, 3, img_cull)
    return culled


def main():
    glb, png, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
    view, scale = "menu", 1
    for arg in sys.argv[4:]:
        if arg.startswith("--view="):
            view = arg.split("=", 1)[1]
        elif arg.startswith("--scale="):
            scale = int(arg.split("=", 1)[1])
    buf = render(glb, png, view, scale)
    culled = write_images(buf, prefix)
    covered = sum(1 for t in buf["tri"] if t >= 0)
    print("wrote %s_{tri,lit,cull}.png  view=%s  %dx%d  covered px %d  front-most hit is a BACK face at %d px"
          % (prefix, view, buf["width"], buf["height"], covered, culled))


if __name__ == "__main__":
    main()
