#!/usr/bin/env python3
"""Lockstep test: psp/game.c (through ../thumby/tests/c_trace.c) and src/game.rs (examples/trace.rs) get the same scripted input and must have
the same state after every tick. Usage: python3 tests/test_lockstep.py [ticks] [scenario ...]   (the arcade rules, ../../ARCADE.md)"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TUI = os.path.join(HERE, '..')
TICKS = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 3000
# name: (C flags, start stage, force capture, god)
SCENARIOS = {
    'stage1': ([], 0, 0, 0),
    'challenge': (['-DSTART_STAGE=3'], 3, 0, 0),
    'capture': (['-DFORCECAPTURE'], 0, 1, 0),
    'late': (['-DSTART_STAGE=11'], 11, 0, 0),
    'stage4': (['-DSTART_STAGE=4'], 4, 0, 0),
    # the ship cannot be hit (except under a beam): long games with captures, results and later stages
    'god': (['-DGODMODE'], 0, 0, 1),
    'godcapture': (['-DGODMODE', '-DFORCECAPTURE'], 0, 1, 1),
    'godstage12': (['-DGODMODE', '-DSTART_STAGE=12'], 12, 0, 1),
}
NAMES = [a for a in sys.argv[1:] if a in SCENARIOS] or list(SCENARIOS)

subprocess.run(['cargo', 'build', '--release', '--example', 'trace', '-q'], cwd=TUI, check=True)
RUST = os.path.join(TUI, 'target', 'release', 'examples', 'trace')
bad = 0
for name in NAMES:
    flags, stage, force, god = SCENARIOS[name]
    exe = os.path.join(TUI, 'target', 'c_trace_' + name)
    subprocess.run(['cc', '-O1', '-w', f'-DTICKS={TICKS}', *flags, '-o', exe, os.path.join(HERE, '..', '..', 'thumby', 'tests', 'c_trace.c'), '-lm'], check=True)
    c_lines = subprocess.run([exe], check=True, capture_output=True, text=True).stdout.split('\n')
    r_lines = subprocess.run([RUST, str(TICKS), str(stage), str(force), str(god)], check=True, capture_output=True, text=True).stdout.split('\n')
    states = set()
    for t in range(TICKS):
        if c_lines[t] != r_lines[t]:
            c, r = c_lines[t].split(' '), r_lines[t].split(' ')
            diff = [(i, r[i], c[i]) for i in range(min(len(c), len(r))) if c[i] != r[i]][:4]
            print(f'FAIL {name}: tick {t}: field/rust/c {diff}')
            bad += 1
            break
        states.add(int(c_lines[t].split(' ')[0]))
    else:
        print(f'PASS {name}: {TICKS} ticks, states seen {sorted(states)}')
sys.exit(1 if bad else 0)
