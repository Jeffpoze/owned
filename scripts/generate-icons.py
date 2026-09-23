"""
Draws the Owned app icon (house with a check, a stack of documents behind it)
and writes the source images used by flutter_launcher_icons and flutter_native_splash.

    python3 scripts/generate-icons.py
    dart run flutter_launcher_icons
    dart run flutter_native_splash:create

Needs Pillow. Drawn at 4x and downsampled for smooth edges.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"
S = 4  # supersampling
N = 1024 * S

BG_TOP = (40, 48, 59)
BG_BOTTOM = (20, 28, 38)
HOUSE = (242, 245, 249)
INK = (18, 26, 36)
MINT = (91, 221, 186)
BLUE = (46, 150, 224)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def vgradient(size, top, bottom, y0=0, y1=None):
    w, h = size
    y1 = h if y1 is None else y1
    g = Image.new("RGB", size)
    d = ImageDraw.Draw(g)
    for y in range(h):
        t = min(1, max(0, (y - y0) / max(1, y1 - y0)))
        d.line([(0, y), (w, y)], fill=lerp(top, bottom, t))
    return g


def rounded_polygon(points, r, steps=24):
    """Polygon with each corner rounded by radius r (quadratic-ish arc)."""
    import math

    out = []
    n = len(points)
    for i in range(n):
        p0, p1, p2 = points[i - 1], points[i], points[(i + 1) % n]
        v1 = (p0[0] - p1[0], p0[1] - p1[1])
        v2 = (p2[0] - p1[0], p2[1] - p1[1])
        l1, l2 = math.hypot(*v1), math.hypot(*v2)
        rr = min(r, l1 / 2, l2 / 2)
        a = (p1[0] + v1[0] / l1 * rr, p1[1] + v1[1] / l1 * rr)
        b = (p1[0] + v2[0] / l2 * rr, p1[1] + v2[1] / l2 * rr)
        for k in range(steps + 1):
            t = k / steps
            # quadratic Bezier a -> p1 -> b
            x = (1 - t) ** 2 * a[0] + 2 * (1 - t) * t * p1[0] + t**2 * b[0]
            y = (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * p1[1] + t**2 * b[1]
            out.append((x, y))
    return out


def mark_layers(scale=1.0, cx=512, cy=512):
    """Shapes in 1024-space, centred on (cx, cy), scaled. Returns dict of polygons."""
    # Designed around (0,0) = centre of the whole mark.
    def P(x, y):
        return ((cx + x * scale) * S, (cy + y * scale) * S)

    house = [P(-330, -120), P(-80, -310), P(170, -120), P(170, 305), P(-330, 305)]
    card1 = [P(150, -150), P(215, -110), P(250, -60), P(250, 305), P(150, 305)]
    card2 = [P(230, 20), P(285, 50), P(305, 90), P(305, 305), P(230, 305)]
    check = [P(-185, 95), P(-100, 185), P(90, -25)]
    return {
        "house": house,
        "card1": card1,
        "card2": card2,
        "check": check,
        "radius": 46 * scale * S,
        "gap": 20 * scale * S,
        "stroke": 80 * scale * S,
        "top": (cy - 310 * scale) * S,
        "bottom": (cy + 305 * scale) * S,
    }


def grow(poly, px):
    """Grow a convex-ish polygon outward from its centroid (for the dark gaps)."""
    cx = sum(p[0] for p in poly) / len(poly)
    cy = sum(p[1] for p in poly) / len(poly)
    out = []
    for x, y in poly:
        dx, dy = x - cx, y - cy
        d = (dx * dx + dy * dy) ** 0.5 or 1
        out.append((x + dx / d * px, y + dy / d * px))
    return out


def draw_mark(canvas, bg_fill, mono=None, **kw):
    """Draw cards, gaps, house and check onto `canvas` (RGBA, supersampled)."""
    m = mark_layers(**kw)
    r = m["radius"]
    card_fill = vgradient((N, N), MINT, BLUE, int(m["top"] + 150 * S), int(m["bottom"]))

    def fill_poly(pts, fill, radius):
        mask = Image.new("L", (N, N), 0)
        ImageDraw.Draw(mask).polygon(rounded_polygon(pts, radius), fill=255)
        if isinstance(fill, Image.Image):
            canvas.paste(fill, (0, 0), mask)
        else:
            canvas.paste(Image.new("RGBA", (N, N), fill), (0, 0), mask)

    def cut(pts, radius):
        """Punch a gap: background colour, or transparent for monochrome/foreground layers."""
        mask = Image.new("L", (N, N), 0)
        ImageDraw.Draw(mask).polygon(rounded_polygon(grow(pts, m["gap"]), radius), fill=255)
        if bg_fill is None:
            alpha = canvas.getchannel("A")
            alpha.paste(0, (0, 0), mask)
            canvas.putalpha(alpha)
        else:
            canvas.paste(Image.new("RGBA", (N, N), bg_fill), (0, 0), mask)

    fill_poly(m["card2"], mono or card_fill, r * 0.6)
    cut(m["card1"], r * 0.6)
    fill_poly(m["card1"], mono or card_fill, r * 0.6)
    cut(m["house"], r)
    fill_poly(m["house"], mono or HOUSE, r)

    d = ImageDraw.Draw(canvas)
    w = int(m["stroke"])
    pts = m["check"]
    check_color = (0, 0, 0, 0) if mono else INK + (255,)
    if mono:
        # knock the check out of the house
        mask = Image.new("L", (N, N), 0)
        md = ImageDraw.Draw(mask)
        md.line(pts, fill=255, width=w, joint="curve")
        for p in (pts[0], pts[-1]):
            md.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=255)
        alpha = canvas.getchannel("A")
        alpha.paste(0, (0, 0), mask)
        canvas.putalpha(alpha)
    else:
        d.line(pts, fill=check_color, width=w, joint="curve")
        for p in (pts[0], pts[-1]):
            d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=check_color)


def finish(img, size):
    return img.resize((size, size), Image.LANCZOS)


def app_icon():
    mark = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    draw_mark(mark, bg_fill=None, scale=1.0, cx=497, cy=512)
    base = vgradient((N, N), BG_TOP, BG_BOTTOM).convert("RGBA")
    base.alpha_composite(mark)
    return base.convert("RGB")


def rounded_tile(icon, size, radius_ratio=0.225):
    tile = icon.resize((size, size), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=size * 4 * radius_ratio, fill=255)
    tile.putalpha(mask.resize((size, size), Image.LANCZOS))
    return tile


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    icon = app_icon()
    finish(icon, 1024).save(OUT / "icon.png")

    # Android adaptive icon: mark inside the 66% safe zone on a transparent layer.
    fg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    draw_mark(fg, bg_fill=None, scale=0.62, cx=500, cy=512)
    finish(fg, 1024).save(OUT / "android-icon-foreground.png")
    finish(vgradient((N, N), BG_TOP, BG_BOTTOM), 1024).save(OUT / "android-icon-background.png")
    mono = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    draw_mark(mono, bg_fill=None, mono=(255, 255, 255, 255), scale=0.62, cx=500, cy=512)
    finish(mono, 1024).save(OUT / "android-icon-monochrome.png")

    # Splash: the rounded icon tile, shown on the app's paper colour.
    rounded_tile(icon, 512).save(OUT / "splash-icon.png")
    # Android 12+ splash masks the image to a circle; keep the tile inside its safe area.
    a12 = Image.new("RGBA", (1152, 1152), (0, 0, 0, 0))
    a12.alpha_composite(rounded_tile(icon, 600), (276, 276))
    a12.save(OUT / "splash-icon-android12.png")
    print("wrote icons to", OUT)


if __name__ == "__main__":
    main()
