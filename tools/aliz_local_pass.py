#!/usr/bin/env python3
"""Close Aliz's open-mouthed grin and give her a solid fringe, locally.

Zero credits, zero network, no Blender. Reads and rewrites the runtime GLB and
its 512-square atlas, and nothing else.

    python3 tools/aliz_local_pass.py <in.glb> <in.png> <out.glb> <out.png>

## What was actually wrong -- measured, not assumed

Both defects had been recorded as "modelled geometry, and the hair has real
holes". Half of that is true, and the half that is not sent the previous attempt
at the wrong fix. `tools/aliz_screen_probe.py` renders the mesh in software with
a z-buffer, so every screen pixel can be traced to a triangle and a texel:

* **The grin IS geometry.** Down the midline the surface jumps from z = 0.215 to
  z = 0.112 in a single pixel -- a **10 cm** cavity in a head 0.28 m deep, with a
  tongue and a strip of teeth inside it. Painting cannot close that.
* **The hair has NO holes.** Flood-filling the background of that render finds
  **zero** enclosed background pixels: nothing shows through. What reads as a
  torn fringe is the *atlas* painting skin over the front of the hair volume,
  leaving a few ragged pink ribbons on a bald forehead. That is a texture
  defect, and a scalp cap or an inner shell -- the obvious fix for holes -- would
  have added triangles and changed nothing at all.

## Why a 3D selection works where the UV box failed

The abandoned `close_aliz_smile.py` selected the mouth with a rectangle on the
atlas and caught leg and dress vertices. That rectangle was the mistake, not the
atlas: rasterising every triangle into UV space and recording **all** claimants
per texel shows 141,206 of 142,116 covered texels belong to exactly one
triangle, and **zero** texels are shared between regions more than 12 cm apart.
The unwrap is fragmented, but it does not overlap.

So the atlas is safe to edit *provided the selection is made in 3D and mapped
forward*. Every texel written here is chosen by where it lives on the character,
and is written only if every triangle claiming it also lives there. A leg cannot
be reached by construction.

## The two edits

**1. The mouth, closed as geometry then painted as a mouth.** The outer face
surface is recovered as a robust quadratic `z = f(x, y)` fitted to the rendered
face around the mouth, re-fitted four times while discarding everything sitting
behind it -- which is precisely the cavity. Every vertex in the mouth box is then
*clamped forward* to that surface. A clamp, not a projection: a vertex already on
the surface does not move, so the lip rim and the silhouette are untouched and no
seam can open. Strength tapers to zero at the box edge so there is no step where
the selection stops. Normals in the patch are replaced by the fitted surface's
own normal, so it lights like a cheek instead of like a throat.

The patch is then painted skin, and one filled shape in art-bible §4's `#9E4F4D`
is drawn on it as a closed smile. §4 is explicit: "one filled shape... no lips,
no lip line, no teeth, no tongue" and "**no visible teeth, ever**". The grin
violated that rule; the fix is the rule.

**2. The fringe, painted solid.** Front-of-head texels above a gentle arc just
clear of the lashes are written in her own hair pink, sampled from her own crown
rather than invented, so the ragged ribbons become one rounded mass -- §4's "2-5
solid rounded masses, no hair cards, no alpha, no strands".

Triangle count, texture size, material count, skin weights, joints and bone
bindings are all untouched: this only moves some positions and normals, and
repaints some texels.
"""

import math
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aliz_head_probe import read_glb, write_glb, load_mesh  # noqa: E402
from aliz_screen_probe import render  # noqa: E402
from png_edit import load as png_load, save as png_save  # noqa: E402

# ---------------------------------------------------------------------------
# Landmarks. Every one of these is measured off the model, not chosen: see
# docs/ALIZ_LOCAL_PASS.md for the measurement that produced each.
# ---------------------------------------------------------------------------

