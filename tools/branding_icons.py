#!/usr/bin/env python3
"""Cuts every shipping app icon from the owner-approved design target
`game/assets/uiGenerated/branding/appIconSource.png` (Aliz hugging Bunny in
front of the cottage). Stdlib only -- no Pillow, no network, no Godot.

The source is a 1254x1254 RGB render of a ROUNDED square on pure black. Two
things are wrong with shipping it as-is:

  * iOS masks the corners itself and wants an OPAQUE square. Shipping the
    rounded render gives black corners under the mask;
  * the render's corner radius (~24.6% of the side) is LARGER than the iOS
    icon mask's (~22.4%), so even over a pastel fill a sliver of fill would
    show at each corner.

So the art is cropped 4% into its own rounded shape (a zoom, not a stretch:
the iOS shape then lies entirely inside the art), composited over the brand
cream where the render was black, and resampled with an area filter -- the
one that stays honest at 40 px, where an icon is two faces or nothing.

Outputs (all paths the export presets / project already name, same filenames):

  game/assets/icon/ios/icon_{40,58,76,80,120,152,167,180,1024}.png   RGB
  game/assets/icon/app_icon_512.png                 RGB, for application/config/icon
  game/assets/icon/preview/icon_{60,76,120,180}.png  RGB, .gdignore'd eyeballing set
  game/assets/icons/android/icon_192.png            RGB legacy launcher icon
  game/assets/icons/android/icon_adaptive_foreground_432.png  RGBA, art at 86%
  game/assets/icons/android/icon_adaptive_background_432.png  RGB flat cream
  docs/shots/brand_icons.png                        contact sheet 1024/180/120/76/40 at 1:1

Usage: python3 tools/branding_icons.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import png_edit as png  # noqa: E402

REPO = os.path.dirname(HERE)
SOURCE = os.path.join(REPO, "game/assets/uiGenerated/branding/appIconSource.png")
IOS_DIR = os.path.join(REPO, "game/assets/icon/ios")
PREVIEW_DIR = os.path.join(REPO, "game/assets/icon/preview")
ANDROID_DIR = os.path.join(REPO, "game/assets/icons/android")
PROJECT_ICON = os.path.join(REPO, "game/assets/icon/app_icon_512.png")
CONTACT_SHEET = os.path.join(REPO, "docs/shots/brand_icons.png")

# Palette.CREAM (#FFF6E5), the boot splash colour. Corners of the square icon
# that iOS masks away, and the Android adaptive background.
CREAM = (255, 246, 229)
# Anything darker than this in the source is the black surround, not art.
BLACK_LUMA = 30
# Zoom into the art so the iOS mask never reaches the render's own corners.
ZOOM = 1.04

IOS_SIZES = [40, 58, 76, 80, 120, 152, 167, 180, 1024]
PREVIEW_SIZES = [60, 76, 120, 180]
ADAPTIVE_SIZE = 432
ADAPTIVE_ART_FRACTION = 0.86


def resample_area(w, h, c, px, nw, nh):
    """Separable area-average (box) resample. Exact for downscaling; alpha is
    premultiplied through the filter so a transparent edge never bleeds its
    (meaningless) colour into the neighbours."""
    has_alpha = c == 4

    def weights(src, dst):
        table = []
        scale = src / float(dst)
        for o in range(dst):
            lo, hi = o * scale, (o + 1) * scale
            taps = []
            i = int(lo)
            while i < hi and i < src:
                cover = min(hi, i + 1) - max(lo, i)
                if cover > 1e-9:
                    taps.append((i, cover / scale))
                i += 1
            table.append(taps)
        return table

    wx, wy = weights(w, nw), weights(h, nh)
    # Horizontal pass -> floats, premultiplied.
    mid = [0.0] * (nw * h * c)
    for y in range(h):
        row = y * w * c
        out = y * nw * c
        for ox, taps in enumerate(wx):
            acc = [0.0] * c
            for i, wt in taps:
                s = row + i * c
                if has_alpha:
                    a = px[s + 3] * wt
                    acc[0] += px[s] * a
                    acc[1] += px[s + 1] * a
                    acc[2] += px[s + 2] * a
                    acc[3] += a
                else:
                    for k in range(c):
                        acc[k] += px[s + k] * wt
            d = out + ox * c
            for k in range(c):
                mid[d + k] = acc[k]
    # Vertical pass -> bytes.
    result = bytearray(nw * nh * c)
    for oy, taps in enumerate(wy):
        for x in range(nw):
            acc = [0.0] * c
            for i, wt in taps:
                s = (i * nw + x) * c
                for k in range(c):
                    acc[k] += mid[s + k] * wt
            d = (oy * nw + x) * c
            if has_alpha:
                a = acc[3]
                if a > 1e-6:
                    for k in range(3):
                        result[d + k] = max(0, min(255, int(round(acc[k] / a))))
                result[d + 3] = max(0, min(255, int(round(a))))
            else:
                for k in range(c):
                    result[d + k] = max(0, min(255, int(round(acc[k]))))
    return nw, nh, c, result


def art_bounds(w, h, px):
    """Bounding box of everything that is not the black surround."""
    left = w
    right = 0
    top = h
    bottom = 0
    for y in range(h):
        row = y * w * 3
        first = None
        last = None
        for x in range(w):
            i = row + x * 3
            if px[i] + px[i + 1] + px[i + 2] > BLACK_LUMA:
                if first is None:
                    first = x
                last = x
        if first is not None:
            left = min(left, first)
            right = max(right, last)
            top = min(top, y)
            bottom = max(bottom, y)
    return left, top, right + 1, bottom + 1


def fill_black_with(w, h, px, fill):
    """The render's rounded corners sit on pure black. Every black pixel becomes
    the fill; the one-pixel antialiased rim is pushed to the fill too, because
    a pixel half-blended with black would otherwise stay as a dark outline."""
    out = bytearray(px)
    dark = bytearray(w * h)
    for y in range(h):
        row = y * w
        for x in range(w):
            i = (row + x) * 3
            if px[i] + px[i + 1] + px[i + 2] <= BLACK_LUMA:
                dark[row + x] = 1
    for y in range(h):
        row = y * w
        for x in range(w):
            if dark[row + x]:
                near = True
            else:
                near = False
                for dy in (-1, 0, 1):
                    yy = y + dy
                    if yy < 0 or yy >= h:
                        continue
                    for dx in (-1, 0, 1):
                        xx = x + dx
                        if 0 <= xx < w and dark[yy * w + xx]:
                            near = True
                            break
                    if near:
                        break
            if near:
                i = (row + x) * 3
                out[i], out[i + 1], out[i + 2] = fill
    return out


def square_art(zoom=ZOOM):
    """-> (side, RGB bytes): the art as an opaque square, black replaced by cream."""
    w, h, c, px = png.load(SOURCE)
    if c != 3:
        raise SystemExit("expected an RGB source, got %d channels" % c)
    x0, y0, x1, y1 = art_bounds(w, h, px)
    side = min(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    crop_side = int(round(side / zoom))
    cx0 = int(round(cx - crop_side / 2.0))
    cy0 = int(round(cy - crop_side / 2.0))
    _, _, _, crop = png.crop(w, h, c, px, cx0, cy0, crop_side, crop_side)
    print("  art bounds %s, crop %dpx at (%d,%d), zoom %.2f"
          % ((x0, y0, x1, y1), crop_side, cx0, cy0, zoom))
    return crop_side, fill_black_with(crop_side, crop_side, crop, CREAM)


def to_rgba(w, h, px):
    out = bytearray(w * h * 4)
    for i in range(w * h):
        out[i * 4:i * 4 + 3] = px[i * 3:i * 3 + 3]
        out[i * 4 + 3] = 255
    return out


def paste(dst_w, dst_h, dst_c, dst, src_w, src_h, src_c, src, x0, y0):
    for y in range(src_h):
        dy = y0 + y
        if dy < 0 or dy >= dst_h:
            continue
        for x in range(src_w):
            dx = x0 + x
            if dx < 0 or dx >= dst_w:
                continue
            s = (y * src_w + x) * src_c
            d = (dy * dst_w + dx) * dst_c
            if dst_c == src_c:
                dst[d:d + dst_c] = src[s:s + src_c]
            elif dst_c == 4 and src_c == 3:
                dst[d:d + 3] = src[s:s + 3]
                dst[d + 3] = 255
            else:
                dst[d:d + 3] = src[s:s + 3]


def flat(w, h, rgb):
    return bytearray(bytes(rgb) * (w * h))


def save_png(path, w, h, c, px):
    """`png_edit.save` writes filter-0 scanlines, which is correct and about
    four times too big for a 1024 icon. This picks the PNG filter per scanline
    (the standard minimum-sum-of-absolute-differences heuristic), then deflates
    at level 9. Same pixels, a third of the bytes."""
    import struct
    import zlib
    stride = w * c
    raw = bytearray()
    prev = bytearray(stride)
    for y in range(h):
        line = px[y * stride:(y + 1) * stride]
        best = None
        best_score = None
        for f in (0, 1, 2, 4):
            out = bytearray(stride)
            if f == 0:
                out[:] = line
            elif f == 1:
                for i in range(stride):
                    left = line[i - c] if i >= c else 0
                    out[i] = (line[i] - left) & 0xFF
            elif f == 2:
                for i in range(stride):
                    out[i] = (line[i] - prev[i]) & 0xFF
            else:
                for i in range(stride):
                    a = line[i - c] if i >= c else 0
                    b = prev[i]
                    cc = prev[i - c] if i >= c else 0
                    p = a + b - cc
                    pa, pb, pc = abs(p - a), abs(p - b), abs(p - cc)
                    pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else cc)
                    out[i] = (line[i] - pred) & 0xFF
            score = sum(v if v < 128 else 256 - v for v in out)
            if best_score is None or score < best_score:
                best, best_score = (f, out), score
        raw.append(best[0])
        raw += best[1]
        prev = line

    def chunk(kind, body):
        return (struct.pack(">I", len(body)) + kind + body
                + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF))
    data = b"\x89PNG\r\n\x1a\n"
    data += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2 if c == 3 else 6, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    data += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(data)


def write(path, w, h, c, px):
    save_png(path, w, h, c, px)
    print("  wrote %-70s %4dx%-4d %s  %6.1f KB"
          % (os.path.relpath(path, REPO), w, h, "RGBA" if c == 4 else "RGB ",
             os.path.getsize(path) / 1024.0))


def main():
    print("branding_icons: from %s" % os.path.relpath(SOURCE, REPO))
    side, art = square_art()

    # One high-quality 1024 master; every smaller size is cut from IT so the
    # family is consistent and the cheap sizes cost seconds, not minutes.
    _, _, _, master = resample_area(side, side, 3, art, 1024, 1024)
    cache = {1024: master}

    def at(size):
        if size not in cache:
            cache[size] = resample_area(1024, 1024, 3, master, size, size)[3]
        return cache[size]

    for size in IOS_SIZES:
        write(os.path.join(IOS_DIR, "icon_%d.png" % size), size, size, 3, at(size))
    for size in PREVIEW_SIZES:
        write(os.path.join(PREVIEW_DIR, "icon_%d.png" % size), size, size, 3, at(size))
    write(PROJECT_ICON, 512, 512, 3, at(512))

    # Android: legacy square, then the adaptive pair. The foreground keeps the
    # art at 86% of the canvas: the launcher's mask shows the inner 72%, so the
    # art always covers the mask, and the two faces (56% of the art's width)
    # sit inside the 66-of-108 safe zone with room to spare.
    write(os.path.join(ANDROID_DIR, "icon_192.png"), 192, 192, 3, at(192))
    fg_side = int(round(ADAPTIVE_SIZE * ADAPTIVE_ART_FRACTION))
    fg = bytearray(ADAPTIVE_SIZE * ADAPTIVE_SIZE * 4)
    offset = (ADAPTIVE_SIZE - fg_side) // 2
    paste(ADAPTIVE_SIZE, ADAPTIVE_SIZE, 4, fg, fg_side, fg_side, 3, at(fg_side), offset, offset)
    write(os.path.join(ANDROID_DIR, "icon_adaptive_foreground_432.png"),
          ADAPTIVE_SIZE, ADAPTIVE_SIZE, 4, fg)
    write(os.path.join(ANDROID_DIR, "icon_adaptive_background_432.png"),
          ADAPTIVE_SIZE, ADAPTIVE_SIZE, 3, flat(ADAPTIVE_SIZE, ADAPTIVE_SIZE, CREAM))

    # Contact sheet at 1:1 -- the only honest way to judge a 40 px icon.
    sizes = [1024, 180, 120, 76, 40]
    gap = 24
    sheet_w = sum(sizes) + gap * (len(sizes) + 1)
    sheet_h = 1024 + gap * 2
    sheet = flat(sheet_w, sheet_h, (236, 232, 224))
    x = gap
    for size in sizes:
        paste(sheet_w, sheet_h, 3, sheet, size, size, 3, at(size), x, sheet_h - gap - size)
        x += size + gap
    write(CONTACT_SHEET, sheet_w, sheet_h, 3, sheet)


if __name__ == "__main__":
    main()
