#!/usr/bin/env python3
"""Standalone Ogg/Vorbis container + codec validator (stdlib only).

Written for the Little Days iOS audio crash audit (res2_inverse /
vorbis_book_decodevv_add crash inside libvorbis on device).

Checks performed per file:
  1. Container: every page's capture pattern, version, header-type flags,
     granule position, serial, monotonic page sequence per serial, segment
     table, and the Ogg CRC32 (poly 0x04c11db7, init 0, no reflection,
     no final xor) recomputed over the whole page with the CRC field zeroed.
  2. Codec: first packet is \\x01vorbis; identification header fields parsed;
     \\x03vorbis comment header and \\x05vorbis setup header present/complete.
  3. Packets: reassembled across page boundaries via the segment table;
     reports packet count, largest packet, and any packet left incomplete
     at EOF.
  4. Granule/duration: last page granule / sample rate.
  5. SHA-256 of the whole file.

Usage: python3 ogg_probe.py FILE [FILE ...] [--json]
"""

import hashlib
import json
import struct
import sys

# ---------------------------------------------------------------------------
# Ogg CRC32: polynomial 0x04c11db7, initial value 0, no input/output
# reflection, no final XOR. (Not the same as zlib's CRC32.)
# ---------------------------------------------------------------------------


def _build_crc_table():
    table = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            if r & 0x80000000:
                r = ((r << 1) ^ 0x04C11DB7) & 0xFFFFFFFF
            else:
                r = (r << 1) & 0xFFFFFFFF
        table.append(r)
    return table


_CRC_TABLE = _build_crc_table()


def ogg_crc32(data: bytes) -> int:
    crc = 0
    for byte in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ _CRC_TABLE[((crc >> 24) & 0xFF) ^ byte]
    return crc


# ---------------------------------------------------------------------------
# Page walking
# ---------------------------------------------------------------------------

CAPTURE = b"OggS"


class Page:
    __slots__ = (
        "offset", "version", "header_type", "granule", "serial", "sequence",
        "crc_stored", "crc_computed", "segments", "seg_table", "body",
        "total_size", "continued", "bos", "eos",
    )


def walk_pages(data: bytes):
    """Yield (Page | None, error_str). Stops at EOF or unrecoverable damage."""
    pos = 0
    n = len(data)
    while pos < n:
        # Resync: find the next capture pattern.
        if data[pos:pos + 4] != CAPTURE:
            nxt = data.find(CAPTURE, pos)
            if nxt < 0:
                yield None, "TRAILING_GARBAGE at 0x%x: %d bytes after last page, no further 'OggS'" % (pos, n - pos)
                return
            yield None, "RESYNC: %d stray bytes at 0x%x before next 'OggS' at 0x%x" % (nxt - pos, pos, nxt)
            pos = nxt
            continue

        if pos + 27 > n:
            yield None, "TRUNCATED_HEADER at 0x%x: only %d bytes left, need 27" % (pos, n - pos)
            return

        hdr = data[pos:pos + 27]
        version = hdr[4]
        header_type = hdr[5]
        granule = struct.unpack_from("<q", hdr, 6)[0]
        serial = struct.unpack_from("<I", hdr, 14)[0]
        sequence = struct.unpack_from("<I", hdr, 18)[0]
        crc_stored = struct.unpack_from("<I", hdr, 22)[0]
        nsegs = hdr[26]

        if pos + 27 + nsegs > n:
            yield None, "TRUNCATED_SEGTABLE at 0x%x: need %d segment bytes" % (pos, nsegs)
            return
        seg_table = data[pos + 27:pos + 27 + nsegs]
        body_len = sum(seg_table)
        body_start = pos + 27 + nsegs
        if body_start + body_len > n:
            yield None, "TRUNCATED_BODY at 0x%x: page declares %d body bytes, only %d available" % (
                pos, body_len, n - body_start)
            return

        total = 27 + nsegs + body_len
        raw = bytearray(data[pos:pos + total])
        raw[22:26] = b"\x00\x00\x00\x00"
        crc_computed = ogg_crc32(bytes(raw))

        p = Page()
        p.offset = pos
        p.version = version
        p.header_type = header_type
        p.granule = granule
        p.serial = serial
        p.sequence = sequence
        p.crc_stored = crc_stored
        p.crc_computed = crc_computed
        p.segments = nsegs
        p.seg_table = seg_table
        p.body = data[body_start:body_start + body_len]
        p.total_size = total
        p.continued = bool(header_type & 0x01)
        p.bos = bool(header_type & 0x02)
        p.eos = bool(header_type & 0x04)
        yield p, None
        pos += total


