#!/usr/bin/env python3
"""Aliz polish pass: close the holes in her hair, peel the folded mouth patch,
calm the hair shading, and pad the atlas gutters. Local only: zero credits, zero
network, no Blender, no regeneration.

    python3 tools/aliz_polish_pass.py <in.glb> <in.png> <out.glb> <out.png>

## What the three "cosmetic" defects actually were -- measured

`tools/aliz_view_probe.py` renders through the REAL menu camera with back-face
culling, which the older head-on probe never did. That one difference is why
the earlier pass recorded "the hair has no holes": without culling, a hole shows
the inside of the far side of the head, which is pink, and looks like hair.

1. **The "chip" beside her face is the sky.** A ray through the chip pixels hits
   nothing but the culled inside of the back of her head: there is a real
   7-vertex hole in the hair mesh on her left side (x +0.18..+0.26, y 1.39..1.54)
   and it is see-through. In the menu it shows sky, in the house it shows the
   purple wall -- hence "pink chip" in one shot and "lavender chip" in another.
   There are ten such boundary loops on the head in total, from a 1 cm slit in
   the fringe to that 15 cm one, plus a detached 16-triangle fragment floating
   at the crown.

2. **The "goatee" is the flattened mouth cavity fighting itself.** Clamping the
   cavity forward (the previous pass) left every wall of the old pocket lying on
   the same surface: 15 triangles now wind backwards and are culled, leaving
   thin gaps exactly along the mouth-corner-to-chin diagonals, and 9.6 cm2 of
   the patch has two or three coplanar front-facing layers z-fighting. 17 rim
   vertices still carry normals that point into a cavity that no longer exists
   (worst: 179 degrees off). At menu distance all of that averages to a smudge
   under the mouth.

3. **The crown lines are lit strand walls.** The fringe strands are modelled as
   ridges on the head, and each ridge has a thin side wall whose normal points
   sideways or down (e.g. (0.92, -0.21, 0.32) beside neighbours at (-0.2, 0, -1)).
   A lit render from the stored normals reproduces every line, so it is neither
   texture nor culling: it is the shading of real geometry seen edge-on.

## The four edits, least destructive first

* **Delete** the floating 16-triangle fragment (a 1 cm chip in space).
* **Cap** each boundary loop on the head by ear-clipping it. Cap triangles reuse
  the loop's own vertices when some choice of their UV duplicates lands on a
  small all-hair footprint; otherwise they get new vertices whose UVs sit on a
  tiny triangle deep inside a solid hair island, so nothing can sweep the atlas.
* **Peel** the mouth patch: drop the back-wound triangles (Godot never drew
  them), then greedily remove coplanar duplicates while a 0.5 mm coverage grid
  proves no hole opens. Recompute the region's normals from what remains.
  About 1 cm2 of partially overlapping coplanar duplicates survives, because
  no member of those pairs can go without opening a hole. Recessing them on
  duplicate vertices was tried and REJECTED: it opened 1.2 mm cracks along
  their free edges that the sky shows through at gameplay distance. Their
  colour is identical and their normals now agree to within a few degrees,
  so the residual flicker is far below what the culled slivers were.
* **Soften the lower face**: the shelf under the closed mouth (the old lower
  lip's edge, Lambert 0.05 under the menu light against 0.23 for the mouth)
  is the dark band that read as a beard. Its normals are blended halfway
  toward the head cylinder, fading out over 3 cm. No vertex moves.
* **Transfer hair normals** from a capsule around the head, 70/30 with the
  smooth mesh normal. Art bible section 4 asks for hair as "solid rounded
  masses"; this shades it as one, so a strand wall no longer lights up as a line.
  Silhouettes are untouched: only normals change.
* **Pad the atlas**: every texel no triangle owns is filled from its nearest
  owned neighbours, so the mipmaps stop averaging black into every island edge.

Skin weights, joints and the animation are untouched. New vertices copy their
joints and weights from the loop vertex they duplicate.
"""

