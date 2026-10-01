"""Reads the frame dumps of `main.py record=FILE:EVERY:COUNT` (128 x 128 RGB565, big endian, back to back) as Pillow images."""
from PIL import Image


def load(path):
    data = open(path, 'rb').read()
    n = 128 * 128 * 2
    frames = []
    for k in range(len(data) // n):
        d = data[k * n:(k + 1) * n]
        px = []
        for i in range(0, n, 2):
            v = d[i] << 8 | d[i + 1]
            px.append((((v >> 11) & 31) * 255 // 31, ((v >> 5) & 63) * 255 // 63, (v & 31) * 255 // 31))
        im = Image.new('RGB', (128, 128))
        im.putdata(px)
        frames.append(im)
    return frames
