#!/usr/bin/env python3
"""Compose the README images from raw kitty screenshots. Used by shots.sh; needs Pillow.

  compose.py monitors OUT  amber.png green.png white.png ice.png color.png
  compose.py compare  OUT  plain.png crt.png
  compose.py crop-box OUT  IN x0 y0 x1 y1  a rectangle of a screenshot, unscaled
"""
import sys

from PIL import Image, ImageDraw, ImageFont

BG = (13, 13, 15)
FG = (222, 222, 222)
DIM = (130, 130, 138)
FONT_CANDIDATES = (
    "/usr/share/fonts/adobe-source-code-pro-fonts/SourceCodePro-Medium.otf",
    "/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf",
    "/usr/share/fonts/liberation-mono/LiberationMono-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
)


def font(size):
    for path in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def load(path, box=None, width=None):
    im = Image.open(path).convert("RGB")
    if box:
        im = im.crop(box)
    if width and im.width != width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    return im


def rounded(im, radius=14):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out


def tile(canvas, im, xy, caption, sub=""):
    x, y = xy
    canvas.paste(rounded(im), (x, y), rounded(im))
    d = ImageDraw.Draw(canvas)
    d.text((x + 4, y + im.height + 10), caption, font=font(22), fill=FG)
    if sub:
        d.text((x + 4, y + im.height + 38), sub, font=font(15), fill=DIM)


def monitors(out, files):
    names = [("amber", "ctrl+alt+1", "amber phosphor terminal"), ("green", "ctrl+alt+2", "P1 green, long afterglow"),
             ("white", "ctrl+alt+3", "paper-white monochrome"), ("ice", "ctrl+alt+4", "cold cyan, heavy bloom"),
             ("color", "ctrl+alt+5", "aperture grille, convergence error")]
    box = (0, 0, 1060, 560)
    w = 600
    shots = [load(f, box, w) for f in files]
    h = shots[0].height
    gap, pad, cap = 28, 36, 74
    cols = 2
    rows = 3
    canvas = Image.new("RGBA", (pad * 2 + cols * w + (cols - 1) * gap, pad * 2 + rows * (h + cap) + (rows - 1) * gap * 0), BG + (255,))
    for i, (im, (name, key, sub)) in enumerate(zip(shots, names)):
        tile(canvas, im, (pad + (i % cols) * (w + gap), pad + (i // cols) * (h + cap)), f"{i + 1}  {name}", f"{key}  ·  {sub}")
    d = ImageDraw.Draw(canvas)
    x, y = pad + (w + gap), pad + 2 * (h + cap)
    d.text((x + 4, y + 8), "one shader, five monitors", font=font(24), fill=FG)
    for n, line in enumerate(("switching is a colour change: one frame, no rebuild", "ctrl+alt+m  picker with live preview", "crt green · crt next · crt save")):
        d.text((x + 4, y + 52 + n * 30), line, font=font(16), fill=DIM)
    canvas.convert("RGB").save(out, optimize=True)


def compare(out, plain_file, crt_file):
    box = (0, 0, 1060, 640)
    w = 640
    a, b = load(plain_file, box, w), load(crt_file, box, w)
    gap, pad, cap = 28, 36, 64
    canvas = Image.new("RGBA", (pad * 2 + 2 * w + gap, pad * 2 + a.height + cap), BG + (255,))
    tile(canvas, a, (pad, pad), "kitty", "same window, same font, no shader")
    tile(canvas, b, (pad + w + gap, pad), "kitty-crt", "retro-crt: one shader file, ten passes")
    canvas.convert("RGB").save(out, optimize=True)


def crop_box(out, src, x0, y0, x1, y1):
    load(src, tuple(int(v) for v in (x0, y0, x1, y1))).save(out, optimize=True)


if __name__ == "__main__":
    command, out, *args = sys.argv[1:]
    {"monitors": lambda: monitors(out, args), "compare": lambda: compare(out, *args), "crop-box": lambda: crop_box(out, *args)}[command]()
