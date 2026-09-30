#!/usr/bin/env python3
"""Record docs/gameplay.gif: the title screen, then the autoplay build, one headless VICE screenshot per few frames.

The game freezes after -DHALT=n frames (see tests/run.sh), so every GIF frame is a separate
run of the same deterministic game. Needs acme, x64sc and Pillow.
Usage: python3 tools/make_gif.py [last_frame] [step]   (the title part is TITLE_FRAMES long)
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
TITLE_FRAMES = 200                                        # game frames of the title screen (the stars twinkle)


def shoot(job):
    play, n = job                                        # play: autoplay build, else the title screen
    prg, png = f'{OUT}/{"p" if play else "t"}{n}.prg', f'{OUT}/{"p" if play else "t"}{n}.png'
    flags = ['-DAUTOPLAY=1'] if play else []
    subprocess.run(['acme', '-f', 'cbm', *flags, f'-DHALT={n}', '-o', prg, 'src/main.asm'], check=True)
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
frames = [(False, n) for n in range(STEP * 2, TITLE_FRAMES + 1, STEP)] + \
         [(True, n) for n in range(STEP * 5, LAST + 1, STEP)]
with ThreadPoolExecutor(6) as pool:
    files = list(pool.map(shoot, frames))
imgs = [Image.open(f).convert('RGB').crop(CROP) for f in files]
imgs[0].save('docs/gameplay.gif', save_all=True, append_images=imgs[1:], duration=STEP * 20,
             loop=0, optimize=True)
print(len(imgs), 'frames,', os.path.getsize('docs/gameplay.gif') // 1024, 'KB')