import math
import struct
import sys
from collections import Counter, defaultdict

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aliz_head_probe import read_glb, write_glb, load_mesh, weld, sample  # noqa: E402
from aliz_local_pass import claim_map  # noqa: E402
from aliz_screen_probe import classify  # noqa: E402
from png_edit import load as png_load, save as png_save  # noqa: E402

HEAD_Y = 1.20            # nothing below this is touched by the hole or hair steps
TINY_SHELL_TRIS = 100    # a welded shell smaller than this on the head is debris

# The mouth patch, generous: the whole clamped pocket plus its rim.
MOUTH_X, MOUTH_Y0, MOUTH_Y1, MOUTH_Z = 0.115, 1.09, 1.28, 0.10
GRID = 0.0005            # coverage grid, metres
LAYER_TOL = 0.002        # two triangles closer than this are the same layer

# Hair normal transfer.
CAPSULE_CENTRE_Z = -0.02
HAIR_PROXY_WEIGHT = 0.70

# Lower-face normal softening: the core region, its fade width, and how far
# toward the head cylinder the normals go at the core.
FACE_SOFT_X, FACE_SOFT_Y0, FACE_SOFT_Y1, FACE_SOFT_Z = 0.09, 1.09, 1.26, 0.12
FACE_SOFT_FADE = 0.03
FACE_SOFT_WEIGHT = 0.50

CAP_UV_MAX_EDGE = 40     # texels; a reused-UV cap footprint longer than this is a sweep
CAP_UV_MIN_HAIR = 0.97


def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def mul(a, k): return (a[0] * k, a[1] * k, a[2] * k)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def length(a): return math.sqrt(dot(a, a))
def unit(a):
    L = length(a)
    return (a[0] / L, a[1] / L, a[2] / L) if L > 1e-12 else (0.0, 0.0, 1.0)


class Mesh:
    """Raw vertex arrays plus a triangle list that can shrink and grow."""

    def __init__(self, js, bin_):
        m = load_mesh(js, bin_)
        self.prim = m["prim"]
        self.pos = list(m["pos"])
        self.nor = list(m["nor"])
        self.uv = list(m["uv"])
        acc = js["accessors"]
        ja = acc[self.prim["attributes"]["JOINTS_0"]]
        wa = acc[self.prim["attributes"]["WEIGHTS_0"]]
        jv, wv = js["bufferViews"][ja["bufferView"]], js["bufferViews"][wa["bufferView"]]
        jb = jv.get("byteOffset", 0) + ja.get("byteOffset", 0)
        wb = wv.get("byteOffset", 0) + wa.get("byteOffset", 0)
        self.joints = [struct.unpack_from("<4B", bin_, jb + 4 * k) for k in range(ja["count"])]
        self.weights = [struct.unpack_from("<4f", bin_, wb + 16 * k) for k in range(wa["count"])]
        idx = m["idx"]
        self.tris = [(idx[t], idx[t + 1], idx[t + 2]) for t in range(0, len(idx), 3)]
        self.reweld()

    def reweld(self):
        self.wid, self.groups = weld(self.pos)

    def add_vertex(self, like, uv):
        self.pos.append(self.pos[like])
        self.nor.append(self.nor[like])
        self.uv.append(uv)
        self.joints.append(self.joints[like])
        self.weights.append(self.weights[like])
        # Keep the weld map honest for the new vertex: same position, same group.
        self.wid.append(self.wid[like])
        self.groups[self.wid[like]].append(len(self.pos) - 1)
        return len(self.pos) - 1

    def face_normal(self, t):
        a, b, c = t
        return cross(sub(self.pos[b], self.pos[a]), sub(self.pos[c], self.pos[a]))

    def centroid(self, t):
        a, b, c = t
        return mul(add(add(self.pos[a], self.pos[b]), self.pos[c]), 1.0 / 3.0)


# ---------------------------------------------------------------------------
# 1. debris
# ---------------------------------------------------------------------------

