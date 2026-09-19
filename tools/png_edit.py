#!/usr/bin/env python3
"""Minimal dependency-free PNG read/write, so character textures can be edited
locally without Pillow (and without spending a single Meshy credit on a fix that
is two dozen pixels wide).

Only what this repo needs: 8-bit RGB/RGBA, non-interlaced. Anything else raises
rather than guessing, because a silently mis-decoded texture is far worse than a
crash during a build step.

    from png_edit import load, save, crop, scale
"""

import struct
import sys
import zlib


def load(path):
    """-> (width, height, channels, bytearray of raw pixels)."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s is not a PNG" % path)
    pos = 8
    idat = bytearray()
    width = height = depth = color = None
    while pos < len(data):
        (length,) = struct.unpack_from(">I", data, pos)
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, color, _c, _f, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or color not in (2, 6) or interlace != 0:
                raise ValueError("unsupported PNG: depth=%d color=%d interlace=%d"
                                 % (depth, color, interlace))
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    channels = 3 if color == 2 else 4
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    out = bytearray(stride * height)
    prev = bytearray(stride)
    src = 0
    for y in range(height):
        filt = raw[src]
        src += 1
        line = bytearray(raw[src:src + stride])
        src += stride
        # PNG per-scanline filters, undone in place.
        if filt == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif filt == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif filt == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif filt == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif filt != 0:
            raise ValueError("unknown PNG filter %d" % filt)
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, channels, out


def save(path, width, height, channels, pixels):
    color = 2 if channels == 3 else 6
    stride = width * channels
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none. Bigger, but trivially correct.
        raw += pixels[y * stride:(y + 1) * stride]
    def chunk(kind, body):
        return (struct.pack(">I", len(body)) + kind + body
                + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF))
    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    out += chunk(b"IEND", b"")
    open(path, "wb").write(out)


def crop(width, height, channels, pixels, x0, y0, w, h):
    out = bytearray(w * h * channels)
    for y in range(h):
        s = ((y0 + y) * width + x0) * channels
        d = y * w * channels
        out[d:d + w * channels] = pixels[s:s + w * channels]
    return w, h, channels, out


def scale(width, height, channels, pixels, factor):
    """Nearest-neighbour upscale, for looking at a few dozen pixels."""
    w, h = width * factor, height * factor
    out = bytearray(w * h * channels)
    for y in range(h):
        sy = y // factor
        for x in range(w):
            sx = x // factor
            s = (sy * width + sx) * channels
            d = (y * w + x) * channels
            out[d:d + channels] = pixels[s:s + channels]
    return w, h, channels, out


if __name__ == "__main__":
    # png_edit.py <in> <out> [x0 y0 w h [zoom]]
    src, dst = sys.argv[1], sys.argv[2]
    W, H, C, P = load(src)
    if len(sys.argv) >= 7:
        W, H, C, P = crop(W, H, C, P, *[int(v) for v in sys.argv[3:7]])
    if len(sys.argv) >= 8:
        W, H, C, P = scale(W, H, C, P, int(sys.argv[7]))
    save(dst, W, H, C, P)
    print("%s -> %s  %dx%d c=%d" % (src, dst, W, H, C))
