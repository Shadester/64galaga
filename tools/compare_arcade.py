#!/usr/bin/env python3
"""Compare the dives of psp/game.c (-DRULES_ARCADE) with the arcade model, launch by launch.

    ARCADE_REF=/path/to/cool8-cpu python3 tools/compare_arcade.py [stage ...]     (default: 1 2 4 5 8 9 12)

Our game runs with an invulnerable ship that does not shoot, so nothing but the scheduler decides who dives. The model runs the same
stage (rank 3, ship fixed in the middle). Both print the first launches: time in arcade frames (60 Hz) from the end of the entry,
the kind and the formation slot. The test fails when the kind or slot of one of the first LAUNCHES differs, or when the time
differs by more than TOLERANCE frames. The time can differ by a little: the scheduler looks at the clock every 16 frames, and the
entry of the stage ends at another phase in our game than in the model.
"""
import os
import subprocess
import sys
import tempfile

LAUNCHES, TOLERANCE, TICKS = 10, 45, 4200
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
ref = os.environ.get('ARCADE_REF') or sys.exit('set ARCADE_REF to a checkout of tomcoolpxl/cool8-cpu')
sys.path.insert(0, os.path.join(ref, 'tools'))
sys.dont_write_bytecode = True
import galaga_dives as gd          # noqa: E402

SLOT = {o: i for i, o in enumerate(list(range(0x30, 0x38, 2)) + list(range(0x40, 0x60, 2)) + list(range(0x08, 0x30, 2)))}
kind = lambda i: 'boss' if i < 4 else 'red' if i < 20 else 'bee'


def ours(stage, tmp):
    game = open(os.path.join(ROOT, 'psp', 'game.c')).read()
    game = game.replace('#include <stdlib.h>', '#include <stdlib.h>\n#include <stdio.h>', 1)
    game = game.replace('static void start_dive(Game *g, int i, int capture, int peel) {\n    Alien *a = &g->al[i];',
                        'static void start_dive(Game *g, int i, int capture, int peel) {\n    Alien *a = &g->al[i];\n'
                        '    fprintf(stderr, "L %d %d\\n", g->af, i);', 1)
    game = game.replace('    ++g->af;\n', '    ++g->af;\n    { static int seen; if (!g->entering && !seen) { seen = 1; fprintf(stderr, "S %d\\n", g->af); } }\n', 1)
    trace = open(os.path.join(ROOT, 'thumby', 'tests', 'c_trace.c')).read()
    trace = trace.replace('#include "../../psp/game.c"', '#include "game.c"')
    trace = trace.replace('in->fire = (t % 7) < 2;', 'in->fire = g->state == S_TITLE && (t & 1);')
    trace = trace.replace('in->pause = 1;', 'in->pause = 0;').replace('script(&g, t, &in);', 'script(&g, t, &in); g.invuln = 100;')
    for name, text in (('game.c', game), ('trace.c', trace)):
        open(os.path.join(tmp, name), 'w').write(text)
    for h in ('game.h', 'arcade_data.h'):
        open(os.path.join(tmp, h), 'w').write(open(os.path.join(ROOT, 'psp', h)).read())
    exe = os.path.join(tmp, 'trace')
    subprocess.run(['cc', '-w', '-O1', '-DRULES_ARCADE', '-DSTART_STAGE=%d' % stage, '-DTICKS=%d' % TICKS, '-o', exe,
                    os.path.join(tmp, 'trace.c'), '-lm'], check=True)
    err = subprocess.run([exe], capture_output=True, text=True, check=True).stderr
    start, out = None, []
    for line in err.splitlines():
        p = line.split()
        if p[0] == 'S' and start is None:
            start = int(p[1])
        elif p[0] == 'L':
            out.append((int(p[1]) - start, int(p[2])))
    return out


def model(stage):
    rec = gd.simulate_attack(stage, frames=2400, fighter_x_fn=lambda t: 0x7A)
    return [(e['t'], SLOT[e['obj']]) for e in rec.machine.events if e['kind'] == 'launch' and e['t'] >= 0 and e['obj'] in SLOT]


def main():
    stages = [int(a) for a in sys.argv[1:]] or [1, 2, 4, 5, 8, 9, 12]
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        for st in stages:
            a, b = ours(st, tmp)[:LAUNCHES], model(st)[:LAUNCHES]
            ok = len(a) == len(b) and all(x[1] == y[1] and abs(x[0] - y[0]) <= TOLERANCE for x, y in zip(a, b))
            bad += not ok
            print('stage %2d %s' % (st, 'ok' if ok else 'DIFFERENT'))
            if not ok or '-v' in os.environ.get('ARCADE_VERBOSE', ''):
                for x, y in zip(a, b):
                    print('    ours %5d %-4s %2d   model %5d %-4s %2d' % (x[0], kind(x[1]), x[1], y[0], kind(y[1]), y[1]))
    sys.exit(1 if bad else 0)


main()
