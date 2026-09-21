#!/usr/bin/env python3
"""Split a Meshy GLB into named parts by connected components. LOCAL ONLY,
no network, no credits, pure stdlib (this runs on a bare machine).

    python3 tools/meshy_split.py <in.glb> --list
    python3 tools/meshy_split.py <in.glb> --parts apple,banana --out-dir <dir>
            [--assign 3=apple,4=apple] [--drop-inner-shells] [--scale 0.26]
            [--origin bottom|keep] [--json]

Why this exists. Meshy generates ONE mesh per task, and two things the game
needs are not one mesh:

  * a set generated as a group ("a red apple and a yellow banana") is cheaper
    than two tasks, but `ART_BIBLE.md` section 6 says one object teaches one
    word -- so the apple and the banana must be separate props;
  * furniture that OPENS (fridge, wardrobe, toy box) is hinged in
    `room.gd` (`_build_wardrobe_doors`, `_openables`) as a body plus door
    leaves on their own pivot nodes, so a generated fridge is useless until
    its door is a separate mesh.

Both are the same operation: find the connected components of the triangle
graph (welded by position, because Meshy splits vertices at UV seams), group
them into the requested parts, and write each part as its own self-contained
GLB with the SAME base-colour texture and material, compacted to only the
vertices it uses (Godot computes a mesh's AABB from every vertex in the
buffer, so an uncompacted part would report the whole set's bounds).

Grouping: the K largest components seed the K named parts (largest first,
in the order the names are given -- pass `--assign` to override any
component by index). Every other component joins the seed whose bounding
box it overlaps most by volume, or the nearest seed centroid when it
overlaps none. `--drop-inner-shells` removes a component whose bounds sit
entirely inside a larger component's bounds at nearly the same extent, which
is Meshy's occasional inner duplicate surface: invisible, and pure triangle
cost.

`--origin bottom` (default) re-centres each part on its own footprint with
its base on Y = 0 -- section 6's "pivot at base centre", which is what lets
a consumer rest a part on a surface by naming the surface. `--scale`
multiplies positions first, so a part can be written in metres.

A JSON report of every part (triangles, vertices, bounds) is printed with
`--json`; `tools/meshy_batch.sh` reads it for the triangle gate.
"""
import argparse
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from optimize_runtime_glb import load_glb, write_glb  # noqa: E402

COMPONENT_TYPES = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}


