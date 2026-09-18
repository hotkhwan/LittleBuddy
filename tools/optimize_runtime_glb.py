#!/usr/bin/env python3
"""Turn a Meshy export into a runtime-legal GLB. LOCAL ONLY, no network.

Usage:
    python3 tools/optimize_runtime_glb.py <in.glb> <out.glb> [--texture 512]

Applies the art bible to the FILE rather than relying on every consumer to
override the material at load time:

  * smooth vertex normals across WELDED positions -- Meshy splits normals at UV
    seams, which shows as hard facets the moment the model is lit. On a decimated
    mesh with no normal map, vertex normals are the only thing carrying surface
    curvature, so this is the single biggest visual win available locally.
  * metallic 0.0 (section 7 is absolute: "there is no metal") and roughness 0.9.
  * emissive, `KHR_materials_specular` and `KHR_materials_ior` stripped -- Meshy
    bakes a full-brightness white emissive that renders the character as a
    glowing cut-out.
  * `doubleSided` off: it doubles overdraw, and overdraw is what costs on a
    tile-based mobile GPU.
  * every texture except base colour dropped, and base colour resampled down.
    Section 7 allows ONE atlas.

The input is never modified. Skinned models keep their skin, joints and weights
untouched -- this tool does not know about rigs, and `build_runtime_character.py`
is the one that does the weight surgery.
"""
import json
import math
import os
import struct
import subprocess
import sys
import tempfile
from collections import defaultdict


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
    bn = bytes(binc) + b"\x00" * ((4 - len(binc) % 4) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bn)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(bn), 0x004E4942))
        f.write(bn)


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    target_texture = 512
    if "--texture" in sys.argv:
        target_texture = int(sys.argv[sys.argv.index("--texture") + 1])
    if not os.path.exists(src):
        raise SystemExit(f"missing {src}")

    gltf, binc = load_glb(src)
    prim = gltf["meshes"][0]["primitives"][0]
    attrs = prim["attributes"]

    def view(acc_i):
        a = gltf["accessors"][acc_i]
        bv = gltf["bufferViews"][a["bufferView"]]
        return a, bv, bv.get("byteOffset", 0) + a.get("byteOffset", 0)

    pa, _, poff = view(attrs["POSITION"])
    na, _, noff = view(attrs["NORMAL"])
    n = pa["count"]

    # ---- smooth normals across welded positions -------------------------
    ia, _, ioff = view(prim["indices"])
    ifmt, isz = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4)}[ia["componentType"]]
    idx = [struct.unpack_from("<" + ifmt, binc, ioff + k * isz)[0] for k in range(ia["count"])]
    pos = [struct.unpack_from("<fff", binc, poff + v * 12) for v in range(n)]

    weld, key_of = {}, []
    for p in pos:
        k = (round(p[0], 6), round(p[1], 6), round(p[2], 6))
        weld.setdefault(k, len(weld))
        key_of.append(weld[k])

    accum = [[0.0, 0.0, 0.0] for _ in range(len(weld))]
    for t in range(0, len(idx) - 2, 3):
        a_, b_, c_ = idx[t], idx[t + 1], idx[t + 2]
        pa_, pb_, pc_ = pos[a_], pos[b_], pos[c_]
        ux, uy, uz = pb_[0] - pa_[0], pb_[1] - pa_[1], pb_[2] - pa_[2]
        vx, vy, vz = pc_[0] - pa_[0], pc_[1] - pa_[1], pc_[2] - pa_[2]
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        for w_ in (a_, b_, c_):
            g = key_of[w_]
            accum[g][0] += nx
            accum[g][1] += ny
            accum[g][2] += nz

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
    print(f"normals : smoothed across {len(weld):,} welded positions "
          f"({changed:,}/{n:,} vertices changed)")

    # ---- material -------------------------------------------------------
    mat = gltf["materials"][0]
    mat.pop("emissiveTexture", None)
    mat.pop("emissiveFactor", None)
    mat.pop("extensions", None)
    mat.pop("normalTexture", None)
    mat.pop("occlusionTexture", None)
    mat["doubleSided"] = False
    pbr = mat.setdefault("pbrMetallicRoughness", {})
    pbr.pop("metallicRoughnessTexture", None)
    pbr["metallicFactor"] = 0.0
    pbr["roughnessFactor"] = 0.9
    gltf.pop("extensionsUsed", None)
    gltf.pop("extensionsRequired", None)
    base = pbr.get("baseColorTexture", {}).get("index", 0)
    print("material: emissive/specular/ior/normal/ORM stripped, "
          "metallic 0.0, roughness 0.9, single-sided")

    # ---- keep only the base colour image --------------------------------
    keep_image = gltf["textures"][base]["source"]
    gltf["textures"] = [{"sampler": gltf["textures"][base].get("sampler", 0),
                         "source": 0}]
    pbr["baseColorTexture"] = {"index": 0}
    images = [gltf["images"][keep_image]]
    gltf["images"] = images

    ibv = gltf["bufferViews"][images[0]["bufferView"]]
    ioff2 = ibv.get("byteOffset", 0)
    blob = bytes(binc[ioff2: ioff2 + ibv["byteLength"]])
    w, h = struct.unpack_from(">II", blob, 16)
    new_blob = blob
    if max(w, h) > target_texture:
        with tempfile.TemporaryDirectory() as td:
            p = os.path.join(td, "t.png")
            open(p, "wb").write(blob)
            subprocess.run(["sips", "-Z", str(target_texture), p], check=True,
                           capture_output=True)
            new_blob = open(p, "rb").read()
        nw, nh = struct.unpack_from(">II", new_blob, 16)
        print(f"texture : {w}x{h} ({len(blob):,} B) -> {nw}x{nh} ({len(new_blob):,} B)")

    # ---- rebuild the binary chunk ---------------------------------------
    # Only bufferViews still referenced survive; dropping the ORM image is most
    # of the file size saving and it is only real if its bytes go too.
    used = set()

    def mark(i):
        if isinstance(i, int):
            used.add(i)
    for acc in gltf["accessors"]:
        mark(acc.get("bufferView"))
    for im in gltf["images"]:
        mark(im.get("bufferView"))
    for sk in gltf.get("skins", []):
        pass  # inverseBindMatrices is an accessor, already covered

    views = gltf["bufferViews"]
    order = sorted(used, key=lambda i: views[i].get("byteOffset", 0))
    remap, out = {}, bytearray()
    new_views = []
    for i in order:
        bv = views[i]
        off = bv.get("byteOffset", 0)
        data = new_blob if i == images[0]["bufferView"] else bytes(binc[off: off + bv["byteLength"]])
        while len(out) % 4:
            out.append(0)
        nb = dict(bv)
        nb["byteOffset"] = len(out)
        nb["byteLength"] = len(data)
        remap[i] = len(new_views)
        new_views.append(nb)
        out += data
    for acc in gltf["accessors"]:
        if "bufferView" in acc:
            acc["bufferView"] = remap[acc["bufferView"]]
    for im in gltf["images"]:
        im["bufferView"] = remap[im["bufferView"]]
    gltf["bufferViews"] = new_views
    gltf["buffers"][0]["byteLength"] = len(out)

    os.makedirs(os.path.dirname(dst), exist_ok=True)
    write_glb(dst, gltf, out)
    print(f"wrote   : {dst}  ({os.path.getsize(dst):,} bytes, "
          f"source {os.path.getsize(src):,})")


if __name__ == "__main__":
    main()