# The cavity, from the software render: x in [-0.057, +0.060], y in [1.135,
# 1.212]. The box is that plus margin. It does NOT define the selection -- the
# flood fill does -- it only stops the fill wandering down onto the underside of
# the jaw, which is recessed for perfectly good reasons and starts at y = 1.122.
CAVITY_X = 0.110
CAVITY_Y0, CAVITY_Y1 = 1.128, 1.238
# Behind the fitted face surface, in metres: what counts as "obviously a hole"
# for a seed, and what counts as "still inside" when growing. The rim sits at
# ~0 by construction, so GROW_DEPTH is what makes the fill stop at the lips.
SEED_DEPTH = 0.030
GROW_DEPTH = 0.005
# Kept 1.2 mm behind the fitted surface: enough for the one directional light to
# put a hairline of shade in the seam, not enough to read as a hole.
MOUTH_RECESS = 0.0012

# Eyes and lashes top out at y = 1.381. The fringe sits clear of them.
FRINGE_Y = 1.418
FRINGE_CURVE = 0.42     # rises toward the temples: y += CURVE * x^2
FRINGE_SOFT = 0.012     # blend band, in metres

# The repaint footprint. Deliberately WIDER than the cavity and separate from
# the geometry taper: the first run reused the taper as the paint weight, and
# at the top of the box that weight is 0.19, so the old teeth survived at 80%
# opacity as white slashes either side of the new mouth. Paint coverage and
# vertex-move strength are different questions and now have different masks.
PATCH_RX, PATCH_RY = 0.082, 0.050
PATCH_CY = 1.1800
PATCH_SOFT = 0.16      # fraction of the radius spent fading out

# Her own colours, sampled from her own model.
HAIR = (254, 121, 151)
SKIN = (253, 206, 182)
MOUTH_INK = (158, 79, 77)     # art bible §4, `#9E4F4D`

# The painted smile, in metres on the model. Anti-aliased over SMILE_AA, which
# matters more than it sounds: this patch is covered by three different atlas
# islands at three different texel densities, and a hard threshold makes the
# island seams visible as steps along the lip.
SMILE_CX, SMILE_CY = 0.000, 1.1835
SMILE_HALF_W = 0.0300
SMILE_DEPTH = 0.0064
SMILE_AA = 0.0016
# The corners ride UP by this much, in metres. Without it the band is a level
# lens and reads as a neutral closed mouth; art bible §4's resting face is
# "content", and the whole point of the pass is that she looks pleased to see
# you rather than alarmed.
SMILE_ARC = 0.0062


# ---------------------------------------------------------------------------
# The outer face surface
# ---------------------------------------------------------------------------

def solve(a, b):
    """Gauss-Jordan on a small dense system. No numpy in this environment."""
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(m[r][c]))
        if abs(m[p][c]) < 1e-12:
            raise ValueError("singular normal equations")
        m[c], m[p] = m[p], m[c]
        pivot = m[c][c]
        for j in range(c, n + 1):
            m[c][j] /= pivot
        for r in range(n):
            if r == c:
                continue
            f = m[r][c]
            if f:
                for j in range(c, n + 1):
                    m[r][j] -= f * m[c][j]
    return [m[i][n] for i in range(n)]


def fit_face_surface(samples, rounds=4, reject=0.012):
    """Robust quadratic z = f(x, y) over the face around the mouth.

    `samples` are (x, y, z) points off the rendered surface, cavity included.
    Each round drops everything sitting more than `reject` BEHIND the current
    fit -- one-sided, because the only thing behind a face is the inside of it.
    """
    pts = list(samples)
    coeff = None
    for _ in range(rounds):
        a = [[0.0] * 6 for _ in range(6)]
        rhs = [0.0] * 6
        for x, y, z in pts:
            t = (1.0, x, y, x * x, y * y, x * y)
            for i in range(6):
                rhs[i] += t[i] * z
                for j in range(6):
                    a[i][j] += t[i] * t[j]
        coeff = solve(a, rhs)
        keep = [(x, y, z) for x, y, z in pts if z > surface(coeff, x, y) - reject]
        if len(keep) < 80 or len(keep) == len(pts):
            pts = keep or pts
            break
        pts = keep
    return coeff, len(pts)


