#!/usr/bin/env python3
"""Compare a 6502 game (Lynx, later the C64) with the C reference psp/game.c at checkpoints.

    python3 tools/compare_6502.py lynx SCENARIO [SCENARIO ...]      ('list' prints the scenarios)

The same scripted game (the AUTOPLAY input of the 6502 game, copied into a small C driver) runs in the C reference and in the ROM.
The ROM runs in Gearlynx (headless, lynx/tools/gearlynx.py); at each checkpoint (a game tick) the state is read from memory by label
(`build/trace_<scenario>/galaga.lbl`) and compared with the state of the C game after the same tick: game state, lives, score, ship
position, and for every alien its state and (when it is on the screen) its position. The arcade rules have no random numbers, so the
games must stay equal.
Needs the Lynx boot ROM (see lynx/CLAUDE.md), cc65 and Gearlynx."""
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
sys.path.insert(0, os.path.join(ROOT, 'lynx', 'tools'))
SKEW = int(os.environ.get('SKEW', '0'))      # the ROM is read between two ticks: its state may be that of the tick before its counter

# name: (ROM flags, C flags, ticks to compare at, what is compared)
SCENARIOS = {
    # the arcade rules without dives, bombs and rams (the ROM has none yet: the C game gets no sorties and an invulnerable ship)
    'arc_entry': (['AUTOPLAY=1', 'NOFIRE=1', 'GODMODE=1', 'NODIVE=1'], ['-DNODIVE'], [130, 300, 500, 700, 900, 1100, 1300, 1600], 'fly-in, swing and breathing'),
    'arc_shoot': (['AUTOPLAY=1', 'GODMODE=1', 'NODIVE=1'], ['-DNODIVE'], [900, 1200, 1500, 2000, 2500], 'shooting the formation'),
    # dives, bombs and rams: the ship cannot be hit (a dual fighter, so that no boss captures it: the beam is the next milestone)
    'arc_dive': (['AUTOPLAY=1', 'NOFIRE=1', 'DUAL=1', 'GODMODE=1'], ['-DGODDUAL'], [900, 1100, 1300, 1600, 2000, 2500, 3200], 'dives, escorts, bombs'),
    'arc_dive2': (['AUTOPLAY=1', 'DUAL=1', 'GODMODE=1'], ['-DGODDUAL'], [1100, 1500, 2000, 2800, 3600, 4500], 'dives while the ship shoots'),
    # a whole game: the ship is hit, dies, is captured, comes back (no help for the ship)
    'arc_play': (['AUTOPLAY=1'], [], [1250, 1300, 1350, 1400, 1500, 1600, 1700], 'a whole game'),
    # a capture: the ship walks under the capture boss, is taken, and shoots the carrier to get it back as a dual fighter
    'arc_capture': (['AUTOPLAY=1', 'CAPTURE=1', 'GODBEAM=1'], ['-DCAPSCRIPT', '-DGODBEAM'], [1100, 1300, 1500, 1660, 1680, 1690, 1700, 1710, 1720, 1750, 2000, 2400, 3000, 4000], 'capture and rescue'),
    'arc_rescue': (['AUTOPLAY=1', 'CAPTURE=1', 'GODBEAM=1', 'LIVES=9'], ['-DCAPSCRIPT', '-DGODBEAM', '-DLIVES9'],
                   [2400, 3000, 3600, 4200, 4800, 5400, 6000, 7000, 8000], 'capture, rescue, dual fighter'),
    'arc_chal': (['AUTOPLAY=1', 'STAGE=3', 'GODMODE=1', 'NODIVE=1'], ['-DNODIVE', '-DSTART_STAGE=3'], [150, 400, 700, 1000, 1400, 1700, 1900], 'a challenge stage'),
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
#ifdef CAPSCRIPT
        if (g.state == S_PLAY || g.state == S_RESULT) in.fire = 0;       /* the ROM's script (lynx/src/game/player.s) */
        if (g.cap == C_BEAM || g.cap == C_CARRY || g.cap == C_DIVING) {
            int bx = g.al[g.capBoss].x;
            in.left = g.px > bx + 2; in.right = g.px < bx - 2;
            if (g.cap == C_CARRY) in.fire = (f & 3) < 2;
        }
#endif
#ifdef GODBEAM
        if (g.state != S_TITLE) g.invuln = g.cap == C_BEAM ? 0 : 100;       /* only the beam can take the ship */
#endif
#ifdef NODIVE
        g.sortie[0] = g.sortie[1] = g.sortie[2] = 1 << 30; g.invuln = 100;
#endif
#ifdef GODDUAL
        if (g.state != S_TITLE) { g.invuln = 100; g.dual = 1; }   /* the ship cannot be hit; a dual fighter is never captured */
#endif
        game_tick(&g, &in);
#ifdef LIVES9
        if (t + 1 == START) g.lives = 9;
#endif
        printf("%d %d %d %d %d %d %d", t + 1, g.state, g.score, g.lives, g.stage, g.px, g.py);
        for (i = 0; i < NAL; ++i) printf(" %d,%d,%d,%d,%d", g.al[i].st, g.al[i].x, g.al[i].y, g.al[i].ent, g.al[i].esc);
        for (i = 0; i < 4; ++i) printf(" %d,%d,%d", g.ps[i].act, g.ps[i].x, g.ps[i].y);
        for (i = 0; i < EBN; ++i) printf(" %d,%d,%d,%d,%d", g.eb[i].act, g.eb[i].x, g.eb[i].y, g.eb[i].dx, g.eb[i].ax);
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
        nb = 8
        al = [tuple(int(v) for v in a.split(',')) for a in p[7:-4 - nb]]
        sh = [tuple(int(v) for v in a.split(',')) for a in p[-4 - nb:-nb]]
        bm = [tuple(int(v) for v in a.split(',')) for a in p[-nb:]]
        rows[int(p[0])] = dict(state=int(p[1]), score=int(p[2]), lives=int(p[3]), stage=int(p[4]), px=int(p[5]), py=int(p[6]), al=al, shots=sh, bombs=bm)
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

    def bombs(self):
        s8 = lambda v: v - 256 if v > 127 else v
        s16 = lambda lo, hi: lo + 256 * hi - (65536 if hi > 127 else 0)
        act, xl, xh, yy, dx, ax = (self.read(n, 8) for n in ('eb_active', 'eb_x', 'eb_msb', 'eb_y', 'eb_dx', 'eb_ax'))
        return [(act[i] & 1, s16(xl[i], xh[i]), yy[i], s8(dx[i]), ax[i]) for i in range(8)]

    def state(self, n_aliens):
        px = self.read('player_x')[0] + 256 * (self.read('player_x_msb')[0] & 1)
        st = [6 if v == 7 else v for v in self.read('enemy_state', n_aliens)]    # the 6502 numbers an entering alien 7, C 6
        xl, xh, yl, yh = (self.read(n, n_aliens) for n in ('ax_lo', 'ax_hi', 'ay_lo', 'ay_hi'))     # signed 16-bit positions
        s16 = lambda lo, hi: lo + 256 * hi - (65536 if hi > 127 else 0)
        al = [(st[i], s16(xl[i], xh[i]), s16(yl[i], yh[i])) for i in range(n_aliens)]
        return dict(state=self.read('game_state')[0], score=bcd(self.read('score', 3)), lives=self.read('lives')[0],
                    stage=int('%x' % self.read('level')[0]), px=px, al=al,
                    shots=[(act & 1, xl + 256 * (xh & 1), yy) for act, xl, xh, yy in zip(self.read('pbul_active', 4), self.read('pbul_x', 4), self.read('pbul_msb', 4), self.read('pbul_y', 4))],
                    esc=self.read('enemy_esc', n_aliens),
                    bombs=self.bombs())


def lynx_state_at(name, rom_flags, tick, start):
    """Build the ROM with -DHALT: the game stops after `tick` ticks at the start of the next one, so the state is exact."""
    build = os.path.join('build', 'trace_%s_%d' % (name, tick))
    subprocess.run(['rm', '-rf', os.path.join(ROOT, 'lynx', build)])
    flags = ' '.join(f'-D {f}' for f in rom_flags) + f' -D HALT={tick + 1}'
    subprocess.run(['make', '-C', os.path.join(ROOT, 'lynx'), f'BUILD={build}', 'CAFLAGS=' + flags],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    ly = Lynx(os.path.join(ROOT, 'lynx', build, 'galaga.lnx'), os.path.join(ROOT, 'lynx', build, 'galaga.lbl'))
    try:
        ly.step(400 + tick)                              # the boot ROM, then the ticks
        t8 = ly.tick8()
        st = ly.state(NAL)
        st['t8'] = t8
        return st
    finally:
        ly.g.p.kill()


def start_tick(rom_flags):
    """The tick at which the ROM leaves the title screen (it needs a fire release and a press: the C game is told the same tick)."""
    build = os.path.join('build', 'trace_start')
    subprocess.run(['rm', '-rf', os.path.join(ROOT, 'lynx', build)])
    flags = ' '.join(f'-D {f}' for f in rom_flags if f.split('=')[0] in ('AUTOPLAY', 'NOFIRE')) + ' -D HALT=400'
    subprocess.run(['make', '-C', os.path.join(ROOT, 'lynx'), f'BUILD={build}', 'CAFLAGS=' + flags],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    ly = Lynx(os.path.join(ROOT, 'lynx', build, 'galaga.lnx'), os.path.join(ROOT, 'lynx', build, 'galaga.lbl'))
    try:
        return ly.sync()
    finally:
        ly.g.p.kill()


NAL = 40


def compare(name):
    from concurrent.futures import ThreadPoolExecutor
    rom_flags, c_flags, ticks, what = SCENARIOS[name]
    start = start_tick(rom_flags)
    ref = c_trace(c_flags, max(ticks) + 5, 'NOFIRE=1' in rom_flags, start)
    with ThreadPoolExecutor(4) as ex:
        roms = list(ex.map(lambda n: lynx_state_at(name, rom_flags, n, start), ticks))
    bad = 0
    for n, a in zip(ticks, roms):
        c = ref[n]
        diffs = []
        if a['t8'] != n & 255:
            diffs.append(f'the ROM stopped at tick {a["t8"]}, not {n & 255} (mod 256): late frames or not enough boot frames')
        for key in ('state', 'score', 'lives', 'stage', 'px'):
            if key == 'stage' and a['state'] == 6 and a[key] == c[key] + 1:
                continue                                 # the 6502 counts the stage when it is cleared, C after the result screen
            if a[key] != c[key]:
                diffs.append(f'{key}: rom {a[key]} c {c[key]}')
        for i in range(4):                        # a shot that is not in flight has no position
            sa, sc = a['shots'][i], c['shots'][i]
            if sa[0] != sc[0] or (sc[0] and sa != sc):
                diffs.append(f'shot {i}: rom {sa} c {sc}')
        for i in range(len(a['bombs'])):                        # a bomb that is not on the screen has no position
            ba, bc = a['bombs'][i], c['bombs'][i]
            if ba[0] != bc[0] or (bc[0] and ba != bc):
                diffs.append(f'bomb {i}: rom {ba} c {bc}')
        for i in range(len(c['al'])):
            (rs, rx, ry), (cs, cx, cy, ce, cesc) = a['al'][i], c['al'][i]
            on = cs != 0 and not (cs == 6 and ce == 0)
            if rs != cs:
                diffs.append(f'alien {i} state: rom {rs} c {cs}')
            elif cs != 0 and a['esc'][i] != cesc:
                diffs.append(f'alien {i} escort of: rom {a["esc"][i]} c {cesc}')
            elif on and (rx != cx or ry != cy):
                diffs.append(f'alien {i} position: rom ({rx},{ry}) c ({cx},{cy})')
        print(f'  tick {n}: ' + ('same' if not diffs else f'{len(diffs)} differences, first: ' + '; '.join(diffs[:3])))
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
