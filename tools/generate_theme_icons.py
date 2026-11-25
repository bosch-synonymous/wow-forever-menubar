"""Draw Menubar's original Mac-inspired status glyphs. No source art is required.

Eight 32-pixel cells per row: speaker states, envelope and bell states.
Harmony and Platinum use indexed pixel art. Aqua and Glass use tintable masks.
Run from any directory with the standard Python interpreter.
"""
import math
import struct
from pathlib import Path

OUTPUT = Path(__file__).resolve().parents[1] / "src/menubar-core/Media/ThemeIcons/status.tga"
FAMILIES = ("harmony", "platinum", "aqua", "glass")
ROLES = ("muted", "low", "medium", "high", "mail", "social", "social-alert", "social-group")
CELL = 32


# Each character is an original one-pixel design decision on the Control Strip's
# scale. Dot is clear, K is the ink contour and lower-case shades model the bevel.
PIXEL_PALETTE = {
    ".": (0, 0, 0, 0),         "K": (24, 23, 29, 255),
    "W": (255, 255, 250, 255), "g": (168, 170, 181, 255),
    "p": (214, 208, 255, 255), "v": (150, 139, 218, 255),
    "s": (88, 81, 151, 255),   "c": (247, 239, 211, 255),
    "t": (196, 182, 149, 255), "r": (163, 49, 55, 255),
    "y": (255, 219, 124, 255), "o": (207, 151, 71, 255),
    "b": (139, 88, 51, 255),   "L": (234, 235, 244, 255),
    "M": (194, 198, 213, 255), "D": (105, 112, 139, 255),
    "n": (47, 52, 78, 255),    "V": (156, 158, 238, 255),
    "u": (102, 102, 191, 255), "S": (64, 69, 142, 255),
    "B": (101, 152, 211, 255),
}

HARMONY_SPEAKER = (
    ".......KK", "......KpK", ".....KpvK", "....KppvK",
    "KKKKppvvK", "KWpppvvvK", "KvvvssssK", "KKKKvsssK",
    "....KsvsK", ".....KsvK", "......KsK", ".......KK",
)
HARMONY_ENVELOPE = (
    ".KKKKKKKKKKKKK.", "KWWWWWWWWWWWWgK", "KgtWWWWWWWWctgK",
    "KcgtWWWWWWctgcK", "KccgtWWWWctgccK", "KcccgrrrrgccccK",
    "KcccgryrbgccccK", "KccgtbrrbctgccK", "KcgtccccccctgcK",
    "KgtccccccccctgK", "KgggggggggggggK", ".KKKKKKKKKKKKK.",
)
HARMONY_BELL = (
    ".....KK.....", "....KyoK....", "...KKKKKK...", "..KWyyobbK..",
    "..KWyoobbK..", "..KyyoobbK..", "..KyoobbbK..", ".KyyooobbbK.",
    ".KWyooobbbK.", "KWyyyyooobbK", "KbbbbbbbbbbK", ".KKKKKKKKKK.",
    ".....KyK....", ".....KKK....",
)
# The Platinum set uses cool silver fittings and stronger facet shading.
PLATINUM_SPEAKER = (
    ".......Kn.", "......KLVK", ".....KpVVK", "....KpVVuK",
    "KKKKpVVuuK", "KLppVVuuuK", "KVvvvuuSuK", "KSSSSuSSuK",
    "KKKKKSSSuK", ".....KSSuK", "......KSsK", ".......Kn.",
)
PLATINUM_ENVELOPE = (
    ".KKKKKKKKKKKKK.", "KWWLLLLLLLLLLMK", "KWMDLLLLLLLMDBK",
    "KLLMDLLLLLMDBBK", "KLMLMDLLLMDLLMK", "KLLMLMDLMDLLLMK",
    "KLLLMDMnMDLLLMK", "KLLMDLMDMLDLLMK", "KLMDLLLLLLMDLMK",
    "KMDLLLLLLLLLMDK", "KMMMMMMMMMMMMDK", "KDDDDDDDDDDDDDK",
    ".nnnnnnnnnnnnn.",
)
PLATINUM_BELL = (
    ".....nn.....", "....nyon....", "...nMMMMn...", "..nWLLMDDn..",
    "..nWLMMDnn..", "..nLMMDDnn..", "..nLMMDnDn..", ".nLMMDDnDDn.",
    ".nWLMMDnDDn.", "nWLLLLMMMDDn", "nMMMDMMDDDDn", ".nnnnnnnnnn.",
    ".....non....", ".....nnn....",
)
# Cumulative arcs keep each volume level legible on the compact 16-pixel grid.
HARMONY_WAVES = (
    (10, 6, ("K.", ".K", ".K", "K.")),
    (12, 4, ("K.", ".K", ".K", ".K", ".K", ".K", ".K", "K.")),
    (13, 2, ("K..", ".K.", ".K.", "..K", "..K", "..K", "..K", "..K", "..K", ".K.", ".K.", "K..")),
)


def pixel_tile(family, role):
    tile = [["."] * 16 for _ in range(16)]

    def stamp(x, y, lines):
        for dy, line in enumerate(lines):
            for dx, mark in enumerate(line):
                if mark != ".":
                    tile[y + dy][x + dx] = mark

    platinum = family == "platinum"
    if role == "mail":
        stamp(0, 2, PLATINUM_ENVELOPE if platinum else HARMONY_ENVELOPE)
    elif role.startswith("social"):
        stamp(2, 1, PLATINUM_BELL if platinum else HARMONY_BELL)
        if role in ("social-alert", "social-group"):
            stamp(0, 2, ("..K", ".K.", "K..", "K.."))
        if role == "social-group":
            stamp(13, 2, ("K..", ".K.", "..K", "..K"))
    else:
        stamp(0, 2, PLATINUM_SPEAKER if platinum else HARMONY_SPEAKER)
        if role == "muted":
            stamp(10, 5, ("r...r", ".r.r.", "..r..", ".r.r.", "r...r"))
        else:
            for wave in HARMONY_WAVES[:("low", "medium", "high").index(role) + 1]:
                stamp(*wave)
    return tile


