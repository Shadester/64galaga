#!/usr/bin/env python3
"""Record docs/gameplay.gif from the desktop engine: the title screen, then the autoplay run (stage intro, fly-in,
shooting, a tractor beam). One screenshot every 4 game ticks (the GIF plays at 12.5 frames/s).
Usage: python3 tools/make_gif.py [game_ticks]   (about 1 minute)"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import rawframes  # noqa: E402

MP = os.path.join(ROOT, 'build', 'mp-thumby', 'ports', 'unix', 'build-standard', 'micropython')
TICKS = int(sys.argv[1]) if len(sys.argv) > 1 else 1100
EVERY = 4
SCALE = 2


def record(args, ticks):
    raw = os.path.join(ROOT, 'build', 'gif.raw')
    os.makedirs(os.path.dirname(raw), exist_ok=True)
    subprocess.run([MP, '-X', 'heapsize=2617152', 'main.py', 'nosave', *args, f'record={raw}:{EVERY}:{ticks // EVERY}'],
                   cwd=os.path.join(ROOT, 'Galaga'), check=True, capture_output=True)
    return rawframes.load(raw)


frames = record([], 120) + record(['autoplay'], TICKS)
frames = [im.resize((im.width * SCALE, im.height * SCALE)) for im in frames]
# one palette of 64 colours for all frames (title and game): a small file, and no colour flicker between frames
from PIL import Image  # noqa: E402
sample = Image.new('RGB', (frames[0].width, frames[0].height * 4))
for k, i in enumerate((0, len(frames) // 4, len(frames) // 2, len(frames) - 1)):
    sample.paste(frames[i], (0, k * frames[0].height))
pal = sample.quantize(64, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
frames = [im.quantize(palette=pal, dither=Image.Dither.NONE) for im in frames]
os.makedirs(os.path.join(ROOT, 'docs'), exist_ok=True)
out = os.path.join(ROOT, 'docs', 'gameplay.gif')
frames[0].save(out, save_all=True, append_images=frames[1:], duration=EVERY * 20, loop=0, optimize=True)
print(len(frames), 'frames,', os.path.getsize(out) // 1024, 'KB')
