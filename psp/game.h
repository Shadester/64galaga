/* Galaga game rules, ported from 64galaga. No platform headers: host-testable.
 * Logic runs at the C64 PAL rate (50 ticks/s) in C64 sprite coordinates:
 * play area x 24..343, y 50..249. x/y are the top-left of a 24x21 sprite box. */
#ifndef GAME_H
#define GAME_H

#ifdef RULES_ARCADE   /* the arcade rules: 40 enemies, see ../ARCADE.md */
#define NAL 40
#define EBN 8   /* enemy bombs on the screen */
#else
#define NAL 32
#define EBN 3
#endif
#define TICK_HZ 50

enum { S_TITLE, S_INTRO, S_PLAY, S_DYING, S_GAMEOVER, S_CAPTURED, S_RESULT, S_READY };
enum { T_BOSS, T_BUTTERFLY, T_BEE };
enum { A_DEAD, A_FORM, A_DIVE, A_RETURN, A_EXPLODE, A_BEAM, A_ENTER };
/* cap: tractor beam / captive state */
enum { C_NONE, C_DIVING, C_BEAM, C_PULL, C_CARRY, C_RESCUE };
/* Sound events, one bit each; the platform clears Game.snd after reading. */
enum {
    SND_SHOOT = 1, SND_EXPLODE = 2, SND_HIT = 4, SND_DEATH = 8, SND_SWOOP = 16,
    JG_STAGE = 32, JG_OVER = 64, JG_CAPTURE = 128, JG_RESCUE = 256, JG_BONUS = 512
};

typedef struct {
    int x, y, st, type, hp, timer, dir, esc, capdive, fired;
    int path, pstep, mir, ent, dly;   /* ent: 0 waiting, 1 on path, 2 homing */
#ifdef RULES_ARCADE
    int dpath, bflags, btmr;   /* dive path (-1: free), bomb flags and the time to the next one (arcade frames) */
#endif
} Alien;
typedef struct { int x, y, act, dx; int ax; } Bullet;   /* ax: the sideways speed of a bomb is dx / 16 pixel a tick, ax the rest */
typedef struct { int left, right, fire, pause, quit; } Input;  /* pause/quit are edge pulses */

typedef struct {
    int state, paused, stateTimer, frame, prevFire;
    int score, hi, lives, stage, diff, nextBonus, challenge, chalVal, chalHits, chalTimer;
    int shots, hits;
    int px, py, invuln, dual, dyingQuiet;
    int formDx, formDir, formTimer, entering, diveTimer;
    int cap, capBoss, beamLen, beamAcc, beamTimer, rx, ry;
    int snd, saveReq;
    Alien al[NAL];
#ifdef RULES_ARCADE   /* the dive scheduler runs on the arcade's 60 Hz clock: 6 arcade frames for every 5 ticks */
    int beamPh, beamStep;   /* the beam: 0 grows, 1 holds (the ship is taken), 2 shrinks; ticks for one of its 4 steps */
    int fclk, ff, swayPos, swayDir, breathe, bstep;   /* the formation: swing while the aliens fly in, then breathe (also on the arcade clock) */
    int clk, af, tmr2, hold, sortie[3], wingm, bombFlags;   /* tmr2: counts down from 120 once in 32 frames (time since the stage began); hold: no bombs after a boss was shot while it dived */
#endif
    Bullet ps[4], eb[EBN];
} Game;

void game_init(Game *g, int hiScore);
void game_tick(Game *g, const Input *in);
void game_autoplay(const Game *g, Input *in);
int slot_x(int i);
int slot_y(int i);

#endif