class Glyph:
    """Paint a supersampled alpha mask in a 16-unit design grid."""

    def __init__(self):
        self.scale = 4
        self.size = 16 * self.scale
        self.pixels = bytearray(self.size ** 2)

    def paint(self, mask, ink=255):
        for row in range(self.size):
            y = (row + 0.5) / self.scale
            for col in range(self.size):
                x = (col + 0.5) / self.scale
                if mask(x, y):
                    self.pixels[row * self.size + col] = ink

    def polygon(self, points, ink=255):
        edges = list(zip(points, points[1:] + points[:1]))

        def inside(x, y):
            return sum((y1 > y) != (y2 > y) and x < x1 + (y-y1)*(x2-x1)/(y2-y1)
                       for ((x1, y1), (x2, y2)) in edges) % 2

        self.paint(inside, ink)

    def stroke(self, points, width, ink=255):
        for (x1, y1), (x2, y2) in zip(points, points[1:]):
            dx, dy = x2 - x1, y2 - y1
            def near(x, y):
                t = max(0, min(1, ((x-x1)*dx + (y-y1)*dy) / (dx*dx + dy*dy)))
                return (x - x1 - t*dx)**2 + (y - y1 - t*dy)**2 <= (width/2)**2
            self.paint(near, ink)

    def dot(self, x, y, radius, ink=255):
        self.paint(lambda a, b: (a-x)**2 + (b-y)**2 <= radius**2, ink)

    def alpha(self, col, row):
        index = row*2*self.size + col*2
        return round((self.pixels[index] + self.pixels[index+1] +
                      self.pixels[index+self.size] + self.pixels[index+self.size+1]) / 4)


def speaker(g, family, state):
    end = 7.8 if family == "glass" else 8
    g.polygon([(1, 6), (4, 6), (end, 2.4), (end, 13.6), (4, 10), (1, 10)])
    if family == "aqua":
        g.stroke([(2, 6.9), (4.4, 6.9), (7, 4.6)], 0.9, 90)
    if state == "muted":
        if family == "glass":
            g.stroke([(2, 2), (13.5, 14)], 3.2, 0)
            g.stroke([(2, 2), (13.5, 14)], 1.4)
        else:
            g.stroke([(10, 6), (14, 10)], 1.4)
            g.stroke([(10, 10), (14, 6)], 1.4)
        return
    count = ("low", "medium", "high").index(state) + 1
    for i in range(count):
        x = 9 + i*2.25
        reach = 1.1 + i*1.35
        points = [(x + math.cos(a/10)*reach*0.6, 8 + math.sin(a/10)*reach)
                  for a in range(-11, 12)]
        # Keep the outer wave inside its cell.
        g.stroke([(px-i*0.55, py) for px, py in points], 1.25 if family == "glass" else 1)


def envelope(g, family):
    # The original flap spans the same bounding box in every generation.
    rim = [(1.5, 3.5), (14.5, 3.5), (14.5, 12.5), (1.5, 12.5), (1.5, 3.5)]
    flap = [(2, 4), (8, 8.5), (14, 4)]
    if family == "aqua":
        g.polygon(rim)
        g.stroke(flap, 1.1, 0)
        g.stroke([(2, 12), (6, 8.8)], 0.85, 55)
        g.stroke([(10, 8.8), (14, 12)], 0.85, 55)
    else:
        width = 1.5
        g.stroke(rim, width)
        g.stroke(flap, width)


def bell(g, state):
    shell = [(2.7, 11.8), (4, 9.6), (4.3, 6), (5, 4.5), (6.3, 3.5),
             (8, 3), (9.7, 3.5), (11, 4.5), (11.7, 6), (12, 9.6), (13.3, 11.8)]
    g.dot(8, 2.7, 1)
    g.dot(8, 12.6, 1.65)
    g.stroke(shell + [shell[0]], 1.5)
    g.stroke([(6.6, 13.4), (8, 14), (9.4, 13.4)], 1.05)
    if state != "social":
        g.stroke([(1.1, 6.2), (1.5, 4.2), (2.7, 2.8)], 1.15)
        if state == "social-group":
            g.stroke([(14.9, 6.2), (14.5, 4.2), (13.3, 2.8)], 1.15)


def generate():
    width, height = CELL*len(ROLES), CELL*len(FAMILIES)
    bgra = bytearray(b"\xff\xff\xff\x00" * width * height)
    for row, family in enumerate(FAMILIES):
        for col, role in enumerate(ROLES):
            if family in ("harmony", "platinum"):
                tile = pixel_tile(family, role)
                for y in range(CELL):
                    for x in range(CELL):
                        red, green, blue, alpha = PIXEL_PALETTE[tile[y//2][x//2]]
                        offset = ((row*CELL+y)*width + col*CELL+x)*4
                        bgra[offset:offset+4] = bytes((blue, green, red, alpha))
                continue
            g = Glyph()
            if col < 4:
                speaker(g, family, role)
            elif role == "mail":
                envelope(g, family)
            elif family == "glass":
                bell(g, role)
            else:
                continue  # Aqua looks up its bells in the Glass row.
            for y in range(CELL):
                for x in range(CELL):
                    bgra[((row*CELL+y)*width + col*CELL+x)*4+3] = g.alpha(x, y)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(header + bgra)


if __name__ == "__main__":
    generate()
