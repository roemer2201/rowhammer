#!/usr/bin/env python3
"""Render an asciinema v2 .cast into an animated GIF using pyte (ANSI ->
screen buffer) and Pillow (rasterize). Handles 8/16 named colors, xterm
256 colors (pyte reports them as 6-hex strings), reverse video and bold.
The demo blocks are flat colors, so all frames share one quantized palette
(no dither), which keeps the GIF small and crisp."""
import json
import pyte
from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONTB = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"

DEF_FG = (0xcc, 0xcc, 0xcc)
DEF_BG = (0x1a, 0x1b, 0x26)
NAMED = {
    "black": (0x2e, 0x34, 0x40), "red": (0xdb, 0x4b, 0x4b),
    "green": (0x36, 0xc6, 0x4b), "brown": (0xe0, 0xb0, 0x30),
    "blue": (0x4b, 0x86, 0xff), "magenta": (0xb0, 0x5c, 0xd8),
    "cyan": (0x38, 0xd8, 0xe0), "white": (0xe8, 0xe8, 0xe8),
    "brightblack": (0x60, 0x66, 0x74), "brightred": (0xff, 0x6b, 0x6b),
    "brightgreen": (0x5c, 0xe0, 0x6b), "brightbrown": (0xff, 0xd0, 0x50),
    "brightblue": (0x6b, 0xa0, 0xff), "brightmagenta": (0xd0, 0x7c, 0xff),
    "brightcyan": (0x58, 0xf0, 0xf8), "brightwhite": (0xff, 0xff, 0xff),
}


def _rgb(c, default):
    if c == "default" or c is None:
        return default
    if c in NAMED:
        return NAMED[c]
    try:
        return (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16))
    except Exception:
        return default


def _load(cast):
    with open(cast) as f:
        header = json.loads(f.readline())
        events = [json.loads(l) for l in f if l.strip()]
    return header, events


def _snapshots(header, events, start=0.0, stop_text=None,
               start_text=None, end_text=None):
    cols, rows = header["width"], header["height"]
    screen = pyte.Screen(cols, rows)
    stream = pyte.Stream(screen)
    frames = []
    started = start_text is None

    def grab():
        return tuple(tuple((ch.data or " ", ch.fg, ch.bg, ch.reverse, ch.bold)
                           for ch in (screen.buffer[y][x] for x in range(cols)))
                     for y in range(rows))

    last_t = 0.0
    prev = None
    for t, _, data in events:
        if prev is not None and started and t > last_t:
            d = t - max(last_t, start)
            if d > 0:
                frames.append([prev, d])
        stream.feed(data)
        last_t = t
        grid = grab()
        text = "\n".join("".join(c[0] for c in r) for r in grid)
        if stop_text is not None and stop_text in text:
            break                                  # cut before the stop screen
        if not started and start_text in text:
            started = True                         # first real gameplay frame
        prev = grid
        if end_text is not None and end_text in text:
            break                                  # include and hold this frame
    if prev is not None:
        frames.append([prev, 1.2])
    merged = []
    for grid, d in frames:
        if merged and merged[-1][0] == grid:
            merged[-1][1] += d
        else:
            merged.append([grid, d])
    return merged, cols, rows


def render(cast, out_gif, start=0.0, stop_text=None, start_text=None,
           end_text=None, speed=1.0, max_frame=2.5, hold=1.4,
           cw=9, ch=19, pad=8, crop_cols=54):
    header, events = _load(cast)
    frames, cols, rows = _snapshots(header, events, start=start,
                                    stop_text=stop_text, start_text=start_text,
                                    end_text=end_text)
    frames[-1][1] = hold
    cols = min(cols, crop_cols)                    # trim blank right margin
    font = ImageFont.truetype(FONT, 16)
    fontb = ImageFont.truetype(FONTB, 16)
    Wp, Hp = cols * cw + 2 * pad, rows * ch + 2 * pad
    images, durations = [], []
    for grid, d in frames:
        img = Image.new("RGB", (Wp, Hp), DEF_BG)
        dr = ImageDraw.Draw(img)
        for y in range(rows):
            for x in range(cols):
                data, fg, bg, rev, bold = grid[y][x]
                fgc, bgc = _rgb(fg, DEF_FG), _rgb(bg, DEF_BG)
                if rev:
                    fgc, bgc = bgc, fgc
                px, py = pad + x * cw, pad + y * ch
                if bgc != DEF_BG:
                    dr.rectangle([px, py, px + cw, py + ch], fill=bgc)
                if data != " ":
                    dr.text((px, py), data, font=(fontb if bold else font), fill=fgc)
        images.append(img)
        durations.append(max(0.04, min(d / speed, max_frame)))
    richest = max(images, key=lambda im: len(im.getcolors(1 << 16) or [(0, 0)]))
    pal = richest.quantize(colors=64, method=Image.MEDIANCUT,
                           dither=Image.Dither.NONE)
    qimages = [im.quantize(palette=pal, dither=Image.Dither.NONE) for im in images]
    ms = [int(x * 1000) for x in durations]
    qimages[0].save(out_gif, save_all=True, append_images=qimages[1:],
                    duration=ms, loop=0, optimize=True, disposal=2)
    import os
    print(f"  gif  {os.path.basename(out_gif)}: {len(qimages)} frames, "
          f"{sum(durations):.1f}s, {Wp}x{Hp}, {os.path.getsize(out_gif) // 1024}KB")
