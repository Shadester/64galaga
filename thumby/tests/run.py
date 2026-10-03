#!/usr/bin/env python3
"""Screenshot tests: run the game in the desktop engine with debug arguments, grab the screen after n game ticks
(main.py record=FILE:n:1) and compare it with tests/ref/<case>.png. The game and the engine are deterministic.
Usage: tests/run.py [--update] [case ...]"""
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import rawframes  # noqa: E402
from PIL import Image, ImageChops  # noqa: E402

MP = os.path.join(ROOT, 'build', 'mp-thumby', 'ports', 'unix', 'build-standard', 'micropython')
LIMIT = 4           # different pixels allowed

# name | arguments | game ticks until the screenshot
CASES = '''
title|c64|60
c64_entry|c64 autoplay nofire|230
c64_settled|c64 autoplay nofire|800
c64_play|c64 autoplay|900
c64_challenge|c64 autoplay stage=3|500
c64_explode|c64 autoplay nofire dieat=650|675
c64_ready|c64 autoplay nofire dieat=650|770
c64_hard|c64 autoplay nofire diff=8|800
c64_pause|c64 autoplay nofire pauseat=700|740
c64_capture|c64 autoplay forcecapture|3000
c64_result|c64 autoplay few diff=2|1080
c64_chalintro|c64 autoplay few diff=2 stage=2|1230
c64_dual|c64 autoplay forcecapture|3600
c64_quit|c64 autoplay quitat=700|701
c64_gameover|c64 autoplay nofire lives=1 dieat=600|700
entry|autoplay nofire|300
settled|autoplay nofire|1300
dive|autoplay nofire|2600
play|autoplay|1500
challenge|autoplay stage=3 nofire|600
chalresult|autoplay stage=3|1500
explode|autoplay nofire dieat=1100|1125
ready|autoplay nofire lives=9 dieat=250|400
pause|autoplay nofire pauseat=1100|1140
quit|autoplay quitat=1100|1101
gameover|autoplay nofire lives=1 dieat=250|400
'''


def run_case(case):
    name, args, ticks = case
    raw = os.path.join(ROOT, 'build', 'test', name + '.raw')
    os.makedirs(os.path.dirname(raw), exist_ok=True)
    subprocess.run([MP, '-X', 'heapsize=2617152', 'main.py', 'nosave', *args.split(), f'record={raw}:{ticks}:1'],
                   cwd=os.path.join(ROOT, 'Galaga'), check=True, capture_output=True, timeout=300)
    png = raw[:-4] + '.png'
    rawframes.load(raw)[0].save(png)
    return name, png


def same(a, b):
    ia, ib = Image.open(a).convert('RGB'), Image.open(b).convert('RGB')
    if ia.size != ib.size:
        return False
    return ImageChops.difference(ia, ib).convert('L').point(lambda v: 255 if v else 0).histogram()[255] <= LIMIT


def main():
    args = sys.argv[1:]
    update = args[:1] == ['--update']
    names = args[1:] if update else args
    cases = [tuple(c.split('|')) for c in CASES.strip().splitlines()]
    cases = [(n, a, int(t)) for n, a, t in cases if not names or n in names]
    os.makedirs(os.path.join(HERE, 'ref'), exist_ok=True)
    fail = 0
    with ThreadPoolExecutor(4) as pool:
        for name, png in pool.map(run_case, cases):
            ref = os.path.join(HERE, 'ref', name + '.png')
            if update:
                os.replace(png, ref)
                print('UPDATED', name)
            elif os.path.exists(ref) and same(png, ref):
                print('PASS', name)
            else:
                print('FAIL', name, '(see', png + ')')
                fail = 1
    return fail


sys.exit(main())
