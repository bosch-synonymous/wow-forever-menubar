"""Generate original theme-tintable status glyphs using only the standard library.

The tool's directory identifies its official provider within this repository.
It creates only that provider's icon and validates the expected TOC.
No image, font, logo or other addon's artwork is imported. Run from anywhere.
"""
from pathlib import Path
import struct

SIZE = 64
SAMPLES = 4
OUTLINE = 4.0  # Approximately one display pixel at a 14–16-unit widget size.
REPOSITORY = Path(__file__).resolve().parents[3]
PROVIDER = Path(__file__).resolve().parent.name
assert PROVIDER in ('performance', 'network'), 'Expected an official status-icon tool directory'
assert (REPOSITORY / 'src' / ('menubar-' + PROVIDER) / ('Menubar_' + PROVIDER.title() + '.toc')).is_file(), 'Expected provider TOC'
DESTINATION = REPOSITORY / 'src' / ('menubar-' + PROVIDER) / 'Media'

POLYGONS = {
    'performance': (
        ((8, 44), (18, 44), (18, 56), (8, 56)),
        ((27, 28), (37, 28), (37, 56), (27, 56)),
        ((46, 10), (56, 10), (56, 56), (46, 56)),
    ),
    'network': (
        ((8, 14), (40, 14), (40, 8), (56, 20), (40, 32), (40, 26), (8, 26)),
        ((56, 38), (24, 38), (24, 32), (8, 44), (24, 56), (24, 50), (56, 50)),
    ),
}


def contains(polygon, x, y):
    inside = False
    previous_x, previous_y = polygon[-1]
    for next_x, next_y in polygon:
        if (previous_y > y) != (next_y > y):
            crossing = previous_x + (y - previous_y) * (next_x - previous_x) / (next_y - previous_y)
            if x < crossing:
                inside = not inside
        previous_x, previous_y = next_x, next_y
    return inside


def near_edge(polygon, x, y):
    previous_x, previous_y = polygon[-1]
    for next_x, next_y in polygon:
        delta_x, delta_y = next_x - previous_x, next_y - previous_y
        projection = ((x - previous_x) * delta_x + (y - previous_y) * delta_y) / (delta_x * delta_x + delta_y * delta_y)
        projection = min(1.0, max(0.0, projection))
        distance_x = x - previous_x - projection * delta_x
        distance_y = y - previous_y - projection * delta_y
        if distance_x * distance_x + distance_y * distance_y <= OUTLINE * OUTLINE:
            return True
        previous_x, previous_y = next_x, next_y
    return False


def generate(provider):
    body, outline = bytearray(), bytearray()
    polygons = POLYGONS[provider]
    for y in range(SIZE):
        for x in range(SIZE):
            body_hits = outline_hits = 0
            for sub_y in range(SAMPLES):
                for sub_x in range(SAMPLES):
                    point_x, point_y = x + (sub_x + 0.5) / SAMPLES, y + (sub_y + 0.5) / SAMPLES
                    filled = any(contains(polygon, point_x, point_y) for polygon in polygons)
                    body_hits += filled
                    outline_hits += filled or any(near_edge(polygon, point_x, point_y) for polygon in polygons)
            body.extend((255, 255, 255, round(body_hits * 255 / SAMPLES ** 2)))
            outline.extend((255, 255, 255, round(outline_hits * 255 / SAMPLES ** 2)))
    # Top-left origin, eight alpha bits, uncompressed true-color BGRA pixels.
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    return header + body, header + outline


if __name__ == '__main__':
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for suffix, pixels in zip(('', '-outline'), generate(PROVIDER)):
        path = DESTINATION / (PROVIDER + suffix + '.tga')
        path.write_bytes(pixels)
        print(f'Generated original {SIZE}x{SIZE} status glyph: {path}')
