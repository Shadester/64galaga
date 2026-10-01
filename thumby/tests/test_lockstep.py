#!/usr/bin/env python3
"""Lockstep test: psp/game.c and Galaga/game.py get the same scripted input and must have the same state after every tick.
Usage: python3 tests/test_lockstep.py [ticks]"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'Galaga'))
import game as G  # noqa: E402

TICKS = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
# name: (C flags, python setup)
SCENARIOS = {
    'stage1': ([], {}),
    'challenge': (['-DSTART_STAGE=3'], {'start_stage_no': 3}),
    'capture': (['-DFORCECAPTURE'], {'force_capture': True}),
    'late': (['-DSTART_STAGE=11'], {'start_stage_no': 11}),
}


def script(g, t, inp, force_capture):
    inp.left = inp.right = inp.fire = inp.pause = inp.quit = 0
    inp.fire = 1 if t % 7 < 2 else 0
    inp.left = 1 if (t // 90) % 2 else 0
    inp.right = 0 if inp.left else 1
    if force_capture:
        if g.state == G.S_PLAY or g.state == G.S_RESULT:
            inp.fire = 0
        if g.cap in (G.C_BEAM, G.C_CARRY, G.C_DIVING):
            bx = g.al[g.capBoss].x
            inp.left = 1 if g.px > bx + 2 else 0
            inp.right = 1 if g.px < bx - 2 else 0
            if g.cap == G.C_CARRY:
                inp.fire = 1 if (t & 3) < 2 else 0
    if t % 1500 == 1499 or t % 1500 == 1503:
        inp.pause = 1


def line(g):
    a = [g.state, g.paused, g.stateTimer, g.frame, g.score, g.hi, g.lives, g.stage, g.diff, g.nextBonus,
         g.challenge, g.chalVal, g.chalHits, g.chalTimer, g.shots, g.hits, g.px, g.py, g.invuln, g.dual,
         g.dyingQuiet, g.formDx, g.formDir, g.formTimer, g.entering, g.diveTimer, g.cap, g.capBoss, g.beamLen,
         g.beamAcc, g.beamTimer, g.rx, g.ry, g.snd]
    s = ' '.join(str(int(v)) for v in a)
    for x in g.al:
        s += ' %d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d' % (x.st, x.x, x.y, x.hp, x.timer, x.dir, x.esc, x.capdive, x.fired, x.pstep, x.ent, x.dly)
    for b in g.ps:
        s += ' %d,%d,%d' % (b.x, b.y, b.act)
    for b in g.eb:
        s += ' %d,%d,%d,%d' % (b.x, b.y, b.act, b.dx)
    return s


def run(name):
    flags, setup = SCENARIOS[name]
    exe = os.path.join(HERE, '..', 'build', 'c_trace_' + name)
    os.makedirs(os.path.dirname(exe), exist_ok=True)
    subprocess.run(['cc', '-O1', '-w', f'-DTICKS={TICKS}', *flags, '-o', exe, os.path.join(HERE, 'c_trace.c'), '-lm'], check=True)
    c_lines = subprocess.run([exe], check=True, capture_output=True, text=True).stdout.split('\n')
    g = G.Game(0)
    for k, v in setup.items():
        setattr(g, k, v)
    inp = G.Input()
    states = set()
    for t in range(TICKS):
        script(g, t, inp, bool(setup.get('force_capture')))
        g.tick(inp)
        states.add(g.state)
        mine = line(g)
        g.snd = g.saveReq = 0
        if mine != c_lines[t]:
            m, c = mine.split(' '), c_lines[t].split(' ')
            diff = [(i, m[i], c[i]) for i in range(min(len(m), len(c))) if m[i] != c[i]][:4]
            raise SystemExit(f'FAIL {name}: tick {t}: field/python/c {diff}')
    print(f'PASS {name}: {TICKS} ticks, states seen {sorted(states)}')


for n in SCENARIOS:
    run(n)
