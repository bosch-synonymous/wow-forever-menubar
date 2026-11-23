"""Generate Menubar's original brown-and-gold eyes icon using only the stdlib.

The square plaque uses original geometry and a procedural brown texture. Its
eyes share the actual High Definition widget sampler, dimensions and blue
palette. No imported game artwork, image, font or logo is read.
Run from anywhere; outputs are the 128px RGBA addon TGA and the 400px RGBA
project PNG at assets/Menubar.png. The PNG is excluded from the player package.
"""
import math
from pathlib import Path
import runpy
import struct
import zlib

SIZE = 128
SAMPLES = 4
ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'src/menubar-core/Media/Menubar.tga'
PROJECT_OUTPUT = ROOT / 'assets/Menubar.png'
PROJECT_SIZE = 400
EYE_FACTOR = 3.4
# Gaze uses the widget's local coordinates: negative x looks left, positive y up.
GAZE_OFFSET = (-1.5, 0.75)
BLUE = (0.16, 0.49, 0.94)
# Loading the original sampler under a non-main name never generates or changes
# the widget's runtime assets. One renderer keeps the two eye styles consistent.
EYE_SAMPLE = runpy.run_path(
    str(ROOT / 'tools/widgets/eyes/generate_assets.py'),
    run_name='menubar_icon_hd_eye_sampler',
)['sample']


def rounded_box(x, y, left, top, right, bottom, radius):
    if not (left <= x < right and top <= y < bottom):
        return False
    near_x = max(left + radius, min(right - radius, x))
    near_y = max(top + radius, min(bottom - radius, y))
    return (x - near_x) ** 2 + (y - near_y) ** 2 <= radius ** 2


def texture(x, y):
    # Low-contrast grain and broad irregular bands are generated from coordinates;
    # the deterministic integer noise has no dependency on a random seed or file.
    cell = ((int(x) * 374761393) ^ (int(y) * 668265263)) & 0xffffffff
    cell = ((cell ^ (cell >> 13)) * 1274126177) & 0xffffffff
    grain = ((cell ^ (cell >> 16)) & 255) / 255 - 0.5
    bands = math.sin(x * 0.13 + math.sin(y * 0.17) * 1.8) * 1.8
    bands += math.sin(x * 0.43 + y * 0.37) * 0.8 + grain * 2.2
    warmth = 2.5 * (1 - y / SIZE)
    return 29 + bands + warmth, 25 + bands * 0.85 + warmth * 0.6, 20 + bands * 0.65


def eye_layer(background, name, x, y, center_x, center_y, width, height, tint):
    u, v = (x - center_x) * 2 / width, (y - center_y) * 2 / height
    if abs(u) > 1 or abs(v) > 1:
        return background
    shade, alpha = EYE_SAMPLE(name, u, v)
    # Match the widget generator's eight-bit texture channels, then its vertex
    # colour and normal alpha blend. The Iris sampler supplies its own pupil.
    shade = round(shade * 255) / 255
    alpha = round(alpha * 255) / 255
    return tuple(background[index] * (1 - alpha) + tint[index] * shade * 255 * alpha
                 for index in range(3))


def eyes(background, x, y):
    factor = EYE_FACTOR
    for offset in (-8, 8):
        center_x, center_y = SIZE / 2 + offset * factor, SIZE / 2
        background = eye_layer(background, 'Orb', x, y, center_x, center_y,
                               14 * factor, 16 * factor, (1, 1, 1))
        iris_x = center_x + GAZE_OFFSET[0] * factor
        iris_y = center_y - GAZE_OFFSET[1] * factor
        background = eye_layer(background, 'Iris', x, y, iris_x, iris_y,
                               5.2 * factor, 6 * factor, BLUE)
        # The glint follows the iris at (-1, +1) in WoW's y-up space.
        background = eye_layer(background, 'Glint', x, y, iris_x - factor, iris_y - factor,
                               2 * factor, 2 * factor, (1, 1, 1))
    return background


def sample(x, y):
    if not rounded_box(x, y, 3, 3, 125, 125, 11):
        return None
    color = 12, 11, 9
    if rounded_box(x, y, 4, 4, 124, 124, 10):
        # Original thin bronze bevel: bright upper lip and a darker lower edge.
        light = 1 - (y - 4) / 120
        color = 96 + light * 79, 65 + light * 71, 29 + light * 39
    if rounded_box(x, y, 6, 6, 122, 122, 8):
        color = 34, 25, 15
    if rounded_box(x, y, 7, 7, 121, 121, 7):
        color = 91, 66, 33
    if rounded_box(x, y, 8, 8, 120, 120, 6):
        color = texture(x, y)
    color = eyes(color, x, y)
    return tuple(max(0, min(255, round(channel))) for channel in color)


def render(size, samples):
    scale = SIZE / size
    pixels = bytearray()
    for y in range(size):
        for x in range(size):
            colors = []
            for sub_y in range(samples):
                for sub_x in range(samples):
                    color = sample((x + (sub_x + 0.5) / samples) * scale,
                                   (y + (sub_y + 0.5) / samples) * scale)
                    if color is not None:
                        colors.append(color)
            if colors:
                channels = (round(sum(color[index] for color in colors) / len(colors)) for index in range(3))
                pixels.extend((*channels, round(len(colors) * 255 / samples ** 2)))
            else:
                pixels.extend((0, 0, 0, 0))
    return pixels


def generate():
    # Top-left origin, eight alpha bits, uncompressed true-color BGRA pixels.
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    rgba = render(SIZE, SAMPLES)
    pixels = bytearray()
    for index in range(0, len(rgba), 4):
        red, green, blue, alpha = rgba[index:index + 4]
        pixels.extend((blue, green, red, alpha))
    return header + pixels


def generate_png():
    def chunk(kind, data):
        checksum = zlib.crc32(kind + data) & 0xffffffff
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', checksum)

    # Render directly at the project size, rather than enlarging the addon TGA.
    pixels = render(PROJECT_SIZE, 2)
    stride = PROJECT_SIZE * 4
    rows = b''.join(b'\0' + pixels[row * stride:(row + 1) * stride] for row in range(PROJECT_SIZE))
    header = struct.pack('>IIBBBBB', PROJECT_SIZE, PROJECT_SIZE, 8, 6, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header)
            + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))


if __name__ == '__main__':
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(generate())
    PROJECT_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    PROJECT_OUTPUT.write_bytes(generate_png())
    print(f'Generated {SIZE}x{SIZE} original Menubar icon: {OUTPUT}')
    print(f'Generated {PROJECT_SIZE}x{PROJECT_SIZE} original project icon: {PROJECT_OUTPUT}')
