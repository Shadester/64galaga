#!/usr/bin/env python3
"""Compare a 6502 game (Lynx, later the C64) with the C reference psp/game.c at checkpoints.

    python3 tools/compare_6502.py lynx SCENARIO [SCENARIO ...]      ('list' prints the scenarios)

The same scripted game (the AUTOPLAY input of the 6502 game, copied into a small C driver) runs in the C reference and in the ROM.
The ROM runs in Gearlynx (headless, lynx/tools/gearlynx.py); at each checkpoint (a game tick) the state is read from memory by label
(`build/trace_<scenario>/galaga.lbl`) and compared with the state of the C game after the same tick: game state, lives, score, ship
position, and for every alien its state and (when it is on the screen) its position. The arcade rules have no random numbers, so the
games must stay equal; the old C64 rules use a random number generator that is not the one of C: only the fly-in can be compared there.
Needs the Lynx boot ROM (see lynx/CLAUDE.md), cc65 and Gearlynx."""
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
sys.path.insert(0, os.path.join(ROOT, 'lynx', 'tools'))

# name: (ROM flags, C flags, ticks to compare at, what is compared)
SCENARIOS = {
    # A check of the tool itself: the start of the game, the intro and the ship are the same in the C64 rules (checked up to tick 130; from
    # about tick 200 the aliens are on other flight paths than in C: the C64 paths.asm and the float paths of psp/game.c are not the same)
    'c64start': (['AUTOPLAY=1', 'NOFIRE=1'], ['-DRULES_C64'], [20, 60, 90, 130], 'start, intro and ship of the C64 rules'),
}

C_DRIVER = r'''
#include <stdio.h>
#include "game.c"
#ifndef TICKS
#define TICKS 3000
#endif
int main(void) {
    static Game g; Input in; int t, i;
    paths_init(); game_init(&g, 0);
    for (t = 0; t < TICKS; ++t) {
        int f = (g.frame + 1) & 255;                 /* the 6502 reads the joystick after it has counted the frame */
        memset(&in, 0, sizeof in);
        in.left = (f & 0x80) != 0; in.right = !in.left;
        in.fire = (f & 8) == 0;
#ifdef NOFIRE
        if (g.state == S_PLAY) in.fire = 0;
#endif
        if (g.state == S_TITLE) in.fire = t + 1 == START;   /* the 6502 title needs a release and a press: the game starts at the tick the ROM started */
        game_tick(&g, &in);
        printf("%d %d %d %d %d %d %d", t + 1, g.state, g.score, g.lives, g.stage, g.px, g.py);
        for (i = 0; i < NAL; ++i) printf(" %d,%d,%d,%d", g.al[i].st, g.al[i].x, g.al[i].y, g.al[i].ent);
        printf("\n");
        g.snd = g.saveReq = 0;
    }
    return 0;
}
'''


def c_trace(cflags, ticks, nofire, start):
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, 'driver.c')
        open(src, 'w').write(C_DRIVER)
        exe = os.path.join(tmp, 'driver')
        subprocess.run(['cc', '-O1', '-w', f'-DTICKS={ticks}', f'-DSTART={start}', '-DNOFIRE' if nofire else '-DX', *cflags, '-I', os.path.join(ROOT, 'psp'),
                        '-o', exe, src, '-lm'], check=True)
        out = subprocess.run([exe], check=True, capture_output=True, text=True).stdout.split('\n')
    rows = {}
    for line in out:
        if not line:
            continue
        p = line.split(' ')
        al = [tuple(int(v) for v in a.split(',')) for a in p[7:]]
        rows[int(p[0])] = dict(state=int(p[1]), score=int(p[2]), lives=int(p[3]), stage=int(p[4]), px=int(p[5]), py=int(p[6]), al=al)
    return rows


def bcd(bs):                                     # BCD bytes, low pair first
    return sum(((b >> 4) * 10 + (b & 15)) * 100 ** k for k, b in enumerate(bs))


