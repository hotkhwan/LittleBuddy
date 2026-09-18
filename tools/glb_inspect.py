#!/usr/bin/env python3
"""Inspect a .glb: geometry, materials, textures, bounds. Local only, no network.

Usage: python3 tools/glb_inspect.py <file.glb> [more.glb ...]

Pure stdlib on purpose — this runs on a bare machine with no pip install, and it
is used to sign off Meshy output before a paid Rigging step, so it must not be
able to fail for environment reasons.
"""
import json
import struct
import sys
import os

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942

# glTF primitive modes
MODES = {0: "POINTS", 1: "LINES", 2: "LINE_LOOP", 3: "LINE_STRIP",
         4: "TRIANGLES", 5: "TRIANGLE_STRIP", 6: "TRIANGLE_FAN"}


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise SystemExit(f"{path}: not a GLB (bad magic)")
    gltf, binchunk = None, None
    off = 12
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        body = data[off + 8: off + 8 + clen]
        if ctype == CHUNK_JSON:
            gltf = json.loads(body.decode("utf-8"))
        elif ctype == CHUNK_BIN:
            binchunk = body
        off += 8 + clen + ((4 - clen % 4) % 4) if clen % 4 else off + 8 + clen
        # recompute robustly
        off = off if clen % 4 else off
    return gltf, binchunk, data, version


def read_glb_simple(path):
    """Chunk walk without the padding subtlety above."""
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise SystemExit(f"{path}: not a GLB (bad magic)")
    gltf, binchunk = None, None
    off = 12
    while off + 8 <= len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        body = data[off + 8: off + 8 + clen]
        if ctype == CHUNK_JSON:
            gltf = json.loads(body.decode("utf-8"))
        elif ctype == CHUNK_BIN:
            binchunk = body
        off += 8 + clen
        off += (4 - (off % 4)) % 4
    return gltf, binchunk, data, version


def image_size(blob):
    """(w, h, kind) for PNG / JPEG bytes, without Pillow."""
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack_from(">II", blob, 16)
        return w, h, "PNG"
    if blob[:2] == b"\xff\xd8":
        i = 2
        while i < len(blob) - 9:
            if blob[i] != 0xFF:
                i += 1
                continue
            marker = blob[i + 1]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                          0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h, w = struct.unpack_from(">HH", blob, i + 5)
                return w, h, "JPEG"
            seglen = struct.unpack_from(">H", blob, i + 2)[0]
            i += 2 + seglen
    return None, None, "?"


def inspect(path):
    gltf, binchunk, raw, version = read_glb_simple(path)
    size = os.path.getsize(path)
    print("=" * 74)
    print(f"{os.path.basename(path)}")
    print("=" * 74)
    print(f"  file size      : {size:,} bytes ({size/1_048_576:.2f} MiB)")
    print(f"  glTF binary ver: {version}")
    gen = (gltf.get("asset") or {}).get("generator", "-")
    print(f"  generator      : {gen}")

    accessors = gltf.get("accessors", [])
    meshes = gltf.get("meshes", [])

    total_v = 0
    total_tri = 0
    mode_counts = {}
    print(f"\n  meshes         : {len(meshes)}")
    for mi, m in enumerate(meshes):
        for pi, prim in enumerate(m.get("primitives", [])):
            mode = prim.get("mode", 4)
            mode_counts[MODES.get(mode, mode)] = mode_counts.get(MODES.get(mode, mode), 0) + 1
            pos = prim.get("attributes", {}).get("POSITION")
            nv = accessors[pos]["count"] if pos is not None else 0
            total_v += nv
            idx = prim.get("indices")
            if idx is not None:
                ni = accessors[idx]["count"]
                tri = ni // 3 if mode == 4 else 0
            else:
                tri = nv // 3 if mode == 4 else 0
            total_tri += tri
            attrs = ",".join(sorted(prim.get("attributes", {})))
            print(f"    mesh[{mi}].prim[{pi}] name={m.get('name','-')!r}")
            print(f"      vertices={nv:,}  triangles={tri:,}  mode={MODES.get(mode, mode)}")
            print(f"      attributes={attrs}")
            print(f"      material={prim.get('material')}")

    print(f"\n  TOTAL vertices : {total_v:,}")
    print(f"  TOTAL triangles: {total_tri:,}")
    print(f"  quads (if fully quad-derived): ~{total_tri//2:,}")
    print(f"  primitive modes: {mode_counts}")

    # skinning / rig
    print(f"\n  skins          : {len(gltf.get('skins', []))}")
    print(f"  animations     : {len(gltf.get('animations', []))}")
    has_joints = any("JOINTS_0" in p.get("attributes", {})
                     for m in meshes for p in m.get("primitives", []))
    print(f"  JOINTS_0 present: {has_joints}   (False = unrigged, as expected pre-Rigging)")

    # materials
    mats = gltf.get("materials", [])
    print(f"\n  materials      : {len(mats)}")
    for i, mt in enumerate(mats):
        pbr = mt.get("pbrMetallicRoughness", {})
        tex_refs = [k for k in ("baseColorTexture", "metallicRoughnessTexture") if k in pbr]
        for k in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            if k in mt:
                tex_refs.append(k)
        print(f"    [{i}] name={mt.get('name','-')!r} alphaMode={mt.get('alphaMode','OPAQUE')} "
              f"doubleSided={mt.get('doubleSided', False)}")
        print(f"        metallic={pbr.get('metallicFactor')} roughness={pbr.get('roughnessFactor')}")
        print(f"        textures={tex_refs or 'none'}")

    # textures
    images = gltf.get("images", [])
    bviews = gltf.get("bufferViews", [])
    print(f"\n  images         : {len(images)}")
    for i, im in enumerate(images):
        if "bufferView" in im and binchunk is not None:
            bv = bviews[im["bufferView"]]
            off = bv.get("byteOffset", 0)
            blob = binchunk[off: off + bv["byteLength"]]
            w, h, kind = image_size(blob)
            print(f"    [{i}] {kind} {w}x{h}  ({bv['byteLength']:,} bytes)  mime={im.get('mimeType','-')}")
        else:
            print(f"    [{i}] uri={im.get('uri','-')[:60]} (external)")

    # bounds, from POSITION accessor min/max
    mins = [float("inf")] * 3
    maxs = [float("-inf")] * 3
    for m in meshes:
        for prim in m.get("primitives", []):
            pos = prim.get("attributes", {}).get("POSITION")
            if pos is None:
                continue
            a = accessors[pos]
            if "min" in a and "max" in a:
                for k in range(3):
                    mins[k] = min(mins[k], a["min"][k])
                    maxs[k] = max(maxs[k], a["max"][k])
    if all(v != float("inf") for v in mins):
        dims = [maxs[k] - mins[k] for k in range(3)]
        axis = "XYZ"
        print("\n  bounding box (glTF is Y-up, -Z forward by convention):")
        for k in range(3):
            print(f"    {axis[k]}: {mins[k]:+8.4f} .. {maxs[k]:+8.4f}   extent={dims[k]:.4f}")
        up = max(range(3), key=lambda k: dims[k])
        print(f"    tallest axis = {axis[up]} (extent {dims[up]:.4f})")
        print(f"    footprint    = X {dims[0]:.4f} x Z {dims[2]:.4f}")
        cx = (mins[0] + maxs[0]) / 2
        cz = (mins[2] + maxs[2]) / 2
        print(f"    centred on X={cx:+.4f}  Z={cz:+.4f}   base Y={mins[1]:+.4f}")
    print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for p in sys.argv[1:]:
        inspect(p)