def _accessor(gltf, binc, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    fmt, size = COMPONENT_TYPES[acc["componentType"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    stride = view.get("byteStride", size * width)
    out = []
    for i in range(acc["count"]):
        base = offset + i * stride
        out.append(struct.unpack_from("<" + fmt * width, binc, base))
    return out


def _primitives(gltf):
    """Every (mesh index, primitive index, node transform) in the default scene.
    Meshy output is one node/one mesh; this tolerates more, and applies node
    transforms so parts land where the scene shows them."""
    found = []

    def walk(node_index, parent):
        node = gltf["nodes"][node_index]
        local = _node_matrix(node)
        world = _mul(parent, local)
        if "mesh" in node:
            for p, _ in enumerate(gltf["meshes"][node["mesh"]]["primitives"]):
                found.append((node["mesh"], p, world))
        for child in node.get("children", []):
            walk(child, world)

    scene = gltf.get("scenes", [{}])[gltf.get("scene", 0)]
    for root in scene.get("nodes", range(len(gltf.get("nodes", [])))):
        walk(root, _identity())
    return found


def _identity():
    return [[1.0 if r == c else 0.0 for c in range(4)] for r in range(4)]


def _node_matrix(node):
    if "matrix" in node:
        m = node["matrix"]  # column-major
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    t = node.get("translation", [0.0, 0.0, 0.0])
    s = node.get("scale", [1.0, 1.0, 1.0])
    x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    rot = [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]
    m = _identity()
    for r in range(3):
        for c in range(3):
            m[r][c] = rot[r][c] * s[c]
        m[r][3] = t[r]
    return m


def _mul(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def _apply(m, p, w=1.0):
    return tuple(m[r][0] * p[0] + m[r][1] * p[1] + m[r][2] * p[2] + m[r][3] * w for r in range(3))


def _normalize(v):
    length = (v[0] ** 2 + v[1] ** 2 + v[2] ** 2) ** 0.5 or 1.0
    return (v[0] / length, v[1] / length, v[2] / length)


def gather(gltf, binc):
    """One flat triangle soup: positions, normals, uvs, material index per
    triangle. Vertices are re-numbered across primitives."""
    pos, nrm, uv, tris, tri_material = [], [], [], [], []
    for mesh_i, prim_i, world in _primitives(gltf):
        prim = gltf["meshes"][mesh_i]["primitives"][prim_i]
        if prim.get("mode", 4) != 4:
            raise SystemExit("only TRIANGLES primitives are supported")
        attrs = prim["attributes"]
        p = _accessor(gltf, binc, attrs["POSITION"])
        n = _accessor(gltf, binc, attrs["NORMAL"]) if "NORMAL" in attrs else [(0.0, 1.0, 0.0)] * len(p)
        t = _accessor(gltf, binc, attrs["TEXCOORD_0"]) if "TEXCOORD_0" in attrs else [(0.0, 0.0)] * len(p)
        base = len(pos)
        pos.extend(_apply(world, v) for v in p)
        nrm.extend(_normalize(_apply(world, v, 0.0)) for v in n)
        uv.extend(t)
        if "indices" in prim:
            idx = [i[0] for i in _accessor(gltf, binc, prim["indices"])]
        else:
            idx = list(range(len(p)))
        material = prim.get("material", 0)
        for k in range(0, len(idx) - 2, 3):
            tris.append((base + idx[k], base + idx[k + 1], base + idx[k + 2]))
            tri_material.append(material)
    return pos, nrm, uv, tris, tri_material


def components(pos, tris):
    """Connected components over triangles, welded by rounded position."""
    canon, seen = [], {}
    for p in pos:
        key = (round(p[0], 5), round(p[1], 5), round(p[2], 5))
        canon.append(seen.setdefault(key, len(seen)))
    parent = list(range(len(seen)))

    def find(v):
        while parent[v] != v:
            parent[v] = parent[parent[v]]
            v = parent[v]
        return v

    for a, b, c in tris:
        ra, rb, rc = find(canon[a]), find(canon[b]), find(canon[c])
        parent[rb] = ra
        parent[find(rc)] = find(ra)
    groups = {}
    for t, (a, _, _) in enumerate(tris):
        groups.setdefault(find(canon[a]), []).append(t)
    ordered = sorted(groups.values(), key=lambda g: (-len(g), g[0]))
    return [_describe(pos, tris, g) for g in ordered]


def _describe(pos, tris, tri_ids):
    verts = {v for t in tri_ids for v in tris[t]}
    lo = [min(pos[v][i] for v in verts) for i in range(3)]
    hi = [max(pos[v][i] for v in verts) for i in range(3)]
    return {"tris": tri_ids, "lo": lo, "hi": hi,
            "centroid": [(lo[i] + hi[i]) * 0.5 for i in range(3)]}


def overlap_volume(a, b):
    v = 1.0
    for i in range(3):
        v *= max(0.0, min(a["hi"][i], b["hi"][i]) - max(a["lo"][i], b["lo"][i]))
    return v


def is_inner_shell(inner, outer):
    if len(inner["tris"]) >= len(outer["tris"]):
        return False
    for i in range(3):
        extent = outer["hi"][i] - outer["lo"][i]
        slack = extent * 0.02 + 1e-6
        if inner["lo"][i] < outer["lo"][i] - slack or inner["hi"][i] > outer["hi"][i] + slack:
            return False
        if (inner["hi"][i] - inner["lo"][i]) < extent * 0.9:
            return False
    return True


def assign_parts(comps, part_names, overrides):
    """component index -> part name (None = dropped)."""
    assignment = {}
    seeds = {}
    seed_pool = [i for i in range(len(comps)) if i not in overrides]
    for name in part_names:
        # An override may already name this part's seed.
        forced = [i for i, n in overrides.items() if n == name]
        if forced:
            seeds[name] = min(forced, key=lambda i: -len(comps[i]["tris"]))
            continue
        if not seed_pool:
            raise SystemExit(f"not enough components to seed part '{name}'")
        seeds[name] = seed_pool.pop(0)
    for name, i in seeds.items():
        assignment[i] = name
    for i, name in overrides.items():
        assignment[i] = name
    for i, comp in enumerate(comps):
        if i in assignment:
            continue
        best, best_score = None, -1.0
        for name, seed_i in seeds.items():
            score = overlap_volume(comp, comps[seed_i])
            if score > best_score:
                best, best_score = name, score
        if best_score <= 0.0:
            def dist(name):
                c = comps[seeds[name]]["centroid"]
                return sum((c[k] - comp["centroid"][k]) ** 2 for k in range(3))
            best = min(seeds, key=dist)
        assignment[i] = best
    return assignment


def build_part(gltf, binc, name, pos, nrm, uv, tris, tri_ids, material_index, scale, origin):
    used = sorted({v for t in tri_ids for v in tris[t]})
    remap = {v: k for k, v in enumerate(used)}
    p = [[c * scale for c in pos[v]] for v in used]
    lo = [min(q[i] for q in p) for i in range(3)]
    hi = [max(q[i] for q in p) for i in range(3)]
    if origin == "bottom":
        shift = [-(lo[0] + hi[0]) * 0.5, -lo[1], -(lo[2] + hi[2]) * 0.5]
        p = [[q[i] + shift[i] for i in range(3)] for q in p]
        lo = [lo[i] + shift[i] for i in range(3)]
        hi = [hi[i] + shift[i] for i in range(3)]
    n = [nrm[v] for v in used]
    t = [uv[v] for v in used]
    index = [remap[v] for tid in tri_ids for v in tris[tid]]

    # -- binary chunk: image (if embedded) | positions | normals | uvs | indices
    blob = bytearray()
    views = []

    def add_view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
        if target:
            view["target"] = target
        views.append(view)
        blob.extend(data)
        return len(views) - 1

    material = json.loads(json.dumps(gltf.get("materials", [{}])[material_index]))
    out = {
        "asset": {"version": "2.0", "generator": "meshy_split.py (Little Days)",
                  "extras": {"splitFrom": os.path.basename(gltf.get("_source", "")), "part": name}},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
            "indices": 3, "material": 0, "mode": 4}]}],
        "materials": [material],
        "accessors": [], "bufferViews": views, "buffers": [],
    }
    images, textures, samplers = _material_textures(gltf, binc, material, add_view)
    if images:
        out["images"], out["textures"] = images, textures
        if samplers:
            out["samplers"] = samplers
    if not textures:
        pbr = material.setdefault("pbrMetallicRoughness", {})
        pbr.pop("baseColorTexture", None)

    def pack(values, fmt):
        return b"".join(struct.pack("<" + fmt * len(v), *v) for v in values)

    pos_view = add_view(pack(p, "f"), 34962)
    nrm_view = add_view(pack(n, "f"), 34962)
    uv_view = add_view(pack(t, "f"), 34962)
    ifmt, itype = ("H", 5123) if len(used) < 65536 else ("I", 5125)
    idx_view = add_view(b"".join(struct.pack("<" + ifmt, i) for i in index), 34963)
    out["accessors"] = [
        {"bufferView": pos_view, "componentType": 5126, "count": len(p), "type": "VEC3",
         "min": [float(x) for x in lo], "max": [float(x) for x in hi]},
        {"bufferView": nrm_view, "componentType": 5126, "count": len(n), "type": "VEC3"},
        {"bufferView": uv_view, "componentType": 5126, "count": len(t), "type": "VEC2"},
        {"bufferView": idx_view, "componentType": itype, "count": len(index), "type": "SCALAR"},
    ]
    out["buffers"] = [{"byteLength": len(blob)}]
    report = {"part": name, "triangles": len(index) // 3, "vertices": len(p),
              "min": lo, "max": hi, "components": len(set(tri_ids)) and None}
    return out, blob, report