def drop_tiny_shells(mesh):
    parent = list(range(len(mesh.groups)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for a, b, c in mesh.tris:
        ra, rb, rc = find(mesh.wid[a]), find(mesh.wid[b]), find(mesh.wid[c])
        parent[rb] = ra
        parent[find(rc)] = find(ra)
    size = Counter(find(mesh.wid[t[0]]) for t in mesh.tris)
    keep, dropped = [], []
    for t in mesh.tris:
        if size[find(mesh.wid[t[0]])] < TINY_SHELL_TRIS and mesh.centroid(t)[1] > HEAD_Y:
            dropped.append(t)
        else:
            keep.append(t)
    mesh.tris = keep
    if dropped:
        c = (0.0, 0.0, 0.0)
        for t in dropped:
            c = add(c, mesh.centroid(t))
        c = mul(c, 1.0 / len(dropped))
        print("debris: dropped %d triangles of a detached fragment at (%+.3f, %.3f, %+.3f)"
              % (len(dropped), *c))
    return len(dropped)


# ---------------------------------------------------------------------------
# 2. holes
# ---------------------------------------------------------------------------

def boundary_loops(mesh):
    """Ordered welded loops, following the existing triangles' edge direction."""
    dedge = defaultdict(list)
    for ti, (a, b, c) in enumerate(mesh.tris):
        w = (mesh.wid[a], mesh.wid[b], mesh.wid[c])
        for k in range(3):
            dedge[(w[k], w[(k + 1) % 3])].append(ti)
    nxt = {}
    for (a, b) in dedge:
        if (b, a) not in dedge and a != b:
            nxt.setdefault(a, b)
    seen, loops = set(), []
    for a in list(nxt):
        if a in seen:
            continue
        loop, cur = [], a
        while cur in nxt and cur not in seen:
            seen.add(cur)
            loop.append(cur)
            cur = nxt[cur]
        if len(loop) >= 3 and cur == a:
            loops.append(loop)
    return loops


def ear_clip(points2d):
    """Triangulate a CCW simple polygon; returns index triples. Falls back to a
    fan when the polygon is too degenerate to clip, which for a 3-5 vertex
    slit is the same answer."""
    n = len(points2d)
    idxs = list(range(n))
    out = []

    def area2(i, j, k):
        (ax, ay), (bx, by), (cx, cy) = points2d[i], points2d[j], points2d[k]
        return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)

    def inside(p, i, j, k):
        (ax, ay), (bx, by), (cx, cy) = points2d[i], points2d[j], points2d[k]
        (px, py) = points2d[p]
        d1 = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
        d2 = (cx - bx) * (py - by) - (cy - by) * (px - bx)
        d3 = (ax - cx) * (py - cy) - (ay - cy) * (px - cx)
        return d1 >= 0 and d2 >= 0 and d3 >= 0

    guard = 0
    while len(idxs) > 3 and guard < 10 * n:
        guard += 1
        clipped = False
        for m in range(len(idxs)):
            i, j, k = idxs[m - 1], idxs[m], idxs[(m + 1) % len(idxs)]
            if area2(i, j, k) <= 1e-12:
                continue
            if any(inside(p, i, j, k) for p in idxs if p not in (i, j, k)):
                continue
            out.append((i, j, k))
            idxs.pop(m)
            clipped = True
            break
        if not clipped:
            break
    if len(idxs) == 3:
        out.append(tuple(idxs))
    elif len(idxs) > 3:
        out = [(idxs[0], idxs[m], idxs[m + 1]) for m in range(1, len(idxs) - 1)]
    return out


def uv_footprint_score(mesh, tri_raw, W, H, C, tex):
    """(fraction of hair texels under the UV triangle, longest UV edge in texels)."""
    (ax, ay), (bx, by), (cx, cy) = [(mesh.uv[v][0] * W, mesh.uv[v][1] * H) for v in tri_raw]
    longest = max(math.hypot(bx - ax, by - ay), math.hypot(cx - bx, cy - by), math.hypot(ax - cx, ay - cy))
    minx, maxx = max(0, int(min(ax, bx, cx)) - 1), min(W - 1, int(max(ax, bx, cx)) + 1)
    miny, maxy = max(0, int(min(ay, by, cy)) - 1), min(H - 1, int(max(ay, by, cy)) + 1)
    d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    hair = total = 0
    if abs(d) > 1e-9:
        inv = 1.0 / d
        for y in range(miny, maxy + 1):
            for x in range(minx, maxx + 1):
                px, py = x + 0.5, y + 0.5
                l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) * inv
                l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) * inv
                l3 = 1.0 - l1 - l2
                if min(l1, l2, l3) < -0.5:
                    continue
                total += 1
                o = (y * W + x) * C
                if classify(tex[o], tex[o + 1], tex[o + 2]) == "hair":
                    hair += 1
    if total == 0:
        # A footprint smaller than a texel: judge the texels under the corners.
        cols = [classify(*sample(tex, W, H, C, *mesh.uv[v])) for v in tri_raw]
        return (sum(1 for c in cols if c == "hair") / 3.0, longest)
    return (hair / total, longest)


