"""Draw original Menubar popup materials at their native nine-slice size."""
from math import exp, hypot
from pathlib import Path
import struct


OUTPUT = Path(__file__).resolve().parents[1] / "src/menubar-core/Media/Popup"


def rounded(x, y, left, top, right, bottom, radius):
    """Signed distance to a rounded rectangle, measured at a subpixel."""
    dx = abs(x - (left + right) / 2) - (right - left) / 2 + radius
    dy = abs(y - (top + bottom) / 2) - (bottom - top) / 2 + radius
    return hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0) - radius


def glass(x, y):
    edge = rounded(x, y, 2.5, 1.5, 61.5, 60.5, 13)
    if edge > 0:
        shadow = max(0, rounded(x, y, 2.5, 2.8, 61.5, 61.8, 13))
        return "frame", (24, 29, 43, 50 * exp(-1.35 * shadow))
    if edge > -0.65:
        return "frame", (86, 93, 108, 145)
    if edge > -1.35:
        return "frame", (255, 255, 255, 243)
    return "panel", (252, 253, 255, 255)


def glass_selection(x, y):
    return 18, 98, 215, 255 if rounded(x, y, 0, 0, 16, 16, 5) <= 0 else 0


def aqua(x, y):
    if x < 1 or x >= 15 or y >= 12:
        distance = max(1 - x, x - 15, y - 12, 0)
        return "frame", (23, 30, 37, max(0, 72 - distance * 20))
    if x < 2 or x >= 14 or y < 1 or y >= 11:
        return "frame", (138, 147, 159, 225)
    level = (249, 246, 239, 246)[int(y) % 4]
    return "panel", (level, level + 1, min(255, level + 3), 241)


def aqua_selection(x, y):
    return (*((52, 108, 182), (48, 102, 176), (41, 95, 168), (48, 102, 176))[int(y) % 4], 255)


def segment(x, y, ax, ay, bx, by):
    t = max(0, min(1, ((x-ax)*(bx-ax) + (y-ay)*(by-ay)) / ((bx-ax)**2 + (by-ay)**2)))
    return hypot(x - ax - t*(bx-ax), y - ay - t*(by-ay))


def marks(x, y):
    if x < 16:
        points = ((3, 8.5), (6.5, 12), (13, 4))
    else:
        x -= 16
        points = ((6, 3.5), (10.5, 8), (6, 12.5))
    distance = min(segment(x, y, *a, *b) for a, b in zip(points, points[1:]))
    return 255, 255, 255, 255 if distance <= 1 else 0


def write(name, width, height, pixel, layer=None):
    # Average premultiplied subpixels, then store straight-alpha BGRA.
    data = bytearray(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28))
    for y in range(height):
        for x in range(width):
            samples = [pixel(x + (sx + 0.5) / 4, y + (sy + 0.5) / 4)
                       for sy in range(4) for sx in range(4)]
            if layer:
                fallback = samples[0][1]
                rim_coverage = sum(rgba[3] for part, rgba in samples if part == "frame") / (16 * 255)
                samples = [rgba for part, rgba in samples if part == layer]
            else:
                fallback = samples[0]
            alpha = sum(sample[3] for sample in samples)
            for channel in (2, 1, 0):
                data.append(round(sum(sample[channel] * sample[3] for sample in samples) / alpha)
                            if alpha else fallback[channel])
            coverage = alpha / 16
            if layer == "panel" and coverage:
                # The rim draws over the face. At their shared antialiased edge,
                # preserve the original coverage when both layers are fully on.
                coverage /= 1 - rim_coverage
            data.append(min(255, round(coverage)))
    (OUTPUT / name).write_bytes(data)


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for layer in ("panel", "frame"):
        write(f"glass-{layer}.tga", 64, 64, glass, layer)
        write(f"aqua-{layer}.tga", 16, 16, aqua, layer)
    write("glass-selection.tga", 16, 16, glass_selection)
    write("aqua-selection.tga", 4, 4, aqua_selection)
    write("marks.tga", 32, 16, marks)
