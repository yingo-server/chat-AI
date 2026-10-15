#!/usr/bin/env python3
"""Generate all launcher icon assets from tools/res/source_icon.png.

Pipeline (deterministic, re-runnable):
  source (192x192, white background, grey-blue emblem)
    ├─ legacy squircle PNG : emblem scaled to 80% of the canvas, centred on a
    │                        white plate, rounded-rect (squircle) mask
    │                        -> mipmap-{d}/ic_launcher.png        (48..192)
    ├─ legacy round PNG    : identical, circular mask
    │                        -> mipmap-{d}/ic_launcher_round.png
    └─ adaptive foreground : white keyed out to alpha, emblem scaled to 62% of
                             the 108dp canvas (inside the 66dp safe zone)
                             -> mipmap-{d}/ic_launcher_foreground.png
                                (108/162/216/324/432 for mdpi..xxxhdpi)

Densities: mdpi 48/108 · hdpi 72/162 · xhdpi 96/216 · xxhdpi 144/324 · xxxhdpi 192/432
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "res")
SRC = os.path.join(RES, "source_icon.png")

# legacy icon size, adaptive foreground size (108dp baseline)
DENSITIES = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}

LEGACY_EMBLEM_RATIO = 0.80   # emblem fills 80% of the legacy canvas
ADAPTIVE_EMBLEM_RATIO = 0.62  # 62% keeps it inside the 66/108 safe zone
SQUIRCLE_RADIUS = 0.22        # fraction of the canvas
WHITE_KEY_LOW = 236           # <= this luminance -> opaque
WHITE_KEY_HIGH = 252          # >= this luminance -> fully transparent
S = 4                         # supersampling


def load_emblem() -> Image.Image:
    im = Image.open(SRC).convert("RGBA")
    return im


def key_out_white(im: Image.Image) -> Image.Image:
    """Turn the near-white background into transparency (keeps interior cut-outs)."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            lum = (r * 299 + g * 587 + b * 114) // 1000
            if lum >= WHITE_KEY_HIGH:
                px[x, y] = (r, g, b, 0)
            elif lum > WHITE_KEY_LOW:
                # linear alpha ramp for smooth edges
                t = (lum - WHITE_KEY_LOW) / float(WHITE_KEY_HIGH - WHITE_KEY_LOW)
                px[x, y] = (r, g, b, int(a * (1 - t)))
    return im


def plate(emblem: Image.Image, size: int, ratio: float,
          bg: tuple = (255, 255, 255, 255)) -> Image.Image:
    """Emblem scaled to `ratio` of `size`, centred on a solid plate."""
    canvas = Image.new("RGBA", (size, size), bg)
    inner = max(1, int(size * ratio))
    e = emblem.resize((inner, inner), Image.LANCZOS)
    off = (size - inner) // 2
    canvas.alpha_composite(e, (off, off))
    return canvas


def mask_for(size: int, round_icon: bool) -> Image.Image:
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    if round_icon:
        d.ellipse([0, 0, size - 1, size - 1], fill=255)
    else:
        d.rounded_rectangle([0, 0, size - 1, size - 1],
                            radius=int(size * SQUIRCLE_RADIUS), fill=255)
    return m


def main() -> None:
    emblem = load_emblem()
    transparent = key_out_white(emblem)

    for name, (legacy_px, adaptive_px) in DENSITIES.items():
        d = os.path.join(RES, f"mipmap-{name}")
        os.makedirs(d, exist_ok=True)

        # ---- legacy squircle / round ----
        for round_icon, fname in ((False, "ic_launcher.png"),
                                  (True, "ic_launcher_round.png")):
            big = legacy_px * S
            art = plate(emblem, big, LEGACY_EMBLEM_RATIO)
            art.putalpha(mask_for(big, round_icon))
            art.resize((legacy_px, legacy_px), Image.LANCZOS).save(
                os.path.join(d, fname))

        # ---- adaptive foreground (transparent, safe-zone scaled) ----
        big = adaptive_px * S
        fg = plate(transparent, big, ADAPTIVE_EMBLEM_RATIO,
                   bg=(0, 0, 0, 0))
        fg.resize((adaptive_px, adaptive_px), Image.LANCZOS).save(
            os.path.join(d, "ic_launcher_foreground.png"))

        print(f"{name}: legacy {legacy_px}px, adaptive {adaptive_px}px")


if __name__ == "__main__":
    main()