# ---------------------------------------------------------------------------
# Vorbis headers
# ---------------------------------------------------------------------------


def parse_ident(packet: bytes):
    """Parse \\x01vorbis identification header (30 bytes)."""
    if len(packet) < 30:
        return None, "identification header is %d bytes, need 30" % len(packet)
    ver, ch, rate, br_max, br_nom, br_min = struct.unpack_from("<IBIiii", packet, 7)
    bs = packet[28]
    fb = packet[29]
    info = {
        "vorbisVersion": ver,
        "channels": ch,
        "sampleRate": rate,
        "bitrateMaximum": br_max,
        "bitrateNominal": br_nom,
        "bitrateMinimum": br_min,
        "blocksize0": 1 << (bs & 0x0F),
        "blocksize1": 1 << ((bs >> 4) & 0x0F),
        "framingBit": fb & 1,
    }
    errs = []
    if ver != 0:
        errs.append("vorbis version %d != 0" % ver)
    if ch == 0:
        errs.append("channels == 0")
    if rate == 0:
        errs.append("sampleRate == 0")
    if info["blocksize0"] > info["blocksize1"]:
        errs.append("blocksize0 %d > blocksize1 %d" % (info["blocksize0"], info["blocksize1"]))
    for key in ("blocksize0", "blocksize1"):
        v = info[key]
        if v < 64 or v > 8192:
            errs.append("%s %d out of legal range 64..8192" % (key, v))
    if not info["framingBit"]:
        errs.append("identification framing bit not set")
    return info, ("; ".join(errs) if errs else None)


def parse_comment(packet: bytes):
    if len(packet) < 11:
        return None, "comment header truncated (%d bytes)" % len(packet)
    pos = 7
    (vlen,) = struct.unpack_from("<I", packet, pos)
    pos += 4
    if pos + vlen > len(packet):
        return None, "comment vendor string overruns packet"
    vendor = packet[pos:pos + vlen].decode("utf-8", "replace")
    pos += vlen
    if pos + 4 > len(packet):
        return None, "comment list count missing"
    (count,) = struct.unpack_from("<I", packet, pos)
    pos += 4
    comments = []
    for _ in range(count):
        if pos + 4 > len(packet):
            return None, "comment entry length overruns packet"
        (clen,) = struct.unpack_from("<I", packet, pos)
        pos += 4
        if pos + clen > len(packet):
            return None, "comment entry overruns packet"
        comments.append(packet[pos:pos + clen].decode("utf-8", "replace"))
        pos += clen
    if pos >= len(packet):
        return None, "comment framing bit missing"
    framing = packet[pos] & 1
    info = {"vendor": vendor, "comments": comments, "framingBit": framing}
    return info, (None if framing else "comment framing bit not set")


# ---------------------------------------------------------------------------
# Whole-file probe
# ---------------------------------------------------------------------------


