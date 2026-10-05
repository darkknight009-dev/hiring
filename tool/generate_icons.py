"""Generate original radar icons with Python's standard library. No downloads."""

from pathlib import Path
import math
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1] / "web"
BACKGROUND = (36, 115, 79)
FOREGROUND = (239, 250, 241)


def chunk(kind: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))


def radar_pixel(x: float, y: float) -> bool:
    radius = math.hypot(x, y)
    rings = any(abs(radius - r) < 0.014 for r in (0.14, 0.26, 0.36))
    # Sweep line, center point, and detected signal stay inside maskable safe zone.
    sweep = abs(x + y) < 0.02 and x >= 0 and y <= 0 and radius < 0.36
    signal = math.hypot(x + 0.22, y + 0.13) < 0.036
    return rings or sweep or signal or radius < 0.025


def write_icon(path: Path, size: int) -> None:
    raw = bytearray()
    for row in range(size):
        raw.append(0)  # PNG row filter: none
        for col in range(size):
            coverage = sum(
                radar_pixel((col + dx) / size - 0.5, (row + dy) / size - 0.5)
                for dx in (0.25, 0.75) for dy in (0.25, 0.75)
            ) / 4
            raw.extend(round(a + (b - a) * coverage)
                       for a, b in zip(BACKGROUND, FOREGROUND))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw)))
    png += chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
    print(path.relative_to(ROOT.parent))


ANDROID_ROOT = Path(__file__).resolve().parents[1] / "android" / "app" / "src" / "main" / "res"
MIPMAPS = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

if __name__ == "__main__":
    for dimension in (192, 512):
        write_icon(ROOT / "icons" / f"Icon-{dimension}.png", dimension)
        write_icon(ROOT / "icons" / f"Icon-maskable-{dimension}.png", dimension)
    write_icon(ROOT / "favicon.png", 32)
    for directory, size in MIPMAPS.items():
        write_icon(ANDROID_ROOT / directory / "ic_launcher.png", size)
