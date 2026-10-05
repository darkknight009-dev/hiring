"""Generate the FeedRadar icon set with Python's standard library. No downloads.

Design: a diagonal deep-to-vivid green gradient with a white radar
(rings + sweeping trail), an amber signal blip, and a center dot.
Full-bleed squares for web and legacy launchers, plus adaptive-icon
foreground layers with transparency for Android 8+.
"""

from pathlib import Path
import math
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
WEB_ROOT = ROOT / "web"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"

# Brand colors.
BG_DARK = (13, 62, 47)     # deep green, top-left
BG_LIGHT = (32, 160, 105)  # vivid green, bottom-right
FG = (245, 252, 248)       # near-white artwork
SIGNAL = (255, 196, 61)    # amber blip
ADAPTIVE_BG = "#0D3E2F"

RING_RADII = (0.13, 0.225, 0.32)
RING_WIDTH = 0.018
BLIP = (0.19, -0.115)
LEAD_ANGLE = math.radians(45)
TRAIL_ANGLE = math.radians(100)


def _lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def background_color(u, v):
    """Diagonal gradient: dark top-left to vivid bottom-right."""
    return _lerp(BG_DARK, BG_LIGHT, (u + v + 1) / 2)


def artwork(u, v):
    """(rgb, alpha) of the radar artwork centered on (0, 0) at unit scale."""
    r = math.hypot(u, v)
    for radius in RING_RADII:
        if abs(r - radius) < RING_WIDTH:
            return FG, 0.95
    # Sweep trail behind a leading edge pointing up-right.
    if r <= RING_RADII[-1] + RING_WIDTH:
        angle = math.atan2(-v, u)  # 0 = right, positive = up
        delta = (LEAD_ANGLE - angle) % (2 * math.pi)
        if delta < TRAIL_ANGLE:
            return FG, 0.9 * (1 - delta / TRAIL_ANGLE)
    # Signal blip with a soft glow.
    d = math.hypot(u - BLIP[0], v - BLIP[1])
    if d < 0.045:
        return SIGNAL, 1.0
    if d < 0.085:
        return SIGNAL, 0.35 * (1 - (d - 0.045) / 0.04)
    if r < 0.028:
        return FG, 1.0  # center dot
    return FG, 0.0


def flat_pixel(u, v, art_scale):
    """Full-bleed icon pixel: artwork composited over the gradient."""
    au, av = u / art_scale, v / art_scale
    alpha = 0.0
    color = FG
    if max(abs(au), abs(av)) <= 0.5:
        color, alpha = artwork(au, av)
    return _lerp(background_color(u, v), color, alpha)


def rgba_pixel(u, v, art_scale):
    """Transparent pixel carrying only the artwork, for adaptive layers."""
    au, av = u / art_scale, v / art_scale
    if max(abs(au), abs(av)) > 0.5:
        return (0, 0, 0, 0)
    color, alpha = artwork(au, av)
    return (*color, round(alpha * 255))


def chunk(kind: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))


def write_png(path: Path, size: int, pixel_fn, rgba: bool = False) -> None:
    raw = bytearray()
    for row in range(size):
        raw.append(0)  # PNG row filter: none
        for col in range(size):
            # 2x2 supersampling for smooth edges.
            acc = None
            for du in (0.25, 0.75):
                for dv in (0.25, 0.75):
                    u = (col + du) / size - 0.5
                    v = (row + dv) / size - 0.5
                    value = pixel_fn(u, v)
                    acc = value if acc is None else [
                        a + b for a, b in zip(acc, value)
                    ]
            raw.extend(round(x / 4) for x in acc)
    color_type = 6 if rgba else 2
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, color_type, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw)))
    png += chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
    print(path.relative_to(ROOT))


MIPMAPS = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

ADAPTIVE_FOREGROUNDS = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}

if __name__ == "__main__":
    for dimension in (192, 512):
        write_png(
            WEB_ROOT / "icons" / f"Icon-{dimension}.png",
            dimension,
            lambda u, v: flat_pixel(u, v, 1.0),
        )
        write_png(
            WEB_ROOT / "icons" / f"Icon-maskable-{dimension}.png",
            dimension,
            lambda u, v: flat_pixel(u, v, 0.62),
        )
    write_png(WEB_ROOT / "favicon.png", 32, lambda u, v: flat_pixel(u, v, 1.0))
    for directory, size in MIPMAPS.items():
        write_png(
            ANDROID_RES / directory / "ic_launcher.png",
            size,
            lambda u, v: flat_pixel(u, v, 1.0),
        )
    for directory, size in ADAPTIVE_FOREGROUNDS.items():
        write_png(
            ANDROID_RES / directory / "ic_launcher_foreground.png",
            size,
            lambda u, v: rgba_pixel(u, v, 0.7),
            rgba=True,
        )

    (ANDROID_RES / "values" / "colors.xml").parent.mkdir(
        parents=True, exist_ok=True
    )
    (ANDROID_RES / "values" / "colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{ADAPTIVE_BG}</color>\n'
        "</resources>\n"
    )
    adaptive_dir = ANDROID_RES / "mipmap-anydpi-v26"
    adaptive_dir.mkdir(parents=True, exist_ok=True)
    (adaptive_dir / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n"
    )
    print(adaptive_dir / "ic_launcher.xml")
