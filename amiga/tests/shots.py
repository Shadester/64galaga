#!/usr/bin/env python3
"""Screenshot tests: each case builds the game with -DAUTOPLAY (the game plays itself) and -DHALT=n (it freezes after n ticks, so the
picture is exact), runs it in vAmigaWeb (tests/vamiga.py) and compares the screen with tests/ref/<case>.png.
Usage: python3 tests/shots.py [--update] [case ...]   (--update: write the references; look at them before you commit them)"""
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

from PIL import Image, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
from vamiga import Session  # noqa: E402

LIMIT = 50                      # different pixels allowed
AUTO = '-DAUTOPLAY -DTITLE_HOLD=0'      # no wait on the title screen: the ticks count from the start
CAPTURE = AUTO + ' -DFORCECAPTURE'
# name: (flags, ticks until the game freezes; 0 = no freeze)
CASES = {
    'title': ('', 0),
    'entry': (AUTO, 230),
    'play': (AUTO, 900),
    'challenge': (AUTO + ' -DSTART_STAGE=3', 500),
    'chalresult': (AUTO + ' -DSTART_STAGE=3', 700),
    'beam': (CAPTURE, 846),
    'captured': (CAPTURE, 950),
    'dual': (CAPTURE, 2700),
}
update = '--update' in sys.argv
names = [a for a in sys.argv[1:] if a in CASES] or list(CASES)


def run(name):
    flags, halt = CASES[name]
    build = os.path.join('build', 'shots_' + name)
    extra = flags + (f' -DHALT={halt}' if halt else '')
    shutil.rmtree(os.path.join(ROOT, build), ignore_errors=True)      # make does not see a change of the flags
    subprocess.run(['make', '-C', ROOT, f'BUILD={build}', f'EXTRA_CFLAGS={extra}'], check=True, capture_output=True)
    out = os.path.join(ROOT, build, 'shot.png')
    with Session(os.path.join(ROOT, build, 'galaga.adf'), warp=100000) as s:
        s.settle(out)                           # the boot of the AROS ROM, the game, and until the game stands still
    ref = os.path.join(HERE, 'ref', name + '.png')
    if update:
        os.makedirs(os.path.dirname(ref), exist_ok=True)
        Image.open(out).convert('RGB').save(ref)
        return name, 'UPDATED'
    if not os.path.exists(ref):
        return name, 'FAIL (no reference)'
    d = ImageChops.difference(Image.open(out).convert('RGB'), Image.open(ref).convert('RGB')).convert('L').point(lambda v: 255 if v > 24 else 0)
    n = sum(1 for v in (d.get_flattened_data() if hasattr(d, 'get_flattened_data') else d.getdata()) if v)
    return name, 'ok' if n <= LIMIT else f'FAIL ({n} pixels differ, see {out})'


with ThreadPoolExecutor(4) as ex:
    results = list(ex.map(run, names))
for name, r in results:
    print(f'{name}: {r}')
sys.exit(1 if any(r.startswith('FAIL') for _, r in results) else 0)
