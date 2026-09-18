#!/usr/bin/env python3
"""Build the runtime Little Buddy GLB from the Meshy source. LOCAL ONLY, no network.

Usage:
    python3 tools/build_runtime_character.py [--dry-run]

Source : game/assets_source/meshy/littleBuddy/babyStanding_rigged_v01.glb
Target : game/assets/characters/littleBuddy/baby/babyLittleBuddy_v01.glb

The source is never modified. Everything here is a local derivation — no Meshy
call, no credit, and nothing invented that was not already in the mesh.

WHAT IT FIXES, and why each one is a defect rather than a preference
-------------------------------------------------------------------
1. CROSS-LEG SKIN WEIGHTS. Auto-rig blended weights across the 0.042 gap between
   the legs, peaking at 0.487 opposite-leg influence at knee height. Moving one
   leg dragged the other knee halfway with it — "knee webbing" in a walk cycle.
   Fix: below the hip, a vertex clearly on one side of the midline may not be
   driven by the other leg's bones at all. A deadband around the midline is left
   untouched, because the crotch legitimately blends both legs.

2. SHOULDER INFLUENCE IN THE HEAD. Both shoulder bones reached vertices high in
   the head (up to 0.291), so arm swing squashed the sides of the head. Fix:
   above the measured head base, shoulder bones are removed entirely.

3. MATERIAL. The rigging step re-baked the material into something unshippable:
   a full-brightness emissive (`emissiveFactor [1,1,1]`) pointing at the base
   colour texture, which renders the baby as a glowing cut-out, plus
   `KHR_materials_specular` at 2.0 (non-physical) and `doubleSided`. All are
   removed here so the GLB on disk is correct rather than relying on every
   consumer to override it.

4. TEXTURE SIZE. One 2048² base colour becomes 1024². (The rig output has only
   this one image — the 4096² metallic-roughness map from the remesh was already
   dropped by the rigging step, which is why the runtime needs no ORM handling.)

Weights are renormalised to sum 1.0 and never gain influences, so the 4-influence
limit holds by construction.

5. SPLIT VERTEX NORMALS. The rig splits normals at UV seams (2,046 welded
   positions disagreeing by up to 164 degrees), which shows as hard facets once
   the emissive above is removed and the model is actually lit. Recomputed
   area-weighted across welded positions.

NOT DONE HERE: no normal map is baked. That needs Blender, which is not
installed. Smooth vertex normals are the documented fallback, and art bible 7
bans normal maps on characters anyway. See docs/RUNTIME_CHARACTER_BUILD.md.
"""
import json
import math
import os
import struct
import subprocess
import sys
import tempfile

SRC = "game/assets_source/meshy/littleBuddy/babyStanding_rigged_v01.glb"
DST = "game/assets/characters/littleBuddy/baby/babyLittleBuddy_v01.glb"

LEFT_LEG = {"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase"}
RIGHT_LEG = {"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"}
SHOULDERS = {"LeftShoulder", "RightShoulder"}

# Midline deadband, in model units on a 1.7-unit-tall rig. Vertices within this
# of x=0 keep both legs: that is the crotch, where blending is correct.
MIDLINE_DEADBAND = 0.015
# Base of the head, measured from the silhouette (narrowest band 48-52% of
# height). Above this, shoulders have no business influencing anything.
HEAD_BASE_Y = 0.95
TARGET_TEXTURE = 1024


def load_glb(path):
    data = open(path, "rb").read()
    if struct.unpack_from("<I", data, 0)[0] != 0x46546C67:
        raise SystemExit(f"{path}: not a GLB")
    gltf = binc = None
    off = 12
    while off + 8 <= len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        body = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            gltf = json.loads(body.decode())
        elif ctype == 0x004E4942:
            binc = bytearray(body)
        off += 8 + clen
        off += (4 - (off % 4)) % 4
    return gltf, binc


def write_glb(path, gltf, binc):
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    bn = bytes(binc)
    bn += b"\x00" * ((4 - len(bn) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(bn)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(bn), 0x004E4942))
        f.write(bn)


