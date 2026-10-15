#!/usr/bin/env python3
"""Generate legacy launcher PNGs (pre-API-26 launchers) for the AI Chat icon.

Design mirrors tools/res/drawable/ic_launcher_foreground.xml exactly:
same viewport (108), same cubic bezier control points → the legacy PNG and the
adaptive icon look identical.

Outputs:
  tools/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png        (squircle)
  tools/res/mipmap-{...}/ic_launcher_round.png                             (circle)
"""
import os
from PIL import Image, ImageDraw, ImageFilter

INK = (70, 80, 107, 255)          # #46506B
ACCENT = (140, 151, 174, 255)     # #8C97AE
BG_TOP = (237, 241, 247)          # #EDF1F7
BG_BOTTOM = (203, 212, 226)       # #CBD4E2
S = 4                             # supersample factor

DENSITIES = {
    "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192,
}

# --- path data (viewport 108), cubic beziers: (start, [ (c1,c2,end), ... ], closed) ---
PATHS = [
    ((54, 74), [((53, 66), (54, 58), (54, 50))], False),                      # stem
    ((54, 66), [((46, 64), (40, 58), (38, 50)), ((46, 52), (52, 58), (54, 66))], True),
    ((54, 70), [((62, 68), (68, 62), (70, 54)), ((62, 56), (56, 62), (54, 70))], True),
    ((54, 48), [((49, 40), (48, 30), (54, 24)), ((60, 30), (59, 40), (54, 48))], True),
    ((52, 50), [((44, 46), (38, 38), (38, 30)), ((46, 32), (52, 40), (52, 50))], True),
    ((56, 50), [((64, 46), (70, 38), (70, 30)), ((62, 32), (56, 40), (56, 50))], True),
    ((54, 50), [((50, 56), (44, 60), (40, 60)), ((42, 54), (48, 50), (54, 50))], True),
]
WIDTHS = [2.6, 2.2, 2.2, 2.4, 2.2, 2.2, 2.2]
DIAMONDS = [(22, 22), (81, 22), (22, 81), (81, 81)]


def bezier_points(p0, segments, steps=24):
    pts = []
    for (c1, c2, p1) in segments:
        for i in range(steps + 1):
            t = i / steps
            mt = 1 - t
            x = (mt ** 3) * p0[0] + 3 * (mt ** 2) * t * c1[0] + 3 * mt * (t ** 2) * c2[0] + (t ** 3) * p1[0]
            y = (mt ** 3) * p0[1] + 3 * (mt ** 2) * t * c1[1] + 3 * mt * (t ** 2) * c2[1] + (t ** 3) * p1[1]
            pts.append((x, y))
        p0 = p1
    return pts


def draw_motif(d, size, scale):
    """scale = pixels per viewport unit"""
    for (start, segs, closed), w in zip(PATHS, WIDTHS):
        pts = bezier_points(start, segs)
        if closed:
            pts.append(pts[0])
        d.line([(x * scale, y * scale) for (x, y) in pts],
               fill=INK, width=max(2, int(round(w * scale))), joint="curve")
    # center dot
    cx, cy, r = 54 * scale, 42 * scale, 2.6 * scale
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=INK)
    # corner diamonds
    s = 2.4 * scale
    for (dx, dy) in DIAMONDS:
        x, y = dx * scale, dy * scale
        d.polygon([(x, y - s), (x + s, y), (x, y + s), (x - s, y)], fill=ACCENT)


def gradient(size, top, bottom):
    g = Image.new("RGB", (1, size), top)
    px = g.load()
    for y in range(size):
        t = y / max(1, size - 1)
        px[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return g.resize((size, size))


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1],
                                        radius=radius, fill=255)
    return m


def make_icon(px, round_icon=False):
    big = px * S
    bg = gradient(px, BG_TOP, BG_BOTTOM).resize((big, big), Image.LANCZOS)
    icon = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    icon.paste(bg, (0, 0))

    motif = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw_motif(ImageDraw.Draw(motif), big, big / 108.0)
    icon.alpha_composite(motif)

    mask = (Image.new("L", (big, big), 0))
    md = ImageDraw.Draw(mask)
    if round_icon:
        md.ellipse([0, 0, big - 1, big - 1], fill=255)
    else:
        mask = rounded_mask(big, int(big * 0.22))
    icon.putalpha(mask)

    return icon.resize((px, px), Image.LANCZOS)


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "res")
    for name, px in DENSITIES.items():
        d = os.path.join(root, f"mipmap-{name}")
        os.makedirs(d, exist_ok=True)
        make_icon(px, False).save(os.path.join(d, "ic_launcher.png"))
        make_icon(px, True).save(os.path.join(d, "ic_launcher_round.png"))
        print(f"mipmap-{name}: {px}x{px} written")


if __name__ == "__main__":
    main()
