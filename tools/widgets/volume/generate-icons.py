"""Generate the original transparent speaker icons used by Menubar: Volume.

Only Python's standard library is needed. These shapes are original geometric
artwork; no other addon's assets or source are inputs. Run from any directory.
"""
from pathlib import Path
import math
import struct

SIZE = 32
SAMPLES = 4
OUTPUT = Path(__file__).resolve().parents[3] / "src" / "menubar-volume" / "Media"


def contains(x, y, state):
    # Speaker body and conical horn, with an open margin for sound arcs.
    body = 4 <= x <= 10 and 12 <= y <= 20
    horn = 9 <= x <= 16 and abs(y - 16) <= (x - 8) * 0.75
    if body or horn:
        return True
    if state == "muted":
        return 20 <= x <= 29 and 10 <= y <= 22 and min(abs((x - 20) - (y - 10) * 0.75),
                                                      abs((x - 20) - (22 - y) * 0.75)) < 1.1
    arcs = {"low": 1, "medium": 2, "high": 3}[state]
    dx, dy = x - 14, y - 16
    radius = math.hypot(dx, dy)
    for level in range(arcs):
        if dx >= 3 and abs(dy) <= dx * 0.8 and abs(radius - (8 + level * 5)) <= 1:
            return True
    return False


def generate(state):
    rgba = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            coverage = sum(contains(x + (sx + 0.5) / SAMPLES,
                                    y + (sy + 0.5) / SAMPLES, state)
                           for sy in range(SAMPLES) for sx in range(SAMPLES))
            alpha = round(coverage * 255 / SAMPLES ** 2)
            # TGA stores BGRA. White artwork takes the current theme's tint at runtime.
            rgba.extend((255, 255, 255, alpha))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    (OUTPUT / f"volume-{state}.tga").write_bytes(header + rgba)


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for state in ("muted", "low", "medium", "high"):
        generate(state)
