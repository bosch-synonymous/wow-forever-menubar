"""Draw the Network widget's original icons, using only the standard library."""
from pathlib import Path
import struct

SIZE = 64
SAMPLES = 4
OUTLINE = 4.0  # Approximately one display pixel at a 14-16-unit widget size.
REPOSITORY = Path(__file__).resolve().parents[3]
DESTINATION = REPOSITORY / 'src' / 'menubar-network' / 'Media'
HEADER = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
ARROWS = (
    ((8, 14), (40, 14), (40, 8), (56, 20), (40, 32), (40, 26), (8, 26)),
    ((56, 38), (24, 38), (24, 32), (8, 44), (24, 56), (24, 50), (56, 50)),
)

# A pair of folded, interlocking arrows on the Control Strip's pixel grid.
# The bare glyph has no control-panel plate behind it.
HARMONY = (
    "........K.......",
    "........KK......",
    "....KKKKhlK.....",
    "...KhhhhllsK....",
    "..KhlllllllsK...",
    ".KhllKKKsssK....",
    ".KllK...KsK.....",
    "..KK.....K......",
    "......K.....KK..",
    ".....KdK...KggK.",
    "....KdddKKKggtK.",
    "...KdgggggggtK..",
    "....KdggttttK...",
    ".....KgtKKKK....",
    "......KK........",
    ".......K........",
)
PALETTE = {
    ".": (0, 0, 0, 0), "K": (31, 56, 50, 255),
    "h": (209, 248, 204, 255), "l": (124, 206, 131, 255), "s": (72, 145, 101, 255),
    "t": (151, 231, 203, 255), "g": (67, 172, 149, 255), "d": (44, 116, 106, 255),
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


def draw_arrows():
    body, outline = bytearray(), bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            body_hits = outline_hits = 0
            for sub_y in range(SAMPLES):
                for sub_x in range(SAMPLES):
                    point_x, point_y = x + (sub_x + 0.5) / SAMPLES, y + (sub_y + 0.5) / SAMPLES
                    filled = any(contains(polygon, point_x, point_y) for polygon in ARROWS)
                    body_hits += filled
                    outline_hits += filled or any(near_edge(polygon, point_x, point_y) for polygon in ARROWS)
            body.extend((255, 255, 255, round(body_hits * 255 / SAMPLES ** 2)))
            outline.extend((255, 255, 255, round(outline_hits * 255 / SAMPLES ** 2)))
    return HEADER + body, HEADER + outline


def draw_harmony():
    pixels = bytearray()
    for y in range(SIZE):
        row = HARMONY[y * len(HARMONY) // SIZE]
        for x in range(SIZE):
            r, g, b, a = PALETTE[row[x * len(row) // SIZE]]
            pixels.extend((b, g, r, a))
    return HEADER + pixels


def wifi_signal(x, y):
    # Three arcs above a dot. The gaps stay open at the widget's 14-unit size.
    dx, dy = x - 32, 51 - y
    squared_radius = dx * dx + dy * dy
    if squared_radius <= 5 ** 2:
        return True
    return abs(dx) <= dy * 1.16 and (
        12 ** 2 <= squared_radius <= 19 ** 2
        or 24 ** 2 <= squared_radius <= 31 ** 2
        or 36 ** 2 <= squared_radius <= 43 ** 2
    )


def draw_wifi():
    pixels = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            hits = sum(wifi_signal(x + (i + 0.5) / SAMPLES, y + (j + 0.5) / SAMPLES)
                       for j in range(SAMPLES) for i in range(SAMPLES))
            pixels.extend((255, 255, 255, round(hits * 255 / SAMPLES ** 2)))
    return HEADER + pixels


if __name__ == '__main__':
    DESTINATION.mkdir(parents=True, exist_ok=True)
    body, outline = draw_arrows()
    for name, pixels in (('network', body), ('network-outline', outline),
                         ('network-harmony', draw_harmony()), ('network-wifi', draw_wifi())):
        path = DESTINATION / (name + '.tga')
        path.write_bytes(pixels)
        print(f'Generated original {SIZE}x{SIZE} status glyph: {path}')