def _material_textures(gltf, binc, material, add_view):
    """Copies only the base-colour texture (section 7: one atlas, no other
    maps) and rewrites the material's texture indices to 0."""
    pbr = material.get("pbrMetallicRoughness", {})
    info = pbr.get("baseColorTexture")
    for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
        material.pop(key, None)
    pbr.pop("metallicRoughnessTexture", None)
    if info is None:
        return [], [], []
    texture = gltf["textures"][info["index"]]
    image = dict(gltf["images"][texture["source"]])
    if "bufferView" in image:
        view = gltf["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        data = bytes(binc[start:start + view["byteLength"]])
        image = {"mimeType": image.get("mimeType", "image/jpeg"), "bufferView": add_view(data)}
    info["index"] = 0
    out_texture = {"source": 0}
    samplers = []
    if "sampler" in texture and gltf.get("samplers"):
        samplers = [gltf["samplers"][texture["sampler"]]]
        out_texture["sampler"] = 0
    return [image], [out_texture], samplers


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("glb")
    ap.add_argument("--list", action="store_true", help="print components and exit")
    ap.add_argument("--parts", default="", help="comma-separated part names, largest component first")
    ap.add_argument("--assign", default="", help="component overrides: 3=apple,4=apple")
    ap.add_argument("--drop-inner-shells", action="store_true")
    ap.add_argument("--scale", type=float, default=1.0, help="multiply positions (units -> metres)")
    ap.add_argument("--origin", choices=["bottom", "keep"], default="bottom")
    ap.add_argument("--out-dir", default="")
    ap.add_argument("--json", action="store_true", help="print a JSON report of the written parts")
    ap.add_argument("--force", action="store_true", help="overwrite existing part files")
    args = ap.parse_args()

    gltf, binc = load_glb(args.glb)
    gltf["_source"] = args.glb
    pos, nrm, uv, tris, tri_material = gather(gltf, binc)
    comps = components(pos, tris)

    def show(i, comp, tag=""):
        print("  [%2d] tris=%5d  X %+.3f..%+.3f  Y %+.3f..%+.3f  Z %+.3f..%+.3f %s" % (
            i, len(comp["tris"]), comp["lo"][0], comp["hi"][0], comp["lo"][1], comp["hi"][1],
            comp["lo"][2], comp["hi"][2], tag), file=sys.stderr)

    print(f"{args.glb}: {len(tris)} triangles, {len(comps)} connected component(s)", file=sys.stderr)
    if args.list or not args.parts:
        for i, comp in enumerate(comps):
            show(i, comp)
        if not args.parts:
            return
    part_names = [n.strip() for n in args.parts.split(",") if n.strip()]
    overrides = {}
    for item in filter(None, args.assign.split(",")):
        index, name = item.split("=")
        overrides[int(index)] = name.strip()
        if name.strip() not in part_names:
            raise SystemExit(f"--assign names unknown part '{name}'")
    assignment = assign_parts(comps, part_names, overrides)

    dropped = set()
    if args.drop_inner_shells:
        for i, comp in enumerate(comps):
            for j, other in enumerate(comps):
                if i != j and assignment[i] == assignment[j] and is_inner_shell(comp, other):
                    dropped.add(i)
                    break
    for i, comp in enumerate(comps):
        tag = "-> DROPPED (inner shell)" if i in dropped else f"-> {assignment[i]}"
        show(i, comp, tag)

    if not args.out_dir:
        raise SystemExit("--out-dir is required to write parts")
    os.makedirs(args.out_dir, exist_ok=True)
    reports = []
    for name in part_names:
        tri_ids = [t for i, comp in enumerate(comps) if assignment[i] == name and i not in dropped
                   for t in comp["tris"]]
        if not tri_ids:
            raise SystemExit(f"part '{name}' received no triangles")
        materials = {tri_material[t] for t in tri_ids}
        if len(materials) != 1:
            raise SystemExit(f"part '{name}' spans {len(materials)} materials; one texture per part is the rule")
        out_path = os.path.join(args.out_dir, f"{name}.glb")
        if os.path.exists(out_path) and not args.force:
            raise SystemExit(f"refusing to overwrite {out_path} (pass --force)")
        doc, blob, report = build_part(gltf, binc, name, pos, nrm, uv, tris, tri_ids,
                                       materials.pop(), args.scale, args.origin)
        write_glb(out_path, doc, blob)
        report["file"] = out_path
        report["bytes"] = os.path.getsize(out_path)
        report.pop("components", None)
        reports.append(report)
        print("  wrote %s: %d tris, %d verts, %.3f x %.3f x %.3f" % (
            out_path, report["triangles"], report["vertices"],
            report["max"][0] - report["min"][0], report["max"][1] - report["min"][1],
            report["max"][2] - report["min"][2]), file=sys.stderr)
    if args.json:
        print(json.dumps({"source": args.glb, "parts": reports}, indent=2))


if __name__ == "__main__":
    main()
