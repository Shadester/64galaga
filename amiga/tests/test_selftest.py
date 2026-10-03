#!/usr/bin/env python3
"""The rules on the 68000. For each scenario: the hash of the scripted game (src/selftest.h) on this Mac, then the same on an
Amiga build that runs in vAmigaWeb: the screen turns green if the hashes are the same, red if not.
Usage: python3 tests/test_selftest.py [ticks] [scenario ...]. Needs m68k-elf-gcc, cc, playwright (see tests/vamiga.py)."""
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
from vamiga import Session  # noqa: E402

TICKS = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 3000
ARCADE = ['-DRULES_ARCADE'] if 'arcade' in sys.argv[1:] else []     # the arcade rules instead of the C64 rules
SCENARIOS = {'stage1': [], 'challenge': ['-DSTART_STAGE=3'], 'capture': ['-DFORCECAPTURE'], 'late': ['-DSTART_STAGE=11']}
NAMES = [a for a in sys.argv[1:] if a in SCENARIOS] or list(SCENARIOS)


def run(name):
    flags = SCENARIOS[name] + ARCADE
    build = os.path.join(ROOT, 'build', 'selftest_' + name)
    shutil.rmtree(build, ignore_errors=True)                  # make does not see a change of the flags
    os.makedirs(build, exist_ok=True)
    exe = os.path.join(build, 'native')
    subprocess.run(['cc', '-O1', '-w', f'-DTICKS={TICKS}', *flags, '-I', os.path.join(ROOT, '..', 'psp'), '-I', os.path.join(ROOT, 'src'),
                    '-o', exe, os.path.join(HERE, 'selftest_native.c')], check=True)
    h = subprocess.run([exe], check=True, capture_output=True, text=True).stdout.strip()
    extra = ' '.join(flags + [f'-DSELFTEST={TICKS}', f'-DSELFTEST_EXPECT=0x{h}u'])
    subprocess.run(['make', '-C', ROOT, f'BUILD=build/selftest_{name}', f'EXTRA_CFLAGS={extra}'], check=True, capture_output=True)
    with Session(os.path.join(build, 'galaga.adf'), warp=100000) as s:
        r = s.wait_pixel({'pass': (0, 240, 0), 'fail': (240, 0, 0)}, timeout=600)
    return name, h, r


with ThreadPoolExecutor(len(NAMES)) as ex:
    results = list(ex.map(run, NAMES))
bad = 0
for name, h, r in results:
    print(f'{"PASS" if r == "pass" else "FAIL"} {name}: {TICKS} ticks, hash {h}, the 68000 says: {r}')
    bad += r != 'pass'
sys.exit(1 if bad else 0)