def probe(path: str) -> dict:
    with open(path, "rb") as fh:
        data = fh.read()

    res = {
        "path": path,
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "errors": [],
        "warnings": [],
        "pages": 0,
        "badCrcPages": [],
        "sequenceIssues": [],
        "serials": {},
    }

    pages = []
    for page, err in walk_pages(data):
        if err:
            res["errors"].append(err)
            continue
        pages.append(page)

    res["pages"] = len(pages)
    if not pages:
        res["errors"].append("no Ogg pages found")
        return res

    expected_seq = {}
    last_page_by_serial = {}
    for p in pages:
        if p.version != 0:
            res["errors"].append("page %d at 0x%x: stream_structure_version %d != 0" % (p.sequence, p.offset, p.version))
        if p.crc_stored != p.crc_computed:
            res["badCrcPages"].append({
                "sequence": p.sequence, "offset": p.offset,
                "stored": "0x%08x" % p.crc_stored, "computed": "0x%08x" % p.crc_computed,
            })
        if p.header_type & 0xF8:
            res["warnings"].append("page %d: reserved header-type bits set (0x%02x)" % (p.sequence, p.header_type))
        exp = expected_seq.get(p.serial, 0)
        if p.sequence != exp:
            res["sequenceIssues"].append(
                "serial 0x%08x: page at 0x%x has sequence %d, expected %d" % (p.serial, p.offset, p.sequence, exp))
        expected_seq[p.serial] = p.sequence + 1
        last_page_by_serial[p.serial] = p
        res["serials"].setdefault("0x%08x" % p.serial, 0)
        res["serials"]["0x%08x" % p.serial] += 1

    first = pages[0]
    if not first.bos:
        res["errors"].append("first page does not have the BOS flag set")
    last = pages[-1]
    if not last.eos:
        res["errors"].append("last page (sequence %d, offset 0x%x) does not have the EOS flag set -> file is truncated"
                             % (last.sequence, last.offset))
    # A page whose last segment is 255 continues into the next page.
    if last.seg_table and last.seg_table[-1] == 255:
        res["errors"].append("last page ends with a 255 lacing value: final packet is incomplete at EOF")

    if len(res["serials"]) > 1:
        res["warnings"].append("multiplexed/chained stream: %d serial numbers" % len(res["serials"]))

    # --- Packet reassembly for the first (primary) logical stream ----------
    serial = first.serial
    stream_pages = [p for p in pages if p.serial == serial]
    packets = []
    cur = bytearray()
    open_packet = False
    for p in stream_pages:
        if p.continued and not open_packet and packets:
            res["warnings"].append("page %d flagged 'continued' but no packet was open" % p.sequence)
        # slice body by lacing values
        off = 0
        for lace in p.seg_table:
            cur.extend(p.body[off:off + lace])
            off += lace
            open_packet = True
            if lace < 255:
                packets.append(bytes(cur))
                cur = bytearray()
                open_packet = False
    if open_packet and cur:
        res["errors"].append("packet left incomplete at EOF (%d bytes buffered)" % len(cur))

    res["packetCount"] = len(packets)
    res["largestPacketBytes"] = max((len(x) for x in packets), default=0)
    res["largestPacketIndex"] = max(range(len(packets)), key=lambda i: len(packets[i])) if packets else -1
    res["smallestPacketBytes"] = min((len(x) for x in packets), default=0)
    res["zeroLengthPackets"] = sum(1 for x in packets if len(x) == 0)

    # --- Vorbis headers -----------------------------------------------------
    if len(packets) < 3:
        res["errors"].append("fewer than 3 packets: Vorbis header set incomplete")
        return res

    h1, h2, h3 = packets[0], packets[1], packets[2]
    if not h1.startswith(b"\x01vorbis"):
        res["errors"].append("first packet is not \\x01vorbis (starts %r)" % h1[:8])
    else:
        info, err = parse_ident(h1)
        if info:
            res["ident"] = info
        if err:
            res["errors"].append("identification header: " + err)
    if not h2.startswith(b"\x03vorbis"):
        res["errors"].append("second packet is not \\x03vorbis (starts %r)" % h2[:8])
    else:
        cinfo, cerr = parse_comment(h2)
        if cinfo:
            res["comment"] = {"vendor": cinfo["vendor"], "tagCount": len(cinfo["comments"]),
                              "tags": cinfo["comments"][:20]}
        if cerr:
            res["errors"].append("comment header: " + cerr)
    if not h3.startswith(b"\x05vorbis"):
        res["errors"].append("third packet is not \\x05vorbis (starts %r)" % h3[:8])
    else:
        res["setupHeaderBytes"] = len(h3)
        # The setup header must end with the framing bit set in its last byte.
        if len(h3) < 8:
            res["errors"].append("setup header is only %d bytes" % len(h3))
        elif not (h3[-1] & 0x01):
            res["errors"].append("setup header framing bit not set in final byte (0x%02x) -> setup header truncated"
                                 % h3[-1])

    # --- Granule / duration -------------------------------------------------
    rate = res.get("ident", {}).get("sampleRate", 0)
    final_granule = last_page_by_serial[serial].granule
    res["finalGranule"] = final_granule
    if rate > 0 and final_granule >= 0:
        res["durationSeconds"] = final_granule / float(rate)
    else:
        res["durationSeconds"] = None
        if final_granule < 0:
            res["errors"].append("final granule position is negative (%d)" % final_granule)

    # Granule monotonicity across audio pages (-1 is legal on header pages).
    prev = None
    for p in stream_pages:
        if p.granule == -1:
            continue
        if prev is not None and p.granule < prev:
            res["errors"].append("granule position goes backwards at page %d: %d < %d" % (p.sequence, p.granule, prev))
        prev = p.granule

    res["audioPackets"] = len(packets) - 3
    return res