def surface(c, x, y):
    return c[0] + c[1] * x + c[2] * y + c[3] * x * x + c[4] * y * y + c[5] * x * y


def surface_normal(c, x, y):
    """Unit normal of z = f(x, y), pointing out of the face (+Z)."""
    dx = c[1] + 2.0 * c[3] * x + c[5] * y
    dy = c[2] + 2.0 * c[4] * y + c[5] * x
    n = (-dx, -dy, 1.0)
    L = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
    return (n[0] / L, n[1] / L, n[2] / L)


# ---------------------------------------------------------------------------
# Atlas ownership -- every claimant of every texel, so nothing is written blind
# ---------------------------------------------------------------------------

def claim_map(pos, uv, idx, W, H):
    """-> (claims, where): claims[i] = every triangle whose UV footprint reaches
    texel i, where[i] = that texel's 3D position taken from its BEST claimant.

    "Best" is the claimant with the most interior barycentric coordinates. This
    is not a nicety. Coverage is deliberately generous by half a texel so seams
    are not dropped, and a half-texel extrapolation off a small triangle can
    land centimetres away: taking the *first* claimant put texels of the upper
    lip at z = -0.091, on the back of the skull, and the mouth repaint then
    skipped them and left the old teeth showing as a white slash.
    """
    claims = [None] * (W * H)
    where = [None] * (W * H)
    best = [-1e9] * (W * H)
    for t in range(0, len(idx), 3):
        a, b, c = idx[t], idx[t + 1], idx[t + 2]
        ax, ay = uv[a][0] * W, uv[a][1] * H
        bx, by = uv[b][0] * W, uv[b][1] * H
        cx, cy = uv[c][0] * W, uv[c][1] * H
        minx = max(0, int(min(ax, bx, cx)) - 1)
        maxx = min(W - 1, int(max(ax, bx, cx)) + 1)
        miny = max(0, int(min(ay, by, cy)) - 1)
        maxy = min(H - 1, int(max(ay, by, cy)) + 1)
        d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(d) < 1e-12 or minx > maxx or miny > maxy:
            continue
        inv = 1.0 / d
        for y in range(miny, maxy + 1):
            py = y + 0.5
            for x in range(minx, maxx + 1):
                px = x + 0.5
                l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) * inv
                l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) * inv
                l3 = 1.0 - l1 - l2
                # Half-texel gutter, so a seam is covered rather than dropped.
                if l1 < -0.5 or l2 < -0.5 or l3 < -0.5:
                    continue
                i = y * W + x
                interior = min(l1, l2, l3)
                # Only a STRICT claimant is recorded as an owner. A triangle
                # whose footprint merely comes within half a texel does sit in
                # `claims` nowhere -- and that matters: several mouth texels are
                # grazed by the gutter of a dress island 0.94 m away, and
                # treating that as ownership refused 600 legitimate writes and
                # left a pink scratch beside the new mouth.
                if interior >= 0.0:
                    if claims[i] is None:
                        claims[i] = [t // 3]
                    else:
                        claims[i].append(t // 3)
                if interior > best[i]:
                    best[i] = interior
                    where[i] = (
                        l1 * pos[a][0] + l2 * pos[b][0] + l3 * pos[c][0],
                        l1 * pos[a][1] + l2 * pos[b][1] + l3 * pos[c][1],
                        l1 * pos[a][2] + l2 * pos[b][2] + l3 * pos[c][2],
                    )
    return claims, where


def replace_embedded_image(js, bin_, png_bytes):
    """Swap the GLB's embedded atlas for `png_bytes`, compacting the buffer.

    **This is not optional.** The import preset is
    `gltf/embedded_image_handling=1` (Extract Textures): Godot pulls the image
    out of the GLB into the sibling `*_texture_0.png` and renders from that.
    Editing only the sibling leaves the GLB still carrying the grinning atlas,
    and the day anything triggers a re-extract the old face comes back. Both
    copies are written, so there is no stale one to come back.

    Every bufferView is relaid out at its new offset rather than the image being
    appended, so the file does not grow by a dead 310 KB copy.
    """
    if not js.get("images"):
        raise ValueError("no embedded image to replace")
    img = js["images"][0]
    if "bufferView" not in img:
        raise ValueError("image is a URI, not embedded -- nothing to replace")
    target = img["bufferView"]

    views = js["bufferViews"]
    order = sorted(range(len(views)), key=lambda k: views[k].get("byteOffset", 0))
    out = bytearray()
    for k in order:
        bv = views[k]
        if k == target:
            data = bytes(png_bytes)
        else:
            start = bv.get("byteOffset", 0)
            data = bytes(bin_[start:start + bv["byteLength"]])
        while len(out) % 4:
            out.append(0)
        bv["byteOffset"] = len(out)
        bv["byteLength"] = len(data)
        out += data
    js["buffers"][0]["byteLength"] = len(out)
    img["mimeType"] = "image/png"
    return out


def tri_centroids(pos, idx):
    out = []
    for t in range(0, len(idx), 3):
        a, b, c = idx[t], idx[t + 1], idx[t + 2]
        out.append((
            (pos[a][0] + pos[b][0] + pos[c][0]) / 3.0,
            (pos[a][1] + pos[b][1] + pos[c][1]) / 3.0,
            (pos[a][2] + pos[b][2] + pos[c][2]) / 3.0,
        ))
    return out


def blend(dst, src, k):
    k = max(0.0, min(1.0, k))
    return tuple(int(round(dst[i] + (src[i] - dst[i]) * k)) for i in range(3))


def patch_weight(x, y):
    """1 across the mouth patch, easing to 0 at its rim. Ellipse in model
    metres, so it is the same shape whichever atlas island reaches it."""
    e = math.hypot(x / PATCH_RX, (y - PATCH_CY) / PATCH_RY)
    if e >= 1.0:
        return 0.0
    if e <= 1.0 - PATCH_SOFT:
        return 1.0
    t = (1.0 - e) / PATCH_SOFT
    return t * t * (3.0 - 2.0 * t)


def smile_weight(x, y):
    """One filled shape -- flat-ish above, arced below -- with a soft edge.

    Art bible §4: "One filled shape in #9E4F4D. No lips, no lip line, no teeth,
    no tongue." The shape is expressed as a signed distance in metres so the
    edge can be feathered; a hard in/out test showed the atlas island seams.
    """
    u = x / SMILE_HALF_W
    if abs(u) >= 1.0 + SMILE_AA / SMILE_HALF_W:
        return 0.0
    bulge = max(0.0, 1.0 - u * u)
    # Centreline rises toward both corners; thickness is greatest in the middle.
    mid = SMILE_CY + SMILE_ARC * min(1.0, u * u)
    lo = mid - SMILE_DEPTH * (0.55 + 0.45 * bulge)
    hi = mid + SMILE_DEPTH * (0.35 + 0.35 * bulge)
    # Distance outside the band, in metres, taking the horizontal ends too.
    d = max(lo - y, y - hi, (abs(x) - SMILE_HALF_W))
    if d <= -SMILE_AA:
        return 1.0
    if d >= SMILE_AA:
        return 0.0
    t = (SMILE_AA - d) / (2.0 * SMILE_AA)
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------------------

def main():
    in_glb, in_png, out_glb, out_png = sys.argv[1:5]
    js, bin_ = read_glb(in_glb)
    m = load_mesh(js, bin_)
    pos, nor, uv, idx = m["pos"], m["nor"], m["uv"], m["idx"]
    W, H, C, tex = png_load(in_png)

    # -- 1. recover the outer face surface from the forward render -----------
    buf = render(in_glb, in_png, head_y=1.24)
    S = buf["size"]
    samples = []
    for i in range(S * S):
        p = buf["pos"][i]
        if p is None:
            continue
        if abs(p[0]) < 0.115 and 1.095 <= p[1] <= 1.265 and p[2] > 0.02:
            samples.append(p)
    coeff, kept = fit_face_surface(samples)
    print("face surface fitted from %d of %d rendered samples" % (kept, len(samples)))
    print("  z at (0, 1.18) = %.4f   at (0.06, 1.18) = %.4f"
          % (surface(coeff, 0.0, 1.18), surface(coeff, 0.06, 1.18)))

    # -- 2. find the cavity by connectivity, then clamp it forward -----------
    #
    # Not by box-and-taper. That was the first version and it under-moved the
    # corners of the mouth: `test_aliz_face.gd` found a vertex still sitting
    # 57 mm behind the face, hidden behind the new lip but very much still a
    # throat. Fading the correction out toward an arbitrary boundary is the
    # wrong shape for this problem.
    #
    # A flood fill is the right shape. Seeds are vertices deep behind the
    # surface near the midline; growth crosses to any neighbour that is also
    # meaningfully behind it. The **lip rim is on the surface**, so the fill
    # stops there by itself -- the cavity is bounded by its own opening. The box
    # only stops the fill wandering down the jaw, which is legitimately recessed
    # and must not be touched.
    #
    # And because every flooded vertex is then clamped at FULL strength, no
    # taper is needed and none is wanted: a vertex near the rim is already near
    # the surface and therefore barely moves, so the patch meets the lip
    # smoothly on its own.
    welded = {}
    for v, p in enumerate(pos):
        welded.setdefault((round(p[0] * 1e5), round(p[1] * 1e5), round(p[2] * 1e5)),
                          []).append(v)
    wid = {}
    for k, group in welded.items():
        for v in group:
            wid[v] = k
    adj = {}
    for t in range(0, len(idx), 3):
        a, b, c = wid[idx[t]], wid[idx[t + 1]], wid[idx[t + 2]]
        for u, w in ((a, b), (b, c), (c, a)):
            adj.setdefault(u, set()).add(w)
            adj.setdefault(w, set()).add(u)

    def depth_of(key):
        v = welded[key][0]
        x, y, z = pos[v]
        return surface(coeff, x, y) - z

    def in_box(key):
        x, y, z = pos[welded[key][0]]
        return abs(x) < CAVITY_X and CAVITY_Y0 < y < CAVITY_Y1 and z > 0.0

    seeds = [k for k in welded
             if in_box(k) and depth_of(k) > SEED_DEPTH
             and abs(pos[welded[k][0]][0]) < 0.06]
    cavity = set(seeds)
    stack = list(seeds)
    while stack:
        k = stack.pop()
        for n in adj.get(k, ()):
            if n in cavity or not in_box(n) or depth_of(n) <= GROW_DEPTH:
                continue
            cavity.add(n)
            stack.append(n)
    print("cavity: %d seeds grew to %d welded vertices" % (len(seeds), len(cavity)))

    moved = 0
    deepest = 0.0
    touched_verts = set()
    for k in cavity:
        for v in welded[k]:
            x, y, z = pos[v]
            target = surface(coeff, x, y) - MOUTH_RECESS
            if z >= target:
                continue
            deepest = max(deepest, target - z)
            pos[v] = (x, y, target)
            nor[v] = surface_normal(coeff, x, y)
            moved += 1
            touched_verts.add(v)
    print("clamped %d vertices forward; largest move %.1f mm" % (moved, deepest * 1000))

    # Write positions and normals back through their own accessors.
    import struct
    for v in touched_verts:
        struct.pack_into("<fff", bin_, m["pos_base"] + v * m["pos_stride"], *pos[v])
        struct.pack_into("<fff", bin_, m["nor_base"] + v * m["nor_stride"], *nor[v])
    # The POSITION accessor's min/max must still bound the data or Godot's
    # importer culls against a stale box. The mouth is interior, so this is
    # belt and braces -- but a wrong min/max is invisible until it is not.
    acc = js["accessors"][m["prim"]["attributes"]["POSITION"]]
    acc["min"] = [min(p[k] for p in pos) for k in range(3)]
    acc["max"] = [max(p[k] for p in pos) for k in range(3)]

    # -- 3. repaint, with every write guarded by where it lives --------------
    claims, where = claim_map(pos, uv, idx, W, H)
    cent = tri_centroids(pos, idx)

    # THE SAFETY GUARD. A texel is written only if EVERY triangle that reaches
    # it lives inside the head. The head is a sphere, not a z > 0 half-space:
    # the first version of this test treated the back of the skull as "off the
    # head" and refused 744 perfectly good writes, which is what left a ghost of
    # the old mouth on the chin. A sphere admits the whole head and still cannot
    # reach a shoulder, let alone a leg -- the nearest non-head geometry is the
    # neck at y = 1.02, well outside it.
    HEAD_C = (0.0, 1.400, 0.0)
    HEAD_R = 0.360

    def all_claimants_on_head(i):
        # No strict owner at all: a gutter texel between islands. Safe to write
        # -- and it MUST be written, or the seam keeps the colour it had and
        # bilinear filtering drags it back over the edit.
        for t in (claims[i] or ()):
            c = cent[t]
            if math.dist(c, HEAD_C) > HEAD_R:
                return False
        return True

    painted_mouth = 0
    painted_hair = 0
    rejected = 0
    painted = bytearray(W * H)
    for i in range(W * H):
        p = where[i]
        if p is None:
            continue
        x, y, z = p

        # --- the mouth patch ---
        if z > 0.0:
            k = patch_weight(x - SMILE_CX, y)
            if k > 0.0:
                if not all_claimants_on_head(i):
                    rejected += 1
                    continue
                o = i * C
                col = blend(SKIN, MOUTH_INK, smile_weight(x - SMILE_CX, y))
                tex[o:o + 3] = bytes(
                    blend((tex[o], tex[o + 1], tex[o + 2]), col, k))
                painted[i] = 1
                painted_mouth += 1
                continue

        # --- the fringe ---
        if z > 0.02 and y > FRINGE_Y - 0.06 and abs(x) < 0.30:
            edge = FRINGE_Y + FRINGE_CURVE * x * x
            if y > edge - FRINGE_SOFT:
                if not all_claimants_on_head(i):
                    rejected += 1
                    continue
                k = min(1.0, (y - (edge - FRINGE_SOFT)) / FRINGE_SOFT)
                o = i * C
                tex[o:o + 3] = bytes(
                    blend((tex[o], tex[o + 1], tex[o + 2]), HAIR, k))
                painted[i] = 1
                painted_hair += 1

    # Edge padding. A handful of texels inside the patch belong to no triangle
    # at all -- they are the gutter between islands -- so the loop above never
    # reached them and they kept the old tongue-pink. At mouth size that is a
    # visible fleck beside the lip, and under bilinear and the generated mipmaps
    # it also bleeds back INTO the edit. Grow the painted colour two texels into
    # unowned atlas, which is what any texture bake does and costs nothing.
    grown = 0
    for _ in range(2):
        add = []
        for i in range(W * H):
            if painted[i] or where[i] is not None:
                continue
            x, y = i % W, i // W
            acc = []
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and painted[ny * W + nx]:
                    o = (ny * W + nx) * C
                    acc.append((tex[o], tex[o + 1], tex[o + 2]))
            if acc:
                add.append((i, tuple(sum(c[k] for c in acc) // len(acc)
                                     for k in range(3))))
        for i, col in add:
            tex[i * C:i * C + 3] = bytes(col)
            painted[i] = 1
        grown += len(add)
    print("edge padding: %d gutter texels filled" % grown)

    print("repainted: mouth %d texels, fringe %d texels; %d writes refused "
          "(a claimant lived off the head)" % (painted_mouth, painted_hair, rejected))
    png_save(out_png, W, H, C, tex)
    print("wrote %s" % out_png)

    # -- 4. keep the GLB's own copy of the atlas in step ---------------------
    bin_ = replace_embedded_image(js, bin_, open(out_png, "rb").read())
    write_glb(out_glb, js, bin_)
    print("wrote %s (embedded atlas replaced too)" % out_glb)


if __name__ == "__main__":
    main()
