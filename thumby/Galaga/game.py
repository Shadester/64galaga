# Galaga rules, a port of psp/game.c (which follows the C64 game). No engine imports: runs on CPython for tests.
# Logic runs at the C64 PAL rate (50 ticks/s) in C64 sprite coordinates: play area x 24..343, y 50..249.
# x / y are the top-left of a 24 x 21 sprite box. Names follow game.c, so a change there can be carried over.
from paths_data import PATHS

NAL = 32
EBN = 3                   # enemy bombs on the screen
ARCADE = False            # the arcade rules (ARCADE.md, the default, switched on below) or the C64 rules: set_arcade() before a Game is made
AD = None
TICK_HZ = 50
MIRROR_X = 344
BOMB_LOW_Y = 163         # arcade rules: no bombs from a diver below this line (97 of 288 screen lines above the ship in the arcade: 67 of 200 here)
BOMB_MAX_DX = 24         # arcade rules: a bomb moves sideways at most 0.6 of its fall speed (2.5 px a tick): 0.6 x 2.5 x 16

S_TITLE, S_INTRO, S_PLAY, S_DYING, S_GAMEOVER, S_CAPTURED, S_RESULT, S_READY = range(8)
T_BOSS, T_BUTTERFLY, T_BEE = range(3)
A_DEAD, A_FORM, A_DIVE, A_RETURN, A_EXPLODE, A_BEAM, A_ENTER = range(7)
C_NONE, C_DIVING, C_BEAM, C_PULL, C_CARRY, C_RESCUE = range(6)   # tractor beam / captive state
P_A, P_B, P_C, P_D = range(4)

# Sound events, one bit each; the platform clears Game.snd after reading.
SND_SHOOT, SND_EXPLODE, SND_HIT, SND_DEATH, SND_SWOOP = 1, 2, 4, 8, 16
JG_STAGE, JG_OVER, JG_CAPTURE, JG_RESCUE, JG_BONUS = 32, 64, 128, 256, 512

BOSS_X = (145, 171, 197, 223)
BOSS_FOR_B = (0, 1, 3, 2, 0)      # arcade: the boss that goes with the wingmen pattern B (B = 1..4)
# Fly-in: launch delay (ticks / 2) per slot
ENTRY_DELAY = (40, 44, 48, 52, 0, 4, 8, 12, 56, 60, 64, 68, 80, 84, 88, 92,
               96, 100, 16, 20, 24, 28, 104, 108, 120, 124, 128, 132, 136, 140, 144, 148)
# Difficulty tables, index diff - 1
DIVE_INTERVAL = (130, 115, 100, 85, 70, 58, 48, 34)
DIVE_MAX = (1, 1, 2, 2, 3, 3, 4, 5)
DIVE_SHOTS = (1, 1, 1, 2, 2, 2, 2, 2)


def set_arcade(on):
    global ARCADE, NAL, EBN, AD
    ARCADE = bool(on)
    NAL = 40 if on else 32
    EBN = 8 if on else 3
    if on and AD is None:
        import arcade_data
        AD = arcade_data


set_arcade(True)


def cdiv(a, b):
    """Integer division that rounds toward zero, as in C."""
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def arc_stage_no(stage):
    """The arcade repeats stages 23..26 (its tables stop there)."""
    if stage > AD.ARC_NSTAGE:
        stage = AD.ARC_NSTAGE - 3 + ((stage - (AD.ARC_NSTAGE - 3)) & 3)
    return stage - 1


def slot_x(i):
    if ARCADE:
        return AD.ARC_SLOT[i][0]
    return BOSS_X[i] if i < 4 else 106 + 26 * ((i - 4) % 7)


