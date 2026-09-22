#!/usr/bin/env python3
"""Minimal Godot 4 .pck reader (stdlib only).

Godot 4 PCK layout (godot/core/io/file_access_pack.cpp):
    magic        u32   0x43504447 ("GDPC")
    pack_version u32   (format version; 2 for Godot 4.0-4.2, 3 for 4.3+)
    ver_major    u32
    ver_minor    u32
    ver_patch    u32
    -- pack_version >= 2 --
    pack_flags   u32   bit0 = encrypted directory, bit1 = rel filebase
    file_base    u64
    reserved     u32 * 16
    file_count   u32
    -- per file --
    path_len     u32   (NUL-padded to a 4-byte multiple)
    path         bytes
    offset       u64
    size         u64
    md5          16 bytes
    flags        u32   (pack_version >= 2 only; bit0 = encrypted file)

Usage:
    python3 pck_read.py PCK --list [--filter SUBSTR]
    python3 pck_read.py PCK --extract SUBSTR --out DIR
    python3 pck_read.py PCK --verify           # recompute every entry's MD5
"""

import argparse
import hashlib
import os
import struct
import sys

MAGIC = 0x43504447


def read_pck(path):
    with open(path, "rb") as fh:
        data = fh.read()

    if len(data) < 4:
        raise SystemExit("file too small")

    base = 0
    if struct.unpack_from("<I", data, 0)[0] != MAGIC:
        # Possibly an embedded pack: the magic is also written at the very end
        # preceded by the pack size (self-contained exe layout).
        if len(data) >= 12 and struct.unpack_from("<I", data, len(data) - 4)[0] == MAGIC:
            ds = struct.unpack_from("<q", data, len(data) - 12)[0]
            base = len(data) - ds - 8
            if struct.unpack_from("<I", data, base)[0] != MAGIC:
                raise SystemExit("not a Godot pack (no GDPC magic)")
        else:
            raise SystemExit("not a Godot pack (no GDPC magic)")

    pos = base + 4
    pack_version, vmaj, vmin, vpat = struct.unpack_from("<IIII", data, pos)
    pos += 16

    pack_flags = 0
    file_base = 0
    dir_offset = None
    if pack_version >= 2:
        pack_flags, file_base = struct.unpack_from("<IQ", data, pos)
        pos += 12

    if pack_version >= 4:
        # Godot 4.7 (pack format 4) moved the file directory to the end of the
        # pack and stores its absolute offset here; file_count is the first
        # u32 AT that offset, not in the fixed header.
        (dir_offset,) = struct.unpack_from("<Q", data, pos)
        pos += 8
        pos += 14 * 4  # remaining reserved words
        pos = base + dir_offset
    else:
        pos += 16 * 4  # reserved

    (file_count,) = struct.unpack_from("<I", data, pos)
    pos += 4

    header = {
        "packVersion": pack_version,
        "godotVersion": "%d.%d.%d" % (vmaj, vmin, vpat),
        "packFlags": pack_flags,
        "encryptedDirectory": bool(pack_flags & 1),
        "fileBase": file_base,
        "directoryOffset": dir_offset,
        "fileCount": file_count,
        "packBytes": len(data),
    }

    if header["encryptedDirectory"]:
        raise SystemExit("pack directory is encrypted; cannot list without the key")

    entries = []
    for _ in range(file_count):
        (plen,) = struct.unpack_from("<I", data, pos)
        pos += 4
        raw = data[pos:pos + plen]
        pos += plen
        p = raw.split(b"\x00", 1)[0].decode("utf-8", "replace")
        offset, size = struct.unpack_from("<QQ", data, pos)
        pos += 16
        md5 = data[pos:pos + 16]
        pos += 16
        flags = 0
        if pack_version >= 2:
            (flags,) = struct.unpack_from("<I", data, pos)
            pos += 4
        entries.append({
            "path": p,
            "offset": offset + file_base,
            "size": size,
            "md5": md5.hex(),
            "flags": flags,
            "encrypted": bool(flags & 1),
        })
    return header, entries, data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pck")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--filter", default="")
    ap.add_argument("--extract", default=None)
    ap.add_argument("--out", default=".")
    ap.add_argument("--verify", action="store_true")
    args = ap.parse_args()

    header, entries, data = read_pck(args.pck)
    print("# %s" % args.pck)
    for k, v in header.items():
        print("#   %s: %s" % (k, v))

    sel = [e for e in entries if args.filter in e["path"]]

    if args.list or (not args.extract and not args.verify):
        total = 0
        for e in sorted(sel, key=lambda x: x["path"]):
            print("%12d  %s%s" % (e["size"], e["path"], "  [ENCRYPTED]" if e["encrypted"] else ""))
            total += e["size"]
        print("# %d entries shown, %d bytes" % (len(sel), total))

    if args.verify:
        bad = 0
        empty_md5 = 0
        for e in entries:
            blob = data[e["offset"]:e["offset"] + e["size"]]
            if len(blob) != e["size"]:
                print("SHORT  %s: wanted %d bytes, pack holds %d" % (e["path"], e["size"], len(blob)))
                bad += 1
                continue
            if e["md5"] == "0" * 32:
                empty_md5 += 1
                continue
            got = hashlib.md5(blob).hexdigest()
            if got != e["md5"]:
                print("BADMD5 %s: stored %s computed %s" % (e["path"], e["md5"], got))
                bad += 1
        print("# verify: %d entries, %d bad, %d with no stored md5" % (len(entries), bad, empty_md5))
        if bad:
            sys.exit(1)

    if args.extract is not None:
        hits = [e for e in entries if args.extract in e["path"]]
        for e in hits:
            rel = e["path"].replace("res://", "").lstrip("/")
            dest = os.path.join(args.out, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as fh:
                fh.write(data[e["offset"]:e["offset"] + e["size"]])
            print("extracted %s -> %s (%d bytes)" % (e["path"], dest, e["size"]))
        print("# %d extracted" % len(hits))


if __name__ == "__main__":
    main()
