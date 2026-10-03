#!/usr/bin/env python3
"""The Amiga build of psp/game.c with the C64 rules reads its flight paths from a table (no floats; the arcade rules have a table anyway). This test runs the thumby trace program
(thumby/tests/c_trace.c) on the normal build and on the table build, for the four scenarios: the output must be the same.
Usage: python3 tests/test_table.py [ticks]"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
C_TRACE = os.path.join(HERE, '..', '..', 'thumby', 'tests', 'c_trace.c')
TABLE = os.path.join(HERE, '..', 'src', 'paths_table.h')
TICKS = int(sys.argv[1]) if len(sys.argv) > 1 else 15000
C64 = ['-DRULES_C64']
SCENARIOS = {'stage1': C64, 'challenge': C64 + ['-DSTART_STAGE=3'], 'capture': C64 + ['-DFORCECAPTURE'], 'late': C64 + ['-DSTART_STAGE=11']}


def trace(name, extra):
    exe = os.path.join(HERE, '..', 'build', f'trace_{name}_{"table" if extra else "float"}')
    os.makedirs(os.path.dirname(exe), exist_ok=True)
    subprocess.run(['cc', '-O1', '-w', f'-DTICKS={TICKS}', *SCENARIOS[name], *extra, '-o', exe, C_TRACE, '-lm'], check=True)
    return subprocess.run([exe], check=True, capture_output=True, text=True).stdout


for n in SCENARIOS:
    a, b = trace(n, []), trace(n, ['-DGAME_PATHS_TABLE="%s"' % TABLE])
    if a != b:
        la, lb = a.split('\n'), b.split('\n')
        t = next(i for i in range(len(la)) if la[i] != lb[i])
        raise SystemExit(f'FAIL {n}: tick {t} differs')
    print(f'PASS {n}: {TICKS} ticks, the table build equals the float build')
