#!/usr/bin/env python3
from __future__ import annotations

import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"
ICONSET = RESOURCES / "AppIcon.iconset"
ICNS = RESOURCES / "AppIcon.icns"
PREVIEW = RESOURCES / "AppIcon.png"
SVG = RESOURCES / "AppIcon.svg"


def lerp(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def mix(c1: tuple[int, int, int], c2: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(lerp(a, b, t) for a, b in zip(c1, c2))


def rounded_rect_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def thermal_color(t: float) -> tuple[int, int, int]:
    stops = [
        (0.00, (18, 31, 62)),
        (0.22, (28, 83, 146)),
        (0.45, (25, 151, 157)),
        (0.63, (238, 204, 84)),
        (0.80, (235, 91, 55)),
        (1.00, (247, 243, 216)),
    ]
    for index, (position, color) in enumerate(stops[1:], start=1):
        previous_position, previous_color = stops[index - 1]
        if t <= position:
            local = (t - previous_position) / (position - previous_position)
            return mix(previous_color, color, max(0, min(1, local)))
    return stops[-1][1]


def make_master(size: int = 1024) -> Image.Image:
    scale = size / 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = rounded_rect_mask(size, round(214 * scale))

    background = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = background.load()
    for y in range(size):
        for x in range(size):
            nx = x / (size - 1)
            ny = y / (size - 1)
            shade = 0.62 * ny + 0.38 * nx
            base = mix((30, 36, 48), (8, 12, 22), shade)
            pixels[x, y] = (*base, 255)
    image.alpha_composite(background)

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse(
        [round(95 * scale), round(60 * scale), round(950 * scale), round(990 * scale)],
        fill=(35, 190, 170, 52),
    )
    glow_draw.ellipse(
        [round(440 * scale), round(175 * scale), round(1040 * scale), round(820 * scale)],
        fill=(242, 112, 69, 56),
    )
    image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(round(52 * scale))))

    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(
        [round(120 * scale), round(150 * scale), round(904 * scale), round(820 * scale)],
        radius=round(94 * scale),
        fill=(17, 23, 34, 235),
        outline=(105, 118, 136, 92),
        width=round(4 * scale),
    )

    panel = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    panel_draw = ImageDraw.Draw(panel)
    panel_box = [round(180 * scale), round(220 * scale), round(844 * scale), round(700 * scale)]
    panel_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(panel_mask).rounded_rectangle(panel_box, radius=round(62 * scale), fill=255)

    thermal = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    thermal_pixels = thermal.load()
    for y in range(panel_box[1], panel_box[3]):
        for x in range(panel_box[0], panel_box[2]):
            nx = (x - panel_box[0]) / max(1, panel_box[2] - panel_box[0])
            ny = (y - panel_box[1]) / max(1, panel_box[3] - panel_box[1])
            wave = 0.5 + 0.5 * math.sin(nx * 7.2 + ny * 4.6)
            spot = math.exp(-(((nx - 0.68) ** 2) / 0.055 + ((ny - 0.34) ** 2) / 0.05))
            cool = math.exp(-(((nx - 0.25) ** 2) / 0.05 + ((ny - 0.66) ** 2) / 0.08))
            t = max(0, min(1, 0.26 + 0.34 * nx + 0.2 * (1 - ny) + 0.22 * wave + 0.35 * spot - 0.2 * cool))
            thermal_pixels[x, y] = (*thermal_color(t), 255)
    heat_draw = ImageDraw.Draw(thermal, "RGBA")
    heat_draw.ellipse(
        [round(560 * scale), round(250 * scale), round(820 * scale), round(500 * scale)],
        fill=(244, 92, 54, 150),
    )
    heat_draw.ellipse(
        [round(640 * scale), round(285 * scale), round(790 * scale), round(430 * scale)],
        fill=(248, 241, 192, 175),
    )
    heat_draw.ellipse(
        [round(210 * scale), round(500 * scale), round(410 * scale), round(675 * scale)],
        fill=(28, 161, 168, 140),
    )
    thermal = thermal.filter(ImageFilter.GaussianBlur(round(3 * scale)))
    thermal.putalpha(panel_mask)
    image.alpha_composite(thermal)

    for offset in range(4):
        alpha = 36 - offset * 6
        step = round((panel_box[2] - panel_box[0]) / 6)
        for i in range(1, 6):
            x = panel_box[0] + i * step
            panel_draw.line(
                [(x, panel_box[1] + round(18 * scale)), (x, panel_box[3] - round(18 * scale))],
                fill=(255, 255, 255, alpha),
                width=round(2 * scale),
            )
        step_y = round((panel_box[3] - panel_box[1]) / 5)
        for i in range(1, 5):
            y = panel_box[1] + i * step_y
            panel_draw.line(
                [(panel_box[0] + round(18 * scale), y), (panel_box[2] - round(18 * scale), y)],
                fill=(255, 255, 255, alpha),
                width=round(2 * scale),
            )
    image.alpha_composite(panel)

    lens_shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    lens_draw = ImageDraw.Draw(lens_shadow)
    lens_draw.ellipse(
        [round(322 * scale), round(352 * scale), round(702 * scale), round(732 * scale)],
        fill=(0, 0, 0, 105),
    )
    image.alpha_composite(lens_shadow.filter(ImageFilter.GaussianBlur(round(22 * scale))))

    draw = ImageDraw.Draw(image)
    draw.ellipse(
        [round(330 * scale), round(330 * scale), round(694 * scale), round(694 * scale)],
        fill=(17, 22, 31, 250),
        outline=(217, 224, 224, 210),
        width=round(12 * scale),
    )
    draw.ellipse(
        [round(390 * scale), round(390 * scale), round(634 * scale), round(634 * scale)],
        fill=(11, 15, 24, 255),
        outline=(58, 207, 195, 175),
        width=round(9 * scale),
    )
    draw.ellipse(
        [round(452 * scale), round(452 * scale), round(572 * scale), round(572 * scale)],
        fill=(19, 38, 68, 255),
    )
    draw.ellipse(
        [round(420 * scale), round(408 * scale), round(485 * scale), round(473 * scale)],
        fill=(245, 250, 246, 180),
    )
    draw.arc(
        [round(365 * scale), round(365 * scale), round(659 * scale), round(659 * scale)],
        210,
        330,
        fill=(255, 132, 84, 220),
        width=round(16 * scale),
    )

    draw.rounded_rectangle(
        [round(314 * scale), round(748 * scale), round(710 * scale), round(832 * scale)],
        radius=round(42 * scale),
        fill=(236, 241, 238, 235),
    )
    draw.rounded_rectangle(
        [round(394 * scale), round(777 * scale), round(630 * scale), round(805 * scale)],
        radius=round(14 * scale),
        fill=(25, 33, 45, 230),
    )
    for x in [456, 512, 568]:
        draw.ellipse(
            [round((x - 10) * scale), round(781 * scale), round((x + 10) * scale), round(801 * scale)],
            fill=(53, 208, 188, 230),
        )

    edge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    edge_draw = ImageDraw.Draw(edge)
    edge_draw.rounded_rectangle(
        [round(10 * scale), round(10 * scale), round(1014 * scale), round(1014 * scale)],
        radius=round(210 * scale),
        outline=(255, 255, 255, 42),
        width=round(7 * scale),
    )
    image.alpha_composite(edge)

    image.putalpha(mask)
    return image


