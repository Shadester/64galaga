#!/usr/bin/env python3
"""Compare two screenshots: exit 0 if they differ in at most LIMIT pixels.

The raster interrupt timing jitters by a line for a few sprites from run to
run (a few dozen pixels); a real change moves whole sprites. Without Pillow
only identical files count as equal. Usage: cmp.py a.png b.png [limit]   or   cmp.py --game a.png (exit 0 if it is a game screen)
"""
import sys

LIMIT = 64


def is_game(path):
    """A screenshot of the game, not of BASIC or of nothing: black border, some lit pixels."""
    try:
        from PIL import Image
        im = Image.open(path).convert('RGB')
    except Exception:
        return False
    return im.getpixel((5, 5)) == (0, 0, 0) and im.getbbox() is not None


def main():
    if sys.argv[1] == '--game':
        return 0 if is_game(sys.argv[2]) else 1
    a, b = sys.argv[1:3]
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else LIMIT
    if open(a, 'rb').read() == open(b, 'rb').read():
        return 0
    try:
        from PIL import Image, ImageChops
    except ImportError:
        return 1
    ia, ib = Image.open(a).convert('RGB'), Image.open(b).convert('RGB')
    if ia.size != ib.size:
        return 1
    diff = ImageChops.difference(ia, ib).convert('L').point(lambda v: 255 if v else 0)
    return 0 if diff.histogram()[255] <= limit else 1


sys.exit(main())
