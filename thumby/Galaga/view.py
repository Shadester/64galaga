# What is on the 128 x 128 screen, from a Game: sprite slots, beam strips, stars, texts. No engine imports: main.py
# moves the engine's nodes to match, tools/preview.py draws the same data with Pillow.
#
# The game runs in C64 coordinates (x 24..343, y 50..249). Screen x = (x - 24) * 0.4, screen y = HUD_H + (y - 50) * 0.56:
# the playfield is stretched to fill the square screen, the sprites are not.
import game as G
import sprite_ids as S

W = H = 128
HUD_H = 14
N_SLOTS = 43                       # 32 aliens, ship, dual ship, captive, 4 player bullets, 3 enemy bullets, the lives icon
SLOT_SHIP, SLOT_DUAL, SLOT_CAPT, SLOT_PBUL, SLOT_EBUL, SLOT_LIFE = 32, 33, 34, 35, 39, 42
NUM_STARS = 12
MAX_MSG = 3
WHITE, RED, CYAN, BLUE = 0, 1, 2, 3          # text colours (main.py maps them)

# sprite id of the first frame by alien type; boss after one hit has its own
ALIEN_SPRITE = (S.BOSS_A, S.BFLY_A, S.BEE_A)


class Scene:
    def __init__(self):
        n = N_SLOTS
        self.sid = [-1] * n               # sprite id (cell in sprites.bmp), -1 = hidden
        self.sx = [0] * n                 # centre, screen pixels
        self.sy = [0] * n
        self.beam_n = 0                   # tractor beam: rows shown, frame index (row * 4 + phase), centre x / y of each row
        self.bx = [0] * 4
        self.by = [0] * 4
        self.bf = [0] * 4
        self.star_x = [(i * 37 + 11) % W for i in range(NUM_STARS)]
        self.star_y = [(i * 53 + 7) % (H - HUD_H) + HUD_H for i in range(NUM_STARS)]
        self.star_v = [1 + i % 3 for i in range(NUM_STARS)]
        self.title = True                 # the title picture instead of the playfield
        self.hud = False
        self.score = self.hi = self.lives = self.level = ''      # the HUD numbers (the labels are fixed)
        self.msg = [''] * MAX_MSG         # centred lines; colour and y per line
        self.msg_col = [WHITE] * MAX_MSG
        self.msg_y = [0] * MAX_MSG
        self.hud_key = None
        self.msg_key = None

    def move_stars(self):
        for i in range(NUM_STARS):
            y = self.star_y[i] + self.star_v[i]
            if y >= H:
                y = HUD_H
                self.star_x[i] = (self.star_x[i] * 5 + 17) % W
            self.star_y[i] = y

    def set_msgs(self, *lines):
        """lines: (text, y, colour) ..."""
        for i in range(MAX_MSG):
            if i < len(lines):
                self.msg[i], self.msg_y[i], self.msg_col[i] = lines[i]
            else:
                self.msg[i] = ''

    def update(self, g):
        sid, sx, sy = self.sid, self.sx, self.sy
        state = g.state
        self.title = state == G.S_TITLE
        self.hud = not self.title
        sid[SLOT_LIFE] = -1 if self.title else S.LIFE
        sx[SLOT_LIFE] = 116
        sy[SLOT_LIFE] = 12
        if self.title or state == G.S_GAMEOVER:       # the C64 hides every sprite at game over
            for i in range(N_SLOTS - 1):
                sid[i] = -1
            self.beam_n = 0
            if self.title:
                self.texts_title(g)
            else:
                self.texts_play(g)
            return
        frame = g.frame
        anim = (frame >> 4) & 1
        # aliens
        for i in range(32):
            a = g.al[i]
            st = a.st
            if st == G.A_DEAD or (st == G.A_ENTER and a.ent == 0):
                sid[i] = -1
                continue
            if st == G.A_EXPLODE:
                f = 2 - (a.timer >> 2)
                sid[i] = S.EXPL1 + (0 if f < 0 else 2 if f > 2 else f)
            elif a.type == G.T_BOSS and a.hp == 1 and not g.challenge:
                sid[i] = S.BOSSP_A + anim
            else:
                sid[i] = ALIEN_SPRITE[a.type] + anim
            sx[i] = ((a.x + 12 - 24) * 2) // 5
            sy[i] = HUD_H + ((a.y + 6 - 50) * 14) // 25
        # ship, dual ship, captive
        blink = (g.invuln & 4) != 0
        px = ((g.px + 12 - 24) * 2) // 5
        py = HUD_H + ((g.py + 7 - 50) * 14) // 25
        sid[SLOT_DUAL] = -1
        if state == G.S_READY or state == G.S_GAMEOVER:
            sid[SLOT_SHIP] = -1
        elif state == G.S_DYING:
            if g.dyingQuiet:
                sid[SLOT_SHIP] = -1
            else:
                f = 3 - (g.stateTimer >> 4)
                sid[SLOT_SHIP] = S.PEXP1 + (0 if f < 0 else 3 if f > 3 else f)
                sx[SLOT_SHIP] = px
                sy[SLOT_SHIP] = py
        elif blink:
            sid[SLOT_SHIP] = -1
        else:
            sid[SLOT_SHIP] = S.SHIP
            sx[SLOT_SHIP] = px
            sy[SLOT_SHIP] = py
            if g.dual:
                sid[SLOT_DUAL] = S.SHIP
                sx[SLOT_DUAL] = px + 6
                sy[SLOT_DUAL] = py
        sid[SLOT_CAPT] = -1
        if g.cap == G.C_CARRY:
            b = g.al[g.capBoss]
            if b.st != G.A_DEAD and b.y >= 32:
                sid[SLOT_CAPT] = S.CAPTIVE
                sx[SLOT_CAPT] = ((b.x + 12 - 24) * 2) // 5
                sy[SLOT_CAPT] = HUD_H + ((b.y - 16 + 7 - 50) * 14) // 25
        elif g.cap == G.C_RESCUE:
            sid[SLOT_CAPT] = S.CAPTIVE
            sx[SLOT_CAPT] = ((g.rx + 12 - 24) * 2) // 5
            sy[SLOT_CAPT] = HUD_H + ((g.ry + 7 - 50) * 14) // 25
        # bullets
        for i in range(4):
            b = g.ps[i]
            if b.act:
                sid[SLOT_PBUL + i] = S.PBUL
                sx[SLOT_PBUL + i] = ((b.x + 9 - 24) * 2) // 5
                sy[SLOT_PBUL + i] = HUD_H + ((b.y + 6 - 50) * 14) // 25
            else:
                sid[SLOT_PBUL + i] = -1
        for i in range(3):
            b = g.eb[i]
            if b.act:
                sid[SLOT_EBUL + i] = S.EBUL
                sx[SLOT_EBUL + i] = ((b.x + 12 - 24) * 2) // 5
                sy[SLOT_EBUL + i] = HUD_H + ((b.y + 4 - 50) * 14) // 25
            else:
                sid[SLOT_EBUL + i] = -1
        # tractor beam: beamLen rows of cells under the boss, colours shimmer every 4 frames
        self.beam_n = 0
        if (g.cap == G.C_BEAM or g.cap == G.C_PULL) and g.beamLen:
            b = g.al[g.capBoss]
            n = g.beamLen
            bxc = ((b.x + 12 - 24) * 2) // 5
            row0 = (b.y - 36) >> 3               # first row of the C64 text grid under the boss: its rows are 8 high
            phase = (frame >> 2) & 3
            for r in range(n):
                self.bx[r] = bxc
                self.by[r] = HUD_H + (((row0 + r) * 8 + 4) * 14) // 25
                self.bf[r] = r * 4 + phase
            self.beam_n = n
        self.texts_play(g)

    # ---- texts: rebuilt only when their inputs change ----
    def texts_title(self, g):
        key = ('t', g.hi)
        if key == self.msg_key:
            return
        self.msg_key = key
        self.hud_key = None
        self.set_msgs(('HI-SCORE %06d' % g.hi, 88, RED), ('PRESS FIRE', 98, WHITE))

    def texts_play(self, g):
        key = (g.score, g.hi, g.lives, g.stage)
        if key != self.hud_key:
            self.hud_key = key
            self.score = '%06d' % g.score
            self.hi = '%06d' % g.hi
            self.lives = '%d' % g.lives
            self.level = '%02d' % g.stage
        st = g.state
        extra = g.challenge and g.chalHits == G.NAL
        key = (st, g.paused, g.stage, g.shots, g.hits, g.chalHits, g.dyingQuiet, st == G.S_GAMEOVER and g.stateTimer == 0)
        if key == self.msg_key:
            return
        self.msg_key = key
        if g.paused:
            self.set_msgs(('PAUSED', 100, WHITE))
        elif st == G.S_INTRO:
            if g.challenge:
                self.set_msgs(('CHALLENGING STAGE', 96, CYAN))
            else:
                self.set_msgs(('STAGE %02d' % g.stage, 96, WHITE))
        elif st == G.S_READY:
            self.set_msgs(('READY', 100, WHITE))
        elif st == G.S_DYING and g.dyingQuiet:
            self.set_msgs(('FIGHTER CAPTURED', 100, RED))
        elif st == G.S_RESULT:
            if g.challenge:
                lines = [('NUMBER OF HITS %d' % g.chalHits, 52, WHITE)]
                if extra:
                    lines += [('PERFECT!', 66, CYAN), ('BONUS 10000', 76, WHITE)]
                self.set_msgs(*lines)
            else:
                ratio = g.hits * 100 // g.shots if g.shots else 0
                self.set_msgs(('SHOTS %3d' % min(g.shots, 999), 52, WHITE), ('HITS  %3d' % min(g.hits, 999), 62, WHITE),
                              ('RATIO %3d%%' % min(ratio, 100), 72, CYAN))
        elif st == G.S_GAMEOVER:
            if g.stateTimer == 0:
                self.set_msgs(('GAME OVER', 56, WHITE), ('PRESS FIRE', 72, WHITE))
            else:
                self.set_msgs(('GAME OVER', 56, WHITE))
        else:
            self.set_msgs()