def write_svg() -> None:
    SVG.write_text(
        """<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\" role=\"img\" aria-label=\"ThermoCam UVC app icon\">
  <defs>
    <linearGradient id=\"bg\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\">
      <stop offset=\"0\" stop-color=\"#263044\"/>
      <stop offset=\"1\" stop-color=\"#080c16\"/>
    </linearGradient>
    <linearGradient id=\"thermal\" x1=\"0\" y1=\"1\" x2=\"1\" y2=\"0\">
      <stop offset=\"0\" stop-color=\"#12203e\"/>
      <stop offset=\"0.3\" stop-color=\"#1c5392\"/>
      <stop offset=\"0.52\" stop-color=\"#19979d\"/>
      <stop offset=\"0.7\" stop-color=\"#eecc54\"/>
      <stop offset=\"0.86\" stop-color=\"#eb5b37\"/>
      <stop offset=\"1\" stop-color=\"#f7f3d8\"/>
    </linearGradient>
  </defs>
  <rect width=\"1024\" height=\"1024\" rx=\"214\" fill=\"url(#bg)\"/>
  <rect x=\"120\" y=\"150\" width=\"784\" height=\"670\" rx=\"94\" fill=\"#111722\" stroke=\"#697688\" stroke-opacity=\".36\" stroke-width=\"4\"/>
  <rect x=\"180\" y=\"220\" width=\"664\" height=\"480\" rx=\"62\" fill=\"url(#thermal)\"/>
  <circle cx=\"512\" cy=\"512\" r=\"182\" fill=\"#11161f\" stroke=\"#d9e0e0\" stroke-width=\"12\"/>
  <circle cx=\"512\" cy=\"512\" r=\"122\" fill=\"#0b0f18\" stroke=\"#3ad0c3\" stroke-opacity=\".72\" stroke-width=\"9\"/>
  <circle cx=\"512\" cy=\"512\" r=\"60\" fill=\"#132644\"/>
  <circle cx=\"452\" cy=\"440\" r=\"33\" fill=\"#f5faf6\" opacity=\".72\"/>
  <path d=\"M314 790c0-23 19-42 42-42h312c23 0 42 19 42 42s-19 42-42 42H356c-23 0-42-19-42-42z\" fill=\"#ecf1ee\" opacity=\".92\"/>
  <rect x=\"394\" y=\"777\" width=\"236\" height=\"28\" rx=\"14\" fill=\"#19212d\"/>
</svg>
""",
        encoding="utf-8",
    )


def main() -> None:
    RESOURCES.mkdir(exist_ok=True)
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir()

    master = make_master()
    master.save(PREVIEW)
    write_svg()

    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for filename, pixels in sizes.items():
        resized = master.resize((pixels, pixels), Image.Resampling.LANCZOS)
        resized.save(ICONSET / filename)

    if ICNS.exists():
        ICNS.unlink()
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)


if __name__ == "__main__":
    main()
