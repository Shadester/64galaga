#!/usr/bin/env python3
"""Compare two screenshots: exit 0 if they differ in at most LIMIT pixels.

The raster interrupt timing jitters by a line for a few sprites from run to
run (a few dozen pixels); a real change moves whole sprites. Without Pillow
only identical files count as equal. Usage: cmp.py a.png b.png [limit]
"""
import sys

LIMIT = 64


def main():
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
