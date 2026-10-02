#!/usr/bin/env python3
"""Record docs/gameplay.gif: the title screen, then the autoplay build (stage intro, fly-in, a tractor beam and a capture).
It runs the game in vAmigaWeb in real time (see tests/vamiga.py) and copies the emulator canvas 20 times a second (the empty copies
are dropped, and every picture is shown for as long as it was on the screen).
Usage: python3 tools/make_gif.py [seconds]   (about 1 minute: the boot of the AROS ROM takes 30 seconds)"""
import base64
import io
import os
import subprocess
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
sys.path.insert(0, os.path.join(ROOT, 'tests'))
from vamiga import Session  # noqa: E402

SECONDS = int(sys.argv[1]) if len(sys.argv) > 1 else 32
OUT = (360, 288)
# the canvas of vAmigaWeb shows 4 canvas pixels for one Amiga pixel across and 2 for one down; the screen starts at (28, 16)
CROP = (28, 16, 28 + 320 * 4, 16 + 256 * 2)

subprocess.run(['make', '-C', ROOT, 'BUILD=build/gif', 'EXTRA_CFLAGS=-DAUTOPLAY -DFORCECAPTURE'], check=True, capture_output=True)


def logo_pixels(im):
    im = im.resize((334, 133), Image.NEAREST)                # (no blending: the colours stay pure)
    return sum(1 for p in (im.get_flattened_data() if hasattr(im, 'get_flattened_data') else im.getdata()) if p[0] > 200 and p[1] > 120 and p[2] < 80)


def decode(d):
    return Image.open(io.BytesIO(base64.b64decode(d.split(',')[1]))).convert('RGB')


def is_black(im):                                          # the emulator does not draw in every callback: the canvas is empty then
    return max(max(p) for p in (im.resize((67, 27)).get_flattened_data() if hasattr(im, 'get_flattened_data') else im.resize((67, 27)).getdata())) < 30


with Session(os.path.join(ROOT, 'build', 'gif', 'galaga.adf')) as s:
    pg = s.page
    # the canvas can only be read inside a frame callback that runs after the emulator's own: install ours when the emulator runs.
    # It records 20 pictures a second from then on, and the cut is made afterwards
    pg.wait_for_timeout(5000)
    pg.evaluate("""()=>{window._f=[];window._n=0;
      function step(){window._n++; if(window._n%3==0){const c=document.querySelector('canvas'); if(c) window._f.push([performance.now(), c.toDataURL('image/png')]);} requestAnimationFrame(step);}
      requestAnimationFrame(step);}""")
    start, checked = None, 0
    for _ in range(300):                                    # until SECONDS seconds after the title screen showed (the yellow of the logo)
        pg.wait_for_timeout(500)
        n = pg.evaluate('window._f.length')
        while start is None and checked < n:                # every picture is looked at once
            if logo_pixels(decode(pg.evaluate(f'window._f[{checked}][1]'))) > 120:
                start = checked
            checked += 1
        if start is not None and n >= start + SECONDS * 20:
            break
    frames, times = [], []
    last = start + SECONDS * 20
    for i in range(start, last, 20):
        for t, d in pg.evaluate(f'window._f.slice({i}, {min(i + 20, last)})'):
            im = decode(d)
            if not is_black(im):
                frames.append(im.crop(CROP).resize(OUT, Image.LANCZOS))
                times.append(t)
durations = [max(20, min(200, round(b - a, -1))) for a, b in zip(times, times[1:])] + [60]      # each frame is shown until the next one
pal = frames[len(frames) // 2].quantize(48, method=Image.Quantize.MEDIANCUT)
frames = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
frames[0].save(os.path.join(ROOT, 'docs', 'gameplay.gif'), save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True)
print(len(frames), 'frames')