class Lynx:
    """Runs a Lynx ROM and reads its state at game ticks."""
    BOOT_MIN = 40

    def __init__(self, rom, lbl):
        from gearlynx import Gearlynx
        self.g = Gearlynx()
        self.g.load(rom)
        txt = open(lbl).read()
        self.lbl = {m.group(2): int(m.group(1), 16) for m in re.finditer(r'al ([0-9A-F]+) \.(\w+)\n', txt)}
        self.emu = 0
        self.offset = None                       # emulated frames before game tick 0

    def read(self, name, n=1):
        d = json.loads(self.g.tool('read_memory', area=0, offset='$%X' % self.lbl[name], size=n)[0]['text'])['data']
        return d if isinstance(d, list) else list(bytes.fromhex(d.replace(' ', '')))

    def step(self, n):
        self.g.frames(n)
        self.emu += n

    def tick8(self):
        return self.read('frame')[0]

    def sync(self):
        """Find the emulated frame at which the game loop starts (the first frame at which the tick counter is not 0), and the
        tick at which the game leaves the title screen. Returns that tick."""
        self.step(self.BOOT_MIN)
        while self.tick8() == 0:
            self.step(1)
        self.offset = self.emu - self.tick8()
        while self.read('game_state')[0] == 0:
            self.step(1)
        return self.emu - self.offset

    def goto(self, n):
        """Step to game tick n (tick = emulated frames - offset, while the game keeps its 50 Hz); returns the tick it is at."""
        self.step(max(0, self.offset + n - self.emu))
        t8 = self.tick8()
        if t8 != n & 255:                        # a late frame: the game is behind: follow its own counter
            return n + (t8 - n + 128) % 256 - 128
        return n

    def state(self, n_aliens):
        px = self.read('player_x')[0] + 256 * (self.read('player_x_msb')[0] & 1)
        xs, ms, ys = self.read('spr_x', n_aliens), self.read('spr_x_msb', n_aliens), self.read('spr_y', n_aliens)
        st = [6 if v == 7 else v for v in self.read('enemy_state', n_aliens)]    # the C64 code numbers an entering alien 7, C 6
        return dict(state=self.read('game_state')[0], score=bcd(self.read('score', 3)), lives=self.read('lives')[0],
                    stage=int('%x' % self.read('level')[0]), px=px,
                    al=[(st[i], xs[i] + 256 * (ms[i] & 1), ys[i]) for i in range(n_aliens)])


def compare(name):
    rom_flags, c_flags, ticks, what = SCENARIOS[name]
    top = max(ticks) + 300
    build = os.path.join('build', 'trace_' + name)
    subprocess.run(['rm', '-rf', os.path.join(ROOT, 'lynx', build)])
    subprocess.run(['make', '-C', os.path.join(ROOT, 'lynx'), f'BUILD={build}', 'CAFLAGS=' + ' '.join(f'-D {f}' for f in rom_flags)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    ly = Lynx(os.path.join(ROOT, 'lynx', build, 'galaga.lnx'), os.path.join(ROOT, 'lynx', build, 'galaga.lbl'))
    start = ly.sync()
    ref = c_trace(c_flags, top, 'NOFIRE=1' in rom_flags, start)
    bad = 0
    n_al = len(ref[1]['al'])
    for n in ticks:
        t = ly.goto(n)
        a, c = ly.state(n_al), ref[t]
        diffs = []
        for key in ('state', 'score', 'lives', 'stage', 'px'):
            if a[key] != c[key]:
                diffs.append(f'{key}: rom {a[key]} c {c[key]}')
        for i in range(n_al):
            (rs, rx, ry), (cs, cx, cy, ce) = a['al'][i], c['al'][i]
            on = cs != 0 and not (cs == 6 and ce == 0)
            if rs != cs:
                diffs.append(f'alien {i} state: rom {rs} c {cs}')
            elif on and (rx != cx or ry != cy):
                diffs.append(f'alien {i} position: rom ({rx},{ry}) c ({cx},{cy})')
        print(f'  tick {t}{" (asked " + str(n) + ")" if t != n else ""}: ' +
              ('same' if not diffs else f'{len(diffs)} differences, first: ' + '; '.join(diffs[:3])))
        bad += bool(diffs)
    print(f'{name} ({what}): ' + ('OK' if not bad else f'{bad} checkpoints differ'))
    return bad


def main():
    if len(sys.argv) < 3 or sys.argv[1] != 'lynx':
        sys.exit(__doc__)
    names = sys.argv[2:]
    if names == ['list']:
        for k, v in SCENARIOS.items():
            print(k, '-', v[3])
        return
    sys.exit(1 if sum(compare(n) for n in names) else 0)


main()