def main(argv):
    as_json = "--json" in argv
    files = [a for a in argv[1:] if not a.startswith("--")]
    out = []
    rc = 0
    for f in files:
        r = probe(f)
        out.append(r)
        if r["errors"] or r["badCrcPages"] or r["sequenceIssues"]:
            rc = 1
    if as_json:
        print(json.dumps(out, indent=2))
        return rc
    for r in out:
        print("=" * 78)
        print(r["path"])
        print("  bytes            : %d" % r["bytes"])
        print("  sha256           : %s" % r["sha256"])
        ident = r.get("ident", {})
        print("  channels         : %s" % ident.get("channels"))
        print("  sampleRate       : %s" % ident.get("sampleRate"))
        print("  bitrate nom/max/min: %s / %s / %s" % (ident.get("bitrateNominal"),
                                                       ident.get("bitrateMaximum"), ident.get("bitrateMinimum")))
        print("  blocksize 0/1    : %s / %s" % (ident.get("blocksize0"), ident.get("blocksize1")))
        print("  vendor           : %s" % r.get("comment", {}).get("vendor"))
        print("  tags             : %s" % r.get("comment", {}).get("tags"))
        print("  setupHeaderBytes : %s" % r.get("setupHeaderBytes"))
        print("  serials          : %s" % r["serials"])
        print("  pages            : %d" % r["pages"])
        print("  bad CRC pages    : %d %s" % (len(r["badCrcPages"]), r["badCrcPages"][:5]))
        print("  sequence issues  : %d %s" % (len(r["sequenceIssues"]), r["sequenceIssues"][:5]))
        print("  packets          : %s (audio %s)" % (r.get("packetCount"), r.get("audioPackets")))
        print("  largest packet   : %s bytes (index %s)" % (r.get("largestPacketBytes"), r.get("largestPacketIndex")))
        print("  smallest packet  : %s bytes; zero-length: %s" % (r.get("smallestPacketBytes"),
                                                                  r.get("zeroLengthPackets")))
        print("  final granule    : %s" % r.get("finalGranule"))
        print("  duration (s)     : %s" % r.get("durationSeconds"))
        print("  warnings         : %s" % (r["warnings"] or "none"))
        print("  ERRORS           : %s" % (r["errors"] or "none"))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
