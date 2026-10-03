#!/usr/bin/env python3
"""Lockstep test: psp/game.c and game.lua (run by PICO-8, headless: tests/trace.p8) get the same scripted input and must have
the same state after every tick. The C side is thumby/tests/c_trace.c (the arcade scenarios: tests/c_trace_arcade.c, psp/game.c, and game.lua with
arcade=true; the c64-* scenarios: -DRULES_C64 and arcade=false). Usage: python3 tests/test_lockstep.py [ticks] [scenario ...]
PICO8 = path of the pico8 binary (default: PATH, then the macOS app)."""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
C_TRACE = os.path.join(HERE, '..', '..', 'thumby', 'tests', 'c_trace.c')
C_TRACE_ARCADE = os.path.join(HERE, 'c_trace_arcade.c')
PICO8 = os.environ.get('PICO8') or shutil.which('pico8') or '/Applications/PICO-8.app/Contents/MacOS/pico8'
TICKS = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
# name: C flags
SCENARIOS = {   # the arcade rules (the default); c64-*: the rules of the c64 game
    'stage1': [],
    'challenge': ['-DSTART_STAGE=3'],
    'capture': ['-DFORCECAPTURE'],
    'late': ['-DSTART_STAGE=11'],
    's4': ['-DSTART_STAGE=4'],
    'beam': ['-DFORCECAPTURE', '-DBEAMTEST'],
    'c64-stage1': ['-DRULES_C64'],
    'c64-challenge': ['-DRULES_C64', '-DSTART_STAGE=3'],
    'c64-capture': ['-DRULES_C64', '-DFORCECAPTURE'],
    'c64-late': ['-DRULES_C64', '-DSTART_STAGE=11'],
}


def run(name):
    exe = os.path.join(HERE, '..', 'build', 'c_trace_' + name)
    os.makedirs(os.path.dirname(exe), exist_ok=True)
    subprocess.run(['cc', '-O1', '-w', f'-DTICKS={TICKS}', *SCENARIOS[name], '-o', exe, C_TRACE if name.startswith('c64-') else C_TRACE_ARCADE, '-lm'], check=True)
    c_lines = subprocess.run([exe], check=True, capture_output=True, text=True).stdout.split('\n')
    out = subprocess.run([PICO8, '-x', os.path.join(HERE, 'trace.p8'), '-p', f'{name} {TICKS}'], check=True,
                         capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=600).stdout.split('\n')
    lines = [l for l in out if l and not l.startswith('RUNNING')]
    if len(lines) != TICKS:
        raise SystemExit(f'FAIL {name}: {len(lines)} lines from pico8, not {TICKS}: {lines[-1][:300] if lines else ""}')
    states = set()
    for t in range(TICKS):
        states.add(int(lines[t].split(' ', 1)[0]))
        if lines[t] != c_lines[t]:
            m, c = lines[t].split(' '), c_lines[t].split(' ')
            diff = [(i, m[i], c[i]) for i in range(min(len(m), len(c))) if m[i] != c[i]][:4]
            raise SystemExit(f'FAIL {name}: tick {t}: field/lua/c {diff}')
    print(f'PASS {name}: {TICKS} ticks, states seen {sorted(states)}')


for n in (sys.argv[2:] or SCENARIOS):
    run(n)
