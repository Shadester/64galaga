#!/usr/bin/env python3
"""Record docs/gameplay.gif: the autoplay build, one headless VICE screenshot per few frames.

The game freezes after -DHALT=n frames (see tests/run.sh), so every GIF frame is a separate
run of the same deterministic game. Needs acme, x64sc and Pillow.
Usage: python3 tools/make_gif.py [last_frame] [step]
"""
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

LAST = int(sys.argv[1]) if len(sys.argv) > 1 else 900
STEP = int(sys.argv[2]) if len(sys.argv) > 2 else 4      # game frames (20 ms each) per GIF frame
OUT = 'build/gif'
CROP = (16, 24, 368, 248)                                 # drop most of the border


def shoot(n):
    prg, png = f'{OUT}/f{n}.prg', f'{OUT}/f{n}.png'
    subprocess.run(['acme', '-f', 'cbm', '-DAUTOPLAY=1', f'-DHALT={n}', '-o', prg, 'src/main.asm'], check=True)
    for _ in range(3):                                   # VICE's autostart occasionally misses
        if os.path.exists(png):
            os.remove(png)
        subprocess.run(['x64sc', '-default', '+sound', '-warp', '-console', '-autostartprgmode', '1',
                        '-VICIIdsize', '-VICIIfilter', '0', '-limitcycles', str(n * 40000 + 20000000),
                        '-exitscreenshot', os.path.abspath(png), '-autostart', prg],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if os.path.exists(png):
            break
    return png


os.makedirs(OUT, exist_ok=True)
frames = list(range(STEP * 5, LAST + 1, STEP))
with ThreadPoolExecutor(6) as pool:
    files = list(pool.map(shoot, frames))
imgs = [Image.open(f).convert('RGB').crop(CROP) for f in files]
imgs[0].save('docs/gameplay.gif', save_all=True, append_images=imgs[1:], duration=STEP * 20,
             loop=0, optimize=True)
print(len(imgs), 'frames,', os.path.getsize('docs/gameplay.gif') // 1024, 'KB')
