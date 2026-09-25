#!/usr/bin/env python3
"""Patch team name foro -> Dev on the original PNG (3 places only)."""
from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

DIR = Path(__file__).resolve().parent
ORIG = DIR / "Product部門方針-summary-detailed-3teams-base.png"
OUT = DIR / "Product部門方針-summary-detailed-3teams.png"
FONT_PATH = "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"
FONT_EN = "/System/Library/Fonts/Supplemental/Arial.ttf"


def load_font(size: int, latin: bool = False) -> ImageFont.FreeTypeFont:
    path = FONT_EN if latin else FONT_PATH
    try:
        return ImageFont.truetype(path, size, index=0)
    except OSError:
        return ImageFont.load_default()


def erase_rect(img: Image.Image, box: tuple[int, int, int, int], fill) -> None:
    ImageDraw.Draw(img).rectangle(box, fill=fill)


def erase_dark_pixels(img: Image.Image, x1: int, x2: int, y1: int, y2: int, bg, thr: int = 200) -> None:
    px = img.load()
    for y in range(y1, y2 + 1):
        for x in range(x1, x2 + 1):
            r, g, b = px[x, y]
            if r < thr and g < thr and b < thr:
                px[x, y] = bg


def draw_left(
    img: Image.Image,
    pos: tuple[int, int],
    text: str,
    color: tuple[int, int, int],
    font_size: int,
    latin: bool = False,
) -> None:
    draw = ImageDraw.Draw(img)
    font = load_font(font_size, latin=latin)
    draw.text(pos, text, fill=color, font=font)


def main() -> None:
    if not ORIG.exists():
        raise SystemExit(f"Missing base image: {ORIG}")

    shutil.copy2(ORIG, OUT)
    img = Image.open(OUT).convert("RGB")

    # Sampled from original green header
    green = (4, 127, 36)
    white = (255, 255, 255)
    black = (30, 30, 30)

    # 1. Header: foro -> Dev (wider erase to remove antialiasing)
    erase_rect(img, (664, 247, 729, 272), green)
    draw_left(img, (676, 250), "Dev", white, 18)

    # 2. FDE flow: (foro) -> (Dev)
    erase_rect(img, (444, 507, 499, 526), white)
    draw_left(img, (450, 511), "(Dev)", black, 10, latin=True)

    # 3. Goal: lowercase foro -> Dev (x=312-366, y=960-971; keep FDE E and dots)
    erase_rect(img, (312, 960, 366, 971), white)
    draw_left(img, (318, 960), "Dev", black, 12, latin=True)

    img.save(OUT, format="PNG", optimize=False)
    print(f"Patched {OUT}")


if __name__ == "__main__":
    main()
