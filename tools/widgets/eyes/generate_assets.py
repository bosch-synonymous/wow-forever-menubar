"""Generate original, deterministic eye geometry as game-compatible 32-bit TGA.

No fonts, models, photographs, external artwork or third-party packages are read.
Run from any directory; the four assets are written beside the addon Lua.
"""
from __future__ import annotations

import math
from pathlib import Path
import struct

SIZE = 64
DESTINATION = Path(__file__).resolve().parents[3] / "src" / "menubar-eyes" / "Assets"


def clamp(value: float) -> float:
    return max(0.0, min(1.0, value))


def sample(name: str, x: float, y: float) -> tuple[float, float]:
    radius = math.hypot(x, y)
    alpha = clamp((1.0 - radius) * SIZE / 2 + 0.5)
    if name == "Orb":
        light = clamp(-0.30 * x - 0.42 * y + 0.85 * math.sqrt(max(0, 1 - radius * radius)))
        sphere = 0.84 + 0.16 * light
        edge = clamp((radius - 0.87) / 0.055)
        shade = sphere * (1 - edge) + 0.035 * edge
    elif name == "SolidIris":
        shade = 1.0
    elif name == "Iris":
        shade = 0.42 + 0.48 * (1 - clamp(radius))
        if radius < 0.28:
            shade = 0.025
        elif radius < 0.36:
            blend = (radius - 0.28) / 0.08
            shade = 0.025 * (1 - blend) + shade * blend
    else:
        shade = 1.0
        alpha *= clamp(1 - radius) ** 1.1
    return shade, alpha


def generate() -> None:
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for name in ("Orb", "Iris", "SolidIris", "Glint"):
        pixels = bytearray(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28))
        for row in range(SIZE):
            for column in range(SIZE):
                x = (column + 0.5) * 2 / SIZE - 1
                y = (row + 0.5) * 2 / SIZE - 1
                shade, alpha = sample(name, x, y)
                channel = round(clamp(shade) * 255)
                pixels.extend((channel, channel, channel, round(clamp(alpha) * 255)))
        (DESTINATION / f"{name}.tga").write_bytes(pixels)
        print(f"Generated {name}.tga ({SIZE}x{SIZE}, original procedural geometry)")


if __name__ == "__main__":
    generate()
