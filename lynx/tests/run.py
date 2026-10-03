#!/usr/bin/env python3
"""Screenshot regression tests: build each case with its debug flags, run it headless in Gearlynx and
compare the last frame with tests/ref/<case>.png.

Every case builds with -DHALT=n: the game freezes after n frames, so the screenshot is exact (Gearlynx is
deterministic, so the compare allows only a few different pixels). Usage:
    tests/run.py [--update] [case ...]
"""
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from gearlynx import Gearlynx  # noqa: E402
from PIL import Image, ImageChops  # noqa: E402

BOOT = 400          # emulated frames the boot ROM needs before the game starts (with room to spare)
LIMIT = 8           # different pixels allowed

# name | flags | game frames until the game freezes (-DHALT)
CASES = '''
title||100
c64_entry|AUTOPLAY=1 NOFIRE=1 RULES_C64=1|230
c64_settled|AUTOPLAY=1 NOFIRE=1 RULES_C64=1|800
c64_play|AUTOPLAY=1 RULES_C64=1|900
c64_challenge|AUTOPLAY=1 STAGE=3 RULES_C64=1|500
c64_explode|AUTOPLAY=1 NOFIRE=1 DIEAT=650 RULES_C64=1|675
c64_ready|AUTOPLAY=1 NOFIRE=1 DIEAT=650 RULES_C64=1|770
c64_hard|AUTOPLAY=1 NOFIRE=1 DIFF=8 RULES_C64=1|800
c64_pause|AUTOPLAY=1 NOFIRE=1 PAUSEAT=700 RULES_C64=1|740
c64_capture|AUTOPLAY=1 CAPTURE=1 RULES_C64=1|3000
c64_result|AUTOPLAY=1 FEW=1 DIFF=2 RULES_C64=1|760
c64_chalintro|AUTOPLAY=1 FEW=1 DIFF=2 STAGE=2 RULES_C64=1|920
c64_dual|AUTOPLAY=1 DUAL=1 RULES_C64=1|600
c64_quit|AUTOPLAY=1 QUITAT=700 RULES_C64=1|800
c64_gameover|AUTOPLAY=1 NOFIRE=1 LIVES=1 DIEAT=600 HALTOVER=1 RULES_C64=1|1200
entry|AUTOPLAY=1 NOFIRE=1|300
formation|AUTOPLAY=1 NOFIRE=1|1300
play|AUTOPLAY=1|1500
dive|AUTOPLAY=1 NOFIRE=1|2600
challenge|AUTOPLAY=1 STAGE=3 NOFIRE=1|600
chalresult|AUTOPLAY=1 STAGE=3|1500
explode|AUTOPLAY=1 NOFIRE=1 DIEAT=1100|1125
ready|AUTOPLAY=1 NOFIRE=1 LIVES=9 DIEAT=250|400
pause|AUTOPLAY=1 NOFIRE=1 PAUSEAT=1100|1140
capture|AUTOPLAY=1 CAPTURE=1 GODBEAM=1|1750
quit|AUTOPLAY=1 QUITAT=1100|1200
gameover|AUTOPLAY=1 NOFIRE=1 LIVES=1 HALTOVER=1|2200
'''


def run_case(case):
    name, flags, frames = case
    out = os.path.join(ROOT, 'build', 'test', name)
    shutil.rmtree(out, ignore_errors=True)               # the Makefile does not see changed flags
    defs = ' '.join(f'-D {f}' for f in flags.split()) + f' -D HALT={frames}'
    subprocess.run(['make', '-C', ROOT, f'BUILD=build/test/{name}', f'CAFLAGS={defs}'], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    png = out + '.png'
    with Gearlynx() as g:
        g.load(os.path.join(out, 'galaga.lnx'))
        g.frames(BOOT + frames)
        g.screenshot(png)
    return name, png


def same(a, b):
    ia, ib = Image.open(a).convert('RGB'), Image.open(b).convert('RGB')
    if ia.size != ib.size:
        return False
    diff = ImageChops.difference(ia, ib).convert('L').point(lambda v: 255 if v else 0)
    return diff.histogram()[255] <= LIMIT


def main():
    args = sys.argv[1:]
    update = args[:1] == ['--update']
    names = args[1:] if update else args
    cases = [tuple(c.split('|')) for c in CASES.strip().splitlines()]
    cases = [(n, f, int(h)) for n, f, h in cases if not names or n in names]
    os.makedirs(os.path.join(ROOT, 'build', 'test'), exist_ok=True)
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