def node_world_y(gltf):
    """World-space Y of every node, by walking the hierarchy from the roots."""
    nodes = gltf["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    out = {}

    def acc(i):
        if i in out:
            return out[i]
        t = nodes[i].get("translation", [0, 0, 0])
        p = parent.get(i)
        # translation-only accumulation is enough: these joints carry no scale
        # and we only need an approximate height to place the head cut.
        out[i] = (acc(p) if p is not None else 0.0) + t[1]
        return out[i]
    for i in range(len(nodes)):
        acc(i)
    return out


def main():
    dry = "--dry-run" in sys.argv
    if not os.path.exists(SRC):
        raise SystemExit(f"source missing: {SRC}")
    gltf, binc = load_glb(SRC)

    prim = gltf["meshes"][0]["primitives"][0]
    attrs = prim["attributes"]
    skin = gltf["skins"][0]
    joints = skin["joints"]
    jname = [gltf["nodes"][j].get("name", f"n{j}") for j in joints]

    def view(acc_i):
        a = gltf["accessors"][acc_i]
        bv = gltf["bufferViews"][a["bufferView"]]
        return a, bv, bv.get("byteOffset", 0) + a.get("byteOffset", 0)

    pa, _, poff = view(attrs["POSITION"])
    ja, _, joff = view(attrs["JOINTS_0"])
    wa, _, woff = view(attrs["WEIGHTS_0"])
    n = pa["count"]
    assert ja["componentType"] == 5121, "expected ubyte joints"
    assert wa["componentType"] == 5126, "expected float weights"

    li = {k for k, nm in enumerate(jname) if nm in LEFT_LEG}
    ri = {k for k, nm in enumerate(jname) if nm in RIGHT_LEG}
    si = {k for k, nm in enumerate(jname) if nm in SHOULDERS}

    stats = {"legFixed": 0, "shoulderFixed": 0, "legWeightRemoved": 0.0,
             "shoulderWeightRemoved": 0.0, "skippedWouldZero": 0, "maxInfluences": 0}

    for v in range(n):
        x, y, _z = struct.unpack_from("<fff", binc, poff + v * 12)
        js = list(struct.unpack_from("<4B", binc, joff + v * 4))
        wsv = list(struct.unpack_from("<4f", binc, woff + v * 16))

        drop = set()
        if y < 0.471 and abs(x) > MIDLINE_DEADBAND:   # below the hip, off-midline
            drop |= (ri if x > 0 else li)             # left side (+x) drops right leg
        if y > HEAD_BASE_Y:
            drop |= si

        if not drop:
            stats["maxInfluences"] = max(stats["maxInfluences"],
                                         sum(1 for w in wsv if w > 0))
            continue

        removed_leg = sum(w for j, w in zip(js, wsv) if j in drop and j in (li | ri))
        removed_sh = sum(w for j, w in zip(js, wsv) if j in drop and j in si)
        new = [0.0 if j in drop else w for j, w in zip(js, wsv)]
        total = sum(new)
        if total <= 1e-6:
            stats["skippedWouldZero"] += 1
            continue
        new = [w / total for w in new]
        if removed_leg > 1e-6:
            stats["legFixed"] += 1
            stats["legWeightRemoved"] = max(stats["legWeightRemoved"], removed_leg)
        if removed_sh > 1e-6:
            stats["shoulderFixed"] += 1
            stats["shoulderWeightRemoved"] = max(stats["shoulderWeightRemoved"], removed_sh)
        stats["maxInfluences"] = max(stats["maxInfluences"], sum(1 for w in new if w > 0))
        struct.pack_into("<4f", binc, woff + v * 16, *new)

    print("weight fix:")
    print(f"  vertices with cross-leg weight removed : {stats['legFixed']}")
    print(f"    largest single removal              : {stats['legWeightRemoved']:.3f}")
    print(f"  vertices with shoulder-in-head removed : {stats['shoulderFixed']}")
    print(f"    largest single removal              : {stats['shoulderWeightRemoved']:.3f}")
    print(f"  skipped (would zero the vertex)        : {stats['skippedWouldZero']}")
    print(f"  max influences per vertex after fix    : {stats['maxInfluences']}")

    # ---- smooth normals -------------------------------------------------
    # The rig export splits vertex normals at UV seams, so shading breaks into
    # visible facets wherever a seam runs. That was hidden in the source file by
    # a full-brightness emissive; once the emissive is removed (below) and the
    # model is actually lit, every seam shows.
    #
    # It matters more here than it would on a dense mesh: at 14k triangles with
    # no normal map, vertex normals are the ONLY thing carrying surface
    # curvature. Recomputing them area-weighted across WELDED positions — not
    # across vertex indices, which is what leaves the seams — is the closest
    # local equivalent to the detail the missing normal map would have supplied.
    ia, ibv, ioff_i = view(prim["indices"])
    icomp = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4)}[ia["componentType"]]
    idx = [struct.unpack_from("<" + icomp[0], binc, ioff_i + k * icomp[1])[0]
           for k in range(ia["count"])]
    na, _, noff = view(attrs["NORMAL"])

    pos = [struct.unpack_from("<fff", binc, poff + v * 12) for v in range(n)]
    weld = {}
    key_of = []
    for p in pos:
        k = (round(p[0], 6), round(p[1], 6), round(p[2], 6))
        if k not in weld:
            weld[k] = len(weld)
        key_of.append(weld[k])

    accum = [[0.0, 0.0, 0.0] for _ in range(len(weld))]
    for t in range(0, len(idx) - 2, 3):
        a_, b_, c_ = idx[t], idx[t + 1], idx[t + 2]
        pa, pb, pc = pos[a_], pos[b_], pos[c_]
        ux, uy, uz = pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2]
        vx, vy, vz = pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2]
        # un-normalised cross product == area-weighted face normal
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        for w_ in (a_, b_, c_):
            g_ = key_of[w_]
            accum[g_][0] += nx
            accum[g_][1] += ny
            accum[g_][2] += nz

    changed = 0
    for v in range(n):
        gx, gy, gz = accum[key_of[v]]
        ln = math.sqrt(gx * gx + gy * gy + gz * gz)
        if ln < 1e-12:
            continue
        nv = (gx / ln, gy / ln, gz / ln)
        old = struct.unpack_from("<fff", binc, noff + v * 12)
        if sum(old[i] * nv[i] for i in range(3)) < 0.999:
            changed += 1
        struct.pack_into("<fff", binc, noff + v * 12, *nv)
    print(f"\nnormals: recomputed smooth across {len(weld):,} welded positions"
          f"  ({changed:,} of {n:,} vertices changed)")

    # ---- material -------------------------------------------------------
    mat = gltf["materials"][0]
    before = json.dumps(mat, sort_keys=True)
    mat.pop("emissiveTexture", None)
    mat.pop("emissiveFactor", None)
    mat.pop("extensions", None)
    mat["doubleSided"] = False
    pbr = mat.setdefault("pbrMetallicRoughness", {})
    pbr["metallicFactor"] = 0.0      # art bible §7: "there is no metal"
    pbr["roughnessFactor"] = 0.9     # §7 band 0.85-1.0
    gltf.pop("extensionsUsed", None)
    gltf.pop("extensionsRequired", None)
    print("\nmaterial:")
    print("  removed emissive (was full-brightness white), specular/ior extensions")
    print("  doubleSided -> false, metallic 0.0, roughness 0.9")
    print(f"  changed: {before != json.dumps(mat, sort_keys=True)}")

    # drop the now-unreferenced duplicate texture entry
    used = set()

    def collect(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k.endswith("Texture") and isinstance(v, dict) and "index" in v:
                    used.add(v["index"])
                collect(v)
        elif isinstance(o, list):
            for v in o:
                collect(v)
    collect(gltf.get("materials", []))
    print(f"  textures still referenced: {sorted(used)} of {len(gltf.get('textures', []))}")

    # ---- texture downsize ----------------------------------------------
    img = gltf["images"][0]
    ibv = gltf["bufferViews"][img["bufferView"]]
    ioff = ibv.get("byteOffset", 0)
    blob = bytes(binc[ioff: ioff + ibv["byteLength"]])
    w, h = struct.unpack_from(">II", blob, 16)
    new_blob = blob
    if max(w, h) > TARGET_TEXTURE and not dry:
        with tempfile.TemporaryDirectory() as td:
            p = os.path.join(td, "t.png")
            open(p, "wb").write(blob)
            subprocess.run(["sips", "-Z", str(TARGET_TEXTURE), p],
                           check=True, capture_output=True)
            new_blob = open(p, "rb").read()
        nw, nh = struct.unpack_from(">II", new_blob, 16)
        print(f"\ntexture: {w}x{h} ({len(blob):,} B) -> {nw}x{nh} ({len(new_blob):,} B)"
              f"  saved {100*(1-len(new_blob)/len(blob)):.0f}%")
    else:
        print(f"\ntexture: {w}x{h} left as is")

    # ---- rebuild the binary chunk with new offsets ----------------------
    # Every bufferView is copied in its original order; only the image view
    # changes length, so accessor byteOffsets (which are relative to their view)
    # stay valid.
    views = gltf["bufferViews"]
    order = sorted(range(len(views)), key=lambda i: views[i].get("byteOffset", 0))
    out = bytearray()
    for i in order:
        bv = views[i]
        off = bv.get("byteOffset", 0)
        data = new_blob if i == img["bufferView"] else bytes(binc[off: off + bv["byteLength"]])
        while len(out) % 4:
            out.append(0)
        bv["byteOffset"] = len(out)
        bv["byteLength"] = len(data)
        out += data
    gltf["buffers"][0]["byteLength"] = len(out)

    if dry:
        print("\n--dry-run: nothing written")
        return
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    write_glb(DST, gltf, out)
    print(f"\nwrote {DST}  ({os.path.getsize(DST):,} bytes, "
          f"source was {os.path.getsize(SRC):,})")


if __name__ == "__main__":
    main()