def slot_y(i):
    if ARCADE:
        return AD.ARC_SLOT[i][1]
    return 72 if i < 4 else 100 + 28 * ((i - 4) // 7)


# A deterministic generator (the C test build uses the same): the game is the same on every device
class Rng:
    def __init__(self):
        self.s = 1

    def seed(self, s):
        self.s = s & 0xffffffff

    def rand(self):
        self.s = (self.s * 1103515245 + 12345) & 0x7fffffff
        return self.s

    def prand(self):
        return self.rand() >> 4


def entry_path(i):
    """(path, mirrored) of the fly-in of slot i."""
    if i < 4 or 8 <= i < 12:
        w = 2
    elif 12 <= i < 18 or i == 22 or i == 23:
        w = 3
    elif i >= 24:
        w = 4
    else:
        w = 1
    if w == 1:
        return P_C, 1 if i in (5, 7, 19, 21) else 0
    if w == 2:
        return P_D, 0
    if w == 3:
        return P_D, 1
    return P_C, 0 if (i - 24) & 1 else 1


class Alien:
    def __init__(self):
        self.reset()

    def reset(self):
        self.x = self.y = self.st = self.type = self.hp = self.timer = self.dir = 0
        self.esc = self.capdive = self.fired = 0
        self.path = self.pstep = self.mir = self.ent = self.dly = 0
        self.dpath = self.bflags = self.btmr = 0          # arcade rules


class Bullet:
    def __init__(self):
        self.x = self.y = self.act = self.dx = self.ax = 0

    def clear(self):
        self.x = self.y = self.act = self.dx = self.ax = 0


class Input:
    def __init__(self):
        self.left = self.right = self.fire = self.pause = self.quit = 0


class Game:
    def __init__(self, hi=0):
        self.rng = Rng()
        self.al = [Alien() for _ in range(NAL)]
        self.ps = [Bullet() for _ in range(4)]
        self.eb = [Bullet() for _ in range(EBN)]
        self.state = S_TITLE
        self.paused = self.stateTimer = self.frame = self.prevFire = 0
        self.score = 0
        self.hi = hi
        self.lives = self.stage = self.diff = self.nextBonus = 0
        self.challenge = self.chalVal = self.chalHits = self.chalTimer = 0
        self.shots = self.hits = 0
        self.px, self.py = 160, 230
        self.invuln = self.dual = self.dyingQuiet = 0
        self.formDx = self.formDir = self.formTimer = self.entering = self.diveTimer = 0
        self.cap = self.capBoss = self.beamLen = self.beamAcc = self.beamTimer = self.rx = self.ry = 0
        self.snd = self.saveReq = 0
        # arcade rules
        self.fclk = self.ff = self.swayPos = self.breathe = self.bstep = 0
        self.swayDir = 1
        self.clk = self.af = self.tmr2 = self.hold = self.wingm = self.bombFlags = 0
        self.sortie = [0, 0, 0]
        self.beamPh = self.beamStep = 0
        # debug starts, as the -D flags of the other ports
        self.start_stage_no = 1
        self.start_diff = 0
        self.start_lives = 3
        self.few = False
        self.force_capture = False

    # ---- helpers ----
    def add_score(self, n):
        self.score += n
        if self.score > 999999:
            self.score = 999999
        if self.score > self.hi:
            self.hi = self.score
        while self.score >= self.nextBonus:
            if self.lives < 9:
                self.lives += 1
            self.nextBonus += 50000 if self.nextBonus == 20000 else 70000
            self.snd |= JG_BONUS

    def setup_stage(self):
        if ARCADE:
            row = AD.ARC_STAGE[arc_stage_no(self.stage)][0]
            self.challenge = AD.ARC_ROW[row][0]
            self.chalVal = 100          # 100 for each enemy, 10,000 when all 40 are hit
        else:
            self.challenge = 1 if (self.stage & 3) == 3 else 0
            self.chalVal = 100 * ((self.stage + 1) // 4)
            if self.chalVal > 900:
                self.chalVal = 900
        self.chalHits = self.chalTimer = self.shots = self.hits = 0
        if ARCADE:
            self.fclk = self.ff = self.swayPos = self.breathe = self.bstep = 0
            self.swayDir = 1
        self.formDx = 0
        self.formDir = 3
        self.formTimer = 0
        self.diveTimer = DIVE_INTERVAL[self.diff - 1]
        if ARCADE:
            self.clk = self.af = self.wingm = self.bombFlags = self.hold = 0
            self.tmr2 = 120
            self.sortie = [22, 2, 2]
        self.cap = C_NONE
        self.beamLen = 0
        for b in self.ps:
            b.clear()
        for b in self.eb:
            b.clear()
        for i in range(NAL):
            a = self.al[i]
            a.reset()
            if ARCADE:
                a.type = T_BOSS if i < 4 else T_BUTTERFLY if i < 20 else T_BEE
            elif self.challenge:
                a.type = T_BUTTERFLY if (i >> 3) == 1 else T_BOSS if (i >> 3) == 3 else T_BEE
            else:
                a.type = T_BOSS if i < 4 else T_BUTTERFLY if i < 18 else T_BEE
            a.hp = 2 if (not self.challenge and a.type == T_BOSS) else 1
            a.st = A_ENTER
            a.y = 255
            if ARCADE:
                continue
            if self.challenge:
                a.path = P_B if (i >> 3) & 1 else P_A
                a.mir = 1 if (i >> 3) >= 2 else 0
            else:
                a.path, a.mir = entry_path(i)
                a.dly = 2 * ENTRY_DELAY[i]
        if ARCADE:          # the launch list of the stage's row: when each slot starts, and on which path
            r = AD.ARC_ROW[row]
            hdr1, l = r[2], r[3]
            for k in range(0, len(l), 3):
                if l[k + 1] >= 0:
                    a = self.al[l[k + 1]]
                    a.dly = l[k]
                    a.path = l[k + 2]
                    a.bflags = hdr1 if AD.ARC_ENTRY_BOMB[l[k + 1]] else 0
                    a.btmr = AD.ARC_PATH[a.path][3]
        if self.few:                       # debug: only three bees
            for i in range(NAL - 3):
                self.al[i].st = A_DEAD

    def start_stage(self):
        self.setup_stage()
        self.state = S_INTRO
        self.stateTimer = 120
        self.snd |= JG_STAGE

    def start_game(self):
        self.rng.seed(self.frame * 2654435761 + 1)
        self.score = 0
        self.lives = self.start_lives
        self.stage = self.start_stage_no
        self.diff = 1
        if self.stage != 1:
            self.diff = min(8, 1 + (self.stage - 1 - self.stage // 4))
        if self.start_diff:
            self.diff = self.start_diff
        self.nextBonus = 20000
        self.dual = 0
        self.cap = C_NONE
        self.px, self.py = 160, 230
        self.invuln = 0
        self.dyingQuiet = 0
        self.start_stage()

    def game_over(self):
        self.state = S_GAMEOVER
        self.stateTimer = 90
        self.snd |= JG_OVER
        self.saveReq = 1

    # ---- player ----
    def player_hit(self, side):
        if self.dual:
            self.dual = 0
            if side == 0:
                self.px += 16
            self.invuln = 90
            self.snd |= SND_HIT
            return
        self.lives -= 1
        self.state = S_DYING
        self.stateTimer = 107 if ARCADE else 63     # the arcade waits 4 x 32 frames before the ship comes back
        self.dyingQuiet = 0
        for b in self.eb:
            b.clear()
        for b in self.ps:
            b.clear()
        self.snd |= SND_HIT | SND_DEATH

    def update_player(self, inp, fire_press):
        maxx = 304 if self.dual else 320
        if inp.left:
            self.px -= 2
        if inp.right:
            self.px += 2
        if self.px < 24:
            self.px = 24
        if self.px > maxx:
            self.px = maxx
        if not fire_press:
            return
        for n in range(2 if self.dual else 1):
            for i in range(n * 2, n * 2 + 2):
                b = self.ps[i]
                if not b.act:
                    b.act = 1
                    b.x = self.px + 3 + 16 * n
                    b.y = 214
                    if self.state != S_RESULT:   # the result screen shows the stage's shots: later ones do not count
                        self.shots += 1
                    self.snd |= SND_SHOOT
                    break

    def update_pshots(self):
        for b in self.ps:
            if b.act:
                b.y -= 4
                if b.y < 20:
                    b.act = 0

    # ---- aliens ----
    def release_capture(self, boss):
        if self.cap and self.cap != C_RESCUE and self.capBoss == boss:
            self.cap = C_NONE

    def alien_hit(self, i):
        a = self.al[i]
        dive = a.st == A_DIVE or a.st == A_ENTER
        self.hits += 1
        if a.hp > 1:
            a.hp -= 1
            self.snd |= SND_SHOOT
            return
        if self.challenge:
            self.chalHits += 1
            pts = self.chalVal
        elif a.type == T_BOSS:
            n = 0
            if dive:
                for e in self.al:
                    if e.esc == i + 1 and (e.st == A_DIVE or e.st == A_RETURN):
                        n += 1
            pts = (400 << n) if dive else 150
            if ARCADE and dive:
                self.hold = 6
        elif a.type == T_BUTTERFLY:
            pts = 160 if dive else 80
        else:
            pts = 100 if dive else 50
        if a.type == T_BOSS and self.cap and self.capBoss == i:
            if self.cap == C_CARRY and (a.st == A_DIVE or a.st == A_RETURN):
                self.cap = C_RESCUE
                self.rx = a.x
                self.ry = a.y - 16
                pts += 1000
                self.snd |= JG_RESCUE
            else:
                self.cap = C_NONE   # captive lost, or capture cancelled (beam vanishes)
        a.st = A_EXPLODE
        a.timer = 11
        self.snd |= SND_EXPLODE
        self.add_score(pts)

    def path_len(self, path):
        return AD.ARC_PATH[path][2] if ARCADE else PATHS[path][2]

    def slot_px(self, i):
        """Where a slot is now: the swing of the whole formation and the breathing of its columns and rows."""
        x = slot_x(i) + self.formDx
        if ARCADE and self.breathe:
            c = AD.ARC_SLOT_COL[i]
            br = AD.ARC_BREATH[self.bstep]
            x += br[c] if c < 5 else -br[9 - c]
        return x

    def slot_py(self, i):
        if ARCADE and self.breathe:
            return slot_y(i) + AD.ARC_BREATH[self.bstep][5 + AD.ARC_SLOT_ROW[i]]
        return slot_y(i)

    def path_step(self, a):
        if ARCADE:      # mirrored paths are separate paths: no mirror here
            d = AD.ARC_PATH[a.path][4]
            k = 2 * a.pstep
            a.x += d[k] - 128
            a.y += d[k + 1] - 128
            a.pstep += 1
            return
        p = PATHS[a.path]
        k = a.pstep
        a.x += -p[3][k] if a.mir else p[3][k]
        a.y += p[4][k]
        a.pstep += 1

    def path_launch(self, a):
        p = AD.ARC_PATH[a.path] if ARCADE else PATHS[a.path]
        a.ent = 1
        a.pstep = 0
        a.x = MIRROR_X - p[0] if (a.mir and not ARCADE) else p[0]
        a.y = p[1]

    def arc_form_frame(self):
        """The formation swings left and right while the aliens fly in (one arcade pixel every 4 frames, +-32), and when they
        are all home and the swing comes back to the middle it starts to breathe (ARC_BREATH)."""
        self.ff += 1
        if self.breathe:
            if not (self.ff & 3):
                self.bstep = (self.bstep + 1) & 63
            return
        if (self.ff - 1) & 3:
            return
        self.swayPos += self.swayDir
        if not self.entering and self.swayPos == 0:
            self.breathe = 1
            self.bstep = 0
        elif self.swayPos >= 32:
            self.swayDir = -1
        elif self.swayPos <= -32:
            self.swayDir = 1
        self.formDx = self.swayPos + cdiv(self.swayPos * 3, 7)     # 320 / 224

    def update_formation(self):
        n = 0
        for a in self.al:
            if a.st == A_ENTER:
                n += 1
        self.entering = n
        if ARCADE:
            if not self.challenge:
                self.fclk += 6
                while self.fclk >= 5:
                    self.arc_form_frame()
                    self.fclk -= 5
            return
        if n or self.challenge:
            return
        self.formTimer += 1
        if self.formTimer >= 10 - self.diff:
            self.formTimer = 0
            self.formDx += self.formDir
            if self.formDx >= 42:
                self.formDir = -3
            if self.formDx <= -42:
                self.formDir = 3

    def update_entry(self):
        for i in range(NAL):
            a = self.al[i]
            if a.st != A_ENTER:
                continue
            if a.ent == 0:
                if ARCADE and self.state != S_PLAY:   # the waves wait while the ship is dead or taken
                    continue
                a.dly -= 1
                if a.dly <= 0:
                    self.path_launch(a)
            elif a.ent == 1:
                if a.pstep >= self.path_len(a.path):
                    a.ent = 2
                else:
                    self.path_step(a)
            else:
                tx = self.slot_px(i)
                ty = self.slot_py(i)
                a.x += 2 if a.x < tx else -2 if a.x > tx else 0
                a.y += 2 if a.y < ty else -2 if a.y > ty else 0
                if abs(a.x - tx) <= 3 and abs(a.y - ty) <= 3:
                    a.st = A_FORM
                    a.x = tx
                    a.y = ty

    def update_challenge(self):
        self.chalTimer += 1
        for i in range(NAL):
            a = self.al[i]
            if a.st != A_ENTER:
                continue
            if a.ent == 0:
                if self.chalTimer >= (a.dly if ARCADE else (i >> 3) * 55 + (i & 7) * 6):
                    self.path_launch(a)
            elif a.pstep >= self.path_len(a.path):
                a.st = A_DEAD
            else:
                self.path_step(a)

    def spawn_ebullet(self, a):
        d = self.px - a.x
        for b in self.eb:
            if not b.act:
                b.act = 1
                b.x = a.x
                b.y = a.y + 8
                if ARCADE:      # aimed at the ship's place now: it needs (py - y) / 2.5 ticks to fall, so it moves dx / ticks a tick, in 16ths
                    b.ax = 0
                    b.dx = cdiv(16 * d, cdiv((self.py - b.y) * 2, 5) + 1)
                    b.dx = BOMB_MAX_DX if b.dx > BOMB_MAX_DX else -BOMB_MAX_DX if b.dx < -BOMB_MAX_DX else b.dx   # the arcade's limit
                    return
                b.dx = 0 if abs(d) < 16 else 1 if d > 0 else -1
                return

    def start_dive(self, i, capture, peel):
        a = self.al[i]
        a.st = A_DIVE
        a.timer = peel
        a.fired = 0
        a.capdive = capture
        if capture:
            a.dir = 1 if a.x < self.px else -1
        else:
            a.dir = 1 if a.x >= 184 else -1
        self.snd |= SND_SWOOP
        if capture:
            self.cap = C_DIVING
            self.capBoss = i
        if ARCADE:      # a dive follows the arcade path of its kind from its slot: a boss and an escort label 2, a butterfly 1, a bee 0
            a.pstep = 0
            a.bflags = self.bombFlags
            a.btmr = 30
            if capture:
                a.dpath = -1
            else:
                label = 2 if (a.esc or a.type == T_BOSS) else 1 if a.type == T_BUTTERFLY else 0
                a.dpath = AD.ARC_DIVE[label][AD.ARC_SLOT_ROW[i]][AD.ARC_SLOT_SIDE[i]]

    def dive_step(self, i):
        if not ARCADE:
            self.dive_step_old(i)
            return
        a = self.al[i]
        if a.capdive:
            self.dive_step_old(i)
            return
        if a.timer > 0:         # an escort waits for its boss
            a.timer -= 1
            a.x = self.slot_px(i)
            a.y = self.slot_py(i)
            return
        if a.dpath >= 0 and a.pstep < AD.ARC_DIVE_PATH[a.dpath][0]:
            d = AD.ARC_DIVE_PATH[a.dpath][2]
            k = 2 * a.pstep
            a.x += d[k] - 128
            a.y += d[k + 1] - 128
        else:                   # the end of the arcade path of a butterfly (it aims at the ship)
            a.y += 3
            if self.frame & 1:
                a.x += 1 if a.x < self.px else -1 if a.x > self.px else 0
        a.pstep += 1
        if a.y >= 244:          # gone below the screen: back from the top when the arcade dive would end
            total = AD.ARC_DIVE_PATH[a.dpath][1] if a.dpath >= 0 else 220
            a.st = A_RETURN
            a.y = 0
            a.timer = total - a.pstep - self.slot_py(i) // 2
            if a.timer < 0:
                a.timer = 0

    def dive_step_old(self, i):
        a = self.al[i]
        dy = 3 if self.diff >= 5 else 2
        if a.timer > 0:
            a.timer -= 1
            a.x += 2 * a.dir
            a.y += 1
            return
        a.y += dy
        if a.capdive or (self.frame & 1):
            a.x += 1 if a.x < self.px else -1 if a.x > self.px else 0
        if not a.esc and not a.capdive:
            mask = 1 if self.diff <= 2 else 0
            if (a.fired == 0 and a.y >= 100) or (a.fired == 1 and DIVE_SHOTS[self.diff - 1] == 2 and a.y >= 150):
                a.fired += 1
                if (self.rng.prand() & mask) == 0:
                    self.spawn_ebullet(a)
        if a.capdive and a.y >= 196:
            a.st = A_BEAM
            self.cap = C_BEAM
            self.beamLen = self.beamAcc = 0
            self.beamTimer = 180
            if ARCADE:      # 10 x p6 arcade frames to grow (p6 = 12, 9 or 6 by stage), then 64 frames to take the ship, then the same to go
                self.beamPh = 0
                self.beamStep = AD.ARC_STAGE[arc_stage_no(self.stage)][1 + 6] * 10 * 5 // 6 // 4
        elif a.y >= 244:
            a.st = A_RETURN
            a.y = 0
            a.capdive = 0

    def update_aliens(self):
        for i in range(NAL):
            a = self.al[i]
            st = a.st
            if st == A_FORM:
                a.x = self.slot_px(i)
                a.y = self.slot_py(i)
                if ARCADE and a.timer > 0:      # just home: it turns round before it can dive again
                    a.timer -= 1
            elif st == A_EXPLODE:
                a.timer -= 1
                if a.timer < 0:
                    a.st = A_DEAD
            elif st == A_DIVE:
                self.dive_step(i)
            elif st == A_RETURN:
                a.x = self.slot_px(i)
                if ARCADE and a.timer > 0:
                    a.timer -= 1
                    continue
                a.y += 2
                if a.y >= self.slot_py(i):
                    a.y = self.slot_py(i)
                    a.st = A_FORM
                    a.esc = 0
                    if ARCADE:      # the arcade takes 54 frames (bee: 3) to settle a boss or a butterfly: 45 ticks
                        a.timer = 3 if a.type == T_BEE else 45

    # ---- the arcade's dive scheduler (f_0857, f_1B65 of the model, see ARCADE.md). One call of arc_frame is one arcade frame ----
    def arc_standby(self, lo, hi):
        for i in range(lo, hi):
            a = self.al[i]
            if a.st == A_FORM and not a.timer:
                return i
        return -1

    def arc_sortie_boss(self):
        """case_bmbr_boss, j_1CAE: who dives with whom."""
        al = self.al
        wing = AD.ARC_WINGMEN
        if not self.cap:
            self.wingm += 1
            if not (self.wingm & 1) and not self.dual:      # every second sortie tries to capture
                slot = self.arc_standby(0, 4)
                if slot >= 0:
                    self.start_dive(slot, 1, 20)
                return
        c = 0
        for k in range(6):          # which of the six wingmen are at home
            w = al[wing[k]]
            c = (c << 1) | (1 if (w.st == A_FORM and not w.timer) else 0)
        slot = -1
        n = 1
        B = cc = 0
        ixl = 0
        while ixl < 2 and slot < 0:     # ixl 0: a boss with two wingmen (the pattern 011, 111, 110), ixl 1: with one
            cc = c
            B = 4
            while B >= 1:
                a = cc & 7
                ok = (a != 4 and a >= 3) if ixl == 0 else (a != 0)
                bs = BOSS_FOR_B[B]
                if ok and al[bs].st == A_FORM and not al[bs].timer:
                    slot = bs
                    n = 2 - ixl
                    break
                B -= 1
                cc >>= 1
            ixl += 1
        if slot < 0:                # a boss alone
            slot = self.arc_standby(0, 4)
            if slot >= 0:
                self.start_dive(slot, 0, 0)
            return
        b = B + 1                   # B and cc are the ones of the match
        esc = []
        for k in range(n):
            cy = cc & 1
            cc = (cc >> 1) | (cy << 7)
            if not cy:
                b -= 1
                cy = cc & 1
                cc = (cc >> 1) | (cy << 7)
                if not cy:
                    b -= 1
            if 0 <= b < 6:
                esc.append(wing[b])
            b -= 1
        for e in esc:
            al[e].esc = slot + 1
        self.start_dive(slot, 0, 0)
        for k in range(len(esc)):
            self.start_dive(esc[k], 0, k + 1)

    def arc_frame(self):
        P = AD.ARC_STAGE[arc_stage_no(self.stage)]      # P[0] is the row, P[k + 1] the parameter pk
        self.af += 1
        if not (self.af & 31):
            if self.tmr2 > 0:
                self.tmr2 -= 1
            if self.hold > 0:
                self.hold -= 1
        hdr0 = AD.ARC_ROW[P[0]][1]
        n = flying = 0
        for a in self.al:
            st = a.st
            if st != A_DEAD and st != A_EXPLODE:
                n += 1
            if st == A_DIVE or st == A_RETURN or st == A_BEAM:
                flying += 1
        tens = n // 10
        maxb = P[5]
        if self.tmr2 < 60:
            maxb = P[6]
        self.bombFlags = AD.ARC_BOMB_TAB[4 * P[1] + tens]
        cont = n < P[8]
        idx = (1 if self.tmr2 < 40 else 0) + (1 if self.tmr2 == 0 else 0)
        if cont:
            reload = (2, 2, 2)
        else:
            reload = (AD.ARC_BOMB_TAB[32 + 4 * P[2] + tens], AD.ARC_RED_RELOAD[3 * P[3] + idx], AD.ARC_BEE_RELOAD[3 * P[4] + idx])
        for a in self.al:       # bombs: a diver drops one at every set bit of its flags, every 20 frames, high on the screen
            if not ((a.st == A_DIVE and not a.capdive) or (a.st == A_ENTER and a.ent == 1)):
                continue
            a.btmr -= 1
            if a.btmr > 0:
                continue
            a.btmr = hdr0
            if (a.bflags & 1) and a.y <= BOMB_LOW_Y and not self.hold:
                self.spawn_ebullet(a)
            a.bflags >>= 1
        if self.entering or (self.af & 15):
            return
        s = self.sortie
        i = 0
        while i < 3:
            s[i] -= 1
            if s[i] == 0:
                break
            i += 1
        if i == 3:
            return
        if flying >= maxb:
            s[i] += 1
            return
        s[i] = reload[i]
        if i == 2:
            n = self.arc_standby(20, 40)
            if n >= 0:
                self.start_dive(n, 0, 0)
        elif i == 1:
            n = self.arc_standby(4, 20)
            if n >= 0:
                self.start_dive(n, 0, 0)
        else:
            self.arc_sortie_boss()

    def select_dive(self):
        if ARCADE:
            if self.challenge:
                return
            self.clk += 6
            while self.clk >= 5:
                self.arc_frame()
                self.clk -= 5
            return
        if self.entering or self.challenge:
            return
        self.diveTimer -= 1
        if self.diveTimer > 0:
            return
        self.diveTimer = DIVE_INTERVAL[self.diff - 1]
        away = 0
        for a in self.al:
            if not a.esc and (a.st == A_DIVE or a.st == A_RETURN or a.st == A_BEAM):
                away += 1
        if away >= DIVE_MAX[self.diff - 1]:
            return
        if self.force_capture and not self.cap and not self.dual and self.al[1].st == A_FORM:
            self.start_dive(1, 1, 20)
            return
        pick = -1
        rng = self.rng
        if not self.cap and not self.dual and (rng.prand() & 1):
            i = rng.prand() & 3
            if self.al[i].st == A_FORM:
                pick = i
        tries = 0
        while pick < 0 and tries < 8:
            i = rng.prand() & 31
            if self.al[i].st == A_FORM:
                pick = i
            tries += 1
        if pick < 0:
            return
        if self.al[pick].type == T_BOSS and not self.cap and not self.dual:
            self.start_dive(pick, 1, 20)
            return
        self.start_dive(pick, 0, 20)
        if self.al[pick].type == T_BOSS and (self.cap or self.dual):
            for k in range(2):
                e = self.al[5 + pick + k]
                if e.st == A_FORM:
                    self.start_dive(5 + pick + k, 0, 32 if k else 26)
                    e.esc = pick + 1

    def update_ebullets(self):
        for b in self.eb:
            if b.act:
                if ARCADE:
                    b.y += 2 + (self.frame & 1)
                    b.ax += b.dx
                    b.x += b.ax >> 4
                    b.ax &= 15
                else:
                    b.y += 3
                    if self.frame & 1:
                        b.x += b.dx
                if b.y >= 250:
                    b.act = 0

    def update_collisions(self):
        for i in range(4):
            b = self.ps[i]
            if not b.act:
                continue
            for j in range(NAL):
                a = self.al[j]
                if a.st == A_DEAD or a.st == A_EXPLODE or (a.st == A_ENTER and a.ent == 0):
                    continue
                if b.y - 8 <= a.y < b.y + 8 and a.x - 6 <= b.x < a.x + 12:
                    b.act = 0
                    self.alien_hit(j)
                    break
        if self.state != S_PLAY or self.invuln:
            return
        for i in range(EBN):
            if self.state != S_PLAY:
                break
            b = self.eb[i]
            if b.act and 227 <= b.y <= 240:
                for j in range(1 + self.dual):
                    sx = self.px + 16 * j
                    if sx - 6 <= b.x <= sx + 7:
                        b.act = 0
                        self.player_hit(j)
                        break
        j = 0
        while j < NAL and self.state == S_PLAY and not self.invuln and not self.challenge:   # challenge aliens never ram
            a = self.al[j]
            if a.st == A_DIVE or (a.st == A_ENTER and a.ent):
                for s in range(1 + self.dual):
                    sx = self.px + 16 * s
                    if self.py - 7 <= a.y <= self.py + 8 and sx - 8 < a.x <= sx + 8:
                        if a.capdive:
                            self.release_capture(j)   # ramming boss drops its captive
                        if a.type == T_BOSS and self.cap == C_CARRY and self.capBoss == j:
                            self.cap = C_NONE
                        a.st = A_EXPLODE
                        a.timer = 11
                        self.snd |= SND_EXPLODE
                        self.player_hit(s)
                        break
            j += 1

    # ---- tractor beam, capture, rescue ----
    def update_capture(self):
        if self.cap == C_BEAM:
            b = self.al[self.capBoss]
            if not (self.frame & 31):
                self.snd |= SND_SWOOP
            if ARCADE and self.beamPh == 0:
                self.beamAcc += 1
                if self.beamAcc >= self.beamStep:
                    self.beamAcc = 0
                    self.beamLen += 1
                    if self.beamLen >= 4:
                        self.beamPh = 1
                        self.beamTimer = 53
            elif ARCADE and self.beamPh == 2:
                self.beamAcc += 1
                if self.beamAcc >= self.beamStep:
                    self.beamAcc = 0
                    self.beamLen -= 1
                    if self.beamLen <= 0:
                        self.cap = C_NONE
                        b.st = A_RETURN
                        b.y = 0
            elif not ARCADE and self.beamLen < 4:
                self.beamAcc += 1
                if self.beamAcc >= 8:
                    self.beamAcc = 0
                    self.beamLen += 1
            elif self.state == S_PLAY and not self.invuln and b.x - 20 <= self.px <= b.x + 19:
                self.cap = C_PULL
                self.state = S_CAPTURED
                self.dual = 0
                for p in self.ps:
                    p.clear()
                self.snd |= JG_CAPTURE
            else:
                self.beamTimer -= 1
                if self.beamTimer <= 0:
                    if ARCADE:
                        self.beamPh = 2
                        self.beamAcc = 0
                    else:
                        self.cap = C_NONE
                        b.st = A_RETURN
                        b.y = 0
        elif self.cap == C_RESCUE:
            tx = self.px + 16
            self.ry += 3
            if self.ry > 230:
                self.ry = 230
            self.rx += 2 if self.rx < tx else -2 if self.rx > tx else 0
            if self.ry == 230 and self.state == S_PLAY and -4 <= self.rx - tx <= 3:
                self.cap = C_NONE
                self.dual = 1
                if self.px > 304:
                    self.px = 304
                self.snd |= JG_RESCUE

    def update_captured(self):
        b = self.al[self.capBoss]
        self.update_ebullets()
        self.py -= 2
        if self.py - b.y >= 22:
            return
        self.py = 230
        self.cap = C_CARRY
        b.st = A_RETURN
        b.y = 0
        b.capdive = 0
        self.lives -= 1
        if self.lives <= 0:
            self.game_over()
            return
        self.state = S_DYING
        self.stateTimer = 100
        self.dyingQuiet = 1

    def next_stage(self):
        if not self.challenge and self.diff < 8:
            self.diff += 1
        self.stage += 1
        self.start_stage()

    def enter_result(self):
        self.state = S_RESULT
        self.stateTimer = 150
        if self.challenge and self.chalHits == NAL:
            self.add_score(10000)

    def move_world(self):
        self.update_formation()
        self.update_entry()
        self.update_aliens()

    def tick(self, inp):
        fire_press = inp.fire and not self.prevFire
        self.prevFire = inp.fire
        if self.state == S_TITLE:
            if fire_press:
                self.start_game()
            self.frame += 1
            return
        if inp.pause and self.state == S_PLAY:
            self.paused = not self.paused
        if self.paused:
            return
        if inp.quit and self.state != S_GAMEOVER:
            self.state = S_TITLE
            self.saveReq = 1
            self.snd = 0
            return
        self.frame += 1
        st = self.state
        if st == S_INTRO:
            self.stateTimer -= 1
            if self.stateTimer <= 0:
                self.state = S_PLAY
        elif st == S_PLAY:
            if self.invuln:
                self.invuln -= 1
            self.update_player(inp, fire_press)
            self.update_pshots()
            if self.challenge:
                self.update_challenge()
                self.update_aliens()
            else:
                self.move_world()
                self.select_dive()
                self.update_ebullets()
            self.update_collisions()
            self.update_capture()
            if self.state != S_PLAY:
                return
            alive = 0
            for a in self.al:
                if a.st != A_DEAD:
                    alive += 1
            if not alive and self.cap != C_RESCUE:
                self.enter_result()
        elif st == S_DYING:
            if self.challenge:
                self.update_aliens()
            else:
                self.move_world()
                self.update_ebullets()
                self.update_capture()
            self.stateTimer -= 1
            if self.stateTimer <= 0:
                if self.lives <= 0:
                    self.game_over()
                else:
                    self.state = S_READY
                    self.stateTimer = 80 if ARCADE else 90      # arcade: 3 x 32 frames after the last flyer is home
        elif st == S_READY:
            if self.challenge:
                self.update_aliens()
            else:
                self.move_world()
            if ARCADE and not self.challenge:     # the ship comes back when nothing flies any more: the divers finish first, the beam too
                self.update_capture()
                flying = 0
                for a in self.al:
                    if a.st == A_DIVE or a.st == A_RETURN or a.st == A_BEAM or (a.st == A_ENTER and a.ent):
                        flying += 1
                if flying:
                    return
            self.stateTimer -= 1
            if self.stateTimer <= 0:
                self.state = S_PLAY
                self.px = 160
                self.invuln = 120
                if ARCADE:      # after a death the sorties start slowly again
                    self.tmr2 += 30
                    if self.tmr2 > 120:
                        self.tmr2 = 120
        elif st == S_CAPTURED:
            self.move_world()
            self.update_capture()
            self.update_captured()
        elif st == S_RESULT:
            self.update_player(inp, fire_press)
            self.update_pshots()
            self.stateTimer -= 1
            if self.stateTimer <= 0:
                self.next_stage()
        elif st == S_GAMEOVER:
            if self.stateTimer > 0:
                self.stateTimer -= 1
            elif fire_press:
                self.state = S_TITLE


def autoplay(g, inp):
    """Synthetic input for unattended runs: sweep, fire, press fire on menus."""
    inp.pause = inp.quit = 0
    inp.fire = 1 if (g.frame & 15) < 2 else 0
    inp.left = 1 if (g.frame >> 7) & 1 else 0
    inp.right = 0 if inp.left else 1
