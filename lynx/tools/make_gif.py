#!/usr/bin/env python3
"""Record docs/gameplay.gif: the title screen, then the autoplay build (stage intro, fly-in, dives, shooting; the ship cannot be hit: GODMODE).

Runs headless Gearlynx and takes a screenshot every few frames. Needs Pillow.
With --portrait: the portrait ROM, docs/gameplay-portrait.gif (Gearlynx turns the picture back).
Usage: python3 tools/make_gif.py [--portrait] [game_frames] [step]
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
from gearlynx import Gearlynx  # noqa: E402
from PIL import Image  # noqa: E402

PORTRAIT = '--portrait' in sys.argv
if PORTRAIT:
    sys.argv.remove('--portrait')
LAST = int(sys.argv[1]) if len(sys.argv) > 1 else 1100       # game frames of the autoplay part
STEP = int(sys.argv[2]) if len(sys.argv) > 2 else 4          # game frames (20 ms each) per GIF frame
TITLE = 120                                                  # game frames of the title screen
SCALE = 3


def build(name, flags):
    out = f'build/gif/{"p_" if PORTRAIT else ""}{name}'
    defs = ' '.join(f'-D {f}' for f in (flags + (' PORTRAIT=1' if PORTRAIT else '')).split())
    subprocess.run(['make', '-C', ROOT, f'BUILD={out}', f'CAFLAGS={defs}'], check=True, stdout=subprocess.DEVNULL)
    return os.path.join(ROOT, out)


def dispadr(g):
    regs = json.loads(g.tool('get_mikey_registers')[0]['text'])['registers']
    return int(next(r[2] for r in regs if r[0] == 'DISPADR')[:2], 16)


def record(out, frames):
    """Frames from the moment the game takes over the display (the boot ROM shows its logo before)."""
    imgs = []
    with Gearlynx() as g:
        g.load(os.path.join(out, 'galaga.lnx'))
        while dispadr(g) not in (0xa0, 0xc0):                # the game's two frame buffers
            g.frames(1)
        for _ in range(frames // STEP):
            g.frames(STEP)
            g.screenshot('build/gif/shot.png')
            imgs.append(Image.open('build/gif/shot.png').convert('RGB').copy())
    return imgs


os.makedirs(os.path.join(ROOT, 'build', 'gif'), exist_ok=True)
os.chdir(ROOT)
imgs = record(build('title', ''), TITLE) + record(build('play', 'AUTOPLAY=1 GODMODE=1'), LAST)
imgs = [im.resize((im.width * SCALE, im.height * SCALE), Image.NEAREST) for im in imgs]
os.makedirs('docs', exist_ok=True)
OUT = 'docs/gameplay-portrait.gif' if PORTRAIT else 'docs/gameplay.gif'
imgs[0].save(OUT, save_all=True, append_images=imgs[1:], duration=STEP * 20, loop=0, optimize=True)
print(len(imgs), 'frames,', os.path.getsize(OUT) // 1024, 'KB')
