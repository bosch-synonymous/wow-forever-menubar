"""Draw the steel repair hammer and its monochrome menu-bar silhouette."""
from pathlib import Path
import struct

MEDIA = Path(__file__).resolve().parents[3] / "src/menubar-durability/Media"
SIZE = 32
SAMPLES = 4

# A wooden haft with a dark edge, a tapered steel peen and a separate striking face.
LAYERS = (
    ((45, 35, 30), ((8.9, 4.5), (11.6, 6.5), (3.9, 15.1), (2.8, 15.4), (0.6, 13.6), (0.6, 12.6))),
    ((174, 99, 43), ((9.2, 5.4), (10.6, 6.6), (3.4, 14.5), (1.5, 13.1))),
    ((247, 183, 99), ((9.3, 5.5), (9.9, 6.0), (2.2, 13.6), (1.5, 13.1))),
    ((35, 41, 49), ((3.5, 3.7), (4.6, 1.6), (6.4, 0.6), (8.6, 0.9), (12.8, 4.6),
                     (13.5, 4.3), (15.5, 5.9), (15.4, 6.8), (12.7, 9.7), (10.4, 7.9),
                     (10.4, 7.2), (6.9, 4.1), (6.0, 3.4))),
    ((133, 153, 170), ((4.8, 2.6), (6.5, 1.3), (8.3, 1.6), (12.3, 5.2), (10.9, 6.7),
                        (7.2, 3.5), (6.1, 2.7))),
    ((219, 232, 237), ((5.2, 2.3), (6.6, 1.3), (8.2, 1.6), (12.2, 5.2), (11.6, 5.8),
                        (7.7, 2.3), (6.5, 2.0))),
    ((188, 205, 217), ((11.1, 7.4), (13.4, 5.2), (14.7, 6.2), (12.6, 8.9))),
)


# The small gap between the handle and head survives a 16-pixel menu-bar render.
# Both components use a white mask so the profile supplies all visible colour.
MONOCHROME = (
    ((255, 255, 255), ((8.2, 6.5), (10.1, 8.0), (3.7, 15.0), (2.5, 15.4),
                       (1.0, 14.1), (1.1, 12.9))),
    ((255, 255, 255), ((2.6, 4.5), (3.8, 2.0), (6.1, 0.8), (8.2, 1.0),
                       (12.6, 4.7), (13.6, 4.2), (15.5, 5.9), (12.8, 9.4),
                       (10.6, 7.7), (10.7, 6.9), (6.9, 3.8), (5.7, 3.3))),
)


def contains(points, x, y):
    inside = False
    previous_x, previous_y = points[-1]
    for next_x, next_y in points:
        if (previous_y > y) != (next_y > y):
            crossing = previous_x + (y - previous_y) * (next_x - previous_x) / (next_y - previous_y)
            if x < crossing:
                inside = not inside
        previous_x, previous_y = next_x, next_y
    return inside


def generate(filename, layers):
    pixels = bytearray()
    step = 16 / (SIZE * SAMPLES)
    for y in range(SIZE):
        for x in range(SIZE):
            covered = []
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    px, py = (x * SAMPLES + sx + 0.5) * step, (y * SAMPLES + sy + 0.5) * step
                    for colour, points in reversed(layers):
                        if contains(points, px, py):
                            covered.append(colour)
                            break
            if covered:
                red, green, blue = (round(sum(channel) / len(covered)) for channel in zip(*covered))
                pixels.extend((blue, green, red, round(255 * len(covered) / SAMPLES ** 2)))
            else:
                pixels.extend((0, 0, 0, 0))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    MEDIA.mkdir(parents=True, exist_ok=True)
    (MEDIA / filename).write_bytes(header + pixels)


if __name__ == "__main__":
    generate("repair-hammer.tga", LAYERS)
    generate("repair-hammer-mono.tga", MONOCHROME)