def safe_hair_texel(W, H, C, tex):
    """The hair texel farthest from any non-hair texel, by erosion."""
    mask = bytearray(1 if classify(tex[i * C], tex[i * C + 1], tex[i * C + 2]) == "hair" else 0
                     for i in range(W * H))
    last = None
    for _ in range(64):
        alive = [i for i in range(W * H) if mask[i]]
        if not alive:
            break
        last = alive
        nxt = bytearray(W * H)
        for i in alive:
            x, y = i % W, i // W
            if 0 < x < W - 1 and 0 < y < H - 1 and all(
                    mask[(y + dy) * W + x + dx] for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                nxt[i] = 1
        mask = nxt
    i = last[len(last) // 2]
    return (i % W, i // W)


def cap_holes(mesh, W, H, C, tex):
    loops = [lp for lp in boundary_loops(mesh)
             if max(mesh.pos[mesh.groups[w][0]][1] for w in lp) > HEAD_Y]
    safe = safe_hair_texel(W, H, C, tex)
    print("holes: %d boundary loops on the head; fallback hair texel (%d, %d)" % (len(loops), *safe))
    added = reused = fresh = 0
    for lp in loops:
        pts = [mesh.pos[mesh.groups[w][0]] for w in lp]
        centre = (0.0, 0.0, 0.0)
        for p in pts:
            centre = add(centre, p)
        centre = mul(centre, 1.0 / len(pts))
        # Outward normal: the neighbouring triangles' own, so the cap winds like them.
        rim = set(lp)
        nsum = (0.0, 0.0, 0.0)
        for t in mesh.tris:
            if any(mesh.wid[v] in rim for v in t):
                nsum = add(nsum, mesh.face_normal(t))
        n = unit(nsum)
        # The existing triangles run a->b along the loop; the cap must run b->a,
        # so triangulate the reversed loop, which is CCW seen from outside.
        rev = lp[::-1]
        rpts = pts[::-1]
        ex = unit(sub(rpts[0], centre))
        ex = unit(sub(ex, mul(n, dot(ex, n))))
        ey = cross(n, ex)
        p2 = [(dot(sub(p, centre), ex), dot(sub(p, centre), ey)) for p in rpts]
        # Ensure CCW in this frame; if the loop came out CW the neighbours' normal
        # and the edge direction disagree, and the fan must be flipped instead.
        signed = sum(p2[i][0] * p2[(i + 1) % len(p2)][1] - p2[(i + 1) % len(p2)][0] * p2[i][1]
                     for i in range(len(p2)))
        flip = signed < 0
        if flip:
            p2 = [(x, -y) for (x, y) in p2]
        tris2d = ear_clip(p2)
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]; zs = [p[2] for p in pts]
        print("  loop n=%d x[%+.3f,%+.3f] y[%.3f,%.3f] z[%+.3f,%+.3f] -> %d triangles%s"
              % (len(lp), min(xs), max(xs), min(ys), max(ys), min(zs), max(zs), len(tris2d),
                 " (winding corrected)" if flip else ""))
        for (i, j, k) in tris2d:
            if flip:
                i, k = k, i
            corners = [rev[i], rev[j], rev[k]]
            # Try every choice of UV duplicate; keep the best all-hair, compact one.
            best = None
            options = [mesh.groups[w] for w in corners]
            for va in options[0]:
                for vb in options[1]:
                    for vc in options[2]:
                        score, longest = uv_footprint_score(mesh, (va, vb, vc), W, H, C, tex)
                        if longest > CAP_UV_MAX_EDGE:
                            continue
                        if best is None or score > best[0]:
                            best = (score, (va, vb, vc))
            if best is not None and best[0] >= CAP_UV_MIN_HAIR:
                mesh.tris.append(best[1])
                reused += 1
            else:
                u0, v0 = (safe[0] + 0.5) / W, (safe[1] + 0.5) / H
                du, dv = 0.6 / W, 0.6 / H
                va = mesh.add_vertex(options[0][0], (u0, v0))
                vb = mesh.add_vertex(options[1][0], (u0 + du, v0))
                vc = mesh.add_vertex(options[2][0], (u0, v0 + dv))
                mesh.tris.append((va, vb, vc))
                fresh += 1
            added += 1
    mesh.reweld()
    print("holes: capped with %d triangles (%d reuse loop UVs, %d on fresh vertices)"
          % (added, reused, fresh))
    return added


# ---------------------------------------------------------------------------
# 3. the mouth patch
# ---------------------------------------------------------------------------

def in_mouth(mesh, v):
    x, y, z = mesh.pos[v]
    return abs(x) < MOUTH_X and MOUTH_Y0 < y < MOUTH_Y1 and z > MOUTH_Z


def mouth_coverage(mesh, region):
    """-> (samples: {(gx,gy): [(z, tri_index)]}) for rendering (front-wound) tris."""
    samples = defaultdict(list)
    for ti in region:
        t = mesh.tris[ti]
        if mesh.face_normal(t)[2] <= 0.0:
            continue
        pa, pb, pc = (mesh.pos[v] for v in t)
        d = (pb[1] - pc[1]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[1] - pc[1])
        if abs(d) < 1e-14:
            continue
        inv = 1.0 / d
        minx, maxx = int((min(pa[0], pb[0], pc[0]) + MOUTH_X) / GRID), int((max(pa[0], pb[0], pc[0]) + MOUTH_X) / GRID) + 1
        miny, maxy = int((min(pa[1], pb[1], pc[1]) - MOUTH_Y0) / GRID), int((max(pa[1], pb[1], pc[1]) - MOUTH_Y0) / GRID) + 1
        for gy in range(miny, maxy + 1):
            py = MOUTH_Y0 + (gy + 0.5) * GRID
            for gx in range(minx, maxx + 1):
                px = -MOUTH_X + (gx + 0.5) * GRID
                l1 = ((pb[1] - pc[1]) * (px - pc[0]) + (pc[0] - pb[0]) * (py - pc[1])) * inv
                l2 = ((pc[1] - pa[1]) * (px - pc[0]) + (pa[0] - pc[0]) * (py - pc[1])) * inv
                l3 = 1.0 - l1 - l2
                if l1 < 0 or l2 < 0 or l3 < 0:
                    continue
                samples[(gx, gy)].append((l1 * pa[2] + l2 * pb[2] + l3 * pc[2], ti))
    return samples


def layers_of(samples, tol=LAYER_TOL):
    """Per sample: the rendering triangles within `tol` of the front-most."""
    out = {}
    for k, hs in samples.items():
        zf = max(h[0] for h in hs)
        out[k] = [ti for (z, ti) in hs if zf - z < tol]
    return out


def peel_mouth(mesh):
    region = [ti for ti, t in enumerate(mesh.tris) if all(in_mouth(mesh, v) for v in t)]
    before = layers_of(mouth_coverage(mesh, region))
    covered_before = set(before)
    fight_before = sum(1 for v in before.values() if len(v) > 1)
    inverted = [ti for ti in region if mesh.face_normal(mesh.tris[ti])[2] <= 0.0]
    print("mouth: %d triangles in the patch; %d wind backwards (culled); z-fighting on %d samples (%.1f cm2)"
          % (len(region), len(inverted), fight_before, fight_before * GRID * GRID * 1e4))

    remove = set(inverted)
    # Greedy peel: drop the most-overlapped duplicate while the coverage holds.
    for _ in range(200):
        live = [ti for ti in region if ti not in remove]
        layers = layers_of(mouth_coverage(mesh, live))
        overlapped = Counter()
        owned = Counter()
        for k, tis in layers.items():
            for ti in tis:
                owned[ti] += 1
                if len(tis) > 1:
                    overlapped[ti] += 1
        cands = sorted((ti for ti in overlapped if overlapped[ti] == owned[ti]),
                       key=lambda ti: -owned[ti])
        # Fully-overlapped triangles: every sample they touch has another layer.
        if not cands:
            # Nothing is entirely redundant; try the ones that are mostly so, but
            # only when removing them provably leaves every sample covered.
            cands = sorted((ti for ti in overlapped if overlapped[ti] >= 0.9 * owned[ti]),
                           key=lambda ti: -overlapped[ti])
        picked = None
        for ti in cands:
            trial = [u for u in live if u != ti]
            after = layers_of(mouth_coverage(mesh, trial))
            if set(after) >= covered_before:
                picked = ti
                break
        if picked is None:
            break
        remove.add(picked)
    live = [ti for ti in region if ti not in remove]
    after = layers_of(mouth_coverage(mesh, live))
    fight_after = sum(1 for v in after.values() if len(v) > 1)
    holes = len(covered_before - set(after))
    print("mouth: removed %d triangles (%d culled + %d duplicate layers); z-fighting now %d samples; new holes %d"
          % (len(remove), len(inverted), len(remove) - len(inverted), fight_after, holes))
    if holes:
        raise SystemExit("mouth peel opened a hole; refusing to write")
    mesh.tris = [t for ti, t in enumerate(mesh.tris) if ti not in remove]
    mesh.reweld()
    return len(remove)


def smooth_normals(mesh, select):
    """Area-weighted welded normals for every raw vertex `select` accepts."""
    acc = defaultdict(lambda: [0.0, 0.0, 0.0])
    for t in mesh.tris:
        n = mesh.face_normal(t)
        for v in t:
            s = acc[mesh.wid[v]]
            s[0] += n[0]; s[1] += n[1]; s[2] += n[2]
    changed = 0
    for v in range(len(mesh.pos)):
        if not select(v):
            continue
        s = acc.get(mesh.wid[v])
        if s is None or length(s) < 1e-12:
            continue
        mesh.nor[v] = unit(s)
        changed += 1
    return changed


def soften_lower_face(mesh):
    """Blend the lower-face normals halfway toward a vertical cylinder round
    the head, fading out over 2-3 cm at the edge of the region.

    Measured on the peeled patch: the mouth patch and the cheeks beside it
    agree (mean normals (-0.04,-0.40,+0.91) and (+0.02,-0.38,+0.89)), but the
    chin directly below drops away at (+0.03,-0.76,+0.54), which under the
    menu's overhead light is Lambert 0.05 against 0.23 for the patch. That
    shelf is the old lower lip's edge. With a grin it was the shadow under a
    lip; under a closed painted mouth it is a dark band that reads as a beard.
    Halving the tilt lifts it to the patch's level without moving a vertex.
    """
    changed = 0
    for g in mesh.groups:
        x, y, z = mesh.pos[g[0]]
        dx = max(0.0, abs(x) - FACE_SOFT_X) / FACE_SOFT_FADE
        dy = max(0.0, FACE_SOFT_Y0 - y, y - FACE_SOFT_Y1) / FACE_SOFT_FADE
        dz = max(0.0, FACE_SOFT_Z - z) / FACE_SOFT_FADE
        d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if d >= 1.0:
            continue
        k = (1.0 - d * d * (3.0 - 2.0 * d)) * FACE_SOFT_WEIGHT
        proxy = unit((x, 0.0, z - CAPSULE_CENTRE_Z))
        for v in g:
            mesh.nor[v] = unit(add(mul(proxy, k), mul(mesh.nor[v], 1.0 - k)))
            changed += 1
    print("face: %d raw vertex normals on the lower face softened toward the head cylinder (%.0f%% at the core)"
          % (changed, FACE_SOFT_WEIGHT * 100))
    return changed


# ---------------------------------------------------------------------------
# 4. hair normals
# ---------------------------------------------------------------------------

def transfer_hair_normals(mesh, W, H, C, tex):
    hair_groups = set()
    for g in mesh.groups:
        if mesh.pos[g[0]][1] < HEAD_Y - 0.15:
            continue
        if any(in_mouth(mesh, v) for v in g):
            continue
        if any(classify(*sample(tex, W, H, C, *mesh.uv[v])) == "hair" for v in g):
            hair_groups.add(mesh.wid[g[0]])
    pts = [mesh.pos[mesh.groups[w][0]] for w in hair_groups]
    if not pts:
        return 0
    ys = [p[1] for p in pts]
    top = max(ys)
    # Capsule: a sphere around the skull, a vertical cylinder below its centre so
    # the long hair shades as a hanging mass rather than as the bottom of a ball.
    radius = max(abs(p[0]) for p in pts)
    cy = top - radius * 0.9
    centre = (0.0, cy, CAPSULE_CENTRE_Z)
    # Smooth mesh normals first, then blend toward the proxy.
    acc = defaultdict(lambda: [0.0, 0.0, 0.0])
    for t in mesh.tris:
        n = mesh.face_normal(t)
        for v in t:
            s = acc[mesh.wid[v]]
            s[0] += n[0]; s[1] += n[1]; s[2] += n[2]
    changed = 0
    for w in hair_groups:
        p = mesh.pos[mesh.groups[w][0]]
        if p[1] >= cy:
            proxy = unit(sub(p, centre))
        else:
            proxy = unit((p[0], 0.0, p[2] - CAPSULE_CENTRE_Z))
        smooth = unit(acc[w]) if length(acc[w]) > 1e-12 else proxy
        n = unit(add(mul(proxy, HAIR_PROXY_WEIGHT), mul(smooth, 1.0 - HAIR_PROXY_WEIGHT)))
        for v in mesh.groups[w]:
            mesh.nor[v] = n
            changed += 1
    print("hair: %d welded vertices (%d raw) take capsule normals, centre y %.3f radius %.3f, %.0f/%.0f blend"
          % (len(hair_groups), changed, cy, radius, HAIR_PROXY_WEIGHT * 100, (1 - HAIR_PROXY_WEIGHT) * 100))
    return changed


# ---------------------------------------------------------------------------
# 5. atlas padding
# ---------------------------------------------------------------------------

def pad_atlas(mesh, W, H, C, tex):
    idx = [v for t in mesh.tris for v in t]
    claims, _ = claim_map(mesh.pos, mesh.uv, idx, W, H)
    filled = bytearray(1 if claims[i] else 0 for i in range(W * H))
    unowned = W * H - sum(filled)
    black = sum(1 for i in range(W * H) if not filled[i]
                and tex[i * C] < 20 and tex[i * C + 1] < 20 and tex[i * C + 2] < 20)
    total = 0
    for _ in range(96):
        frontier = []
        for i in range(W * H):
            if filled[i]:
                continue
            x, y = i % W, i // W
            acc = [0, 0, 0]; n = 0
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and filled[ny * W + nx]:
                    o = (ny * W + nx) * C
                    acc[0] += tex[o]; acc[1] += tex[o + 1]; acc[2] += tex[o + 2]; n += 1
            if n:
                frontier.append((i, (acc[0] // n, acc[1] // n, acc[2] // n)))
        if not frontier:
            break
        for i, col in frontier:
            tex[i * C:i * C + 3] = bytes(col)
            filled[i] = 1
        total += len(frontier)
    print("atlas: %d unowned texels (%d of them black) padded from their islands; %d filled"
          % (unowned, black, total))
    return total


# ---------------------------------------------------------------------------
# 6. write
# ---------------------------------------------------------------------------

def rebuild(js, bin_, mesh, png_bytes):
    acc = js["accessors"]
    attrs = mesh.prim["attributes"]
    payload = {}
    n = len(mesh.pos)
    payload[acc[attrs["POSITION"]]["bufferView"]] = b"".join(struct.pack("<3f", *p) for p in mesh.pos)
    payload[acc[attrs["NORMAL"]]["bufferView"]] = b"".join(struct.pack("<3f", *p) for p in mesh.nor)
    payload[acc[attrs["TEXCOORD_0"]]["bufferView"]] = b"".join(struct.pack("<2f", *p) for p in mesh.uv)
    payload[acc[attrs["JOINTS_0"]]["bufferView"]] = b"".join(struct.pack("<4B", *p) for p in mesh.joints)
    payload[acc[attrs["WEIGHTS_0"]]["bufferView"]] = b"".join(struct.pack("<4f", *p) for p in mesh.weights)
    flat = [v for t in mesh.tris for v in t]
    ia = acc[mesh.prim["indices"]]
    if ia["componentType"] == 5123:
        if n > 65535:
            raise SystemExit("too many vertices for uint16 indices")
        payload[ia["bufferView"]] = b"".join(struct.pack("<H", v) for v in flat)
    else:
        payload[ia["bufferView"]] = b"".join(struct.pack("<I", v) for v in flat)
    payload[js["images"][0]["bufferView"]] = bytes(png_bytes)
    for name in ("POSITION", "NORMAL", "TEXCOORD_0", "JOINTS_0", "WEIGHTS_0"):
        acc[attrs[name]]["count"] = n
    ia["count"] = len(flat)
    pa = acc[attrs["POSITION"]]
    pa["min"] = [min(p[k] for p in mesh.pos) for k in range(3)]
    pa["max"] = [max(p[k] for p in mesh.pos) for k in range(3)]
    for k, bv in enumerate(js["bufferViews"]):
        if k in payload:
            continue
        start = bv.get("byteOffset", 0)
        payload[k] = bytes(bin_[start:start + bv["byteLength"]])
    out = bytearray()
    views = js["bufferViews"]
    for k in sorted(range(len(views)), key=lambda k: views[k].get("byteOffset", 0)):
        while len(out) % 4:
            out.append(0)
        views[k]["byteOffset"] = len(out)
        views[k]["byteLength"] = len(payload[k])
        out += payload[k]
    js["buffers"][0]["byteLength"] = len(out)
    return out


def main():
    in_glb, in_png, out_glb, out_png = sys.argv[1:5]
    js, bin_ = read_glb(in_glb)
    mesh = Mesh(js, bin_)
    W, H, C, tex = png_load(in_png)
    tris0, verts0 = len(mesh.tris), len(mesh.pos)

    drop_tiny_shells(mesh)
    mesh.reweld()
    cap_holes(mesh, W, H, C, tex)
    peel_mouth(mesh)
    n_mouth = smooth_normals(mesh, lambda v: in_mouth(mesh, v))
    print("mouth: %d raw vertices took smooth normals from the peeled surface" % n_mouth)
    soften_lower_face(mesh)
    transfer_hair_normals(mesh, W, H, C, tex)
    pad_atlas(mesh, W, H, C, tex)

    png_save(out_png, W, H, C, tex)
    bin_ = rebuild(js, bin_, mesh, open(out_png, "rb").read())
    write_glb(out_glb, js, bin_)
    print("triangles %d -> %d, vertices %d -> %d; wrote %s and %s"
          % (tris0, len(mesh.tris), verts0, len(mesh.pos), out_glb, out_png))
    if len(mesh.tris) > 4000:
        raise SystemExit("over the 4,000-triangle budget")


if __name__ == "__main__":
    main()
