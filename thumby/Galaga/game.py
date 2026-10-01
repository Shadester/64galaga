# Galaga rules, a port of psp/game.c (which follows the C64 game). No engine imports: runs on CPython for tests.
# Logic runs at the C64 PAL rate (50 ticks/s) in C64 sprite coordinates: play area x 24..343, y 50..249.
# x / y are the top-left of a 24 x 21 sprite box. Names follow game.c, so a change there can be carried over.
from paths_data import PATHS

NAL = 32
TICK_HZ = 50
MIRROR_X = 344

S_TITLE, S_INTRO, S_PLAY, S_DYING, S_GAMEOVER, S_CAPTURED, S_RESULT, S_READY = range(8)
T_BOSS, T_BUTTERFLY, T_BEE = range(3)
A_DEAD, A_FORM, A_DIVE, A_RETURN, A_EXPLODE, A_BEAM, A_ENTER = range(7)
C_NONE, C_DIVING, C_BEAM, C_PULL, C_CARRY, C_RESCUE = range(6)   # tractor beam / captive state
P_A, P_B, P_C, P_D = range(4)

# Sound events, one bit each; the platform clears Game.snd after reading.
SND_SHOOT, SND_EXPLODE, SND_HIT, SND_DEATH, SND_SWOOP = 1, 2, 4, 8, 16
JG_STAGE, JG_OVER, JG_CAPTURE, JG_RESCUE, JG_BONUS = 32, 64, 128, 256, 512

BOSS_X = (145, 171, 197, 223)
# Fly-in: launch delay (ticks / 2) per slot
ENTRY_DELAY = (40, 44, 48, 52, 0, 4, 8, 12, 56, 60, 64, 68, 80, 84, 88, 92,
               96, 100, 16, 20, 24, 28, 104, 108, 120, 124, 128, 132, 136, 140, 144, 148)
# Difficulty tables, index diff - 1
DIVE_INTERVAL = (130, 115, 100, 85, 70, 58, 48, 34)
DIVE_MAX = (1, 1, 2, 2, 3, 3, 4, 5)
DIVE_SHOTS = (1, 1, 1, 2, 2, 2, 2, 2)


def slot_x(i):
    return BOSS_X[i] if i < 4 else 106 + 26 * ((i - 4) % 7)


def slot_y(i):
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


class Bullet:
    def __init__(self):
        self.x = self.y = self.act = self.dx = 0


class Input:
    def __init__(self):
        self.left = self.right = self.fire = self.pause = self.quit = 0


class Game:
    def __init__(self, hi=0):
        self.rng = Rng()
        self.al = [Alien() for _ in range(NAL)]
        self.ps = [Bullet() for _ in range(4)]
        self.eb = [Bullet() for _ in range(3)]
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
        # debug starts, as the -D flags of the other ports
        self.start_stage_no = 1
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
        self.challenge = 1 if (self.stage & 3) == 3 else 0
        self.chalVal = 100 * ((self.stage + 1) // 4)
        if self.chalVal > 900:
            self.chalVal = 900
        self.chalHits = self.chalTimer = self.shots = self.hits = 0
        self.formDx = 0
        self.formDir = 3
        self.formTimer = 0
        self.diveTimer = DIVE_INTERVAL[self.diff - 1]
        self.cap = C_NONE
        self.beamLen = 0
        for b in self.ps:
            b.x = b.y = b.act = b.dx = 0
        for b in self.eb:
            b.x = b.y = b.act = b.dx = 0
        for i in range(NAL):
            a = self.al[i]
            a.reset()
            if self.challenge:
                a.type = T_BUTTERFLY if (i >> 3) == 1 else T_BOSS if (i >> 3) == 3 else T_BEE
            else:
                a.type = T_BOSS if i < 4 else T_BUTTERFLY if i < 18 else T_BEE
            a.hp = 2 if (not self.challenge and a.type == T_BOSS) else 1
            a.st = A_ENTER
            a.y = 255
            if self.challenge:
                a.path = P_B if (i >> 3) & 1 else P_A
                a.mir = 1 if (i >> 3) >= 2 else 0
            else:
                a.path, a.mir = entry_path(i)
                a.dly = 2 * ENTRY_DELAY[i]

    def start_stage(self):
        self.setup_stage()
        self.state = S_INTRO
        self.stateTimer = 120
        self.snd |= JG_STAGE

    def start_game(self):
        self.rng.seed(self.frame * 2654435761 + 1)
        self.score = 0
        self.lives = 3
        self.stage = self.start_stage_no
        self.diff = 1
        if self.stage != 1:
            self.diff = min(8, 1 + (self.stage - 1 - self.stage // 4))
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
        self.stateTimer = 63
        self.dyingQuiet = 0
        for b in self.eb:
            b.x = b.y = b.act = b.dx = 0
        for b in self.ps:
            b.x = b.y = b.act = b.dx = 0
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

    def path_step(self, a):
        p = PATHS[a.path]
        k = a.pstep
        a.x += -p[3][k] if a.mir else p[3][k]
        a.y += p[4][k]
        a.pstep += 1

    def path_launch(self, a):
        p = PATHS[a.path]
        a.ent = 1
        a.pstep = 0
        a.x = MIRROR_X - p[0] if a.mir else p[0]
        a.y = p[1]

    def update_formation(self):
        n = 0
        for a in self.al:
            if a.st == A_ENTER:
                n += 1
        self.entering = n
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
                a.dly -= 1
                if a.dly <= 0:
                    self.path_launch(a)
            elif a.ent == 1:
                if a.pstep >= PATHS[a.path][2]:
                    a.ent = 2
                else:
                    self.path_step(a)
            else:
                tx = slot_x(i) + self.formDx
                ty = slot_y(i)
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
                if self.chalTimer >= (i >> 3) * 55 + (i & 7) * 6:
                    self.path_launch(a)
            elif a.pstep >= PATHS[a.path][2]:
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

    def dive_step(self, i):
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
        elif a.y >= 244:
            a.st = A_RETURN
            a.y = 0
            a.capdive = 0

    def update_aliens(self):
        for i in range(NAL):
            a = self.al[i]
            st = a.st
            if st == A_FORM:
                a.x = slot_x(i) + self.formDx
                a.y = slot_y(i)
            elif st == A_EXPLODE:
                a.timer -= 1
                if a.timer < 0:
                    a.st = A_DEAD
            elif st == A_DIVE:
                self.dive_step(i)
            elif st == A_RETURN:
                a.x = slot_x(i) + self.formDx
                a.y += 2
                if a.y >= slot_y(i):
                    a.y = slot_y(i)
                    a.st = A_FORM
                    a.esc = 0

    def select_dive(self):
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
        for i in range(3):
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
            if self.beamLen < 4:
                self.beamAcc += 1
                if self.beamAcc >= 8:
                    self.beamAcc = 0
                    self.beamLen += 1
            elif self.state == S_PLAY and not self.invuln and b.x - 20 <= self.px <= b.x + 19:
                self.cap = C_PULL
                self.state = S_CAPTURED
                self.dual = 0
                for p in self.ps:
                    p.x = p.y = p.act = p.dx = 0
                self.snd |= JG_CAPTURE
            else:
                self.beamTimer -= 1
                if self.beamTimer <= 0:
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
                    self.stateTimer = 90
        elif st == S_READY:
            if self.challenge:
                self.update_aliens()
            else:
                self.move_world()
            self.stateTimer -= 1
            if self.stateTimer <= 0:
                self.state = S_PLAY
                self.px = 160
                self.invuln = 120
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
